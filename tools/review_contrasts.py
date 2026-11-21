#!/usr/bin/env python3
import argparse
import concurrent.futures
import glob
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAMMAR_DIR = os.path.join(ROOT, "JapaneseGrammarScanner", "Resources", "Grammar")
CONTRASTS = os.path.join(GRAMMAR_DIR, "contrasts", "contrasts.json")
STANDARD = os.path.join(ROOT, "docs", "content", "contrasts-standard.md")
RECORDS = os.path.join(ROOT, "tools", "contrast_reviews.json")
CALIBRATION = os.path.join(ROOT, "tools", "contrast_review_calibration.json")
API_URL = os.environ.get("OPENCODE_URL", "https://opencode.ai/zen/go/v1/chat/completions")
SESSION_ID = "contrast-review-" + hashlib.sha256(str(time.time()).encode()).hexdigest()[:16]
USER_AGENT = "jgs-contrast-review/1.0"
MODEL = "deepseek-v4.1-flash"
REASONING_EFFORT = "high"
PRICE_PER_MTOK = {"input": 0.3, "cached": 0.006, "output": 1.2}
KIND_HEADINGS = {"root": "## 同一个词变来的", "look": "## 长得像的", "meaning": "## 意思差不多的"}

SYSTEM = """你是日语语法学习 App 的内容审核员。App 的「相近语法」把一个语法点（本页）和另一个语法点（对方）放在一起比较，分三组：同一个词变来的（root）、长得像的（look）、意思差不多的（meaning）。

请严格按下面的内容质量标准，判断给你的这一条对比是否合格。机器已经检查过格式（组说明的写法、虚线线索、高亮能否识别、例句重复），你只判断机器判断不了的部分：
- root：两边是否真的来自同一个具体的词，词源是否真实；能否从本义分别讲通两边的意思；讲解有没有讲出从本义到两个用法的变化路径。
- look：形状是否只差很小的地方；意思是否明显不同；学习者是否真会看错。
- meaning：组说明是不是一个具体的共同意思；这个意思是否是双方各自详情页里的正式义项；替换测试能否成立；差别是不是同一个意思里的差别，而不是两个不同的意思；是否属于「不收」里列的情况（只是中文译法一样、同类意思程度不同、意思相反）。写了 sense 时，只看本页那个义项。
- 所有组：组里这一条是否兑现组说明的卖点；对方详情页是否真的讲这个用法；两句例句是不是最小对比，讲解是否说清「看哪里就能分辨」；日语是否自然，注音是否正确，中文翻译是否准确。

下面这些不是 fail 的理由，不要写进 problems：
- 组说明的格式、虚线线索词有没有在讲解里点名、sense 有没有写、例句是否重复：这些由机器检查。只有一组「意思差不多的」时不写 sense 是对的。
- 多义语法点只拿其中一个义项来比，这很正常，不算混义。只有组说明、一句话区别或讲解本身把两个不同的意思拼在一起，才算混义。
- 两句例句的句子框架不同：标准说的是「尽量」最小对比。只要两句各自能看出差别，讲解给出了能照着做的分辨方法，就合格。
- 组说明说得出一个共同意思（如「都表示原因」「都表示「必须」」）就够具体；不合格的是「和时间有关」「和否定呼应」这类大类。
- 替换测试：同一类句子两边都能自然地说，换了以后基本意思不变、只是语感或评价不同，就成立；不要求完全同义，也不要求每个例句都能互换。

只输出一个 JSON 对象，不要输出别的文字：
{"verdict": "pass" 或 "fail", "problems": [{"rule": "违反的标准条目，简短", "detail": "具体哪里不对"}], "fix": "不通过时，建议怎么改（改写、换对比对象、移出这一组、移到待用清单），通过时为空字符串"}
有任何一条实质问题就判 fail；只是措辞可以更好、不影响学习者理解的，判 pass。"""


def standard_rules(kind):
    with open(STANDARD, encoding="utf-8") as fh:
        text = fh.read()
    sections = re.split(r"(?m)^(?=## )", text)
    common = next(s for s in sections if s.startswith("## 三组都要做到的"))
    own = next(s for s in sections if s.startswith(KIND_HEADINGS[kind]))
    return common.strip() + "\n\n" + own.strip()


