# Delete three dead `lib/tir` values found by the `.mli` pass

Landed 2026-08-27.

PR #370's `.mli` pass (and the earlier #368) operated under a no-`.ml`-edits
constraint: three values had zero callers anywhere in the tree, but hiding an
unused value in an `.mli` turns it into an unused-value error under
warnings-as-errors, so each was kept public with a doc comment explaining it
was dead and naming deletion as the right follow-up. This is that follow-up.

## What was deleted

- `emit_main_wrapper` (`lib/tir/llvm_toplevel.ml`) — a real function body
  (not a re-export), carried verbatim from `llvm_emit.ml` in the Wave 3 file
  split. The compiler evidently emits its main wrapper by some other path.
- `target_arch` (`lib/tir/llvm_toplevel.ml`)
- `reserved_ctor_tag_limit` (`lib/tir/llvm_builtins.ml`)

Each had exactly one reference in the whole tree: its own `let`. Re-verified
with `forge search --callers <name>` (no references) and
`grep -rn <name> lib bin lsp forge test` (definition/declaration only) before
deleting the `.ml` definition and the matching `.mli` `val` (and doc-comment
callout) together.

## Why these three and not `inject_iface_exports_ref`

This project has now found dead-but-declared code eight and nine times over
(see `2026-08-26-compiler-file-decomposition-complete.md` and the
`effects.ml` / `register_types_for_check` / `compile_scc` todos). Not every
instance is rot: `inject_iface_exports_ref` reads as a breadcrumb for
unfinished work and was deliberately left alone. These three carry no such
signal — both `.mli` doc comments were explicit that deletion was the correct
next step, and `emit_main_wrapper`'s sibling in the `march_println`/`writev`
incident (dead 13 months behind a live-looking declaration) was the
cautionary comparison, not a reason to keep it.

## Verification

- `dune build --root . @check --force`: stayed at the pre-existing 17
  `Unbound module "Alcotest"` errors (forge/test infra gap, unrelated to this
  change) — same 17, reordered by parallel build scheduling.
- `scripts/ir-oracle.sh baseline|check`: IR IDENTICAL across 241 programs
  (baselined against a private `HOME`, per
  `project_home_cache_path_contamination_oracles`). Deleting genuinely dead
  code cannot move emitted output; a diff here would have meant one of the
  three was live and the deletion should stop.
- `scripts/run-tests.sh`: all suites passed (exit 0).
