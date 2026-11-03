# Shell: a node's HELLO triple could run commands on the operator's machine

Logged 2026-10-13. Found by a security review of the remote shell / observe
work (the R5 review packet's own question, "does the forge client trust the
node's output unsafely", answered yes for one field).

## The problem (`bin/shell_cmd.ml`, `lib/jit/repl_jit.ml`)

`HELLO` is the one unauthenticated verb besides `IDENT`; the protocol is
one-way authenticated (the node verifies the client's signed fragments, the
client verifies nothing about the node). The client took `triple:` from the
reply as a bare substring (`field`) and `shell_compile` spliced it into the
clang command line as ` --target=<triple>` with every path quoted and the
triple not, then ran it with `Sys.command` (`/bin/sh -c`). The in-process
link route did the same in its `clang -###` probe, before `run_argv`, and
fell back to the first site on failure. `Jit_emit.target_of_triple` only
prefix-matches the arch, so a triple that starts validly and ends in a
metacharacter reached one of the two. Space-free payloads pass `field`.

Locally this is same-uid (0600 socket, peer-uid check). `forge shell` also
reaches a remote host's `.shell` socket over an ssh tunnel
(`forge/lib/cmd_shell.ml`), so a compromised deployment host could pivot to
the operator's workstation on the first evaluated input. Confirmed against
the unfixed client with a fake unix-socket node: its injected command ran.

## The fix

- `Jit_emit.triple_ok`: allowlist `[A-Za-z0-9._-]+`, non-empty.
- `Repl_jit.shell_target_flags ~triple`: the builder, extracted from
  `shell_compile`; raises on a triple the allowlist rejects and
  `Filename.quote`s it besides, so both `Sys.command` sites are safe
  regardless of caller. `""`/`unknown` still mean no `--target`.
- `bin/shell_cmd.ml`: validates at the `HELLO` parse and refuses the
  session (exit 1, message), like the missing-challenge refusal.

## Tests

`test/test_shell_triple.ml` (compiler suite, `shell_triple`): the allowlist
on real triples and on a metacharacter corpus; the builder on a real triple,
on the sentinels, and refusing the corpus (proven to go red with the guard
removed). The shell goldens (`native_shell_session/node/skew`) prove a real
node's triple still compiles. The client-side refusal against a live
hostile node was checked by hand with a fake unix-socket server; no
automated fake-node fixture exists yet (a follow-up if the shell protocol
grows more node-supplied fields).
