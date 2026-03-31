# `forge bastion gen auth` — Auth Generator Design

**Status:** Draft
**Scope:** Broad design — developer experience, generated artifacts, phasing, open questions

---

## Overview

`forge bastion gen auth` scaffolds a complete session-based authentication system into an existing Bastion application. The developer runs one command and gets: user registration, login/logout, email confirmation, password reset, remember-me, and the middleware to protect routes — all wired into their existing router and config.

The generator is opinionated about security defaults (bcrypt, constant-time comparison, rate-limited login, signed tokens) but the generated code lives entirely in the application, so developers own it and can modify anything.

```bash
forge bastion gen auth
```

No arguments for v1. One strategy (session-based), one schema (User), one context (Accounts). The generator detects the app name from `forge.toml` and derives module names accordingly.


## What It Feels Like

You run `forge bastion gen auth` in a fresh Bastion project. Forge prints:

```
* creating src/my_app/schemas/user.march
* creating src/my_app/schemas/user_token.march
* creating src/my_app/contexts/accounts.march
* creating src/my_app/handlers/auth/registration_handler.march
* creating src/my_app/handlers/auth/session_handler.march
* creating src/my_app/handlers/auth/confirmation_handler.march
* creating src/my_app/handlers/auth/password_reset_handler.march
* creating src/my_app/auth.march
* creating src/templates/auth/register.march.html
* creating src/templates/auth/login.march.html
* creating src/templates/auth/forgot_password.march.html
* creating src/templates/auth/reset_password.march.html
* creating src/templates/auth/confirm.march.html
* creating priv/depot/migrations/20260330120000_create_users.march
* creating priv/depot/migrations/20260330120001_create_user_tokens.march
* creating test/my_app/contexts/accounts_test.march
* creating test/my_app/handlers/auth/registration_handler_test.march
* creating test/my_app/handlers/auth/session_handler_test.march
* creating test/support/auth_test_helpers.march

The following files need manual changes:

  1. Add auth routes to src/my_app/router.march:

     fn route(conn, method, ["auth" | rest]) do
       conn
       |> MyApp.Auth.fetch_current_user()
       |> MyApp.AuthRouter.route(method, rest)
     end

  2. Add to your endpoint pipeline in src/my_app/endpoint.march:

     |> MyApp.Auth.fetch_current_user()

  3. Add the auth Vault table to your application start in src/my_app.march:

     {Vault, name: :auth_tokens, type: :set, read_concurrency: true}

  4. Configure password hashing in config/config.march:

     fn auth() do
       %{ hash_rounds: 12 }
     end

Run `forge depot.migrate` to create the users and user_tokens tables.
```

You run `forge depot.migrate`, start the server with `forge dev`, visit `/auth/register`, create an account, and you're logged in. The whole flow works. Then you go read the generated code to understand it, because it's all yours.


## Generated Artifacts

### Schemas

**`src/my_app/schemas/user.march`**

```march
mod MyApp.Schemas.User do
  import Depot.Gate

  fn schema() do
    Depot.Schema.define("users", %{
      fields: %{
        id:              (UUID,        %{primary_key: true, default: :gen_random_uuid}),
        email:           (String,      %{null: false}),
        hashed_password: (String,      %{null: false}),
        confirmed_at:    (UtcDatetime, %{nullable: true}),
        inserted_at:     UtcDatetime,
        updated_at:      UtcDatetime,
        -- virtual fields (not persisted)
        password:        (String,      %{virtual: true})
      }
    })
  end

  fn registration_gate(params) do
    cast(Depot.Schema.blank(schema()), params, ["email", "password"])
    |> validate_required(["email", "password"])
    |> validate_format("email", ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length("email", [LenMax(160)])
    |> validate_length("password", [LenMin(12), LenMax(72)])
    |> hash_password()
    |> unique_constraint("email", [ConstraintName("users_email_index")])
  end

  fn password_gate(user, params) do
    cast(user, params, ["password"])
    |> validate_required(["password"])
    |> validate_length("password", [LenMin(12), LenMax(72)])
    |> hash_password()
  end

  fn email_gate(user, params) do
    cast(user, params, ["email"])
    |> validate_required(["email"])
    |> validate_format("email", ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length("email", [LenMax(160)])
    |> unique_constraint("email", [ConstraintName("users_email_index")])
  end

  fn confirm_gate(user) do
    cast(user, %{"confirmed_at": DateTime.utc_now()}, ["confirmed_at"])
  end

  pfn hash_password(gate) do
    case get_change(gate, "password") do
      Some(password) ->
        gate
        |> put_change("hashed_password", March.Crypto.hash_password(password))
        |> delete_change("password")
      None -> gate
    end
  end
end
```

