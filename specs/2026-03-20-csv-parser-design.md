# CSV Parser Design

**Date:** 2026-03-20
**Status:** Draft
**Depends on:** File I/O builtins (implemented), resource cleanup (`register_resource`, implemented)

## Goals

Build a fast, correct CSV parser into March's stdlib. Designed for the interpreter phase but structured so the API maps cleanly to a future SIMD/mmap native codegen path.

- **Copy-on-escape model** — fields are zero-cost views during scanning; copies happen only when a quoted field contains `""` escapes that need unescaping. In the interpreter phase this is implemented as eager `List(String)` per row. In the native phase, unquoted fields will be direct pointers into the mmap'd buffer.
- **Scoped resource lifecycle** — no `Seq`-based lazy API. File handles never escape the module. `each_row` (callback) and `read_all` (eager) are the two consumption modes. `register_resource` guarantees cleanup even on actor crash.
- **Two modes** — `Simple` (split on delimiter, no quoting) and `Rfc4180` (full RFC 4180 compliance: quoted fields, `""` escapes, embedded newlines, embedded delimiters).
- **Streaming by default** — `each_row` processes one row at a time with a 64KB read buffer. Memory usage is O(largest row), not O(file size).

## Non-Goals (v1)

- Writer/serializer — trivial to add later, not needed now
- Lazy `Seq`-based API — resource lifecycle too fragile without linear types
- Schema validation / typed columns — userland concern
- Parallel chunk parsing — native codegen phase
- SIMD scanning — native codegen phase
- mmap — native codegen phase

## Research Summary

Surveyed the fastest CSV parsers across ecosystems to extract implementation patterns:

