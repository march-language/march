# Shell: declare the caps a fragment reaches through library code (R5.6)

Logged 2026-10-06; done 2026-10-07 (observe plan R5.6, design correction C4).

`march --shell` used to declare a fragment's capabilities from the
pre-bound cap names its input mentioned (`console`, `clock`, `intro`,
`debug`). A fragment that reached a capability through program or library
code declared nothing. A Depot query opens a socket (`IO.NetConnect`) and
draws randomness for SCRAM (`IO.Random`), yet was audited `caps:"-"`, and
`$MARCH_SHELL_POLICY` passed it whatever the policy said.

## What changed

- **Client** (`Repl_jit.shell_compile`): the caps are those of the C
  symbols the fragment's emitted code calls (`Llvm_builtins.called_c_symbols`
  through `Cap_symbols.cap_of_symbol`). This is the same channel a binary's
  `@__march_cap_*` markers use. A fragment carries every body it runs, so the
  set covers what the input reaches through any code.
  - The fragment gains an exported `__march_cap_manifest`: the caps, sorted,
    one per line.
  - The client signs exactly that set as `caps:` (`shell_fragment.sf_caps`).
- **Node** (`runtime/march_shell.c`): the policy is checked against the
  signed caps before loading, as before. After `dlopen`, the fragment's
  manifest must list exactly the signed caps:
  - `ERR cap_tamper` when it does not;
  - `ERR no_cap_manifest` when the fragment has none.

  This proves the signed line describes this fragment: a stale or broken
  client cannot run a fragment under a narrower declaration than its own
  code. It proves nothing about a signer who edits both, which is the deploy
  key's trust, as for `ACTIVATE`.

## Tests

- **`test/shell_check.ml` (node),** against hand-written fragments:
  - a manifest that matches the signed caps runs;
  - signed caps the manifest does not list are refused (`cap_tamper`);
  - signed caps narrower than the manifest are refused (`cap_tamper`);
  - a fragment without a manifest is refused (`no_cap_manifest`).
- **`test/shell/session.txt` (client):** `nap()` is a program function that
  reads the clock. It is refused with `policy IO.Clock` under a policy
  without `IO.Clock`, though the input names no capability. Before this
  change it ran.

Not done: the plan's manifest for `--hot-reload` deploy patches
(`ACTIVATE`), and `forge cap inspect`'s check that the manifest and the
per-cap markers agree. Both concern deploys, not the shell.