**`src/my_app/schemas/user_token.march`**

A separate table for all token types — email confirmation, password reset, remember-me session tokens. Each token row has a context field (`:session`, `:confirm`, `:reset_password`) and an expiry. This avoids storing long-lived secrets in cookies directly.

```march
mod MyApp.Schemas.UserToken do
  import Depot.Gate

  fn schema() do
    Depot.Schema.define("user_tokens", %{
      fields: %{
        id:          (UUID,        %{primary_key: true, default: :gen_random_uuid}),
        user_id:     (UUID,        %{null: false, references: references("users", %{on_delete: :delete_all})}),
        token:       (Binary,      %{null: false}),
        context:     (String,      %{null: false}),
        sent_to:     (String,      %{nullable: true}),
        inserted_at: UtcDatetime
      }
    })
  end
end
```

Token design: the raw token is a 32-byte random value. For session tokens, the raw token goes in the cookie and a SHA-256 hash is stored in the database. For email tokens, the raw token goes in the URL and the hash is stored. This means a database leak doesn't compromise active sessions or pending confirmations.

### Migrations

Two migrations. The users table has a unique index on email (citext for case-insensitive matching). The user_tokens table indexes on `(token, context)` for lookup and `(user_id)` for cleanup.

```march
mod Migrations.CreateUsers do
  import Depot.Migration

  fn up() do
    execute("CREATE EXTENSION IF NOT EXISTS citext")

    create_table("users", %{
      id:              (UUID,        %{primary_key: true, default: :gen_random_uuid}),
      email:           (:citext,     %{null: false}),
      hashed_password: (String,      %{null: false}),
      confirmed_at:    (UtcDatetime, %{null: true}),
      inserted_at:     (UtcDatetime, %{null: false}),
      updated_at:      (UtcDatetime, %{null: false})
    })

    create_index("users", [:email], %{unique: true, name: "users_email_index"})
  end

  fn down() do
    drop_table("users")
  end
end
```

```march
mod Migrations.CreateUserTokens do
  import Depot.Migration

  fn up() do
    create_table("user_tokens", %{
      id:          (UUID,        %{primary_key: true, default: :gen_random_uuid}),
      user_id:     (UUID,        %{null: false, references: references("users", %{on_delete: :delete_all})}),
      token:       (Binary,      %{null: false}),
      context:     (String,      %{null: false}),
      sent_to:     (String,      %{null: true}),
      inserted_at: (UtcDatetime, %{null: false})
    })

    create_index("user_tokens", [:token, :context])
    create_index("user_tokens", [:user_id])
  end

  fn down() do
    drop_table("user_tokens")
  end
end
```

### Context Module

**`src/my_app/contexts/accounts.march`**

This is the business logic layer. Handlers never touch the database directly — everything goes through Accounts. This makes testing straightforward and keeps handlers thin.

```march
mod MyApp.Accounts do
  import MyApp.Schemas.User
  import MyApp.Schemas.UserToken

  -- Registration
  fn register_user(params) -> Result(User, Gate)
  fn confirm_user(token: String) -> Result(User, :invalid_token)

  -- Authentication
  fn get_user_by_email_and_password(email, password) -> Option(User)

  -- Session tokens (DB-backed)
  fn generate_user_session_token(user) -> String
  fn get_user_by_session_token(token) -> Option(User)
  fn delete_user_session_token(token) -> :ok
  fn delete_all_user_tokens(user) -> :ok

  -- Email confirmation tokens
  fn generate_confirm_token(user) -> String
  fn confirm_user(token) -> Result(User, :invalid_token)

  -- Password reset tokens
  fn generate_password_reset_token(user) -> String
  fn get_user_by_reset_token(token) -> Option(User)
  fn reset_user_password(user, params) -> Result(User, Gate)

  -- User queries
  fn get_user(id) -> Option(User)
  fn get_user_by_email(email) -> Option(User)
end
```

