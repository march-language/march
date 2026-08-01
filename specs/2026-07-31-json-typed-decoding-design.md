# Typed JSON Decoding — design

**Status:** implemented (Tasks 1-7 complete; combinators remain an open,
unmotivated non-goal — see `specs/todos.md`)
**Date:** 2026-07-31
**Scope:** the "type safety at the edge" goal from
`specs/2026-07-30-json-streaming-design.md` (its Component 4), rescoped after
discovering that `derive Json` already exists.

---

## Goal

Let a caller turn JSON — including multi-GB NDJSON — into *their own* types,
with errors good enough to act on, without ever holding more than one record
in memory.

Concretely, the end state:

```march
JsonStream.each_typed(path, fn (u : User) -> ...)   -- Result(T, DecodeError) per record
```

where a failure names **which field of which record** failed, not just
"expected Int".

## What already exists, and why this spec is not the one phase 1 scoped

Phase 1's Component 4 scoped an Elm-style combinator library
(`Decode.field`/`Decode.list`/`Decode.map2`) built from scratch. **That was
written without accounting for `derive Json`, which already exists** and
covers most of the same ground:

- `derive Json for T` (`lib/desugar/desugar.ml:1479`) generates two standalone
  functions: `to_json(x : T) : JsonValue` and
  `from_json(v : JsonValue) : Result(T, String)`.
- It handles records, enums, and variants with arguments
  (`test/stdlib/test_derive_json.march`), recursing into nested derived types.

So a from-scratch combinator layer would duplicate working machinery. The real
gaps are narrower and sharper:

1. **Errors are a bare `String` with no path.** `from_json` returns
   `Result(T, String)`. A failure in record 40,000 of an NDJSON file reports
   `"expected Int"` and nothing else. JsonStream carries an *absolute byte
   offset* through every tokenizer error precisely so large-file failures are
   locatable — and the typed layer throws that away at the last step.
2. **Nothing connects `derive Json` to `JsonStream`.** `each_value(path, fn v -> from_json(v))`
   should work today, but it is untested, undocumented, and unproven — so the
   feature's headline use case has never been demonstrated end to end.
3. **Decoding requires a `JsonValue` tree.** `from_json` pattern-matches on
   `JsonValue` constructors, so every record is materialized as a tree before
   it becomes a `User`. For a 2GB single document with a huge top-level array,
   per-record is fine; for a single huge *object*, it is not.

Combinators remain genuinely useful for shapes derivation cannot express
(optional/defaulted fields, renamed keys, unions, cross-field validation) —
but nobody has yet shown a workload that needs them, so they are **out of
scope** here and stay open. Building them first would be solving the problem
we can most easily imagine rather than the one we measured.

## Decisions taken

Two forks were decided before this spec was written:

- **Scope**: wire the existing derivation to the stream and fix the error
  type, rather than build combinators.
- **Tree**: decode **straight from events**, not from a per-record
  `JsonValue`.

The second is the expensive one and deserves its cost stated plainly:
`from_json` consumes a tree by construction, so event-direct decoding cannot
reuse it. It requires generating a **second, event-consuming decoder per
type** in `desugar.ml` — compiler work, not stdlib work. That is why this
spec sequences it second rather than first.

## Sequencing, and why this order

Phase A is not a stepping stone that gets thrown away: it defines the error
type that Phase B also emits, and it produces the differential oracle that
makes Phase B verifiable.

### Phase A — connect it, and fix the errors

**A1. Prove the existing path end to end.** Tests and docs for
`derive Json` + `JsonStream`: an NDJSON file of records decoded to a user type
via `each_value` + `from_json`, including a malformed record. This is mostly
verification of a path we believe already works; if it does not, that is a
finding worth having before building anything on top.

**A2. Give decode errors a path.** Replace `from_json`'s bare `String` with a
structured error carrying a location:

```march
type DecodePath = PField(String) | PIndex(Int)      -- one step
type DecodeError = DecodeError(String, List(DecodePath))
```

rendered as `users[3].id: expected Int, found String`. The generated decoder
prepends a step as it descends into a field or element, so the path builds
itself without threading a cursor through user code.

This benefits **every** `derive Json` user, not only streaming callers — it is
the highest-leverage item in the spec and the one most independent of the
rest.

