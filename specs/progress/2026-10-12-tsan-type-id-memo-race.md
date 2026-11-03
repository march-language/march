# `[P4]` TSAN: the runtime's lazily memoised type ids raced across schedulers — FIXED

Found 2026-10-12 by the TSAN sweep over `test/native/*.march` (every fixture with an
`.expected`, built with `MARCH_SANITIZE=thread`, run at 1, 2 and 14 schedulers).

## What TSAN reported

Six runtime helpers cache `march_type_id_of_name(<name>)` in a function-local
`static int32_t` (0 = not yet computed) with a plain `if (id == 0) id = ...`:

- `is_bytes_value` (`runtime/march_extras.c`): `Bytes.Bytes` and `Bytes`
- `iolist_type_id` / `iolist_type_id_bare` (`march_extras.c`)
- `list_type_id` / `result_type_id` / `file_error_type_id` (`runtime/march_runtime.c`)

Two green threads on different schedulers calling, for example, `sha256` (via
`string_or_bytes_to_raw` -> `is_bytes_value`) or building a `List` in C, race on the
first fill: a plain read on one thread against a plain write on another. Seen in
`block_sender_loopback`, `control_channel_loopback` and `credit_backpressure_loopback`.

## Benign, but undefined

Every thread stores the same value (the id is a pure FNV hash of a constant name), and
an aligned `int32_t` cannot tear on arm64 or x86-64, so no wrong answer was possible.
It is still a C11 data race, and any TSAN report on a green thread was the trigger
for the macOS self-deadlock in
`specs/progress/2026-10-11-macos-tsan-scheduler-wedge.md`.

## Fix

`march_type_id_memo(int32_t *slot, const char *name)` in `runtime/march_runtime.h`
reads and writes the slot with relaxed `__atomic` builtins. Every memo site uses it.
On arm64, a relaxed load or store is the same `ldr`/`str` as the plain access.

Verified: the three fixtures rebuilt with the fix report nothing at 1, 2 and 14
schedulers.
