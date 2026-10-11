#!/usr/bin/env python3
"""Render the user's personal Steam/Apple icon from versioned vector geometry.

See assets/brand/README.md for source provenance and trademark status.
"""
from pathlib import Path
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw


def brand_path(name, x, y, size):
    """Render the M/L/H/V/C/S/Z subset used by these pinned SVGs via Pillow.

    Keeping the source paths avoids hand-drawn approximations and extra native
    rasterizer dependencies in CI. Unsupported path commands fail closed.
    """
    root = ET.parse(Path(__file__).resolve().parents[1] / 'assets/brand' / (name + '.svg')).getroot()
    if root.attrib['viewBox'] != '0 0 24 24':
        raise ValueError('Unexpected vector coordinate system')
    path = ImageDraw.Outline()
    def pixels(point): return (x + point[0] * size / 24, y + point[1] * size / 24)
    for shape in root.findall('{http://www.w3.org/2000/svg}path'):
        tokens = re.findall(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', shape.attrib['d'])
        pos = 0; command = None; current = (0., 0.); origin = current; previous = ''; control = None
        while pos < len(tokens):
            if tokens[pos].isalpha():
                command = tokens[pos]; pos += 1
            if command is None:
                raise ValueError('Missing SVG command')
            kind = command.upper()
            if kind == 'Z':
                path.close(); current = origin; control = None; previous = kind; command = None
                continue
            counts = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4}
            if kind not in counts:
                raise ValueError(f'Unsupported SVG command: {command}')
            count = counts[kind]
            values = list(map(float, tokens[pos:pos + count])); pos += count
            if len(values) != count:
                raise ValueError('Truncated SVG command')
            relative = command.islower()
            def point(a, b):
                return (a + current[0], b + current[1]) if relative else (a, b)
            if kind == 'H': end = (values[0] + (current[0] if relative else 0), current[1])
            elif kind == 'V': end = (current[0], values[0] + (current[1] if relative else 0))
            else: end = point(*values[-2:])
            if kind == 'M':
                path.move(*pixels(end)); origin = end
                command = 'l' if relative else 'L'
            elif kind in ('L', 'H', 'V'): path.line(*pixels(end))
            else:
                first = point(*values[:2]) if kind == 'C' else (
                    (2 * current[0] - control[0], 2 * current[1] - control[1])
                    if previous in ('C', 'S') and control is not None else current)
                second = point(*values[-4:-2])
                path.curve(*pixels(first), *pixels(second), *pixels(end))
                control = second
            if kind not in ('C', 'S'): control = None
            current = end; previous = kind
        path.close()
    return path

def icon(size=1024):
    scale = 2
    w = size * scale
    im = Image.new("RGB", (w, w), "#040d20")
    p = im.load()
    for y in range(w):
        for x in range(w):
            nx, ny = x / w, y / w
            glow = max(0, 1 - math.hypot(nx - .18, ny - .08) / 1.25)
            p[x,y] = (int(3+4*glow), int(9+30*glow), int(27+94*glow))
    draw = ImageDraw.Draw(im)
    def c(v):return round(v*w)
    # Soft neon bezel and a square iOS-safe margin (iOS masks its app icons).
    draw.rounded_rectangle((c(.045),c(.045),c(.955),c(.955)),radius=c(.19),outline="#006cf4",width=c(.008))
    draw.rounded_rectangle((c(.059),c(.059),c(.941),c(.941)),radius=c(.18),outline="#1d88ff",width=c(.002))
    white = "#f8fbff"
    draw.shape(brand_path('steam', c(.14), c(.13), c(.69)), fill=white)
    draw.shape(brand_path('apple', c(.745), c(.735), c(.16)), fill=white)
    return im.resize((size,size),Image.Resampling.LANCZOS)

def main():
    root=Path(sys.argv[1]) if len(sys.argv)>1 else Path("app/Madeira/Assets.xcassets/AppIcon.appiconset")
    root.mkdir(parents=True,exist_ok=True)
    # The upstream source already contains AppIcon-1024.png. If left in
    # the catalog after rewriting Contents.json it becomes an unassigned
    # image and Xcode warns on every build. This is only the temp clone.
    for stale in root.glob("*.png"):
        if stale.name != "SteamMobile1024.png":
            stale.unlink()
    image=icon()
    image.save(root/"SteamMobile1024.png",optimize=True)
    (root/"Contents.json").write_text(json.dumps({
        "images":[{"filename":"SteamMobile1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],
        "info":{"author":"xcode","version":1}},indent=2)+"\n")
    print("Steam Mobile icon generated:",root/"SteamMobile1024.png")
if __name__=="__main__":main()
