# `[P3]` Multi-lib `[[ffi]]` (array-of-tables in forge.toml)

Split out of `specs/todos/2026-06-19-p3-language-features.md` (one item per file). The rest of
the FFI work in that file (`forge ffi import`, recursive/generic codecs, an OCaml FFI layer) is
independent.

A project can declare one `[ffi]` library today. Declaring several needs array-of-tables
(`[[ffi]]`), which is blocked on a limitation in forge's TOML parser. The same limitation also
blocks `[[ffi.rust]]` and Rust crate publishing beyond path-only dependencies. Fixing the
parser is the prerequisite; the `[[ffi]]` build integration follows.

History of the C-first FFI: `specs/c-ffi-gaps.md`.

## Done 2026-10-06

The parser prerequisite had already landed: `forge/lib/toml.ml` parses
`[[array-of-tables]]` and has `get_all_sections`. What was left was the
build integration. `Project.load_from_dir` read `[ffi]` with `get_section`,
which returns only the FIRST table of a name, so a second `[[ffi]]` table's
shims and link flags were silently dropped. `[ffi.rust]` was a single
optional crate.

Now (`forge/lib/project.ml`): `ffi_sources` and `ffi_link` concatenate every
`ffi` table in declaration order, and `ffi_rust` is a list with one entry per
`[[ffi.rust]]` table. `Cmd_build.ffi_flags_full` builds each crate in order
and stops at the first failure. Cross-compiling still refuses any Rust crate.
The single-table spellings `[ffi]` / `[ffi.rust]` read exactly as before.
Documented in `docs/ffi.md`.

Tests (`forge/test/test_forge.ml`, `ffi` group): two `[[ffi]]` tables and two
`[[ffi.rust]]` tables load in full, and `ffi_flags_of` passes both
libraries' `--ffi-c` / `--ffi-link` to the compiler. A single `[ffi]` table
is unchanged.

Not covered here: publishing a package whose Rust crate is anything other
than a path dependency. That is registry and archive work, separate from
reading the tables.
