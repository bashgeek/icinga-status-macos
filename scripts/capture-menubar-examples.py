#!/usr/bin/env python3
"""Capture native menu bar labels as Retina assets using the built Debug app."""
import base64
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
executable = root / "build/Build/Products/Debug/Icinga Status.app/Contents/MacOS/Icinga Status"
result = subprocess.run(
    [str(executable), "--demo", "--capture-menubar-examples-stdout"],
    capture_output=True, text=True, check=True, timeout=60,
)
captures = {}
for line in result.stdout.splitlines():
    if line.startswith("Menu bar example: "):
        capture = json.loads(line.removeprefix("Menu bar example: "))
        captures[capture["name"], capture["appearance"]] = base64.b64decode(capture["png"], validate=True)

names = [f"MenuBarExample-{mode}-{state}"
         for mode in ["browserBadge", "fullStatus", "problemCount", "icon"]
         for state in ["healthy", "problems", "unavailable"]]
expected = {(name, appearance) for name in names for appearance in ["light", "dark"]}
if set(captures) != expected:
    raise SystemExit(f"Incomplete capture: expected 24 images, received {len(captures)}. Assets unchanged.")

assets = root / "Sources/IcingaStatus/Resources/Assets.xcassets"
for name in names:
    directory = assets / f"{name}.imageset"
    directory.mkdir(exist_ok=True)
    images = []
    for appearance in ["light", "dark"]:
        filename = f"{appearance}@2x.png"
        (directory / filename).write_bytes(captures[name, appearance])
        entry = {"filename": filename, "idiom": "universal", "scale": "2x"}
        if appearance == "dark":
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(entry)
    (directory / "Contents.json").write_text(json.dumps({
        "images": images, "info": {"author": "xcode", "version": 1}
    }, indent=2) + "\n")
print("Captured 24 Retina images for 4 display styles, 3 states, and 2 appearances.")
