# Predicate names: resolve and print them right (2026-11-06)

Plan: `specs/plans/2026-11-06-predicate-names-plan.md`. Closes three todos and one bullet:

| Todo | Priority | Outcome |
|---|---|---|
| `2026-11-04-refine-pred-str-drops-parens` | P4 | `pred_str` keeps the parentheses a reparse needs |
| `2026-10-31-reflection-encoder-gaps`, bullet "predicate display-name resolution in the propagation pre-pass" | P2 file | already closed by 71f112f4a; pinned, bullet removed |
| `2026-10-29-predicate-vocabulary-shadows-user-functions` | P2 | new warning `predicate_vocabulary_shadowed` |
| `2026-11-03-reflect-type-name-clash-with-stdlib` | P3 | same-named types of different arity are told apart |

All tests are in the new `pred-names` group (`test/test_refine_pred_names.ml`, 24 cases).

## What changed

- **`pred_str` (`lib/refinecheck/refine_scope.ml`).** It printed every binary operator flat, so
  `_ <= a && _ <= b && (_ == a || _ == b)` (`Math.min_int`) printed as
  `… && _ == a || _ == b`, `_ == (a + b) * 2` as `_ == a + b * 2`, and
  `_ == (keys(m) == empty)` (`Map.is_empty`) as text that does not parse. Inference reads this
  text back (`Infer_vocab.candidate_of_text`) and `--refine-infer-apply` writes it. Now a child
  is parenthesised when it binds looser than its parent, as tightly but on the right of a
  left-associative operator, or when both are comparisons (`binop_level`, the parser's
  `expr_or` … `expr_mul` levels); `!` and unary `-` parenthesise any infix operand.
- **#20.** 71f112f4a ("resolve every reflected call by site") replaced name-based predicate
  resolution with per-span resolution (`Refine_term.pred_expr` → `pred_sites` →
  `Reflect_state.call_sym`), so the walk and the postcondition pre-pass
  (`gate_unverified_posts_ih`) resolve identically. The bullet had been copied into the todo
  afterwards. Pinned: a bare `dbl` inside `mod Inner`, with an outer decoy `dbl`, resolves to
  `Inner.dbl` in a postcondition a caller uses through the pre-pass. The probe found one false
  warning: a qualified `Inner.dbl(n)` that resolved and proved still got `refinement_unchecked`,
  because `warn_predicate_expr` took its dotted-name branch before checking `resolve_site`.
  A call resolved at its site now gets no unchecked warning.
- **`predicate_vocabulary_shadowed` (`lib/refinecheck/refine_check.ml`).** `warn_predicate_decls`
  now threads the functions declared in each enclosing module (`scope_fn`, innermost first).
  A predicate applying `len`, `elts`, `keys` or `is_<Ctor>` while a user function of that name
  is in scope gets a warning saying the predicate means the built-in. The verdict is unchanged
  (F21 is kept, not altered). Stdlib functions are exempt (`Typecheck_builtins.file_is_stdlib`):
  `Map` declares `fn keys` and writes `keys(_)` meaning the built-in on purpose. Set operators
  are not warned: a well-formed `member(x, s)` is the set operator by its arguments, and a
  malformed one already warns `refinement_unchecked`. New code in `lib/errors/code.ml`, page
  `specs/lang/errors/predicate_vocabulary_shadowed.md`, corpus case
  `test/errors/predicate_vocabulary_shadowed_1`.
- **Arity (`lib/refinecheck/refine_encode.ml`).** A user `type Tree` made every predicate over it
  `unreflectable-predicate`: `poly_sort` asked `adt_of_short_type_name "Tree"`, which answered
  the ambiguity sentinel because `OrderedMap` also declares a `Tree`, so `size`'s logic symbol
  was never registered. The typechecker never unifies types of different arities
  (`expected Tree but got Tree(Int, Int)`), so `short_name_conflated ?arity`,
  `adt_sort_name ?arity` and `adt_of_type_name ?arity` now count only declarants of the
  reference's arity, and `finalize_ctor_names` marks a declarant's constructors ambiguous only
  when another declarant has its arity. A built-in counts at its `Typecheck_builtins.builtin_types`
  arity (now exported). Same-arity names stay a skip: a user `type Tree(a, b)` accepts an
  `OrderedMap` tree (`size(m.tree)` typechecks), so preferring the user's declaration could
  prove a false fact; that waits on `2026-10-13-same-short-name-nested-types-unify`. The
  "Rename your type" message (`conflated_param_type`) now finds the declaration in scope at
  the predicate rather than the first bare-name match, which was a stdlib `fn size`.

## Found on the way

- `specs/todos/2026-11-06-predicate-call-not-unfolded-from-body.md`: `{Int | _ == dbl(n)}` on a
  body `n + n` is skipped; stage 2 does not unfold a predicate-side call the body does not make.
- `scripts/seed-error-corpus.sh` would add 90 never-seeded cases from existing pages; not done
  here (out of scope).

## Verification

| Check | Result |
|---|---|
| `pred-names` (24): parentheses ×5, #20 pin + qualified-call warning + control, shadow warning ×6, arity ×10 | each new behaviour RED → GREEN; the controls (sibling-module `len`, well-formed `member`, stdlib Map/List/Set, same-arity `Tree(a, b)`, `DownReason`, `Option(a)`, type errors) green before and after |
| Two existing tests that pinned the old conservative #8 behaviour | `module-qualified-measure-and-sort` 0 (arity-0 user `Tree`: skip → proved, 3 is a member) and `reflect-lemma` 51 (the name-clash warning now on a same-arity `Tree(a, b)`; arity-0 `Tree` admits the lemma) re-pinned |
| Error corpus (`run_errors.exe`) | 412 pass; regenerating changed no existing case |
| Refine audit baselines | regenerated, unchanged |
| Refine oracle vs merge-base | IDENTICAL (8153 lines, 574 fixtures) |
| Types oracle vs merge-base | tier 1 and tier 2 IDENTICAL (1066 fixtures, 9602 lines) |
| `scripts/affected.sh --run --full` | see the PR |
