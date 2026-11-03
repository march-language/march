# Shell: automated fake-node fixture for hostile HELLO replies

Logged 2026-10-13, follow-up to
`specs/progress/2026-10-13-shell-hello-triple-command-injection.md`.

The client-side refusal of a node whose `HELLO` triple is not a target
triple (`bin/shell_cmd.ml`, the `triple =` field of the session record) is
covered only by a manual check. The builder layer
(`Repl_jit.shell_target_flags`) has unit tests, but a refactor of HELLO
parsing could drop the client guard without any test going red.

## What to add

A golden in `test/dune` that starts a fake unix-socket node (a small C or
OCaml fixture next to `test/shell_check.ml`) answering `HELLO` with
`triple:x86_64-unknown-linux-gnu;<command>` and a valid `session:`, then runs
`march --shell <sock> --shell-inputs <file>` against it. Expected: exit 1,
stderr names "HELLO triple is not a valid target triple", and the command's
marker file does not exist.

If the shell protocol grows more node-supplied fields, route them through
one HELLO parser with per-field validators and extend this fixture to cover
each.
