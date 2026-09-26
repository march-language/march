# DONE A non-inlined user fn named like a builtin was emitted under the builtin's C symbol

Filed 2026-09-25 while closing
`specs/progress/2026-09-25-runtime-symbol-naming-and-uncompiled-caps.md`.
Fixed 2026-09-25.

## The bug

The entry module's top-level functions keep bare names in TIR (lowering strips
the entry module's name). Codegen turns every function name into a symbol with
`Llvm_builtins.mangle_extern`, at definitions and at references, and
`mangle_extern` looks the bare name up in the builtin table first. So a user

```march
fn file_read(x : Int) : Int do ... end    -- any of the ~330 names with a c_name row
```

that survived to emission (too big to inline, or used as a value) was emitted
as `define i64 @march_file_read(i64 %x.arg)`. That collided with the
preamble's `declare ptr @march_file_read(ptr)`, and clang failed with
`invalid redefinition of function 'march_file_read'`. The interpreter ran the
program fine. A small function is inlined and never emitted, so the bug hid
until the function grew.

## What a bare name means (the interpreter is the reference)

Measured with a program whose shadow has the builtin's type
(`fn int_to_string(x : Int) : String`), so the typechecker accepts every use:

| reference to the shadowed name                      | interpreter | typechecker binds |
|-----------------------------------------------------|-------------|-------------------|
| entry fn body (incl. one declared before the shadow)| user fn     | user fn           |
| nested `mod Inner` in the entry file                | user fn     | builtin           |
| `impl` method body in the entry file                | user fn     | user fn           |
| the shadow's own body (self-call)                   | user fn     | builtin           |
| stdlib code (`String.reverse` → `string_reverse`)   | builtin     | builtin           |

The two "builtin" cells for the typechecker are a separate, typecheck-side
split (repo memory `module_fn_shadowing_builtin_typecheck_runtime_split`):
with a shadow of a DIFFERENT type they are type errors, so no such program
reaches codegen. With a compatible type they run the user fn in the
interpreter, and the compiled build now does the same.

## The fix: disambiguate at lowering, where scope is known

The TIR name alone cannot tell the user's fn from the builtin: the prelude is
unwrapped into the entry module with bare names too, and the stdlib modules
lowered into the same program call builtins by bare name. So the decision is
made while lowering, and the result is a distinct TIR name.

- `Tir_names.builtin_shadow_name n = n ^ "$u"` (the same suffix
  `Llvm_builtins.user_symbol_of` already gives a user fn named like a libc
  symbol; `$` is unlexable, so no user name collides with it).
- `Lower.lower_module` computes `Lower_state._entry_builtin_shadows`: the
  top-level `DFn`s written in the entry file (span file = the entry module's
  file, so the prelude and stdlib decls in `m.mod_decls` do not count) whose
  name `Llvm_builtins.has_c_mapping`, except `main` (mapped to `march_main` by
  design) and a fn with default arguments (lowered only as `name$N`, which
  never collides). New optional `?shadow_builtins` (default `true`); the REPL
  JIT passes `false`, because it binds fragments' fns by bare name through
  closure slots and already keeps runtime-defined names out of a fragment
  (`is_c_runtime_fn`).
- `Lower_state._builtin_shadows` is the table in effect for the code being
  lowered, consulted by `resolve_use_alias` right after the local-binding
  checks. It is:
  - the entry table inside every top-level declaration written in the entry
    file (`with_decl_builtin_shadows`, applied per decl in Pass 1's impl
    collection and in Pass 2; Pass 1 now calls `collect_iface_impls` one
    top-level decl at a time, which is equivalent because it keeps no state
    across top-level decls);
  - minus a nested module's own fn names inside that module
    (`hiding_builtin_shadows` in `lower_mod_decls`, the `DMod` recursion of
    `collect_iface_impls`, and `Lower_tests`);
  - empty in stdlib / prelude / other-file declarations, and inside a lazily
    lowered stdlib module (`_ensure_module_lowered`), which can be triggered
    from inside an entry fn's body.
- Pass 2 renames the `DFn`'s own `fn_name` through the same table.
- Only references written in the source go through `resolve_use_alias`, so a
  builtin call that lowering synthesises itself (e.g. `register_resource`)
  is untouched.
- `Vectorize_mark` matches a `@vectorize` fn by source name; it also accepts
  the shadow name.

The new name survives the rest of the pipeline without special cases: mono's
specialisations append `$…` after it, `mangle_extern` passes a `$`-containing
name through unchanged, and consumers that match by base name
(`strip_specialization_suffix`, `--compile-so` exports, contracts) strip it
back to the source name. `Purity` strips to the base name and so treats a
call to the shadow as the (impure) builtin, which is conservative.

## Capability attribution: locals are not builtins

`Cap_attrib.walk` masked a call to a DEFINED name (`~is_defined`). Before the
rename, that also accidentally masked a call through a local of the same name
(`fn call_param(file_read : Int -> Int, x : Int) = file_read(x)`), because
the user's `file_read` was "defined". With the user fn now defined as
`file_read$u`, the fixture's `call_param` was charged `IO.FileRead` and the
compiled build failed the ceiling. The walk now tracks locally bound names
(fn params, `let`, case-branch vars, `letrec` fns and their params) and never
charges a call or value reference through one.

Related, NOT fixed here: the typecheck-side capability scan has the same
false positive for a program with a parameter named like a capability builtin
and NO top-level fn of that name (`function bodies in M call builtins that
require Cap(IO.FileRead)`), interpreted and compiled alike.

## Evidence

- New native golden `test/native/user_fn_named_like_builtin.{march,expected}`
  (dune rules `native_user_fn_named_like_builtin` and
  `interp_user_fn_named_like_builtin`, 2 lines in
  `test/refine_audit/corpus.baseline`). `.expected` is the interpreter's
  output; both backends are diffed against it. It defines `file_read`,
  `dns_resolve`, `string_reverse`, `string_repeat` and `int_to_string` at top
  level (each calling recursive helpers, called from two or more sites,
  `file_read` also passed as a value), uses the entry shadow from a nested
  module and an `impl` body, gives a nested module its own `string_repeat`,
  calls a parameter named `file_read`, and calls `String.reverse` (the stdlib
  wrapper around the builtin `string_reverse`).
- RED on origin/main (`d39d1d454`): the interpreter prints the golden;
  `--compile` fails with `error: invalid redefinition of function
  'march_file_read'` (`define i64 @march_file_read(i64 %n.arg)`).
- GREEN: both dune rules match byte-for-byte. The neighbouring name-collision
  goldens `shadowed_builtin_name`, `c_symbol_collision`, `user_fn_named_own`
  and `prelude_scope_user_shadow` still match.
