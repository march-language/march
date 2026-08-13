# `[P1]` `Regex.matches` is now linear-time — the ReDoS is closed for the boolean API

**Status:** Landed (2026-08-12). Plan §6.2 of
`specs/plans/2026-08-09-parsing-and-string-search.md`.

## The vulnerability, measured rather than asserted

`stdlib/regex.march` matched by backtracking: each quantifier tried its
longest run first and retried shorter ones on failure, and `find_match`
retried every start position. Repeated quantifiers over one class followed by
a byte that never matches therefore cost O(n^k).

Compiled `--opt 2`, pattern `a*a*a*a*b` against a run of `a`:

| n | time |
|---|---|
| 20 | 0.013s |
| 40 | 0.223s |
| 60 | 1.395s |
| 80 | **5.675s** |

**80 bytes of input, five seconds.** Reachable from a pattern in a config file
plus a short user-supplied string.

**One correction to the plan.** §6.0 cites `(a+)+$` as the live example. That
pattern is **not expressible in this engine** — it has neither groups nor
alternation. The real exposure is *polynomial*, not exponential, and needs
repeated quantifiers rather than nested ones. Still a denial of service; a
different shape than advertised, and worth stating accurately.

## Why the fix is small

That same narrowness is the opportunity. The supported language is a **flat
sequence of quantified atoms** plus optional `^`/`$`, so the NFA is a line of
states — state `i` means "items[0..i) consumed". No general Thompson
construction is required:

    epsilon : i -> i+1   when item i may match zero times
    byte c  : i -> i+1   when atom i matches c and the quantifier is spent
              i -> i     when atom i matches c and may repeat

`X+` is rewritten as `X X*` first, so the simulation handles three quantifiers
instead of four. Simulating the *set* of reachable states is O(n × m) and
cannot blow up: there are only m+1 states, so no input can make the per-byte
work grow.

## Result

`matches` / `matches_opts` now route through the NFA. Same input as above:

| n | before | after |
|---|---|---|
| 80 | 5.675s | **0.00022s** |
| 400 | ~95 min (extrapolated) | 0.00127s |
| 2000 | — | 0.00579s |

26,000× at n=80, and the scaling is linear: 5× the input costs ~5× the time.

## Correctness

The two engines must agree, or this is a silent behaviour change rather than a
performance fix. `matches_backtracking` is retained and public **precisely so
the parity test has something to compare against** — a test that compared the
linear engine with itself would prove nothing.

Parity is asserted across literals, `.`, `^`, `$`, `*`, `+`, `?`, character
classes, negated classes, ranges, `\d`/`\w`/`\s` and their negations, empty
patterns and empty subjects, plus the blowup patterns themselves. Plus a
linearity test: 400 bytes against `a*a*a*a*b`, which would not finish under
backtracking.

**`test/stdlib/test_regex.march` was registered in no runner at all** — 21
tests that had never executed. Wiring it up came first, so the engine change
had a safety net before it was made. That is the third unwired test file found
in this work.

## What is NOT fixed

`find`, `find_all`, `replace`, `replace_all` and `split` still use the
backtracking `find_match`, because they need match *positions* and the NFA as
built answers only "does it match". **They remain vulnerable.** Filed:
`specs/todos/2026-08-12-regex-find-family-still-backtracks.md`.
