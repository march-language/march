# DONE 2026-10-07: B7.2, depend-mode source key

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §17, B7.2.

## The problem

The source-level cache key hashed every `.march` file in the entry's directory
and in every `MARCH_LIB_PATH` directory, because the resolver may auto-discover
any of them. Editing a sibling the build never loads therefore missed the
cache and ran the whole front end.

## The design: ccache's depend mode, made sound for the resolver

- **Record.** After a successful run, `bin/main.ml` records the load set the
  resolver actually produced (`resolve_imports`'s `user_files`) in
  `.march/cas/loadsets/<digest of entry + walked dirs>`. The record holds the
  walked directories, the loaded files, and a digest of every walked `.march`
  file that was *not* loaded.
- **Store.** The artifact and its diagnostics (B7.1) are also stored under the
  depend-mode key: entry bytes, the stdlib digest, and the path and bytes of each
  loaded file.
- **Look up.** The next run uses the depend-mode key if the record is still
  valid, and the full walk otherwise.

"Still valid" has to mean "the resolver would load the same set". The plan's
condition ("a listed file is missing or a new `.march` appears") is not enough
on its own. The resolver keeps a discovered module iff it is reachable by name
from kept sources or carries a global-effect declaration (`impl`, `interface`,
`derive`, `protocol`, `extern`, tests, …). So an edit to an *unloaded* sibling
can make it loaded, and the plan's rule would then serve a stale hit. A record
is valid only when all of these hold:

- the walked directories are the same, and no new `.march` file appeared in
  any of them;
- every loaded file still exists;
- every unloaded sibling whose bytes changed still parses, has no global-effect
  declaration (`Resolver.has_global_effect_decl`), and has no anchor (its module
  name, type and constructor names: `Resolver.provided_anchor_names`) among the
  tokens of the entry or a loaded file (`Resolver.referenced_name_tokens`). In
  other words, the resolver would prune it again.

Also, a **post-TIR hit now records the source-level entry**: artifact,
diagnostics, depend key and load set. A post-TIR hit has run the whole front end,
so it knows all of them. Before this, every build after one that fell back stopped
at the slower post-TIR hit until the next full compile.

## Tests

`test/test_cas_b7.ml`, run with `--timings` so a source-level hit (no stamps)
is told apart from a post-TIR hit (stamps up to `cas-hash`):

| Step | Expected |
|---|---|
| cold | full compile, prints 42 |
| warm | source-level hit |
| edit an unloaded sibling | **source-level hit** (a miss before) |
| that sibling gains an `interface` | not a source-level hit (record invalid) |
| edit the loaded sibling | full compile, prints 43 |
| a new sibling in the entry's directory shadows the `MARCH_LIB_PATH` module the entry imports | prints 63, not a stale 42 |

Red, each on a throwaway edit:
- with depend mode disabled, the "edit an unloaded sibling" step fails;
- with the new-file check removed, the shadowing test serves the stale `42`.
