#!/usr/bin/env python3
import json
import os
import sys
import urllib.request

REQUIRED = ["validate-data", "build-and-test", "e2e"]


def problems_in_one_run(runs):
    latest = {}
    for r in sorted(runs, key=lambda r: r.get("started_at") or ""):
        latest[r["name"]] = r
    bad = []
    for name in REQUIRED:
        r = latest.get(name)
        if r is None:
            bad.append(f"{name}：这个提交还没有跑过")
        elif r["status"] != "completed":
            bad.append(f"{name}：还在运行（{r['status']}），等跑完再发版")
        elif r["conclusion"] != "success":
            bad.append(f"{name}：没有通过（{r['conclusion']}）{r.get('html_url', '')}")
    return bad


def problems(runs):
    by_run = {}
    for r in runs:
        if r["name"] in REQUIRED:
            by_run.setdefault(r["check_suite"]["id"], []).append(r)
    if not by_run:
        return problems_in_one_run([])
    reports = [problems_in_one_run(rs) for rs in by_run.values()]
    if any(not bad for bad in reports):
        return []
    newest = max(by_run, key=lambda k: max(r.get("started_at") or "" for r in by_run[k]))
    return problems_in_one_run(by_run[newest])


def main():
    repo, sha = sys.argv[1], sys.argv[2]
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/commits/{sha}/check-runs?per_page=100",
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"})
    bad = problems(json.load(urllib.request.urlopen(req))["check_runs"])
    if bad:
        print(f"::error::提交 {sha[:7]} 的 CI 没有全部通过，不能发版：")
        for b in bad:
            print(f"::error::  {b}")
        return 1
    print(f"提交 {sha[:7]} 的 {'、'.join(REQUIRED)} 全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
