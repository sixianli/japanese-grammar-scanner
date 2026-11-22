#!/usr/bin/env python3
"""同形语法已合并为一个语法点，标题不再带中文说明，各语言译文也不再需要单独的 title。
本脚本删除译文文件中残留的 title 字段（可重复运行）。"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar", "l10n")


def main():
    for path in sorted(glob.glob(os.path.join(L10N, "l10n_*.json"))):
        data = json.load(open(path, encoding="utf-8"))
        if any("title" in item for item in data):
            for item in data:
                item.pop("title", None)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
                f.write("\n")
    print("ok")


if __name__ == "__main__":
    main()
