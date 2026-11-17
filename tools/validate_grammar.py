#!/usr/bin/env python3
"""校验 App 内置的语法静态资源 (JapaneseGrammarScanner/Resources/Grammar/grammar_*.json)。

检查项:
  * 必填字段齐全、类型正确
  * id 全局唯一
  * similar[].id / subsumes 引用的 id 必须存在
  * patterns 正则可编译, 且只使用 ICU(NSRegularExpression) 与 Python 共同支持的语法
  * 每个例句至少被本语法点的一个 pattern 命中 (保证扫描时真的能识别出来)
  * negativeExamples (可选) 中的句子不能被本语法点命中

用法: python3 tools/validate_grammar.py
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")

LEVELS = {"N5", "N4", "N3", "N2", "N1"}
REQUIRED_STR = ["id", "title", "level", "meaning", "connection", "etymology"]
REQUIRED_LIST_STR = ["usage", "scenarios", "patterns"]
FORBIDDEN_REGEX = [r"\(\?P", r"\\A", r"\\Z", r"\(\?#"]


def main() -> int:
    files = sorted(glob.glob(os.path.join(GRAMMAR_DIR, "grammar_*.json")))
    if not files:
        print("没有找到语法资源文件")
        return 1

    errors = []
    points = {}
    for path in files:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{name}: JSON 解析失败: {e}")
            continue
        if not isinstance(data, list):
            errors.append(f"{name}: 顶层必须是数组")
            continue
        for gp in data:
            gid = gp.get("id", "<无 id>")
            where = f"{name}:{gid}"
            for k in REQUIRED_STR:
                if not isinstance(gp.get(k), str) or not gp[k].strip():
                    errors.append(f"{where}: 缺少字符串字段 {k}")
            for k in REQUIRED_LIST_STR:
                v = gp.get(k)
                if not isinstance(v, list) or not v or not all(isinstance(x, str) and x for x in v):
                    errors.append(f"{where}: {k} 必须是非空字符串数组")
            if gp.get("level") not in LEVELS:
                errors.append(f"{where}: level 非法 {gp.get('level')}")
            ex = gp.get("examples")
            if not isinstance(ex, list) or len(ex) < 2:
                errors.append(f"{where}: examples 至少 2 条")
                ex = []
            for e in ex:
                if not isinstance(e, dict) or not e.get("ja") or not e.get("zh"):
                    errors.append(f"{where}: example 需要 ja/zh 字段: {e}")
            sim = gp.get("similar")
            if not isinstance(sim, list) or not sim:
                errors.append(f"{where}: similar 至少 1 条")
                sim = []
            for s in sim:
                if not isinstance(s, dict) or not s.get("title") or not s.get("explanation"):
                    errors.append(f"{where}: similar 需要 title/explanation 字段: {s}")
            if gid in points:
                errors.append(f"{where}: id 重复")
            points[gid] = (where, gp)

    for gid, (where, gp) in points.items():
        for s in gp.get("similar", []) or []:
            sid = s.get("id") if isinstance(s, dict) else None
            if sid and sid not in points:
                errors.append(f"{where}: similar 引用了不存在的 id {sid}")
        for sid in gp.get("subsumes", []) or []:
            if sid not in points:
                errors.append(f"{where}: subsumes 引用了不存在的 id {sid}")

        compiled = []
        for p in gp.get("patterns", []) or []:
            for bad in FORBIDDEN_REGEX:
                if re.search(bad, p):
                    errors.append(f"{where}: pattern 使用了不兼容 ICU 的语法: {p}")
            try:
                compiled.append(re.compile(p))
            except re.error as e:
                errors.append(f"{where}: pattern 无法编译 {p!r}: {e}")
        if not compiled:
            continue
        for e in gp.get("examples", []) or []:
            ja = e.get("ja", "") if isinstance(e, dict) else ""
            if ja and not any(c.search(ja) for c in compiled):
                errors.append(f"{where}: 例句未被 patterns 命中: {ja}")
        for neg in gp.get("negativeExamples", []) or []:
            hit = next((c.pattern for c in compiled if c.search(neg)), None)
            if hit:
                errors.append(f"{where}: 反例被误命中 ({hit}): {neg}")

    errors += validate_l10n(files)

    print(f"共 {len(points)} 个语法点, {len(files)} 个文件")
    if errors:
        print(f"发现 {len(errors)} 个问题:")
        for e in errors:
            print("  - " + e)
        return 1
    print("全部通过 ✅")
    return 0


# 只出现在简体/繁体中文、不会出现在日语里的常用字，用于检查译文是否残留中文
# 只出现在中文、在日语中不使用的字（简体字及与日语新字体不同的繁体字），用于检查译文是否残留中文。
# 注意不要加入日语也使用的汉字（語、過、進、為、個、義、種、詞、従 等）。
CHINESE_ONLY = set("这们吗么说时为个词动语义过还没让对该种样从进這們嗎麼說對該讓樣")
L10N_LANGS = ["en", "ko", "es", "vi", "zh-Hant"]


def validate_l10n(base_files):
    """校验 l10n/l10n_<lang>_<level>.json 翻译文件与基础文件结构一致。"""
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
                errors.append(f"{name}: id 列表/顺序与 {os.path.basename(base_path)} 不一致")
                continue
            for b, t in zip(base, tr):
                where = f"{name}:{b['id']}"
                for k in ["meaning", "connection", "etymology"]:
                    if not isinstance(t.get(k), str) or not t[k].strip():
                        errors.append(f"{where}: 缺少 {k}")
                for k in ["usage", "scenarios"]:
                    v = t.get(k)
                    if not isinstance(v, list) or len(v) != len(b[k]) or not all(isinstance(x, str) and x.strip() for x in v):
                        errors.append(f"{where}: {k} 条数应为 {len(b[k])}")
                ex = t.get("examples")
                if not isinstance(ex, list) or len(ex) != len(b["examples"]) or not all(isinstance(x, str) and x.strip() for x in ex):
                    errors.append(f"{where}: examples 应为 {len(b['examples'])} 条译文字符串")
                sim = t.get("similar")
                if not isinstance(sim, list) or len(sim) != len(b["similar"]):
                    errors.append(f"{where}: similar 条数应为 {len(b['similar'])}")
                else:
                    for s_ in sim:
                        if not isinstance(s_, dict) or not s_.get("title") or not s_.get("explanation"):
                            errors.append(f"{where}: similar 需要 title/explanation")
                if lang != "zh-Hant":
                    texts = [t.get("meaning", ""), t.get("connection", ""), t.get("etymology", "")]
                    texts += (t.get("usage") or []) + (t.get("scenarios") or []) + [x for x in (ex or []) if isinstance(x, str)]
                    texts += [s_.get("explanation", "") + s_.get("title", "") for s_ in (sim or []) if isinstance(s_, dict)]
                    bad = sorted({c for txt in texts for c in str(txt) if c in CHINESE_ONLY})
                    if bad:
                        errors.append(f"{where}: 译文残留中文字符 {''.join(bad)}")
    return errors


if __name__ == "__main__":
    sys.exit(main())
