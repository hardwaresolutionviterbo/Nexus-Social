#!/usr/bin/env python3
"""Genera il catalogo di Scambia & Vendi dalla specifica del titolare.

Legge docs/fase5/CATALOGO_TITOLARE.md (sezione 2) e scrive:
  - supabase/migrations/0011_marketplace_catalogo_dati.sql (righe della tabella delle categorie);
  - lib/features/market/market_catalog_data.dart (stessa lista per l'app e per i test).

Gli ID sono UUID v5 calcolati dallo slug: sono identici su ogni database e non cambiano mai.
Gli slug delle sottocategorie: slug della categoria + nome senza articoli e congiunzioni.
Uso: python3 tool/marketplace/genera_catalogo.py
"""
import re
import unicodedata
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "docs/fase5/CATALOGO_TITOLARE.md"
NS = uuid.UUID("6f1c2a52-9c8e-4b4e-9b0a-70a7a2f1e5d1")  # spazio dei nomi di Piazly
STOP = {"e", "di", "per", "da", "d", "la", "il", "lo", "le", "i", "gli", "a", "con", "in"}


def slugify(text: str) -> str:
    t = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    words = [w for w in re.split(r"[^a-z0-9]+", t) if w and w not in STOP]
    return "-".join(words)


def parse():
    cats = []
    in_section = False
    for line in SPEC.read_text(encoding="utf-8").splitlines():
        if line.startswith("## 2."):
            in_section = True
            continue
        if line.startswith("## ") and in_section:
            break
        if not in_section:
            continue
        m = re.match(r"^### (\d+) – (.+) \(`([a-z0-9-]+)`\)$", line)
        if m:
            cats.append({"n": int(m.group(1)), "name": m.group(2), "slug": m.group(3), "subs": []})
        elif line.startswith("- ") and cats:
            cats[-1]["subs"].append(line[2:].strip())
    return cats


def display(name: str) -> str:
    # «MOTORI» → «Motori», «CASA E ARREDAMENTO» → «Casa e arredamento»
    return name[:1] + name[1:].lower()


def sql_text(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main():
    cats = parse()
    assert len(cats) == 19, len(cats)
    rows = []
    seen = set()
    for c in cats:
        cid = uuid.uuid5(NS, c["slug"])
        assert c["slug"] not in seen
        seen.add(c["slug"])
        rows.append((cid, None, display(c["name"]), c["slug"], c["n"] * 10))
        for i, s in enumerate(c["subs"], start=1):
            slug = f'{c["slug"]}-{slugify(s)}'
            assert slug not in seen, slug
            seen.add(slug)
            rows.append((uuid.uuid5(NS, slug), cid, s, slug, i * 10))

    sql = [
        "-- Piazly · Fase 5, Blocco 1: dati del catalogo di Scambia & Vendi.",
        "-- GENERATO da tool/marketplace/genera_catalogo.py dalla specifica del titolare",
        "-- (docs/fase5/CATALOGO_TITOLARE.md): non modificare a mano.",
        "-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.",
        "",
        "insert into public.marketplace_categories (id, parent_id, name, slug, sort_order) values",
    ]
    vals = []
    for cid, pid, name, slug, order in rows:
        vals.append(f"  ('{cid}', {('NULL' if pid is None else repr(str(pid)))}, {sql_text(name)}, '{slug}', {order})")
    sql.append(",\n".join(vals) + "\non conflict (id) do nothing;")
    (ROOT / "supabase/migrations/0011_marketplace_catalogo_dati.sql").write_text("\n".join(sql) + "\n", encoding="utf-8")

    dart = [
        "// GENERATO da tool/marketplace/genera_catalogo.py dalla specifica del titolare",
        "// (docs/fase5/CATALOGO_TITOLARE.md): non modificare a mano.",
        "",
        "import 'market_models.dart';",
        "",
        "/// Catalogo di Scambia & Vendi: 19 categorie con le loro sottocategorie.",
        "/// Il server (tabella marketplace_categories) resta il riferimento per lo stato attivo.",
        "const List<MarketCategory> builtInMarketCatalog = <MarketCategory>[",
    ]
    for cid, pid, name, slug, order in rows:
        n = name.replace("\\", "\\\\").replace("'", "\\'")
        parent = "null" if pid is None else f"'{pid}'"
        dart.append(f"  MarketCategory(id: '{cid}', parentId: {parent}, name: '{n}', slug: '{slug}', sortOrder: {order}),")
    dart.append("];")
    out = ROOT / "lib/features/market/market_catalog_data.dart"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(dart) + "\n", encoding="utf-8")
    print(f"{len(cats)} categorie, {len(rows) - len(cats)} sottocategorie")


if __name__ == "__main__":
    main()
