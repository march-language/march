# Array-backed `Bytes` — design

Status: implemented (phase 1). 2026-08-10.

## The problem

`stdlib/bytes.march` declared

```march
type Bytes = Bytes(List(Int))
```

so every byte of a payload was one 32-byte heap cons cell holding a
tagged 63-bit integer. Consequences, all measured rather than assumed
(interpreted `march`, arm64 macOS, payload = `String.repeat("abcdefghij", n)`):

| operation                | 4 000 B  | 16 000 B | 64 000 B |
|--------------------------|---------:|---------:|---------:|
| `Bytes.from_string`      |    47 ms |   189 ms |   810 ms |
| `Bytes.get(b, len-1)`    |    67 ms |   263 ms |  1063 ms |
| `Bytes.slice(b, len-100, 100)` | 65 ms | 264 ms |  1057 ms |
| `Bytes.length` × 100     |  3449 ms | 13383 ms | 54439 ms |
| 2 000 sequential `get`   | 32810 ms | 32282 ms | 32814 ms |

`length` is O(n), `get` is O(i), `slice` is O(start+len). A 256 KB
`from_string` did not finish in ten minutes.

At the C FFI boundary it was worse: `compress_bytes_from_raw` allocated one
cons cell per byte, so `march_gzip_decode` of a 12 MB tar allocated ~12M cells
(hundreds of MB) before any March code ran. `compress_bytes_to_raw` walked the
whole spine twice.

## The representation actually chosen

`Bytes` is now

```march
type Bytes = Bytes(String)
```

A March `String` is already the array-backed byte buffer this change was
looking for: `march_string` is `{ int64 rc; int32 tag; int32 pad; int64 len;
char data[] }` — a single `march_alloc` block with a length field and a
contiguous, NUL-safe, `memcpy`-able payload. It is not a text type in the
runtime; `march_string_byte_at`, `march_string_slice`, `march_string_chars`
and `march_char_from_int` are all byte-indexed, not codepoint-indexed
(`runtime/march_runtime.c:772, 3179, 3235, 3190`).

### Why not a new `ByteBuf` primitive

The obvious alternative was a fresh opaque heap type in the `NativeIntArr`
mould. It was rejected because it costs strictly more and buys nothing here:

* A new `TCon` has to be threaded through `typecheck.ml` (`builtin_types`,
  `builtin_bindings`, `non_sendable_types`), `eval.ml` (a new `value`
  constructor plus every builtin), `llvm_builtins.ml` (table rows *and*
  `PDeclare` markers), `defun.ml`, `borrow.ml`, `purity.ml`, the golden LLVM
  preamble in `test_codegen.ml`, and — because it would be a new tag — the
  message-copy walker in `march_message.c` and the GC's `pass2_visit`.
* `String` already has every one of those, plus interning, cross-heap copy,
  hashing, and generic compare, all exercised for years.
* The FFI layer had **already** unilaterally decided `Bytes` was a flat
  buffer: `march_bytes_borrow` is literally `march_str_borrow`
  (`runtime/march_ffi.c:52-58`), `rust/march/src/value.rs:216` borrows
  `&[u8]` out of one, and the interpreter marshals `Bytes` as an OCaml string
  (`lib/eval/eval.ml:1859, 1940`). The list representation and the FFI
  representation disagreed; this change makes them the same thing rather than
  adding a third.

### Why the wrapper constructor stays

`Bytes` remains a one-field boxed ADT cell — `[rc][tag=0][pad][field@16]` —
exactly as before. Only the *contents* of field 0 change, from a cons spine to
a `march_string *`. That is deliberate:

* `lib/tir/repr.ml:18-22` classifies `Bytes` as `Boxed` (not `Newtype`) only
  because `find_variant` matches type-def names exactly and the non-entry
  module registers it as `"Bytes.Bytes"`. `llvm_case.ml:80-115` compensates on
  the destructure side. `drop.ml:67-70` excludes the shape from deep drop
  precisely because the C runtime builds these cells by hand. Changing the
  wrapper would relitigate all three, and the last time that classification
  moved it silently made compiled `Bytes.concat` return empty and hung
  forgepm's Postgres handshake (`specs/progress_through_july_2026.md:4780`).
* Keeping the cell means every existing `*(void **)((char *)bytes_val + 16)`
  in the runtime keeps compiling and keeps pointing at the payload. Only what
  it *is* changes, so each such site is a small local edit rather than a
  layout migration.
* `march_extras.c`'s String-or-Bytes sniff (`:396`, "int64 at offset 8 is zero
  ⇒ Bytes ctor") still discriminates correctly: a `Bytes` cell has tag 0 and
  pad 0 there, a `march_string` has `MARCH_STRING_TAG` = -1.

## Complexity, before and after

