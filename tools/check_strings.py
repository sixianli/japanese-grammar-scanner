#!/usr/bin/env python3
"""硬门槛：界面上的中文文字都要在 tools/make_strings.py 里有全部语言的翻译。

扫描 Swift 代码里会显示到界面上的中文字面量（tr("…")、Text(localized: "…")、Button / Label / NavigationLink / Section 的标题、
引导页 title / message、LegalContent 的小节、AppFeature 的使用指南），没有在 make_strings.py 的 S 里登记的就报错。
含 \\( 插值的文字按 %lld / %@ 规则另行登记，这里跳过。
用法: python3 tools/check_strings.py
"""
import glob
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "JapaneseGrammarScanner")
CJK = re.compile(r"[㐀-鿿]")
# 不翻译的文字（语言的本名等）
VERBATIM = {"简体中文", "繁體中文"}
PATTERNS = [
    r'\btr\("((?:[^"\\]|\\.)*)"\)',
    r'Text\(localized:\s*"((?:[^"\\]|\\.)*)"\)',
    r'\b(?:title|message|body|summary|tip|usage):\s*"((?:[^"\\]|\\.)*)"',
    r'Step\("[^"]*",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)',
    r'case \.\w+:\s*"((?:[^"\\]|\\.)*)"',
]


def load_keys():
    # make_strings.py 顶部会 import opencc（CI 的数据校验环境里没有装）：这里只需要它的字典，换成占位模块
    import types
    stub = types.ModuleType("opencc")
    stub.OpenCC = lambda *_: None
    sys.modules.setdefault("opencc", stub)
    spec = importlib.util.spec_from_file_location("make_strings", os.path.join(ROOT, "tools", "make_strings.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return set(mod.S)


def main():
    keys = load_keys()
    missing = {}
    for f in glob.glob(os.path.join(APP, "**", "*.swift"), recursive=True):
        src = open(f, encoding="utf-8").read()
        # 只看代码，不看注释
        src = re.sub(r"//[^\n]*", "", src)
        for pat in PATTERNS:
            for m in re.finditer(pat, src):
                for s in m.groups():
                    if not s or not CJK.search(s) or "\\(" in s or s in VERBATIM:
                        continue
                    if s.replace('\\"', '"') not in keys:
                        missing.setdefault(s, os.path.relpath(f, ROOT))
    for f in glob.glob(os.path.join(APP, "Resources", "Legal", "*.json")):
        import json
        for c in json.load(open(f, encoding="utf-8")).get("components", []):
            if CJK.search(c.get("usage", "")) and c["usage"] not in keys:
                missing.setdefault(c["usage"], os.path.relpath(f, ROOT))
    if missing:
        print(f"有 {len(missing)} 条界面文字没有翻译（请在 tools/make_strings.py 的 S 和 MY 里补上，再运行 make_strings.py）:")
        for s, f in sorted(missing.items(), key=lambda x: x[1]):
            print(f"  - {f}: {s}")
        return 1
    print(f"界面文字翻译：全部 {len(keys)} 条已登记 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
