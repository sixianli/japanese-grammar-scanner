#!/usr/bin/env python3
"""识别准确度评测（离线）。

输入：
  * CI「OCR Eval」导出的 Vision 原始结果目录（每张图一个 JSON，含各方案的行文字与位置）
  * 人工整理的标准正文（tests/ocr/groundtruth/<图>.txt：只含印刷的日文正文，不含注音、手写、非日文）
做法：用 App 同样的语法匹配规则（Python 版，正则与 App 共用），分别对「标准正文」和「识别结果」找语法点，
比较两者：
  * 召回率：标准正文里能找到的语法点，识别结果里也找到了多少（漏识别越少越高）
  * 精确率：识别结果里找到的语法点，有多少确实在标准正文里（误报越少越高）
  * 字符准确率：识别文字与标准正文的相似度
还可以对识别出的行做后处理（过滤注音、过滤非日文……），比较不同方案。

用法: python3 tools/ocr_eval.py <ocr-out 目录> [--gt tests/ocr/groundtruth] [--detail]
"""
import argparse
import difflib
import glob
import json
import os
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")

KANA = re.compile(r"[぀-ヿ]")
KANJI = re.compile(r"[㐀-鿿々〆]")
JA = re.compile(r"[぀-ヿ㐀-鿿々〆ー]")
SENTENCE_END = set("。！？!?」』…")


# ---------- 语法匹配（与 GrammarMatcher.swift 相同的逻辑） ----------

class Matcher:
    def __init__(self):
        self.rules = []
        subsumes = {}
        for f in sorted(glob.glob(os.path.join(GRAMMAR, "grammar_*.json"))):
            for p in json.load(open(f, encoding="utf-8")):
                if not p.get("scannable", True):
                    continue
                regs = []
                for pat in p["patterns"]:
                    try:
                        regs.append(re.compile(pat))
                    except re.error:
                        pass
                self.rules.append((p["id"], regs))
                subsumes[p["id"]] = set(p.get("subsumes") or [])
        self.subsumes = subsumes

    def matches(self, text):
        raw = []
        for gid, regs in self.rules:
            ranges = sorted((m.start(), m.end()) for r in regs for m in r.finditer(text) if m.end() > m.start())
            merged = []
            for s, e in ranges:
                if merged and s < merged[-1][1]:
                    merged[-1] = (merged[-1][0], max(merged[-1][1], e))
                else:
                    merged.append((s, e))
            raw += [(gid, s, e) for s, e in merged]
        out = []
        for gid, s, e in raw:
            if any(o != gid and gid in self.subsumes.get(o, ()) and s < oe and os_ < e for o, os_, oe in raw):
                continue
            out.append((gid, s, e))
        return out

    def ids(self, text):
        return {m[0] for m in self.matches(text)}


# ---------- 行的后处理方案 ----------

def assemble(lines):
    """与 TextRecognizer.assemble 相同：行直接相连，上一行以句末标点结尾时换行。"""
    text = ""
    for ln in lines:
        t = ln["text"].strip()
        if not t:
            continue
        if text and text[-1] in SENTENCE_END:
            text += "\n"
        text += t
    return text


def is_furigana(ln, median_h):
    """注音：只含假名、字高明显小于正文的短行。"""
    t = ln["text"].strip()
    h = ln["box"][3]
    if not t or not median_h:
        return False
    kana_only = all(KANA.match(c) or c in "・ー " for c in t)
    return kana_only and h < median_h * 0.62


def is_non_japanese(ln):
    """几乎没有日文字符的行（英文、越南文、韩文、乱码）。"""
    t = re.sub(r"\s", "", ln["text"])
    if not t:
        return True
    ja = len(JA.findall(t))
    return ja / len(t) < 0.3


