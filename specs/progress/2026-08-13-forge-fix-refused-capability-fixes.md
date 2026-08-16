# `forge fix` refused to apply the exact fixes it advertised for capability errors

**Status:** Landed (2026-08-13). Task 1 of the capability-UX plan
(`specs/2026-08-13-capability-ux-plan.md`).

## The bug

Both capability diagnostics — the missing-`needs` error and the missing-grant
error on `main` — print `` `forge fix` can apply this. `` in their message.
Neither one ever could.

`Cmd_fix.collect_all_fixes` returned `(fix_item list * bool)`, where the
`bool` (`has_errors`) was set whenever a collected diagnostic was
error-severity. `run` then refused with `"project has errors — fix them
before running \`forge fix\`"` whenever `has_errors` was true.

The condition is inverted. `parse_fix_line` returns `None` for any
diagnostic whose JSON `fix` field is `null` — i.e. for any diagnostic without
a machine-applicable fix — so a diagnostic can only reach `collect_all_fixes`'s
loop body, and therefore only set `has_errors`, if it **has** a fix.
`forge fix` refused precisely when it had safe, applicable work to do. A
genuinely unfixable error (one with no `fix` field) never set `has_errors` at
all and never blocked anything.

Both capability errors are error-severity and both carry a `fix`, so a
capability-incorrect module was exactly the case this gate blocked.

## The fix

- `lib/typecheck/typecheck.ml` (~line 13174): the missing-grant error on
  `main` now passes `~code:"cap_grant"` to `Err.error_with_fix`, matching how
  the missing-`needs` error already emits `cap_needs:<Cap>`. `error_with_fix`
  already accepted an optional `?code` — no new function was needed.
- `forge/lib/cmd_fix.ml`: `collect_all_fixes` no longer tracks or returns
  `has_errors`; its return type is now plain `fix_item list`. The call site
  in `run` no longer gates on it — a fix is only ever emitted alongside a
  diagnostic the compiler produced from a successfully parsed file, so a file
  that fails to parse contributes no fixes and nothing is applied to it. The
  gate protected nothing; removing it removes nothing but the refusal.

## Test

`forge/test/test_cap_sandbox.ml`: `test_forge_fix_applies_capability_errors`
writes a module with no `needs`/grant declarations at all
(`fn main() do println("hi") end`), runs `forge fix` against it end-to-end,
and asserts both that the command exits 0 and that the file now contains
`needs IO.Console` and `Cap(IO.Console)` in the grant parameter.

## Verification

```
dune build --root . bin/main.exe forge/bin/main.exe forge/test/test_cap_sandbox.exe
./_build/default/forge/test/test_cap_sandbox.exe -e
```

11 tests run, all green, including the new one. Full suite
(`scripts/run-tests.sh`) also run — see the task report for exact output.
