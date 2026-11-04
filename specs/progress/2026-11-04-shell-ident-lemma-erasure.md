# `march shell` reported the stdlib's `impl Eq(List(a))` as differing from the node (2026-11-04)

Main went red after #1081 (reflection phase 3) merged. In the native goldens `shell_skew`,
`shell_skew_force`, `shell_link`, `shell_session` and `shell_leak`, every session reported one
more declaration differing from the node's build, "an impl of List.Eq".

## Cause

The shell's identity table (`lib/jit/shell_ident.ml`) hashes each declaration's source text from
its start to the next declaration's start.

- **The two sides hashed different declaration lists.**
  - The node's build computes its table before lemma erasure (`bin/main.ml`, "The shell's
    identity table").
  - The client was handed the program after `erase_lemmas`, which drops every unreferenced
    lemma declaration.
- **Why it only showed up now.** Phase 3 added the first stdlib lemmas, directly after
  `impl Eq(List(a))` in `stdlib/list.march`. On the client, that impl's region therefore ran on
  to the end of the module and took in the lemmas' text.

## Fix

The driver keeps the declarations from before erasure (`shell_client_decls`) and passes them to
`Shell_cmd.run ~ident_decls`. The client hashes the same regions the node did and still runs the
erased program.

## Verification

| Check | Result |
|---|---|
| `shell_link` on main before the fix | the extra "an impl of List.Eq" line (red) |
| the five shell goldens after the fix (every golden that runs `--shell`) | all pass |
