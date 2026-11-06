"""Tests for scripts/gen-authority-data.py, the generator behind docs/_data/authority.json.

Run: python3 test/explainer/test_gen_authority.py

They cover the generator's pure parts and the committed data. A fresh run against the
compiler and forge is CI's `--check` step.
"""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("gen_authority_data", ROOT / "scripts" / "gen-authority-data.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

UFW = """# ==> ufw-lab-1.sh <==
#!/bin/sh
ufw allow 22/tcp comment 'ssh (march deploys)'
ufw allow from lab-2 to any port 7946 proto tcp comment 'march cluster from work'
ufw --force enable

# ==> ufw-lab-2.sh <==
ufw allow 22/tcp comment 'ssh (march deploys)'
ufw allow from lab-1 to any port 7946 proto tcp comment 'march cluster from ingress'
ufw allow from lab-3 to any port 7947 proto tcp comment 'march control from lab-3'
"""


class Reach(unittest.TestCase):
    def test_classes(self):
        self.assertEqual(gen.reach_class([]), "none")
        self.assertEqual(gen.reach_class(["IO.Console", "IO.Clock", "IO.Spawn", "IO.Mut"]), "inside")
        self.assertEqual(gen.reach_class(["Session.Live"]), "inside")
        self.assertEqual(gen.reach_class(["IO.Console", "IO.FileWrite"]), "outside")
        self.assertEqual(gen.reach_class(["IO.NetConnect.TLS"]), "outside")
        self.assertEqual(gen.reach_class(["IO"]), "outside")
        # a capability whose name merely starts like an outside one is not one
        self.assertEqual(gen.reach_class(["IO.ProcessX"]), "inside")

    def test_module_facts_groups_and_counts(self):
        caps = [{"module": "B", "needs": ["IO.FileWrite"]}, {"module": "A", "needs": []},
                {"module": "C", "needs": ["IO.Mut"]}, {"module": "D"}]
        facts = gen.module_facts(caps, {"B"})
        self.assertEqual(facts["total"], 4)
        self.assertEqual(facts["classes"], {"none": 2, "inside": 1, "outside": 1})
        self.assertEqual([m["name"] for m in facts["list"]], ["A", "D", "C", "B"])
        self.assertEqual([m["name"] for m in facts["own"]], ["B"])


class Topology(unittest.TestCase):
    def test_firewall_rules(self):
        rules = gen.firewall_rules(UFW)
        self.assertEqual(rules["lab-1"], [{"from": "lab-2", "port": 7946}])
        self.assertEqual(rules["lab-2"], [{"from": "lab-1", "port": 7946}, {"from": "lab-3", "port": 7947}])

    def test_added_caps(self):
        before = {"a": ["IO.Clock"], "b": ["IO.Mut"]}
        after = {"a": ["IO.Clock", "IO.NetConnect"], "b": ["IO.Mut"], "c": ["IO.Console"]}
        self.assertEqual(gen.added_caps(before, after), {"a": ["IO.NetConnect"], "b": [], "c": ["IO.Console"]})

    def test_toml_excerpt_drops_comments_and_separates_tables(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "t.toml"
            p.write_text("# top\n[roles]\nx = 1\n\n# why\n[pool.a]\nstart = \"A.start\"\n")
            self.assertEqual(gen.toml_excerpt(p), ["[roles]", "x = 1", "", "[pool.a]", 'start = "A.start"'])


class Excerpts(unittest.TestCase):
    SRC = "-- c\nmod A do\n  needs IO.Clock\n  needs IO.Mut\n\n  fn f() : () do\n    if x do\n      ()\n    end\n  end\nend\n"

    def test_code_only(self):
        self.assertEqual(gen.code_only("-- a\n-- b\n\nmod A do\nend\n"), "mod A do\nend\n")

    def test_block_ends_at_the_matching_end(self):
        self.assertEqual(gen.block(self.SRC, "fn f"), "fn f() : () do\n  if x do\n    ()\n  end\nend\n")

    def test_module_head(self):
        self.assertEqual(gen.module_head(self.SRC, "A"), "mod A do\n  needs IO.Clock\n  needs IO.Mut\n")


class Inputs(unittest.TestCase):
    def test_committed_data_matches_its_inputs(self):
        self.assertTrue(gen.check_inputs(gen.DATA, ROOT),
                        "docs/_data/authority.json is stale: run scripts/gen-authority-data.py")

    def test_fixtures_are_inputs(self):
        names = {str(p.relative_to(ROOT)) for p in gen.input_files(ROOT)}
        for want in ("examples/lab_app/src/lab_app.march", "examples/lab_app/topology.toml",
                     "docs/assets/explainer/authority/gauge-1.1/src/gauge.march",
                     "docs/assets/explainer/authority/programs/ceiling.march"):
            self.assertIn(want, names)

    def test_pinned_phrases_are_still_in_the_docs(self):
        self.assertEqual(set(gen.pinned_facts(ROOT)), {e["key"] for e in gen.PINNED})

    def test_the_line_the_dependency_replaces_is_in_the_lab_app(self):
        self.assertIn(gen.PROBE_LINE, (gen.LAB / "src" / "lab_app.march").read_text())

    def test_the_app_itself_has_no_dependency(self):
        self.assertNotIn("[deps]", (gen.LAB / "forge.toml").read_text())


class Data(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(gen.DATA.read_text())

    def test_no_scratch_path_leaks_into_the_data(self):
        text = gen.DATA.read_text()
        for needle in ("/tmp/", "/var/folders", "/private/", "/Users/", "/home/"):
            self.assertNotIn(needle, text)

    def test_pools_were_derived_by_the_compiler(self):
        for p in self.data["topology"]["pools"]:
            self.assertEqual(p["caps_source"], "compiler")
            self.assertTrue(p["caps"])

    def test_own_modules_are_the_ones_the_source_declares(self):
        declared = set(gen.source_modules(gen.LAB / "src" / "lab_app.march"))
        self.assertTrue({m["name"] for m in self.data["modules"]["own"]} <= declared)
        self.assertIn("Probe", {m["name"] for m in self.data["modules"]["own"]})


if __name__ == "__main__":
    unittest.main()
