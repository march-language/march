# The remaining RC leaks: three live, one not a leak, two already closed

**Date:** 2026-09-16
**Status:** design. Every number below was measured on this date at `0a4275849`
(the `if`/`else` dead-side fix), `--compile --opt 2`, Darwin arm64, with
`live_allocs()` before/after the loop.

This supersedes the measured figures in
`specs/todos/2026-09-06-closure-capture-release-widening.md` and
`specs/todos/2026-09-13-fire-and-forget-tasks-retain-objects.md`, all of which
predate `specs/progress/2026-09-16-if-else-drops-the-dead-side.md`. That fix
moved several of them to zero, so the old numbers no longer describe the tree.
`specs/2026-09-11-codegen-leaks-design.md` is now fully landed (§5 was the last
section) and is closed.

## Current state, measured

| Shape | per iteration | Verdict |
|---|---|---|
| `List.map(xs, fn s -> string_length(s) + k)` | 0.00015 | **flat** — was 1.0 |
| `List.fold_left` / `List.filter` with a capturing lambda | 0.00005 | **flat** |
| apply fn reading two or three heap captures, applied | 0.00015 | **flat** — §1 landed |
| `Array.set` into the TAIL (last 32 slots) | 0.0001 | **flat** |
| closure capturing a `String`, **applied once** | 0.0001 | **flat** (control) |
| closure capturing a `String`, **never applied** | **1.0001** | **LIVE — §A** |
| `Array.set` into the TRIE | **2.997** | **LIVE — §B** |
| `NativeArray.fold_float` | **2.0 per call** | **LIVE — §C** |
| fire-and-forget `task_spawn`, drained | 0.0002 | **not a leak — §D** |

Everything in the flat rows is a shape one of these todos names as leaking. They
are listed so the next person does not re-derive a fixed bug from a stale file.

---

## §A. A closure that is dropped without ever being applied

**The only remaining closure leak, and the keystone.** Item 3 of the widening
todo, implemented once as a runtime drop table and **backed out as a
use-after-free** (`specs/progress/2026-09-15-closure-captures-released-by-the-hof-loop.md`).

### Measured

20,000 iterations, one heap capture (`s`, a fresh `String`):

| | per iteration |
|---|---|
| closure in a list, never applied | 1.0001 |
| closure bound to a local, dropped unapplied | 1.0001 |
| **three** closures over the same `s` in a list, list dropped | 1.0001 |
| closure applied once (control) | 0.0001 |

The environment cell itself IS released — the shallow `EDecRC` frees it. What
leaks is the CAPTURE inside it. The third row is the tell: three closures over
one `s` leak one object, not three, because the leak is `s`'s refcount never
reaching zero, not three orphaned cells.

The control row is what makes this narrow: when the closure is applied,
`Drop.rewrite_apply_clo_drop` deep-drops the environment through the apply
function and the captures are released. The gap is exactly the path where the
apply function never runs.

### Why the previous attempt was a use-after-free

The drop table was gated on `Drop.owning_apply_fns`, which asks **does this
closure type's environment escape?** — a per-TYPE question. The outer release
needs a different one: **did THIS allocation site take its own reference to
each capture?** Perceus emits no RC op when a closure captures a borrowed alias
(a field of a live record, an entry a `Map` still owns), so such an environment
owns nothing and must release nothing. ASAN caught it on `two-node[skew]`: a
node id decoded off the wire and still owned by the members `Map` was freed by
the deep drop of a closure that had captured it.

### Design

