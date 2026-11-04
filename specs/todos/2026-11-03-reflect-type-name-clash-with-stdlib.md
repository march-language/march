`[P3]` A user type whose short name the stdlib also declares (`type Tree`, as `OrderedMap.Tree`
does) cannot be used in a refinement predicate or a lemma's theorem: `Refine_encode` marks a
conflated short name ambiguous (`ambiguous_adts`), because the typechecker can conflate the two,
and a function over it is never resolved at a predicate call site. Since
`specs/progress/2026-11-03-lemma-tooling-bugfixes.md` the warning says so and suggests renaming.
The fix proper is to resolve the user's own declaration when the call site's module declares
it (the typechecker's current-module rule), without letting the two datatypes share
constructors in the logic. Encoder territory (`finalize_ctor_names`, `adt_sort_name`).
