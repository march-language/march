# ocap: run-time path scopes are lexical (no realpath / O_NOFOLLOW)

Logged 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 7).

A path scope (`needs IO.FileRead("/srv/")` on `main` or a function, or a `MARCH_GRANT` path)
is checked at run time by comparing whole segments lexically: a relative target is resolved
against the current directory, then `.` and `..` are folded (`stdlib/authority.march`
`normalize` / `path_within`, `runtime/march_authority.c`). A symlink inside `/srv/` that
points at `/etc/passwd` is therefore admitted by `IO.FileRead("/srv/")`, and a rename between
the check and the open (TOCTOU) is not seen.

What to do: resolve the target (`realpath` of its existing prefix) before matching, or open
with `O_NOFOLLOW` / `openat2(RESOLVE_BENEATH)` relative to the scope's directory where the
platform has it (see `specs/todos/2026-11-13-macos-dir-symlinks-refused.md` for how
`File.Dir` already does this). Keep the interpreter, JS and C policies identical
(`test/test_authority_differential.ml`).
