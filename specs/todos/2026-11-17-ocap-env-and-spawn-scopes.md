# ocap: `IO.Env(prefix)` and `IO.Spawn(max(n))` scopes

Logged 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 7;
design `specs/2026-11-10-object-capability-design.md` §6).

The design's scope language includes an environment-variable prefix on `IO.Env` and a spawn
budget on `IO.Spawn`. Neither is in the scope language yet (`lib/caps/cap_scope.ml`, the
parser in `stdlib/authority.march` and `runtime/march_authority.c`), so `needs IO.Env("APP_")`
does not parse and every `IO.Env` / `IO.Spawn` limit is all-or-nothing.

What to do: add both forms to the parser and formatter (and the tree-sitter grammar), give
`IO.Env` a name-kind check against the variable name, and give `IO.Spawn(max(n))` a counter in
the layer that spawns decrement (shared across the frame's dynamic extent). Keep the three
policies in step (`test/test_authority_differential.ml`).
