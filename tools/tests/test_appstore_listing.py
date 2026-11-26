import copy
import os
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import appstore_listing as al


def png(width, height):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"")) + chunk(b"IEND", b""))


def listing(name="Japanese Grammar Lookup", shots="en"):
    return {"name": name, "subtitle": "JLPT N5-N1 grammar by photo",
            "privacyPolicyUrl": "https://example.com/privacy/", "promotionalText": "Promo",
            "keywords": "nihongo,n2,n3", "description": "Description", "supportUrl": "https://example.com/",
            "marketingUrl": "https://example.com/", "screenshots": shots}


class FakeApi:
    def __init__(self, version_state="PREPARE_FOR_SUBMISSION", existing_shots=None, info_state="PREPARE_FOR_SUBMISSION"):
        self.calls = []
        self.info_state = info_state
        self.parts = []
        self.version_state = version_state
        self.existing_shots = existing_shots or []
        self.next_id = 0
        self.ver_locs = {"zh-Hans": {"id": "vl-zh", "attributes": dict(listing(), locale="zh-Hans")}}

    def new_id(self, prefix):
        self.next_id += 1
        return f"{prefix}{self.next_id}"

    def call(self, method, path, body=None):
        self.calls.append((method, path.split("?")[0], body))
        if method == "GET":
            if path.startswith("/apps?"):
                return {"data": [{"id": "app", "attributes": {"primaryLocale": "zh-Hans"}}]}
            if path == "/apps/app/appInfos":
                return {"data": [{"id": "info", "attributes": {"state": self.info_state}}]}
            if path.startswith("/apps/app/appStoreVersions"):
                return {"data": [{"id": "ver", "attributes": {"appVersionState": self.version_state}}]}
            if path.startswith("/appInfos/info/appInfoLocalizations"):
                return {"data": [{"id": "il-zh", "attributes": {"locale": "zh-Hans", "name": "旧名", "subtitle": "副标题",
                                                                  "privacyPolicyUrl": "https://example.com/privacy/"}}]}
            if path.startswith("/appStoreVersions/ver/appStoreVersionLocalizations"):
                return {"data": [copy.deepcopy(v) for v in self.ver_locs.values()]}
            if path == "/appStoreVersionLocalizations/vl-zh/appScreenshotSets":
                return {"data": [{"id": "set-zh", "attributes": {"screenshotDisplayType": al.DISPLAY_TYPE}}]}
            if path.endswith("/appScreenshotSets"):
                return {"data": []}
            if path == "/appScreenshotSets/set-zh/appScreenshots":
                return {"data": [{"id": f"old{i}", "attributes": {"sourceFileChecksum": c}}
                                 for i, c in enumerate(self.existing_shots)]}
            raise AssertionError(f"unexpected GET {path}")
        if method == "POST" and path == "/appScreenshots":
            size = body["data"]["attributes"]["fileSize"]
            return {"data": {"id": self.new_id("shot"), "attributes": {"uploadOperations": [
                {"method": "PUT", "url": "https://upload.example/1", "offset": 0, "length": size // 2, "requestHeaders": []},
                {"method": "PUT", "url": "https://upload.example/2", "offset": size // 2, "length": size - size // 2,
                 "requestHeaders": []}]}}}
        if method == "POST" and path == "/appStoreVersionLocalizations":
            locale = body["data"]["attributes"]["locale"]
            if locale in self.ver_locs:
                raise SystemExit(f"HTTP 409 Entity with locale: {locale} already exists")
            created = {"id": self.new_id("vl-"), "attributes": dict(body["data"]["attributes"])}
            self.ver_locs[locale] = created
            return {"data": copy.deepcopy(created)}
        if method == "POST":
            created = {"id": self.new_id(path.strip("/")), "attributes": body["data"]["attributes"]}
            if path == "/appInfoLocalizations":
                locale = body["data"]["attributes"]["locale"]
                self.ver_locs.setdefault(locale, {"id": self.new_id("vl-auto-"), "attributes": {"locale": locale}})
            return {"data": created}
        if method == "PATCH" and path.startswith("/appStoreVersionLocalizations/"):
            loc = next(v for v in self.ver_locs.values() if v["id"] == body["data"]["id"])
            loc["attributes"].update(body["data"]["attributes"])
            return {"data": copy.deepcopy(loc)}
        if method == "PATCH" and "relationships" not in path:
            return {"data": {"id": body["data"]["id"], "attributes": body["data"]["attributes"]}}
        return {}

    def put_part(self, operation, data):
        self.parts.append((operation["url"], len(data)))

    def writes(self):
        return [(m, p) for m, p, _ in self.calls if m != "GET"]


class AppStoreListingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.shots = self.tmp.name
        for folder in ("en", "zh-Hans"):
            os.makedirs(os.path.join(self.shots, folder))
            for i in (1, 2):
                with open(os.path.join(self.shots, folder, f"{i}.png"), "wb") as f:
                    f.write(png(1206, 2622) + bytes([i]) + folder.encode())

    def tearDown(self):
        self.tmp.cleanup()

    def listings(self):
        return {loc: listing(shots="zh-Hans" if loc == "zh-Hans" else "en") for loc in al.REQUIRED_LOCALES}

    def test_repository_listings_pass(self):
        self.assertEqual(al.check(al.load_listings()), [])

    def test_every_store_language_is_required(self):
        listings = self.listings()
        del listings["en-GB"]
        problems = al.check(listings, self.shots)
        self.assertEqual(len(problems), 1)
        self.assertIn("en-GB", problems[0])

    def test_overlong_subtitle_is_rejected(self):
        listings = self.listings()
        listings["ko"]["subtitle"] = "x" * 31
        problems = al.check(listings, self.shots)
        self.assertTrue(any("ko" in p and "subtitle" in p and "30" in p for p in problems))

    def test_keyword_already_in_subtitle_is_rejected(self):
        listings = self.listings()
        listings["vi"]["keywords"] = "nihongo,JLPT,n3"
        problems = al.check(listings, self.shots)
        self.assertEqual(len(problems), 1)
        self.assertIn("JLPT", problems[0])

    def test_burmese_script_is_rejected_because_app_store_refuses_it(self):
        listings = self.listings()
        listings["en-GB"]["description"] = "Explanations in English, \u1019\u103c\u1014\u103a\u1019\u102c and more"
        problems = al.check(listings, self.shots)
        self.assertEqual(len(problems), 1)
        self.assertIn("en-GB", problems[0])
        self.assertIn("description", problems[0])

    def test_large_display_screenshot_size_is_rejected(self):
        with open(os.path.join(self.shots, "en", "1.png"), "wb") as f:
            f.write(png(1320, 2868))
        problems = al.check(self.listings(), self.shots)
        self.assertTrue(problems)
        self.assertTrue(all("1320" in p for p in problems))

    def test_dry_run_writes_nothing(self):
        api = FakeApi()
        log = []
        al.sync(api, "bundle", "1.4", self.listings(), apply=False, log=log.append, screenshot_dir=self.shots)
        self.assertEqual(api.writes(), [])
        self.assertEqual(api.parts, [])
        self.assertTrue(any(line.startswith("zh-Hans：App 信息") and "更新 name" in line for line in log))
        self.assertTrue(any(line.startswith("ko：App 信息") and "新建" in line for line in log))

    def test_upload_patches_only_changed_fields_and_creates_missing_languages(self):
        zh_shots = [al.md5(p) for p in al.screenshot_files({"screenshots": "zh-Hans"}, self.shots)]
        api = FakeApi(existing_shots=zh_shots)
        al.sync(api, "bundle", "1.4", self.listings(), apply=True, log=lambda _: None, screenshot_dir=self.shots)
        patches = [(p, b) for m, p, b in api.calls if m == "PATCH" and p == "/appInfoLocalizations/il-zh"]
        self.assertEqual(len(patches), 1)
        self.assertEqual(set(patches[0][1]["data"]["attributes"]), {"name", "subtitle"})
        self.assertFalse(any(p == "/appStoreVersionLocalizations/vl-zh" for m, p, _ in api.calls if m == "PATCH"))
        self.assertEqual(set(api.ver_locs), al.REQUIRED_LOCALES)
        for locale, loc in api.ver_locs.items():
            self.assertEqual({f: loc["attributes"].get(f) for f in al.VERSION_FIELDS},
                             {f: self.listings()[locale][f] for f in al.VERSION_FIELDS})
        self.assertFalse(any(p.startswith("/appScreenshots/old") for _, p in api.writes()))

    def test_new_language_screenshots_are_uploaded_committed_and_ordered(self):
        api = FakeApi()
        listings = {"zh-Hans": listing(shots="zh-Hans"), "ko": listing(shots="en")}
        al.sync(api, "bundle", "1.4", listings, apply=True, log=lambda _: None, screenshot_dir=self.shots)
        sets = [b for m, p, b in api.calls if m == "POST" and p == "/appScreenshotSets"]
        self.assertEqual([s["data"]["attributes"]["screenshotDisplayType"] for s in sets], [al.DISPLAY_TYPE])
        commits = [b["data"]["attributes"] for m, p, b in api.calls
                   if m == "PATCH" and p.startswith("/appScreenshots/shot")]
        files = al.screenshot_files({"screenshots": "en"}, self.shots)
        self.assertIn({"uploaded": True, "sourceFileChecksum": al.md5(files[0])}, commits)
        self.assertEqual(len(api.parts), 2 * 4)
        orders = [b for m, p, b in api.calls if m == "PATCH" and p.endswith("/relationships/appScreenshots")]
        self.assertEqual(len(orders), 2)
        self.assertEqual(len(orders[-1]["data"]), 2)

    def test_changed_screenshots_replace_the_old_ones(self):
        api = FakeApi(existing_shots=["stale"])
        al.sync(api, "bundle", "1.4", {"zh-Hans": listing(shots="zh-Hans")}, apply=True, log=lambda _: None,
                screenshot_dir=self.shots)
        self.assertIn(("DELETE", "/appScreenshots/old0"), api.writes())
        self.assertEqual(sum(1 for m, p in api.writes() if (m, p) == ("POST", "/appScreenshots")), 2)

    def test_submitted_version_is_not_touched(self):
        api = FakeApi(version_state="WAITING_FOR_REVIEW")
        with self.assertRaises(SystemExit):
            al.sync(api, "bundle", "1.4", self.listings(), apply=True, log=lambda _: None, screenshot_dir=self.shots)
        self.assertEqual(api.writes(), [])


    def test_dry_run_without_editable_version_compares_with_live_listing(self):
        api = FakeApi(version_state="READY_FOR_DISTRIBUTION", info_state="READY_FOR_DISTRIBUTION")
        log = []
        al.sync(api, "bundle", "1.4", self.listings(), apply=False, log=log.append, screenshot_dir=self.shots)
        self.assertEqual(api.writes(), [])
        self.assertTrue(any("线上" in line for line in log))
        self.assertTrue(any(line.startswith("zh-Hans：App 信息") and "更新 name" in line for line in log))

    def test_upload_without_editable_version_is_refused(self):
        api = FakeApi(version_state="READY_FOR_DISTRIBUTION", info_state="READY_FOR_DISTRIBUTION")
        with self.assertRaises(SystemExit):
            al.sync(api, "bundle", "1.4", self.listings(), apply=True, log=lambda _: None, screenshot_dir=self.shots)
        self.assertEqual(api.writes(), [])


if __name__ == "__main__":
    unittest.main()
