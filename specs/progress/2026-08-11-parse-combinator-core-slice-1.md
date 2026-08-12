# `[P2]` `Parse`: parser combinator core

**Status:** Landed (2026-08-11). Covers most of
`specs/plans/2026-08-09-parsing-and-string-search.md` §10 step 1; the
recovery combinators (§3.6) and the golden error corpus (§3.7) remain.

New stdlib module `stdlib/parse.march`, registered in
`lib/modules/stdlib_manifest.ml` and exercised by `test/stdlib/test_parse.march`
(runner entry in `test/test_stdlib_march.ml`).

## What shipped

The error contract from plan §3.1 is in place *before* any grammar convenience,
which was the whole point of sequencing it this way:

```march
type Expected  = ExpLit(String) | ExpLabel(String) | ExpEof
type ParseErr  = { pos: Int, expected: List(Expected), context: List((String, Int)) }
type ParseReply(a) = ROk(a, Int, Int) | RFail(ParseErr) | RCut(ParseErr)
type Parser(a) = Parser(String -> Int -> ParseReply(a))
```

Primitives: `lit`, `byte`, `byte_if`, `eof`, `pure`.
Sequencing: `and_then`, `skip_then`, `skip_first`, `map`.
Choice: `alt`. Repetition: `many`, `many1`, `sep_by`, `sep_by1`.
Error control: `commit`, `ctx`, `label`. Running: `run`.
Rendering: `render`, `line_col`.

Both asymmetries the plan argued for are real in the code:

- **Success carries only integers.** `ROk` holds the value, the new offset, and
  the furthest offset any sub-parse failed at. Expected-sets and context stacks
  are built only on failure paths.
- **Soft vs hard failure is in the type.** `RFail` / `RCut` rather than a
  boolean, so `alt` cannot forget to check it — and `alt` propagates a `RCut`
  instead of trying its second alternative, which is what makes a commit
  point stick.

**Furthest-failure merging (§3.2) works**, which is the highest-leverage rule
for message quality: when ordered choice exhausts its alternatives it reports
the one that got deepest, and merges expected-sets on ties.

**Commit points and context (§3.3)** are in: `commit` upgrades a soft failure
to hard, `alt` refuses to backtrack past it, and `ctx` pushes a
`(name, start_offset)` frame onto hard failures only — a soft failure is a
path not taken, and naming every alternative a parser merely tried would be
noise rather than context.

**Labels carry the consumed-input rule (§3.4).** `label` substitutes its
human-named class *only* when the inner parser failed without consuming; if
the parser got somewhere before failing, its specific error is kept, so a
label can never hide real progress.

## Verification

Written test-first. Slice 1 (`run`/`lit`) was watched failing with
`Unknown module Parse` before the module existed.

Where implementation and tests were written together, non-vacuousness was
established afterwards by sabotage — each mutation reverted and re-verified
green:

| Sabotage | Test that caught it |
|---|---|
| `merge_err` returns `b` (the "report the last alternative" bug) | furthest-failure |
| `label` drops its consumed-input guard | label keeps inner error |
| `commit` returns `RFail` instead of `RCut` | commit blocks alt |
| `many` swallows `RCut` instead of propagating | many propagates cut |
| `line_col` stops counting newlines | render reports 2:3 |

The commit test is built so a broken `commit` yields `Ok`, not a different
error: its second alternative *would* succeed on the input, so swallowing the
hard failure produces a parse rather than a wrong message.

The `many` zero-width guard is *not* in that table on purpose: removing it
produces an infinite loop, and there is no `timeout(1)` on this machine, so
spawning an unkillable spin to prove the point was a worse trade than
reasoning from the loop — without the guard the recursive call advances
neither `i` nor `acc`, so it cannot terminate. The guard's presence is pinned
by a test that `many(lit(""))` returns at all.

