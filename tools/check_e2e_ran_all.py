#!/usr/bin/env python3
"""核对端对端测试的日志：JapaneseGrammarScannerUITests 里的每个测试方法都出现在「通过」的记录里。

测试进程中途崩溃重启时，xcodebuild 会直接跳过当时正在跑的用例，既不算通过也不算失败，最后仍可能显示成功。
用法: python3 tools/check_e2e_ran_all.py e2e.log
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def declared():
    tests = set()
    for f in glob.glob(os.path.join(ROOT, "JapaneseGrammarScannerUITests", "*.swift")):
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


def passed(log):
    pat = re.compile(r"Test Case '-\[JapaneseGrammarScannerUITests\.(\w+) (\w+)\]' passed")
    return {f"{a}.{b}" for a, b in pat.findall(open(log, encoding="utf-8", errors="replace").read())}


def main():
    want, got = declared(), passed(sys.argv[1])
    missing = sorted(want - got)
    print(f"端对端测试：声明 {len(want)} 个，通过 {len(got & want)} 个")
    if missing:
        print("没有通过记录（失败、被跳过或没跑到）:")
        for t in missing:
            print("  - " + t)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
