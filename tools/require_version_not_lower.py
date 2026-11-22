#!/usr/bin/env python3
import os
import sys
import urllib.parse


def parse(version):
    return tuple(int(p) for p in version.split("."))


def highest(versions):
    return max(versions, key=parse, default=None)


def problem(new_version, existing_versions):
    top = highest(existing_versions)
    if top is not None and parse(new_version) < parse(top):
        return (f"版本号 {new_version} 低于 TestFlight 上已有的 {top}。"
                f"TestFlight 首页只显示版本号最高的构建，测试者会看不到这次上传。请用不低于 {top} 的版本号。")
    return None


def fetch_versions():
    from testflight_status import call
    app = call("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": os.environ["BUNDLE_ID"]}))["data"][0]
    res = call("GET", f"/apps/{app['id']}/preReleaseVersions?limit=200")
    return [v["attributes"]["version"] for v in res["data"]]


def main():
    new_version = sys.argv[1]
    existing = fetch_versions()
    print("TestFlight 上已有的版本：", ", ".join(sorted(existing, key=parse)) or "无")
    message = problem(new_version, existing)
    if message:
        print(f"::error::{message}")
        sys.exit(1)
    print(f"版本号 {new_version} 可以使用")


if __name__ == "__main__":
    main()
