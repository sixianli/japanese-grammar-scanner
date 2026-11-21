#!/usr/bin/env python3
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


DEBT = os.path.join(ROOT, "tools", "contrast_debt.json")
DEBT_KINDS = {
    "cue": "虚线线索没有在「怎么分辨」里点名",
    "note": "组说明不合格式",
    "highlight": "例句高亮部分认不出是这个语法点",
    "duplicate": "同一个详情页里例句重复",
}
VAGUE_MEANING_NOTE = re.compile(r"」或「|」／「|，或|有关|这类|之类|搭配|两种")
PUNCT = re.compile(r"[\s。、，,.！!？?「」『』…—\-]")


def note_problem(kind, note):
    if kind == "meaning" and VAGUE_MEANING_NOTE.search(note):
        return "「意思差不多的」说明只能写一个具体的共同意思，不能用「或」「／」把两个意思连在一起，也不能写「有关」「这类」这种笼统说法"
    if kind == "look" and "↔" not in note and "「" not in note:
        return "「长得像的」说明要写出长得像的写法：「A ↔ B」，写法完全一样时用「」写出这个写法"
    if kind == "root" and "「" not in note:
        return "「同一个词变来的」说明要用「」写出源头词"
    return None


def plain(ja):
    return "".join((seg[1:] if seg[:1] in "*~" else seg).split(":", 1)[0] for seg in ja.split("|"))


def highlight_spans(ja):
    pos, spans = 0, []
    for seg in ja.split("|"):
        text = (seg[1:] if seg[:1] in "*~" else seg).split(":", 1)[0]
        if seg.startswith("*"):
            spans.append((pos, pos + len(text)))
        pos += len(text)
    return spans


def recognized(patterns, ja):
    text = plain(ja)
    hits = [(m.start(), m.end()) for pat in patterns for m in re.finditer(pat, text) if m.end() > m.start()]
    return any(max(a, c) < min(b, d) for a, b in highlight_spans(ja) for c, d in hits)


def same_sentence_key(text):
    return PUNCT.sub("", text)


def page_sentences(point, groups):
    out = []
    for n, sense in enumerate(point.get("senses") or []):
        out += [(f"义项{n + 1}", e["ja"]) for e in sense.get("examples") or []]
    for scenes in (point.get("scenes") or {}).values():
        out += [("场景", sc["example"]["ja"]) for sc in scenes]
    for g in groups:
        for it in g["items"]:
            for key in ("this", "that"):
                out += [(f"相近语法 {g['kind']}/{it['id']}", plain(s.get("ja", ""))) for s in sentences(it, key)]
    return out


def is_han(c):
    return "\u4e00" <= c <= "\u9fff" or c == "々"


def has_kana(text):
    return any("\u3040" <= c <= "\u30ff" for c in text)


def cue_words(ja):
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
    v = item.get(key)
    if isinstance(v, dict):
        return [v]
    return v if isinstance(v, list) else []


def text_fields(item):
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
    points = {}
    for f in glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json")):
        with open(f, encoding="utf-8") as fh:
            points.update({p["id"]: p for p in json.load(fh)})
    ids = set(points)
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

    debt = {k: set() for k in DEBT_KINDS}
    if not only_base and os.path.exists(DEBT):
        with open(DEBT, encoding="utf-8") as fh:
            debt.update({k: set(v) for k, v in json.load(fh).items() if k in DEBT_KINDS})
    failing = {k: set() for k in DEBT_KINDS}

    def report(kind, key, message):
        failing[kind].add(key)
        if key not in debt[kind]:
            errors.append(message)

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
            else:
                problem = note_problem(g["kind"], g["note"])
                if problem:
                    report("note", f"{pid}/{g['kind']}", f"contrasts.json: {pid}/{g['kind']} {problem}：{g['note']}")
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
                    owner = points.get(pid if key == "this" else it["id"])
                    for n, sent in enumerate(sents):
                        check_ja(sent.get("ja", ""), f"{where} ({key}[{n}])", errors)
                        if owner and not recognized(owner["patterns"], sent.get("ja", "")):
                            report("highlight", f"{pid}/{g['kind']}/{it['id']}/{key}{n}",
                                   f"{where} ({key}[{n}]): 高亮部分没被 {owner['id']} 的识别规则认出"
                                   f"「{plain(sent.get('ja', ''))}」")
                if pid in forms and "thisTitle" not in it:
                    check_forms(pid, sentences(it, "this"), forms[pid], where + " (本页)", errors)
                if it["id"] in forms and "title" not in it:
                    check_forms(it["id"], sentences(it, "that"), forms[it["id"]], where + " (对方)", errors)
                unnamed = [w for key in ("this", "that") for sent in sentences(it, key)
                           for w in cue_words(sent.get("ja", "")) if not cue_named(w, it.get("explain", ""))]
                if unnamed:
                    report("cue", f"{pid}/{g['kind']}/{it['id']}",
                           f"{where}: 虚线线索没有在「怎么分辨」里点名：{'、'.join(dict.fromkeys(unnamed))}"
                           f"（讲解里写出这个词，或者不标线索）")
                if "wrong" in it and not it["wrong"].get("ja", "").strip():
                    errors.append(f"{where}: wrong.ja 为空")

    groups_by_point = {p["id"]: p["groups"] for p in base}
    for pid, point in ([] if only_base else sorted(points.items())):
        seen = {}
        for where, text in page_sentences(point, groups_by_point.get(pid, [])):
            k = same_sentence_key(text)
            if k in seen:
                report("duplicate", f"{pid}/{k}",
                       f"{pid} 详情页: 例句「{text}」重复出现（{seen[k]}、{where}），第二处要换一句")
            else:
                seen[k] = where

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
        if "--update-debt" in sys.argv:
            with open(DEBT, "w", encoding="utf-8") as fh:
                json.dump({k: sorted(v) for k, v in failing.items()}, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
            debt = failing
            print(f"已写入 {os.path.relpath(DEBT, ROOT)}")
        for kind, label in DEBT_KINDS.items():
            stale = sorted(debt[kind] - failing[kind])
            if stale:
                errors.append(f"tools/contrast_debt.json 的 {kind} 里有 {len(stale)} 条已经改好（或已删除），"
                              f"请运行 --update-debt 把它们移出清单：{'、'.join(stale[:5])}")
            print(f"{label}的旧条目（待改）：{len(failing[kind] & debt[kind])} 条")

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
