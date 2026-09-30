# `[P3]` Multi-lib `[[ffi]]` (array-of-tables in forge.toml)

Split out of `specs/todos/2026-06-19-p3-language-features.md` (one item per file). The rest of
the FFI work in that file (`forge ffi import`, recursive/generic codecs, an OCaml FFI layer) is
independent.

A project can declare one `[ffi]` library today. Declaring several needs array-of-tables
(`[[ffi]]`), which is blocked on a limitation in forge's TOML parser. The same limitation also
blocks `[[ffi.rust]]` and Rust crate publishing beyond path-only dependencies. Fixing the
parser is the prerequisite; the `[[ffi]]` build integration follows.

History of the C-first FFI: `specs/c-ffi-gaps.md`.
