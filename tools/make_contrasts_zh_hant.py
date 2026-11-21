#!/usr/bin/env python3
"""从简体中文的相近语法资料（contrasts.json）生成繁体中文翻译（contrasts_zh-Hant.json）。

OpenCC（s2twp）只转换中文部分，日语保持原样：
  * 含假名的「」『』引用、〜 开头的语法形式、含假名的日语片段（连同紧挨着的汉字，如 来た、着く、静か）
  * 还有一张「日语汉字词」表（医者、机、来週 …），出现时也不转换
转换后检查：简体文件里出现的每个日语片段，在繁体文件对应位置必须原样保留，否则报错。
用法: python3 tools/make_contrasts_zh_hant.py
"""
import glob
import json
import os
import re
import sys

from opencc import OpenCC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar", "contrasts")
cc = OpenCC("s2twp")

KANA = "ぁ-ゟ゠-ヿー"
KANJI = "㐀-鿿々〆"
# 不能被转换的日语汉字词（讲解正文里有时不加引号、也不带假名出现）
JA_WORDS = ["医者", "来週", "猫"]
# OpenCC（台湾用语）对这几个词的转换在语法讲解里是错的
FIX = {"錶面": "表面", "物件": "對象"}
# 引号里有假名的才算日语（「刚刚」这类中文引语照常转换）
PROTECT = re.compile(
    r"「[^」]*[" + KANA + r"][^」]*」|『[^』]*[" + KANA + r"][^』]*』"
    r"|[〜～][" + KANA + KANJI + r"]*"
    # 含假名的日语片段：前面的汉字只在词首（前一个字不是汉字）、且最多两个字时算进来，如 医者になる、泳げる；
    # 中间的汉字要后面还跟着假名才算（電話がかかってきた），这样「动词ます形」「な形容词」里的中文不会被当成日语
    r"|(?:(?<![" + KANJI + r"])[" + KANJI + r"]{1,2})?[" + KANA + r"]+(?:[" + KANJI + r"]+[" + KANA + r"]+)*"
)
JA_WORDS_IN_TEXT = JA_WORDS
KANJI_CHARS = "".join(chr(c) for c in range(0x3400, 0xA000)) + "々〆"


def japanese_corpus():
    """所有日语例句（相近语法例句 + 语法库例句）：用来判断假名前面的汉字是日语词的一部分，还是中文讲解里的词"""
    parts = []
    with open(os.path.join(DIR, "contrasts.json"), encoding="utf-8") as fh:
        for p in json.load(fh)["points"]:
            for g in p["groups"]:
                for it in g["items"]:
                    for k in ("this", "that"):
                        for s in sentences(it[k]):
                            parts.append(re.sub(r":[^|]*", "", (s.get("ja") or "")).replace("|", "").replace("*", "").replace("~", ""))
    for f in glob.glob(os.path.join(os.path.dirname(DIR), "grammar_*.json")):
        with open(f, encoding="utf-8") as fh:
            for p in json.load(fh):
                for x in p.get("senses", []):
                    parts += [e.get("ja", "") for e in x.get("examples", [])]
    return "\n".join(parts)


CORPUS = None


def protected_spans(text):
    """日语片段的位置。假名前面的汉字：日语例句里确实出现过「这几个汉字＋这个假名」才算日语（医者に、来た），
    否则当作中文讲解（动词ます形、读な、却是な），照常转换。"""
    global CORPUS
    if CORPUS is None:
        CORPUS = japanese_corpus()
    spans = []
    for m in PROTECT.finditer(text):
        a, b = m.start(), m.end()
        run = m.group(0)
        if run[0] not in "「『〜～":
            lead = len(run) - len(run.lstrip(KANJI_CHARS))
            if lead and run[:lead + 1] not in CORPUS:
                a += lead
        spans.append((a, b))
    return spans


def conv(text):
    if not isinstance(text, str):
        return text
    out, last = [], 0
    for a, b in protected_spans(text):
        out.append(convert_plain(text[last:a]))
        out.append(text[a:b])
        last = b
    out.append(convert_plain(text[last:]))
    return "".join(out)


def convert_plain(s):
    if not s:
        return s
    keep = re.compile("|".join(map(re.escape, JA_WORDS_IN_TEXT)))
    out, last = [], 0
    for m in keep.finditer(s):
        out.append(cc.convert(s[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(cc.convert(s[last:]))
    text = "".join(out)
    for a, b in FIX.items():
        text = text.replace(a, b)
    return text


def sentences(v):
    return [v] if isinstance(v, dict) else (v or [])


def item(it):
    o = {"id": it["id"]}
    for k in ("title", "thisTitle"):
        if k in it:
            o[k] = conv(it[k])
    o["diff"] = conv(it["diff"])
    for k in ("this", "that"):
        o[k] = [{"tag": conv(s["tag"]), "tr": conv(s["tr"])} for s in sentences(it[k])]
    if "wrong" in it:
        o["wrong"] = {"why": conv(it["wrong"]["why"])}
    o["explain"] = conv(it["explain"])
    return o


def japanese_runs(text):
    return [text[a:b] for a, b in protected_spans(text or "")]


def main():
    with open(os.path.join(DIR, "contrasts.json"), encoding="utf-8") as fh:
        base = json.load(fh)
    out = {"points": [{"id": p["id"], "groups": [{"kind": g["kind"], "note": conv(g["note"]),
                                                  "items": [item(i) for i in g["items"]]}
                                                 for g in p["groups"]]} for p in base["points"]]}
    # 检查：日语片段原样保留
    errors = 0
    for bp, lp in zip(base["points"], out["points"]):
        for bg, lg in zip(bp["groups"], lp["groups"]):
            pairs = [(bg["note"], lg["note"])]
            for bi, li in zip(bg["items"], lg["items"]):
                pairs += [(bi["diff"], li["diff"]), (bi["explain"], li["explain"])]
            for zh, hant in pairs:
                for run in japanese_runs(zh):
                    if run not in hant:
                        errors += 1
                        print(f"  {bp['id']}: 日语片段被改动「{run}」")
    with open(os.path.join(DIR, "contrasts_zh-Hant.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"contrasts_zh-Hant.json：{len(out['points'])} 个语法点" + ("" if not errors else f"，{errors} 处日语被改动"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
