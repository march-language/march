# Distributed March Explainer Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one scrolling docs page, at most a 20-minute read, that follows `examples/lab_app` from its 16-line `protocol Order` to a running, failing-over, hot-deployed cluster, with pinned graphics that change as the reader scrolls.

**Architecture:** A Python generator writes every number, code excerpt and diagnostic the page shows into `docs/_data/explainer.json`; Jekyll renders those into the page and inlines the same data for the scripts. Plain browser scripts (no build step) provide a scroll engine, deterministic simulation cores, SVG figure builders and canvas renderers; the cores and builders are pure and are tested under `node --test`.

**Tech Stack:** Jekyll (github-pages gem, existing), Liquid, plain ES2017 JavaScript, canvas and inline SVG, Python 3 standard library, `node --test`.

**Spec:** `specs/2026-11-05-distributed-explainer-design.md`. Read it first; this plan argues from it.

**Not in this plan:** extending `examples/lab_app` and `scripts/lab` with a canary step, a failing-canary scenario and an actor with a state migration. That is a separate plan (`specs/todos/2026-11-05-lab-app-canary-and-migration.md`). Task 13 here consumes its output and is blocked until it lands. Re-running the lab belongs to that work too; when it records a passing run, a follow-up adds the lab's numbers to the data file as pinned facts that point at the run's progress note.

## Global Constraints

- At most a 20-minute read: at most 3,200 words of prose and cards, at most 44 cards. `scripts/check-explainer-budget.py` enforces both.
- The system the page follows is `examples/lab_app`. Do not invent another example.
- Every number on the page comes from `docs/_data/explainer.json`. No number is typed into the page by hand.
- Every simulation is deterministic (seeded) and is labelled on the page as a simulation.
- Black, grey, hatching and one accent colour (`--mx-accent`), defined for both site themes.
- No JavaScript build step, no dependency on the reference library, no charting library.
- Works at 375 px width, in the dark and light themes, and with `prefers-reduced-motion: reduce`.
- Without JavaScript the page reads as an article: text, code, and a static image of each graphic.
- The page does not mention the subject of the reference piece.
- All CSS classes and ids the page adds start with `mx-`. All scripts attach to one global, `window.MarchExplainer`, and also export through `module.exports` when `module` exists.
- Stage files by name; never `git add -A` or `git add .`. No attribution lines in commit messages.
- After each commit, record it in the decision graph: `deciduous add action "<what>" -c 85 --commit HEAD` and link it to node 2915.
- Do not regenerate `docs/pagefind/`.
- Run `dune` with `--root .` from this worktree.

## Review Focus

1. `examples/lab_app/src/lab_app.march` is edited after the data was generated: the page would show stale counts. Expected: doc-lint fails until the generator is re-run. Test in Task 1.
2. The reader lands mid-page (an anchor link, a fast flick, a reload): a figure must show the state for the active card without having passed the earlier cards. Expected: every figure state is absolute. Tests in Tasks 5, 9, 11, 12.
3. The tab is hidden for minutes and shown again: the first animation frame carries a huge time step. Expected: simulations clamp the step and never exceed a node's capacity. Test in Task 9.
4. The window is resized or the phone rotated while a simulation runs. Expected: the canvas re-measures and draws at the new size, with nothing stretched. Check in Task 10.
5. One figure throws while mounting, or the data file is missing a section. Expected: that figure shows a short located error box and every other section still renders. Test in Task 5.

## File Structure

| File | Responsibility |
|---|---|
| `scripts/gen-explainer-data.py` | Runs the compiler on the lab app and writes `docs/_data/explainer.json`; `--check` and `--check-inputs` modes |
| `scripts/check-explainer-budget.py` | Word and card budget for the page |
| `docs/_data/explainer.json` | Generated. The only source of numbers, excerpts and diagnostics |
| `docs/protocol-to-cluster.md` | The page: prose and cards, hand-written |
| `docs/_includes/explainer.html` | Styles, inlined data, script tags |
| `docs/assets/explainer/scroll.js` | Which card is active, as pure functions plus one scroll listener |
| `docs/assets/explainer/rng.js` | Seeded random numbers |
| `docs/assets/explainer/figures.js` | SVG string builders for the static figures |
| `docs/assets/explainer/sim-cluster.js`, `sim-mailbox.js`, `sim-release.js` | Simulation cores, no DOM |
| `docs/assets/explainer/draw.js` | Canvas renderers for the three simulations |
| `docs/assets/explainer/story.js` | Figure registry; maps each card to a figure state |
| `docs/assets/explainer/programs/*.march` | The wrong programs chapter 1 shows |
| `docs/assets/explainer/fallback/*` | One static image per figure for readers without JavaScript |
| `test/explainer/*.test.js`, `test/explainer/test_gen.py`, `test/explainer/fixtures/*` | Tests |

## Data file shape

Every task that reads or writes `docs/_data/explainer.json` uses these keys.

```json
{
  "generated": { "commit": "eb8819a16", "date": "2026-11-05", "lab_app_sha256": "<hex>" },
  "order": {
    "source": ["@[endpoints]", "protocol Order do", "..."],
    "roles": ["Shop", "Stock", "Ledger"],
    "tags": ["Want", "Have", "Book", "Booked", "Out", "Skip"],
    "fingerprint": "fbc924928c002942943a81b564d2408d",
    "modules": [ { "name": "Order_Msg", "linear_states": 0, "functions": 18 } ],
    "linear_states": 15,
    "functions": 152
  },
  "state_map": { "axes": { "Shop": 0, "Stock": 0, "Ledger": 0 }, "cells": 0, "reachable": [[0, 0, 0]] },
  "programs": { "<name>": { "source": "...", "output": "...", "exit": 1 } },
  "timings": { "heartbeat_s": 1, "silent_timeout_s": 10, "setup_s": 20, "suspect_s": 3, "settle_s": 15, "drain_soft_ms": 3000, "drain_hard_ms": 8000 },
  "topology": { "ingress": "lab-1", "stock_hosts": ["lab-2", "lab-3", "lab-4"], "books_hosts": ["lab-3", "lab-4"], "stock_capacity": 32, "ledger_capacity": 64 },
  "sim": { "seed": 20261105, "load_per_s": 14, "session_s": [1.2, 2.8], "restart_s": 1 },
  "deploy": {}
}
```

