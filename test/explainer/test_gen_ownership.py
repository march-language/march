"""Tests for scripts/gen-ownership-data.py, the generator behind docs/_data/ownership.json.

Run: python3 test/explainer/test_gen_ownership.py

They cover the generator's pure parts (the excerpt cutter, the warning stripper, the
trace folding, the token-line finder) and the committed data. A fresh run against the
compiler is CI's `--check` step.
"""
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("gen_ownership_data", ROOT / "scripts" / "gen-ownership-data.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

SRC = """-- comment
mod Own do
  needs IO.Console

  type Tree = Leaf(Int) | Node(Tree, Tree)

  @[no_alloc]
  fn inc_leaves(t : Tree) : Tree do
    match t do
    Leaf(n)    -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
    end
  end

  fn sum_leaves(t : Tree) : Int do
    0
  end

  fn main() : Int do
    linear let t : Tree = Leaf(1)
    let t2 = inc_leaves(t)
    sum_leaves(t2) - sum_leaves(t)
  end
end
"""

WHY = """No copies found: every value passed to a function that reuses it in place is its last use.
-- WARNING: RECURSION ----------------------- owned.march

Function `inc_leaves` is structurally recursive but not tail-recursive. [non_tail_recursion]

10 |     Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
                            ^^^^^^^^^^^^^



-- WARNING: COPY --------------------------- shared.march

`inc_leaves` builds a new copy instead of reusing `t` in place. [copy_shared]

27 |     let t2 = inc_leaves(t)
                             ^


"""

TRACE = """{"event":"alloc","addr":"0x10","size":24,"rc":1,"tag":0,"site":0,"ts_ns":1}
{"event":"alloc","addr":"0x20","size":24,"rc":1,"tag":0,"site":0,"ts_ns":2}
{"event":"alloc","addr":"0x30","size":32,"rc":1,"tag":0,"site":1,"ts_ns":3}

{"event":"inc_ref","addr":"0x30","size":0,"rc":2,"tag":0,"site":2,"ts_ns":4}
{"event":"alloc","addr":"0x40","size":24,"rc":1,"tag":0,"site":3,"ts_ns":5}
{"event":"alloc","addr":"0x50","size":24,"rc":1,"tag":-1,"site":4,"ts_ns":6}
{"event":"alloc","addr":"0x60","size":64,"rc":1,"tag":-7,"site":5,"ts_ns":7}
{"event":"alloc","addr":"0x70","size":24,"rc":1,"tag":0,"site":6,"ts_ns":8}
{"event":"dec_ref","addr":"0x30","size":0,"rc":1,"tag":0,"site":-1,"ts_ns":9}
{"event":"free","addr":"0x10","size":0,"rc":0,"tag":0,"site":7,"ts_ns":10}
{"event":"immortal","addr":"0x50","size":0,"rc":0,"tag":-1,"site":4,"ts_ns":11}
"""
SITES = ["build#1:march_alloc", "build#7:march_alloc", "inc_leaves#4:march_incrc", "inc_leaves#3:march_alloc",
         "march_main#1:march_int_to_string", "$lam0#4:march_task_spawn_thunk",
         "go$apply$0_List_chunks_List_Tree_Int#5:march_alloc", "sum_leaves$own0#1:march_decrc_local"]


class Excerpt(unittest.TestCase):
    def test_cuts_the_named_functions_with_their_attribute_and_dedents(self):
        self.assertEqual(gen.excerpt(SRC, ["inc_leaves"]),
                         "@[no_alloc]\nfn inc_leaves(t : Tree) : Tree do\n  match t do\n"
                         "  Leaf(n)    -> Leaf(n + 1)\n  Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))\n"
                         "  end\nend\n")

    def test_joins_functions_in_the_order_asked_with_one_blank_line(self):
        text = gen.excerpt(SRC, ["main", "sum_leaves"])
        self.assertEqual(text, "fn main() : Int do\n  linear let t : Tree = Leaf(1)\n  let t2 = inc_leaves(t)\n"
                               "  sum_leaves(t2) - sum_leaves(t)\nend\n\nfn sum_leaves(t : Tree) : Int do\n  0\nend\n")

    def test_lines_remember_their_source_line(self):
        lines = gen.excerpt_lines(SRC, ["sum_leaves", "main"])
        self.assertEqual(lines[0], (15, "fn sum_leaves(t : Tree) : Int do"))
        self.assertEqual(lines[3], (None, ""))
        self.assertEqual(gen.excerpt_line_of(lines, 20), 6)      # `linear let t`
        self.assertIsNone(gen.excerpt_line_of(lines, 8))         # inside inc_leaves, not shown

    def test_a_function_whose_name_is_a_prefix_of_another_is_not_confused(self):
        self.assertTrue(gen.excerpt(SRC, ["sum_leaves"]).startswith("fn sum_leaves("))


class Diagnostics(unittest.TestCase):
    def test_strip_warnings_drops_recursion_blocks_and_keeps_the_rest(self):
        kept = gen.strip_warnings(WHY)
        self.assertNotIn("RECURSION", kept)
        self.assertTrue(kept.startswith("No copies found: every value"))
        self.assertIn("-- WARNING: COPY --------------------------- shared.march\n\n`inc_leaves` builds", kept)
        self.assertTrue(kept.endswith("^\n"))
        self.assertNotIn("\n\n\n", kept)

    def test_strip_warnings_drops_clang_and_compiled_lines(self):
        text = ("warning: overriding the module target triple with arm64-apple-macosx26.0.0 [-Woverride-module]\n"
                "1 warning generated.\ncompiled bin\n")
        self.assertEqual(gen.strip_warnings(text), "")
        self.assertEqual(gen.strip_warnings("-- CONTRACT --- a.march\n\nx\n" + text), "-- CONTRACT --- a.march\n\nx\n")

    def test_points_at_slug_and_reason(self):
        out = ("-- CONTRACT ------------------------- contract_bare.march\n\n"
               "`width_bare` is marked @[no_alloc] but allocates. [no_alloc]\n"
               "  In `width_bare`: `int_to_string` allocates.\n\n"
               "10 |   fn width_bare(i : Int) : Int do\n          ^^^^^^^^^^\n")
        self.assertEqual(gen.points_at(out), 10)
        self.assertEqual(gen.slug_of(out), "no_alloc")
        self.assertEqual(gen.reason_of(out), "In `width_bare`: `int_to_string` allocates.")
        self.assertIsNone(gen.points_at("No copies found.\n"))


class Trace(unittest.TestCase):
    def test_fold_counts_per_site_sorted(self):
        per = gen.fold_trace(TRACE.splitlines(), SITES)
        self.assertEqual(list(per), sorted(per))
        self.assertEqual(per["build#1:march_alloc"], {"alloc": 2, "inc": 0, "dec": 0, "free": 0})
        self.assertEqual(per["inc_leaves#4:march_incrc"], {"alloc": 0, "inc": 1, "dec": 0, "free": 0})
        self.assertEqual(per["runtime"], {"alloc": 0, "inc": 0, "dec": 1, "free": 0})
        self.assertEqual(per["sum_leaves$own0#1:march_decrc_local"]["free"], 1)
        self.assertNotIn("immortal", json.dumps(per))

    def test_site_parts(self):
        self.assertEqual(gen.site_parts("inc_leaves#3:march_alloc"), ("inc_leaves", "march_alloc"))
        self.assertEqual(gen.site_parts("march_main#1:march_int_to_string"), ("main", "march_int_to_string"))
        self.assertEqual(gen.site_parts("List.pmap_n$List_Tree$Fn_Tree_Tree$Int#8:march_alloc"),
                         ("List.pmap_n$List_Tree$Fn_Tree_Tree$Int", "march_alloc"))
        self.assertEqual(gen.site_parts("runtime"), ("runtime", None))

    def test_trace_facts_attributes_cells_tasks_and_plumbing(self):
        facts = gen.trace_facts(gen.fold_trace(TRACE.splitlines(), SITES))
        self.assertEqual(facts["allocs"], {"build": 3, "inc_leaves": 1, "main": 0,
                                           "tasks": 1, "plumbing": 1, "total": 7})
        self.assertEqual(facts["incs"], {"build": 0, "inc_leaves": 1, "main": 0})


class Token(unittest.TestCase):
    def test_linear_let_binder_and_each_later_use(self):
        text = gen.excerpt(SRC, ["inc_leaves", "main"])
        # line 1 is `@[no_alloc]`, 2-7 inc_leaves, 8 blank, 9 `fn main`, 10 the binding
        self.assertEqual(gen.token_lines(text), ("linear", 10, [11, 12]))

    def test_the_binder_is_the_last_binding_so_a_linear_parameter_above_does_not_win(self):
        kind, binder, uses = gen.token_lines("fn f(linear t : Tree) : Tree do\n  g(t)\nend\n\n"
                                             "fn main() : Int do\n  linear let t : Tree = Leaf(1)\n  0\nend\n")
        self.assertEqual((kind, binder, uses), ("linear", 6, []))

    def test_affine_parameter_counts_each_use_on_a_line(self):
        kind, binder, uses = gen.token_lines("fn twice(t : affine Tree) : Int do\n  sum(t) + sum(t)\nend\n")
        self.assertEqual((kind, binder, uses), ("affine", 1, [2, 2]))

    def test_t2_and_tree_are_not_uses_of_t(self):
        _, _, uses = gen.token_lines("linear let t : Tree = x\nlet t2 = int_to_string(t2)\nTree\n")
        self.assertEqual(uses, [])


class Inputs(unittest.TestCase):
    def test_committed_data_matches_its_inputs(self):
        self.assertTrue(gen.check_inputs(gen.DATA, ROOT),
                        "docs/_data/ownership.json is stale: run scripts/gen-ownership-data.py")

    def test_fixtures_pinned_files_and_the_script_are_inputs(self):
        names = {str(p.relative_to(ROOT)) for p in gen.input_files(ROOT)}
        for want in ("docs/assets/explainer/ownership/programs/owned.march",
                     "docs/assets/explainer/ownership/programs/contract_caller.march",
                     "specs/lang/memory-model.md", "specs/lang/linear-types.md",
                     "specs/todos/2026-11-04-alloc-bound-contract.md", "scripts/gen-ownership-data.py"):
            self.assertIn(want, names)

    def test_every_excerpt_names_a_fixture(self):
        for name in gen.EXCERPTS:
            self.assertTrue((gen.PROGRAMS / f"{name}.march").exists(), name)
        self.assertEqual(set(gen.EXCERPTS), {p.stem for p in gen.PROGRAMS.glob("*.march")})

    def test_pinned_phrases_are_still_in_the_specs(self):
        self.assertEqual(set(gen.pinned_facts(ROOT)), {e["name"] for e in gen.PINNED} | {"alloc_bound"})


class Data(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(gen.DATA.read_text())

    def test_no_scratch_path_leaks_into_the_data(self):
        text = gen.DATA.read_text()
        for needle in ("/tmp/", "/var/folders", "/private/", "/Users/", "/home/", "ts_ns"):
            self.assertNotIn(needle, text)

    def test_the_tree_and_the_runs_agree(self):
        tree, runs = self.data["tree"], self.data["runs"]
        self.assertEqual(tree["cells"], tree["leaves"] + tree["nodes"])
        for name in gen.RUNS:
            self.assertEqual(runs[name]["allocs"]["build"], tree["cells"], name)
            self.assertEqual(runs[name]["exit"], 0)
        self.assertEqual(runs["owned"]["allocs"]["inc_leaves"], 0)
        self.assertEqual(runs["parallel"]["allocs"]["inc_leaves"], 0)
        self.assertEqual(runs["parallel"]["allocs"]["tasks"], 2)
        self.assertEqual(runs["shared"]["allocs"]["inc_leaves"], tree["cells"])
        self.assertEqual(runs["vault"]["allocs"]["inc_leaves"], tree["cells"])
        self.assertIn("[copy_shared]", runs["shared"]["why_copies"])
        self.assertTrue(runs["vault"]["why_copies"].startswith("No copies found"))

    def test_verdicts_match_exit_codes_and_excerpt_lines(self):
        for key, e in self.data["linear"].items():
            self.assertEqual(e["exit"], 0 if e["verdict"] == "ok" else 1, key)
            n = len(e["excerpt"].splitlines())
            self.assertTrue(1 <= e["binder"] <= n, key)
            for u in e["uses"]:
                self.assertTrue(e["binder"] < u <= n, key)
            if e["verdict"] != "ok":
                self.assertTrue(1 <= e["at"] <= n, key)
                self.assertEqual(e["output"].splitlines()[2], e["headline"], key)
        self.assertEqual(self.data["linear"]["never"]["uses"], [])
        self.assertEqual(len(self.data["linear"]["twice"]["uses"]), 2)

    def test_contracts(self):
        c = self.data["contracts"]
        self.assertEqual(c["candidate"]["code"], "no_alloc_candidate")
        self.assertEqual(c["candidate"]["fix"].strip(), "@[no_alloc]")
        for key in ("pinned", "transient", "caller"):
            self.assertEqual(c[key]["exit"], 0, key)
        for key in ("bare", "boxed"):
            self.assertEqual(c[key]["exit"], 1, key)
            self.assertTrue(c[key]["reason"].startswith("In `"), key)
        self.assertEqual(c["caller"]["allocs"]["inc_leaves"], c["caller"]["tree_cells"])
        self.assertTrue(c["pinned"]["excerpt"].startswith("@[no_alloc]\nfn inc_leaves("))


if __name__ == "__main__":
    unittest.main()
