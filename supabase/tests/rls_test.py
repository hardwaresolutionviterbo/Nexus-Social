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
VALID_VAT_2 = "11111111115"  # un'altra partita IVA inventata valida
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
            device: str | None = None, content_type: str = "image/jpeg") -> int:
    """Chiamata allo Storage temporaneo; restituisce solo lo stato HTTP."""
    headers = {"apikey": ANON, "Content-Type": content_type}
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
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        # Connessione chiusa dal server (per esempio file oltre il limite): rifiutato.
        return 599


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
    same = [rpc("chat_register_identity", {"p_signature_key": key(1), "p_packages": []}, ta)[0]
            for _ in range(6)]
    mine = rpc("chat_my_identity", {}, ta)
    check("R1", "Chiave della chat e pacchetti registrati; tabelle della chat mai leggibili dall'app",
          all(r[0] in (200, 204) for r in (reg_a, reg_b, reg_d)) and count(ta) == 3 and count(tb) == 3
          and all(x in (200, 204) for x in same) and mine == (200, key(1))
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
    rpc("chat_mark", {"p_conversation": conv, "p_delivered": msg_id, "p_read": (msg_id or 0) + 1000}, tb)
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


def check_chat_media_phase4() -> None:
    """S · Allegati cifrati della chat (Fase 4, Blocco 3): solo chi è nella chat."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    blob = bytes(range(256)) * 8  # byte illeggibili, come un allegato cifrato
    bin_type = "application/octet-stream"
    _, conv = rpc("chat_open_direct", {"p_user": UID_B}, ta)
    _, req = rpc("chat_open_direct", {"p_user": UID_A}, td)  # rifiutata da A nei casi R

    def up(tok, path, kind=bin_type, data=blob):
        return storage("POST", f"chat-media/{path}", tok, data, content_type=kind)

    def down(tok, path):
        return storage("GET", f"authenticated/chat-media/{path}", tok)

    own = f"{conv}/{UID_A}/allegatoProvaA000001.bin"
    s_own = up(ta, own)
    s_foreign_folder = up(ta, f"{conv}/{UID_B}/allegatoIntruso00001.bin")
    s_outsider = up(td, f"{conv}/{UID_D}/allegatoEstraneo0001.bin")
    s_jpeg = up(ta, f"{conv}/{UID_A}/allegatoInChiaro0001.bin", "image/jpeg")
    s_name = up(ta, f"{conv}/{UID_A}/corto.bin")
    s_big = up(ta, f"{conv}/{UID_A}/allegatoTroppoGrande1.bin", data=b"x" * (52428800 + 1))
    check("S1", "Allegato caricato solo da chi è nella chat, nella propria cartella, cifrato, ≤ 50 MB",
          s_own == 200 and s_foreign_folder >= 400 and s_outsider >= 400 and s_jpeg >= 400
          and s_name >= 400 and s_big >= 400,
          f"{s_own}, {s_foreign_folder}, {s_outsider}, {s_jpeg}, {s_name}, {s_big}")

    g_b, g_d, g_anon = down(tb, own), down(td, own), down(None, own)
    g_public = storage("GET", f"public/chat-media/{own}", None)
    listed = storage("POST", "list/chat-media", td, json.dumps({"prefix": f"{conv}/"}).encode(),
                     content_type="application/json")
    check("S2", "Lo scarica solo l'altra persona della chat; estranei, anonimi e link pubblici no",
          g_b == 200 and g_d >= 400 and g_anon >= 400 and g_public >= 400,
          f"{g_b}, {g_d}, {g_anon}, {g_public}, elenco={listed}")

    in_req = f"{req}/{UID_D}/allegatoRichiesta0001.bin"
    s_req = up(td, in_req)
    check("S3", "Richiesta rifiutata: chi l'ha rifiutata non riceve allegati",
          s_req == 200 and down(ta, in_req) >= 400 and down(td, in_req) == 200,
          f"{s_req}, {down(ta, in_req)}")

    rpc("block_user", {"p_user_id": UID_B}, ta)
    blocked = down(tb, own)
    up_blocked = up(tb, f"{conv}/{UID_B}/allegatoBloccato001.bin")
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    check("S4", "Con un blocco l'allegato non si scarica e non si carica",
          blocked >= 400 and up_blocked >= 400 and down(tb, own) == 200,
          f"{blocked}, {up_blocked}")

    overwrite = storage("PUT", f"chat-media/{own}", ta, b"altro", content_type=bin_type)
    storage("DELETE", f"chat-media/{own}", td)
    still = down(tb, own)
    removed = storage("DELETE", f"chat-media/{own}", tb)
    gone = down(tb, own)
    check("S5", "Nessuna modifica; l'estraneo non cancella; chi riceve cancella dopo lo scaricamento",
          overwrite >= 400 and still == 200 and removed == 200 and gone >= 400,
          f"{overwrite}, {still}, {removed}, {gone}")


def check_chat_groups_phase4() -> None:
    """T · Gruppi cifrati (Fase 4, Blocco 4): amministratori, inviti, gruppo cifrato, foto."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A), (tb, UID_D), (td, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)

    def b64(n: int, size: int = 120) -> str:
        return base64.b64encode(bytes([n % 256]) * size).decode()

    def mine(tok) -> dict:
        return {c["id"]: c for c in rows(rpc("chat_conversations", {}, tok))}

    def got(tok, conv) -> list:
        return [(m["kind"], m["sender_id"]) for m in rows(rpc("chat_sync", {"p_after": 0, "p_limit": 500}, tok))
                if m["conversation_id"] == conv]

    # Pacchetti chiave freschi per tutti (i casi R ne hanno consumati).
    for tok, n in ((ta, 1), (tb, 3), (td, 4)):
        s_id, key = rpc("chat_my_identity", {}, tok)
        rpc("chat_add_key_packages", {"p_packages": [b64(200 + n, 300)] * 5}, tok)

    # T1 · Creazione: B (che ha A in rubrica) entra, D riceve un invito
    s1, conv = rpc("chat_create_group", {"p_title": "Gita al lago", "p_members": [UID_B, UID_D]}, ta)
    if not isinstance(conv, str):
        check("T1", "Gruppo creato", False, f"{s1}, {conv}")
        return
    long_title = rpc("chat_create_group", {"p_title": "x" * 61, "p_members": []}, ta)
    a_view = mine(ta).get(conv, {})
    d_view = mine(td).get(conv, {})
    check("T1", "Gruppo creato: A amministratore, B membro da aggiungere, D invitato (richiesta)",
          s1 == 200 and long_title[0] >= 400 and a_view.get("kind") == "group"
          and a_view.get("my_role") == "admin" and a_view.get("title") == "Gita al lago"
          and a_view.get("members") == 2 and a_view.get("pending") == 1
          and d_view.get("status") == "request" and a_view.get("peer_id") is None,
          f"{s1}, {long_title[0]}, {a_view.get('members')}, {a_view.get('pending')}, {d_view.get('status')}")

    # T2 · Solo gli amministratori gestiscono il gruppo
    b_add = rpc("chat_group_add", {"p_conversation": conv, "p_members": [UID_D]}, tb)
    b_admin = rpc("chat_group_set_admin", {"p_conversation": conv, "p_user": UID_B, "p_admin": True}, tb)
    b_title = rpc("chat_group_update", {"p_conversation": conv, "p_title": "Nuovo", "p_description": ""}, tb)
    b_code = rpc("chat_group_invite_code", {"p_conversation": conv}, tb)
    b_kp = rpc("chat_group_claim_key_package", {"p_conversation": conv, "p_user": UID_B}, tb)
    b_commit = rpc("chat_group_commit", {"p_conversation": conv, "p_generation": 0, "p_group_id": b64(9, 16),
                                          "p_commit": None, "p_welcome": b64(10, 300),
                                          "p_added": [UID_B], "p_removed": []}, tb)
    direct_kp = rpc("chat_claim_key_package", {"p_conversation": conv}, ta)
    check("T2", "Un membro non aggiunge, non nomina, non rinomina, non crea codici né modifica il gruppo cifrato",
          all(r[0] >= 400 for r in (b_add, b_admin, b_title, b_code, b_kp, b_commit, direct_kp)),
          f"{[r[0] for r in (b_add, b_admin, b_title, b_code, b_kp, b_commit, direct_kp)]}")

    # T3 · Nascita del gruppo cifrato con controllo della generazione
    d_kp = rpc("chat_group_claim_key_package", {"p_conversation": conv, "p_user": UID_D}, ta)
    kp = rpc("chat_group_claim_key_package", {"p_conversation": conv, "p_user": UID_B}, ta)
    born = rpc("chat_group_commit", {"p_conversation": conv, "p_generation": 0, "p_group_id": b64(5, 16),
                                      "p_commit": None, "p_welcome": b64(6, 300),
                                      "p_added": [UID_B], "p_removed": []}, ta)
    again = rpc("chat_group_commit", {"p_conversation": conv, "p_generation": 0, "p_group_id": b64(5, 16),
                                       "p_commit": None, "p_welcome": b64(6, 300),
                                       "p_added": [UID_B], "p_removed": []}, ta)
    b_got = got(tb, conv)
    check("T3", "Gruppo cifrato nato (generazione 1); doppione rifiutato; l'invitato non riceve nulla",
          kp[0] == 200 and d_kp[0] >= 400 and born == (200, 1) and again[0] >= 400
          and ("welcome", UID_A) in b_got and got(td, conv) == []
          and mine(ta)[conv].get("pending") == 0,
          f"{kp[0]}, {d_kp[0]}, {born}, {again[0]}, {b_got}")

    # T4 · Messaggi: arrivano a chi è dentro; spariscono quando tutti li hanno ricevuti
    s4, sent = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": b64(30)}, ta)
    msg = sent[0]["id"] if s4 == 200 and sent else 0
    b_msgs = got(tb, conv)
    d_send = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": b64(31)}, td)
    rpc("chat_mark", {"p_conversation": conv, "p_delivered": msg, "p_read": msg}, tb)
    left = sql(f"select count(*) from public.chat_messages where conversation_id = '{conv}' and kind = 'app';")
    ticks = mine(ta)[conv]
    check("T4", "B riceve il messaggio e gli avvisi; l'invitato non scrive; letto da tutti → sparisce",
          s4 == 200 and ("app", UID_A) in b_msgs and any(k == "event" for k, _ in b_msgs)
          and d_send[0] >= 400 and left == "0"
          and ticks.get("peer_read_upto") == msg,
          f"{s4}, {b_msgs}, {d_send[0]}, {left}, {ticks.get('peer_read_upto')}")

    # T5 · L'invitato accetta: viene aggiunto e non riceve i messaggi precedenti
    s5, early = rpc("chat_send", {"p_conversation": conv, "p_generation": 1, "p_payload": b64(32)}, ta)
    rpc("chat_respond_request", {"p_conversation": conv, "p_accept": True}, td)
    pending = mine(ta)[conv].get("pending")
    kp_d = rpc("chat_group_claim_key_package", {"p_conversation": conv, "p_user": UID_D}, ta)
    step = rpc("chat_group_commit", {"p_conversation": conv, "p_generation": 1, "p_group_id": b64(5, 16),
                                      "p_commit": b64(40, 200), "p_welcome": b64(41, 300),
                                      "p_added": [UID_D], "p_removed": []}, ta)
    d_got = got(td, conv)
    b_got = got(tb, conv)
    later = rpc("chat_send", {"p_conversation": conv, "p_generation": 2, "p_payload": b64(33)}, td)
    check("T5", "Invito accettato: D aggiunto (generazione 2), riceve l'invito cifrato e non i messaggi di prima",
          pending == 1 and kp_d[0] == 200 and step == (200, 2)
          and ("welcome", UID_A) in d_got and ("app", UID_A) not in d_got
          and ("commit", UID_A) in b_got and later[0] == 200,
          f"{pending}, {kp_d[0]}, {step}, {d_got}, {later[0]}")

    # T6 · Codice d'invito: solo amministratori; entra chi lo usa; revocato non vale più
    code_s, code = rpc("chat_group_invite_code", {"p_conversation": conv}, ta)
    rpc("chat_group_remove", {"p_conversation": conv, "p_user": UID_D}, td)
    out = conv not in mine(td)
    info = rpc("chat_group_invite_info", {"p_code": code}, td)
    join = rpc("chat_group_join", {"p_code": code}, td)
    d_state = sql(f"select status || '/' || mls_state from public.chat_members "
                  f"where conversation_id = '{conv}' and user_id = '{UID_D}';")
    rpc("chat_group_invite_revoke", {"p_conversation": conv}, ta)
    rpc("chat_group_remove", {"p_conversation": conv, "p_user": UID_D}, td)
    rejoin = rpc("chat_group_join", {"p_code": code}, td)
    bogus = rpc("chat_group_join", {"p_code": "ZZZZZZZZZZ"}, td)
    check("T6", "Uscita, rientro con il codice (vecchio telefono da togliere e riaggiungere); codice revocato o falso rifiutato",
          code_s == 200 and isinstance(code, str) and len(code) == 10 and out
          and info[0] == 200 and (rows(info) or [{}])[0].get("title") == "Gita al lago"
          and join == (200, conv) and d_state == "active/to_readd"
          and rejoin[0] >= 400 and bogus[0] >= 400,
          f"{code_s}, {out}, {info[0]}, {join[0]}, {d_state}, {rejoin[0]}, {bogus[0]}")

    # T7 · Amministratori: si nominano; il gruppo non resta mai senza
    up = rpc("chat_group_set_admin", {"p_conversation": conv, "p_user": UID_B, "p_admin": True}, ta)
    down_a = rpc("chat_group_set_admin", {"p_conversation": conv, "p_user": UID_A, "p_admin": False}, tb)
    last = rpc("chat_group_set_admin", {"p_conversation": conv, "p_user": UID_B, "p_admin": False}, tb)
    roles = {m["user_id"]: m["role"] for m in rows(rpc("chat_group_members", {"p_conversation": conv}, tb))}
    check("T7", "B nominato amministratore; A tolto; l'ultimo amministratore non si toglie",
          up[0] in (200, 204) and down_a[0] in (200, 204) and last[0] >= 400
          and roles.get(UID_B) == "admin" and roles.get(UID_A) == "member",
          f"{up[0]}, {down_a[0]}, {last[0]}, {roles}")

    # T8 · Telefono nuovo: va riaggiunto; chi esce va tolto dal gruppo cifrato
    rpc("chat_register_identity", {"p_signature_key": base64.b64encode(bytes([77]) * 32).decode(),
                                   "p_packages": [b64(90, 300)]}, ta)
    states = {m["user_id"]: m["mls_state"] for m in rows(rpc("chat_group_members", {"p_conversation": conv}, tb))}
    readd = rpc("chat_group_claim_key_package", {"p_conversation": conv, "p_user": UID_A}, tb)
    a_send = rpc("chat_send", {"p_conversation": conv, "p_generation": 2, "p_payload": b64(34)}, ta)
    fix = rpc("chat_group_commit", {"p_conversation": conv, "p_generation": 2, "p_group_id": b64(5, 16),
                                     "p_commit": b64(42, 200), "p_welcome": b64(43, 300),
                                     "p_added": [UID_A], "p_removed": [UID_A]}, tb)
    after = {m["user_id"]: m["mls_state"] for m in rows(rpc("chat_group_members", {"p_conversation": conv}, tb))}
    check("T8", "Telefono nuovo di A: da riaggiungere (non scrive finché non rientra); B lo riaggiunge",
          states.get(UID_A) == "to_readd" and readd[0] == 200 and a_send[0] >= 400
          and fix == (200, 3) and after.get(UID_A) == "in",
          f"{states}, {readd[0]}, {a_send[0]}, {fix}, {after}")

    # T9 · Foto del gruppo e allegati: membri sì, estranei no
    photo = f"chat-group-photos/{conv}/foto.jpg"
    up_admin = storage("POST", photo, tb, b"\xff\xd8\xff" + b"0" * 200)
    up_member = storage("PUT", photo, ta, b"\xff\xd8\xff" + b"1" * 200)
    see_member = storage("GET", f"authenticated/{photo}", ta)
    see_out = storage("GET", f"authenticated/{photo}", td)
    media_in = storage("POST", f"chat-media/{conv}/{UID_A}/allegatoGruppo00001.bin", ta,
                       bytes(range(256)), content_type="application/octet-stream")
    media_out = storage("POST", f"chat-media/{conv}/{UID_D}/allegatoGruppo00002.bin", td,
                        bytes(range(256)), content_type="application/octet-stream")
    rpc("chat_group_update", {"p_conversation": conv, "p_title": "Gita al lago 2026",
                              "p_description": "Sabato 9:00", "p_photo_changed": True}, tb)
    view = mine(ta)[conv]
    check("T9", "Foto: la cambia l'amministratore e la vede chi è nel gruppo; allegati solo per chi è dentro",
          up_admin == 200 and up_member >= 400 and see_member == 200 and see_out >= 400
          and media_in == 200 and media_out >= 400
          and view.get("title") == "Gita al lago 2026" and view.get("photo_version") == 1,
          f"{up_admin}, {up_member}, {see_member}, {see_out}, {media_in}, {media_out}, {view.get('title')}")


def check_backup_phase4() -> None:
    """V · Backup della chat cifrato (Fase 4, Blocco 6): un file per account, solo del proprietario."""
    ta, tb = token(UID_A), token(UID_B)
    blob = bytes(range(256)) * 16  # byte illeggibili, come un backup cifrato
    bin_type = "application/octet-stream"
    own = f"chat-backups/{UID_A}/backup.bin"

    def info(tok) -> list:
        status, body = rpc("chat_backup_info", {}, tok)
        return body if status == 200 and isinstance(body, list) else [status]

    s_own = storage("POST", own, ta, blob, content_type=bin_type)
    s_other = storage("POST", f"chat-backups/{UID_B}/backup.bin", ta, blob, content_type=bin_type)
    s_name = storage("POST", f"chat-backups/{UID_A}/altro.bin", ta, blob, content_type=bin_type)
    s_plain = storage("POST", f"chat-backups/{UID_B}/backup.bin", tb, b"{}", content_type="application/json")
    s_big = storage("POST", f"chat-backups/{UID_B}/backup.bin", tb, b"x" * (20971520 + 1), content_type=bin_type)
    check("V1", "Backup caricato solo nel proprio file, cifrato, ≤ 20 MB",
          s_own == 200 and s_other >= 400 and s_name >= 400 and s_plain >= 400 and s_big >= 400,
          f"{s_own}, {s_other}, {s_name}, {s_plain}, {s_big}")

    g_a = storage("GET", f"authenticated/{own}", ta)
    g_b = storage("GET", f"authenticated/{own}", tb)
    g_anon = storage("GET", f"authenticated/{own}", None)
    g_public = storage("GET", f"public/{own}", None)
    listed = storage("POST", "list/chat-backups", tb, json.dumps({"prefix": f"{UID_A}/"}).encode(),
                     content_type="application/json")
    check("V2", "Il backup lo scarica solo il proprietario; altri utenti, anonimi e link pubblici no",
          g_a == 200 and g_b >= 400 and g_anon >= 400 and g_public >= 400,
          f"{g_a}, {g_b}, {g_anon}, {g_public}, elenco={listed}")

    ia, ib = info(ta), info(tb)
    anon_info = rpc("chat_backup_info", {}, None)[0]
    check("V3", "Data e dimensione del backup solo per il proprietario",
          len(ia) == 1 and isinstance(ia[0], dict) and int(ia[0].get("size") or 0) == len(blob)
          and ib == [] and anon_info >= 400,
          f"{ia}, {ib}, {anon_info}")

    up_b = storage("PUT", own, tb, b"rovinato", content_type=bin_type)
    del_b = storage("DELETE", own, tb)
    replaced = storage("PUT", own, ta, blob[:1000], content_type=bin_type)
    size_after = info(ta)
    removed = storage("DELETE", own, ta)
    check("V4", "Solo il proprietario sostituisce o cancella il backup",
          up_b >= 400 and replaced == 200 and size_after and isinstance(size_after[0], dict)
          and int(size_after[0].get("size") or 0) == 1000 and removed == 200 and info(ta) == [],
          f"{up_b}, {del_b}, {replaced}, {size_after}, {removed}")


def check_chat_reports_phase4() -> None:
    """W · Segnalazione di una chat (Fase 4, Blocco 7): solo i messaggi scelti, solo agli admin."""
    ta, tb, tc, td = token(UID_A), token(UID_B), token(UID_C), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    _, conv = rpc("chat_open_direct", {"p_user": UID_B}, ta)
    chosen = [{"a": "2026-11-18T18:00:00Z", "da": UID_B, "t": "Mandami prima i soldi con una ricarica"},
              {"a": "2026-11-18T18:01:00Z", "da": "io", "t": "No, preferisco di persona"}]

    def report(tok, c=conv, reason="truffa", msgs=None, details="Chiede soldi in anticipo"):
        return rpc("chat_report", {"p_conversation": c, "p_reason": reason, "p_details": details,
                                   "p_messages": chosen if msgs is None else msgs}, tok)

    ok = report(ta)
    outsider = report(tc)
    bad_reason = report(ta, reason="antipatico")
    too_many = report(ta, msgs=[chosen[0]] * 51)
    too_long = report(ta, msgs=[{"a": "2026-11-18T18:00:00Z", "da": "io", "t": "x" * 4001}])
    anon = report(None)
    check("W1", "Segnala solo chi è nella chat, con un motivo valido e al massimo 50 messaggi scelti",
          ok[0] == 200 and isinstance(ok[1], str) and outsider[0] >= 400 and bad_reason[0] >= 400
          and too_many[0] >= 400 and too_long[0] >= 400 and anon[0] >= 400,
          f"{ok[0]}, {outsider[0]}, {bad_reason[0]}, {too_many[0]}, {too_long[0]}, {anon[0]}")

    reads = [rows(get("/rest/v1/chat_reports?select=*", t)) for t in (ta, tb, tc)]
    sql(f"insert into public.admin_users (user_id, role) values ('{UID_D}', 'moderator') on conflict do nothing;")
    seen = rows(get("/rest/v1/chat_reports?select=*", td))
    sql(f"delete from public.admin_users where user_id = '{UID_D}';")
    mine = [r for r in seen if r.get("id") == ok[1]]
    check("W2", "Le segnalazioni le leggono solo gli amministratori: solo i messaggi scelti",
          reads == [[], [], []] and len(mine) == 1 and mine[0].get("reported_user_id") == UID_B
          and [m.get("t") for m in mine[0].get("messages") or []] == [m["t"] for m in chosen]
          and mine[0].get("reason") == "truffa",
          f"{[len(r) for r in reads]}, {len(mine)}")

    again = report(ta, reason="molestie", msgs=[chosen[0]])
    count = sql(f"select count(*) from public.chat_reports where reporter_id = '{UID_A}' "
                f"and conversation_id = '{conv}' and status = 'open';")
    sql(f"insert into public.chat_reports (reporter_id, conversation_id, reason, status) "
        f"select '{UID_B}', '{conv}', 'spam', 'closed' from generate_series(1, 10);")
    limited = report(tb)
    sql(f"delete from public.chat_reports where reporter_id = '{UID_B}';")
    check("W3", "Una sola segnalazione aperta per chat (si aggiorna); al massimo 10 al giorno",
          again[0] == 200 and again[1] == ok[1] and count == "1" and limited[0] >= 400,
          f"{again[0]}, {count}, {limited[0]}")

    direct = [
        request("POST", "/rest/v1/chat_reports", jwt=ta,
                body={"reporter_id": UID_A, "conversation_id": conv, "reason": "spam"}),
        request("PATCH", f"/rest/v1/chat_reports?id=eq.{ok[1]}", jwt=ta, prefer="return=representation",
                body={"status": "closed"}),
        request("DELETE", f"/rest/v1/chat_reports?id=eq.{ok[1]}", jwt=tb, prefer="return=representation"),
    ]
    still = sql(f"select status from public.chat_reports where id = '{ok[1]}';")
    check("W4", "Nessuno scrive, cambia o cancella le segnalazioni direttamente",
          all(denied(d) for d in direct) and still == "open", f"{[d[0] for d in direct]}, {still}")


def check_calls_phase4() -> None:
    """X · Chiamate (Fase 4, Blocco 8): solo nelle chat a due accettate, squillo solo per l'offerta."""
    ta, tb, tc, td = token(UID_A), token(UID_B), token(UID_C), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    _, conv = rpc("chat_open_direct", {"p_user": UID_A}, tb)
    sql(f"update public.chat_members set status = 'active', muted_until = null where conversation_id = '{conv}';")
    gen = int(sql(f"select generation from public.chat_conversations where id = '{conv}';") or 0)
    if gen == 0:
        sql(f"update public.chat_conversations set generation = 1 where id = '{conv}';")
        gen = 1
    rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": True,
                              "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                              "p_time_zone": "Europe/Rome"}, ta)
    fid = "fidTelefonoChiamateA_" + "x" * 12
    rpc("push_register", {"p_fid": fid, "p_platform": "android"}, ta)

    def queue() -> list:
        out = sql(f"select kind || '|' || body from private.push_queue where user_id = '{UID_A}' order by id;")
        return [line for line in out.splitlines() if line]

    def signal(tok, c=conv, ring=False, video=False):
        payload = base64.b64encode(bytes([9]) * 60).decode()
        return rpc("call_signal", {"p_conversation": c, "p_generation": gen, "p_payload": payload,
                                   "p_ring": ring, "p_video": video}, tok)

    sql("delete from private.push_queue;")
    sql(f"delete from private.call_rings where user_id = '{UID_B}';")
    offer = signal(tb, ring=True)
    after_offer = queue()
    sql("delete from private.push_queue;")
    quiet = [signal(tb)[0], signal(tb)[0]]
    after_quiet = queue()
    video = signal(tb, ring=True, video=True)
    after_video = queue()
    check("X1", "L'offerta fa squillare («Chiamata in arrivo»); risposta e chiusura non mandano notifiche",
          offer[0] == 200 and after_offer == ["call|Chiamata in arrivo"] and quiet == [200, 200]
          and after_quiet == [] and video[0] == 200 and after_video == ["call|Videochiamata in arrivo"],
          f"{offer[0]}, {after_offer}, {quiet}, {after_quiet}, {video[0]}, {after_video}")

    _, req = rpc("chat_open_direct", {"p_user": UID_A}, td)
    sql(f"update public.chat_conversations set generation = greatest(generation, 1) where id = '{req}';")
    stranger = rpc("call_signal", {"p_conversation": req, "p_generation": 1,
                                   "p_payload": base64.b64encode(bytes([9]) * 60).decode(),
                                   "p_ring": True, "p_video": False}, td)
    outsider = signal(tc, ring=True)
    rpc("block_user", {"p_user_id": UID_B}, ta)
    blocked = signal(tb, ring=True)
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    anon = signal(None, ring=True)
    check("X2", "Non si chiama da una richiesta di messaggio, da fuori, con un blocco o senza accesso",
          stranger[0] >= 400 and outsider[0] >= 400 and blocked[0] >= 400 and anon[0] >= 400,
          f"{stranger[0]}, {outsider[0]}, {blocked[0]}, {anon[0]}")

    sql(f"insert into private.call_rings (user_id) select '{UID_B}' from generate_series(1, 30);")
    limited = signal(tb, ring=True)
    still_quiet = signal(tb)
    sql(f"delete from private.call_rings where user_id = '{UID_B}';")
    check("X3", "Al massimo 30 squilli l'ora (le chiusure passano comunque)",
          limited[0] >= 400 and still_quiet[0] == 200, f"{limited[0]}, {still_quiet[0]}")

    sql("delete from private.push_queue;")
    sql(f"update public.chat_members set muted_until = 'infinity' where conversation_id = '{conv}' and user_id = '{UID_A}';")
    muted = signal(tb, ring=True)
    muted_queue = queue()
    sql(f"update public.chat_members set muted_until = null where conversation_id = '{conv}';")
    direct = request("POST", "/rest/v1/rpc/push_enqueue", jwt=tb, body={})
    check("X4", "Chat silenziata: la chiamata arriva ma non squilla; la coda non si tocca da fuori",
          muted[0] == 200 and muted_queue == [] and direct[0] >= 400, f"{muted[0]}, {muted_queue}, {direct[0]}")
    rpc("push_unregister", {"p_fid": fid}, ta)


def check_realtime_phase4() -> None:
    """RT · Tempo reale (Fase 4, Blocco 9): tocchi vuoti sul canale privato, solo per il proprietario."""
    ta, tb = token(UID_A), token(UID_B)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    _, conv = rpc("chat_open_direct", {"p_user": UID_A}, tb)
    sql(f"update public.chat_members set status = 'active' where conversation_id = '{conv}';")
    gen = int(sql(f"select generation from public.chat_conversations where id = '{conv}';") or 0)
    if gen == 0:
        sql(f"update public.chat_conversations set generation = 1 where id = '{conv}';")
        gen = 1

    def pokes(user) -> int:
        return int(sql(f"select count(*) from realtime.messages where topic = 'u:{user}' "
                       "and inserted_at > now() - interval '10 minutes';") or 0)

    a0, b0 = pokes(UID_A), pokes(UID_B)
    sent = rpc("chat_send", {"p_conversation": conv, "p_generation": gen,
                             "p_payload": base64.b64encode(bytes([5]) * 60).decode()}, tb)
    a1, b1 = pokes(UID_A), pokes(UID_B)
    # realtime.send aggiunge solo un identificativo casuale del tocco: nessun contenuto.
    with_content = sql(f"select count(*) from realtime.messages where topic like 'u:%' "
                       "and (payload - 'id') <> '{}'::jsonb;")
    check("RT1", "Messaggio → tocco vuoto sul canale di chi riceve (non di chi scrive)",
          sent[0] == 200 and a1 == a0 + 1 and b1 == b0 and with_content == "0",
          f"{sent[0]}, {a0}->{a1}, {b0}->{b1}, con contenuto={with_content}")

    first = sent[1][0]["id"] if isinstance(sent[1], list) and sent[1] else 0
    rpc("chat_mark", {"p_conversation": conv, "p_delivered": first, "p_read": 0}, ta)
    b2 = pokes(UID_B)
    check("RT2", "Spunte: anche chi ha scritto riceve un tocco", b2 >= b1 + 1, f"{b1}->{b2}")

    # La regola del canale (applicata da Supabase Realtime per ogni ascoltatore).
    policies = sql("select count(*) || '|' || coalesce(string_agg(qual, ' '), '') from pg_policies "
                   "where schemaname = 'realtime' and tablename = 'messages' and cmd in ('SELECT', 'ALL') "
                   "and permissive = 'PERMISSIVE';")
    count, _, qual = policies.partition("|")

    def allowed(sub: str | None, topic: str) -> str:
        now = int(time.time())
        claims = "" if sub is None else json.dumps({
            "iss": f"https://securetoken.google.com/{PROJECT}", "aud": PROJECT, "sub": sub,
            "iat": now - 10, "exp": now + 3600})
        out = sql("begin; "
                  f"select set_config('request.jwt.claims', '{claims}', true); "
                  f"select set_config('realtime.topic', '{topic}', true); "
                  "select coalesce((select realtime.topic()) = 'u:' || public.current_uid_raw(), false); rollback;")
        vals = [line.strip() for line in out.splitlines() if line.strip() in ("t", "f")]
        return vals[-1] if vals else "?"

    own, other, anon = allowed(UID_A, f"u:{UID_A}"), allowed(UID_B, f"u:{UID_A}"), allowed(None, f"u:{UID_A}")
    check("RT3", "Il canale u:<uid> lo ascolta solo il proprietario; altri utenti e anonimi no",
          count == "1" and "current_uid_raw" in qual and "topic" in qual
          and (own, other, anon) == ("t", "f", "f"),
          f"regole={count}, {own}, {other}, {anon}")


def check_preview_phase4() -> None:
    """AP · Anteprima cifrata nella notifica (Fase 4, Blocco 10): passa solo con il consenso."""
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    _, conv = rpc("chat_open_direct", {"p_user": UID_A}, tb)
    sql(f"update public.chat_members set status = 'active', muted_until = null where conversation_id = '{conv}';")
    gen = int(sql(f"select generation from public.chat_conversations where id = '{conv}';") or 0)
    if gen == 0:
        sql(f"update public.chat_conversations set generation = 1 where id = '{conv}';")
        gen = 1
    fid = "fidTelefonoAnteprimaA_" + "x" * 12
    rpc("push_register", {"p_fid": fid, "p_platform": "android"}, ta)

    def settings(preview: bool):
        rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": preview,
                                  "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                                  "p_time_zone": "Europe/Rome"}, ta)

    def send(tok, preview, c=conv):
        return rpc("chat_send_preview", {"p_conversation": c, "p_generation": gen,
                                         "p_payload": base64.b64encode(bytes([6]) * 60).decode(),
                                         "p_preview": preview}, tok)

    def queued() -> list:
        out = sql(f"select coalesce(preview, '-') || '|' || coalesce(sender_id, '-') from private.push_queue "
                  f"where user_id = '{UID_A}' and kind = 'chat';")
        return [line for line in out.splitlines() if line]

    sealed = base64.b64encode(bytes(range(60))).decode()
    settings(True)
    sql("delete from private.push_queue;")
    ok = send(tb, sealed)
    with_consent = queued()
    bad = [send(tb, "non è base64!")[0], send(tb, "A" * 601)[0]]
    outsider = send(tc, sealed)[0]
    check("AP1", "Anteprima cifrata in coda così com'è, con chi l'ha scritta; formati strani e estranei rifiutati",
          ok[0] == 200 and with_consent == [f"{sealed}|{UID_B}"] and all(b >= 400 for b in bad) and outsider >= 400,
          f"{ok[0]}, {with_consent}, {bad}, {outsider}")

    settings(False)
    sql("delete from private.push_queue;")
    send(tb, sealed)
    without = queued()
    settings(True)
    check("AP2", "Con «Mostra chi scrive» spento l'anteprima non parte", without == ["-|-"], f"{without}")

    sql("delete from private.push_queue;")
    plain = rpc("chat_send", {"p_conversation": conv, "p_generation": gen,
                              "p_payload": base64.b64encode(bytes([6]) * 60).decode()}, tb)
    check("AP3", "Senza anteprima (app vecchia) la notifica resta generica",
          plain[0] == 200 and queued() == ["-|-"], f"{plain[0]}, {queued()}")
    rpc("push_unregister", {"p_fid": fid}, ta)


def check_group_calls_phase4() -> None:
    """GC · Chiamate di gruppo (Fase 4, Blocco 10): solo chi è dentro il gruppo, squillo ai membri."""
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    _, conv = rpc("chat_create_group", {"p_title": "Calcetto", "p_members": [UID_B]}, ta)
    sql(f"update public.chat_members set status = 'active', mls_state = 'in', muted_until = null "
        f"where conversation_id = '{conv}';")
    sql(f"update public.chat_conversations set generation = 1 where id = '{conv}';")
    fid = "fidTelefonoGruppoB_" + "x" * 12
    rpc("push_register", {"p_fid": fid, "p_platform": "android"}, tb)
    rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": True,
                              "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                              "p_time_zone": "Europe/Rome"}, tb)

    def signal(tok, ring=True, video=False):
        return rpc("call_signal", {"p_conversation": conv, "p_generation": 1,
                                   "p_payload": base64.b64encode(bytes([8]) * 60).decode(),
                                   "p_ring": ring, "p_video": video}, tok)

    def queue() -> list:
        out = sql(f"select kind || '|' || title || '|' || body from private.push_queue where user_id = '{UID_B}';")
        return [line for line in out.splitlines() if line]

    sql("delete from private.push_queue;")
    sql(f"delete from private.call_rings where user_id = '{UID_A}';")
    ring = signal(ta, video=True)
    rung = queue()
    sql("delete from private.push_queue;")
    join = signal(tb, ring=False)
    after_join = queue()
    outsider = signal(tc)
    check("GC1", "Chiamata di gruppo: squilla ai membri («Calcetto · Videochiamata di gruppo»); entrare non squilla; da fuori no",
          ring[0] == 200 and len(rung) == 1 and rung[0].startswith("call|Calcetto|")
          and rung[0].endswith("Videochiamata di gruppo") and join[0] == 200 and after_join == [] and outsider[0] >= 400,
          f"{ring[0]}, {rung}, {join[0]}, {after_join}, {outsider[0]}")

    sql(f"update public.chat_members set mls_state = 'to_add' where conversation_id = '{conv}' and user_id = '{UID_B}';")
    not_in = signal(tb)
    sql(f"update public.chat_members set mls_state = 'in' where conversation_id = '{conv}' and user_id = '{UID_B}';")
    sql("delete from private.push_queue;")
    sql(f"update public.chat_members set muted_until = 'infinity' where conversation_id = '{conv}' and user_id = '{UID_B}';")
    muted = signal(ta)
    muted_queue = queue()
    sql(f"update public.chat_members set muted_until = null where conversation_id = '{conv}';")
    check("GC2", "Chi non è ancora dentro la cifratura non chiama; gruppo silenziato: nessuno squillo",
          not_in[0] >= 400 and muted[0] == 200 and muted_queue == [], f"{not_in[0]}, {muted[0]}, {muted_queue}")
    rpc("push_unregister", {"p_fid": fid}, tb)


def check_contact_names_phase4() -> None:
    """CN · Nomi della rubrica (Fase 4, Blocco 11): l'impronta → persona solo per i contatti riconosciuti."""
    ta, tc = token(UID_A), token(UID_C)
    tag_b = sql(f"select tag from private.phone_numbers where user_id = '{UID_B}';")
    tag_d = sql(f"select tag from private.phone_numbers where user_id = '{UID_D}';")
    sql(f"insert into public.consents (user_id, kind) values ('{UID_A}', 'contacts') "
        "on conflict (user_id, kind) do update set revoked_at = null;")
    sql(f"insert into private.contact_links (owner_id, contact_id, expires_at) values "
        f"('{UID_A}', '{UID_B}', now() + interval '30 days') on conflict (owner_id, contact_id) "
        "do update set expires_at = excluded.expires_at;")
    sql(f"delete from private.contact_links where owner_id = '{UID_A}' and contact_id = '{UID_D}';")
    status, rows = rpc("match_contact_tags", {"p_tags": [tag_b, tag_d, "ab" * 32]}, ta)
    got = sorted((r.get("id"), r.get("tag")) for r in rows) if isinstance(rows, list) else rows
    check("CN1", "Risponde solo per le persone già riconosciute come contatti (non per gli altri numeri)",
          status == 200 and got == [(UID_B, tag_b)], f"{status}, {len(got) if isinstance(got, list) else got}")

    no_consent = rpc("match_contact_tags", {"p_tags": [tag_b]}, tc)[0]
    bad = rpc("match_contact_tags", {"p_tags": ["non-valido"]}, ta)[0]
    anon = rpc("match_contact_tags", {"p_tags": [tag_b]}, None)[0]
    sql(f"update private.contact_links set expires_at = now() - interval '1 second' "
        f"where owner_id = '{UID_A}' and contact_id = '{UID_B}';")
    _, expired = rpc("match_contact_tags", {"p_tags": [tag_b]}, ta)
    sql(f"update private.contact_links set expires_at = now() + interval '30 days' "
        f"where owner_id = '{UID_A}' and contact_id = '{UID_B}';")
    check("CN2", "Senza consenso, con dati strani, senza accesso o con il contatto scaduto: niente",
          no_consent >= 400 and bad >= 400 and anon >= 400 and expired == [],
          f"{no_consent}, {bad}, {anon}, {expired}")


def check_presence_phase4() -> None:
    """OL · Online e ultimo accesso (Fase 4, Blocco 12): secondo la privacy di ognuno, e reciproco."""
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    # B ha A in rubrica; C no.
    sql(f"insert into private.contact_links (owner_id, contact_id, expires_at) values "
        f"('{UID_B}', '{UID_A}', now() + interval '30 days') on conflict (owner_id, contact_id) "
        "do update set expires_at = excluded.expires_at;")
    sql(f"delete from private.contact_links where owner_id = '{UID_B}' and contact_id = '{UID_C}';")
    for t in (ta, tb, tc):
        rpc("set_last_seen", {"p_value": "contatti"}, t)

    def seen(tok, who=UID_B):
        status, rows = rpc("presence_of", {"p_users": [who]}, tok)
        row = rows[0] if status == 200 and isinstance(rows, list) and rows else {}
        return status, row.get("online"), row.get("last_seen") is not None

    ping = rpc("presence_ping", {"p_online": True}, tb)[0]
    contact = seen(ta)
    stranger = seen(tc)
    rpc("set_last_seen", {"p_value": "tutti"}, tb)
    everyone = seen(tc)
    rpc("set_last_seen", {"p_value": "nessuno"}, tb)
    nobody = seen(ta)
    rpc("set_last_seen", {"p_value": "contatti"}, tb)
    check("OL1", "«I miei contatti»: lo vede chi è nella rubrica; «Tutti»: tutti; «Nessuno»: nessuno",
          ping in (200, 204) and contact == (200, True, True) and stranger == (200, False, False)
          and everyone == (200, True, True) and nobody == (200, False, False),
          f"{ping}, {contact}, {stranger}, {everyone}, {nobody}")

    rpc("set_last_seen", {"p_value": "nessuno"}, ta)
    hidden_me = seen(ta)
    rpc("set_last_seen", {"p_value": "contatti"}, ta)
    rpc("block_user", {"p_user_id": UID_B}, ta)
    blocked = seen(ta)
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    check("OL2", "Chi nasconde il proprio non vede quello degli altri; con un blocco nessuno dei due",
          hidden_me == (200, False, False) and blocked == (200, False, False), f"{hidden_me}, {blocked}")

    rpc("presence_ping", {"p_online": False}, tb)
    away = seen(ta)
    bad = rpc("set_last_seen", {"p_value": "amici"}, ta)[0]
    anon = [rpc("presence_ping", {"p_online": True}, None)[0], rpc("presence_of", {"p_users": [UID_B]}, None)[0]]
    _, mine = rpc("get_my_privacy", {}, ta)
    check("OL3", "App chiusa: non più online ma ultimo accesso; valori strani e senza accesso rifiutati",
          away == (200, False, True) and bad >= 400 and all(x >= 400 for x in anon)
          and isinstance(mine, dict) and mine.get("last_seen") == "contatti",
          f"{away}, {bad}, {anon}, {mine.get('last_seen') if isinstance(mine, dict) else mine}")


def check_statuses_phase4() -> None:
    """ST · Stati (Fase 4, Blocco 13): li vede solo chi l'autore ha scelto, per 24 ore."""
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)
    for t, other in ((ta, UID_B), (tb, UID_A), (tb, UID_C), (tc, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    sql(f"insert into private.contact_links (owner_id, contact_id, expires_at) values "
        f"('{UID_B}', '{UID_A}', now() + interval '30 days') on conflict (owner_id, contact_id) "
        "do update set expires_at = excluded.expires_at;")
    sql(f"delete from private.contact_links where owner_id = '{UID_B}' and contact_id = '{UID_C}';")
    sql(f"delete from public.statuses where user_id = '{UID_B}';")

    def create(kind="testo", body="Al mare!", media=None, audience="contatti", people=None, tok=None):
        return rpc("status_create", {"p_kind": kind, "p_body": body, "p_color": 2, "p_media_path": media,
                                     "p_audience": audience, "p_people": people or []}, tok or tb)

    def feed_ids(tok) -> set:
        status, rows = rpc("status_feed", {}, tok)
        return {r["id"] for r in rows} if status == 200 and isinstance(rows, list) else {"errore"}

    s1 = create()
    a_sees, c_sees = feed_ids(ta), feed_ids(tc)
    anon = rpc("status_feed", {}, None)[0]
    empty = create(body="   ")[0]
    check("ST1", "«I miei contatti»: lo vede chi l'autore ha in rubrica, non gli altri",
          s1[0] == 200 and s1[1] in a_sees and s1[1] not in c_sees and anon >= 400 and empty >= 400,
          f"{s1[0]}, {s1[1] in a_sees}, {s1[1] in c_sees}, {anon}, {empty}")

    except_a = create(audience="tranne", people=[UID_A])[1]
    only_c_no_contact = create(audience="solo", people=[UID_C])[1]
    c_before = only_c_no_contact in feed_ids(tc)
    sql(f"insert into private.contact_links (owner_id, contact_id, expires_at) values "
        f"('{UID_B}', '{UID_C}', now() + interval '30 days') on conflict (owner_id, contact_id) "
        "do update set expires_at = excluded.expires_at;")
    only_c = create(audience="solo", people=[UID_C])[1]
    a2, c2 = feed_ids(ta), feed_ids(tc)
    nobody = create(audience="solo", people=[])[0]
    check("ST2", "«Tranne…» esclude; «Solo…» solo le persone scelte (e che l'autore ha in rubrica)",
          except_a not in a2 and only_c in c2 and only_c not in a2 and not c_before
          and only_c_no_contact in c2 and nobody >= 400,
          f"{except_a in a2}, {only_c in c2}, {only_c in a2}, {c_before}, {nobody}")
    sql(f"delete from private.contact_links where owner_id = '{UID_B}' and contact_id = '{UID_C}';")

    jpg = b"\xff\xd8\xff" + bytes(200)
    up = storage("POST", f"stati/{UID_B}/foto1.jpg", tb, jpg, content_type="image/jpeg")
    foreign_up = storage("POST", f"stati/{UID_B}/intruso.jpg", tc, jpg, content_type="image/jpeg")
    photo = create(kind="foto", body="", media=f"{UID_B}/foto1.jpg")
    stolen = create(kind="foto", body="", media=f"{UID_A}/qualcosa.jpg")[0]
    get_a = storage("GET", f"authenticated/stati/{UID_B}/foto1.jpg", ta)
    get_c = storage("GET", f"authenticated/stati/{UID_B}/foto1.jpg", tc)
    check("ST3", "Foto: caricata solo nella propria cartella; la apre solo chi può vedere lo stato",
          up == 200 and foreign_up >= 400 and photo[0] == 200 and stolen >= 400 and get_a == 200 and get_c >= 400,
          f"{up}, {foreign_up}, {photo[0]}, {stolen}, {get_a}, {get_c}")

    seen = rpc("status_seen", {"p_id": s1[1]}, ta)[0]
    seen_c = rpc("status_seen", {"p_id": s1[1]}, tc)[0]
    _, viewers = rpc("status_viewers", {"p_id": s1[1]}, tb)
    _, not_owner = rpc("status_viewers", {"p_id": s1[1]}, ta)
    sql(f"update public.statuses set expires_at = now() - interval '1 second' where user_id = '{UID_B}';")
    expired = s1[1] in feed_ids(ta)
    get_expired = storage("GET", f"authenticated/stati/{UID_B}/foto1.jpg", ta)
    _, cleaned = rpc("status_cleanup", {}, tb)
    left = sql(f"select count(*) from public.statuses where user_id = '{UID_B}';")
    check("ST4", "Chi l'ha visto lo sa solo l'autore; dopo 24 ore sparisce e i file si possono togliere",
          seen in (200, 204) and seen_c >= 400 and [v.get("user_id") for v in viewers] == [UID_A]
          and not_owner == [] and not expired and get_expired >= 400
          and f"{UID_B}/foto1.jpg" in [c.get("media_path") for c in cleaned] and left == "0",
          f"{seen}, {seen_c}, {len(viewers)}, {not_owner}, {expired}, {get_expired}, {left}")


def check_live_location_phase4() -> None:
    """GP · GPS in tempo reale (Blocco 15): solo le persone scelte, a tempo, revocabile."""
    ta, tb, tc = token(UID_A), token(UID_B), token(UID_C)
    for t, other in ((ta, UID_B), (tb, UID_A), (tb, UID_C), (tc, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    sql(f"insert into private.contact_links (owner_id, contact_id, expires_at) values "
        f"('{UID_B}', '{UID_A}', now() + interval '30 days') on conflict (owner_id, contact_id) "
        "do update set expires_at = excluded.expires_at;")
    sql(f"delete from private.contact_links where owner_id = '{UID_B}' and contact_id = '{UID_C}';")
    rpc("live_share_stop", {}, tb)

    def seen(tok) -> list:
        status, rows = rpc("live_visible", {}, tok)
        return [r.get("user_id") for r in rows] if status == 200 and isinstance(rows, list) else ["errore"]

    ok = rpc("live_share_start", {"p_viewers": [UID_A], "p_minutes": 60}, tb)[0]
    not_contact = rpc("live_share_start", {"p_viewers": [UID_C], "p_minutes": 60}, tb)[0]
    bad_time = rpc("live_share_start", {"p_viewers": [UID_A], "p_minutes": 600}, tb)[0]
    anon = rpc("live_share_start", {"p_viewers": [UID_A], "p_minutes": 15}, None)[0]
    _, mine = rpc("live_my_shares", {}, tb)
    check("GP1", "Si accende solo per chi è in rubrica, per 15 min, 1 ora o 8 ore",
          ok == 200 and not_contact >= 400 and bad_time >= 400 and anon >= 400
          and [m.get("viewer_id") for m in mine] == [UID_A],
          f"{ok}, {not_contact}, {bad_time}, {anon}, {len(mine)}")

    before = seen(ta)
    up = rpc("live_update", {"p_lat": 42.42, "p_lng": 12.1, "p_accuracy": 12}, tb)
    c_up = rpc("live_update", {"p_lat": 45.0, "p_lng": 9.0, "p_accuracy": 10}, tc)
    a_rows = rpc("live_visible", {}, ta)[1]
    c_sees, b_sees = seen(tc), seen(tb)
    stored_c = sql(f"select count(*) from private.live_positions where user_id = '{UID_C}';")
    direct = request("GET", "/rest/v1/live_positions?select=*", jwt=ta)[0]
    check("GP2", "La posizione la vede solo la persona scelta; senza condivisione non si salva",
          before == [] and up == (200, True) and a_rows and abs(a_rows[0].get("lat", 0) - 42.42) < 1e-6
          and c_sees == [] and b_sees == [] and c_up == (200, False) and stored_c == "0" and direct >= 400,
          f"{before}, {up}, {c_sees}, {b_sees}, {c_up}, {stored_c}, {direct}")

    rpc("block_user", {"p_user_id": UID_B}, ta)
    blocked_shares = sql(f"select count(*) from private.live_shares where owner_id = '{UID_B}';")
    blocked_pos = sql(f"select count(*) from private.live_positions where user_id = '{UID_B}';")
    rpc("unblock_user", {"p_user_id": UID_B}, ta)
    check("GP3", "Bloccare qualcuno chiude subito la condivisione e cancella la posizione",
          blocked_shares == "0" and blocked_pos == "0" and seen(ta) == [],
          f"{blocked_shares}, {blocked_pos}")

    rpc("live_share_start", {"p_viewers": [UID_A], "p_minutes": 15}, tb)
    rpc("live_update", {"p_lat": 42.4, "p_lng": 12.1, "p_accuracy": 8}, tb)
    sql(f"update private.live_shares set expires_at = now() - interval '1 second' where owner_id = '{UID_B}';")
    expired = seen(ta)
    left = sql(f"select count(*) from private.live_positions where user_id = '{UID_B}';")
    rpc("live_share_start", {"p_viewers": [UID_A], "p_minutes": 15}, tb)
    rpc("live_update", {"p_lat": 42.4, "p_lng": 12.1, "p_accuracy": 8}, tb)
    stop = rpc("live_share_stop", {"p_viewer": UID_A}, tb)[0]
    after_stop = sql(f"select count(*) from private.live_positions where user_id = '{UID_B}';")
    check("GP4", "A tempo scaduto o revocata, sparisce e l'ultima posizione si cancella",
          expired == [] and left == "0" and stop in (200, 204) and after_stop == "0" and seen(ta) == [],
          f"{expired}, {left}, {stop}, {after_stop}")


def check_ai_limits_phase4() -> None:
    """IA · Piazly AI (Blocco 18): limiti per persona contati solo dalla funzione `ia`."""
    ta = token(UID_A)
    service = token(None, role="service_role")
    user_try = rpc("rubrica_consume_limit", {"p_uid": UID_A, "p_kind": "ia_testo", "p_max": 40}, ta)
    text = [rpc("rubrica_consume_limit", {"p_uid": UID_B, "p_kind": "ia_testo", "p_max": 2}, service)[1]
            for _ in range(3)]
    image = rpc("rubrica_consume_limit", {"p_uid": UID_B, "p_kind": "ia_immagini", "p_max": 1}, service)[1]
    other = rpc("rubrica_consume_limit", {"p_uid": UID_B, "p_kind": "ia_altro", "p_max": 1}, service)
    check("IA1", "Domande e immagini IA contate a parte, solo dal server; tipi sconosciuti rifiutati",
          user_try[0] >= 400 and text == [True, True, False] and image is True and other[0] >= 400,
          f"{user_try[0]}, {text}, {image}, {other[0]}")


def check_business_phase6() -> None:
    """BZ · Aziende (Fase 6, Blocco 1): pagina con sede fissa, dati privati, verifica dell'admin."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_D), (td, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    page = {
        "p_display_name": "Bottega Verdi", "p_category": "negozio", "p_description": "Prova",
        "p_street": "Via Roma", "p_civic": "12", "p_city": "Porano", "p_cap": "05010",
        "p_province": "tr", "p_lat": 42.6851, "p_lng": 12.1029, "p_phone": "0763 000000",
        "p_booking_url": "https://esempio.it/prenota",
        "p_hours": {"1": [[420, 780], [960, 1200]], "5": [[1080, 1560]]},
        "p_photos": [], "p_published": True,
    }
    saved, saved_body = rpc("business_page_save", page, td)
    private_user = rpc("business_page_save", page, ta)[0]
    abroad = rpc("business_page_save", {**page, "p_lat": 48.85, "p_lng": 2.35}, td)[0]
    bad_hours = rpc("business_page_save", {**page, "p_hours": {"1": [[900, 600]]}}, td)[0]
    bad_photo = rpc("business_page_save", {**page, "p_photos": [f"{UID_A}/foto-abcdefgh12.jpg"]}, td)[0]
    anon = rpc("business_page_save", page, None)[0]
    direct = request("POST", "/rest/v1/business_pages", jwt=td,
                     body={"id": UID_D, "display_name": "x", "category": "bar", "street": "Via",
                           "civic": "1", "city": "X", "cap": "00100", "province": "RM",
                           "lat": 42.0, "lng": 12.0})[0]
    check("BZ1", "Pagina attività solo per le Aziende, sede in Italia, orari e foto controllati",
          saved in (200, 204) and private_user >= 400 and abroad >= 400 and bad_hours >= 400
          and bad_photo >= 400 and anon >= 400 and direct >= 400,
          f"{saved} {saved_body}, {private_user}, {abroad}, {bad_hours}, {bad_photo}, {anon}, {direct}")

    s_get, got = rpc("business_page_get", {"p_id": UID_D}, ta)
    s_near, near = rpc("businesses_nearby", {"p_lat": 42.69, "p_lng": 12.10, "p_radius_km": 5}, ta)
    far = rpc("businesses_nearby", {"p_lat": 45.46, "p_lng": 9.19, "p_radius_km": 5}, ta)[1]
    private_rows = rows(get(f"/rest/v1/business_private?select=*&id=eq.{UID_D}", ta))
    text = json.dumps(got)
    check("BZ2", "Insegna e sede pubbliche; ragione sociale e partita IVA restano private",
          s_get == 200 and isinstance(got, dict) and got.get("province") == "TR"
          and got.get("verified") is False and "Bottega Verdi Srl" not in text and VALID_VAT not in text
          and s_near == 200 and [r.get("id") for r in near] == [UID_D] and far == [] and private_rows == [],
          f"{s_get}, {s_near}, {len(near) if isinstance(near, list) else near}, {far}, {len(private_rows)}")

    rpc("block_user", {"p_user_id": UID_D}, ta)
    blocked_near = rpc("businesses_nearby", {"p_lat": 42.69, "p_lng": 12.10, "p_radius_km": 5}, ta)[1]
    blocked_get = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    rpc("unblock_user", {"p_user_id": UID_D}, ta)
    check("BZ3", "Chi ha bloccato (o è bloccato) non vede la pagina né il segnaposto",
          blocked_near == [] and blocked_get is None, f"{blocked_near}, {blocked_get}")

    dup = rpc("business_register", {"p_business_name": "Copia Srl", "p_vat_number": VALID_VAT}, ta)[0]
    user_review = rpc("business_review", {"p_id": UID_D, "p_approve": True}, ta)[0]
    user_queue = rpc("business_review_queue", {}, ta)[0]
    sql(f"insert into public.admin_users (user_id, role) values ('{UID_B}', 'moderator') "
        "on conflict (user_id) do nothing;")
    s_queue, queue = rpc("business_review_queue", {}, tb)
    approve = rpc("business_review", {"p_id": UID_D, "p_approve": True, "p_note": "ok"}, tb)[0]
    rpc("subscription_admin_extend", {"p_id": UID_D, "p_months": 1}, tb)  # badge: anche abbonamento (0035)
    verified = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    sql(f"delete from public.admin_users where user_id = '{UID_B}';")
    changed = rpc("business_register", {"p_business_name": "Bottega Verdi Srl", "p_vat_number": "12345678903"}, td)[0]
    after_change = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    check("BZ4", "Solo un amministratore approva; cambiare partita IVA fa ripartire la verifica; IVA unica",
          dup >= 400 and user_review >= 400 and user_queue >= 400 and s_queue == 200
          and UID_D in [r.get("id") for r in queue] and approve in (200, 204)
          and isinstance(verified, dict) and verified.get("verified") is True
          and changed in (200, 204) and isinstance(after_change, dict) and after_change.get("verified") is False,
          f"{dup}, {user_review}, {user_queue}, {s_queue}, {approve}, {verified}, {changed}")

    convert = rpc("business_register", {"p_business_name": "Mario Rossi Bar", "p_vat_number": VALID_VAT_2}, ta)[0]
    kind = sql(f"select account_type from public.profiles where id = '{UID_A}';")
    sql("select set_config('nexus.internal', 'on', false); "
        f"delete from public.business_private where id = '{UID_A}'; "
        f"update public.profiles set account_type = 'private' where id = '{UID_A}';")
    check("BZ5", "Un Privato maggiorenne può registrare l'attività e diventa Azienda",
          convert in (200, 204) and kind == "business", f"{convert}, {kind}")


def check_subscriptions_phase6() -> None:
    """AB · Abbonamento (Fase 6, Blocco 2): prova di 7 giorni, admin, badge solo se attivo."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    sql(f"delete from public.business_subscriptions where id = '{UID_D}'; "
        f"delete from private.business_trials where used_by = '{UID_D}';")
    sql(f"insert into public.admin_users (user_id, role) values ('{UID_B}', 'moderator') "
        "on conflict (user_id) do nothing;")
    rpc("business_review", {"p_id": UID_D, "p_approve": True}, tb)
    before = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    s_trial, trial = rpc("subscription_start_trial", {}, td)
    after = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    near = rpc("businesses_nearby", {"p_lat": 42.69, "p_lng": 12.10, "p_radius_km": 5}, ta)[1]
    again = rpc("subscription_start_trial", {}, td)[0]
    private_user = rpc("subscription_start_trial", {}, ta)[0]
    check("AB1", "Approvata senza abbonamento: niente badge; prova di 7 giorni una sola volta",
          isinstance(before, dict) and before.get("verified") is False and s_trial == 200
          and isinstance(trial, dict) and trial.get("active") is True and trial.get("trial_used") is True
          and isinstance(after, dict) and after.get("verified") is True
          and any(r.get("id") == UID_D and r.get("verified") is True for r in near)
          and again >= 400 and private_user >= 400,
          f"{before}, {s_trial} {trial}, {after}, {again}, {private_user}")

    others = rows(get(f"/rest/v1/business_subscriptions?select=*&id=eq.{UID_D}", ta))
    mine = rows(get(f"/rest/v1/business_subscriptions?select=*&id=eq.{UID_D}", td))
    forge = request("PATCH", f"/rest/v1/business_subscriptions?id=eq.{UID_D}", jwt=td,
                    body={"current_period_end": "2099-01-01T00:00:00Z"})[0]
    user_extend = rpc("subscription_admin_extend", {"p_id": UID_D, "p_months": 12}, td)[0]
    end_now = sql(f"select current_period_end < now() + interval '8 days' from public.business_subscriptions "
                  f"where id = '{UID_D}';")
    check("AB2", "Abbonamento privato; l'azienda non può allungarselo da sola",
          others == [] and len(mine) == 1 and forge >= 400 and user_extend >= 400 and end_now == "t",
          f"{len(others)}, {len(mine)}, {forge}, {user_extend}, {end_now}")

    sql(f"update public.business_subscriptions set current_period_end = now() - interval '1 second' "
        f"where id = '{UID_D}';")
    expired = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    expired_mine = rpc("subscription_mine", {}, td)[1]
    retry = rpc("subscription_start_trial", {}, td)[0]
    extend = rpc("subscription_admin_extend", {"p_id": UID_D, "p_months": 1}, tb)[0]
    extended = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    stop = rpc("subscription_admin_stop", {"p_id": UID_D}, tb)[0]
    stopped = rpc("business_page_get", {"p_id": UID_D}, ta)[1]
    queue = rpc("business_review_queue", {}, tb)[1]
    sql(f"delete from public.admin_users where user_id = '{UID_B}';")
    check("AB3", "Alla scadenza il badge sparisce; l'admin può riattivare e fermare",
          isinstance(expired, dict) and expired.get("verified") is False
          and isinstance(expired_mine, dict) and expired_mine.get("active") is False and retry >= 400
          and extend in (200, 204) and isinstance(extended, dict) and extended.get("verified") is True
          and stop in (200, 204) and isinstance(stopped, dict) and stopped.get("verified") is False
          and isinstance(queue, list) and any(r.get("id") == UID_D and r.get("subscription_source") == "admin"
                                              for r in queue),
          f"{expired}, {expired_mine}, {retry}, {extend}, {extended}, {stop}, {stopped}")


def check_promotions_phase6() -> None:
    """PR · Promozioni e coupon (Fase 6, Blocco 3)."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_D), (td, UID_A), (tb, UID_D), (td, UID_B)):
        rpc("unblock_user", {"p_user_id": other}, t)
    sql(f"delete from public.promotions where business_id = '{UID_D}'; "
        f"update public.business_subscriptions set current_period_end = now() - interval '1 second' "
        f"where id = '{UID_D}';")
    start = sql("select to_char(now() at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"');")
    end = sql("select to_char((now() + interval '2 days') at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"');")
    too_long = sql("select to_char((now() + interval '8 days') at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"');")
    offer = {"p_kind": "offerta", "p_title": "Colazione -20%", "p_description": "Solo oggi",
             "p_starts_at": start, "p_ends_at": end, "p_coupon_text": "Sconto 20%", "p_coupon_limit": 1}
    no_premium = rpc("promotion_create", offer, td)[0]
    sql(f"insert into public.business_subscriptions (id, source, current_period_end) "
        f"values ('{UID_D}', 'admin', now() + interval '1 month') on conflict (id) do update "
        "set current_period_end = now() + interval '1 month';")
    s_offer, offer_id = rpc("promotion_create", offer, td)
    s_event = rpc("promotion_create", {"p_kind": "evento", "p_title": "Concerto in piazza", "p_starts_at": start,
                                       "p_ends_at": end, "p_lat": 42.70, "p_lng": 12.11,
                                       "p_place_label": "Piazza del Popolo, Orvieto"}, td)[0]
    offer_elsewhere = rpc("promotion_create", {**offer, "p_lat": 42.70, "p_lng": 12.11}, td)[0]
    week_plus = rpc("promotion_create", {**offer, "p_ends_at": too_long}, td)[0]
    private_user = rpc("promotion_create", offer, ta)[0]
    more = [rpc("promotion_create", {**offer, "p_title": f"Offerta {i}"}, td)[0] for i in range(4)]
    check("PR1", "Promozioni solo con Premium, al massimo 7 giorni e 5 al giorno; luogo diverso solo per eventi",
          no_premium >= 400 and s_offer == 200 and s_event == 200 and offer_elsewhere >= 400
          and week_plus >= 400 and private_user >= 400 and more[:3] == [200, 200, 200] and more[3] >= 400,
          f"{no_premium}, {s_offer}, {s_event}, {offer_elsewhere}, {week_plus}, {private_user}, {more}")

    near = rpc("promotions_nearby", {"p_lat": 42.69, "p_lng": 12.10, "p_radius_km": 10}, ta)[1]
    of_d = rpc("promotions_of", {"p_business_id": UID_D}, ta)[1]
    direct = get("/rest/v1/promotions?select=*", ta)
    rpc("block_user", {"p_user_id": UID_D}, ta)
    blocked = rpc("promotions_nearby", {"p_lat": 42.69, "p_lng": 12.10, "p_radius_km": 10}, ta)[1]
    rpc("unblock_user", {"p_user_id": UID_D}, ta)
    event = [p for p in near if p.get("kind") == "evento"] if isinstance(near, list) else []
    check("PR2", "Mappa delle promozioni: visibili a tutti tranne chi è bloccato; evento nel suo luogo",
          isinstance(near, list) and len(near) == 5 and isinstance(of_d, list) and len(of_d) == 5
          and (direct[0] >= 400 or rows(direct) == []) and blocked == []
          and len(event) == 1 and event[0].get("at_site") is False and abs(event[0].get("lat", 0) - 42.70) < 1e-6,
          f"{len(near) if isinstance(near, list) else near}, {direct[0]}, {blocked}, {event}")

    s_claim, code = rpc("coupon_claim", {"p_promotion_id": offer_id}, ta)
    again = rpc("coupon_claim", {"p_promotion_id": offer_id}, ta)[1]
    sold_out = rpc("coupon_claim", {"p_promotion_id": offer_id}, tb)[0]
    own = rpc("coupon_claim", {"p_promotion_id": offer_id}, td)[0]
    mine = rpc("coupons_mine", {}, ta)[1]
    check("PR3", "Coupon: uno a persona, codice stabile, limite rispettato, non per il titolare",
          s_claim == 200 and isinstance(code, str) and len(code) == 8 and again == code
          and sold_out >= 400 and own >= 400 and isinstance(mine, list)
          and any(c.get("my_coupon") == code for c in mine),
          f"{s_claim}, {again == code}, {sold_out}, {own}")

    wrong_shop = rpc("coupon_redeem", {"p_code": code}, tb)[0]
    s_ok, ok = rpc("coupon_redeem", {"p_code": f"PIAZLY-{code.lower()}"}, td)
    twice = rpc("coupon_redeem", {"p_code": code}, td)[0]
    stats = rpc("promotions_mine", {}, td)[1]
    first = [p for p in stats if p.get("id") == offer_id] if isinstance(stats, list) else []
    check("PR4", "Convalida solo dall'attività, una volta; conteggio clienti senza dire chi sono",
          wrong_shop >= 400 and s_ok == 200 and isinstance(ok, dict) and ok.get("redeemed") == 1 and twice >= 400
          and len(first) == 1 and first[0].get("claimed") == 1 and first[0].get("redeemed") == 1
          and UID_A not in json.dumps(stats),
          f"{wrong_shop}, {s_ok} {ok}, {twice}, {first}")

    rpc("promotion_cancel", {"p_id": offer_id}, td)
    canceled = rpc("promotions_of", {"p_business_id": UID_D}, ta)[1]
    sql(f"update public.business_subscriptions set current_period_end = now() - interval '1 second' "
        f"where id = '{UID_D}';")
    expired = rpc("promotions_nearby", {"p_lat": 42.69, "p_lng": 12.10, "p_radius_km": 10}, ta)[1]
    check("PR5", "Promozione annullata sparisce; senza Premium spariscono tutte",
          isinstance(canceled, list) and len(canceled) == 4 and expired == [],
          f"{len(canceled) if isinstance(canceled, list) else canceled}, {expired}")


def check_reviews_phase6() -> None:
    """RV · Recensioni verificate (Fase 6, Blocco 4): solo chi ha usato un coupon in cassa."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    for t, other in ((ta, UID_B), (tb, UID_A), (ta, UID_D), (td, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    sql(f"delete from public.business_reviews where business_id = '{UID_D}';")
    # Dal caso PR4: A ha usato in cassa un coupon di D; B no.
    s_a = rpc("review_save", {"p_business_id": UID_D, "p_rating": 5, "p_body": "Ottima colazione"}, ta)[0]
    s_b = rpc("review_save", {"p_business_id": UID_D, "p_rating": 1, "p_body": "Mai stato qui"}, tb)[0]
    s_own = rpc("review_save", {"p_business_id": UID_D, "p_rating": 5, "p_body": "Siamo i migliori"}, td)[0]
    s_bad = rpc("review_save", {"p_business_id": UID_D, "p_rating": 6, "p_body": ""}, ta)[0]
    direct = request("POST", "/rest/v1/business_reviews", jwt=tb,
                     body={"business_id": UID_D, "author_id": UID_B, "rating": 1})[0]
    check("RV1", "Recensione solo da clienti verificati (coupon usato in cassa), non dal titolare",
          s_a in (200, 204) and s_b >= 400 and s_own >= 400 and s_bad >= 400 and direct >= 400,
          f"{s_a}, {s_b}, {s_own}, {s_bad}, {direct}")

    seen_b = rpc("reviews_of", {"p_business_id": UID_D}, tb)[1]
    seen_a = rpc("reviews_of", {"p_business_id": UID_D}, ta)[1]
    text = json.dumps(seen_b)
    check("RV2", "Media e numero per tutti; si vede il nome pubblico, mai l'identificativo",
          isinstance(seen_b, dict) and seen_b.get("count") == 1 and float(seen_b.get("average")) == 5.0
          and seen_b.get("can_review") is False and UID_A not in text
          and isinstance(seen_a, dict) and seen_a.get("can_review") is True
          and seen_a["items"][0].get("mine") is True,
          f"{seen_b}, {seen_a}")

    review_id = seen_a["items"][0]["id"] if isinstance(seen_a, dict) and seen_a.get("items") else None
    s_reply = rpc("review_reply", {"p_review_id": review_id, "p_reply": "Grazie, a presto!"}, td)[0]
    s_fake_reply = rpc("review_reply", {"p_review_id": review_id, "p_reply": "Risposta finta"}, ta)[0]
    rpc("review_save", {"p_business_id": UID_D, "p_rating": 3, "p_body": "Buona ma lenta"}, ta)
    after = rpc("reviews_of", {"p_business_id": UID_D}, tb)[1]
    rpc("block_user", {"p_user_id": UID_A}, tb)
    blocked = rpc("reviews_of", {"p_business_id": UID_D}, tb)[1]
    rpc("unblock_user", {"p_user_id": UID_A}, tb)
    check("RV3", "Risponde solo il titolare; la recensione si corregge; chi blocca non la vede",
          s_reply in (200, 204) and s_fake_reply >= 400 and isinstance(after, dict)
          and after.get("count") == 1 and float(after.get("average")) == 3.0
          and after["items"][0].get("reply") == "Grazie, a presto!"
          and isinstance(blocked, dict) and blocked.get("count") == 0,
          f"{s_reply}, {s_fake_reply}, {after}, {blocked}")

    user_delete = rpc("review_admin_delete", {"p_review_id": review_id}, ta)[0]
    sql(f"insert into public.admin_users (user_id, role) values ('{UID_B}', 'moderator') "
        "on conflict (user_id) do nothing;")
    admin_delete = rpc("review_admin_delete", {"p_review_id": review_id}, tb)[0]
    sql(f"delete from public.admin_users where user_id = '{UID_B}';")
    gone = rpc("reviews_of", {"p_business_id": UID_D}, ta)[1]
    check("RV4", "Solo un amministratore toglie le recensioni degli altri",
          user_delete >= 400 and admin_delete in (200, 204) and isinstance(gone, dict) and gone.get("count") == 0,
          f"{user_delete}, {admin_delete}, {gone}")


def check_admin_phase7() -> None:
    """GS · Gestionale (Fase 7, Blocco 1): accesso con PIN, segnalazioni, avvisi e ban."""
    ta, tb, td = token(UID_A), token(UID_B), token(UID_D)
    dev_b = "gestionaleB_" + "c" * 32
    for t, other in ((ta, UID_D), (td, UID_A), (ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    s_l, listing = rpc("create_listing", {"p_kind": "social", "p_title": "Annuncio da moderare",
                                          "p_description": "", "p_lat": 41.9, "p_lon": 12.49}, ta)
    _, comment = rpc("add_listing_comment", {"p_listing": listing, "p_body": "Commento da moderare"}, ta)
    rep_l = rpc("report_listing", {"p_listing": listing, "p_reason": "truffa",
                                   "p_details": "Chiede un anticipo"}, td)[0]
    rep_c = rpc("report_comment", {"p_comment": comment, "p_reason": "spam"}, td)[0]
    assert s_l == 200 and rep_l in (200, 204) and rep_c in (200, 204), f"{s_l}, {rep_l}, {rep_c}"

    # GS1 · Solo un amministratore con il PIN attivo entra nel gestionale.
    user_access = rpc("admin_access", {}, ta)[1]
    user_queue = rpc("admin_reports", {}, ta)[0]
    user_search = rpc("admin_users_search", {"p_query": "utente"}, ta)[0]
    anon_queue = rpc("admin_reports", {}, None)[0]
    sql(f"insert into public.admin_users (user_id, role) values ('{UID_B}', 'moderator') "
        "on conflict (user_id) do nothing;")
    nopin_access = rpc("admin_access", {}, tb)[1]
    nopin_queue = rpc("admin_reports", {}, tb)[0]
    pin = rpc("set_pin", {"p_new_pin": "735193"}, tb, dev_b)[0]
    pin_access = rpc("admin_access", {}, tb, dev_b)[1]
    other_phone = rpc("admin_reports", {}, tb)[0]
    direct = [rows(get(f"/rest/v1/{t}?select=*", tb)) for t in ("moderation_notices", "user_moderation")]
    check("GS1", "Gestionale solo per amministratori con PIN, dal telefono verificato",
          user_access == {"admin": False} and user_queue >= 400 and user_search >= 400 and anon_queue >= 400
          and isinstance(nopin_access, dict) and nopin_access.get("pin") is False and nopin_queue >= 400
          and pin in (200, 204) and isinstance(pin_access, dict) and pin_access.get("pin") is True
          and other_phone >= 400 and direct == [[], []],
          f"{user_access}, {user_queue}, {user_search}, {anon_queue}, {nopin_access}, {nopin_queue}, "
          f"{pin}, {pin_access}, {other_phone}, {direct}")

    # GS2 · Coda: contenuto, motivo e autore; mai chi ha segnalato.
    s_q, queue = rpc("admin_reports", {}, tb, dev_b)
    by_id = {r.get("id"): r for r in queue} if isinstance(queue, list) else {}
    it_l, it_c = by_id.get(listing) or {}, by_id.get(comment) or {}
    text = json.dumps([it_l, it_c])
    check("GS2", "Coda delle segnalazioni con contenuto, motivo e autore, senza chi ha segnalato",
          s_q == 200 and it_l.get("kind") == "listing" and it_l.get("reasons") == ["truffa"]
          and (it_l.get("preview") or {}).get("title") == "Annuncio da moderare"
          and (it_l.get("author") or {}).get("id") == UID_A and it_l.get("details") == ["Chiede un anticipo"]
          and it_c.get("kind") == "comment" and (it_c.get("preview") or {}).get("text") == "Commento da moderare"
          and UID_D not in text,
          f"{s_q}, {it_l}, {it_c}")

    # GS3 · Elimina l'annuncio, ignora il commento: la persona riceve l'avviso.
    user_resolve = rpc("admin_report_resolve", {"p_kind": "listing", "p_id": listing, "p_action": "remove"}, ta)[0]
    rm = rpc("admin_report_resolve", {"p_kind": "listing", "p_id": listing, "p_action": "remove"}, tb, dev_b)[0]
    ig = rpc("admin_report_resolve", {"p_kind": "comment", "p_id": comment, "p_action": "ignore"}, tb, dev_b)[0]
    bad_warn = rpc("admin_report_resolve", {"p_kind": "comment", "p_id": comment, "p_action": "warn",
                                            "p_message": ""}, tb, dev_b)[0]
    state = sql(f"select status from public.listings where id = '{listing}';")
    rep_states = sql("select string_agg(distinct status::text, ',' order by status::text) from public.reports "
                     f"where target_id in ('{listing}', '{comment}');")
    after = rpc("admin_reports", {}, tb, dev_b)[1]
    mine = rpc("my_moderation", {}, ta)[1]
    kinds = [n.get("kind") for n in (mine or {}).get("notices", [])]
    check("GS3", "Elimina l'annuncio o ignora la segnalazione; la coda si svuota; avviso alla persona",
          user_resolve >= 400 and rm in (200, 204) and ig in (200, 204) and bad_warn >= 400
          and state == "removed" and rep_states == "dismissed,resolved"
          and isinstance(after, list) and listing not in [r.get("id") for r in after]
          and kinds == ["removed"] and UID_B not in json.dumps(mine),
          f"{user_resolve}, {rm}, {ig}, {bad_warn}, {state}, {rep_states}, {kinds}")

    # GS4 · Ban: niente nuovi contenuti, motivo visibile; sblocco.
    ban_user = rpc("admin_ban_user", {"p_user": UID_D, "p_days": 7, "p_reason": "Prova"}, ta)[0]
    ban_admin = rpc("admin_ban_user", {"p_user": UID_B, "p_days": 7, "p_reason": "Prova"}, tb, dev_b)[0]
    bad_days = rpc("admin_ban_user", {"p_user": UID_A, "p_days": 3, "p_reason": "Prova"}, tb, dev_b)[0]
    ban = rpc("admin_ban_user", {"p_user": UID_A, "p_days": 7, "p_reason": "Annunci ingannevoli"}, tb, dev_b)[0]
    banned_listing = rpc("create_listing", {"p_kind": "social", "p_title": "Durante il ban",
                                            "p_description": "", "p_lat": 41.9, "p_lon": 12.49}, ta)[0]
    _, other = rpc("create_listing", {"p_kind": "social", "p_title": "Annuncio di D",
                                      "p_description": "", "p_lat": 41.9, "p_lon": 12.49}, td)
    banned_comment = rpc("add_listing_comment", {"p_listing": other, "p_body": "Durante il ban"}, ta)[0]
    during = rpc("my_moderation", {}, ta)[1] or {}
    unban_user = rpc("admin_unban_user", {"p_user": UID_A}, ta)[0]
    unban = rpc("admin_unban_user", {"p_user": UID_A}, tb, dev_b)[0]
    s_again, again = rpc("create_listing", {"p_kind": "social", "p_title": "Dopo lo sblocco",
                                            "p_description": "", "p_lat": 41.9, "p_lon": 12.49}, ta)
    check("GS4", "Ban di 1, 7, 30 giorni o definitivo: niente annunci o commenti; motivo visibile; sblocco",
          ban_user >= 400 and ban_admin >= 400 and bad_days >= 400 and ban == 200
          and banned_listing >= 400 and banned_comment >= 400
          and during.get("banned_until") is not None and during.get("ban_reason") == "Annunci ingannevoli"
          and unban_user >= 400 and unban in (200, 204) and s_again == 200,
          f"{ban_user}, {ban_admin}, {bad_days}, {ban}, {banned_listing}, {banned_comment}, {during}, "
          f"{unban_user}, {unban}, {s_again}")

    # GS5 · Scheda utente con lo storico; avvisi letti; nessun dato privato.
    warn = rpc("admin_warn_user", {"p_user": UID_A, "p_message": "Usa titoli chiari, grazie"}, tb, dev_b)[0]
    s_d, detail = rpc("admin_user_detail", {"p_user": UID_A}, tb, dev_b)
    actions = [h.get("action") for h in (detail or {}).get("history", [])]
    uname = sql(f"select username from public.profiles where id = '{UID_A}';")
    s_s, found = rpc("admin_users_search", {"p_query": uname}, tb, dev_b)
    before = len((rpc("my_moderation", {}, ta)[1] or {}).get("notices", []))
    rpc("moderation_notices_read", {}, ta)
    after_read = (rpc("my_moderation", {}, ta)[1] or {}).get("notices")
    private_text = json.dumps([detail, found])
    check("GS5", "Scheda utente con storico delle azioni; avvisi letti; nessun dato privato",
          warn in (200, 204) and s_d == 200 and actions[:5] == ["warn", "unban", "ban", "ignore", "remove"]
          and s_s == 200 and isinstance(found, list) and UID_A in [r.get("id") for r in found]
          and before >= 4 and after_read == [] and "Mario Rossi" not in private_text
          and "birth" not in private_text and "phone" not in private_text,
          f"{warn}, {s_d}, {actions}, {s_s}, {found}, {before}, {after_read}")

    rpc("close_my_listing", {"p_id": other}, td)
    rpc("close_my_listing", {"p_id": again}, ta)
    sql(f"delete from public.admin_users where user_id = '{UID_B}'; "
        f"delete from private.trusted_devices where user_id = '{UID_B}'; "
        f"delete from private.account_security where id = '{UID_B}';")


def check_push_phase4() -> None:
    """U · Notifiche (Fase 4, Blocco 5): coda server, silenzia, non disturbare, mai i Mi piace."""
    ta, tb = token(UID_A), token(UID_B)
    for t, other in ((ta, UID_B), (tb, UID_A)):
        rpc("unblock_user", {"p_user_id": other}, t)
    fid_a = "fidTelefonoA_" + "x" * 20

    def queue(user=UID_A) -> list:
        out = sql(f"select kind || '|' || title || '|' || body || '|' || count from private.push_queue "
                  f"where user_id = '{user}' order by id;")
        return [line for line in out.splitlines() if line]

    def clear() -> None:
        sql("delete from private.push_queue;")

    def b64(n: int) -> str:
        return base64.b64encode(bytes([n]) * 60).decode()

    reg = rpc("push_register", {"p_fid": fid_a, "p_platform": "android"}, ta)
    bad = rpc("push_register", {"p_fid": "x", "p_platform": "android"}, ta)
    steal = rpc("push_register", {"p_fid": fid_a, "p_platform": "android"}, tb)
    owner_b = sql(f"select user_id from public.push_devices where fid = '{fid_a}';")
    rpc("push_register", {"p_fid": fid_a, "p_platform": "android"}, ta)
    owner_a = sql(f"select user_id from public.push_devices where fid = '{fid_a}';")
    direct = [get(f"/rest/v1/{t}?select=*", ta) for t in ("push_devices", "push_settings")]
    server_fns = [rpc(f, {}, ta)[0] for f in ("push_claim", "push_server_config")]
    check("U1", "Telefono registrato per le notifiche (uno per account); tabelle e funzioni del server chiuse",
          reg[0] in (200, 204) and bad[0] >= 400 and steal[0] in (200, 204) and owner_b == UID_B
          and owner_a == UID_A and all(denied(d) for d in direct) and all(x >= 400 for x in server_fns),
          f"{reg[0]}, {bad[0]}, {owner_b == UID_B}, {owner_a == UID_A}, {[d[0] for d in direct]}, {server_fns}"
          + ("" if reg[0] in (200, 204) else f" · {str(reg[1])[:300]}"))

    _, conv = rpc("chat_open_direct", {"p_user": UID_A}, tb)
    gen = int(sql(f"select generation from public.chat_conversations where id = '{conv}';") or 0)
    if gen == 0:
        sql(f"update public.chat_conversations set generation = 1 where id = '{conv}';")
        gen = 1
    rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": True,
                              "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                              "p_time_zone": "Europe/Rome"}, ta)

    def send() -> int:
        return rpc("chat_send", {"p_conversation": conv, "p_generation": gen, "p_payload": b64(7)}, tb)[0]

    clear()
    s1, s2 = send(), send()
    q = queue()
    check("U2", "Messaggio → notifica per chi riceve (non per chi scrive), raggruppata, senza testo",
          s1 == 200 and s2 == 200 and len(q) == 1 and q[0].startswith("chat|")
          and q[0].endswith("|2 nuovi messaggi|2") and queue(UID_B) == [],
          f"{s1}, {s2}, {q}, {queue(UID_B)}")

    clear()
    mute = rpc("chat_set_mute", {"p_conversation": conv, "p_until": "infinity"}, ta)
    send()
    muted = queue()
    past = rpc("chat_set_mute", {"p_conversation": conv, "p_until": "2020-01-01T00:00:00Z"}, ta)
    rpc("chat_set_mute", {"p_conversation": conv, "p_until": None}, ta)
    send()
    check("U3", "Chat silenziata: nessuna notifica; riattivata: di nuovo",
          mute[0] in (200, 204) and muted == [] and past[0] >= 400 and len(queue()) == 1,
          f"{mute[0]}, {muted}, {past[0]}, {queue()}")

    clear()
    now_rome = sql("select to_char(now() at time zone 'Europe/Rome', 'HH24:MI');")
    hour = int(now_rome[:2])
    dnd = rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": True,
                                    "p_dnd_enabled": True, "p_dnd_from": f"{(hour - 1) % 24:02d}:00",
                                    "p_dnd_to": f"{(hour + 2) % 24:02d}:00", "p_time_zone": "Europe/Rome"}, ta)
    send()
    quiet = queue()
    bad_tz = rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True,
                                       "p_preview": True, "p_dnd_enabled": False, "p_dnd_from": "22:00",
                                       "p_dnd_to": "07:00", "p_time_zone": "Luna/Base"}, ta)
    rpc("push_set_settings", {"p_messages": False, "p_comments": True, "p_market": True, "p_preview": False,
                              "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                              "p_time_zone": "Europe/Rome"}, ta)
    send()
    off = queue()
    rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": False,
                              "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                              "p_time_zone": "Europe/Rome"}, ta)
    send()
    hidden = queue()
    check("U4", "Non disturbare e messaggi spenti: nessuna notifica; senza anteprima nemmeno il nome",
          dnd[0] in (200, 204) and quiet == [] and bad_tz[0] >= 400 and off == []
          and hidden == ["chat|Piazly|Hai un nuovo messaggio|1"],
          f"{dnd[0]}, {quiet}, {bad_tz[0]}, {off}, {hidden}")
    rpc("push_set_settings", {"p_messages": True, "p_comments": True, "p_market": True, "p_preview": True,
                              "p_dnd_enabled": False, "p_dnd_from": "22:00", "p_dnd_to": "07:00",
                              "p_time_zone": "Europe/Rome"}, ta)

    clear()
    listing = sql("select id from public.listings order by created_at limit 1;")
    likes = comments = []
    if listing:
        sql("insert into public.notifications (recipient_id, kind, listing_id, actor_id) values "
            f"('{UID_A}', 'listing_like', '{listing}', '{UID_B}');")
        likes = queue()
        sql("insert into public.notifications (recipient_id, kind, listing_id, actor_id) values "
            f"('{UID_A}', 'listing_comment', '{listing}', '{UID_B}');")
        comments = queue()
    check("U5", "Mi piace: nessuna notifica; commento: notifica «ha commentato il tuo annuncio»",
          bool(listing) and likes == [] and len(comments) == 1 and comments[0].startswith("comment|Piazly|")
          and "ha commentato il tuo annuncio" in comments[0],
          f"{bool(listing)}, {likes}, {comments}")

    claimed = sql("select count(*) from public.push_claim(50);")
    left = sql("select count(*) from private.push_queue;")
    check("U6", "La funzione del server prende le notifiche (una per telefono) e svuota la coda",
          claimed == "1" and left == "0", f"{claimed}, {left}")


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
    check_chat_media_phase4()
    check_chat_groups_phase4()
    check_push_phase4()
    check_backup_phase4()
    check_chat_reports_phase4()
    check_calls_phase4()
    check_realtime_phase4()
    check_preview_phase4()
    check_group_calls_phase4()
    check_contact_names_phase4()
    check_presence_phase4()
    check_statuses_phase4()
    check_live_location_phase4()
    check_ai_limits_phase4()
    check_business_phase6()
    check_subscriptions_phase6()
    check_promotions_phase6()
    check_reviews_phase6()
    check_admin_phase7()
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
