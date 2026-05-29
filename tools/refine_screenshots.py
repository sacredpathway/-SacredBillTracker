#!/usr/bin/env python3
"""
Sacred Bill Tracker — App Store screenshot refinement (Option C, Method B).

Reads the existing per-device PNGs in _AppStoreScreenshots_generated/ and
rewrites the marketing-overlay region (top headline area + side/bottom
frame hairlines) in a unified gold-on-deep-black premium theme.

The device + app UI region is preserved untouched.

Headline sizing — METHOD B (cap-height normalization with side-pad clamp):
  All six headlines on a given device are rendered at the SAME font size,
  chosen as the largest size at which the LONGEST headline still fits
  within 88% of the canvas width. Same font size + same font face means
  identical cap-height on every screen — equal visual weight, single
  line, never edge-to-edge.

Output: SacredBillTracker_AppStoreScreenshots_REFINED/{iPhone_6_7,iPhone_6_9,iPad_13}/*.png
"""

from __future__ import annotations
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

# ----------------------------------------------------------------------------
# Theme
# ----------------------------------------------------------------------------

GOLD            = (212, 175,  55)   # #D4AF37
GOLD_BRIGHT     = (228, 192,  72)
WHITE           = (255, 255, 255)
TEXT_PRIMARY    = (252, 252, 252)
TEXT_SECONDARY  = (172, 172, 172)
BG_DEEP         = ( 11,  15,  12)
BG_EDGE         = (  4,   6,   5)

LATO_BLACK   = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"
LATO_BOLD    = "/usr/share/fonts/truetype/lato/Lato-Bold.ttf"
LATO_REGULAR = "/usr/share/fonts/truetype/lato/Lato-Regular.ttf"
LATO_MEDIUM  = "/usr/share/fonts/truetype/lato/Lato-Medium.ttf"

# Headline width clamp — % of canvas width that the headline is allowed to
# occupy. 0.88 leaves a comfortable side margin on every screen.
CLAMP_PCT       = 0.88

# ----------------------------------------------------------------------------
# Per-device layout
# ----------------------------------------------------------------------------

LAYOUTS = {
    "iPhone_6_7": {
        "size":           (1290, 2796),
        "headline_y":     155,
        "headline_size":  118,   # max — actual size derived per device
        "subtitle_size":  44,
        "device_top_y":   430,
        "underline_w":    230,
        "underline_h":    8,
        "side_pad":       80,
        "top_hair_h":     6,
        "bot_hair_h":     6,
        "bot_hair_y":    2790,
        "subtitle_gap":   28,    # gap between underline bottom and subtitle top
    },
    "iPhone_6_9": {
        "size":           (1320, 2868),
        "headline_y":     160,
        "headline_size":  122,
        "subtitle_size":  46,
        "device_top_y":   440,
        "underline_w":    240,
        "underline_h":    8,
        "side_pad":       82,
        "top_hair_h":     6,
        "bot_hair_h":     6,
        "bot_hair_y":    2862,
        "subtitle_gap":   30,
    },
    "iPad_13": {
        "size":           (2064, 2752),
        "headline_y":     200,
        "headline_size":  140,
        "subtitle_size":  56,
        "device_top_y":   500,
        "underline_w":    340,
        "underline_h":    10,
        "side_pad":       130,
        "top_hair_h":     8,
        "bot_hair_h":     8,
        "bot_hair_y":    2746,
        "subtitle_gap":   36,
    },
}

# ----------------------------------------------------------------------------
# Per-screenshot copy (gold-themed, leading order requested by user)
# ----------------------------------------------------------------------------
SCREENS = [
    ("01_Dashboard.png", "Every Bill,",            "Household and business in one place."),
    ("02_Bills.png",     "Track What's Due",        "Filter by household or business."),
    ("03_Calendar.png",  "See the Whole Month",     "Per-day markers. Never get caught off guard."),
    ("04_Reports.png",   "Cash Flow at a Glance",   "Monthly totals and category breakdowns."),
    ("05_Settings.png",  "You're in Control",       "Reminders, sync, account — your data, your call."),
    ("06_Paywall.png",   "7 Days Free, Then Pro",   "$4.99 / month · $39.99 / year. Cancel any time."),
]

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)

