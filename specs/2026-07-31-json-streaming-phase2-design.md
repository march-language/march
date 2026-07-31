# Streaming JSON — Phase 2: Throughput

**Status:** draft, not yet implemented
**Date:** 2026-07-31
**Scope:** phase 2 of two. Phase 1
(`specs/2026-07-30-json-streaming-design.md`) delivered the safety skeleton —
a total, resumable, constant-memory tokenizer — and explicitly ranked speed
below totality. This phase spends the speed, **behind the phase-1 interface,
without changing it**.

---

## Goal

Make `JsonStream` fast enough that streaming is not a performance penalty for
choosing it. Concretely: close the gap to `Json.parse` on in-memory input, so
that callers who need bounded memory are not paying multiples for it.

Everything phase 1 established is a hard constraint here, not a nice-to-have:
totality, absolute byte offsets, the decision table, `cap no_panic`, the
public API, and the property that **event boundaries do not depend on chunk
boundaries**. A faster tokenizer that changes any of them is a failure, not a
tradeoff.

## Why this phase is not the SIMD phase it was scoped as

Phase 1's spec named phase 2 "SIMD structural scanning", written after phase
1's benchmark reported. It has now reported, and it points somewhere else
first.

Measured 2026-07-31, compiled `--opt 2`, 20,000 NDJSON records
(`{"id": N, "name": "user-N", "active": true, "tags": [1, 2, 3]}`), run
order swapped between arms to rule out the first-position warmup effect
(`specs/benchmarks.md` methodology; the two orderings agreed to within 3ms):

| | ms | what it does |
|---|---|---|
| `Json.parse` | 62 | parses **and builds 20,000 full `JsonValue` trees** |
| `JsonStream` | 223–226 | parses and **only counts** events |

The streaming tokenizer is ~3.6× slower than the non-streaming parser while
doing strictly less work. Both are pure March, byte-at-a-time, probing with
`string_byte_at`. That is not a scanning-throughput gap — the two scan
identically. It is a **materialization** gap:

- `Json.parse`'s `scan_string` slices whole **runs**: the escape-free common
  case reaches the closing quote with its accumulator still `Nil` and returns
  **one** `string_slice` for the entire token (`stdlib/json.march`, and its
  own comment says exactly this).
- `JsonStream`'s `str_byte` calls `byte_to_char(c)` per content byte
  (`stdlib/json_stream.march:351`), so every byte costs a 1-byte string
  allocation **plus** a cons cell, joined at token end. Numbers accumulate the
  same way in `num_byte`.

So the tokenizer allocates roughly two heap objects per string byte where the
existing parser allocates one object per *run*. On string-heavy JSON — which
is most real JSON — that is the dominant term.

**This is a prerequisite for SIMD, not an alternative to it.** Phase 1 fixed
the C/March boundary rule: C helpers return *offsets* and never interpret
structure. An offset only pays if the March side then slices a run off it.
Adding vectorized scanning while per-byte materialization dominates would
optimize the smaller half of the work and — worse — under-measure what SIMD
is actually worth, producing a wrong verdict on whether the C surface earns
its keep at all.

Hence the sequencing below: **make materialization run-shaped, re-measure,
and let that number decide whether any C is written.** This is the same
discipline `specs/2026-07-26-string-performance-design.md` imposed on itself
after an asymptotically-correct argument produced defects at real sizes; the
identical failure mode is available here.

## A cheap surprise: the first task needs no C at all

`String.index_of_from` / the `string_index_of_from` builtin already exists
(`stdlib/string.march:332`, `runtime/march_runtime.c:3260`) and is backed by
`march_memmem` — two-stage `memchr` + `memcmp`, riding libc's SIMD-optimised
`memchr`.

