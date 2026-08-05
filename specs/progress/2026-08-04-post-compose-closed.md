# 2026-08-04 — A CLOSED measure postcondition composes through an unannotated `let`

Task 2 of the "remaining seven" refinement-composition batch. Re-lands the
producer half of the `scope_add_binding` widening that was prototyped,
verified, and deliberately reverted during the 2026-08-03 #171 investigation
(see `specs/todos/2026-07-29-refinement-contract-composition-follow-ups-open-from-the-2026-07.md`).

## The gap

```march
type Tree = Leaf | Node(Tree, Int, Tree)

@[measure]
fn size(t : Tree) : Int do
  match t do
    Leaf -> 0
    Node(l, _, r) -> 1 + size(l) + size(r)
  end
end

fn grow(t : Tree) : {Tree | size(_) > 0} do
  match t do
    Leaf -> Node(Leaf, 1, Leaf)
    Node(l, y, r) -> Node(Node(l, y, r), 1, Leaf)
  end
end

fn needs_nonempty(x : {Tree | size(_) > 0}) : Int do 1 end

fn go(t : Tree) : Int do
  let r = grow(t)
  needs_nonempty(r)     -- was: solver-undecided, silently skipped
end
```

The identically-refined annotated spelling (`let r : {Tree | size(_) > 0} =
grow(t)`) already composed, via a wholly separate mechanism
(`check_let_annotation` + `refined_scope_ty`'s ADT arm, unconditional in
`scope_add_binding`'s `PatVar n, Some r` case). The UNANNOTATED spelling
(`let r = grow(t)`) goes through the postcond-derived arm instead, which
seeded a scope entry only for a scalar- or record-sorted postcondition; a
plain multi-constructor ADT (`Tree`, `List(a)`) fell into the `Some _ | None
-> sc` catch-all and the fact vanished, even though the CONSUMER
(`load_scope_measure_facts`) already existed and already read exactly this
shape for a refined parameter.

## Root cause, and the trap in the obvious fix

The obvious fix — add an arm `Some (binder, pred, Some srt) when is_meas_sort
srt -> …` — builds and looks plausible, but never fires: `postcond`
(`postcond_of`, backed by `return_refine_sorted`) reports a plain ADT return's
sort at the **bare** `adt_sort_name` (`"M_Tree"`), the same convention
`refined_param_ty` uses for a refined PARAMETER — not at the `$Meas:`-prefixed
marker (`meas_sort_name` = `meas_sort_prefix ^ adt_sort_name`) that
`refined_scope_ty` gives a directly-annotated local. `is_meas_sort` tests for
the `"$Meas:"` prefix specifically, so an arm gated on it against `postcond`'s
raw sort silently never matches — the entry would still vanish, just one
`match` arm later, and every downstream test would still read "skipped" with
no clue why. Caught by building a debug harness that printed
`load_scope_measure_facts`'s own `List.assoc_opt` result before the
`is_meas_sort` guard: the sc entry for the bound name was simply not there at
all, tracing back to `postcond`'s `Some(_,_,"M_Tree")` never matching either
of the two guards already present.

The fix instead detects "a registered ADT sort that is not a record"
(`Hashtbl.mem adt_ctors srt`, after the `is_record_sort` arm has already
claimed the record case) and re-tags it with `meas_sort_prefix` at the point
of insertion into `scope`, so the entry lands on the one spelling every scope
consumer (`load_scope_measure_facts` and its constructor-tag analogue
`load_scope_tester_facts`) already reads. Nothing downstream needed to
change.

## Scope

Deliberately **Closed** only — the postcondition mentions no parameter other
than the refined value itself (`size(_) > 0`). The **Relational** case
(`size(_) == size(t) + 1`, mentioning another caller variable) needs a
separate widening of `load_scope_measure_facts`'s resolver (item 2 of the
"three independent things" list in the todos file above) and is explicitly
out of scope here; the fixture in `post-compose-closed` stays Closed on
purpose.

## Verification

- RED confirmed before the fix: `post-compose-closed` case 0 (`no error` /
  `violated=0` / `skipped=0`) FAILed with `skipped=1`; case 1 (REJECT
  CONTROL — rebinding `r` before the call) already passed.
- Fix applied to `lib/refinecheck/refine_check.ml`'s `scope_add_binding`
  (the postcond arm around line ~2075); comment updated to describe the new
  behaviour instead of the old refusal.
- GREEN: both `post-compose-closed` cases pass; full `test_refinecheck`
  suite: 466/466 (464 baseline + 2 new), 0 failures.
- Load-bearing: gating the new arm on `false &&` reproduced the exact RED
  failure; removing the gate restored green.
- Stdlib sweep (`--check` over every `stdlib/*.march`, `.march/cas/{artifacts-v2,vc}`
  cleared first): byte-identical pre- vs. post-fix output. Positive control
  (a fixed fixture reproducing the `grow`/`needs_nonempty` shape, checked with
  `--refine-report` under both binaries): pre-fix reports `reason:
  solver-undecided` on the composed call; post-fix reports nothing (proved) —
  confirms the sweep instrument can detect a real change, so the empty stdlib
  diff is meaningful rather than vacuous.
- Corpus sweep (`specs/lang/types/{accept,reject}/*.march`): only the two
  pre-existing, already-recorded failures (`accept/t49`, garbage bytes in a
  capability name affecting `reject/t39`'s diagnostic text, not its verdict)
  — no new accept/reject regressions.
- Full suite (`scripts/run-tests.sh -q`): 782/782 green. Full (non-`-q`)
  run additionally hit `run_stdlib`'s known-environmental `adversarial-
  regressions #40 MARCH_SANITIZE` (confirmed: a trivial unrelated
  `clang -fsanitize=address` C program also hung under the same host load —
  not this change) and one transient flake in the same suite (`Vault.update`
  concurrency test #20, passed cleanly on an isolated re-run) — both
  consistent with pre-recorded environmental issues, neither touched by this
  change (confined to `lib/refinecheck/refine_check.ml` and
  `test/test_refinecheck.ml`).

## Status

Task 2 shipped alone is intentionally partial per the task-2 brief: it makes
the Closed shape compose but not the Relational shape (Task 3, a later
dispatch, is what makes the brief's original motivating repro — a relational
measure postcondition — actually work). If Task 3 does not land on this
branch, this note is the explicit record of which shapes compose (Closed,
through an unannotated `let`, for a non-record registered ADT) and which do
not yet (Relational, any binding form).
