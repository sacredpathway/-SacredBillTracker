#!/usr/bin/env python3
"""
Generate App-Store-ready PNGs for SacredBillTracker at all required device
sizes and deploy them to a clean Desktop/AppStoreScreenshots/ structure.

iPad strategy: render the same iPhone-aspect content (which matches what
the universal SwiftUI app actually renders), but inside a LARGER device
frame on the iPad canvas, plus a soft "halo" gradient + secondary brand
mark to fill negative space — App-Store-clean, no awkward clipping.
"""
from __future__ import annotations
import os, shutil, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

import generate_screenshots as gs  # noqa
from generate_screenshots import (  # noqa
    SACRED, GOLD, HOUSEHOLD, LIME, AMBER,
    LATO_BLACK, LATO_REG,
    font, text_size, vertical_gradient, rounded_rect,
    render_screen, wrap_to_lines,
    paste_real_logo,
    draw_dashboard, draw_bills, draw_calendar,
    draw_reports, draw_settings, draw_paywall,
)

PROJECT = Path("/sessions/wizardly-youthful-maxwell/mnt/SACRED BILL TRACKER")

SCREENS = [
    ("01_Dashboard.png", "Every Bill,",          "Household and business in one place.",  draw_dashboard, GOLD),
    ("02_Bills.png",     "Track What's Due",     "Filter by household or business.",       draw_bills,    HOUSEHOLD),
    ("03_Calendar.png",  "See the Whole Month",  "Per-day markers. Never get caught off guard.", draw_calendar, LIME),
    ("04_Reports.png",   "Cash Flow at a Glance","Monthly totals and category breakdowns.", draw_reports,  GOLD),
    ("05_Settings.png",  "You're in Control",    "Reminders, sync, account — your data, your call.", draw_settings, AMBER),
    ("06_Paywall.png",   "7 Days Free, Then Pro","$4.99 / month · $39.99 / year. Cancel any time.",  draw_paywall,  GOLD),
]

