#!/usr/bin/env python3
"""生成 App 图标「鳥居フレーム」(1024x1024, 无透明通道)。
扫描：书页四角的取景框 + 扫描光线；日本：朱红鸟居 + 夕阳渐变；文法：书页上的「文法」，「法」带荧光笔高亮。
字体：Noto Serif JP（SIL Open Font License 1.1，可商用），首次运行自动下载到 tools/.cache/。
用法: python3 tools/make_icon.py
"""
import os
import urllib.request

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "JapaneseGrammarScanner", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
CACHE = os.path.join(ROOT, "tools", ".cache")
FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifjp/NotoSerifJP%5Bwght%5D.ttf"
FONT = os.path.join(CACHE, "NotoSerifJP.ttf")

S = 2048
SHU = (214, 52, 42)
SUMI = (28, 24, 24)
PAPER = (255, 252, 245)
MARKER = (255, 205, 70)


def serif(size):
    if not os.path.exists(FONT):
        os.makedirs(CACHE, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL, FONT)
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([900])
    except Exception:  # noqa: BLE001
        pass
    return f


def main():
    top, bot = (255, 218, 192), (238, 112, 104)
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bot)))

    # 鸟居：笠木（黑）+ 岛木（朱）+ 贯 + 额束 + 两根柱子 + 根卷
    d.polygon([(110, 300), (S - 110, 300), (S - 200, 480), (200, 480)], fill=SUMI)
    d.rounded_rectangle((200, 430, S - 200, 580), radius=20, fill=SHU)
    d.rectangle((250, 690, S - 250, 800), fill=SHU)
    d.rectangle((S // 2 - 46, 580, S // 2 + 46, 690), fill=SHU)
    for x in (400, S - 400):
        d.rectangle((x - 82, 580, x + 82, S - 120), fill=SHU)
        d.rectangle((x - 104, S - 210, x + 104, S - 120), fill=SUMI)

    # 书页（带柔和投影）
    page = (640, 880, S - 640, S - 270)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((page[0] + 10, page[1] + 24, page[2] + 10, page[3] + 24), radius=60, fill=(90, 20, 20, 90))
    im = Image.alpha_composite(im.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(30))).convert("RGB")
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(page, radius=60, fill=PAPER)

    # 荧光笔高亮「法」+ 文字
    cx = S // 2
    d.rounded_rectangle((page[0] + 50, 1290, page[2] - 50, page[3] - 50), radius=28, fill=MARKER)
    f = serif(380)
    d.text((cx, 1080), "文", font=f, fill=SUMI, anchor="mm")
    d.text((cx, 1500), "法", font=f, fill=SUMI, anchor="mm")

    # 取景框四角（白）
    L, W, inset = 150, 30, 26
    x0, y0, x1, y1 = page[0] - inset, page[1] - inset, page[2] + inset, page[3] + inset
    for (x, y, dx, dy) in [(x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)]:
        d.rounded_rectangle((min(x, x + dx * L), min(y, y + dy * W), max(x, x + dx * L), max(y, y + dy * W)), radius=W // 2, fill=(255, 255, 255))
        d.rounded_rectangle((min(x, x + dx * W), min(y, y + dy * L), max(x, x + dx * W), max(y, y + dy * L)), radius=W // 2, fill=(255, 255, 255))

    # 扫描光线
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((page[0] - 70, 1270, page[2] + 70, 1294), radius=12, fill=(255, 255, 255, 240))
    glow = layer.filter(ImageFilter.GaussianBlur(22))
    im = Image.alpha_composite(Image.alpha_composite(im.convert("RGBA"), glow), layer).convert("RGB")

    final = im.resize((1024, 1024), Image.LANCZOS)
    final.save(OUT)
    # 同一张图也作为普通图片资源（引导页中显示）
    final.save(os.path.join(os.path.dirname(os.path.dirname(OUT)), "AppIconImage.imageset", "AppIconImage.png"))
    print("saved", OUT)


if __name__ == "__main__":
    main()
