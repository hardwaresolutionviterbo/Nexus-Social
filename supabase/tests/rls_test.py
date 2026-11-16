#!/usr/bin/env python3
"""Test di sicurezza Supabase (regola R3, docs/fase1/TEST_SUPABASE_RLS.md).

Gira SOLO contro il Supabase temporaneo avviato in GitHub Actions (supabase start).
- Utenti e dati inventati.
- Token di prova firmati con la chiave locale del database temporaneo, con le stesse
  informazioni di un token Firebase (emittente, destinatario, soggetto, ruolo).
- Nei log solo nome del caso ed esito: mai token, chiavi o contenuti.

Variabili richieste: API_URL, ANON_KEY, JWT_SECRET, DB_URL (da `supabase status -o env`).
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = os.environ["API_URL"].rstrip("/")
ANON = os.environ["ANON_KEY"]
SECRET = os.environ["JWT_SECRET"].encode()
DB_URL = os.environ["DB_URL"]

PROJECT = "demo-nexus-social"
OTHER_PROJECT = "altro-progetto-firebase"
UID_A = "utenteAprova0000000000000001"
UID_B = "utenteBprova0000000000000002"
UID_C = "utenteCprova0000000000000003"
UID_D = "utenteDprova0000000000000004"  # Azienda
UID_E = "utenteEprova0000000000000005"  # usato per i rifiuti (mai creato)

PUBLIC_PROFILE_KEYS = {
    "id", "account_type", "username", "public_name", "avatar_path",
    "avatar_thumb_path", "bio", "social_links", "rating_avg", "rating_count", "created_at",
}
VALID_VAT = "01234567897"  # partita IVA inventata con cifra di controllo corretta
JPEG = bytes.fromhex("ffd8ffe000104a46494600010100000100010000ffd9")  # JPEG minimo

results: list[tuple[str, str, bool, str]] = []


# ---------------------------------------------------------------- strumenti

def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(sub: str | None = UID_A, *, project: str = PROJECT, role: str | None = None,
          iat_offset: int = -10, exp_offset: int = 3600, secret: bytes | None = None,
          extra: dict | None = None) -> str:
    now = int(time.time())
    claims = {
        "iss": f"https://securetoken.google.com/{project}",
        "aud": project,
        "iat": now + iat_offset,
        "auth_time": now + iat_offset,
        "exp": now + exp_offset,
    }
    # Come i veri token Firebase senza Cloud Function: nessun claim `role` (migrazione 0017).
    if role is not None:
        claims["role"] = role
    if sub is not None:
        claims["sub"] = sub
        claims["user_id"] = sub
    if extra:
        claims.update(extra)
    header = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64(json.dumps(claims).encode())
    signing = f"{header}.{payload}".encode()
    sig = b64(hmac.new(secret or SECRET, signing, hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"


def request(method: str, path: str, *, jwt: str | None = None, body=None,
            prefer: str | None = None, device: str | None = None) -> tuple[int, object]:
    headers = {"apikey": ANON, "Content-Type": "application/json"}
    if device is not None:
        headers["x-device-id"] = device
    if jwt is not None:
        headers["Authorization"] = f"Bearer {jwt}"
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{API}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            return err.code, json.loads(raw) if raw else None
        except ValueError:
            return err.code, raw.decode(errors="replace")


def get(path, jwt=None):
    return request("GET", path, jwt=jwt)


def rpc(name, args, jwt=None, device=None):
    return request("POST", f"/rest/v1/rpc/{name}", jwt=jwt, body=args, device=device)


def sql(statement: str) -> str:
    out = subprocess.run(
        ["psql", DB_URL, "-v", "ON_ERROR_STOP=1", "-At", "-c", statement],
        check=True, capture_output=True, text=True,
    )
    return out.stdout.strip()


def check(case: str, description: str, condition: bool, detail: str = "") -> None:
    results.append((case, description, bool(condition), detail if not condition else ""))


def rows(resp) -> list:
    status, body = resp
    return body if status == 200 and isinstance(body, list) else []


def denied(resp) -> bool:
    """Accesso negato: errore HTTP, oppure nessuna riga restituita o toccata."""
    status, body = resp
    if status >= 400:
        return True
    return isinstance(body, list) and len(body) == 0


# ---------------------------------------------------------------- preparazione

def setup() -> dict:
    sql(
        "insert into private.settings (key, value) values "
        f"('firebase_project_id', '{PROJECT}') "
        "on conflict (key) do update set value = excluded.value;"
    )
    ta, tb = token(UID_A), token(UID_B)
    ids = {}
    for tok, username, full_name, birth in (
        (ta, "utente_a", "Mario Rossi", "1990-05-01"),
        (tb, "utente_b", "Laura Bianchi", "1985-11-20"),
    ):
        s, _ = rpc("create_my_profile", {"p_username": username, "p_full_name": full_name,
                                         "p_birth_date": birth}, tok)
        assert s in (200, 204), f"creazione profilo: HTTP {s}"
    s, _ = rpc("create_my_profile", {
        "p_username": "bottega_d", "p_full_name": "Paolo Verdi", "p_birth_date": "1980-03-03",
        "p_account_type": "business", "p_business_name": "Bottega Verdi Srl",
        "p_vat_number": VALID_VAT}, token(UID_D))
    assert s in (200, 204), f"creazione Azienda: HTTP {s}"
    s, _ = rpc("update_my_profile", {
        "p_username": "utente_b", "p_full_name": "Laura Bianchi", "p_bio": "Bio segreta di B",
        "p_social_links": {"instagram": "laura.b"}, "p_show_bio": False,
        "p_show_social": True}, tb)
    assert s in (200, 204), f"aggiornamento profilo B: HTTP {s}"
    # Annunci di A: uno senza modalità (predefinita), uno preciso.
    s, ids["a_default"] = rpc("create_listing", {
        "p_kind": "social", "p_title": "Annuncio predefinito", "p_description": "",
        "p_lat": 41.9028, "p_lon": 12.4964}, ta)
    assert s == 200, f"create_listing predefinito: HTTP {s}"
    s, ids["a_precise"] = rpc("create_listing", {
        "p_kind": "social", "p_title": "Annuncio preciso", "p_description": "",
        "p_lat": 41.8902, "p_lon": 12.4922, "p_location_mode": "precise"}, ta)
    assert s == 200, f"create_listing preciso: HTTP {s}"
    s, ids["b_listing"] = rpc("create_listing", {
        "p_kind": "sale", "p_title": "Vendita di B", "p_description": "",
        "p_lat": 45.4642, "p_lon": 9.19, "p_price_cents": 1000}, tb)
    assert s == 200, f"create_listing di B: HTTP {s}"
    s, body = request("POST", "/rest/v1/reports", jwt=ta, prefer="return=representation",
                      body={"reporter_id": UID_A, "target": "listing",
                            "target_id": ids["b_listing"], "reason": "Prova"})
    assert s == 201, f"segnalazione di A: HTTP {s}"
    ids["a_report"] = body[0]["id"]
    return ids


# ---------------------------------------------------------------- casi

def near(lat, lon, jwt, radius=5000):
    return rows(rpc("nearby_listings", {"p_lat": lat, "p_lon": lon, "p_radius_m": radius}, jwt))


def by_id(items, listing_id):
    return next((x for x in items if x.get("id") == listing_id), None)


def run(ids: dict) -> None:
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)

    # Controllo di avvio dell'app (Profilo → «Collegato»): «ping» risponde anche prima
    # dell'accesso; tutto il resto no (migrazione 0017).
    s, body = rpc("ping", {})
    s2, _ = get("/rest/v1/profiles?select=id&limit=1")
    check("APP", "Il controllo di avvio dell'app risponde («ping») senza dare dati",
          s == 200 and body is True and s2 >= 400, f"HTTP {s}, {body}, {s2}")

    # A · Separazione tra dati pubblici e privati
    mine = rows(get(f"/rest/v1/profile_private?id=eq.{UID_A}", ta))
    check("A1", "A legge i propri dati privati",
          len(mine) == 1 and mine[0]["full_name"] == "Mario Rossi")
    pub_b = rows(rpc("get_public_profile", {"p_id": UID_B}, ta))
    check("A2", "A legge il profilo pubblico di B, solo campi pubblici",
          len(pub_b) == 1 and set(pub_b[0]) <= PUBLIC_PROFILE_KEYS, str(pub_b and sorted(pub_b[0])))
    text = json.dumps(pub_b)
    check("A3", "Il profilo pubblico non contiene nome completo né data di nascita",
          "Bianchi" not in text and "1985" not in text and "full_name" not in text
          and "birth" not in text)
    check("A4", "Il nome pubblico è abbreviato («Laura B.»)",
          bool(pub_b) and pub_b[0]["public_name"] == "Laura B.")

    # B · Nessuna lettura dei dati privati altrui
    check("B1", "A legge i dati privati di B direttamente: nessuna riga",
          denied(get(f"/rest/v1/profile_private?id=eq.{UID_B}", ta)))
    all_rows = rows(get("/rest/v1/profile_private?select=id", ta))
    filt1 = get("/rest/v1/profile_private?full_name=eq.Laura%20Bianchi", ta)
    filt2 = rows(get("/rest/v1/profile_private?birth_date=gte.1900-01-01&order=birth_date", ta))
    check("B2", "Filtri, ordinamenti e ricerche non rivelano i dati privati di B",
          [r["id"] for r in all_rows] == [UID_A] and denied(filt1)
          and [r["id"] for r in filt2] == [UID_A])
    upd = request("PATCH", f"/rest/v1/profile_private?id=eq.{UID_B}", jwt=ta,
                  prefer="return=representation", body={"full_name": "Hacker X"})
    dele = request("DELETE", f"/rest/v1/profiles?id=eq.{UID_B}", jwt=ta,
                   prefer="return=representation")
    b_after = rows(get(f"/rest/v1/profile_private?id=eq.{UID_B}", tb))
    check("B3", "A non può modificare né cancellare i dati di B",
          denied(upd) and denied(dele) and b_after and b_after[0]["full_name"] == "Laura Bianchi")
    ins1 = request("POST", "/rest/v1/profiles", jwt=ta, body={"id": UID_C, "username": "finto_c"})
    ins2 = request("POST", "/rest/v1/profile_private", jwt=ta,
                   body={"id": UID_B, "full_name": "Furto Identita"})
    check("B4", "A non può creare un profilo o dati privati con l'identità di altri",
          ins1[0] >= 400 and ins2[0] >= 400, f"HTTP {ins1[0]}, {ins2[0]}")
    sw = request("PATCH", f"/rest/v1/profiles?id=eq.{UID_A}", jwt=ta,
                 prefer="return=representation", body={"id": UID_B})
    still = rows(get(f"/rest/v1/profiles?id=eq.{UID_A}&select=id", ta))
    check("B5", "A non può cambiare il proprio identificativo in quello di B",
          sw[0] >= 400 and len(still) == 1, f"HTTP {sw[0]}")
    near_items = near(41.9028, 12.4964, tb)
    keys = set().union(*(set(x) for x in near_items)) if near_items else set()
    check("B6", "nearby_listings non restituisce dati privati",
          bool(near_items) and not ({"full_name", "birth_date", "exact_location"} & keys)
          and "Rossi" not in json.dumps(near_items))
    check("B7", "Senza token: nessun dato dei profili, pubblici o privati",
          rows(get("/rest/v1/profiles")) == [] and denied(get("/rest/v1/profile_private")))

    # C · Token non validi o di altri utenti
    check("C1", "Nessun token: trattato come non autenticato",
          rows(get("/rest/v1/profiles")) == [])
    s, _ = get("/rest/v1/profiles", token(UID_A, iat_offset=-7200, exp_offset=-3600))
    check("C2", "Token scaduto: rifiutato", s == 401, f"HTTP {s}")
    s, _ = get("/rest/v1/profiles", token(UID_A, secret=b"chiave-sbagliata-" * 4))
    check("C3", "Token firmato con una chiave sconosciuta: rifiutato", s == 401, f"HTTP {s}")
    other = token(UID_A, project=OTHER_PROJECT)
    check("C4", "Token di un altro progetto Firebase: nessun accesso",
          denied(get("/rest/v1/profiles", other)) and denied(get("/rest/v1/profile_private", other))
          and rpc("create_listing", {"p_kind": "social", "p_title": "Intruso", "p_description": "",
                                     "p_lat": 41.9, "p_lon": 12.5}, other)[0] >= 400)
    check("C5", "Token valido di B: vede i propri dati privati, mai quelli di A",
          [r["id"] for r in rows(get("/rest/v1/profile_private", tb))] == [UID_B])
    h, p, sgn = ta.split(".")
    claims = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
    claims["sub"] = UID_B
    forged = f"{h}.{b64(json.dumps(claims).encode())}.{sgn}"
    s, _ = get("/rest/v1/profile_private", forged)
    check("C6", "Token di A modificato per fingersi B: rifiutato", s == 401, f"HTTP {s}")
    s, body = get("/rest/v1/profiles", "abc.def")
    leak = json.dumps(body) if body is not None else ""
    check("C7", "Token malformato: rifiutato, senza dettagli sensibili",
          s == 401 and SECRET.decode() not in leak, f"HTTP {s}")
    future = token(UID_A, iat_offset=3600, exp_offset=7200)
    s, _ = get("/rest/v1/profile_private", future)
    check("C8", "Token emesso nel futuro: rifiutato o senza accesso",
          s == 401 or denied((s, rows(get("/rest/v1/profile_private", future)))), f"HTTP {s}")

    # D · Regole dello schema
    ins = request("POST", "/rest/v1/admin_users", jwt=ta, body={"user_id": UID_A})
    check("D1", "Un utente non diventa admin da solo", ins[0] >= 400, f"HTTP {ins[0]}")
    check("D3", "Le segnalazioni di A non sono leggibili da B",
          denied(get(f"/rest/v1/reports?id=eq.{ids['a_report']}", tb)))

    # D2 · Posizione degli annunci (P9)
    items = near(41.9028, 12.4964, tb)
    d = by_id(items, ids["a_default"])
    check("D2.1", "Senza modalità: approssimata; altri vedono solo zona e fascia di distanza",
          d is not None and d["location_mode"] == "approximate"
          and (abs(d["approx_lat"] - 41.9028) > 1e-4 or abs(d["approx_lon"] - 12.4964) > 1e-4)
          and d["distance_band_m"] % 250 == 0)
    loc = get(f"/rest/v1/listing_locations?listing_id=eq.{ids['a_default']}", tb)
    raw = get(f"/rest/v1/listings?id=eq.{ids['a_default']}", tb)
    check("D2.2", "Il punto preciso di un annuncio approssimato non è leggibile da altri",
          denied(loc) and "exact" not in json.dumps(raw[1]))
    items = near(41.8902, 12.4922, tb)
    p_ = by_id(items, ids["a_precise"])
    check("D2.3", "Modalità precisa: gli altri vedono esattamente il punto scelto",
          p_ is not None and p_["location_mode"] == "precise"
          and abs(p_["approx_lat"] - 41.8902) < 1e-6 and abs(p_["approx_lon"] - 12.4922) < 1e-6)
    both = near(41.896, 12.494, tb, radius=10000)
    d2, p2 = by_id(both, ids["a_default"]), by_id(both, ids["a_precise"])
    check("D2.4", "Stesso autore, due annunci: ognuno rispetta la propria modalità",
          d2 is not None and p2 is not None and d2["location_mode"] == "approximate"
          and p2["location_mode"] == "precise")
    r1 = rpc("set_listing_location_mode", {"p_listing_id": ids["a_default"], "p_mode": "precise"}, tb)
    r2 = request("PATCH", f"/rest/v1/listings?id=eq.{ids['a_default']}", jwt=tb,
                 prefer="return=representation", body={"location_mode": "precise"})
    after = by_id(near(41.9028, 12.4964, tb), ids["a_default"])
    check("D2.5", "Un altro utente non può cambiare modalità o posizione di un annuncio",
          r1[0] >= 400 and denied(r2) and after and after["location_mode"] == "approximate")
    r3 = rpc("set_listing_location_mode", {"p_listing_id": ids["a_precise"], "p_mode": "approximate"}, ta)
    p3 = by_id(near(41.8902, 12.4922, tb), ids["a_precise"])
    check("D2.6", "Da precisa ad approssimata: il punto preciso non è più visibile",
          r3[0] in (200, 204) and p3 is not None and p3["location_mode"] == "approximate"
          and (abs(p3["approx_lat"] - 41.8902) > 1e-4 or abs(p3["approx_lon"] - 12.4922) > 1e-4))
    own_loc = rows(get(f"/rest/v1/listing_locations?listing_id=eq.{ids['a_default']}", ta))
    own = rows(get(f"/rest/v1/listings?id=eq.{ids['a_default']}&select=id,location_mode", ta))
    check("D2.7", "L'autore vede la propria posizione salvata e la modalità",
          len(own_loc) == 1 and own and own[0]["location_mode"] == "approximate")
    s, _ = rpc("nearby_listings", {"p_lat": 41.9, "p_lon": 12.5})
    check("D2.8", "Senza token: nessuna posizione",
          s >= 400 and rows(get("/rest/v1/listings")) == [], f"HTTP {s}")

    # E · Nessun accesso amministrativo per percorsi alternativi
    check("E1", "Un utente normale non si inserisce tra gli admin",
          request("POST", "/rest/v1/admin_users", jwt=tb, body={"user_id": UID_B})[0] >= 400)
    sql(f"insert into public.admin_users (user_id, role) values ('{UID_B}', 'moderator') "
        "on conflict do nothing;")
    check("E2", "Un utente normale non vede l'elenco degli admin",
          rows(get("/rest/v1/admin_users", ta)) == [])
    m1 = request("POST", "/rest/v1/user_moderation", jwt=ta,
                 body={"user_id": UID_B, "banned_until": "2099-01-01T00:00:00Z"})
    m2 = request("POST", "/rest/v1/user_moderation", jwt=ta,
                 body={"user_id": UID_A, "banned_until": None})
    check("E3", "Un utente normale non crea sanzioni, né per altri né per sé",
          m1[0] >= 400 and m2[0] >= 400, f"HTTP {m1[0]}, {m2[0]}")
    sql(f"delete from public.admin_users where user_id = '{UID_B}';")
    up = request("PATCH", f"/rest/v1/reports?id=eq.{ids['a_report']}", jwt=tb,
                 prefer="return=representation", body={"status": "resolved"})
    check("E4", "Un utente normale non legge né gestisce le segnalazioni altrui",
          denied(get("/rest/v1/reports", tb)) and denied(up))
    e5a = request("PATCH", f"/rest/v1/listings?id=eq.{ids['b_listing']}", jwt=ta,
                  prefer="return=representation", body={"title": "Modificato da A"})
    e5b = request("PATCH", f"/rest/v1/profiles?id=eq.{UID_A}", jwt=ta,
                  prefer="return=representation", body={"rating_avg": 5, "rating_count": 99})
    e5c = request("PATCH", f"/rest/v1/profiles?id=eq.{UID_A}", jwt=ta,
                  prefer="return=representation", body={"public_name": "Admin Finto"})
    check("E5", "Nessuna modifica di campi protetti o di dati altrui",
          denied(e5a) and e5b[0] >= 400 and e5c[0] >= 400,
          f"HTTP {e5a[0]}, {e5b[0]}, {e5c[0]}")
    fake_sr = token(UID_A, role="service_role", secret=b"chiave-non-del-progetto" * 2)
    s1, _ = get("/rest/v1/profile_private", fake_sr)
    s2, _ = get("/rest/v1/profile_private", token(UID_A, role="supabase_admin"))
    s3, _ = get("/rest/v1/profile_private", token(UID_A, role="admin"))
    fake_claims = token(UID_A, extra={"is_admin": True, "user_role": "admin", "admin": True})
    check("E6", "Ruoli o permessi falsificati non danno privilegi",
          s1 == 401 and s2 >= 400 and s3 >= 400
          and denied(get(f"/rest/v1/reports?reporter_id=neq.{UID_A}", fake_claims))
          and [r["id"] for r in rows(get("/rest/v1/profile_private", fake_claims))] == [UID_A],
          f"HTTP {s1}, {s2}, {s3}")
    e7a = get("/rest/v1/admin_users")
    e7b = rpc("create_listing", {"p_kind": "social", "p_title": "Anonimo", "p_description": "",
                                 "p_lat": 41.9, "p_lon": 12.5})
    e7c = get("/rest/v1/user_moderation")
    check("E7", "Chiave pubblica senza token: nessun accesso alle funzioni amministrative",
          denied(e7a) and e7b[0] >= 400 and denied(e7c), f"HTTP {e7b[0]}")
    s, body = rpc("is_admin", {}, ta)
    check("E8", "Funzioni con permessi elevati: nessuna azione da admin per utenti normali",
          s == 200 and body is False
          and rpc("set_listing_location_mode",
                  {"p_listing_id": ids["b_listing"], "p_mode": "precise"}, ta)[0] >= 400)


def storage(method: str, path: str, jwt: str | None, data: bytes | None = None,
            device: str | None = None) -> int:
    """Chiamata allo Storage temporaneo; restituisce solo lo stato HTTP."""
    headers = {"apikey": ANON, "Content-Type": "image/jpeg"}
    if device is not None:
        headers["x-device-id"] = device
    if jwt is not None:
        headers["Authorization"] = f"Bearer {jwt}"
    req = urllib.request.Request(f"{API}/storage/v1/object/{path}", data=data,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            resp.read()
            return resp.status
    except urllib.error.HTTPError as err:
        err.read()
        return err.code


def check_profile_block2() -> None:
    """F · Profilo completo (Fase 2, Blocco 2)."""
    ta, tb, td, te = token(UID_A), token(UID_B), token(UID_D), token(UID_E)
    young = f"{time.gmtime().tm_year - 13}-01-01"
    teen = f"{time.gmtime().tm_year - 16}-01-01"

    # F1 · Età minima e Azienda solo maggiorenni, controllate dal server
    r1 = rpc("create_my_profile", {"p_username": "troppo_giovane", "p_full_name": "Tizio Primo",
                                   "p_birth_date": young}, te)
    r2 = rpc("create_my_profile", {"p_username": "azienda_minore", "p_full_name": "Tizio Primo",
                                   "p_birth_date": teen, "p_account_type": "business",
                                   "p_business_name": "Minore Srl", "p_vat_number": VALID_VAT}, te)
    r3 = rpc("create_my_profile", {"p_username": "azienda_iva_errata",
                                   "p_full_name": "Tizio Primo", "p_birth_date": "1980-01-01",
                                   "p_account_type": "business", "p_business_name": "Errata Srl",
                                   "p_vat_number": "01234567890"}, te)
    none_e = rows(get(f"/rest/v1/profiles?id=eq.{UID_E}&select=id", ta))
    check("F1", "Sotto i 14 anni, Azienda minorenne o partita IVA errata: profilo rifiutato",
          r1[0] >= 400 and r2[0] >= 400 and r3[0] >= 400 and none_e == [],
          f"HTTP {r1[0]}, {r2[0]}, {r3[0]}")

    # F2 · Dati Azienda: ragione sociale pubblica, partita IVA privata, stato in verifica
    pub_d = rows(rpc("get_public_profile", {"p_id": UID_D}, ta))
    bp_other = get(f"/rest/v1/business_private?id=eq.{UID_D}", ta)
    s, mine_d = rpc("get_my_profile", {}, td)
    check("F2", "Azienda (P4): ragione sociale e partita IVA solo al titolare, stato «in verifica»",
          len(pub_d) == 1 and pub_d[0]["account_type"] == "business"
          and VALID_VAT not in json.dumps(pub_d) and "Bottega" not in json.dumps(pub_d)
          and denied(bp_other) and mine_d.get("business_name") == "Bottega Verdi Srl"
          and s == 200 and isinstance(mine_d, dict) and mine_d.get("vat_number") == VALID_VAT
          and mine_d.get("business_status") == "pending")

    # F3 · Interruttori del profilo pubblico (P3), applicati dal server
    pub_b = rows(rpc("get_public_profile", {"p_id": UID_B}, ta))
    s, mine_b = rpc("get_my_profile", {}, tb)
    direct = get(f"/rest/v1/profiles?id=eq.{UID_B}&select=bio,social_links", ta)
    check("F3", "Bio nascosta da B: gli altri non la vedono (né con letture dirette), B sì",
          len(pub_b) == 1 and pub_b[0]["bio"] is None
          and pub_b[0]["social_links"] == {"instagram": "laura.b"}
          and "Bio segreta" not in json.dumps(direct[1]) and direct[0] >= 400
          and s == 200 and mine_b.get("bio") == "Bio segreta di B")

    # F4 · Social solo come nome utente su reti note
    bad1 = rpc("update_my_profile", {"p_username": "utente_a", "p_full_name": "Mario Rossi",
                                     "p_bio": None, "p_social_links": {"sito": "esempio"},
                                     "p_show_bio": True, "p_show_social": True}, ta)
    bad2 = rpc("update_my_profile", {"p_username": "utente_a", "p_full_name": "Mario Rossi",
                                     "p_bio": None,
                                     "p_social_links": {"instagram": "javascript:alert(1)"},
                                     "p_show_bio": True, "p_show_social": True}, ta)
    check("F4", "Social non validi (rete sconosciuta o link) rifiutati",
          bad1[0] >= 400 and bad2[0] >= 400, f"HTTP {bad1[0]}, {bad2[0]}")

    # F5 · @username univoco, normalizzato, nomi riservati esclusi
    taken = rpc("username_available", {"p_username": "UTENTE_B"}, ta)
    reserved = rpc("username_available", {"p_username": "piazly_ufficiale"}, ta)
    free = rpc("username_available", {"p_username": "nome_libero"}, ta)
    own = rpc("username_available", {"p_username": "utente_a"}, ta)
    dup = rpc("update_my_profile", {"p_username": "Utente_B", "p_full_name": "Mario Rossi",
                                    "p_bio": None, "p_social_links": {}, "p_show_bio": True,
                                    "p_show_social": True}, ta)
    check("F5", "@username: già preso (anche con maiuscole) o riservato non disponibile",
          taken[1] is False and reserved[1] is False and free[1] is True and own[1] is True
          and dup[0] >= 400, f"HTTP {dup[0]}")

    # F6 · Scritture dirette e campi bloccati
    w1 = request("PATCH", f"/rest/v1/profiles?id=eq.{UID_A}", jwt=ta,
                 prefer="return=representation", body={"bio": "diretta"})
    w2 = request("PATCH", f"/rest/v1/profile_private?id=eq.{UID_A}", jwt=ta,
                 prefer="return=representation", body={"birth_date": "2015-01-01"})
    w3 = request("POST", "/rest/v1/business_private", jwt=ta,
                 body={"id": UID_A, "vat_number": VALID_VAT})
    priv_a = rows(get(f"/rest/v1/profile_private?id=eq.{UID_A}", ta))
    check("F6", "Niente scritture dirette; la data di nascita non si cambia",
          w1[0] >= 400 and w2[0] >= 400 and w3[0] >= 400
          and priv_a and priv_a[0]["birth_date"] == "1990-05-01",
          f"HTTP {w1[0]}, {w2[0]}, {w3[0]}")

    # F7 · Foto profilo nella propria cartella, leggibili solo da utenti autenticati
    up_own_a = storage("POST", f"avatars/{UID_A}/avatar-provaA0001.jpg", ta, JPEG)
    up_own_t = storage("POST", f"avatars/{UID_A}/thumb-provaA0001.jpg", ta, JPEG)
    up_other = storage("POST", f"avatars/{UID_B}/avatar-intruso0001.jpg", ta, JPEG)
    set_other = rpc("set_my_avatar", {"p_avatar_path": f"{UID_B}/avatar-provaB0001.jpg",
                                      "p_thumb_path": f"{UID_B}/thumb-provaB0001.jpg"}, ta)
    set_missing = rpc("set_my_avatar", {"p_avatar_path": f"{UID_A}/avatar-mancante01.jpg",
                                        "p_thumb_path": f"{UID_A}/thumb-mancante01.jpg"}, ta)
    set_ok = rpc("set_my_avatar", {"p_avatar_path": f"{UID_A}/avatar-provaA0001.jpg",
                                   "p_thumb_path": f"{UID_A}/thumb-provaA0001.jpg"}, ta)
    read_b = storage("GET", f"authenticated/avatars/{UID_A}/thumb-provaA0001.jpg", tb)
    read_anon = storage("GET", f"authenticated/avatars/{UID_A}/thumb-provaA0001.jpg", None)
    read_public = storage("GET", f"public/avatars/{UID_A}/thumb-provaA0001.jpg", None)
    pub_a = rows(rpc("get_public_profile", {"p_id": UID_A}, tb))
    check("F7", "Foto: caricate solo nella propria cartella, viste solo da utenti autenticati",
          up_own_a == 200 and up_own_t == 200 and up_other >= 400 and set_other[0] >= 400
          and set_missing[0] >= 400 and set_ok[0] in (200, 204) and read_b == 200
          and read_anon >= 400 and read_public >= 400
          and pub_a and pub_a[0]["avatar_thumb_path"] == f"{UID_A}/thumb-provaA0001.jpg",
          f"HTTP {up_own_a}, {up_own_t}, {up_other}, {set_other[0]}, {set_missing[0]}, "
          f"{set_ok[0]}, {read_b}, {read_anon}, {read_public}")

    # F8 · Senza token: nessun profilo né funzione del profilo
    n1 = rpc("get_public_profile", {"p_id": UID_A})
    n2 = rpc("create_my_profile", {"p_username": "anonimo", "p_full_name": "Anonimo Uno",
                                   "p_birth_date": "1990-01-01"})
    check("F8", "Senza token: funzioni del profilo non disponibili",
          n1[0] >= 400 and n2[0] >= 400, f"HTTP {n1[0]}, {n2[0]}")


def check_privacy_block3() -> None:
    """G · Privacy e blocchi (Fase 2, Blocco 3)."""
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)

    # G1 · Scelte di partenza (P5, P8, P3)
    s, pa = rpc("get_my_privacy", {}, ta)
    check("G1", "Partenza: numero ai contatti riconosciuti, «trovarmi» spento, bio e social visibili",
          s == 200 and isinstance(pa, dict) and pa.get("phone_visibility") == "contacts"
          and pa.get("discoverable") is False and pa.get("show_bio") is True
          and pa.get("show_social") is True and pa.get("blocked_count") == 0, str(pa))

    # G2 · Ogni scelta si salva subito ed è privata
    r1 = rpc("set_phone_visibility", {"p_value": "nobody"}, ta)
    r2 = rpc("set_profile_visibility", {"p_show_bio": False, "p_show_social": True}, ta)
    s, pa = rpc("get_my_privacy", {}, ta)
    other = get(f"/rest/v1/privacy_settings?id=eq.{UID_A}", tb)
    direct = request("PATCH", f"/rest/v1/privacy_settings?id=eq.{UID_A}", jwt=ta,
                     prefer="return=representation", body={"discoverable": True})
    check("G2", "Le scelte si salvano subito; nessuno legge o scrive direttamente quelle altrui",
          r1[0] in (200, 204) and r2[0] in (200, 204) and pa.get("phone_visibility") == "nobody"
          and pa.get("show_bio") is False and denied(other) and direct[0] >= 400
          and rpc("get_my_privacy", {}, ta)[1].get("discoverable") is False,
          f"HTTP {r1[0]}, {r2[0]}, {direct[0]}")
    bad = rpc("set_phone_visibility", {"p_value": "everyone"}, ta)
    check("G3", "Nessuna opzione per mostrare il numero a tutti", bad[0] >= 400, f"HTTP {bad[0]}")
    rpc("set_phone_visibility", {"p_value": "contacts"}, ta)
    rpc("set_profile_visibility", {"p_show_bio": True, "p_show_social": True}, ta)

    # G4 · A blocca B: B non vede più profilo e foto di A, e non lo scopre
    rb = rpc("block_user", {"p_user_id": UID_B}, ta)
    pub = rows(rpc("get_public_profile", {"p_id": UID_A}, tb))
    direct_b = rows(get(f"/rest/v1/profiles?id=eq.{UID_A}&select=id,username", tb))
    photo_b = storage("GET", f"authenticated/avatars/{UID_A}/thumb-provaA0001.jpg", tb)
    seen_by_b = rows(get(f"/rest/v1/user_blocks?blocked_id=eq.{UID_B}", tb))
    a_sees_b = rows(rpc("get_public_profile", {"p_id": UID_B}, ta))
    c_sees_a = rows(rpc("get_public_profile", {"p_id": UID_A}, tc))
    check("G4", "Bloccato: niente profilo né foto di chi l'ha bloccato, e nessun avviso",
          rb[0] in (200, 204) and pub == [] and direct_b == [] and photo_b >= 400
          and seen_by_b == [] and len(a_sees_b) == 1 and len(c_sees_a) == 1,
          f"HTTP {rb[0]}, foto {photo_b}")

    # G5 · Elenco dei bloccati: solo dati pubblici
    lst = rows(rpc("my_blocked_users", {}, ta))
    text = json.dumps(lst)
    check("G5", "Elenco dei bloccati con soli dati pubblici («Laura B.», @utente_b)",
          len(lst) == 1 and lst[0]["public_name"] == "Laura B." and "Bianchi" not in text
          and "birth" not in text and rows(rpc("my_blocked_users", {}, tb)) == [])

    # G6 · Blocchi non validi o falsificati
    self_b = rpc("block_user", {"p_user_id": UID_A}, ta)
    ghost = rpc("block_user", {"p_user_id": "utenteInesistente000000001"}, ta)
    again = rpc("block_user", {"p_user_id": UID_B}, ta)
    forged = request("POST", "/rest/v1/user_blocks", jwt=tb,
                     body={"blocker_id": UID_A, "blocked_id": UID_D})
    undo = request("DELETE", f"/rest/v1/user_blocks?blocker_id=eq.{UID_A}", jwt=tb,
                   prefer="return=representation")
    check("G6", "Non si blocca sé stessi o utenti inesistenti; nessun blocco a nome di altri",
          self_b[0] >= 400 and ghost[0] >= 400 and again[0] in (200, 204)
          and forged[0] >= 400 and denied(undo)
          and len(rows(rpc("my_blocked_users", {}, ta))) == 1,
          f"HTTP {self_b[0]}, {ghost[0]}, {again[0]}, {forged[0]}")

    # G7 · Sblocco: tutto torna visibile
    ru = rpc("unblock_user", {"p_user_id": UID_B}, ta)
    check("G7", "Dopo lo sblocco B rivede il profilo e la foto di A",
          ru[0] in (200, 204) and len(rows(rpc("get_public_profile", {"p_id": UID_A}, tb))) == 1
          and storage("GET", f"authenticated/avatars/{UID_A}/thumb-provaA0001.jpg", tb) == 200,
          f"HTTP {ru[0]}")

    # G8 · Senza token
    n1 = rpc("get_my_privacy", {})
    n2 = rpc("block_user", {"p_user_id": UID_B})
    check("G8", "Senza token: impostazioni privacy e blocchi non disponibili",
          n1[0] >= 400 and n2[0] >= 400, f"HTTP {n1[0]}, {n2[0]}")


def check_security_block4() -> None:
    """H · Verifica in due passaggi con PIN (Fase 2, Blocco 4). Utente C, creato qui."""
    tc = token(UID_C)
    dev1 = "telefonoUno_" + "a" * 32
    dev2 = "telefonoDue_" + "b" * 32
    s, _ = rpc("create_my_profile", {"p_username": "utente_c", "p_full_name": "Carla Neri",
                                     "p_birth_date": "1992-02-02"}, tc, dev1)
    assert s in (200, 204), f"creazione profilo C: HTTP {s}"

    # H1 · PIN di 6 cifre, salvato solo come hash
    bad = [rpc("set_pin", {"p_new_pin": p}, tc, dev1)[0] for p in ("12345", "1234567", "abcdef")]
    ok = rpc("set_pin", {"p_new_pin": "482913"}, tc, dev1)
    stored = sql(f"select pin_hash from private.account_security where id = '{UID_C}';")
    check("H1", "PIN solo di 6 cifre; sul server c'è solo l'hash, mai il PIN",
          all(b >= 400 for b in bad) and ok[0] in (200, 204) and stored.startswith("$2")
          and "482913" not in stored, f"HTTP {bad}, {ok[0]}")

    # H2 · Telefono attendibile: tutto normale
    s1, me1 = rpc("get_my_profile", {}, tc, dev1)
    s2, st1 = rpc("security_status", {}, tc, dev1)
    check("H2", "Dal telefono su cui è stato impostato il PIN l'utente vede i propri dati",
          s1 == 200 and isinstance(me1, dict) and me1.get("username") == "utente_c"
          and st1.get("pin_enabled") is True and st1.get("device_trusted") is True)

    # H3 · Telefono nuovo (o nessun codice): nessun accesso ai dati finché non c'è il PIN
    s3, me2 = rpc("get_my_profile", {}, tc, dev2)
    s4, me3 = rpc("get_my_profile", {}, tc)
    priv = rows(get(f"/rest/v1/profile_private?id=eq.{UID_C}", tc))
    upd = rpc("update_my_profile", {"p_username": "rubato", "p_full_name": "Carla Neri",
                                    "p_bio": None, "p_social_links": {}, "p_show_bio": True,
                                    "p_show_social": True}, tc, dev2)
    chg = rpc("set_pin", {"p_new_pin": "111111"}, tc, dev2)
    _, st2 = rpc("security_status", {}, tc, dev2)
    check("H3", "Da un telefono nuovo, senza PIN: nessun dato letto o modificato",
          me2 is None and me3 is None and priv == [] and upd[0] >= 400 and chg[0] >= 400
          and st2.get("pin_enabled") is True and st2.get("device_trusted") is False,
          f"HTTP {s3}, {s4}, {upd[0]}, {chg[0]}")

    # H4 · PIN sbagliato: niente accesso; 5 errori bloccano i tentativi
    wrong = [rpc("verify_pin", {"p_pin": "000000"}, tc, dev2)[1] for _ in range(5)]
    locked = rpc("verify_pin", {"p_pin": "482913"}, tc, dev2)
    _, st3 = rpc("security_status", {}, tc, dev2)
    check("H4", "PIN errato: nessun accesso; dopo 5 errori anche il PIN giusto deve aspettare",
          wrong == [False] * 5 and locked[0] >= 400 and st3.get("locked_until") is not None
          and st3.get("device_trusted") is False, f"{wrong}, HTTP {locked[0]}")
    sql(f"update private.account_security set locked_until = null where id = '{UID_C}';")

    # H5 · PIN giusto: il telefono nuovo diventa attendibile
    right = rpc("verify_pin", {"p_pin": "482913"}, tc, dev2)
    s5, me4 = rpc("get_my_profile", {}, tc, dev2)
    check("H5", "PIN corretto: il telefono nuovo vede di nuovo i propri dati",
          right[1] is True and s5 == 200 and isinstance(me4, dict))

    # H6 · Cambiare o togliere il PIN richiede quello attuale
    c1 = rpc("set_pin", {"p_new_pin": "222222", "p_current_pin": "999999"}, tc, dev1)
    c2 = rpc("disable_pin", {"p_pin": "999999"}, tc, dev1)
    c3 = rpc("set_pin", {"p_new_pin": "735102", "p_current_pin": "482913"}, tc, dev1)
    check("H6", "Cambio o disattivazione del PIN solo con il PIN attuale",
          c1[0] >= 400 and c2[0] >= 400 and c3[0] in (200, 204),
          f"HTTP {c1[0]}, {c2[0]}, {c3[0]}")

    # H7 · Uscita sicura: il telefono non è più attendibile
    rpc("forget_this_device", {}, tc, dev2)
    _, me5 = rpc("get_my_profile", {}, tc, dev2)
    _, me6 = rpc("get_my_profile", {}, tc, dev1)
    check("H7", "Dopo l'uscita sicura quel telefono richiede di nuovo il PIN; gli altri no",
          me5 is None and isinstance(me6, dict))

    # H8 · PIN dimenticato: ripristino solo dopo 7 giorni
    early = rpc("complete_pin_reset", {}, tc, dev2)
    s6, avail = rpc("request_pin_reset", {}, tc, dev2)
    still = rpc("complete_pin_reset", {}, tc, dev2)
    sql(f"update private.account_security set reset_requested_at = now() - interval '8 days' "
        f"where id = '{UID_C}';")
    done = rpc("complete_pin_reset", {}, tc, dev2)
    _, me7 = rpc("get_my_profile", {}, tc, dev2)
    _, st4 = rpc("security_status", {}, tc, dev2)
    check("H8", "PIN dimenticato: ripristino possibile solo dopo 7 giorni dalla richiesta",
          early[0] >= 400 and s6 == 200 and avail is not None and still[0] >= 400
          and done[0] in (200, 204) and isinstance(me7, dict) and st4.get("pin_enabled") is False,
          f"HTTP {early[0]}, {still[0]}, {done[0]}")

    # H9 · Nessuno rende attendibile un telefono per altri o legge i dati del PIN
    t1 = rpc("trust_this_device", {"p_uid": UID_A}, tc, dev2)
    t2 = get("/rest/v1/account_security", tc)
    t3 = rpc("current_uid_raw", {}, tc, dev2)
    check("H9", "Funzioni interne e dati del PIN non raggiungibili dall'app",
          t1[0] >= 400 and t2[0] >= 400 and t3[0] >= 400, f"HTTP {t1[0]}, {t2[0]}, {t3[0]}")

    # H10 · Gli utenti senza PIN non cambiano comportamento
    s7, me8 = rpc("get_my_profile", {}, token(UID_A))
    check("H10", "Senza PIN tutto funziona come prima, anche senza codice del telefono",
          s7 == 200 and isinstance(me8, dict) and me8.get("username") == "utente_a")


def check_contacts_block5() -> None:
    """I · Rubrica (Fase 2, Blocco 5). Utenti A, B, D; codici OPRF simulati."""
    attest_key = "chiave-di-firma-solo-per-test-0123456789"
    sql("insert into private.settings (key, value) values ('rubrica_attest_key', "
        f"'{attest_key}') on conflict (key) do update set value = excluded.value;")
    phones = {UID_A: "+393000000001", UID_B: "+393000000002", UID_D: "+393000000004"}
    tags = {u: hashlib.sha256(f"tag-{u}".encode()).hexdigest() for u in phones}
    tok = {u: token(u, extra={"phone_number": p}) for u, p in phones.items()}

    def sign(uid, phone, tag, ts):
        return hmac.new(attest_key.encode(), f"{uid}|{phone}|{tag}|{ts}".encode(),
                        hashlib.sha256).hexdigest()

    def register(uid, phone=None, tag=None, ts=None, sig=None):
        phone = phone or phones[uid]
        tag = tag or tags[uid]
        ts = ts if ts is not None else int(time.time())
        sig = sig or sign(uid, phone, tag, ts)
        return rpc("register_my_phone", {"p_phone": phone, "p_tag": tag, "p_ts": ts,
                                         "p_sig": sig}, tok[uid])

    # I1 · Il proprio numero si registra solo con la firma del server e il numero dell'accesso
    bad_sig = register(UID_A, sig="00" * 32)
    other_phone = register(UID_A, phone=phones[UID_B])
    old = register(UID_A, ts=int(time.time()) - 3600)
    ok = [register(u)[0] for u in (UID_A, UID_B, UID_D)]
    check("I1", "Numero registrato solo con firma valida, recente e uguale a quello dell'accesso",
          bad_sig[0] >= 400 and other_phone[0] >= 400 and old[0] >= 400
          and all(x in (200, 204) for x in ok), f"HTTP {bad_sig[0]}, {other_phone[0]}, {old[0]}, {ok}")

    # I2 · Senza consenso niente sincronizzazione; «trovarmi» non si accende da solo
    no_consent = rpc("match_contacts", {"p_tags": [tags[UID_B]]}, tok[UID_A])
    disc = rpc("set_discoverable", {"p_value": True}, tok[UID_D])
    _, pd = rpc("get_my_privacy", {}, tok[UID_D])
    check("I2", "Senza consenso: nessuna sincronizzazione e «trovarmi» non attivabile",
          no_consent[0] >= 400 and disc[0] >= 400 and pd.get("discoverable") is False
          and pd.get("contacts_enabled") is False, f"HTTP {no_consent[0]}, {disc[0]}")

    # I3 · Consenso con data; chi l'ha attivato è trovabile; il riconoscimento funziona
    for u in (UID_A, UID_B):
        rpc("enable_contacts", {}, tok[u])
    s1, found = rpc("match_contacts", {"p_tags": [tags[UID_B], tags[UID_D], "ab" * 32]}, tok[UID_A])
    _, pa = rpc("get_my_privacy", {}, tok[UID_A])
    cons = rows(get("/rest/v1/consents?select=kind,granted_at,revoked_at", tok[UID_A]))
    check("I3", "Consenso registrato con data; riconosciuto solo chi ha attivato «trovarmi»",
          s1 == 200 and [f["id"] for f in found] == [UID_B]
          and pa.get("contacts_enabled") is True and pa.get("contacts_synced_at") is not None
          and pa.get("contacts_expire_at") is not None and len(cons) == 1
          and cons[0]["revoked_at"] is None, str(found))

    # I4 · Numero visibile solo al contatto riconosciuto, se consentito; mai agli altri
    _, mine = rpc("my_contacts", {}, tok[UID_A])
    seen = rpc("contact_phone", {"p_id": UID_B}, tok[UID_A])[1]
    stranger = rpc("contact_phone", {"p_id": UID_B}, tok[UID_D])[1]
    rpc("set_phone_visibility", {"p_value": "nobody"}, tok[UID_B])
    hidden = rpc("contact_phone", {"p_id": UID_B}, tok[UID_A])[1]
    rpc("set_phone_visibility", {"p_value": "contacts"}, tok[UID_B])
    check("I4", "Numero di B: lo vede A che lo ha in rubrica; mai uno sconosciuto; con «Nessuno» nessuno",
          mine and mine[0].get("phone") == phones[UID_B] and seen == phones[UID_B]
          and stranger is None and hidden is None, f"{seen}, {stranger}, {hidden}")

    # I5 · «Trovarmi» spento: non si viene più riconosciuti
    rpc("set_discoverable", {"p_value": False}, tok[UID_B])
    _, again = rpc("match_contacts", {"p_tags": [tags[UID_B]]}, tok[UID_A])
    rpc("set_discoverable", {"p_value": True}, tok[UID_B])
    check("I5", "Con «trovarmi» spento B non viene riconosciuto", again == [], str(again))

    # I6 · Limiti: 3 sincronizzazioni al giorno, 2.000 numeri, solo codici validi
    third = rpc("match_contacts", {"p_tags": [tags[UID_B]]}, tok[UID_A])
    fourth = rpc("match_contacts", {"p_tags": [tags[UID_B]]}, tok[UID_A])
    big = rpc("match_contacts", {"p_tags": ["ab" * 32] * 2001}, tok[UID_B])
    junk = rpc("match_contacts", {"p_tags": ["+393000000001"]}, tok[UID_B])
    check("I6", "Al massimo 3 sincronizzazioni al giorno e 2.000 codici; niente numeri in chiaro",
          third[0] == 200 and fourth[0] >= 400 and big[0] >= 400 and junk[0] >= 400,
          f"HTTP {third[0]}, {fourth[0]}, {big[0]}, {junk[0]}")

    # I7 · Blocco: il contatto sparisce
    rpc("block_user", {"p_user_id": UID_A}, tok[UID_B])
    _, blocked = rpc("my_contacts", {}, tok[UID_A])
    rpc("unblock_user", {"p_user_id": UID_A}, tok[UID_B])
    check("I7", "Se uno dei due blocca l'altro, il contatto non compare", blocked == [], str(blocked))

    # I8 · Scadenza dopo 30 giorni
    sql(f"update private.contact_links set expires_at = now() - interval '1 second' "
        f"where owner_id = '{UID_A}';")
    _, expired = rpc("my_contacts", {}, tok[UID_A])
    sql(f"update private.contact_links set expires_at = now() + interval '30 days' "
        f"where owner_id = '{UID_A}';")
    check("I8", "Dati della rubrica scaduti: non più usati", expired == [], str(expired))

    # I9 · Revoca e cancella
    rv = rpc("revoke_contacts", {}, tok[UID_A])
    _, after = rpc("my_contacts", {}, tok[UID_A])
    links = sql(f"select count(*) from private.contact_links where owner_id = '{UID_A}';")
    _, pa2 = rpc("get_my_privacy", {}, tok[UID_A])
    nomore = rpc("match_contacts", {"p_tags": [tags[UID_B]]}, tok[UID_B])
    check("I9", "«Revoca e cancella»: dati derivati cancellati subito, consenso revocato",
          rv[0] in (200, 204) and after == [] and links == "0"
          and pa2.get("contacts_enabled") is False and pa2.get("contacts_synced_at") is None,
          f"HTTP {rv[0]}, link {links}")

    # I10 · Tabelle private non raggiungibili, consensi altrui non leggibili, senza token niente
    t1 = get("/rest/v1/phone_numbers", tok[UID_A])
    t2 = rows(get(f"/rest/v1/consents?user_id=eq.{UID_B}", tok[UID_A]))
    t3 = rpc("my_contacts", {})
    t4 = rpc("contacts_consent_active", {"p_uid": UID_B}, tok[UID_A])
    check("I10", "Numeri e codici solo sul server; consensi altrui e funzioni interne non accessibili",
          t1[0] >= 400 and t2 == [] and t3[0] >= 400 and t4[0] >= 400,
          f"HTTP {t1[0]}, {t3[0]}, {t4[0]}")


def check_map_listings_phase3() -> None:
    """J · Annunci della Mappa (Fase 3, Blocco 2). Utenti A e B."""
    ta, tb = token(UID_A), token(UID_B)
    soon = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3 * 3600))
    week = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 7 * 86400))
    too_far = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 8 * 86400))
    past = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 60))

    def publish(tok, title="Chi viene a prendere un caffè?", lat=43.7696, lon=11.2558,
                mode="approximate", expires=None, photos=None, details=""):
        return rpc("publish_map_listing", {
            "p_title": title, "p_details": details, "p_lat": lat, "p_lon": lon,
            "p_location_mode": mode, "p_expires_at": expires or soon,
            "p_photos": photos or []}, tok)

    def mine(tok):
        return rows(rpc("my_map_listings", {}, tok))

    # J1 · Zona approssimata (preselezionata): gli altri vedono solo la zona, l'autore il punto
    up = storage("POST", f"listing-photos/{UID_A}/fotoProva0001.jpg", ta, JPEG)
    s, approx_id = publish(ta, photos=[f"{UID_A}/fotoProva0001.jpg"])
    seen = by_id(near(43.7696, 11.2558, tb), approx_id)
    own = next((x for x in mine(ta) if x["id"] == approx_id), None)
    check("J1", "Annuncio Libero in zona approssimata: gli altri vedono solo la zona, l'autore il suo punto",
          up == 200 and s == 200 and seen is not None and seen["category"] == "libera"
          and seen["location_mode"] == "approximate"
          and (abs(seen["approx_lat"] - 43.7696) > 1e-4 or abs(seen["approx_lon"] - 11.2558) > 1e-4)
          and "exact" not in json.dumps(seen) and own is not None
          and abs(own["exact_lat"] - 43.7696) < 1e-6 and own["status"] == "active"
          and own["photos"] == [f"{UID_A}/fotoProva0001.jpg"],
          f"HTTP foto {up}, pubblica {s}")

    # J2 · Punto scelto a mano (bar, punto d'incontro): visibile esattamente
    s, manual_id = publish(ta, title="Calcetto stasera, ci manca uno", lat=43.7731, lon=11.2560,
                           mode="precise", expires=week)
    seen = by_id(near(43.7731, 11.2560, tb), manual_id)
    check("J2", "Punto scelto a mano: gli altri vedono esattamente quel punto",
          s == 200 and seen is not None and seen["location_mode"] == "precise"
          and abs(seen["approx_lat"] - 43.7731) < 1e-6, f"HTTP {s}")

    # J3 · Regole: testo, scadenza (1 ora - 7 giorni), foto proprie ed esistenti, massimo 4
    storage("POST", f"listing-photos/{UID_B}/fotoDiB0001.jpg", tb, JPEG)
    bad = {
        "testo corto": publish(ta, title="ok")[0],
        "oltre 7 giorni": publish(ta, expires=too_far)[0],
        "già scaduto": publish(ta, expires=past)[0],
        "foto di B": publish(ta, photos=[f"{UID_B}/fotoDiB0001.jpg"])[0],
        "foto inesistente": publish(ta, photos=[f"{UID_A}/nonCaricata001.jpg"])[0],
        "5 foto": publish(ta, photos=[f"{UID_A}/fotoProva0001.jpg"] * 5)[0],
        "senza modalità": rpc("publish_map_listing", {
            "p_title": "Senza modalità", "p_details": "", "p_lat": 43.77, "p_lon": 11.25,
            "p_location_mode": None, "p_expires_at": soon}, ta)[0],
    }
    check("J3", "Testo, scadenza, foto e modalità controllati dal server",
          all(code >= 400 for code in bad.values()),
          ", ".join(f"{k}: {v}" for k, v in bad.items() if v < 400))

    # J4 · Una zona approssimata non diventa «precisa» senza un punto scelto a mano
    r = rpc("set_listing_location_mode", {"p_listing_id": approx_id, "p_mode": "precise"}, ta)
    seen = by_id(near(43.7696, 11.2558, tb), approx_id)
    check("J4", "La posizione reale del telefono non si rende visibile cambiando modalità",
          r[0] >= 400 and seen is not None and seen["location_mode"] == "approximate"
          and (abs(seen["approx_lat"] - 43.7696) > 1e-4 or abs(seen["approx_lon"] - 11.2558) > 1e-4),
          f"HTTP {r[0]}")

    # J5 · Modifica solo dall'autore e solo con le funzioni previste
    ok = rpc("update_my_listing", {"p_id": approx_id, "p_title": "Caffè al bar della piazza?",
                                   "p_details": "Verso le 17", "p_expires_at": soon,
                                   "p_photos": []}, ta)
    other = rpc("update_my_listing", {"p_id": approx_id, "p_title": "Modificato da B",
                                      "p_details": "", "p_expires_at": soon, "p_photos": []}, tb)
    direct = request("PATCH", f"/rest/v1/listings?id=eq.{approx_id}", jwt=ta,
                     prefer="return=representation", body={"title": "Diretto"})
    own = next((x for x in mine(ta) if x["id"] == approx_id), None)
    check("J5", "L'autore modifica testo, scadenza e foto; nessun altro, nessuna scrittura diretta",
          ok[0] in (200, 204) and other[0] >= 400 and direct[0] >= 400 and own is not None
          and own["title"] == "Caffè al bar della piazza?" and own["photos"] == [],
          f"HTTP {ok[0]}, {other[0]}, {direct[0]}")

    # J6 · Spostare il punto: nuovo punto scelto a mano, oppure di nuovo la zona
    mv = rpc("move_my_listing", {"p_id": approx_id, "p_lat": 43.7800, "p_lon": 11.2400,
                                 "p_location_mode": "precise"}, ta)
    seen = by_id(near(43.7800, 11.2400, tb), approx_id)
    mv_b = rpc("move_my_listing", {"p_id": approx_id, "p_lat": 43.0, "p_lon": 11.0,
                                   "p_location_mode": "precise"}, tb)
    check("J6", "Solo l'autore sposta l'annuncio; il nuovo punto scelto è quello visibile",
          mv[0] in (200, 204) and mv_b[0] >= 400 and seen is not None
          and abs(seen["approx_lat"] - 43.78) < 1e-6, f"HTTP {mv[0]}, {mv_b[0]}")

    # J7 · Chiudere: sparisce dalla mappa, resta tra i miei come chiuso; non si riapre da solo
    cl = rpc("close_my_listing", {"p_id": manual_id}, ta)
    gone = by_id(near(43.7731, 11.2560, tb), manual_id) is None
    own = next((x for x in mine(ta) if x["id"] == manual_id), None)
    revive = request("PATCH", f"/rest/v1/listings?id=eq.{manual_id}", jwt=ta,
                     prefer="return=representation", body={"status": "active"})
    again = rpc("update_my_listing", {"p_id": manual_id, "p_title": "Riaperto",
                                      "p_details": "", "p_expires_at": soon, "p_photos": []}, ta)
    check("J7", "Annuncio chiuso: non più sulla mappa, non modificabile né riattivabile",
          cl[0] in (200, 204) and gone and own is not None and own["status"] == "completed"
          and revive[0] >= 400 and again[0] >= 400, f"HTTP {cl[0]}, {revive[0]}, {again[0]}")

    # J8 · Blocchi (P12): gli annunci non si vedono in nessuna delle due direzioni
    s, b_id = publish(tb, title="Annuncio di B a Firenze", lat=43.7700, lon=11.2500)
    rpc("block_user", {"p_user_id": UID_B}, ta)
    b_sees_a = by_id(near(43.78, 11.24, tb, radius=10000), approx_id)
    a_sees_b = by_id(near(43.77, 11.25, ta, radius=10000), b_id)
    b_direct = rows(get(f"/rest/v1/listings?id=eq.{approx_id}&select=id", tb))
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    back = by_id(near(43.78, 11.24, tb, radius=10000), approx_id)
    check("J8", "Con un blocco gli annunci spariscono per entrambi; dopo lo sblocco tornano",
          s == 200 and b_sees_a is None and a_sees_b is None and b_direct == [] and back is not None)

    # J9 · Senza token: niente pubblicazione né elenco
    n1 = publish(None)
    n2 = rpc("my_map_listings", {})
    check("J9", "Senza token: non si pubblica e non si leggono annunci",
          n1[0] >= 400 and n2[0] >= 400, f"HTTP {n1[0]}, {n2[0]}")


def check_nearby_phase3() -> None:
    """K · Annunci vicini, filtri, «Disponibile ora», segnalazione (Fase 3, Blocco 3)."""
    ta, tb = token(UID_A), token(UID_B)
    soon = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3 * 3600))
    BO = (44.4949, 11.3426)

    def publish(tok, title, lat, lon, mode="approximate"):
        s, body = rpc("publish_map_listing", {
            "p_title": title, "p_details": "", "p_lat": lat, "p_lon": lon,
            "p_location_mode": mode, "p_expires_at": soon, "p_photos": []}, tok)
        return body if s == 200 else None

    def nearby(tok, lat=BO[0], lon=BO[1], **kw):
        params = {"p_lat": lat, "p_lon": lon}
        params.update(kw)
        s, body = rpc("map_listings_nearby", params, tok)
        return s, (body if isinstance(body, list) else [])

    def find(items, lid):
        return next((x for x in items if x["id"] == lid), None)

    a_here = publish(ta, "Aperitivo in piazza Maggiore?", *BO)
    a_20km = publish(ta, "Giro in bici sui colli", 44.6710, 11.3426, "precise")
    a_40km = publish(ta, "Pesca al lago", 44.8550, 11.3426, "precise")

    # K1 · Annunci vicini con il profilo pubblico essenziale, mai il punto salvato
    s, items = nearby(tb, p_radius_m=10000)
    seen = find(items, a_here)
    _, mine = nearby(ta, p_radius_m=10000)
    own = find(mine, a_here)
    check("K1", "Annunci vicini: zona pubblica, distanza arrotondata, @username; nessun punto salvato",
          s == 200 and seen is not None and seen["is_mine"] is False
          and seen["owner_id"] == UID_A and seen["owner_username"]
          and seen["category"] == "libera" and seen["distance_band_m"] % 250 == 0
          and (abs(seen["lat"] - BO[0]) > 1e-4 or abs(seen["lon"] - BO[1]) > 1e-4)
          and "exact" not in json.dumps(seen) and own is not None and own["is_mine"] is True,
          f"HTTP {s}")

    # K2 · Raggio: 10 km di partenza, fino a 30 km, mai oltre (Milano non vede Torino)
    _, r10 = nearby(tb, p_radius_m=10000)
    _, r30 = nearby(tb, p_radius_m=30000)
    _, r99 = nearby(tb, p_radius_m=99000)
    check("K2", "Raggio rispettato: 20 km fuori a 10 km, dentro a 30 km; 40 km mai, anche chiedendo 99 km",
          find(r10, a_20km) is None and find(r30, a_20km) is not None
          and find(r30, a_40km) is None and find(r99, a_40km) is None)

    # K3 · Categoria: la scheda Promozioni non mostra gli annunci Liberi (vuota fino alla Fase 6)
    _, promo = nearby(tb, p_radius_m=30000, p_category="promozione")
    check("K3", "Scheda Promozioni separata dagli annunci delle persone",
          find(promo, a_here) is None and find(promo, a_20km) is None)

    # K4 · Orario: pubblicati nell'ultima ora (gli annunci appena creati ci sono)
    sql("select set_config('nexus.internal', 'on', false); "
        f"update public.listings set created_at = now() - interval '5 hours' where id = '{a_20km}'")
    _, last_hour = nearby(tb, p_radius_m=30000, p_published_within_hours=1)
    _, today = nearby(tb, p_radius_m=30000, p_published_within_hours=24)
    check("K4", "Filtro orario: nell'ultima ora solo i recenti; in 24 ore anche quello di 5 ore fa",
          find(last_hour, a_here) is not None and find(last_hour, a_20km) is None
          and find(today, a_20km) is not None)

    # K5 · «Disponibile ora»: lo imposta solo l'autore; il filtro lo rispetta
    _, before = nearby(tb, p_radius_m=10000, p_available_now=True)
    on = rpc("set_my_listing_available", {"p_id": a_here, "p_available": True}, ta)
    other = rpc("set_my_listing_available", {"p_id": a_here, "p_available": False}, tb)
    _, after = nearby(tb, p_radius_m=10000, p_available_now=True)
    mine_list = rows(rpc("my_map_listings", {}, ta))
    own = next((x for x in mine_list if x["id"] == a_here), None)
    check("K5", "«Disponibile ora» solo dall'autore e filtrabile",
          find(before, a_here) is None and on[0] in (200, 204) and other[0] >= 400
          and find(after, a_here) is not None and own is not None and own["available_now"] is True,
          f"HTTP {on[0]}, {other[0]}")

    # K6 · Blocchi: spariscono dagli annunci vicini, in entrambe le direzioni
    b_here = publish(tb, "Partita a scacchi al parco", 44.4960, 11.3440)
    rpc("block_user", {"p_user_id": UID_A}, tb)
    _, b_view = nearby(tb, p_radius_m=10000)
    _, a_view = nearby(ta, p_radius_m=10000)
    rpc("unblock_user", {"p_user_id": UID_A}, tb)
    _, b_back = nearby(tb, p_radius_m=10000)
    check("K6", "Con un blocco gli annunci vicini spariscono per entrambi; dopo lo sblocco tornano",
          b_here is not None and find(b_view, a_here) is None and find(a_view, b_here) is None
          and find(b_back, a_here) is not None)

    # K7 · Segnalazione: motivo da elenco, una sola aperta, mai sui propri annunci
    r1 = rpc("report_listing", {"p_listing": a_here, "p_reason": "spam"}, tb)
    r2 = rpc("report_listing", {"p_listing": a_here, "p_reason": "spam"}, tb)
    bad = rpc("report_listing", {"p_listing": a_here, "p_reason": "non mi piace"}, tb)
    selfrep = rpc("report_listing", {"p_listing": a_here, "p_reason": "spam"}, ta)
    mine_reports = rows(get(f"/rest/v1/reports?target_id=eq.{a_here}&select=id,reason,status", tb))
    a_reads = rows(get(f"/rest/v1/reports?target_id=eq.{a_here}&select=id", ta))
    check("K7", "Segnalazione registrata una volta; motivo libero e autosegnalazione rifiutati; l'autore non la vede",
          r1[0] in (200, 204) and r2[0] in (200, 204) and bad[0] >= 400 and selfrep[0] >= 400
          and len(mine_reports) == 1 and mine_reports[0]["status"] == "open" and a_reads == [],
          f"HTTP {r1[0]}, {r2[0]}, {bad[0]}, {selfrep[0]}, segnalazioni {len(mine_reports)}")

    # K8 · Senza token: nessun annuncio vicino, nessuna segnalazione
    n1 = rpc("map_listings_nearby", {"p_lat": BO[0], "p_lon": BO[1]})
    n2 = rpc("report_listing", {"p_listing": a_here, "p_reason": "spam"})
    check("K8", "Senza token: niente annunci vicini né segnalazioni",
          (n1[0] >= 400 or n1[1] == []) and n2[0] >= 400, f"HTTP {n1[0]}, {n2[0]}")


def check_interactions_phase3() -> None:
    """L · Eventi di gruppo, reazioni, commenti, notifiche (Fase 3, Blocco 4). A, B, C, D."""
    ta, tb, tc, td = token(UID_A), token(UID_B), token(UID_C), token(UID_D)
    soon = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3 * 3600))
    PD = (45.4064, 11.8768)

    s, ev = rpc("publish_map_listing", {
        "p_title": "Ci mancano due persone per il calcetto", "p_details": "", "p_lat": PD[0],
        "p_lon": PD[1], "p_location_mode": "precise", "p_expires_at": soon, "p_photos": [],
        "p_group_spots": 2}, ta)

    def social(tok):
        return rpc("listing_social", {"p_listing": ev}, tok)[1] or {}

    def people(tok, what):
        return [x["user_id"] for x in rows(rpc("listing_people", {"p_listing": ev, "p_what": what}, tok))]

    def notes(tok):
        return rows(rpc("my_notifications", {}, tok))

    # L1 · Evento di gruppo: partecipo, conteggio, «mancano N persone», al completo
    j_b = rpc("join_listing", {"p_listing": ev}, tb)
    j_d = rpc("join_listing", {"p_listing": ev}, td)
    j_c = rpc("join_listing", {"p_listing": ev}, tc)
    j_a = rpc("join_listing", {"p_listing": ev}, ta)
    full = social(tb)
    near_resp = rpc("map_listings_nearby", {"p_lat": PD[0], "p_lon": PD[1]}, tc)
    if near_resp[0] != 200:
        print(f"map_listings_nearby (C): HTTP {near_resp[0]} {str(near_resp[1])[:300]}")
    near_items = rows(near_resp)
    seen = next((x for x in near_items if x["id"] == ev), {})
    rpc("leave_listing", {"p_listing": ev}, tb)
    after = social(tc)
    check("L1", "Evento: partecipano in 2 su 2, poi al completo; l'autore non partecipa; si può uscire",
          s == 200 and j_b[0] in (200, 204) and j_d[0] in (200, 204) and j_c[0] >= 400
          and j_a[0] >= 400 and full.get("participants") == 2 and full.get("i_participate") is True
          and full.get("group_spots") == 2 and seen.get("participants") == 2
          and seen.get("group_spots") == 2 and after.get("participants") == 1,
          f"HTTP {s}, {j_b[0]}, {j_d[0]}, {j_c[0]}, {j_a[0]}")

    # L2 · Mi piace avvisa l'autore (raggruppati); Non mi piace mai
    rpc("set_listing_reaction", {"p_listing": ev, "p_kind": "like"}, tb)
    rpc("set_listing_reaction", {"p_listing": ev, "p_kind": "like"}, td)
    rpc("set_listing_reaction", {"p_listing": ev, "p_kind": "dislike"}, tc)
    rpc("set_listing_reaction", {"p_listing": ev, "p_kind": "dislike"}, tb)
    likes_a = [n for n in notes(ta) if n["listing_id"] == ev and n["kind"] == "listing_like"]
    kinds_a = {n["kind"] for n in notes(ta) if n["listing_id"] == ev}
    counts = social(tc)
    check("L2", "Mi piace raggruppati in una notifica all'autore; i Non mi piace non avvisano",
          len(likes_a) == 1 and likes_a[0]["actor_count"] == 2 and kinds_a == {"listing_like"}
          and counts.get("likes") == 1 and counts.get("dislikes") == 2
          and counts.get("my_reaction") == "dislike",
          f"notifiche {[(n['kind'], n['actor_count']) for n in notes(ta)]}, conteggi {counts}")

    # L3 · Elenchi di chi ha reagito e di chi partecipa
    check("L3", "Elenchi nominativi di Mi piace, Non mi piace e partecipanti",
          people(tc, "like") == [UID_D] and set(people(tc, "dislike")) == {UID_B, UID_C}
          and people(tc, "participant") == [UID_D])

    # L4 · Commenti e risposte: chi commenta segue il post e riceve le risposte
    _, c_b = rpc("add_listing_comment", {"p_listing": ev, "p_body": "Io ci sono!"}, tb)
    _, r_d = rpc("add_listing_comment", {"p_listing": ev, "p_body": "Anche io", "p_parent": c_b}, td)
    _, r_a = rpc("add_listing_comment", {"p_listing": ev, "p_body": "Perfetto, a stasera",
                                         "p_parent": r_d}, ta)
    nb = {(n["kind"], n["actor_id"]) for n in notes(tb) if n["listing_id"] == ev}
    nd = {(n["kind"], n["actor_id"]) for n in notes(td) if n["listing_id"] == ev}
    na = {(n["kind"], n["actor_id"]) for n in notes(ta) if n["listing_id"] == ev}
    lst = rows(rpc("listing_comments_list", {"p_listing": ev}, tc))
    parents = {x["id"]: x["parent_id"] for x in lst}
    check("L4", "Commenti e risposte (un livello): avvisati autore, chi riceve la risposta e chi segue",
          ("comment_reply", UID_D) in nb and ("followed_comment", UID_A) in nb
          and ("comment_reply", UID_A) in nd
          and ("listing_comment", UID_B) in na and ("listing_comment", UID_D) in na
          and not any(k[1] == UID_A for k in na)
          and parents.get(c_b) is None and parents.get(r_d) == c_b and parents.get(r_a) == c_b,
          f"B {nb}, D {nd}, A {na}")

    # L5 · Mi piace a un commento: avvisato chi l'ha scritto
    rpc("set_comment_like", {"p_comment": c_b, "p_like": True}, ta)
    rpc("set_comment_like", {"p_comment": c_b, "p_like": True}, td)
    lk = [n for n in notes(tb) if n["kind"] == "comment_like" and n["comment_id"] == c_b]
    item = next((x for x in rows(rpc("listing_comments_list", {"p_listing": ev}, ta)) if x["id"] == c_b), {})
    check("L5", "Mi piace ai commenti raggruppati per chi ha scritto il commento",
          len(lk) == 1 and lk[0]["actor_count"] == 2 and item.get("likes") == 2
          and item.get("liked_by_me") is True)

    # L6 · «Disattiva notifiche per questo post»
    before_b = len(notes(tb))
    rpc("set_listing_muted", {"p_listing": ev, "p_muted": True}, tb)
    before_a = len([n for n in notes(ta) if n["kind"] == "listing_comment"])
    rpc("add_listing_comment", {"p_listing": ev, "p_body": "Porto il pallone"}, td)
    after_a = len([n for n in notes(ta) if n["kind"] == "listing_comment"])
    check("L6", "Post silenziato: chi lo ha disattivato non riceve più avvisi, l'autore sì",
          len(notes(tb)) == before_b and after_a == before_a + 1 and social(tb).get("muted") is True)

    # L7 · Blocchi (P12): niente interazioni né visibilità tra A e D
    rpc("block_user", {"p_user_id": UID_D}, ta)
    d_comment = rpc("add_listing_comment", {"p_listing": ev, "p_body": "Ci sei?"}, td)
    d_react = rpc("set_listing_reaction", {"p_listing": ev, "p_kind": "like"}, td)
    a_list = rows(rpc("listing_comments_list", {"p_listing": ev}, ta))
    a_people = people(ta, "like") + people(ta, "participant")
    a_notes = [n for n in notes(ta) if n["actor_id"] == UID_D]
    a_social = social(ta)
    rpc("unblock_user", {"p_user_id": UID_D}, ta)
    check("L7", "Con un blocco: niente commenti né reazioni, e l'autore non vede quelli dell'altro",
          d_comment[0] >= 400 and d_react[0] >= 400
          and all(x["author_id"] != UID_D for x in a_list) and UID_D not in a_people
          and a_notes == [] and a_social.get("likes") == 0,
          f"HTTP {d_comment[0]}, {d_react[0]}")

    # L8 · Cancellare: il proprio commento, o qualsiasi commento del proprio annuncio
    del_other = rpc("delete_my_comment", {"p_comment": c_b}, tc)
    del_owner = rpc("delete_my_comment", {"p_comment": r_d}, ta)
    still = {x["id"] for x in rows(rpc("listing_comments_list", {"p_listing": ev}, tc))}
    check("L8", "Commento cancellato dall'autore dell'annuncio; nessun altro cancella quelli altrui",
          del_other[0] >= 400 and del_owner[0] in (200, 204) and r_d not in still and c_b in still,
          f"HTTP {del_other[0]}, {del_owner[0]}")

    # L9 · Lette: contatore azzerato solo per sé
    _, unread_a = rpc("unread_notifications_count", {}, ta)
    _, unread_b = rpc("unread_notifications_count", {}, tb)
    rpc("mark_notifications_read", {}, ta)
    _, zero_a = rpc("unread_notifications_count", {}, ta)
    _, same_b = rpc("unread_notifications_count", {}, tb)
    check("L9", "«Segna come lette» azzera solo le proprie notifiche",
          unread_a > 0 and zero_a == 0 and same_b == unread_b and unread_b > 0,
          f"{unread_a} → {zero_a}; B {unread_b} → {same_b}")

    # L10 · Nessun accesso diretto alle tabelle; senza token nessuna funzione
    direct = [
        get("/rest/v1/notifications?select=id", ta),
        get("/rest/v1/listing_comments?select=id", ta),
        request("POST", "/rest/v1/listing_reactions", jwt=tb,
                body={"listing_id": ev, "user_id": UID_B, "kind": "like"}),
        request("POST", "/rest/v1/notifications", jwt=tb,
                body={"recipient_id": UID_A, "kind": "listing_like", "listing_id": ev,
                      "actor_id": UID_B}),
    ]
    anon = [rpc("listing_social", {"p_listing": ev}), rpc("my_notifications", {}),
            rpc("set_listing_reaction", {"p_listing": ev, "p_kind": "like"})]
    check("L10", "Tabelle delle interazioni non accessibili direttamente; senza token niente",
          all(denied(r) for r in direct) and all(r[0] >= 400 for r in anon),
          f"{[r[0] for r in direct]}, {[r[0] for r in anon]}")


def check_marketplace_phase5() -> None:
    """M · Scambia & Vendi, Blocco 1: catalogo e pubblicazione (Fase 5). Utenti A, B, D."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    RM = (41.9028, 12.4964)

    s, cats = rpc("marketplace_categories_list", {}, ta)
    cats = cats if isinstance(cats, list) else []
    by_slug = {c["slug"]: c for c in cats}
    parents = [c for c in cats if c["parent_id"] is None]
    subs = [c for c in cats if c["parent_id"] is not None]
    anon = rpc("marketplace_categories_list", {})
    check("M1", "Catalogo: 19 categorie, 271 sottocategorie collegate, slug e ID univoci",
          s == 200 and len(parents) == 19 and len(subs) == 271
          and len({c["slug"] for c in cats}) == 290 and len({c["id"] for c in cats}) == 290
          and all(any(p["id"] == c["parent_id"] for p in parents) for c in subs)
          and "motori-auto" in by_slug and "elettronica-smartphone" in by_slug
          and (anon[0] >= 400 or anon[1] == []),
          f"HTTP {s}: {len(parents)} categorie, {len(subs)} sottocategorie")

    phone = by_slug["elettronica-smartphone"]["id"]
    car = by_slug["motori-auto"]["id"]
    flat = by_slug["immobili-appartamenti-vendita"]["id"]
    repair = by_slug["servizi-riparazioni-elettroniche"]["id"]
    storage("POST", f"listing-photos/{UID_A}/mercatoA0001.jpg", ta, JPEG)
    storage("POST", f"listing-photos/{UID_B}/mercatoB0001.jpg", tb, JPEG)
    storage("POST", f"listing-photos/{UID_D}/mercatoD0001.jpg", td, JPEG)
    pa, pb, pd = [f"{UID_A}/mercatoA0001.jpg"], [f"{UID_B}/mercatoB0001.jpg"], [f"{UID_D}/mercatoD0001.jpg"]

    def publish(tok, **kw):
        body = {"p_type": "sell", "p_category": phone, "p_title": "iPhone 13 128 GB",
                "p_description": "Perfetto, con scatola", "p_price_cents": 35000,
                "p_condition": "excellent", "p_ships": True, "p_pickup": True,
                "p_attributes": {"memoria": "128 GB"}, "p_lat": RM[0], "p_lon": RM[1],
                "p_location_mode": "approximate", "p_photos": pa, "p_wanted_in_exchange": None,
                "p_no_prohibited_items": True}
        body.update(kw)
        return rpc("publish_market_listing", body, tok)

    # M2 · Vendita completa: pubblicata, visibile agli altri, nei propri annunci
    s, res = publish(ta)
    sell_id = (res or {}).get("id") if isinstance(res, dict) else None
    seen_b = rows(get(f"/rest/v1/listings?id=eq.{sell_id}&select=id,kind,market_type", tb))
    mine = next((x for x in rows(rpc("my_market_listings", {}, ta)) if x["id"] == sell_id), None)
    check("M2", "Vendita con foto, prezzo, condizioni e consegna: pubblicata e visibile",
          s == 200 and res.get("review_status") == "published" and len(seen_b) == 1
          and seen_b[0]["market_type"] == "sell" and mine is not None
          and mine["price_cents"] == 35000 and mine["status"] == "active",
          f"HTTP {s} {res}")

    # M3 · Regole della specifica e delle decisioni del titolare
    bad = {
        "vendita senza prezzo": publish(ta, p_price_cents=None)[0],
        "regalo con prezzo": publish(ta, p_type="free")[0],
        "senza foto": publish(ta, p_photos=[])[0],
        "categoria principale": publish(ta, p_category=by_slug["elettronica"]["id"])[0],
        "condizioni mancanti": publish(ta, p_condition=None)[0],
        "condizioni inventate": publish(ta, p_condition="quasi")[0],
        "né ritiro né spedizione": publish(ta, p_ships=False, p_pickup=False)[0],
        "campo non previsto": publish(ta, p_attributes={"km": 1000})[0],
        "auto senza anno": publish(ta, p_category=car, p_attributes={"km": 90000})[0],
        "immobile senza mq": publish(ta, p_category=flat, p_attributes={})[0],
        "divieti non confermati": publish(ta, p_no_prohibited_items=False)[0],
        "foto di un altro": publish(ta, p_photos=pb)[0],
        "11 foto": publish(ta, p_photos=pa * 11)[0],
        "anno assurdo": publish(ta, p_category=car, p_attributes={"anno": 1800})[0],
        "cerco in cambio su vendita": publish(ta, p_wanted_in_exchange="una bici")[0],
    }
    ok = {
        "cerco senza foto": publish(ta, p_type="wanted", p_photos=[], p_price_cents=None,
                                    p_condition=None, p_ships=False, p_pickup=False)[0],
        "regalo senza prezzo": publish(ta, p_type="free", p_price_cents=None)[0],
        "scambio con cosa cerchi": publish(ta, p_type="swap", p_price_cents=None,
                                           p_wanted_in_exchange="una bici da corsa")[0],
        "auto con anno e km": publish(ta, p_category=car, p_title="Fiat Panda 2015",
                                      p_attributes={"anno": 2015, "km": 90000})[0],
        "servizio senza condizioni": publish(ta, p_category=repair, p_title="Riparo smartphone",
                                             p_condition=None, p_ships=False, p_pickup=False,
                                             p_attributes={})[0],
        "immobile con mq": publish(ta, p_category=flat, p_title="Trilocale in centro",
                                   p_price_cents=25000000000, p_condition=None, p_ships=False,
                                   p_pickup=False, p_attributes={"mq": 85, "locali": 3})[0],
    }
    check("M3", "Prezzo, foto, condizioni, consegna, campi specifici, divieti: regole del server",
          all(v >= 400 for v in bad.values()) and all(v == 200 for v in ok.values()),
          ", ".join([f"{k}: {v}" for k, v in bad.items() if v < 400]
                    + [f"{k}: {v}" for k, v in ok.items() if v != 200]))

    # M4 · Parole a rischio: annuncio in revisione, invisibile agli altri
    s, res = publish(tb, p_title="Vendo pistola softair", p_photos=pb)
    flagged = (res or {}).get("id") if isinstance(res, dict) else None
    b_mine = next((x for x in rows(rpc("my_market_listings", {}, tb)) if x["id"] == flagged), None)
    a_sees = rows(get(f"/rest/v1/listings?id=eq.{flagged}&select=id", ta))
    check("M4", "Prodotto a rischio: in revisione, visibile solo all'autore",
          s == 200 and res.get("review_status") == "pending_review" and a_sees == []
          and b_mine is not None and b_mine["review_status"] == "pending_review", f"HTTP {s} {res}")

    # M5 · Categorie: nessuno le modifica dall'app; lo slug non cambia mai
    ins = request("POST", "/rest/v1/marketplace_categories", jwt=ta,
                  body={"id": "00000000-0000-0000-0000-000000000001", "name": "Finta", "slug": "finta"})
    upd = request("PATCH", f"/rest/v1/marketplace_categories?id=eq.{phone}", jwt=ta,
                  prefer="return=representation", body={"name": "Telefonini"})
    try:
        sql(f"update public.marketplace_categories set slug = 'telefonini' where id = '{phone}'")
        slug_locked = False
    except subprocess.CalledProcessError:
        slug_locked = True
    check("M5", "Categorie non modificabili dall'app; slug immutabile anche dal database",
          denied(ins) and denied(upd) and slug_locked, f"HTTP {ins[0]}, {upd[0]}")

    # M6 · Rinnovo a 30 giorni e chiusura solo dall'autore
    if sell_id is None:
        check("M6", "Rinnovo e chiusura (annuncio di prova non pubblicato)", False)
        return
    sql("select set_config('nexus.internal', 'on', false); "
        f"update public.listings set created_at = now() - interval '29 days', "
        f"expires_at = now() + interval '1 day' where id = '{sell_id}'")
    rn = rpc("renew_market_listing", {"p_id": sell_id}, ta)
    rn_b = rpc("renew_market_listing", {"p_id": sell_id}, tb)
    cl_b = rpc("close_market_listing", {"p_id": sell_id}, tb)
    after = next((x for x in rows(rpc("my_market_listings", {}, ta)) if x["id"] == sell_id), {})
    cl = rpc("close_market_listing", {"p_id": sell_id}, ta)
    closed = next((x for x in rows(rpc("my_market_listings", {}, ta)) if x["id"] == sell_id), {})
    check("M6", "Rinnovo di 30 giorni oltre la data di creazione; chiusura; nessun altro li usa",
          rn[0] == 200 and rn_b[0] >= 400 and cl_b[0] >= 400 and cl[0] in (200, 204)
          and after.get("status") == "active" and closed.get("status") == "completed",
          f"HTTP {rn[0]}, {rn_b[0]}, {cl_b[0]}, {cl[0]}")

    # M7 · Non sulla Mappa (D10) né nella vecchia ricerca generica
    _, d_res = publish(td, p_photos=pd, p_title="Bici da corsa", p_attributes={})
    d_id = (d_res or {}).get("id") if isinstance(d_res, dict) else None
    if d_id is None:
        check("M7", "Annuncio di prova di D non pubblicato", False, f"{d_res}")
        return
    m1 = rpc("map_listings_nearby", {"p_lat": RM[0], "p_lon": RM[1], "p_radius_m": 30000}, tb)[1] or []
    m2 = rpc("nearby_listings", {"p_lat": RM[0], "p_lon": RM[1], "p_radius_m": 30000}, tb)[1] or []
    check("M7", "Gli annunci di Scambia & Vendi non compaiono sulla Mappa",
          d_id is not None and all(x["id"] != d_id for x in m1) and all(x["id"] != d_id for x in m2))

    # M8 · Anti-spam (D9): al massimo 20 annunci nuovi al giorno
    sql("insert into public.listings (owner_id, kind, title, approx_location, market_type, "
        "market_category_id, expires_at) "
        f"select owner_id, kind, title, approx_location, market_type, market_category_id, expires_at "
        f"from public.listings, generate_series(1, 19) where id = '{d_id}'")
    s21, _ = publish(td, p_photos=pd, p_title="Ventunesimo annuncio", p_attributes={})
    check("M8", "Il ventunesimo annuncio della giornata viene rifiutato", s21 >= 400, f"HTTP {s21}")


