#!/usr/bin/env python3
"""扫描体验评测：在 95 张实拍照片上，按用户实际看到的样子检查高亮框和语法点。

输入：CI「OCR Eval」导出的 ocr-out 目录（每张照片一个 JSON，含 boxes / clusters）。
输出：
  1. 指标（--report 前缀.json / .md）
     - 框数、每张平均框数
     - 框重叠率：与「另一个高亮块」的框有明显重叠（交集 > 较小框面积 15%）的框占比
     - 过高框比例：框的高度 > 本页框高中位数 × 1.6 的框占比（斜拍时外接矩形会比字高出一截）
     - 多语法块比例：一个框里包含 2 个及以上语法点的高亮块占比
     - 长跨度块比例：命中原文超过 12 个字的语法点占比（容易框得太大）
  2. 人工核对用的标注图（--sheets 目录）：照片上画出所有框并编号，旁边列出每个编号对应的语法点和命中的原文。

用法：
  python3 tools/scan_ux_eval.py <ocr-out 目录> [--config base] [--report 前缀] [--sheets 目录]
"""
import argparse
import glob
import json
import os
import statistics

from PIL import Image, ImageDraw, ImageFont
from shapely.geometry import Polygon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLES = os.path.join(ROOT, "tests", "ocr", "samples")
GRAMMAR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")
FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"


def titles():
    t = {}
    for f in glob.glob(os.path.join(GRAMMAR, "grammar_*.json")):
        for p in json.load(open(f, encoding="utf-8")):
            t[p["id"]] = f'{p["title"]} ({p["level"]})'
    return t


def quad_of(box, W, H):
    q = box.get("quad")
    if q and len(q) == 8:
        pts = [(q[i] * W, q[i + 1] * H) for i in range(0, 8, 2)]
    else:
        x, y, w, h = box["rect"]
        pts = [(x * W, y * H), ((x + w) * W, y * H), ((x + w) * W, (y + h) * H), (x * W, (y + h) * H)]
    return pts


def edge_height(pts):
    """四边形的「高」：左右两条边长度的平均（斜拍时比外接矩形的高更接近字高）"""
    import math
    l = math.dist(pts[0], pts[3])
    r = math.dist(pts[1], pts[2])
    return (l + r) / 2


def ckey(b):
    """高亮块的标识（旧版导出没有 cluster 字段时用语法点组合代替）"""
    return b.get("cluster", tuple(b.get("grammar", [])))


def analyze(path, config):
    rec = json.load(open(path, encoding="utf-8"))
    d = rec.get(config) or {}
    W, H = rec["width"], rec["height"]
    boxes = d.get("boxes", [])
    clusters = {c["id"]: c for c in d.get("clusters", [])}
    polys = []
    for b in boxes:
        pts = quad_of(b, W, H)
        poly = Polygon(pts)
        if not poly.is_valid:
            poly = poly.buffer(0)
        polys.append((b, pts, poly))
    heights = [edge_height(p) for _, p, _ in polys]
    med = statistics.median(heights) if heights else 0
    overlap = tall = 0
    for i, (b, pts, poly) in enumerate(polys):
        for j, (b2, _, poly2) in enumerate(polys):
            if i == j or ckey(b) == ckey(b2):
                continue
            inter = poly.intersection(poly2).area
            if inter > 0.15 * min(poly.area, poly2.area):
                overlap += 1
                break
        if med and edge_height(pts) > 1.6 * med:
            tall += 1
    if not clusters:  # 旧版导出：按框推断高亮块
        clusters = {ckey(b): {"grammar": b.get("grammar", [])} for b in boxes}
    multi = sum(1 for c in clusters.values() if len(c.get("grammar", [])) > 1)
    matched = [t for c in clusters.values() for t in (c.get("matched") or {}).values()]
    long_spans = sum(1 for t in matched if len(t.replace("\n", "")) > 12)
    return {
        "image": os.path.basename(path)[:-5], "boxes": len(boxes), "overlapBoxes": overlap, "tallBoxes": tall,
        "clusters": len(clusters), "multiClusters": multi, "matches": len(matched), "longSpans": long_spans,
    }, rec, d, polys


