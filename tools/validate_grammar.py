#!/usr/bin/env python3
"""校验 App 内置的语法静态资源。

基础文件 JapaneseGrammarScanner/Resources/Grammar/grammar_*.json：
  * 必填字段齐全、类型正确；id 全局唯一；similar[].id / subsumes 引用存在
  * patterns 正则可编译，且只用 ICU(NSRegularExpression) 与 Python 共同支持的语法
  * 每个义项(senses)的每个例句都能被本语法点的 patterns 命中
  * negativeExamples 不能被命中
翻译文件 Resources/Grammar/l10n/l10n_<语言>_<等级>.json：
  * 与基础文件 id / 顺序 / 各数组长度一致，无空字段，译文不残留中文

用法: python3 tools/validate_grammar.py [--base-only] [--only <文件名片段>]
  --only n3_b04      只报告文件名包含该片段的文件的问题（并行编写时使用）
tools/grammar_catalog.json（全部语法点清单）中的 id 也视为已存在，可在 similar 中引用。
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")

LEVELS = {"N5", "N4", "N3", "N2", "N1"}
REQUIRED_STR = ["id", "title", "level", "meaning", "connection", "etymology", "formation"]
REMOVED_FIELDS = ["usage", "scenarios", "examples"]
FORBIDDEN_REGEX = [r"\(\?P", r"\\A", r"\\Z", r"\(\?#"]
L10N_LANGS = ["en", "ko", "es", "vi", "zh-Hant"]
# 只出现在中文、在日语中不使用的字（简体字及与日语新字体不同的繁体字），用于检查译文是否残留中文。
# 注意不要加入日语也使用的汉字（語、過、進、為、個、義、種、詞、従、話 等）。
CHINESE_ONLY = set("这们吗么说时为个词动语义过还没让对该种样从进這們嗎麼說對該讓樣")


# 简体中文专用字（日语中不使用），用于检查「」里的日语引文是否混入简体字
SIMPLIFIED_ONLY = set("这们吗么说时为个词动语义过还没让对该种样从进话见长门问间东车马鸟鱼读写买卖发电气书习师图钱银铁关开汉韩实运办务边应与专业")
QUOTE_RE = re.compile(r"「([^」]+)」")


def check_quotes(texts, where, errors):
    for t in texts:
        if not isinstance(t, str):
            continue
        for m in QUOTE_RE.finditer(t):
            inner = m.group(1)
            # 含假名、且不是「名词＋の」这类夹带中文说明的接续公式 → 视为日语引文
            if re.search(r"[\u3040-\u30ff]", inner) and "＋" not in inner and "+" not in inner:
                bad = sorted({c for c in inner if c in SIMPLIFIED_ONLY})
                if bad:
                    errors.append(f"{where}: 日语引文「{inner}」混入简体字 {''.join(bad)}")


def all_strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            if k not in ("patterns", "negativeExamples"):
                yield from all_strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from all_strings(v)


def is_str(v):
    return isinstance(v, str) and v.strip() != ""


def is_example(e):
    return isinstance(e, dict) and is_str(e.get("ja")) and is_str(e.get("zh"))


def check_point(gp, where, errors):
    for k in REQUIRED_STR:
        if not is_str(gp.get(k)):
            errors.append(f"{where}: 缺少字符串字段 {k}")
    for k in REMOVED_FIELDS:
        if k in gp:
            errors.append(f"{where}: 旧字段 {k} 应删除（已改为 senses / notes / scenes）")
    pats = gp.get("patterns")
    if not isinstance(pats, list) or not pats or not all(is_str(p) for p in pats):
        errors.append(f"{where}: patterns 必须是非空字符串数组")
    if gp.get("level") not in LEVELS:
        errors.append(f"{where}: level 非法 {gp.get('level')}")

    senses = gp.get("senses")
    if not isinstance(senses, list) or not (1 <= len(senses) <= 6):
        errors.append(f"{where}: senses 需要 1~6 个义项")
        senses = []
    for i, s in enumerate(senses):
        w = f"{where}.senses[{i}]"
        if not isinstance(s, dict):
            errors.append(f"{w}: 必须是对象")
            continue
        for k in ["label", "meaning", "connection"]:
            if not is_str(s.get(k)):
                errors.append(f"{w}: 缺少 {k}")
        ex = s.get("examples")
        if not isinstance(ex, list) or not (1 <= len(ex) <= 3) or not all(is_example(e) for e in ex):
            errors.append(f"{w}: examples 需要 1~3 个 {{ja, zh}}")

    notes = gp.get("notes", [])
    if not isinstance(notes, list) or not (1 <= len(notes) <= 5) or not all(is_str(n) for n in notes):
        errors.append(f"{where}: notes 应为 1~5 条字符串")

    kanji = gp.get("kanji")
    if kanji is not None and not (is_str(kanji) and re.search(r"[\u3400-\u9fff々]", kanji)):
        errors.append(f"{where}: kanji 若提供，必须是含汉字的写法")
    aliases = gp.get("aliases", [])
    if not isinstance(aliases, list) or not all(is_str(a) for a in aliases):
        errors.append(f"{where}: aliases 必须是字符串数组")

    scenes = gp.get("scenes")
    if not isinstance(scenes, dict):
        errors.append(f"{where}: 缺少 scenes")
    else:
        for key, lo, hi in [("daily", 1, 5), ("work", 1, 4)]:
            arr = scenes.get(key)
            if not isinstance(arr, list) or not (lo <= len(arr) <= hi):
                errors.append(f"{where}: scenes.{key} 需要 {lo}~{hi} 个场景")
                continue
            for j, sc in enumerate(arr):
                if not (isinstance(sc, dict) and is_str(sc.get("title")) and is_str(sc.get("description")) and is_example(sc.get("example"))):
                    errors.append(f"{where}: scenes.{key}[{j}] 需要 title / description / example{{ja, zh}}")

    sim = gp.get("similar")
    if not isinstance(sim, list) or not sim:
        errors.append(f"{where}: similar 至少 1 条")
    else:
        for s in sim:
            if not isinstance(s, dict) or not is_str(s.get("title")) or not is_str(s.get("explanation")):
                errors.append(f"{where}: similar 需要 title/explanation: {s}")


def sense_examples(gp):
    for s in gp.get("senses") or []:
        if isinstance(s, dict):
            for e in s.get("examples") or []:
                if isinstance(e, dict) and e.get("ja"):
                    yield e["ja"]


def validate_base(files):
    errors, points = [], {}
    for path in files:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{name}: JSON 解析失败: {e}")
            continue
        for gp in data:
            gid = gp.get("id", "<无 id>")
            where = f"{name}:{gid}"
            check_point(gp, where, errors)
            check_quotes(all_strings(gp), where, errors)
            if gid in points:
                errors.append(f"{where}: id 重复")
            points[gid] = (where, gp)

    known = set(points)
    catalog = os.path.join(ROOT, "tools", "grammar_catalog.json")
    if os.path.exists(catalog):
        with open(catalog, encoding="utf-8") as f:
            known |= {it["id"] for it in json.load(f)}
    for gid, (where, gp) in points.items():
        if "scannable" in gp and not isinstance(gp["scannable"], bool):
            errors.append(f"{where}: scannable 必须是 true/false")
        for s in gp.get("similar") or []:
            sid = s.get("id") if isinstance(s, dict) else None
            if not sid:
                errors.append(f"{where}: similar「{s.get('title') if isinstance(s, dict) else s}」缺少 id（相近语法必须是语法库中已收录的语法点）")
            elif sid not in points:
                errors.append(f"{where}: similar 引用了不存在的 id {sid}")
            elif sid == gid:
                errors.append(f"{where}: similar 不能引用自己")
        for sid in gp.get("subsumes") or []:
            if sid not in known:
                errors.append(f"{where}: subsumes 引用了不存在的 id {sid}")
        compiled = []
        for p in gp.get("patterns") or []:
            for bad in FORBIDDEN_REGEX:
                if re.search(bad, p):
                    errors.append(f"{where}: pattern 使用了不兼容 ICU 的语法: {p}")
            try:
                compiled.append(re.compile(p))
            except re.error as e:
                errors.append(f"{where}: pattern 无法编译 {p!r}: {e}")
        if not compiled:
            continue
        for ja in sense_examples(gp):
            if not any(c.search(ja) for c in compiled):
                errors.append(f"{where}: 义项例句未被 patterns 命中: {ja}")
        for neg in gp.get("negativeExamples") or []:
            hit = next((c.pattern for c in compiled if c.search(neg)), None)
            if hit:
                errors.append(f"{where}: 反例被误命中 ({hit}): {neg}")
    return errors, points


def same_len(a, b):
    return isinstance(a, list) and isinstance(b, list) and len(a) == len(b)


def validate_l10n(base_files):
    errors = []
    l10n_dir = os.path.join(GRAMMAR_DIR, "l10n")
    for base_path in base_files:
        level = os.path.basename(base_path)[len("grammar_"):-len(".json")]
        with open(base_path, encoding="utf-8") as f:
            base = json.load(f)
        for lang in L10N_LANGS:
            path = os.path.join(l10n_dir, f"l10n_{lang}_{level}.json")
            name = os.path.basename(path)
            if not os.path.exists(path):
                errors.append(f"{name}: 缺少翻译文件")
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    tr = json.load(f)
            except Exception as e:  # noqa: BLE001
                errors.append(f"{name}: JSON 解析失败: {e}")
                continue
            if [t.get("id") for t in tr] != [b["id"] for b in base]:
                errors.append(f"{name}: id 列表/顺序与基础文件不一致")
                continue
            for b, t in zip(base, tr):
                w = f"{name}:{b['id']}"
                texts = []
                for k in ["meaning", "connection", "etymology", "formation"]:
                    if not is_str(t.get(k)):
                        errors.append(f"{w}: 缺少 {k}")
                    texts.append(t.get(k, ""))
                if not same_len(t.get("senses"), b.get("senses")):
                    errors.append(f"{w}: senses 数量应为 {len(b.get('senses') or [])}")
                else:
                    for bs, ts in zip(b["senses"], t["senses"]):
                        if not all(is_str(ts.get(k)) for k in ["label", "meaning", "connection"]):
                            errors.append(f"{w}: senses 缺少 label/meaning/connection")
                        if not same_len(ts.get("examples"), bs["examples"]) or not all(is_str(x) for x in ts.get("examples") or []):
                            errors.append(f"{w}: senses.examples 应为 {len(bs['examples'])} 条译文字符串")
                        texts += [ts.get("label", ""), ts.get("meaning", ""), ts.get("connection", "")] + list(ts.get("examples") or [])
                if not same_len(t.get("notes", []), b.get("notes", [])):
                    errors.append(f"{w}: notes 数量应为 {len(b.get('notes', []))}")
                texts += [x for x in t.get("notes", []) if isinstance(x, str)]
                tsc, bsc = t.get("scenes") or {}, b.get("scenes") or {}
                for key in ["daily", "work"]:
                    if not same_len(tsc.get(key), bsc.get(key)):
                        errors.append(f"{w}: scenes.{key} 数量应为 {len(bsc.get(key) or [])}")
                        continue
                    for sc in tsc[key]:
                        if not (isinstance(sc, dict) and all(is_str(sc.get(k)) for k in ["title", "description", "example"])):
                            errors.append(f"{w}: scenes.{key} 需要 title/description/example(译文字符串)")
                        else:
                            texts += [sc["title"], sc["description"], sc["example"]]
                if not same_len(t.get("similar"), b.get("similar")):
                    errors.append(f"{w}: similar 数量应为 {len(b.get('similar') or [])}")
                else:
                    for s in t["similar"]:
                        if not (isinstance(s, dict) and is_str(s.get("title")) and is_str(s.get("explanation"))):
                            errors.append(f"{w}: similar 需要 title/explanation")
                        else:
                            texts += [s["title"], s["explanation"]]
                if lang != "zh-Hant":
                    bad = sorted({c for txt in texts for c in str(txt) if c in CHINESE_ONLY})
                    if bad:
                        errors.append(f"{w}: 译文残留中文字符 {''.join(bad)}")
    return errors


def main() -> int:
    files = sorted(glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json")))
    if not files:
        print("没有找到语法资源文件")
        return 1
    errors, points = validate_base(files)
    freq_path = os.path.join(GRAMMAR_DIR, "frequency.json")
    if os.path.exists(freq_path):
        with open(freq_path, encoding="utf-8") as f:
            freq = json.load(f)
        for gid in points:
            if freq.get(gid) not in ("high", "medium", "low"):
                errors.append(f"frequency.json: 缺少 {gid} 的出题频率")
    if "--base-only" not in sys.argv:
        errors += validate_l10n(files)
    if "--only" in sys.argv:
        frag = sys.argv[sys.argv.index("--only") + 1]
        errors = [e for e in errors if frag in e.split(":")[0]]
    print(f"共 {len(points)} 个语法点, {len(files)} 个文件")
    if errors:
        print(f"发现 {len(errors)} 个问题:")
        for e in errors:
            print("  - " + e)
        return 1
    print("全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
