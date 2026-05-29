"""
App Store mockups for Sacred Bill Tracker — premium polish pass.

- iPhone: 1320 x 2868   (iPhone 17 Pro Max)
- iPad:   2064 x 2752   (iPad Pro 13" M5)

Design:
- Clean light Apple-style gradient (NO beige), subtle warm radial accent
- Device fills 88-90% of width, centered, soft drop shadow
- Bold marketing headline at the top
- Screenshot brightened/contrast-boosted for crispness
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance
from pathlib import Path
import numpy as np
import re

ROOT = Path("/sessions/sleepy-charming-dirac/mnt/SacredBillTracker/_mockups_src")
OUT  = Path("/sessions/sleepy-charming-dirac/mnt/SacredBillTracker/_mockups_out")

# Premium gradient: cool white → very light blue-gray
GRAD_TOP = (255, 255, 255)   # pure white
GRAD_MID = (244, 247, 252)
GRAD_BOT = (226, 232, 242)   # cool gray-blue

# Subtle warm gold radial accent behind device — keeps brand without beige bg
ACCENT_COLOR = (212, 168, 84)   # Sacred Bill Tracker gold
ACCENT_ALPHA = 28               # very subtle

DEVICE_BLACK   = (16, 16, 18)
DEVICE_HILITE  = (52, 54, 58)   # subtle frame highlight stroke
DEVICE_INNER   = (4, 4, 6)
SHADOW_COLOR   = (12, 24, 50, 70)

HEADLINE_COLOR = (24, 28, 38)   # near-black, slight cool tint

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

HEADLINES = {
    "01_dashboard": "See Your Spending Clearly",
    "02_bills":     "Track Everything In One Place",
    "03_edit_bill": "Simple Bill Management",
    "04_reports":   "Stay Organized Every Month",
    "05_settings":  "Never Miss Another Bill",
}

IPHONE_LABEL = {
    "18.14.21": "01_dashboard",
    "18.16.26": "02_bills",
    "18.22.23": "03_edit_bill",
    "18.27.45": "04_reports",
    "18.31.58": "05_settings",
}
IPAD_LABEL = {
    "15.40.37": "01_dashboard",
    "16.01.16": "02_bills",
    "16.12.28": "03_edit_bill",
    "16.14.06": "04_reports",
    "16.15.19": "05_settings",
}


def time_key(name: str) -> str:
    m = re.search(r"at (\d\d\.\d\d\.\d\d)", name)
    return m.group(1) if m else ""


# -------- background ------------------------------------------------------

def make_background(w: int, h: int) -> Image.Image:
    """Premium Apple-style gradient with subtle warm gold radial accent."""
    # 3-stop vertical gradient using numpy
    t = np.linspace(0, 1, h, dtype=np.float32)
    top  = np.array(GRAD_TOP, dtype=np.float32)
    mid  = np.array(GRAD_MID, dtype=np.float32)
    bot  = np.array(GRAD_BOT, dtype=np.float32)

    # blend top->mid for first half, mid->bot for second half
    col = np.zeros((h, 3), dtype=np.float32)
    half = h // 2
    t1 = np.linspace(0, 1, half, dtype=np.float32)[:, None]
    t2 = np.linspace(0, 1, h - half, dtype=np.float32)[:, None]
    col[:half] = top * (1 - t1) + mid * t1
    col[half:] = mid * (1 - t2) + bot * t2

    arr = np.broadcast_to(col[:, None, :], (h, w, 3)).astype(np.uint8).copy()
    bg = Image.fromarray(arr, "RGB").convert("RGBA")

    # subtle warm radial accent behind where device will be
    accent = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ad = ImageDraw.Draw(accent)
    cx, cy = w // 2, int(h * 0.55)
    rmax = int(min(w, h) * 0.55)
    ad.ellipse((cx - rmax, cy - rmax, cx + rmax, cy + rmax),
               fill=(*ACCENT_COLOR, ACCENT_ALPHA))
    accent = accent.filter(ImageFilter.GaussianBlur(radius=180))
    bg = Image.alpha_composite(bg, accent)
    return bg.convert("RGB")


# -------- device ----------------------------------------------------------

def rounded_mask(w: int, h: int, radius: int) -> Image.Image:
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1),
                                        radius=radius, fill=255)
    return m


def enhance_screenshot(img: Image.Image) -> Image.Image:
    """Brighten + crisp the screenshot slightly."""
    img = ImageEnhance.Brightness(img).enhance(1.03)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    img = ImageEnhance.Color(img).enhance(1.04)
    img = ImageEnhance.Sharpness(img).enhance(1.15)
    return img


def composite_device(canvas: Image.Image,
                     screenshot_path: Path,
                     frame_top_y: int,
                     frame_bottom_y: int,
                     frame_width: int,
                     bezel: int,
                     screen_radius: int,
                     frame_radius: int) -> None:
    """Place a device-framed screenshot inside the given vertical region."""
    cw, ch = canvas.size
    shot = Image.open(screenshot_path).convert("RGB")
    shot = enhance_screenshot(shot)
    sw, sh = shot.size

    # screen size (inside bezel)
    screen_w = frame_width - bezel * 2
    screen_h = int(sh * (screen_w / sw))

    # If exceeds vertical budget, scale by height
    max_h = (frame_bottom_y - frame_top_y) - bezel * 2
    if screen_h > max_h:
        screen_h = max_h
        screen_w = int(sw * (screen_h / sh))
        frame_width = screen_w + bezel * 2

    shot = shot.resize((screen_w, screen_h), Image.LANCZOS)
    screen_mask = rounded_mask(screen_w, screen_h, screen_radius)
    rounded_shot = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 0))
    rounded_shot.paste(shot, (0, 0), screen_mask)

    # frame plate
    frame_w = screen_w + bezel * 2
    frame_h = screen_h + bezel * 2
    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    # outer titanium body
    fd.rounded_rectangle((0, 0, frame_w - 1, frame_h - 1),
                         radius=frame_radius, fill=DEVICE_BLACK)
    # subtle outer highlight stroke (1px) for premium look
    fd.rounded_rectangle((0, 0, frame_w - 1, frame_h - 1),
                         radius=frame_radius, outline=DEVICE_HILITE, width=2)
    # inner pocket
    inset = max(bezel // 4, 3)
    fd.rounded_rectangle(
        (inset, inset, frame_w - 1 - inset, frame_h - 1 - inset),
        radius=max(frame_radius - inset, screen_radius + 4),
        fill=DEVICE_INNER,
    )
    # paste screen
    frame.paste(rounded_shot, (bezel, bezel), rounded_shot)

    # position
    fx = (cw - frame_w) // 2
    fy = frame_top_y + ((frame_bottom_y - frame_top_y) - frame_h) // 2

    # soft shadow
    shadow_layer = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    sd.rounded_rectangle(
        (fx - 6, fy + 30, fx + frame_w + 6, fy + frame_h + 60),
        radius=frame_radius + 6,
        fill=SHADOW_COLOR,
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=56))

    canvas_rgba = canvas.convert("RGBA")
    canvas_rgba = Image.alpha_composite(canvas_rgba, shadow_layer)

    placed = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    placed.paste(frame, (fx, fy), frame)
    canvas_rgba = Image.alpha_composite(canvas_rgba, placed)

    canvas.paste(canvas_rgba.convert("RGB"))


# -------- headline --------------------------------------------------------

def draw_headline(canvas: Image.Image, text: str, font_size: int,
                  center_y: int) -> None:
    cw, ch = canvas.size
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT_BOLD, font_size)

    # Wrap if too long
    max_w = int(cw * 0.86)
    words = text.split()
    lines = [text]
    if draw.textlength(text, font=font) > max_w:
        # try to split into two lines around the middle
        mid = len(words) // 2
        lines = [" ".join(words[:mid]), " ".join(words[mid:])]

    line_h = int(font_size * 1.1)
    total_h = line_h * len(lines)
    y0 = center_y - total_h // 2
    for i, line in enumerate(lines):
        tw = draw.textlength(line, font=font)
        x = (cw - tw) // 2
        draw.text((x, y0 + i * line_h), line,
                  fill=HEADLINE_COLOR, font=font)


# -------- main builds -----------------------------------------------------

def build_iphone():
    src = ROOT / "iPhone"
    dst = OUT / "iPhone"
    dst.mkdir(parents=True, exist_ok=True)

    CW, CH = 1320, 2868
    HEADLINE_SIZE = 96
    HEADLINE_AREA_BOTTOM = 360       # headline lives in y=0..360
    HEADLINE_CENTER_Y = 200

    DEVICE_TOP = HEADLINE_AREA_BOTTOM
    DEVICE_BOTTOM = CH - 60          # tiny bottom margin

    # Frame width 88% of canvas
    FRAME_WIDTH = int(CW * 0.92)     # ~1214
    BEZEL = 16
    SCREEN_R = 96
    FRAME_R = 116

    for f in sorted(src.glob("*.png")):
        key = time_key(f.name)
        label = IPHONE_LABEL.get(key)
        if not label:
            continue
        canvas = make_background(CW, CH)
        composite_device(
            canvas, f,
            frame_top_y=DEVICE_TOP,
            frame_bottom_y=DEVICE_BOTTOM,
            frame_width=FRAME_WIDTH,
            bezel=BEZEL,
            screen_radius=SCREEN_R,
            frame_radius=FRAME_R,
        )
        draw_headline(canvas, HEADLINES[label], HEADLINE_SIZE,
                      HEADLINE_CENTER_Y)
        out = dst / f"iphone_{label}.png"
        canvas.save(out, "PNG", optimize=True)
        print(f"iPhone {label}: {out.name} {canvas.size}")


def build_ipad():
    src = ROOT / "iPad"
    dst = OUT / "iPad"
    dst.mkdir(parents=True, exist_ok=True)

    CW, CH = 2064, 2752
    HEADLINE_SIZE = 110
    HEADLINE_AREA_BOTTOM = 320
    HEADLINE_CENTER_Y = 180

    DEVICE_TOP = HEADLINE_AREA_BOTTOM
    DEVICE_BOTTOM = CH - 70

    FRAME_WIDTH = int(CW * 0.90)
    BEZEL = 22
    SCREEN_R = 48
    FRAME_R = 68

    for f in sorted(src.glob("*.png")):
        key = time_key(f.name)
        label = IPAD_LABEL.get(key)
        if not label:
            continue
        canvas = make_background(CW, CH)
        composite_device(
            canvas, f,
            frame_top_y=DEVICE_TOP,
            frame_bottom_y=DEVICE_BOTTOM,
            frame_width=FRAME_WIDTH,
            bezel=BEZEL,
            screen_radius=SCREEN_R,
            frame_radius=FRAME_R,
        )
        draw_headline(canvas, HEADLINES[label], HEADLINE_SIZE,
                      HEADLINE_CENTER_Y)
        out = dst / f"ipad_{label}.png"
        canvas.save(out, "PNG", optimize=True)
        print(f"iPad   {label}: {out.name} {canvas.size}")


if __name__ == "__main__":
    build_iphone()
    build_ipad()