# ----------------------------------------------------------------------------
def compose_ipad_v2(out_w: int, out_h: int, headline: str, subhead: str,
                    screen_renderer, accent) -> Image.Image:
    """iPad layout: large iPhone-aspect mockup + radial gold halo + small
    secondary 'tree-of-life' watermark in side margin so the canvas reads
    intentional, not empty."""
    img = Image.new("RGB", (out_w, out_h))
    bg = vertical_gradient((out_w, out_h), (0, 0, 0), (10, 8, 12))
    img.paste(bg, (0, 0))

    # Soft radial gold halo behind the device for premium depth
    halo = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    cx, cy = out_w // 2, int(out_h * 0.55)
    rmax = int(min(out_w, out_h) * 0.55)
    for i in range(40):
        t = i / 40
        rr = int(rmax * (1 - t))
        a = int(40 * (1 - t))
        hd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr),
                   fill=(*GOLD, a))
    halo = halo.filter(ImageFilter.GaussianBlur(80))
    img = Image.alpha_composite(img.convert("RGBA"), halo).convert("RGB")
    d = ImageDraw.Draw(img)

    # ---- Top accent line + headline ----
    accent_h = max(4, int(out_h * 0.004))
    d.rectangle((0, int(out_h * 0.005), out_w, int(out_h * 0.005) + accent_h),
                fill=accent)
    head_top = int(out_h * 0.055)
    f_head = font(LATO_BLACK, int(out_w * 0.067))
    f_sub  = font(LATO_REG,   int(out_w * 0.030))
    y = head_top
    for line in headline.split("\n"):
        tw, th = text_size(f_head, line)
        d.text((out_w / 2 - tw / 2, y), line, font=f_head, fill=(255, 255, 255))
        y += th + 10
    uw = int(out_w * 0.10); uh = max(8, int(out_w * 0.006))
    d.rounded_rectangle(
        (out_w / 2 - uw / 2, y + 10, out_w / 2 + uw / 2, y + 10 + uh),
        radius=uh // 2, fill=accent,
    )
    y += uh + 26
    for line in wrap_to_lines(subhead, f_sub, int(out_w * 0.86)):
        tw, th = text_size(f_sub, line)
        d.text((out_w / 2 - tw / 2, y), line, font=f_sub, fill=(220, 220, 226))
        y += th + 6

    # ---- iPhone-aspect device on iPad canvas — sized to leave headline room ----
    iphone_aspect = 2.165  # h / w
    # Reserve ~15% top for headline area, ~3% bottom margin → device fits in 82% h
    device_h = int(out_h * 0.82)
    device_w = int(device_h / iphone_aspect)
    # If width exceeds 60% of canvas, cap (otherwise halo becomes invisible)
    if device_w > int(out_w * 0.60):
        device_w = int(out_w * 0.60)
        device_h = int(device_w * iphone_aspect)
    device_x = (out_w - device_w) // 2
    device_y = int(out_h * 0.155)

    # device shadow — two-layer soft realistic shadow
    sh_outer = Image.new("RGBA", (device_w + 360, device_h + 360), (0, 0, 0, 0))
    sd1 = ImageDraw.Draw(sh_outer)
    sd1.rounded_rectangle((180, 200, 180 + device_w, 200 + device_h),
                          radius=int(device_w * 0.13), fill=(0, 0, 0, 95))
    sh_outer = sh_outer.filter(ImageFilter.GaussianBlur(110))
    img.paste(sh_outer, (device_x - 180, device_y - 180), sh_outer)
    sh_inner = Image.new("RGBA", (device_w + 160, device_h + 160), (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(sh_inner)
    sd2.rounded_rectangle((80, 100, 80 + device_w, 100 + device_h),
                          radius=int(device_w * 0.13), fill=(0, 0, 0, 140))
    sh_inner = sh_inner.filter(ImageFilter.GaussianBlur(45))
    img.paste(sh_inner, (device_x - 80, device_y - 80), sh_inner)

    # device body
    d2 = ImageDraw.Draw(img)
    rounded_rect(d2, (device_x, device_y, device_x + device_w, device_y + device_h),
                 int(device_w * 0.13), fill=(8, 8, 10))
    bezel = int(device_w * 0.025)
    sx0 = device_x + bezel; sy0 = device_y + bezel
    sx1 = device_x + device_w - bezel; sy1 = device_y + device_h - bezel
    screen_w = sx1 - sx0; screen_h = sy1 - sy0
    content = render_screen(screen_renderer, screen_w, screen_h).convert("RGB")
    mask = Image.new("L", (screen_w, screen_h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, screen_w, screen_h),
                         radius=int(device_w * 0.10), fill=255)
    img.paste(content, (sx0, sy0), mask)

    # ---- Secondary tree-of-life watermark in side margins ----
    # Left side
    side_logo_r = int(device_w * 0.32)
    left_cx = device_x // 2
    left_cy = int(out_h * 0.55)
    if left_cx - side_logo_r > 20:
        # faded / low-opacity logo paste
        try:
            logo = gs._get_real_logo().resize(
                (side_logo_r * 2, side_logo_r * 2), Image.LANCZOS,
            ).copy()
            # reduce alpha
            r, g, b, a = logo.split()
            a = a.point(lambda p: int(p * 0.18))
            logo.putalpha(a)
            img_rgba = img.convert("RGBA")
            img_rgba.paste(logo, (left_cx - side_logo_r, left_cy - side_logo_r), logo)
            img = img_rgba.convert("RGB")
        except Exception:
            pass

    # ---- Small "Universal · iPhone & iPad" tag bottom center ----
    d3 = ImageDraw.Draw(img)
    f_tag = font(LATO_BLACK, int(out_w * 0.022))
    tag = "Universal · iPhone & iPad"
    tw, th = text_size(f_tag, tag)
    bx = (out_w - tw) // 2 - 22
    by = int(out_h * 0.965) - th - 12
    d3.rounded_rectangle((bx, by, bx + tw + 44, by + th + 24),
                         radius=24, fill=(255, 255, 255, 0),
                         outline=(*GOLD, 255), width=2)
    d3.text(((out_w - tw) / 2, by + 10), tag, font=f_tag, fill=GOLD)

    return img


def render_set(size: tuple[int, int], dst_dir: Path, kind: str) -> list[Path]:
    out_w, out_h = size
    dst_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for fname, headline, subhead, renderer, accent in SCREENS:
        if kind == "ipad":
            img = compose_ipad_v2(out_w, out_h, headline, subhead, renderer, accent)
        else:
            img = gs.compose_marketing(
                out_w, out_h, headline, subhead, renderer, accent, is_pad=False,
            )
        out = dst_dir / fname
        img.save(out, "PNG", optimize=True)
        written.append(out)
        print(f"  wrote {out.relative_to(PROJECT)} ({out_w}x{out_h})")
    return written


def main():
    desktop_root = PROJECT / "AppStoreScreenshots_FINAL"
    desktop_root.mkdir(parents=True, exist_ok=True)

    print("[iPhone 6.7] 1290x2796")
    render_set((1290, 2796), desktop_root / "iPhone_6_7", "phone")
    print("[iPhone 6.9] 1320x2868")
    render_set((1320, 2868), desktop_root / "iPhone_6_9", "phone")
    print("[iPhone 6.1] 1170x2532")
    render_set((1170, 2532), desktop_root / "iPhone_6_1", "phone")
    print("[iPad 13] 2064x2752")
    render_set((2064, 2752), desktop_root / "iPad_13", "ipad")
    print("[iPad 12.9] 2048x2732")
    render_set((2048, 2732), desktop_root / "iPad_12_9", "ipad")

    print()
    print(f"Done. Output: {desktop_root}")


if __name__ == "__main__":
    main()