def check_marketplace_search_phase5() -> None:
    """N · Scambia & Vendi, Blocco 2: ricerca, filtri, ordinamenti, scheda (Fase 5). Utenti A, B, D."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    MI = (45.4641, 9.1912)        # Milano: A, zona approssimata
    MI_B = (45.5000, 9.1900)      # circa 4 km a nord: B, punto preciso
    MONZA = (45.5800, 9.2700)     # circa 14 km: D (azienda)
    # Partenza pulita: nessun blocco tra A, B e D; D sotto il limite giornaliero (M8).
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    sql(f"delete from public.listings where owner_id = '{UID_D}' and photos = '{{}}'")

    _, cats = rpc("marketplace_categories_list", {}, ta)
    by_slug = {c["slug"]: c for c in (cats if isinstance(cats, list) else [])}
    music = by_slug["musica-strumenti"]["id"]
    guitars = by_slug["musica-strumenti-chitarre"]["id"]
    basses = by_slug["musica-strumenti-bassi"]["id"]
    amps = by_slug["musica-strumenti-amplificatori"]["id"]
    pa, pb, pd = [f"{UID_A}/mercatoA0001.jpg"], [f"{UID_B}/mercatoB0001.jpg"], [f"{UID_D}/mercatoD0001.jpg"]

    def publish(tok, photos, lat_lon, **kw):
        body = {"p_type": "sell", "p_category": guitars, "p_title": "Chitarra",
                "p_description": "", "p_price_cents": 10000, "p_condition": "good",
                "p_ships": False, "p_pickup": True, "p_attributes": {},
                "p_lat": lat_lon[0], "p_lon": lat_lon[1], "p_location_mode": "approximate",
                "p_photos": photos, "p_wanted_in_exchange": None, "p_no_prohibited_items": True,
                "p_open_to_swap": False, "p_cash_adjustment": False}
        body.update(kw)
        s, res = rpc("publish_market_listing", body, tok)
        return s, (res.get("id") if isinstance(res, dict) else None)

    def search(tok=ta, **kw):
        body = {"p_section": "sale", "p_lat": MI[0], "p_lon": MI[1], "p_radius_km": 30}
        body.update(kw)
        s, res = rpc("market_search", body, tok)
        return s, (res if isinstance(res, list) else [])

    def ids(res):
        return [x["id"] for x in res]

    s1, a_gtr = publish(ta, pa, MI, p_title="Chitarra acustica Yamaha",
                        p_description="Corde nuove, custodia inclusa", p_price_cents=15000,
                        p_open_to_swap=True, p_cash_adjustment=True)
    s2, b_gtr = publish(tb, pb, MI_B, p_title="Chitarra elettrica Fender Stratocaster",
                        p_price_cents=60000, p_condition="like_new", p_ships=True, p_pickup=False,
                        p_location_mode="precise")
    s3, d_amp = publish(td, pd, MONZA, p_category=amps, p_title="Amplificatore valvolare",
                        p_description="Perfetto per chitarra elettrica", p_price_cents=20000,
                        p_condition="new", p_ships=True, p_pickup=True)
    s4, b_bass = publish(tb, pb, MI_B, p_type="swap", p_category=basses, p_title="Basso elettrico",
                         p_price_cents=None, p_wanted_in_exchange="una chitarra",
                         p_cash_adjustment=True, p_location_mode="precise")
    check("N0", "Annunci di prova per la ricerca pubblicati (anche con le opzioni di scambio)",
          all(x == 200 for x in (s1, s2, s3, s4)) and None not in (a_gtr, b_gtr, d_amp, b_bass),
          f"HTTP {s1}, {s2}, {s3}, {s4}")
    if None in (a_gtr, b_gtr, d_amp, b_bass):
        return

    # N1 · Due sezioni, un solo sistema (D10); parametri controllati dal server
    s, sale = search(p_category=music)
    _, swap = search(p_section="swap", p_category=music)
    anon = rpc("market_search", {"p_section": "sale"})
    bad = [search(p_section="mappa")[0], search(p_sort="a_caso")[0],
           search(p_section="sale", p_types=["swap"])[0], search(p_seller="amici")[0],
           search(p_price_min_cents=500, p_price_max_cents=100)[0],
           search(p_sort="nearest", p_lat=None, p_lon=None)[0],
           search(p_conditions=["rotto"])[0]]
    check("N1", "Vendita mostra solo vendite, Scambia scambi/regali/cerco; parametri errati rifiutati",
          s == 200 and set(ids(sale)) == {a_gtr, b_gtr, d_amp} and ids(swap) == [b_bass]
          and all(x["market_type"] == "sell" for x in sale) and anon[0] >= 400
          and all(x >= 400 for x in bad), f"HTTP {s}, {ids(sale)}, {ids(swap)}, {bad}")

    # N2 · Ricerca per parola (D4): radici italiane, parti di parola nel titolo, «Più pertinenti»
    _, w1 = search(p_query="chitarre")                 # plurale → chitarra/chitarre
    _, w2 = search(p_query="strato")                   # parte di parola nel titolo
    _, w3 = search(p_query="chitarra", p_sort="relevant")
    _, w4 = search(p_query="pianoforte")
    check("N2", "Parola nel titolo o nella descrizione; i titoli che la contengono vengono prima",
          set(ids(w1)) == {a_gtr, b_gtr, d_amp} and ids(w2) == [b_gtr]
          and set(ids(w3)[:2]) == {a_gtr, b_gtr} and ids(w3)[2:] == [d_amp] and w4 == [],
          f"{len(w1)}, {ids(w2)}, {len(w3)}, {len(w4)}")

    # N3 · Filtri: categoria, sottocategoria, prezzo, condizioni, privato/azienda, consegna
    f = {
        "sottocategoria": ids(search(p_category=music, p_subcategory=amps)[1]) == [d_amp],
        "prezzo": set(ids(search(p_category=music, p_price_min_cents=15000,
                                 p_price_max_cents=20000)[1])) == {a_gtr, d_amp},
        "condizioni": ids(search(p_category=music, p_conditions=["like_new", "fair"])[1]) == [b_gtr],
        "azienda": ids(search(p_category=music, p_seller="business")[1]) == [d_amp],
        "privato": set(ids(search(p_category=music, p_seller="private")[1])) == {a_gtr, b_gtr},
        "spedizione": set(ids(search(p_category=music, p_ships=True)[1])) == {b_gtr, d_amp},
        "ritiro": set(ids(search(p_category=music, p_pickup=True)[1])) == {a_gtr, d_amp},
    }
    check("N3", "Categoria, sottocategoria, prezzo, condizioni, privato o azienda, spedizione, ritiro",
          all(f.values()), ", ".join(k for k, v in f.items() if not v))

    # N4 · Località, raggio e «Più vicini»: distanza dal punto pubblico, mai il punto salvato
    _, near10 = search(p_category=music, p_radius_km=10)
    _, nearest = search(p_category=music, p_sort="nearest")
    _, anywhere = search(p_category=music, p_lat=41.9, p_lon=12.5, p_radius_km=None)
    _, far = search(p_category=music, p_lat=41.9, p_lon=12.5, p_radius_km=50)
    a_row = by_id(nearest, a_gtr) or {}
    check("N4", "Raggio sul punto pubblico, ordinamento per distanza, distanza arrotondata",
          set(ids(near10)) == {a_gtr, b_gtr} and ids(nearest) == [a_gtr, b_gtr, d_amp]
          and set(ids(anywhere)) == {a_gtr, b_gtr, d_amp} and far == []
          and all(x["distance_band_m"] % 250 == 0 for x in nearest)
          and (a_row.get("lat"), a_row.get("lon")) != MI and "exact_lat" not in a_row
          and abs(a_row.get("lat", 0) - 45.465) < 1e-9,
          f"{ids(near10)}, {ids(nearest)}, {len(anywhere)}, {len(far)}, {a_row.get('lat')}")

    # N5 · Ordinamento per prezzo
    _, up = search(p_category=music, p_sort="price_asc")
    _, down = search(p_category=music, p_sort="price_desc")
    check("N5", "Prezzo crescente e decrescente",
          ids(up) == [a_gtr, d_amp, b_gtr] and ids(down) == [b_gtr, d_amp, a_gtr],
          f"{ids(up)}, {ids(down)}")

    # N6 · Disponibilità allo scambio e conguaglio
    open_sale = ids(search(p_category=music, p_open_to_swap=True)[1])
    cash_swap = ids(search(p_section="swap", p_category=music, p_cash_adjustment=True)[1])
    wrong = [publish(tb, pb, MI_B, p_type="swap", p_category=basses, p_price_cents=None,
                     p_open_to_swap=True)[0],
             publish(tb, pb, MI_B, p_cash_adjustment=True)[0]]
    up_a = rpc("update_market_listing", {
        "p_id": a_gtr, "p_category": guitars, "p_title": "Chitarra acustica Yamaha",
        "p_description": "Corde nuove, custodia inclusa", "p_price_cents": 15000,
        "p_condition": "good", "p_ships": False, "p_pickup": True, "p_attributes": {},
        "p_photos": pa, "p_wanted_in_exchange": None, "p_open_to_swap": False,
        "p_cash_adjustment": False}, ta)
    open_after = ids(search(p_category=music, p_open_to_swap=True)[1])
    check("N6", "«Valuto anche scambi» e «conguaglio»: filtri, regole e modifica",
          open_sale == [a_gtr] and cash_swap == [b_bass] and all(x >= 400 for x in wrong)
          and up_a[0] == 200 and open_after == [],
          f"{open_sale}, {cash_swap}, {wrong}, {up_a[0]}, {open_after}")

    # N7 · Data di pubblicazione
    sql("select set_config('nexus.internal', 'on', false); "
        f"update public.listings set created_at = now() - interval '10 days' where id = '{d_amp}'")
    recent7 = set(ids(search(p_category=music, p_published_within_days=7)[1]))
    recent30 = set(ids(search(p_category=music, p_published_within_days=30)[1]))
    check("N7", "Pubblicati negli ultimi 7 o 30 giorni",
          recent7 == {a_gtr, b_gtr} and recent30 == {a_gtr, b_gtr, d_amp}, f"{recent7}, {recent30}")

    # N8 · Scheda; annunci in revisione e persone bloccate
    sql("select set_config('nexus.internal', 'on', false); "
        f"update public.listings set review_status = 'pending_review' where id = '{b_gtr}'")
    a_hidden = b_gtr not in ids(search(p_category=music)[1])
    a_card = rows(rpc("market_listing", {"p_id": b_gtr}, ta))
    b_card = rows(rpc("market_listing", {"p_id": b_gtr}, tb))
    sql("select set_config('nexus.internal', 'on', false); "
        f"update public.listings set review_status = 'published' where id = '{b_gtr}'")
    card = rows(rpc("market_listing", {"p_id": d_amp, "p_lat": MI[0], "p_lon": MI[1]}, ta))
    rpc("block_user", {"p_user_id": UID_D}, ta)
    blocked_search = d_amp not in ids(search(p_category=music)[1])
    blocked_card = rows(rpc("market_listing", {"p_id": d_amp}, ta))
    d_blocked = a_gtr not in ids(search(td, p_category=music)[1])
    rpc("unblock_user", {"p_user_id": UID_D}, ta)
    back = d_amp in ids(search(p_category=music)[1])
    c = card[0] if card else {}
    check("N8", "Scheda completa; in revisione solo per l'autore; blocchi in entrambe le direzioni",
          a_hidden and a_card == [] and len(b_card) == 1 and b_card[0]["is_mine"]
          and c.get("owner_is_business") is True and c.get("owner_username") == "bottega_d"
          and c.get("price_cents") == 20000 and c.get("item_condition") == "new"
          and c.get("distance_band_m", 1) % 250 == 0
          and blocked_search and blocked_card == [] and d_blocked and back,
          f"{a_hidden}, {len(a_card)}, {len(b_card)}, {blocked_search}, {d_blocked}, {back}")

    # N9 · Mi piace, commenti, segnalazione: come sulla Mappa; non sugli annunci in revisione
    like = rpc("set_listing_reaction", {"p_listing": b_gtr, "p_kind": "like"}, ta)
    social = rpc("listing_social", {"p_listing": b_gtr}, tb)[1] or {}
    com = rpc("add_listing_comment", {"p_listing": b_gtr, "p_body": "È ancora disponibile?"}, ta)
    notes = rows(rpc("my_notifications", {}, tb))
    rep = rpc("report_listing", {"p_listing": d_amp, "p_reason": "truffa"}, ta)
    _, flagged = publish(tb, pb, MI_B, p_title="Pistola softair", p_category=guitars)
    like_flag = rpc("set_listing_reaction", {"p_listing": flagged, "p_kind": "like"}, ta)
    rep_flag = rpc("report_listing", {"p_listing": flagged, "p_reason": "pericolo"}, ta)
    check("N9", "Mi piace, commenti e notifiche sugli annunci pubblicati; in revisione non esistono",
          like[0] in (200, 204) and social.get("likes") == 1 and com[0] == 200
          and any(n.get("listing_id") == b_gtr for n in notes) and rep[0] in (200, 204)
          and flagged is not None and like_flag[0] >= 400 and rep_flag[0] >= 400,
          f"HTTP {like[0]}, {com[0]}, {rep[0]}, {like_flag[0]}, {rep_flag[0]}")

    # N10 · Pagine da 20 (D9), senza doppioni
    sub = amps
    sql("insert into public.listings (owner_id, kind, title, approx_location, market_type, "
        "market_category_id, market_price_cents, item_condition, pickup, photos, expires_at, created_at) "
        f"select '{UID_D}', 'market', 'Cassa ' || g, "
        "st_setsrid(st_makepoint(7.68, 45.07), 4326)::extensions.geography, 'sell', "
        f"'{sub}', 1000 + g, 'good', true, array['{pd[0]}'], now() + interval '20 days', "
        "now() - make_interval(mins => g) from generate_series(1, 25) g")
    TO = (45.07, 7.68)
    s1, p1 = search(p_lat=TO[0], p_lon=TO[1], p_radius_km=5, p_subcategory=sub)
    s2, p2 = search(p_lat=TO[0], p_lon=TO[1], p_radius_km=5, p_subcategory=sub, p_offset=20)
    check("N10", "Prima pagina 20 annunci, seconda 5, nessun doppione",
          s1 == 200 and s2 == 200 and len(p1) == 20 and len(p2) == 5
          and not set(ids(p1)) & set(ids(p2)), f"{len(p1)}, {len(p2)}")


def check_swap_proposals_phase5() -> None:
    """O · Scambia & Vendi, Blocco 3: proposte di scambio (Fase 5). Utenti A, B, D."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    FI = (43.7696, 11.2558)
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A), (tb, UID_D), (td, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    _, cats = rpc("marketplace_categories_list", {}, ta)
    by_slug = {c["slug"]: c for c in (cats if isinstance(cats, list) else [])}
    games = by_slug["giochi-hobby-videogiochi"]["id"] if "giochi-hobby-videogiochi" in by_slug \
        else next(c["id"] for c in cats if c["slug"].startswith("giochi-hobby-"))
    bikes = by_slug["sport-outdoor-ciclismo"]["id"]
    pa, pb = [f"{UID_A}/mercatoA0001.jpg"], [f"{UID_B}/mercatoB0001.jpg"]

    def publish(tok, photos, **kw):
        body = {"p_type": "sell", "p_category": games, "p_title": "Oggetto", "p_description": "",
                "p_price_cents": 5000, "p_condition": "good", "p_ships": False, "p_pickup": True,
                "p_attributes": {}, "p_lat": FI[0], "p_lon": FI[1], "p_location_mode": "approximate",
                "p_photos": photos, "p_no_prohibited_items": True}
        body.update(kw)
        s, res = rpc("publish_market_listing", body, tok)
        return res.get("id") if s == 200 and isinstance(res, dict) else None

    def mine(tok):
        return {x["id"]: x for x in rows(rpc("my_swap_proposals", {}, tok))}

    def notes(tok, kind):
        return [n for n in rows(rpc("my_notifications", {}, tok)) if n.get("kind") == kind]

    console = publish(ta, pa, p_type="swap", p_price_cents=None, p_title="Console PS4 con giochi",
                      p_wanted_in_exchange="una bici", p_cash_adjustment=True)
    lamp = publish(ta, pa, p_title="Lampada da tavolo")
    tent = publish(ta, pa, p_title="Tenda da campeggio", p_open_to_swap=True)
    books = publish(ta, pa, p_type="swap", p_price_cents=None, p_title="Libri fantasy")
    bike = publish(tb, pb, p_category=bikes, p_title="Bici da città")
    scooter = publish(tb, pb, p_category=bikes, p_title="Monopattino elettrico")
    flagged = publish(tb, pb, p_title="Casco moto")
    check("O0", "Annunci di prova per le proposte pubblicati",
          None not in (console, lamp, tent, books, bike, scooter, flagged),
          f"{[console, lamp, tent, books, bike, scooter, flagged]}")
    if None in (console, lamp, tent, books, bike, scooter, flagged):
        return
    sql("select set_config('nexus.internal', 'on', false); "
        f"update public.listings set review_status = 'pending_review' where id = '{flagged}'")

    def propose(tok, target, items, **kw):
        body = {"p_listing": target, "p_items": items, "p_cash_cents": None,
                "p_cash_direction": None, "p_message": ""}
        body.update(kw)
        s, res = rpc("propose_swap", body, tok)
        return s, (res if s == 200 and isinstance(res, str) else None)

    # O1 · Proposta con un annuncio e un conguaglio; la vedono solo le due parti
    s, p1 = propose(tb, console, [bike], p_cash_cents=2000, p_cash_direction="requester_pays",
                    p_message="Ti do la bici e 20 €")
    a_view, b_view = mine(ta).get(p1, {}), mine(tb).get(p1, {})
    check("O1", "Proposta con annuncio e conguaglio: stato «In attesa», notifica all'autore",
          s == 200 and a_view.get("status") == "pending" and not a_view.get("from_me")
          and a_view.get("i_am_owner") and b_view.get("from_me")
          and [i["id"] for i in a_view.get("items", [])] == [bike]
          and a_view.get("cash_cents") == 2000 and a_view.get("other_username") == "utente_b"
          and any(n["listing_id"] == console for n in notes(ta, "swap_proposal")),
          f"HTTP {s}, {a_view.get('status')}")

    # O2 · Regole: annunci propri, scambiabili, conguaglio ammesso, nessun estraneo
    bad = {
        "proprio annuncio": propose(ta, console, [lamp])[0],
        "non scambiabile": propose(tb, lamp, [bike])[0],
        "nessun annuncio": propose(tb, tent, [])[0],
        "annuncio altrui": propose(tb, tent, [lamp])[0],
        "sei annunci": propose(tb, tent, [bike] * 6)[0],
        "conguaglio non accettato": propose(tb, tent, [bike], p_cash_cents=1000,
                                            p_cash_direction="owner_pays")[0],
        "conguaglio sotto 1 €": propose(tb, books, [bike], p_cash_cents=50,
                                        p_cash_direction="owner_pays")[0],
        "direzione inventata": propose(tb, console, [scooter], p_cash_cents=1000,
                                       p_cash_direction="a_metà")[0],
        "seconda in attesa": propose(tb, console, [scooter])[0],
        "annuncio in revisione": propose(tb, books, [flagged])[0],
    }
    d_sees = mine(td)
    d_answer = rpc("respond_swap", {"p_proposal": p1, "p_accept": True}, td)
    d_cancel = rpc("cancel_swap", {"p_proposal": p1}, td)
    d_cand = rpc("swap_offer_candidates", {"p_proposal": p1}, td)
    direct = get(f"/rest/v1/swap_proposals?id=eq.{p1}", tb)
    check("O2", "Regole delle proposte; chi non è parte non vede né tocca nulla",
          all(v >= 400 for v in bad.values()) and p1 not in d_sees and d_answer[0] >= 400
          and d_cancel[0] >= 400 and d_cand[0] >= 400 and denied(direct),
          ", ".join(f"{k}: {v}" for k, v in bad.items() if v < 400)
          + f" | D: {p1 in d_sees}, {d_answer[0]}, {d_cancel[0]}, {d_cand[0]}")

    # O3 · Controproposta: chiude la precedente e la gira all'altra parte
    cand_a = {x["id"] for x in rows(rpc("swap_offer_candidates", {"p_proposal": p1}, ta))}
    cand_b = {x["id"] for x in rows(rpc("swap_offer_candidates", {}, tb))}
    s, p2 = (lambda r: (r[0], r[1] if r[0] == 200 else None))(rpc("counter_swap", {
        "p_proposal": p1, "p_items": [bike, scooter], "p_cash_cents": None,
        "p_cash_direction": None, "p_message": "Mi servono bici e monopattino"}, ta))
    own_answer = rpc("respond_swap", {"p_proposal": p2, "p_accept": True}, ta)
    old_again = rpc("respond_swap", {"p_proposal": p1, "p_accept": True}, ta)
    view = mine(tb)
    check("O3", "Controproposta: la precedente diventa «Controproposta», la nuova va a chi aveva proposto",
          s == 200 and view.get(p1, {}).get("status") == "countered"
          and view.get(p2, {}).get("status") == "pending" and not view.get(p2, {}).get("from_me")
          and view.get(p2, {}).get("parent_id") == p1
          and {i["id"] for i in view.get(p2, {}).get("items", [])} == {bike, scooter}
          and {bike, scooter} <= cand_a and {bike, scooter} <= cand_b and flagged not in cand_b
          and own_answer[0] >= 400 and old_again[0] >= 400
          and any(n.get("proposal_id") == p2 for n in notes(tb, "swap_counter")),
          f"HTTP {s}, {own_answer[0]}, {old_again[0]}")

    # O4 · Accettazione, notifica, nessun ripensamento
    acc = rpc("respond_swap", {"p_proposal": p2, "p_accept": True}, tb)
    again = rpc("respond_swap", {"p_proposal": p2, "p_accept": False}, tb)
    cancel_acc = rpc("cancel_swap", {"p_proposal": p2}, ta)
    check("O4", "Accettata: stato «Accettata», notifica a chi l'aveva fatta; non si cambia più",
          acc[0] == 200 and acc[1] == "accepted" and mine(ta).get(p2, {}).get("status") == "accepted"
          and again[0] >= 400 and cancel_acc[0] >= 400
          and any(n.get("proposal_id") == p2 for n in notes(ta, "swap_accepted")),
          f"HTTP {acc[0]}, {again[0]}, {cancel_acc[0]}")

    # O5 · Annullare: solo chi l'ha fatta e solo in attesa
    _, p3 = propose(tb, tent, [bike])
    a_cancel = rpc("cancel_swap", {"p_proposal": p3}, ta)
    b_cancel = rpc("cancel_swap", {"p_proposal": p3}, tb)
    late = rpc("respond_swap", {"p_proposal": p3, "p_accept": True}, ta)
    check("O5", "Annullata da chi l'ha fatta, prima della risposta; poi non si accetta più",
          p3 is not None and a_cancel[0] >= 400 and b_cancel[0] in (200, 204)
          and mine(ta).get(p3, {}).get("status") == "cancelled" and late[0] >= 400,
          f"{p3}, {a_cancel[0]}, {b_cancel[0]}, {late[0]}")

    # O6 · Rifiutare
    _, p4 = propose(tb, tent, [scooter], p_message="E questo?")
    rej = rpc("respond_swap", {"p_proposal": p4, "p_accept": False}, ta)
    check("O6", "Rifiutata: stato «Rifiutata»",
          p4 is not None and rej[1] == "rejected" and mine(tb).get(p4, {}).get("status") == "rejected",
          f"{p4}, {rej}")

    # O7 · Si accetta solo se gli annunci sono ancora disponibili
    _, p5 = propose(tb, books, [scooter])
    rpc("close_market_listing", {"p_id": scooter}, tb)
    gone = rpc("respond_swap", {"p_proposal": p5, "p_accept": True}, ta)
    item = next(iter(mine(ta).get(p5, {}).get("items", [])), {})
    check("O7", "Annuncio offerto chiuso: la proposta non si può accettare",
          p5 is not None and gone[0] >= 400 and item.get("available") is False
          and mine(ta).get(p5, {}).get("status") == "pending", f"{p5}, {gone[0]}")

    # O8 · Blocchi: niente proposte né elenchi tra persone bloccate
    rpc("block_user", {"p_user_id": UID_B}, ta)
    blocked_new = propose(tb, tent, [bike])[0]
    blocked_list = p5 in mine(ta) or p5 in mine(tb)
    blocked_answer = rpc("respond_swap", {"p_proposal": p5, "p_accept": False}, ta)
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    check("O8", "Con un blocco: nessuna nuova proposta, elenco e risposte nascosti",
          blocked_new >= 400 and not blocked_list and blocked_answer[0] >= 400,
          f"{blocked_new}, {blocked_list}, {blocked_answer[0]}")

    # O9 · Anti-spam (D9): 30 proposte al giorno
    sql("insert into public.swap_proposals (target_listing_id, owner_id, requester_id, from_id, "
        "to_id, status) "
        f"select '{lamp}', '{UID_A}', '{UID_D}', '{UID_D}', '{UID_A}', 'rejected' "
        "from generate_series(1, 30)")
    d_items = [x["id"] for x in rows(rpc("swap_offer_candidates", {}, td))][:1]
    s31 = propose(td, console, d_items)[0]
    check("O9", "La trentunesima proposta della giornata viene rifiutata",
          len(d_items) == 1 and s31 >= 400, f"{len(d_items)}, HTTP {s31}")


def check_deals_feedback_phase5() -> None:
    """P · Scambia & Vendi, Blocco 4: conclusione e feedback (Fase 5). Utenti A, B, D."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A), (tb, UID_D), (td, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    mine_a = {x["title"]: x for x in rows(rpc("my_market_listings", {}, ta))}
    lamp = mine_a.get("Lampada da tavolo", {}).get("id")
    tent = mine_a.get("Tenda da campeggio", {}).get("id")
    console = mine_a.get("Console PS4 con giochi", {}).get("id")
    accepted = [p for p in rows(rpc("my_swap_proposals", {}, ta))
                if p.get("status") == "accepted" and p.get("target_id") == console]
    p2 = accepted[0]["id"] if accepted else None
    bike = next((i["id"] for i in (accepted[0]["items"] if accepted else [])
                 if i["title"] == "Bici da città"), None)
    check("P0", "Annunci e proposta accettata del Blocco 3 disponibili",
          None not in (lamp, tent, console, p2, bike), f"{[lamp, tent, console, p2, bike]}")
    if None in (lamp, tent, console, p2, bike):
        return
    # Le 30 proposte finte di O9 (D su «Lampada») non devono fare di D un interlocutore.
    sql(f"delete from public.swap_proposals where requester_id = '{UID_D}' and target_listing_id = '{lamp}'")
    rpc("add_listing_comment", {"p_listing": lamp, "p_body": "Mi interessa, è ancora disponibile?"}, tb)

    def deals(tok):
        return {d["id"]: d for d in rows(rpc("my_deals", {}, tok))}

    def kinds(tok, kind):
        return [n for n in rows(rpc("my_notifications", {}, tok)) if n.get("kind") == kind]

    def status_of(listing):
        return sql(f"select status from public.listings where id = '{listing}'")

    # P1 · L'autore indica la persona tra chi ha commentato o proposto
    cand = [c["id"] for c in rows(rpc("deal_candidates", {"p_listing": lamp}, ta))]
    b_cand = rpc("deal_candidates", {"p_listing": lamp}, tb)
    stranger = rpc("mark_listing_concluded", {"p_listing": lamp, "p_other": UID_D}, ta)
    on_swap = rpc("mark_listing_concluded", {"p_listing": console, "p_other": UID_B}, ta)
    not_mine = rpc("mark_listing_concluded", {"p_listing": lamp, "p_other": UID_B}, tb)
    s, d1 = rpc("mark_listing_concluded", {"p_listing": lamp, "p_other": UID_B}, ta)
    twice = rpc("mark_listing_concluded", {"p_listing": lamp, "p_other": UID_B}, ta)
    check("P1", "Conclusione indicata dall'autore solo verso chi ha commentato o proposto",
          cand == [UID_B] and b_cand[0] >= 400 and stranger[0] >= 400 and on_swap[0] >= 400
          and not_mine[0] >= 400 and s == 200 and twice[0] >= 400
          and any(n.get("deal_id") == d1 for n in kinds(tb, "deal_confirm")),
          f"{cand == [UID_B]}, {b_cand[0]}, {stranger[0]}, {on_swap[0]}, {not_mine[0]}, {s}, {twice[0]}")
    if s != 200 or not isinstance(d1, str):
        return

    # P2 · Feedback solo dopo la conclusione; la conferma dell'altra parte chiude l'annuncio
    early = rpc("leave_feedback", {"p_deal": d1, "p_stars": 5, "p_comment": ""}, ta)
    owner_answer = rpc("answer_deal", {"p_deal": d1, "p_confirm": True}, ta)
    ok = rpc("answer_deal", {"p_deal": d1, "p_confirm": True}, tb)
    again = rpc("answer_deal", {"p_deal": d1, "p_confirm": False}, tb)
    d = deals(ta).get(d1, {})
    check("P2", "Prima della conferma nessun feedback; confermata: conclusa e annuncio chiuso",
          early[0] >= 400 and owner_answer[0] >= 400 and ok[1] == "completed" and again[0] >= 400
          and d.get("completed") is True and status_of(lamp) == "completed"
          and any(n.get("deal_id") == d1 for n in kinds(ta, "deal_completed")),
          f"{early[0]}, {owner_answer[0]}, {ok}, {again[0]}, {d.get('completed')}, {status_of(lamp)}")

    # P3 · Un feedback a testa, 1-5 stelle, non modificabile; media e elenco
    f_a = rpc("leave_feedback", {"p_deal": d1, "p_stars": 5, "p_comment": "Puntuale e gentile"}, ta)
    f_a2 = rpc("leave_feedback", {"p_deal": d1, "p_stars": 1, "p_comment": "ripensamento"}, ta)
    f_bad = rpc("leave_feedback", {"p_deal": d1, "p_stars": 6, "p_comment": ""}, tb)
    f_d = rpc("leave_feedback", {"p_deal": d1, "p_stars": 1, "p_comment": ""}, td)
    f_b = rpc("leave_feedback", {"p_deal": d1, "p_stars": 4, "p_comment": ""}, tb)
    sum_b = (rows(rpc("feedback_summary", {"p_user": UID_B}, td)) or [{}])[0]
    sum_a = (rows(rpc("feedback_summary", {"p_user": UID_A}, td)) or [{}])[0]
    lst = rows(rpc("feedback_list", {"p_user": UID_B}, td))
    upd = request("PATCH", f"/rest/v1/market_feedback?deal_id=eq.{d1}", jwt=ta, body={"stars": 1},
                  prefer="return=representation")
    check("P3", "Feedback a testa dopo la conclusione; media e elenco; nessuna modifica",
          f_a[0] == 200 and f_a2[0] >= 400 and f_bad[0] >= 400 and f_d[0] >= 400 and f_b[0] == 200
          and float(sum_b.get("average") or 0) == 5.0 and sum_b.get("count") == 1
          and float(sum_a.get("average") or 0) == 4.0 and sum_b.get("completed_deals") == 1
          and len(lst) == 1 and lst[0].get("author_username") == "utente_a"
          and lst[0].get("comment") == "Puntuale e gentile" and denied(upd)
          and any(n.get("deal_id") == d1 for n in kinds(tb, "feedback_received")),
          f"{f_a[0]}, {f_a2[0]}, {f_bad[0]}, {f_d[0]}, {f_b[0]}, {sum_b}, {sum_a}, {len(lst)}")

    # P4 · «Non è avvenuto» e annullamento
    _, d2 = rpc("mark_listing_concluded", {"p_listing": tent, "p_other": UID_B}, ta)
    d2 = d2 if isinstance(d2, str) else None
    no = rpc("answer_deal", {"p_deal": d2, "p_confirm": False}, tb)
    s3, d3 = rpc("mark_listing_concluded", {"p_listing": tent, "p_other": UID_B}, ta)
    d3 = d3 if isinstance(d3, str) else None
    cancel_b = rpc("cancel_deal", {"p_deal": d3}, tb)
    cancel_a = rpc("cancel_deal", {"p_deal": d3}, ta)
    late = rpc("answer_deal", {"p_deal": d3, "p_confirm": True}, tb)
    no_fb = rpc("leave_feedback", {"p_deal": d2, "p_stars": 3, "p_comment": ""}, ta)
    check("P4", "«Non è avvenuto» riapre; l'autore annulla finché l'altro non risponde",
          no[1] == "declined" and s3 == 200 and cancel_b[0] >= 400 and cancel_a[0] in (200, 204)
          and late[0] >= 400 and no_fb[0] >= 400 and status_of(tent) == "active",
          f"{no}, {s3}, {cancel_b[0]}, {cancel_a[0]}, {late[0]}, {no_fb[0]}, {status_of(tent)}")

    # P5 · Scambio: conclusione confermata da entrambi
    w = rpc("confirm_swap_concluded", {"p_proposal": p2}, ta)
    w2 = rpc("confirm_swap_concluded", {"p_proposal": p2}, ta)
    wd = rpc("confirm_swap_concluded", {"p_proposal": p2}, td)
    c = rpc("confirm_swap_concluded", {"p_proposal": p2}, tb)
    prop = next((x for x in rows(rpc("my_swap_proposals", {}, tb)) if x["id"] == p2), {})
    swap_deal = next((x for x in deals(tb).values() if x.get("proposal_id") == p2), {})
    fb_swap = rpc("leave_feedback", {"p_deal": swap_deal.get("id"), "p_stars": 5, "p_comment": ""}, tb)
    check("P5", "Scambio: «Completata» solo con la conferma di entrambi; annunci chiusi",
          w[1] == "waiting" and w2[0] >= 400 and wd[0] >= 400 and c[1] == "completed"
          and prop.get("status") == "completed" and status_of(console) == "completed"
          and status_of(bike) == "completed" and fb_swap[0] == 200
          and any(n.get("proposal_id") == p2 for n in kinds(tb, "deal_confirm")),
          f"{w}, {w2[0]}, {wd[0]}, {c}, {prop.get('status')}, {status_of(console)}, {fb_swap[0]}")

    # P6 · Blocchi: i feedback e le conclusioni tra persone bloccate non si vedono
    rpc("block_user", {"p_user_id": UID_B}, ta)
    hidden_sum = (rows(rpc("feedback_summary", {"p_user": UID_B}, ta)) or [{}])[0]
    hidden_list = rows(rpc("feedback_list", {"p_user": UID_B}, ta))
    hidden_deals = d1 in deals(ta)
    d_sees = (rows(rpc("feedback_summary", {"p_user": UID_B}, td)) or [{}])[0]
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    direct = get("/rest/v1/market_deals?select=id", ta)
    check("P6", "Con un blocco feedback e conclusioni spariscono; tabelle mai accessibili direttamente",
          (hidden_sum.get("count") or 0) == 0 and hidden_list == [] and not hidden_deals
          and d_sees.get("count") == 1 and denied(direct),
          f"{hidden_sum}, {len(hidden_list)}, {hidden_deals}, {d_sees}, {direct[0]}")


def check_comments_categories_phase5() -> None:
    """Q · Commenti completi (Mappa e Scambia & Vendi) e categorie (Fase 5, Blocco 5). A, B, D."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A), (tb, UID_D), (td, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    sql(f"delete from public.admin_users where user_id = '{UID_D}'")
    mine_a = {x["title"]: x for x in rows(rpc("my_market_listings", {}, ta))}
    books = mine_a.get("Libri fantasy", {}).get("id")
    soon = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3 * 3600))
    s_map, coffee = rpc("publish_map_listing", {
        "p_title": "Chi viene a prendere un caffè?", "p_details": "", "p_lat": 45.07,
        "p_lon": 7.68, "p_location_mode": "approximate", "p_expires_at": soon, "p_photos": []}, ta)
    coffee = coffee if isinstance(coffee, str) else None
    check("Q0", "Annuncio di Scambia & Vendi e post della Mappa di prova",
          books is not None and coffee is not None, f"{books}, HTTP {s_map}")
    if books is None or coffee is None:
        return

    def comments(tok, listing):
        return {c["id"]: c for c in rows(rpc("listing_comments_list", {"p_listing": listing}, tok))}

    def comment(tok, listing, body, parent=None):
        s, cid = rpc("add_listing_comment", {"p_listing": listing, "p_body": body, "p_parent": parent}, tok)
        return cid if s == 200 and isinstance(cid, str) else None

    # Q1 · Modifica del proprio commento con «modificato»
    cb = comment(tb, books, "Li scambieresti con dei gialli?")
    ed = rpc("edit_my_comment", {"p_comment": cb, "p_body": "Li scambieresti con tre gialli?"}, tb)
    by_a = rpc("edit_my_comment", {"p_comment": cb, "p_body": "Modificato da altri"}, ta)
    by_d = rpc("edit_my_comment", {"p_comment": cb, "p_body": "Modificato da altri"}, td)
    empty = rpc("edit_my_comment", {"p_comment": cb, "p_body": "   "}, tb)
    seen = comments(td, books).get(cb, {})
    check("Q1", "Solo chi l'ha scritto modifica il commento; gli altri vedono «modificato»",
          cb is not None and ed[0] in (200, 204) and by_a[0] >= 400 and by_d[0] >= 400
          and empty[0] >= 400 and seen.get("body") == "Li scambieresti con tre gialli?"
          and seen.get("edited") is True and seen.get("can_hide") is False,
          f"{cb}, {ed[0]}, {by_a[0]}, {by_d[0]}, {empty[0]}, {seen.get('edited')}")

    # Q2 · L'autore dell'annuncio nasconde: autore invariato, testo solo a chi può
    h_d = rpc("set_comment_hidden", {"p_comment": cb, "p_hidden": True}, td)
    h_b = rpc("set_comment_hidden", {"p_comment": cb, "p_hidden": True}, tb)
    h_a = rpc("set_comment_hidden", {"p_comment": cb, "p_hidden": True}, ta)
    d_view, b_view, a_view = comments(td, books).get(cb, {}), comments(tb, books).get(cb, {}), \
        comments(ta, books).get(cb, {})
    reply = comment(td, books, "Rispondo al nascosto", parent=cb)
    like = rpc("set_comment_like", {"p_comment": cb, "p_like": True}, td)
    edit_hidden = rpc("edit_my_comment", {"p_comment": cb, "p_body": "Ritento"}, tb)
    rpc("set_comment_hidden", {"p_comment": cb, "p_hidden": False}, ta)
    back = comments(td, books).get(cb, {})
    check("Q2", "Nascosto dall'autore dell'annuncio: niente testo per gli altri, niente risposte né Mi piace",
          h_d[0] >= 400 and h_b[0] >= 400 and h_a[0] in (200, 204)
          and d_view.get("hidden") is True and d_view.get("body") is None
          and d_view.get("author_username") == "utente_b"
          and b_view.get("body") == "Li scambieresti con tre gialli?"
          and a_view.get("body") is not None and a_view.get("can_hide") is True
          and reply is None and like[0] >= 400 and edit_hidden[0] >= 400
          and back.get("hidden") is False and back.get("body") is not None,
          f"{h_d[0]}, {h_b[0]}, {h_a[0]}, {d_view.get('hidden')}, {d_view.get('body')}, {reply}, {like[0]}")

    # Q3 · Anche la moderazione nasconde
    sql(f"insert into public.admin_users (user_id) values ('{UID_D}') on conflict do nothing")
    adm = rpc("set_comment_hidden", {"p_comment": cb, "p_hidden": True}, td)
    adm_view = comments(td, books).get(cb, {})
    sql(f"delete from public.admin_users where user_id = '{UID_D}'")
    rpc("set_comment_hidden", {"p_comment": cb, "p_hidden": False}, ta)
    check("Q3", "Un amministratore nasconde e vede il testo",
          adm[0] in (200, 204) and adm_view.get("hidden") is True and adm_view.get("body") is not None
          and adm_view.get("can_hide") is True, f"{adm[0]}, {adm_view.get('hidden')}")

    # Q4 · Segnalazione di un commento
    r_ok = rpc("report_comment", {"p_comment": cb, "p_reason": "spam", "p_details": "Ripetuto"}, td)
    r_twice = rpc("report_comment", {"p_comment": cb, "p_reason": "spam"}, td)
    r_own = rpc("report_comment", {"p_comment": cb, "p_reason": "spam"}, tb)
    r_bad = rpc("report_comment", {"p_comment": cb, "p_reason": "noia"}, ta)
    n_rep = sql(f"select count(*) from public.reports where target = 'comment' and target_id = '{cb}'")
    check("Q4", "Commento segnalato una volta; non il proprio; motivo controllato",
          r_ok[0] in (200, 204) and r_twice[0] in (200, 204) and r_own[0] >= 400 and r_bad[0] >= 400
          and n_rep == "1", f"{r_ok[0]}, {r_own[0]}, {r_bad[0]}, {n_rep}")

    # Q5 · Anti-spam (D9): 10 al minuto, 100 al giorno
    sql("select set_config('nexus.internal', 'on', false); "
        "insert into public.listing_comments (listing_id, author_id, body) "
        f"select '{books}', '{UID_D}', 'Spam ' || g from generate_series(1, 10) g")
    minute = comment(td, books, "Ancora uno")
    sql("select set_config('nexus.internal', 'on', false); "
        "update public.listing_comments set created_at = now() - interval '2 minutes' "
        f"where author_id = '{UID_D}'")
    after = comment(td, books, "Ora si può")
    sql("select set_config('nexus.internal', 'on', false); "
        "insert into public.listing_comments (listing_id, author_id, body, created_at) "
        f"select '{books}', '{UID_D}', 'Vecchio ' || g, now() - interval '1 hour' "
        "from generate_series(1, 100) g")
    day = comment(td, books, "Troppi oggi")
    sql(f"delete from public.listing_comments where author_id = '{UID_D}' "
        "and (body like 'Spam %' or body like 'Vecchio %')")
    check("Q5", "L'undicesimo commento in un minuto e il centunesimo del giorno vengono rifiutati",
          minute is None and after is not None and day is None, f"{minute}, {after}, {day}")

    # Q6 · Le stesse regole sulla Mappa
    cm = comment(tb, coffee, "Io ci sono alle 17")
    ed_m = rpc("edit_my_comment", {"p_comment": cm, "p_body": "Io ci sono alle 18"}, tb)
    hide_m = rpc("set_comment_hidden", {"p_comment": cm, "p_hidden": True}, ta)
    m_view = comments(td, coffee).get(cm, {})
    rep_m = rpc("report_comment", {"p_comment": cm, "p_reason": "altro"}, td)
    check("Q6", "Sulla Mappa: modifica, nascondi e segnala come in Scambia & Vendi",
          cm is not None and ed_m[0] in (200, 204) and hide_m[0] in (200, 204)
          and m_view.get("hidden") is True and m_view.get("body") is None and m_view.get("edited") is True
          and rep_m[0] in (200, 204), f"{cm}, {ed_m[0]}, {hide_m[0]}, {m_view}, {rep_m[0]}")

    # Q7 · Categorie: solo amministratori; slug dal nome e immutabile; archiviate restano integre
    no_admin = [rpc("admin_create_category", {"p_name": "Prova"}, ta)[0],
                rpc("admin_categories", {}, ta)[0],
                rpc("admin_archive_category", {"p_id": "ac787308-86bb-591f-b63c-305f6932da26"}, ta)[0]]
    sql(f"insert into public.admin_users (user_id) values ('{UID_D}') on conflict do nothing")
    elec = "ac787308-86bb-591f-b63c-305f6932da26"
    _, main = rpc("admin_create_category", {"p_name": "Articoli per la casa d'epoca"}, td)
    _, sub = rpc("admin_create_category", {"p_name": "Droni e accessori", "p_parent": elec}, td)
    _, dup = rpc("admin_create_category", {"p_name": "Droni & accessori", "p_parent": elec}, td)
    main = main if isinstance(main, dict) else {}
    sub = sub if isinstance(sub, dict) else {}
    dup = dup if isinstance(dup, dict) else {}
    deep = rpc("admin_create_category", {"p_name": "Troppo in fondo", "p_parent": sub.get("id")}, td)
    ren = rpc("admin_update_category", {"p_id": sub.get("id"), "p_name": "Droni",
                                        "p_description": "Droni e ricambi", "p_sort_order": 5}, td)
    slug_after = sql(f"select slug from public.marketplace_categories where id = '{sub.get('id')}'")
    listed = {c["id"]: c for c in (rpc("marketplace_categories_list", {}, ta)[1] or [])}
    off = rpc("admin_set_category_active", {"p_id": sub.get("id"), "p_active": False}, td)
    listed_off = {c["id"] for c in (rpc("marketplace_categories_list", {}, ta)[1] or [])}
    pub_off = rpc("publish_market_listing", {
        "p_type": "sell", "p_category": sub.get("id"), "p_title": "Drone", "p_description": "",
        "p_price_cents": 10000, "p_condition": "good", "p_ships": False, "p_pickup": True,
        "p_attributes": {}, "p_lat": 45.07, "p_lon": 7.68, "p_location_mode": "approximate",
        "p_photos": [f"{UID_A}/mercatoA0001.jpg"], "p_no_prohibited_items": True}, ta)
    music = sql("select id from public.marketplace_categories where slug = 'musica-strumenti'")
    arch = rpc("admin_archive_category", {"p_id": music}, td)
    gone = {c["slug"] for c in (rpc("marketplace_categories_list", {}, ta)[1] or [])}
    adm_rows = {c["slug"]: c for c in rows(rpc("admin_categories", {}, td))}
    still = sql("select count(*) from public.listings where kind = 'market' and status = 'active' "
                "and market_category_id in (select id from public.marketplace_categories "
                "where slug like 'musica-strumenti-%')")
    sql("update public.marketplace_categories set archived_at = null, is_active = true "
        "where slug like 'musica-strumenti%'")
    sql(f"delete from public.admin_users where user_id = '{UID_D}'")
    check("Q7", "Categorie gestite solo dagli amministratori, slug stabile, archivio senza perdere annunci",
          all(x >= 400 for x in no_admin)
          and main.get("slug") == "articoli-casa-epoca"
          and sub.get("slug") == "elettronica-droni-accessori"
          and dup.get("slug") == "elettronica-droni-accessori-2"
          and deep[0] >= 400 and ren[0] in (200, 204) and slug_after == "elettronica-droni-accessori"
          and listed.get(sub.get("id"), {}).get("name") == "Droni"
          and off[0] in (200, 204) and sub.get("id") not in listed_off and pub_off[0] >= 400
          and arch[0] in (200, 204) and "musica-strumenti" not in gone
          and "musica-strumenti-chitarre" not in gone
          and adm_rows.get("musica-strumenti-chitarre", {}).get("archived_at") is not None
          and int(still or 0) > 0,
          f"{no_admin}, {main}, {sub}, {dup}, {deep[0]}, {ren[0]}, {slug_after}, {off[0]}, "
          f"{pub_off[0]}, {arch[0]}, {still}")