Key behaviors:

- `get_user_by_email_and_password` uses constant-time password comparison even when the user doesn't exist (to prevent timing attacks that reveal which emails are registered).
- `register_user` validates via the registration gate, inserts, and returns the user or the gate with errors.
- Token generation creates 32 random bytes, stores SHA-256 hash in DB, returns URL-safe Base64 of the raw bytes.
- Token verification hashes the incoming token and looks up the hash. Expired tokens are rejected (session: 60 days, confirmation: 7 days, password reset: 1 hour).
- `delete_all_user_tokens` is called on password change to invalidate all sessions.


### Auth Module (Middleware)

**`src/my_app/auth.march`**

Two middleware functions that plug into the pipeline. These follow the typed middleware pattern — `fetch_current_user` loads from session into assigns, `require_auth` halts if nobody's there.

```march
mod MyApp.Auth do
  import Bastion.Conn

  fn fetch_current_user(conn: Conn(WithSession)) -> Conn(WithSession) do
    let token = get_session(conn, "user_token")
    let user = case token do
      Some(t) -> MyApp.Accounts.get_user_by_session_token(t)
      None -> None
    end
    conn |> assign(:current_user, user)
  end

  fn require_auth(conn: Conn(WithSession)) -> Conn(WithSession) do
    case conn.assigns.current_user do
      Some(_user) -> conn
      None ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect("/auth/login")
        |> halt()
    end
  end

  fn redirect_if_authenticated(conn: Conn(WithSession)) -> Conn(WithSession) do
    case conn.assigns.current_user do
      Some(_user) ->
        conn |> redirect("/") |> halt()
      None -> conn
    end
  end

  -- Helpers for handlers
  fn log_in_user(conn, user) -> Conn do
    let token = MyApp.Accounts.generate_user_session_token(user)
    conn
    |> renew_session()
    |> put_session("user_token", token)
  end

  fn log_out_user(conn) -> Conn do
    case get_session(conn, "user_token") do
      Some(token) -> MyApp.Accounts.delete_user_session_token(token)
      None -> :ok
    end
    conn
    |> clear_session()
    |> redirect("/")
  end

  pfn renew_session(conn) do
    -- Clear session data but keep CSRF token to prevent fixation
    let csrf = get_session(conn, "_csrf_token")
    conn
    |> clear_session()
    |> put_session("_csrf_token", csrf)
  end
end
```

### Handlers

Four handler modules, all thin. They parse params, call Accounts, render or redirect.

**`src/my_app/handlers/auth/registration_handler.march`**

```march
mod MyApp.Handlers.Auth.RegistrationHandler do
  import Bastion.Conn

  fn new(conn) do
    conn |> render("auth/register.march.html", %{gate: None})
  end

  fn create(conn) do
    let params = conn.body_params["user"]
    case MyApp.Accounts.register_user(params) do
      Ok(user) ->
        -- Generate confirmation token, deliver email
        let token = MyApp.Accounts.generate_confirm_token(user)
        MyApp.Notifier.deliver_confirmation(user.email, token)
        conn
        |> MyApp.Auth.log_in_user(user)
        |> put_flash(:info, "Account created. Please check your email to confirm.")
        |> redirect("/")
      Err(gate) ->
        conn |> render("auth/register.march.html", %{gate: Some(gate)})
    end
  end
end
```

**`session_handler.march`** — `new` (login form), `create` (authenticate + log in), `delete` (log out).

**`confirmation_handler.march`** — `new` (resend form), `create` (resend email), `confirm` (verify token from URL, set `confirmed_at`).

**`password_reset_handler.march`** — `new` (forgot form), `create` (send email), `edit` (reset form with token), `update` (set new password, invalidate all tokens).


### Auth Router

**`src/my_app/auth_router.march`**

