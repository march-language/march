Termination checking, phase 4: `@[diverges]`, actor handlers, `cap total`, the class-E sweep

Design: `specs/2026-10-26-termination-checking-design.md` §2.2, §3.7, §4.1, §6, §7 and §8
phase 4; decisions D1-D6. Branch `claude/termination`, on top of phase 3 and its review
fixes (`specs/progress/2026-10-27-termination-phase3.md`). The rulings of phases 0-3
stand. D5's stdlib hang fixes are PR #1030, elsewhere, and are not repeated here.

## What changed

- **`@[diverges]` (§2.2).**
  - `Refine_term.certify` gives an SCC with a marked member the new certificate
    `Diverges` (`cert=diverges`). `plan_metrics` files no obligation for it
    (`St_diverges`), and `finish` reports `diverges`.
  - The induction hypothesis is withheld from it, since only `structural` and `metric`
    license one. It is also withheld from any SCC that reaches a marked one: in
    `ih_prepare`, "may diverge" now includes `Refine_term.scc_diverges`, which matters
    for a NON-recursive marked function (phase 3's rule only looked at uncertified
    recursive SCCs).
  - D6: `diverges` joins `known_fn_attributes`.
  - `diverges_conflict` (new code) is raised by `Refine_check.diverges_conflicts`:
    `@[diverges]` with `@[measure]` or `@[decreases]` on one function, and a measure
    whose SCC reaches a marked function. The measure gate's "not structurally recursive"
    message is not added on top for a marked measure. A `@[decreases]` on a cycle that a
    *sibling* marks gets `attribute_no_effect`.
  - "May diverge" is inferred upward (D4): `Refine_term.divergence` walks the SCC DAG,
    callees first, and records a `culprit` per SCC: `Marked`, `Uncertified` (recursive,
    with no `structural`/`metric`/`trusted` certificate) or `Unresolved_call`. A marked
    culprit is preferred, so the report can say "through `@[diverges]`". Interface
    dispatch edges (new `e_dispatch` field) do not carry it (ruling below).
  - `--termination-report` lists every marked unit (recursive or not, class E, shape
    `diverges`), counts `N diverges` on the certificate line, and adds
    `may diverge through @[diverges]: N units: …`.
- **Actor handlers (§3.7).** A handler is a non-recursive unit, and `send(self(), …)` is
  an `ESend`, not a call, so it is no edge. The report gains one line per handler that
  may not return: `handler <site> Counter.Spin may not return: it reaches `spin`, …`. It is
  never a diagnostic, except under `cap total`.
