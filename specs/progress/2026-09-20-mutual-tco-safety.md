# Mutual TCO: a group that would free a forwarded argument early is not flattened

Closes option 1 of [[2026-09-26-mutual-tco-forwarded-arg]] (P1,
kept open for option 2). Plan: `specs/2026-09-20-mutual-tco-safety-implementation.md`.

## The bug

`__mutco_take_next_inspect__` ran the Perceus dec chain of a wrapped tail call on the
loop's back edge. The chain is `let t = inspect(x, rest, why) in dec_rc why; t`: `why`
is forwarded to a borrowed parameter and released after the call, which is right under
real recursion and wrong in a loop, where "after the call" is the next iteration. The
DecRC freed the string one instruction before the loop read it again:
`refused: no-y; refused: no-y` for `"no-x", "no-y"`, a heap-use-after-free in
`march_string_eq` under ASAN. Skipping the DecRC, the self-TCO arms' rule (eafbd71a),
leaks it instead, which is exactly what B7 (`test_mutual_tco_borrowed_arg_decref_on_live_path`)
was written to catch. Neither side of the transform is right for this shape.

## The decision

Refuse the loop. `Llvm_tco.find_mutual_tco_groups` gets a fourth condition,
`group_back_edges_safe`: every member's body is walked for the two Perceus-wrapped
shapes the mutual arms intercept (`ELet (tmp, EApp (f, args), chain)` with
`is_trivial_dec_chain_returning`, `ESeq (EApp (f, args), chain)` with
`is_trivial_dec_chain`, `f` a group member), and `back_edge_drops_forwarded_arg`
asks whether any cleanup op in the chain (`cleanup_target`) targets one of the call's
forwarded, non-dup-bound arguments, the forwarded set computed as the self-TCO arms
compute theirs (`dup_bound_vars` over the member's own body). One hit and the SCC is
not a TCO group: its members are emitted by `emit_fn` as ordinary functions, the tail
calls are real calls, and the drop is the ordinary post-call drop it always was. The
walk covers every position, not only tail positions, because the arms fire on the shape
wherever it sits once the group context is installed.

`lib/tir/llvm_emit_tcoarm.ml` is unchanged: the mutual arms are only reached for safe
groups now and still emit their whole chain. Self-TCO is unchanged too; it keeps the
"skip" side and therefore the leak half of the same tension (a self call forwarding a
non-dup-bound owned value and dropping it after the call never drops it). That is the
mirror problem, noted here and in the todo, not widened into this change.

Why not the alternatives now: a pending-drop list drained on every `ret` (option 2) is
faithful but a runtime cost on the transform's hot path and a bigger change; the
owned-only rule (option 3) is this predicate with a narrower net. The todo stays open
for option 2, and when it lands the predicate becomes its trigger instead of a refusal.

## What it costs

Only the refused shape: a mutual group forwarding an owned heap value to a borrowed
parameter and releasing it after the call. It now recurses for real, so a deep enough
input grows the stack there. `stdlib/session_node.march`'s `invite_role`/`answer_or_next`
pair was that shape and is being rewritten as a single recursive function regardless.
Groups over integers, and list walks whose forwarded values are borrowed fields of the
scrutinee (or dup-bound), are untouched and keep their loop (pinned by
`test_mutual_tco_safe_group_still_flattened`).

## Tests

- `test/native/mutual_tco_forwarded_arg.march` (+ `.expected`, the interpreter's output)
  gets its `test/dune` golden pair. RED against dace3e20e (`refused: no-y; refused: no-y`,
  diff exit 1), GREEN with the fix (diff exit 0). Its second half walks a 20000-element
  list through a second pair and asserts `live_allocs` grew by under 1000, so refusing the
  loop is shown not to leak either. (That pair, `walk`/`step`, was never a mutual group
  in either compiler: the inliner folds `step` into `walk`, which becomes a self-TCO
  loop. The codegen test below is where the mutual list walk is pinned.)
- `test_codegen.ml`, `mutual_tco_codegen`: B7 keeps its name and doc comment, appended
  with why it flipped, and now asserts that NO `mutual_loop`/`__mutco_` is emitted for
  its fixture, that `build_loop` really calls `consume_loop`, and that its `march_decrc`
  survives as an ordinary post-call drop. New `test_mutual_tco_safe_group_still_flattened`:
  even/odd over ints and a `Cons(x, rest)` walk handed to the other member both still get
  `mutual_loop`.
- `test/refine_audit/corpus.baseline`: the two `native_mutual_tco_forwarded_arg` lines
  were already committed (005b3f109, when the fixture landed without a rule); the
  regeneration was run once and produced no diff.
- TIR snapshots: unchanged (45 cases, no fixture in the corpus has the shape).

## Benchmarks (compiled, `--opt 2`, A/B vs a compiler built from dace3e20e, alternating, one warm-up each, best of 3)

| benchmark | dace3e20e | this change |
|-----------|-----------|-------------|
| `bench/fib.march` | 0.441s | 0.443s |
| `bench/list_ops.march` | 0.072s | 0.073s |

Measured on a shared box at load average ~12.7 (another agent's compile running), so
the resolution is a few ms; the three pairs were within 4 ms of each other for fib and
1 ms for list_ops.

Neither benchmark contains a mutual group, so no loop was refused; the numbers are
noise-level, as expected.
