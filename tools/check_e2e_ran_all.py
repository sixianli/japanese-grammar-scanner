#!/usr/bin/env python3
import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def declared(root=ROOT):
    tests = set()
    for f in glob.glob(os.path.join(root, "JapaneseGrammarScannerUITests", "*.swift")):
        cls = None
        for line in open(f, encoding="utf-8"):
            m = re.match(r"\s*(?:final\s+)?class\s+(\w+)\s*:\s*(\w+)", line)
            if m:
                cls = m.group(1) if m.group(2) in ("E2ETestCase", "XCTestCase") else None
                continue
            m = re.match(r"\s*func\s+(test\w+)\s*\(\s*\)", line)
            if m and cls:
                tests.add(f"{cls}.{m.group(1)}")
    return tests


def results(log, outcome):
    pat = re.compile(r"Test Case '-\[JapaneseGrammarScannerUITests\.(\w+) (\w+)\]' " + outcome)
    return {f"{a}.{b}" for a, b in pat.findall(open(log, encoding="utf-8", errors="replace").read())}


def passed(log):
    return results(log, "passed")


def retried(log):
    """失败过、重跑后通过的用例（CI 机器满载时的偶发失败，仍要留意）"""
    return sorted(results(log, "failed") & passed(log))


def selection_names(only):
    return [t.strip() for t in only.split(",") if t.strip()]


def expected(only, root=ROOT):
    tests = declared(root)
    names = selection_names(only)
    if not names:
        return tests
    want = set()
    for name in names:
        if "/" in name:
            want.add(name.replace("/", "."))
        else:
            want |= {t for t in tests if t.split(".")[0] == name}
    return want


def missing(log, only="", root=ROOT):
    return sorted(expected(only, root) - passed(log))


def rerun_value(tests):
    return ",".join(t.replace(".", "/") for t in tests)


def main():
    parser = argparse.ArgumentParser(description="核对 e2e 日志里，该跑的每个用例都有「通过」记录（被跳过的用例 xcodebuild 不算失败）")
    parser.add_argument("log")
    parser.add_argument("--only", default="", help="和 workflow 的 e2e_only 输入相同；留空表示核对全部用例")
    args = parser.parse_args()
    want = expected(args.only)
    gone = missing(args.log, args.only)
    print(f"端对端测试：应跑 {len(want)} 个，通过 {len(want) - len(gone)} 个")
    flaky = retried(args.log)
    if flaky:
        print(f"其中 {len(flaky)} 个第一次失败、重跑才过（偶发，若反复出现要查）：")
        for t in flaky:
            print("  - " + t)
        print("连跑几遍确认：手动触发 iOS Build & Test，e2e_repeat 填 5，e2e_only 填")
        print("  " + rerun_value(flaky))
        print(f"::warning::{len(flaky)} 个端对端用例重跑才过：{rerun_value(flaky)}")
    if gone:
        print("没有通过记录（失败、被跳过或没跑到）:")
        for t in gone:
            print("  - " + t)
        print("只重跑这些用例：手动触发 iOS Build & Test，e2e_only 填")
        print("  " + rerun_value(gone))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
