# A module-level `let` annotation is checked

Shipped 2026-09-19.

## The bug

`let x : Int = "hello"` inside a `mod` was accepted by `march --check`. The
`Ast.DLet` arm of `check_decl` (`lib/typecheck/typecheck.ml`) inferred the RHS
with `infer_expr` and unified it with the pattern, but never read `b.bind_ty`
except as the gate for the Vault value restriction (`demote_vault_handle_vars`).
The block-`let` path already checked annotations through `infer_let_annotated`.

## The fix

The `DLet` arm now calls `infer_let_annotated` (inside the same `with_no_caller`
wrapper), so a module-level annotation behaves exactly like a block one: the RHS
is checked against the annotation (`check_expr`, reason `RAnnotation`), the
annotated type becomes the binding's type, an unresolvable annotation name is
reported, and a phantom-tag-only annotation falls back to inference.
Generalisation is unchanged: `let id : (a) -> a = fn x -> x` at module level is
still usable at both `Int` and `String`, interpreted and compiled.

## Verification

- New reject fixture `specs/lang/types/reject/t262_toplevel_let_annotation_mismatch.march`:
  exit 0 on the pre-fix compiler, rejected with ``expected `Int` but got `String` `` after.
  `check_types.sh`: 381/381.
- Stdlib: `march --check` on every `stdlib/*.march` (124 files) with the pre-fix and
  post-fix compilers, private `HOME` each, `MARCH_STDLIB` pinned: byte-identical output
  and exit codes. No stdlib module has an annotated module-level `let`.
- The only other tracked `.march` files with a two-space-indented annotated `let`
  (`examples/stats_basic.march`, `test/stdlib/test_random.march`,
  `test/stdlib/test_stats.march`) check identically before and after.

## Follow-up

The corpus's two-repo rule applies: `reject/t262` must be mirrored in
march-language/march-lean (confirm the `march-lean-dispatch` run after merge, or
ledger a skip there).
