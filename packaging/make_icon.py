"""Builds the app icon from packaging/icon-source.png (run with any Python that
has Pillow, numpy and scipy; the app itself doesn't need them):

    python packaging/make_icon.py

Cuts the black background along the icon's rounded square, then writes
gui/app.ico (16-256 px, each size downscaled in steps and lightly sharpened),
gui/app.png (2048 px, upscaled) and gui/gamdl_gui/qml/icons/app.png (512 px).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

SRC = Path(__file__).with_name("icon-source.png")
GUI = Path(__file__).resolve().parent.parent / "gui"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else GUI.parent / "build" / "icon-preview"
OUT.mkdir(parents=True, exist_ok=True)

rgb = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)

# The icon body is a rounded square on black. Cut along an ideal rounded
# rectangle (drawn at 4x and scaled down for smooth anti-aliasing) just inside
# the bright neon rim, so no dark background clings to the edge.
L, T, R, B = 27, 21, 1227, 1228   # measured edges of the square
INSET, RADIUS, K = 3, 300, 4      # RADIUS: measured corner radius
mask = Image.new("L", (rgb.shape[1] * K, rgb.shape[0] * K), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    ((L + INSET) * K, (T + INSET) * K, (R - INSET) * K, (B - INSET) * K), radius=(RADIUS - INSET) * K, fill=255
)
alpha = np.asarray(mask.resize((rgb.shape[1], rgb.shape[0]), Image.LANCZOS)).astype(float)
clean = Image.fromarray(np.dstack([rgb, alpha]).clip(0, 255).astype(np.uint8), "RGBA")

# Square it up with a small, even margin.
box = clean.getbbox()
side = max(box[2] - box[0], box[3] - box[1])
pad = round(side * 0.015)
square = Image.new("RGBA", (side + 2 * pad,) * 2, (0, 0, 0, 0))
square.paste(clean.crop(box), (pad + (side - (box[2] - box[0])) // 2, pad + (side - (box[3] - box[1])) // 2))
master = square.resize((1024, 1024), Image.LANCZOS)


def shrink(im: Image.Image, size: int) -> Image.Image:
    """Halve with LANCZOS until close, then one final resize."""
    while im.width // 2 >= size * 1.5:
        im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
    return im.resize((size, size), Image.LANCZOS)


def scaled(size: int) -> Image.Image:
    """The full artwork, for sizes where its text is still readable."""
    return shrink(master, size)


# Small sizes (taskbar, title bar, Explorer lists) can't show the whole artwork
# legibly, so they zoom in on the words. 16-24 px show "DIE!" alone; 32-64 px
# show "DIE! Apple". size -> (zoom, centre x, centre y in the source, contrast boost 0..1)
SMALL = {
    16: (1.58, 632, 615, 1.0),
    20: (1.58, 632, 615, 1.0),
    24: (1.58, 632, 615, 0.9),
    32: (1.75, 640, 700, 0.8),
    40: (1.6, 640, 690, 0.6),
    48: (1.5, 640, 680, 0.5),
    64: (1.25, 640, 660, 0.3),
}
SRC_RGB = Image.open(SRC).convert("RGB")


def punch(im: Image.Image, k: float) -> Image.Image:
    """Darken the background mid-tones so the bright letters stand out."""
    a = np.asarray(im).astype(float) / 255
    lum = a.max(axis=2, keepdims=True)
    curve = np.clip((lum - 0.12 * k) / (1 - 0.12 * k), 0, 1) ** (1 + 0.5 * k)
    a = a * (curve / np.maximum(lum, 1e-4))
    im = Image.fromarray((a.clip(0, 1) * 255).astype(np.uint8))
    return ImageEnhance.Color(im).enhance(1 + 0.15 * k)


def small(size: int) -> Image.Image:
    zoom, cx, cy, k = SMALL[size]
    half = 1200 / zoom / 2
    cx, cy = min(max(cx, half), SRC_RGB.width - half), min(max(cy, half), SRC_RGB.height - half)
    im = punch(SRC_RGB.resize((size * 8,) * 2, Image.LANCZOS, box=(cx - half, cy - half, cx + half, cy + half)), k)
    if size <= 24:
        # Keep only the "DIE!" row; fade the rest into the icon's dark purple.
        a = np.asarray(im).astype(float)
        ys = np.arange(a.shape[0])[:, None, None] / a.shape[0]
        top, bottom, fade = 0.30, 0.67, 0.04
        m = np.clip(np.minimum((ys - (top - fade)) / fade, ((bottom + fade) - ys) / fade), 0, 1)
        im = Image.fromarray((a * m + np.array([38, 6, 52], float) * (1 - m)).clip(0, 255).astype(np.uint8))
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius=int(im.width * 0.24), fill=255)
    im = im.convert("RGBA")
    im.putalpha(mask)
    return shrink(im, size).filter(ImageFilter.UnsharpMask(radius=0.5, percent=int(60 + 60 * k), threshold=0))


sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
frames = {s: small(s) if s in SMALL else scaled(s) for s in sizes}
# The sidebar logo is drawn at about 22 px: use the readable small version.
small(64).save(GUI / "gamdl_gui" / "qml" / "icons" / "app-small.png")
frames[256].save(GUI / "app.ico", format="ICO", sizes=[(s, s) for s in sizes],
                 append_images=[frames[s] for s in sizes if s != 256], bitmap_format="png")
scaled(512).save(GUI / "gamdl_gui" / "qml" / "icons" / "app.png")
# A large copy for stores, websites and print: upscaled from the full-resolution
# cut-out (not the 1024 master) with LANCZOS, then lightly sharpened.
large = square.resize((2048, 2048), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))
large.save(GUI / "app.png")

# Preview: every size on a dark and a light taskbar colour.
sheet = Image.new("RGBA", (1100, 420), (243, 243, 243, 255))
sheet.paste(Image.new("RGBA", (1100, 210), (32, 32, 32, 255)), (0, 0))
x = 20
for s in [16, 20, 24, 32, 48, 64, 96, 128]:
    for y0 in (0, 210):
        sheet.alpha_composite(frames[s], (x, y0 + 105 - s // 2))
    x += s + 30
sheet.save(OUT / "sizes.png")
print("wrote", GUI / "app.ico", "| preview:", OUT / "sizes.png")

# The installer's top-right picture, at each size Windows uses for 100-250% scaling.
wizard = GUI.parent / "packaging" / "wizard"
wizard.mkdir(exist_ok=True)
for px in (55, 64, 69, 83, 92, 110, 138):
    canvas = Image.new("RGBA", (px, px), (255, 255, 255, 255))   # wizard header is white
    canvas.alpha_composite(small(64).resize((px, px), Image.LANCZOS) if px < 80 else scaled(px))
    canvas.convert("RGB").save(wizard / f"small-{px}.bmp")
print("wrote installer header images in", wizard)

# The installer's side panel (first and last pages), at each size Windows uses
# for 100-250% scaling: purple gradient, the icon, the name and its meaning.
from PIL import ImageFont

FONTS = Path("C:/Windows/Fonts")


def side_panel(w: int, h: int) -> Image.Image:
    y = np.linspace(0, 1, h)[:, None]
    top, bottom = np.array([28, 6, 40], float), np.array([74, 10, 92], float)
    grad = top + (bottom - top) * y
    img = np.repeat(grad[:, None, :], w, axis=1).reshape(h, w, 3)
    # soft magenta glow behind the icon
    yy, xx = np.mgrid[0:h, 0:w]
    glow = np.exp(-(((xx - w / 2) / (w * 0.55)) ** 2 + ((yy - h * 0.38) / (h * 0.28)) ** 2))
    img = img + glow[..., None] * np.array([120, 20, 110], float) * 0.55
    panel = Image.fromarray(img.clip(0, 255).astype(np.uint8)).convert("RGBA")
    icon_px = int(w * 0.72)
    icon = scaled(icon_px)
    panel.alpha_composite(icon, ((w - icon_px) // 2, int(h * 0.38 - icon_px / 2)))
    draw = ImageDraw.Draw(panel)
    title = ImageFont.truetype(str(FONTS / "YuGothB.ttc"), int(w * 0.135))
    sub = ImageFont.truetype(str(FONTS / "segoeui.ttf"), int(w * 0.075))
    ty = int(h * 0.38 + icon_px / 2 + w * 0.09)
    for text, font, colour, gap in (("死ねアップル", title, (255, 255, 255), w * 0.06), ("Die, Apple.", sub, (230, 190, 245), 0)):
        bw = draw.textlength(text, font=font)
        draw.text(((w - bw) / 2, ty), text, font=font, fill=colour)
        ty += font.size + gap
    return panel.convert("RGB")


# Exact panel size at each display scale (164x314 at 100%), so nothing is padded.
SIDE_SIZES = [(round(164 * k), round(314 * k)) for k in (1, 1.25, 1.5, 1.75, 2, 2.25, 2.5)]
for w, h in SIDE_SIZES:
    side_panel(w, h).save(wizard / f"side-{w}.bmp")
print("wrote installer side panels in", wizard, [f"{w}x{h}" for w, h in SIDE_SIZES])
