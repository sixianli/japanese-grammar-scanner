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
JA_WORDS = ["医者", "来週", "猫"]
FIX = {"錶面": "表面", "物件": "對象"}
PROTECT = re.compile(
    r"「[^」]*[" + KANA + r"][^」]*」|『[^』]*[" + KANA + r"][^』]*』"
    r"|[〜～][" + KANA + KANJI + r"]*"
    r"|(?:(?<![" + KANJI + r"])[" + KANJI + r"]{1,2})?[" + KANA + r"]+(?:[" + KANJI + r"]+[" + KANA + r"]+)*"
)
JA_WORDS_IN_TEXT = JA_WORDS
KANJI_CHARS = "".join(chr(c) for c in range(0x3400, 0xA000)) + "々〆"


def japanese_corpus():
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


def conv(text, words=()):
    if not isinstance(text, str):
        return text
    spans = protected_spans(text) + [(m.start(), m.end()) for w in words for m in re.finditer(re.escape(w), text)]
    merged = []
    for a, b in sorted(spans):
        if merged and a <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], b))
        else:
            merged.append((a, b))
    out, last = [], 0
    for a, b in merged:
        out.append(convert_plain(text[last:a], words))
        out.append(text[a:b])
        last = b
    out.append(convert_plain(text[last:], words))
    return "".join(out)


def cue_words(it):
    out = []
    for k in ("this", "that"):
        for s in sentences(it[k]):
            cur = ""
            for seg in (s.get("ja") or "").split("|"):
                if seg.startswith("~"):
                    cur += seg[1:].split(":", 1)[0]
                elif cur:
                    out.append(cur)
                    cur = ""
            if cur:
                out.append(cur)
    return tuple(dict.fromkeys(out))


def convert_plain(s, words=()):
    if not s:
        return s
    keep = re.compile("|".join(map(re.escape, sorted(set(JA_WORDS_IN_TEXT) | set(words), key=len, reverse=True))))
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
    o["explain"] = conv(it["explain"], cue_words(it))
    return o


def japanese_runs(text):
    return [text[a:b] for a, b in protected_spans(text or "")]


def main():
    with open(os.path.join(DIR, "contrasts.json"), encoding="utf-8") as fh:
        base = json.load(fh)
    out = {"points": [{"id": p["id"], "groups": [{"kind": g["kind"], "note": conv(g["note"]),
                                                  "items": [item(i) for i in g["items"]]}
                                                 for g in p["groups"]]} for p in base["points"]]}
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
