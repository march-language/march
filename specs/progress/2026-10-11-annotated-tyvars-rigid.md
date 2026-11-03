# `[P3]` Typecheck: a type variable in a signature can be silently fixed by the body

**Closed 2026-10-11: option (a) landed** (see "Option (a)" at the end).

Filed 2026-09-18, found while designing `specs/2026-09-18-parametric-element-flow-design.md` §1.

`fn bad(xs : List(a)) : List(a) do [0 - 5] end` typechecks: `a` is an
ordinary unification variable, fixed to `Int` by the body. Callers see
`List(Int) -> List(Int)` (`bad(["x"])` is "expected String but got Int",
pointing at the call rather than the definition). OCaml does the same; most
readers take `a` to mean "for all a".

Decide: (a) make annotation type variables rigid (an error at the definition,
breaking for any code relying on this), (b) warn when an annotated variable is
unified with a concrete type, or (c) document the current semantics in
`specs/lang/types.md`. The refinement checker does not depend on the choice:
its Phase 0 fix reads the inferred type (`2026-09-18-refine-parametric-rule-trusts-flexible-tyvars.md`).
Before choosing (a), measure how much of the stdlib and ecosystem relies on it.

## Decision (repo owner, 2026-09-22)

Option **(b) now, moving to (a) later**: warn when an annotated type variable
is unified with a concrete type, and later make annotation type variables
rigid. **Measurement first**: before the warning lands, count the sites in
`stdlib/`, `specs/lang/types/accept`, `test/stdlib`, and `test/native` whose
signature type variables the body fixes (to a concrete type, or to another
annotation variable of the same function). That count sizes (b)'s noise and
(a)'s breakage. (c), documenting the flexible semantics as intended, is
rejected.

## Measurement (2026-09-22)

A probe in `check_fn` (lib/typecheck/typecheck.ml), run once the body is
checked and the self-type unified, looked at each type variable written in
the signature (`fn_tvars`, restricted to names with a source occurrence in
the parameter/return annotations or bounds). It classified each as **bound
to a concrete (non-variable) type**, or **unified with an earlier-written
variable of the same signature**. Every file was run through `--check`
directly, stdlib files included (the user-facing filter hides stdlib
diagnostics, but the probe printed to stderr unfiltered):

| corpus | files | concrete | aliased |
|---|---:|---:|---:|
| `stdlib/*.march` | 124 | **1** | 0 |
| `specs/lang/types/accept` | 169 | 0 | 0 |
| `test/stdlib` | 105 | 0 | 0 |
| `test/native` | 256 | 0 | 0 |

The one genuine site was `OrderedMap.values`
(`stdlib/ordered_map.march:245`). Its `v` was fixed to a function type
`b -> b`, because `List.map(…, fn (_, v) -> v)` passes a two-parameter lambda,
not a tuple pattern. Callers saw `List(b -> b)`. This was a real bug, not
intended genericity. Its neighbours `keys` and `from_list` had the same
mistake but failed to typecheck outright, and the stdlib diagnostic filter
hid that. All three are fixed.

The raw probe output also had 26 artifact hits: `Random.shuffle`'s `a` :=
`String`, `RRBVec`'s `a` := `AcNode`, `ConsistentHash.new`'s `a` := `Int`, and
so on. They appeared only when `stdlib/list.march`, `map.march` or
`array.march` was the entry file. Checking one of those standalone loads it a
second time as a user module that shadows the real one, so dependent stdlib
bodies unify against the wrong definitions and report type errors. None of
those sites fires when its own module is checked, or when a test program uses
it. The shipped warning is skipped for a body with a type error, so it does
not report them.

An attempt to extend the sweep to local ecosystem projects (depot, conduit,
envoy, forgepm, …) with a hand-set `MARCH_LIB_PATH` was abandoned. Nearly
every file failed dependency resolution (unknown modules/constructors), which
masks the result. Measuring those needs each project's own `forge` build.

## Status

- **(b) done** (2026-09-22): the `annotated_tyvar_fixed` warning. See
  `specs/progress/2026-09-22-annotated-tyvar-fixed-warning.md`.
- **(a) open**: rigid annotation type variables. Sizing: 1 site in the in-repo
  corpora (now fixed), so turning the warning into an error breaks nothing in
  the repo today. Open questions for (a): the ecosystem count (above), and
  whether an aliased pair (`fn f(x : a, y : b) : a do y end`) is rejected as
  well, as it would be under rigid skolems.

## Option (a) (2026-10-11): annotation type variables are rigid

The `annotated_tyvar_fixed` diagnostic is now an **Error**
(`check_annotated_tyvar_fixings`, lib/typecheck/typecheck.ml, formerly
`warn_annotated_tyvar_fixings`). The accept/reject set is that of rigid
skolems for written signature variables, checked after the body rather than by
skolemising during it, so the error points at the signature and names the type
the body needed.

- **Aliased pairs are rejected too** (`fn f(x : a, y : b) : a do y end`), as
  under rigid skolems. That answers the second open question; (b) already
  warned on them as a preview.
- **Re-measured before flipping** (`--check` on every `.march` under
  `test/native`, `test/stdlib`, `test/golden`, `specs/lang/types/accept`,
  `examples`, `bench`: 792 files): 0 sites. The stdlib internal-type-error
  ratchet (`run-tests.sh -q compiler`) is unchanged, so no stdlib function
  relies on a flexible signature variable. The one golden diagnostic that
  showed the warning (`test/errors/annotated_tyvar_fixed_1`) now shows it as
  an error.
- **Not measured: the ecosystem** (depot, conduit, envoy, forgepm, ...), for
  the reason given above. A library that relied on a flexible signature
  variable now fails to compile; the hint names the concrete type to write.
- Unchanged scope: local `let x : a = ...` and lambda annotations are not
  checked; the check is skipped after a body error.

Tests: `specs/lang/types/reject/t317_annotated_tyvar_rigid.march` (exit 0
before, rejected after), the `annotated_tyvar_fixed` group in
`test/test_compiler.ml` (now asserting Error severity), and the regenerated
`test/errors/annotated_tyvar_fixed_1` golden. Docs: `docs/types.md` and
`specs/lang/type-system.md` ("A signature's type variables must stay generic").
