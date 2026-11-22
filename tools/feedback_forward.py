#!/usr/bin/env python3
"""把 CloudKit 公共数据库里的新反馈转发到开发者邮箱（由 .github/workflows/feedback-forward.yml 定时运行）。

环境变量（都放在 GitHub Secrets / Variables 里，不要写进代码）：
  CLOUDKIT_CONTAINER        iCloud 容器 ID，例如 iCloud.com.example.app
  CLOUDKIT_KEY_ID           CloudKit 服务器访问密钥的 Key ID
  CLOUDKIT_PRIVATE_KEY      对应的 EC 私钥（PEM 全文）
  FEEDBACK_SMTP_HOST        发信服务器，例如 smtp.gmail.com / smtp.qq.com / smtp.163.com
  FEEDBACK_SMTP_PORT        默认 465（SSL）；587 时使用 STARTTLS
  FEEDBACK_SMTP_USER        发信邮箱账号
  FEEDBACK_SMTP_PASSWORD    邮箱的「应用专用密码 / 授权码」（不是登录密码）
  FEEDBACK_TO               收件地址（不填则发给 FEEDBACK_SMTP_USER 自己）
  STATE_FILE                记录已转发到哪一条（毫秒时间戳）的文件
用法：
  python3 tools/feedback_forward.py            # 转发新反馈
  python3 tools/feedback_forward.py --test     # 只发一封测试邮件，检查邮箱配置
"""
import base64
import datetime
import hashlib
import json
import os
import smtplib
import ssl
import sys
import time
import urllib.request
from email.message import EmailMessage

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

API = "https://api.apple-cloudkit.com"


def env(name, default=None, required=True):
    v = os.environ.get(name, default)
    if required and not v:
        sys.exit(f"缺少配置 {name}")
    return v


def ck_request(subpath, body):
    key = serialization.load_pem_private_key(env("CLOUDKIT_PRIVATE_KEY").encode(), password=None)
    data = json.dumps(body).encode()
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = f"{date}:{base64.b64encode(hashlib.sha256(data).digest()).decode()}:{subpath}"
    signature = base64.b64encode(key.sign(payload.encode(), ec.ECDSA(hashes.SHA256()))).decode()
    req = urllib.request.Request(API + subpath, data=data, method="POST", headers={
        "Content-Type": "application/json",
        "X-Apple-CloudKit-Request-KeyID": env("CLOUDKIT_KEY_ID"),
        "X-Apple-CloudKit-Request-ISO8601Date": date,
        "X-Apple-CloudKit-Request-SignatureV1": signature,
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"CloudKit 请求失败 {e.code}: {e.read().decode(errors='replace')[:500]}")


def fetch_new(since_ms):
    container = env("CLOUDKIT_CONTAINER")
    subpath = f"/database/1/{container}/production/public/records/query"
    records, marker = [], None
    while True:
        body = {
            "query": {
                "recordType": "Feedback",
                "filterBy": [{"fieldName": "___createTime", "comparator": "GREATER_THAN",
                              "fieldValue": {"value": since_ms, "type": "TIMESTAMP"}}],
                "sortBy": [{"fieldName": "___createTime", "ascending": True}],
            },
            "resultsLimit": 50,
        }
        if marker:
            body["continuationMarker"] = marker
        res = ck_request(subpath, body)
        records += [r for r in res.get("records", []) if "serverErrorCode" not in r]
        marker = res.get("continuationMarker")
        if not marker:
            return records


def field(rec, name):
    return (rec.get("fields", {}).get(name) or {}).get("value")


def smtp_send(msg):
    host = env("FEEDBACK_SMTP_HOST")
    port = int(env("FEEDBACK_SMTP_PORT", "465"))
    user = env("FEEDBACK_SMTP_USER")
    password = env("FEEDBACK_SMTP_PASSWORD")
    if port == 465:
        with smtplib.SMTP_SSL(host, port, context=ssl.create_default_context(), timeout=60) as s:
            s.login(user, password)
            s.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=60) as s:
            s.starttls(context=ssl.create_default_context())
            s.login(user, password)
            s.send_message(msg)


def new_message(subject):
    msg = EmailMessage()
    sender = env("FEEDBACK_SMTP_USER")
    msg["From"] = sender
    msg["To"] = os.environ.get("FEEDBACK_TO") or sender
    msg["Subject"] = subject
    return msg


def forward(rec):
    kind = field(rec, "kind") or "Feedback"
    tag = {"Bug": "功能 bug", "Content": "内容", "Suggestion": "建议"}.get(kind, kind)
    created = rec.get("created", {}).get("timestamp", 0)
    when = datetime.datetime.fromtimestamp(created / 1000, datetime.timezone(datetime.timedelta(hours=8)))
    msg = new_message(f"[{tag}] 用户反馈 · App {field(rec, 'appVersion') or '?'} · {when:%m-%d %H:%M}")
    lines = [
        field(rec, "message") or "（没有填写描述）",
        "",
        "——",
        f"类型：{tag}",
        f"时间：{when:%Y-%m-%d %H:%M}（北京时间）",
        f"App 版本：{field(rec, 'appVersion') or '?'}",
        f"系统：iOS {field(rec, 'osVersion') or '?'} · {field(rec, 'device') or '?'}",
        f"语言：{field(rec, 'language') or '?'}",
    ]
    if field(rec, "context"):
        lines.append(f"来自：{field(rec, 'context')}")
    lines.append(f"记录 ID：{rec.get('recordName')}")
    msg.set_content("\n".join(lines))
    for i, asset in enumerate(field(rec, "screenshots") or []):
        url = (asset.get("downloadURL") or "").replace("${f}", f"screenshot-{i + 1}.jpg")
        if not url:
            continue
        with urllib.request.urlopen(url, timeout=60) as r:
            msg.add_attachment(r.read(), maintype="image", subtype="jpeg", filename=f"screenshot-{i + 1}.jpg")
    smtp_send(msg)


def main():
    if "--test" in sys.argv:
        msg = new_message("测试：反馈转发邮箱配置成功")
        msg.set_content("收到这封邮件，说明 GitHub Actions 已经可以把用户反馈转发到这个邮箱。")
        smtp_send(msg)
        print("测试邮件已发送")
        return
    state = env("STATE_FILE")
    since = None
    if os.path.exists(state):
        try:
            since = int(open(state).read().strip())
        except ValueError:
            since = None
    if since is None:
        since = int((time.time() - 3 * 86400) * 1000)  # 第一次运行：转发最近 3 天的
    records = fetch_new(since)
    print(f"新反馈 {len(records)} 条")
    for rec in records:
        forward(rec)
        since = max(since, rec.get("created", {}).get("timestamp", since))
        # 每转发一条就记录一次，中途失败下次也不会重复发送已发出的
        os.makedirs(os.path.dirname(state) or ".", exist_ok=True)
        with open(state, "w") as f:
            f.write(str(since))
    if not records:
        os.makedirs(os.path.dirname(state) or ".", exist_ok=True)
        with open(state, "w") as f:
            f.write(str(since))


if __name__ == "__main__":
    main()
