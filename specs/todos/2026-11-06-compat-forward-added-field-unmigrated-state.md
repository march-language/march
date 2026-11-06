`[P2]` `@compat(forward)` / `@compat(any)`: an added field with no migration leaves the old-shaped state in place (suspected unsound, not reproduced)

Found by reading, while building derived migrations (M11). Not reproduced.

`docs/hot-code-reload.md` said that under `@compat(forward)` "existing actors use default
values from `init`" for added fields. Nothing implemented that: with no
`<actor>_migrate_state` in the patch, `march_reload.c` sets `migrate_fn = NULL`
(`resolve_migrate_fn` finds no `__migrate_<Actor>`), and the live actor keeps its old state
record while the new handlers read the new layout. If so, a read of an added field is past
the end of the old record.

M11 covers the constant-`init` case under every policy (the derived function exists, so the
state is migrated). What remains is an added field whose `init` value is not a constant, and
any change under `@compat(any)`.

To do: reproduce (v1 `state { a : Int }`, v2 `@compat(forward)` adding `b : String` read by a
handler, `init(x : String) { a: 0, b: x }` so nothing is derived; deploy and send the
handler's message, under ASAN). If confirmed: refuse the deploy unless a migration exists,
or remove the two policies. The doc now says the state keeps its old shape and recommends a
migration.
