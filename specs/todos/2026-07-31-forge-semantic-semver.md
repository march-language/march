`[P2]` # forge publish compares signatures as strings, so a breaking release can ship as a patch

Split 2026-09-18 out of `2026-07-31-p1-tooling-forge-build-tool.md` per
`specs/2026-09-18-forge-p1-design.md` §3, which has the full design. The
original bullet ("text-heuristic; linearity/generic diffing needs compiler
integration") undersold it: this one has a correctness consequence.

`forge/lib/resolver_api_surface.ml` reads the real AST, but diffs what it reads
as rendered strings (`params_raw`, `return_raw`, `body_raw`), and
`cmd_publish.ml` refuses an under-bumped release on that verdict. So a string
comparison is gating publishes.

**False PATCH, the dangerous direction:** a public function with no return-type
annotation renders `return_raw = ""` on both sides (`render_return`,
`fn_ret_ty = None -> ""`), so changing what it returns reads as no change and a
breaking release publishes as a patch.

**False MAJOR:** renaming a parameter or a type variable, or loosening a
refinement, changes the text without breaking a caller.

**Design:** compare typechecker-resolved types — normalised, tvars alpha-renamed,
aliases expanded, parameter names dropped — rather than rendered text. See the
spec for the four steps and the verification bar.

**Correction, 2026-09-18:** the spec originally claimed `--emit-core-ast`
already exposes inferred types. It does not — `ret_ty` is `null` for an
unannotated function, which is the whole case — and typechecking the OLD
version needs its dependency tree, which parsing does not. Effort revised M -> L.

**Cheaper first step (S), closing the dangerous direction on its own:** treat an
unannotated public function whose clauses changed as a surface the diff cannot
see, the way an unparseable file already is, and refuse to certify a
PATCH/MINOR for it with a message naming the function. Sound, cheap, and noisy
in proportion to unannotated public API — whether that noise is acceptable is a
product call. Details in the spec's "A cheaper guard".

`[P2]`: a real correctness gap in a release gate, but it needs a publisher and a
specific kind of change to bite.
