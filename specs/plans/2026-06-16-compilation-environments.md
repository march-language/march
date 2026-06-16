# Compilation Environments & Per-Project Config

**Status:** Draft  
**Scope:** `forge/` (dep scoping) + `lib/` (compile-time config access) + `stdlib/config.march` (runtime env query)

---

## Overview

March programs need three things that are currently missing:

1. **Dep scoping** — production deps ship; dev/test deps don't. Dev and test need a shared non-prod bucket AND the ability to have their own exclusive deps.
2. **Compile-time config** — values baked into the binary at compile time, enabling dead-code elimination of debug paths.
3. **Runtime env query** — a stable `Config.env()` / `Config.is_prod()` so application code can branch on environment at runtime.

Item 3 already partially exists (`Config.env` reads `MARCH_ENV`). This spec finalises the dep scoping model and introduces the compile-time config system.

---

## 1. Environments

Three environments, selected by `MARCH_ENV`:

| Env | Default for | Meaning |
|-----|-------------|---------|
| `dev` | `forge build`, `forge run` | Local development |
| `test` | `forge test` | Automated test runs (CI or local) |
| `prod` | `forge build --release` | Deployed binary |

`MARCH_ENV` always overrides the default:

```bash
forge build                  # MARCH_ENV=dev  (implicit)
forge test                   # MARCH_ENV=test (implicit)
forge build --release        # MARCH_ENV=prod (implicit)
MARCH_ENV=prod forge build   # explicit override, no --release required
```

When `MARCH_ENV` is unset and no flag is given, `dev` is assumed.

---

## 2. Dep Scoping

### Four buckets

| Section | `dev` | `test` | `prod` | Resolved by `forge deps` | Notes |
|---------|-------|--------|--------|--------------------------|-------|
| `[deps]` | ✓ | ✓ | ✓ | always | Ships to prod consumers |
| `[dev-deps]` | ✓ | ✓ | — | always | Shared non-prod tooling |
| `[dev-only-deps]` | ✓ | — | — | always | Dev-exclusive (hot reload, dashboards) |
| `[test-deps]` | — | ✓ | — | always | Test-exclusive (test frameworks, fuzz libs) |

All four buckets are always fetched by `forge deps` so switching between environments is instant. Only the MARCH_LIB_PATH passed to the compiler changes per environment.

### forge.toml syntax

Both inline and section forms work, identical to the existing `[deps]` / `[dev-deps]` style:

```toml
[package]
name = "myapp"
version = "0.1.0"
type  = "app"

[deps]
http = { version = "~> 2.0" }

[dev-deps]
# Available in both dev and test — most common non-prod bucket.
devtools  = { version = "~> 0.1" }
depot_dev = { path = "../depot_dev" }

[dev-only-deps]
# Not available in test — live reload, dev dashboard, proxies.
live_reload = { git = "https://github.com/march-language/live_reload", branch = "main" }

[test-deps]
# Not available in dev — test frameworks, property testing, mocking.
march_test = { version = "~> 0.2" }
propcheck  = { version = "~> 0.1" }
```

Section form (dot-style) also works:

```toml
[test-deps.march_test]
version = "~> 0.2"

[dev-only-deps.live_reload]
git    = "https://github.com/march-language/live_reload"
branch = "main"
```

### Current state vs target state

`dev-deps` is currently parsed and stored in `Project.dev_deps` but is **not wired into MARCH_LIB_PATH** in either `cmd_build.ml` or `cmd_test.ml` — it is effectively a no-op today. This spec fixes that.

### `forge add` flags

| Flag | Writes to |
|------|-----------|
| _(none)_ | `[deps]` |
| `--dev` | `[dev-deps]` |
| `--dev-only` | `[dev-only-deps]` |
| `--test` | `[test-deps]` |

---

## 3. Compile-Time Config

### forge.toml config sections

```toml
[config]
# Defaults for all environments.
log_level      = "info"
debug_asserts  = false
api_base_url   = "https://api.example.com"

[config.dev]
log_level     = "debug"
debug_asserts = true
api_base_url  = "http://localhost:4000"

[config.test]
log_level = "warn"
# debug_asserts inherits false from [config]

[config.prod]
log_level = "error"
# api_base_url inherits from [config]
```

Resolution: env-specific section overrides `[config]` defaults. Missing keys fall back to `[config]`. Missing in both is a compile error.

Values are strings only. Booleans (`true`/`false`) and integers are parsed as strings and coerced by the accessor.

### March access syntax

Compile-time config is accessed via `Config.compile_get`:

```march
-- Returns a String, resolved at compile time.
let level = Config.compile_get("log_level")

-- Coercion helpers — also compile-time.
let debug = Config.compile_bool("debug_asserts")   -- Bool
let timeout = Config.compile_int("timeout_ms")     -- Int
```

`Config.compile_get` and its typed variants are **compiler builtins**, not runtime lookups. The compiler replaces the call site with the literal value from `forge.toml` during the typecheck/lower pass. Any `if` or `match` branching on the result is eligible for dead-code elimination.

Example — the debug block is compiled out in prod/test:

```march
if Config.compile_bool("debug_asserts") do
  assert check_invariant(state)
end
```

In prod (where `debug_asserts = false`), the entire `if` body is DCE'd.

### Error behaviour

- Accessing a key not present in `[config]` or the active env section → **compile error** with the missing key name.
- Accessing a key whose value cannot be coerced (e.g. `compile_int("log_level")`) → **compile error**.
- `[config.*]` sections referencing unknown env names (not `dev`, `test`, `prod`) → **compile warning**, ignored.