```march
mod MyApp.AuthRouter do
  import Bastion.Router
  import Bastion.Conn

  -- Registration (redirect away if already logged in)
  fn route(conn, :get, ["register"]) do
    conn |> MyApp.Auth.redirect_if_authenticated()
         |> MyApp.Handlers.Auth.RegistrationHandler.new()
  end

  fn route(conn, :post, ["register"]) do
    conn |> MyApp.Auth.redirect_if_authenticated()
         |> MyApp.Handlers.Auth.RegistrationHandler.create()
  end

  -- Login
  fn route(conn, :get, ["login"]) do
    conn |> MyApp.Auth.redirect_if_authenticated()
         |> MyApp.Handlers.Auth.SessionHandler.new()
  end

  fn route(conn, :post, ["login"]) do
    conn |> Bastion.Security.RateLimit.limit(%{
              key: fn c -> c.remote_ip end,
              limit: 10,
              window: 60_000,
              vault_table: :auth_rate_limit
            })
         |> MyApp.Handlers.Auth.SessionHandler.create()
  end

  -- Logout
  fn route(conn, :delete, ["logout"]) do
    MyApp.Handlers.Auth.SessionHandler.delete(conn)
  end

  -- Confirmation
  fn route(conn, :get, ["confirm", token]) do
    MyApp.Handlers.Auth.ConfirmationHandler.confirm(conn, token)
  end

  fn route(conn, :get, ["confirm"]) do
    MyApp.Handlers.Auth.ConfirmationHandler.new(conn)
  end

  fn route(conn, :post, ["confirm"]) do
    MyApp.Handlers.Auth.ConfirmationHandler.create(conn)
  end

  -- Password reset
  fn route(conn, :get, ["reset-password"]) do
    MyApp.Handlers.Auth.PasswordResetHandler.new(conn)
  end

  fn route(conn, :post, ["reset-password"]) do
    MyApp.Handlers.Auth.PasswordResetHandler.create(conn)
  end

  fn route(conn, :get, ["reset-password", token]) do
    MyApp.Handlers.Auth.PasswordResetHandler.edit(conn, token)
  end

  fn route(conn, :put, ["reset-password", token]) do
    MyApp.Handlers.Auth.PasswordResetHandler.update(conn, token)
  end
end
```

### Templates

Functional templates that render HTML forms. Minimal styling — the generator produces semantic HTML with class names a developer can style. Forms auto-include CSRF tokens via Bastion's form handling.

Each template receives assigns and renders to an IOList. Error display reads from the gate's error map when present.

### Test Helpers

**`test/support/auth_test_helpers.march`**

```march
mod MyApp.AuthTestHelpers do
  fn register_user(attrs \\ %{}) do
    let defaults = %{
      "email" => "user_#{March.Crypto.random_hex(4)}@example.com",
      "password" => "valid_password_123"
    }
    let params = Map.merge(defaults, attrs)
    case MyApp.Accounts.register_user(params) do
      Ok(user) -> user
      Err(gate) -> panic("register_user failed: #{inspect(Depot.Gate.errors(gate))}")
    end
  end

  fn log_in_user(conn, user) do
    let token = MyApp.Accounts.generate_user_session_token(user)
    conn |> Bastion.Test.init_session() |> put_session("user_token", token)
  end
end
```


## Key Design Decisions

### Password Hashing: bcrypt via `March.Crypto`

Use bcrypt (via C FFI binding to the system `libcrypt` or a vendored implementation). Bcrypt is the pragmatic choice — well-understood, widely deployed, and the work factor is tunable via config. Argon2 is technically superior but adds a heavier C dependency; PBKDF2 is weaker for the same cost. The generated code calls `March.Crypto.hash_password/1` and `March.Crypto.verify_password/2`, so if the stdlib later adds argon2, users swap one function call.

This means the generator **depends on `March.Crypto` existing** with at least:

- `hash_password(plain) -> String` — bcrypt hash with configurable rounds
- `verify_password(plain, hash) -> Bool` — constant-time comparison
- `random_bytes(n) -> Binary` — CSPRNG
- `random_hex(n) -> String` — hex-encoded random bytes
- `sha256(data) -> Binary` — for token hashing
- `secure_compare(a, b) -> Bool` — constant-time string comparison
- `base64_url_encode(binary) -> String` — URL-safe encoding for tokens

### Token Architecture

All tokens follow the same pattern: generate random bytes, store a hash, compare hashes on verification. Three token contexts with different lifetimes:

