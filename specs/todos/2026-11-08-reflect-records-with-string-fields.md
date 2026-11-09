`[P2]` A record with a `String` field is not usable in a lemma's predicate

Found 2026-11-08 while building the rollback round trip (progress
`2026-11-08-hcr-rollback-roundtrip`).

```march
mod H5t do
  type N = { a : Int, s : String }
  fn mk(x : Int) : N do { a: x, s: "v2" } end
  fn un(n : N) : Int do n.a end
  @[lemma]
  fn l(x : Int) : {Unit | un(mk(x)) == x} do () end
end
```

`mk` and `un` are both reported `reflected` by `--reflect-report`, yet the lemma is an
`unreflectable-predicate` skip. The same program with `s : Int` (and `s: 2`) proves. So a
reflected function over a record with a String field cannot be unfolded in a stage-2 query:
probably the record's `$Str` field sort, or the string literal constant, does not reach the
query's declarations.

Effect: an actor whose state has a String field gets `not proved` for its rollback round trip
(and any lemma over such a record). Done when the lemma above proves, with a RED fixture.