A JSON string run ends at exactly one of two bytes: `"` or `\`. (Raw control
bytes are passed through per phase 1's decision table, so they do not end a
run.) So the run end is:

```
min(index_of_from(chunk, "\"", i), index_of_from(chunk, "\\", i))
```

— two memchr-backed scans, already vectorized, callable from March today.
Number lexemes are simpler still: a number contains no escapes, so within a
chunk it is **always** exactly one slice.

Phase 2 therefore starts with zero new C and rides existing SIMD. Whether a
purpose-built single-pass byte-set scanner beats two `memchr` passes is an
empirical question, and it is the gate in *Decision criteria* below — not an
assumption.

---

## Component 1 — Run-slicing for string content

Replace per-byte accumulation with per-run slicing in `str_byte`'s `SPlain`
path, keeping the existing piece list solely for the cases that genuinely
need it.

The piece list does not go away, and this is the crux of preserving phase 1's
guarantees. Pieces remain the mechanism for:

- **a run interrupted by a chunk boundary** — the reason `PStr` exists at
  all; a run that reaches end-of-chunk contributes its slice and the token
  stays open,
- **escapes**, which split a token into runs exactly as they do in
  `Json.parse`,
- **`\uXXXX` output**, which is synthesized bytes rather than input bytes.

What changes is only the common case: an uninterrupted run inside one chunk
becomes one `string_slice`, not N one-byte strings and N cons cells.

Three invariants the implementation must not lose, each with a specific way
of going wrong:

1. **`max_token_bytes` still trips, at the same offset.** The check moves
   from per-byte to per-run and must be applied *before* materializing the
   slice — a 10MB run against an 8MB limit must return
   `ETokenLimit(soff)` (token start, per phase 1's decision table), not
   allocate 10MB first and then complain.
2. **A pending high surrogate suppresses run-slicing.** With `hi >= 0`, the
   only legal next byte is `\`; any other byte is
   `EMalformed("lone high surrogate…")` at that byte. Run-slicing must not
   scan past it and report the error at the wrong offset — or worse, absorb
   it into a run.
3. **Event boundaries stay chunk-independent.** This is what the every-byte-
   split differential harness exists to prove, and it is the single most
   important test in the repo for this change.

## Component 2 — Run-slicing for number lexemes

`num_byte` accumulates `char_from_int(c)` per byte. A number lexeme has no
escapes and no internal structure, so within a chunk it is one contiguous
byte range: scan forward while `is_num_byte`, then take one slice. The
cross-chunk case keeps the piece list, identically to strings.

`valid_num` and `num_finalize` are unchanged — validation still runs on the
complete lexeme, so shape errors keep reporting the token start offset
exactly as the decision table specifies.

This is the simpler of the two and is worth doing even if Component 1 were to
disappoint, because it removes an allocation per digit from every numeric
field.

## Component 3 — Re-measure, and decide

This component produces no optimization. It produces the number that decides
whether phase 2 continues into C.

Re-run `bench/json_stream.march` and the `Json.parse` A/B from *Why*
(same-session, order-swapped, compiled `--opt 2`), plus a **string-heavy**
and a **number-heavy** corpus variant, since the two components are expected
to pay off unevenly and one aggregate number would blur attribution.

## Decision criteria — committed in advance

Written before the work, so the verdict is not negotiated after seeing a
number one has grown attached to:

- **If Components 1–2 land JsonStream within ~1.5× of `Json.parse`** on the
  A/B: the materialization diagnosis is confirmed. Proceed to Component 4
  only if a profile then shows scanning — not allocation, not RC — as the
  next dominant term.
- **If they land it within ~1.5× and scanning is *not* dominant:** phase 2
  **stops here** and the SIMD component is closed as not-built, with the
  measurement recorded, in the manner of phase-2-string Tasks 4 and 5. A C
  surface that does not pay is a permanent maintenance and safety liability
  under this feature's threat model, and declining to add it is a result.
- **If they do not close most of the gap:** the diagnosis in *Why* is wrong.
  Stop and profile properly before writing any C — an unexplained gap plus
  new C is how phase 1's carefully-bounded totality argument gets quietly
  spent.

## Component 4 — A byte-set scanner in C (CONDITIONAL, gated above)

Only if Component 3's gate opens. Design constraints are inherited verbatim
from phase 1's C/March boundary rule and are not renegotiable here:

> C primitives are stateless, bounds-checked scanners. All structure lives in
> March.

Shape: `march_scan_until(hay, len, byte_a, byte_b) -> offset`, one pass
finding the first occurrence of either byte, versus the current two
`index_of_from` calls. Stateless, length-counted, no NUL assumptions, no
knowledge of quoting or escapes — nothing it can misinterpret about malformed
input, because it interprets nothing.

It must be differentially tested against the pure-March implementation it
replaces, which phase 1 deliberately preserved as a known-total reference:
same corpus, same every-byte-split harness, identical event streams.

## Component 5 — `feed` without the event list (CONDITIONAL)

Phase 1's risk section flagged that `feed` returning `List(Event)` allocates
per event, and noted a fold-callback variant is API-compatible to add. If
Component 3's profile shows event-list allocation as a dominant term, add
`feed_fold(st, chunk, z, f)` alongside `feed` — additive, with `feed` kept
and reimplemented on top of it so there is one code path, not two.

Not committed now: it is exactly the kind of API surface that should follow a
measurement rather than an intuition.

## Non-goals

- **No interface change.** `feed`/`finish`/`start*`/`fold`/`build`/
  `each_value` keep their signatures and semantics. Phase 1's tests are the
  contract, and they must pass unmodified — a test that needs editing to
  accommodate a speedup is a behavior change wearing a disguise.
- **No new events, no decision-table changes**, including the deliberate
  UTF-8 pass-through and control-byte pass-through choices.
- **No typed decoder layer.** Still deferred (phase 1 Component 4).
- **No string views / mmap.** A view type would subsume run-slicing, but it
  is a representation change touching RC/FBIP and the shared-owner refcount
  contention documented at `string_parallel_scan`'s 4-worker ceiling. Out of
  scope; noted so the overlap is deliberate rather than forgotten.
- **No parallel parsing.** The chunk-boundary problem is real and unsolved
  (`string_parallel_scan`'s "known limitation, deliberate").

## Risks

- **Run-slicing silently changing event boundaries.** The failure mode is a
  token whose split differs by chunk arrival — invisible in aggregate tests,
  caught only by the every-byte-split differential. That harness must be run
  and green before any benchmark number is believed, and never weakened to
  accommodate a fast path.
- **Token-limit regression.** Moving the check from per-byte to per-run is
  the most likely place to accidentally allow an unbounded allocation before
  the limit trips — precisely the property the adversarial token-bomb test
  exists to protect. Check before materializing.
- **`cap no_panic` friction** on new offset arithmetic, as in phase 1.
- **CAS/staging traps** when benchmarking: `dune build --root . @install`
  restages stdlib before compiled runs, and codegen-affecting flags must be
  in `cas_flags` or cached binaries silently ignore them. A/B arms need the
  artifact cache cleared between them; two arms served the same cached
  binary once produced a confident null result in this repo.
- **Load contamination** on timings — concurrent sessions run suites in this
  worktree set; slow-with-flat-RSS means load, not regression.

## Open questions

1. Whether `index_of_from` called twice beats one purpose-built two-byte
   scanner enough to justify the C — this is Component 3's gate, listed here
   so it is not mistaken for settled.
2. Whether run-slicing changes the partial-token memory accounting enough to
   retire phase 1's deferred minor (the constant-factor looseness), or merely
   improves it. Expected: the common case collapses to one slice, but a
   near-limit token straddling many chunks keeps a piece per chunk, which is
   already bounded by chunk count.
3. `EvNumRaw(String)` (phase 1 open question 1) interacts with Component 2 —
   if number lexemes become slices anyway, preserving the raw lexeme becomes
   nearly free. Worth revisiting *during* Component 2 rather than after.

## Deliverables

- Run-sliced `str_byte`/`num_byte` in `stdlib/json_stream.march`, with phase
  1's full test suite passing **unmodified**.
- Benchmark results per Component 3 recorded in `specs/benchmarks.md`, with
  the phase-1 baseline retained alongside for comparison.
- A recorded verdict on Components 4–5 — built, or closed as not-built with
  the measurement that closed them.
- `specs/todos.md` / `specs/progress.md` / `CHANGELOG.md` updated in the same
  commits, per `CLAUDE.md`.