def load_points(grammar_dir=GRAMMAR_DIR):
    points = {}
    for f in glob.glob(os.path.join(grammar_dir, "grammar_*.json")):
        with open(f, encoding="utf-8") as fh:
            points.update({p["id"]: p for p in json.load(fh)})
    return points


def load_base(path=CONTRASTS):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)["points"]


def plain(ja):
    out = []
    for seg in ja.split("|"):
        body = seg[1:] if seg[:1] in "*~" else seg
        base = body.split(":", 1)[0]
        mark = "【" + base + "】" if seg.startswith("*") else ("〔" + base + "〕" if seg.startswith("~") else base)
        out.append(mark)
    return "".join(out)


def page_summary(point):
    if not point:
        return None
    return {
        "id": point["id"],
        "title": point.get("title"),
        "senses": [{"label": s.get("label"), "meaning": s.get("meaning")} for s in point.get("senses") or []],
    }


def sentences(item, key):
    v = item.get(key)
    if isinstance(v, dict):
        return [v]
    return v if isinstance(v, list) else []


def item_key(pid, group, item):
    sense = str(group["sense"]) if "sense" in group else ""
    suffix = "#" + item["title"] if "title" in item else ""
    return f"{pid}/{group['kind']}{sense}/{item['id']}{suffix}"


def item_payload(pid, group, item, points):
    payload = {
        "kind": group["kind"],
        "note": group.get("note"),
        "this_page": page_summary(points.get(pid)),
        "that_page": page_summary(points.get(item["id"])),
        "item": item,
    }
    if "sense" in group:
        payload["sense"] = group["sense"]
    return payload


def review_items(base, points):
    return [(item_key(p["id"], g, it), item_payload(p["id"], g, it, points))
            for p in base for g in p["groups"] for it in g["items"]]


def prompt_version():
    rules = "\n".join(standard_rules(k) for k in KIND_HEADINGS)
    return hashlib.sha256((MODEL + REASONING_EFFORT + SYSTEM + rules).encode("utf-8")).hexdigest()[:16]


def content_hash(payload):
    blob = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256((prompt_version() + blob).encode("utf-8")).hexdigest()[:20]


def gate_problems(base, points, records):
    problems = []
    for key, payload in review_items(base, points):
        rec = records.get(key)
        if rec is None:
            problems.append(f"{key}: 没有模型审核记录")
        elif rec.get("hash") != content_hash(payload):
            problems.append(f"{key}: 内容或标准在审核后改过，需要重新审核")
        elif (rec.get("final") or {}).get("hash") != rec["hash"]:
            problems.append(f"{key}: 还没有对当前内容做最终把关（初审结论：{rec.get('verdict')}）")
        elif rec["final"].get("verdict") != "pass":
            problems.append(f"{key}: 最终把关不通过：{rec['final'].get('reason', '')}")
    return problems


def apply_final(base, points, records, entries):
    current = {key: content_hash(payload) for key, payload in review_items(base, points)}
    errors = []
    for e in entries:
        key, verdict = e.get("key"), e.get("verdict")
        rec = records.get(key)
        if key not in current:
            errors.append(f"{key}: 现在的资料里没有这一条")
        elif verdict not in ("pass", "fail"):
            errors.append(f"{key}: 结论只能是 pass 或 fail：{verdict}")
        elif rec is None or rec.get("hash") != current[key]:
            errors.append(f"{key}: 初审之后内容改过，要先重新初审")
        else:
            rec["final"] = {"hash": rec["hash"], "verdict": verdict, "reason": e.get("reason", ""),
                            "action": e.get("action", "")}
    return errors


