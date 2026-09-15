#!/usr/bin/env python3
"""Export sample-data screenshots from the built Debug app, plus a gallery and ZIP."""
import base64
import html
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
executable = root / "build/Build/Products/Debug/Icinga Status.app/Contents/MacOS/Icinga Status"
output = root / "build/screenshots"
output.mkdir(parents=True, exist_ok=True)

states = [
    ("healthy", "All healthy"),
    ("warnings", "Service warnings"),
    ("critical", "Hosts down and critical services"),
    ("mixed", "Mixed incidents"),
    ("connectionFailure", "API connection failures"),
]
captures = []
for scenario, title in states:
    captures.append((f"menu-bar-{scenario}", title, "Menu bar", ["--preview-menubar", "--scenario", scenario]))
for scenario, title in states:
    captures.append((f"overview-{scenario}", title, "Open panel", ["--preview-integration", "--scenario", scenario]))
for tab in ["hosts", "services"]:
    captures.append((tab, tab.title(), "Panel tabs", ["--preview-integration", f"--preview-{tab}", "--scenario", "mixed"]))
for tab in ["instances", "monitoring", "notifications", "general"]:
    captures.append((f"settings-{tab}", tab.title(), "Settings", ["--preview-settings", f"--preview-{tab}"]))
captures.append(("about", "About Icinga Status", "About", ["--preview-about"]))

images = []
for appearance in ["light", "dark"]:
    for name, title, section, arguments in captures:
        args = [str(executable), "--demo", "--capture-preview-stdout", *arguments]
        if appearance == "dark":
            args.append("--preview-dark")
        result = subprocess.run(args, capture_output=True, text=True, check=True, timeout=30)
        encoded = [line.removeprefix("Preview PNG: ") for line in result.stdout.splitlines()
                   if line.startswith("Preview PNG: ")]
        if len(encoded) != 1:
            raise SystemExit(f"No unique PNG received for {name} ({appearance}).")
        data = base64.b64decode(encoded[0], validate=True)
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise SystemExit(f"Invalid PNG for {name} ({appearance}).")
        filename = f"{name}-{appearance}.png"
        (output / filename).write_bytes(data)
        images.append((filename, title, section, appearance))
        print(f"Captured {filename}", flush=True)

cards = []
for section in ["Menu bar", "Open panel", "Panel tabs", "Settings", "About"]:
    cards.append(f"<h2>{html.escape(section)}</h2><div class='grid'>")
    for filename, title, group, appearance in images:
        if group != section:
            continue
        caption = html.escape(f"{title} · {appearance.title()}")
        cards.append(f"<figure><a href='{filename}'><img loading='lazy' src='{filename}' alt='{caption}'></a>"
                     f"<figcaption>{caption} <a href='{filename}' download>Download PNG</a></figcaption></figure>")
    cards.append("</div>")

(output / "index.html").write_text("""<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Icinga Status screenshots</title>
<style>
:root { color-scheme: light dark; font: 15px/1.55 system-ui, sans-serif; }
body { max-width: 1500px; margin: 40px auto; padding: 0 24px; }
h1 { margin-bottom: 8px; } h2 { margin-top: 48px; }
p { max-width: 800px; } a { color: light-dark(#005ec4, #87bfff); }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 480px), 1fr)); gap: 24px; }
figure { margin: 0; padding: 20px; border: 1px solid light-dark(#ddd, #444); border-radius: 12px; }
img { display: block; max-width: 100%; height: auto; margin: auto; }
figcaption { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px; margin-top: 16px; }
</style>
<h1>Icinga Status screenshots</h1>
<p>Native app views captured with development sample data in light and dark appearances.
Menu bar context uses representative macOS controls. Development scenario controls remain visible
in the panel. Click any image for the full resolution PNG.</p>
""" + "\n".join(cards) + "\n</html>\n")

archive = root / "build/icinga-status-screenshots.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
    for filename in ["index.html", *(image[0] for image in images)]:
        bundle.write(output / filename, arcname=f"icinga-status-screenshots/{filename}")
print(f"Saved {len(images)} PNGs, gallery: {output / 'index.html'}, archive: {archive}", flush=True)
