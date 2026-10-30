#!/usr/bin/env python3
"""Sinh bộ icon THBIKE (Android launcher + adaptive + monochrome + thông báo + splash + iOS).

Chạy lại:  python3 tool/make_thbike_icon.py        (cần Pillow)

Thiết kế "Premium Electric Motorcycle Technology":
  • Monogram TH cách điệu, nghiêng về phía trước (tốc độ), chữ bạc kim loại.
  • Thanh ngang của chữ H là TIA SÉT xanh điện (năng lượng / điện).
  • Vệt sáng xanh điện bên dưới (bánh xe/quỹ đạo tốc độ) kèm các ô pin nhỏ.
  • Nền đen → xanh than, viền sáng xanh điện. Không dùng logo hãng khác.
Toàn bộ vẽ bằng đa giác → không phụ thuộc phông chữ.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android/app/src/main/res")
IOS = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
SS = 3  # siêu lấy mẫu

BLUE_TOP, BLUE_BOT = (96, 220, 255), (14, 120, 255)      # xanh điện
SILVER_TOP, SILVER_BOT = (250, 252, 255), (138, 150, 168)  # bạc
BG_TOP, BG_BOT = (5, 7, 11), (12, 22, 42)

# Toạ độ thiết kế trên lưới 100x100 (trước khi nghiêng).
T_BAR = [(6, 22), (50, 22), (50, 35), (6, 35)]
T_STEM = [(20, 35), (34, 35), (34, 80), (20, 80)]
H_L = [(53, 22), (65, 22), (65, 80), (53, 80)]
H_R = [(81, 22), (93, 22), (93, 80), (81, 80)]
BOLT = [(76, 40), (60, 58), (69, 58), (62, 74), (84, 52), (73, 52), (80, 40)]  # giữa 2 thân H
BOLT = [(77.5, 34), (66.5, 57), (72.5, 57), (68, 78), (80, 49), (74.5, 49), (79, 34)]
SWOOSH = [(6, 88), (93, 88), (86, 92.5), (14, 92.5)]
PIPS = [(36 + i * 10, 95.5, 42 + i * 10, 98) for i in range(3)]
SHEAR = 0.16
CX, CY = 49.5, 55  # tâm khối hình để canh giữa


def _vgrad(size, top, bot):
    g = Image.linear_gradient("L").resize(size)
    a = Image.new("RGB", size, top)
    b = Image.new("RGB", size, bot)
    return Image.composite(b, a, g)


def _tx(pts, S, scale, shear=True):
    """Lưới thiết kế → pixel: nghiêng, co theo `scale`, canh giữa."""
    out = []
    for x, y in pts:
        xs = x + (SHEAR * (CY - y) if shear else 0)
        out.append(((xs - CX) * scale + S / 2, (y - CY) * scale + S / 2))
    return out


def draw_art(size, fill=0.60, mono=False, with_text=True, extras=True):
    """Phần hình trên nền trong suốt. `fill` = tỷ lệ chiều rộng khối chữ trên canvas."""
    S = size * SS
    scale = S * fill / 90.0
    # mặt nạ chữ (bạc)
    m_silver = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m_silver)
    if with_text:
        for poly in (T_BAR, T_STEM, H_L, H_R):
            d.polygon(_tx(poly, S, scale), fill=255)
    # mặt nạ xanh: tia sét (+ vệt sáng, pin)
    m_blue = Image.new("L", (S, S), 0)
    db = ImageDraw.Draw(m_blue)
    db.polygon(_tx(BOLT, S, scale), fill=255)
    if extras:
        db.polygon(_tx(SWOOSH, S, scale), fill=255)
        for x0, y0, x1, y1 in PIPS:
            p = _tx([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], S, scale)
            db.polygon(p, fill=255)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if mono:
        white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
        # chừa khe quanh tia sét để silhouette đơn sắc vẫn đọc được chữ H + sét
        k = max(3, int(S * 0.012)) | 1
        gap = m_blue.filter(ImageFilter.MaxFilter(k * 2 + 1))
        m_silver = ImageChops.subtract(m_silver, gap)
        full = ImageChops.lighter(m_silver, m_blue)
        layer.paste(white, (0, 0), full)
    else:
        # quầng sáng xanh điện phía sau
        glow = m_blue.filter(ImageFilter.GaussianBlur(S * 0.018))
        glow_col = Image.new("RGBA", (S, S), BLUE_BOT + (255,))
        glow_a = glow.point(lambda v: int(v * 0.85))
        layer.paste(glow_col, (0, 0), glow_a)
        # chữ bạc (gradient dọc) + viền sáng trên
        silver = _vgrad((S, S), SILVER_TOP, SILVER_BOT).convert("RGBA")
        layer.paste(silver, (0, 0), m_silver)
        # tia sét + vệt xanh điện
        blue = _vgrad((S, S), BLUE_TOP, BLUE_BOT).convert("RGBA")
        layer.paste(blue, (0, 0), m_blue)
    return layer.resize((size, size), Image.LANCZOS)


def background(size, rounded):
    S = size * SS
    g = _vgrad((S, S), BG_TOP, BG_BOT).convert("RGBA")
    # ánh sáng xanh điện mờ từ đáy (cảm giác chiều sâu)
    rim = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rim).ellipse([-S * 0.2, S * 0.62, S * 1.2, S * 1.55], fill=255)
    rim = rim.filter(ImageFilter.GaussianBlur(S * 0.09)).point(lambda v: int(v * 0.40))
    g.paste(Image.new("RGBA", (S, S), (20, 110, 255, 255)), (0, 0), rim)
    if rounded:
        m = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
        g.putalpha(m)
        # viền mảnh xanh điện
        ring = Image.new("L", (S, S), 0)
        rd = ImageDraw.Draw(ring)
        w = max(2, int(S * 0.012))
        rd.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), outline=255, width=w)
        g.paste(Image.new("RGBA", (S, S), (40, 150, 255, 255)), (0, 0), ring.point(lambda v: int(v * 0.55)))
    return g.resize((size, size), Image.LANCZOS)


def full(size, rounded):
    bg = background(size, rounded)
    bg.alpha_composite(draw_art(size, fill=0.66))
    return bg


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)


def main():
    # Nguồn 1024 cho flutter_launcher_icons / cửa hàng (vuông, không bo; iOS tự bo)
    save(full(1024, False), os.path.join(ROOT, "assets/icon/icon.png"))
    # Foreground adaptive: vùng an toàn 66/108 ≈ 61% → chữ chiếm ≤ 0.56 chiều rộng
    save(draw_art(1024, fill=0.56), os.path.join(ROOT, "assets/icon/icon_foreground.png"))
    for d, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(full(px, True), f"{RES}/mipmap-{d}/ic_launcher.png")
    for d, px in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)):
        save(draw_art(px, fill=0.56), f"{RES}/drawable-{d}/ic_launcher_foreground.png")
        save(draw_art(px, fill=0.56, mono=True), f"{RES}/drawable-{d}/ic_launcher_monochrome.png")
    for d, px in (("mdpi", 144), ("hdpi", 216), ("xhdpi", 288), ("xxhdpi", 432), ("xxxhdpi", 576)):
        save(full(px, True), f"{RES}/drawable-{d}/splash_logo.png")
    # Icon thông báo: silhouette trắng, bỏ chi tiết nhỏ để rõ ở 24dp
    for d, px in (("mdpi", 24), ("hdpi", 36), ("xhdpi", 48), ("xxhdpi", 72), ("xxxhdpi", 96)):
        save(draw_art(px, fill=0.92, mono=True, extras=False), f"{RES}/drawable-{d}/ic_stat_thbike.png")
    # iOS: ảnh vuông, KHÔNG alpha (App Store yêu cầu)
    base = full(1024, False).convert("RGB")
    import json
    cj = json.load(open(os.path.join(IOS, "Contents.json")))
    for im in cj["images"]:
        fn = im.get("filename")
        if not fn:
            continue
        pt = float(im["size"].split("x")[0])
        sc = int(im["scale"].replace("x", ""))
        px = int(round(pt * sc))
        base.resize((px, px), Image.LANCZOS).save(os.path.join(IOS, fn))
    print("OK")


if __name__ == "__main__":
    main()
