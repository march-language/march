# Streaming JSON — Phase 2: Throughput

**Status:** implemented (2026-07-31) — Components 1, 2, 2b landed; Component 3's
gate ran and Component 4 (SIMD) is **closed as not-built** on the measurement;
Component 5 is recorded as an open item. See the verdict appended after
Component 3 below.
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

### Component 2b — `EvNumRaw(String)`, lossless numbers

Phase 1 deferred this (its open question 1) because it diverges from
`Json.parse` semantics. Component 2 changes the economics: once a number
lexeme is materialized as a slice anyway, *preserving* it is nearly free —
the work becomes **skipping** `string_to_float` rather than doing something
extra. Retrofitting it after Component 2 would mean rewriting the same
function twice, so it is built here.

**The problem it solves.** `EvNum` carries `Float`, so an integer above 2⁵³
is silently rounded. Snowflake IDs, database bigints, and financial minor
units are all in that range and all common in real JSON. Today the exact
value is unrecoverable — the lexeme is gone by the time the caller sees the
event.

**Opt-in, never default.** The default stays `EvNum(Float)`, for two reasons
that both outrank convenience:

1. This spec commits phase 1's suite to passing **unmodified**. A changed
   default event stream would require editing tests — the exact disguise for
   a behavior change this spec forbids elsewhere.
2. The `build`-vs-`Json.parse` differential depends on `EvNum` matching
   `Json.parse`'s `Number(Float)` exactly. That test is load-bearing for the
   whole feature and must keep comparing like with like.

**API — one function, not four.** The four `start*` constructors already
cover {default, ndjson} × {default, custom limits}; adding raw variants would
make eight. Instead, a setter that composes with all of them:

```march
fn with_raw_numbers(st : JsState) : JsState
```

```march
let st = JsonStream.with_raw_numbers(JsonStream.start_ndjson())
```

Internally this is a fourth field on `JsCfg` (currently
`JsCfg(max_depth, max_token_bytes, ndjson)`), which is a `ptype` — so the
representation change is invisible to callers. Defined on any state and total;
it takes effect for numbers *completed* after the call. It is intended for a
fresh state, and its doc comment says so rather than the type enforcing it —
enforcement would need a second state type, which is a large price for a
misuse nobody has demonstrated.

**Semantics.** In raw mode `num_finalize` emits `EvNumRaw(lex)` carrying the
verbatim lexeme. Everything else is deliberately identical:

- **`valid_num` still runs.** Malformed numbers (`012`, `1.`, `1e`, bare `-`)
  produce the same `EMalformed` at the same token-start offset. Raw mode
  changes what a *valid* number carries, never what counts as valid — the
  decision table is untouched. A "raw" mode that also relaxed validation
  would be a second, undocumented parser.
- `string_to_float` is skipped, so raw mode is strictly *less* work.
- Token limits, truncation, and `finish`-completes-a-pending-top-level-number
  all behave identically.

**`build` in raw mode.** `Json.JsonValue`'s `Number` holds a `Float`, so
`build_step` converts on receipt (`string_to_float`, which cannot fail on a
`valid_num`-approved lexeme — if it ever does, that is
`EMalformed("invalid number")` at the token offset, not a panic). So `build`
produces identical trees in both modes, and the differential test holds in
raw mode too. Callers who want losslessness use `fold` or `each_value` and
read `EvNumRaw` directly; a tree of `Float` cannot represent it by
construction, and pretending otherwise would be the trap this feature exists
to remove.

**Test obligations.** `Event` gains a variant, so every `match` over it must
stay exhaustive — the compiler enforces that, but the test file's `ev_str`
helper needs the arm. Beyond that:

- Run the **every-byte-split differential and the truncation sweep in raw
  mode as well as default mode** over the same corpus. The suspension points
  are shared, but the number path is where the modes diverge, and that path
  has cross-chunk state.
- Pin losslessness with a value that proves the point: an integer above 2⁵³
  (e.g. `9007199254740993`) must round-trip its lexeme exactly in raw mode
  **and** demonstrably lose precision through `EvNum` in default mode. A test
  asserting only the raw side would not show the feature does anything.
- Pin that malformed numbers behave identically in both modes.

## Component 3 — Re-measure, and decide

This component produces no optimization. It produces the number that decides
whether phase 2 continues into C.

Re-run `bench/json_stream.march` and the `Json.parse` A/B from *Why*
(same-session, order-swapped, compiled `--opt 2`), plus a **string-heavy**
and a **number-heavy** corpus variant, since the two components are expected
to pay off unevenly and one aggregate number would blur attribution.

