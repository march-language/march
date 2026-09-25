# `[P0]` DONE Compiled `Base64.encode` / `sha256` on a `Bytes` SIGBUSed

Reported 2026-09-24 from forgepm's test suite (`test/mail_test.march`, the
Mailgun basic-auth header). On main `15acbe3a`:

```march
let s = "Basic " ++ Base64.encode(Bytes.from_string("api:SECRET"))
```

compiled to a binary that died with `march: fatal SIGBUS ... fault outside its
stack` (exit 138). The interpreter printed `Basic YXBpOlNFQ1JFVA==`, as did the
compiled build from `b26bacf0` (Aug 21).

## Root cause

`march_base64_encode` and `string_or_bytes_to_raw` (used by `march_sha256` /
`march_sha512`) in `runtime/march_extras.c` take "a String or a Bytes" and told
them apart by the 64-bit word at offset 8: a String's length there, a Bytes
ctor's `tag:i32 + pad:i32`. They treated the value as Bytes only when the whole
word was 0.

`d738f996a` ("boxed ADT cells carry a runtime type id", 2026-09-11) made every
compiler-emitted constructor header store a negative type id into `pad`
(`Bytes.Bytes` → `-298936870`). A compiler-built `Bytes` therefore failed the
check, was read as a `march_string`, and its payload pointer's low bits were
taken as a length for a `malloc` + `memcpy` that ran off the mapping. A
C-built Bytes (`bytes_wrap`, pad 0), e.g. the result of `Base64.decode`, still
worked, which is why only freshly constructed Bytes crashed.

Found by reading the emitted IR (`store i32 -298936870` at +12 of the `Bytes`
cell), not by a commit-by-commit bisect; the causal link was proved by the
perturbation below.

## Fix

`is_bytes_value` in `runtime/march_extras.c`: tag 0 and pad either 0 (C-built)
or the type id of `Bytes.Bytes` / bare `Bytes` (when `bytes.march` is itself
the entry module), computed with `march_type_id_of_name`, which mirrors
`Llvm_ctx.type_id_of_name`. Both call sites use it; `march_base64_encode` now
goes through `string_or_bytes_to_raw` rather than its own copy of the check.

## Test

`test/native/bytes_typeid_base64_sha.march`: compiled and interpreter runs both
diffed against one `.expected` (compiler-built Bytes, runtime-built Bytes, empty
Bytes, url/mime variants, `sha256`, and the String callers through `Crypto`).
Reverting only `runtime/march_extras.c` makes the compiled rule SIGBUS (RED);
the fix makes it GREEN.
