#!/usr/bin/env python3
"""汇总 App 内匿名使用统计（CloudKit 公共数据库里的 UsageDay 记录），每周发一封报告邮件。

由 .github/workflows/usage-report.yml 每周一运行，也可手动运行。配置和反馈转发共用
（CLOUDKIT_* / FEEDBACK_SMTP_* 等，见 docs/feedback/SETUP.md），不需要额外的密钥。

每台设备每天最多一条 UsageDay 记录，不含任何设备或个人编号。口径：
  总用户数   = 所有带「新安装」标记的记录数（每台设备只会有一条）
  日活 DAU   = 某一天的记录数
  周活 WAU   = 某一 ISO 周里带「本周第一次」标记的记录数
  月活 MAU   = 某个月里带「本月第一次」标记的记录数
  国家 / 地区 = App Store 店面所在国家（ISO 3166 alpha-3，例如 CHN / JPN / USA）

用法：
  python3 tools/usage_report.py                 # 拉取最近 120 天的数据，发邮件
  python3 tools/usage_report.py --dry-run       # 只打印报告，不发邮件
  python3 tools/usage_report.py --from-json f   # 用本地导出的记录（测试用），配合 --dry-run
"""
import collections
import datetime
import glob
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")

COUNTRY_ZH = {
    "CHN": "中国大陆", "TWN": "中国台湾", "HKG": "中国香港", "MAC": "中国澳门", "JPN": "日本", "KOR": "韩国",
    "USA": "美国", "CAN": "加拿大", "GBR": "英国", "AUS": "澳大利亚", "NZL": "新西兰", "SGP": "新加坡",
    "MYS": "马来西亚", "THA": "泰国", "VNM": "越南", "MMR": "缅甸", "IDN": "印度尼西亚", "PHL": "菲律宾",
    "IND": "印度", "DEU": "德国", "FRA": "法国", "ESP": "西班牙", "ITA": "意大利", "NLD": "荷兰",
    "BRA": "巴西", "MEX": "墨西哥", "ARG": "阿根廷", "CHL": "智利", "COL": "哥伦比亚", "PER": "秘鲁",
    "RUS": "俄罗斯", "UKR": "乌克兰", "POL": "波兰", "SWE": "瑞典", "NOR": "挪威", "FIN": "芬兰",
    "DNK": "丹麦", "CHE": "瑞士", "AUT": "奥地利", "BEL": "比利时", "PRT": "葡萄牙", "IRL": "爱尔兰",
    "TUR": "土耳其", "SAU": "沙特阿拉伯", "ARE": "阿联酋", "ISR": "以色列", "EGY": "埃及", "ZAF": "南非",
    "MNG": "蒙古", "NPL": "尼泊尔", "BGD": "孟加拉国", "LKA": "斯里兰卡", "KHM": "柬埔寨", "LAO": "老挝",
}


def country_name(code):
    if not code:
        return "未知"
    return f"{COUNTRY_ZH.get(code, code)}（{code}）"


def grammar_titles():
    t = {}
    for f in glob.glob(os.path.join(GRAMMAR, "grammar_*.json")):
        for p in json.load(open(f, encoding="utf-8")):
            t[p["id"]] = f'{p["title"]}（{p["level"]}）'
    return t


def fetch_records(days=120):
    import feedback_forward as ff
    container = ff.env("CLOUDKIT_CONTAINER")
    subpath = f"/database/1/{container}/production/public/records/query"
    since = (datetime.date.today() - datetime.timedelta(days=days)).isoformat()
    out, marker = [], None
    while True:
        body = {
            "query": {
                "recordType": "UsageDay",
                "filterBy": [{"fieldName": "day", "comparator": "GREATER_THAN_OR_EQUALS",
                              "fieldValue": {"value": since, "type": "STRING"}}],
            },
            "resultsLimit": 200,
        }
        if marker:
            body["continuationMarker"] = marker
        res = ff.ck_request(subpath, body)
        for r in res.get("records", []):
            if "serverErrorCode" in r:
                continue
            out.append({k: (v or {}).get("value") for k, v in r.get("fields", {}).items()})
        marker = res.get("continuationMarker")
        if not marker:
            return out


