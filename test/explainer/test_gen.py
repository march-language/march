"""Tests for scripts/gen-explainer-data.py, the generator behind docs/_data/explainer.json.

Run: python3 -m unittest test/explainer/test_gen.py -v
"""
import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
MARCH = os.environ.get("MARCH_BIN") or str(ROOT / "_build" / "default" / "bin" / "main.exe")

_spec = importlib.util.spec_from_file_location("gen_explainer_data", ROOT / "scripts" / "gen-explainer-data.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)


def load(name):
    return json.loads((FIXTURES / name).read_text())


class OrderFacts(unittest.TestCase):
    def test_order_facts_counts(self):
        facts = gen.order_facts(load("core-ast-order.json"), load("Order.json"))
        self.assertEqual([m["name"] for m in facts["modules"]],
                         ["Order_Msg", "Order_Shop", "Order_Stock", "Order_Ledger", "Order_Run"])
        self.assertEqual([m["linear_states"] for m in facts["modules"]], [0, 5, 6, 4, 0])
        self.assertEqual([m["functions"] for m in facts["modules"]], [18, 33, 37, 26, 38])
        self.assertEqual((facts["linear_states"], facts["functions"]), (15, 152))
        self.assertEqual(facts["fingerprint"], "fbc924928c002942943a81b564d2408d")
        self.assertEqual(facts["tags"], ["Want", "Have", "Book", "Booked", "Out", "Skip"])
        self.assertEqual(facts["roles"], ["Shop", "Stock", "Ledger"])

    def test_state_types_split_into_conversation_states_and_parked_tokens(self):
        facts = gen.order_facts(load("core-ast-order.json"), load("Order.json"))
        self.assertEqual(facts["conversation_states"], 12)
        self.assertEqual(facts["linear_states"] - facts["conversation_states"], 3)   # one Parked_<Role> each
        shop = next(m for m in facts["modules"] if m["name"] == "Order_Shop")
        self.assertEqual(shop["states"], ["S_send_Want", "S_offer_have_out", "S_recv_Booked", "S_end"])

    def test_strips_are_the_generated_state_types(self):
        s = gen.strips(load("core-ast-order.json"))
        self.assertEqual(s["Shop"], ["send Want", "offer have/out", "recv Booked", "end"])
        self.assertEqual(s["Stock"], ["recv Want", "choose have/out", "send Book", "send Skip", "end"])
        self.assertEqual(s["Ledger"], ["offer have/out", "send Booked", "end"])

    def test_strip_lengths_match_the_state_map_axes(self):
        # two independent derivations of a role's positions must agree: the compiler's
        # generated state types, and this script's own projection of the step tree
        s = gen.strips(load("core-ast-order.json"))
        axes, _ = gen.reachable(load("Order.json")["current"]["steps"], ["Shop", "Stock", "Ledger"])
        self.assertEqual({r: len(v) for r, v in s.items()}, axes)

    def test_ledger_excerpt_is_the_actor_head_with_its_comment(self):
        ex = gen.excerpts(ROOT / "examples/lab_app/src/lab_app.march")["ledger_actor"]
        lines = ex.splitlines()
        self.assertTrue(lines[0].startswith("-- Order.Ledger"))
        self.assertIn("starts again from 0", ex)
        self.assertIn("actor LedgerActor do", lines)
        self.assertIn("total : Int", ex)
        self.assertTrue(lines[-1].startswith("  init("))
        self.assertLessEqual(len(lines), 12)

    def test_stock_signature_shows_its_grant(self):
        sig = gen.excerpts(ROOT / "examples/lab_app/src/lab_app.march")["stock_signature"]
        self.assertTrue(sig.startswith("fn stock("))
        self.assertIn("Cap(IO.Mut)", sig)
        self.assertIn("Order_Stock.Entry", sig)

    def test_order_source_is_the_sixteen_lines(self):
        src = gen.order_source(ROOT / "examples/lab_app/src/lab_app.march")
        self.assertEqual(len(src), 16)
        self.assertEqual(src[0].strip(), "@[endpoints]")
        self.assertEqual(src[-1].strip(), "end")
        self.assertEqual(src[1], "protocol Order do")   # the common indent is removed


class InputGuard(unittest.TestCase):
    def test_check_inputs_accepts_an_unchanged_lab_app(self):
        with tempfile.TemporaryDirectory() as d:
            lab = Path(d) / "lab_app.march"
            shutil.copy(ROOT / "examples/lab_app/src/lab_app.march", lab)
            data = Path(d) / "explainer.json"
            data.write_text(json.dumps({"generated": {"lab_app_sha256": gen.lab_app_sha256(lab)}}))
            self.assertTrue(gen.check_inputs(data, lab))

    def test_check_inputs_detects_an_edited_lab_app(self):
        with tempfile.TemporaryDirectory() as d:
            lab = Path(d) / "lab_app.march"
            shutil.copy(ROOT / "examples/lab_app/src/lab_app.march", lab)
            data = Path(d) / "explainer.json"
            data.write_text(json.dumps({"generated": {"lab_app_sha256": gen.lab_app_sha256(lab)}}))
            with lab.open("a") as f:
                f.write("-- an edit\n")
            self.assertFalse(gen.check_inputs(data, lab))


def msg(frm, to, tag):
    return {"msg": {"from": frm, "to": to, "tag": tag, "payload": "Int"}}


ECHO = [msg("A", "B", "Ping"), msg("B", "A", "Pong")]
LINE = [msg("Buyer", "Shop", "Order"), msg("Shop", "Ledger", "Charge"),
        msg("Ledger", "Shop", "Receipt"), msg("Shop", "Buyer", "Confirm")]


class StateMap(unittest.TestCase):
    def test_echo_reachable_cells(self):
        axes, cells = gen.reachable(ECHO, ["A", "B"])
        self.assertEqual(axes, {"A": 3, "B": 3})
        self.assertEqual(cells, [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2]])

    def test_three_role_line_is_nine_of_forty_five(self):
        axes, cells = gen.reachable(LINE, ["Buyer", "Shop", "Ledger"])
        self.assertEqual(axes, {"Buyer": 3, "Shop": 5, "Ledger": 3})
        self.assertEqual(len(cells), 9)

    def test_order_state_map_is_consistent(self):
        axes, cells = gen.reachable(load("Order.json")["current"]["steps"], ["Shop", "Stock", "Ledger"])
        total = axes["Shop"] * axes["Stock"] * axes["Ledger"]
        self.assertIn([0, 0, 0], cells)
        self.assertLess(len(cells), total)
        self.assertTrue(all(0 <= c[i] < n for c in cells for i, n in enumerate(axes.values())))

    def test_state_map_records_the_role_order_of_its_cells(self):
        # JSON object keys are written sorted, so `axes` alone loses the order the cell
        # tuples are in; the figure reads it from `roles`.
        sm = gen.state_map(load("Order.json")["current"]["steps"], ["Shop", "Stock", "Ledger"])
        self.assertEqual(sm["roles"], ["Shop", "Stock", "Ledger"])
        self.assertEqual(sm["cells"], sm["axes"]["Shop"] * sm["axes"]["Stock"] * sm["axes"]["Ledger"])
        self.assertEqual(sm["path"][0], [0, 0, 0])
        self.assertEqual(sorted(sm["path"]), sm["reachable"])

    def test_loop_returns_to_its_first_state(self):
        a = gen.project([{"loop": [msg("A", "B", "Tick")]}], "A")
        self.assertEqual(a["edges"], {0: [(("send", "B", "Tick"), 0)]})   # one state, a self-loop
        self.assertEqual(a["final"], set())

    def test_stop_leaves_the_loop_for_a_final_state(self):
        steps = [{"loop": [msg("A", "B", "Tick"), "stop"]}]
        a = gen.project(steps, "A")
        self.assertEqual(a["edges"], {0: [(("send", "B", "Tick"), 1)]})
        self.assertEqual(a["final"], {1})

    def test_a_role_outside_a_message_takes_no_step(self):
        a = gen.project(ECHO, "C")
        self.assertEqual((a["edges"], a["final"]), ({}, {0}))

    def test_an_unbounded_protocol_is_refused(self):
        with self.assertRaises(SystemExit):
            gen.reachable([{"loop": [msg("A", "B", "Tick")]}], ["A", "B"])


