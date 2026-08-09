# Native `from_json` ICE → single-impl resolution + clean ambiguity diagnostic

**Fixed 2026-08-08.** `march --compile test/stdlib/test_json_typed.march` died with
an internal compiler error (exit 3): "llvm_emit: unresolved interface-method call
to `from_json` reached codegen unspecialized … refusing to silently bind".

## Root cause

`from_json` dispatches on its **result** type — its argument is always a
`JsonValue`, the same in every impl — so mono's first-argument interface
dispatch (`resolve_impl_by_type` on the first arg's type name) can never match
a `JsonFrom$T.from_json` impl (registered under `T`, not `JsonValue`). Worse,
the typechecker does not back-propagate the target type into the call's
span, so the call-site result type in TIR is an unpinned TVar
(`Result('_37892, DecodeError)`) even when a field of the decoded value is
used — full return-type dispatch is unreachable at the mono layer with
today's type_map (see `specs/todos/2026-07-31-from-json-return-type-dispatch-unimplemented.md`,
still open).

Two failure modes existed, depending on whether the impls survived to
`ctx.top_fns`:

- impls referenced elsewhere (the test file) → the llvm_calls guard fired →
  ICE, exit 3;
- impls dropped by mono's reachability walk (a minimal single-derive
  program!) → the guard saw no candidates → bare `declare @from_json` →
  raw `Undefined symbols: _from_json` linker error.

Notably the **single-derive** case — one `derive Json` in the module, the
common real-world shape — was genuinely unambiguous yet still failed to link.

## Fix (two layers)

1. **`Mono.return_position_single_impl`** (`lib/tir/mono.ml`, wired into both
   the EApp and ECallPtr unresolved-callee branches): when first-arg dispatch
   fails but exactly ONE distinct impl symbol is registered AND that impl's
   own first parameter type equals the call's first-argument type (proving the
   argument is not the dispatch position — the call typechecked against this
   very signature), resolve to that impl. Single-derive `from_json` now
   compiles and runs natively.

2. **`Llvm_calls.Ambiguous_iface_call`**: with ≥2 impls the call is genuinely
   ambiguous (unpinned result TVar), a USER error, not a compiler bug. The
   guard now raises this dedicated exception — also consulting
   `Lower_state.get_iface_methods()` when the impls were DCE'd out of
   `top_fns`, so the former linker-error path gets the same message —
   and `bin/main.ml` renders it as a clean diagnostic, exit 1 (not the
   internal-compiler-error path, exit 3).

## Witnesses

`test/test_codegen.ml` suite `derive_json_dispatch_codegen`:
- "compiled single-derive bare from_json resolves" — interpreter baseline +
  compiled parity (`ok: a`), formerly a linker error;
- "ambiguous multi-derive from_json: clean diagnostic, not ICE" — exit ≠ 0,
  message names the method and candidates, no "internal compiler error".

## Still open (unchanged by this fix)

- Return-type-directed dispatch proper: `specs/todos/2026-07-31-from-json-return-type-dispatch-unimplemented.md`.
- Nested `derive Json` first-arg `to_json` dispatch
  (`specs/todos/2026-07-31-nested-derive-json-fails-to-link-compiled-backend.md`):
  still unresolved because the call site's structural record type
  (nested records expanded) never matches `record_to_typename`'s declared-shape
  key — but its failure mode is now the clean ambiguity diagnostic instead of
  a linker error.
- `test/stdlib/test_json_typed.march` (6 derives in one module) still cannot
  be compiled natively — by design it exercises the interpreter's
  lexical-rebinding semantics; natively it now fails with the clean
  diagnostic instead of the ICE.
