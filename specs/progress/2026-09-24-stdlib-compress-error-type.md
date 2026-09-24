# `[P2]` DONE compress.march: the gzip/zstd builtins return `Result(_, String)`, its signatures say `Compress.Error`

Filed 2026-09-22 from the stdlib internal-error sweep
(`2026-09-22-stdlib-internal-type-errors.md`). 19 errors in `stdlib/compress.march`.

`stdlib/compress.march:23` declares a structured `type Error`, and the public
signatures promise `Result(Bytes, Compress.Error)`. The underlying builtins
(`stdlib_gzip_encode`, `stdlib_gzip_decode`, …) are typed as returning
`Result(Bytes, String)`, so every wrapper is "expected `Error` but got `String`"
(:70, :80, :92, :134, :146, :179, :189, :201, :282). The streaming wrappers add
a second shape of failure — `decode_stream` at :105/:116/:209/:217 reports
"expected `Result(Bytes, Error)` but got `f -> (e -> d -> c) -> b`" and
":270/:261 This is not a function — it has type `Result(Bytes, String)`", which
looks like the `Seq.map` callback being applied with the wrong arity on top of
the error-type mismatch.

Either map the builtin's `String` into `Compress.Error` at each wrapper, or
retype the builtins to return the structured error. Fix the `Seq.map` call
shapes at the same time; the arity errors may be a consequence of the first
mismatch rather than independent.

## Resolution (2026-09-24)

Decision (owner): map the builtin's `String` into `Compress.Error` at each
wrapper and leave the builtins' error type alone.

What was wrong: three separate things, not one.

1. **Error type.** Every wrapper returned the builtin's `Result(Bytes, String)`
   where it promised `Result(Bytes, Compress.Error)`. At runtime the `Err`
   payload was a string, so `Err(Compress.InvalidInput(_))` never matched.
   Fixed with two classifiers in `Compress` that read the codec message (the
   compiled shim `runtime/march_compress.c` and the interpreter's
   `lib/eval/compress_stubs.c` spell the same messages):
   - decode: `"size limit exceeded"` / `"exceeds limit"` -> `InsufficientOutput`;
     `"out of memory"`, a failed `...Init...`, `"not available"` -> `Io(msg)`;
     everything else (inflate failed, unexpected end, zstd frame errors,
     brotli decompression failed) -> `InvalidInput(msg)`.
   - encode: `"input too large"` -> `InvalidInput(msg)`; everything else -> `Io(msg)`.
   The wrappers call `Compress.lift_encode_error` / `lift_decode_error`.
   These are **public**, which was not the plan: a bare call to a parent
   `pfn` from inside `mod Gzip` typechecks and interprets but fails to LINK
   compiled (`"_map_encode"` undefined), and a qualified call to a `pfn` is
   rejected as private. That is a compiler bug independent of Compress (it
   reproduces in a two-file `MARCH_LIB_PATH` program), filed as
   `specs/todos/2026-09-24-nested-module-bare-parent-call-link-failure.md`.
2. **The streaming functions' annotations** (`encode_stream`/`decode_stream`
   in Gzip and Zstd) were `Seq(Bytes) -> Seq(Result(...))`. `Seq(a)`'s
   parameter is the church-encoded fold closure, not the element type
   (`ptype Seq(a) = Seq(a)` in `stdlib/seq.march`), so `Seq(Bytes)` can never
   match a real sequence. That was the "expected `f -> (e -> d -> c) -> b` but
   got `Bytes`" family; the `Seq.map` calls themselves were fine. The
   annotations were removed (a comment says why). Pre-fix, a user program
   calling `Compress.Gzip.decode_stream(Seq.from_list([...]))` did not typecheck.
3. **`stdlib_brotli_encode`'s typecheck signature had one parameter too few**
   (`Bytes -> Int -> Result`, where the interpreter and codegen both take
   `(data, mode, quality)`). That was the ":261/:270 This is not a function"
   pair. Fixed in `lib/typecheck/typecheck_builtins.ml`. This is an arity fix,
   not the error-type retyping the decision ruled out.

Doc strings updated: the module header, the `Error` variants' meanings, the
stream examples, and the zstd/brotli examples that did `"..." ++ e` on what is
now an `Error`.

Evidence:
- `march --check stdlib/compress.march`: 19 errors -> 0; the ratchet row is removed.
- `test_gzip_decode_invalid_is_structured` (run_stdlib, `Quick`): interpreted
  gzip decode of garbage is `Err(Compress.InvalidInput(msg))`, `msg` naming the codec.
- `test_compress_decode_error_structured_both_backends` (run_stdlib, `Slow`,
  compiled + interpreted): gzip/deflate/zstd/brotli decode of garbage ->
  `InvalidInput` (zstd/brotli built without their library report
  `Io("... not available ...")`, which the test allows), a gzip round-trip,
  and `Gzip.decode_stream` over `Seq.from_list`. Identical output on both
  backends. Pre-fix the program does not typecheck (the stream call).
