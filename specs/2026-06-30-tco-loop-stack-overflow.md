# TCO loop stack growth from per-iteration `alloca`, and a Perceus tail-call detection gap

**Status: FIXED (2026-06-30).** Both fixes are in `lib/tir/llvm_emit.ml`.

## 1. Symptom

`Bytes.from_string` (stdlib, `stdlib/bytes.march`) crashed with SIGBUS/SIGSEGV on inputs
above roughly 10,000 characters, despite its recursive helper (`from_string_go`) being a
straightforward accumulator-passing tail call that the compiler's TCO machinery correctly
identified and compiled as a back-edge loop (confirmed via disassembly — no `bl` self-call,
a genuine backward branch). `Bytes.length` (`list_len`) crashed similarly around 200,000
elements, but disassembly showed it was **not** compiled as a loop at all — a plain
recursive `bl` call, real stack growth.

This mattered beyond the stdlib: forgepm's publish route parses uploaded tarballs via
`Bytes.from_string`/`Bytes.length`, so a large-enough package upload would crash the server
even after the unrelated cross-module `Option`-repr bug (see
`specs/2026-06-30-mono-cross-module-option-repr-bug.md`) was fixed.

## 2. Root cause 1 — TCO loop bodies leak stack space per iteration

A self-tail-recursive function is compiled as `entry → br loop; loop: ...; br loop` (a
back-edge), which is correct for eliminating *call-frame* growth. But the loop *body*
between the header and the back-edge still contains ordinary `alloca` instructions — for
case-branch bindings, tuple/struct construction, closure environments, etc. — emitted by
the normal expression-emission code path, which does not know it is inside a TCO loop.

LLVM's `alloca` has stack-allocation-once-per-*execution* semantics: a constant-size
`alloca` textually inside a loop is **not** hoisted to a single static frame slot, because
each pass through the loop body executes the instruction again and must get a distinct
address (the value could still be live from the previous iteration in general). The
backend lowers this as a genuine dynamic `sub sp, sp, #N` at the point of the `alloca`,
and that space is only reclaimed by the function's `ret` — never by a loop back-edge.
Confirmed on the compiled binary: `_Bytes.from_string_go`'s disassembly showed 5+ dynamic
`sub sp,sp,x / str .. [sp] / ...` sequences between the loop header and the back-edge, with
no matching restore before branching back — so `sp` marches downward by a bounded-but-nonzero
amount on every iteration, unboundedly over enough iterations.

**Verified in isolation** with hand-written LLVM IR before touching the compiler:
```llvm
; loop with `alloca [64 x i8]` + memset in the body, no stacksave/restore
; running with n=1,000,000 → EXIT=139 (SIGSEGV, stack overflow)
```
Adding `%sp = call ptr @llvm.stacksave()` at the loop header and
`call void @llvm.stackrestore(ptr %sp)` immediately before the back-edge → `EXIT=0`.

### Fix

- Added `tco_stack_save : string` (single-function TCO) and `mutual_tco_stack_save : string`
  (combined mutual-recursion TCO) fields to the emitter context, holding the SSA value name
  of the `llvm.stacksave()` result taken once at the top of the loop header (after the
  reduction-budget check, before installing TCO context).
- Declared `llvm.stacksave`/`llvm.stackrestore` in the module preamble.
- Every back-edge site (`ELet`-wrapped Perceus TCO, plain `EApp` TCO, and the mutual-TCO
  `EApp` redirect) now emits `call void @llvm.stackrestore(ptr %sp)` immediately before the
  `br label %loop`, after storing the new argument values into the parameter slots (order
  doesn't matter here since the values being decremented/stored are already-materialized SSA
  registers, not memory reads that could be invalidated by the restore).

## 3. Root cause 2 — a second, unmatched Perceus tail-call shape

Fixing (2) alone did not fix `Bytes.length`/`list_len`, because that function wasn't being
recognized as tail-recursive at all. Its TIR:

```
fn my_len(xs, n) : Int =
  case xs of
  Nil() -> n
  Cons($f1, $f2) ->
    let t = inc_rc $f2; $f2 in
    let n2 = +(n, 1) in
    my_len(t, n2);      -- tail call
    dec_rc t            -- runs AFTER, per March's borrow-argument calling convention
```

i.e. `ESeq(EApp(self, args), EDecRC(t))` — the call is **not** wrapped in an `ELet`. The
existing Perceus-wrapped-TCO handler only matched `ELet(tmp, EApp(self,args), body)` where
`body` is a trivial dec-chain *returning* `tmp`. This shape arises specifically when the
matched constructor wildcards a field (`Cons(_, t)` — no binding needed for the discarded
head), so Perceus has no need to bind the call's result to a temp before decrementing; it
just runs the call, then releases the local `t` the caller no longer needs (arguments are
borrowed by callees under March's convention, so the caller decrements its own copy after
the call returns).

The generic `ESeq` case in `emit_expr` unconditionally clears `tco_in_tail` before emitting
`e1` (since `e1` is not syntactically in tail position from a naive read), so the self-call
compiled as an ordinary `call` — real, unbounded stack growth, silently. No warning, no
error — just a stack overflow for sufficiently large inputs.

### Fix

Added `is_trivial_dec_chain` (checks that an expression is a chain of only
`EDecRC`/`EIncRC`/`EAtomicDecRC`/`EAtomicIncRC`/`EFree` — no `ELet`, no trailing "return
value" atom) and a new `emit_expr` case matching
`ESeq(EApp(f, args), dec_chain) when ctx.tco_in_tail && f is self && is_trivial_dec_chain dec_chain`.
Mirrors the existing `ELet`-wrapped case: evaluate new args, run the dec/inc chain (old
parameter slots still valid), store new args into the parameter slots, stackrestore, back-edge.

## 4. Validation

- Minimal repro (`my_len` matching `Cons(_, t)`, 200,000-element list): before fix, SIGBUS;
  after fix, disassembly shows a back-edge loop (no `bl` self-call) and the program exits 0.
- `Bytes.from_string` + `Bytes.length` combined, 200,000-character string: exits 0, prints
  correct length at every stage (was crashing at ~10,000 for `from_string`, ~200,000 for
  `length`, before either fix).
- Full march regression suite, all green, zero new failures:
  `run_compiler.exe` 372/372, `run_eval.exe` 224/224, `run_codegen.exe` 322/322,
  `run_stdlib.exe` 788/788 (including the "slow" tests the quick suite skips).
- forgepm's full Playwright suite: 7/7 publish tests, 29/30 overall (see
  `specs/2026-06-30-mono-cross-module-option-repr-bug.md` for that validation's details).

## 5. Known limitation not fixed here

Nested (non-top-level) `fn go(...) do ... end` closures that self-recurse do **not** get
TCO at all — they compile as an indirect call through the closure's `$apply` wrapper
(`blr`/indirect call), never as a loop back-edge, regardless of either fix above. Only
top-level `pfn`/`fn` self-recursion is eligible for the TCO transform. `stdlib/bytes.march`
originally used this nested-closure pattern in seven functions and was rewritten to lift
each `fn go` to a module-level `pfn` helper — the actual fix for the *reachability* of TCO,
independent of the two bugs in this doc, which are about TCO *correctness* once a function
is eligible. If a future change reintroduces nested self-recursive closures in a hot path,
they will silently NOT be tail-call optimized.
