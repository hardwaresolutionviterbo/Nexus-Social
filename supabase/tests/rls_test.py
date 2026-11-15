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


def token(sub: str | None = UID_A, *, project: str = PROJECT, role: str = "authenticated",
          iat_offset: int = -10, exp_offset: int = 3600, secret: bytes | None = None,
          extra: dict | None = None) -> str:
    now = int(time.time())
    claims = {
        "iss": f"https://securetoken.google.com/{project}",
        "aud": project,
        "role": role,
        "iat": now + iat_offset,
        "auth_time": now + iat_offset,
        "exp": now + exp_offset,
    }
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

    # Compatibilità con il controllo di avvio dell'app (Profilo → «Collegato»).
    s, body = get("/rest/v1/profiles?select=id&limit=1")
    check("APP", "Il controllo di avvio dell'app risponde HTTP 200 senza dati",
          s == 200 and body == [], f"HTTP {s}")

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
