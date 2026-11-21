import os
import subprocess
import sys
import tempfile
import textwrap
import unittest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)

import check_e2e_ran_all
import e2e_shards

SWIFT = textwrap.dedent("""
    final class DetailTests: E2ETestCase {
        func testTitleBar() {
        }
        func testFavorite() {
        }
    }
    final class SearchTests: E2ETestCase {
        func testNoResults() {
        }
    }
""")


def passed_line(cls, method):
    return f"Test Case '-[JapaneseGrammarScannerUITests.{cls} {method}]' passed (3.1 seconds).\n"


class E2ESelectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tests_dir = os.path.join(self.tmp.name, "JapaneseGrammarScannerUITests")
        os.makedirs(tests_dir)
        with open(os.path.join(tests_dir, "Tests.swift"), "w", encoding="utf-8") as f:
            f.write(SWIFT)
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def write_log(self, text):
        path = os.path.join(self.tmp.name, "e2e.log")
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def test_selection_of_class_and_method_becomes_one_group(self):
        groups, errors = e2e_shards.select("DetailTests/testTitleBar, SearchTests", self.root)

        self.assertEqual(errors, [])
        self.assertEqual(e2e_shards.matrix(groups), {"include": [{
            "shard": 1,
            "only": "-only-testing:JapaneseGrammarScannerUITests/DetailTests/testTitleBar "
                    "-only-testing:JapaneseGrammarScannerUITests/SearchTests",
        }]})

    def test_unknown_class_is_rejected(self):
        _, errors = e2e_shards.select("DetailTest", self.root)

        self.assertEqual(len(errors), 1)
        self.assertIn("DetailTest", errors[0])

    def test_unknown_method_is_rejected(self):
        _, errors = e2e_shards.select("DetailTests/testTitle", self.root)

        self.assertEqual(len(errors), 1)
        self.assertIn("DetailTests/testTitle", errors[0])

    def test_dot_separator_is_rejected(self):
        _, errors = e2e_shards.select("DetailTests.testTitleBar", self.root)

        self.assertEqual(len(errors), 1)

    def test_selection_with_no_names_is_rejected(self):
        _, errors = e2e_shards.select(" , ", self.root)

        self.assertEqual(len(errors), 1)

    def test_selected_tests_all_passed(self):
        log = self.write_log(passed_line("DetailTests", "testTitleBar") + passed_line("SearchTests", "testNoResults"))

        missing = check_e2e_ran_all.missing(log, "DetailTests/testTitleBar,SearchTests", self.root)

        self.assertEqual(missing, [])

    def test_selected_test_without_pass_record_is_missing(self):
        log = self.write_log(passed_line("DetailTests", "testFavorite"))

        missing = check_e2e_ran_all.missing(log, "DetailTests", self.root)

        self.assertEqual(missing, ["DetailTests.testTitleBar"])

    def test_selected_test_that_ran_zero_times_is_missing(self):
        log = self.write_log("** TEST EXECUTE SUCCEEDED **\n")

        missing = check_e2e_ran_all.missing(log, "SearchTests/testNoResults", self.root)

        self.assertEqual(missing, ["SearchTests.testNoResults"])

    def test_full_run_requires_every_declared_test(self):
        log = self.write_log(passed_line("DetailTests", "testTitleBar") + passed_line("SearchTests", "testNoResults"))

        missing = check_e2e_ran_all.missing(log, "", self.root)

        self.assertEqual(missing, ["DetailTests.testFavorite"])

    def test_rerun_value_lists_missing_tests_for_dispatch_input(self):
        self.assertEqual(
            check_e2e_ran_all.rerun_value(["DetailTests.testTitleBar", "SearchTests.testNoResults"]),
            "DetailTests/testTitleBar,SearchTests/testNoResults",
        )

    def test_command_line_rejects_unknown_selection_with_exit_code(self):
        result = subprocess.run(
            [sys.executable, os.path.join(TOOLS, "e2e_shards.py"), "--only", "NoSuchTests"],
            capture_output=True, text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NoSuchTests", result.stderr)


if __name__ == "__main__":
    unittest.main()
