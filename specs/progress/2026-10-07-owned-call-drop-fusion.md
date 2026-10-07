# DONE Owned-call drop fusion: a borrowed call whose argument dies there consumes it

Done 2026-10-07. Follows `specs/progress/2026-10-07-binary-trees-static-nullary-and-idle-ticks.md`
and `specs/todos/2026-08-04-x86-benchmark-findings.md` (section 2, binary-trees),
which stays open for its other findings.

## The problem

Borrow inference marks `check(t : Tree)` in `bench/binary_trees.march` as
borrowing `t` (it only reads it), so a caller that builds a tree just to check
it compiled to

```
let $t : Tree = make(depth) in
let $rc : Int = check($t) in
__drop$Tree($t);
$rc
```

The tree was walked twice: once by `check`, then again by the recursive deep
drop. `__drop$Tree` was the hottest function in a `sample` profile (~22%).

## Design

When a known call `f(.., x, ..)` passes `x` at one of `f`'s BORROWED
positions, `x` is dead after the call and the caller owns it (exactly the
condition under which Perceus emitted the post-call drop), Perceus now calls
an owned clone `f$own<i>` instead and emits no drop. In the clone those
positions are owned parameters, so Perceus places their releases the way it
does for any owned parameter: a destructuring `match` on a dead scrutinee gets
the scrutinee's own `dec_rc` at the arm head, which `Llvm_case` already
compiles as drop specialisation (`march_decrc_freed`: a unique cell is freed
shallowly and its fields move to the arm's binders; a shared cell is
decremented and the fields are dup'd). The fields are then owned and dying at
the recursive calls, which redirect to the clone again. One traversal frees
the tree:

```
fn check$own0(t : Tree) : Int =
  case t of
  Leaf() -> dec_rc t; 1
  Node(l, r) -> dec_rc t; check$own0(l) + check$own0(r) + 1
```

Implementation (lib/tir/perceus.ml, lib/tir/perceus_core.ml):

- `Perceus_core.owned_calls`: the module-scoped clone table carried in the
  Perceus `env` (`None` = feature off). `owned_call_redirect` is consulted in
  the `EApp` case after the post-call drop list is computed.
- Clones are made LAZILY: only a (callee, positions) pair some call site
  redirected to gets a clone, built from the callee's pre-RC body (the same
  body the original's RC insertion receives) and RC-processed after every
  original, under the original's borrow modes minus those positions. A
  clone's own calls may request further clones (drained to a fixpoint).
  Originals are processed first, so their `$rc_N` names do not depend on the
  feature.
- `oc_useful` (a least fixpoint, `compute_useful_positions`) gates the
  redirect in ORIGINAL functions: some handed position must be one the clone
  does something with (the parameter is an `ECase` scrutinee, or is handed on
  at a useful position of another eligible function). Owning anything else
  only moves the caller's drop into a copy of the callee (the first
  prototype cloned `println$String` for nothing).
- Once a call is redirected, EVERY dying argument at a borrowed position is
  handed over, not just the useful ones, and inside a clone there is no gate
  at all. Both are about loops, not profit: in a clone, the variables that
  were borrowed in the original (its owned parameters and the fields matched
  out of them) are owned, and a call that kept a post-call drop of one would
  no longer be a tail call where the original's was. The first version
  handed over only the useful positions and turned
  `test/native/mutual_tco_forwarded_arg.march`'s `walk`/`step` loop into
  real recursion (`step$own1` kept a `dec_rc x` after its tail call; after
  inlining that was a stack overflow at 20 000 elements). The fixture's
  `walk_s`/`step_s` case reproduces it (stack-guard SIGBUS) when the handed
  set is narrowed back.
- A clone parameter its body never mentions (handed over so the call keeps
  no drop) is released at the clone's entry.
- `Perceus.perceus_owned` returns the borrow map extended with every clone's
  modes; `Contract_pipeline` hands that map to `Drop` and `Escape`, so both
  judge a clone's owned positions as owned.
- Unused originals (every call redirected) and unused clones (every call
  inlined) are removed by the existing DCE.

### Why it is sound

The caller-side drop and the redirect are two ways to spend the same
reference: the condition is literally Perceus's existing post-call-drop
condition (`Unr`, needs RC, dead after the call, borrowed position, not a
closure free variable, not moved by a TRMC hole fill, not a field borrowed
from a live parent), so the caller owned exactly one reference to `x` and
gives it to the callee instead of releasing it. Inside the clone the
parameter is an ordinary owned parameter, and everything after that is the
existing, general Perceus discipline for owned parameters plus the existing
shared/unique split in `Llvm_case`. A shared subtree (rc > 1) is never freed
by the owned walk: `march_decrc_freed` only decrements it and the fields are
dup'd before the arm consumes them. A static nullary cell (rc =
`MARCH_RC_IMMORTAL`) passed owned is released by a decrement that is a no-op.
A borrowed parameter is by definition never stored, returned or captured, so
the clone consumes nothing a caller still expects.

### Exclusions

- **Where it is off entirely:** unoptimised builds, the JS target, hot reload
  (a clone is a second copy of a body the HCR identity machinery does not
  track, as for `Hof_spec`), the REPL/JIT (it calls `Perceus.perceus`, which
  never redirects), and `MARCH_NO_OWNED_CALLS=1`.
- **Callees never cloned** (`Perceus.owned_clone_eligible`): anything but
  `FnNormal`/`FnFused` kinds, apply functions (closure ABI: every parameter
  is already owned), actor dispatch / `on_stop` / inspect glue the runtime
  calls by name, hot-reload migration entry points, `__drop$` helpers, RPC
  stubs, `main`, and functions with no borrowed parameter. A clone is an
  extra function; the original keeps its name, ABI and borrow modes.
