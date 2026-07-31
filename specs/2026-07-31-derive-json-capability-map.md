# `derive Json` capability map (Task 1)

Discovery + wiring proof for the typed JSON decoding plan
(`specs/2026-07-31-json-typed-decoding-design.md`). Produced by probing
the existing `derive Json` generator (`lib/desugar/desugar.ml` ~1479-1730)
against `test/stdlib/test_json_typed.march` plus a set of standalone
scratch repros (not committed; commands and output are inlined below so
they can be reproduced).

## Headline finding: cross-type shadowing (single most important result)

**`derive Json for T` binds one bare `from_json`/`to_json` pair per
module. Every subsequent `derive Json for U` in the same module rebinds
those same bare names, silently discarding the previous type's
decoder/encoder.** There is no per-type dispatch on the bare call —
`from_json`/`to_json` resolve dynamically to whichever type derived Json
*last* in declaration order, regardless of which type the call site
actually intends.

Repro (`test_derive_json_multi.march`, already committed to the repo
(`git log` shows it landed in commit `6486a275`) but never registered in
`test/test_stdlib_march.ml` — this pre-existing file already demonstrates
the bug, it was just never wired into the alcotest suite, so nothing
currently catches it):

```bash
./_build/default/bin/main.exe test/stdlib/test_derive_json_multi.march
```
```
Point: {"x":42,"y":99}
Color: {"tag":"Green"}
Shape: {"tag":"Circle","0":5}
Point error: invalid JSON for Shape
Color error: invalid JSON for Shape
Shape roundtrip: Circle(5)
```
`Point` and `Color` derived Json earlier than `Shape`; both their
`from_json` calls resolve to `Shape`'s decoder and fail. Reordering
(`Shape` declared first, `Point` last) flips which one fails — it is
strictly last-declared-wins, independent of record vs. variant kind
(confirmed with a minimal 2-type repro).

**Consequence for nested records is worse than a wrong-type error — it's
an uncatchable panic.** `type Inner = { id : Int }` (`derive Json`) then
`type Outer = { label : String, inner : Inner }` (`derive Json`), with
*no other type* deriving Json in the module:

```bash
# repro (not committed): Inner + Outer only, from_json on a valid Outer literal
./_build/default/bin/main.exe /tmp/probe_nested_only.march
```
```
panic: invalid JSON for Outer

Stack trace (most recent call first):
  [0] from_json()   .../probe_nested_only.march:9
```
Root cause: the generated field decoder for a non-primitive field type
(`lib/desugar/desugar.ml:1599-1610` and the variant-arg equivalent at
1661-1676) is
```
match from_json(raw) do
  Ok(v) -> v
  Err(e) -> panic(e)
end
```
Because bare `from_json` always resolves to the most-recently-derived
type, `Outer`'s own recursive decode of its `inner : Inner` field calls
**`Outer`'s own** `from_json` (not `Inner`'s) on `{"id":7}`. That
correctly returns `Err("invalid JSON for Outer")` (shape mismatch) — and
the wrapping match unconditionally promotes that `Err` to a `panic`,
which is not catchable from March code. **Any record containing a field
whose type is itself a `derive Json`-derived record will panic on decode
if reached through the normal recursive path** — this reproduces with
the minimal two-type case, so it is not an artifact of the multi-type
shadowing above (though shadowing also affects it: if a later type is
declared, the earlier-declared nested type's decode instead silently
targets the later type's decoder, occasionally *masking* the panic with
a wrong-but-graceful `Err`, which is arguably worse).

This — not `Option`/`List`/type-parameters — is the finding that most
directly reshapes what Phase B must do: **it must give every derived
`from_json`/`to_json` a name (or dispatch mechanism) that does not
collide across types in the same module**, and it must fix the
nested-record recursive-decode path so a genuinely nested field resolves
to its own type's decoder rather than the enclosing type's.

Because a live, registered probe of this exact bug would either panic
and take down the whole alcotest test case (if the nested type is last
declared) or silently target the wrong type (if anything is declared
after it) — neither a trustworthy, isolated demonstration —
`test/stdlib/test_json_typed.march` does not exercise it as a live `test`
block; it is documented here from the standalone repro above, and the
committed test file explains the reasoning in a comment at the point
where `Inner`/`Outer` would otherwise appear.

## Capability table