def user_message(payload):
    item = payload["item"]
    lines = [
        f"组：{payload['kind']}",
        f"组说明：{payload['note']}",
    ]
    if "sense" in payload:
        lines.append(f"这一组对应本页第 {payload['sense']} 个义项")
    lines += [
        "本页详情页：" + json.dumps(payload["this_page"], ensure_ascii=False),
        "对方详情页：" + json.dumps(payload["that_page"], ensure_ascii=False),
        f"一句话区别（diff）：{item.get('diff')}",
    ]
    for key, label in (("this", "本页例句"), ("that", "对方例句")):
        for s in sentences(item, key):
            lines.append(f"{label}：{plain(s.get('ja', ''))}｜标签：{s.get('tag')}｜翻译：{s.get('tr')}")
    if "wrong" in item:
        lines.append(f"✗ 例：{plain(item['wrong'].get('ja', ''))}｜为什么错：{item['wrong'].get('why')}")
    lines.append(f"怎么分辨（explain）：{item.get('explain')}")
    lines.append("例句里【】是语法本体（高亮），〔〕是线索词（虚线）。")
    return "\n".join(lines)


def system_message(kind):
    return SYSTEM + "\n\n内容质量标准：\n" + standard_rules(kind)


def call_model(payload, timeout=180, retries=4):
    body = json.dumps({
        "model": MODEL,
        "temperature": 0,
        "reasoning_effort": REASONING_EFFORT,
        "response_format": {"type": "json_object"},
        "messages": [{"role": "system", "content": system_message(payload["kind"])},
                     {"role": "user", "content": user_message(payload)}],
    }).encode("utf-8")
    req = urllib.request.Request(API_URL, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": "Bearer " + os.environ.get("OPENCODE_API_KEY", "proxy-injected"),
        "User-Agent": USER_AGENT,
        "x-opencode-session": SESSION_ID,
    })
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.load(resp)
            text = data["choices"][0]["message"]["content"]
            verdict = json.loads(text[text.find("{"):text.rfind("}") + 1])
            return verdict, data.get("usage", {})
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                raise SystemExit(f"opencode 拒绝了请求（{e.code}）：{e.read()[:300]!r}")
            err = e
        except (urllib.error.URLError, OSError, KeyError, ValueError) as e:
            err = e
        time.sleep(2 ** attempt * 3)
    raise RuntimeError(f"模型调用失败：{err}")


def usage_cost(usage):
    if "list_cost" in (usage.get("opencode") or {}):
        return usage["opencode"]["list_cost"]
    prompt = usage.get("prompt_tokens", 0)
    cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens", 0) or usage.get("prompt_cache_hit_tokens", 0)
    out = usage.get("completion_tokens", 0)
    return ((prompt - cached) * PRICE_PER_MTOK["input"] + cached * PRICE_PER_MTOK["cached"]
            + out * PRICE_PER_MTOK["output"]) / 1e6


def allowance_used(usage):
    return (usage.get("opencode") or {}).get("allowance", 0.0)


def run_many(jobs, workers, on_result=None):
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(call_model, payload): key for key, payload in jobs}
        for n, fut in enumerate(concurrent.futures.as_completed(futures), 1):
            key = futures[fut]
            try:
                results[key] = fut.result()
            except RuntimeError as e:
                print(f"  ! {key}: {e}", file=sys.stderr)
            else:
                if on_result:
                    on_result(key, results[key])
            if n % 50 == 0:
                print(f"  已审 {n}/{len(jobs)}", file=sys.stderr)
    return results


def load_records(path=RECORDS):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)["records"]


def save_records(records, path=RECORDS):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"model": MODEL, "records": dict(sorted(records.items()))}, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, path)


def review_and_record(jobs, records, workers, path=RECORDS):
    payloads = dict(jobs)
    totals = {"cost": 0.0, "allowance": 0.0}

    def record(key, result):
        verdict, usage = result
        totals["cost"] += usage_cost(usage)
        totals["allowance"] += allowance_used(usage)
        records[key] = {"hash": content_hash(payloads[key]), "verdict": verdict.get("verdict"),
                        "reason": reason_text(verdict), "fix": verdict.get("fix", "")}
        save_records(records, path)

    run_many(jobs, workers, on_result=record)
    return totals["cost"], totals["allowance"]


def reason_text(verdict):
    parts = [f"{p.get('rule')}：{p.get('detail')}" for p in verdict.get("problems") or []]
    return "；".join(parts)


