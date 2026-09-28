#!/usr/bin/env python3
"""Compose App Store marketing screenshots from raw UITest captures.

Setup (venv intentionally outside the repo):
    python3 -m venv /tmp/hy-venv && /tmp/hy-venv/bin/pip install pillow

Usage:
    /tmp/hy-venv/bin/python scripts/store_screenshots.py --raw /tmp/hy-raw --out ios/StoreAssets/screenshots

Expects raw captures at <raw>/iphone/<name>.png (1320x2868) and <raw>/ipad/<name>.png
(2064x2752). Writes finished PNGs into <out>/iphone-6.9/, <out>/iphone-6.5/ and
<out>/ipad-13/ plus preview-iphone.png / preview-ipad.png contact sheets.
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Brand colors sampled from ios/App/AppState.swift (Design.green / Design.ink family).
GRADIENT_TOP = (0x0E, 0x3D, 0x2B)
GRADIENT_BOTTOM = (0x06, 0x1B, 0x13)
GLOW_COLOR = (0x2A, 0x8A, 0x5E)
GLOW_ALPHA = 0.35
SUB_COLOR = (0xCF, 0xE8, 0xDA)
BRAND_COLOR = (0x8F, 0xCB, 0xA8)
BEZEL_COLOR = (0x0B, 0x0B, 0x0C)
STROKE_COLOR = (0x3A, 0x3A, 0x3C)

# (output name, raw capture name, headline, subheadline)
SHOTS = [
    ("01-iyiyim", "02-ana-ekran", "Bir dokunuşla\n“İyiyim” deyin",
     "Her gün tek dokunuş. Telefon numarası, SMS gerekmez."),
    ("02-ailem", "04-ailem", "Takip değil,\nhaber",
     "Konum yok, ölçüm yok. Sadece “bugün iyiyim”."),
    ("03-rahat", "03-haber-verildi", "Aileniz\niçi rahat",
     "Haberiniz kaydedilir; yakınlarınız uygulamada anında görür."),
    ("04-davet", "05-davet", "Yakınınızı\nbir kodla ekleyin",
     "QR veya 12 haneli kod. 48 saat geçerli, tek kullanımlık."),
    ("05-saat", "06-kontrol-saati", "Saati siz\nbelirleyin",
     "Hatırlatma saati ve bekleme süresi sizin elinizde."),
    ("06-baslangic", "01-giris", "Adınızı yazın,\nbaşlayın",
     "Hesabınız bu cihaz için saniyeler içinde oluşur."),
]

# Per-canvas layout. s scales every spec number to the canvas width.
CANVASES = {
    "iphone-6.9": dict(raw="iphone", W=1320, H=2868, s=1320 / 1320,
                       screen_w=1040, screen_r=150, bezel=26, bezel_r=176,
                       island=True, headline=104, sub=46),
    "iphone-6.5": dict(raw="iphone", W=1284, H=2778, s=1284 / 1320,
                       screen_w=1040, screen_r=150, bezel=26, bezel_r=176,
                       island=True, headline=104, sub=46),
    "ipad-13": dict(raw="ipad", W=2064, H=2752, s=2064 / 2064,
                    screen_w=1500, screen_r=90, bezel=34, bezel_r=90 + 34,
                    island=False, headline=120, sub=54),
}

SF_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
AVENIR_NEXT = "/System/Library/Fonts/Avenir Next.ttc"


def load_font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    """SF Rounded at the given variable weight; Avenir Next fallback."""
    for path in (SF_ROUNDED, "/System/Library/Fonts/SFNS.ttf"):
        if not os.path.exists(path):
            continue
        try:
            font = ImageFont.truetype(path, size)
        except Exception:
            continue
        try:
            names = [n.decode() if isinstance(n, bytes) else n for n in font.get_variation_names()]
        except Exception:
            return font
        if weight in names:
            try:
                font.set_variation_by_name(weight)
                return font
            except Exception:
                pass
        for fallback in (["Regular"] if weight == "Medium" else []):
            if fallback in names:
                try:
                    font.set_variation_by_name(fallback)
                    return font
                except Exception:
                    pass
        return font
    if os.path.exists(AVENIR_NEXT):
        regular = None
        for index in range(64):
            try:
                face = ImageFont.truetype(AVENIR_NEXT, size, index=index)
            except Exception:
                break
            style = (face.getname()[1] or "").lower()
            if weight == "Bold" and style == "bold":
                return face
            if weight == "Medium" and style == "medium":
                return face
            if style in ("regular", "book") and regular is None:
                regular = face
        return regular or ImageFont.truetype(AVENIR_NEXT, size)
    return ImageFont.load_default()


def vertical_gradient(w: int, h: int, top, bottom) -> Image.Image:
    column = Image.new("RGB", (1, h))
    px = column.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return column.resize((w, h), Image.BICUBIC)


def glow_alpha(w: int, h: int, cx: float, cy: float, radius: float) -> Image.Image:
    """Soft quadratic radial falloff, computed small then upscaled."""
    sw, sh = max(1, w // 8), max(1, h // 8)
    mask = Image.new("L", (sw, sh))
    px = mask.load()
    scx, scy, sr = cx / 8, cy / 8, radius / 8
    for y in range(sh):
        for x in range(sw):
            v = max(0.0, 1.0 - math.hypot(x - scx, y - scy) / sr)
            px[x, y] = round(255 * GLOW_ALPHA * v * v)
    return mask.resize((w, h), Image.BICUBIC)


def rounded_mask(w: int, h: int, radius: int) -> Image.Image:
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    return mask


def wrap_lines(draw, text, font, max_w):
    lines, current = [], ""
    for word in text.split(" "):
        candidate = f"{current} {word}".strip()
        if not current or draw.textlength(candidate, font=font) <= max_w:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_centered_lines(draw, lines, font, cx, top, spacing, fill) -> float:
    """Returns the y just below the last rendered line."""
    ascent, descent = font.getmetrics()
    step = (ascent + descent) * spacing
    y = top
    for line in lines:
        w = draw.textlength(line, font=font)
        draw.text((cx - w / 2, y), line, font=font, fill=fill)
        y += step
    return y - step + ascent + descent


def draw_tracked(draw, text, font, cx, y, tracking, fill):
    widths = [draw.textlength(ch, font=font) for ch in text]
    x = cx - (sum(widths) + tracking * (len(text) - 1)) / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += w + tracking


def compose(screen: Image.Image, cfg, headline: str, sub: str) -> Image.Image:
    W, H, s = cfg["W"], cfg["H"], cfg["s"]
    canvas = vertical_gradient(W, H, GRADIENT_TOP, GRADIENT_BOTTOM).convert("RGBA")

    glow = Image.new("RGBA", (W, H), GLOW_COLOR + (0,))
    glow.putalpha(glow_alpha(W, H, 0.25 * W, 0.12 * H, 0.9 * W))
    canvas.alpha_composite(glow)

    # Device geometry (spec numbers are in units of s).
    screen_w = round(cfg["screen_w"] * s)
    screen_h = round(screen.size[1] * screen_w / screen.size[0])
    bezel = round(cfg["bezel"] * s)
    bezel_w, bezel_h = screen_w + 2 * bezel, screen_h + 2 * bezel
    bezel_x, bezel_y = round((W - bezel_w) / 2), round(720 * s)
    bezel_r = round(cfg["bezel_r"] * s)

    # Drop shadow under the bezel.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [bezel_x, bezel_y + round(34 * s), bezel_x + bezel_w, bezel_y + bezel_h + round(34 * s)],
        radius=bezel_r, fill=(0, 0, 0, round(255 * 0.45)))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(round(70 * s))))

    # Bezel + inner highlight stroke.
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle([bezel_x, bezel_y, bezel_x + bezel_w, bezel_y + bezel_h],
                           radius=bezel_r, fill=BEZEL_COLOR)
    inset = max(1, round(s))
    stroke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(stroke).rounded_rectangle(
        [bezel_x + inset, bezel_y + inset,
         bezel_x + bezel_w - inset, bezel_y + bezel_h - inset],
        radius=max(1, bezel_r - inset),
        outline=STROKE_COLOR + (round(255 * 0.40),), width=max(1, round(2 * s)))
    canvas.alpha_composite(stroke)

    # Screen with rounded corners.
    shot = screen.resize((screen_w, screen_h), Image.LANCZOS)
    sx, sy = bezel_x + bezel, bezel_y + bezel
    canvas.paste(shot, (sx, sy), rounded_mask(screen_w, screen_h, round(cfg["screen_r"] * s)))

    if cfg["island"]:
        pw, ph = round(250 * s), round(74 * s)
        cx, cy = W / 2, sy + round(28 * s)
        draw.rounded_rectangle([cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2],
                               radius=ph / 2, fill=(0, 0, 0, 255))

    # Text stack.
    draw_tracked(draw, "HERŞEY YOLUNDA", load_font(round(30 * s), "Medium"),
                 W / 2, round(110 * s), 4 * s, BRAND_COLOR)
    headline_font = load_font(round(cfg["headline"] * s), "Bold")
    bottom = draw_centered_lines(draw, headline.split("\n"), headline_font,
                                 W / 2, round(190 * s), 1.08, (255, 255, 255))
    sub_font = load_font(round(cfg["sub"] * s), "Medium")
    draw_centered_lines(draw, wrap_lines(draw, sub, sub_font, 0.82 * W), sub_font,
                        W / 2, bottom + round(36 * s), 1.15, SUB_COLOR)

    return canvas.convert("RGB")


def contact_sheet(images, path):
    thumbs = []
    height = 0
    for img in images:
        w = 400
        h = round(img.size[1] * w / img.size[0])
        thumbs.append(img.resize((w, h), Image.LANCZOS))
        height = max(height, h)
    sheet = Image.new("RGB", (400 * len(thumbs), height))
    for i, img in enumerate(thumbs):
        sheet.paste(img, (400 * i, 0))
    sheet.save(path, "PNG")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True, help="directory with iphone/ and ipad/ raw captures")
    parser.add_argument("--out", required=True, help="output directory")
    args = parser.parse_args()

    failures = []
    outputs = {}
    for size_name, cfg in CANVASES.items():
        out_dir = os.path.join(args.out, size_name)
        os.makedirs(out_dir, exist_ok=True)
        outputs[size_name] = []
        for out_name, raw_name, headline, sub in SHOTS:
            raw_path = os.path.join(args.raw, cfg["raw"], f"{raw_name}.png")
            try:
                screen = Image.open(raw_path).convert("RGBA")
            except OSError as error:
                failures.append(f"{size_name}/{out_name}: cannot open {raw_path}: {error}")
                continue
            image = compose(screen, cfg, headline, sub)
            path = os.path.join(out_dir, f"{out_name}.png")
            image.save(path, "PNG")
            expected = (cfg["W"], cfg["H"])
            if image.size != expected:
                failures.append(f"{path}: size {image.size} != {expected}")
            outputs[size_name].append(path)
            print(f"wrote {path} {image.size[0]}x{image.size[1]}")

    for size_name, preview in (("iphone-6.9", "preview-iphone.png"), ("ipad-13", "preview-ipad.png")):
        if len(outputs[size_name]) == len(SHOTS):
            sheet_path = os.path.join(args.out, preview)
            contact_sheet([Image.open(p) for p in sorted(outputs[size_name])], sheet_path)
            print(f"wrote {sheet_path}")

    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
