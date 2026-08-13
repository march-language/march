# `[P1]` `Regex.find`/`replace`/`split` are linear — the ReDoS is fully closed

**Status:** Landed (2026-08-13). Completes
`2026-08-12-regex-linear-matcher.md`, which closed only the boolean API.

## What was left open

`matches` was already linear, but `find`, `find_all`, `replace`,
`replace_all` and `split` still called the backtracking matcher, because they
need a `(start, end)` span and the NFA as first built answered only "does it
match". Those are the entry points an application is most likely to point at
user input, so the measured denial of service was still reachable — and worse,
the merged changelog said the ReDoS was closed, which a reader could
reasonably take to mean all of `Regex` was safe.

## How positions are tracked

Each active NFA state additionally carries the **earliest input offset that
reached it**. When the accepting state is live, that offset is the match
start. Duplicate states are merged keeping the smaller offset, so the active
set still cannot exceed m+1 entries and the linear bound holds.

Semantics are leftmost, then longest: once a match starting at `s0` is known,
no new start states are seeded (a later start cannot be more leftmost), and
the end is extended while states carrying `s0` keep accepting.

## Verified against the old engine, not assumed

Greedy backtracking and leftmost-longest are **not the same rule in general**,
so the todo that filed this work said to verify rather than assume. Both
engines are retained — `find_backtracking` alongside `find_linear` — and the
differential test compares the **matched substring**, not just a boolean,
across 21 cases: literals, `.`, `*`, `+`, `?`, anchors at both ends, character
classes and ranges, `\d`/`\w`, empty matches (`a*` against `bbb`), patterns
where greedy ordering is load-bearing (`a*ab` against `aab`, `a*a` against
`aaa`), and non-matches. They agree everywhere on the supported syntax.

## Result

Pattern `a*a*a*a*b` (never matches), compiled `--opt 2`:

| call | n=80 before | n=80 after | n=2000 after |
|---|---|---|---|
| `find` | 5.7s (via the same matcher) | 0.00039s | 0.0096s |
| `find_all` | " | 0.00037s | — |
| `replace` | " | 0.00036s | — |
| `replace_all` | " | — | 0.0094s |
| `split` | " | 0.00042s | — |

Note the repeated-scan family (`find_all`, `replace_all`, `split`) restarts the
search after each match, so a subject with many matches is O(matches x n x m).
That is ordinary quadratic-ish scanning, not the pattern-driven blowup this
work removed — each individual scan is bounded by the pattern length.

## Also fixed

The `CHANGELOG.md` entry that should have accompanied the first half. It now
describes the whole fix, states the measured numbers, and corrects the
`(a+)+$` framing.
