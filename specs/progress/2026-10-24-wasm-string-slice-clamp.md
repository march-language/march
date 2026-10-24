# `[P2]` wasm `march_string_slice` read before the buffer on a negative start

Fixed 2026-10-24.

`runtime/march_runtime_wasm.c` (the runtime behind the in-browser compiled path) guarded only
`start >= length || len <= 0`, so a negative `start` indexed `str->data[start + i]` before the
buffer. Native (`runtime/march_runtime.c`) and the interpreter (`string_slice` in
`lib/eval/eval_builtins.ml`) clamp both arguments. Offsets are bytes everywhere in C/interp.

| input | wasm before | wasm after = native = interp |
|---|---|---|
| `start < 0` | OOB read (`start + len` shortens len too) | start := 0, len unchanged |
| `start > length` | empty | empty (start := length) |
| `len < 0` | empty | empty |
| `len` past the end | clamped | clamped to `length - start` |

Audit of the other wasm string functions: the rest of the file's string functions are
identity/empty stubs (`split`, `trim`, `pad_*`, `last_index_of`, ...) or index only with
loop-bounded indices (`contains`, `starts_with`, `ends_with`, `index_of`); there is no wasm
`char_at`/`byte_at`/`take`/`drop`. Nothing else needed a clamp.

Test: `test/native/string_slice_clamp.march` runs on the interpreter and compiled native
against one golden (dune rule in `test/dune`, both in `runtest`). The wasm C file itself cannot
be built where this was written (no emcc; Apple clang has no wasm32 target), so wasm is not
exercised by it; CI's `browser-repl` job builds the in-browser March.
