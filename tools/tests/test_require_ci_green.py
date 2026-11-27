import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from require_ci_green import problems


def run(name, suite, started, conclusion="success", status="completed"):
    return {"name": name, "check_suite": {"id": suite}, "started_at": started,
            "status": status, "conclusion": conclusion, "html_url": f"https://example.invalid/{suite}/{name}"}


FULL_PASS = [
    run("validate-data", 1, "2026-11-26T22:33:00Z"),
    run("build-and-test", 1, "2026-11-26T23:00:00Z"),
    run("e2e", 1, "2026-11-27T01:42:00Z"),
]

TARGETED_PASS = [
    run("validate-data", 2, "2026-11-27T02:07:00Z"),
    run("build-and-test", 2, "2026-11-27T02:07:30Z", conclusion="skipped"),
    run("e2e", 2, "2026-11-27T02:52:00Z"),
]


class RequireCiGreenTests(unittest.TestCase):
    def test_full_run_with_all_jobs_passing_is_allowed(self):
        self.assertEqual(problems(FULL_PASS), [])

    def test_later_targeted_run_does_not_hide_earlier_full_pass(self):
        self.assertEqual(problems(FULL_PASS + TARGETED_PASS), [])

    def test_targeted_run_alone_is_rejected(self):
        bad = problems(TARGETED_PASS)
        self.assertEqual(len(bad), 1)
        self.assertIn("build-and-test", bad[0])

    def test_jobs_from_different_runs_cannot_be_combined(self):
        mixed = [
            run("validate-data", 1, "2026-11-26T22:33:00Z"),
            run("build-and-test", 1, "2026-11-26T23:00:00Z"),
            run("e2e", 1, "2026-11-27T01:42:00Z", conclusion="failure"),
            run("e2e", 2, "2026-11-27T02:52:00Z"),
        ]
        self.assertNotEqual(problems(mixed), [])

    def test_failed_e2e_is_rejected(self):
        bad = problems(FULL_PASS[:2] + [run("e2e", 1, "2026-11-27T01:42:00Z", conclusion="failure")])
        self.assertEqual(len(bad), 1)
        self.assertIn("e2e", bad[0])

    def test_running_job_is_rejected(self):
        bad = problems(FULL_PASS[:2] + [run("e2e", 1, "2026-11-27T01:42:00Z", conclusion=None, status="in_progress")])
        self.assertEqual(len(bad), 1)
        self.assertIn("还在运行", bad[0])

    def test_commit_without_ci_is_rejected(self):
        self.assertEqual(len(problems([])), 3)


if __name__ == "__main__":
    unittest.main()