def strip_foreign_segments(text):
    """去掉行内的非日文片段（如「夜市：night market／夜市／야시장」后半段）。"""
    parts = re.split(r"(／|/)", text)
    keep = []
    for p in parts:
        if p in ("／", "/"):
            continue
        if not p.strip():
            continue
        if len(JA.findall(p)) / max(len(p.strip()), 1) >= 0.3:
            keep.append(p)
    return "／".join(keep) if keep else ""


def variant_lines(lines, variant):
    if variant == "raw":
        return lines
    heights = [ln["box"][3] for ln in lines if len(JA.findall(ln["text"])) >= 4]
    median_h = statistics.median(heights) if heights else 0
    out = []
    for ln in lines:
        if "furigana" in variant and is_furigana(ln, median_h):
            continue
        if "foreign" in variant and is_non_japanese(ln):
            continue
        if "segments" in variant:
            t = strip_foreign_segments(ln["text"])
            if not t:
                continue
            ln = dict(ln, text=t)
        out.append(ln)
    return out


# ---------- 评测 ----------

def norm(s):
    return re.sub(r"\s", "", s)


def text_metrics(ocr, gt):
    """字符准确率（1 - CER）、假名插入率（注音混入）、非日文插入率（噪声混入）。"""
    from rapidfuzz.distance import Levenshtein
    a, b = norm(gt), norm(ocr)
    dist = Levenshtein.distance(a, b)
    cer = dist / max(len(a), 1)
    kana_ins = foreign_ins = 0
    for op in Levenshtein.editops(a, b):
        if op.tag in ("insert", "replace"):
            c = b[op.dest_pos]
            if KANA.match(c):
                kana_ins += 1
            elif not JA.match(c) and not re.match(r"[0-9０-９、。「」（）・：…！？ー〜]", c):
                foreign_ins += 1
    n = max(len(b), 1)
    return {"charAccuracy": max(0.0, 1 - cer), "kanaInsertRate": kana_ins / n, "foreignInsertRate": foreign_ins / n}


def summarize(rows):
    tp = sum(r["tp"] for r in rows)
    fp = sum(r["fp"] for r in rows)
    fn = sum(r["fn"] for r in rows)
    rec_ = tp / max(tp + fn, 1)
    pre = tp / max(tp + fp, 1)
    out = {
        "images": len(rows),
        "charAccuracy": statistics.mean(r["charAccuracy"] for r in rows),
        "kanaInsertRate": statistics.mean(r["kanaInsertRate"] for r in rows),
        "foreignInsertRate": statistics.mean(r["foreignInsertRate"] for r in rows),
        "grammarRecall": rec_,
        "grammarPrecision": pre,
        "grammarF1": 2 * rec_ * pre / max(rec_ + pre, 1e-9),
        "pageExact": sum(1 for r in rows if r["fp"] == 0 and r["fn"] == 0) / max(len(rows), 1),
        "expectedGrammar": tp + fn,
    }
    boxes = [r for r in rows if r.get("boxes") is not None]
    if boxes:
        exact = sum(r["boxes"]["exact"] for r in boxes)
        total = sum(r["boxes"]["exact"] + r["boxes"]["estimated"] for r in boxes)
        out["boxExactRate"] = exact / max(total, 1)
    secs = [r["seconds"] for r in rows if r.get("seconds") is not None]
    if secs:
        out["secondsPerImage"] = statistics.mean(secs)
    return out


