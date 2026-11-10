# Records and variants with String or Float fields reflect (2026-11-09)

Closes `specs/todos/2026-11-08-reflect-records-with-string-fields.md` (found
building the rollback round trip, `2026-11-08-hcr-rollback-roundtrip`).

```march
mod H5t do
  type N = { a : Int, s : String }
  fn mk(x : Int) : N do { a: x, s: "v2" } end
  fn un(n : N) : Int do n.a end
  @[lemma]
  fn l(x : Int) : {Unit | un(mk(x)) == x} do () end
end
```

`mk` and `un` were reported reflected, yet the lemma was an
`unreflectable-predicate` skip; with `s : Int` it proved. The same held for a
`Float` field and for a variant payload (`Named(String, Int)`). So an actor
whose state had a String field could not prove its rollback round trip.

## Cause

`smt_sort_of_field` (`lib/refinecheck/refine_encode.ml`) gave only `Int` and
`Bool` constructor fields a real sort; a `String` or `Float` field was the
opaque `Elem`. Reflection encodes a String value at `$Str` and a Float at the
FloatingPoint sort (D9), so `N(x, $str_v2)` was a sort conflict and the
predicate was refused before any query was sent.

## Fix

- **Field sorts.** A `String` field is `$Str`, a `Float` field `Float64`.
- **One string preamble, first.** A datatype with a String field now names
  `$Str` in its `declare-datatypes`, and the query builders assemble their
  preambles from several sources in their own orders; 16 queries of the
  fixture program (stdlib ones among them) declared such a datatype before
  `(declare-sort $Str 0)` and z3 rejected them. `Smt.hoist_string_decls`,
  applied by `Solver.check` to every query, drops each copy of the three
  string lines and puts one at the top of any query that mentions `$Str`. The
  lines are defined once, in `Smt` (`string_preamble`), and `Refine_encode`
  uses that definition. The removal matches each line as a substring, not a
  whole line: one builder emits `...)))(declare-sort $Str 0)` on one line,
  and a line-based hoist left that duplicate declaration behind (caught by
  `set-refinements` #33).
- **The float sort gate.** `mentions_float` treated any float under a
  constructor as mis-sorted, so a call passing `{ b: 2, f: 1.5 }` to a
  `{F | _.b > 0}` parameter, proved before, became a `float-sort-gate` skip
  (and the violating call went silent). A float at a constructor's Float field
  is well sorted, like one at a reflected function's Float parameter.

## Tests

`reflect-lemma` group (`test/test_refine_lemma.ml`), `scalar_fields*`:
- five lemmas over String/Float records and a String variant prove (red with
  the field-sort change reverted);
- four false ones stay unproved or refuted;
- a call passing a record with a Float field is proved, and a violating one
  violated (red with the `mentions_float` arm disabled);
- a cold check of the fixture logs no `rejected` verdict under
  `MARCH_REFINE_Z3_LOG` (red with the hoist disabled, and red with a
  line-based hoist: the fixture includes a set refinement over a String
  field, whose builder writes the same-line declaration).

## Not covered

- A `Set(String)` measure collecting a String field (`names(Ent(s, rest)) =
  union(singleton(s), names(rest))`) proves nothing, on main as here; filed as
  `specs/todos/2026-11-09-refine-set-string-measure.md`.
- At a call site a record literal's Float field is still an unknown value
  (`term_fits_sort` refuses a float term there); the other fields are checked.