The zeros in `state_map` are placeholders for the shape only; Task 2 computes the values.

---

### Task 1: Generator for the `Order` facts

**Files:**
- Create: `scripts/gen-explainer-data.py`, `test/explainer/test_gen.py`, `test/explainer/fixtures/core-ast-order.json`, `test/explainer/fixtures/Order.json`, `docs/_data/explainer.json`
- Modify: `scripts/check-docs.sh` (new Check H), `scripts/affected.sh`, `scripts/test-affected.sh`

**Interfaces:**
- Produces: `order_source(path: str) -> list[str]`; `order_facts(core_ast: dict, protocol_record: dict) -> dict` (the `order` object without `source`); `lab_app_sha256(path: str) -> str`; CLI `gen-explainer-data.py [--check | --check-inputs]`; the `generated` and `order` keys of the data file.

- [ ] **Step 1: Record the fixtures.** From a fresh directory under a private `HOME`, run `march --check --emit-protocols <dir> examples/lab_app/src/lab_app.march` and `march --emit-core-ast examples/lab_app/src/lab_app.march > core.json` (the second takes the file as the flag's own argument). Save `<dir>/Order.json` as the fixture. Save a trimmed `core.json` that keeps `module.decls` entries whose `kind` is `DMod` and whose name starts with `Order_`, with each inner declaration reduced to its `kind`.

- [ ] **Step 2: Write the failing tests** in `test/explainer/test_gen.py` (`unittest`, importing the script by path):

```python
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

def test_check_inputs_detects_an_edited_lab_app(self):
    # copy the data file and the lab app to a temp dir, append a comment line to the
    # lab app copy, run check_inputs(data_path, lab_app_path)
    self.assertFalse(gen.check_inputs(tmp_data, tmp_lab_app))
```

- [ ] **Step 3: Run** `python3 -m unittest test/explainer/test_gen.py -v`. Expected: FAIL, the module has no `order_facts`.

- [ ] **Step 4: Implement** the three functions and the CLI. `order_facts` counts `DAlwaysLinearType` as a linear state and `DFn` as a function. Tags are read from the protocol record's step tree in first-appearance order. `order_source` returns the lines from `@[endpoints]` through the `end` that closes `protocol Order`, with the common leading indent removed. The CLI finds the compiler at `$MARCH_BIN` or `_build/default/bin/main.exe`, runs it from a fresh temp directory under a private `HOME`, and writes the data file with sorted keys and a trailing newline. `--check` regenerates to memory and exits 1 with a diff if the file differs, ignoring `generated.date`. `--check-inputs` needs no compiler: it exits 1 if `generated.lab_app_sha256` differs from the lab app's current hash.

- [ ] **Step 5: Run the tests.** Expected: PASS.

- [ ] **Step 6: Generate and wire the guard.** Run `dune build --root . bin/main.exe`, then `scripts/gen-explainer-data.py`. Add Check H to `scripts/check-docs.sh` after Check G: it runs `scripts/gen-explainer-data.py --check-inputs` and prints `ok — explainer data matches examples/lab_app` or fails with `run scripts/gen-explainer-data.py`. In `scripts/affected.sh`, add a rule before the `scripts/*|.github/*|…|examples/*` catch-all: `examples/lab_app/*|scripts/gen-explainer-data.py|docs/_data/explainer.json|test/explainer/*.py` selects `CHECKS scripts/check-docs.sh` and `CHECKS "python3 -m unittest test/explainer/test_gen.py"`. Pin it in `scripts/test-affected.sh` with an `expect checks` line for `examples/lab_app/src/lab_app.march`.

- [ ] **Step 7: Verify.** `scripts/check-docs.sh` prints `doc-lint passed`; `scripts/test-affected.sh` passes; appending a blank line to the lab app makes `scripts/check-docs.sh` fail at Check H (then revert the edit).

- [ ] **Step 8: Commit** the seven files named above with message `docs: generator for the distributed explainer's Order facts`.

---

### Task 2: The state map

**Files:**
- Modify: `scripts/gen-explainer-data.py`, `test/explainer/test_gen.py`, `docs/_data/explainer.json`

**Interfaces:**
- Consumes: the protocol record's `current.steps` tree (`msg`, `choose`, `loop`, `stop` nodes) from Task 1's fixture.
- Produces: `project(steps: list, role: str) -> Automaton` where `Automaton` is `{"start": int, "edges": {int: [(action, int)]}, "final": set[int]}` and `action` is `("send" | "recv", peer, tag)`; `reachable(steps: list, roles: list[str]) -> tuple[dict[str, int], list[list[int]]]` returning each role's state count and the sorted reachable cells; the `state_map` key.

- [ ] **Step 1: Write the failing tests.**

```python
ECHO = [msg("A", "B", "Ping"), msg("B", "A", "Pong")]
def test_echo_reachable_cells(self):
    axes, cells = gen.reachable(ECHO, ["A", "B"])
    self.assertEqual(axes, {"A": 3, "B": 3})
    self.assertEqual(cells, [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2]])

LINE = [msg("Buyer", "Shop", "Order"), msg("Shop", "Ledger", "Charge"),
        msg("Ledger", "Shop", "Receipt"), msg("Shop", "Buyer", "Confirm")]
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
```

`msg(frm, to, tag)` is a test helper building `{"msg": {"from": frm, "to": to, "tag": tag, "payload": "Int"}}`.

- [ ] **Step 2: Run.** Expected: FAIL, no `reachable`.

- [ ] **Step 3: Implement.** The algorithm the signatures do not determine:

```
project(steps, role):
  walk the tree in order, keeping a current state and allocating a new state per action of `role`.
  msg from role        -> edge (send, to, tag) to a new state
  msg to role          -> edge (recv, from, tag) to a new state
  msg not touching role -> no edge
  choose by X          -> project each branch from the same current state; the branch ends are
                          merged into one state unless the branch ends in `stop`
  loop                 -> remember the state at loop entry; at the end of the body, redirect the
                          body's last edge to the entry state; `stop` ends the role (final state)
  merge states that have no action between them, then renumber states in first-visit order.

reachable(steps, roles):
  config = (state per role, one FIFO queue of tags per ordered pair of roles)
  start  = (each automaton's start, empty queues)
  breadth-first: a role may take a send edge (append the tag to its queue to the peer), or a
  recv edge whose tag is at the head of the queue from that peer (pop it).
  a cell is the tuple of role states; collect the distinct cells of every visited config.
  stop with an error if any queue grows past 8 (the protocol is not bounded).
```

- [ ] **Step 4: Run.** Expected: PASS.

- [ ] **Step 5: Regenerate** the data file and confirm `state_map.cells` equals the product of the axes and `state_map.reachable` is non-empty.

- [ ] **Step 6: Commit** `docs: compute the explainer's state map from the Order projection`.

---

### Task 3: Timings, topology and pinned facts

**Files:**
- Modify: `scripts/gen-explainer-data.py`, `test/explainer/test_gen.py`, `docs/_data/explainer.json`

**Interfaces:**
- Produces: `topology_facts(toml_path: str, overlay_path: str) -> dict`; `PINNED: list[dict]` where each entry is `{"key": str, "value": int, "file": str, "must_contain": str}`; `pinned_facts(root: Path) -> dict` raising `SystemExit` naming the entry whose `must_contain` text is no longer in its file; the `timings`, `topology` and `sim` keys.

- [ ] **Step 1: Write the failing tests.**

```python
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

def test_pinned_fact_fails_when_its_source_text_is_gone(self):
    # point one PINNED entry at a temp file that lacks its must_contain text
    with self.assertRaises(SystemExit): gen.pinned_facts(tmp_root)
```

- [ ] **Step 2: Run.** Expected: FAIL.

- [ ] **Step 3: Implement.** Read both TOML files with `tomllib`. Each `PINNED` entry names the file and the exact phrase that states the value: `specs/lang/choreography.md` for the heartbeat ("pinged every second"), the silence cutoff ("for 10") and the setup time ("20 seconds"); `docs/lab.md` for the suspect timeout ("(3 s)") and the settle period ("15 s settle period"); `examples/lab_app/topology.toml` for the drain deadlines (parsed, not pinned). `sim` is a literal in the script with a comment that these values are chosen for legibility and are stated on the page.

- [ ] **Step 4: Run.** Expected: PASS. Regenerate the data file.

- [ ] **Step 5: Commit** `docs: timings and topology facts for the explainer`.

---

### Task 4: Scroll engine

**Files:**
- Create: `docs/assets/explainer/scroll.js`, `test/explainer/scroll.test.js`
- Modify: `.github/workflows/doc-lint.yml`, `scripts/affected.sh`, `scripts/test-affected.sh`

**Interfaces:**
- Produces, on `MarchExplainer.scroll`:
  - `activeStep(rects: {top: number, bottom: number}[], viewportHeight: number, trigger: number) -> number`
  - `stepProgress(rect: {top: number, bottom: number}, viewportHeight: number, trigger: number) -> number`
  - `observeSteps(elements: Element[], opts: {trigger?: number, onStep(i: number): void, onProgress?(i: number, p: number): void}) -> () => void`

- [ ] **Step 1: Write the failing tests** with `node:test` and `node:assert`:

```js
const { activeStep, stepProgress } = require('../../docs/assets/explainer/scroll.js');
const rects = [{ top: 100, bottom: 400 }, { top: 400, bottom: 700 }, { top: 700, bottom: 1000 }];
test('no step before the first one reaches the line', () => assert.equal(activeStep(rects, 800, 0.1), -1));
test('the step under the line is active', () => assert.equal(activeStep(rects, 800, 0.6), 1));   // line at 480
test('past the last step the last one stays active', () =>
  assert.equal(activeStep(rects.map(r => ({ top: r.top - 2000, bottom: r.bottom - 2000 })), 800, 0.6), 2));
test('progress is clamped to 0..1', () => {
  assert.equal(stepProgress({ top: 600, bottom: 900 }, 800, 0.6), 0);
  assert.equal(stepProgress({ top: 380, bottom: 580 }, 800, 0.6), 0.5);
  assert.equal(stepProgress({ top: -500, bottom: -200 }, 800, 0.6), 1);
});
test('an empty list has no active step', () => assert.equal(activeStep([], 800, 0.6), -1));
```

- [ ] **Step 2: Run** `node --test test/explainer/`. Expected: FAIL, cannot find module.

- [ ] **Step 3: Implement.** The line is at `trigger * viewportHeight`. The active step is the last rect whose `top` is at or above the line. `observeSteps` uses one passive scroll listener and one resize listener, throttled with `requestAnimationFrame`, default trigger 0.6; it calls `onStep` only when the index changes, calls it once on start, and skips the `onProgress` call in the frame where the step changed.

- [ ] **Step 4: Run.** Expected: PASS.

- [ ] **Step 5: Wire CI.** Add a step to the doc-lint job after "Lint docs…": name `Test the explainer's scripts`, run `node --test test/explainer/`. In `scripts/affected.sh`, extend Task 1's rule so `docs/assets/explainer/*` and `test/explainer/*.js` select `CHECKS "node --test test/explainer/"`; pin it in `scripts/test-affected.sh`.

- [ ] **Step 6: Commit** `docs: scroll engine for the explainer`.

---

### Task 5: Page shell and figure registry

**Files:**
- Create: `docs/protocol-to-cluster.md`, `docs/_includes/explainer.html`, `docs/assets/explainer/story.js`, `test/explainer/story.test.js`, `scripts/check-explainer-budget.py`, `test/explainer/test_budget.py`

**Interfaces:**
- Consumes: `MarchExplainer.scroll.observeSteps` (Task 4); `window.MARCH_EXPLAINER_DATA` (the data file, inlined).
- Produces:
  - Markup contract: `<section class="mx-scrolly" data-figure="NAME">` containing `<div class="mx-figure">` and `<div class="mx-steps">` with `<div class="mx-step" data-state="STATE">` cards.
  - `MarchExplainer.registerFigure(name: string, mount: (host: Element, data: object) => {setState(state: string, progress: number): void})`
  - `MarchExplainer.mountAll(root: Element, data: object) -> void`
  - `check-explainer-budget.py PAGE [--max-words 3200] [--max-cards 44]`, exit 1 over budget, printing words and cards per `##` section.

- [ ] **Step 1: Write the failing tests.** `story.test.js` builds a minimal fake DOM (plain objects with `querySelectorAll`, `dataset`, `appendChild`):

```js
test('a figure that throws gets an error box and the others still mount', () => {
  const calls = [];
  ME.registerFigure('bad', () => { throw new Error('boom'); });
  ME.registerFigure('good', (host) => ({ setState: (s) => calls.push(s) }));
  ME.mountAll(fakeRoot(['bad', 'good']), {});
  assert.match(fakeRoot.lastErrorText, /bad: boom/);
  assert.deepEqual(calls, ['first']);          // the first card's state is applied on mount
});
test('an unknown figure name is reported, not thrown', () => {
  assert.doesNotThrow(() => ME.mountAll(fakeRoot(['nope']), {}));
});
```

`test_budget.py`:

```python
def test_counts_words_outside_code_and_liquid(self):
    page = "## One\n\nfour words of prose\n\n```march\nignored code here\n```\n{{ site.data.x }}\n<div class=\"mx-step\" data-state=\"a\">two words</div>\n"
    self.assertEqual(budget.count(page), {"One": {"words": 6, "cards": 1}})
def test_over_budget_exits_one(self):
    self.assertEqual(budget.main([path_to_long_fixture, "--max-words", "5"]), 1)
```

- [ ] **Step 2: Run both test files.** Expected: FAIL.

- [ ] **Step 3: Implement** `story.js` and the budget script. `mountAll` wraps each mount in try/catch; on failure it puts `<p class="mx-error">NAME: MESSAGE</p>` in the figure host. It calls `setState` with the first card's state on mount, then on every step change, and with progress on scroll.

- [ ] **Step 4: Write the page shell.** Front matter: `layout: docs`, `title: "From a Protocol to a Cluster"`, `permalink: /docs/protocol-to-cluster/`, a `description`, and no `nav_order` yet (Task 14 adds it). Body: a hand-written-page comment, `{% include explainer.html %}`, the opening section showing the 16 lines from `site.data.explainer.order.source` in a `march` code block, and empty `##` headings for chapters 1 to 5 and the close. The include holds: the `mx-` styles (one grid cell shared by figure and steps so the figure stays pinned at phone width; `--mx-accent: #ff6b5e` under the dark theme and `#c0392b` under the light theme; a visible `mx-sim-label` class reading "Simulation"), `<script>window.MARCH_EXPLAINER_DATA = {{ site.data.explainer | jsonify }};</script>`, script tags for `scroll.js` then `story.js` with the `?v={{ site.time | date: '%s' }}` suffix the layout uses, and a `DOMContentLoaded` call to `mountAll`.

- [ ] **Step 5: Run the tests.** Expected: PASS.

- [ ] **Step 6: Verify in a browser.** `cd docs && bundle exec jekyll serve --port 4010`, open `/docs/protocol-to-cluster/`. Check: the 16 lines render; no console errors; the page is absent from the sidebar; at 375 px there is no horizontal scroll; both themes are legible.

- [ ] **Step 7: Commit** `docs: page shell and figure registry for the explainer`.

---

### Task 6: Static figure builders

**Files:**
- Create: `docs/assets/explainer/figures.js`, `test/explainer/figures.test.js`
- Modify: `docs/_includes/explainer.html` (script tag)

**Interfaces:**
- Consumes: the data file shape.
- Produces, on `MarchExplainer.figures`, each returning an SVG string sized by `opts.width`:
  - `stateMap(stateMap: object, opts: {width: number, lit: number, wrong?: number[]}) -> string`: the first `lit` reachable cells filled; `wrong`, a cell outside the reachable set, drawn in the accent colour.
  - `fanOut(order: object, opts: {width: number, stage: 'source' | 'modules' | 'states' | 'functions'}) -> string`
  - `strip(automaton: {labels: string[]}, opts: {width: number, at: number}) -> string`
  - `detectionTimeline(timings: object, opts: {width: number, mode: 'crash' | 'silent', elapsed: number}) -> string`
  - `functionSquares(deploy: {total_functions: number, changed_functions: string[]}, opts: {width: number, showChanged: boolean}) -> string`

- [ ] **Step 1: Write the failing tests.** Count elements with a regular expression over the returned string:

```js
const count = (svg, cls) => (svg.match(new RegExp('class="' + cls + '"', 'g')) || []).length;
test('fan-out draws one square per state and per function', () => {
  const svg = figures.fanOut(data.order, { width: 680, stage: 'functions' });
  assert.equal(count(svg, 'mx-state'), 15);
  assert.equal(count(svg, 'mx-fn'), 152);
  assert.equal(count(svg, 'mx-srcline'), 16);
});
test('fan-out at the source stage draws only the source lines', () => {
  const svg = figures.fanOut(data.order, { width: 680, stage: 'source' });
  assert.equal(count(svg, 'mx-fn'), 0);
});
test('state map draws every cell and lights the first n reachable', () => {
  const sm = { axes: { A: 3, B: 3 }, cells: 9, reachable: [[0,0],[1,0],[1,1],[1,2],[2,2]] };
  const svg = figures.stateMap(sm, { width: 680, lit: 3 });
  assert.equal(count(svg, 'mx-cell') + count(svg, 'mx-cell mx-lit'), 9);
  assert.equal(count(svg, 'mx-cell mx-lit'), 3);
});
test('timeline has one ping per second up to the cutoff', () => {
  const svg = figures.detectionTimeline({ heartbeat_s: 1, silent_timeout_s: 10 }, { width: 680, mode: 'silent', elapsed: 10 });
  assert.equal(count(svg, 'mx-ping'), 9);
  assert.equal(count(svg, 'mx-failed'), 1);
});
test('function squares mark exactly the changed functions', () => {
  const svg = figures.functionSquares({ total_functions: 40, changed_functions: ['Work.reply'] }, { width: 680, showChanged: true });
  assert.equal(count(svg, 'mx-fn') + count(svg, 'mx-fn mx-changed'), 40);
  assert.equal(count(svg, 'mx-fn mx-changed'), 1);
});
test('a 320 px figure keeps every element inside its width', () => { /* parse x and width attributes; assert x + width <= 320 */ });
```

- [ ] **Step 2: Run.** Expected: FAIL.

- [ ] **Step 3: Implement.** Colours come only from CSS classes, never inline hex. Source-line bars are drawn at lengths proportional to each line's character count. The state map lays roles out as blocks of the first role, columns of the second and rows of the third.

- [ ] **Step 4: Run.** Expected: PASS.

- [ ] **Step 5: Commit** `docs: static figure builders for the explainer`.

---

### Task 7: Chapter 1, what the declaration rules out

**Files:**
- Create: `docs/assets/explainer/programs/skip_step.march`, `offer_misses_branch.march`, `send_out_of_turn.march`
- Modify: `scripts/gen-explainer-data.py`, `test/explainer/test_gen.py`, `docs/_data/explainer.json`, `docs/protocol-to-cluster.md`, `docs/assets/explainer/story.js`

**Interfaces:**
- Consumes: `figures.stateMap` (Task 6), `registerFigure` (Task 5).
- Produces: `run_programs(dir: Path, march: str) -> dict` filling the `programs` key; figure `state-map` with states `empty`, `path` (progress lights the cells in order), `skip`, `offer`, `turn`.

- [ ] **Step 1: Write the three programs.** Each contains the `Order` protocol exactly as in the lab app and one role body with one mistake: a Stock body that sends `Book` before choosing; a Shop body whose offer handles `have` only; a Ledger body that sends `Booked` before it has received `Book`. Model them on `docs/assets/error-tour/28-role-skips-a-step.march` and `25-offer-not-exhaustive.march`.

- [ ] **Step 2: Write the failing test.**

```python
def test_each_wrong_program_is_rejected_with_a_protocol_message(self):
    progs = gen.run_programs(ROOT / "docs/assets/explainer/programs", MARCH)
    self.assertEqual(sorted(progs), ["offer_misses_branch", "send_out_of_turn", "skip_step"])
    for p in progs.values():
        self.assertEqual(p["exit"], 1)
        self.assertIn("Order", p["output"])
        self.assertNotIn(str(ROOT), p["output"])     # no absolute paths leak into the page
```

Skip the test with a clear message when no compiler is built.

- [ ] **Step 3: Run.** Expected: FAIL. Implement `run_programs` the way `scripts/gen-error-tour.py` runs its programs (fresh directory, private `HOME`, file named after the program). Run again: PASS. Regenerate the data file.

- [ ] **Step 4: Write the chapter:** 5 cards, about 370 words. Diagnostics are rendered from `site.data.explainer.programs.<name>.output` in `text` blocks. Counts use `site.data.explainer.state_map.cells` and `state_map.reachable | size`.

- [ ] **Step 5: Verify.** `scripts/check-explainer-budget.py docs/protocol-to-cluster.md` passes; in the browser each card changes the figure, and reloading with the last card in view shows the last state.

- [ ] **Step 6: Commit** `docs: explainer chapter 1, what the declaration rules out`.

---

### Task 8: Chapter 2, what the compiler makes of it

**Files:**
- Modify: `docs/protocol-to-cluster.md`, `docs/assets/explainer/story.js`, `scripts/gen-explainer-data.py`, `test/explainer/test_gen.py`, `docs/_data/explainer.json`

**Interfaces:**
- Consumes: `figures.fanOut`, `figures.strip` (Task 6); `project` (Task 2).
- Produces: data key `order.strips: {"Shop": [str], "Stock": [str], "Ledger": [str]}`, each role's steps as short labels (`"send Want"`, `"recv Have"`); figure `fan-out` with states `source`, `project`, `modules`, `states`, `functions`, `typecheck`, `grants`, `main`, `binary`.

- [ ] **Step 1: Write the failing test.**

```python
def test_strips_follow_the_projection(self):
    s = gen.strips(load("Order.json")["current"]["steps"], ["Shop", "Stock", "Ledger"])
    self.assertEqual(s["Shop"][0], "send Want")
    self.assertEqual(s["Stock"][0], "recv Want")
    self.assertTrue(all(lbl.split()[0] in ("send", "recv", "choose", "offer", "end") for r in s.values() for lbl in r))
```

- [ ] **Step 2: Run, implement `strips`, run again.** Regenerate.

- [ ] **Step 3: Write the chapter:** 8 cards, about 600 words, in the order of the seven stations in the spec's chapter 2, with two cards on grants. Name the compiler files the spec names. The strip is a margin figure inside the `project` and `typecheck` cards. State plainly that there is no separate session checker.

- [ ] **Step 4: Verify** the budget check and the browser as in Task 7. `scripts/check-docs.sh` passes (every compiler path the page names exists).

- [ ] **Step 5: Commit** `docs: explainer chapter 2, what the compiler makes of it`.

---

### Task 9: Cluster simulation core

**Files:**
- Create: `docs/assets/explainer/rng.js`, `docs/assets/explainer/sim-cluster.js`, `test/explainer/sim-cluster.test.js`

**Interfaces:**
- Produces:
  - `MarchExplainer.rng.mulberry32(seed: number) -> () => number`
  - On `MarchExplainer.simCluster`:
    - `create(cfg: {seed, loadPerS, sessionS: [number, number], stockCapacity, ledgerCapacity, hosts: {id: string, books: boolean}[], suspectS, settleS, restartS}) -> State`
    - `step(state, dt: number) -> void` (clamps `dt` to 0.1)
    - `advance(state, seconds: number) -> void`
    - `kill(state, host: number, mode: 'crash' | 'silent') -> void`
    - `revive(state, host: number) -> void`
  - `State`: `{t, hosts: [{id, books, status: 'up' | 'suspect' | 'dead' | 'restarting', incarnation, stock: (number | null)[]}], ledger: {host: number | null, slots: (number | null)[]}, sessions: [...], counters: {started, completed, cancelled, refused}}`

Rules, from the spec's chapter 4: the Ledger starts on the last `books` host. Each session takes one Stock slot on a host and one Ledger slot. A host that is full, suspect or dead is skipped and the next host is tried; a suspect host is still tried once and the attempt bounces. If no Stock host or no Ledger can take the session it is refused. Killing a host cancels its sessions; `crash` cancels at once, `silent` cancels after `suspectS`. A killed Ledger host loses the role, which moves to another live `books` host after `suspectS`; a returning host does not take it back within `settleS`. `revive` restarts the host, which is up after `restartS` with `incarnation + 1`.

- [ ] **Step 1: Write the failing tests.**

```js
const cfg = { seed: 1, loadPerS: 14, sessionS: [1.2, 2.8], stockCapacity: 32, ledgerCapacity: 64,
  hosts: [{ id: 'lab-2', books: false }, { id: 'lab-3', books: true }, { id: 'lab-4', books: true }],
  suspectS: 3, settleS: 15, restartS: 1 };
const live = (s) => s.sessions.length;
test('same seed, same history', () => {
  const a = sim.create(cfg), b = sim.create(cfg); sim.advance(a, 30); sim.advance(b, 30);
  assert.deepEqual(a.counters, b.counters);
});
test('every started session is accounted for', () => {
  const s = sim.create(cfg); sim.advance(s, 20); sim.kill(s, 0, 'crash'); sim.advance(s, 20);
  const c = s.counters; assert.equal(c.started, c.completed + c.cancelled + c.refused + live(s));
});
test('no host ever holds more than its capacity, even after a long pause', () => {
  const s = sim.create({ ...cfg, loadPerS: 200 }); sim.step(s, 60); sim.advance(s, 10);
  for (const h of s.hosts) assert.ok(h.stock.filter(x => x !== null).length <= 32);
  assert.ok(s.ledger.slots.filter(x => x !== null).length <= 64);
});
test('a crashed host loses its sessions at once and takes no new ones', () => {
  const s = sim.create(cfg); sim.advance(s, 10); const before = s.counters.cancelled;
  sim.kill(s, 0, 'crash');
  assert.ok(s.counters.cancelled > before);
  sim.advance(s, 5); assert.equal(s.hosts[0].stock.filter(x => x !== null).length, 0);
});
test('a silent host keeps its sessions until the suspect timeout', () => {
  const s = sim.create(cfg); sim.advance(s, 10); const before = s.counters.cancelled;
  sim.kill(s, 0, 'silent'); sim.advance(s, 2.5); assert.equal(s.counters.cancelled, before);
  sim.advance(s, 1); assert.ok(s.counters.cancelled > before);
});
test('the ledger moves to the other books host, and not back within the settle period', () => {
  const s = sim.create(cfg); sim.advance(s, 5); const first = s.ledger.host;
  sim.kill(s, first, 'crash'); sim.advance(s, 4); assert.notEqual(s.ledger.host, first); assert.notEqual(s.ledger.host, null);
  const second = s.ledger.host; sim.revive(s, first); sim.advance(s, 10); assert.equal(s.ledger.host, second);
});
test('a revived host comes back as the next incarnation', () => {
  const s = sim.create(cfg); sim.kill(s, 0, 'crash'); sim.revive(s, 0); sim.advance(s, 2);
  assert.equal(s.hosts[0].status, 'up'); assert.equal(s.hosts[0].incarnation, 2);
});
test('with every stock host down, sessions are refused', () => {
  const s = sim.create(cfg); [0, 1, 2].forEach(i => sim.kill(s, i, 'crash')); sim.advance(s, 6);
  const r = s.counters.refused; sim.advance(s, 3); assert.ok(s.counters.refused > r);
});
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `rng.js` and `sim-cluster.js`. No DOM, no `Math.random`, no wall clock.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `docs: cluster simulation core for the explainer`.

---

### Task 10: Cluster view and chapter 4

**Files:**
- Create: `docs/assets/explainer/draw.js`
- Modify: `docs/_includes/explainer.html`, `docs/assets/explainer/story.js`, `docs/protocol-to-cluster.md`

**Interfaces:**
- Consumes: `simCluster` (Task 9), `figures.detectionTimeline` (Task 6), `timings`, `topology`, `sim` data keys.
- Produces: `MarchExplainer.draw.cluster(ctx: CanvasRenderingContext2D, state: State, size: {width, height}, colors: {ink, dim, accent}) -> void`; figure `cluster` with states `steady`, `full`, `stock-crash`, `silent`, `ledger-stop`, `return`, `no-offer`; `MarchExplainer.scripts: {[state: string]: {at: number, do: (sim, s) => void}[]}`, the timed actions that define each state.

- [ ] **Step 1: Define each state as a script** from a fresh `create`: for example `stock-crash` is "advance 8 s, kill host 0 by crash". `setState` builds a new simulation from the seed, runs the script, then animates forward from there. With `prefers-reduced-motion: reduce` it advances a further 6 s and draws once. Every simulation figure follows this rule; Tasks 11 and 13 reuse it for the mailbox and release figures.

- [ ] **Step 2: Write the failing test** in `test/explainer/story.test.js`:

```js
test('every cluster state is reachable from scratch and reproducible', () => {
  for (const name of ['steady', 'full', 'stock-crash', 'silent', 'ledger-stop', 'return', 'no-offer']) {
    const a = ME.buildState('cluster', name, data), b = ME.buildState('cluster', name, data);
    assert.deepEqual(a.counters, b.counters, name);
  }
});
test('the full state has a full host and the no-offer state has refusals', () => {
  assert.ok(ME.buildState('cluster', 'full', data).hosts.some(h => h.stock.every(x => x !== null)));
  assert.ok(ME.buildState('cluster', 'no-offer', data).counters.refused > 0);
});
```

`ME.buildState(figure, state, data)` is the pure part of `setState`; add it to `story.js`.

- [ ] **Step 3: Run (FAIL), implement, run (PASS).** The renderer reads colours from computed styles of the `mx-` classes, draws one square per slot, dots for sessions in transit, hatching for a dead host, and the four counters. It re-measures the canvas with a `ResizeObserver` and scales by `devicePixelRatio`.

- [ ] **Step 4: Write the chapter:** 8 cards, about 600 words, following the spec's six cards with the detection timeline as an inline figure in the crash-versus-hang card. State the raised load from `site.data.explainer.sim.load_per_s`, and the lab's real pace, in the first card. Label the figure "Simulation". Cite `test/two_node/` scenario names as the evidence (`crash_before_send`, `crash_after_send`, `silent`, `session_refused`, `cluster_takeover`), saying they use other protocols on the same runtime.

- [ ] **Step 5: Verify.** Budget check passes. In the browser: each card shows its state; resize the window mid-animation and rotate at 375 px, and the canvas stays sharp and unstretched; with reduced motion emulated the figure is still.

- [ ] **Step 6: Commit** `docs: explainer chapter 4, the cluster view`.

---

### Task 11: Mailbox simulation and chapter 3

**Files:**
- Create: `docs/assets/explainer/sim-mailbox.js`, `test/explainer/sim-mailbox.test.js`
- Modify: `docs/assets/explainer/draw.js`, `docs/assets/explainer/story.js`, `docs/_includes/explainer.html`, `docs/protocol-to-cluster.md`, `scripts/gen-explainer-data.py`, `docs/_data/explainer.json`

**Interfaces:**
- Produces, on `MarchExplainer.simMailbox`:
  - `create(cfg: {seed, arrivalS, serviceS, migrateS, holds: boolean}) -> {t, queue: {kind: 'msg' | 'marker', epoch: number}[], version: number, migrating: boolean, held: boolean, total: number, handled: {old: number, new: number}}` (`total` is the actor's state: it goes up by one per message handled)
  - `step(state, dt)`, `advance(state, seconds)`, `deploy(state)`, `crash(state)`, `releaseHold(state)`
  - `MarchExplainer.draw.mailbox(ctx, state, size, colors)`
  - Data key `programs.ledger_actor`: the `LedgerActor` declaration excerpted from the lab app, first 12 lines, plus the comment above it.
  - Figure `mailbox` with states `idle`, `one-at-a-time`, `sessions`, `crash`, `restart`, `lost-total`.

- [ ] **Step 1: Write the failing tests.**

```js
test('messages ahead of the marker run on the old code', () => {
  const s = sim.create({ seed: 1, arrivalS: 0.4, serviceS: 0.4, migrateS: 1, holds: false });
  sim.advance(s, 4); const ahead = s.queue.length; sim.deploy(s); const oldBefore = s.handled.old;
  while (s.version === 1) sim.step(s, 0.05);
  assert.equal(s.handled.old - oldBefore, ahead);
});
test('nothing is handled while the state is migrating', () => {
  const s = sim.create({ seed: 1, arrivalS: 0.4, serviceS: 0.4, migrateS: 1, holds: false });
  sim.advance(s, 2); sim.deploy(s);
  while (!s.migrating) sim.step(s, 0.05);
  const h = s.handled.old + s.handled.new; while (s.migrating) sim.step(s, 0.05);
  assert.equal(s.handled.old + s.handled.new, h);
});
test('an actor holding sessions stays on the old code until released', () => {
  const s = sim.create({ seed: 1, arrivalS: 0.4, serviceS: 0.4, migrateS: 1, holds: true });
  sim.advance(s, 2); sim.deploy(s); sim.advance(s, 20); assert.equal(s.version, 1);
  sim.releaseHold(s); sim.advance(s, 5); assert.equal(s.version, 2);
});
test('a crash empties the state and the restart begins from zero', () => {
  const s = sim.create({ seed: 1, arrivalS: 0.4, serviceS: 0.4, migrateS: 1, holds: false });
  sim.advance(s, 5); assert.ok(s.total > 0); sim.crash(s); assert.equal(s.total, 0);
  sim.advance(s, 3); assert.ok(s.total > 0);
});
```

- [ ] **Step 2: Run (FAIL), implement, run (PASS).**

- [ ] **Step 3: Write the chapter:** 6 cards, about 450 words. Show the ledger excerpt from the data file. Say plainly that the total starts again from 0 when the role moves to another host, quoting the lab app's own comment. Link to the actors and supervision chapters.

- [ ] **Step 4: Verify** budget and browser as before.

- [ ] **Step 5: Commit** `docs: explainer chapter 3, inside one node`.

---

### Task 12: Release rollout simulation

**Files:**
- Create: `docs/assets/explainer/sim-release.js`, `test/explainer/sim-release.test.js`
- Modify: `docs/assets/explainer/draw.js`, `docs/_includes/explainer.html`

**Interfaces:**
- Produces, on `MarchExplainer.simRelease`:
  - `create(cfg: {seed, hosts: string[], leader: number, canary: number, windowS: number, loadPerS: number, sessionS: [number, number]}) -> {t, phase: 'idle' | 'send' | 'forward' | 'canary' | 'gate' | 'rest' | 'complete' | 'halted', hosts: {id, version: 1 | 2}[], counters: {oldReplies, newReplies, drained, failed}}`
  - `start(state, opts: {canaryFails: boolean})`, `step(state, dt)`, `advance(state, seconds)`
  - `MarchExplainer.draw.release(ctx, state, size, colors)`

- [ ] **Step 1: Write the failing tests.**

```js
const cfg = { seed: 1, hosts: ['lab-2', 'lab-3', 'lab-4'], leader: 0, canary: 1, windowS: 3, loadPerS: 8, sessionS: [0.8, 1.6] };
test('a clean release ends with every host on the new code and no failed session', () => {
  const s = sim.create(cfg); sim.advance(s, 3); sim.start(s, { canaryFails: false }); sim.advance(s, 30);
  assert.equal(s.phase, 'complete'); assert.deepEqual(s.hosts.map(h => h.version), [2, 2, 2]);
  assert.equal(s.counters.failed, 0); assert.ok(s.counters.newReplies > 0);
});
test('only the canary changes before the gate closes', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false });
  while (s.phase !== 'gate') sim.step(s, 0.05);
  assert.equal(s.hosts.filter(h => h.version === 2).length, 1);
});
test('a failed gate halts the release and rolls nothing back', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: true }); sim.advance(s, 30);
  assert.equal(s.phase, 'halted'); assert.equal(s.hosts.filter(h => h.version === 2).length, 1);
});
test('sessions in flight on a host when it takes the patch are drained, not failed', () => {
  const s = sim.create(cfg); sim.advance(s, 5); sim.start(s, { canaryFails: false }); sim.advance(s, 30);
  assert.ok(s.counters.drained > 0); assert.equal(s.counters.failed, 0);
});
test('after completion no reply comes from the old code', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false }); sim.advance(s, 40);
  const old = s.counters.oldReplies; sim.advance(s, 10); assert.equal(s.counters.oldReplies, old);
});
```

- [ ] **Step 2: Run (FAIL), implement, run (PASS).** The canary is the last host that is not the leader.
- [ ] **Step 3: Commit** `docs: release rollout simulation for the explainer`.

---

### Task 13: Chapter 5, deploying while it runs

**Blocked** until the lab-extension plan lands. It consumes from that work:

- the name of the lab app's migrating actor and its `<actor>_migrate_state` function, for the code excerpt;
- the lab scenario names that cover the canary step, the failing canary and the migration;
- the canary window the lab deploys with.

**Files:**
- Modify: `scripts/gen-explainer-data.py`, `test/explainer/test_gen.py`, `docs/_data/explainer.json`, `docs/protocol-to-cluster.md`, `docs/assets/explainer/story.js`

**Interfaces:**
- Consumes: `simRelease` (Task 12), `simMailbox` (Task 11), `figures.functionSquares` (Task 6).
- Produces: data key `deploy: {total_functions: int, changed_functions: [str], canary: int, canary_window_ms: int, migrate_excerpt: str}`; `impl_hash_diff(before: str, after: str) -> list[str]` over two `.hashes` files; figures `changed` (states `all`, `changed`), `release` (states `flowing`, `signed`, `canary`, `rest`, `complete`, `halted`), `marker` (states `landed`, `old-finishes`, `migrate`, `new-code`, `hold`).

- [ ] **Step 1: Write the failing test.**

```python
def test_impl_hash_diff_names_only_changed_symbols(self):
    before = "Work.reply aaa s1 l1\nWork.stock bbb s2 l2\n"
    after  = "Work.reply ccc s1 l3\nWork.stock bbb s2 l2\n"
    self.assertEqual(gen.impl_hash_diff(before, after), ["Work.reply"])