def pct(x):
    return f"{x:.1%}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ocr_dir")
    ap.add_argument("--gt", default=os.path.join(ROOT, "tests", "ocr", "groundtruth"))
    ap.add_argument("--variants", default="raw,furigana,furigana+foreign,furigana+foreign+segments")
    ap.add_argument("--report", help="输出路径前缀：写出 <前缀>.json（完整数据）与 <前缀>.tables.md（表格）")
    ap.add_argument("--detail", action="store_true")
    args = ap.parse_args()

    m = Matcher()
    labels_path = os.path.join(args.gt, "labels.json")
    labels = json.load(open(labels_path, encoding="utf-8")) if os.path.exists(labels_path) else {}
    variants = args.variants.split(",")
    per = {}  # 方案 -> [每张图的结果]
    for f in sorted(glob.glob(os.path.join(args.ocr_dir, "*.json"))):
        name = os.path.splitext(os.path.basename(f))[0]
        gt_path = os.path.join(args.gt, name + ".txt")
        if not os.path.exists(gt_path):
            continue
        gt_text = "\n".join(l for l in open(gt_path, encoding="utf-8").read().splitlines() if not l.startswith("#"))
        expected = m.ids(gt_text)
        rec = json.load(open(f, encoding="utf-8"))
        for config in [k for k in rec if isinstance(rec[k], dict) and "lines" in rec[k]]:
            for v in variants:
                text = assemble(variant_lines(rec[config]["lines"], v))
                got = m.ids(text)
                row = {"image": name, "tp": len(got & expected), "fp": len(got - expected), "fn": len(expected - got),
                       "missed": sorted(expected - got), "extra": sorted(got - expected),
                       "seconds": rec[config].get("seconds"), "boxes": rec[config].get("boxStats") if v == "raw" else None}
                row.update(text_metrics(text, gt_text))
                per.setdefault(f"{config}/{v}", []).append(row)

    if not per:
        sys.exit("没有可评测的数据（检查 OCR 目录与标准正文目录）")

    overall = {k: summarize(rows) for k, rows in per.items()}
    tags = sorted({t for l in labels.values() for t in l.get("tags", [])})
    by_tag = {}
    for k, rows in per.items():
        by_tag[k] = {}
        for t in tags:
            sub = [r for r in rows if t in labels.get(r["image"], {}).get("tags", [])]
            if sub:
                by_tag[k][t] = summarize(sub)

    lines = ["| 方案 | 图片 | 字符准确率 | 假名插入率 | 噪声插入率 | 语法召回率 | 语法精确率 | F1 | 整页全对率 | 精确定位率 | 平均耗时 |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for k, o in overall.items():
        lines.append(f"| {k} | {o['images']} | {pct(o['charAccuracy'])} | {pct(o['kanaInsertRate'])} | {pct(o['foreignInsertRate'])} | "
                     f"{pct(o['grammarRecall'])} | {pct(o['grammarPrecision'])} | {pct(o['grammarF1'])} | {pct(o['pageExact'])} | "
                     f"{pct(o['boxExactRate']) if 'boxExactRate' in o else '—'} | "
                     f"{('%.2fs' % o['secondsPerImage']) if 'secondsPerImage' in o else '—'} |")
    if tags:
        lines += ["", "按难点分组（语法 F1 / 字符准确率）：", "",
                  "| 方案 | " + " | ".join(tags) + " |", "|---|" + "---|" * len(tags)]
        for k in per:
            cells = []
            for t in tags:
                o = by_tag[k].get(t)
                cells.append(f"{pct(o['grammarF1'])} / {pct(o['charAccuracy'])} ({o['images']})" if o else "—")
            lines.append(f"| {k} | " + " | ".join(cells) + " |")
    table = "\n".join(lines)
    print(table)

    if args.detail:
        for k, rows in per.items():
            print(f"\n== {k}")
            for r in rows:
                print(f"{r['image']}: 字符{r['charAccuracy']:.0%} tp={r['tp']} fp={r['fp']} fn={r['fn']}  漏={r['missed'][:8]}  多={r['extra'][:8]}")

    if args.report:
        os.makedirs(os.path.dirname(args.report) or ".", exist_ok=True)
        with open(args.report + ".json", "w", encoding="utf-8") as fh:
            json.dump({"overall": overall, "byTag": by_tag, "perImage": per}, fh, ensure_ascii=False, indent=1)
        with open(args.report + ".tables.md", "w", encoding="utf-8") as fh:
            fh.write(table + "\n")
        print(f"\n已写出 {args.report}.json 与 {args.report}.tables.md")


if __name__ == "__main__":
    main()