1. **The analysis.** In `Drop`, which runs after RC insertion, walk every
   `EAlloc (TCon (clo_name, _), captures)`. For each capture atom with
   `Kind.needs_rc_of = true`, the site owns it iff an `EIncRC` / `EAtomicIncRC`
   on that same variable appears in the immediately-preceding `ESeq`/`ELet`
   prefix. Take the conjunction over captures, then over every allocation site
   of the type; fail closed on any shape not recognised.

   Deliberately conservative: a capture whose ownership arrived by last-use
   transfer (no `inc_rc`, because the alloc consumes the local's only
   reference) is indistinguishable **syntactically** from a borrowed alias, and
   only the first is safe. Requiring the explicit `inc_rc` declines both. That
   leaks where it could reclaim, which is the correct direction, and it is the
   whole reason the previous attempt was unsound.

   Measure the admit rate before building step 2 — if it is near zero the
   design needs the borrowed-set plumbed into `Drop` instead, which is a larger
   change and should be decided on that number rather than assumed.

2. **The drop function.** For each admitted closure type, synthesize
   `__drop$clo$<name>` releasing exactly the captures that need RC. This is the
   same shape `Drop.build_aggregate_drop_fn` already emits for records.

3. **The table.** Register `apply_fn_ptr -> drop_fn_ptr` at module init. Key by
   the code pointer in field 0 rather than a header tag: the closure header's
   `pad` word is free (`MARCH_CLO_ARG0_BORROWED` was retired 2026-09-14) but the
   pointer needs no allocation of a new id space.

4. **The release.** A bare `EDecRC` on a value of function type lowers to
   `march_decrc_closure`, which on reaching zero looks field 0 up in the table
   and calls the drop before freeing. Types that are not in the table keep
   today's shallow release.

**REPL/JIT and hot reload:** per-fragment modules must APPEND to the table, not
replace it (`lib/tir/llvm_repl.ml`'s finalizers, and the five sites listed in
`project_builtin_multisite_gotchas`). A fragment that replaces the table
silently un-registers every earlier fragment's closures.

### Verification bar

- The four-row probe above as the RED control, with the applied-once row as the
  direction that must not move.
- **The ASAN gate, specifically `two-node[skew]`** — it is the scenario that
  caught the previous attempt, and it is now in the standing gate
  (`specs/progress/2026-09-16-asan-gate-sweeps-the-two-node-scenarios.md`).
  A green local suite proves nothing here; the backed-out version was green.
- `bench/list_ops.march` for the closure path.

**Effort: L.** **Risk: high** — this is the one item in this file with a
recorded use-after-free against it.

---

## §B. `Array.set` leaks ~3 objects per trie update

Item 4 of the widening todo (GAPS G81).

### Measured

300-element `Array.PVec(String)`, 20,000 updates:

| | per update |
|---|---|
| set into the tail (indices 290-297) | 0.0001 |
| set into the trie (indices 0-7) | **2.997** |

The tail half is now flat, which is what item 1's landing predicted and nobody
had re-measured. Only the trie path leaks, and it leaks a tight 3 objects per
update — consistent with the path allocating a fresh node per level and
releasing none of the replaced ones.

### Blocked on a prerequisite

`Array.lst_replace_nth` binds the node it replaces by name in the arm that
discards it, so Perceus never releases it. The wildcard fix that worked for
`lst_set` in `7eb8d76a` was applied here, measured **neutral**, and reverted:
the deep drop it enables is emitted as `__drop$TrieNode_String` against a
`TrieNode(NativeU8Arr)` value — a monomorphization mismatch in the
mono-TVar-collapse family (`project_mono_wildcard_tvar_collapse`).

**Do not re-apply the wildcard fix before understanding that mismatch.** It is
the actual work item; the leak is downstream of it. Start by dumping
`--emit-llvm` for a `PVec(String)` update and reading which `__drop$` symbol the
trie arm calls.

Also unreleased on this path, per the original report and not re-measured here:
`trie_update`'s `ascend` never releases its `stk` spine or the frame tuples it
walks.

**Effort: M once unblocked; the mono mismatch is its own S-to-M investigation.**

---

## §C. `NativeArray.fold_float` leaks exactly 2 objects per call

New, found while re-measuring. Not in any todo.

### Measured

16-element `NativeFloatArr`, 2,000 calls, `fn (p, x) -> p +. x`:

