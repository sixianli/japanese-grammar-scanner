#!/usr/bin/env python3
"""给含有中文说明的语法标题（如「〜そうだ（样态）」）写入各语言的 title。
用法: python3 tools/l10n_titles.py   （在翻译文件生成后运行，可重复运行）"""
import glob
import json
import os

from opencc import OpenCC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar", "l10n")
GRAMMAR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")

# id: (en, ko, es, vi)
TITLES = {
    "you-ni-purpose": ("〜ように (purpose)", "〜ように (목적)", "〜ように (finalidad)", "〜ように (mục đích)"),
    "sou-da-appearance": ("〜そうだ (looks like)", "〜そうだ (양태)", "〜そうだ (apariencia)", "〜そうだ (trông có vẻ)"),
    "sou-da-hearsay": ("〜そうだ (hearsay)", "〜そうだ (전문)", "〜そうだ (según dicen)", "〜そうだ (nghe nói)"),
    "ba-conditional": ("〜ば (conditional)", "〜ば (가정)", "〜ば (condicional)", "〜ば (giả định)"),
    "passive": ("〜れる・〜られる (passive)", "〜れる・〜られる (수동)", "〜れる・〜られる (pasiva)", "〜れる・〜られる (bị động)"),
    "causative": ("〜せる・〜させる (causative)", "〜せる・〜させる (사역)", "〜せる・〜させる (causativa)", "〜せる・〜させる (sai khiến)"),
    "noni": ("〜のに (contrast)", "〜のに (역접)", "〜のに (concesión)", "〜のに (nghịch tiếp)"),
    "kara-reason": ("〜から (reason)", "〜から (원인・이유)", "〜から (causa)", "〜から (nguyên nhân)"),
}
LANGS = ["en", "ko", "es", "vi"]


def main():
    cc = OpenCC("s2twp")
    base_titles = {}
    for f in glob.glob(os.path.join(GRAMMAR, "grammar_*.json")):
        for p in json.load(open(f, encoding="utf-8")):
            base_titles[p["id"]] = p["title"]
    for path in sorted(glob.glob(os.path.join(L10N, "l10n_*.json"))):
        lang = os.path.basename(path).split("_")[1]
        data = json.load(open(path, encoding="utf-8"))
        for item in data:
            if item["id"] not in TITLES:
                continue
            if lang == "zh-Hant":
                item["title"] = cc.convert(base_titles[item["id"]])
            elif lang in LANGS:
                item["title"] = TITLES[item["id"]][LANGS.index(lang)]
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print("ok")


if __name__ == "__main__":
    main()
