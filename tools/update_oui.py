# /// script
# requires-python = ">=3.10"
# ///
"""Download the IEEE MA-L (OUI-24) registry and write Resources/oui.tsv (one line per entry: 6-hex-digit OUI \t organization).

Usage: uv run tools/update_oui.py
Note: IEEE rejects browser and Python-urllib User-Agents (418 / block page); curl's UA gets through.
"""
import csv
import io
import pathlib
import urllib.request

URL = "https://standards-oui.ieee.org/oui/oui.csv"
OUT = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "oui.tsv"


def main() -> None:
    req = urllib.request.Request(URL, headers={"User-Agent": "curl/8.7.1"})
    raw = urllib.request.urlopen(req, timeout=120).read().decode("utf-8")
    rows = {}
    for r in csv.DictReader(io.StringIO(raw)):
        oui = r["Assignment"].strip().upper()
        name = " ".join(r["Organization Name"].split())
        if len(oui) == 6 and name:
            rows[oui] = name
    OUT.write_text("".join(f"{k}\t{v}\n" for k, v in sorted(rows.items())), encoding="utf-8")
    print(f"Wrote {OUT}: {len(rows)} entries")


if __name__ == "__main__":
    main()
