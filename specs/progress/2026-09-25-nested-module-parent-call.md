# `[P2]` DONE A nested module's call to an enclosing module's function fails to LINK

Filed 2026-09-24 while fixing `stdlib/compress.march`'s hidden type errors
(`specs/progress/2026-09-24-stdlib-compress-error-type.md`). Fixed 2026-09-25.

## The bug

```march
-- lib/outer.march   (reached through MARCH_LIB_PATH, or any stdlib module)
mod Outer do
  pfn helper(x : Int) : Int do x + 1 end
  mod Inner do
    fn f(x : Int) : Int do helper(x) end
  end
end

-- main.march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(Outer.Inner.f(41)))
  end
end
```

`MARCH_LIB_PATH=lib march main.march` printed `42`. `march --compile` failed at
link time: `"_helper", referenced from: ... ld: symbol(s) not found`.

The todo said the same shape written inside the entry module links. It does
not. `mod Main do mod Outer do ... end ... end` fails to link the same way. It
only works when `helper` sits at the entry module's own top level, whose fns
keep their bare names.

The workaround, the qualified spelling `Outer.helper(x)`, had two problems:

- when `Outer` is a registry module (every stdlib module), a `pfn` spelled that
  way was rejected as "Function `helper` is private to module `Outer`", though
  the caller is lexically inside `Outer`. That is why `Compress.lift_encode_error`
  / `lift_decode_error` had to be public.
- when `Outer` is in the same file, `Outer.helper` resolved only through the
  typechecker's dot-suffix fallback, so it meant whatever bare `helper` meant
  at the call site. If the nested module had its own `helper`, it got that one.

## Cause

**Lowering.** A nested module's fns are emitted as `<prefix><name>` (for
example `Outer.helper`). Bare references are then rewritten to match by
`Lower_decls.rename_tir_vars prefix direct_fn_names`. Both nested-module
walkers apply it with the fns of the module being lowered only:
`lower_mod_decls` in `lib/tir/lower.ml`, used for the entry module's `DMod`s,
which include every `MARCH_LIB_PATH` and stdlib module, and
`lower_stdlib_mod_decls` in `lib/tir/lower_decls.ml`, the on-demand stdlib
loader. So `Inner`'s bare `helper` matched nothing and was emitted bare.

`Lower_state.resolve_use_alias` had a matching gap. `_current_module_fns`
holds only the current module's names, so a bare call to an enclosing
module's fn fell through to the program-global `_use_aliases` table. Any
other module's `import` of a same-named fn could hijack it there.

**Typecheck.** A `DMod`'s body binds its own fns bare. Nothing binds the
enclosing module's fns under their qualified names. `Outer.helper` from inside
`Inner` therefore failed `lookup_var` and fell to `resolve_qualified_var`,
which reads registry exports, so a private member was reported as private. In
a file with no registry entry, it fell to the dot-suffix fallback instead.

## Fix

- `Lower_decls.rename_scoped_vars scopes fn` applies `rename_tir_vars` once
  per level: the module itself first, then each enclosing module out to, but
  not including, the entry module's unprefixed top level. After the inner pass
  has rewritten `f` to `Outer.Inner.f`, the outer passes, which match bare
  names, can no longer touch it. An inner fn therefore shadows an outer one of
  the same name, and a local binder still shadows both (`rename_tir_vars` is
  scope-aware). `lower_mod_decls`, `lower_stdlib_mod_decls`, and the
  nested-actor path thread an `enclosing` list through their recursion and use
  it.
- `Lower_state._enclosing_module_fns` / `with_enclosing_module_fns`: the
  enclosing levels' bare names. `resolve_use_alias` leaves them bare, and the
  rename qualifies them. The check runs after the current module's own import
  aliases (an import in the inner module is the nearer binding) and before
  the global table.
- Typecheck `DMod`: before a nested module's body is checked, each fn of the
  enclosing module (`env.local_fns`) is also bound as
  `<cap_qual_prefix>.<fn>` with the bare name's scheme, in the nested module's
  env only. The export step re-exports `pub_set` members only, so nothing
  leaks. A lexically enclosed qualified call to a `pfn` now typechecks and
  names the right fn.
- `stdlib/compress.march`: `lift_encode_error` / `lift_decode_error` are
  `pfn` again, and the Gzip/Deflate/Zstd/Brotli wrappers call them by their
  bare names.

Not changed: impl-method bodies (`collect_iface_impls`) and test bodies
(`Lower_tests.collect_tests`) inside a nested module still qualify only
their own module's fns.

## Evidence

- `run_codegen` group `nested_module_parent_call`, 3 tests, all RED with the
  four compiler sources swapped back to `origin/main`, all GREEN with the fix:
  - `MARCH_LIB_PATH` two-file program: a parent `pfn` declared before the
    nested module, a parent `fn` declared after it, two levels of nesting, an
    inner fn shadowing an outer one, and a qualified `Outer.helper`. Compiled
    output `42 40 300 51 102 9`. RED: `"_helper"` undefined at link.
  - the same modules nested in the entry file. RED: same link error.
  - `Outer.helper(x)` from an `Inner` that has its own `helper : String ->
    String`, interpreted and compiled, prints `42!`. RED: rejected by the
    typechecker (`expected Int but got String`), because the suffix fallback
    picked Inner's `helper`.
- The stdlib ratchet (`run_compiler`, "stdlib internal-type-error ratchet")
  with the lifts made `pfn` but still called qualified: 15 errors in
  `compress.march` without the typecheck fix, 0 with it.
- A compiled program calling `Compress.Gzip.decode` against the new
  `compress.march` fails to link with the `origin/main` compiler and prints
  `invalid_input` with the fix. `run_stdlib` group `compress stdlib` (32
  tests, including the Slow compiled + interpreted
  `decode errors are Compress.Error`): green.
- `march --check --stdlib-source` over every `stdlib/*.march`, with the pre-
  and post-change compilers and separate HOMEs: byte-identical output.
- `run_compiler -q`: 1222 tests green.

Still open: the INTERPRETER's version of a related case, where a nested module
calls a parent fn declared after it, fails with "stub ... called before
initialisation". Filed as
`specs/todos/2026-09-25-interp-nested-module-forward-parent-fn-stub.md`.
