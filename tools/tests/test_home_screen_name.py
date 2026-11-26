import importlib.util
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = importlib.util.spec_from_file_location("check_strings", os.path.join(ROOT, "tools", "check_strings.py"))
check_strings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_strings)


def catalog(**names):
    return {"strings": {"CFBundleDisplayName": {"localizations": {
        lang.replace("_", "-"): {"stringUnit": {"state": "translated", "value": v}} for lang, v in names.items()}}}}


class HomeScreenNameTests(unittest.TestCase):
    def repo_catalog(self):
        return json.load(open(check_strings.INFO_PLIST, encoding="utf-8"))

    def test_repository_home_screen_names_all_fit(self):
        self.assertEqual(check_strings.home_screen_name_problems(self.repo_catalog()), [])

    def test_traditional_chinese_home_screen_name_uses_bunpo_wording(self):
        names = self.repo_catalog()["strings"]["CFBundleDisplayName"]["localizations"]
        self.assertEqual(names["zh-Hant"]["stringUnit"]["value"], "日語文法速查")

    def test_name_truncated_on_iphone_se_is_rejected(self):
        problems = check_strings.home_screen_name_problems(catalog(en="Japanese Grammar", zh_Hans="日语语法速查"))
        self.assertEqual(len(problems), 1)
        self.assertIn("Japanese Grammar", problems[0])

    def test_name_with_squeezed_spaces_on_iphone_se_is_rejected(self):
        self.assertEqual(len(check_strings.home_screen_name_problems(catalog(en="JLPT Grammar"))), 1)


if __name__ == "__main__":
    unittest.main()
