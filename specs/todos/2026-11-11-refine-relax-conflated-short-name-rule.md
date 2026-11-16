`[P3]` Relax the refinement checker's "conflated short name" rule now that the typechecker tells the types apart

`Refine_encode.short_name_conflated` makes every datatype whose short name two declarants share
resolve no constructor (so no proof over such a type), and treats a user declaration of a
built-in name the stdlib does not declare the same way. It was a workaround for the typechecker
unifying such types. The typechecker no longer does, for:

- two variant types in two modules of the checked program (#1235,
  `specs/progress/2026-10-13-same-short-name-nested-types-unify.md`);
- a user variant named like a built-in or stdlib type
  (`specs/progress/2026-11-02-typecheck-conflates-same-short-named-types.md`).

It still does for two stdlib types of one short name, for records, for two declarations at one
module path, and in the REPL; the rule must stay for those.

## Why it was not done with the typechecker fix

The checker reaches a datatype from a type NAME on two paths, and both lose the distinction the
typechecker now makes:

- a typechecker type (`T.TCon`): an entry-level identity (`Main.Tree`) is read by its short name
  (`Typecheck_nominal.refine_name`), so it lands where the bare stdlib `Tree` lands. Five further
  sites take the last segment of any name (`Refine_term.bare`).
- an AST type (`A.TyCon`): looked up by the text written, about 15 sites
  (`adt_sort_name name.txt`), with no account of which file wrote it. A stdlib signature naming
  `Array` would resolve to a user's `type Array` once the rule is gone.

## Sketch

1. One resolver for each path, used by every site: a typechecker name resolves by identity
   (`Typecheck_nominal.is_identity`, then the declarant at that path; a bare name that a user
   identity shadows is the BASE type, which is the stdlib's declarant or no datatype); an AST
   name resolves by `Typecheck_nominal.ref_identity` on its span first.
2. Drop the rule for a pair the resolver tells apart; keep it for the cases listed above.
3. The smallest first cut: a user variant named like a built-in that only builtin signatures
   name (`CancelToken`, `TimerRef`: no source can write the built-in's name, so the AST path is
   always the user's). The `ctor review4` tests `ct1`/`tr1` in `test/test_refine_reflect1b.ml`
   pin the current answer and would flip to `proved` for the user-typed value.

Check with `scripts/oracle-base.sh refine` and the `reflect-ctor`, `pred-names` groups; each of
the five review rounds in `specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`
found a way a relaxed rule proved something false.
