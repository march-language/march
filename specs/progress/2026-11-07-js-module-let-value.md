# `--target js`: a non-entry module-level `let` read as its closure wrapper (#1170) (2026-11-07)

## Symptom

On `--target js`, a module-level `let` in any module other than the entry module (a nested
`mod`, a `MARCH_LIB_PATH` module, a stdlib module) evaluated to its closure-protocol
wrapper object: `println(int_to_string(Cst.n))` printed `[object Object]`, and
`Bytes.encode_base64` (which reads its module-level `let b64_alphabet`) threw
`TypeError: s.slice is not a function`. The interpreter and native were right, and so was
a `let` in the entry module.

## Cause

A non-entry module-level `let` is lowered to a zero-parameter function
(`lib/tir/lower.ml`, `lib/tir/lower_decls.ml`); the entry module's lets go into `top_lets`
and are injected as locals. `emit_atom` in `lib/tir/js_emit.ml` emitted `<name>$clo` for
every name in `fn_names`, so a value-position read of the zero-arg function got the
wrapper. Native calls it: `Llvm_ctx.zero_arg_fns` excludes zero-arg fns from the
function-pointer arm of `llvm_emit.ml`'s `emit_atom`, which then falls through to the
0-arg call path.

## Fix

`js_emit.ml` keeps `zero_arg_fns` (the zero-parameter subset of `fn_names`, filled with
it in `emit_module`). `emit_atom`'s `AVar` arm, for a name in `fn_names` that is not a
local: at a `TFn` type it still emits the `$clo` wrapper (native's TFn arm wraps it in a
closure too); otherwise, for a zero-arg fn, it emits `name()` (`(await name())` for an
async fn). It is called on every read, with no caching, as native does. `ADefRef` is
unchanged (native emits a function pointer for it).

## Tests

`test/native/module_let_value.march` (nested-mod `let` of Int, String and tuple; a
function reading one; the entry-module control; `Bytes.encode_base64`), expected output
from the interpreter, pinned on `--target js` by the `js_module_let_value` rules in
`test/dune`. Red before the fix (`[object Object]`, then the `s.slice` TypeError), green
after. The fixture is not `js_`-prefixed, so it also gets native IR-gate and
interpreter-oracle coverage.

## Not fixed here

A function-typed non-entry `let` (`mod Cst do let inc = fn x -> x + 1 end`, called as
`Cst.inc(4)`) is wrong on native as well as JS:
`specs/todos/2026-11-07-function-typed-module-let-outside-entry.md`.
