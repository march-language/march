# Compiled-backend codegen bugs in HTTP handler paths (2026-06-29)


- [ ] **Home-route empty render** — compiled `GET /` returns a 200 with an EMPTY body (`octet-stream`); isolated to `list_popular(8)` / `home_page(...)`. `/packages` (also DB+HTML) and `registry_stats()` (in `forge test`) are fine. Likely the same monomorphization class as the publish-path fix above (a generic projection feeding a generic callee) — re-test against a fresh compiled forgepm binary before assuming it still reproduces.
