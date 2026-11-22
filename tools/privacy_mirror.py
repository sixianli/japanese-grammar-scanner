#!/usr/bin/env python3
import argparse
import html
import importlib.util
import json
import os
import re
import subprocess
import sys
import types
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from validate_compliance import legal_sections, payments_enabled  # noqa: E402

SITE = "https://sinimite.work"
PAGE_PATH = "/works/grammar-scanner/privacy/"
LANGS = {"zh": "", "en": "/en", "ja": "/ja"}
FILES = {"zh": "grammar-scanner-privacy.md", "en": "grammar-scanner-privacy.en.md", "ja": "grammar-scanner-privacy.ja.md"}
JA_FILE = os.path.join(ROOT, "tools", "compliance", "privacy_ja.json")
UPDATED_LABEL = {"zh": "最后更新：", "en": "Last updated: ", "ja": "最終更新："}
TITLE_SEP = {"zh": "：", "en": ": ", "ja": "："}
TRANSLATION_KEY = "works-grammar-scanner-privacy"
BEGIN, END = "<!-- privacy:begin -->", "<!-- privacy:end -->"


def english_strings():
    sys.modules.setdefault("opencc", types.SimpleNamespace(OpenCC=lambda *_: None))
    spec = importlib.util.spec_from_file_location("make_strings", os.path.join(ROOT, "tools", "make_strings.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return {k: v[0] for k, v in mod.S.items()}


def japanese_strings():
    with open(JA_FILE, encoding="utf-8") as f:
        return json.load(f)


def active(when, cloud, payments):
    return {"always": True, "cloud": cloud, "noCloud": not cloud, "payments": payments}[when]


def sections(lang, cloud, payments, en=None, ja=None):
    found, updated, _ = legal_sections()
    out = []
    for sid, (title, body, when) in found.items():
        if not active(when, cloud, payments):
            continue
        if lang == "zh":
            out.append((sid, title, body))
        elif lang == "en":
            out.append((sid, en[title], en[body]))
        else:
            out.append((sid, ja[sid]["title"], ja[sid]["body"]))
    return out, updated


def render(lang, cloud, payments, en=None, ja=None):
    items, updated = sections(lang, cloud, payments, en, ja)
    lines = [BEGIN, f'<p class="privacy-updated">{UPDATED_LABEL[lang]}{updated}</p>', '<ul class="privacy-list">']
    for sid, title, body in items:
        lines.append(f'<li id="privacy-{sid}"><b>{html.escape(title, quote=False)}</b>{TITLE_SEP[lang]}{html.escape(body, quote=False)}</li>')
    lines += ["</ul>", END]
    return "\n".join(lines)


def expected(lang, cloud, payments, en, ja):
    items, updated = sections(lang, cloud, payments, en, ja)
    return updated, {sid: normalize(f"{title}{TITLE_SEP[lang]}{body}") for sid, title, body in items}


def normalize(text):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", text))).strip()


def parse_page(page):
    m = re.search(r"privacy-updated[^>]*>(.*?)</p>", page, re.S)
    updated = normalize(m.group(1)) if m else None
    items = {sid: normalize(body) for sid, body in re.findall(r'<li id="?privacy-([\w-]+)"?[^>]*>(.*?)</li>', page, re.S)}
    return updated, items


def compare(lang, page, cloud, payments, en, ja):
    updated, want = expected(lang, cloud, payments, en, ja)
    got_updated, got = parse_page(page)
    problems = []
    if got_updated is None or not got_updated.endswith(updated):
        problems.append(f"{lang}：最后更新日期应为 {updated}，网页上是 {got_updated}")
    for sid in want.keys() - got.keys():
        problems.append(f"{lang}：网页上缺少「{sid}」这一节")
    for sid in got.keys() - want.keys():
        problems.append(f"{lang}：网页上多了「{sid}」这一节，App 里没有")
    for sid in want.keys() & got.keys():
        if want[sid] != got[sid]:
            problems.append(f"{lang}：「{sid}」和 App 里不一致\n    App： {want[sid]}\n    网页：{got[sid]}")
    return problems


def check_translations(en, ja):
    found, _, _ = legal_sections()
    problems = []
    for sid, (title, body, _) in found.items():
        for zh in (title, body):
            if zh not in en:
                problems.append(f"「{sid}」没有英文译文（tools/make_strings.py）：{zh}")
        entry = ja.get(sid)
        if entry is None:
            problems.append(f"「{sid}」没有日文译文（{os.path.relpath(JA_FILE, ROOT)}）")
        elif entry.get("source_title") != title or entry.get("source_body") != body:
            problems.append(f"「{sid}」的中文改过了，日文译文还是按旧原文翻的：更新 {os.path.relpath(JA_FILE, ROOT)} 里的 source_title / source_body 和译文")
    for sid in ja.keys() - found.keys():
        problems.append(f"{os.path.relpath(JA_FILE, ROOT)} 里的「{sid}」在 App 的隐私政策里已经没有了，删掉")
    return problems


def write_siblog(directory, cloud, payments, en, ja):
    for lang, name in FILES.items():
        path = os.path.join(directory, "content", "works", name)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if BEGIN not in text or END not in text:
            raise SystemExit(f"{path} 里没有 {BEGIN} … {END} 标记")
        start, stop = text.index(BEGIN), text.index(END) + len(END)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text[:start] + render(lang, cloud, payments, en, ja) + text[stop:])
        print(f"已更新 {path}")
    record_translation_hash(directory)


def record_translation_hash(directory):
    out = subprocess.run([sys.executable, "scripts/check_multilingual_content.py", "--print-source-hashes"],
                         cwd=directory, capture_output=True, text=True, check=True).stdout
    source_hash = dict(line.split("\t", 1) for line in out.splitlines() if "\t" in line)[TRANSLATION_KEY].strip()
    for lang in ("en", "ja"):
        path = os.path.join(directory, "content", "works", FILES[lang])
        with open(path, encoding="utf-8") as f:
            text = f.read()
        text = re.sub(r'^translationReviewed = .*\n', "", text, flags=re.M)
        text = re.sub(r'^translationSourceHash = .*\n', "", text, flags=re.M)
        text = text.replace(f'translationKey = "{TRANSLATION_KEY}"\n',
                            f'translationKey = "{TRANSLATION_KEY}"\ntranslationReviewed = true\ntranslationSourceHash = "{source_hash}"\n', 1)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    print(f"英文、日文页面已记录中文原文指纹 {source_hash}（译文来自 App 的英文翻译和 tools/compliance/privacy_ja.json）")


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "privacy-mirror-check"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def main():
    ap = argparse.ArgumentParser(description="App 主页（SiBlog）上的隐私政策必须和 App 里的一致")
    ap.add_argument("--check", action="store_true", help="每一节都有英文、日文译文，且日文译文对应当前中文原文")
    ap.add_argument("--write-siblog", metavar="SIBLOG_DIR", help="按 App 重写博客里中英日三种语言的隐私政策")
    ap.add_argument("--check-live", action="store_true", help="打开线上三种语言的隐私政策页，和 App 逐节对比，对不上就失败")
    ap.add_argument("--cloud", default="true", choices=["true", "false"], help="这次发版是否打开 iCloud 上报（CLOUD_FEEDBACK）")
    args = ap.parse_args()
    cloud = args.cloud == "true"
    payments = payments_enabled()
    en, ja = english_strings(), japanese_strings()

    problems = check_translations(en, ja)
    if problems:
        print("隐私政策译文有问题：\n  - " + "\n  - ".join(problems))
        return 1
    if args.write_siblog:
        write_siblog(args.write_siblog, cloud, payments, en, ja)
    if args.check_live:
        for lang, prefix in LANGS.items():
            url = SITE + prefix + PAGE_PATH
            try:
                page = fetch(url)
            except Exception as e:
                problems.append(f"{lang}：打不开 {url}（{e}）")
                continue
            problems += compare(lang, page, cloud, payments, en, ja)
        if problems:
            print("App 主页上的隐私政策和 App 里的不一致，不能发版。按 App 重新生成博客里的政策：\n"
                  "  python3 tools/privacy_mirror.py --write-siblog <SiBlog 目录>，合并到 SiBlog 的 main 并等部署完成。\n  - "
                  + "\n  - ".join(problems))
            return 1
        print(f"App 主页上的隐私政策（{SITE}{PAGE_PATH}，中英日）和 App 里的一致 ✅")
    elif not args.write_siblog:
        print("隐私政策的英文、日文译文齐全，且对应当前中文原文 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
