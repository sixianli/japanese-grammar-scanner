#!/usr/bin/env python3
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_e2e_ran_all import declared

SHARDS = [
    ["SettingsTests"],
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


def matrix(groups):
    return {"include": [{"shard": i + 1, "only": " ".join(
        f"-only-testing:JapaneseGrammarScannerUITests/{t}" for t in group)} for i, group in enumerate(groups)]}


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        print(json.dumps(matrix([[t.strip() for t in sys.argv[2].split(",") if t.strip()]]), ensure_ascii=False))
        return 0
    classes = {t.split(".")[0] for t in declared()}
    bad = problems(SHARDS, classes)
    if bad:
        print("端对端测试分组有问题：", file=sys.stderr)
        for b in bad:
            print("  - " + b, file=sys.stderr)
        return 1
    print(json.dumps(matrix(SHARDS), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