| Capability | Result | Observed message / behavior |
|---|---|---|
| Flat record round-trip | **works** | `Ok(r)` with correct fields |
| Nested record (record field of another derive-Json record) | **fails — panic** | `panic: invalid JSON for Outer` (uncatchable); see above |
| Enum (no-arg variants) | **works** | `Ok(Red)` etc. |
| Variant with args | **works** | `Ok(Rect(3,4))` etc., positional keys `"0"`, `"1"`, ... |
| `Option(T)` field | **unsupported (runtime crash)** | compiles; `to_json`/`from_json` crash: `field access on non-record value` — self-recursion, see below |
| `List(T)` field | **unsupported (runtime crash)** | same as `Option(T)` |
| Type parameter (`type Box(a) = { value : a }`) | **unsupported (runtime crash)** | same as `Option(T)` |
| Multiple types deriving Json in one module | **fails — cross-type shadowing** | last-declared type's `from_json`/`to_json` silently wins for every bare call in the module; see headline finding |
| Missing field | **error, not a crash** | `invalid JSON for Flat` (generic — does not name the missing field) |
| Wrong field type | **error, not a crash** | `invalid JSON for Flat` (same generic message as missing-field; the two are indistinguishable from the message alone) |
| Unknown extra field | **ignored (accepted)** | decode succeeds silently; matches Decision 2 in the design doc, so no fix needed for that decision, but the current behavior is coincidental (see below) |
| Duplicate key | **first occurrence wins, accepted** | `{"name":"a","name":"b",...}` decodes with `name = "a"` (`Json.parse` keeps first-seen association-list entry; `Json.get` returns the first match) |
| `JsonStream.each_value` + `from_json` wiring | **works, for the happy path** | NDJSON file → 3 typed records via `each_value(path, cb)`, `cb` calling `from_json` per value |
| `JsonStream` syntax-level malformed input | **surfaces as a stream-level `Err`** | e.g. unclosed object: `"expected ',' or '}' in object at byte 17"` — this is JsonStream's own tokenizer error, unrelated to `derive Json` |
| Wrong-typed field *inside* an otherwise well-formed NDJSON record | **swallowed — ergonomics gap** | `each_value`'s callback return value is discarded by `nd_events` (`stdlib/json_stream.march:791-797`); a `from_json` `Err` inside the callback has no path back to the stream-level `Result`. `each_value` reports `Ok(())` for the whole file even though one record failed to decode — the callback's own side effect (e.g. `IO.puts`) is the only record of the failure |

### Why "unknown extra field is ignored" is coincidental, not designed

`decoder_pat_for_ty`/the record decode body only ever reads the fields it
was told to expect via `Json.get(v, "<field name>")` — it never inspects
the full key set of the incoming object, so an extra key is never
*looked at*, let alone rejected. There is no ignore-list or validation
step; "ignored" is simply what happens when nothing consults the extra
data. Decision 2 in the design doc wants exactly this behavior kept, so
no behavior change is needed here — but Phase B should make it an
intentional, tested guarantee rather than an accident of how the decoder
happens to be structured, since a future change to record decoding could
regress it silently.

## Reproduction commands used

```bash
dune build --root . bin/main.exe

# Registered suite (this task's committed file)
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march

# Pre-existing, unregistered file that already demonstrates cross-type shadowing
./_build/default/bin/main.exe test/stdlib/test_derive_json_multi.march

# Alcotest registration (test/test_stdlib_march.ml)
dune build --root . test/run_stdlib.exe
./_build/default/test/run_stdlib.exe -e
```

Standalone scratch repros used to isolate each finding (Option/List/type
parameter compile-then-crash; nested-record panic in a minimal 2-type
module; declaration-order sensitivity of the shadowing bug) were written
under the session scratchpad and are not part of this commit; their
exact source and output are quoted inline above and in
`.superpowers/sdd/2026-07-31-json-typed-decoding/task-1-report.md`.

## What Phase B must therefore handle

1. **Fix (or design around) cross-type shadowing.** This is the
   blocking issue: any real application deriving Json for more than one
   type in a module is currently broken for every type except the
   last-declared one. Phase B's typed-decoding mechanism cannot be layered
   on top of bare `from_json`/`to_json` calls as they exist today; it
   needs a name or dispatch scheme keyed by type (the existing
   `JsonTo`/`JsonFrom` pseudo-interfaces already do per-type impl-table
   entries for variants per the desugar.ml comment — Phase B should
   route ALL calls, including the generated nested-field recursive calls,
   through that dispatch rather than through a bare, overwritable name).
2. **Fix the nested-record panic.** A record containing a field of
   another derive-Json type must decode via *that field's own* decoder,
   not recurse into the enclosing type's decoder, and a shape mismatch on
   a nested field must produce a `Err` that propagates as a `Result`, not
   an uncatchable `panic`.
3. **Decide on `Option(T)` / `List(T)` / type-parameter support.**
   Currently these compile (silently, since the derive generator has no
   type-shape check) but crash at runtime the moment they're used. Phase
   B either needs first-class encoders/decoders for `Option` and `List`
   (almost certainly required — these are extremely common field types)
   or the derive generator needs to reject them at compile time with a
   clear diagnostic instead of silently generating code that crashes at
   first use.
4. **Give missing-field and wrong-type errors distinguishable messages.**
   Both currently collapse to the same generic `invalid JSON for <Type>`;
   a typed-decoding feature that reports errors for humans (or for
   programmatic retry/validation UIs) should at minimum say which field
   and why.
5. **Preserve the "ignore unknown fields" and "first-key-wins on
   duplicates" behaviors deliberately**, with tests, rather than relying
   on them falling out of how the decoder happens to be structured today.
6. **Address the `JsonStream.each_value` callback ergonomics gap.** A
   `from_json` failure inside the callback is currently invisible to the
   caller of `each_value` — the stream reports success regardless. Any
   "NDJSON file → typed records" convenience API this plan adds should
   either (a) let the callback signal failure back into the stream's
   `Result`, or (b) provide a higher-level combinator (e.g. an
   `each_typed(path, fn v -> Result(T, String))`) that does this properly
   instead of asking every caller to reinvent it.
