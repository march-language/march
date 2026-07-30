# March Configuration System — Design Proposal

**Status:** Draft
**Date:** 2026-03-25
**Scope:** Compile-time and runtime application configuration for the March language and `forge` build tool

---

## 1. Motivation

Every non-trivial application needs configuration — database URLs, feature flags, API keys, port numbers, log levels. The way a language handles configuration has an outsized effect on developer ergonomics, deployment safety, and security posture.

March sits at an interesting intersection: it has Elixir's expressive syntax and module system, ML's type safety, and compiles to native code via LLVM. This means March must solve configuration problems that span two worlds — the ergonomic, layered config of dynamic languages and the compile-time guarantees of systems languages.

This document surveys how five languages handle configuration, extracts the best ideas from each, and proposes a unified config system for March.

---

## 2. Survey of Existing Approaches

### 2.1 Elixir/Phoenix — The Gold Standard for Ergonomics

**Architecture:**

Elixir uses a layered file-based config system evaluated at two distinct phases:

```
config/config.exs        (compile-time, all environments)
  └─ import_config "#{config_env()}.exs"
       ├─ config/dev.exs   (compile-time, dev only)
       ├─ config/test.exs  (compile-time, test only)
       └─ config/prod.exs  (compile-time, prod only)

config/runtime.exs        (runtime, all environments, evaluated at boot)
```

Compile-time configs (`config.exs`, `dev.exs`, etc.) are evaluated during `mix compile` and their values are frozen into BEAM bytecode. The `runtime.exs` file was introduced in Elixir 1.11 to solve a critical problem: production secrets should never be required at build time.

**Compile-time vs runtime access:**

```elixir
# Compile-time — value baked into bytecode, validated at boot
@api_url Application.compile_env(:my_app, :api_url)

# Runtime — fetched dynamically on each call
def api_url, do: Application.fetch_env!(:my_app, :api_url)
```

**Deep merge semantics:** Keyword lists are recursively merged across config files. Later files override earlier ones, but nested keyword lists are merged rather than replaced. This is elegant but occasionally surprising — you cannot *remove* a key, only override it.

**Secrets:** The community convention is to read secrets from environment variables inside `runtime.exs` using `System.fetch_env!/1`, which fails loudly if the variable is missing. `.env` files (via the `Dotenvy` library) are used for local development.

**What works well:**
- Clean separation of compile-time structure from runtime secrets
- Environment-specific files are intuitive and discoverable
- `runtime.exs` runs consistently in dev, test, and prod
- Deep merge makes layering config feel natural
- `compile_env` catches stale compiled config at boot

**What the community dislikes:**
- The compile-time vs runtime distinction is a persistent source of bugs, especially for newcomers who use module attributes (compile-time) when they need runtime values
- Config has changed significantly across Elixir versions (`config/releases.exs` → `runtime.exs`), leaving old tutorials misleading
- Deep merge of keyword lists means you can't remove keys or replace a list wholesale
- Cross-application config dependencies can break Docker builds where apps compile independently

### 2.2 Rust — Explicit Layering with Type Safety

**Architecture:**

Rust has no built-in config system. The ecosystem has converged on composing several crates:

- **`config-rs`** — Layered configuration: defaults → file → env → CLI
- **`dotenvy`** — `.env` file loading for development
- **`envy`** — Deserialize environment variables directly into typed structs
- **`secrecy`** — Wrapper type that redacts secrets from logs and zeros memory on drop

```rust
let config = Config::builder()
    .set_default("server_port", 8080)?
    .add_source(File::with_name("config/default"))
    .add_source(File::with_name(&format!("config/{}", env)))
    .add_source(Environment::with_prefix("APP").separator("__"))
    .build()?
    .try_deserialize::<AppConfig>()?;
```

**Compile-time config** is entirely separate, using Cargo's `env!()` macro (embed env var at compile time), `#[cfg(feature = "...")]` for feature flags, `include_str!()` for file embedding, and `build.rs` scripts for dynamic generation. There is zero ambiguity about what's compile-time vs runtime.

**What works well:**
- Typed config via `serde` — invalid config is a compile error, not a runtime crash
- Clear, explicit layering with visible precedence
- `secrecy::Secret<T>` prevents accidental logging of sensitive values
- Feature flags give zero-cost compile-time conditional compilation
- No global state (config is a value you pass around)