def check_claimless_access() -> None:
    """Z · Accesso senza il «timbro» `role: authenticated` (migrazione 0017)."""
    ta = token(UID_A)
    with_role = token(UID_A, role="authenticated")
    supa = token(UID_A, role="authenticated", extra={"iss": "https://example.supabase.co/auth/v1"})
    expired = token(UID_A, exp_offset=-60)
    # Z1 · Senza un utente Firebase valido il server non risponde a nulla, tranne «ping»
    ping = rpc("ping", {})
    anon_uid = rpc("current_uid", {})
    anon_profiles = get("/rest/v1/profiles?select=id")
    anon_cats = rpc("marketplace_categories_list", {})
    anon_search = rpc("market_search", {"p_section": "sale"})
    old_uid = rpc("current_uid", {}, expired)
    supa_uid = rpc("current_uid", {}, supa)
    check("Z1", "Senza accesso Firebase valido tutto è chiuso (solo «ping» risponde)",
          ping == (200, True) and anon_uid[0] >= 400 and anon_profiles[0] >= 400
          and anon_cats[0] >= 400 and anon_search[0] >= 400 and old_uid[0] >= 400
          and supa_uid[0] >= 400,
          f"{ping}, {anon_uid[0]}, {anon_profiles[0]}, {anon_cats[0]}, {anon_search[0]}, "
          f"{old_uid[0]}, {supa_uid[0]}")
    # Z2 · Il token Firebase senza «role» funziona come quello con il timbro
    a1, a2 = rpc("current_uid", {}, ta), rpc("current_uid", {}, with_role)
    me1, me2 = rows(get("/rest/v1/profile_private?select=id", ta)), \
        rows(get("/rest/v1/profile_private?select=id", with_role))
    check("Z2", "Senza «role» l'utente è riconosciuto come con il timbro",
          a1 == (200, UID_A) and a2 == (200, UID_A)
          and [r["id"] for r in me1] == [UID_A] and me1 == me2, f"{a1}, {a2}, {me1}, {me2}")
    # Z3 · Foto: senza accesso nessun caricamento; con il token senza «role» sì
    up = storage("POST", f"listing-photos/{UID_A}/senza-accesso.jpg", None, data=JPEG)
    other = storage("POST", f"listing-photos/{UID_B}/non-mia.jpg", ta, data=JPEG)
    mine = storage("POST", f"listing-photos/{UID_A}/senza-timbro.jpg", ta, data=JPEG)
    check("Z3", "Foto: senza accesso nessun caricamento; ognuno solo nella propria cartella",
          up >= 400 and other >= 400 and mine == 200, f"{up}, {other}, {mine}")
    # Z4 · Gli stessi permessi per anon e authenticated, anche nelle migrazioni future
    diff = sql("select coalesce(string_agg(kind || ' ' || object, '; '), '') "
               "from private.anon_authenticated_differences()")
    check("Z4", "Permessi identici per richieste con e senza timbro", diff == "", diff[:300])


