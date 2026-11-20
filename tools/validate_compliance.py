#!/usr/bin/env python3
"""硬门槛：隐私政策、开源许可要和最新的代码一致，对不上 CI 就不通过。

隐私政策（JapaneseGrammarScanner/Services/LegalContent.swift）
  * 扫描 App 代码里 import 的框架、Info.plist 权限、iCloud（CloudKit）上报的每个字段、本机存储、打开的网址，
    和 tools/compliance/privacy_inventory.json 逐项核对：代码里有、清单里没有 → 不通过；清单里有、代码里已经没有 → 不通过
  * 清单里每一项要求出现的词（mentions / 字段说明）必须写在 LegalContent 对应的小节里
  * 清单的指纹必须等于 LegalContent.privacyInventoryHash：清单变了，政策和「最后更新」必须一起改
  * 网站上的隐私政策（docs/index.html 中 privacy:begin … privacy:end）必须和 LegalContent 生成的一致
开源许可（JapaneseGrammarScanner/Resources/Legal/third_party.json，App 的「开源许可」页直接读取）
  * 扫描 Swift 包（Package.resolved）、tools/ 里 import 的第三方 Python 包、用到的字体，
    每个都要在 third_party.json（进 App，要署名）或 tools/compliance/dev_only.json（只在开发时用）里
  * 列着、但项目里已经不用的组件 → 不通过

用法：python3 tools/validate_compliance.py              校验
      python3 tools/validate_compliance.py --write-web  按 LegalContent 重新生成网站上的隐私政策
      python3 tools/validate_compliance.py --hash       打印清单指纹（更新清单后填进 LegalContent.privacyInventoryHash）
"""
import glob
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "JapaneseGrammarScanner")
INVENTORY = os.path.join(ROOT, "tools", "compliance", "privacy_inventory.json")
DEV_ONLY = os.path.join(ROOT, "tools", "compliance", "dev_only.json")
THIRD_PARTY = os.path.join(APP, "Resources", "Legal", "third_party.json")
LEGAL = os.path.join(APP, "Services", "LegalContent.swift")
WEB = os.path.join(ROOT, "docs", "index.html")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def swift_files():
    return sorted(glob.glob(os.path.join(APP, "**", "*.swift"), recursive=True))


