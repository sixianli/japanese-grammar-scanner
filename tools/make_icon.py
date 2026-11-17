#!/usr/bin/env python3
"""生成 App 图标 (1024x1024, 无透明通道)。用法: python3 tools/make_icon.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "JapaneseGrammarScanner", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
FONT = "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"
if not os.path.exists(FONT):
    FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"

S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
top, bottom = (232, 72, 85), (150, 30, 70)
for y in range(S):
    t = y / (S - 1)
    d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

# 书页
page = (212, 250, 812, 790)
d.rounded_rectangle(page, radius=48, fill=(255, 250, 242))
# 文本行
font = ImageFont.truetype(FONT, 150)
d.rounded_rectangle((292, 340, 732, 420), radius=14, fill=(230, 226, 220))
d.rounded_rectangle((292, 640, 640, 700), radius=14, fill=(230, 226, 220))
# 高亮的语法
d.rounded_rectangle((280, 450, 744, 610), radius=22, fill=(255, 214, 70))
text = "文法"
w = d.textlength(text, font=font)
d.text(((S - w) / 2, 452), text, font=font, fill=(60, 30, 40))

# 取景框四角
c, L, W = (255, 255, 255), 130, 34
for (x, y, dx, dy) in [(120, 120, 1, 1), (S - 120, 120, -1, 1), (120, S - 120, 1, -1), (S - 120, S - 120, -1, -1)]:
    d.rounded_rectangle(sorted([x, x + dx * L])[:1] + sorted([y, y + dy * W])[:1] + sorted([x, x + dx * L])[1:] + sorted([y, y + dy * W])[1:], radius=W // 2, fill=c)
    d.rounded_rectangle(sorted([x, x + dx * W])[:1] + sorted([y, y + dy * L])[:1] + sorted([x, x + dx * W])[1:] + sorted([y, y + dy * L])[1:], radius=W // 2, fill=c)

img.save(OUT)
print("saved", OUT)