- **`cap total` (§4.1, D2).**
  - Lexer token `CAP_TOTAL` (`"cap" [ \t]+ "total"`), parser rule `cap_total_decl` giving
    `DOpts ["total"]`. That is no AST change; menhir still reports 7 conflicts.
  - Tree-sitter: `'total'` in `capability_declaration`, with `src/` regenerated and the
    corpus case extended. Grammar corpus `parse/p45_cap_total_and_diverges.march`;
    INDEX counts 62/45/17.
  - `Refine_check.cap_unit_spans "total"` marks the functions, `impl` methods and actor
    handlers of each decl list that declares it (each `mod` decides for itself; a
    `describe` inherits). A local takes its enclosing function's.
  - Demand: under the cap, and under `--termination-report`, the plan now also covers
    every SCC reachable from the demanded ones, since the inference reads their
    certificates.
  - `report_cap_total`: every unit of a `cap total` list whose SCC may diverge is a
    `termination_unproved` ERROR. `main`, its local functions and marked units (or those
    whose enclosing function is marked) are exempt.
    - An uncertified cycle is worded as phase 2 words an annotated one: the failing call
      and its counterexample.
    - A caller is worded "`run` may not terminate: it reaches `serve`, which is marked
      `@[diverges]`".
    - A handler is worded "handler `Box.Tick` may not return: …".
    - An annotated `@[decreases]` that fails in a `cap total` module is an error too
      (`report_termination`'s `strict`).
- **`termination_unproved` texts** move into `unproved_text`, shared by both emitters.
  When the counterexample gives the single metric variable `x` a negative value and the
  failing caller has an `if x == 0` exit, the diagnostic carries the machine fix
  `FReplace (that condition, "x <= 0")` and a note. `forge fix` and `--check-json` see
  it; the error-corpus twin `termination_unproved_1` now shows the fix and "after fix:
  exit 0".
- **LSP (§6).** All three code actions are offered on a `termination_unproved`
  diagnostic, in `code_actions_diag.ml`:
  - **change `x == 0` to `x <= 0`**: the generic `fix_actions`, which now also reads the
    client's context diagnostics (deduplicated against its own). The LSP does not run the
    refinement checker, so the diagnostic only ever arrives as context.
  - **mark `f` `@[diverges]`** (`termination_actions`): inserts the attribute, or
    replaces the function's `@[decreases(...)]`, since the two together are a conflict.
  - **add `@[decreases(e)]`**: the FRAME. The compiler appends `note: try
    `@[decreases(e)]`.` when `Refine_term.suggest_metric` returns a metric, and it
    returns none until phase 5. The LSP reads the note.

  `Analysis.diag_to_lsp` is exported. `lsp/test` links `march_refinecheck`.
- **Class E (§0.5, §7).** The classifier's `E?` used to come from a name heuristic
  (`loop`, `serve`, `recv`, …). It now means a recursive unit with no syntactic metric
  whose SCC reaches an external-event builtin (`Refine_term.event_builtins`): a message,
  a connection, a socket, file or process read, the clock, or a `Vault`/mailbox another
  task writes. A unit covered by `@[diverges]` is class `E`, where "covered" means the
  unit itself, a member of its cycle, or the function enclosing a local.
- **The sweep** (below): 23 stdlib and 3 test/native functions marked `@[diverges]`. The
  attribute sits on the `fn` line itself, so no line number moves.
- **Docs and records.**
  - `specs/lang/refinement-types.md`: new sections "Functions meant to run for ever:
    `@[diverges]`", "Actor handlers", "Requiring termination: `cap total`" and "Editor
    repairs". The class table and the attribute list are updated.
  - `specs/lang/errors/diverges_conflict.md` (new) and `termination_unproved.md`
    (`cap total`, the fix, the editor). `scripts/gen-lang-docs.py` was rerun.
  - CHANGELOG `### Changed`.
  - New todo `specs/todos/2026-10-28-termination-diverges-gaps.md`.
- Error corpus: `scripts/seed-error-corpus.sh` added `diverges_conflict_1`. It also
  proposed 46 twins for other reject programs that are not yet in the corpus; they are
  not this phase's, and were deleted. `UPDATE_ERRORS=1` regenerated
  `diverges_conflict_1` and `termination_unproved_1` (now with its fix).

## Tests

Group `termination-diverges` (`test/test_refine_term.ml`, 13 cases) and the LSP group
`termination code actions` (`lsp/test/test_lsp_actions.ml`, 4 cases). Every RED-table
row is covered:

| Row | Cases |
|---|---|
| t1 `@[diverges]` | `spin` is `cert=diverges`, has no Termination obligation, no `unknown_attribute`, a class-E report row and `1 diverges`; a non-recursive marked `wait_for` is listed, and `f` "may diverge through" it; the IH is withheld from certified `f` reaching it (control: unmarked, `f` proves) |
| `conflict` | `@[diverges]` + `@[measure]`, + `@[decreases]` (no obligation, no `invalid_decreases` / `termination_unproved` / `attribute_no_effect`), and a measure calling a marked `base` (control: unmarked, none) |
| t12 handlers | exactly one handler line, `Counter.Spin may not return: it reaches `spin`…`; `Go` (certified `countdown`) and `Again` (`send(self(), …)`) clean; no diagnostic |
| `cap_total` | errors are exactly `Box.Tick`, `down`, `run`; `countdown`, `uses`, `Box.Calm`, `serve`, `pump` (marked) with its local loop, and a recursive `main` are clean; without the cap nothing (D2); a nested `mod` does not inherit; an `impl` is a unit and a dispatch to it does not carry its divergence |
| `ratchet` | stdlib and test/native: the unannotated class-E units equal the allow lists exactly |
| LSP | `x == 0` -> `x <= 0`, `@[diverges]` replacing `@[decreases]`, `@[diverges]` inserted under `cap total`, the `@[decreases(e)]` frame (not offered from a real diagnostic; offered and round-tripping from one carrying the note): each applied, re-checked, nothing left |

RED first: `stub-no-phase4` (no `Diverges` certificate, `diverges` unknown again, no IH
withholding, no conflicts, no handler lines, no `cap total` pass, no LSP termination
actions, no `x <= 0` fix, unit-only `@[diverges]` cover) fails 13 of the 17; the four
that pass are controls (non-recursive listing aside, below). First failing line:

```
FAIL spin certificate
   Expected: `"diverges"'
   Received: `"unproved:not-decreasing"'
```

Then each rule's REJECT row under one perturbation (`perturb.py` in the session
scratchpad, not committed; one edit, rebuild, cold VC cache, both groups, restore):

