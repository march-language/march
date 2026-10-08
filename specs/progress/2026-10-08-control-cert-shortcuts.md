# Control-plane certificate role shortcuts

`forge cluster cert --control-agent` appends `Ctl.Agent:initiate` to the
explicit `--roles` list. `--control-candidate` also appends
`Ctl.Control:offer`. Combining the flags does not duplicate grants; existing
roles remain intact. These are permission shortcuts, not cluster configuration
or extra authority beyond the named roles.

Validation: all six Forge cluster tests pass, including the new role-composition
test; the built CLI's help advertises both flags. This closes only the shortcut
item in [the control wiring TODO](../todos/2026-09-28-dd-step12a-control-wiring.md).
