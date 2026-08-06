# `Array.pop` panicked but was on no `cap no_panic` list — FIXED 2026-08-05

Found while running the feasibility gate for contracting `Array.get`/`set`/`pop`
(that gate came back NO-GO — see
`specs/todos/2026-08-05-measure-over-scalar-ctor-field.md`, which stays open).

## The hole

`stdlib/array.march:392` — `Array.pop` panics on an empty vector:

```march
fn pop(v) do
  match v do
  PVec(0, _, _, _) -> panic("Array.pop: empty vector")
  ...
```

`Array` has exactly three public functions that can panic on a precondition:
`get`, `set` (index out of range) and `pop` (empty). `panic_surface_stdlib`
listed `Array.get` and `Array.set`; `Array.pop` appeared on **neither** it nor
`panic_surface_contracted`, so a `cap no_panic` module could call it and compile
clean — the capability promising no panics while admitting a call that can
panic. `specs/progress/2026-08-05-no-panic-ban-list-audit.md` does not mention
`Array.pop` anywhere, so this was an omission of that audit, not a deliberate
exclusion.

## RED, before the fix

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

`march --check` exited 1 with exactly ONE error, naming `Array.get`.
`Array.pop` drew nothing.

## The fix

- `"Array.pop"` added to `panic_surface_stdlib` (`lib/typecheck/typecheck.ml`).
- A `panic_surface_suggestion` arm: "Check `Array.length(v) > 0` before
  calling." — the wording the audit already uses for `Random.choice` /
  `Stats.*`.
- **Not** added to `panic_surface_contracted` / `Panic_surface_by_proof`'s
  covered set. There is no contract to consult, so the ban must stay purely
  syntactic. Verified programmatically that the ban lists and the covered set
  remain disjoint: ban = `{Array.get, Array.pop, Array.set}`, covered = 25
  names, intersection empty (also empty for `panic_surface_prelude`).
- The `panic_surface_stdlib` comment now records *why* these three cannot
  simply be moved into the contracted set, pointing at the open measure todo,
  so the next reader does not retry the NO-GO.

## Scope check on the rest of `array.march`

Every `panic(` site in the module mapped to its enclosing function:

| function | visibility | panics |
|---|---|---|
| `get` | public | yes (index out of range) — already banned |
| `set` | public | yes (index out of range) — already banned |
| `pop` | public | yes (empty) — **fixed here** |
| `lst_nth`, `lst_last`, `trie_get`, `trie_update` | private | yes |

The private helpers are reached from `push`/`push_leaf`/`pop_leaf` as well, but
`Array.push` is **total** from a caller's view — its `lst_nth` path panics only
on a trie-invariant violation that no input can produce. Banning it would
reject correct code, which is this subsystem's cardinal sin, so it stays
unbanned. `empty`, `length`, `is_empty`, `map`, `fold_left`, `to_list`,
`from_list` reach no panic at all. No further holes in this module.

## GREEN

Two cases in `test/test_compiler.ml`'s `cap_no_panic` group:

- `cap no_panic + unguarded Array.pop: error` — asserts on the DIAGNOSTIC
  MESSAGE (an `Error` naming `Array.pop` and "can panic"), not on `has_errors`.
  A bare boolean would go green on any unrelated diagnostic in the fixture,
  including the one about `Array.get`. Asserts through both pipelines: the
  proof-capable one and the typecheck-only one (`march check`, LSP). For a
  contracted name those two diverge; for this one they must not, and that is
  what keeps `Array.pop`'s absence from the covered set honest.
- `Array.pop outside cap no_panic: no error` — the ban is scoped to the
  capability. Without it, a change that reported the name everywhere would
  still pass the case above.

Confirmed RED first by reverting only `lib/typecheck/typecheck.ml` to `HEAD`
(file-copy swap, not `git stash`) and rebuilding: the message assertion failed,
the unscoped case passed. Restored: `run_compiler.exe -e` → 727 tests,
`Test Successful`, exit 0 (was 725).

End-to-end after the fix, same fixture: exit 1, now TWO errors — one naming
`Array.pop` with the length-check suggestion, one naming `Array.get`.

## Sweep

No `cap no_panic` module anywhere calls `Array.pop`. The only `cap no_panic`
module in the stdlib is `stdlib/json_stream.march`, which does not use `Array`;
`test/stdlib/test_array.march` calls `Array.pop` three times but declares no
capability; the `conduit` / `test_conduit_app` ecosystem checkouts contain no
`Array.pop` at all. So nothing in-tree or in the ecosystem breaks — and the
positive control above is what makes that a measurement rather than a
byte-identical no-op: the fixture demonstrably compiled clean before and errors
now.

## Docs

Both copies updated (`docs/capabilities.md`, `specs/lang/capabilities.md`), at
both the ban-list description and the transitive-blame paragraph. `CHANGELOG.md`
under `### Fixed`, stating plainly that `cap no_panic` previously compiled clean
for a function that can genuinely panic, and that affected modules now fail to
compile.
