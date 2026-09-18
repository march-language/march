# `[P1]` Tooling: Forge Build Tool

> **2026-09-18: triaged in `specs/2026-09-18-forge-p1-design.md`.** None of the
> three bullets below is a defect, and they are not one kind of work. The spec
> recommends splitting this file in three and re-prioritising: offline mode is
> **already designed and half landed**
> (`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md`, §3
> remaining); feature flags need a **language decision** before a design (three
> options laid out); and semantic semver checking is a **real correctness gap**
> in `forge publish` — signatures are compared as rendered strings, so an
> unannotated public function's return-type change reads as no change and a
> breaking release publishes as a patch. Priorities left to the owner.

- [ ] **Vendoring / explicit offline mode** (`forge vendor`, `--offline`) — partly mitigated by the CAS cache; no explicit story.
- [ ] **Optional dependencies / feature flags** — conditional deps and compile-time features (a language-design question).
- [ ] **Full AST-based semver-compat checking on publish** — `Resolver_api_surface` is text-heuristic; linearity/generic diffing needs compiler integration.

---
