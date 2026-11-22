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

**Also a `restrict` budget (added 2026-11-19 by ocap phase 5,
specs/plans/2026-11-19-ocap-p5-restrict-plan.md, decision 10).** Design §9 lets a `restrict`
carry a spawn budget (`restrict IO.Spawn(max(4)) do ... end`): the tasks and actors started
inside the block's dynamic extent share one counter, separate from any outer budget, and a
spawn past it is refused with `ByRestrict(where)`. Since `IO.Spawn(max(n))` is not in the scope
language, a `restrict` can only admit or refuse spawning outright. When the form lands, the
counter belongs to the restrict's layer (`Authority.restrict_layer`), and scope values need it
too (`IO.Spawn(max(n))` as a literal scope expression; a computed `n` goes through
`Scope.build`). Add a conformance fixture beside `restrict_task_inherits`.
