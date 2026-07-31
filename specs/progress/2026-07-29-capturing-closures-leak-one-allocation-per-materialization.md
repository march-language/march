- ✅ **Capturing closures leak one allocation per materialization (compiled) — FIXED 2026-07-29** (`lib/tir/borrow.ml` `infer_module`'s `init` pins apply-fn param 0 to owned; `lib/tir/perceus.ml` `insert_apply_fn_clo_drop` emits the matching callee-side release). Root cause: TWO independent notions of "$clo is borrowed" — the borrow map (what callers consult in Perceus's `EApp` case) and the per-function `borrowed` set (what suppresses the callee's drop) — disagreed, so the caller deferred to the callee and the callee deferred to the borrow map. A prior callee-only attempt produced 3 double-frees plus 8 stdlib crashes precisely because it flipped only the second. Measured: 4M-iteration loop 4,000,000 allocations / ~125 MB peak RSS → ~2.9 MB floor; `live_allocs` growth over 20,000 materializations 20,000 → bounded (`test_capturing_closure_materialization_no_leak_compiled`, verified non-vacuous against origin/main which reports `LEAKED 20000`). The drop is deliberately NOT emitted for capture-free apply fns: natively their closure is the immortal static global where a decrement is a no-op, but under the REPL/JIT (`static_closure_ok` is `not ctx.repl && ..`) it is a real allocation, and dropping it made `run_codegen`'s "stdlib List.length via precompile" jump through a zeroed apply-fn slot (EXC_BAD_ACCESS at 0x0, frame #0 = 0x0) while every native program stayed green. **Residual — FIXED 2026-07-29 (same-day follow-up).** A SELF-RECURSIVE capturing
closure leaked one allocation per top-level MATERIALIZATION (not per recursion
level — the whole recursion reuses one heap object via the self-binding alias).
`insert_apply_fn_clo_drop`'s single unconditional early drop cancels the
self-binding's protective `inc_rc $clo` (net zero) but never releases the
actual transferred reference, which flows unchanged through the recursion and
is abandoned at any base-case branch that never uses the self-binding again.
Fixed with a SECOND, path-sensitive pass (`insert_dec_on_dead_paths`, same
function): walks the body via `Dce.free_vars` and inserts an additional drop
exactly where the self-binding becomes dead, leaving live (recursive) paths
untouched. Both the unconditional early drop and the path-sensitive walk are
required — two intermediate versions were each broken a different way: the
walk alone left the protective inc permanently uncanceled on the recursive
path (rc grows unbounded); a naive "recurse into the let's tail" version of
the walk inserted a spurious SECOND drop on the live path when the consuming
call lived in the let's RHS rather than its tail (`let $t = ...call_ptr
helper(...) in +($t,k)`) — a double-free waiting to happen, not merely a
missed leak. Measured: `outer()` materializing a self-recursive `helper`
capturing `k`, looped 20,000 times, `LEAKED 20000` before, `BOUNDED` after.
Verified non-vacuous (via a `DUNE_CACHE=disabled` rebuild of the pre-fix file —
`--force` alone was insufficient, dune's shared cache served a stale artifact
on the first attempt). Two new regression tests in `test/test_codegen.ml`'s
`string_literal_codegen` group: the leak-bound assertion, and a fib-shaped
double-recursive-call correctness check (compiled vs. interpreted parity) to
catch an over-eager drop as a wrong value or crash rather than growth.

Investigated as a related follow-up but NOT fixed at the time (since FIXED —
see "Third attempt" below): extending this same capture-free-under-REPL gap
(the note above) by threading an `is_repl` flag into
`insert_apply_fn_clo_drop` reintroduced the EXACT SIGSEGV the guard exists to
prevent (`repl_jit_cross_line` test 7, "stdlib List.length via precompile") —
reverted. `task_spawn`-ing a genuinely capture-free closure from a REPL
fragment still leaked one allocation per materialization.

**Second attempt (2026-07-30), one real bug fixed, the leak still open.**
Traced the crash to a genuine, independent gap: `lib/tir/llvm_repl.ml`'s
persistent REPL variable slots (`@march_repl_get`/`@march_repl_set`,
`runtime/march_extras.c`'s `march_repl_slots` array) did **zero RC
bookkeeping** — every read of a heap-typed slot (a String, a closure, any
boxed value) handed out the slot's own reference with no dup, and every
overwrite discarded whatever reference the slot held with no release. A
capture-free closure bound at the REPL prompt and read back from a later
fragment was freed on the first call as a direct consequence: the read gave
the caller the slot's only reference, that reference got consumed, and the
slot was left holding a dangling pointer for its next read.

Fixed at the LLVM-emission call sites — `emit_prev_slot_bridges` and
`emit_slot_loader_fns` (two independent read sites for the same slot; a
prior binding can be referenced either bridged directly into a later
fragment's entry block or via a generated zero-arg loader function) now
`march_incrc` a heap-typed slot's value on every read; `emit_store_to_slot`
`march_decrc`s whatever the slot held before a write replaces it (this
matters concretely for the `"v"` magic slot — the last-expression-value
binding, genuinely reused/overwritten across every subsequent REPL
expression, unlike an ordinary `let` which gets a fresh slot per
declaration). All three gated on the *static* `Tir.ty` at the LLVM-emission
call site, deliberately **not** inside `march_repl_get`/`march_repl_set`
themselves: slots store `Int`/`Bool`/`Float` **UNTAGGED** — unlike March's
usual `(n<<1)|1` tagged-immediate convention — so a blind
`IS_HEAP_PTR`-gated incrc/decrc inside the untyped C functions would have
misfired on an ordinary integer whose raw bit pattern happens to look
pointer-shaped (caught this before it shipped, via a `git show`-sourced
diff against the pre-edit file — never actually built or run). Verified:
all 24 `repl_jit_cross_line`/`repl_jit_regression` tests pass with this fix
alone, including "var redefinition" and "P0: List.length x3 successive
fragments" — the shapes that actually exercise repeated slot access.

Re-threading `is_repl` on top of this fix hit the **same** SIGSEGV, in the
**same** test, at the **same** address (`0x0`, frame `0x0` — a jump through
a null code pointer). So the slot mechanism was real but not the whole
story: there is at least one more path, somewhere in how the precompiled
stdlib passes a capture-free closure around internally, that is not yet
understood. Reverted the `is_repl` threading again (verified via
`grep is_repl lib/tir/perceus.ml lib/jit/repl_jit.ml` → no matches);
**kept** the slot RC fix, since it is a real, independent correctness fix
regardless of whether the capture-free leak is ever closed.

**Third attempt (2026-07-30) — FIXED, and the crash the first two attempts
kept hitting was never the mechanism either of them guessed at.**

Diagnosed from an actual stack trace this time (`lldb -b` on
`_build/default/test/run_codegen.exe -e repl_jit_cross_line`, with the drop
forced on via a temporary env-var hack), which neither prior attempt took:

```
frame #0: 0x0000000000000000
frame #1: repl_0.so`go$apply$218 + 432
frame #2: repl_0.so`List.length$List_Int + 68
```

The crashing closure is `go`, the inner **self-recursive** helper of
`List.length` — and it is capture-free, which is exactly why a blanket
"drop capture-free apply fns under REPL" hit it. The over-release is
straightforward once the frame is visible: a self-recursive capture-free
apply fn ALREADY releases its own reference, through `lift_lambda`'s
self-binding alias, via completely ordinary RC insertion. Confirmed in the
emitted TIR (`MARCH_DUMP_TXT=perceus`):

```
fn go$apply($clo, lst, acc) =
  let go = $clo in
  case lst of
    Nil()        -> dec_rc go; dec_rc lst; acc
    Cons($f,$t)  -> ... call_ptr go(t, $t2)
```

`dec_rc go` on the dead path, transfer into `call_ptr go(..)` on the live
one — the alias is an ordinary owned local and Perceus handles it correctly
with no help. Adding an unconditional entry drop on top is a SECOND release
of the same reference: rc hits 0 on the first call, the closure is freed,
and the recursive dispatch reads a zeroed apply-fn slot. Hence frame #0 =
0x0. Native never showed it because `static_closure_ok` routes native builds
to the immortal global, where the over-release cannot reach 0.

**The fix, and the third mechanism.** Two changes, each covering one of the
two capture-free shapes; the second was found by measurement AFTER the first
was green, and is genuinely independent:

1. `lib/tir/perceus.ml` `insert_apply_fn_clo_drop ~repl` (threaded through
   `insert_rc` ← `perceus ~repl` ← `lib/jit/repl_jit.ml`'s `lower_module`,
   which passes `~repl:true` to match `Llvm_emit`'s `ctx.repl` exactly).
   Under REPL only, an apply fn whose body mentions `$clo` **nowhere** gets
   an entry `dec_rc $clo`. The `not (mem $clo (free_vars body))` test is the
   whole correctness story: it is precisely what excludes the self-recursive
   case above, which mentions `$clo` via its self-binding and must stay
   untouched. Covers capture-free **lambdas**.

2. `lib/tir/llvm_calls.ml` `clo_wrap_define ~drop_clo` (passed
   `~drop_clo:ctx.repl` at all three emission sites — two in
   `lib/tir/llvm_emit.ml`'s `emit_atom`, one in `lib/tir/llvm_repl.ml`'s
   `emit_repl_fn_with_closure_slot`). Covers capture-free **top-level
   function values**, which materialize an `@<fn>$clo_wrap` trampoline that
   is synthesized at LLVM emission and has no TIR apply fn at all — so
   Perceus can never reach it, and change (1) alone left it leaking at the
   full pre-fix rate. This is sound alongside PR #123's slot-read `incrc`:
   a slot-held closure now hands out a fresh reference per read, which the
   wrapper's drop balances.

**Measured** (new `test/test_codegen.ml` regression,
`repl_jit_cross_line` "capture-free closure materialization does not leak",
reading `march_live_allocs` via `dlsym` out of the JIT's own runtime `.so`
so the fragments under test stay ordinary REPL input): over 2,000
materializations in a REPL fragment, both shapes grew by exactly **2,000**
before and **0** after. Each half is pinned independently — with only (1)
applied, the lambda phase reports 0 and the top-level-fn phase still
reports 2,000.

**Native impact: none, and proven rather than argued.** Both arms are gated
on `repl`/`ctx.repl`, and a program exercising both closure shapes plus
`List.length` emits **byte-identical** `--emit-llvm --opt 2` IR before and
after (928 lines, `diff` clean), with identical program output.

Verified: `repl_jit_cross_line` fully green (10/10 including the new test)
and re-run 20x for the flakiness this area has a history of (0 failures);
full `dune build --root . @runtest` green apart from
`adversarial-regressions` 39 (`MARCH_SANITIZE` 30s timeout), confirmed
**pre-existing** by reverting the five source files to base via file-copy
swap (never `git stash` in a march worktree) and reproducing it there.

  **Follow-up audit (2026-07-29, same day): the $clo drop is only sound because every C-runtime call site that invokes a closure's apply function now agrees on the calling convention — and four distinct families of call sites did not, each fixed in `runtime/march_runtime.c` / `lib/tir/llvm_emit.ml`:**
  - `__try_call`/`__try_call_val` (runtime/march_runtime.c) called their thunk once then explicitly `march_decrc`'d it — a second consumption of the reference the thunk's own apply function already released. Flaky, not deterministic (6/30 crashes on a single-capture thunk before the fix, 0/30 after) — freed memory frequently still looked valid enough not to crash immediately. `__try_call` is directly user-callable (`tir_names.ml` documents this) and one of `test/imports/erased_clo_native`'s dune-rule golden tests hit this exact shape, which is how it was traced after CI stayed red past the first (task_spawn) fix.
  - `march_typed_array_map`/`_fold` and `native_int_arr_map`/`map2`/`native_float_arr_map`/`map2` call the SAME closure once per array element without transferring ownership per call — fixed with `march_incrc` before each call plus one `march_decrc` after the loop, since the closure arrives as exactly one transferred reference (confirmed via TIR: `inc_rc closure; NativeArray.map_int(a1, closure)` is emitted only when the closure is still live afterward).
  - A parallel, LLVM-IR-level inline fast path for the same builtins (`lib/tir/llvm_emit.ml`'s `emit_native_map_inline_loop`/`emit_native_map2_inline_loop`, P10 Phase 2c) bypasses the C runtime entirely and needed the identical incrc-per-call-plus-final-decrc fix at the IR-emission level — this is why `test/native/native_arr_map_inline_capture.march` and 4 sibling goldens kept crashing even after the C-runtime functions were fixed.
  - `march_signal_drain` calls a registered watcher closure repeatedly, once per signal delivery, for the program's entire lifetime, without transferring ownership on any call — fixed with `march_incrc` before each `apply()` call and (unlike the array builtins) no matching decrc, since the watcher table's one held reference persists across drains and is released only by the existing replace/unwatch path. Deterministic, not flaky: a capturing watcher raised twice crashed on delivery 2 every run before the fix.
  - The actor message-dispatch loop (`runtime/march_runtime.c`'s `actor_green_thread`) has the identical shape — a long-lived closure invoked once per inbound message — and received the same defensive fix, though whether today's actor lowering can actually produce a CAPTURING dispatch closure (as opposed to always capture-free) was not independently confirmed; applied given the severity of the failure mode and the exact shape match with the confirmed Signal.watch bug.

  All four were caught by running `dune build @runtest` (the full CI-equivalent suite, including every dune-rule golden/native test) — `scripts/run-tests.sh` and the four alcotest binaries alone never exercise dune-rule tests and reported fully green while `test/imports/erased_clo_native` and 5 native array-map goldens were failing in CI. New alcotest regressions in `test/test_codegen.ml`'s `try_call_capture_ownership_codegen` group cover all four shapes (single-capture `__try_call`/`__try_call_val`, the panic/longjmp path, a closure reused after `NativeArray.map_int`, and a Signal.watch handler delivered 3 times), each run 15–30x since several of these are heap-timing-dependent rather than deterministic.
