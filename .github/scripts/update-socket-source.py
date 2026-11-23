"""Keep Socket IPA releases in Keystone's existing FlareStore/AltStore feed.

Inputs: <source.json> <Socket IPA> <GitHub download URL> <release-notes.md>
Do not replace or reorder Keystone's own app entry. Read package metadata, not a guessed version.
"""
import json
import plistlib
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

source_file, ipa_file, notes_file = map(Path, [sys.argv[1], sys.argv[2], sys.argv[4]])
url = sys.argv[3]
if not url.startswith("https://github.com/soum91/keystone/releases/download/socket-build-"):
    raise SystemExit("Refusing unexpected release URL")
with zipfile.ZipFile(ipa_file) as ipa:
    name = next(n for n in ipa.namelist()
                if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist"))
    info = plistlib.loads(ipa.read(name))
if info.get("CFBundleIdentifier") != "com.soum91.socket":
    raise SystemExit("IPA bundle identifier is not Socket")

raw = json.loads(source_file.read_text(encoding="utf-8"))
apps = raw.setdefault("apps", [])
if not any(a.get("bundleIdentifier") == "com.soum91.keystone" for a in apps):
    raise SystemExit("Keystone entry missing; refusing to replace source")

notes_lines = Path(notes_file).read_text(encoding="utf-8").splitlines()
notes = "\n".join(x.strip() for x in notes_lines
                  if x.strip().startswith("- ") or "require real-device verification" in x.lower()).strip()
if not notes:
    notes = "Socket iOS app: standalone per-outlet control and native Shortcuts support; verify the power strip's hardware datapoints."

new_entry = {
    "version": info["CFBundleShortVersionString"],
    "buildVersion": str(info["CFBundleVersion"]),
    "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": notes,
    "downloadURL": url,
    "size": ipa_file.stat().st_size,
    "minOSVersion": info.get("MinimumOSVersion", "17.0"),
}
old_app = next((app for app in apps if app.get("bundleIdentifier") == "com.soum91.socket"), {})
previous = old_app.get("versions", [])
if previous and int(previous[0].get("buildVersion", 0)) > int(new_entry["buildVersion"]):
    print("A newer Surge IPA is already published; preserving the FlareStore feed.")
    raise SystemExit(0)
versions = [new_entry] + [v for v in previous if v.get("buildVersion") != new_entry["buildVersion"]]
versions = sorted(versions, key=lambda v: tuple(int(n) for n in v["version"].split(".") if n.isdigit()), reverse=True)[:25]
app = {
    "name": "Surge",
    "bundleIdentifier": "com.soum91.socket",
    "developerName": "soum91",
    "subtitle": "Power strip control and Shortcuts",
    "localizedDescription": "Surge controls the power strip through your existing Keystone ESP32 bridge or an independent Tuya Smart cloud QR login, with named outlet Shortcuts. Apple Home integration still requires a working Keystone LAN connection.",
    "iconURL": url.rsplit("/", 1)[0] + "/surge-icon.png",
    "tintColor": "34D399",
    "category": "utilities",
    "screenshotURLs": old_app.get("screenshotURLs", []),
    "versions": versions,
    "version": versions[0]["version"],
    "versionDate": versions[0]["date"],
    "versionDescription": versions[0]["localizedDescription"],
    "downloadURL": versions[0]["downloadURL"],
    "size": versions[0]["size"],
    "appPermissions": {},
}
raw["apps"] = [a for a in apps if a.get("bundleIdentifier") != "com.soum91.socket"] + [app]
source_file.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"FlareStore source: Socket {new_entry['version']} build {new_entry['buildVersion']}; Keystone retained.")
