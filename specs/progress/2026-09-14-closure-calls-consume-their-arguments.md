# A closure call consumes its arguments, on every side

**Landed 2026-09-14.** Closes the 2026-08-21 todo
`ecallptr-owned-arg-borrow-callee-leak` (this file is that todo, moved) and §3 of
`specs/2026-09-11-codegen-leaks-design.md`, with three pieces that design did not
anticipate and one of its predictions corrected.

## The defect

```march
pfn call_n(f : (String) -> Int, n : Int, acc : Int) : Int do
  if n <= 0 do acc else call_n(f, n - 1, acc + f(int_to_string(n))) end
end
-- f = fn (s : String) -> string_length(s), taken from a list
```

One leaked `String` per call (10,002 over 10,000 calls on `origin/main`
61d5f167, Darwin arm64, `--compile --opt 2`), and an argument the caller kept
using became immortal. The two sides of a closure call disagreed:

- **Caller** (Perceus's `ECallPtr` case, and the direct `EApp` Known_call makes
  of it): every argument is owned; a live-after argument is dup'd, a dead one
  transferred.
- **Callee** (`Borrow.infer_module`): only `$clo` was pinned owned. A parameter
  whose body only read it stayed borrowed and never released the transferred
  reference.

Everyday shapes that hit it: a `List.filter` predicate, `to_string` of a
`List(String)` (prelude's Show maps `fn x -> show(x)` over the list: 20,005
objects over 10,000 calls), a record passed to a lambda.

## What landed

The convention is now stated once, in `lib/tir/clo_flags.ml`: **a closure call
consumes every heap argument except a boxed Float.**

1. **Callee pin** (`lib/tir/borrow.ml` `infer_module`): every apply-fn
   parameter is owned, not just `$clo`.
2. **Unused parameters are released at entry**
   (`Perceus.insert_dead_apply_param_drops`). An owned parameter with no use
   (`fn _ -> 0`, `fn (acc, _) -> acc`) has no last use to hang a release on.
   Not in the design; the pin alone left `fn (s : String) -> 7` leaking.
3. **Record-alias lambda parameters** (`lib/tir/lower_expr.ml` `ELam`): an
   annotation `p : Pt` lowered syntactically to `TCon "Pt"`, which no RC pass
   treats as a record, so a field read dup'd the whole record and the
   owned-aggregate parameter drop never fired (2 objects per call, before and
   after the pin). The typechecker's expanded `TRecord` is used instead. Not in
   the design.
4. **`$clo_wrap` trampolines release what their target borrows**
   (`Llvm_calls.clo_wrap_define ~borrowed`). A named top-level function or
   builtin passed as a value is called through an LLVM-level trampoline that
   Perceus never sees; its target may borrow a parameter. `Clo_flags` now
   carries each function's per-parameter borrow modes from Perceus to the
   emitter (it used to carry the single `MARCH_CLO_ARG0_BORROWED` bit, now
   retired along with the header pad stamping). Not in the design; `List.map(xs,
   slen)` leaked 1 per element with every other piece in place. An actor's
   dispatch function is excluded: `actor_green_thread` calls its trampoline with
   the actor record and message without handing over references, and the
   release freed the live actor (ASAN: `g35_actor_spawn_send`,
   `g40_actor_foreign_msg_drop`).
5. **The C runtime follows the convention** (`march_clo_arg_retain` in
   `runtime/march_runtime.h`): `march_typed_array_map` and
   `march_typed_array_fold` retain the array element they pass;
   `fold_release_prev_acc` releases only a Float accumulator (the callee
   consumes any other) and lost its arg0 witness. The Float test is taken
   BEFORE the call: the first version read the tag of an accumulator the
   callee had already freed, which every local run survived and ASAN reported
   on `native_arr_fold_acc_leak_probe`; `march_vault_update` releases
   the current value only when it is a Float; `march_call` (FFI upcalls)
   retains each argument, keeping its documented borrow semantics.
