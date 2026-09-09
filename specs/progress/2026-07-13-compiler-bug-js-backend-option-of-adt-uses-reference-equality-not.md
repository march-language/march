# Compiler bug — JS backend `Option`-of-ADT `==` uses reference equality, not structural equality (filed, not fixed, 2026-07-13)


- ❌ **Comparing an `Option(ADT)` with `==` on the JS target always evaluates
  `false`, even when both sides hold structurally identical values**, when
  the right-hand side is a freshly-constructed value (e.g. `Some(SomeCtor)`
  written inline at the comparison site). Minimal shape: `game.special ==
  Some(Perihelion.Upgrades.TrajectoryPreview)` where `SpecialKind` is a
  zero-argument-constructor sum type. `lib/tir/js_emit.ml` compiles this to
  raw JavaScript `===` (object-reference equality) instead of calling the
  compiler's own generated structural-equality helper (`__eq_TypeName`, see
  `emit_eq_fn`) — so two objects with identical `{ $: "Some", _0: { $: "..."
  } }` shape, but different allocations, never compare equal. Confirmed via
  reading the emitted JS directly (`$t29798 === $t29800` where `$t29800` is
  a brand-new object literal built at the comparison site) and via a pixel-
  level canvas check in a live browser (the gated draw call, and even an
  unconditional debug `println` inside its branch, silently never executed
  — no thrown error, no console output, just always-false).
- **Found via Perihelion's trajectory-preview line** (`game.special ==
  Some(Perihelion.Upgrades.TrajectoryPreview)` in `perihelion.march`'s
  `draw`), which never rendered on the compiled JS build despite the
  underlying physics (`predict_trajectory`) being independently confirmed
  correct via the interpreter (`Perihelion.Core.predict_trajectory` returns
  24 well-formed points from a direct interpreter test). The interpreter
  and (presumably) native/LLVM backends are NOT suspected of the same bug —
  this was only observed on `--target js`, and the codebase's established
  convention elsewhere is to compare `Option`/ADT values via `match`, not
  `==`, which sidesteps the bug entirely (pattern matches compile to
  tag-based `switch` dispatch, not `===`).
- **Workaround applied in Perihelion** (not a compiler fix): rewrote the one
  affected comparison as `match game.special do Some(TrajectoryPreview) ->
  ... | _ -> () end`, matching this codebase's already-universal convention
  for every OTHER `Option`/ADT comparison in the game. This was, in fact,
  the ONLY site in the entire `demo_app/perihelion/` tree that compared an
  `Option` via `==` rather than `match` — everywhere else (Task 3/8/9's
  special-swap logic in `apply_upgrade`/`collide_ball_pickups`) already
  used `match` and was unaffected.
- **Not investigated:** whether this affects non-`Option` generic wrapper
  types, tuples, or records containing ADT fields compared via `==` on the
  JS target, or whether `EApp`'s `eq_`-named dispatch (`js_emit.ml:553-559`,
  which correctly calls `__eq_TypeName`) is simply never reached for values
  of a builtin/stdlib parametric type like `Option` — the fix likely lives
  in how `==` on a generic/parametric-typed expression resolves its
  equality strategy before reaching `js_emit.ml`, not in `js_emit.ml`
  itself. Scope and root cause not narrowed further; flagged for separate
  investigation.
