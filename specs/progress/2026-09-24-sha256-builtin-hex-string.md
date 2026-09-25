# `sha256` builtin: typecheck said `Bytes -> Bytes`, both backends returned a hex String

**Landed:** 2026-09-24.

## Symptom

```march
let d = sha256(Bytes.from_string("abc"))
println(int_to_string(Bytes.length(d)))
```

typechecked, then: interpreted, `panic: match failure ... no branch matched
the value "ba7816bf..."` (a String reached `Bytes.length`'s pattern match);
compiled, `march: fatal SIGBUS ... fault outside its stack`, exit 138.

## Two bugs

1. **Signature.** `lib/typecheck/typecheck_builtins.ml` declared
   `("sha256", Bytes -> Bytes)`, but `lib/eval/eval_builtins.ml`'s arm returns
   `VString (Digestif.SHA256.to_hex ...)` and `runtime/march_extras.c`'s
   `march_sha256` returns `march_string_lit(hex, 64)`. `Crypto.sha256`
   (over `stdlib_sha256 : String -> String`), `md5` and `sha512` all return
   hex Strings too. Canonical choice: **hex String**; the signature is now
   `Bytes -> String`. `lib/tir/llvm_builtins.ml`'s `ret_ty` already said
   `TString`, so codegen was never the one lying. Raw digests stay with
   `hmac_sha256_bytes` / `sha1_bytes`, which return Bytes on both backends.

2. **Runtime.** Even with the signature fixed, compiled `sha256(bytes)`
   still died: `march_sha256` served both the String-typed `stdlib_sha256`
   and the Bytes-typed `sha256` through one C function that guessed the
   argument's kind by testing whether the 64-bit word at offset 8 was zero
   ("a Bytes ctor has tag 0, pad 0"). The compiler now stamps a type id into
   the pad word (+12) of every boxed ctor, so that word is never zero for a
   Bytes box, every Bytes read as a `march_string`, and the payload POINTER
   at +16 was taken as the string length: `memcpy` of gigabytes, SIGBUS.
   Fix: `march_sha256_of_bytes` (Bytes only, via `bytes_to_raw`) is the C
   entry for the `sha256` builtin, chosen by the compiler from the static
   type; `march_sha256` / `march_sha512` are String-only and the guessing
   helper is deleted. (`march_sha1_bytes` was fixed the same way earlier for
   `UUID.v5`.)

## Files

- `lib/typecheck/typecheck_builtins.ml` — `sha256 : Bytes -> String`.
- `runtime/march_extras.c`, `runtime/march_runtime.h` — `march_sha256_of_bytes`;
  `string_or_bytes_to_raw` removed.
- `lib/tir/llvm_builtins.ml` — `sha256` row's `c_name`/`declare_sig`, preamble
  `PDeclare`; `test/test_codegen.ml` preamble golden.
- `test/refine_audit/corpus.baseline` — regenerated (the audit sweeps every
  `test/native` fixture, so the new one adds two lines).

## Tests (both backends)

- `test/native/sha256_hex_string.march` + `.expected`: run interpreted AND
  compiled by `test/dune`, both diffed against the same golden.
- `test/stdlib/test_crypto_builtins.march` (registered in
  `test/test_stdlib_march.ml`): the interpreter suite.
- `test/test_compiler.ml` `sha256_builtin_type`: String-typed use accepted,
  Bytes-typed use rejected.

Before the fix the native fixture reproduced exit 138 on the compiled run and
the stdlib file failed to typecheck (`string_length` of a `Bytes`).
