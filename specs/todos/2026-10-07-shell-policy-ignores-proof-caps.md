# Shell policy does not gate `Actor.Debug` / `Actor.Introspect`

Logged 2026-10-07 (found while adding `--force`,
[progress](../progress/2026-10-07-shell-force.md)).

`$MARCH_SHELL_POLICY` is checked against a fragment's signed `caps:`, and
the node requires those to equal the fragment's `__march_cap_manifest`
(`runtime/march_shell.c`). That manifest comes from the C symbols the
emitted code calls (`lib/caps/cap_symbols.ml`). `Actor.Debug` and
`Actor.Introspect` are proof caps with no symbol, so they never appear in
it.

Repro: start the `native_shell_skew.out` node (`test/dune`) with a policy of
only `IO.Console`. Then `Actor.inspect_state(debug, Actor.pid_from_int(intro, 0), 500)`
runs and answers `Ok({ n: 1 })`, audited with `"caps":"-"`. `docs/observe.md`
says the policy lists "the capabilities an input may use", and `test/dune`'s
session test lists `Actor.Debug` in its policy as if it mattered.

What to do: add the proof caps an input's code reaches to the manifest.
They can come from the reached stdlib functions (`Actor.debug`,
`Actor.introspect`, or the runtime symbols `march_actor_inspect*` and the
`pid_of_int` family), or from Cap types in the fragment's TIR. Then a
policy without `Actor.Debug` refuses `inspect_state`. Add a negative case
to `test/shell/session.txt`. Part of the R5 security review's scope.