| Parser | Language | Key technique | Throughput |
|--------|----------|--------------|------------|
| [Sep](https://github.com/nietras/Sep) | C# | SIMD separator scan, `ReadOnlySpan<char>` zero-copy fields | ~4 GB/s |
| [csvmonkey](https://github.com/dw/csvmonkey) | C++ | SIMD bitmask scan, mmap, offset-pair fields | ~3 GB/s |
| [zsv](https://github.com/nicholasgasior/zsv) | C | SIMD + streaming, configurable delimiters | ~2.5 GB/s |
| [xsv](https://github.com/BurntSushi/xsv) | Rust | DFA-based scanner, `&[u8]` borrows into buffer | ~1.5 GB/s |
| Polars CSV | Rust | Parallel chunk parsing, rayon, SIMD | ~2 GB/s (multi-core) |
| Python `csv` | Python | Byte-at-a-time C loop, copy per field | ~50 MB/s |

**Common patterns across all fast implementations:**

1. **Separate scan from materialize.** The hot loop identifies field boundaries (offset + length pairs). Actual string construction is deferred until the caller needs the value.
2. **SIMD for delimiter/quote/newline detection.** Load 32-64 bytes, compare against delimiter/quote/newline masks, use `ctz`/`popcnt` to find positions. Falls back to scalar for remainder.
3. **mmap instead of buffered I/O.** Eliminates read syscalls and double-buffering. The OS handles paging.
4. **Copy-on-escape, not copy-always.** Unquoted fields are zero-copy borrows. Only fields with `""` escapes require allocation (to remove the doubled quotes).
5. **Avoid per-field allocation.** Sep uses spans, csvmonkey uses offset pairs, xsv uses `&[u8]` slices. Allocation happens at the row level (array of spans) or not at all.

**Design decision: Option B (copy-on-escape) over Option A (Perceus borrow inference).**

Option A would have Perceus infer field lifetimes automatically — fields start as borrows into the read buffer, promoted to RC'd strings only when they escape. But borrow inference is fragile at API boundaries: the moment a field is stored in a list, passed to another function, or captured in a closure, the borrow breaks and you get RC traffic anyway. Option B makes the zero-copy path explicit and predictable, matching what Sep/csvmonkey/zsv all do.

## Architecture

### Layer 1: OCaml Builtins (`lib/eval/eval.ml`)

Three builtins form the low-level substrate:

```
csv_open(path, delimiter, mode)  → handle
csv_next_row(handle)             → List(String) | :eof
csv_close(handle)                → :ok
```

Internal state per handle:

```ocaml
type csv_reader = {
  ic: in_channel;
  buf: Buffer.t;        (* 64KB read buffer *)
  delimiter: char;
  mode: [`Simple | `Rfc4180];
  mutable eof: bool;
}
```

**Scanner design:**

- **Simple mode:** Scan for delimiter byte and newline byte. Split. No state machine needed.
- **RFC 4180 mode:** 4-state FSM:

```
         ┌──────────────────────┐
         │                      │
    FieldStart ──quote──► Quoted ──quote──► QuoteInQuoted
         │                  │                    │
      delim/NL           other                 quote → back to Quoted
         │                  │                  delim/NL → emit field
         ▼                  ▼                    │
     emit empty         accumulate               ▼
                                            emit field
         │
       other
         │
         ▼
      Unquoted ──delim/NL──► emit field
         │
       other → accumulate
```

States: `FieldStart`, `Unquoted`, `Quoted`, `QuoteInQuoted`.

- `FieldStart` + `"` → enter `Quoted`
- `FieldStart` + delimiter/newline → emit empty field
- `FieldStart` + other → enter `Unquoted`, accumulate
- `Unquoted` + delimiter/newline → emit field
- `Unquoted` + other → accumulate
- `Quoted` + `"` → enter `QuoteInQuoted`
- `Quoted` + other → accumulate (including newlines and delimiters)
- `QuoteInQuoted` + `"` → accumulate literal `"`, back to `Quoted` (this is the `""` escape)
- `QuoteInQuoted` + delimiter/newline → emit field
- `QuoteInQuoted` + EOF → emit field

**Buffer management:** Read 64KB chunks from `in_channel`. The scanner operates on the buffer, refilling when exhausted. Fields that span buffer boundaries are handled by accumulating into a `Buffer.t` — this is the slow path and only matters for fields larger than 64KB.

**Resource safety:** `csv_open` calls `register_resource` with the `csv_close` cleanup function. If the actor crashes or the handle is abandoned, the file descriptor is closed.

### Layer 2: March Module (`stdlib/csv.march`)

```march
mod Csv do
  type CsvError = ParseError(String) | FileError(String)
  type CsvMode = Simple | Rfc4180

  -- Primary streaming API: callback-based, guaranteed cleanup
  pub fn each_row(path, delimiter, mode, callback) : Result(:ok, CsvError) do
    let handle = csv_open(path, delimiter, mode)
    let result = loop(handle, callback)
    csv_close(handle)
    result
  end

  -- Convenience: materialize all rows (small files only)
  pub fn read_all(path, delimiter, mode) : Result(List(List(String)), CsvError) do
    let rows = []
    each_row(path, delimiter, mode, fn row -> rows = rows ++ [row] end)
    -- Note: actual impl will use acc pattern, not mutation
  end

  -- Header-aware: first row as header, callback receives (header, row)
  pub fn each_row_with_header(path, delimiter, mode, callback) : Result(:ok, CsvError) do
    let handle = csv_open(path, delimiter, mode)
    let header = csv_next_row(handle)
    let result = loop_with(handle, header, callback)
    csv_close(handle)
    result
  end

  -- 80% use case: comma-delimited, RFC 4180
  pub fn read_csv(path) : Result(List(List(String)), CsvError) do
    read_all(path, ",", Rfc4180)
  end
end
```

No `rows()` / `Seq` API. File handles never escape the module boundary.

### Error Handling

- `csv_open` on nonexistent file → `Error(FileError("..."))`, no handle created
- Unclosed quote at EOF → `Error(ParseError("unclosed quote at line N"))` — the handle is still closed via `register_resource`
- Malformed fields in Simple mode → impossible (everything is valid, just split on delimiter)
- IO errors during `csv_next_row` → `Error(FileError("..."))`, handle remains valid for `csv_close`

## Future Native Codegen Path

The API (`csv_open` / `csv_next_row` / `csv_close`) stays identical. The implementation behind the builtins changes:

| Component | Interpreter (now) | Native (future) |
|-----------|-------------------|------------------|
| I/O | `in_channel` + 64KB buffer | `mmap` — OS handles paging |
| Scanning | Byte-at-a-time OCaml loop | SIMD bitmask scan (32/64 bytes) |
| Field access | Copy into `List(String)` | Offset+length pairs into mmap buffer |
| Quote detection | 4-state FSM | XOR bitmask trick across chunks |
| Mode switch | `if mode = Simple` branch | Separate codegen paths, no branch in hot loop |

**SIMD dispatch (future):**

`csv_open` detects CPU features once and sets a function pointer:
- AVX-512 available → `csv_next_row_avx512`
- AVX2 available → `csv_next_row_avx2`
- fallback → `csv_next_row_scalar`

No per-row branch.

**Key constraint this imposes now:** The March-side API must not assume anything about field lifetimes beyond "valid during the current callback invocation in `each_row`". The interpreter copies into `List(String)` so this is invisible today. When we move to native zero-copy, fields will be borrows into the mmap'd page, invalidated on the next `csv_next_row` call.

## Implementation Plan

### Phase 1: OCaml Builtins

**Files:** `lib/eval/eval.ml`

1. Add `csv_reader` record type (in_channel, Buffer.t, delimiter, mode, eof flag)
2. Implement `csv_open` builtin — open file, create reader, register_resource
3. Implement `csv_next_row` builtin — Simple mode: split on delimiter/newline
4. Implement `csv_next_row` builtin — RFC 4180 mode: 4-state FSM
5. Implement `csv_close` builtin — close channel, deregister resource
6. Wire builtins into the eval dispatch table

### Phase 2: March Module

**Files:** `stdlib/csv.march` (new), `bin/main.ml` (add to stdlib load order)

1. Create `stdlib/csv.march` with `Csv` module
2. Implement `each_row` — open/loop/close with error handling
3. Implement `read_all` — accumulator pattern over `each_row`
4. Implement `each_row_with_header` — read first row, then loop
5. Implement `read_csv` — convenience wrapper
6. Add to stdlib load order in `bin/main.ml`

### Phase 3: Tests

**Files:** `test/test_march.ml`

| Test | Coverage |
|------|----------|
| Simple: unquoted row | Basic delimiter splitting |
| Simple: empty fields | `a,,b` → `["a", "", "b"]` |
| RFC 4180: quoted field with delimiter | `"hello, world"` → single field |
| RFC 4180: escaped quotes | `"say ""hi"""` → `say "hi"` |
| RFC 4180: embedded newlines | `"line1\nline2"` → single field |
| RFC 4180: mixed quoted/unquoted | `a,"b,c",d` → three fields |
| RFC 4180: unclosed quote | Error path |
| Large row (>64KB) | Buffer boundary crossing |
| Resource cleanup | `csv_close` called on error |
| `each_row` end-to-end | March-side callback test |
| `each_row_with_header` | Header separated from data rows |
| `read_csv` convenience | Comma + RFC 4180 defaults |

### Phase 4: Benchmark

**Files:** `bench/csv_parse.march` (new)

Generate a 100K-row CSV, parse it with `each_row`, report rows/sec. This establishes the interpreter-phase baseline and catches regressions when builtins change.

## Estimated Touch Points

| Action | File |
|--------|------|
| Modify | `lib/eval/eval.ml` |
| Modify | `bin/main.ml` |
| Modify | `test/test_march.ml` |
| Create | `stdlib/csv.march` |
| Create | `bench/csv_parse.march` |
