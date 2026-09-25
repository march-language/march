# `forge audit --inferred`: toolchain probe, per-dependency cache, `--allow-unanalyzable`

**DONE 2026-09-24.** Bullets 1–3 of
[../todos/2026-08-04-dependency-cap-audit-followups.md](../todos/2026-08-04-dependency-cap-audit-followups.md).
Bullets 4 (`forge add`/`forge outdated` wiring) and 5 (registry cross-check) are still
open there. Design context: `specs/2026-08-03-forge-cap-audit-design.md` §4.3.

Code: `forge/lib/cmd_audit.ml` (collection, cache, reporting), `forge/lib/cap_package.ml`
(`probe_caps_support`, `compiler_identity`), `forge/bin/main.ml` (the flag and the man
page). Tests: `forge/test/test_audit_inferred.ml` (new; in the `forge/test` `(tests)`
stanza).

## 1. The toolchain probe

**What it keys on.** The probe does not match an error message or a version number. It
checks the contract that `Cap_package.of_package` relies on. It writes a trivial module
(`mod ForgeCapsProbe do fn probe() : Int do 1 end end`) to a temp dir and runs
`march caps <it>` with the toolchain `PATH` prefix and an empty `MARCH_LIB_PATH`. The
toolchain supports `caps` if and only if that exits 0 and prints a JSON object with a
`"caps"` field. Why not the other candidates:

- A `--help` listing is not possible: `march --help` is `Arg.parse`'s option list, and
  subcommands are not in it.
- A version compare gets nightlies wrong. `--version` prints the dune-project version,
  and `nightly-20260805` has `caps` but reports `0.2.0` (checked with
  `git show nightly-20260805:dune-project`). A version floor would reject it, and dev
  builds have the same problem.
- `march caps` with no files: the current compiler prints `march check: no files
  specified`, and a pre-`caps` compiler also exits 1 with a usage line. Telling them
  apart would mean matching message text.

The trivial-module run takes about 0.2s with a warm stdlib cache. It runs **lazily,
once per audit, just before the first real `march caps`**, so an audit where every
dependency is a cache hit never probes. That is sound because a hit's key includes the
compiler identity: a hit means this exact compiler already produced a successful
result. When the probe fails, the error gives the resolved `march` path
(`sh -c 'command -v march'` under the same prefix), its `--version` output, the first
release with `caps` (0.3.0, nightly-20260805, from `git tag --contains` on the commit
that added it), how to fix it, and the first three lines the probe printed.

Measured against a real pre-`caps` toolchain (`~/.march/versions/nightly-20260629`,
`march 0.1.0`, which prints `Usage: march [options] [file.march]`, exit 1) by pinning a
scratch project to it:

```
error: the March toolchain this audit runs does not support `march caps`, which `forge audit --inferred` needs.
toolchain: /Users/…/.march/versions/nightly-20260629/bin/march (march 0.1.0)
`march caps` first shipped in march 0.3.0 (or nightly-20260805). …
```

A related gap is closed too. `Cmd_build.lib_path_env` turns a `Toolchain.path_prefix`
error (a `.march-version` pin whose toolchain is not installed) into `""`, which means
"use whatever `march` is on PATH". In inferred mode that error now stops the audit.
`lib_path_env` itself is unchanged; other commands still fall through.

## 2. The cache

It lives at `<project>/.forge/audit-cache/<key>.caps`, next to `check_all`'s
`.forge/check-cache/`, and follows the same marker-cache pattern. A hit is only a file
whose first line is `forge-audit-caps v1`, so an empty or truncated file can never read
as "no capabilities". Writes go to a temp file and are then renamed. Only successful
analyses are cached. A failure is re-run every time, so a dependency is never pinned as
unanalyzable.

**Key** (MD5 via `Digest`, over NUL-separated fields):
`forge-audit-inferred-v1`; the compiler identity; the dependency's exact
`Cmd_build.lib_path_env` prefix string (toolchain `PATH` plus `MARCH_LIB_PATH`); the
dependency's directory; the path and contents of every `.march` file under the
dependency (`march_files_under`); and the path and contents of every `.march` file in
every other lib directory on its `MARCH_LIB_PATH`. That last set comes from the same
`collect_transitive_deps` + `dep_to_lib_paths` walk `lib_path_env` does, in dev scope as
`lib_path_env` defaults to. It is what `check_all_cache_key`'s documented limitation
misses: a path dependency edited in place leaves the env string unchanged.