def check_rubrica_server() -> None:
    """Y · Rubrica su Supabase (migrazione 0018): chiavi e limiti solo per la funzione."""
    ta = token(UID_A)
    service = token(None, role="service_role")
    # Y1 · Le chiavi nascono nel database, valide, e le legge solo il ruolo di servizio
    n = int("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)
    oprf = sql("select value from private.settings where key = 'oprf_key'")
    by_user = rpc("rubrica_server_config", {}, ta)
    by_anon = rpc("rubrica_server_config", {})
    by_service = rpc("rubrica_server_config", {}, service)
    row = (by_service[1] or [{}])[0] if isinstance(by_service[1], list) else {}
    check("Y1", "Chiavi della rubrica generate nel database e leggibili solo dalla funzione",
          len(oprf) == 64 and 0 < int(oprf, 16) < n and by_user[0] >= 400 and by_anon[0] >= 400
          and by_service[0] == 200 and row.get("oprf_key") == oprf
          and len(row.get("attest_key") or "") >= 32 and row.get("firebase_project_id") == PROJECT,
          f"{len(oprf)}, {by_user[0]}, {by_anon[0]}, {by_service[0]}")
    # Y2 · Limiti giornalieri contati nel database, solo dalla funzione
    user_try = rpc("rubrica_consume_limit", {"p_uid": UID_A, "p_kind": "sincronizzazioni", "p_max": 3}, ta)
    got = [rpc("rubrica_consume_limit", {"p_uid": UID_E, "p_kind": "sincronizzazioni", "p_max": 3},
               service)[1] for _ in range(4)]
    other_kind = rpc("rubrica_consume_limit", {"p_uid": UID_E, "p_kind": "mio_numero", "p_max": 5}, service)[1]
    bad = rpc("rubrica_consume_limit", {"p_uid": "uid con spazi", "p_kind": "mio_numero", "p_max": 5}, service)
    check("Y2", "Tre sincronizzazioni al giorno, contate a parte dal proprio numero",
          user_try[0] >= 400 and got == [True, True, True, False] and other_kind is True and bad[0] >= 400,
          f"{user_try[0]}, {got}, {other_kind}, {bad[0]}")


def check_chat_phase4() -> None:
    """R · Chat a due cifrata (Fase 4, Blocco 1). Utenti A, B, D; il server vede solo base64."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A), (tb, UID_D), (td, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    # B ha A in rubrica (A gli scrive direttamente); A non ha D (D scrive come richiesta).
    sql("insert into private.contact_links (owner_id, contact_id, expires_at) "
        f"values ('{UID_B}', '{UID_A}', now() + interval '30 days') "
        "on conflict (owner_id, contact_id) do update set expires_at = excluded.expires_at; "
        f"delete from private.contact_links where owner_id = '{UID_A}' and contact_id = '{UID_D}';")

    def key(n: int) -> str:
        return base64.b64encode(bytes([n]) * 32).decode()

    def blob(n: int, size: int = 200) -> str:
        return base64.b64encode(bytes([n % 256]) * size).decode()

    def count(tok) -> int:
        s, body = rpc("chat_key_package_count", {}, tok)
        return body if s == 200 and isinstance(body, int) else -1

    def convs(tok) -> dict:
        return {c["id"]: c for c in rows(rpc("chat_conversations", {}, tok))}

    def sync(tok, after=0) -> list:
        return rows(rpc("chat_sync", {"p_after": after, "p_limit": 200}, tok))

    # R1 · Identità e pacchetti chiave; tabelle mai leggibili direttamente
    reg_a = rpc("chat_register_identity", {"p_signature_key": key(1), "p_packages": [blob(11)] * 3}, ta)
    reg_b = rpc("chat_register_identity", {"p_signature_key": key(2), "p_packages": [blob(21), blob(22), blob(23)]}, tb)
    reg_d = rpc("chat_register_identity", {"p_signature_key": key(4), "p_packages": [blob(41)]}, td)
    bad_key = rpc("chat_register_identity", {"p_signature_key": "non valida", "p_packages": []}, ta)
    bad_kp = rpc("chat_add_key_packages", {"p_packages": ["<script>"]}, ta)
    anon = rpc("chat_conversations", {})
    tables = [get(f"/rest/v1/{t}?select=*", ta) for t in
              ("chat_identities", "chat_key_packages", "chat_conversations", "chat_members", "chat_messages")]
    check("R1", "Chiave della chat e pacchetti registrati; tabelle della chat mai leggibili dall'app",
          all(r[0] in (200, 204) for r in (reg_a, reg_b, reg_d)) and count(ta) == 3 and count(tb) == 3
          and bad_key[0] >= 400 and bad_kp[0] >= 400 and anon[0] >= 400
          and all(denied(t) for t in tables),
          f"{reg_a[0]}, {reg_b[0]}, {reg_d[0]}, {count(ta)}, {bad_key[0]}, {bad_kp[0]}, {anon[0]}, "
          f"{[t[0] for t in tables]}")

    # R2 · Aprire una chat: una sola per coppia, mai con sé stessi o con chi non esiste
    s1, conv = rpc("chat_open_direct", {"p_user": UID_B}, ta)
    s2, again = rpc("chat_open_direct", {"p_user": UID_A}, tb)
    self_open = rpc("chat_open_direct", {"p_user": UID_A}, ta)
    ghost = rpc("chat_open_direct", {"p_user": UID_E}, ta)
    a_view = convs(ta).get(conv, {})
    check("R2", "Chat A↔B unica, attiva per entrambi (B ha A in rubrica), senza numero di telefono",
          s1 == 200 and s2 == 200 and conv == again and self_open[0] >= 400 and ghost[0] >= 400
          and a_view.get("status") == "active" and convs(tb).get(conv, {}).get("status") == "active"
          and a_view.get("peer_username") == "utente_b" and a_view.get("generation") == 0
          and not any("phone" in k for k in a_view),
          f"{s1}, {s2}, {self_open[0]}, {ghost[0]}, {a_view.get('status')}")

    # R3 · Pacchetto chiave dell'altra persona: consumato, e mai per chi non è nella chat
    s, claimed = rpc("chat_claim_key_package", {"p_conversation": conv}, ta)
    got = claimed[0] if s == 200 and isinstance(claimed, list) and claimed else {}
    outsider = rpc("chat_claim_key_package", {"p_conversation": conv}, td)
    check("R3", "A riceve un pacchetto di B (poi cancellato); D, estraneo, no",
          s == 200 and got.get("package") == blob(21) and got.get("signature_key") == key(2)
          and count(tb) == 2 and outsider[0] >= 400,
          f"{s}, {count(tb)}, {outsider[0]}")

    # R4 · Apertura cifrata con controllo della generazione (niente doppie aperture)
    st_a = rpc("chat_start", {"p_conversation": conv, "p_generation": 0,
                              "p_group_id": blob(5, 16), "p_welcome": blob(6, 300)}, ta)
    st_b = rpc("chat_start", {"p_conversation": conv, "p_generation": 0,
                              "p_group_id": blob(7, 16), "p_welcome": blob(8, 300)}, tb)
    st_d = rpc("chat_start", {"p_conversation": conv, "p_generation": 1,
                              "p_group_id": blob(9, 16), "p_welcome": blob(9, 300)}, td)
    view = convs(tb).get(conv, {})
    check("R4", "Prima apertura: generazione 1; la seconda sulla stessa generazione è rifiutata",
          st_a == (200, 1) and st_b[0] >= 400 and st_d[0] >= 400 and view.get("generation") == 1
          and view.get("mls_group_id") == blob(5, 16) and view.get("peer_joined_key") == key(1)
          and view.get("my_joined_key") == key(2),
          f"{st_a}, {st_b[0]}, {st_d[0]}, {view.get('generation')}")

    # R5 · Messaggi cifrati: li riceve solo l'altra persona della chat
    sent = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": blob(30, 120)}, ta)
    msg_id = sent[1][0]["id"] if sent[0] == 200 and isinstance(sent[1], list) and sent[1] else None
    old_gen = rpc("chat_send", {"p_conversation": conv, "p_generation": 0, "p_payload": blob(31)}, ta)
    not_b64 = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": "ciao in chiaro!"}, ta)
    by_d = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": blob(32)}, td)
    b_got = [(m["kind"], m["sender_id"]) for m in sync(tb) if m["conversation_id"] == conv]
    a_got = [m for m in sync(ta) if m["conversation_id"] == conv]
    d_got = [m for m in sync(td) if m["conversation_id"] == conv]
    direct = get("/rest/v1/chat_messages?select=id,payload", td)
    check("R5", "B riceve invito e messaggio di A; A non riceve i propri; D nulla; solo base64",
          msg_id is not None and old_gen[0] >= 400 and not_b64[0] >= 400 and by_d[0] >= 400
          and denied(direct)
          and b_got == [("welcome", UID_A), ("app", UID_A)] and a_got == [] and d_got == [],
          f"{sent[0]}, {old_gen[0]}, {not_b64[0]}, {by_d[0]}, {b_got}, {len(a_got)}, {len(d_got)}")

    # R6 · Spunte: consegnato e letto; i messaggi ricevuti spariscono dal server
    before = convs(ta).get(conv, {})
    unread_b = convs(tb).get(conv, {}).get("unread")
    rpc("chat_mark", {"p_conversation": conv, "p_delivered": msg_id, "p_read": 0}, tb)
    mid = convs(ta).get(conv, {})
    rpc("chat_mark", {"p_conversation": conv, "p_delivered": msg_id, "p_read": msg_id + 1000}, tb)
    after = convs(ta).get(conv, {})
    left = sql(f"select count(*) from public.chat_messages where conversation_id = '{conv}';")
    check("R6", "Spunte inviato → consegnato → letto; dopo la consegna il server non conserva nulla",
          before.get("peer_delivered_upto") == 0 and unread_b == 1
          and mid.get("peer_delivered_upto") == msg_id and mid.get("peer_read_upto") == 0
          and after.get("peer_read_upto") == msg_id and left == "0"
          and convs(tb).get(conv, {}).get("unread") == 0,
          f"{before.get('peer_delivered_upto')}, {unread_b}, {mid.get('peer_delivered_upto')}, "
          f"{after.get('peer_read_upto')}, {left}")

    # R7 · Richieste dagli sconosciuti: niente spunte finché non accetti, al massimo 10 messaggi
    s, req = rpc("chat_open_direct", {"p_user": UID_A}, td)
    rpc("chat_claim_key_package", {"p_conversation": req}, td)
    rpc("chat_start", {"p_conversation": req, "p_generation": 0,
                       "p_group_id": blob(50, 16), "p_welcome": blob(51, 300)}, td)
    statuses = [rpc("chat_send", {"p_conversation": req, "p_generation": 1,
                                  "p_payload": blob(60 + i)}, td)[0] for i in range(11)]
    a_req = convs(ta).get(req, {})
    last = max((m["id"] for m in sync(ta) if m["conversation_id"] == req), default=0)
    rpc("chat_mark", {"p_conversation": req, "p_delivered": last, "p_read": last}, ta)
    d_view = convs(td).get(req, {})
    check("R7", "Richiesta di D: per A è «richiesta»; D non vede consegnato/letto; stop all'11° messaggio",
          s == 200 and a_req.get("status") == "request" and statuses[:10] == [200] * 10
          and statuses[10] >= 400 and d_view.get("peer_delivered_upto") == 0
          and d_view.get("peer_read_upto") == 0,
          f"{s}, {a_req.get('status')}, {statuses}, {d_view.get('peer_read_upto')}")

    # R8 · Rifiutare una richiesta: sparisce per A, D non lo sa e i suoi messaggi non arrivano
    rej = rpc("chat_respond_request", {"p_conversation": req, "p_accept": False}, ta)
    again_rej = rpc("chat_respond_request", {"p_conversation": req, "p_accept": True}, ta)
    later = rpc("chat_send", {"p_conversation": req, "p_generation": 1, "p_payload": blob(99)}, td)
    check("R8", "Richiesta rifiutata: non è più tra le chat di A e nulla le arriva; D continua a vederla",
          rej[0] in (200, 204) and again_rej[0] >= 400 and req not in convs(ta)
          and not [m for m in sync(ta) if m["conversation_id"] == req]
          and req in convs(td),
          f"{rej[0]}, {again_rej[0]}, {later[0]}")

    # R9 · Blocco: la chat sparisce e non si scrive più, in entrambi i versi
    rpc("block_user", {"p_user_id": UID_B}, ta)
    b_send = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": blob(70)}, tb)
    reopen = rpc("chat_open_direct", {"p_user": UID_A}, tb)
    hidden = conv not in convs(tb) and conv not in convs(ta)
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    check("R9", "Con un blocco la chat non si vede, non si riapre e non si scrive",
          b_send[0] >= 400 and reopen[0] >= 400 and hidden and conv in convs(ta),
          f"{b_send[0]}, {reopen[0]}, {hidden}")

    # R10 · Telefono nuovo: chiave cambiata visibile all'altra persona, la chat si riapre
    rpc("chat_register_identity", {"p_signature_key": key(3), "p_packages": [blob(24), blob(25)]}, tb)
    changed = convs(ta).get(conv, {})
    rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": blob(71)}, ta)
    s, claimed = rpc("chat_claim_key_package", {"p_conversation": conv}, ta)
    got = claimed[0] if s == 200 and isinstance(claimed, list) and claimed else {}
    st = rpc("chat_start", {"p_conversation": conv, "p_generation": 1,
                            "p_group_id": blob(12, 16), "p_welcome": blob(13, 300)}, ta)
    reopened = convs(ta).get(conv, {})
    old = sql(f"select count(*) from public.chat_messages where conversation_id = '{conv}' "
              "and generation < 2;")
    check("R10", "Telefono nuovo di B: vecchi pacchetti cancellati, A vede la chiave cambiata e riapre",
          changed.get("peer_signature_key") == key(3) and changed.get("peer_joined_key") == key(2)
          and got.get("package") == blob(24) and got.get("signature_key") == key(3)
          and st == (200, 2) and reopened.get("peer_joined_key") == key(3) and old == "0",
          f"{changed.get('peer_signature_key') == key(3)}, {s}, {st}, {old}")


def main() -> int:
    try:
        ids = setup()
    except Exception as exc:  # noqa: BLE001
        print(f"::error::Preparazione dei dati di prova fallita: {exc}")
        return 1
    run(ids)
    check_profile_block2()
    check_privacy_block3()
    check_security_block4()
    check_contacts_block5()
    check_map_listings_phase3()
    check_nearby_phase3()
    check_interactions_phase3()
    check_marketplace_phase5()
    check_marketplace_search_phase5()
    check_swap_proposals_phase5()
    check_deals_feedback_phase5()
    check_comments_categories_phase5()
    check_claimless_access()
    check_rubrica_server()
    check_chat_phase4()
    failed = [r for r in results if not r[2]]
    print(f"{'Caso':6} {'Esito':9} Descrizione")
    for case, desc, ok, detail in results:
        print(f"{case:6} {'superato' if ok else 'FALLITO':9} {desc}" + (f"  [{detail}]" if detail else ""))
    print(f"\n{len(results) - len(failed)} superati su {len(results)}")
    expected = os.environ.get("EXPECT_FAIL")
    if expected:
        # Controprova: con un difetto introdotto apposta il caso indicato DEVE fallire.
        caught = any(case == expected and not ok for case, _, ok, _ in results)
        print(f"Controprova: il caso {expected} " + ("ha rilevato il difetto." if caught
              else "NON ha rilevato il difetto."))
        return 0 if caught else 1
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("## Test di sicurezza Supabase (database temporaneo)\n\n| Caso | Esito | Descrizione |\n|---|---|---|\n")
            for case, desc, ok, _ in results:
                fh.write(f"| {case} | {'✅' if ok else '❌'} | {desc} |\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
