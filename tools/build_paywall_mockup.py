#!/usr/bin/env python3
"""
Generate a paywall screen mockup that visually matches Sacred Bill Tracker's
actual design language (pure black bg, gold accent, dark cards, tree-of-life
logo, pill tab bar at bottom for iPhone / top for iPad).

Output:
  _real_screens/06_Paywall_iphone.png   (1179 × 2556 — matches IMG_18xx)
  _real_screens/06_Paywall_ipad.png     (2064 × 2752 — matches IMG_004x portrait)
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

PROJECT = Path("/sessions/wizardly-youthful-maxwell/mnt/SACRED BILL TRACKER")
DST     = PROJECT / "_real_screens"

LOGO_PATH = PROJECT / "SacredBillTracker/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png"

LATO_BLACK = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"
LATO_BOLD  = "/usr/share/fonts/truetype/lato/Lato-Bold.ttf"
LATO_REG   = "/usr/share/fonts/truetype/lato/Lato-Regular.ttf"
LATO_MED   = "/usr/share/fonts/truetype/lato/Lato-Medium.ttf"

# Colors lifted from real screenshots
BLACK       = (0, 0, 0)
CARD        = (22, 22, 26)        # dark card on black
CARD_HI     = (32, 32, 38)        # selected card
GOLD        = (212, 175, 55)
GOLD_LIGHT  = (228, 192, 72)
GREEN       = (91, 153, 67)
WHITE       = (255, 255, 255)
GRAY_TEXT   = (160, 160, 168)
GRAY_LABEL  = (110, 110, 118)
ROOT_GOLD   = (190, 145, 50)


def font(path, size):
    return ImageFont.truetype(path, size)


def text_w(d, s, f):
    bb = d.textbbox((0, 0), s, font=f)
    return bb[2] - bb[0]


def text_h(d, s, f):
    bb = d.textbbox((0, 0), s, font=f)
    return bb[3] - bb[1]


def draw_status_bar(d: ImageDraw.ImageDraw, W: int, time_text: str = "10:01"):
    """Match the iPhone Dynamic Island look at top."""
    f = font(LATO_BOLD, max(28, W // 36))
    d.text((W * 0.06, W * 0.045), time_text, font=f, fill=WHITE)
    # Right side: signal + battery (simple shapes)
    bx = int(W * 0.78)
    by = int(W * 0.05)
    sz = max(8, W // 70)
    for i in range(4):
        h = int(sz * (0.4 + 0.2 * i))
        d.rectangle((bx + i * sz * 1.3, by + sz - h,
                     bx + i * sz * 1.3 + sz, by + sz),
                    fill=WHITE)
    # Battery
    bx2 = int(W * 0.90)
    d.rounded_rectangle((bx2, by, bx2 + int(W * 0.07), by + sz + 4),
                        radius=4, outline=WHITE, width=2)
    d.rounded_rectangle((bx2 + 4, by + 4,
                         bx2 + int(W * 0.07) - 4, by + sz),
                        radius=2, fill=(76, 217, 100))


def paste_logo(canvas: Image.Image, cx: int, cy: int, r: int):
    if not LOGO_PATH.exists():
        d = ImageDraw.Draw(canvas)
        d.ellipse((cx - r, cy - r, cx + r, cy + r),
                  outline=GOLD, width=max(4, r // 20))
        return
    logo = Image.open(LOGO_PATH).convert("RGBA").resize((r * 2, r * 2),
                                                        Image.LANCZOS)
    canvas.paste(logo, (cx - r, cy - r), logo)


def draw_pill_tabbar_iphone(canvas: Image.Image, W: int, H: int, active: int):
    """Pill-shaped frosted tab bar matching the real app."""
    d = ImageDraw.Draw(canvas)
    bar_h = int(W * 0.155)
    side  = int(W * 0.04)
    bottom_inset = int(H * 0.018)
    bar_top  = H - bar_h - bottom_inset
    bar_x0   = side
    bar_x1   = W - side
    pill_r   = bar_h // 2

    # Subtle outer pill
    d.rounded_rectangle((bar_x0, bar_top, bar_x1, bar_top + bar_h),
                        radius=pill_r, fill=(28, 28, 32))

    tabs = ["Dashboard", "Bills", "Calendar", "Reports", "Settings"]
    tw = (bar_x1 - bar_x0) / len(tabs)
    f_label = font(LATO_MED, max(18, W // 50))

    # Selected pill
    sel_cx = bar_x0 + tw * active + tw / 2
    sel_w  = int(tw * 0.86)
    sel_h  = int(bar_h * 0.78)
    sel_x0 = int(sel_cx - sel_w / 2)
    sel_y0 = bar_top + (bar_h - sel_h) // 2
    d.rounded_rectangle((sel_x0, sel_y0, sel_x0 + sel_w, sel_y0 + sel_h),
                        radius=sel_h // 2, fill=(60, 50, 25))

    for i, name in enumerate(tabs):
        cx = bar_x0 + tw * i + tw / 2
        cy = bar_top + bar_h * 0.32
        col = GOLD if i == active else GRAY_TEXT
        # Icon: simple filled square as placeholder for tab icon
        ic_sz = int(W * 0.045)
        d.rounded_rectangle((cx - ic_sz, cy - ic_sz / 2,
                             cx + ic_sz, cy + ic_sz),
                            radius=ic_sz // 4, fill=col if i == active else col)
        # Label
        lw = text_w(d, name, f_label)
        d.text((cx - lw / 2, cy + ic_sz + 12), name, font=f_label, fill=col)

    # Home indicator
    pill_w = int(W * 0.36)
    pill_h = max(5, int(H * 0.005))
    pill_x = (W - pill_w) // 2
    pill_y = H - pill_h - int(bottom_inset * 0.4)
    d.rounded_rectangle((pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
                        radius=pill_h // 2, fill=WHITE)


def draw_pill_tabbar_ipad(canvas: Image.Image, W: int, H: int, active: int):
    """iPad has the tab bar at TOP center, BELOW the iOS status bar."""
    d = ImageDraw.Draw(canvas)
    bar_h = int(W * 0.04)
    bar_w = int(W * 0.40)
    bar_x = (W - bar_w) // 2
    bar_y = int(H * 0.025)  # below status bar
    d.rounded_rectangle((bar_x, bar_y, bar_x + bar_w, bar_y + bar_h),
                        radius=bar_h // 2, fill=(28, 28, 32))
    tabs = ["Dashboard", "Bills", "Calendar", "Reports", "Settings"]
    tw = bar_w / len(tabs)
    sel_x = int(bar_x + tw * active)
    d.rounded_rectangle((sel_x + 4, bar_y + 3,
                         sel_x + int(tw) - 4, bar_y + bar_h - 3),
                        radius=(bar_h - 6) // 2, fill=(60, 60, 66))
    f = font(LATO_MED, max(20, int(bar_h * 0.55)))
    for i, name in enumerate(tabs):
        cx = bar_x + tw * i + tw / 2
        col = WHITE if i == active else GRAY_TEXT
        lw = text_w(d, name, f)
        d.text((cx - lw / 2, bar_y + (bar_h - text_h(d, name, f)) / 2 - 2),
               name, font=f, fill=col)


def draw_paywall_content(canvas: Image.Image, W: int, H: int, is_pad: bool):
    d = ImageDraw.Draw(canvas)

    # ---- Brand row at top (Sacred Bill Tracker + logo) ----
    if is_pad:
        top_y = int(H * 0.10)
    else:
        top_y = int(H * 0.10)

    logo_r = int(W * (0.06 if is_pad else 0.10))
    logo_cx = W // 2
    logo_cy = top_y + logo_r
    paste_logo(canvas, logo_cx, logo_cy, logo_r)
    y = logo_cy + logo_r + int(W * (0.025 if is_pad else 0.04))

    # ---- Title ----
    f_title = font(LATO_BLACK, int(W * (0.045 if is_pad else 0.07)))
    title = "Sacred Bill Tracker"
    tw = text_w(d, title, f_title)
    d.text(((W - tw) / 2, y), title, font=f_title, fill=WHITE)
    y += text_h(d, title, f_title) + int(W * 0.012)

    # Subtitle "Upgrade to Premium"
    f_sub = font(LATO_BOLD, int(W * (0.030 if is_pad else 0.045)))
    sub = "Upgrade to Premium"
    tw = text_w(d, sub, f_sub)
    d.text(((W - tw) / 2, y), sub, font=f_sub, fill=GOLD)
    y += text_h(d, sub, f_sub) + int(W * (0.014 if is_pad else 0.020))

    # ---- Benefits list ----
    benefits = [
        ("Unlimited bills",         "Track every household + business bill"),
        ("Advanced reports",        "Cash flow, trends, category breakdowns"),
        ("Sync across devices",     "iPhone, iPad, and the web"),
        ("Smart reminders",         "Stay ahead of every due date"),
    ]
    f_b_head = font(LATO_BOLD, int(W * (0.025 if is_pad else 0.038)))
    f_b_sub  = font(LATO_REG,  int(W * (0.018 if is_pad else 0.028)))
    pad_x = int(W * (0.10 if is_pad else 0.07))
    row_h = int(W * (0.07 if is_pad else 0.105))

    for label, desc in benefits:
        # Gold checkmark circle
        cy = y + row_h // 2
        cx = pad_x + int(W * 0.025)
        rr = int(W * (0.018 if is_pad else 0.028))
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=GOLD)
        # Check
        d.line((cx - rr * 0.5, cy,
                cx - rr * 0.1, cy + rr * 0.4),
               fill=BLACK, width=max(3, int(W * 0.004)))
        d.line((cx - rr * 0.1, cy + rr * 0.4,
                cx + rr * 0.55, cy - rr * 0.4),
               fill=BLACK, width=max(3, int(W * 0.004)))
        # Label + desc
        text_x = cx + rr + int(W * 0.020)
        d.text((text_x, y + int(row_h * 0.05)),
               label, font=f_b_head, fill=WHITE)
        d.text((text_x, y + int(row_h * 0.50)),
               desc,  font=f_b_sub,  fill=GRAY_TEXT)
        y += row_h + int(W * 0.005)

    y += int(W * (0.020 if is_pad else 0.030))

    # ---- Plan cards (Yearly highlighted, Monthly below) ----
    plans_x = int(W * (0.12 if is_pad else 0.06))
    plans_w = W - 2 * plans_x
    plan_h = int(W * (0.080 if is_pad else 0.115))

    # Yearly (selected — gold border)
    rect = (plans_x, y, plans_x + plans_w, y + plan_h)
    d.rounded_rectangle(rect, radius=int(plan_h * 0.18),
                        fill=CARD_HI, outline=GOLD, width=max(3, int(W * 0.004)))
    f_pn = font(LATO_BLACK, int(W * (0.030 if is_pad else 0.044)))
    f_pp = font(LATO_REG,   int(W * (0.020 if is_pad else 0.030)))
    d.text((plans_x + int(W * 0.025), y + int(plan_h * 0.18)),
           "Yearly · $39.99", font=f_pn, fill=WHITE)
    d.text((plans_x + int(W * 0.025), y + int(plan_h * 0.58)),
           "$3.33/month · 7-day free trial", font=f_pp, fill=GRAY_TEXT)
    # SAVE 33% pill on the right
    save_w = int(W * (0.10 if is_pad else 0.16))
    save_h = int(plan_h * 0.45)
    save_x = plans_x + plans_w - save_w - int(W * 0.025)
    save_y = y + (plan_h - save_h) // 2
    d.rounded_rectangle((save_x, save_y, save_x + save_w, save_y + save_h),
                        radius=save_h // 2, fill=GOLD)
    f_sv = font(LATO_BLACK, int(save_h * 0.55))
    save_t = "SAVE 33%"
    sw = text_w(d, save_t, f_sv)
    sh = text_h(d, save_t, f_sv)
    d.text((save_x + (save_w - sw) / 2, save_y + (save_h - sh) / 2 - 2),
           save_t, font=f_sv, fill=BLACK)

    y += plan_h + int(W * 0.012)

    # Monthly
    rect = (plans_x, y, plans_x + plans_w, y + plan_h)
    d.rounded_rectangle(rect, radius=int(plan_h * 0.18),
                        fill=CARD, outline=(60, 60, 66), width=2)
    d.text((plans_x + int(W * 0.025), y + int(plan_h * 0.18)),
           "Monthly · $4.99", font=f_pn, fill=WHITE)
    d.text((plans_x + int(W * 0.025), y + int(plan_h * 0.58)),
           "Billed monthly · cancel anytime", font=f_pp, fill=GRAY_TEXT)

    y += plan_h + int(W * (0.020 if is_pad else 0.030))

    # ---- CTA button ----
    cta_h = int(W * (0.075 if is_pad else 0.105))
    cta_x0 = plans_x
    cta_x1 = plans_x + plans_w
    d.rounded_rectangle((cta_x0, y, cta_x1, y + cta_h),
                        radius=cta_h // 2, fill=GOLD)
    f_cta = font(LATO_BLACK, int(cta_h * 0.42))
    cta_t = "Start 7-day free trial"
    tw = text_w(d, cta_t, f_cta)
    th = text_h(d, cta_t, f_cta)
    d.text(((W - tw) / 2, y + (cta_h - th) / 2 - 4),
           cta_t, font=f_cta, fill=BLACK)
    y += cta_h + int(W * 0.018)

    # Disclosure
    f_dis = font(LATO_REG, int(W * (0.014 if is_pad else 0.022)))
    disc = "Auto-renews until canceled. Manage in Settings."
    tw = text_w(d, disc, f_dis)
    d.text(((W - tw) / 2, y), disc, font=f_dis, fill=GRAY_LABEL)
    y += text_h(d, disc, f_dis) + int(W * 0.010)
    rest = "Restore Purchases   ·   Terms   ·   Privacy"
    f_r = font(LATO_BOLD, int(W * (0.014 if is_pad else 0.022)))
    tw = text_w(d, rest, f_r)
    d.text(((W - tw) / 2, y), rest, font=f_r, fill=GOLD_LIGHT)


def build_iphone_paywall() -> Image.Image:
    W, H = 1179, 2556
    canvas = Image.new("RGB", (W, H), BLACK)
    draw_status_bar(ImageDraw.Draw(canvas), W)
    draw_paywall_content(canvas, W, H, is_pad=False)
    draw_pill_tabbar_iphone(canvas, W, H, active=4)  # any tab; user will see paywall
    return canvas


def build_ipad_paywall() -> Image.Image:
    W, H = 2064, 2752
    canvas = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(canvas)
    # iPad status bar — anchored at very top, smaller font to avoid clash
    f = font(LATO_BOLD, 28)
    d.text((W * 0.04, 18), "11:03 PM", font=f, fill=WHITE)
    d.text((W * 0.115, 18), "Thu Apr 30", font=f, fill=WHITE)
    # Battery indicator right
    bx = int(W * 0.92); by = 18
    d.rounded_rectangle((bx, by, bx + 70, by + 28),
                        radius=5, outline=WHITE, width=2)
    d.rounded_rectangle((bx + 3, by + 3, bx + 60, by + 25),
                        radius=2, fill=(76, 217, 100))
    draw_pill_tabbar_ipad(canvas, W, H, active=4)
    draw_paywall_content(canvas, W, H, is_pad=True)
    return canvas


def main():
    iphone = build_iphone_paywall()
    iphone.save(DST / "06_Paywall_iphone.png", "PNG", optimize=True)
    print(f"  wrote {DST / '06_Paywall_iphone.png'}  {iphone.size}")

    ipad = build_ipad_paywall()
    ipad.save(DST / "06_Paywall_ipad.png", "PNG", optimize=True)
    print(f"  wrote {DST / '06_Paywall_ipad.png'}    {ipad.size}")


if __name__ == "__main__":
    main()
