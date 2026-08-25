# REPL JIT: a `fn` calling a previously REPL-defined `fn` produced invalid IR

**Status: fixed** (2026-08-24, both clang and ORC backends)

## Symptom

```
march(1)> fn f(x) do x + 1 end
val f = <fn>
march(2)> fn g(x) do f(x) end
jit error: clang failed (...): invalid redefinition of function 'f'
march(3)> g(41)
I cannot find `g`.
```

Same failure with a prior `let`-bound lambda as the callee (`let h = fn x ->
x + 5` then `fn g2(x) do h(x) end`). Interpreter mode (`MARCH_REPL_INTERP=1`)
handled the session fine.

## Root cause

Fn-defining REPL fragments expose prior bindings via module-level **slot
loaders** (`Llvm_repl.emit_slot_loader_fns` emits `define ptr @f()` reading
the binding's persistent slot), unlike expression fragments, which bridge
slots into `var_slot` allocas. The `EApp` emission path knew about neither
`top_fns` nor `var_slot` entries for `f`, so the call fell into the
unknown-function fallback — which emitted `declare ptr @f(i64)` for the very
symbol the loader defines in the same module. Invalid module; the whole
fragment (including `g`) was lost.

Note the collision partner was the **unknown-fn fallback declare**
(`llvm_emit.ml`'s EApp/ECallPtr catch-alls), not `partition_fns`/`extern_fns`
— `f` is not in the second fragment's TIR at all, so `partition_fns` never
saw it.

Even without the collision, a direct `declare`+call would have been wrong
twice over: the fallback's call-site-erased signature (`ptr @f(i64)`) does
not match the real fragment-0 define (`i64 @f(i64)`), and a direct extern
call would pin the callee version compiled at `g`'s definition time instead
of following the slot (see "Known limitations" in
`2026-08-24-repl-jit-fn-redefinition-silently-ignored.md`).

## Fix

Route calls to slot-loader names through the loader + closure dispatch:

- `Llvm_ctx.repl_slot_fns` — new ctx table; `emit_slot_loader_fns` records
  each bare binding name it emits a loader for.
- `llvm_emit.ml` `emit_atom`: new `AVar` arm (above the runtime-prefix /
  builtin first-class-value arms, so a REPL binding shadows a same-named
  builtin exactly as the expression-fragment `var_slot` bridge does) — a
  reference to a slot-loader name emits `call <ty> @<name>()`, materialising
  the slot's current value (the closure, for fn/lambda bindings).
- `llvm_emit.ml` `EApp`: new arm mirroring the existing var_slot→`ECallPtr`
  redirect — `EApp` of a slot-loader name (not in `top_fns`) becomes
  `ECallPtr (AVar f, args)`.
- `llvm_emit.ml` `ECallPtr` no-var-slot catch-all: excluded slot-loader
  names so they reach the generic closure-dispatch arm, whose `emit_atom`
  of the callee now yields the loader-loaded closure.

No declare is emitted (no collision), and the call goes through the
closure's `$clo_wrap` (uniform tagged-ptr ABI, correct for odd/even Int
results, Floats, Strings) reading the slot at **call time**.

## Verification

- `test/test_jit.ml`: 4 new subprocess session tests (`clang`/`orc` ×
  fn-calls-prior-fn / fn-calls-let-lambda), written first and failing 4/4
  before the fix. NOTE: run with `HOME` and `MARCH_BIN` set (the dune rule
  does this); without `MARCH_BIN` the sessions skip vacuously.
- Manual sessions on both backends: chained slot calls (`k → g → f`),
  odd/even Int results, String concat through two slot fns, Float chain
  (`quarter(x) = half(half(x))`), recursion + slot call (`fact(n) + f(0)`),
  prior-`let` capture, let-bound-lambda callee — all correct and matching
  interpreter semantics.
- Full suite green (see PR).

Non-REPL compilation is untouched: `repl_slot_fns` is only ever populated by
`emit_slot_loader_fns`, which only REPL fn-fragment emission calls.

## Still-open adjacent limitations (pre-existing, unchanged)

- `fn` redefinition was fixed separately (PR #339, landed the same day):
  a redefinition compiles under a fresh slot, so a direct call gets the new
  body while an earlier fn keeps reading the slot index it was compiled
  against — which is exactly interpreter mode's lexical semantics (verified:
  2 / 3 / 101 for the redefine-then-call session on interp, clang, and ORC).
  Pinned by the `redefine then call through prior fn` tests in
  `test/test_jit.ml`.
- Referencing a prior fn as a bare value (`let h = f`) errors ("unbound
  variable: f") — separate path, not addressed here.
- A later `let x = ...` REBINDING allocates a fresh slot; already-compiled
  fns keep reading the slot index captured at their compile time.
