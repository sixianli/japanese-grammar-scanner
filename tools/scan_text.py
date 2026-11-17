#!/usr/bin/env python3
"""在命令行里模拟 App 的语法识别（与 GrammarMatcher.swift 逻辑一致），方便调试正则误判/漏判。

用法:
  python3 tools/scan_text.py "宿題を忘れてしまったので、先生に怒られた。"
  python3 tools/scan_text.py -f some_text.txt
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")


def load():
    pts = []
    for p in sorted(glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json"))):
        with open(p, encoding="utf-8") as f:
            pts += json.load(f)
    return pts


def merge(ranges):
    out = []
    for s, e in sorted(ranges):
        if out and s < out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out


def scan(text, points):
    raw = []
    for p in points:
        rs = []
        for pat in p["patterns"]:
            rs += [(m.start(), m.end()) for m in re.finditer(pat, text) if m.end() > m.start()]
        raw += [(p["id"], r) for r in merge(rs)]
    sub = {p["id"]: set(p.get("subsumes") or []) for p in points}
    res = [
        (gid, r) for gid, r in raw
        if not any(o != gid and gid in sub[o] and max(r[0], orr[0]) < min(r[1], orr[1]) for o, orr in raw)
    ]
    return sorted(res, key=lambda x: (x[1][0], -(x[1][1] - x[1][0])))


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    text = open(args[1], encoding="utf-8").read() if args[0] == "-f" else " ".join(args)
    points = load()
    titles = {p["id"]: f'{p["title"]} ({p["level"]})' for p in points}
    for gid, (s, e) in scan(text, points):
        ctx = text[max(0, s - 8):s] + "【" + text[s:e] + "】" + text[e:e + 8]
        print(f"{titles[gid]:<28} {ctx.replace(chr(10), ' ')}")


if __name__ == "__main__":
    main()
