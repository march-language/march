"""Tests for scripts/check-explainer-budget.py. Run: python3 test/explainer/test_budget.py"""
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("check_explainer_budget", ROOT / "scripts" / "check-explainer-budget.py")
budget = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(budget)


class Budget(unittest.TestCase):
    def test_counts_words_outside_code_and_liquid(self):
        page = ("## One\n\nfour words of prose\n\n```march\nignored code here\n```\n"
                "{{ site.data.x }}\n<div class=\"mx-step\" data-state=\"a\">two words</div>\n")
        self.assertEqual(budget.count(page), {"One": {"words": 6, "cards": 1}})

    def test_front_matter_comments_and_drawers_do_not_count(self):
        page = ("---\ntitle: Many words in the front matter\n---\n"
                "<!-- a hand-written comment -->\n## One\n\nthree real words\n"
                "<details><summary>How we counted</summary>a long derivation nobody must read</details>\n")
        self.assertEqual(budget.count(page), {"One": {"words": 3, "cards": 0}})

    def test_text_before_the_first_heading_is_counted_as_the_opening(self):
        self.assertEqual(budget.count("two words\n\n## One\n\nthree more words\n"),
                         {"(opening)": {"words": 2, "cards": 0}, "One": {"words": 3, "cards": 0}})

    def test_over_budget_exits_one(self):
        with tempfile.TemporaryDirectory() as d:
            page = Path(d) / "long.md"
            page.write_text("## One\n\n" + "word " * 50 + "\n")
            self.assertEqual(budget.main([str(page), "--max-words", "5"]), 1)
            self.assertEqual(budget.main([str(page), "--max-words", "50"]), 0)

    def test_too_many_cards_exits_one(self):
        with tempfile.TemporaryDirectory() as d:
            page = Path(d) / "cards.md"
            page.write_text("## One\n\n" + '<div class="mx-step" data-state="a">x</div>\n' * 3)
            self.assertEqual(budget.main([str(page), "--max-cards", "2"]), 1)


class PageLint(unittest.TestCase):
    def test_no_generated_number_starts_a_line_before_a_full_stop(self):
        # `{{ n }}. Text` at the start of a line renders as "64. Text", which Markdown
        # turns into a numbered list and the sentence into its first item.
        import re
        page = (ROOT / "docs" / "protocol-to-cluster.md").read_text()
        bad = [l for l in page.splitlines() if re.match(r"^\{\{[^}]*\}\}[.)]\s", l)]
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
