#!/usr/bin/env python3
"""Build the iOS Surge icon from the ORIGINAL neon artwork selected for the app.

Unlike the previous procedural icon, this reads the neon artwork itself. The
source is a compressed RGB WebP rendition of the generated power-strip design;
1024px PNG is produced for Xcode's AppIcon and the FlareStore release asset.
"""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = root / "Art" / "surge-neon-original.webp"
dest = root / "Sources" / "Assets.xcassets" / "AppIcon.appiconset" / "surge.png"
if not source.is_file():
    raise SystemExit("Missing original neon icon. Refusing to substitute artwork.")
with Image.open(source) as image:
    im = image.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
dest.parent.mkdir(parents=True, exist_ok=True)
im.save(dest, format="PNG", optimize=True)
print(f"Surge icon: {source} -> {dest}")
