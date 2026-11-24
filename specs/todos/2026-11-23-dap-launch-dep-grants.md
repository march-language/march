# `march dap`: dependency grants are read once, at server start

Logged 2026-11-23 by ocap phase 6, Task 5 fix round 1 (review M4).

`march dap` installs the dependency grants (`--dep-grants FILE`, else `MARCH_DEP_GRANTS`) once,
when the server starts (`bin/main.ml`, the `dap` branch). A DAP `launch` request carries no
grants: `lib/dap/dap_session.ml` reads only `program` from its arguments, and `make_program`
receives only the path. So an editor that sets `MARCH_DEP_GRANTS` in a launch configuration's
`env` gets the grants of the server's own environment.

`march dap` also loads no `MARCH_LIB_PATH` modules, so a dependency's code is not on the
debugged program's path today. Grants matter only for a program that is itself inside a
granted root (the `test/dap` case).

What to do: pass the launch arguments to `make_program`, read `env.MARCH_DEP_GRANTS` (and
`MARCH_LIB_PATH`) from them, and reinstall the grants per launch with `Dep_grants.set_active`.