class Facts(unittest.TestCase):
    def test_topology_facts(self):
        t = gen.topology_facts(ROOT / "examples/lab_app/topology.toml", ROOT / "examples/lab_app/topology.lab.toml")
        self.assertEqual((t["stock_capacity"], t["ledger_capacity"]), (32, 64))
        self.assertEqual(t["stock_hosts"], ["lab-2", "lab-3", "lab-4"])
        self.assertEqual(t["books_hosts"], ["lab-3", "lab-4"])
        self.assertEqual(t["ingress"], "lab-1")

    def test_pinned_facts_values(self):
        p = gen.pinned_facts(ROOT)
        self.assertEqual(p, {"heartbeat_s": 1, "silent_timeout_s": 10, "setup_s": 20,
                             "suspect_s": 3, "settle_s": 15, "drain_soft_ms": 3000, "drain_hard_ms": 8000})

    def test_lab_run_is_read_from_its_progress_note(self):
        run = gen.lab_run(ROOT)
        self.assertEqual(run, {"date": "2026-10-05", "commit": "53d66f068", "failover_s": 1,
                               "source": "specs/progress/2026-10-05-multi-host-lab.md"})

    def test_lab_run_fails_when_the_note_no_longer_says_so(self):
        with tempfile.TemporaryDirectory() as d:
            note = Path(d) / "specs/progress/2026-10-05-multi-host-lab.md"
            note.parent.mkdir(parents=True)
            note.write_text("## Results (2026-10-05, main at 53d66f068, load 5-13)\nnothing about failover\n")
            with self.assertRaises(SystemExit):
                gen.lab_run(Path(d))

    def test_pinned_fact_fails_when_its_source_text_is_gone(self):
        with tempfile.TemporaryDirectory() as d:
            tmp_root = Path(d)
            for rel in {e["file"] for e in gen.PINNED} | {"examples/lab_app/topology.toml"}:
                (tmp_root / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / rel, tmp_root / rel)
            self.assertEqual(gen.pinned_facts(tmp_root)["suspect_s"], 3)      # the copy is intact
            lab = tmp_root / "docs/lab.md"
            lab.write_text(lab.read_text().replace("SWIM suspect timeout (3 s)", "SWIM suspect timeout (5 s)"))
            with self.assertRaises(SystemExit) as cm:
                gen.pinned_facts(tmp_root)
            self.assertIn("suspect_s", str(cm.exception))


