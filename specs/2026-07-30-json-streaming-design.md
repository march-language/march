# Streaming JSON — Phase 1: Total, Resumable, Constant-Memory

**Status:** phase 1 implemented (2026-07-31) — tokenizer (`stdlib/json_stream.march`),
totality/truncation/differential test harnesses, drivers (`fold`/`build`/`each_value`),
and the `bench/json_stream.march` baseline are all done; compiled parity confirmed
(including a surrogate-pair round-trip). Component 4 (typed decoding, below) is
deferred — it was scoped as separable from the start and nothing in Components 1–3
depends on it. Phase 2 (SIMD structural scanning) is not started; see the open item
in `specs/todos.md`. No decision-table deviations were found during implementation.
**Date:** 2026-07-30
**Scope:** phase 1 of two. This phase builds the safety skeleton — a pure-March
resumable tokenizer plus its consumers — and proves totality and constant
memory. Phase 2 (SIMD structural scanning) gets its own spec, written after
phase 1's benchmark reports, and slots in *behind* the interface defined here
without changing it.

---

## Goal

Parse JSON inputs too large to hold in memory — multi-GB files, NDJSON logs,
chunked HTTP bodies — with three properties, in priority order:

1. **Totality.** No input, however malformed, truncated, or adversarial,
   causes a panic, crash, stack overflow, or OOM. Every failure is an `Err`
   with a byte offset. This is the property phase 1 exists to establish;
   speed explicitly ranks below it.
2. **Constant memory.** RSS is bounded by
   `chunk size + one partial token + context stack + undelivered events`,
   independent of document size. The partial token and context stack are
   themselves bounded by explicit, caller-configurable limits.
3. **Type safety at the edge.** Callers land in `Result(T, Error)` for their
   own `T`, not in a dynamically-shaped tree they must pattern-match
   defensively at every use site. (The decoder layer, Component 4, delivers
   this; the tokenizer delivers 1 and 2.)

What already exists and is *not* rebuilt: chunked delivery. `HttpClient.stream_get`
(chunk callbacks over the wire), `File.with_chunks` (bounded-buffer file
reads), and `Compress.*`'s streaming `Seq(Bytes)` variants are the input
sources this parser is designed to sit behind. `Json.parse`
(`stdlib/json.march`) remains the whole-document API for small payloads.

## Why a resumable state machine, not recursive descent

The existing `Json.parse` is a recursive-descent parser over a complete
string. Extending it to streaming fails on three counts, each a safety
property, not a performance one:

