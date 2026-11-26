#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LISTING_DIR = os.path.join(ROOT, "docs", "appstore", "listing")
SCREENSHOT_DIR = os.path.join(ROOT, "docs", "appstore", "screenshots")
API = "https://api.appstoreconnect.apple.com/v1"

REQUIRED_LOCALES = {"zh-Hans", "zh-Hant", "en-US", "en-GB", "ko", "es-MX", "es-ES", "vi"}
DISPLAY_TYPE = "APP_IPHONE_61"
SCREENSHOT_SIZES = {(1206, 2622), (1179, 2556)}
LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "keywords": 100, "description": 4000}
APP_INFO_FIELDS = ("name", "subtitle", "privacyPolicyUrl")
VERSION_FIELDS = ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")
REFUSED_SCRIPTS = {"缅甸文": ((0x1000, 0x109F), (0xA9E0, 0xA9FF), (0xAA60, 0xAA7F))}
EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


def load_listings(directory=LISTING_DIR):
    listings = {}
    for name in sorted(os.listdir(directory)):
        if name.endswith(".json"):
            with open(os.path.join(directory, name), encoding="utf-8") as f:
                listings[name[:-5]] = json.load(f)
    return listings


def screenshot_files(listing, directory=SCREENSHOT_DIR):
    folder = os.path.join(directory, listing["screenshots"])
    if not os.path.isdir(folder):
        return []
    return [os.path.join(folder, n) for n in sorted(os.listdir(folder)) if n.lower().endswith(".png")]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def keyword_repeats(listing):
    title = f"{listing['name']} {listing['subtitle']}".lower()
    return [k for k in (w.strip() for w in listing["keywords"].split(",")) if k and k.lower() in title]


def refused_script(text):
    for script, ranges in REFUSED_SCRIPTS.items():
        if any(lo <= ord(ch) <= hi for ch in text for lo, hi in ranges):
            return script
    return None


def check(listings, screenshot_dir=SCREENSHOT_DIR):
    problems = []
    for locale in sorted(REQUIRED_LOCALES - listings.keys()):
        problems.append(f"缺少 {locale} 的商店文案（docs/appstore/listing/{locale}.json）")
    for locale, listing in sorted(listings.items()):
        empty = [f for f in APP_INFO_FIELDS + VERSION_FIELDS + ("screenshots",) if not str(listing.get(f, "")).strip()]
        if empty:
            problems.append(f"{locale}：{', '.join(empty)} 是空的")
            continue
        for field, limit in LIMITS.items():
            if len(listing[field]) > limit:
                problems.append(f"{locale}：{field} 有 {len(listing[field])} 个字符，超过 App Store 的上限 {limit}")
        for field in APP_INFO_FIELDS + VERSION_FIELDS:
            script = refused_script(listing[field])
            if script:
                problems.append(f"{locale}：{field} 里有{script}，App Store Connect 不收这种文字，改用拉丁字母写")
        for field in ("privacyPolicyUrl", "supportUrl", "marketingUrl"):
            if not listing[field].startswith("https://"):
                problems.append(f"{locale}：{field} 必须是 https 网址")
        for word in keyword_repeats(listing):
            problems.append(f"{locale}：关键词「{word}」已经在名称或副标题里，重复不增加搜索权重，删掉")
        files = screenshot_files(listing, screenshot_dir)
        if not 1 <= len(files) <= 10:
            problems.append(f"{locale}：截图要 1 到 10 张，现在 {len(files)} 张（docs/appstore/screenshots/{listing['screenshots']}/）")
        for path in files:
            size = png_size(path)
            if size not in SCREENSHOT_SIZES:
                problems.append(f"{locale}：{os.path.relpath(path, ROOT)} 是 {size}，"
                                f"「iPhone with Dynamic Island (medium display)」只收 1206×2622 或 1179×2556")
    return problems


def md5(path):
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()


