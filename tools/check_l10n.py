# /// script
# requires-python = ">=3.10"
# ///
"""Check that every localizable string in the code has a Simplified Chinese translation.

Usage: uv run tools/check_l10n.py
Builds with `-emit-localized-strings` to collect the keys the compiler sees (String(localized:),
Text("..."), Button("..."), …) and compares them with Resources/zh-Hans.lproj/Localizable.strings.
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
ZH = ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings"

# Keys that read the same in both languages (units, identifiers, symbols)
SAME = {"", "—", "dBm", "SSID", "BSSID", "WiFi-Scanner", "%lld", "%lld dBm", "%lld dB", "%lld MHz", "ch%lld · %lld dBm"}


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

    zh = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", str(ZH)],
                                   capture_output=True, check=True).stdout)
    missing = {k: loc for k, loc in keys.items() if k not in zh and k not in SAME}
    unused = sorted(set(zh) - set(keys))
    for k, loc in missing.items():
        print(f"missing  {loc}  {k!r}")
    for k in unused:
        print(f"unused   {k!r}")
    print(f"{len(keys)} keys, {len(missing)} missing, {len(unused)} unused")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
