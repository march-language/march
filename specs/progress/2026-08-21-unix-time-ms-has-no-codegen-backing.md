# `unix_time_ms` / `unix_time` typecheck but have no codegen backing

Filed 2026-08-21. Found while writing `test/test_socket_timeout.ml`, which
wanted to measure elapsed time inside a compiled March probe.

## Symptom

A program that calls `unix_time_ms()` typechecks cleanly, compiles to LLVM IR,
and then fails at link time:

```
Undefined symbols for architecture arm64:
  "_unix_time_ms", referenced from:
      _probe_recv_timeout in march_socket_timeout_564-e5aec1.o
```

The builtin is registered in `lib/typecheck/typecheck.ml` (type
`() -> Int`, capability `IO.Clock`) but has no entry in
`lib/tir/llvm_builtins.ml` and no `march_*` symbol in the C runtime, so the
compiled backend emits a call to a symbol nobody defines. It works interpreted.

The same appears to apply to `unix_time` (`() -> Float`) — both are registered
side by side at `typecheck.ml:2512-2513` — though only `unix_time_ms` was
observed failing.

## Why it matters

The failure lands at **link** time, not compile time, with a C-level symbol
name and no March span. Nothing tells the author that the builtin they used is
interpreter-only, and nothing in the stdlib docs marks it as such.

## Fix

Either give it codegen backing (a `march_unix_time_ms` runtime symbol plus the
`llvm_builtins.ml` entry and `PDeclare`, following any `IO.Clock` sibling that
already links), or reject it at typecheck time under `--compile` with a real
diagnostic. The first is preferable — a clock is not an unreasonable thing to
want in a compiled program.

Worth auditing the whole builtin table for other entries that typecheck but do
not link: the two tables are maintained by hand and nothing cross-checks them.
That audit is the more valuable half of this item.

---

## RESOLVED (2026-08-22) — codegen backing, plus the audit

Fixed the first way this file offers: real codegen backing, not a `--compile`
rejection. A clock is not an unreasonable thing to want in a compiled program.

### `unix_time` was already fine

This file guessed both were broken. Only `unix_time_ms` was: `unix_time` has had
its `llvm_builtins.ml` entry, its `PDeclare`, `march_unix_time` in the C runtime
and a JS arm all along. Corrected here so the next reader does not go looking.

### What `unix_time_ms` needed — seven sites

The multi-site trap this repo keeps re-paying. Adding one builtin touched:

- `runtime/march_runtime.c` — `march_unix_time_ms`, and `runtime/march_runtime.h`
- `lib/tir/llvm_builtins.ml` — table entry AND the `PDeclare` (they are separate
  lists; the entry alone gets you `use of undefined value '@march_unix_time_ms'`)
- `lib/tir/defun.ml` `builtin_names` — without it, Defun turns the call into a
  closure application and the symbol comes back as `unix_time_ms$clo_wrap`
- `lib/tir/purity.ml` — a wall clock read is not pure; two reads must not CSE
- `lib/tir/js_emit.ml` — the call arm, the `runtime_uses` registration, and the
  `const unix_time_ms = ...` wrapper shim for the closure-application path
- `runtime/march_runtime.mjs` — `march_unix_time_ms`

`march_unix_time_ms` computes in integers (`tv_sec * 1000 + tv_nsec / 1000000`)
rather than `(int64_t)(march_unix_time() * 1000.0)`: a double has 53 mantissa
bits, and the seconds-as-double round trip drops sub-millisecond resolution as
the epoch grows.

### The audit — the more valuable half, as this file said

Cross-checked all 531 names in `typecheck.ml`'s builtin table against what the
compiled backend can actually resolve (an `llvm_builtins` entry, a string
literal anywhere in `lib/tir`/`lib/jit`, or a bare-named definition in
`runtime/*.c` — the last is a real and undocumented third route, which is how
`uuid_v7` and the whole `logger_*` family link). Five names came out with none
of the three. Probed each:

| builtin | interpreted | compiled | disposition |
|---|---|---|---|
| `unix_time_ms` | works | link error | FIXED here |
| `string_to_codepoints` | works | link error | FIXED here |
| `string_from_codepoint` | works | link error | FIXED here |
| `worker` | implemented | link error | filed, see below |
| `dynamic_supervisor` | implemented | link error | filed, see below |
| `from_json_events` | `unbound variable` | link error | filed, see below |

`string_to_codepoints` / `string_from_codepoint` are the identical defect and
were fixed the same way (`march_string_to_codepoints` /
`march_string_from_codepoint`, next to `march_string_chars`, whose list and
niche-Option conventions they share; plus `borrow.ml` entries, which
`string_chars` itself is missing). The C decoder deliberately reproduces the
interpreter's handling of a TRUNCATED UTF-8 sequence — the lead BYTE, not a
replacement character — because the two backends have to agree and the
interpreter is the older one.

`worker` / `dynamic_supervisor` build `ChildSpec` values for the supervision
DSL and giving them codegen backing is a different piece of work;
`from_json_events` is a table entry with no implementation on either backend.
All three are out of scope here and are filed as
`specs/todos/2026-08-22-builtins-that-typecheck-but-do-not-link.md`.

Nothing cross-checks the two tables, so this audit will rot. That todo carries
the reproduction recipe.

### Test

`test/native/builtin_link_backing.march` + `.expected`, wired into `test/dune`.
All three builtins. Nothing about a wall clock is reproducible, so every clock
assertion is a RELATION (epoch is past, the two clock builtins agree within a
second, the clock does not run backwards) rather than a value; the codepoint
rows cover 1-, 2-, 3- and 4-byte UTF-8, the empty string, out-of-range, and a
lone UTF-16 surrogate half.

RED, against the unfixed compiler — this is what the whole item is about, a
failure with a C symbol name and no March span:

```
Undefined symbols for architecture arm64:
  "_unix_time_ms", referenced from:
      _march_main in unix_time_ms_codegen-fc5ede.o
      _unix_time_ms$clo_wrap in unix_time_ms_codegen-fc5ede.o
ld: symbol(s) not found for architecture arm64
```

and for the codepoint pair, `_string_from_codepoint` / `_string_to_codepoints`.
GREEN: compiled output byte-identical to interpreted.
