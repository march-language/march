# `[P2]` `Array.pop` panics but is not on the `cap no_panic` ban list

Found while running the feasibility gate for contracting `Array.get`/`set`/`pop`
(see `specs/todos/2026-08-05-measure-over-scalar-ctor-field.md` for that
NO-GO). Not fixed there, because fixing it is a ban-list content change of
exactly the shape the 2026-08-05 ban-list audit did, and it needs that audit's
full treatment (test, docs, stdlib sweep), not a drive-by edit inside an
unrelated gate.

`stdlib/array.march:392` — `Array.pop` panics on an empty vector:

```march
fn pop(v) do
  match v do
  PVec(0, _, _, _) -> panic("Array.pop: empty vector")
  ...
```

`Array` has exactly three public functions that can panic — `get`, `set`, `pop`.
`Typecheck.panic_surface_stdlib` lists `Array.get` and `Array.set`; `Array.pop`
appears on neither the syntactic ban list nor
`Typecheck.panic_surface_contracted`, so a `cap no_panic` module can call it and
compile clean.

Reproduced against `bin/main.exe` at `faabfd06`:

```march
mod PopBan do
  cap no_panic
  fn f(v) do
    let (v2, x) = Array.pop(v)
    x
  end
  fn g(v) do Array.get(v, 0) end
  fn main() : Int do 0 end
end
```

`march --check` exits 1 with ONE error, naming `Array.get`. `Array.pop` draws
nothing. This is the direction the plan's global constraints call out as
equally serious to a false positive: a call that can genuinely panic compiling
clean inside a capability that promises it cannot.

`specs/progress/2026-08-05-no-panic-ban-list-audit.md` records the audit that
added twelve coverage-hole names; `Array.pop` is not mentioned anywhere in it,
so this looks like an omission rather than a deliberate exclusion.

- [ ] Add `"Array.pop"` to `panic_surface_stdlib` (NOT to
      `panic_surface_contracted` — it has no contract, and per the linked todo
      it cannot get a dischargeable one until scalar constructor fields survive
      call-site reflection).
- [ ] Add a `panic_surface_suggestion` case in the style of the existing
      entries ("check `Array.length(v) > 0` first", mirroring the
      `List.tail`/`Random.choice` wording).
- [ ] Test both directions: a `cap no_panic` module calling `Array.pop` must
      ERROR, and the same call outside `cap no_panic` must stay silent.
- [ ] Stdlib + ecosystem sweep with a positive control, since this turns
      previously-clean code into an error; changelog under `### Changed`.
