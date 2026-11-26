#!/usr/bin/env python3
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_e2e_ran_all import ROOT, declared, selection_names

SHARDS = [
    ["SettingsTests", "LineSelectFlowTests"],
    ["ScanResultTests", "HomeTests", "SakuraAnimationTests"],
    ["DetailTests", "ReviewTests"],
    ["EndToEndTests", "FavoritesTests", "SearchTests", "LibraryTests", "FreshInstallTests"],
]


def problems(shards, classes):
    assigned = [c for shard in shards for c in shard]
    out = []
    for c in sorted(classes - set(assigned)):
        out.append(f"{c} 没有分到任何一组，CI 不会跑它，请加进 tools/e2e_shards.py 的 SHARDS")
    for c in sorted({c for c in assigned if assigned.count(c) > 1}):
        out.append(f"{c} 同时分在多组里，会重复跑")
    for c in sorted(set(assigned) - classes):
        out.append(f"{c} 在 JapaneseGrammarScannerUITests 里不存在（改名或删掉了？）")
    return out


def select(only, root=ROOT):
    tests = declared(root)
    classes = {t.split(".")[0] for t in tests}
    names = selection_names(only)
    if not names:
        return [], ["e2e_only 里没有用例名；格式是 类名 或 类名/方法名，多个用逗号分开"]
    errors = []
    for name in names:
        known = name.replace("/", ".") in tests if name.count("/") == 1 else name in classes
        if not known:
            errors.append(f"{name} 不是 JapaneseGrammarScannerUITests 里的用例；格式是 类名 或 类名/方法名（例如 DetailTests/testSenseRowsJumpWithinPage）")
    return [names], errors


def matrix(groups):
    return {"include": [{"shard": i + 1, "only": " ".join(
        f"-only-testing:JapaneseGrammarScannerUITests/{t}" for t in group)} for i, group in enumerate(groups)]}


def report(title, errors):
    print(title, file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    return 1


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        groups, errors = select(sys.argv[2])
        if errors:
            return report("e2e_only 填写有误，没有开始跑：", errors)
        print(json.dumps(matrix(groups), ensure_ascii=False))
        return 0
    classes = {t.split(".")[0] for t in declared()}
    bad = problems(SHARDS, classes)
    if bad:
        return report("端对端测试分组有问题：", bad)
    print(json.dumps(matrix(SHARDS), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
