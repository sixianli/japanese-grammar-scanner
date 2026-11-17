#!/usr/bin/env python3
"""离线生成假名注音（振り仮名）数据：Resources/Grammar/furigana.json

收集所有日语文本（义项例句、场景例句、讲解中「」里的日语），用 SudachiPy（字典 sudachidict_core）做形态素分析，
只给汉字部分标注平假名读音（送假名不重复标注）。App 运行时直接查表显示，不做任何在线/模型推断。

输出格式：{ "日本語の文": [["日本語", "にほんご"], ["の", null], ["文", "ぶん"]], ... }  （只收录含汉字的文本）
用法: pip install sudachipy sudachidict_core && python3 tools/make_furigana.py
"""
import glob
import json
import os
import re

from sudachipy import dictionary, tokenizer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")
OUT = os.path.join(GRAMMAR_DIR, "furigana.json")

KANJI = re.compile(r"[㐀-鿿豈-﫿々〆ヶ]")
KANA = re.compile(r"[぀-ヿー]")
QUOTED = re.compile(r"「([^」]+)」|『([^』]+)』")
# 形态素分析容易读错的词（按上下文最常见的读法覆盖）
OVERRIDES = {"何時": "なんじ", "一日": "いちにち", "今日中": "きょうじゅう", "上手": "じょうず", "下手": "へた"}

tok = dictionary.Dictionary(dict="core").create()
MODE = tokenizer.Tokenizer.SplitMode.C


def kata2hira(s: str) -> str:
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def align(surface: str, reading: str):
    """把一个词的读音分配到汉字部分：食べる/たべる → [食:た][べる]"""
    if not KANJI.search(surface):
        return [[surface, None]]
    parts = re.findall(r"[㐀-鿿豈-﫿々〆ヶ]+|[^㐀-鿿豈-﫿々〆ヶ]+", surface)
    pattern = "".join("(.+?)" if KANJI.match(p) else "(" + re.escape(kata2hira(p)) + ")" for p in parts)
    m = re.fullmatch(pattern, reading)
    if not m:
        return [[surface, reading]]
    return [[p, g if KANJI.match(p) else None] for p, g in zip(parts, m.groups())]


def furigana(text: str):
    segs = []
    for m in tok.tokenize(text, MODE):
        surface = m.surface()
        reading = OVERRIDES.get(surface) or kata2hira(m.reading_form())
        if not KANJI.search(surface) or not reading or reading == surface:
            segs.append([surface, None])
        else:
            segs += align(surface, reading)
    # 合并相邻的无注音片段
    merged = []
    for base, ruby in segs:
        if ruby is None and merged and merged[-1][1] is None:
            merged[-1][0] += base
        else:
            merged.append([base, ruby])
    return merged


def japanese_texts():
    texts = set()

    def add_quoted(s):
        if not isinstance(s, str):
            return
        for m in QUOTED.finditer(s):
            inner = m.group(1) or m.group(2)
            if KANA.search(inner) or KANJI.search(inner):
                texts.add(inner)

    def walk(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "ja" and isinstance(v, str):
                    texts.add(v)
                elif k in ("patterns", "negativeExamples", "id", "subsumes"):
                    continue
                else:
                    walk(v)
        elif isinstance(obj, list):
            for v in obj:
                walk(v)
        else:
            add_quoted(obj)

    for path in glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json")) + glob.glob(os.path.join(GRAMMAR_DIR, "l10n", "*.json")):
        with open(path, encoding="utf-8") as f:
            walk(json.load(f))
    return texts


def main():
    out = {}
    for t in sorted(japanese_texts()):
        if KANJI.search(t):
            out[t] = furigana(t)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print(f"wrote {OUT}: {len(out)} entries")


if __name__ == "__main__":
    main()