| Perturbation | First failing line |
|---|---|
| `no-diverges-cert` | `FAIL spin certificate` / `Received: "unproved:not-decreasing"`; conflict-decreases `FAIL no obligation` / `Received: ["proved"]` |
| `unknown-diverges` | `FAIL no unknown_attribute` / `Expected: 0 Received: 1` |
| `no-nonrec-rows` | `FAIL report: …` (no `wait_for` row) |
| `no-ih-withhold` | `FAIL marked: f post: some tail skipped, none violated; got proved,proved` |
| `no-conflict` | three `FAIL one diverges_conflict` / `Expected: 1 Received: 0` |
| `no-measure-conflict` | `FAIL one diverges_conflict` (the measure row) |
| `measure-gate-dup` | `FAIL no structural-wording invalid_measure besides` / `Received: 1` |
| `no-handler-lines` | `FAIL one handler line` / `Expected: 1 Received: 0` |
| `ignore-certs` (every recursion uncertified) | `Counter.Go` flagged (`Received: 2`); cap total `Received: ["Box.Calm"; "Box.Tick"; "countdown"; "down"; "run"; "uses"]` |
| `send-is-edge` (an `ESend` as an unresolved call) | `Counter.Again may not return: it calls `send`…` (`Received: 2`) |
| `no-main-exempt` | `Received: ["Box.Tick"; "down"; "main"; "run"]` |
| `diverges-not-allowed` | `Received: ["Box.Tick"; "down"; "pump/go"; "run"]` |
| `total-inherits` | `FAIL no error` / `Received: ["Inner.spin"]` |
| `no-cap-total` | `FAIL the errors` / `Received: []`; both LSP `cap total` cases |
| `dispatch-carries` | `Received: ["g"; "impl Show.show"; "spin"]` |
| `impl-not-unit` | `Received: ["spin"]` |
| `name-heuristic` (phase 0's classifier) | stdlib `Received: "aho_corasick.march:bfs_loop, list.march:sort_by/sort_loop, msgpack.march:decode_all_loop, sort.march:mergesort_by/sort_loop, xml.march:xml_loop"`; native "no longer class E": the three deadline loops |
| `unit-only-cover` | `Received: "session_node.march:check_waiting, …:consume, …:resume_with"` |
| `drop-annotation-stdlib` (`PeerReader.serve`) | `Received: "peer_reader.march:serve"` |
| `drop-annotation-native` (`observe_debug` `spin`) | `Received: "observe_debug.march:spin"` |
| `no-eq-fix` | `x == 0: no action "Replace `n == 0` with `n <= 0`"` |
| `no-term-actions` | three `no action "…@[diverges]…"` / `"Add `@[decreases(100 - n)]` to `up`"` |
| `fix-own-diags-only` | `x == 0: no action "Replace `n == 0` with `n <= 0`"` |
| `no-replace-decreases` | `no action "Replace `@[decreases]` on `down` with `@[diverges]`"` (only "Mark") |

Two perturbations came back green on the first run and the tests were strengthened,
not the perturbation dropped: `send-is-edge` first patched a builtin path `send` never
takes (it is an `ESend`), and `diverges-not-allowed` had no fixture where the exemption
mattered (a marked function's OWN cycle is skipped anyway), so `pump` with a local
loop was added.

## The sweep

Rule used: mark a loop whose end waits on an event that may never come (a message, a
connection, the next frame, the end of an external stream, a flag or reply from
another task). Do not mark one bounded by its own data, a counter, a budget, or a
deadline on the clock.

**Marked, stdlib (23):**
- `ChannelSocket.ws_loop`: reads WebSocket frames until `Close`.
- `ClusterNode.read_link`: reads link frames until an error or the epoch drains.
- `ClusterNode.accept_loop`: accepts connections until stopped.
- `ClusterNode.tick_loop`: ticks until the node is stopped.
- `ClusterNode.reserve`: re-reads a claim while a concurrent release races it (a
  lock-free retry: it ends only when other tasks let it).
- `Csv.each_row_loop`, `Csv.collect_loop`, `Csv.with_header_loop`: read rows until EOF
  of a file that may be a pipe.
- `File.each_line_loop`, `File.each_chunk_loop`: the same, for lines and chunks.
- `HttpTransport.stream_chunked_body`: reads chunked frames until the terminal one.
- `NetKernel.recv_frame`, `NetKernel.recv_frame_exact`: read another frame whenever
  `unseal` drops one.
- `NodeCall.serve_loop`: serves requests until an error.
- `NodeCall.recv_reply`: reads frames until the matching correlation.
- `NodeSend.recv_failure`: reads frames until a failure frame.
- `PeerReader.serve`: reads frames until `on_frame` says stop.
- `Session.ip_drain`: steps an in-process session until no delivery is queued (a
  `loop` protocol never quiesces).
- `SessionNode.heartbeat`: pings until the link is done.
- `SessionNode.await_outcome`: asks the endpoint actor again while it is alive.
- `SessionNode.drain`: drains deliveries fed by the readers. One mark covers its cycle
  with `check_waiting`, `consume` and `resume_with`.
- `Topology.place_loop`: reconciles placement until closing or stopped.
- `Topology.supervise_wait`: waits until stopped.

**Marked, test/native (3):**
- `control_channel_loopback` `read_data`: reads a socket to EOF.
- `observe_debug` `spin`: ticks until the process exits.
- `actor_monitor_down_reason` `wait_for_queued_message`: spins until another actor's
  mailbox fills.

**Judged terminating, or unmarkable, and on the ratchet's allow lists (stdlib 18,
native 5):**
- `Control.await_state`: a time-bounded poll. It ends only for `poll_ms > 0`; filed.
- `File.with_lines/do_lines`, `File.with_chunks/do_chunks`, `Seq.from_file_lines/do_lines`,
  `Seq.from_file_chunks/do_chunks`: genuine read-to-EOF loops, but in local `fn`s, which
  take no attribute. Their enclosing functions return a lazy `Seq`, so marking those
  would be false.
- `HttpClient.reconnect_and_retry` / `transport_keepalive`: bounded by `retries_left`.
- `HttpTransport.stream_fixed_body`, `HttpTransport.tls_recv_all`: bounded by
  `remaining`.
- `NetKernel.recv_frame_plain`: recurses only while fewer than 4 header bytes are
  buffered.
- `NetKernel.recv_exact_until`: bounded by `need` and a deadline.
- `NodeQueue.admit_waiting`, `NodeQueue.drain`: drain a finite deque.
- `SessionNode.accept_all`: removes the accepted role from `expected` each round.
- `SessionNode.await_answer`, `SessionNode.fill_roles`: bounded by the `budget` Vault.
- `Topology.drain_wait`: bounded by the `hard_ms` deadline (it exits the process).
- `Topology.watchdog`: bounded by the `limit` deadline.
- native, deadline loops: `actor_call_late_reply` and `timer_leak_probe` `spin_until`,
  `supervisor_concurrent_child_crash` `await_dequeued` / `await_restart`,
  `supervisor_respawn_names_before_activation` `resolve`.

**Rejected from phase 0's heuristic list (not class E at all):**
- `AhoCorasick.bfs_loop`: a BFS over a finite trie.
- `List.sort_by/sort_loop`, `Sort.mergesort_by/sort_loop`: merge passes.
- `Msgpack.decode_all_loop`: consumes its input.
- `Xml.xml_loop`: a parser over its input.

Totals against §7: the design counted 41 stdlib class-E units by hand and 8 native.
This classifier finds 44 stdlib units: 23 marked functions cover 26 of them, and 18
are allowed. It finds 8 native: 3 marked, 5 allowed. The stdlib counts differ from 41
because the rules differ: this one includes loops with a deadline or a budget (then
allowed) and the four local loops, and the design's hand count was by name.

## Rulings

- **Ruling: class E is "no syntactic metric, and the cycle reaches an external-event
  builtin", not phase 0's name heuristic.**
  - Why: the heuristic flagged five terminating loops (`bfs_loop`, two `sort_loop`s, a
    decoder, a parser), which the ratchet would have had to allow-list for ever. It also
    missed loops named otherwise (`stream_chunked_body`, `ip_drain`, the
    `SessionNode.drain` cycle). The `name-heuristic` perturbation shows both.
  - Cost if wrong: a loop on a builtin missing from `event_builtins` is classed `?` and
    escapes the ratchet (filed).
- **Ruling: the ratchet allows a short, reasoned list.**
  - Why: deadline, budget and counter loops do end, so `@[diverges]` on them would be
    false. The spec's "zero class-E units without `@[diverges]`" is read as "zero
    unexplained". The test fails both ways: on a new unmarked loop, and on a stale entry.
  - Cost if wrong: an allowed loop that really can hang is not marked. Each entry names
    its bound.
- **Ruling: a deadline on the clock bounds a loop; `ClusterNode.reserve`'s race retry
  does not.**
  - Why: the clock advances whatever the program does. A retry that ends only when
    another task stops interfering depends on that task.
  - Cost if wrong: report-only, either way (filed).
- **Ruling: one `@[diverges]` covers its whole cycle, and the function around a
  local.**
  - Why: a cycle diverges or terminates as a whole, and a local `fn` cannot be
    annotated. Certification already treats the SCC as one unit.
  - Cost if wrong: a cycle-mate that would have certified alone loses its hypothesis.
    It is in a diverging cycle, so it had none.
- **Ruling: the attribute goes on the `fn` line in the sweep.**
  - Why: a line of its own shifts every later line of the file, and with them panic
    locations and spans, which would blur the IR oracle's "attributes do not reach
    codegen". The parser accepts either placement (p45 has both).
  - Cost if wrong: style only.
- **Ruling: "may diverge" for the report and `cap total` does not follow interface
  dispatch edges. The induction hypothesis still does.**
  - Why: a dispatch picks its `impl` by a dictionary, a value, so the caller
    terminates modulo it, as modulo a function argument (§3.6). Each `impl` is its own
    unit, checked under `cap total`. Without this, every `println` reaches the prelude's
    `Show` impls, whose cycle is uncertified today (structural recursion through `map`'s
    lambda is not followed), and `cap total` flags any function that prints. The `dispatch-carries` perturbation shows exactly that.
  - Cost if wrong: an `impl` that diverges and sits outside a `cap total` module is not
    flagged where it is called (filed).
- **Ruling: under `cap total`, a function that calls a `@[diverges]` one must be marked
  too.**
  - Why: D4 lifts the burden by default, but `cap total` asks for it. This is
    Idris's `partial` under `%default total`. The "Mark `@[diverges]`" action makes it
    one click.
  - Cost if wrong: one more annotation per caller, only in an opt-in module.
- **Ruling: `main` and its local functions are exempt; a handler cannot be.**
  - Why: §3.7 exempts `main`. Its locals are part of it. Handlers take no attribute.
  - Cost if wrong: a handler that blocks on purpose cannot live in a `cap total`
    module (filed).
- **Ruling: `cap total` and the report demand every SCC reachable from the
  demanded ones.**
  - Why: the inference reads their certificates. An undemanded recursive SCC has
    only phase 1's structural certificate, so a callee with a provable metric would
    count as "may diverge".
  - Cost if wrong: more obligations under `--termination-report` and `cap total`
    only. The default `--check` demand is unchanged, and the oracle is identical.
- **Ruling: `trusted` counts as a certificate for `cap total` (not for the IH).**
  - Why: `@[trusted]` is the user's assertion, which `cap total` accepts like
    `cap verified` accepts it for contracts. Phase 3's IH ruling stands.
  - Cost if wrong: a `@[trusted]` diverging function passes `cap total`.
- **Ruling: the `x <= 0` repair is the diagnostic's machine fix, not an LSP-only
  action.**
  - Why: `forge fix` and `--check-json` get it for free, and the error corpus checks
    that the fixed program is clean ("after fix: exit 0"). The LSP's generic fix action
    now reads context diagnostics, since this one never comes from the LSP's own
    analysis.
  - Cost if wrong: none. It applies only to a single-variable metric with a negative
    witness and a literal `x == 0` exit.
- **Ruling: the `@[decreases(e)]` action reads a `note: try …` line in the message.**
  - Why: a diagnostic carries one fix, which is taken by `x <= 0`. A note is how
    phase 5 can hand over a metric with no new channel.
  - Cost if wrong: phase 5 may prefer a structured field; the frame is small.

## Oracles

All ran under private `HOME`s, with `_build/default/stdlib` deleted. The baselines were
recorded before the first edit, with the phase-3 exe (`f9367d42e`), frozen.

- **`scripts/refine-oracle.sh check`: `REFINEMENT DIAGNOSTICS IDENTICAL (7861 lines
  over 552 fixtures)`.** The stdlib annotations withhold the IH from any SCC reaching
  them, but the only demanded IH SCC in the corpus is `Range.filter_list` (phase 3's
  measurement). No fixture declares `cap total` or `@[diverges]`.
  - Proved able to go red: with `diverges` removed from the known attributes,
    `DIAGNOSTICS CHANGED — 275 differing lines`, the `unknown_attribute` warnings on the
    annotated native fixtures (`18 |   @[diverges] fn wait_for_queued_message(pid) do`).
- **`scripts/ir-oracle.sh check`: `IR IDENTICAL across 497 programs`.**
  - The first baseline attempt was killed. It ran in this worktree while the stdlib
    was being annotated, so it would have mixed sources.
  - The baseline was recorded in a pristine detached worktree at `f9367d42e` (session
    scratchpad), with the frozen phase-3 exe. The check ran in the same directory,
    detached at `64dfbae65`, with the frozen final exe, so the fixtures' absolute
    paths match.
  - Attributes do not reach codegen.
- **`scripts/types-oracle.sh`: not run.** The parser change adds a token and a rule
  producing the existing `DOpts`; the AST type is unchanged.
- Tree-sitter: `scripts/check-tree-sitter.sh`: `1669/1673 files parse clean; 4 known
  failures`, ok, with no new `known-failures.txt` entry and no keyword-allowlist change
  (`cap total` is one token, like `cap verified`). `tree-sitter test`: 70/70.
- Grammar corpus `check_grammar.sh`: 62 passed. `scripts/check-docs.sh`: passed.
- Timing (§9), `--check --refine-report`, phase-3 exe against the final one, interleaved,
  5 runs each after a warm-up, median, load ~5:
  - `stdlib/list.march`: 1.204 s → 1.223 s (101.6%);
  - `stdlib/json.march`: 1.232 s → 1.218 s (98.9%).

## Suites

Full `scripts/run-tests.sh` at load average 5-8: `All suites passed`, 13 suites, 6158
tests. Among them:
- `march-refinecheck`: 1921, including the 13 `termination-diverges` cases and all
  phase 0-3 `termination-*` groups;
- `march-compiler`: 1453;
- `march-codegen`: 720;
- `march-stdlib`: 899;
- `errors`: 300, including the new `diverges_conflict_1`;
- `march-lsp`: 392, including the 4 termination code actions.

## Not done

- Everything in `specs/todos/2026-10-28-termination-diverges-gaps.md`: class I, the
  `Control.await_state` `poll_ms <= 0` hang, attributes on local `fn`s, the
  hand-written event-builtin list, editor publication of refinement diagnostics, and
  handlers under `cap total`.
- Phase 5 (inference). The `@[decreases(e)]` action is only its frame.
