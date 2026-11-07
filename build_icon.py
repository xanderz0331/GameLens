#!/usr/bin/env python3
"""生成 GameLens 的 AppIcon.icns（纯本地绘制，无外部依赖）。"""
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
OUT = os.path.dirname(os.path.abspath(__file__))


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=color)
    return img


def squircle_mask(size, radius, inset):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    return mask


def load_font(size):
    candidates = [
        ("/System/Library/Fonts/PingFang.ttc", 2),
        ("/System/Library/Fonts/PingFang.ttc", 0),
        ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0),
        ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
    ]
    for path, index in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=index)
            except Exception:
                continue
    return ImageFont.load_default()


def build():
    inset = 62
    radius = 225

    base = gradient(S, (91, 108, 255), (138, 63, 252)).convert("RGBA")
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [inset, inset + 22, S - inset, S - inset + 22], radius=radius, fill=(0, 0, 0, 90)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.alpha_composite(shadow)
    canvas.paste(base, (0, 0), squircle_mask(S, radius, inset))

    # 白色对话气泡
    bubble = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(bubble)
    bx0, by0, bx1, by1 = 205, 250, 819, 690
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=96, fill=(255, 255, 255, 255))
    d.polygon([(360, 682), (352, 828), (500, 686)], fill=(255, 255, 255, 255))
    canvas.alpha_composite(bubble)

    # 「译」字：先测量再等比缩放到气泡里
    font = load_font(560)
    measure = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dm = ImageDraw.Draw(measure)
    bbox = dm.textbbox((0, 0), "译", font=font)
    glyph = Image.new("RGBA", (bbox[2] - bbox[0], bbox[3] - bbox[1]), (0, 0, 0, 0))
    ImageDraw.Draw(glyph).text((-bbox[0], -bbox[1]), "译", font=font, fill=(43, 45, 66, 255))

    target_h = 286
    scale = target_h / glyph.height
    glyph = glyph.resize((max(1, int(glyph.width * scale)), target_h), Image.LANCZOS)

    center_x, center_y = 512, 470
    canvas.alpha_composite(glyph, (center_x - glyph.width // 2, center_y - glyph.height // 2))

    canvas.save(os.path.join(OUT, "icon-1024.png"))
    return canvas


if __name__ == "__main__":
    build()
