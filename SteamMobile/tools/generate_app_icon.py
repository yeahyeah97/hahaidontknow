#!/usr/bin/env python3
"""Create Steam Mobile's original dark-blue iOS home-screen icon.

An independent source-drawn illustration using Pillow; no copyrighted Steam
or Apple artwork is redistributed as a binary asset. The white geometry is a
Steam-inspired mechanical linkage with a small Apple-shaped badge. The artwork
is intended only as user-requested personal app branding.
"""
from pathlib import Path
import json
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

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
    def ell(box,fill,outline=None,width=1):draw.ellipse(tuple(c(x) for x in box),fill=fill,outline=outline,width=c(width))
    # Soft neon bezel and a square iOS-safe margin (iOS masks its app icons).
    draw.rounded_rectangle((c(.045),c(.045),c(.955),c(.955)),radius=c(.19),outline="#006cf4",width=c(.008))
    draw.rounded_rectangle((c(.059),c(.059),c(.941),c(.941)),radius=c(.18),outline="#1d88ff",width=c(.002))
    white = "#f8fbff"
    # Steam-inspired linkage (independent vector redraw, not a packaged logo asset).
    draw.line([(c(-.07),c(.33)),(c(.29),c(.54)),(c(.61),c(.34))],fill=white,width=c(.125),joint="curve")
    ell((.49,.16,.84,.51),white)
    ell((.54,.21,.79,.46),"#092047")
    ell((.59,.26,.74,.41),white)
    ell((.18,.47,.43,.72),white)
    ell((.23,.52,.38,.67),"#092047")
    # Tiny Apple-shaped badge in lower-right: rounded silhouette + detached leaf.
    apple=[(.745,.755),(.721,.719),(.704,.671),(.711,.628),(.733,.601),
           (.758,.595),(.779,.605),(.807,.594),(.835,.602),(.850,.628),
           (.842,.672),(.824,.724),(.801,.754),(.785,.751),(.770,.746)]
    draw.polygon([(c(x),c(y)) for x,y in apple],fill=white)
    draw.ellipse((c(.786),c(.566),c(.818),c(.590)),fill=white)
    draw.polygon([(c(.814),c(.607)),(c(.848),c(.603)),(c(.847),c(.641)),(c(.822),c(.636))],fill="#082145")
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