**Compatibility.** `from_json`'s error type changes, which is a breaking
change for anyone matching on the `String`. Options, to be decided during
implementation with the corpus in hand: change it outright (the derivation is
young and in-repo callers are countable), or keep `from_json` and add
`from_json_at`. Prefer changing it outright if the caller count is small —
two near-identical entry points is a worse permanent cost than one migration.

**A3. Attach byte offsets.** A per-record decode failure should be able to say
*which record*. `JsonStream` already knows the absolute byte offset of every
event; the record-level driver can carry the offset of the record's opening
event into the `DecodeError`. This is what makes a failure in gigabyte 3
actionable, and it is the thread's whole motivation.

### Phase B — decode straight from events

Generate a second derived function per type that consumes the `Event` stream
directly:

```march
from_json_events(events, st) : Result((T, State), DecodeError)
```

For a record, the generated decoder is a small state machine: expect
`EvObjStart`; on each `EvKey` dispatch to the matching field slot; on
`EvObjEnd` construct the value, erroring on missing required fields. A field
whose type is itself derived recurses into *its* generated decoder, driven by
the same event stream — which is what makes nesting work without a tree.

**Why this is real work, not a refactor:** `desugar.ml`'s derive codegen
currently emits `JsonValue`-pattern matches (`decoder_pat_for_ty`,
`lib/desugar/desugar.ml:1499`). An event-consuming decoder shares none of that
shape — it is generated control flow over a token stream, with its own
handling of field order (JSON objects are unordered, so slots must be filled
opportunistically), missing fields, duplicate keys, and unknown fields.

**Unknown-field policy must be explicit**, not accidental: skipping an unknown
field means skipping a whole *subtree* of events, which the generated code has
to do correctly (depth counting) or it desynchronizes the stream — a failure
mode with no analogue in the tree path, where an unknown key is simply never
read.

**The oracle.** Phase A's tree path becomes the differential reference:
for every corpus document, `from_json(build(doc))` and
`from_json_events(events(doc))` must agree — same value on success, same
verdict on failure. That is the same technique phase 1 used against
`Json.parse`, and it is what makes a generated state machine trustworthy.

## Non-goals

- **Combinators** (`Decode.field`/`map2`/`one_of`). Still open, still
  unmotivated by a demonstrated workload. Revisit with one.
- **Schema validation** beyond what the target type expresses.
- **Changing `JsonStream`'s tokenizer or its public API.** Phase 1 and 2's
  guarantees — totality, chunk-independence of event boundaries, `cap
  no_panic`, bounded memory — are hard constraints; the every-byte-split
  differential must keep passing untouched.
- **`to_json` changes.** Encoding is not in scope.

## Risks

- **Scope inversion.** Phase B is compiler work and is easy to start before
  Phase A's error type is settled — which would mean designing the error twice
  and generating it twice. A must precede B.
- **Desynchronization on unknown fields.** The single most likely way the
  generated event decoder goes wrong, and it fails *silently* (wrong value,
  no error) rather than loudly. The differential oracle is the only practical
  net; every corpus document should include unknown fields.
- **Breaking `from_json`'s error type** (see A2) — a real migration cost,
  taken deliberately rather than papered over with a duplicate entry point.
- **Derivation gaps surfacing late.** `derive Json`'s current coverage of
  generics, `Option`, and collections is not established by this spec. A1
  should map it and record what it finds, before B assumes it.

## Open questions

1. Does `derive Json` handle `Option(T)`, `List(T)`, and type parameters
   today? A1 answers this by test, and the answer scopes B.
2. Whether A2 replaces `from_json`'s error or adds `from_json_at` — decide
   from the in-repo caller count.
3. Whether the per-record driver should expose the record's byte offset in the
   public API or only inside `DecodeError`.

## Deliverables

- A1: tests + docs proving `derive Json` × `JsonStream` end to end, plus a
  written map of what `derive Json` actually supports.
- A2: `DecodeError` with paths, generated by the derivation; callers migrated.
- A3: record byte offsets in decode failures.
- B: `from_json_events` derivation, an explicit unknown-field policy, and the
  tree-vs-events differential oracle over a corpus that includes unknown
  fields, missing fields, and nesting.
- Docs per `CLAUDE.md` in the same commits (`specs/todos.md`,
  `specs/progress.md`, `CHANGELOG.md`).
