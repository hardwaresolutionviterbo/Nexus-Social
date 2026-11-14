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
            prefer: str | None = None) -> tuple[int, object]:
    headers = {"apikey": ANON, "Content-Type": "application/json"}
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


def rpc(name, args, jwt=None):
    return request("POST", f"/rest/v1/rpc/{name}", jwt=jwt, body=args)


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


def storage(method: str, path: str, jwt: str | None, data: bytes | None = None) -> int:
    """Chiamata allo Storage temporaneo; restituisce solo lo stato HTTP."""
    headers = {"apikey": ANON, "Content-Type": "image/jpeg"}
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


def main() -> int:
    try:
        ids = setup()
    except Exception as exc:  # noqa: BLE001
        print(f"::error::Preparazione dei dati di prova fallita: {exc}")
        return 1
    run(ids)
    check_profile_block2()
    check_privacy_block3()
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
