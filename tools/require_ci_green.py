#!/usr/bin/env python3
"""发版硬门槛：同一个提交的 CI（数据校验、单元测试、端到端测试）必须全部跑完并通过，才能打包上传。

用法（release.yml 里调用）: GH_TOKEN=... python3 tools/require_ci_green.py <owner/repo> <commit sha>
"""
import json
import os
import sys
import urllib.request

REQUIRED = ["validate-data", "build-and-test", "e2e"]


def main():
    repo, sha = sys.argv[1], sys.argv[2]
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/commits/{sha}/check-runs?per_page=100",
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"})
    runs = json.load(urllib.request.urlopen(req))["check_runs"]
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
    if bad:
        print(f"::error::提交 {sha[:7]} 的 CI 没有全部通过，不能发版：")
        for b in bad:
            print(f"::error::  {b}")
        return 1
    print(f"提交 {sha[:7]} 的 {'、'.join(REQUIRED)} 全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