def draw_sheet(rec, d, polys, names, out):
    img = Image.open(os.path.join(SAMPLES, rec["file"])).convert("RGB")
    W, H = img.size
    draw = ImageDraw.Draw(img, "RGBA")
    font = ImageFont.truetype(FONT, max(18, W // 60))
    order = {}
    for b, pts, _ in polys:
        cid = ckey(b)
        n = order.setdefault(cid, len(order) + 1)
        draw.polygon(pts, outline=(220, 30, 30, 255), fill=(255, 220, 0, 50), width=max(2, W // 600))
        x, y = pts[0]
        draw.text((x, y - font.size - 2), str(n), fill=(220, 30, 30, 255), font=font, stroke_width=2, stroke_fill="white")
    clusters = {c["id"]: c for c in d.get("clusters", [])}
    lines = []
    for cid, n in sorted(order.items(), key=lambda t: t[1]):
        c = clusters.get(cid, {})
        segs = "／".join(c.get("segments", []))
        parts = [f'{names.get(g, g)}「{(c.get("matched") or {}).get(g, "").replace(chr(10), "")}」' for g in c.get("grammar", [])]
        lines.append(f"{n}. 框：「{segs}」 → " + "；".join(parts))
    # 右侧列表
    side_w = int(W * 0.9)
    lf = ImageFont.truetype(FONT, max(16, W // 75))
    sheet = Image.new("RGB", (W + side_w, max(H, (len(lines) + 2) * (lf.size + 8))), "white")
    sheet.paste(img, (0, 0))
    sd = ImageDraw.Draw(sheet)
    y = 10
    for t in lines:
        # 太长的行折成两行
        while t:
            cut = t[:60]
            sd.text((W + 10, y), cut, fill="black", font=lf)
            y += lf.size + 6
            t = t[60:]
    scale = 2000 / max(sheet.size)
    if scale < 1:
        sheet = sheet.resize((int(sheet.width * scale), int(sheet.height * scale)))
    sheet.save(out, quality=85)
    return lines


def pct(x):
    return f"{x * 100:.1f}%"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ocr_dir")
    ap.add_argument("--config", default="base")
    ap.add_argument("--report")
    ap.add_argument("--sheets")
    args = ap.parse_args()
    names = titles()
    rows, listings = [], {}
    for f in sorted(glob.glob(os.path.join(args.ocr_dir, "*.json"))):
        row, rec, d, polys = analyze(f, args.config)
        rows.append(row)
        if args.sheets:
            os.makedirs(args.sheets, exist_ok=True)
            listings[row["image"]] = draw_sheet(rec, d, polys, names, os.path.join(args.sheets, row["image"] + ".jpg"))
    tot = lambda k: sum(r[k] for r in rows)
    summary = {
        "images": len(rows), "boxes": tot("boxes"), "boxesPerImage": tot("boxes") / max(len(rows), 1),
        "overlapRate": tot("overlapBoxes") / max(tot("boxes"), 1), "tallRate": tot("tallBoxes") / max(tot("boxes"), 1),
        "multiClusterRate": tot("multiClusters") / max(tot("clusters"), 1), "longSpanRate": tot("longSpans") / max(tot("matches"), 1),
    }
    table = ("| 指标 | 结果 |\n|---|---|\n"
             f"| 照片 | {summary['images']} |\n| 框数（每张平均） | {summary['boxes']}（{summary['boxesPerImage']:.1f}） |\n"
             f"| 框重叠率 | {pct(summary['overlapRate'])} |\n| 过高框比例 | {pct(summary['tallRate'])} |\n"
             f"| 多语法块比例 | {pct(summary['multiClusterRate'])} |\n| 长跨度命中比例 | {pct(summary['longSpanRate'])} |\n")
    print(table)
    if args.report:
        json.dump({"summary": summary, "perImage": rows, "listings": listings},
                  open(args.report + ".json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        open(args.report + ".md", "w", encoding="utf-8").write(table)


if __name__ == "__main__":
    main()
