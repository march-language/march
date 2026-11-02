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

## Review round 1 (of `c87e66495`)

A fresh soundness review found two false proofs and a parity regression; each fix landed
test-first (the `ctor review` cases of `reflect-ctor`, RED on `c87e66495`).

- **C1 (new in `c87e66495`): a nested pattern resolved through a guessed field type.** In
  `type W = W1(Tq)` with `Tq` declared by `A` and `B`, `W1`'s field sort comes from
  `adt_sort_name "Tq"`, the preferred declarant `M_A$Tq`; the reflected body read `W1(K(n))`'s `K`
  as `A.Tq`'s only constructor, so the tester was always true and `need1(g(w))` was proved though
  `B.c4(B.W1(B.Z))` passes 0. Fix: `ambiguous_adts` holds every datatype key whose TYPE NAME two
  or more modules (or a module and a built-in) declare; `ctor_of_adt` resolves a constructor
  through such a key only when that constructor name is declared by that datatype alone anywhere
  (the name then fixes the datatype by itself; this keeps a user top-level `Tree` with
  `UTip | UBranch` beside the stdlib `OrderedMap.Tree` axiomatised,
  `module-qualified-measure-and-sort`). Every resolver that receives a datatype (reflected
  patterns via `field_adt`, `Refine_post.ctor_belongs`, `Refine_check`'s container sites,
  measure arms, `reflect_dt`) goes through `ctor_of_adt`, so all of them decline alike.
- **C2 (already on main): a user type named like a built-in replaced the built-in.** `List`,
  `Option` and `Result` now count as declarants of their names (pseudo path `$builtin`, key the
  bare one), so a nested `type Option(a) = Some(a)` makes `Option` ambiguous: the user type gets
  its qualified key, the built-in keeps `M_Option` and its constructors, and constructors resolved
  through either decline (unless unique by name). A TOP-LEVEL user `type Option` is filed under
  the pseudo path `$top` (`M_$top$Option`) instead of overwriting the bare key. Tests: nested
  `Option`, `Result` and `List` (the last was already not proved: a guard), and top-level
  `Option`.
- **I1: the parity net agreed on a wrong model.** `ctors_of` again refuses a datatype in
  `ambiguous_adts` and a constructor whose name another datatype declares (its interpreter value
  carries only the bare name). Tests: `B.g` of C1 is not reported agreeing; a function whose body
  resolves no `Tq` constructor (`B.h`) is `not-compared` for want of a generator (RED, `agree
  100 inputs`, with only this fix reverted).
- **I2: `load_scope_tester_facts`** now requires the caller's declared sort marker to be the
  goal's datatype (`$Meas:<adt>`) before reading the caller's `is_C` fact in it. Cheap, so done;
  no probe reached it.

Probes: `p3` (nested `Option`) all three sites skip (were two false proofs); `p6` both sites skip
(was a false proof); `p6b` (no `A.Tq`) still reports line 13 `violated`.

Ruling (superseded by round 2): a datatype whose type name is ambiguous loses constructor
resolution except for constructor names unique program-wide.

Verification after round 1: `scripts/run-tests.sh refinecheck` 2,102 tests green;
`-q compiler` 1,351 green; `scripts/oracle-base.sh refine` IDENTICAL against `8aaeb6176`, and
`refine-oracle.sh monotone` GREEN over 139,456 sites with 0 moves.

## Review round 2 (of `c87e66495` + `037744add`)

Five false proofs, all already present at base `8aaeb6176` (none a regression), none closed by
round 1. **Root cause neither round saw: the typechecker treats two types of one SHORT name as one
type** (`A.Tq` and `B.Tq` unify; a user type and a built-in of one name likewise): `A.g(B.ZB)`
typechecks (probe `q1`), and the same program with B's type renamed is rejected (`c2diff`). So a
constructor only `A.Tq` declares can legally be matched against a `B.Tq` value, and round 1's
"a program-wide-unique constructor name pins its datatype" was false. Filed:
`specs/todos/2026-11-02-typecheck-conflates-same-short-named-types.md` (`[P1]`), and the compiled
crash of the `DownReason` probe, `specs/todos/2026-11-02-compiled-user-downreason-crashes-llvm-toplevel.md`.

The rule now separates "the type is KNOWN but its short name is conflated" from "no type
information":

