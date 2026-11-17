#!/usr/bin/env python3
"""查询 App Store Connect：等待最新构建处理完成，并把它加入所有内部测试群组（TestFlight）。
环境变量：ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID, [VERSION]
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {method} {path}: {e.read().decode()[:500]}")
        raise


def main():
    app = call("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": os.environ["BUNDLE_ID"]}))["data"][0]
    print("App:", app["attributes"]["name"], app["id"])
    version = os.environ.get("VERSION")
    for attempt in range(60):
        q = {"filter[app]": app["id"], "sort": "-uploadedDate", "limit": "1", "include": "preReleaseVersion"}
        if version:
            q["filter[preReleaseVersion.version]"] = version
        res = call("GET", "/builds?" + urllib.parse.urlencode(q))
        if res["data"]:
            b = res["data"][0]
            a = b["attributes"]
            print(f"Build {a['version']} state={a['processingState']} uploaded={a['uploadedDate']} expired={a['expired']}")
            if a["processingState"] == "VALID":
                break
            if a["processingState"] in ("FAILED", "INVALID"):
                sys.exit("构建处理失败")
        else:
            print("还没有找到构建，等待…")
        time.sleep(60)
    else:
        sys.exit("等待超时")

    # 出口合规：Info.plist 已声明不使用非豁免加密，这里再确认一次
    if a.get("usesNonExemptEncryption") is None:
        try:
            call("PATCH", f"/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
        except urllib.error.HTTPError:
            pass

    groups = call("GET", f"/apps/{app['id']}/betaGroups")["data"]
    for g in groups:
        ga = g["attributes"]
        if ga.get("isInternalGroup"):
            try:
                call("POST", f"/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": b["id"]}]})
                print(f"已加入内部测试群组「{ga['name']}」")
            except urllib.error.HTTPError:
                print(f"加入群组「{ga['name']}」失败（可能已自动加入）")
    detail = call("GET", f"/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
    print("TestFlight 状态:", json.dumps(detail, ensure_ascii=False))


if __name__ == "__main__":
    main()
