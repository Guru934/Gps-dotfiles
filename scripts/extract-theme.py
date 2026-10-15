#!/usr/bin/env python3
import colorsys, json, os, subprocess

STATE_JSON = "/tmp/gps-theme.json"
LAST_WALL = "/tmp/gps-last-wall.txt"

def get_current_wallpaper():
    try:
        out = subprocess.check_output(["awww", "query"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if "image:" in line:
                return line.split("image:", 1)[1].strip()
    except Exception:
        pass
    return ""

def extract_dominant_hsv(img_path):
    from PIL import Image
    img = Image.open(img_path).convert("RGB").resize((64, 64))
    buckets = [0.0] * 36
    r_sum = [0.0] * 36
    g_sum = [0.0] * 36
    b_sum = [0.0] * 36

    for r, g, b in img.getdata():
        rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
        h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
        if v < 0.15 or s < 0.18:
            continue
        idx = int(h * 36) % 36
        weight = (s ** 1.4) * (v ** 1.1)
        buckets[idx] += weight
        r_sum[idx] += rf * weight
        g_sum[idx] += gf * weight
        b_sum[idx] += bf * weight

    best = max(range(36), key=lambda i: buckets[i])
    if buckets[best] <= 0:
        return 0.92, 0.45, 0.90
    w = buckets[best]
    return colorsys.rgb_to_hsv(r_sum[best] / w, g_sum[best] / w, b_sum[best] / w)

def hsv_hex(h, s, v, alpha=""):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return f"#{alpha}{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}"

def hsv_rgba_hex(h, s, v, alpha_hex="FF"):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return f"#{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}{alpha_hex}"

def main():
    wall = get_current_wallpaper()
    if not wall or not os.path.exists(wall):
        return

    h, s, _ = extract_dominant_hsv(wall)
    acc_s = max(0.55, min(0.82, s * 0.95))
    acc_v = 0.96

    r, g, b = colorsys.hsv_to_rgb(h, acc_s, acc_v)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    accent_fg = "#140E14" if lum > 0.48 else "#FFFFFF"

    theme = {
        "wallpaper": wall,
        "surface": hsv_hex(h, 0.48, 0.13, "F2"),
        "card": hsv_hex(h, 0.44, 0.20),
        "cardHover": hsv_hex(h, 0.46, 0.28),
        "track": hsv_hex(h, 0.50, 0.09),
        "border": hsv_hex(h, 0.45, 0.36),
        "brandAccent": hsv_hex(h, acc_s, acc_v),
        "brandAccentFg": accent_fg,
        "textMain": "#FFFFFF",
        "textMuted": hsv_hex(h, 0.14, 0.86)
    }

    with open(STATE_JSON, "w", encoding="utf-8") as f:
        json.dump(theme, f)

    # Update Hyprland active border to match wallpaper
    b1 = hsv_hex(h, acc_s, acc_v)[1:].lower()
    b2 = hsv_hex((h + 0.08) % 1.0, acc_s, 0.92)[1:].lower()
    inact = hsv_hex(h, 0.40, 0.32)[1:].lower()
    subprocess.run([
        "hyprctl", "--batch",
        f"keyword general:col.active_border rgba({b1}ee) rgba({b2}ee) 45deg ; "
        f"keyword general:col.inactive_border rgba({inact}aa)"
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Update Rofi theme colors to match wallpaper
    rofi_path = os.path.expanduser("~/.config/rofi/config.rasi")
    if os.path.exists(rofi_path):
        with open(rofi_path, "r", encoding="utf-8") as f:
            rasi = f.read()
        import re
        rasi = re.sub(r"bg:\s*#[0-9A-Fa-f]+;", f"bg: {hsv_rgba_hex(h, 0.48, 0.13, 'F0')};", rasi)
        rasi = re.sub(r"card:\s*#[0-9A-Fa-f]+;", f"card: {hsv_rgba_hex(h, 0.44, 0.20)};", rasi)
        rasi = re.sub(r"hover:\s*#[0-9A-Fa-f]+;", f"hover: {hsv_rgba_hex(h, 0.46, 0.28)};", rasi)
        rasi = re.sub(r"accent:\s*#[0-9A-Fa-f]+;", f"accent: {hsv_rgba_hex(h, acc_s, acc_v)};", rasi)
        rasi = re.sub(r"accent-fg:\s*#[0-9A-Fa-f]+;", f"accent-fg: {accent_fg}FF;", rasi)
        rasi = re.sub(r"border-col:\s*#[0-9A-Fa-f]+;", f"border-col: {hsv_rgba_hex(h, 0.45, 0.36)};", rasi)
        with open(rofi_path, "w", encoding="utf-8") as f:
            f.write(rasi)

if __name__ == "__main__":
    main()
