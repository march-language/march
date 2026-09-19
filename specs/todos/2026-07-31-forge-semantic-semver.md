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

**False MAJOR.** `forge/lib/resolver_api_surface.ml` still diffs rendered
strings (`params_raw`, `return_raw`, `body_raw`). Renaming a parameter or a type
variable, or loosening a refinement, changes the text without breaking a caller.

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
