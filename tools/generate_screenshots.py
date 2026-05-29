"""
Sacred Bill Tracker — App Store marketing screenshot generator.

Produces App-Store-compliant marketing screenshots at the three required
sizes:

    iPhone 6.9" : 1320 x 2868
    iPhone 6.7" : 1290 x 2796
    iPad 13"    : 2064 x 2752

Layout per screenshot:
    - Top band  : dark Tree-of-Life gradient + headline + subhead
    - Middle    : device-frame mockup of the relevant SwiftUI screen
    - Bottom    : faint footer with category dot

Six screens are rendered: Dashboard, Bills, Calendar, Reports, Settings,
Paywall. Output goes to:

    Desktop/SacredBillTracker/AppStoreScreenshots/<device>/<NN_screen>.png

These are *marketing fallbacks* — replace any of them with a real
simulator capture (Cmd+S in Simulator) before submitting if you want
pure-app screenshots. App Store rules allow marketing-style screenshots
as long as they accurately represent the app.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ----------------------------------------------------------------------------
# Brand palette — mirrors SacredBillTracker/Extensions/Color+Theme.swift
# ----------------------------------------------------------------------------

GOLD       = (200, 155,  75)   # #C89B4B  appAccent
AMBER      = (184, 120,  47)   # #B8782F  appAmber / business
LIME       = (175, 210,  80)   # #AFD250  appLime
HOUSEHOLD  = ( 91, 153,  67)   # #5B9943  household leaf green
SACRED     = ( 13,  13,  15)   # #0D0D0F  sacred black
INK        = ( 28,  28,  30)
INK2       = ( 44,  44,  46)
SURFACE    = (242, 242, 247)
CARD       = (255, 255, 255)
SUBTLE     = (235, 235, 240)
MUTED      = (118, 118, 128)
TEXT       = ( 28,  28,  30)
DANGER     = (255,  69,  58)

# ----------------------------------------------------------------------------
# Fonts
# ----------------------------------------------------------------------------

LATO_BOLD     = "/usr/share/fonts/truetype/lato/Lato-Bold.ttf"
LATO_BLACK    = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"
LATO_REG      = "/usr/share/fonts/truetype/lato/Lato-Regular.ttf"
LATO_MED      = "/usr/share/fonts/truetype/lato/Lato-Medium.ttf"
LATO_SEMI     = "/usr/share/fonts/truetype/lato/Lato-Semibold.ttf"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


# ----------------------------------------------------------------------------
# Device configurations
# ----------------------------------------------------------------------------


@dataclass
class Device:
    name: str          # subfolder name
    out_size: tuple    # (w, h) of marketing image
    is_pad: bool       # True for iPad layout


DEVICES = [
    Device("iPhone_6_9", (1320, 2868), is_pad=False),
    Device("iPhone_6_7", (1290, 2796), is_pad=False),
    Device("iPad_13",    (2064, 2752), is_pad=True),
]


# ----------------------------------------------------------------------------
# Real app icon (Tree-of-Life) — loaded once, pasted into screenshots
# ----------------------------------------------------------------------------

_REAL_LOGO_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "SacredBillTracker/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png",
)
_REAL_LOGO = None  # lazy-loaded RGBA Image


def _get_real_logo() -> Image.Image:
    global _REAL_LOGO
    if _REAL_LOGO is None:
        _REAL_LOGO = Image.open(_REAL_LOGO_PATH).convert("RGBA")
    return _REAL_LOGO


def paste_real_logo(canvas: Image.Image, cx: int, cy: int, r: int) -> None:
    """Paste the real Tree-of-Life logo centered at (cx, cy) with radius r.
    Replaces ad-hoc ellipse+rect 'fake tree' drawings with the actual app icon."""
    diameter = max(8, int(r * 2))
    logo = _get_real_logo().resize((diameter, diameter), Image.LANCZOS)
    canvas.paste(logo, (int(cx - r), int(cy - r)), logo)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------


def vertical_gradient(size, top_rgb, bottom_rgb):
    w, h = size
    img = Image.new("RGB", (1, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        r = round(top_rgb[0] + (bottom_rgb[0] - top_rgb[0]) * t)
        g = round(top_rgb[1] + (bottom_rgb[1] - top_rgb[1]) * t)
        b = round(top_rgb[2] + (bottom_rgb[2] - top_rgb[2]) * t)
        px[0, y] = (r, g, b)
    return img.resize((w, h))


def rounded_rect(draw, xy, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_text(draw, xy, text, fnt, fill, anchor="la"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)


def text_size(fnt, text):
    bbox = fnt.getbbox(text)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def shadowed_card(canvas: Image.Image, xy, radius, fill, shadow_blur=18, shadow_alpha=70):
    x0, y0, x1, y1 = xy
    pad = shadow_blur * 2
    s = Image.new("RGBA", (x1 - x0 + pad * 2, y1 - y0 + pad * 2), (0, 0, 0, 0))
    sd = ImageDraw.Draw(s)
    sd.rounded_rectangle((pad, pad, pad + (x1 - x0), pad + (y1 - y0)),
                         radius=radius, fill=(0, 0, 0, shadow_alpha))
    s = s.filter(ImageFilter.GaussianBlur(shadow_blur))
    canvas.alpha_composite(s, (x0 - pad, y0 - pad + 6))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(xy, radius=radius, fill=fill)


def small_dot(draw, cx, cy, r, fill):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


# ----------------------------------------------------------------------------
# Screen content renderers
#
# Each renderer draws the *interior* of a phone screen at the given size
# (sw, sh). Content is intentionally simple but matches the real app
# layout: BrandHeader, FilterPicker, StatCards grid, etc.
# ----------------------------------------------------------------------------


def draw_status_bar(d: ImageDraw.ImageDraw, sw: int, color=TEXT):
    f = font(LATO_BOLD, max(28, sw // 30))
    d.text((sw * 0.07, sw * 0.04), "9:41", font=f, fill=color)
    # right-side icons (signal/wifi/battery) as simple shapes
    bx = sw - sw * 0.2
    by = sw * 0.05
    sz = max(8, sw // 60)
    for i in range(4):
        d.rectangle((bx + i * sz * 1.2, by + (3 - i) * sz * 0.3,
                     bx + i * sz * 1.2 + sz, by + sz * 1.2), fill=color)
    d.rounded_rectangle((sw - sw * 0.11, sw * 0.045,
                         sw - sw * 0.04, sw * 0.075),
                        radius=4, outline=color, width=2)


def draw_brand_header(d: ImageDraw.ImageDraw, x, y, w, h, canvas: Image.Image | None = None):
    rounded_rect(d, (x, y, x + w, y + h), 22, fill=SACRED)
    # disc with real Tree-of-Life app icon
    cy = y + h // 2
    cx = x + h // 2 + 8
    rr = h // 2 - 12
    if canvas is not None:
        paste_real_logo(canvas, cx, cy, rr)
    # title text
    f1 = font(LATO_BLACK, max(28, h // 3))
    f2 = font(LATO_REG, max(18, h // 5))
    tx = cx + rr + 22
    d.text((tx, y + h * 0.18), "Sacred Bill Tracker", font=f1, fill=(255, 255, 255))
    d.text((tx, y + h * 0.55), "Household + Business", font=f2, fill=(220, 220, 226))


def draw_filter_pills(d: ImageDraw.ImageDraw, x, y, w, h, active_idx=0):
    labels = ["All", "Household", "Business"]
    seg_w = w / 3
    rounded_rect(d, (x, y, x + w, y + h), h // 2, fill=SUBTLE)
    rounded_rect(d, (x + active_idx * seg_w + 4, y + 4,
                     x + (active_idx + 1) * seg_w - 4, y + h - 4),
                 (h - 8) // 2, fill=CARD)
    f = font(LATO_SEMI, h // 2 - 4)
    for i, label in enumerate(labels):
        cx = x + i * seg_w + seg_w / 2
        tw, th = text_size(f, label)
        d.text((cx - tw / 2, y + h / 2 - th / 2 - 2), label, font=f,
               fill=TEXT if i == active_idx else MUTED)


def draw_stat_card(canvas: Image.Image, x, y, w, h, title, value, sub, tint):
    d = ImageDraw.Draw(canvas)
    shadowed_card(canvas, (x, y, x + w, y + h), 22, CARD, shadow_blur=14, shadow_alpha=40)
    d = ImageDraw.Draw(canvas)
    # tint badge
    bw = max(40, w // 5)
    rounded_rect(d, (x + 16, y + 16, x + 16 + bw, y + 16 + bw), bw // 4, fill=tint)
    f_title = font(LATO_MED, h // 7)
    f_value = font(LATO_BLACK, int(h // 3.2))
    f_sub   = font(LATO_REG, int(h // 9))
    d.text((x + 18, y + 16 + bw + 12), title, font=f_title, fill=MUTED)
    d.text((x + 18, y + 16 + bw + 12 + h // 7 + 4), value, font=f_value, fill=TEXT)
    d.text((x + 18, y + h - 16 - h // 9 - 6), sub, font=f_sub, fill=MUTED)


def draw_dashboard(canvas: Image.Image, sw: int, sh: int):
    d = ImageDraw.Draw(canvas)
    canvas.paste(Image.new("RGB", (sw, sh), SURFACE))
    d = ImageDraw.Draw(canvas)
    draw_status_bar(d, sw)
    pad = sw // 18
    y = int(sh * 0.075)
    # Title
    f_title = font(LATO_BLACK, sw // 12)
    d.text((pad, y), "Dashboard", font=f_title, fill=TEXT)
    y += sw // 9
    # Brand header
    draw_brand_header(d, pad, y, sw - 2 * pad, int(sw * 0.18), canvas)
    y += int(sw * 0.18) + 18
    # Filter
    draw_filter_pills(d, pad, y, sw - 2 * pad, int(sw * 0.085))
    y += int(sw * 0.085) + 22
    # Stats grid 2x2
    gap = 14
    cw = (sw - 2 * pad - gap) // 2
    ch = int(cw * 0.85)
    stats = [
        ("Due Today",  "3",  "$432.50",  AMBER),
        ("This Week",  "5",  "$1,184.00", LIME),
        ("Overdue",    "1",  "$89.99",   DANGER),
        ("Upcoming",  "12",  "$3,602.40", GOLD),
    ]
    for i, (title, value, sub, tint) in enumerate(stats):
        row, col = divmod(i, 2)
        cx = pad + col * (cw + gap)
        cy = y + row * (ch + gap)
        draw_stat_card(canvas, cx, cy, cw, ch, title, value, sub, tint)
    y += 2 * ch + gap + 22
    # Cash flow card
    cf_h = int(sw * 0.32)
    shadowed_card(canvas, (pad, y, sw - pad, y + cf_h), 22, CARD, 14, 40)
    d = ImageDraw.Draw(canvas)
    f_h = font(LATO_BLACK, sw // 18)
    f_l = font(LATO_REG, sw // 30)
    f_v = font(LATO_BLACK, sw // 16)
    d.text((pad + 24, y + 22), "This Month", font=f_h, fill=TEXT)
    d.text((pad + 24, y + 22 + sw // 18 + 6), "Household + Business", font=f_l, fill=MUTED)
    # bars
    bar_y = y + cf_h - 80
    bar_w = sw - 2 * pad - 48
    bar_h = 28
    rounded_rect(d, (pad + 24, bar_y, pad + 24 + int(bar_w * 0.62), bar_y + bar_h),
                 bar_h // 2, fill=HOUSEHOLD)
    rounded_rect(d, (pad + 24 + int(bar_w * 0.62), bar_y,
                     pad + 24 + bar_w, bar_y + bar_h),
                 bar_h // 2, fill=AMBER)
    d.text((pad + 24, bar_y - sw // 18 - 8), "$5,218.39", font=f_v, fill=TEXT)
    # legend
    sx = pad + 24
    ly = bar_y + bar_h + 16
    small_dot(d, sx + 10, ly + 12, 8, HOUSEHOLD)
    d.text((sx + 28, ly), "Household  $3,236", font=f_l, fill=MUTED)
    sx2 = pad + 24 + bar_w // 2
    small_dot(d, sx2 + 10, ly + 12, 8, AMBER)
    d.text((sx2 + 28, ly), "Business  $1,982", font=f_l, fill=MUTED)
    # tab bar at bottom
    draw_tab_bar(d, sw, sh, active_idx=0)


def draw_tab_bar(d: ImageDraw.ImageDraw, sw: int, sh: int, active_idx: int):
    # Safe-area home-indicator inset — keeps the bar clear of the rounded
    # screen mask corners and gives a real-device "home indicator" gutter.
    safe_bottom = int(sh * 0.05)
    bar_h = int(sw * 0.16)
    y = sh - bar_h - safe_bottom
    # Bar background extends down through the home-indicator gutter so the
    # whole bottom band reads as one continuous tab area.
    d.rectangle((0, y, sw, sh), fill=CARD)
    d.line((0, y, sw, y), fill=SUBTLE, width=2)
    tabs = ["Dashboard", "Bills", "Calendar", "Reports", "Settings"]
    f = font(LATO_MED, sw // 38)
    cw = sw / len(tabs)
    for i, name in enumerate(tabs):
        cx = i * cw + cw / 2
        cy = y + bar_h * 0.32
        # icon as simple rounded rect or shape
        col = GOLD if i == active_idx else MUTED
        ic_sz = int(sw * 0.04)
        d.rounded_rectangle((cx - ic_sz, cy - ic_sz, cx + ic_sz, cy + ic_sz),
                            radius=ic_sz // 3, outline=col, width=4)
        tw, _ = text_size(f, name)
        d.text((cx - tw / 2, cy + ic_sz + 8), name, font=f, fill=col)
    # Home indicator pill (subtle, like real iPhone)
    pill_w = int(sw * 0.36)
    pill_h = max(5, int(sh * 0.005))
    pill_x = (sw - pill_w) // 2
    pill_y = sh - safe_bottom // 2 - pill_h // 2
    d.rounded_rectangle(
        (pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
        radius=pill_h // 2, fill=(28, 28, 30),
    )


# ----------- Bills ----------------------------------------------------------


def draw_bill_row(canvas, x, y, w, h, name, amount, due, category_tint, status):
    d = ImageDraw.Draw(canvas)
    shadowed_card(canvas, (x, y, x + w, y + h), 18, CARD, 12, 35)
    d = ImageDraw.Draw(canvas)
    # category swatch
    rounded_rect(d, (x + 12, y + 12, x + 12 + 8, y + h - 12), 4, fill=category_tint)
    f_name = font(LATO_BOLD, h // 4)
    f_meta = font(LATO_REG, h // 6)
    f_amt  = font(LATO_BLACK, h // 3)
    d.text((x + 36, y + 14), name, font=f_name, fill=TEXT)
    d.text((x + 36, y + 14 + h // 4 + 4), due, font=f_meta, fill=MUTED)
    # amount right
    aw, _ = text_size(f_amt, amount)
    d.text((x + w - aw - 18, y + 18), amount, font=f_amt, fill=TEXT)
    # status pill
    sw_ = h // 2 + 30
    sx = x + w - sw_ - 18
    sy = y + h - h // 3 - 10
    if status == "Paid":
        fill = HOUSEHOLD
    elif status == "Overdue":
        fill = DANGER
    else:
        fill = (245, 245, 248)
    rounded_rect(d, (sx, sy, sx + sw_, sy + h // 3), h // 6, fill=fill)
    f_s = font(LATO_BOLD, h // 5)
    tw, th = text_size(f_s, status)
    d.text((sx + sw_ / 2 - tw / 2, sy + h // 6 - th / 2 - 1),
           status, font=f_s,
           fill=(255, 255, 255) if status != "Unpaid" else MUTED)


def draw_bills(canvas, sw, sh):
    canvas.paste(Image.new("RGB", (sw, sh), SURFACE))
    d = ImageDraw.Draw(canvas)
    draw_status_bar(d, sw)
    pad = sw // 18
    y = int(sh * 0.075)
    f_title = font(LATO_BLACK, sw // 12)
    d.text((pad, y), "Bills", font=f_title, fill=TEXT)
    # plus button
    cx = sw - pad - 32
    cy = y + sw // 28
    d.ellipse((cx - 36, cy - 36, cx + 36, cy + 36), fill=GOLD)
    d.line((cx - 18, cy, cx + 18, cy), fill="white", width=6)
    d.line((cx, cy - 18, cx, cy + 18), fill="white", width=6)
    y += sw // 9
    draw_filter_pills(d, pad, y, sw - 2 * pad, int(sw * 0.085))
    y += int(sw * 0.085) + 18
    # Search
    sh_h = int(sw * 0.085)
    rounded_rect(d, (pad, y, sw - pad, y + sh_h), sh_h // 2, fill=SUBTLE)
    f_p = font(LATO_REG, sh_h // 2 - 4)
    d.text((pad + 28, y + sh_h // 2 - (sh_h // 2 - 4) // 2 - 4),
           "Search bills…", font=f_p, fill=MUTED)
    y += sh_h + 18
    bills = [
        ("Rent",                 "$1,850.00", "Due in 2 days · Household",  HOUSEHOLD, "Unpaid"),
        ("Electric Bill",         "$142.50", "Due Apr 30 · Auto-pay",       HOUSEHOLD, "Unpaid"),
        ("Internet",              "$89.99",  "3 days overdue · Household",  HOUSEHOLD, "Overdue"),
        ("Adobe Creative Cloud",  "$54.99",  "Due May 10 · Auto-pay",       AMBER,    "Unpaid"),
        ("Quarterly Taxes",      "$2,400.00","Due May 18 · Business",       AMBER,    "Unpaid"),
        ("Phone Plan",            "$78.40",  "Paid Apr 12 · Household",     HOUSEHOLD, "Paid"),
        ("LLC Annual Fee",        "$300.00", "Due Jun 1 · Business",        AMBER,    "Unpaid"),
    ]
    bh = int(sw * 0.22)
    gap = 12
    bar_reserve = int(sw * 0.16 + sh * 0.05)  # tab bar + home indicator safe area
    for i, (n, amt, due, t, st) in enumerate(bills):
        if y + bh > sh - bar_reserve - 16:
            break
        draw_bill_row(canvas, pad, y, sw - 2 * pad, bh, n, amt, due, t, st)
        y += bh + gap
    draw_tab_bar(d, sw, sh, active_idx=1)


# ----------- Calendar -------------------------------------------------------


def draw_calendar(canvas, sw, sh):
    canvas.paste(Image.new("RGB", (sw, sh), SURFACE))
    d = ImageDraw.Draw(canvas)
    draw_status_bar(d, sw)
    pad = sw // 18
    y = int(sh * 0.075)
    f_title = font(LATO_BLACK, sw // 12)
    d.text((pad, y), "Calendar", font=f_title, fill=TEXT)
    y += sw // 9
    # month header
    f_mo = font(LATO_BOLD, sw // 16)
    d.text((pad, y), "April 2026", font=f_mo, fill=TEXT)
    # nav arrows
    rx = sw - pad
    cy = y + sw // 32
    d.polygon([(rx - 24, cy - 18), (rx - 24, cy + 18), (rx - 6, cy)], fill=GOLD)
    d.polygon([(rx - 96, cy - 18), (rx - 96, cy + 18), (rx - 114, cy)], fill=GOLD)
    y += sw // 12
    # weekday header
    f_wd = font(LATO_SEMI, sw // 36)
    days = ["S", "M", "T", "W", "T", "F", "S"]
    cell_w = (sw - 2 * pad) / 7
    for i, dy in enumerate(days):
        tw, _ = text_size(f_wd, dy)
        d.text((pad + i * cell_w + cell_w / 2 - tw / 2, y), dy, font=f_wd, fill=MUTED)
    y += sw // 22
    # 6 rows of dates (April 2026 starts on Wednesday).
    # Use a fixed compact cell height so the calendar doesn't sprawl down
    # with empty space when there are only 30 days to show.
    f_d = font(LATO_BOLD, sw // 22)
    today = 28
    start_offset = 3  # Wed = index 3
    rows = 6
    bar_reserve = int(sw * 0.16 + sh * 0.05)
    cell_h = min((sh - y - bar_reserve - 16) / rows, sw * 0.16)
    for r in range(rows):
        for c in range(7):
            idx = r * 7 + c
            day = idx - start_offset + 1
            if day < 1 or day > 30:
                continue
            cx = pad + c * cell_w + cell_w / 2
            cy = y + r * cell_h + cell_h / 2 - 4
            if day == today:
                d.ellipse((cx - 26, cy - 26, cx + 26, cy + 26), fill=GOLD)
                col = (255, 255, 255)
            else:
                col = TEXT
            tw, th = text_size(f_d, str(day))
            d.text((cx - tw / 2, cy - th / 2), str(day), font=f_d, fill=col)
            # bill markers (random-ish)
            markers = []
            if day in (2, 7, 12, 18, 22, 25, 30):
                markers.append(HOUSEHOLD)
            if day in (10, 18, 28):
                markers.append(AMBER)
            if day == 22:
                markers.append(DANGER)
            if markers:
                mx = cx - len(markers) * 9
                my = cy + 30
                for m in markers:
                    small_dot(d, mx, my, 7, m)
                    mx += 18

    # Today's bills preview card
    grid_bottom = int(y + rows * cell_h)
    if grid_bottom < sh - bar_reserve - 40:
        gy = grid_bottom + 24
        gh = int(sw * 0.5)
        avail = sh - bar_reserve - 16 - gy
        gh = int(min(gh, max(0, avail)))
        if gh > 80:
            shadowed_card(canvas, (pad, gy, sw - pad, gy + gh), 22, CARD, 14, 40)
            d = ImageDraw.Draw(canvas)
            f_t = font(LATO_BLACK, sw // 22)
            f_l = font(LATO_REG, sw // 32)
            f_a = font(LATO_BOLD, sw // 26)
            d.text((pad + 22, gy + 18), "Tue, Apr 28", font=f_t, fill=TEXT)
            d.text((pad + 22, gy + 18 + sw // 22 + 6),
                   "2 bills due today", font=f_l, fill=MUTED)
            # 2 bill rows inside the card
            ry = gy + 18 + sw // 22 + 6 + sw // 26
            for nm, amt, tnt in [
                ("Rent",         "$1,850.00", HOUSEHOLD),
                ("Phone Plan",   "$78.40",    HOUSEHOLD),
            ]:
                if ry + sw // 18 > gy + gh - 12:
                    break
                small_dot(d, pad + 32, ry + sw // 60, 8, tnt)
                d.text((pad + 56, ry), nm, font=f_l, fill=TEXT)
                aw, _ = text_size(f_a, amt)
                d.text((sw - pad - 22 - aw, ry), amt, font=f_a, fill=TEXT)
                ry += sw // 16

    d = ImageDraw.Draw(canvas)
    draw_tab_bar(d, sw, sh, active_idx=2)


# ----------- Reports --------------------------------------------------------


def draw_reports(canvas, sw, sh):
    canvas.paste(Image.new("RGB", (sw, sh), SURFACE))
    d = ImageDraw.Draw(canvas)
    draw_status_bar(d, sw)
    pad = sw // 18
    y = int(sh * 0.075)
    f_title = font(LATO_BLACK, sw // 12)
    d.text((pad, y), "Reports", font=f_title, fill=TEXT)
    y += sw // 9
    draw_filter_pills(d, pad, y, sw - 2 * pad, int(sw * 0.085))
    y += int(sw * 0.085) + 18
    # Big total card
    th_ = int(sw * 0.36)
    shadowed_card(canvas, (pad, y, sw - pad, y + th_), 22, CARD, 14, 40)
    d = ImageDraw.Draw(canvas)
    f_l = font(LATO_REG, sw // 30)
    f_v = font(LATO_BLACK, int(sw * 0.13))
    d.text((pad + 24, y + 22), "TOTAL THIS MONTH", font=f_l, fill=MUTED)
    d.text((pad + 24, y + 60), "$5,218.39", font=f_v, fill=TEXT)
    # mini trend
    f_d_ = font(LATO_SEMI, sw // 32)
    d.text((pad + 24, y + th_ - 60), "↑ 12% vs last month",
           font=f_d_, fill=HOUSEHOLD)
    y += th_ + 18
    # Category breakdown bars
    f_h = font(LATO_BOLD, sw // 22)
    d.text((pad, y), "By Category", font=f_h, fill=TEXT)
    y += sw // 18
    cats = [
        ("Rent / Mortgage", 1850, HOUSEHOLD),
        ("Utilities",         320, HOUSEHOLD),
        ("Software",          165, AMBER),
        ("Taxes",            2400, AMBER),
        ("Internet / Phone",  168, HOUSEHOLD),
        ("Insurance",         315, HOUSEHOLD),
    ]
    max_v = max(v for _, v, _ in cats)
    f_n = font(LATO_SEMI, sw // 30)
    f_a = font(LATO_BOLD, sw // 30)
    for n, v, t in cats:
        bw = int((sw - 2 * pad) * (v / max_v) * 0.9)
        d.text((pad, y), n, font=f_n, fill=TEXT)
        amt = f"${v:,}"
        aw, _ = text_size(f_a, amt)
        d.text((sw - pad - aw, y), amt, font=f_a, fill=TEXT)
        y += sw // 28
        rounded_rect(d, (pad, y, pad + bw, y + 18), 9, fill=t)
        y += 30
    draw_tab_bar(d, sw, sh, active_idx=3)


# ----------- Settings -------------------------------------------------------


def draw_settings(canvas, sw, sh):
    canvas.paste(Image.new("RGB", (sw, sh), SURFACE))
    d = ImageDraw.Draw(canvas)
    draw_status_bar(d, sw)
    pad = sw // 18
    y = int(sh * 0.075)
    f_title = font(LATO_BLACK, sw // 12)
    d.text((pad, y), "Settings", font=f_title, fill=TEXT)
    y += sw // 9
    # Pro upsell card
    pro_h = int(sw * 0.26)
    shadowed_card(canvas, (pad, y, sw - pad, y + pro_h), 22, SACRED, 16, 50)
    d = ImageDraw.Draw(canvas)
    # real Tree-of-Life app icon
    cx = pad + pro_h // 2 + 8
    cy = y + pro_h // 2
    rr = pro_h // 2 - 18
    paste_real_logo(canvas, cx, cy, rr)
    d = ImageDraw.Draw(canvas)
    f_h = font(LATO_BLACK, sw // 18)
    f_b = font(LATO_REG, sw // 32)
    f_p = font(LATO_BOLD, sw // 26)
    d.text((cx + rr + 22, y + 24), "Upgrade to Pro", font=f_h, fill=(255, 255, 255))
    d.text((cx + rr + 22, y + 24 + sw // 18 + 6),
           "Unlimited bills, business tracking,",
           font=f_b, fill=(220, 220, 226))
    d.text((cx + rr + 22, y + 24 + sw // 18 + 6 + sw // 32 + 4),
           "reports, and cloud sync.",
           font=f_b, fill=(220, 220, 226))
    # PRO badge pill
    bp_w, bp_h = sw // 6, sw // 22
    bx = sw - pad - bp_w - 18
    by = y + 22
    rounded_rect(d, (bx, by, bx + bp_w, by + bp_h), bp_h // 2, fill=GOLD)
    f_pp = font(LATO_BLACK, bp_h - 16)
    d.text((bx + bp_w / 2 - 30, by + 6), "PRO", font=f_pp, fill=SACRED)
    y += pro_h + 18
    rows = [
        ("Notifications",    "Remind 3 days before"),
        ("Cloud Sync",       "On"),
        ("Account",          "you@example.com"),
        ("Restore Purchases","→"),
        ("Privacy Policy",   "→"),
        ("Terms of Use",     "→"),
        ("Support",          "demarquishinton@gmail.com"),
        ("Delete Account",   "→"),
    ]
    f_n = font(LATO_BOLD, sw // 26)
    f_v = font(LATO_REG, sw // 32)
    rh = int(sw * 0.105)
    # group container
    list_y = y
    list_h = rh * len(rows)
    shadowed_card(canvas, (pad, list_y, sw - pad, list_y + list_h),
                  22, CARD, 12, 30)
    d = ImageDraw.Draw(canvas)
    for i, (n, v) in enumerate(rows):
        ry = list_y + i * rh
        d.text((pad + 24, ry + rh / 2 - sw // 50),
               n, font=f_n,
               fill=DANGER if n == "Delete Account" else TEXT)
        vw, _ = text_size(f_v, v)
        d.text((sw - pad - 24 - vw, ry + rh / 2 - sw // 60),
               v, font=f_v, fill=MUTED)
        if i < len(rows) - 1:
            d.line((pad + 24, ry + rh, sw - pad - 24, ry + rh),
                   fill=SUBTLE, width=1)
    draw_tab_bar(d, sw, sh, active_idx=4)


# ----------- Paywall --------------------------------------------------------


def draw_paywall(canvas, sw, sh):
    # gradient background
    canvas.paste(vertical_gradient((sw, sh), SACRED, (30, 24, 18)))
    d = ImageDraw.Draw(canvas)
    draw_status_bar(d, sw, color=(255, 255, 255))
    pad = sw // 18
    y = int(sh * 0.085)
    # close X (drawn as two strokes for font-coverage independence)
    cxx, cyy = pad + 14, y + 6
    rs = sw // 36
    d.line((cxx - rs, cyy - rs, cxx + rs, cyy + rs),
           fill=(220, 220, 226), width=4)
    d.line((cxx - rs, cyy + rs, cxx + rs, cyy - rs),
           fill=(220, 220, 226), width=4)
    y += sw // 14
    # real Tree-of-Life app icon
    cx = sw // 2
    rr = sw // 7
    paste_real_logo(canvas, cx, y + rr, rr)
    d = ImageDraw.Draw(canvas)
    y += 2 * rr + 24
    # Headline
    f_h = font(LATO_BLACK, sw // 11)
    f_s = font(LATO_REG, sw // 26)
    head = "Sacred Bill Tracker Pro"
    sub  = "Track every household and business"
    sub2 = "bill, with sync across devices."
    for line, fnt, col in [
        (head, f_h, (255, 255, 255)),
        (sub,  f_s, (220, 220, 226)),
        (sub2, f_s, (220, 220, 226)),
    ]:
        tw, th = text_size(fnt, line)
        d.text((cx - tw / 2, y), line, font=fnt, fill=col)
        y += th + 12
    y += 12
    # Plan picker (yearly highlighted)
    plan_w = sw - 2 * pad
    plan_h = int(sw * 0.16)
    # yearly
    rounded_rect(d, (pad, y, pad + plan_w, y + plan_h), 22,
                 fill=(255, 255, 255), outline=GOLD, width=4)
    f_pn = font(LATO_BLACK, sw // 22)
    f_pp = font(LATO_BOLD, sw // 20)
    f_pl = font(LATO_REG, sw // 36)
    d.text((pad + 22, y + 18), "Yearly", font=f_pn, fill=TEXT)
    d.text((pad + 22, y + 18 + sw // 22 + 4),
           "$39.99 / year · 7-day free trial", font=f_pl, fill=MUTED)
    save_w = sw // 5
    save_x = pad + plan_w - save_w - 18
    rounded_rect(d, (save_x, y + plan_h / 2 - sw // 30,
                     save_x + save_w, y + plan_h / 2 + sw // 30),
                 sw // 30, fill=GOLD)
    f_sv = font(LATO_BLACK, sw // 36)
    d.text((save_x + sw // 50, y + plan_h / 2 - sw // 60),
           "SAVE 33%", font=f_sv, fill=SACRED)
    y += plan_h + 14
    # monthly
    rounded_rect(d, (pad, y, pad + plan_w, y + plan_h), 22,
                 fill=(40, 40, 44), outline=(70, 70, 76), width=2)
    d.text((pad + 22, y + 18), "Monthly", font=f_pn, fill=(255, 255, 255))
    d.text((pad + 22, y + 18 + sw // 22 + 4),
           "$4.99 / month · 7-day free trial", font=f_pl, fill=(200, 200, 206))
    y += plan_h + 28
    # CTA
    cta_h = int(sw * 0.13)
    rounded_rect(d, (pad, y, sw - pad, y + cta_h), cta_h // 2, fill=GOLD)
    f_c = font(LATO_BLACK, sw // 18)
    txt = "Start 7 days free"
    tw, th = text_size(f_c, txt)
    d.text((sw / 2 - tw / 2, y + cta_h / 2 - th / 2 - 2),
           txt, font=f_c, fill=SACRED)
    y += cta_h + 18
    # Disclosure
    f_dis = font(LATO_REG, sw // 42)
    disc = ("Auto-renews until canceled. Manage in Settings → Apple ID.")
    tw, _ = text_size(f_dis, disc)
    d.text((sw / 2 - tw / 2, y), disc, font=f_dis, fill=(180, 180, 188))
    y += sw // 26
    # Restore + links
    f_r = font(LATO_BOLD, sw // 36)
    rest = "Restore Purchases"
    tw, _ = text_size(f_r, rest)
    d.text((sw / 2 - tw / 2, y), rest, font=f_r, fill=GOLD)
    y += sw // 24
    f_lk = font(LATO_REG, sw // 42)
    lks = "Terms  ·  Privacy"
    tw, _ = text_size(f_lk, lks)
    d.text((sw / 2 - tw / 2, y), lks, font=f_lk, fill=(180, 180, 188))
    y += sw // 18

    # Feature list — fills the rest of the screen with pro perks
    perks = [
        ("Unlimited bills",                   GOLD),
        ("Track household + business",        LIME),
        ("Reports + monthly cash flow",       HOUSEHOLD),
        ("Cloud sync across iPhone & iPad",   AMBER),
        ("Cancel any time, no questions",     GOLD),
    ]
    f_p = font(LATO_SEMI, sw // 28)
    for label, col in perks:
        if y > sh - sw // 8:
            break
        # check icon
        cy0 = y + sw // 56
        d.line((pad + 16, cy0, pad + 30, cy0 + 14), fill=col, width=4)
        d.line((pad + 30, cy0 + 14, pad + 56, cy0 - 12), fill=col, width=4)
        d.text((pad + 76, y), label, font=f_p, fill=(235, 235, 240))
        y += sw // 18


# ----------------------------------------------------------------------------
# Marketing layout — composes a screen mockup onto a branded background
# ----------------------------------------------------------------------------


SCREENS = [
    ("Dashboard",  "Every Bill,",  "Household and business in one place.",  draw_dashboard, GOLD),
    ("Bills",      "Track What's Due,",  "Filter by household or business.",  draw_bills,    HOUSEHOLD),
    ("Calendar",   "See the Whole Month",  "Per-day markers. Never get caught off guard.",  draw_calendar, LIME),
    ("Reports",    "Cash Flow at a Glance",  "Monthly totals and category breakdowns.",     draw_reports,  AMBER),
    ("Settings",   "You're in Control",  "Reminders, sync, account — your data, your call.",draw_settings, GOLD),
    ("Paywall",    "7 Days Free, Then Pro",  "$4.99 / month · $39.99 / year. Cancel any time.", draw_paywall,  GOLD),
]


def render_screen(screen_renderer, sw, sh) -> Image.Image:
    canvas = Image.new("RGBA", (sw, sh), (255, 255, 255, 255))
    screen_renderer(canvas, sw, sh)
    return canvas.convert("RGBA")


def compose_marketing(out_w, out_h, headline, subhead, screen_img, accent, is_pad):
    img = Image.new("RGB", (out_w, out_h))
    # Deep, clean black gradient — top pure black, bottom slightly warmer
    # near-black for depth without washed-out tones.
    bg = vertical_gradient((out_w, out_h), (0, 0, 0), (10, 8, 12))
    img.paste(bg, (0, 0))
    d = ImageDraw.Draw(img)

    # decorative top gradient accent line
    accent_h = int(out_h * 0.004)
    d.rectangle((0, int(out_h * 0.005),
                 out_w, int(out_h * 0.005) + accent_h),
                fill=accent)

    # Headline + subhead block at top — more breathing room from top edge.
    head_top = int(out_h * 0.048)
    f_head = font(LATO_BLACK, int(out_w * (0.092 if not is_pad else 0.064)))
    f_sub  = font(LATO_REG,   int(out_w * (0.040 if not is_pad else 0.030)))
    headlines = headline.split("\n") if "\n" in headline else [headline]
    y = head_top
    for line in headlines:
        tw, th = text_size(f_head, line)
        d.text((out_w / 2 - tw / 2, y), line, font=f_head, fill=(255, 255, 255))
        y += th + 10
    # gold underline mark
    uw = int(out_w * (0.13 if not is_pad else 0.10))
    d.rectangle((out_w / 2 - uw / 2, y + 8,
                 out_w / 2 + uw / 2, y + 8 + max(7, int(out_w * 0.009))),
                fill=accent)
    y += 30 if not is_pad else 24
    sub_lines = wrap_to_lines(subhead, f_sub, int(out_w * 0.86))
    for line in sub_lines:
        tw, th = text_size(f_sub, line)
        d.text((out_w / 2 - tw / 2, y), line, font=f_sub, fill=(232, 232, 237))
        y += th + 4

    # MUCH larger device frame — fill ~90% of canvas width.
    # Constraint: device aspect 2.165 means very tall, so device_h must be
    # whatever fits with width=0.90 — and we anchor it below the headline area.
    device_w = int(out_w * (0.90 if not is_pad else 0.55))
    device_h = int(device_w * 2.165)
    # If that would overflow canvas height, cap by height instead.
    if device_h > int(out_h * 0.84):
        device_h = int(out_h * 0.84)
        device_w = int(device_h / 2.165)
    device_x = (out_w - device_w) // 2
    device_y = int(out_h * (0.14 if not is_pad else 0.14))

    # device shadow — two-layer soft realistic shadow
    # Outer ambient (large soft glow)
    sh_outer = Image.new("RGBA", (device_w + 320, device_h + 320), (0, 0, 0, 0))
    sd1 = ImageDraw.Draw(sh_outer)
    sd1.rounded_rectangle((160, 180, 160 + device_w, 180 + device_h),
                          radius=int(device_w * 0.13), fill=(0, 0, 0, 90))
    sh_outer = sh_outer.filter(ImageFilter.GaussianBlur(95))
    img.paste(sh_outer, (device_x - 160, device_y - 160), sh_outer)
    # Inner cast (tighter darker)
    sh_inner = Image.new("RGBA", (device_w + 140, device_h + 140), (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(sh_inner)
    sd2.rounded_rectangle((70, 90, 70 + device_w, 90 + device_h),
                          radius=int(device_w * 0.13), fill=(0, 0, 0, 130))
    sh_inner = sh_inner.filter(ImageFilter.GaussianBlur(40))
    img.paste(sh_inner, (device_x - 70, device_y - 70), sh_inner)

    # device body (dark frame)
    d2 = ImageDraw.Draw(img)
    rounded_rect(d2, (device_x, device_y, device_x + device_w, device_y + device_h),
                 int(device_w * 0.13), fill=(8, 8, 10))
    # inner screen
    bezel = int(device_w * 0.025)
    sx0 = device_x + bezel
    sy0 = device_y + bezel
    sx1 = device_x + device_w - bezel
    sy1 = device_y + device_h - bezel
    screen_w = sx1 - sx0
    screen_h = sy1 - sy0
    # render screen content at the screen size
    content = render_screen_for_size(screen_img, screen_w, screen_h)
    # mask to rounded corners
    mask = Image.new("L", (screen_w, screen_h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, screen_w, screen_h),
                         radius=int(device_w * 0.10), fill=255)
    img.paste(content, (sx0, sy0), mask)

    return img


def render_screen_for_size(screen_renderer, w, h):
    return render_screen(screen_renderer, w, h).convert("RGB")


def wrap_to_lines(text, fnt, max_w):
    words = text.split()
    lines, line = [], ""
    for word in words:
        candidate = (line + " " + word).strip()
        if text_size(fnt, candidate)[0] <= max_w:
            line = candidate
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


# ----------------------------------------------------------------------------
# Driver
# ----------------------------------------------------------------------------


def main():
    out_root = os.environ.get(
        "SBT_SCREENSHOT_OUT",
        "/sessions/keen-awesome-dirac/mnt/SACRED BILL TRACKER/_AppStoreScreenshots_generated",
    )
    for device in DEVICES:
        out_dir = os.path.join(out_root, device.name)
        os.makedirs(out_dir, exist_ok=True)
        for i, (name, headline, subhead, renderer, accent) in enumerate(SCREENS, start=1):
            img = compose_marketing(
                device.out_size[0], device.out_size[1],
                headline, subhead, renderer, accent, device.is_pad,
            )
            out_path = os.path.join(out_dir, f"{i:02d}_{name}.png")
            img.save(out_path, "PNG", optimize=True)
            print(f"[ok] {device.name}/{i:02d}_{name}.png  {device.out_size}")


if __name__ == "__main__":
    main()
