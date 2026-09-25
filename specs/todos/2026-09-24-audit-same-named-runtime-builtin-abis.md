# Audit the ABI of builtins that link only because a same-named C function exists

Filed 2026-09-24, split out of
`specs/progress/2026-09-24-interpreter-only-builtins.md`.

`test/test_builtin_compiled_lowering.ml` accepts one group in
`special_lowerings` for a single reason: the generic extern-call path emits
`call @<name>`, and the runtime defines a C function with exactly that name,
so the call links. The group is `__try_call`, `__try_call_val`,
`http_fetch`, `http_fetch_available` and the `logger_*` family.
(`dns_resolve`, `uuid_v7` and `uuid_v7_at` left the group on 2026-09-25: each
was renamed to a `march_*` C function with an explicit row and `declare_sig`,
and `dns_resolve`'s argument is now classified borrowed. See
`specs/progress/2026-09-25-runtime-symbol-naming-and-uncompiled-caps.md`.)

Nobody has checked the C signature against the TIR call. The things to check
are argument count and order, i64 vs ptr for each argument (the erased-i64
convention), the return representation (a tagged scalar or a boxed `Option`
or `Result`), and the argument ownership (which `Borrow` classification each
builtin needs). For each builtin, either give it an explicit
`lib/tir/llvm_builtins.ml` row with a `declare_sig` (so the borrow guard sees
it), or write down why the generic path is correct.