- **Arguments never handed over:** in an original function, a variable
  passed more than once in the same call (inside a clone it is handed to
  every position, see the closed gap below), any call where a variable sits at
  both an owned and a borrowed position (the dual-position accounting stays
  as it was), and a variable bound directly by `let v = EAlloc ...` in the
  caller: `Escape` may stack-promote such a cell through a borrowing callee,
  which an owning one forbids.
- **Loops stay loops:** inside `f`, a recursive call to `f` is never
  redirected (its `Llvm_tco` back edge is untouched). Inside a clone
  `f$ownM`, a call to `f` goes to the clone for its own positions: `f$ownM`
  itself when they match (so a tail-recursive reader's clone is a loop too:
  `len$own0` walks a 300 000-element list in the fixture), else a sibling
  clone, with which it forms a clean tail-call cycle that `Llvm_tco`'s
  mutual-TCO groups flatten (`swap_count`, `zip_len` in the fixture).
- **Closed gap (follow-up, same day):** a variable passed twice in one call
  stayed with the caller (handing it to one position would let the clone
  free it while the other, borrowed, position still reads it). Inside a
  clone such a call kept its post-call drop, and that was reachable: a
  mutual loop passing a row twice overflowed the stack at 1 000 000 rows.
  Inside a clone the variable is now handed to every borrowed position it
  occupies, dup'd once per extra position before the call; originals keep
  the drop. See `specs/progress/2026-10-07-owned-call-dup-arg.md`.
- FFI externs and builtins are not functions in the module and are never
  cloned; their borrowed arguments keep the caller-side drop.

## Measurements

Apple M3 Max, one compiler binary, `--compile --opt 2`, A/B against the same
compiler with `MARCH_NO_OWNED_CALLS=1` (its own CAS tag `noowncall`, and the
two binaries differ), runs interleaved, load average ~17-25 from other
sessions. Outputs identical in both modes for all three.

| benchmark | runs | on: min / median | off: min / median | change (min / median) |
|---|---:|---:|---:|---:|
| binary_trees | 15 | 68.1 / 69.4 ms | 72.1 / 74.8 ms | −5.5% / −7.2% |
| binary_trees (order reversed) | 15 | 67.7 / 69.9 ms | 72.7 / 74.9 ms | −6.9% / −6.7% |
| tree_transform | 9 | 594.0 / 603.9 ms | 596.8 / 604.8 ms | flat |
| list_ops | 15 | 34.0 / 37.1 ms | 36.0 / 37.7 ms | flat (noise) |

binary_trees' `sum_trees` and `main` now call `check$own0` and contain no
`__drop$Tree` call; the original `check` is gone (DCE: every call was
redirected). What the saving is: one tree traversal (a tag load and a call per
node); the per-node `march_decrc_freed` and the free itself remain, they just
happen during `check`. tree_transform gets `sum_leaves$own0`, list_ops
`ifold$hspec$1$own0`; neither moved measurably.

Compile time: `--emit-llvm --opt 2` of the fixture (whole stdlib), 5 runs:
2458 vs 2385 ms min (+3%), 2479 vs 2457 ms median (+1%).

## Verification

- `test/native/owned_call_drop_fusion.march` (+ `.expected`, the
  interpreter's output; dune rule pair `owned_call_drop_fusion`): trees and
  lists read once and dropped; an argument read again after the first call
  (only the second call may consume it); a subtree shared by two trees and
  read on its own afterwards (rc > 1 through the owned walk); a static
  nullary passed owned; two mutually recursive readers; a wrapper that only
  hands its argument on; two tree parameters, both dying and one dying; a
  tree captured by a closure; a tree inside a constructor; a 300 000-element
  owned tail-recursive list walk; mutual tail recursion forwarding a list
  field (200 000 elements); a self call that swaps a field into the other
  parameter (sibling clones); and a churn loop that must stay flat by
  `live_allocs`. Matches the interpreter compiled with the feature on and
  with `MARCH_NO_OWNED_CALLS=1`. Its two refine-audit baseline lines are in
  `test/refine_audit/corpus.baseline`.
- IR check (`owned_call_drop_fusion_llvm_check`): the binary-trees-shaped
  `churn` calls `check$own0` (7 calls) and no `__drop$` helper, and
  `check$own0` releases with `decrc_freed`. RED with the kill switch (0
  owned calls, 10 drop calls).
- The fixture is RED (stack-guard SIGBUS at "mutual walk") when the handed
  set is narrowed back to the useful positions, the first version's bug.
- All 321 native goldens with a `.expected` (`test/native/`), compiled in a
  scratch directory with the feature on: 292 match; each of the other 29
  fails identically with `MARCH_NO_OWNED_CALLS=1` (fixtures that need their
  dune rule's flags, env or stdin, JS-only ones, expected panics). The one
  regression the first version had there, `mutual_tco_forwarded_arg`, is
  what led to the hand-everything rule above.
- `scripts/run-tests.sh -q compiler codegen`: all passed (1290 + 675).
- TIR snapshots (`run_snapshots.exe`): unchanged, 57 passed. The harness
  calls `Perceus.perceus`, which never redirects, so the corpus's TIR shape
  is untouched by design; the feature's own shape is pinned by the IR check.
- Not done: an ASAN run. On this base (PR #861) every `MARCH_SANITIZE=1`
  binary, a one-line `println("hi")` included, sat for minutes without
  printing (the fixture the same with `MARCH_NO_OWNED_CALLS=1`), so the
  sanitizer sweep is left to CI.