| Context | Stored in | Lifetime | Invalidated on |
|---|---|---|---|
| `:session` | Cookie (raw) + DB (hash) | 60 days | Logout, password change |
| `:confirm` | Email URL (raw) + DB (hash) | 7 days | Confirmation, new token generated |
| `:reset_password` | Email URL (raw) + DB (hash) | 1 hour | Password change, new token generated |

Why store session tokens in the database at all? So that password changes can invalidate all sessions across all devices. The cookie holds the raw token; the DB holds the SHA-256 hash. Session lookup on each request is a single indexed query — fast enough that Vault caching isn't needed for v1, but could be added later.

### Integration with Existing Session Middleware

The auth system **builds on top of** the existing session middleware rather than replacing it. The session middleware handles cookie signing/encryption, CSRF, and session data storage. Auth adds one key to the session: `"user_token"`.

Flow on each request:
1. `Bastion.Middleware.load_session` — reads signed session cookie, populates `conn.assigns.session`
2. `MyApp.Auth.fetch_current_user` — reads `session["user_token"]`, looks up user from DB, puts into `conn.assigns.current_user`
3. Route-specific: `MyApp.Auth.require_auth` — halts with redirect if no current user

This means auth doesn't touch session configuration, signing salts, or cookie settings. It's a consumer of the session, not an owner.

### What the Generator Modifies vs. Creates

**Creates (new files):** Everything listed in the artifacts section. These are wholly owned by the application.

**Modifies (nothing, by design):** The generator does not patch existing files. Instead, it prints instructions for what the developer needs to add to their router, endpoint, and application supervisor. This is deliberate:

- Routers in March are pattern-matched functions, not DSL blocks. Injecting a new function clause into the middle of a `route/3` pattern match is fragile and error-prone.
- The endpoint pipeline is a single expression. Inserting middleware at the right position requires understanding the developer's existing pipeline.
- Application supervision trees are similarly bespoke.

Printing clear, copy-pasteable instructions is more reliable than code patching and lets the developer choose where auth fits in their existing structure.

**Future consideration:** A `forge bastion gen auth --apply` flag could attempt to patch files using AST transforms once the March compiler exposes a formatting/rewriting API.

### Rate Limiting

Login attempts are rate-limited by remote IP using the existing `Bastion.Security.RateLimit` module backed by Vault. The generated router applies rate limiting to `POST /auth/login` — 10 attempts per minute per IP. This is a sane default; developers can adjust or add per-email limiting.

The Vault table for rate limiting (`auth_rate_limit`) is added to the application supervisor alongside the auth tokens table.

### Email Sending: The Notifier Pattern

The generator creates a `MyApp.Notifier` module with functions like `deliver_confirmation/2` and `deliver_password_reset/2`. In v1, these **log the email to the console** rather than sending it. The function signatures accept email address and token, build the email body, and pass it to a configurable delivery backend.

```march
mod MyApp.Notifier do
  fn deliver_confirmation(email, token) do
    let url = "#{MyApp.Config.base_url()}/auth/confirm/#{token}"
    deliver(email, "Confirm your account", "Visit: #{url}")
  end

  fn deliver_password_reset(email, token) do
    let url = "#{MyApp.Config.base_url()}/auth/reset-password/#{token}"
    deliver(email, "Reset your password", "Visit: #{url}")
  end

  pfn deliver(to, subject, body) do
    -- v1: log to console. Replace with real delivery.
    March.Logger.info("EMAIL to=#{to} subject=#{subject}\n#{body}")
    Ok(%{to: to, subject: subject, body: body})
  end
end
```

This is intentionally minimal. A proper mailer abstraction (with adapters for SMTP, Postmark, SES, etc.) is out of scope for the auth generator. The notifier pattern gives developers a clear seam to plug in real delivery when they're ready.


## What's Missing from the Stdlib

### Required Before the Generator Ships

These don't exist yet and the generator cannot function without them:

1. **`March.Crypto` module** — password hashing (bcrypt via FFI), CSPRNG, SHA-256, constant-time comparison, Base64 URL encoding. This is the critical dependency. Without it, there's no secure auth.

2. **`citext` support in Depot migrations** — The migration uses Postgres `citext` for case-insensitive email storage. Depot needs to handle the `execute("CREATE EXTENSION ...")` escape hatch and recognize `:citext` as a column type (or at least pass it through to SQL).

