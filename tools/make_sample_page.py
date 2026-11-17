#!/usr/bin/env python3
"""生成内置示例书页图片（用于“试试示例”与 App 审核）。用法: python3 tools/make_sample_page.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Assets.xcassets", "SamplePage.imageset")
FONT = "/usr/share/fonts/opentype/ipafont-mincho/ipam.ttf"
if not os.path.exists(FONT):
    FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"

LINES = [
    "第三課　はじめての一人旅",
    "",
    "去年の夏、私は初めて一人で京都へ行った",
    "ことがある。駅に着いたとき、雨が降りそう",
    "だったので、コンビニで傘を買っておいた。",
    "地図を見ながら歩いていたら、道に迷って",
    "しまった。親切なおばあさんが駅まで連れて",
    "行ってくれたおかげで、無事に旅館に着く",
    "ことができた。日本語がもっと上手に話せる",
    "ようになりたいと思う。来年もまた行くつもり",
    "だ。忙しいにもかかわらず、友達も一緒に",
    "行きたいと言っているらしい。",
]

W, H = 1200, 1500
img = Image.new("RGB", (W, H), (250, 246, 236))
d = ImageDraw.Draw(img)
title = ImageFont.truetype(FONT, 56)
body = ImageFont.truetype(FONT, 48)
y = 110
for i, line in enumerate(LINES):
    f = title if i == 0 else body
    d.text((90, y), line, font=f, fill=(35, 30, 28))
    y += 100 if i == 0 else 92
d.text((W // 2 - 20, H - 90), "— 24 —", font=ImageFont.truetype(FONT, 30), fill=(120, 110, 100))
os.makedirs(OUT_DIR, exist_ok=True)
img.save(os.path.join(OUT_DIR, "SamplePage.png"))
with open(os.path.join(OUT_DIR, "Contents.json"), "w") as fp:
    fp.write('{\n  "images" : [ { "filename" : "SamplePage.png", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
print("ok")
