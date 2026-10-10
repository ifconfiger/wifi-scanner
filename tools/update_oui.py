# /// script
# requires-python = ">=3.10"
# ///
"""从 IEEE 下载 MA-L (OUI-24) 注册表，生成 Resources/oui.tsv（每行：6 位十六进制 OUI \t 机构名）。

用法：uv run tools/update_oui.py
注意：IEEE 会拒绝浏览器和 Python-urllib 的 User-Agent（返回 418/拒绝页），curl 的 UA 可以通过。
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
    print(f"写入 {OUT}：{len(rows)} 条")


if __name__ == "__main__":
    main()