class Programs(unittest.TestCase):
    @unittest.skipUnless(Path(MARCH).exists(), "no compiler built; run `dune build --root . bin/main.exe`")
    def test_each_wrong_program_is_rejected_with_a_protocol_message(self):
        progs = gen.run_programs(ROOT / "docs/assets/explainer/programs", MARCH)
        self.assertEqual(sorted(progs), ["offer_misses_branch", "send_out_of_turn", "skip_step"])
        for p in progs.values():
            self.assertEqual(p["exit"], 1)
            self.assertIn("Order", p["output"])
            self.assertNotIn(str(ROOT), p["output"])     # no absolute paths leak into the page
            self.assertIn("Order", p["headline"])
            self.assertTrue(p["headline"].endswith("]"))  # the message line carries its code
            self.assertIn("pfn ", p["body"])             # just the role body, for the card
            self.assertNotIn("protocol Order", p["body"])
            self.assertFalse(p["body"].startswith(" "))

    def test_headline_is_the_message_line(self):
        out = "-- PROTOCOL ---- x.march\n\nRole `A` tries to send here. [protocol_step_order]\n\n25 |   code\n"
        self.assertEqual(gen.headline(out), "Role `A` tries to send here. [protocol_step_order]")

    def test_each_program_is_placed_on_a_cell_the_protocol_reaches(self):
        _, cells = gen.reachable(load("Order.json")["current"]["steps"], ["Shop", "Stock", "Ledger"])
        self.assertEqual(sorted(gen.PROGRAM_CELLS), ["offer_misses_branch", "send_out_of_turn", "skip_step"])
        for name, cell in gen.PROGRAM_CELLS.items():
            self.assertIn(cell, cells, name)


if __name__ == "__main__":
    unittest.main()
