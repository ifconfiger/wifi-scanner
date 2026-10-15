# /// script
# dependencies = ["pillow>=10", "numpy"]
# ///
"""Generate the WiFi-Viewer icon: dark rounded tile + channel spectrum curves for three bands.
Usage: uv run tools/make_icon.py  →  Resources/AppIcon.icns + Resources/AppIcon.png"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # 2x supersampling, downscaled to 1024 at the end
ROOT = Path(__file__).resolve().parent.parent / "Resources"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background():
    # macOS icon grid: 824×824 body on a 1024 canvas, corner radius ≈ 185
    inset, radius = int(S * 100 / 1024), int(S * 185 / 1024)
    grad = Image.new("RGBA", (S, S))
    top, bottom = (24, 38, 82), (8, 13, 32)
    px = np.zeros((S, S, 4), dtype=np.uint8)
    t = np.linspace(0, 1, S)[:, None]
    for i in range(3):
        px[..., i] = (top[i] + (bottom[i] - top[i]) * t).astype(np.uint8)
    px[..., 3] = 255
    grad = Image.fromarray(px, "RGBA")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, S - inset, S - inset), radius, fill=255)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Drop shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (inset, inset + 24, S - inset, S - inset + 24), radius, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    canvas.paste(grad, (0, 0), mask)
    return canvas, mask, inset


def main():
    canvas, mask, inset = background()
    body = (inset, inset, S - inset, S - inset)
    w = body[2] - body[0]
    left, right = body[0] + w * 0.10, body[2] - w * 0.10
    base_y = body[1] + w * 0.80

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # Grid lines
    for k in range(1, 5):
        y = base_y - k * w * 0.13
        d.line((left, y, right, y), fill=(120, 150, 220, 38), width=4)

    # Three spectra: 2.4 GHz orange, 5 GHz blue, 6 GHz purple (matches the in-app colors)
    bands = [
        (0.24, 0.13, 0.50, (255, 159, 10)),
        (0.52, 0.17, 0.66, (10, 132, 255)),
        (0.79, 0.12, 0.38, (191, 90, 242)),
    ]
    xs = np.linspace(left, right, 900)
    for cx, half, height, color in bands:
        c = left + (right - left) * cx
        hw = (right - left) * half
        ys = base_y - height * w * np.exp(-((xs - c) / hw) ** 6)  # Flat-topped curve, like a Wi-Fi channel spectrum
        keep = (base_y - ys) > 2  # Keep only the raised part so the curve doesn't run along the baseline
        pts = list(zip(xs[keep], ys[keep]))
        pts = [(pts[0][0], base_y)] + pts + [(pts[-1][0], base_y)]
        fill = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(fill).polygon(pts, fill=color + (95,))
        layer.alpha_composite(fill)
        glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(glow).line(pts, fill=color + (200,), width=68, joint="curve")
        layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26)))
        ImageDraw.Draw(layer).line(pts, fill=color + (255,), width=36, joint="curve")

    # Thick strokes overshoot the baseline at their ends; trim everything below it
    ImageDraw.Draw(layer).rectangle((0, base_y + 8, S, S), fill=(0, 0, 0, 0))
    ImageDraw.Draw(layer).line((left, base_y, right, base_y), fill=(170, 195, 245, 200), width=16)

    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), Image.composite(layer.getchannel("A"), Image.new("L", (S, S), 0), mask))
    canvas.alpha_composite(clipped)

    # Top highlight
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle(body, int(S * 185 / 1024), outline=(255, 255, 255, 45), width=6)
    canvas.alpha_composite(hl)

    icon = canvas.resize((1024, 1024), Image.LANCZOS)
    ROOT.mkdir(exist_ok=True)
    icon.save(ROOT / "AppIcon.png")
    icon.save(ROOT / "AppIcon.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("ok", ROOT / "AppIcon.icns")


if __name__ == "__main__":
    main()
