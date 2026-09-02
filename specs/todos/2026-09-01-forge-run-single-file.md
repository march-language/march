`[P2]` # `forge run FILE` — run a single `.march` file

Filed 2026-09-01. Design approved; not yet implemented.

## The gap

`forge run` takes no positional argument. It builds and runs *the current
project*: the entry comes from `forge.toml`'s `[package] entrypoint`, else
`lib/<name>.march`, and anything else is an `entry point not found` error
(`forge/lib/cmd_run.ml`, `forge/bin/main.ml` `run_cmd`).

So there is no forge-level way to run one file. The workaround is to bypass
forge entirely and invoke `march foo.march`, which means hand-assembling
`MARCH_LIB_PATH` and the FFI shim flags that `forge build`/`forge test` build
for you — the file cannot import the project's own modules without it.

`forge test [FILE...]` already solves the same problem for tests, and its
shape is the precedent this item follows.

## Design

### 1. CLI surface

`forge run` grows an optional `pos_all` list. The first positional is the file;
the rest are the program's own arguments. Cmdliner's `--` already ends option
parsing, so no custom tokenising is needed.

```
forge run                        # unchanged: project entry, interpreted
forge run foo.march              # run that file
forge run --compiled foo.march   # LLVM pipeline, then exec the binary
forge run foo.march -- a b c     # a b c become the program's argv
forge run -- a b c               # project entry, with argv
```

If the first positional is not an existing file, fail before doing any work.

`--dump-phases`, `--compiled` and `--target` all apply to a FILE run.

### 2. `Cmd_run` restructuring

The organising idea: **`Cmd_run` resolves an *entry* plus a *context*, then runs
it.** Whether the entry came from `forge.toml` or from the command line is a
detail below that. This is what lets argv work on the project path too, instead
of leaving a hole there.

One resolver:

- `file = Some f` — entry is `f`. Context from `Project.load ()`: on success,
  `Cmd_build.lib_path_env proj` plus `Cmd_build.ffi_flags_full proj`, so an
  ad-hoc file inside a project can import that project's and its dependencies'
  modules. On failure, empty lib path and no FFI flags — the same fallback
  `Cmd_test.run_files` already uses for ad-hoc test files.
- `file = None` — today's logic verbatim; a project is required.

Two executors:

- **Interpreted.** `interp_command` gains `~args`; otherwise unchanged, so the
  unit test that pins its FFI flags (`forge/test/test_forge.ml`,
  `"interp_command"`) keeps testing what it was written to test.
- **Compiled.** With a FILE, call `Cmd_build.compile_entry` into a temp output,
  exec it with the program args, then remove it — the CAS makes the recompile
  cheap, so the binary is disposable. The temp output's extension follows the
  target the same way `Cmd_build.build` chooses one: a native binary with no
  extension, `.mjs` under `--target js`, which is then run with `node` (the
  existing `--compiled` branch already does this). With no FILE, keep calling
  `Cmd_build.build`, leaving the project's target-dir, CAS and workspace
  semantics untouched.

`Cmd_watch.run_action` calls `Cmd_run.run ~compiled:true ?target`; the new
parameters are optional, so it needs no change.

### 3. Compiler support for interpreted argv

Needed because `march` accepts exactly one positional (`bin/main.ml`, the
`Usage: march [options] [file.march]` branch) and the interpreter's
`process_argv` builtin returns the *compiler process's* `Sys.argv`
(`lib/eval/eval_builtins.ml`). Without this, `forge run f.march -- a b` would
work only under `--compiled`, and silently mean something else by default.

- `bin/main.ml`: add an `--args` spec using OCaml's `Arg.Rest`, which collects
  every remaining token verbatim. Forge always emits it last:
  `march foo.march --args a b`.
- Seed a `program_argv : string list option ref` with `entry :: args` before
  evaluation, following the existing bin-sets-an-eval-ref precedent
  (`March_eval.Eval.ffi_shim_so`). The ref must be defined early enough in the
  `lib/eval/` include chain for `eval_builtins` to read it.
- `process_argv` returns that list when set, and today's `Sys.argv` when not, so
  no existing behaviour changes. Nothing in the tree pins the interpreted
  values — `test/test_codegen.ml` uses `process_argv` only under
  `List.length` — so the risk is low.

Resulting semantics: `argv[0]` is the script path when interpreted and the
binary path when compiled. Both are "the thing being run", which is as close as
the two paths can get; the compiled path cannot report a `.march` path it never
executes.

## Verification

- `forge/test/test_forge.ml`: unit tests for the command builder with args, and
  for entry resolution with and without a project.
- A behavioural test: one file printing `System.argv()` produces identical
  output interpreted and compiled.
- Compiler-side test that `--args` seeds `process_argv`, and that omitting it
  leaves the old behaviour intact.

## Docs to update on landing

- `docs/tooling.md` (the forge CLI reference; `forge run` is documented there).
- `CHANGELOG.md`, under `### Added`.
- `git mv` this file to `specs/progress/`.
