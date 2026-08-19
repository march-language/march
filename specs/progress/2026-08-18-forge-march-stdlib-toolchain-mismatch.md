# forge paired one install's compiler with another install's stdlib

**Status:** fixed (2026-08-18)

## Symptom

`forge` subprocesses reported large numbers of type errors in source that was
correct. In one case `forge bastion.new` failed with 47 errors across 12 files
— including files in a dependency — while the *identical* entry module, module
set and compiler returned 0 errors under a direct `march --check`, plain
`march <file>`, and a full `march --compile`.

The errors all looked like Vault element-type confusion (`expected \`Int\` but
got \`List(...)\``, `expected \`Int\` but got \`Bool\``), which reads as a bug in
the project's own Vault usage. It was not.

## Root cause

`Archive_store.find_stdlib_dir` resolved the stdlib from **forge's own
executable**:

```ocaml
let exe_dir = Filename.dirname Sys.executable_name in
[ exe_dir ^ "/../stdlib"; ...; exe_dir ^ "/../share/march"; "stdlib" ]
```

but `Archive_store.run_task` (and `cmd_build`, `cmd_deps`, `registry_client`,
`registry_query`) invoke `march` through `Toolchain.path_prefix ()`, which puts
the **resolved toolchain**'s `bin/` first on PATH.

Those are two different installs whenever forge did not come from the toolchain
prefix. On the reporting machine:

- executed compiler: `~/.march/versions/local-main-6b6a1811/bin/march` (2026-08-18)
- exported stdlib:   `~/.opam/march/share/march`                       (2026-08-14 13:15)

The stdlib predated `ffdb0da4` (#282, typed Vault handles, 2026-08-14 15:38),
so a post-`Vault(v)` compiler was typechecking a pre-`Vault(v)` stdlib.

Isolated measurement — identical compiler, lib path and entry file, only
`MARCH_STDLIB` differing:

| stdlib | result |
| --- | --- |
| the toolchain's own | exit 0, 0 errors |
| the opam install's  | exit 1, 47 errors |

## Fix

`Toolchain.stdlib_dir` returns `versions/<tag>/stdlib` for the resolved version,
and `Archive_store.find_stdlib_dir` now reads:

1. `MARCH_STDLIB` (explicit override)
2. the resolved toolchain's stdlib
3. forge-exe-relative candidates — **only when no version is resolved**

Step 2 deliberately does not fall through to step 3. If a toolchain is resolved
but ships no `stdlib/`, the answer is `None`: emitting no `MARCH_STDLIB` lets the
compiler resolve its own exe-relative stdlib, which is correct by construction.
Falling back to forge's prefix is what created the mismatch.

Six call sites share `Archive_store.find_stdlib_dir` and are fixed by this.
`cmd_notebook.ml` carried a second copy of the same exe-relative guess and now
delegates to the shared resolver; its `find_march` was also forge-exe-relative,
so it is now toolchain-aware too — otherwise the fix would have introduced the
mirror-image mismatch there (toolchain stdlib + a `march` sitting beside forge).

## Verification

Same machine, same sources, no `MARCH_STDLIB` override:

- before: `forge bastion.new` → exit 1, 47 errors
- after:  `forge bastion.new` → exit 0, scaffolds a working app

`@forge/test/runtest` passes (including `build_check` and `cap_sandbox`);
`run_compiler` 924 tests and `run_eval` 263 tests pass.

## Note for future debugging

A `forge` diagnostic is not authoritative on its own. To see what forge actually
passes, put a shim first on PATH that logs `env | grep -E '^(MARCH|FORGE)'` and
then execs the real binary, running forge under `MARCH_HOME=<empty-dir>` so the
shim wins over `Toolchain.path_prefix`.
