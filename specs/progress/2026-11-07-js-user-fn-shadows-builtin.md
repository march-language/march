# A user fn named like a builtin is called on `--target js`; `not(<literal>)` folds respect a user `fn not` (#1177) (2026-11-07)

## Symptom

On `--target js`, an entry-module top-level `fn negate` was never called: `negate("a")`
compiled to `(-"a")` (NaN), and prefix `-y`, which lowers to a `negate` call, to the JS
negation. `fn not` was ignored the same way through `not(x)` and `!x`. A user fn named
like a builtin that JS also exposes as a first-class value (`int_mod`, `int_xor`,
`string_length`, `float_to_string`, ...) made the module fail to load:
`SyntaxError: Identifier 'int_xor' has already been declared`. Separately, `not(true)` /
`!false` were folded to the builtin result by name before codegen, so native also ignored
a user `fn not` for a literal argument. The interpreter called the user fn throughout.

## Cause

- `emit_val_impl` (`lib/tir/js_emit.ml`) dispatches every builtin arm on the callee's bare
  name, with no check that a user function owns that name. Native solved this with
  `shadows_dispatched_builtin` (`lib/tir/llvm_emit.ml`), an arm ahead of the builtin arms.
- `emit_module` declared `const <name> = { _0: ... }` first-class wrappers for some
  runtime-backed builtins unconditionally, next to the user's `function <name>`.
- `lib/tir/fold.ml` and `lib/tir/simplify.ml` folded `not(<bool literal>)` by name. They
  also synthesise calls to `not` (`x == false` / `false == x` -> `not x`; `if x then false
  else true` -> `not x`), which with a user `fn not` would call it, since the backends route
  a `not` call to the user fn.

## Fix

- `js_emit.ml`: `shadows_js_builtin ctx name` is `fn_names` membership (builtins have no
  March definition, the same discriminator as native's `top_fns`), except `panic`:
  Prelude's own `fn panic(msg) do panic_(msg) end` is in `tm_fns`, its JS arm is the same
  behaviour, and an entry module cannot define `panic` (Prelude_collision rejects it). An
  `EApp` arm ahead of all the bare-name arms emits a plain call through the new
  `emit_direct_call` helper, which the general-call fallback now uses too. This covers
  every bare-name arm in `emit_val_impl` (`inline_binop`'s named forms, `negate`/`not`,
  `int_*`, `string_*`, `math_*`, the `eq_`/`neq_` prefix arms, and the rest), not only
  `negate`/`not`. It goes further than native's predicate (`Builtin_name` plus
  `is_int_bitwise`) because JS dispatches by name on names native does not
  (`string_length`, `math_sqrt`, `int_to_string`, ...). An audit program shadowing
  `string_length`, `int_xor`, `math_sqrt`, `int_to_string`, `negate` and `not` now prints
  the same on all three backends. `println` gets no exception: a user `fn println` now
  runs on all three backends. Prelude's `println` is normally absent from `tm_fns` (its
  calls are the builtin); when it is present (used as a first-class value,
  `List.each(xs, println)`) its calls now go through it, as on native. That program fails
  on `--target js` before and after this change (Prelude `println`'s body calls `show`,
  which has no JS mapping) and crashes natively, both independent of this fix.
- `emit_module` skips a first-class builtin wrapper whose name is in `fn_names`.
- `Fold.has_user_not m` (a top-level fn named `not` in `tm_fns`) gates the
  `not(<literal>)` fold and the `x == false` -> `not x` rewrites in `fold.ml`, and the
  `not(<literal>)` fold and the `if x then false else true` -> `not x` rewrite in
  `simplify.ml`. A module without a user `not` is unchanged.

## Tests

- `test/native/shadowed_negate_not.march`: user `negate`, `not`, `string_length`,
  `int_xor`, each with a marker println; `-y`, `negate(y)`, `!t`, `not(t)`, `not(true)`,
  `!false`, `t == false`. Expected output from the interpreter, pinned on `--target js`
  (`js_shadowed_negate_not`) and natively (`native_shadowed_negate_not`) in `test/dune`.
  Red before: JS failed to load (`int_xor` redeclared); native printed `false` for
  `not(true)` and `true` for `!false` with no marker. Green after.
- `test/native/shadowed_builtin_name.march` (the native witness for
  `shadows_dispatched_builtin`) is now also run on `--target js` (`js_shadowed_builtin_name`).
  Red before (`Identifier 'int_mod' has already been declared`), green after.
