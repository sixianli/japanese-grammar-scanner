import copy
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import privacy_mirror as pm


def minified(block):
    return re.sub(r'="([\w-]+)"', r"=\1", block).replace("\n", "")


class PrivacyMirrorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.en = pm.english_strings()
        cls.ja = pm.japanese_strings()

    def page(self, lang, cloud=True):
        return "<html><body>" + minified(pm.render(lang, cloud, False, self.en, self.ja)) + "</body></html>"

    def test_generated_pages_match_the_app_in_every_language(self):
        for lang in pm.LANGS:
            with self.subTest(lang=lang):
                self.assertEqual(pm.compare(lang, self.page(lang), True, False, self.en, self.ja), [])

    def test_changed_sentence_is_reported(self):
        page = self.page("en").replace("never uploaded", "sometimes uploaded")
        problems = pm.compare("en", page, True, False, self.en, self.ja)
        self.assertEqual(len(problems), 1)
        self.assertIn("camera", problems[0])

    def test_missing_section_is_reported(self):
        page = self.page("zh").split('<li id=privacy-contact>')[0] + "</ul></body></html>"
        problems = pm.compare("zh", page, True, False, self.en, self.ja)
        self.assertTrue(any("contact" in p and "缺少" in p for p in problems))

    def test_page_for_a_build_without_cloud_does_not_match_a_cloud_build(self):
        problems = pm.compare("zh", self.page("zh", cloud=False), True, False, self.en, self.ja)
        self.assertTrue(any("usage-stats" in p for p in problems))
        self.assertTrue(any("feedback-offline" in p for p in problems))

    def test_stale_last_updated_date_is_reported(self):
        _, updated = pm.sections("ja", True, False, self.en, self.ja)
        page = self.page("ja").replace(updated, "2000-01-01")
        problems = pm.compare("ja", page, True, False, self.en, self.ja)
        self.assertTrue(any("最后更新" in p for p in problems))

    def test_japanese_translated_from_old_chinese_is_rejected(self):
        ja = copy.deepcopy(self.ja)
        ja["camera"]["source_body"] = "旧的中文原文"
        problems = pm.check_translations(self.en, ja)
        self.assertEqual(len(problems), 1)
        self.assertIn("camera", problems[0])

    def test_current_translations_are_complete(self):
        self.assertEqual(pm.check_translations(self.en, self.ja), [])


if __name__ == "__main__":
    unittest.main()