| entry point | per call |
|---|---|
| `fold_float` | **2.0005** |
| `fold_int` | 0.0005 |
| `sum_float` | 0.0005 |
| `map2_float` | 0.0005 |
| `map_float` | 0.0000 |

Length-independent — 4 / 16 / 64 / 256 elements all grow by the same 4,001 over
2,000 calls. So it is not the per-element boxing inside the loop, which
`runtime/march_runtime.c:9060 native_float_arr_fold` already releases
(`march_decrc(elem)` and `fold_release_prev_acc`, both pinned by their own
fixtures). It is the boundary: the **initial accumulator box** the caller
allocates for `0.0`, which `fold_release_prev_acc` deliberately excludes from
release (it is the caller's `acc`), and the **returned result box**, which the
caller unboxes and drops on the floor.

`fold_int` is the control that isolates the cause: `clo_call_int_int`
wire-tags its scalar instead of boxing, and it is flat.

### Design

This is the same ownership question the SIMD vector box just answered
(`specs/progress/2026-09-16-simd-vector-box-released.md`): a value boxed by the
CALLER to cross a `ptr` slot, for a callee that borrows it, is the caller's to
release. Release the argument box after the call and the result box after
`march_unbox_float`, at the call site in `lib/tir/llvm_emit_call.ml`, gated on
the builtin's borrow classification rather than hardcoded per name.

Check `native_float_arr_fold`'s siblings in the same sweep — every `f64` entry
point that takes or returns a boxed Float across the C boundary has the same
shape, and only `fold_float` was exercised by this probe's argument pattern.

**Effort: S.** **Risk: low**, but it is still a release added where none ran, so
it takes the ASAN gate like everything else in this file.

---

## §D. Fire-and-forget tasks do not leak

`specs/todos/2026-09-13-fire-and-forget-tasks-retain-objects.md` reports
`live_allocs` growing by 3,540 / 4,452 / 3,595 over 5,000 fire-and-forget
spawns and names the open question: *a leak, or tasks not yet run?*

**Tasks not yet run.** Reproduced and resolved:

| method, 5,000 spawns | grew |
|---|---|
| capture-free thunk + 2,000 `task_yield()` (the todo's method) | 3,115 / 3,700 / 3,297 |
| the same, then `run_until_idle()` | 4 |
| capture-free thunk + `run_until_idle()` | 1 |
| thunk capturing a fresh heap `String` + `run_until_idle()` | 2 |
| thunk capturing one shared heap `String` + `run_until_idle()` | 2 |

The first row reproduces the todo's numbers, variance included. The second row
is the same run continued: the pending work drains and the count collapses to 4.

The todo's reason for doubting "not yet run" — *"a hundredfold more yields did
not reduce it"* — is exactly right as an observation and wrong as an inference.
`task_yield()` yields the current green thread; it does not drain the pending
queue, so more of them do not help. `run_until_idle()` does.

Completion was proved independently rather than assumed: a variant whose thunks
each `println` a line emitted all 10,100 expected lines with `grew=0`.

**Action: close the todo**, and record the apparatus lesson — a
`live_allocs()` sample taken after `task_yield()` alone measures queue depth,
not retention.

---

## Not leaks, listed so they are not mistaken for this work

- `specs/todos/2026-09-03-field-escape-owns-is-per-type-not-per-field` and
  `specs/todos/2026-09-04-unbox-aware-case-join-slot` are PERFORMANCE items
  (an elidable RC pair, a boxed join slot). Neither leaks.
- `specs/todos/2026-08-07-drop-guided-reuse-coverage` was measured as not worth
  building. Do not rebuild it.

## Suggested order

1. **§C** — small, self-contained, and the ownership question is already
   settled by the SIMD fix; good warm-up that exercises the ASAN gate.
2. **§A** — the keystone, and the only one that needs a new analysis. Measure
   the admit rate first and let that decide whether the conservative
   syntactic gate is enough.
3. **§B** — only after someone has read the monomorphization mismatch.