def calibrate(workers, total_items):
    with open(CALIBRATION, encoding="utf-8") as fh:
        cases = json.load(fh)["cases"]
    jobs = [(c["key"], c["payload"]) for c in cases]
    results = run_many(jobs, workers)
    right, cost, allowance = 0, 0.0, 0.0
    for c in cases:
        if c["key"] not in results:
            print(f"✗ {c['key']}: 没有结果")
            continue
        verdict, usage = results[c["key"]]
        cost += usage_cost(usage)
        allowance += allowance_used(usage)
        ok = verdict.get("verdict") == c["expected"]
        right += ok
        print(f"{'✓' if ok else '✗'} {c['key']}: 应为 {c['expected']}，模型 {verdict.get('verdict')}｜{reason_text(verdict)[:160]}")
    n = len(results)
    print(f"\n准确率 {right}/{len(cases)}；按量计价约 ${cost:.4f}，用掉 Go 额度 ${allowance:.4f}")
    if n:
        print(f"按每条平均估算，全量 {total_items} 条：按量计价约 ${cost / n * total_items:.2f}，"
              f"Go 额度约 ${allowance / n * total_items:.2f}")
    return right == len(cases)


def main():
    ap = argparse.ArgumentParser(description="用模型按 docs/content/contrasts-standard.md 审核相近语法对比")
    ap.add_argument("--check", action="store_true", help="发版门槛：每条对比都要有和当前内容一致的「通过」记录")
    ap.add_argument("--calibrate", action="store_true", help="用已知答案的对比测准确度并估算全量费用")
    ap.add_argument("--run", action="store_true", help="审核没有有效记录的对比（要花钱）")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only", default="", help="只审 key 以这些前缀开头的条目，逗号分隔")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--pending-final", action="store_true", help="列出初审过、还没最终把关的条目")
    ap.add_argument("--verdict", default="", help="和 --pending-final 一起用：只列初审为 pass 或 fail 的")
    ap.add_argument("--set-final", default="", help="把最终把关结论（JSON Lines 文件）写进审核记录")
    args = ap.parse_args()

    base, points = load_base(), load_points()
    if args.check:
        problems = gate_problems(base, points, load_records())
        if problems:
            print(f"相近语法模型审核：{len(problems)} 条没有有效的「通过」记录")
            for p in problems[:30]:
                print("  - " + p)
            return 1
        print("相近语法模型审核：全部通过 ✅")
        return 0
    if args.pending_final:
        records = load_records()
        shown = 0
        for key, payload in review_items(base, points):
            rec = records.get(key)
            if not rec or rec.get("hash") != content_hash(payload) or (rec.get("final") or {}).get("hash") == rec["hash"]:
                continue
            if args.verdict and rec.get("verdict") != args.verdict:
                continue
            print(f"### {key}\n{user_message(payload)}\n初审：{rec.get('verdict')}｜{rec.get('reason')}\n初审建议：{rec.get('fix', '')}\n")
            shown += 1
            if args.limit and shown >= args.limit:
                break
        return 0
    if args.set_final:
        records = load_records()
        with open(args.set_final, encoding="utf-8") as fh:
            entries = [json.loads(line) for line in fh if line.strip()]
        errors = apply_final(base, points, records, entries)
        save_records(records)
        for e in errors:
            print("  ! " + e)
        print(f"写入最终结论 {len(entries) - len(errors)} 条，拒绝 {len(errors)} 条")
        return 1 if errors else 0
    if args.calibrate:
        return 0 if calibrate(args.workers, len(review_items(base, points))) else 1
    if args.run:
        records = load_records()
        prefixes = [p for p in args.only.split(",") if p]
        jobs = [(k, p) for k, p in review_items(base, points)
                if records.get(k, {}).get("hash") != content_hash(p)
                and (not prefixes or any(k.startswith(x) for x in prefixes))]
        if args.limit:
            jobs = jobs[:args.limit]
        print(f"待审 {len(jobs)} 条", file=sys.stderr)
        cost, allowance = review_and_record(jobs, records, args.workers)
        fails = sum(1 for r in records.values() if r["verdict"] != "pass")
        print(f"按量计价约 ${cost:.3f}，用掉 Go 额度 ${allowance:.3f}；记录 {len(records)} 条，其中不通过 {fails} 条")
        return 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
