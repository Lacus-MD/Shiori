#!/usr/bin/env python3
"""Draws the layers of Shiori's app icon (Shiori/Resources/ShioriIcon.icon).

The mark: three rows of a sidebar in washi cream on the icon's ink
background, the middle one lit, and a vermilion bookmark ribbon (栞, shiori)
hanging down across it — your place, marked. Layers are drawn at 4x and
scaled down for clean edges. Run from the repository root:

    python3 Design/make_icon.py            # writes the .icon assets
    python3 Design/make_icon.py --preview  # also writes Design/icon-preview.png
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4
ICON = Path("Shiori/Resources/ShioriIcon.icon")

CREAM = (244, 234, 216)
INK = (27, 29, 44)
VERMILION = (226, 72, 52)
VERMILION_DARK = (178, 44, 34)

ROW_X = (214, 810)
ROW_H = 112
ROW_CENTERS = (340, 512, 684)
RIBBON_X = (612, 712)
RIBBON_BOTTOM = 880
NOTCH = 64


def canvas():
    return Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))


def s(v):
    return int(round(v * SCALE))


def finish(img):
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def rows():
    img = canvas()
    d = ImageDraw.Draw(img)
    for i, cy in enumerate(ROW_CENTERS):
        lit = i == 1
        top, bottom = cy - ROW_H / 2, cy + ROW_H / 2
        fill = CREAM + ((255,) if lit else (46,))
        d.rounded_rectangle([s(ROW_X[0]), s(top), s(ROW_X[1]), s(bottom)], radius=s(ROW_H / 2), fill=fill)
        # A glyph and a name, like a sidebar entry.
        mark = INK + (255,) if lit else CREAM + (120,)
        r = 26
        gx = ROW_X[0] + 66
        d.rounded_rectangle([s(gx - r), s(cy - r), s(gx + r), s(cy + r)], radius=s(10), fill=mark)
        bar_end = ROW_X[0] + (330 if lit else 290)
        d.rounded_rectangle([s(gx + 52), s(cy - 13), s(bar_end), s(cy + 13)], radius=s(13), fill=mark)
    return finish(img)


def ribbon():
    img = canvas()
    d = ImageDraw.Draw(img)
    x0, x1 = RIBBON_X
    mid = (x0 + x1) / 2
    shape = [(s(x0), s(-20)), (s(x1), s(-20)), (s(x1), s(RIBBON_BOTTOM)),
             (s(mid), s(RIBBON_BOTTOM - NOTCH)), (s(x0), s(RIBBON_BOTTOM))]
    d.polygon(shape, fill=VERMILION + (255,))
    # A soft fold along the left edge gives the silk some body.
    fold = canvas()
    fd = ImageDraw.Draw(fold)
    fd.polygon([(s(x0 - 10), s(-20)), (s(x0 + 26), s(-20)), (s(x0 + 26), s(RIBBON_BOTTOM - 16)), (s(x0 - 10), s(RIBBON_BOTTOM))],
               fill=VERMILION_DARK + (95,))
    fold = fold.filter(ImageFilter.GaussianBlur(s(14)))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(shape, fill=255)
    img.paste(Image.alpha_composite(img, fold), (0, 0), mask)
    return finish(img)


def icon_json():
    tinted_glass = [{"value": False}, {"appearance": "tinted", "value": True}]
    return {
        "fill-specializations": [
            {"value": {"linear-gradient": ["extended-srgb:0.168627,0.180392,0.270588,1",
                                           "extended-srgb:0.074510,0.078431,0.121569,1"]}},
            {"appearance": "dark", "value": {"linear-gradient": ["extended-srgb:0.168627,0.180392,0.270588,1",
                                                                  "extended-srgb:0.074510,0.078431,0.121569,1"]}},
            {"appearance": "tinted", "value": "system-dark"},
        ],
        "groups": [
            {
                "name": "Bookmark ribbon",
                "layers": [{"name": "Ribbon", "image-name": "ribbon.png", "glass-specializations": tinted_glass}],
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency-specializations": [{"value": {"enabled": False, "value": 0}},
                                                 {"appearance": "tinted", "value": {"enabled": True, "value": 0.2}}],
            },
            {
                "name": "Sidebar rows",
                "layers": [{"name": "Rows", "image-name": "rows.png", "glass-specializations": tinted_glass}],
                "shadow": {"kind": "neutral", "opacity": 0.12},
                "translucency-specializations": [{"value": {"enabled": False, "value": 0}},
                                                 {"appearance": "tinted", "value": {"enabled": True, "value": 0.35}}],
            },
        ],
        "supported-platforms": {"squares": "shared"},
    }


def preview(layers):
    """A flat look at the icon: gradient, squircle mask, layers."""
    bg = Image.new("RGBA", (SIZE, SIZE))
    top, bottom = (43, 46, 69), (19, 20, 31)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        ImageDraw.Draw(bg).line([(0, y), (SIZE, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    for layer in layers:
        bg = Image.alpha_composite(bg, layer)
    mask = Image.new("L", (SIZE * SCALE, SIZE * SCALE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE * SCALE - 1, SIZE * SCALE - 1], radius=s(230), fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask.resize((SIZE, SIZE), Image.LANCZOS))
    return out


def main():
    assets = ICON / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    layers = [rows(), ribbon()]
    layers[0].save(assets / "rows.png")
    layers[1].save(assets / "ribbon.png")
    (ICON / "icon.json").write_text(json.dumps(icon_json(), indent=2) + "\n")
    if "--preview" in sys.argv:
        preview(layers).save("Design/icon-preview.png")


if __name__ == "__main__":
    main()
