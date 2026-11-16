`[P3]` A `Set(String)` measure over a String constructor field proves nothing

Found 2026-11-09 while reflecting String fields
(`specs/progress/2026-11-09-reflect-records-with-string-fields.md`).

```march
mod SM do
  type Ent = Ent(String, Ent) | Done
  @[measure]
  fn names(e : Ent) : Set(String) do
    match e do
      Ent(s, rest) -> union(singleton(s), names(rest))
      Done -> empty()
    end
  end
  fn add(s : String, e : Ent) : {Ent | member(s, names(_))} do Ent(s, e) end
  fn need(e : {Ent | member("a", names(_))}) : Int do 0 end
  fn go() : Int do need(Ent("a", Done)) end
end
```

`add`'s postcondition is `unreflectable-subject` and `go`'s call
`solver-undecided`, on main before and after String fields got the `$Str`
sort. `set_ret_elem` gives a `Set(String)` measure the element sort `Elem`
while the field it collects is now `$Str`, so the arm's axiom is refused by its
sort check; the measure should be `Set($Str)`.

Done when both obligations above prove, with a wrong variant that stays
unproved.
