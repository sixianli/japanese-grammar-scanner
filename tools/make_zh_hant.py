#!/usr/bin/env python3
"""用 OpenCC (s2twp, 台湾正体+常用词) 从简体中文基础资料生成繁体中文翻译文件。
日语片段（「」『』内的内容、以 〜 开头的语法形式）保持不变。
用法: pip install opencc-python-reimplemented && python3 tools/make_zh_hant.py
"""
import glob
import json
import os
import re

from opencc import OpenCC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")
cc = OpenCC("s2twp")

JA = r"[぀-ヿ㐀-鿿ーー々〆〜～]"
PROTECT = re.compile(r"「[^」]*」|『[^』]*』|[〜～]" + JA + "*")


def conv(text: str) -> str:
    out, last = [], 0
    for m in PROTECT.finditer(text):
        out.append(cc.convert(text[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(cc.convert(text[last:]))
    return "".join(out)


def main():
    for path in sorted(glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json"))):
        level = os.path.basename(path)[len("grammar_"):-len(".json")]
        with open(path, encoding="utf-8") as f:
            base = json.load(f)
        out = []
        for p in base:
            item = {"id": p["id"]}
            if re.search(r"[（(][^）)]*[\u4e00-\u9fff]", p["title"]):
                item["title"] = conv(p["title"])
            out.append({
                **item,
                "meaning": conv(p["meaning"]),
                "connection": conv(p["connection"]),
                "senses": [{
                    "label": conv(x["label"]),
                    "meaning": conv(x["meaning"]),
                    "connection": conv(x["connection"]),
                    "examples": [conv(e["zh"]) for e in x["examples"]],
                } for x in p["senses"]],
                "notes": [conv(x) for x in p.get("notes", [])],
                "scenes": {k: [{
                    "title": conv(sc["title"]),
                    "description": conv(sc["description"]),
                    "example": conv(sc["example"]["zh"]),
                } for sc in p["scenes"][k]] for k in ("daily", "work")},
                "etymology": conv(p["etymology"]),
                "formation": conv(p.get("formation", "")),
                "similar": [{"title": conv(s["title"]), "explanation": conv(s["explanation"])} for s in p["similar"]],
            })
        dst = os.path.join(GRAMMAR_DIR, "l10n", f"l10n_zh-Hant_{level}.json")
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print("wrote", dst, len(out))


if __name__ == "__main__":
    main()
