#!/usr/bin/env python3
"""Deterministic 1024px Surge power-strip icon. Original art, generated during CI."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math

SIZE = 1024
OUTPUT = Path(__file__).resolve().parents[1] / "Sources/Assets.xcassets/AppIcon.appiconset/surge.png"
OUTPUT.parent.mkdir(parents=True, exist_ok=True)

def color(hexval, alpha=255):
    s = hexval.strip("#")
    return tuple(int(s[i:i+2], 16) for i in (0, 2, 4)) + (alpha,)

# Dark midnight teal canvas with soft diagonal glow and no transparency.
im = Image.new("RGB", (SIZE, SIZE))
px = im.load()
for y in range(SIZE):
    for x in range(SIZE):
        t = x / SIZE * 0.24 + (1-y / SIZE) * 0.1
        glow = max(0, 1-math.hypot(x-700, y-620)/750)*.37
        px[x,y] = (int(7+7*t), int(21+25*t+42*glow), int(36+27*t+48*glow))
im = im.convert("RGBA")

streak = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
d = ImageDraw.Draw(streak)
d.arc((-450, 410, 1470, 1920), 170, 280, fill=color("#12dfc5", 85), width=18)
d.arc((-550, -1070, 1520, 1060), 20, 125, fill=color("#049cbd", 60), width=15)
im = Image.alpha_composite(im, streak.filter(ImageFilter.GaussianBlur(17)))
im = Image.alpha_composite(im, streak)

aura = Image.new("RGBA", (SIZE,SIZE), (0,0,0,0))
ImageDraw.Draw(aura).rounded_rectangle((285,128,748,930),radius=110,outline=color("#0ff5dd",165),width=24)
im = Image.alpha_composite(im, aura.filter(ImageFilter.GaussianBlur(40)))

shape = Image.new("RGBA", (SIZE,SIZE), (0,0,0,0))
d = ImageDraw.Draw(shape)
d.rounded_rectangle((489,15,544,196),radius=27,fill=color("#0c4052"),outline=color("#5efce8",180),width=9)
d.rounded_rectangle((300,114,734,932),radius=108,fill=color("#071d30"),outline=color("#54dace"),width=16)
d.rounded_rectangle((325,140,708,908),radius=89,fill=color("#0e2839"),outline=color("#1e5e67"),width=7)
for cy in (296,496,696):
    d.rounded_rectangle((391,cy-81,643,cy+81),radius=74,fill=color("#09202d"),outline=color("#20e6c4",240),width=12)
    d.rounded_rectangle((459,cy-38,481,cy+10),radius=5,fill=color("#e8ffff"),outline=color("#64e9ea"),width=2)
    d.rounded_rectangle((552,cy-38,574,cy+10),radius=5,fill=color("#e8ffff"),outline=color("#64e9ea"),width=2)
    d.rounded_rectangle((499,cy+19,534,cy+45),radius=10,fill=color("#e8ffff"),outline=color("#64e9ea"),width=2)
d.rounded_rectangle((381,802,654,891),radius=29,fill=color("#081b2b"),outline=color("#155764"),width=5)
d.rounded_rectangle((431,822,602,850),radius=7,fill=color("#092633"),outline=color("#29e9d1"),width=7)
d.rounded_rectangle((461,857,572,880),radius=10,fill=color("#081d2c"),outline=color("#29e9d1"),width=6)
d.ellipse((505,168,528,191),fill=color("#4afdd7"))
im = Image.alpha_composite(im,shape)
im.convert("RGB").save(OUTPUT,format="PNG",optimize=True)
print(OUTPUT)
