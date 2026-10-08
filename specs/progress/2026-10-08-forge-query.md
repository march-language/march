# DONE 2026-10-08: `forge query`

`march query` (A7, `specs/progress/` entry for the query interface) takes a file. In a
project the file, the library path and the build's flags are all things forge already knows,
so `forge query` fills them in.

## What landed

- **`forge/lib/cmd_query.ml`, `forge query ARGS...`.** forge does not parse the query
  grammar. It passes the query's own arguments to `march query` unchanged, so the compiler
  stays the one place that defines it (forge shells out to `march` and links none of the
  compiler's libraries). What forge adds:
  - the project's entry file, unless a `.march` file is named (a library has no entry file
    and gets an error saying so);
  - the project's `MARCH_LIB_PATH` and resolved toolchain (`Cmd_build.lib_path_env`);
  - the build's compiler flags: optimisation level, `--target`, `--pin-main`, hot-reload,
    `[ffi]` sources and links, the topology digest when a build has written one, and protocol
    baselines;
  - `--release`, `--target T`, `--at PASS`, `--json`; anything after `--` goes to the
    compiler. `--opt` and `--target` in the passthrough are refused with the forge spelling,
    because forge's flags come last and would silently win.
- **`Cmd_build.compile_flags`**, extracted from `compile_command`, builds those flags for
  both. `compile_command`'s output is byte-identical (the existing `pin_main` test pins it).
  `Cmd_build.normalise_target` is the target-alias table `build` had inline.
  `Cmd_build.protocol_flags` gained `?emit` so a query passes the baselines without
  `--emit-protocols`, which writes.
- **Read-only.** No `[ffi.rust]` crate is built (its archive is linked only if a previous
  build left it), no preprocessor runs, no baseline is written, no toolchain is downloaded.
- **Outside a project**, `forge query verify FILE` works on the named file with the default
  flags.
- **Docs**: a new "Asking the Compiler Questions" section on the site's tooling page (the
  site had nothing on `march query` or the verifier before), the march-debug skill, and the
  changelog.

## Verified end to end

On a scaffolded app, with the freshly built compiler:
- Every query form runs and exits with the compiler's own code; `--json` is one object.
- `forge query key` and `--release` give different post-TIR keys.
- **The key is the build's key.** The post-TIR key printed before any build is the key
  reported as `cached` after `forge build`, and `why-miss` then reports a source-level hit.
  (The source-level key does change across the first build: before it, no list of loaded
  files is recorded, after it the key is over exactly the files that build loaded.)

## Red

`forge/test/test_forge.ml`, group `forge_query`: command shape (entry appended only when no
file is named, `--at`/`--json` forwarded, a hostile name stays one quoted word), `--opt` and
`--target` refused, the build and the query share one flag builder, and a library without a
named file is an error. Removing the shell quoting makes the shape test fail.