An earlier sabotage attempt (`if a.pos > b.pos` → `if false`) did *not* fail
the test, because the tie branch still selects `a.pos`. Worth recording: a
sabotage that leaves the observable behavior intact proves nothing, and it
looked at first glance like the test was vacuous when it was the sabotage that
was inert.

## Findings that fed back into the plan

- **March has no character literal.** The plan's `chr('(')` examples were not
  valid March; the API is byte-oriented (`Int` codes via `string_byte_at`) with
  `lit(String)` as the ergonomic primitive. Plan examples corrected.
- **`Reply` collides.** `channel.march` already declares a `Reply` constructor
  and the stdlib shares one global namespace, so the reply type is
  `ParseReply`. No other name in the `.march` corpus collides with the new
  types or constructors (checked repo-wide).
- **Multi-argument function types are written curried** (`f : b -> a -> b`,
  per `sort.march`'s comparators) but called uncurried (`f(x, y)`).
- **A lambda body cannot host a local named recursive function.** `lit`'s
  byte-scan loop is a module-level tail-recursive `pfn`, not a local `fn go`
  inside the closure.
- **Adding a stdlib module trips `scripts/check-docs.sh`** (module count
  112 → 113). Current-truth docs updated; two spec statements describing a
  historical blast-radius sweep over 112 modules carry `doc-lint:ignore-count`
  markers instead, since editing them would falsify what was actually swept.
- **`satisfy` is a reserved keyword** (it belongs to refinement types), so the
  conventional combinator name does not parse as a function. It is `byte_if`
  here, which also pairs with `byte`.
- **A lambda cannot destructure a tuple parameter.** `fn ((x, _)) -> x` is a
  parse error; `fn (x, _) -> x` is a *two-parameter* lambda, not a
  destructure. Use `fn (pr) -> match pr do (x, _) -> x end`. (Named functions
  *can* destructure: `fn f((x, y)) do ... end`.)
- **The test harness's stdlib load list is not the production manifest.**
  `test_stdlib_march.ml` has its own `all_stdlib_decls`, and `tuple.march` is
  in `stdlib_manifest.ml` but not in it — so `Tuple.first` worked under the
  real compiler and was `unbound variable` under the harness. `parse.march`
  now uses pattern destructuring and depends on neither. Keeping a new stdlib
  module dependency-light avoids the whole class.

## Known limitation, deliberately taken

The Int-only success channel means that when `p` succeeds having internally
failed deeper than where `q` later fails, the depth survives but the
expected-set does not. `and_then` reports `q`'s error (which has a real
expected-set) rather than a bare position. Same trade the Parsec family makes.
If it produces misleading messages on a real grammar, widen the success channel
to `(pos, expected)` and pay for it — do not paper over it at the call site.
Revisit after the JSON/TOML rewrite (plan §10 step 2).

## Rendering

`render` produces the compiler's voice from a byte offset:

    2:3: I was expecting `Z`
    1:3: I was expecting `cd` in the block that started at 1:3

Byte offset → 1-based line/column happens once, in `line_col`, at render time
— never in the parse loop, which is the whole reason positions are integers.
Only the innermost context frame is named: a full stack reads as a trace, and
a parse error is not a stack trace.

Two guards worth naming, both pinned by tests:

- `many`'s `j == i` check. A parser that succeeds without consuming (`lit("")`)
  would otherwise be retried at the same offset forever — a hang that looks
  like an infinite loop in the user's grammar.
- `many` propagates `RCut` rather than ending the list. Once a commit point
  inside an item has been passed the item was not optional, and stopping
  quietly would turn a real error into a short parse.

## Next

The recovery combinators (§3.6) — `recover(p, sync, default)` and `fence(p)` —
so a driver can collect several errors from one pass instead of stopping at
the first. Then the golden error corpus (§3.7), which is the actual acceptance
bar for step 1.

Separately, an OCaml-side `to_diagnostic` that renders a `ParseErr` into
`lib/errors/errors.ml`'s type would make library and compiler diagnostics
indistinguishable and give LSP integration for free — that is what §8's
editor probes want.