6. **`pid_of_int` returns an owned reference** (`march_pid_of_int`). It returned
   the actor record without a count. That only stayed balanced while nothing
   dropped the Pid: `List.length` is a `go` apply fn, so with the pin it
   consumed `Actor.list()`'s list and released each pid, freeing live actors.
   `test/native/actor_enumeration.march` printed killed actors as alive, and
   SIGSEGV'd on some runs: the released record was reused as a list cell, so
   `is_alive` read false. `origin/main` was 6/6 correct, this branch 12/12
   after the fix. (`main` was safe only because a `List(Pid)` drop never
   reaches its pids; an explicit `dec_rc` of a Pid variable does.)

   An owned `pid_of_int` fails as a LEAK wherever a caller never releases the
   pid, never as a free: `send`, `is_alive` and the rest of the actor family
   are still classified owned and never release it. Marking `send`,
   `is_alive`, `get_actor_field` and `mailbox_size` borrowed was tried and
   backed out: it released pids returned by `spawn` and crashed
   `actor_mailbox_alarm`, `actor_stash_become`, `actor_stop_drains_mailbox`
   and `supervisor_deflected_crash_absorbed`. That half stays in
   `specs/todos/2026-09-13-send-leaks-a-reference-to-a-live-pid.md`, updated.

   The three tests that read an actor's refcount went red, for two reasons.
   Their probe `ffi_test_actor_rc` called `march_pid_of_int` itself, so every
   reading added one: it now reports the count without its own reference and
   releases it. And a pid minted inside a measured window now leaves one
   reference behind in `send`: `actor_dispatch_rc_window` and
   `actor_crash_rc_restore` mint the pid before the first reading, and
   `actor_send_to_self` expects exactly one reference per send (10), which is
   the leak that todo tracks.

### Corrected prediction

The design said #321's caller-side Float releases (`release_float_arg_boxes`)
must be deleted, because a consuming callee would free the call site's float
box. It does not: an apply fn's Float parameter is unboxed in its prologue
(`Llvm_toplevel.emit_fn`) and never an RC value in TIR, so the pin does not
touch it. The Float probe leg and `native_float_box_abi_leak_probe` stayed flat
with the pin and the releases in place. Float boxes remain the caller's, which
is why the runtime keeps its Float-tag checks.

## Not closed here

- `List.map(xs, fn s -> string_length(s) + k)` (a *capturing* lambda through
  `List.map`) still leaks 1 object per `map` call: `map`'s internal `go` closure
  is freed with a shallow `dec_rc go`, so its captured `f` is never released.
  That is item 2/3 of `specs/todos/2026-09-06-closure-capture-release-widening.md`,
  not an argument-ownership question (it leaked 2 per call before this change,
  1 after).
- `clo_call_dbl_dbl` / `clo_call_dbl_dbl_dbl` (`native_float_arr_map` and
  friends) allocate a Float box per call and never release it or the returned
  box. Compiled code usually takes the inline map loop instead.
- A closure parameter still typed `TVar` after mono, handed a Float box by a C
  helper, would release a box the helper also releases. Pre-existing in the
  fold helpers' Float-tag reasoning; not observed.

## Verification

- `test/native/closure_call_arg_ownership_probe.march`: 11 legs (reading,
  live-after, ignoring, storing lambdas; Float; record alias; `to_string`;
  `List.filter`; fold ignoring its element; named function via a list and to
  `List.map`), each printing its computed value (golden matches the
  interpreter) and asserting `< 200` objects over 5,000 calls. Before: 6 legs
  leaked 1–2 objects per call.
- **RED controls**, each reverting one piece with the rest in place, on the
  fixture: the apply-fn pin → 6 legs leak; the `$clo_wrap` releases → both
  named-function legs; the dead-parameter drops → both ignoring legs; the
  record-alias lowering → the record leg. The runtime element retain in
  `march_typed_array_fold` → `native_arr_fold_acc_leak_probe` SIGTRAP, 3/3.
  An unowned `pid_of_int` → `actor_enumeration` wrong output and SIGSEGV.
- **ASAN** (linux/arm64 container, `specs/lang/golden/sanitize.sh`): 71/71
  clean, plus 20 more native programs 3 runs each (this fixture, the fold,
  closure, show, builtin-borrow, niche, task and Float-ABI probes, and the actor
  rc / mailbox / stash / stop / supervisor goldens), all clean.
  `actor_enumeration` is a use-after-free under ASAN on `main` too, filed as
  `specs/todos/2026-09-14-actor-enumeration-use-after-free-under-asan.md`.
- Existing guards green: `native_arr_fold_acc_leak_probe` (its String legs are
  now held flat by the callee, not the retired header bit),
  `native_arr_fold_leak_probe`, `native_float_box_abi_leak_probe`,
  `closure_capture_release_probe`, the actor rc probes, the full
  `@test/runtest` alias, TIR snapshots unchanged.
- **Benchmarks** (compiled `--opt 2`, interleaved against `origin/main`
  61d5f167, 5 timed rounds, load ~7): `bench/list_ops.march` median 0.072 s
  vs 0.072 s, `bench/tree_transform.march` 0.695 s vs 0.703 s; outputs
  byte-identical. The extra callee-side releases and the dropped caller-side
  dups net out.
