# `[P2]` JSON rewrite with combinators — the A/B against hand-written

Plan step 2 of `specs/plans/2026-08-09-parsing-and-string-search.md`. This file
is written **before** any measurement, so the bar cannot be set to whatever the
result turns out to be.

## The acceptance bar, pre-committed 2026-08-12

Measured against the existing hand-written `Json.parse` on the same inputs, on
the same machine, in the same run:

| Ratio (combinator ÷ hand-written) | Verdict |
|---|---|
| **≤ 3×** | Combinators displace hand-written for config-shaped formats. Adopt. |
| **3× – 5×** | Judgement call. Document and hand the decision up; do not adopt silently. |
| **> 5×** | Combinators do not displace hand-written here. Keep them for grammars where authoring cost dominates, and say so plainly. |

Two conditions on any number claimed:

1. **Same-process A/B.** Both parsers run in one program over the same input,
   alternating, so machine state and warmup are shared. A number from two
   separate runs is not evidence (`feedback_absolute_ms_baselines_are_not_regression_detectors`).
2. **First-position warmup discount.** The first timed variant pays a warmup
   penalty of roughly 25% on this codebase regardless of which one it is, so
   each variant is run in both positions and the better of each is compared.

Correctness and error quality are **not** graded on a curve: the combinator
parser must agree with the hand-written one on every corpus input, and must
produce a strictly more informative message on malformed input, or the
experiment has failed regardless of speed.

## Result — the experiment FAILED its own bar, on both axes

`Json.parse_c` in `stdlib/json.march` is a complete second implementation
built on `Parse`. It reuses `scan_string` and `parse_number`, so token
scanning is held constant and the comparison isolates STRUCTURAL parsing.

### Correctness: pass

16/16 valid inputs produce identical values; 7/7 malformed inputs are rejected
by both. Two real bugs in the combinator grammar were found and fixed getting
there, both worth recording because neither is obvious:

- **A number was not tokenized.** `c_number` was not wrapped in the
  trailing-whitespace token wrapper, so `{"a" : 1 , ...}` failed at the space
  after `1` while `[1,2]` passed. A grammar can be wrong only for inputs with
  optional whitespace in one specific position.
- **`ctx` wrapped only the closing delimiter.** It therefore recorded the
  offset where `}` was *expected* as the object's start, and reported "in the
  object that started at 1:10" for an object that started at 1:1. `ctx` must
  enclose the whole construct, not the token whose absence is detected.

### Speed: 16.5x slower — decisively past the >5x line

Compiled `--opt 2`, 18201-byte document, 200 iterations, same process, each
variant run in both positions:

    hand: 0.1436s / 0.1446s  -> 0.1436s
    comb: 2.5103s / 2.3725s  -> 2.3725s
    ratio 16.5x

Both positions agree closely, so this is not warmup noise.

**The leading suspect, and it is structural rather than incidental.** The
parser graph is rebuilt during the parse, not once. `delay(fn -> c_value())`
calls the constructor on *every* recursive descent, so each nested value
re-allocates the whole six-way alternative chain and every closure under it —
O(depth x grammar size) allocations per document, on top of one `ParseReply`
per combinator step. A memoizing `delay` (build once, reuse the `Parser`)
would remove the larger term and is the obvious next measurement. Until that
is tried, 16.5x is an upper bound on the cost, not a settled number.

### Error quality: mixed, not strictly better — which also fails the bar

The combinator version wins on **position and context** and loses on **what
was expected**:

| Input | Hand-written | Combinator |
|---|---|---|
| `[1,2` | unterminated array, expected ',' or ']' | 1:5: I was expecting `]` in the array that started at 1:1 |
| `{"a" 1}` | expected ':' after object key, found: '1' | 1:6: I was expecting `:` in the object that started at 1:1 |
| `{"a":}` | unexpected character: '}' | 1:2: I was expecting `}` in the object that started at 1:1 |
| `tru` | unexpected end of input, expected: true | 1:1: I was expecting a JSON value |
| `[1] x` | unexpected character after JSON value: 'x' | 1:5: I was expecting end of input |

Rows 3 and 4 are regressions. `{"a":}` should say a value is missing after
`:`; instead the deeper failure is lost because `sep_by` ends in
`alt(sep_by1, pure(Nil))`, the empty alternative succeeds, and **`and_then`'s
failure path keeps only the second parser's error** — discarding the furthest
position threaded through the success reply.

That is exactly the KNOWN LIMITATION documented on the Int-only success
channel, and this is the real grammar the plan said to revisit it against. The
evidence is now in: **widen the success channel to carry `(pos, expected)`**
and pay the allocation, or accept that ordered choice will sometimes report
the shallow error. `tru` is a separate, milder case — the label's
consumed-input rule correctly replaces the expected-set, but `true`/`false`/
`null` failing without consuming means the label hides which keyword was closest.

## Verdict

Against the bar set before measuring: **do not replace the hand-written JSON
parser.**

`Json.parse_c` has been **removed from the stdlib** rather than kept around.
It was ~100 lines loaded by every March program, in service of an experiment
that concluded "do not adopt", and it made `json.march` depend on
`parse.march`. The full implementation, the correctness harness and the
benchmark are reproducible from commit `159ea9e8`; re-run them there after
either fix below lands.

(`parse.march` stays ahead of `json.march`/`toml.march` in both load lists.
The dependency is gone, but the ordering costs nothing and the next stdlib
consumer of `Parse` will want it.)

This is a useful result, not a wasted one. It says the combinator library is
correct and its authoring story works — a complete JSON grammar is ~80 lines
against 400+ hand-written — while its execution model needs two specific,
identified fixes before it can carry a hot path:

1. memoizing `delay`, so the grammar is built once rather than per descent;
2. a wider success channel, so ordered choice stops losing the deeper error.

Both are worth doing before any further format is ported, and both are filed:

- `specs/todos/2026-08-12-parse-rebuilds-its-grammar-on-every-descent.md`
- `specs/todos/2026-08-12-parse-and-then-discards-the-deeper-error.md`

They are ordered: the `delay` fix changes the allocation budget against which
the wider success channel has to be judged, so it goes first. Neither was
speculative before this experiment; both are now measured.

**What was kept.** The three combinators the experiment forced out — `delay`,
`take_while`/`take_while1`, `optional` — stay in `Parse` with their tests.
They are not JSON-specific: recursion, single-slice token capture and
optionality are needed by every grammar, and finding them is most of what a
first real grammar is *for*.