def inventory_hash(inv):
    data = {k: v for k, v in inv.items() if not k.startswith("_")}
    return hashlib.sha256(json.dumps(data, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:12]


# MARK: 从代码里找出实际用到的东西

def detect_app():
    frameworks, records, local, hosts = set(), {}, False, set()
    for f in swift_files():
        src = read(f)
        for m in re.finditer(r"^\s*import\s+([A-Za-z_]\w*)", src, re.M):
            frameworks.add(m.group(1))
        if re.search(r"\bUserDefaults\b|\bFileManager\b", src):
            local = True
        for m in re.finditer(r'URL\(string:\s*"https?://([^/"]+)', src):
            hosts.add(m.group(1))
        types = set(re.findall(r'recordType(?::|\s*=)\s*"(\w+)"', src))
        fields = set(re.findall(r'\b\w+\["(\w+)"\]\s*=', src))
        if types and fields:
            if len(types) > 1:
                raise SystemExit(f"{os.path.relpath(f, ROOT)}：一个文件里有多种 CloudKit 记录，请拆开（校验脚本按文件对应字段）")
            records.setdefault(types.pop(), set()).update(fields)
    perms = set(re.findall(r"INFOPLIST_KEY_(NS\w+UsageDescription)", read(os.path.join(ROOT, "JapaneseGrammarScanner.xcodeproj", "project.pbxproj"))))
    for plist in glob.glob(os.path.join(APP, "**", "Info.plist"), recursive=True):
        perms |= set(re.findall(r"<key>(NS\w+UsageDescription)</key>", read(plist)))
    return frameworks, records, local, hosts, perms


def legal_sections():
    """解析 LegalContent.swift 里隐私政策的各小节：id → (title, body, when)"""
    src = read(LEGAL)
    start = src.index("static let privacyAll")
    end = src.index("]", src.index("Section(id: \"contact\"", start))
    sections = {}
    for m in re.finditer(r'Section\(id:\s*"([\w-]+)",\s*title:\s*"([^"]*)",\s*body:\s*"([^"]*)"(?:,\s*when:\s*\.(\w+))?',
                         src[start:end + 1]):
        sections[m.group(1)] = (m.group(2), m.group(3), m.group(4) or "always")
    updated = re.search(r'privacyUpdated\s*=\s*"([^"]+)"', src).group(1)
    h = re.search(r'privacyInventoryHash\s*=\s*"([^"]+)"', src).group(1)
    return sections, updated, h


# MARK: 网站上的隐私政策

def web_html(sections, updated, payments):
    labels = {"cloud": "", "noCloud": "（App 内提交未开启时）", "payments": ""}
    out = [f"<small>最后更新：{updated}</small>", "<ul>"]
    for sid, (title, body, when) in sections.items():
        if when == "payments" and not payments:
            continue
        out.append(f'<li id="privacy-{sid}"><b>{title}{labels.get(when, "")}</b>：{body}</li>')
    out.append("</ul>")
    return "\n".join(out)


def payments_enabled():
    m = re.search(r"paymentsEnabled\s*=\s*(true|false)", read(os.path.join(APP, "App", "AppLinks.swift")))
    return bool(m and m.group(1) == "true")


def main():
    errors = []
    inv = json.loads(read(INVENTORY))
    if "--hash" in sys.argv:
        print(inventory_hash(inv))
        return 0
    frameworks, records, local, hosts, perms = detect_app()
    sections, updated, recorded_hash = legal_sections()

    def need(section_ids, mentions, what):
        for sid in section_ids:
            if sid not in sections:
                errors.append(f"隐私政策缺少「{sid}」小节（{what}）")
                continue
            body = sections[sid][1]
            for word in mentions:
                if word not in body:
                    errors.append(f"隐私政策「{sections[sid][0]}」没有写到「{word}」（{what}）")

    def ids(entry):
        return entry.get("sections") or [entry["section"]]

    # 框架
    known = inv["frameworks"]
    for fw in sorted(frameworks - set(known)):
        errors.append(f"代码 import 了 {fw}，privacy_inventory.json 里没有登记（和隐私无关就登记为 null）")
    for fw in sorted(set(known) - frameworks):
        errors.append(f"privacy_inventory.json 登记了 {fw}，代码里已经不用了，请删掉并检查隐私政策")
    for fw, entry in known.items():
        if entry and fw in frameworks:
            need(ids(entry), entry.get("mentions", []), f"用了 {fw}")
    # 权限
    for p in sorted(perms - set(inv["permissions"])):
        errors.append(f"App 申请了权限 {p}，privacy_inventory.json 里没有登记")
    for p in sorted(set(inv["permissions"]) - perms):
        errors.append(f"privacy_inventory.json 登记了权限 {p}，App 已经不申请了")
    for p, entry in inv["permissions"].items():
        need(ids(entry), entry.get("mentions", []), f"权限 {p}")
    # 本机存储
    if local:
        need(ids(inv["local_storage"]), inv["local_storage"]["mentions"], "本机存储")
    # iCloud 上报字段
    known_records = inv["cloudkit_records"]
    for rtype in sorted(set(records) - set(known_records)):
        errors.append(f"代码往 iCloud 写 {rtype} 记录，privacy_inventory.json 里没有登记")
    for rtype in sorted(set(known_records) - set(records)):
        errors.append(f"privacy_inventory.json 登记了 {rtype} 记录，代码里已经不写了")
    for rtype, entry in known_records.items():
        found = records.get(rtype, set())
        for f in sorted(found - set(entry["fields"])):
            errors.append(f"{rtype} 新上报了字段 {f}，privacy_inventory.json 里没有登记，隐私政策也要写上")
        for f in sorted(set(entry["fields"]) - found):
            errors.append(f"privacy_inventory.json 里 {rtype}.{f} 代码已经不上报了，请删掉并改隐私政策")
        need(ids(entry), sorted(set(entry["fields"].values())), f"{rtype} 上报的字段")
    # 网址
    for h in sorted(hosts - set(inv["web_hosts"])):
        errors.append(f"代码里打开了 {h}，privacy_inventory.json 的 web_hosts 里没有登记")
    for h in sorted(set(inv["web_hosts"]) - hosts):
        errors.append(f"privacy_inventory.json 登记了网址 {h}，代码里已经没有了")
    # 指纹：清单变了，政策和日期要一起改
    if recorded_hash != inventory_hash(inv):
        errors.append(f"privacy_inventory.json 变了：请同步修改隐私政策，更新 LegalContent.privacyUpdated，"
                      f"并把 privacyInventoryHash 改成 {inventory_hash(inv)}")
    # 网站
    html = read(WEB)
    generated = web_html(sections, updated, payments_enabled())
    m = re.search(r"<!-- privacy:begin -->\n(.*?)<!-- privacy:end -->", html, re.S)
    generated += "\n"
    if "--write-web" in sys.argv:
        if not m:
            raise SystemExit("docs/index.html 里没有 <!-- privacy:begin --> … <!-- privacy:end --> 标记")
        html = html[:m.start(1)] + generated + html[m.end(1):]
        with open(WEB, "w", encoding="utf-8") as fh:
            fh.write(html)
        print("已重新生成 docs/index.html 的隐私政策")
    elif not m or m.group(1) != generated:
        errors.append("网站上的隐私政策（docs/index.html）和 App 里的不一致：运行 python3 tools/validate_compliance.py --write-web")

    # 开源许可
    tp = json.loads(read(THIRD_PARTY))["components"]
    dev = json.loads(read(DEV_ONLY))
    used = set()
    stdlib = set(sys.stdlib_module_names)
    local_modules = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(ROOT, "tools", "**", "*.py"), recursive=True)}
    for f in glob.glob(os.path.join(ROOT, "tools", "**", "*.py"), recursive=True):
        src = read(f)
        for m2 in re.finditer(r"^\s*(?:import|from)\s+([A-Za-z_]\w*)", src, re.M):
            mod = m2.group(1)
            if mod not in stdlib and mod not in local_modules:
                used.add(f"python:{mod}")
        for m2 in re.finditer(r"([A-Za-z][\w%\[\]-]*?)(?:%5B[^.]*%5D|\[[^\].]*\])?\.(?:ttf|otf|ttc)\b", src):
            used.add(f"font:{m2.group(1)}")
    for resolved in glob.glob(os.path.join(ROOT, "**", "Package.resolved"), recursive=True):
        if "/build/" in resolved:
            continue
        for pin in json.loads(read(resolved)).get("pins", []):
            used.add(f"spm:{pin.get('identity')}")
    covered = {d for c in tp for d in c["detect"]} | {f"python:{k}" for k in dev.get("python", {})} | \
              {f"spm:{k}" for k in dev.get("spm", {})} | {f"font:{k}" for k in dev.get("font", {})}
    for u in sorted(used - covered):
        errors.append(f"项目用到了第三方组件 {u}：进 App 的写进 Resources/Legal/third_party.json（开源许可页署名），"
                      f"只在开发时用的写进 tools/compliance/dev_only.json")
    for c in tp:
        if not any(d in used for d in c["detect"]):
            errors.append(f"开源许可里列着 {c['name']}，项目里已经不用了，请删掉")
    for k in dev.get("python", {}):
        if f"python:{k}" not in used:
            errors.append(f"dev_only.json 里列着 {k}，项目里已经不用了，请删掉")

    print(f"隐私政策：{len(sections)} 节，清单 {len(known)} 个框架、{sum(len(e['fields']) for e in known_records.values())} 个上报字段；"
          f"开源许可：{len(tp)} 个组件")
    if errors:
        print(f"发现 {len(errors)} 个问题:")
        for e in errors:
            print("  - " + e)
        return 1
    print("全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
