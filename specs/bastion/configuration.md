# Bastion: Configuration

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Config Files

Bastion follows a layered configuration model with distinct compile-time and runtime config:

| File | When evaluated | Purpose |
|---|---|---|
| `config/config.march` | Compile time | Base config, shared across environments |
| `config/dev.march` | Compile time | Development overrides |
| `config/test.march` | Compile time | Test overrides |
| `config/prod.march` | Compile time | Production overrides |
| `config/runtime.march` | App startup | Runtime config (reads env vars) |

Compile-time config affects compilation (e.g., which modules to include, optimization levels). Runtime config affects behavior at startup (e.g., database credentials, port number).

---

## Base Config

```march
# config/config.march
mod MyApp.Config do
  fn base() do
    %{
      port: 4000,
      secret_key_base: Env.fetch!("SECRET_KEY_BASE")
    }
  end

  fn db() do
    %{
      hostname: Env.get("DB_HOST", "localhost"),
      port: Env.get("DB_PORT", "5432") |> String.to_int(),
      database: Env.get("DB_NAME", "my_app_dev"),
      username: Env.get("DB_USER", "postgres"),
      password: Env.get("DB_PASS", ""),
      pool_size: 10
    }
  end

  fn session() do
    %{
      store: :cookie,
      key: "_my_app_session",
      signing_salt: "my_app_salt",
      secure: Env.get("MIX_ENV") == "prod"
    }
  end
end
```

---

## Runtime Config

```march
# config/runtime.march — evaluated at application start, NOT at compile time
mod MyApp.Config.Runtime do
  fn load() do
    %{
      port: Env.get("PORT", "4000") |> String.to_int(),
      secret_key_base: Env.fetch!("SECRET_KEY_BASE"),
      db: %{
        hostname: Env.fetch!("DB_HOST"),
        port: Env.get("DB_PORT", "5432") |> String.to_int(),
        database: Env.fetch!("DB_NAME"),
        username: Env.fetch!("DB_USER"),
        password: Env.fetch!("DB_PASS"),
        pool_size: Env.get("DB_POOL_SIZE", "10") |> String.to_int()
      },
      bastion: %{
        env: :prod,
        log_level: Env.get("LOG_LEVEL", "info") |> String.to_atom(),
        log_format: :json
      }
    }
  end
end
```

---

## Environment Selection

Forge uses the `MARCH_ENV` environment variable to select the compile-time configuration:

```bash
forge dev         # MARCH_ENV=dev  (default)
forge test        # MARCH_ENV=test
MARCH_ENV=prod forge build --release
```

`Bastion.env()` returns the compiled-in environment (`:dev`, `:test`, or `:prod`). This is baked into the binary at compile time and cannot be changed at runtime.

---

## forge.toml

Project-level configuration lives in `forge.toml`:

```toml
[package]
name = "my_app"
version = "0.1.0"

[dependencies]
bastion = "0.1.0"
depot = "0.1.0"

[js_deps]
# JavaScript dependencies for WASM island bundling
chart_js = "4.4.0"

[hooks]
# Run external tools as part of the build
before_build = "npx tailwindcss -i src/css/app.css -o priv/static/css/app.css --minify"
dev_watch = "npx tailwindcss -i src/css/app.css -o priv/static/css/app.css --watch"

[bastion.security]
warn_on_raw_html = true   # default: true in dev, false in prod
```
