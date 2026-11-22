import copy
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import review_contrasts as rc

POINTS = {
    "node": {"id": "node", "title": "〜ので", "senses": [{"label": "因为（客观）", "meaning": "客观说明原因"}]},
    "kara-from": {"id": "kara-from", "title": "〜から", "senses": [{"label": "因为（主观）", "meaning": "主观说明原因"}]},
}
BASE = [{
    "id": "node",
    "groups": [{
        "kind": "meaning",
        "note": "都表示原因「因为……」",
        "items": [{
            "id": "kara-from",
            "diff": "ので 客观；から 主观。",
            "this": [{"ja": "雨:あめ|な|*ので|、|中止:ちゅうし|です|。", "tag": "客观", "tr": "因为下雨，取消了。"}],
            "that": [{"ja": "雨:あめ|だ|*から|、|~やめよう|。", "tag": "主观", "tr": "下雨了，别去了。"}],
            "explain": "句末是「やめよう」这类劝诱时只能用 から。",
        }],
    }],
}]


def passing_records(base):
    return {key: {"hash": rc.content_hash(payload), "verdict": "pass", "reason": "ok",
                  "final": {"hash": rc.content_hash(payload), "verdict": "pass", "reason": "ok"}}
            for key, payload in rc.review_items(base, POINTS)}


class GateTests(unittest.TestCase):
    def test_item_without_review_record_blocks_release(self):
        problems = rc.gate_problems(BASE, POINTS, {})

        self.assertEqual(len(problems), 1)
        self.assertIn("node/meaning/kara-from", problems[0])

    def test_item_with_matching_pass_record_is_allowed(self):
        records = passing_records(BASE)

        self.assertEqual(rc.gate_problems(BASE, POINTS, records), [])

    def test_editing_an_example_after_review_invalidates_the_record(self):
        records = passing_records(BASE)
        edited = copy.deepcopy(BASE)
        edited[0]["groups"][0]["items"][0]["that"][0]["tr"] = "下雨了，咱们别去了。"

        problems = rc.gate_problems(edited, POINTS, records)

        self.assertEqual(len(problems), 1)
        self.assertIn("node/meaning/kara-from", problems[0])

    def test_editing_the_group_note_invalidates_the_record(self):
        records = passing_records(BASE)
        edited = copy.deepcopy(BASE)
        edited[0]["groups"][0]["note"] = "都表示原因"

        self.assertEqual(len(rc.gate_problems(edited, POINTS, records)), 1)

    def test_changing_the_target_pages_senses_invalidates_the_record(self):
        records = passing_records(BASE)
        points = copy.deepcopy(POINTS)
        points["kara-from"]["senses"].append({"label": "从（起点）", "meaning": "表示起点"})

        self.assertEqual(len(rc.gate_problems(BASE, points, records)), 1)

    def test_final_review_fail_blocks_release_even_if_first_pass_passed(self):
        records = passing_records(BASE)
        for r in records.values():
            r["final"]["verdict"] = "fail"

        problems = rc.gate_problems(BASE, POINTS, records)

        self.assertEqual(len(problems), 1)
        self.assertIn("不通过", problems[0])


class FinalReviewTests(unittest.TestCase):
    def test_first_pass_without_final_review_blocks_release(self):
        records = passing_records(BASE)
        for r in records.values():
            del r["final"]

        problems = rc.gate_problems(BASE, POINTS, records)

        self.assertEqual(len(problems), 1)
        self.assertIn("最终把关", problems[0])

    def test_final_pass_overrides_a_first_pass_fail(self):
        records = passing_records(BASE)
        for r in records.values():
            r["verdict"] = "fail"

        self.assertEqual(rc.gate_problems(BASE, POINTS, records), [])

    def test_final_review_of_older_content_is_not_accepted(self):
        records = passing_records(BASE)
        for r in records.values():
            r["final"]["hash"] = "older-content"

        self.assertEqual(len(rc.gate_problems(BASE, POINTS, records)), 1)



class ApplyFinalTests(unittest.TestCase):
    def test_final_verdict_is_recorded_against_the_reviewed_content(self):
        records = passing_records(BASE)
        for r in records.values():
            del r["final"]

        errors = rc.apply_final(BASE, POINTS, records, [
            {"key": "node/meaning/kara-from", "verdict": "pass", "reason": "同一个「因为」"}])

        self.assertEqual(errors, [])
        self.assertEqual(rc.gate_problems(BASE, POINTS, records), [])

    def test_final_verdict_for_content_changed_since_first_pass_is_refused(self):
        records = passing_records(BASE)
        edited = copy.deepcopy(BASE)
        edited[0]["groups"][0]["items"][0]["diff"] = "改过的区别"

        errors = rc.apply_final(edited, POINTS, records, [
            {"key": "node/meaning/kara-from", "verdict": "pass", "reason": "ok"}])

        self.assertEqual(len(errors), 1)
        self.assertEqual(len(rc.gate_problems(edited, POINTS, records)), 1)

    def test_final_verdict_for_unknown_item_is_refused(self):
        records = passing_records(BASE)

        errors = rc.apply_final(BASE, POINTS, records, [
            {"key": "node/meaning/no-such-item", "verdict": "pass", "reason": "ok"}])

        self.assertEqual(len(errors), 1)

    def test_verdict_other_than_pass_or_fail_is_refused(self):
        records = passing_records(BASE)

        errors = rc.apply_final(BASE, POINTS, records, [
            {"key": "node/meaning/kara-from", "verdict": "ok", "reason": "ok"}])

        self.assertEqual(len(errors), 1)


class RunTests(unittest.TestCase):
    def test_interrupted_run_keeps_reviews_already_finished(self):
        import tempfile
        jobs = [("a", {"n": 1}), ("b", {"n": 2})]
        calls = []

        def fake_call(payload):
            calls.append(payload["n"])
            if payload["n"] == 2:
                raise KeyboardInterrupt
            return {"verdict": "pass", "problems": []}, {}

        original = rc.call_model
        rc.call_model = fake_call
        path = os.path.join(tempfile.mkdtemp(), "records.json")
        try:
            with self.assertRaises(KeyboardInterrupt):
                rc.review_and_record(jobs, {}, workers=1, path=path)
        finally:
            rc.call_model = original
        saved = rc.load_records(path)
        self.assertEqual(saved["a"]["verdict"], "pass")
        self.assertEqual(saved["a"]["hash"], rc.content_hash({"n": 1}))
        self.assertNotIn("b", saved)


if __name__ == "__main__":
    unittest.main()