- **Truncation becomes a normal state, not an error.** A chunked source can
  split the input anywhere: mid-escape (`\` at a chunk's last byte), between
  `\u` surrogate halves, mid-number, mid-`true`. A recursive parser encodes
  "incomplete" as an error path at every buffer-end check — dozens of sites,
  each individually writable wrong. A state machine encodes each suspension
  point as a `State` constructor, and the compiler's exhaustiveness checking
  verifies every one is handled. Truncation handling becomes structural.
- **Depth is data, and data is hostile.** `[[[[…` a million deep runs
  recursive descent off the green-thread stack; the guard page turns that
  into exactly the crash this spec exists to exclude. The state machine keeps
  nesting context in an explicit heap list, bounded by `max_depth`, exceeded
  → `Err(EDepthLimit(off))`.
- **Suspend/resume is the API.** `feed` must return to its caller between
  chunks. Recursive descent would need its whole call stack reified to
  suspend; the state machine's "call stack" is already a value.

## The C/March boundary rule

Everything phase 2 will add for speed moves work toward C, and C over
untrusted input is where "no crash on malformed data" is hardest. So the
contract is fixed now, while there is no C in the parser at all:

> **C primitives are stateless, bounds-checked scanners. All structure lives
> in March.** A C helper may answer "where is the next byte from this set in
> `[lo, hi)`", "is `[lo, hi)` valid UTF-8", "classify these bytes" — taking
> explicit lengths, returning offsets/booleans, never interpreting quoting,
> escapes, or nesting. `march_memmem` (`runtime/march_runtime.c`) is the
> existing proof of the pattern: length-counted, no NUL assumptions, no
> state, nothing to get wrong about malformed input because it assigns no
> meaning to the bytes.

Phase 1 has **zero new C**. The tokenizer is pure March, so the totality
argument rests entirely on March's type system plus the checks below, and
phase 2's scanners can be differentially tested against a known-total
reference.

---

## Component 1 — The tokenizer (`stdlib/json_stream.march`)

New module `JsonStream`, one top-level `mod` per the file convention.
Declared `cap no_panic`: today that capability's enforcement is
division-safety (Z3-checked, `lib/refinecheck/division_safety.ml`), so it is
a gate rather than a full totality proof — but it is a *machine-checked*
gate, it will catch a careless `%`/`/` in offset arithmetic, and the module
is positioned to benefit as the capability's scope grows.

### Events

```march
type Event =
    EvObjStart
  | EvObjEnd
  | EvArrStart
  | EvArrEnd
  | EvKey(String)
  | EvStr(String)
  | EvNum(Float)
  | EvBool(Bool)
  | EvNull
```

Constructor names are deliberately prefixed: `Json.JsonValue` already claims
`Null | Bool | Number | Str | Array | Object`, the constructor namespace is
flat (the FQN overhaul, `specs/plans/2026-07-17-fqn-type-ctor-identity.md`,
is still open), and same-named constructors at different tags have a
documented compiled-only miscompile history. Do not "clean up" these names
until FQN identity lands.

`EvNum` carries `Float` to match `Json.parse`'s existing behavior exactly —
the differential test in Component 5 depends on that. Integer-precision loss
above 2^53 is a real limitation shared with the existing parser; an
`EvNumRaw(String)` lexeme-preserving variant is listed under open questions,
not silently included.

### Errors

```march
type Error =
    EMalformed(String, Int)   -- what was wrong, absolute byte offset
  | EDepthLimit(Int)
  | ETokenLimit(Int)
  | ETruncated(Int)           -- only ever produced by finish()
```

Offsets are absolute across all chunks fed so far, so an error in gigabyte 3
is locatable without re-reading gigabytes 1–2.

### API

```march
ptype State = ...            -- opaque; constructors private

type Limits = Limits(Int, Int)   -- max_depth, max_token_bytes

fn default_limits() : Limits     -- Limits(512, 8_000_000)

fn start() : State
fn start_with(limits : Limits) : State
-- ("start", not "init": `init` is a reserved word in March's parser)

fn feed(st : State, chunk : String) : Result((List(Event), State), Error)
fn finish(st : State) : Result(List(Event), Error)
```

`finish` returns events, not `Unit`: a top-level number only ends at a
delimiter or EOF, so for input `"42"` the `EvNum` cannot be emitted by any
`feed` — it completes inside `finish`. (Caught during implementation
planning; the original draft's `Result(Unit, Error)` silently lost that
event.)

Semantics:

- `feed` consumes the whole chunk, emits every event that *completed* within
  it, and returns the successor state holding any partial token and the
  nesting context. A chunk may complete zero events (e.g. the middle of a
  long string) — that is `Ok(([], st'))`, not an error.
- A malformed byte fails fast: `Err(EMalformed(..))` at the offending offset.
  The tokenizer validates as it goes; it never buffers past an error to
  "see if it gets better."
- **Errors are final.** On `Err`, `feed` returns no successor state, so there
  is no "poisoned state" to misuse: the caller still holds the pre-error
  state, and feeding it again is deterministic (same state + same chunk →
  same error). Total, idempotent, nothing undefined to document around.
- `finish` on a state with an open string/object/array/number-in-progress
  returns `Err(ETruncated(off))` — except a pending top-level *number*, which
  is completed and returned (see the `finish` signature note above). On a
  state that consumed exactly one complete top-level value (or, in NDJSON
  mode below, any number of them), `Ok(remaining_events)`.
- The top level accepts one JSON value, matching `Json.parse` (including its
  "trailing garbage is an error" rule). A separate entry point
  `start_ndjson()` accepts whitespace-separated concatenated values, since NDJSON
  is the dominant large-file shape and treating it as a mode of the tokenizer
  is simpler and safer than making every caller split lines first.

### Malformed-data decision table

Committed now so implementation doesn't improvise:

| Input condition | Behavior |
|---|---|
| Truncated anywhere (EOF mid-token, mid-value, mid-escape) | `feed` holds state; `finish` → `ETruncated` |
| Unknown escape, bad `\u`, lone surrogate | `EMalformed` at the escape's offset. (An earlier draft noted `Json.parse` rejected all `\uXXXX`; that gap was fixed on main 2026-07-30 — including surrogate-pair handling — so verdict-differential corpora now include `\u` documents.) |
| Leading zeros, `1.`, `.5`, `1e`, `-` alone | `EMalformed` (same rules as `Json.parse`) |
| Nesting deeper than `max_depth` | `EDepthLimit` at the opening bracket |
| Single token (string/number) longer than `max_token_bytes` | `ETokenLimit` — bounds the partial-token buffer, hence RSS |
| Invalid UTF-8 in string content | **Passed through as bytes**, phase 1. March strings are byte strings and `Json.parse` does not validate either. Escape sequences are always validated (they are structural). SIMD UTF-8 validation is a phase 2 option behind the same interface, off by default for compatibility. |
| Raw control bytes (< 0x20) inside strings | **Passed through**, matching `Json.parse` (which does not reject them). Strict-RFC rejection would be a behavior divergence; deferred with the UTF-8 question. |
| Embedded NUL | Ordinary data (length-counted strings) |
| `true`/`false`/`null` split across chunks | Held as partial token, resumed |
| Duplicate object keys | Passed through (tokenizer has no object semantics; the decoder layer or tree builder decides) |

### Memory accounting

Per the goal statement, live memory is: the caller's chunk (caller-owned,
freed when the caller drops it — Perceus frees it as soon as `feed` returns
and the caller moves on), the partial-token buffer (≤ `max_token_bytes`),
the context stack (≤ `max_depth` cons cells), and the returned event list
(bounded by events completed in one chunk, itself bounded by chunk size).
No component grows with document size. This paragraph is the claim the
Component 5 RSS test verifies.

## Component 2 — Drivers

Thin, and mostly demonstrations that the sources already compose:

```march
-- Fold events from any chunk sequence (file, HTTP, decompressor):
fn fold(chunks : Seq(String), z : b, f : (b, Event) -> b) : Result(b, Error)

-- Convenience: NDJSON records from a file path, one JsonValue per line-value
fn each_value(path : String, cb : JsonValue -> Unit) : Result(Unit, Error)
```

`fold` is the composition point: `File.with_chunks` for files,
`HttpClient.stream_get`'s callback adapted to a `Seq`, and
`Compress.Gzip`/`Zstd` streaming decode for compressed inputs all produce
chunk sequences. A gzipped NDJSON pull over HTTP is
`stream_get → Gzip stream-decode → JsonStream.fold` with every stage
bounded-memory and every stage returning `Result`.

## Component 3 — Tree building (compatibility)

```march
fn build(chunks : Seq(String)) : Result(JsonValue, Error)
```

(Typed `Error`, not `Json.parse`'s `String` — an `err_to_string` helper
covers callers who want the string.)

Folds events into the existing `Json.JsonValue`. Exists for two reasons:
it is the differential-testing bridge to `Json.parse` (Component 5), and it
gives streaming-input callers the familiar tree when the document is known
small. It inherits the tree's memory cost by construction, and its doc
comment says so. Reimplementing `Json.parse` itself on top of the tokenizer
is a possible later convergence, explicitly not part of phase 1.

## Component 4 — Typed decoding (sketch, separable)

The type-safety payoff: a decoder-combinator layer (Elm/serde-shaped) so the
dynamic-to-typed translation happens once, totally, centrally:

```march
-- Decoder(a) : JsonValue -> Result(a, DecodeError), composable
Decode.field("id", Decode.int)
Decode.map2(mk_user, Decode.field("id", Decode.int),
                     Decode.field("name", Decode.string))
```

For streaming, the decoder attaches **per record** — each NDJSON value, each
element of a top-level array — so records are typed and released one at a
time: `stream → Seq(Result(T, DecodeError))`. Full combinator API design
(record helpers, `one_of`, recursive decoders, error paths that name the
JSON pointer) is its own piece of work; phase 1 commits only to the
attachment point (per-record `JsonValue`, via Component 3's folder applied
per record) and ships `Decode` as a follow-on inside the phase if time
allows. Nothing in Components 1–3 depends on it.

## Component 5 — Verification

Totality claims get tests, not arguments:

- **Every-byte-split differential** (the load-bearing test): for each corpus
  document, for every split point `0..len`, feed the two pieces and assert
  the event stream is byte-identical to the one-shot feed. Exhaustively
  exercises every suspension point for ~free. Corpus: the existing
  `Json.parse` doctests' inputs plus escapes, surrogates, long numbers,
  `true/false/null`, nested structures, and NDJSON samples. Registered
  `` `Slow `` if it exceeds the quick budget.
- **Truncation sweep**: for each corpus document, every strict prefix must
  end in `feed`-ok + `finish` → `ETruncated`, or a well-formed shorter value
  where the prefix happens to be one (NDJSON). Never a crash; asserted under
  the interpreter and compiled.
- **Differential vs `Json.parse`**: `build(chunks_of(s)) == Json.parse(s)`
  over the corpus, including the error/ok verdict (offsets/messages may
  differ; the verdict may not).
- **Adversarial**: depth bomb (10⁶ open brackets → `EDepthLimit`, flat RSS),
  token bomb (single huge string → `ETokenLimit`), sticky-error re-feed,
  chunk sizes 1 byte and 16MB.
- **Memory ceiling**: compiled, feed a generated multi-GB-equivalent NDJSON
  stream (generator, not a checked-in file) and assert `march_live_allocs`
  returns to baseline between records and peak RSS stays under a stated
  bound. This is the constant-memory claim made falsifiable.
- **Parity**: interpreted vs compiled event streams identical over the
  corpus (the differential-oracle lesson: compute-heavy paths are exactly
  where compiled-only bugs hide).
- **Benchmark**: `bench/json_stream.march` — NDJSON records/sec and one
  large-document event throughput, with an entry in `specs/benchmarks.md`.
  Phase 1 sets the baseline phase 2 must beat; no speed target is set here.

## Non-goals for phase 1

- **No SIMD, no new C.** Phase 2, own spec, same interface.
- **No CSV work.** `Csv.each_row` exists; its zero-copy row variant is a
  separate effort.
- **No string views / mmap.** The copy-per-string-event cost is real and is
  precisely what phase 2 + the string-view investigation address; phase 1
  accepts it to get the safety skeleton stood up.
- **No `Json.parse` replacement.** It stays as-is for small payloads.
- **No schema validation.** The decoder layer types values; validating
  against a JSON Schema document is out of scope entirely.

## Risks

- **Pure-March tokenizer speed.** A byte-at-a-time March loop will be slow —
  possibly slower than `Json.parse` on in-memory inputs. Accepted: phase 1's
  deliverable is the interface and its totality proof; the benchmark exists
  to quantify exactly this for phase 2. The risk to watch is the interface
  accidentally *forbidding* fast implementation (e.g. an event granularity
  that forces per-byte allocation); the every-byte-split test doubles as a
  check that event boundaries don't depend on chunk boundaries, which is the
  property phase 2's block-scanning needs.
- **Event-list allocation churn.** `feed` returning `List(Event)` allocates
  per event. If the benchmark shows this dominating, a fold-callback variant
  of `feed` (no intermediate list) is API-compatible to add; not committed
  now.
- **`cap no_panic` scope.** The capability checks division today, not
  indexing or matching. The totality argument therefore rests mainly on
  structure (total byte probes via `string_byte_at`'s negative sentinel,
  exhaustive matches, the decision table). Stated plainly so nobody mistakes
  the capability marker for a proof.
- **Ctor-namespace collisions.** Mitigated by prefixed names (`Ev*`, `E*`);
  see Component 1. New constructors added later must follow suit.

## Open questions

1. ~~`EvNumRaw(String)` for lossless large integers~~ — **RESOLVED
   2026-07-31: build it in phase 2, Component 2b**
   (`specs/2026-07-31-json-streaming-phase2-design.md`). Opt-in via
   `with_raw_numbers`; `EvNum(Float)` stays the default, so this spec's
   `Json.parse` differential and the whole phase 1 suite are unaffected.
   Phase 2's number run-slicing materializes the lexeme as a slice anyway,
   which turns preserving it into *skipping* `string_to_float` rather than
   extra work.
2. UTF-8 validation default once a fast validator exists — opt-in stays the
   phase 1 answer; revisit with phase 2 data.
3. Whether `Decode` ships inside phase 1 or immediately after — attachment
   point is fixed either way.

## Deliverables

- `stdlib/json_stream.march` (`JsonStream`, `cap no_panic`): `Event`,
  `Error`, `Limits`, `State`, `start`/`start_with`/`start_ndjson`, `feed`,
  `finish`, `fold`, `each_value`, `build`.
- Test suites per Component 5, in the stdlib test binary that actually runs
  them (note the two-exe split: `run_stdlib` vs `test_stdlib_march.exe`).
- `bench/json_stream.march` + `specs/benchmarks.md` entry.
- Doc updates in the same commits: `specs/todos.md`, `specs/progress.md`,
  `CHANGELOG.md` (Added), stdlib module count if the docs lint tracks it.
- A phase 2 spec seeded with phase 1's benchmark numbers.
