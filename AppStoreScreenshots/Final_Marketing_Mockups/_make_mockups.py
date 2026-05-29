#!/usr/bin/env python3
"""
Sacred Bill Tracker — App Store marketing mockup generator.

Composites the raw simulator screenshots from
  ../New_Features_May_2026/
into premium dark-gradient marketing mockups, written into THIS folder.

Run:
  cd ~/Documents/Claude/Projects/SACRED\ BILL\ TRACKER/AppStoreScreenshots/Final_Marketing_Mockups
  python3 _make_mockups.py

Output sizes match Apple App Store specs:
  iPhone 6.9" Display    1320 × 2868
  iPad 13" Display       2064 × 2752
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# --------------------------------------------------------------- paths

HERE = Path(__file__).resolve().parent
SRC  = HERE.parent / "New_Features_May_2026"

# --------------------------------------------------------------- spec

IPHONE_SIZE = (1320, 2868)
IPAD_SIZE   = (2064, 2752)

SHOTS = [
    # n  source-suffix              headline                              subheadline
    (1, "DashboardSplit",      "Separate Business & Personal Bills",  "Track every responsibility with total clarity."),
    (2, "DashboardCombined",   "One Shared Financial View",           "Combine personal, business, and shared bills instantly."),
    (3, "BillsSortMenu",       "Powerful Smart Sorting",              "Sort by amount, due date, category, alphabetical order, and more."),
    (4, "BillsSortedByAmount", "Built for Couples & Teams",           "Share bills, organize responsibilities, and stay aligned together."),
    (5, "DashboardHero",       "Never Miss Another Bill",             "Shared budgeting with peace of mind built in."),
]

# --------------------------------------------------------------- palette

BG_TOP         = (10, 14, 20)       # deep charcoal
BG_BOTTOM      = (26, 36, 48)       # warm charcoal
ACCENT_GLOW    = (212, 175, 55, 70) # warm gold (Sacred Bill Tracker brand)
HEADLINE_COLOR = (248, 244, 235)    # cream
SUB_COLOR      = (175, 173, 165)    # warm gray

# --------------------------------------------------------------- fonts

FONT_PATHS_BOLD = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFNSDisplay.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial Bold.ttf",
]
FONT_PATHS_REG = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
]

def load_font(paths, size):
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()

# --------------------------------------------------------------- helpers

def gradient_bg(size):
    w, h = size
    base = Image.new("RGB", size, BG_TOP)
    px = base.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
        g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
        b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    # warm vignette upper-left
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-w // 5, -h // 6, w // 2, h // 3), fill=ACCENT_GLOW)
    glow = glow.filter(ImageFilter.GaussianBlur(int(min(size) * 0.10)))
    out = Image.alpha_composite(base.convert("RGBA"), glow)
    return out.convert("RGB")

def wrap(text, font, draw, max_w):
    out, line = [], ""
    for word in text.split():
        cand = f"{line} {word}".strip()
        b = draw.textbbox((0, 0), cand, font=font)
        if b[2] - b[0] <= max_w:
            line = cand
        else:
            if line:
                out.append(line)
            line = word
    if line:
        out.append(line)
    return out

def line_h(font, draw):
    b = draw.textbbox((0, 0), "Hg", font=font)
    return b[3] - b[1]

# --------------------------------------------------------------- compose

def render(src_path: Path, dst_path: Path, headline: str, sub: str,
           canvas_size, *, top_pad_pct=0.07, headline_pct=0.046, sub_pct=0.020,
           shot_scale_max=0.74):
    if not src_path.exists():
        print(f"  ! missing: {src_path.name}")
        return False

    cw, ch = canvas_size
    canvas = gradient_bg(canvas_size).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    margin = int(cw * 0.08)
    text_max_w = cw - margin * 2

    h_font = load_font(FONT_PATHS_BOLD, int(ch * headline_pct))
    s_font = load_font(FONT_PATHS_REG,  int(ch * sub_pct))

    # vertical placement
    y = int(ch * top_pad_pct)

    for line in wrap(headline, h_font, draw, text_max_w):
        b = draw.textbbox((0, 0), line, font=h_font)
        tw = b[2] - b[0]
        draw.text(((cw - tw) // 2, y), line, font=h_font, fill=HEADLINE_COLOR)
        y += line_h(h_font, draw) + int(ch * 0.006)

    y += int(ch * 0.012)

    for line in wrap(sub, s_font, draw, text_max_w):
        b = draw.textbbox((0, 0), line, font=s_font)
        tw = b[2] - b[0]
        draw.text(((cw - tw) // 2, y), line, font=s_font, fill=SUB_COLOR)
        y += line_h(s_font, draw) + int(ch * 0.004)

    text_block_bottom = y + int(ch * 0.025)

    # screenshot
    shot = Image.open(src_path).convert("RGBA")
    sw, sh = shot.size
    avail_h = ch - text_block_bottom - int(ch * 0.045)
    avail_w = cw - margin * 2
    scale = min(avail_h / sh, avail_w / sw, shot_scale_max)
    new_size = (int(sw * scale), int(sh * scale))
    shot = shot.resize(new_size, Image.LANCZOS)

    sx = (cw - new_size[0]) // 2
    sy = text_block_bottom

    # subtle shadow plate
    pad = int(min(new_size) * 0.05)
    shadow = Image.new("RGBA",
                       (new_size[0] + pad * 2, new_size[1] + pad * 2),
                       (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad, pad + new_size[0], pad + new_size[1]),
        radius=int(min(new_size) * 0.045),
        fill=(0, 0, 0, 150),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(pad * 0.7)))
    canvas.alpha_composite(shadow, dest=(sx - pad, sy - pad + int(pad * 0.4)))
    canvas.alpha_composite(shot,   dest=(sx, sy))

    canvas.convert("RGB").save(dst_path, "PNG", optimize=True)
    print(f"  ✓ {dst_path.name}  ({cw}×{ch})  source={src_path.name}")
    return True

def main():
    HERE.mkdir(parents=True, exist_ok=True)
    print(f"source: {SRC}")
    print(f"output: {HERE}\n")
    if not SRC.exists():
        print(f"!! source folder missing: {SRC}")
        return

    print("iPhone 6.9\" — 1320 × 2868")
    for n, suffix, h, s in SHOTS:
        render(SRC / f"iPhone_{n}_{suffix}.png",
               HERE / f"iPhone_Final_{n}.png",
               h, s, IPHONE_SIZE)

    print("\niPad 13\" — 2064 × 2752")
    for n, suffix, h, s in SHOTS:
        render(SRC / f"iPad_{n}_{suffix}.png",
               HERE / f"iPad_Final_{n}.png",
               h, s, IPAD_SIZE,
               top_pad_pct=0.06, headline_pct=0.050, sub_pct=0.022,
               shot_scale_max=0.68)

    print("\nDone. 10 mockup PNGs in:")
    print(f"  {HERE}")

if __name__ == "__main__":
    main()
