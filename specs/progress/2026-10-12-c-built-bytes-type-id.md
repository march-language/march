# Compiled `to_string` of a Bytes the C runtime built printed `#<tag:0>`

**Date:** 2026-10-12. Found by the interpreter-vs-compiled differential sweep
(group V).

## What was wrong

```march
println(to_string(Base64.decode("aGVsbG8=")))
-- interpreted: Ok(Bytes("hello"))
-- compiled:    Ok(#<tag:0>)
```

`Base64.decode` returns the `Bytes` cell `march_base64_decode` builds in C
(`bytes_wrap`). Compiled constructor stores stamp the header pad word with
the type's id (`-(1 + fnv1a32("Bytes.Bytes") & 0x3FFFFFFF)`, see the
`march_hdr` comment in `runtime/march_runtime.h`), and the renderer names a
cell reached through an erased slot by that id. C-built Bytes cells left the
pad at 0, so the renderer had only the tag. A `Bytes` built in March
(`Bytes.from_string`) printed correctly.

## The fix

`runtime/march_runtime.h`: `march_bytes_type_id()`, the same hash as
`march_type_id_of_name("Bytes.Bytes")`, inlined so `march_http.c` (built
without `march_extras.c` by `bench/bench_http_simd.sh`) can use it. The three
C constructors of a Bytes cell stamp it: `bytes_wrap` (`march_extras.c`:
base64 decode, the SHA/HMAC/PBKDF2 digests, random bytes, `NativeU8Arr` -> Bytes),
`compress_bytes_from_raw` (`march_compress.c`) and `make_bytes_from_raw`
(`march_http.c`).

## Tests

`test/native/bytes_c_built_to_string.march` (+ `.expected`, rule in
`test/dune`, refine audit baseline regenerated): a March-built and a C-built
Bytes, alone, in a `Result` and in a list; compiled output equals the
interpreter's. Before the fix lines 2 and 3 printed `#<tag:0>`.