3. **`Binary` field type in Depot** — Token storage uses raw binary (bytea). The schema and migration system need to support this type for `user_tokens.token`.

### Can Be Reused As-Is

- **Session middleware** — cookie signing, session data, CSRF. No changes needed.
- **BastionCookies** — signed/encrypted cookie primitives. Used by session middleware.
- **Config system** — layered config with runtime env var support. Auth config slots in naturally.
- **Vault** — rate limit counters and optional token caching.
- **Depot Gate/Schema/Repo** — the entire persistence layer works for auth schemas and queries.
- **`Bastion.Security.RateLimit`** — Vault-backed rate limiting for login.
- **CSRF protection** — forms already get CSRF tokens automatically.
- **`Bastion.Test`** — sandbox test mode with per-test transactions.

### Nice to Have (Not Blockers)

- **`March.Crypto.Bcrypt` vs `March.Crypto.Argon2`** — Ship with bcrypt, add argon2 later. The generated code calls generic `hash_password`/`verify_password` so the backing algorithm is swappable.
- **Mailer abstraction** — Would make the Notifier more useful out of the box, but console logging works for development and the seam is clean.
- **Flash messages** — The generated code calls `put_flash/3`. If Bastion doesn't have flash messages yet (session-stored, cleared after next read), this needs to exist.
- **`Bastion.Test.Conn`** — Test helpers for building fake request conns, dispatching them through routers, and asserting on responses. The auth handler tests need this.


## Phasing

### Phase 1: Foundation (build now)

Ship `March.Crypto` with the minimum surface area: `hash_password`, `verify_password`, `random_bytes`, `sha256`, `secure_compare`, `base64_url_encode`. This can use bcrypt via C FFI or, as a temporary measure, PBKDF2 from the existing stdlib if bcrypt bindings aren't ready. The API stays the same either way.

Ensure Depot supports `Binary` columns and raw SQL `execute()` in migrations.

Ensure `put_flash`/`get_flash` exist in Bastion's conn helpers.

### Phase 2: Generator (build next)

Implement `forge bastion gen auth` itself — the template engine that stamps out all the files listed above. The generator is "just" a code emitter; the interesting work is in the generated code, not the generator. Test by running it against a fresh `forge new` project and verifying the full flow works end-to-end.

### Phase 3: Polish (iterate)

- Add `--apply` flag to auto-patch router/endpoint/supervisor
- Real email delivery adapter (at least one: SMTP or a popular API provider)
- Optional "remember me" checkbox using longer-lived session tokens with a separate cookie
- Account settings page (change email, change password)
- Confirmation-required gate (block certain actions until email is confirmed)
- `forge bastion gen auth --api` variant that generates token-based auth for API-only apps


## Open Questions

1. **Password length max: 72 or 128?** Bcrypt truncates at 72 bytes. We validate at 72 to be honest about it. But should we pre-hash with SHA-256 to support longer passwords (the way Dropbox does)? Adds complexity but removes a surprising limitation.

2. **Email confirmation: required or optional?** Phoenix makes it optional — you can log in without confirming. We could generate a `require_confirmed` middleware that blocks unconfirmed users from certain routes. Default to optional for v1?

3. **Remember me: cookie or longer session?** Phoenix uses a separate "remember me" cookie with a longer-lived token. An alternative is just extending the session lifetime when the checkbox is checked. The separate cookie approach is more secure (the session cookie can stay short-lived) but adds complexity to the generated code.

4. **Should the generator create an Accounts context, or put auth functions directly on the User schema module?** Phoenix separates them (Accounts context + User schema). This separation is good for large apps but feels like ceremony for small ones. Since the generated code is editable, lean toward the Phoenix approach — it's easier to collapse later than to split apart.

5. **How should the generator handle existing files?** If `user.march` already exists (maybe from a previous `forge bastion gen schema`), should the generator refuse, merge, or overwrite? Refusing with a clear error message is safest for v1.

6. **Token cleanup:** Expired tokens accumulate in the database. Should the generator include a periodic cleanup task (a Vault-backed sweeper that runs `DELETE FROM user_tokens WHERE inserted_at < ...` on an interval)? Or leave that as an exercise?

7. **Multi-tenancy:** Some apps need per-org users. The generated schema is single-tenant. Should there be a `--tenant` flag, or is that a separate generator entirely?