**What the community dislikes:**
- Requires combining 3-4 crates for a complete solution
- `config-rs` has had maintenance gaps and forces key lowercasing
- No standard convention — every project invents its own config setup

### 2.3 Go — Pragmatic but Messy

**Architecture:**

Go's dominant config library is **Viper**, which provides layered config with this precedence: explicit `Set` > CLI flags > env vars > config files > remote KV stores > defaults.

```go
viper.SetDefault("port", 8080)
viper.SetConfigName("config")
viper.AddConfigPath(".")
viper.ReadInConfig()
viper.SetEnvPrefix("APP")
viper.AutomaticEnv()

port := viper.GetInt("port")
```

Go 1.16+ added `//go:embed` for compile-time file embedding. Build-time values are injected via `ldflags -X main.Version=1.0.0`.

**What works well:**
- Viper's layering is comprehensive and well-understood
- `//go:embed` is elegant for default configs
- `caarlos0/env` provides struct-tag-based env parsing similar to Rust's `envy`

**What the community dislikes:**
- Viper uses global mutable state, making testing painful
- Viper forces all keys to lowercase, violating JSON/YAML/TOML specs
- Viper bundles every format parser, inflating binaries (~12MB overhead)
- No type safety — `GetString`/`GetInt` return zero values on missing keys instead of errors
- The community is migrating toward **Koanf** (modular, no global state, respects key casing)

### 2.4 Gleam — Explicit and Type-Safe, but Minimal

**Architecture:**

Gleam has no macros and no built-in config system. `gleam.toml` is a project manifest (like `Cargo.toml`), not application config. Configuration is handled through explicit function calls:

```gleam
import envoy

pub fn load_config() -> Result(Config, ConfigError) {
  use db_url <- result.try(envoy.get("DATABASE_URL"))
  use port_str <- result.try(envoy.get("PORT"))
  use port <- result.try(int.parse(port_str))

  Ok(Config(database_url: db_url, port: port, debug: False))
}
```

There is no environment-specific config mechanism — projects use convention (checking an `APP_ENV` variable) and manually dispatch to different config modules.

**What works well:**
- Fully type-safe — config is just data, parsed into records
- No magic — configuration is explicit function calls
- Natural fit for 12-Factor apps

**What the community dislikes:**
- Boilerplate-heavy for large configs
- No built-in layering or merging
- No standard convention for dev/test/prod separation
- Missing compile-time config entirely (no macros, no embed)

### 2.5 Zig — Compile-Time Power

**Architecture:**

Zig's build system can expose options to source code via generated modules:

```zig
// build.zig
const options = b.addOptions();
options.addOption(bool, "enable_tracy", false);
options.addOption([]const u8, "version", "1.0.0");
exe.addOptions("build_options", options);
```

```zig
// src/main.zig
const opts = @import("build_options");
const version = opts.version;  // comptime known
```

`@embedFile` embeds file contents at compile time. Runtime config is done manually via `std.posix.getenv()` and file I/O — there's no standard library or convention for it.

