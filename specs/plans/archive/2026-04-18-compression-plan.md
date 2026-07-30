# Compression — gzip, zstd, brotli, deflate

**Status:** Planning
**Date:** 2026-04-18

## Motivation

Compression is needed at every layer:

- **HTTP responses**: `Content-Encoding: gzip` / `br` — without this, web apps
  send 3–10× more bytes than necessary. The HTTP server currently has no
  middleware for this.
- **File I/O**: reading/writing `.gz` files is routine in data pipelines,
  log archival, and data exchange.
- **Log rotation**: compressed log files are the standard.
- **Build artifacts**: forge packages are archives; compression is implicit.
- **Data pipelines**: zstd is the modern default for bulk data (Kafka, Parquet,
  databases).

The HTTP server adding gzip middleware is the single change that would help the
most users immediately.

---

## Module design

### `stdlib/compress.march`

One top-level module with sub-modules per algorithm. This avoids polluting the
top-level namespace and lets users import only what they need.

```march
mod Compress do

  type Error =
      InvalidInput(String)
    | InsufficientOutput
    | Io(String)

  -- ── Gzip ────────────────────────────────────────────────────────────────

  mod Gzip do
    type Level = BestSpeed | Default | BestCompression | Level(Int)  -- 1–9

    fn encode(data : Bytes) : Result(Bytes, Compress.Error)
    fn encode_level(data : Bytes, level : Level) : Result(Bytes, Compress.Error)
    fn decode(data : Bytes) : Result(Bytes, Compress.Error)

    -- Streaming (integrates with Seq)
    fn encode_stream(input : Seq(Bytes)) : Seq(Bytes)
    fn decode_stream(input : Seq(Bytes)) : Seq(Bytes)
  end

  -- ── Zstd ────────────────────────────────────────────────────────────────

  mod Zstd do
    type Level = Fast(Int) | Default | Best

    fn encode(data : Bytes) : Result(Bytes, Compress.Error)
    fn encode_level(data : Bytes, level : Level) : Result(Bytes, Compress.Error)
    fn decode(data : Bytes) : Result(Bytes, Compress.Error)

    fn encode_stream(input : Seq(Bytes)) : Seq(Bytes)
    fn decode_stream(input : Seq(Bytes)) : Seq(Bytes)
  end

  -- ── Deflate (raw, no header) ─────────────────────────────────────────────

  mod Deflate do
    fn encode(data : Bytes) : Result(Bytes, Compress.Error)
    fn decode(data : Bytes) : Result(Bytes, Compress.Error)
  end

  -- ── Brotli ───────────────────────────────────────────────────────────────

  mod Brotli do
    type Mode = Generic | Text | Font
    type Level = Level(Int)  -- 0–11

    fn encode(data : Bytes) : Result(Bytes, Compress.Error)
    fn encode_mode(data : Bytes, mode : Mode, level : Level) : Result(Bytes, Compress.Error)
    fn decode(data : Bytes) : Result(Bytes, Compress.Error)
  end

end
```

---

## HTTP server middleware

The most user-visible payoff. Add a single `Compress.gzip_middleware` that can
be composed into the Bastion / `http_server` pipeline:

```march
-- stdlib/compress.march (continued)

-- HTTP-level helpers live here, not in Bastion, so non-Bastion servers
-- can use them too.
fn gzip_response(resp : HttpResponse, min_size : Int) : HttpResponse
  -- If resp body is >= min_size bytes, gzip it and set Content-Encoding.

fn accept_encoding(req : HttpRequest) : List(String)
  -- Parse the Accept-Encoding header into a list of tokens.

fn best_encoding(req : HttpRequest) : Option(String)
  -- Return "zstd" | "br" | "gzip" | None based on Accept-Encoding + availability.
```

Usage in a server handler:
```march
fn my_handler(req : HttpRequest) : HttpResponse
  let body = render_page(req)
  let resp = Http.ok(body)
  Compress.gzip_response(resp, 1024)  -- compress if >= 1 KB
end
```

---

## Implementation

All four algorithms need C FFI — a pure March implementation of zlib or zstd is
not practical. The plan is thin shims over established C libraries:

| Algorithm | C library | Availability | License |
|-----------|-----------|--------------|---------|
| Gzip / Deflate | `zlib` | Ubiquitous (macOS, every Linux) | zlib/libpng |
| Zstd | `libzstd` | Standard on modern Linux; Homebrew on macOS | BSD |
| Brotli | `libbrotli` | Optional (Homebrew; apt `libbrotli-dev`) | MIT |

### C shim (`runtime/march_compress.c`)

Each algorithm gets a pair of functions:
- `march_gzip_encode(buf, len, level, out_buf, out_len)` → `int` (0=ok, -1=err)
- `march_gzip_decode(buf, len, out_buf, out_len)` → `int`

For streaming: a context struct with `march_gzip_stream_begin`, `_feed`, `_flush`,
`_end`. The March `Seq(Bytes)` streaming wrappers poll these.

### Dune integration

```dune
(library
  (name march_runtime)
  (c_names march_runtime march_compress ...)
  (c_library_flags (-lz -lzstd))  ; brotli optional via feature flag
)
```

### Availability fallback

If a library is absent at link time, the corresponding `Compress.Zstd` /
`Compress.Brotli` sub-module is omitted. The type checker reports a clear error:
`Compress.Zstd is not available — install libzstd and rebuild`.

This is better than a runtime `Err` because users discover the gap at compile
time.

---

## Seq streaming design

Streaming compression/decompression maps cleanly onto `Seq(Bytes)` (the existing
church-encoded fold):

```march
-- Internal: feed chunks through a zlib z_stream.
-- Each input chunk may produce 0..N output chunks.
pfn gzip_encode_fold(state : ZlibState, chunk : Bytes, k : Bytes -> Unit) : ZlibState
  ...

fn encode_stream(input : Seq(Bytes)) : Seq(Bytes)
  Seq.flat_map(input, fn chunk ->
    let (compressed, _state) = zlib_feed(chunk)
    Seq.from_list(compressed))
end
```

This is sufficient for log compression and HTTP streaming. True backpressure
(blocking when the consumer is slow) requires the `Flow` module and is deferred.

---

## Implementation order

1. **Gzip encode/decode** (one-shot, zlib) — unblocks HTTP compression
2. **HTTP gzip middleware** — depends on (1); immediate user payoff
3. **Deflate** — trivial once zlib shim exists
4. **Gzip streaming** — needed for large file processing
5. **Zstd** — second library; higher priority than Brotli for data pipelines
6. **Brotli** — optional, web-facing, lower priority

## Out of scope

- `tar` / `zip` archive formats (separate plan; compression is a prerequisite)
- LZ4, Snappy (nice to have; can live in external packages)
- Hardware-accelerated compression (ISA-L etc.)
- Streaming backpressure (deferred to Flow module redesign)