def text_width(text: str, size: int, font_path: str = LATO_BLACK) -> int:
    """Measure rendered width of `text` at `size` pt in the given font."""
    font = load_font(font_path, size)
    img = Image.new("RGB", (1, 1))
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0]

def compute_unified_size(layout: dict, screens) -> int:
    """METHOD B: pick the largest font size at which EVERY headline in the
    set still fits within CLAMP_PCT of the canvas width. Same size for all
    six → same cap-height → equal visual weight."""
    W = layout["size"][0]
    max_w = int(W * CLAMP_PCT)
    start = layout["headline_size"]

    # Find the per-headline max-fitting size, then take the MIN across all.
    per_headline_max = []
    for _, headline, _ in screens:
        size = start
        # If at the starting size the text is wider than max_w, scale down
        # proportionally. Otherwise the starting size is fine for this one.
        w = text_width(headline, size)
        if w > max_w:
            size = int(size * max_w / w)
            # Verify (Lato metrics are nearly linear in pt size, but be safe)
            while size > 40 and text_width(headline, size) > max_w:
                size -= 2
        per_headline_max.append(size)

    return min(per_headline_max)

def make_background(W: int, H: int) -> Image.Image:
    """Deep dark canvas with very subtle vertical vignette only at edges."""
    bg = Image.new("RGB", (W, H), BG_DEEP)
    px = bg.load()
    edge_band = int(H * 0.12)
    for y in range(H):
        if y < edge_band:
            t = 1.0 - (y / edge_band)
        elif y > H - edge_band:
            t = 1.0 - ((H - y) / edge_band)
        else:
            t = 0.0
        r = int(BG_DEEP[0] * (1 - t) + BG_EDGE[0] * t)
        g = int(BG_DEEP[1] * (1 - t) + BG_EDGE[1] * t)
        b = int(BG_DEEP[2] * (1 - t) + BG_EDGE[2] * t)
        for x in range(W):
            px[x, y] = (r, g, b)
    return bg

