# `[P2]` compress.march: the gzip/zstd builtins return `Result(_, String)`, its signatures say `Compress.Error`

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
