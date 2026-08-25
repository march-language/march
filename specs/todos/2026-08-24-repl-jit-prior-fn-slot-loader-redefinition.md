# `[P2]` REPL JIT: defining a fn that calls a fn from an earlier line fails with "invalid redefinition"

```
$ march
march(1)> fn a1(x : Int) : Int do x + 1 end
val a1 = <fn>
march(2)> fn b1(x : Int) : Int do a1(x) * 2 end
jit error: clang failed (IR preserved at .../repl_1.ll):
  <stdin>:503:12: error: invalid redefinition of function 'a1'
march(3)> b1(5)
I cannot find `b1`.
```

Both backends (ORC reports it as `LLVMParseIRInContext: invalid redefinition of
function 'a1'`). Independent of lambdas — the bodies above contain none.
Pre-existing: reproduced on unmodified sources, not introduced by
`specs/progress/2026-08-24-defun-capture-shadowing-and-repl-fn-lambda-fragment.md`,
which is where it was noticed.

## Root cause (confirmed by reading the emitted IR)

`b1`'s fragment ends up with `a1` at TWO different arities:

```llvm
declare ptr @a1(i64 %arg0)      ; from extern_fns — a1's real signature
define ptr @a1() {              ; from emit_slot_loader_fns — the slot reader
entry:
  %raw = call i64 @march_repl_get(i64 0)
  ...
}
  %cr2 = call ptr @a1(i64 %ld1) ; b1's body wants the real one
```

`Repl_jit.run_decl` registers every REPL-defined `fn` in `ctx.var_slots` (so a
LATER fragment can load its closure value out of the persistent slot) AND in
`ctx.compiled_fns` (so a later fragment `declare`s it as an extern). When the
next fragment needs both — `a1` is a prior slot AND a callee — the two
mechanisms emit the same LLVM symbol name:
`Llvm_repl.emit_slot_loader_fns` emits `define <ret> @<bare>()` for each prior
slot, while `Llvm_toplevel.fn_declare_str` emits `declare` for each extern.

A `let`-bound value has no such conflict (it is never also a top-level symbol),
which is why only the fn-after-fn shape breaks.

## Sketch of a fix

The slot loader needs a name that cannot collide with the function's own
symbol — e.g. emit it as `@<bare>$slot_load` and have the bridging lookup ask
for that name — or `emit_slot_loader_fns` should skip any slot whose bare name
is already being `declare`d as an extern fn in this fragment (the body then
resolves the direct call, and the first-class-value path still has the
`$clo_wrap` trampoline). The first is the safer of the two: skipping loses the
ability to reference the prior fn as a VALUE in that same fragment.

Regression test belongs in `test/test_codegen.ml`'s `repl_jit_cross_line`
group, modeled on `test_repl_jit_fn_lambda_shadows_hof_param` — two
`run_decl ~is_fn_decl:true` calls followed by a `run_expr`, asserting `b1(5)`
is `"12"`.