def draw_hairline(canvas: Image.Image, layout: dict, y: int, h: int):
    """Premium gold hairline — full-width, soft-edged."""
    W = layout["size"][0]
    overlay = Image.new("RGBA", (W, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    cx = W // 2
    for x in range(W):
        t = abs(x - cx) / cx
        a = int(255 * (1.0 - 0.25 * t))
        r = int(GOLD_BRIGHT[0] * (1 - 0.4 * t) + GOLD[0] * 0.4 * t)
        g = int(GOLD_BRIGHT[1] * (1 - 0.4 * t) + GOLD[1] * 0.4 * t)
        b = int(GOLD_BRIGHT[2] * (1 - 0.4 * t) + GOLD[2] * 0.4 * t)
        od.line([(x, 0), (x, h - 1)], fill=(r, g, b, a))
    canvas.paste(overlay, (0, y), overlay)

def draw_headline(canvas: Image.Image, layout: dict, headline: str, size: int) -> int:
    """Render headline at the *unified* font size. Returns the y just below
    the gold underline so the subtitle can dock at a consistent offset.
    """
    W, _ = layout["size"]
    draw = ImageDraw.Draw(canvas)
    font = load_font(LATO_BLACK, size)

    bbox = draw.textbbox((0, 0), headline, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (W - text_w) // 2 - bbox[0]
    y = layout["headline_y"]

    # subtle drop shadow for premium depth
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.text((x + 2, y + 4), headline, font=font, fill=(0, 0, 0, 180))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    canvas.paste(shadow, (0, 0), shadow)

    draw.text((x, y), headline, font=font, fill=TEXT_PRIMARY)

    # Gold underline — fixed pill width, identical across screens.
    uw = layout["underline_w"]
    uh = layout["underline_h"]
    ux1 = (W - uw) // 2
    uy = y + text_h + 24

    underline = Image.new("RGBA", (uw + uh * 2, uh * 2), (0, 0, 0, 0))
    ud = ImageDraw.Draw(underline)
    ud.rounded_rectangle(
        [0, 0, uw + uh * 2 - 1, uh - 1],
        radius=uh // 2,
        fill=GOLD + (255,),
    )
    canvas.paste(underline, (ux1 - uh, uy), underline)

    return uy + uh

def draw_subtitle(canvas: Image.Image, layout: dict, subtitle: str, y_start: int):
    """Subtitle docks at y_start + subtitle_gap. With a unified headline
    size, every screen has the same y_start, so the subtitle baseline is
    pixel-identical across all six screens."""
    W, _ = layout["size"]
    draw = ImageDraw.Draw(canvas)
    try:
        font = load_font(LATO_MEDIUM, layout["subtitle_size"])
    except OSError:
        font = load_font(LATO_REGULAR, layout["subtitle_size"])

    max_w = W - layout["side_pad"] * 2
    # Word-wrap if the subtitle is too long for one line
    words = subtitle.split(" ")
    lines = []
    cur = ""
    for w in words:
        test = (cur + " " + w).strip()
        bb = draw.textbbox((0, 0), test, font=font)
        if bb[2] - bb[0] <= max_w:
            cur = test
        else:
            lines.append(cur); cur = w
    if cur: lines.append(cur)

    line_h = layout["subtitle_size"] + 8
    y = y_start + layout["subtitle_gap"]
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=font)
        x = (W - (bb[2] - bb[0])) // 2 - bb[0]
        draw.text((x, y), line, font=font, fill=TEXT_SECONDARY)
        y += line_h

def soften_existing_top(strip: Image.Image) -> Image.Image:
    """Some originals have a vivid green/lime top bar baked in. Replace the
    very top 30 px of the preserved bottom strip with our deep-black
    background so the gold hairline above is the only top accent."""
    W, H = strip.size
    if H < 60:
        return strip
    out = strip.copy()
    od = ImageDraw.Draw(out)
    od.rectangle([0, 0, W, 30], fill=BG_DEEP)
    return out

def refine(src_path: Path, dst_path: Path, headline: str, subtitle: str,
           layout: dict, unified_size: int):
    src = Image.open(src_path).convert("RGB")
    W, H = layout["size"]
    if src.size != (W, H):
        src = src.resize((W, H), Image.LANCZOS)

    canvas = make_background(W, H)

    # Preserve device + UI region exactly as captured.
    bottom = src.crop((0, layout["device_top_y"], W, H))
    bottom = soften_existing_top(bottom)
    canvas.paste(bottom, (0, layout["device_top_y"]))

    # Top hairline.
    draw_hairline(canvas, layout, 0, layout["top_hair_h"])

    # Headline at unified size + fixed-width underline.
    underline_bottom = draw_headline(canvas, layout, headline, unified_size)

    # Subtitle at fixed offset from underline.
    draw_subtitle(canvas, layout, subtitle, underline_bottom)

    # Bottom hairline.
    draw_hairline(canvas, layout, layout["bot_hair_y"], layout["bot_hair_h"])

    dst_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dst_path, "PNG", optimize=True)


def main():
    project = Path("/sessions/practical-stoic-ritchie/mnt/SACRED BILL TRACKER")
    src_root = project / "_AppStoreScreenshots_generated"
    dst_root = project / "SacredBillTracker_AppStoreScreenshots_REFINED"

    if not src_root.exists():
        print(f"FATAL: source folder not found: {src_root}")
        sys.exit(1)

    summary = []
    for device, layout in LAYOUTS.items():
        unified_size = compute_unified_size(layout, SCREENS)
        print(f"[{device}] unified headline size = {unified_size} pt "
              f"(starting from {layout['headline_size']} pt)")
        for fname, headline, subtitle in SCREENS:
            src = src_root / device / fname
            dst = dst_root / device / fname
            if not src.exists():
                print(f"  SKIP missing: {src}")
                continue
            refine(src, dst, headline, subtitle, layout, unified_size)
            summary.append(str(dst.relative_to(project)))
            print(f"  ✓ {dst.relative_to(project)}")

    print()
    print(f"Wrote {len(summary)} screenshots to {dst_root.relative_to(project)}/")


if __name__ == "__main__":
    main()
