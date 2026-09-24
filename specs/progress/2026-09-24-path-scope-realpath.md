# DONE 2026-09-24: `--cap-sandbox` write scopes are resolved with realpath at startup

First bullet of `specs/todos/2026-08-04-path-scope-followups.md` (the
`forge cap run`, scoped-marker and `csv_open` bullets stay open there).
Design: `specs/2026-08-04-path-scoped-capabilities-design.md` §5 and §6.

## Cause

Scope normalization is lexical by design (`Cap_scope.normalize`, no
filesystem access), because the build machine's filesystem is not the
deployment machine's. `bin/main.ml`'s `cap_sandbox_define` put the lexical
scope straight into the compile-time SBPL text as
`(allow file-write* (subpath "/tmp/x"))`. Seatbelt matches a subpath against
the path after symlink resolution, and on macOS `/tmp` is a symlink to
`/private/tmp`, so the rule matched nothing. Every write was denied, including
the in-scope ones. The only warning was a comment telling scope authors to
write the resolved path themselves.

## Fix

The resolution now happens in the runtime, on the machine that runs the
program:

- `bin/main.ml` (`cap_sandbox_define`): scoped write grants are no longer part
  of `MARCH_CAP_PROFILE`. The normalized scopes go into a second define,
  `MARCH_CAP_WRITE_SCOPES`, as comma-separated C string literals (C-escaped:
  quote, backslash and control bytes; UTF-8 passes through). An unscoped grant
  still emits `(allow file-write*)` into the base profile, as before.
- `runtime/march_runtime.c` (`march_sandbox_install`, macOS branch): when
  `MARCH_CAP_WRITE_SCOPES` is defined, each scope goes through
  `march_scope_resolve` and a `(allow file-write* (subpath "<resolved>"))`
  clause, SBPL-escaped, is appended to a copy of the profile before
  `sandbox_init`. The resolver:
  - calls `realpath` on the longest existing prefix, trimming one component
    at a time, then appends the rest lexically (`.` is skipped, `..` pops,
    never above `/`). This covers a scope that does not exist yet, which is
    the common case when the program creates the directory.
  - resolves a scope that is itself a symlink to its target (`realpath` does
    that).
  - falls back to the lexical text if nothing resolves or the result is
    longer than `PATH_MAX`. The first cannot happen for an absolute path,
    because `/` always exists.

  The cost is one `realpath` per scope (plus one per missing trailing
  component) at startup.

Linux is unchanged. Its `--cap-sandbox` is seccomp-bpf, which filters syscall
numbers, not paths. `IO.FileWrite` there is all-or-nothing
(`MARCH_CAP_DENY_WRITE` only when the capability is not held), so scopes are
never used at run time. The array is compiled only in the `__APPLE__` branch,
so the unused define has no effect on Linux.

The drift test (`test/test_cap_sandbox_profile.ml`) extracts the
`(version 1)` string from the binary. Its fixture declares no scopes, so the
base profile text it compares is unchanged.

## Evidence

Three new macOS cases in `test/test_cap_sandbox_runtime.ml` (suite
`cap_sandbox_runtime` in `run_compiler`). Each compiles a `--cap-sandbox`
program whose scope is spelled through `/tmp`, checks that the in-scope write
succeeds, and checks that the raw-C `sbx_probe_write_open` outside the scope
still gets `EPERM`:

1. Scope `/tmp/march_sbx_scope_<pid>_<rand>` (exists): `file_write` inside it,
   `dir_mkdir` of a new subdirectory, and a write into that subdirectory.
2. Scope `<dir>/notyet`, which does not exist at startup: `dir_mkdir` of the
   scope itself, then a write inside it.
3. Scope `<dir>/link`, a symlink to `<dir>/real`: a write through the link,
   and a check that it landed in `real/`.

- **Red:** with `bin/main.ml` and `runtime/march_runtime.c` swapped back to
  origin/main (test file kept), all three fail on their first in-scope
  assertion (`inscope = 0`, `mkdir = 0`, `inscope = 0`). The four existing
  macOS cases stay green.
- **Green:** with the fix, `cap_sandbox_runtime` passes all 7 macOS cases
  (the 5 Linux cases skip on macOS). `cap_sandbox_profile` (5) and
  `cap_scope` (18) also pass.

The Linux cases were not run locally (macOS host). Linux behaviour is
unchanged by construction, and CI's Linux leg runs this file.
