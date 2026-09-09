`[P3]` The five `lsp/lib/analysis*` / `code_actions_*` modules have no `.mli`

**Filed:** 2026-08-26 — out of scope of Phase 4 of
`specs/plans/2026-08-19-compiler-file-decomposition.md`, which was code motion
only (see `specs/progress/2026-08-26-lsp-analysis-decomposition-phase4.md`).

After the Phase 4 split, `lsp/lib/` holds:

| module | lines | interface |
|---|---|---|
| `analysis.ml` | 5,201 | none |
| `analysis_types.ml` | 302 | none |
| `analysis_util.ml` | 574 | none |
| `code_actions_ast.ml` | 1,097 | none |
| `code_actions_diag.ml` | 1,019 | none |

`analysis_util.ml` is the interesting one: it is a grab-bag *by construction* —
the mechanically-computed transitive closure of what the two code-action engines
reach back into `analysis.ml` for. An interface is the place to record which of
its 37 definitions are genuinely shared surface (`rename_at`, `references_at`,
`apply_fix_registry`, …) and which are engine-only implementation detail that
only ended up public because the closure dragged them along.

`code_actions_ast.mli` and `code_actions_diag.mli` are the cheapest and most
valuable: each should expose exactly one value.

Method is the one established by PR #354 and Phase 3: generate the maximal
inferred interface with

```
ocamlfind ocamlc -i -I <objs> -I <dep objs> -open <Alias> <file>.ml
```

then curate conservatively — hide a value only when `forge search --callers
<name>` plus a grep sweep prove nothing outside uses it; when in doubt, expose;
never edit a consumer to accommodate hiding.

**One wrinkle specific to `analysis.ml`:** it republishes the new modules with
`include Analysis_util` and `include Code_actions_diag`, so its `.mli` has to
restate everything those bring in (`include module type of` or an explicit
enumeration). That makes it a larger and less obviously-profitable job than the
four modules in PR #354, which had no `include`s to account for. Do the four
small modules first; `analysis.mli` may not be worth it until `analysis.ml`
itself is split further.

Gates: the five executables under `lsp/test/` (now reachable as
`scripts/run-tests.sh lsp utf16 jsonrpc incremental query_cli`) plus
`dune build --root . @check`, which sits at 17 pre-existing errors under
`forge/test/` and `js/` from a missing optional opam dep. `scripts/ir-oracle.sh`
and `scripts/refine-oracle.sh` prove nothing about LSP code.