### No config files in v1

Config lives in `forge.toml` only. There are no `config/dev.march` files in v1. The Bastion configuration spec (`specs/bastion/configuration.md`) documents a richer `config/*.march` system for application-level runtime config; that is a separate concern and is not affected by this spec.

---

## 4. Runtime Env Query

The existing `Config` stdlib module already exposes `Config.env()`, `Config.is_dev()`, `Config.is_test()`, `Config.is_prod()` reading `MARCH_ENV` at runtime. That API is unchanged.

`Config.compile_env()` (new) returns the env baked in at compile time as a String literal — useful for embedding in logs or diagnostics:

```march
Logger.info("starting in env: " <> Config.compile_env())  -- "dev", "test", or "prod"
```

This is a `Config.compile_get` equivalent for the implicit `MARCH_ENV` key, not a runtime read.

---

## 5. Implementation Plan

### Phase 1 — Dep scoping (forge only, no compiler changes)

**`forge/lib/project.ml`**

- Add fields to `project`:
  ```ocaml
  test_deps     : (string * dep) list;
  dev_only_deps : (string * dep) list;
  ```
- Parse `[test-deps]` and `[dev-only-deps]` sections (both inline and dot-style), mirroring the existing `[dev-deps]` parser.
- Add to `load_from` record construction.

**`forge/lib/cmd_build.ml`** — `lib_path_env`

Currently `lib_path_env` only walks `proj.deps`. New logic:

```
dev build   → deps + dev_deps + dev_only_deps
test build  → deps + dev_deps + test_deps  (handled in cmd_test.ml)
prod build  → deps only  (--release flag sets env=prod)
```

Concretely: read `MARCH_ENV` (defaulting to `dev`) inside `lib_path_env`. For non-release builds, include `dev_deps + dev_only_deps` paths. For release builds, include only `deps` paths.

**`forge/lib/cmd_test.ml`** — `project_env`

Include `dev_deps + test_deps` paths in the MARCH_LIB_PATH built by `project_env`. Remove `dev_only_deps`.

**`forge/lib/cmd_deps.ml`** — `install_dep` loop

Extend the `all_deps` list to include `dev_deps + dev_only_deps + test_deps` (all four buckets always fetched). The per-bucket split is purely a MARCH_LIB_PATH concern, not a fetch concern.

**`forge/lib/cmd_add.ml`**

Add `--dev-only` and `--test` flags alongside the existing `--dev` flag. Route to the correct section in `forge.toml`.

**Tests**

- `forge/test/test_forge.ml`: add cases for each new section name, `forge add --dev-only`, `forge add --test`, verify correct MARCH_LIB_PATH construction per env.

### Phase 2 — Compile-time config (compiler + forge)

**`forge/lib/project.ml`**

- Add `config : (string * string) list` field — the resolved flat key→value map for the active env (merge `[config]` defaults with `[config.<env>]` overrides).
- Parse `[config]` and `[config.dev]` / `[config.test]` / `[config.prod]` sections.
- Resolve in `load_from` based on `MARCH_ENV`.
- Expose in `project` record so the compiler can read it via env var or a flag.

**Compiler integration**

The compiler receives compile-time config via the `MARCH_COMPILE_CONFIG` environment variable — a newline-separated `key=value` list serialised by forge before invoking the march binary. This keeps the compiler/forge interface clean (no new flags, no forge.toml parser in the compiler).

Alternatively: pass config values as `-D key=value` flags (similar to CPP defines). Either approach is valid; the `-D` flag approach is more explicit and easier to test in isolation.

**`lib/typecheck/typecheck.ml`** (or `lib/eval/eval.ml`)

Implement `Config.compile_get`, `Config.compile_bool`, `Config.compile_int`, `Config.compile_env` as special builtins resolved during typecheck/lower:

- During name resolution, treat `Config.compile_get(key)` specially.
- Substitute the literal value from the config map.
- Return type is always `String` (or `Bool` / `Int` for typed variants).
- Emit a compile error if the key is missing or the coercion fails.

**`stdlib/config.march`**

Add `compile_get`, `compile_bool`, `compile_int`, `compile_env` declarations as external builtins (no March body — resolved by the compiler).

**`syntax_reference.md`**

Add a section on compile-time config access.

**Tests**

- Compiler tests in `test/test_march.ml`: verify substitution, DCE, missing-key error, type-mismatch error.
- Forge tests: verify config section parsing, env override resolution, error on missing key.

---

## 6. Explicitly Out of Scope (v1)

- `config/*.march` files (runtime config files à la Elixir `config/runtime.exs`) — this is the Bastion app config story, not forge.
- Per-environment compiler optimization flags (`-O2` in prod, `-O0` in dev) — the March compiler build itself stays simple; optimization is a separate concern.
- `feature` flags / optional deps — a separate spec.
- `[config]` values as March expressions (only string literals in v1).
- Env-scoped `[patch]` overrides.

---

## 7. Open Questions

1. **Naming: `dev-only-deps` vs something shorter?** `dev-exclusive-deps` is more precise but longer. Could also be `dev-extra-deps`. Current proposal: `dev-only-deps`.
2. **Config delivery to compiler: env var vs `-D` flags?** `-D` flags are more explicit and compose better with direct `march` invocations outside of forge. Env var keeps the CLI cleaner. Recommendation: `-D key=value` repeated for each key, consistent with C preprocessor conventions.
3. **Should `forge test` also include `dev-only-deps`?** Current spec says no — if you want something in test, put it in `dev-deps` or `test-deps`. This keeps the environments meaningfully distinct.