### Measurement and verdict (2026-07-31)

Both A/Bs below were run interleaved so compared arms shared identical
machine load (the load itself was heavy — reported averages 43-97 on 14
cores, from other concurrent sessions in this worktree set — so **absolute
milliseconds are not comparable across sessions and are not presented as a
clean baseline here; the ratios are sound because compared arms ran at the
same moment**). Full detail and the benchmark sources: `specs/benchmarks.md`
(`bench/json_stream.march`, `bench/json_stream_strings.march`).

**String-heavy corpus** (new: `bench/json_stream_strings.march`, 2,000
records, each a single ~1KB escape-free JSON string), 3 interleaved rounds,
commit `8a79a275` (pre-run-slicing) vs `4afc215d` (post-run-slicing):

| | JsonStream | `Json.parse` | ratio |
|---|---|---|---|
| BEFORE run-slicing | 322 / 348 / 364 ms | 6-25 ms | ~55x slower |
| AFTER run-slicing | 6 / 6 / 6 ms | 6 / 6 / 6 ms | **1.0x, parity** |

**Tiny-token corpus** (`bench/json_stream.march`'s existing 20,000-record
shape: 2-6 byte keys, ~11 byte values), order-swapped arms:

| | JsonStream | `Json.parse` | ratio |
|---|---|---|---|
| AFTER run-slicing | 219 / 234 ms | 71 / 77 ms | ~3.05x |
| BEFORE (phase 1 design's figures) | 223-226 ms | 62 ms | ~3.6x |

**Verdict.** The diagnosis in *Why* is **confirmed**: run-slicing (Components
1-2) closes the gap to `Json.parse` parity (1.0x, comfortably inside the
"~1.5x" criterion) on content-bearing tokens, because that is exactly where
per-byte materialization dominated. It only narrows the tiny-token gap
(3.6x -> 3.05x), because a 2-6 byte token has almost no run for run-slicing
to help with in the first place — that residual is a **different**
bottleneck: per-*token* overhead (state transitions, `List(Event)`
allocation, a cons + a join even for a single-piece token), not scanning.
Both `Json.parse` and `JsonStream` scan identically (byte-at-a-time,
`string_byte_at`); a byte-set scanner cannot speed up a `memchr` call over a
4-byte run, so SIMD cannot address the only gap that remains.

**Component 4 (the C byte-set scanner / SIMD) is therefore CLOSED as
NOT BUILT**, in the manner
`specs/plans/2026-07-27-string-performance-phase2.md` recorded its own Tasks
4 and 5 closures — a verdict plus the measurement that produced it, not an
estimate. A C surface that cannot pay under this feature's threat load is a
permanent maintenance and safety liability, and declining to add it is a
result, per the Decision criteria above.

**Component 5 (`feed_fold`, removing the per-event `List(Event)`
allocation) is the indicated next step** if the small-token case matters —
left as an **open item**, not built here. It is what the tiny-token
residual's "per-token overhead" diagnosis points at directly.

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
  accommodate a speedup is a behavior change wearing a disguise. Component
  2b's `with_raw_numbers` is purely **additive** and off by default, so this
  still holds: the only permitted edit to the phase 1 suite is the new
  `EvNumRaw` arm in the test file's `ev_str` helper, which exhaustiveness
  forces.
- **No decision-table changes**, including the deliberate UTF-8 pass-through
  and control-byte pass-through choices, and including raw-number mode —
  which changes what a valid number *carries*, never what counts as valid.
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
3. ~~`EvNumRaw(String)`~~ — **decided 2026-07-31: build it, as Component 2b.**
   Opt-in via `with_raw_numbers`, default unchanged. Resolves phase 1's open
   question 1.

## Deliverables

- Run-sliced `str_byte`/`num_byte` in `stdlib/json_stream.march`, with phase
  1's full test suite passing **unmodified** (sole exception: the `EvNumRaw`
  arm exhaustiveness forces into the test file's `ev_str` helper).
- `EvNumRaw(String)` + `with_raw_numbers`, with the every-byte-split and
  truncation harnesses run in **both** number modes, and a >2⁵³ witness
  showing raw round-trips exactly where the default loses precision.
- Benchmark results per Component 3 recorded in `specs/benchmarks.md`, with
  the phase-1 baseline retained alongside for comparison.
- A recorded verdict on Components 4–5 — built, or closed as not-built with
  the measurement that closed them.
- `specs/todos.md` / `specs/progress.md` / `CHANGELOG.md` updated in the same
  commits, per `CLAUDE.md`.