def total_users_ever():
    """总用户数要看全部历史，不只最近 120 天"""
    import feedback_forward as ff
    container = ff.env("CLOUDKIT_CONTAINER")
    subpath = f"/database/1/{container}/production/public/records/query"
    n, marker = 0, None
    while True:
        body = {
            "query": {
                "recordType": "UsageDay",
                "filterBy": [{"fieldName": "newInstall", "comparator": "EQUALS",
                              "fieldValue": {"value": 1, "type": "INT64"}}],
            },
            "resultsLimit": 200, "desiredKeys": ["day"],
        }
        if marker:
            body["continuationMarker"] = marker
        res = ff.ck_request(subpath, body)
        n += sum(1 for r in res.get("records", []) if "serverErrorCode" not in r)
        marker = res.get("continuationMarker")
        if not marker:
            return n


def as_json(v, default):
    if isinstance(v, (dict, list)):
        return v
    try:
        return json.loads(v or "")
    except ValueError:
        return default


def iso_week(day):
    y, w, _ = datetime.date.fromisoformat(day).isocalendar()
    return f"{y:04d}-W{w:02d}"


def bar(n, top, width=20):
    return "█" * max(1 if n else 0, round(width * n / top)) if top else ""


def build_report(records, total_ever=None, today=None):
    today = today or datetime.date.today()
    titles = grammar_titles()
    for r in records:
        r["newInstall"] = int(r.get("newInstall") or 0)
        r["firstInWeek"] = int(r.get("firstInWeek") or 0)
        r["firstInMonth"] = int(r.get("firstInMonth") or 0)
        r["sessions"] = int(r.get("sessions") or 0)
        r["week"] = r.get("week") or iso_week(r["day"])
        r["month"] = r.get("month") or r["day"][:7]

    last_week = iso_week((today - datetime.timedelta(days=7)).isoformat())
    this_month = today.strftime("%Y-%m")
    last_month = (today.replace(day=1) - datetime.timedelta(days=1)).strftime("%Y-%m")

    dau = collections.Counter(r["day"] for r in records)
    wau = collections.Counter(r["week"] for r in records if r["firstInWeek"])
    mau = collections.Counter(r["month"] for r in records if r["firstInMonth"])
    new_week = collections.Counter(r["week"] for r in records if r["newInstall"])
    total = total_ever if total_ever is not None else sum(r["newInstall"] for r in records)

    L = []
    L.append(f"日语语法速查 · 使用统计周报（截至 {today:%Y-%m-%d}）")
    L.append("")
    L.append("一、用户规模")
    L.append(f"  累计用户（装过并打开过的设备）：{total}")
    L.append(f"  上周（{last_week}）周活 WAU：{wau.get(last_week, 0)}，其中新用户 {new_week.get(last_week, 0)}")
    L.append(f"  本月（{this_month}，进行中）月活 MAU：{mau.get(this_month, 0)}")
    L.append(f"  上月（{last_month}）月活 MAU：{mau.get(last_month, 0)}")
    recent_days = [(today - datetime.timedelta(days=i)).isoformat() for i in range(1, 8)]
    avg_dau = sum(dau.get(d, 0) for d in recent_days) / 7
    L.append(f"  最近 7 天日均日活 DAU：{avg_dau:.1f}")
    if wau.get(last_week):
        L.append(f"  黏性（日均 DAU / WAU）：{avg_dau / wau[last_week] * 100:.0f}%")
    L.append("")

    L.append("二、最近 12 周趋势（周活 / 新用户）")
    weeks = sorted(set(wau) | set(new_week))[-12:]
    top = max([wau.get(w, 0) for w in weeks] or [0])
    for w in weeks:
        L.append(f"  {w}  {wau.get(w, 0):>5}  新 {new_week.get(w, 0):>4}  {bar(wau.get(w, 0), top)}")
    L.append("")

    L.append("三、最近 14 天日活")
    days = [(today - datetime.timedelta(days=i)).isoformat() for i in range(14, 0, -1)]
    top = max([dau.get(d, 0) for d in days] or [0])
    for d in days:
        L.append(f"  {d}  {dau.get(d, 0):>5}  {bar(dau.get(d, 0), top)}")
    L.append("")

    # 国家：按月活（每台设备每月只算一次）
    month_for_country = last_month if mau.get(last_month) else this_month
    by_country = collections.Counter(r.get("country") or "" for r in records
                                     if r["firstInMonth"] and r["month"] == month_for_country)
    all_country = collections.Counter(r.get("country") or "" for r in records if r["newInstall"])
    L.append(f"四、国家 / 地区（{month_for_country} 月活）")
    top = max(by_country.values() or [0])
    n = sum(by_country.values())
    for c, k in by_country.most_common(20):
        L.append(f"  {country_name(c):<16} {k:>5}  {k / n * 100:5.1f}%  {bar(k, top)}")
    if all_country:
        L.append("  最近 120 天新用户来源：" + "，".join(f"{country_name(c)} {k}" for c, k in all_country.most_common(10)))
    L.append("")

    recent = [r for r in records if r["day"] >= (today - datetime.timedelta(days=28)).isoformat()]
    hours = [0] * 24
    for r in recent:
        for i, v in enumerate(as_json(r.get("hours"), [0] * 24)[:24]):
            hours[i] += int(v or 0)
    L.append("五、使用时段（最近 28 天，用户当地时间，打开 App 的次数）")
    top = max(hours)
    for i, v in enumerate(hours):
        L.append(f"  {i:02d}:00  {v:>6}  {bar(v, top, 30)}")
    L.append("")

    grammar = collections.Counter()
    levels = collections.Counter()
    for r in recent:
        grammar.update({k: int(v) for k, v in as_json(r.get("grammar"), {}).items()})
        levels.update({k: int(v) for k, v in as_json(r.get("levels"), {}).items()})
    L.append("六、JLPT 等级分布（最近 28 天打开讲解的次数）")
    n = sum(levels.values())
    for lv in ["N5", "N4", "N3", "N2", "N1"]:
        k = levels.get(lv, 0)
        L.append(f"  {lv}  {k:>6}  {k / n * 100 if n else 0:5.1f}%  {bar(k, max(levels.values() or [0]))}")
    L.append("")
    L.append("七、查得最多的语法点（最近 28 天，前 30）")
    for i, (g, k) in enumerate(grammar.most_common(30), 1):
        L.append(f"  {i:>2}. {titles.get(g, g)}  {k}")
    L.append("")

    lang = collections.Counter(r.get("language") or "?" for r in records if r["firstInMonth"] and r["month"] == month_for_country)
    ver = collections.Counter(r.get("appVersion") or "?" for r in recent)
    L.append("八、其他")
    L.append("  App 界面语言（月活）：" + "，".join(f"{k} {v}" for k, v in lang.most_common()))
    L.append("  App 版本（最近 28 天的记录）：" + "，".join(f"{k} {v}" for k, v in ver.most_common()))
    sessions = sum(r["sessions"] for r in recent)
    L.append(f"  最近 28 天打开次数：{sessions}，人均每个活跃日 {sessions / max(len(recent), 1):.1f} 次")
    L.append("")
    L.append("说明：只统计没有关闭「设置 → 匿名使用统计」、且登录了 iCloud 的设备；数据不含任何设备或个人编号。")
    return "\n".join(L)


def main():
    dry = "--dry-run" in sys.argv
    if "--from-json" in sys.argv:
        records = json.load(open(sys.argv[sys.argv.index("--from-json") + 1], encoding="utf-8"))
        total = None
    else:
        records = fetch_records()
        total = total_users_ever()
    report = build_report(records, total)
    print(report)
    if dry:
        return
    import feedback_forward as ff
    msg = ff.new_message(f"日语语法速查 · 使用统计周报 {datetime.date.today():%m-%d}")
    msg.set_content(report)
    ff.smtp_send(msg)
    print("报告已发送")


if __name__ == "__main__":
    main()
