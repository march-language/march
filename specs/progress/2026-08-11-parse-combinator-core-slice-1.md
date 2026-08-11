# `[P2]` `Parse`: parser combinator core, first slice

**Status:** Landed (2026-08-11). First slice of
`specs/plans/2026-08-09-parsing-and-string-search.md` §10 step 1.

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

Combinators: `run`, `lit`, `and_then`, `alt`, `commit`, `ctx`, `label`.

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

The commit test is built so a broken `commit` yields `Ok`, not a different
error: its second alternative *would* succeed on the input, so swallowing the
hard failure produces a parse rather than a wrong message.

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

## Known limitation, deliberately taken

The Int-only success channel means that when `p` succeeds having internally
failed deeper than where `q` later fails, the depth survives but the
expected-set does not. `and_then` reports `q`'s error (which has a real
expected-set) rather than a bare position. Same trade the Parsec family makes.
If it produces misleading messages on a real grammar, widen the success channel
to `(pos, expected)` and pay for it — do not paper over it at the call site.
Revisit after the JSON/TOML rewrite (plan §10 step 2).

## Next

`byte`/`satisfy`, `map`/`skip_then`, `many`/`sep_by` in tail-recursive form,
`to_diagnostic` (§3.5), and the recovery combinators (§3.6) — then the golden
error corpus (§3.7), which is the acceptance bar for step 1.

`to_diagnostic` is the one with an external dependency worth planning around:
it renders into the compiler's own diagnostic type (`lib/errors/errors.ml`) so
library errors and compiler errors look identical and LSP integration is free.
Byte-offset → line/column conversion belongs there, once, at render time —
never in the parse loop.