1. **`short_name_conflated`**: two or more module paths declare the short name (the seeded
   built-ins `List`/`Option`/`Result` counted under `$builtin`), or a user declares a name from
   the typechecker's built-in type table (`Typecheck_builtins.builtin_type_names`, now exported;
   no hand-written list) that no stdlib file declares itself (`DownReason` without the stdlib's
   `DistLink`, `Array`, …). A stdlib declaration of a built-in name (`Set`, `Map`, `Seq`, `Pid`,
   `DownReason`) IS that nominal type, not a second declarant. Every key of a conflated name is in
   `ambiguous_adts`.
2. **`ctor_of_adt` returns `None` for every key in `ambiguous_adts`**, with no exception (round
   1's unique-name exception is gone).
3. **A site whose type is known but conflated declines**: `adt_of_type_name` (and so
   `adt_of_tc_ty`, `adt_of_decl_ty`, `tc_adt_at`) returns the sentinel `$ambiguous`, which
   resolves no constructor, instead of `None`; `field_adt` returns it for a conflated field type.
   `resolve_source_ctor` never falls back to the name when it was handed a datatype. This closes
   `c1` (nested pattern through a field), `c2` (arm exclusion), `c3` (top-level `type Option`),
   `c4` (call-site tester) and `c5` (`type DownReason`).
4. `Refine_post.ctor_belongs`, measure arms (`smt_arms`), `Refine_check`'s container sites and
   `reflect_dt` all resolve through `ctor_of_adt`, so they decline alike.
5. **`unique_ctor` (no type information at all) only for a constructor whose datatype is not
   conflated.** Ruling: that is safe. A well-typed program builds a value matched by `C` with
   `C`'s datatype `D`, or with a datatype the typechecker conflates with `D`, which exists only if
   `D`'s short name is conflated; that case now declines. Cost if wrong: none found; the
   alternative (never use the name alone) would also drop sites with no type map (unit
   harnesses that do not typecheck).

Minor items: the stale `rekey` comment about a top-level user `Option` is corrected (such a type
is filed under `$top` since round 1, so the built-in stays the preferred declarant of
`adt_sort_name "Option"`, which also settles "a top-level user `List`/`Option` becomes the
preferred declarant").

**Accepted cost:** `module-qualified-measure-and-sort` (a user top-level `Tree` beside the stdlib's
`OrderedMap.Tree`) no longer proves or refutes; both cases are skips, and the test now pins that.
By the same conflation those proofs were not safe.

Tests (`reflect-ctor`, written first, RED on `037744add`, all reporting `proved`): `ctor review2
c1` … `c5` (the five probes), plus `ctor review2: a program with no short-name conflation keeps
its proofs` (GREEN before and after). Round-1 probes `p1`…`p10`, `t1` and round-2 probes rerun:
no false proof; `p6b` line 13 still `violated`; `c2`, `c3`, `c5`'s reachable `need1(0)` is now
reported `violated` (it is).

Verification after round 2: `scripts/run-tests.sh refinecheck` 2,108 tests green; `-q compiler`
1,351 green; `scripts/oracle-base.sh refine` IDENTICAL against `8aaeb6176`, and
`refine-oracle.sh monotone` GREEN over 139,456 sites with 0 moves. The corpus (`test/native`,
`stdlib`) has no site that depended on a conflated short name, so the conflation rule moved no
oracle row; its cost shows only in `module-qualified-measure-and-sort`.

## CI round 1 (PR #1056): conformance reject/t109

`reject/t109_refine_induction_propagates.march` declares `type Tree`, and the stdlib's
`OrderedMap` declares one too, so after review round 2 its constructors resolve nothing
and the induction-proved postcondition no longer reaches `needEmpty`: the fixture's
expected violation went silent (`dune build @types-check`, "rejected but message lacks
refinement violation"). This is the accepted cost of round 2, not a new bug.

- **Fix:** the fixture's type is renamed `ITree`, with a comment saying why; what it
  tests (a proved postcondition propagating through structural induction) is unchanged.
  `@types-check`: 492 passed, 0 failed.
- **Tried and reverted: conflate only same-arity declarants.** `unify` equates two
  `TCon`s only when the argument counts agree too, and an annotation must give a
  parameterised type all its arguments (`type_arity`), so a user `type Tree` and
  `OrderedMap.Tree(k, v)` really are two types to the typechecker. But narrowing
  `ambiguous_adts` that way is unsound as things stand: `adt_sort_name`, `field_adt` and
  the other bare-name lookups would then resolve `Tree` to a guessed preferred declarant
  (possibly `OrderedMap`'s) and trust it, the exact shape of review round 1's C1. Doing
  it safely means making every bare-name lookup pick the declarant by arity. That, or
  the typechecker fix (todo `2026-11-02-typecheck-conflates-same-short-named-types`),
  is the way to give same-named user types their proofs back.

## Review round 3 (of `8b855a5f1`)

Three more false proofs, all present at base `8aaeb6176`; each fix landed test-first (`ctor
review3` cases of `reflect-ctor`, RED on `8b855a5f1`: every one reported `proved`).

- **C1: a second declaration at the SAME module path was not a declarant.**
  `short_name_conflated` counted distinct paths, so `type Zq` twice in one module (`h5`), a
  reopened `mod A` (`h6`), or a user `mod Membership` re-declaring the stdlib's
  `Membership.MemberStatus` (`m1`; likewise a user `mod DistLink`, or a dependency module sharing
  a path with a user module) collapsed into one entry, and the last one registered became the
  whole datatype, while the typechecker merges both. It now counts declaration ENTRIES: two or
  more declarations of a short name, even at one path, conflate it. (`decl_key` still keys by
  path; with the name conflated nothing resolves through that key.)
- **C2: a type the typechecker synthesises was not a declarant.** An actor's handlers get the
  message type `<Actor>_Msg`; a user `type Counter_Msg` beside `actor Counter` (`ac1`) matched
  `Inc()` against its own constructors. `register_adt_names` now enters `<Actor>_Msg` (spelled
  by the typechecker's new `Typecheck_env.actor_msg_type_name`, which every typechecker site now
  uses) under the pseudo path `$synth`. The actor type itself was already a declarant (it is
  registered as a record). No protocol/session type is synthesised under a user-visible name
  (searched every `ci_type` construction in `lib/typecheck/`).
- **C3: "known, not a variant" collapsed to "unknown".** `adt_of_type_name` returned `None` for
  `Int`, `String`, a record, or any unregistered type, and `None` sends a site to the name
  alone (`t1`: `needi(n)` for `n : Int` proved `is_Rz(_)`). It now returns the sentinel for
  every known type that is not a registered variant; `adt_of_tc_ty` / `adt_of_decl_ty` return
  `None` only for a type VARIABLE (and the sentinel for an arrow, tuple, …); the reflected
  guard's parameter sort and `tester_ctor` treat a known non-datatype sort the same way. In
  `Refine_call.resolve_tester`, a parameter declared with a type variable falls back to the
  actual's own type, not straight to the name.
- **Minor:** the list-length narrowing in `Refine_check` now asks whether the scrutinee's `Cons`
  is the built-in list's (`resolve_source_ctor ?adt:subj_adt "Cons"`) instead of `sort_of_ctor
  "Cons"`.

Not reintroduced: narrowing conflation to same-arity declarants (tried and reverted in CI round
1).

Probes: across `ctor-review/`, `ctor-review2/` and `ctor-review3/` the only `proved` sites left
are the ones the reviews listed as legitimate: `p10`/`p10b`, round-1 `t1`, `d1`-`d4`, `s2*`,
`h3f` (an unreachable `_` arm) and `lp2` (the renamed control). A `ctor review3` control test
pins `lp2`'s proofs.

Rulings: (1) a declaration ENTRY is a declarant, so a program that declares one type name twice
(even at one path) loses constructor facts over it; cost if wrong: lost proofs only, and such a
program is already merged by the typechecker. (2) A type variable is the only "no type
information"; everything else known and not a variant declines. Cost if wrong: lost proofs on a
tester over a polymorphic reflected parameter (`SParam`), which now declines.

Verification after round 3: `scripts/run-tests.sh refinecheck` 2,114 tests green; `-q compiler`
1,351 green; `dune build --root . @types-check --force`: `core-march-types: 492 passed, 0
failed`; `scripts/oracle-base.sh refine` IDENTICAL against `8aaeb6176`, and `refine-oracle.sh
monotone` GREEN over 139,456 sites with 0 moves.
