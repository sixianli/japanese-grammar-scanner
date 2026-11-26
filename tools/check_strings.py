#!/usr/bin/env python3
"""硬门槛：界面上的中文文字都要在 tools/make_strings.py 里有全部语言的翻译。

扫描 Swift 代码里会显示到界面上的中文字面量（tr("…")、Text(localized: "…")、Button / Label / NavigationLink / Section 的标题、
引导页 title / message、LegalContent 的小节、AppFeature 的使用指南），没有在 make_strings.py 的 S 里登记的就报错。
含 \\( 插值的文字按 %lld / %@ 规则另行登记，这里跳过。
桌面名（CFBundleDisplayName）每种语言都必须是 HOME_SCREEN_FITS 里实拍过、在最窄的 iPhone 上不会被截断的名字。
用法: python3 tools/check_strings.py
"""
import glob
import importlib.util
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "JapaneseGrammarScanner")
CJK = re.compile(r"[㐀-鿿]")
VERBATIM = {"简体中文", "繁體中文"}
INFO_PLIST = os.path.join(APP, "InfoPlist.xcstrings")
HOME_SCREEN_FITS = {
    "日语语法速查", "日语语法", "日语语法扫描", "日语语法拍照",
    "日語文法速查", "日語語法速查", "日語文法", "日文文法", "日檢文法",
    "JP Grammar", "Gramática JP", "Ngữ Pháp JP",
    "일본어 문법", "일본어 문법 스캔", "일어 문법",
    "ဂျပန်သဒ္ဒါ",
}
PATTERNS = [
    r'\btr\("((?:[^"\\]|\\.)*)"\)',
    r'Text\(localized:\s*"((?:[^"\\]|\\.)*)"\)',
    r'\b(?:title|message|body|summary|tip|usage):\s*"((?:[^"\\]|\\.)*)"',
    r'Step\("[^"]*",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)',
    r'case \.\w+:\s*"((?:[^"\\]|\\.)*)"',
]


def load_keys():
    import types
    stub = types.ModuleType("opencc")
    stub.OpenCC = lambda *_: None
    sys.modules.setdefault("opencc", stub)
    spec = importlib.util.spec_from_file_location("make_strings", os.path.join(ROOT, "tools", "make_strings.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return set(mod.S)


def home_screen_name_problems(catalog):
    names = catalog["strings"]["CFBundleDisplayName"]["localizations"]
    return [f"{lang}: 「{v['stringUnit']['value']}」没有在最窄的 iPhone 上实拍过，可能被截断；实拍确认后加进 HOME_SCREEN_FITS"
            for lang, v in sorted(names.items()) if v["stringUnit"]["value"] not in HOME_SCREEN_FITS]


def main():
    home = home_screen_name_problems(json.load(open(INFO_PLIST, encoding="utf-8")))
    if home:
        print("桌面名可能被截断：")
        for p in home:
            print("  - " + p)
        return 1
    keys = load_keys()
    missing = {}
    for f in glob.glob(os.path.join(APP, "**", "*.swift"), recursive=True):
        src = open(f, encoding="utf-8").read()
        src = re.sub(r"//[^\n]*", "", src)
        for pat in PATTERNS:
            for m in re.finditer(pat, src):
                for s in m.groups():
                    if not s or not CJK.search(s) or "\\(" in s or s in VERBATIM:
                        continue
                    if s.replace('\\"', '"') not in keys:
                        missing.setdefault(s, os.path.relpath(f, ROOT))
    for f in glob.glob(os.path.join(APP, "Resources", "Legal", "*.json")):
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
