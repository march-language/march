`[P3]` # forge publish compares signatures as text: a harmless rename reads as MAJOR, and unannotated functions get no precise verdict

Split 2026-09-18 out of `2026-07-31-p1-tooling-forge-build-tool.md` per
`specs/2026-09-18-forge-p1-design.md` §3, which has the full design.

**The dangerous direction is closed** (2026-09-18,
`specs/progress/2026-09-18-forge-publish-refuses-unannotated-body-changes.md`).
A public function with no return-type annotation used to render
`return_raw = ""` on both sides, so changing what it returned published as a
PATCH. `diff` now reports an unannotated function whose body changed as
`UnverifiableFn`, and refuses to certify less than MAJOR for it. That is sound,
but coarse, hence what remains:

**False MAJOR — renames DONE 2026-10-11.** `diff` no longer compares rendered
strings. It compares a structural key built from the AST
(`fn_key` / `type_key` in `forge/lib/resolver_api_surface.ml`): parameter names
dropped, type variables alpha-renamed in order of first occurrence (params,
return, bounds), a type's declared parameters included. So renaming a parameter
or a type variable is a PATCH, while identifying two variables, swapping
parameters, dropping a default or adding a constructor stays MAJOR. Two former
false PATCHes closed on the way: a type's parameters were not compared at all
(`type Box(a)` -> `type Box(a, b)` diffed as no change), and neither was
constructor visibility (`type T = ...` -> `opaque type T = ...`). Tests:
`forge/test/test_api_surface.ml`, group `structural-comparison`.

What is still text, and why:

- **Refinements** keep their binder and predicate verbatim, so loosening one
  (or renaming its binder) is still MAJOR. Classifying by direction is design
  step 3 and needs the refinement checker's implication query.
- **"Aliases expanded" (step 1) has nothing to act on.** The grammar has no
  user-written alias: `type UserId = Int` is a variant with one constructor
  named `Int` (see `walk_type_def` in `lib/refinecheck/refine_audit.ml`).
  `TDAlias` only comes from desugar-generated decls, which `forge publish`
  never sees. Revisit if alias syntax is added.
- **Pattern heads** of a multi-head function are compared as written (they
  were before too). They are behaviour, not type, so this is a false MAJOR
  when only a pattern changes.

**New finding, 2026-10-11 — a false PATCH the guard below does not cover.**
`UnverifiableFn` fires only when the RETURN type is unannotated. A parameter
with no type annotation has the same problem: `fn f(x) : Int do x + 1 end` ->
`fn f(x) : Int do String.length(x) end` changes the parameter's inferred type
from `Int` to `String`, the signature key is identical (`_`), and it publishes
as a PATCH. Extending the guard to "any unannotated parameter, and the clauses
changed" is the same sound-but-noisy trade the return-type guard made; it was
left as a product call rather than widened silently. The inferred-type
comparison below retires both.

**Imprecise for unannotated functions.** Any body change to one now requires a
major bump, even when the inferred return type is unchanged.

**Design:** compare typechecker-resolved types, normalised, with tvars
alpha-renamed, aliases expanded and parameter names dropped, rather than
rendered text. That also retires `UnverifiableFn`, because the inferred type
fills the missing annotation. See the spec for the four steps and the
verification bar.

**Correction, 2026-09-18:** the spec originally claimed `--emit-core-ast`
already exposes inferred types. It does not: `ret_ty` is `null` for an
unannotated function, which is the whole case. Typechecking the OLD version also
needs its dependency tree, which parsing does not. Effort revised M -> L.

`[P3]` (was P2 until the false-PATCH guard landed): what is left makes publishing
stricter than necessary, never wrong in the direction that ships a break.