**Compiler identity** (`Cap_package.compiler_identity`): the resolved `march` path, its
`realpath`, `Digest.file` of the real executable, the global toolchain
(`~/.march/current`'s target) and `MARCH_STDLIB`. The last two cover a wrapper script
that execs through `current` (its bytes do not change when the active toolchain does)
and a swapped stdlib under the same binary. It is computed once per audit.

Collection prints nothing now. The old `eprintf` on a failed dependency moved into
reporting. So a hit and a miss print the same bytes, which the test asserts.

## 3. Unanalyzable dependencies and `--allow-unanalyzable`

**Behaviour change without the flag.** On origin/main, `--inferred` did not fail on an
unanalyzable dependency. It printed the error to stderr and used the **declared** set
(`caps_of_dir`) in its place, so an unanalyzable dependency with no `needs` showed as
`— no capabilities` and the audit passed. That is the conflation the design forbids,
and it did not match what the todo described ("loud, never 'no capabilities'", and
"the gate cannot be adopted until the graph checks cleanly"). It is also a regression
from the retired `forge cap deps`, which refused to record while any dependency was
`NOT ANALYZABLE`. The rule now, without the flag:

- `collect` returns unanalyzable dependencies separately
  (`collected.unanalyzable : (name * reason) list`), never inside `deps` with an empty
  or declared set.
- The check lists each one as `? name — NOT ANALYZABLE` plus the first 8 lines of the
  reason, and exits 1.
- `--record` refuses to write a baseline.

With `--allow-unanalyzable`:

- The check gates on the analyzable subset. An unanalyzable dependency's baseline entry
  is set aside, so it is reported neither as `dependency removed` nor as unchanged. The
  unanalyzable list is still printed on every run, tagged `(excluded from the gate by
  --allow-unanalyzable)`.
- `--record` writes the analyzable dependencies and carries over any set already
  recorded for an unanalyzable one. It prints what it left out.
- The flag without `--inferred` is an error, because declared mode never fails to
  analyze.

## Evidence

`forge/test/test_audit_inferred.ml`, 8 cases. Each runs `Cmd_audit.run` in-process
against a scratch project. The project's `march` is a fake shell script first on `PATH`
that logs every invocation, under an empty `MARCH_HOME`.

RED on origin/main: the four changed source files (`cap_package.ml`/`.mli`,
`cmd_audit.ml`, `forge/bin/main.ml`) were swapped back to `origin/main` by file copy,
with the flag-only cases removed because they cannot compile without the flag. Five of
five cases failed:

| Case | Red on origin/main | Green |
|---|---|---|
| old march is named, once | `Ok 0` (each dep fell back to declared caps) | one error naming the path, `march 0.2.0`, `0.3.0`; exactly one probe `caps` call; zero dep runs |
| uninstalled pin is an error | `Ok 0` via PATH `march` | error `… is not installed`, zero dep runs |
| hit skips march caps, same output | no cache dir written | miss runs `march caps`; hit runs neither it nor the probe; byte-identical stdout |
| invalidation | `warm: expected 1, got 2` | re-analyzes after editing the dep, a file only on its lib path, or the compiler script; warm again after |
| without the flag it fails | `record` returned `Ok` | `record` refuses, check exits 1, both list `bad — NOT ANALYZABLE` and the reason; no `bad — no capabilities` |
| `--allow-unanalyzable` gates on the rest | does not compile (no flag) | record 0, lock has `good` only; check 0 with bad listed; same tree without the flag: 1 |
| `--allow-unanalyzable` keeps a recorded set | does not compile | not reported as removed; re-record keeps `bad = ["IO.Process"]` |
| flag requires `--inferred` | does not compile | `Error` |

Real-compiler checks, run by hand on a scratch project: the opam `march 0.4.0` passes
the probe; a dependency with a real type error shows as `NOT ANALYZABLE` with the
compiler's `expected Int but got String` line, and the audit exits 1; the cache file is
written; the pinned pre-`caps` nightly gives the error quoted above.

`dune build --root . @forge/test/runtest`: exit 0, every forge suite green.
