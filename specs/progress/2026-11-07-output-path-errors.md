# An unwritable `-o` path is a user error, not an ICE (issue #1181, 2026-11-07)

## The bug

`march --target js -o dist/x.mjs hello.march` with no `dist/` printed
`march: internal compiler error: Sys_error("dist/x.mjs: No such file or directory")`,
an OCaml backtrace and "This is a compiler bug", and exited 3. The JS branch of
`compile` in `bin/main.ml` wrote the output with a bare `open_out out_bin`, and its
`Sys_error` reached the compile pipeline's catch-all `| exn ->` handler, which treats
anything that lands there as a compiler bug. An output path that is a directory, or sits
under a regular file, or under a directory without write permission, failed the same way.
The source-map write just above it caught `Sys_error` and dropped it without a word.

Native `--compile -o out/x` with no `out/` did not ICE, but it was inconsistent: a CAS
cache hit created the directory (`Cas.copy_file_exec` runs `mkdir_p` on the destination's
parent) and a miss failed in the linker (`ld: open() failed ... march: clang failed`).

## The fix (`bin/main.ml`)

- **`prepare_output_path`**, called once on `out_bin` for every `--compile` target (JS,
  wasm, native) before anything is written: an existing directory is rejected, missing
  parent directories are created (`Toolchain.mkdir_p`), and a parent that is not a directory
  (or cannot be created) is rejected. Each rejection is `output_path_error`:
  `march: error: cannot write the output <path>: <reason>`, exit 1, the code every other
  diagnosed user error uses (exit 3 stays reserved for a real compiler crash).
- **`write_output_file`** writes the JS output; a `Sys_error` that still happens (e.g. a
  read-only directory) becomes the same `output_path_error`.
- **The source map** failing to write is a `march: warning: cannot write the source map ...`,
  and the output then carries no `//# sourceMappingURL` comment naming a file that is not
  there.

## Tests

`test/test_codegen.ml`, group `iface_impl_mono_codegen`, case "unwritable -o path: dirs
created, plain error, no ICE (#1181)": JS with a two-level missing parent (builds, writes
the map, runs under node), JS under a regular file and onto a directory (exit 1, `error:`
naming the path, no "internal compiler error"), native with a missing parent (builds and
runs), native under a regular file (exit 1, no ICE). Red before the fix on the first check:
the ICE text and exit 3.

## Docs

`docs/tooling.md`, JavaScript Backend: `-o` creates missing parent directories; an
unwritable path is an error with exit 1.
