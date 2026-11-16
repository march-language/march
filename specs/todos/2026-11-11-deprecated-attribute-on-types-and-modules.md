`[P2]` `@[deprecated("...")]` on a `type` and on a `mod`.

Package B1 of `specs/plans/2026-11-11-pre-1.0-execution-plan.md` landed the attribute on
functions (`specs/progress/2026-11-11-deprecated-attribute.md`). `specs/lang/compatibility.md`
promises it for types and modules too. Today the parser rejects it there with a message that
says so (`decl` in `lib/parser/parser.mly`, the `nonempty_list(fn_attr); TYPE | PTYPE | OPAQUE | MOD`
rules).

What it needs:

- **A place in the AST.** `fn_def` has `fn_attr_args`; `DType` and `DMod` have no attribute
  slot. `DType`/`DMod` are matched in several hundred places, so adding a field to either is a
  cross-cutting change. Two cheaper routes were considered and not taken:
  a `DOpts ["deprecated"; msg]` as the first declaration of the module body (works for `mod`,
  the formatter must print it back above the `mod`); and a sibling declaration before the
  `type` (the `decl` nonterminal returns one declaration, so `decl_list_r` would have to
  splice two, and the formatter groups `DOpts` with the capability directives).
- **What a "use" is.** For a type: a type annotation, a constructor in an expression or a
  pattern, a record literal, and an `impl` head. For a module: every qualified reference
  `Mod.x`, and `use`/`alias`/`import` of it. The function check
  (`warn_if_deprecated` in `lib/typecheck/typecheck.ml`) hangs off `EVar` resolution only.
- The same exemption: no warning inside the declaring module.
- `@[deprecated]` on an `actor` is still silently dropped by the actor attribute rules
  (they keep only `compat` and `remote`); reject it or support it.
- Update `specs/lang/compatibility.md` ("Not built yet"), `specs/lang/errors/deprecated.md`
  and the parse-error hint when this lands.
