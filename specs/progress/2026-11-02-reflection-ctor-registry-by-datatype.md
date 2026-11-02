`[P1]` Refinement checker: the constructor registry is keyed by (datatype, constructor), and a
source constructor is resolved by the type the checker knows for it. Filed as the first bullet
of `specs/todos/2026-10-31-reflection-encoder-gaps.md` (phase 1b ruling 1; the phase-1a review's
`ctor2.march`).

## The bug

`Refine_encode` kept every constructor table (`ctor_field_sorts`, `ctor_field_sorts_poly`,
`ctor_field_names`, `ctor_param_fields`, `ctor_field_params`, `ctor_field_joint`) and the
constructor lists of `adt_ctors` by the constructor's source NAME. A user `type Mb = Some(Int) |
None` therefore overwrote the built-in `Option`'s `Some(a)`: every `Option` instance of the
program was declared `(M_Option$X 0)) (((None) (Some (Some_0 Int))))`, stage-1 queries
included. z3 rejected the ill-sorted queries (no false proof was found), and reflection declined
every constructor two datatypes declare, so the stdlib `Option` functions were never unfolded in
such a program.

## The fix

**SMT naming scheme.** A constructor name that ONE datatype declares keeps its source spelling
(`Cons`, `Some` in a program with no other `Some`): the queries of a program without a collision
are byte-for-byte what they were. A name two or more datatypes declare is qualified by its
datatype's sort for every one of them: `<sort>$<Ctor>` (`M_Option$Some`, `M_Mb$Some`), with
testers `(_ is M_Option$Some)` and selectors `M_Option$Some_0`. `$` cannot occur in a March name,
so a qualified spelling never meets a source one. Every constructor-keyed table and every
`adt_ctors` list holds the SMT name, so a reader that starts from a term (`ctor_view`, the
selector parser, `resolve_sorts`, the datatype declarations) needs no change.

- `finalize_ctor_names` (run at the end of `finalize_adt_canonical`, once the datatype keys are
  final) computes `ctor_decls` (source name -> datatypes) and `ctor_source` (SMT name -> source
  name), rewrites the pass-1 lists, and re-keys the built-in `List`/`Option`/`Result` entries.
- Pass 2 (`register_field_sorts`) registers each declaration's constructors under its OWN
  datatype (`decl_key`), not the preferred declarant `adt_sort_name` picks for a bare type name.
- A SOURCE name becomes an SMT one only through `ctor_of_adt adt c` (the datatype is known) or
  `unique_ctor c` (one datatype declares it); `resolve_source_ctor` combines them. A colliding
  source name looked up directly in a table misses, so an unconverted reader declines.
- The type comes from `adt_of_tc_ty` / `adt_of_decl_ty`: a typechecker or declared type whose
  short name ONE module declares. A type name two modules declare (`A.T`, `B.T`) pins nothing.
- Messages and counterexample values show the source name (`ctor_display`, `unqualify_ctors`);
  `Witness` decodes a model's qualified constructor back to the source one.

**Where a constructor is now resolved by type** (each declines when the type does not pin one
datatype that declares it):

| Site | Type used |
|---|---|
| reflected body `ECon` (`Refine_reflect.tr_val`) | the expression's typechecker type |
| reflected body `PatCon` (`pat`) | the scrutinee's type; a nested pattern by its field's sort |
| reflected guard tester (`pre_of`) | the parameter's sort |
| predicate/actual `ECon` (`Refine_scope.smt_of_r`) | the expression's typechecker type |
| call-site tester (`Refine_call.resolve_tester`) | the refined or named parameter's declared type, else the subject's type |
| path tester (`path_resolve_tester`) | the caller value's type |
| `reflect_dt` / `check_post` constructions and patterns | the datatype already fixed there |
| `match` arm narrowing, exclusions, record binders (`Refine_check`) | the scrutinee's type |
| container constructions and destructurings (`Refine_check`) | the container entry's type |
| measure arms (`build_measure_preamble`, totality message) | the measure parameter's type |

**Declines that are new.** A constructor term whose name two datatypes declare and whose type is
not known (no type map, or an ambiguous type name) was reflected before as an untyped
`App ("Some", …)` (`Refine_scope`) or against whichever declaration registered last; it is now
not reflected. A measure whose arm names a constructor its parameter's datatype does not declare
is not axiomatised. `reflect_parity.ctors_of` no longer refuses a colliding constructor (the
reason it gave, the name-keyed registry, is gone).

## Tests (`reflect-ctor`, `test/test_refine_reflect1b.ml`)

RED before the fix, GREEN after:
- `ctor (a)`: a user `Some(Int)` leaves `Option`'s sorts alone (every `M_Option` instance in the
  z3 log declares its payload at the instance's own sort) and `need(get(wrap(100)))`,
  `need(get(Some(100)))` are proved.
- `ctor (b)`: one program matching on `U.Mb`'s `Some` and `Option`'s `Some`: each proved through
  its own type (`uses: val`, `uses: get`).
- `ctor (d)`: the false obligations of the same program are `violated`, not skipped.
- a library module declaring `Some(Int)`, reached directly and through `alias`: `Option` sites
  proved/violated correctly, the library sites (not unfolded today) neither proved nor violated.
- a nested `mod Option` declaring `Some`: `get(Some(98))` violated, the nested site not violated.
- `is_Some(_)` in a predicate with a user `Some` in the program: proved / violated.

GREEN before and after (guard): `ctor (c)`, two modules each declaring `type T` with a `K`: the
type name pins nothing, so neither call is proved or violated. The existing `5b REJECT` cases
stay green.

## Rulings

1. **Qualify every colliding declaration, not all but one.** Leaving the "preferred" one bare
   would let a reader that was not converted hit it silently. Cost if wrong: none for soundness;
   a colliding name's queries change spelling.
2. **The type comes from the typechecker's type map, accepted only when the type's short name
   has one declaring module.** The typechecker's `ci_type` is the bare type name, so two `type T`
   are indistinguishable there; such a type declines. Cost if wrong: lost proofs on programs
   whose type names collide (user `type Tree` vs the stdlib `OrderedMap.Tree`), same as before.
3. **Parameters and locals cannot shadow a constructor** (constructors are capitalised, binders
   are not), so the shadowing tests the brief asks for apply to module/alias resolution; those
   are the library/alias and nested-module cases above. Type-name resolution itself
   (`adt_sort_name`'s preferred declarant) is unchanged and still used for sorts; this change
   never resolves a constructor through it when the name is ambiguous.
4. **A user top-level `type Option` (same key as the built-in) still replaces the built-in.**
   That is a type-name collision, not a constructor one; out of scope.

## Verification

- `scripts/run-tests.sh refinecheck`: 2,095 tests, all green (`reflect-ctor` 7 cases).
- `scripts/run-tests.sh -q compiler`: 1,351 tests, all green.
- `scripts/oracle-base.sh refine` against the merge-base `8aaeb6176`: IDENTICAL (7,968 report
  lines over 569 fixtures); `scripts/refine-oracle.sh monotone`: GREEN over 139,456 sites, 0
  moves (no new proof, no lost proof, no new or withdrawn violation). The corpus has no program
  whose user-visible sites depend on a colliding constructor, so the new proofs show only in the
  `reflect-ctor` cases.
