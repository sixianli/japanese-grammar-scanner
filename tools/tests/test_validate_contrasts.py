import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["zh-Hant", "en", "ko", "es", "vi", "my"]

POINTS = [
    {"id": "node", "title": "〜ので", "senses": [{"label": "原因", "meaning": "客观说明原因", "examples": [{"ja": "雨なので行かない。", "zh": "因为下雨不去。"}]}],
     "patterns": ["ので"], "scenes": {}},
    {"id": "kara-from", "title": "〜から", "senses": [{"label": "原因", "meaning": "主观说明原因", "examples": [{"ja": "暑いから窓を開けよう。", "zh": "热，开窗吧。"}]}],
     "patterns": ["から"], "scenes": {}},
    {"id": "mou-ta-already", "title": "もう〜た", "senses": [{"label": "已经", "meaning": "已经", "examples": [{"ja": "もう食べた。", "zh": "已经吃了。"}]}],
     "patterns": ["もう"], "scenes": {}},
]

ITEM = {
    "id": "kara-from",
    "diff": "ので 客观；から 主观。",
    "this": [{"ja": "雨:あめ|な|*ので|、|中止:ちゅうし|です|。", "tag": "客观", "tr": "因为下雨，取消了。"}],
    "that": [{"ja": "雨:あめ|だ|*から|、|~やめよう|。", "tag": "主观", "tr": "下雨了，别去了。"}],
    "explain": "句末是「やめよう」这类劝诱时只能用 から。",
}
BASE = [
    {"id": "node", "groups": [{"kind": "meaning", "note": "都表示原因「因为……」", "items": [ITEM]}]},
    {"id": "kara-from", "groups": []},
    {"id": "mou-ta-already", "groups": []},
]


def localized(explain):
    item = {"id": "kara-from", "diff": "ので is objective; から is subjective.",
            "this": [{"tag": "objective", "tr": "It was cancelled because of rain."}],
            "that": [{"tag": "subjective", "tr": "It's raining, let's not go."}],
            "explain": explain}
    return [{"id": "node", "groups": [{"kind": "meaning", "note": "Both mean “because”.", "items": [item]}]},
            {"id": "kara-from", "groups": []}, {"id": "mou-ta-already", "groups": []}]


class ValidateContrastsTests(unittest.TestCase):
    def run_validator(self, base, loc):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root)
        os.makedirs(os.path.join(root, "tools"))
        shutil.copy(os.path.join(TOOLS, "validate_contrasts.py"), os.path.join(root, "tools"))
        grammar = os.path.join(root, "JapaneseGrammarScanner", "Resources", "Grammar")
        cdir = os.path.join(grammar, "contrasts")
        os.makedirs(cdir)
        with open(os.path.join(grammar, "grammar_n5.json"), "w", encoding="utf-8") as fh:
            json.dump(POINTS, fh, ensure_ascii=False)
        with open(os.path.join(cdir, "contrasts.json"), "w", encoding="utf-8") as fh:
            json.dump({"points": base}, fh, ensure_ascii=False)
        for lang in LANGS:
            with open(os.path.join(cdir, f"contrasts_{lang}.json"), "w", encoding="utf-8") as fh:
                json.dump({"points": loc}, fh, ensure_ascii=False)
        res = subprocess.run([sys.executable, os.path.join(root, "tools", "validate_contrasts.py")],
                             capture_output=True, text=True)
        return res.returncode, res.stdout

    def test_valid_data_passes(self):
        code, out = self.run_validator(BASE, localized("A sentence ending in 「やめよう」 needs から."))
        self.assertEqual(code, 0, out)

    def test_grammar_point_without_contrast_entry_is_reported(self):
        base = [p for p in copy.deepcopy(BASE) if p["id"] != "mou-ta-already"]
        loc = [p for p in localized("「やめよう」 needs から.") if p["id"] != "mou-ta-already"]
        code, out = self.run_validator(base, loc)
        self.assertEqual(code, 1)
        self.assertIn("mou-ta-already", out)
        self.assertIn("没有相近语法条目", out)

    def test_translation_that_drops_the_cue_word_is_reported(self):
        code, out = self.run_validator(BASE, localized("Use から when the sentence ends in an invitation."))
        self.assertEqual(code, 1)
        self.assertIn("contrasts_en.json", out)
        self.assertIn("やめよう", out)


if __name__ == "__main__":
    unittest.main()
