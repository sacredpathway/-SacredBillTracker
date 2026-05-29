#!/usr/bin/env python3
"""
Compose marketing layer OVER unmodified real app screenshots.

Rules:
- DO NOT alter the screenshot pixels (no crop, no resize beyond exact-match
  scaling for iPhone 6.9 since the native is 1179×2556 and target 1320×2868).
- Add a dark canvas extension at the TOP of the screenshot for the headline.
- Marketing copy: bold white headline + subtext + thin gold accent line.
- Background outside the screenshot: solid #0B0B0F (matches phone's near-black).

Output:
- iPhone 6.7  (1290 × 2796)  — uses iPhone native 1179×2556 placed centered
- iPhone 6.9  (1320 × 2868)  — uses iPhone native scaled +8.5% to fit width
- iPad 13     (2752 × 2064)  — landscape, headline overlays the top
                               status bar region only

Outputs to:
  SacredBillTracker_AppStoreScreenshots_FINAL/{iPhone_6_7,iPhone_6_9,iPad_13}/
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

PROJECT = Path("/sessions/wizardly-youthful-maxwell/mnt/SACRED BILL TRACKER")
SRC     = PROJECT / "_real_screens"
DST     = PROJECT / "SacredBillTracker_AppStoreScreenshots_FINAL"

LATO_BLACK = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"
LATO_REG   = "/usr/share/fonts/truetype/lato/Lato-Regular.ttf"
LATO_MED   = "/usr/share/fonts/truetype/lato/Lato-Medium.ttf"

BG_COLOR     = (252, 252, 253)    # near-white daytime
BG_BOTTOM    = (240, 240, 244)    # subtle light-gray gradient bottom
HEADLINE_COL = (18, 18, 24)        # near-black on white
SUB_COL      = (90, 90, 100)       # muted gray subtext
GOLD         = (190, 145, 50)      # darker gold for white bg contrast
GREEN        = (60, 120, 50)
LIME         = (130, 165, 60)
AMBER        = (160, 95, 30)

# Maps source file → marketing copy + accent color
# iPad uses NEW portrait captures (IMG_0045-0049, reverse mapping)
SCREENS = [
    ("01_Dashboard.png", "IMG_1805.png", "IMG_0049.png",
     "Every Bill, One Place",        "Household + business tracked together.",  GOLD),
    ("02_Bills.png",     "IMG_1806.png", "IMG_0048.png",
     "Track What's Due",             "Filter by household or business.",         GREEN),
    ("03_Calendar.png",  "IMG_1807.png", "IMG_0047.png",
     "Never Miss a Due Date",        "See every bill on a single month view.",   LIME),
    ("04_Reports.png",   "IMG_1808.png", "IMG_0046.png",
     "Cash Flow at a Glance",        "Monthly totals by category.",              GOLD),
    ("05_Settings.png",  "IMG_1809.png", "IMG_0045.png",
     "You're in Control",            "Reminders, sync, and account.",            AMBER),
    ("06_Paywall.png",   "06_Paywall_iphone.png", "06_Paywall_ipad.png",
     "Upgrade to Premium",           "Unlock Full Control.",                     GOLD),
]


def font(path, size):
    return ImageFont.truetype(path, size)


def text_w(d, s, f):
    bb = d.textbbox((0, 0), s, font=f)
    return bb[2] - bb[0]


def text_h(d, s, f):
    bb = d.textbbox((0, 0), s, font=f)
    return bb[3] - bb[1]


def render_headline_strip(canvas: Image.Image, strip_top: int, strip_h: int,
                          headline: str, subhead: str, accent: tuple,
                          is_pad: bool) -> None:
    """Draw headline + subhead + accent line into the strip region."""
    W, _ = canvas.size
    d = ImageDraw.Draw(canvas)

    if is_pad:
        head_size = int(W * 0.038)
        sub_size  = int(W * 0.018)
        accent_w  = int(W * 0.07)
    else:
        head_size = int(W * 0.090)
        sub_size  = int(W * 0.038)
        accent_w  = int(W * 0.13)

    f_head = font(LATO_BLACK, head_size)
    f_sub  = font(LATO_REG, sub_size)

    # Compute total stack height to center vertically inside strip
    th = text_h(d, headline, f_head)
    sh = text_h(d, subhead,  f_sub)
    accent_h = max(6, int(W * 0.006 if not is_pad else W * 0.004))
    gap_after_head = int(strip_h * 0.08)
    gap_after_accent = int(strip_h * 0.10)
    total_h = th + gap_after_head + accent_h + gap_after_accent + sh
    y = strip_top + (strip_h - total_h) // 2

    # Headline
    tw = text_w(d, headline, f_head)
    d.text(((W - tw) / 2, y), headline, font=f_head, fill=HEADLINE_COL)
    y += th + gap_after_head

    # Accent line
    rect = (W // 2 - accent_w // 2, y,
            W // 2 + accent_w // 2, y + accent_h)
    d.rounded_rectangle(rect, radius=accent_h // 2, fill=accent)
    y += accent_h + gap_after_accent

    # Subhead
    tw = text_w(d, subhead, f_sub)
    d.text(((W - tw) / 2, y), subhead, font=f_sub, fill=SUB_COL)


def make_light_canvas(W: int, H: int) -> Image.Image:
    """Daytime canvas: subtle vertical gradient white → light gray."""
    canvas = Image.new("RGB", (W, H), BG_COLOR)
    px = canvas.load()
    for y in range(H):
        t = y / max(H - 1, 1)
        r = int(BG_COLOR[0] + (BG_BOTTOM[0] - BG_COLOR[0]) * t)
        g = int(BG_COLOR[1] + (BG_BOTTOM[1] - BG_COLOR[1]) * t)
        b = int(BG_COLOR[2] + (BG_BOTTOM[2] - BG_COLOR[2]) * t)
        for x in range(W):
            px[x, y] = (r, g, b)
    return canvas


def cast_soft_shadow(canvas: Image.Image, x: int, y: int, w: int, h: int,
                     radius: int) -> None:
    """Soft realistic drop shadow — two layers, low opacity."""
    # Outer ambient
    pad = 80
    sh_outer = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sd1 = ImageDraw.Draw(sh_outer)
    sd1.rounded_rectangle((pad, pad + 22, pad + w, pad + h + 22),
                          radius=radius, fill=(20, 20, 30, 55))
    sh_outer = sh_outer.filter(ImageFilter.GaussianBlur(60))
    canvas_rgba = canvas.convert("RGBA")
    canvas_rgba.paste(sh_outer, (x - pad, y - pad), sh_outer)
    # Inner tighter
    sh_inner = Image.new("RGBA", (w + 60, h + 60), (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(sh_inner)
    sd2.rounded_rectangle((30, 38, 30 + w, 38 + h),
                          radius=radius, fill=(20, 20, 30, 70))
    sh_inner = sh_inner.filter(ImageFilter.GaussianBlur(22))
    canvas_rgba.paste(sh_inner, (x - 30, y - 30), sh_inner)
    canvas.paste(canvas_rgba.convert("RGB"))


def draw_iphone_frame(canvas: Image.Image, screen: Image.Image,
                      sx: int, sy: int) -> None:
    """Draw modern iPhone bezel around screenshot. Adds dark bezel + dynamic
    island. Screen content stays untouched."""
    sw, sh = screen.size
    bezel = max(14, int(sw * 0.024))
    corner = int(sw * 0.115)

    # Outer device shape (slightly larger than screen)
    dev_w = sw + bezel * 2
    dev_h = sh + bezel * 2
    dev_x = sx - bezel
    dev_y = sy - bezel

    # Soft shadow behind the device first
    cast_soft_shadow(canvas, dev_x, dev_y, dev_w, dev_h, corner + bezel)

    # Device body (very dark gray, not pure black, so it reads on white bg)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((dev_x, dev_y, dev_x + dev_w, dev_y + dev_h),
                        radius=corner + bezel, fill=(28, 28, 32))

    # Inner thin highlight bezel for premium feel
    d.rounded_rectangle((dev_x + bezel // 3, dev_y + bezel // 3,
                         dev_x + dev_w - bezel // 3, dev_y + dev_h - bezel // 3),
                        radius=corner + bezel - bezel // 3,
                        outline=(60, 60, 66), width=2)

    # Mask the screenshot to rounded corners and paste
    mask = Image.new("L", (sw, sh), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, sw, sh), radius=corner, fill=255)
    canvas.paste(screen, (sx, sy), mask)


def compose_iphone(src: Image.Image, target: tuple[int, int],
                   headline: str, subhead: str, accent: tuple,
                   scale_to_fit: bool) -> Image.Image:
    """White daytime canvas + iPhone-framed screenshot + headline strip."""
    canvas = make_light_canvas(*target)
    W, H = target
    sw, sh = src.size

    if scale_to_fit:
        # Slightly upscale screenshot so device frame fills canvas nicely.
        new_w = int(W * 0.86)
        new_h = int(sh * (new_w / sw))
        screen = src.resize((new_w, new_h), Image.LANCZOS)
    else:
        # Match canvas at ~92% width for full impact.
        new_w = int(W * 0.86)
        new_h = int(sh * (new_w / sw))
        screen = src.resize((new_w, new_h), Image.LANCZOS)

    sw, sh = screen.size

    # Headline area at top, device below
    bottom_margin = max(40, int(H * 0.025))
    sx = (W - sw) // 2
    sy = H - sh - bottom_margin

    strip_h = sy
    if strip_h < 200:
        strip_h = 200

    draw_iphone_frame(canvas, screen, sx, sy)
    render_headline_strip(canvas, 0, strip_h, headline, subhead,
                          accent, is_pad=False)
    return canvas


def draw_ipad_frame(canvas: Image.Image, screen: Image.Image,
                    sx: int, sy: int) -> None:
    """Draw modern iPad bezel around screenshot."""
    sw, sh = screen.size
    bezel = max(20, int(sw * 0.020))
    corner = int(sw * 0.040)
    dev_w = sw + bezel * 2
    dev_h = sh + bezel * 2
    dev_x = sx - bezel
    dev_y = sy - bezel

    cast_soft_shadow(canvas, dev_x, dev_y, dev_w, dev_h, corner + bezel)

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((dev_x, dev_y, dev_x + dev_w, dev_y + dev_h),
                        radius=corner + bezel, fill=(28, 28, 32))
    d.rounded_rectangle((dev_x + bezel // 3, dev_y + bezel // 3,
                         dev_x + dev_w - bezel // 3, dev_y + dev_h - bezel // 3),
                        radius=corner + bezel - bezel // 3,
                        outline=(60, 60, 66), width=2)

    mask = Image.new("L", (sw, sh), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, sw, sh), radius=corner, fill=255)
    canvas.paste(screen, (sx, sy), mask)


def compose_ipad(src: Image.Image, headline: str, subhead: str,
                 accent: tuple) -> Image.Image:
    """White daytime canvas + iPad-framed screenshot + headline at bottom
    (since iPad tab bar is at the TOP of the screenshot, we don't put
    headline above it)."""
    target = (2064, 2752)
    W, H = target
    canvas = make_light_canvas(W, H)

    # Resize screenshot to fit canvas with margin for headline strip + frame
    new_w = int(W * 0.84)
    sw, sh = src.size
    new_h = int(sh * (new_w / sw))
    screen = src.resize((new_w, new_h), Image.LANCZOS)
    sw, sh = screen.size

    # Headline at TOP of canvas (above device), device sits below
    headline_h = int(H * 0.13)
    sx = (W - sw) // 2
    sy = headline_h + int(H * 0.02)
    # If device would overflow, shrink slightly
    if sy + sh > H - int(H * 0.02):
        new_h2 = H - int(H * 0.02) - sy
        new_w2 = int(sw * (new_h2 / sh))
        screen = src.resize((new_w2, new_h2), Image.LANCZOS)
        sw, sh = screen.size
        sx = (W - sw) // 2

    draw_ipad_frame(canvas, screen, sx, sy)
    render_headline_strip(canvas, 0, headline_h, headline, subhead,
                          accent, is_pad=True)
    return canvas


def main():
    (DST / "iPhone_6_7").mkdir(parents=True, exist_ok=True)
    (DST / "iPhone_6_9").mkdir(parents=True, exist_ok=True)
    (DST / "iPad_13").mkdir(parents=True, exist_ok=True)

    for out_name, iphone_src, ipad_src, headline, subhead, accent in SCREENS:
        # iPhone 6.7
        i_path = SRC / iphone_src
        if not i_path.exists():
            print(f"  skip iPhone (missing): {iphone_src}")
            continue
        iphone_img = Image.open(i_path).convert("RGB")

        # 6.7 — 1290×2796, native screenshot fits
        out67 = compose_iphone(iphone_img, (1290, 2796), headline, subhead,
                               accent, scale_to_fit=False)
        out67.save(DST / "iPhone_6_7" / out_name, "PNG", optimize=True)
        print(f"  wrote iPhone_6_7/{out_name} ({out67.size})")

        # 6.9 — 1320×2868, slight upscale needed
        out69 = compose_iphone(iphone_img, (1320, 2868), headline, subhead,
                               accent, scale_to_fit=True)
        out69.save(DST / "iPhone_6_9" / out_name, "PNG", optimize=True)
        print(f"  wrote iPhone_6_9/{out_name} ({out69.size})")

        # iPad 13 (landscape 2752×2064)
        p_path = SRC / ipad_src
        if not p_path.exists():
            print(f"  skip iPad (missing): {ipad_src}")
            continue
        ipad_img = Image.open(p_path).convert("RGB")
        out_ipad = compose_ipad(ipad_img, headline, subhead, accent)
        out_ipad.save(DST / "iPad_13" / out_name, "PNG", optimize=True)
        print(f"  wrote iPad_13/{out_name} ({out_ipad.size})")

    print("Done.")


if __name__ == "__main__":
    main()