**What works well:**
- `build_options` is elegant — typed compile-time config with CLI overrides
- `@embedFile` is simple and powerful
- Crystal-clear comptime vs runtime boundary (it's in the type system)

**What the community dislikes:**
- No runtime config story at all — every project rolls its own
- No standard config file format support in stdlib

### 2.6 12-Factor App Principles

The 12-Factor methodology mandates storing config in environment variables, ensuring the same artifact can run across environments without modification. Its strengths are simplicity and universality. Its weaknesses are lack of type safety, poor discoverability (which env vars are required?), flat namespace (no nesting), and difficulty managing dozens of variables.

Modern practice layers `.env` files for development on top of native env vars in production, with a typed validation step at application boot.

---

## 3. Design Principles for March

Drawing from the survey, these principles should guide March's config system:

1. **Compile-time and runtime are distinct and unambiguous.** Like Rust and Zig, there must be no confusion about when a value is resolved. Unlike Elixir, where this distinction caused years of bugs.

2. **Config is typed data, not stringly-typed.** Like Rust's `serde` deserialization and Gleam's records. Invalid config should fail at load time with clear errors, not silently return zero values.

3. **Layered config with explicit precedence.** Like Rust's `config-rs` and Elixir's file chain. Defaults < file < environment-specific file < env vars < CLI flags.

4. **Config is a value, not global state.** Like Rust and Koanf. Config should be a record you construct and pass, not a global mutable store like Viper.

5. **Secrets are first-class.** Like Rust's `secrecy` crate. Secret values should have a wrapper type that prevents accidental logging.

6. **Environment-specific config is discoverable.** Like Elixir's `config/{env}.exs` convention. The file structure should make it obvious what varies per environment.

7. **Works in both compiled and interpreted modes.** March has a REPL — config must work there too, not just in release builds.

8. **No macros required.** March doesn't have macros yet. The config system must work with functions, types, and the build tool alone.

---

## 4. Proposed Design

### 4.1 File Structure

A March project created with `forge new my_app` would generate:

```
my_app/
  forge.toml              # Project manifest (like gleam.toml / Cargo.toml)
  config/
    config.march          # Base config (all environments)
    dev.march             # Development overrides
    test.march            # Test overrides
    prod.march            # Production overrides
    runtime.march         # Runtime config (evaluated at boot, not compile)
  src/
    main.march
```

### 4.2 The `forge.toml` Manifest

Project metadata and build configuration. **Not** application config.

```toml
[project]
name = "my_app"
version = "0.1.0"
march = "0.1.0"

[dependencies]
http = "~> 1.0"
db = "~> 0.5"

[dev_dependencies]
test_helpers = "~> 0.2"

[build]
target = "native"          # "native" | "wasm"

[build.options]
enable_tracing = { type = "bool", default = false, description = "Enable tracing instrumentation" }
log_backend = { type = "string", default = "console", description = "Log output backend" }
```

Build options declared in `forge.toml` become available as compile-time constants (see §4.4).

### 4.3 Config Files — Compile-Time Layer

Config files use March syntax. They are **evaluated at compile time** by `forge` and produce a typed config record.

**`config/config.march`** — Base configuration:

```march
# config/config.march
# Base configuration for all environments

use Config

config :my_app,
  port: 4000,
  log_level: :info,
  pool_size: 10

config :my_app, :database,
  adapter: :postgres,
  pool_size: 10,
  timeout: 15_000

config :my_app, :cache,
  backend: :ets,
  ttl: 3600

# Import environment-specific overrides
import_config "#{Config.env()}.march"
```

**`config/dev.march`** — Development overrides:

```march
use Config

config :my_app,
  port: 4000,
  log_level: :debug,
  pool_size: 2

config :my_app, :database,
  hostname: "localhost",
  database: "my_app_dev"
```

**`config/prod.march`** — Production overrides:

```march
use Config

config :my_app,
  log_level: :warn,
  pool_size: 50

config :my_app, :cache,
  backend: :redis,
  ttl: 86_400
```

**Merge semantics:** Records are shallowly merged by default. Each `config` call merges its fields into the existing config for that key. To replace a value entirely (including nested records), use `config!` (the "bang" variant):

```march
# Merges with existing :cache config
config :my_app, :cache, ttl: 7200

# Replaces entire :cache config
config! :my_app, :cache,
  backend: :memory,
  ttl: 300
```

This avoids Elixir's problem of being unable to remove keys during merge.

### 4.4 Compile-Time Constants — `forge` Build Options

Build options declared in `forge.toml` are exposed as a generated module, similar to Zig's `@import("build_options")`:

```march
# In application code
use Forge.BuildOptions

# These are comptime constants — resolved during compilation
mod Tracing do
  if BuildOptions.enable_tracing do
    def instrument(func), do: trace_wrapper(func)
  else
    def instrument(func), do: func
  end
end
```

Build options are set via CLI:

```bash
forge build --enable-tracing=true --log-backend=syslog
```

For embedding files at compile time:

```march
# Embed file contents as a string constant
@embed_file "templates/default.html"
const default_template : String

# Embed file as bytes
@embed_file "assets/logo.png"
const logo_bytes : Bytes
```

The `@embed_file` attribute is resolved by `forge` at compile time. The file path is relative to the project root.

### 4.5 Runtime Config — `config/runtime.march`

The runtime config file is evaluated at application boot, **not** at compile time. This is where secrets and deployment-specific values belong.

```march
# config/runtime.march
# Evaluated at boot time. Environment variables are available.
# This file is included in forge releases.

use Config
use System

config :my_app, :database,
  url: System.fetch_env!("DATABASE_URL"),
  pool_size: System.get_env("POOL_SIZE", "10") |> Int.parse!()

config :my_app,
  port: System.get_env("PORT", "4000") |> Int.parse!(),
  secret_key: System.fetch_env!("SECRET_KEY") |> Secret.wrap()

# Environment-specific runtime behavior
if Config.env() == :prod do
  config :my_app, :cache,
    url: System.fetch_env!("REDIS_URL")
end
```

**Key constraints on `runtime.march`:**
- Cannot use `Forge` module functions (not available in releases)
- Cannot use `@embed_file` (that's compile-time)
- Can use `Config.env()` to check the build environment
- Is executed in all environments (dev, test, prod) — unlike Elixir's old `releases.exs`

### 4.6 Typed Config Access in Application Code

Config values are accessed through a typed API. March's type system ensures you get the right types at the call site.

**Defining a config schema (recommended):**

```march
mod MyApp.Config do
  use Config.Schema

  schema :database do
    field :url, String
    field :adapter, Atom, default: :postgres
    field :pool_size, Int, default: 10
    field :timeout, Int, default: 15_000
    field :hostname, String, default: "localhost"
    field :database, String
  end

  schema :cache do
    field :backend, Atom, default: :ets
    field :ttl, Int, default: 3600
    field :url, String, required: false
  end

  schema :root do
    field :port, Int, default: 4000
    field :log_level, Atom, default: :info
    field :pool_size, Int, default: 10
    field :secret_key, Secret(String), required: false
  end
end
```

This generates typed accessor functions and validates config at boot:

```march
# In application code — runtime access, fully typed
let db_config = Config.fetch!(:my_app, :database)
# db_config : MyApp.Config.Database
# db_config.url : String
# db_config.pool_size : Int

let port = Config.fetch!(:my_app, :root).port
# port : Int

# Pattern matching works
case Config.fetch(:my_app, :cache) do
  Ok(cache) -> start_cache(cache)
  Error(reason) -> log_warning("Cache not configured: #{reason}")
end
```

**Without a schema (quick and dirty):**

```march
# Untyped access — returns Dynamic, requires casting
let port = Config.get(:my_app, :port, default: 4000)
# port : Dynamic — you must cast it

let port = Config.get!(:my_app, :port) |> Dynamic.to_int!()
```

The schema approach is strongly recommended. It provides compile-time validation that all required fields are present, documentation of expected types, and IDE autocompletion.

### 4.7 The `Secret` Type

A wrapper type for sensitive values, inspired by Rust's `secrecy` crate:

```march
mod Secret do
  @opaque
  type Secret(a) = Secret(a)

  def wrap(value : a) -> Secret(a), do: Secret(value)

  def expose(secret : Secret(a)) -> a do
    let Secret(value) = secret
    value
  end

  # Debug/Display shows redacted value
  impl Display for Secret(a) do
    def to_string(_secret), do: "[REDACTED]"
  end

  impl Debug for Secret(a) do
    def inspect(_secret), do: "Secret([REDACTED])"
  end
end
```

Usage:

```march
# In runtime.march
config :my_app,
  api_key: System.fetch_env!("API_KEY") |> Secret.wrap()

# In application code
let config = Config.fetch!(:my_app, :root)
# config.api_key : Secret(String)

# Printing config won't leak the key
IO.inspect(config)
# => %{port: 4000, api_key: Secret([REDACTED]), ...}

# Must explicitly unwrap to use
let key = Secret.expose(config.api_key)
http_client.set_header("Authorization", "Bearer #{key}")
```

### 4.8 Environment Variables and `.env` Files

For local development, `forge` loads `.env` files automatically:

```
.env                  # Loaded in all environments (gitignored)
.env.dev              # Loaded only in dev
.env.test             # Loaded only in test
.env.example          # Checked into git — documents required vars
```

Precedence: actual env vars > `.env.{env}` > `.env`

```bash
# .env.example (committed to git)
DATABASE_URL=postgres://localhost/my_app_dev
SECRET_KEY=change-me-in-production
PORT=4000
REDIS_URL=redis://localhost:6379
```

`forge` loads `.env` files **before** evaluating `config/runtime.march`, so `System.fetch_env!` sees values from both real env vars and `.env` files.

In production (via `forge release`), `.env` files are **not** loaded — only real environment variables are used. This prevents accidental use of development secrets in production.

### 4.9 Compile-Time vs Runtime — Summary

| Mechanism | Phase | Mutable? | Use For |
|-----------|-------|----------|---------|
| `forge.toml` `[build.options]` | Compile | No | Feature flags, build modes |
| `@embed_file` | Compile | No | Templates, default configs, assets |
| `config/config.march` | Compile | No | App structure, non-secret defaults |
| `config/{env}.march` | Compile | No | Environment-specific structure |
| `config/runtime.march` | Boot | No* | Secrets, deployment-specific values |
| `Config.fetch!/2` | Runtime | No* | Accessing config in application code |

\* Values are set once at boot and don't change during the application's lifetime, though they can differ between deployments.

### 4.10 The `Config.env()` Function

Returns the current build environment as an atom:

```march
Config.env()  # => :dev | :test | :prod | custom atom
```

Set via:

```bash
MARCH_ENV=prod forge build
MARCH_ENV=test forge test    # forge test sets this automatically
forge run                    # defaults to :dev
```

Custom environments are supported:

```bash
MARCH_ENV=staging forge build
```

This requires a corresponding `config/staging.march` file if environment-specific compile-time config is needed.

### 4.11 Config in the REPL

When using March's REPL (`forge repl` or `march`), config works with these conventions:

- `MARCH_ENV` defaults to `:dev`
- `config/config.march` and `config/dev.march` are evaluated
- `config/runtime.march` is evaluated, with `.env` and `.env.dev` loaded first
- Config can be reloaded interactively:

```march
iex> Config.reload!()
# Re-evaluates runtime.march with current env vars
# => :ok
```

### 4.12 Config in `forge release`

When building a release:

1. `forge` compiles with the specified `MARCH_ENV` (default: `:prod`)
2. `config/config.march` + `config/{env}.march` are evaluated at compile time
3. `config/runtime.march` is bundled into the release
4. At boot, the release evaluates `runtime.march` before starting the application supervision tree
5. `.env` files are **not** loaded in releases

This mirrors Elixir's approach but without the historical baggage of `releases.exs`.

---

## 5. Layering and Precedence — Full Picture

The complete precedence order, from lowest to highest priority:

```
1. Schema defaults (field :port, Int, default: 4000)
2. config/config.march (base config)
3. config/{env}.march (environment-specific overrides)
4. config/runtime.march (runtime overrides, secrets)
5. Environment variables (when accessed directly via System.get_env)
```

For compile-time build options:

```
1. forge.toml [build.options] defaults
2. CLI flags (forge build --enable-tracing=true)
```

---

## 6. Validation and Error Handling

### 6.1 Boot-Time Validation

When a config schema is defined, `forge` validates the loaded config against it at application boot:

```march
# If DATABASE_URL is missing and the field is required:
# ** (Config.ValidationError) Missing required config field :url
#    in schema MyApp.Config.Database
#
#    This field has no default value. Set it in config/runtime.march:
#      config :my_app, :database, url: System.fetch_env!("DATABASE_URL")
#
#    Or set the DATABASE_URL environment variable.
```

### 6.2 Compile-Time Validation

`forge` can validate at compile time that:

- All `Config.fetch!` calls reference keys that exist in some config file or schema
- Schema field types match the values provided in config files
- Required fields without defaults are set in `runtime.march` (warning, not error — they might come from env vars)

### 6.3 The `config.check` Command

```bash
forge config.check
# Validates all config files parse correctly
# Checks schema coverage
# Reports which fields are set at compile-time vs runtime
# Warns about fields with no source

forge config.check --env=prod
# Validates prod config specifically
# Checks that all required fields have sources
```

---

## 7. Comparison with Surveyed Languages

| Feature | Elixir | Rust | Go | Gleam | Zig | **March** |
|---------|--------|------|----|-------|-----|-----------|
| Typed config | Partial | Via serde | No | Via records | Via structs | **Via schemas** |
| Compile/runtime separation | Confusing | Clear | Unclear | Runtime only | Clear | **Clear** |
| Layered merging | Deep merge | Builder pattern | Viper layers | Manual | Manual | **Shallow merge + `config!`** |
| Secret type | No | `secrecy` | No | No | No | **`Secret(a)`** |
| Env-specific files | Yes | Convention | Convention | Convention | No | **Yes (built-in)** |
| .env support | Via library | Via dotenvy | Via godotenv | Via library | No | **Built into `forge`** |
| Compile-time flags | Feature flags | Cargo features | Build tags | No | Build options | **`forge.toml` options** |
| File embedding | No | `include_str!` | `//go:embed` | No | `@embedFile` | **`@embed_file`** |
| Config validation | At boot | At deserialize | No | Manual | No | **Schema + boot + CLI** |
| REPL support | Yes | N/A | N/A | Limited | N/A | **Yes** |
| Global state | Yes | No | Yes (Viper) | No | No | **No** |

---

## 8. Detailed API Reference

### 8.1 `Config` Module

```march
mod Config do
  # Fetch a config value, raising on missing key
  def fetch!(app : Atom, key : Atom) -> a

  # Fetch a config value, returning Result
  def fetch(app : Atom, key : Atom) -> Result(a, Config.Error)

  # Get with a default (untyped)
  def get(app : Atom, key : Atom, default: a) -> a

  # Get the current environment
  def env() -> Atom

  # Reload runtime config (REPL only)
  def reload!() -> :ok

  # List all config for an app
  def all(app : Atom) -> Map(Atom, Dynamic)
end
```

### 8.2 `Config.Schema` Module

```march
mod Config.Schema do
  # Declare a config schema
  # Generates a record type and typed accessor
  macro schema(name : Atom, block)

  # Declare a field within a schema
  macro field(name : Atom, type : Type, opts \\ [])

  # Field options:
  #   default: value       — default value if not configured
  #   required: bool       — whether the field must be set (default: true if no default)
  #   validate: fn(a) -> bool — custom validation function
  #   doc: String          — documentation string
end
```

### 8.3 `System` Module (Config-Relevant Functions)

```march
mod System do
  # Get env var, raising if missing
  def fetch_env!(key : String) -> String

  # Get env var, returning Result
  def fetch_env(key : String) -> Result(String, :not_set)

  # Get env var with default
  def get_env(key : String, default : String) -> String
end
```

### 8.4 `Secret` Module

```march
mod Secret do
  @opaque
  type Secret(a)

  def wrap(value : a) -> Secret(a)
  def expose(secret : Secret(a)) -> a
  def map(secret : Secret(a), func : fn(a) -> b) -> Secret(b)
end
```

---

## 9. Migration Path and Future Work

### 9.1 Phase 1 — MVP (Current Proposal)

- Config files with `config/3` and `import_config`
- `runtime.march` for boot-time config
- `System.fetch_env!/1` for env vars
- `.env` file loading in dev
- `Config.fetch!/2` for runtime access

### 9.2 Phase 2 — Schemas and Validation

- `Config.Schema` for typed config records
- Boot-time schema validation
- `forge config.check` command
- `Secret(a)` wrapper type

### 9.3 Phase 3 — Advanced Features

- `@embed_file` for compile-time file embedding
- `Forge.BuildOptions` for compile-time constants
- Config providers (pluggable backends for Vault, AWS Secrets Manager, etc.)
- Hot config reloading for long-running services
- Config diffing (`forge config.diff --env=prod`)

### 9.4 Open Questions

1. **Should `config/3` use March syntax or a restricted DSL?** Using full March syntax in config files is powerful but means config files could have side effects. Elixir limits config files to the `Config` module's functions. March should probably do the same — config files can only call `config`, `config!`, `import_config`, `Config.env()`, and `System.*` functions.

2. **Should schemas be opt-in or required?** Opt-in is more pragmatic for small projects. Required schemas would catch more errors but add friction.

3. **How should config work with March's module system?** Should each module declare its own config schema, or should there be one central schema? Elixir uses app-level config with per-library keys. This seems like the right granularity.

4. **Should `Secret(a)` zero memory on drop?** In a GC'd or LLVM-compiled language, this is harder to guarantee than in Rust. Worth investigating LLVM's support for volatile writes to prevent optimization.

5. **What config file format for `runtime.march`?** Using March syntax means the file is evaluated as code. An alternative is TOML/YAML for runtime config (simpler, no code execution), but this loses the ability to do conditional logic (`if Config.env() == :prod`). The Elixir precedent of using language syntax is probably right.

---

## 10. Example: Complete Config for a Web Application

```
my_web_app/
  forge.toml
  config/
    config.march
    dev.march
    test.march
    prod.march
    runtime.march
  .env.example
  .env              (gitignored)
  src/
    main.march
    config.march    (schema definitions)
    router.march
    ...
```

**`forge.toml`:**

```toml
[project]
name = "my_web_app"
version = "1.0.0"
march = "0.1.0"

[dependencies]
phoenix = "~> 2.0"
ecto = "~> 4.0"
redis = "~> 1.0"

[build.options]
enable_live_reload = { type = "bool", default = false }
```

**`config/config.march`:**

```march
use Config

config :my_web_app,
  port: 4000,
  log_level: :info

config :my_web_app, :database,
  adapter: :postgres,
  pool_size: 10

config :my_web_app, :cache,
  backend: :ets,
  ttl: 3600

import_config "#{Config.env()}.march"
```

**`config/dev.march`:**

```march
use Config

config :my_web_app,
  log_level: :debug

config :my_web_app, :database,
  hostname: "localhost",
  database: "my_web_app_dev",
  username: "postgres",
  password: "postgres"
```

**`config/prod.march`:**

```march
use Config

config :my_web_app,
  log_level: :warn,
  pool_size: 50

config :my_web_app, :cache,
  backend: :redis
```

**`config/runtime.march`:**

```march
use Config
use System

if Config.env() == :prod do
  config :my_web_app, :database,
    url: System.fetch_env!("DATABASE_URL") |> Secret.wrap(),
    pool_size: System.get_env("POOL_SIZE", "20") |> Int.parse!()

  config :my_web_app,
    port: System.get_env("PORT", "4000") |> Int.parse!(),
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE") |> Secret.wrap()

  config :my_web_app, :cache,
    url: System.fetch_env!("REDIS_URL")
end

if Config.env() == :dev do
  config :my_web_app, :database,
    url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/my_web_app_dev")
end
```

**`src/config.march`:**

```march
mod MyWebApp.Config do
  use Config.Schema

  schema :root do
    field :port, Int, default: 4000, doc: "HTTP server port"
    field :log_level, Atom, default: :info
    field :pool_size, Int, default: 10
    field :secret_key_base, Secret(String), required: false
  end

  schema :database do
    field :url, Secret(String), doc: "Full database connection URL"
    field :adapter, Atom, default: :postgres
    field :pool_size, Int, default: 10
    field :hostname, String, default: "localhost"
    field :database, String, required: false
    field :username, String, required: false
    field :password, String, required: false
    field :timeout, Int, default: 15_000
  end

  schema :cache do
    field :backend, Atom, default: :ets
    field :ttl, Int, default: 3600
    field :url, String, required: false
  end
end
```

**`src/main.march`:**

```march
mod MyWebApp do
  use Config

  def start() do
    let config = Config.fetch!(:my_web_app, :root)
    let db = Config.fetch!(:my_web_app, :database)

    IO.puts("Starting on port #{config.port}")
    IO.puts("Database: #{db}")  # Secret fields show as [REDACTED]

    let db_url = Secret.expose(db.url)
    Database.connect!(db_url)

    Router.start(port: config.port)
  end
end
```

**`.env.example`:**

```bash
# Required in production
DATABASE_URL=postgres://user:pass@localhost/my_web_app_dev
SECRET_KEY_BASE=generate-with-forge-gen-secret
REDIS_URL=redis://localhost:6379

# Optional
PORT=4000
POOL_SIZE=10
```
