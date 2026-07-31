# Refinement legibility follow-ups (OPEN, from the 2026-07-28 `--refine-report`/measure-alias/`cap verified` work)

- **No `@[trusted]` escape hatch.** `cap verified` has no way to accept a single
  obligation the checker cannot discharge; the only outs are `assert` or dropping
  the capability. Until this exists, `cap verified` is not usable at scale.
- **A refinement in an `interface`'s OWN method signature is unenforced.**
  `fn run : a -> {Int | _ > 0} -> Int` written in the interface obliges no call
  site. Nothing assumes it either, so this is a missing check rather than an
  unsound one — but it silently does nothing, which is the failure mode this
  area keeps producing. The supported spelling is a refinement on the `impl`
  method's parameter (adopted when the method name is unambiguous).
- **Postconditions are not in the ledger.** `check_post` neither records nor
  escalates, so `--refine-report` undercounts by every undischarged *return*
  refinement and `cap verified` silently permits one. Still open as of
  2026-07-29 and stated in both `specs/lang/refinement-types.md` and
  `docs/refinement-types.md`.
- **The measure-alias gates are unit-global.** One genuine competing binding
  anywhere in the compilation unit — the prepended stdlib, or any
  `MARCH_LIB_PATH` dependency the author never opened — withdraws
  `List.length` / `String.byte_size` / `string_byte_length` as measure aliases
  for the entire program. Deciding whether a competitor could actually win at a
  given call site needs a resolver the pass does not have there, and the error
  directions are asymmetric (over-withdraw = silence, under-withdraw = a false
  positive), so the coarseness is deliberate — but it is a real coverage cost
  and the glob-import regression below shows how invisibly it can bite.
- **`collect_direct_names` (`lib/desugar/desugar.ml`) still ends in a wildcard**,
  covering only `DFn` and `DLet`. It is the fifth walk of this family and the one
  that was not made exhaustive; it decides which self-qualified spellings
  `strip_entry_self_qual` rewrites.
- **Impl-method contract adoption ignores `use`-imported impl methods** when
  judging whether a method name is ambiguous: `adoptable_impl_methods` counts
  only the compilation unit's own `DFn`/`DImpl` declarations.
- **`alias-withdrawn` attribution does not follow a laundered guard.**
  `let n = List.length(ys)` then `if n > 0` falls back to the general
  `solver-undecided` message even when the withdrawal really was the cause.
- **A qualified spelling INSIDE a predicate enforces nothing, silently.**
  `{List(Int) | List.length(_) > 0}` parses and typechecks, and enforces
  nothing at all: refinement predicates are not run through desugar, so
  `List.length` stays an `EField` chain rather than the dotted `EVar` the alias
  keys on, and the obligation is skipped. Pre-existing, not introduced here —
  but it is the one case this branch leaves invisible, which is exactly the
  failure mode `--refine-report` exists to surface. At minimum the pass should
  WARN on an unreflectable qualified call in a predicate; the fuller fix is to
  desugar predicate expressions the way bodies are. (The supported spelling is
  the bare measure, `len(_) > 0`.)

---
