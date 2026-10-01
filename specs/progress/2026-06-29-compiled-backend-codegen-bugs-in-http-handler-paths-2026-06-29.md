**Closed 2026-10-01 as stale (could not reproduce).** The todo said to re-test before assuming
the empty `GET /` body still reproduces. Re-test against current main (compiler built from
origin/main of 2026-09-30/10-01):

- Real forgepm (`/Users/80197052/code/forgepm`) cannot be built against current main: it
  depends on `bastion` (removed; `.march.html` preprocessor is `bastion lower`), plus a live
  Postgres for `list_popular`/`list_recent`/`registry_stats`. So the full handler was not run.
- Instead the isolated half the todo named, `Forgepm.Web.Pages.home_page(user, stats, popular,
  recent)`, was compiled standalone. `lib/forgepm/web/pages.march` was copied up to the end of
  `home_page` (the `IslandView.scripts()` and `SearchIsland.ssr` calls stubbed to `""`; the
  `~H` sigil is built into March, so no preprocessor is needed) and driven via `MARCH_LIB_PATH`
  from an entry that mirrors `web_router.march`'s `home`: `Ok(s) -> s | Err(_) -> {record}` for
  stats, `Ok(ps) -> ps | Err(_) -> []` for `popular` and `recent` (a generic projection feeding
  a generic callee, the suspected class), lists of 6-field package records.
- Result: interpreted, `--compile`, and `--compile --opt 2` all print a non-empty body that
  contains both `/packages/a` and `/packages/b`, and the all-`Err` path also renders non-empty.

Residual risk, stated plainly: this does not exercise `pkg_exec`/`Db.exec`/`rows_to_pkgs`
(row decoding feeding `list_popular`). If an empty `/` is seen again on a real compiled
forgepm build, file a fresh todo with a repro instead of reopening this one.

# Compiled-backend codegen bugs in HTTP handler paths (2026-06-29)


- [ ] **Home-route empty render** — compiled `GET /` returns a 200 with an EMPTY body (`octet-stream`); isolated to `list_popular(8)` / `home_page(...)`. `/packages` (also DB+HTML) and `registry_stats()` (in `forge test`) are fine. Likely the same monomorphization class as the publish-path fix above (a generic projection feeding a generic callee) — re-test against a fresh compiled forgepm binary before assuming it still reproduces.
