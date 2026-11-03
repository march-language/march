`[P3]` - [x] **Module-declared scalar aggregates get the unboxed layout.**

First slice of `specs/todos/2026-10-07-module-type-layouts.md` (which stays
open for the newtype and niche layouts). Landed 2026-10-11.

## What was wrong

Lowering registers a type declared in a module as `Geo.P2` and builds its
values under the short key `P2.P2`. `Kind.canonical_name` asked every
representation question under the short name, which missed the qualified
declaration, so a module-declared `P2(Int, Int)` or `Vec3(Float, Float,
Float)` was always a boxed heap cell. Only types declared directly in the
entry module (registered bare) got the Milestone-3 struct-value layout.

## The change

- `Kind.canonical_name` resolves a short name to its qualified declaration
  when that declaration is an unboxed aggregate (`k_unboxed_short`, an index
  built with the table). Both spellings answer `Unboxed`, the construction
  site's short key builds `%ub.Geo_P2`, and the match reads the same struct.
- Only aggregates. An unboxed value that enters a ptr slot (list element,
  tuple field, actor message, generic `to_string`) is boxed by
  `Llvm_ctx.coerce` into the same tagged cell the Boxed layout uses, so the
  runtime, the wire format and printing see what they saw before. Newtype
  and niche have no such boundary (see the todo).
- `Process.LiveProcess` is built by C as a boxed cell
  (`process_spawn_async`), so `c_boxed_types` excludes it from the unboxed
  set. Extern-crossing, actor-message and colliding types were already
  excluded. Stdlib types that change layout: `DateTime.Date`,
  `DateTime.Time`, `Decimal.Decimal`, `JsonStream.JsCfg`,
  `JsonStream.JsonLimits`; none is built or read by the C runtime.
- `llvm_case.ml`'s unboxed fast path names the struct through
  `canonical_name` (it used the scrutinee's spelling and produced
  `%ub.P2` against a `%ub.Units_P2` value).
- A match whose result slot is an unboxed struct and whose default arm
  panics (a tuple match such as `match (a, b) do (P2(..), P2(..)) -> ...`)
  stored the panic's Unit `0` into the struct slot: invalid IR
  (`store %ub.P2 0`). This was already broken for entry-module types on
  main. A diverging arm now stores `poison`.

## Proof

- `test_codegen` / `unboxed_aggregates` / "module-declared aggregate is
  unboxed": a nested-module `Vec3` is built with `insertvalue
  %ub.Geo_Vec3`, read with `extractvalue`, and the module has no
  `march_alloc` call. "C-built module aggregate stays boxed" pins
  `LiveProcess` Boxed under both spellings.
- `test_kind` "both spellings of a type get one answer" now expects
  `Lib.P2` Unboxed under both spellings.
- `test/native/module_unboxed_aggregate.march`: match, list element, tuple
  field, closure capture, boxed-constructor field, derived `Eq` and generic
  `to_string`, compiled output equal to the interpreter's. Refine audit
  baseline regenerated.
- Benchmarks (`--compile --opt 2`, A/B against origin/main, 5 interleaved
  runs, load avg ~35): `tree_transform` median 795 ms base / 716 ms new,
  `binary_trees` 82 / 83 ms. Neither declares a module aggregate, so this is
  noise; outputs identical.
