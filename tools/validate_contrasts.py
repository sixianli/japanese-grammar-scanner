#!/usr/bin/env python3
"""校验「相近语法」新版对比资料 Resources/Grammar/contrasts/。

contrasts.json（简体中文基础文件）：
  * 语法点 id、对比对象 id 都存在于语法库；同一语法点下对比对象不重复
  * 分组 kind 只能是 root / look / meaning，且按这个顺序出现、不重复、不为空
  * 例句写法正确：用 | 分段；「漢字:かな」注音只放在含汉字的片段上、读音只用假名；
    * 开头 = 语法本体（每句至少一处）；~ 开头 = 线索
  * 线索（虚线）必须是「怎么分辨」（explain）里点名的词（Build 17 反馈 9）：相邻的 ~ 片段连成一个词，
    这个词要在 explain 里出现（全是汉字的词，前后紧挨着汉字不算，和 App 里 RubyText.cueRanges 同一条规则）。
    找不出起决定作用的词就不标。旧资料里还没改好的条目记在 tools/contrast_cue_debt.json，
    新写的、改过的条目不能再进这个清单；清单里的条目改好后要删掉（--update-cue-debt 重新生成）。
  * 文字字段不为空
  * this / that 是例句数组（兼容旧的单个对象）
  * 多形式语法点（contrasts/forms.json 里 type=A）：没有用 title / thisTitle 点明只比哪一种时，
    这一侧每种形式都要有一句例句（高亮部分里出现该形式的 key）
contrasts_<语言>.json（翻译）：
  * 与基础文件结构一一对应（语法点、分组、条目的顺序和数量）；文字字段不为空
  * 除繁体中文外，译文不残留中文专用字

用法: python3 tools/validate_contrasts.py
      python3 tools/validate_contrasts.py --base <某个批次文件.json> [--forms <forms.json>]
          只校验这一份基础文件（分批编写时用）
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")
DIR = os.path.join(GRAMMAR_DIR, "contrasts")
KINDS = ["root", "look", "meaning"]
LANGS = ["zh-Hant", "en", "ko", "es", "vi", "my"]
CHINESE_ONLY = set("这们吗么说时为个词动语义过还没让对该种样从进這們嗎麼說對該讓樣")
KANJI = re.compile(r"[㐀-鿿々〆0-9０-９]")
KANA = re.compile(r"^[ぁ-ゟ゠-ヿー]+$")


def strip_quotes(text):
    """去掉「」『』里的日语和以 〜 开头的语法形式（这些本来就允许出现汉字）。"""
    text = re.sub(r"「[^」]*」|『[^』]*』", "", text)
    return re.sub(r"[〜～✗][぀-ヿ㐀-鿿ー々]*", "", text)


def check_ja(ja, where, errors):
    has_grammar = False
    for seg in ja.split("|"):
        if not seg:
            errors.append(f"{where}: 有空片段")
            continue
        body = seg
        if body[0] in "*~":
            if body[0] == "*":
                has_grammar = True
            body = body[1:]
        if ":" in body:
            base, ruby = body.split(":", 1)
            if not base or not ruby:
                errors.append(f"{where}: 注音片段写法不对「{seg}」")
            elif not KANJI.search(base):
                errors.append(f"{where}: 注音放在了没有汉字的片段上「{seg}」")
            elif not KANA.match(ruby):
                errors.append(f"{where}: 读音只能是假名「{seg}」")
        elif re.search(r"[㐀-鿿]", body):
            errors.append(f"{where}: 汉字没有注音「{seg}」")
    if not has_grammar:
        errors.append(f"{where}: 例句里没有标出语法本体（* 开头的片段）")


CUE_DEBT = os.path.join(ROOT, "tools", "contrast_cue_debt.json")


def is_han(c):
    return "\u4e00" <= c <= "\u9fff" or c == "々"


def has_kana(text):
    return any("\u3040" <= c <= "\u30ff" for c in text)


def cue_words(ja):
    """例句里的线索词：相邻的 ~ 片段连成一个词。"""
    out, cur = [], ""
    for seg in ja.split("|"):
        if not seg:
            continue
        body = seg[1:] if seg[0] in "*~" else seg
        if seg[0] == "~":
            cur += body.split(":", 1)[0]
        elif cur:
            out.append(cur)
            cur = ""
    if cur:
        out.append(cur)
    return out


def cue_named(word, text):
    """线索词在讲解里出现（规则同 RubyText.cueRanges）。"""
    start = 0
    while True:
        i = text.find(word, start)
        if i < 0:
            return False
        if has_kana(word):
            return True
        before = text[i - 1] if i > 0 else ""
        after = text[i + len(word)] if i + len(word) < len(text) else ""
        if not (before and is_han(before)) and not (after and is_han(after)):
            return True
        start = i + 1


def sentences(item, key):
    """this / that：例句数组（旧格式是单个对象）。"""
    v = item.get(key)
    if isinstance(v, dict):
        return [v]
    return v if isinstance(v, list) else []


def text_fields(item):
    """一个条目里需要翻译的文字（与 App 的 apply 顺序一致）。"""
    out = [("diff", item.get("diff")), ("explain", item.get("explain"))]
    for key in ("this", "that"):
        for n, s in enumerate(sentences(item, key)):
            out += [(f"{key}[{n}].tag", s.get("tag")), (f"{key}[{n}].tr", s.get("tr"))]
    if "wrong" in item:
        out.append(("wrong.why", item["wrong"].get("why")))
    if "title" in item:
        out.append(("title", item.get("title")))
    if "thisTitle" in item:
        out.append(("thisTitle", item.get("thisTitle")))
    return out


def highlighted(ja):
    return "".join(seg[1:].split(":")[0] for seg in ja.split("|") if seg.startswith("*"))


def check_forms(pid, sents, forms, where, errors):
    """A 类多形式语法点：每种形式都要有一句例句（高亮里出现 key；一句只算它包含的最长 key）。"""
    keys = sorted((f["key"] for f in forms), key=len, reverse=True)
    covered = set()
    for s in sents:
        h = highlighted(s.get("ja", ""))
        hit = next((k for k in keys if k in h), None)
        if hit:
            covered.add(hit)
    missing = [k for k in keys if k not in covered]
    if missing:
        errors.append(f"{where}: {pid} 有几种用法不同的形式，缺少这些形式的例句：{'、'.join(missing)}"
                      f"（只比其中一种时用 title / thisTitle 点明）")


def main():
    errors = []
    ids = set()
    for f in glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json")):
        with open(f, encoding="utf-8") as fh:
            ids |= {p["id"] for p in json.load(fh)}
    only_base = "--base" in sys.argv
    base_path = sys.argv[sys.argv.index("--base") + 1] if only_base else os.path.join(DIR, "contrasts.json")
    if not os.path.exists(base_path):
        print("没有 contrasts.json，跳过")
        return 0
    with open(base_path, encoding="utf-8") as fh:
        base = json.load(fh)["points"]
    forms_path = sys.argv[sys.argv.index("--forms") + 1] if "--forms" in sys.argv else os.path.join(DIR, "forms.json")
    forms = {}
    if os.path.exists(forms_path):
        with open(forms_path, encoding="utf-8") as fh:
            forms = {k: v["forms"] for k, v in json.load(fh).items() if v.get("type") == "A" and v.get("forms")}

    cue_debt = set()
    if not only_base and os.path.exists(CUE_DEBT):
        with open(CUE_DEBT, encoding="utf-8") as fh:
            cue_debt = set(json.load(fh)["items"])
    cue_failing = set()

    seen_points = set()
    for p in base:
        pid = p["id"]
        if pid not in ids:
            errors.append(f"contrasts.json: 语法点 {pid} 不存在")
        if pid in seen_points:
            errors.append(f"contrasts.json: 语法点 {pid} 重复")
        seen_points.add(pid)
        kinds = [g["kind"] for g in p["groups"]]
        if any(k not in KINDS for k in kinds) or kinds != sorted(set(kinds), key=KINDS.index):
            errors.append(f"contrasts.json: {pid} 的分组必须按 root/look/meaning 顺序且不重复：{kinds}")
        targets = set()
        for g in p["groups"]:
            if not g["items"]:
                errors.append(f"contrasts.json: {pid}/{g['kind']} 没有条目（没有就不要写这一组）")
            if not g.get("note", "").strip():
                errors.append(f"contrasts.json: {pid}/{g['kind']} 缺少说明")
            for it in g["items"]:
                where = f"contrasts.json: {pid} → {it['id']}"
                if it["id"] not in ids:
                    errors.append(f"{where}: 对比对象不存在")
                if it["id"] == pid:
                    errors.append(f"{where}: 不能和自己对比")
                if it["id"] in targets and "title" not in it:
                    errors.append(f"{where}: 同一个语法点下重复出现")
                targets.add(it["id"])
                for name, val in text_fields(it):
                    if not isinstance(val, str) or not val.strip():
                        errors.append(f"{where}: {name} 为空")
                for key in ("this", "that"):
                    sents = sentences(it, key)
                    if not sents:
                        errors.append(f"{where}: 缺少 {key} 例句")
                    for n, sent in enumerate(sents):
                        check_ja(sent.get("ja", ""), f"{where} ({key}[{n}])", errors)
                if pid in forms and "thisTitle" not in it:
                    check_forms(pid, sentences(it, "this"), forms[pid], where + " (本页)", errors)
                if it["id"] in forms and "title" not in it:
                    check_forms(it["id"], sentences(it, "that"), forms[it["id"]], where + " (对方)", errors)
                unnamed = [w for key in ("this", "that") for sent in sentences(it, key)
                           for w in cue_words(sent.get("ja", "")) if not cue_named(w, it.get("explain", ""))]
                if unnamed:
                    key = f"{pid}/{g['kind']}/{it['id']}"
                    cue_failing.add(key)
                    if key not in cue_debt:
                        errors.append(f"{where}: 虚线线索没有在「怎么分辨」里点名：{'、'.join(dict.fromkeys(unnamed))}"
                                      f"（讲解里写出这个词，或者不标线索）")
                if "wrong" in it and not it["wrong"].get("ja", "").strip():
                    errors.append(f"{where}: wrong.ja 为空")

    for lang in ([] if only_base else LANGS):
        path = os.path.join(DIR, f"contrasts_{lang}.json")
        name = os.path.basename(path)
        if not os.path.exists(path):
            errors.append(f"{name}: 缺少翻译文件")
            continue
        with open(path, encoding="utf-8") as fh:
            loc = json.load(fh)["points"]
        if [p["id"] for p in loc] != [p["id"] for p in base]:
            errors.append(f"{name}: 语法点列表与基础文件不一致")
            continue
        for bp, lp in zip(base, loc):
            if len(bp["groups"]) != len(lp["groups"]):
                errors.append(f"{name}: {bp['id']} 分组数量不一致")
                continue
            for bg, lg in zip(bp["groups"], lp["groups"]):
                texts = [("note", lg.get("note"))]
                if lg.get("kind") != bg["kind"]:
                    errors.append(f"{name}: {bp['id']} 分组顺序与基础文件不一致（{lg.get('kind')} ≠ {bg['kind']}）")
                if [i.get("id") for i in lg["items"]] != [i["id"] for i in bg["items"]]:
                    errors.append(f"{name}: {bp['id']}/{bg['kind']} 条目的对比对象与基础文件不一致")
                if len(bg["items"]) != len(lg["items"]):
                    errors.append(f"{name}: {bp['id']}/{bg['kind']} 条目数量不一致")
                    continue
                for bi, li in zip(bg["items"], lg["items"]):
                    for key in ("this", "that"):
                        if len(sentences(li, key)) != len(sentences(bi, key)):
                            errors.append(f"{name}: {bp['id']} → {bi['id']} {key} 例句数量与基础文件不一致")
                    if "thisTitle" in bi and "thisTitle" not in li:
                        errors.append(f"{name}: {bp['id']} → {bi['id']} 缺少 thisTitle")
                    if "wrong" in bi and "wrong" not in li:
                        errors.append(f"{name}: {bp['id']} → {bi['id']} 缺少 wrong.why")
                    if "title" in bi and "title" not in li:
                        errors.append(f"{name}: {bp['id']} → {bi['id']} 缺少 title")
                    texts += [(f"{bi['id']}.{n}", v) for n, v in text_fields(li)]
                for n, v in texts:
                    where = f"{name}: {bp['id']} {n}"
                    if not isinstance(v, str) or not v.strip():
                        errors.append(f"{where} 为空")
                    elif lang != "zh-Hant":
                        left = set(strip_quotes(v)) & CHINESE_ONLY
                        if left:
                            errors.append(f"{where} 残留中文：{''.join(sorted(left))}")

    if not only_base:
        if "--update-cue-debt" in sys.argv:
            with open(CUE_DEBT, "w", encoding="utf-8") as fh:
                json.dump({"_doc": "虚线线索还没在「怎么分辨」里点名的旧条目（语法点/组/对比对象）。只能删，不能加；"
                                   "改好一条就删一条（python3 tools/validate_contrasts.py --update-cue-debt）。",
                           "items": sorted(cue_failing)}, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
            cue_debt = cue_failing
            print(f"已写入 {os.path.relpath(CUE_DEBT, ROOT)}：{len(cue_failing)} 条")
        stale = sorted(cue_debt - cue_failing)
        if stale:
            errors.append(f"tools/contrast_cue_debt.json 里有 {len(stale)} 条已经改好（或已删除），请运行 "
                          f"--update-cue-debt 把它们移出清单：{'、'.join(stale[:5])}")
        print(f"虚线线索待改的旧条目：{len(cue_failing & cue_debt)} 条")

    n_items = sum(len(g["items"]) for p in base for g in p["groups"])
    print(f"相近语法对比：{len(base)} 个语法点，{n_items} 条对比")
    if errors:
        print(f"发现 {len(errors)} 个问题:")
        for e in errors:
            print("  - " + e)
        return 1
    print("全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
