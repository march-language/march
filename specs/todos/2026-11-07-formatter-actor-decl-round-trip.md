`[P3]` Formatter: actor declarations do not round-trip

Filed while fixing #1174 / #1175 (`specs/progress/2026-11-07-formatter-no-placeholder-text.md`).
`march fmt` now re-parses its output and refuses to write a file whose AST changed. A sweep
over copies of `test/**/*.march` with that check showed that most remaining refusals are
`actor` declarations. `emit_decl`'s `DActor` case (lib/format/format.ml) prints `state`,
`init`, the `on` handlers and `on_stop`. It does not print these `actor_def` fields:

- `actor_supervise` (a `supervise do ... end` block);
- `actor_mailbox` (`mailbox N policy`);
- `actor_compat` (`@compat`) and `actor_invariant` (`@invariant`);
- `actor_remote` (`@[remote]`);
- the actor's visibility.

Before the round-trip check, `march fmt` deleted these silently. Now such a file is reported
(`not formatted: the formatted output parses to a different program`) and left unchanged.
The actor cases in the sweep include `test/native/supervisor_*.march`,
`test/native/actor_*.march`, `test/cap_mock/cap_mock_supervised*.march` and
`test/hcr_migration_check/check_fns.march`.

Done when each field prints in its surface syntax and those files pass the round-trip check
(`check_roundtrip` in `test/test_fmt.ml` is the harness).