```

- [ ] **Step 2: Run (FAIL), implement, run (PASS).** The generator builds the lab app twice with `--compile --dump-impl-hashes`, once as committed and once with the `hot_role` tag edit applied to a temp copy, using the topology digest the way `scripts/determinism-oracle.sh` builds `examples/topology_app`. `total_functions` is the number of lines in the first `.hashes` file.

- [ ] **Step 3: Write the chapter:** 9 cards, about 680 words, in the spec's order: the changed-function squares, the signed release, the canary and its gate, the rest, the halted replay, the mailbox marker, the ledger's hold, the card on what a hot patch cannot replace, and the collapsed `<details>` drawer on changing the protocol with a link to the choreography chapter. Show all four counters, including drained sessions.

- [ ] **Step 4: Verify** budget, browser and `scripts/check-docs.sh`.

- [ ] **Step 5: Commit** `docs: explainer chapter 5, deploying while it runs`.

---

### Task 14: Close, fallbacks and publishing

**Files:**
- Create: `docs/assets/explainer/fallback/` (one image per figure)
- Modify: `docs/protocol-to-cluster.md`, `docs/_includes/explainer.html`, `CHANGELOG.md`, `.github/workflows/doc-lint.yml`; move `specs/todos/2026-11-05-distributed-explainer-page.md` to `specs/progress/`

**Interfaces:**
- Consumes: every figure.

- [ ] **Step 1: Write the close:** 2 cards, about 150 words, the four limits from the spec's close.
- [ ] **Step 2: Add the fallbacks.** For each SVG figure, write its final state to `fallback/<name>.svg` by calling the builder under node. For each canvas figure, capture its final state from the browser as `fallback/<name>.png` at 1360 px wide. Put each inside a `<noscript>` in its figure host with alt text that states what the figure shows.
- [ ] **Step 3: Add the budget check to doc-lint:** a step running `scripts/check-explainer-budget.py docs/protocol-to-cluster.md`.
- [ ] **Step 4: Publish.** Add `nav_order: 10.9` to the page (the Concurrency group, after Choreography). Add a `### Documentation` bullet under `## [Unreleased]` in `CHANGELOG.md`. `git mv` the todo to `specs/progress/` and add two lines on what shipped.
- [ ] **Step 5: Verify everything.** `node --test test/explainer/`; `python3 -m unittest discover test/explainer -p 'test_*.py'`; `scripts/gen-explainer-data.py --check`; `scripts/check-docs.sh`; `scripts/check-explainer-budget.py docs/protocol-to-cluster.md`. In the browser: with JavaScript disabled the page reads top to bottom with an image in every figure; the page appears in the sidebar under Concurrency; 375 px, both themes and reduced motion all hold; a full read-through with a timer comes in under 20 minutes.
- [ ] **Step 6: Commit** `docs: publish the distributed March explainer`.