| operation      | before      | after            | notes |
|----------------|-------------|------------------|-------|
| `length`       | O(n)        | **O(1)**         | `string_byte_length` reads the len field |
| `get`          | O(i)        | **O(1)**         | `string_byte_at` |
| `slice`        | O(start+len)| **O(len)**       | one `memcpy`, no prefix walk |
| `concat`       | O(n)        | O(n)             | one `memcpy` pair, ~32× less memory |
| `to_string`    | O(n)        | **O(1)**         | unwrap |
| `from_string`  | O(n)        | **O(1)**         | wrap |
| `is_empty`     | O(1)        | O(1)             | |
| `to_list`      | **O(1)**    | **O(n)**         | regression — see below |
| `from_list`    | **O(1)**    | **O(n)**         | regression — see below |
| C `bytes_to_raw`   | O(n), 2 passes, malloc+copy | **O(1)** borrow | payload is already contiguous |
| C `bytes_from_raw` | O(n), n allocations | **O(n)** single `memcpy` | |

Memory per byte of payload drops from ~32 bytes (a cons cell) to 1.

### The `to_list` / `from_list` regression

These were O(1) — they were the constructor and its inverse. They are now
O(n) conversions. This is the one place the change is not a strict
improvement, and it was audited rather than waved through:

* `stdlib/net_kernel.march:23-24` (`str_to_bytes` / `bytes_to_str`) round-trip
  through them on the wire path. Both are now expressed directly over
  `from_string`/`to_string`, which are O(1), so the net-kernel path gets
  *faster*, not slower.
* `stdlib/string.march:454-456` uses them on 1–4 byte codepoint encodings.
* Downstream, the overwhelming majority of `from_list` call sites are test
  fixtures spelling out literal byte arrays (`depot` has ~940, essentially all
  in `test/`). Those pay O(n) once on a handful of bytes.
* The counterweight is `String.to_codepoints` (`stdlib/string.march:478-515`),
  which called `Bytes.get(b, i)` in a loop and was therefore **O(n²)**. It is
  now O(n) with no source change.

### Aliasing, sharing and RC

Slices **copy**; they do not share the underlying buffer. This is the
conservative choice and it is a deliberate one:

* A sharing slice needs an `(owner, offset, len)` triple, which makes the
  payload cell contain a heap pointer child. `march_decrc`
  (`runtime/march_runtime.c:330-352`) is *shallow* — it does one `free(p)` and
  never recurses; child decrements are emitted by Perceus into generated code.
  A hand-built-in-C cell with a pointer child therefore has no one to drop the
  owner, and `drop.ml` explicitly refuses to destructure this shape. Getting
  that right means either a new resource-tagged cell with a destructor or new
  Perceus knowledge, i.e. exactly the cost the `String` reuse was chosen to
  avoid.
* Copying keeps `Bytes` immutable and freely sendable between actors, which
  the message-copy walker already handles for strings.
* The asymptotic win is preserved anyway: the old `slice` was O(start+len)
  because it had to *walk* to `start`. The new one is O(len). For the tar
  walking that motivated this work, `start` is large and `len` is small.

Sharing slices are a plausible follow-up, but they should be a separate
change with their own RC design, not a rider on this one.

## Streaming

Out of scope here, and this design does not foreclose it. The shape a chunked
reader wants is `Seq(Bytes)` (`stdlib/seq.march:308` already documents
`from_file_chunks` that way, though `file_read_chunk` currently returns
`Option(String)` — with `Bytes = Bytes(String)` that mismatch becomes a
one-line wrap instead of an O(n) conversion). A chunked
`Compress.gzip_decode_chunks : Bytes -> Seq(Bytes)` would drive zlib's
`inflate` with a fixed output window and yield one `march_string_lit` per
window, never materialising the whole payload. The 256 MB
`MAX_DECOMPRESS_SIZE` guard in `march_compress.c` exists precisely because
today it must.

## Vectorization

The payload is a contiguous `uint8_t` run at a fixed offset in a single
allocation, so it is directly usable with `memcpy`/SIMD from C. The FFI
already hands it out as a `march_slice { const uint8_t *; size_t }` with no
copy. No March-level vector API is added here; this change is what makes one
possible.

## Compatibility

The public `Bytes` API is unchanged in name, arity and type: `get`, `length`,
`slice`, `to_list`, `from_list`, `to_string`, `from_string`, `concat`,
`empty`, `is_empty`, `to_hex`, `from_hex`, `encode_base64`, `decode_base64`,
`encode_utf8`, `decode_utf8`, `Eq(Bytes)`.

What does break is code that reaches *through* the abstraction and matches the
constructor's payload as a list. Inside this repo that is
`stdlib/crypto.march:46,202` and `stdlib/uuid.march:287,291`, both fixed here.
Outside it, `bastion/lib/security/crypto.march:70,258,325` and
`bastion/lib/security/hkdf.march:37,49` do the same and will need the same
one-line change to `Bytes.from_list` / `Bytes.to_list`.
