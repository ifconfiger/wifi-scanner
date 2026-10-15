# /// script
# requires-python = ">=3.10"
# ///
"""Check that every localizable string in the code is translated in every language.

Usage: uv run tools/check_l10n.py
Builds with `-emit-localized-strings` to collect the keys the compiler sees (String(localized:),
Text("..."), Button("..."), …) and compares them with each Resources/<lang>.lproj/Localizable.strings (+ .stringsdict for plurals).
Exits non-zero when translations are missing.
"""
import glob
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "Resources"

# Keys that read the same in every language (units, identifiers, symbols)
SAME = {"", "—", "dBm", "SSID", "BSSID", "WiFi-Viewer", "%lld", "%lld dBm", "%lld dB", "%lld MHz", "ch%lld · %lld dBm"}


def main() -> int:
    env = dict(os.environ)
    xcode = "/Applications/Xcode.app/Contents/Developer"
    if "DEVELOPER_DIR" not in env and pathlib.Path(xcode).exists():
        env["DEVELOPER_DIR"] = xcode
    with tempfile.TemporaryDirectory() as out:
        subprocess.run(
            ["swift", "build", "-c", "release",
             "-Xswiftc", "-emit-localized-strings", "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", out],
            cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL,
        )
        keys: dict[str, str] = {}
        for f in sorted(glob.glob(f"{out}/*.stringsdata")):
            data = json.load(open(f))
            for entries in data.get("tables", {}).values():
                for e in entries:
                    keys.setdefault(e["key"], f"{pathlib.Path(data['source']).name}:{e['location']['startingLine']}")

    failed = False
    for lproj in sorted(RES.glob("*.lproj")):
        lang = lproj.stem
        if lang == "en":
            continue
        tr: set[str] = set()
        for name in ("Localizable.strings", "Localizable.stringsdict"):
            if (lproj / name).exists():
                tr |= set(load(lproj / name))
        missing = {k: loc for k, loc in keys.items() if k not in tr and k not in SAME}
        unused = sorted(tr - set(keys))
        for k, loc in missing.items():
            print(f"{lang}: missing  {loc}  {k!r}")
        for k in unused:
            print(f"{lang}: unused   {k!r}")
        print(f"{lang}: {len(keys)} keys, {len(missing)} missing, {len(unused)} unused")
        failed |= bool(missing)
    return 1 if failed else 0


def load(path: pathlib.Path) -> dict:
    return json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                                     capture_output=True, check=True).stdout)


if __name__ == "__main__":
    sys.exit(main())
