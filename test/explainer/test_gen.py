"""Tests for scripts/gen-explainer-data.py, the generator behind docs/_data/explainer.json.

Run: python3 -m unittest test/explainer/test_gen.py -v
"""
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"

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


if __name__ == "__main__":
    unittest.main()