class Api:
    def __init__(self):
        import jwt
        now = int(time.time())
        self._token = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
            os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})

    def call(self, method, path, body=None):
        req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": "Bearer " + self._token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
                return json.loads(data) if data else {}
        except urllib.error.HTTPError as e:
            raise SystemExit(f"App Store Connect 返回 HTTP {e.code}（{method} {path.split('?')[0]}）：{e.read().decode()[:800]}")

    def put_part(self, operation, data):
        headers = {h["name"]: h["value"] for h in operation.get("requestHeaders", [])}
        req = urllib.request.Request(operation["url"], method=operation["method"], data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=120):
            pass


def attrs(resource):
    return resource.get("attributes", {})


def find_app(api, bundle_id):
    data = api.call("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id}))["data"]
    if not data:
        raise SystemExit(f"App Store Connect 里找不到 Bundle ID 为 {bundle_id} 的 App")
    return data[0]


LIVE_INFO_STATES = ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE")


def find_version(api, app_id, version, apply, log):
    q = urllib.parse.urlencode({"filter[platform]": "IOS", "filter[versionString]": version, "limit": "5"})
    data = api.call("GET", f"/apps/{app_id}/appStoreVersions?{q}")["data"]
    if not data:
        raise SystemExit(f"App Store Connect 里还没有 iOS {version} 这个版本，先在网页上建好")
    v = data[0]
    state = attrs(v).get("appVersionState") or attrs(v).get("appStoreState")
    if state not in EDITABLE_STATES:
        if apply:
            raise SystemExit(f"iOS {version} 现在的状态是 {state}，不能再改商店信息")
        log(f"iOS {version} 现在的状态是 {state}，不能写入；下面只和这个版本线上的文案做对比")
    return v


def find_app_info(api, app_id, apply, log):
    infos = api.call("GET", f"/apps/{app_id}/appInfos")["data"]
    states = [(info, attrs(info).get("state") or attrs(info).get("appStoreState")) for info in infos]
    for info, state in states:
        if state not in LIVE_INFO_STATES + ("REPLACED_WITH_NEW_INFO",):
            return info
    live = [info for info, state in states if state in LIVE_INFO_STATES]
    if apply or not live:
        raise SystemExit("找不到可以编辑的 App 信息（appInfo），可能当前没有待提交的版本")
    log("当前没有待提交的版本，App 信息（名称、副标题）只和线上的做对比，不能写入")
    return live[0]


def changed_fields(current, wanted, fields):
    return {f: wanted[f] for f in fields if (current or {}).get(f) != wanted[f]}


def sync_localization(api, kind, parent_type, parent_id, existing, locale, wanted, fields, apply, log):
    current = existing.get(locale)
    diff = changed_fields(attrs(current) if current else None, wanted, fields)
    if current and not diff:
        log(f"{locale}：{kind}没有变化")
        return current
    log(f"{locale}：{kind}{'更新' if current else '新建'} {', '.join(sorted(diff))}")
    if not apply:
        return current
    res_type = {"appInfo": "appInfoLocalizations", "appStoreVersion": "appStoreVersionLocalizations"}[parent_type]
    if current:
        body = {"data": {"type": res_type, "id": current["id"], "attributes": diff}}
        return api.call("PATCH", f"/{res_type}/{current['id']}", body)["data"]
    body = {"data": {"type": res_type, "attributes": dict({"locale": locale}, **{f: wanted[f] for f in fields}),
                     "relationships": {parent_type: {"data": {"type": parent_type + "s", "id": parent_id}}}}}
    return api.call("POST", f"/{res_type}", body)["data"]


def upload_screenshot(api, set_id, path):
    with open(path, "rb") as f:
        data = f.read()
    body = {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
                     "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}}
    shot = api.call("POST", "/appScreenshots", body)["data"]
    for op in attrs(shot)["uploadOperations"]:
        api.put_part(op, data[op["offset"]:op["offset"] + op["length"]])
    commit = {"data": {"type": "appScreenshots", "id": shot["id"],
                       "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}
    api.call("PATCH", f"/appScreenshots/{shot['id']}", commit)
    return shot["id"]


def sync_screenshots(api, version_loc, locale, files, apply, log):
    if version_loc is None:
        log(f"{locale}：截图 {len(files)} 张待上传（语言页新建后上传）")
        return
    sets = api.call("GET", f"/appStoreVersionLocalizations/{version_loc['id']}/appScreenshotSets")["data"]
    others = sorted({attrs(s)["screenshotDisplayType"] for s in sets} - {DISPLAY_TYPE})
    if others:
        log(f"{locale}：后台另有截图组 {', '.join(others)}，不动")
    target = next((s for s in sets if attrs(s)["screenshotDisplayType"] == DISPLAY_TYPE), None)
    current = api.call("GET", f"/appScreenshotSets/{target['id']}/appScreenshots")["data"] if target else []
    wanted = [md5(p) for p in files]
    if [attrs(s).get("sourceFileChecksum") for s in current] == wanted:
        log(f"{locale}：截图（{DISPLAY_TYPE}）{len(files)} 张没有变化")
        return
    log(f"{locale}：截图（{DISPLAY_TYPE}）替换：删掉后台 {len(current)} 张，上传 {len(files)} 张")
    if not apply:
        return
    if target is None:
        body = {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                         "relationships": {"appStoreVersionLocalization": {
                             "data": {"type": "appStoreVersionLocalizations", "id": version_loc["id"]}}}}}
        target = api.call("POST", "/appScreenshotSets", body)["data"]
    for shot in current:
        api.call("DELETE", f"/appScreenshots/{shot['id']}")
    ids = [upload_screenshot(api, target["id"], p) for p in files]
    order = {"data": [{"type": "appScreenshots", "id": i} for i in ids]}
    api.call("PATCH", f"/appScreenshotSets/{target['id']}/relationships/appScreenshots", order)


def by_locale(resources):
    return {attrs(r)["locale"]: r for r in resources}


def sync(api, bundle_id, version, listings, apply, log=print, screenshot_dir=SCREENSHOT_DIR):
    app = find_app(api, bundle_id)
    info = find_app_info(api, app["id"], apply, log)
    ver = find_version(api, app["id"], version, apply, log)
    info_locs = by_locale(api.call("GET", f"/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"])
    primary = attrs(app).get("primaryLocale")
    order = sorted(listings, key=lambda loc: (loc != primary, loc))
    for locale in order:
        sync_localization(api, "App 信息（名称、副标题、隐私政策网址）", "appInfo", info["id"], info_locs, locale,
                          listings[locale], APP_INFO_FIELDS, apply, log)
    ver_locs = by_locale(api.call("GET", f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")["data"])
    for locale in order:
        listing = listings[locale]
        version_loc = sync_localization(api, "版本页文案（描述、关键词、宣传文本、网址）", "appStoreVersion", ver["id"],
                                        ver_locs, locale, listing, VERSION_FIELDS, apply, log)
        sync_screenshots(api, version_loc, locale, screenshot_files(listing, screenshot_dir), apply, log)
    extra = sorted(set(ver_locs) - set(listings))
    if extra:
        log(f"后台还有仓库里没有的语言：{', '.join(extra)}（不删，需要时在网页上处理）")


def main():
    ap = argparse.ArgumentParser(description="把 docs/appstore/listing/ 里的多语言商店文案和截图同步到 App Store Connect")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="只在本地检查文案长度、关键词重复、截图尺寸")
    mode.add_argument("--dry-run", action="store_true", help="连上 App Store Connect，只列出会改什么，不改")
    mode.add_argument("--upload", action="store_true", help="连上 App Store Connect 并写入")
    ap.add_argument("--version", help="要改的 iOS 版本号，如 1.4")
    args = ap.parse_args()

    listings = load_listings()
    problems = check(listings)
    if problems:
        print("商店文案或截图有问题：\n  - " + "\n  - ".join(problems))
        return 1
    print(f"商店文案和截图检查通过（{len(listings)} 种语言）✅")
    if args.check:
        return 0
    if not args.version:
        ap.error("--dry-run / --upload 需要 --version")
    missing = [v for v in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8", "BUNDLE_ID") if not os.environ.get(v)]
    if missing:
        print(f"缺少配置 {', '.join(missing)}（在 GitHub 仓库的 Secrets / Variables 里）")
        return 1
    sync(Api(), os.environ["BUNDLE_ID"], args.version, listings, apply=args.upload)
    print("已写入 App Store Connect ✅" if args.upload else "以上是会改动的内容（没有写入）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
