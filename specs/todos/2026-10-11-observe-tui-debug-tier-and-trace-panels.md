`[P3]` **`forge observe` TUI: state, messages and trace inside the Actor panel.**

R7 ([progress](../progress/2026-10-11-observe-r7-tui-watch-dumps.md)) shipped the
interactive view with the observe-tier panels. Left out, each for a stated reason:

- **Actor panel: `STATE` and `MESSAGES`.** Both are signed debug-tier requests
  (`~/.march/ed25519_secret.key`, a per-request nonce, a node policy file). The
  TUI shows `ACTOR <pid>` and points at `forge observe --state PID`. Wiring `t`/`m`
  keys needs the signing helper from `Cmd_observe.debug_request` called from the
  loop (with its 8 s ceiling, since the loop is single-threaded and a `STATE`
  waits on the actor), and `MESSAGES` itself is
  [still open](2026-10-05-observe-messages-verb.md).
- **Trace panel.** R8; the panel type has one constructor to add (see the header
  of `forge/lib/observe_tui.ml`).
- **Cluster panel on a real node.** It renders a `CLUSTER` reply, but no such verb
  exists yet ([cluster section](2026-10-02-observe-r1-cluster-section.md)); the
  panel is tested over a fixture of the planned shape, so its field names may
  need adjusting when the verb lands.
- **Actors panel counter sorts are cumulative** (`slices`, `msgs_in`, `msgs_out`):
  a windowed `TOP` holds the node's connection thread for the window on every
  refresh. A rate column could be computed client-side from two successive
  frames.
