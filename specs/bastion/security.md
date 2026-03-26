# Bastion: Security

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Philosophy

Bastion ships **secure by default**. Security features that protect against common web vulnerabilities are enabled out of the box — developers opt *out* when they have a specific reason to.

| Feature | Default | Opt-out/Configure |
|---|---|---|
| CSRF protection | ON for form submissions | Disable per-route with `skip_csrf` |
| Secure cookie flags | ON (HttpOnly, Secure, SameSite=Lax) | Override in session config |
| Template XSS escaping | ON (all expressions auto-escaped) | Use `raw()` for trusted content |
| Security headers | ON (full suite) | Override individual headers in config |
| Request size limits | ON (1MB default) | Configure in endpoint |
| HTTPS redirect (prod) | ON | Disable in config |
| CORS | OFF (same-origin only) | Explicit config required |
| Rate limiting | OFF | Explicit config required |

---

## CSRF Protection

Bastion generates a unique CSRF token per session, stored in the session cookie. All non-GET/HEAD/OPTIONS requests with content type `application/x-www-form-urlencoded` or `multipart/form-data` must include a valid token. JSON API requests (content type `application/json`) are exempt by default since they're protected by the same-origin policy.

```march
mod Bastion.Security.CSRF do
  # Middleware: verifies CSRF token on form submissions
  fn protect(conn: Conn(WithSession)) -> Conn(WithSession) do
    case conn.method do
      method when method in [:get, :head, :options] ->
        conn
      _ ->
        case get_req_header(conn, "content-type") do
          "application/json" -> conn  # JSON APIs exempt
          _ -> verify_csrf_token(conn)
        end
    end
  end

  # Get the current CSRF token for embedding in forms
  fn token(conn: Conn(WithSession)) -> String

  # Skip CSRF for a specific route (e.g., webhooks)
  fn skip(conn: Conn) -> Conn
end
```

Templates include the CSRF token automatically in forms:

```march
# The ~H template compiler automatically injects a hidden CSRF field
# into any <form> tag with method="post" (or put/patch/delete)
~H"""
<form method="post" action="/posts">
  <!-- Bastion auto-injects: <input type="hidden" name="_csrf_token" value="..."> -->
  <input type="text" name="title" />
  <button type="submit">Create</button>
</form>
"""
```

For routes that need to bypass CSRF (e.g., incoming webhooks from third parties):

```march
fn route(conn, :post, ["webhooks", "stripe"]) do
  conn
  |> Bastion.Security.CSRF.skip()
  |> MyApp.WebhookHandler.stripe(conn)
end
```

---

## Security Headers

Bastion ships a security headers middleware that sets protective headers on every response:

```march
mod Bastion.Security.Headers do
  fn defaults(conn: Conn) -> Conn do
    conn
    |> put_resp_header("x-frame-options", "SAMEORIGIN")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-xss-protection", "0")  # disabled in favor of CSP
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_resp_header("cross-origin-embedder-policy", "require-corp")
  end
end
```

Override per-route for specific needs:

```march
# Allow embedding as a widget
fn route(conn, :get, ["embed", "widget"]) do
  conn
  |> delete_resp_header("x-frame-options")
  |> render_widget()
end
```

---

## Content Security Policy (CSP)

Bastion ships a strict default CSP that is aware of its own architecture — specifically, it allows WASM execution for islands and the Bastion client runtime script:

```march
mod Bastion.Security.CSP do
  fn default_policy(conn: Conn) -> Conn do
    nonce = generate_nonce()
    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", String.join([
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}'",         # only nonced scripts
      "style-src 'self' 'nonce-#{nonce}'",           # only nonced styles
      "img-src 'self' data: https:",
      "font-src 'self'",
      "connect-src 'self' wss://#{conn.host}",       # WebSocket for channels
      "worker-src 'self' blob:",
      "wasm-unsafe-eval",                             # required for WASM islands
      "frame-ancestors 'self'",
      "base-uri 'self'",
      "form-action 'self'"
    ], "; "))
  end
end
```

The `wasm-unsafe-eval` directive is required for WASM island execution. As the CSP spec evolves with more granular WASM controls, Bastion will adopt them.

Customize the CSP in config:

```march
# config/config.march
fn csp_overrides() do
  %{
    "img-src": "'self' data: https://cdn.myapp.com",
    "connect-src": "'self' wss://#{host} https://api.stripe.com"
  }
end
```

---

## CORS (Explicit Configuration)

CORS is **off by default** (same-origin only). When building a JSON API consumed by a different origin, configure CORS explicitly:

```march
mod Bastion.Security.CORS do
  fn allow(conn: Conn, opts: CORSOpts) -> Conn
  # opts: %{
  #   origins: ["https://frontend.myapp.com"],
  #   methods: [:get, :post, :put, :delete],
  #   headers: ["content-type", "authorization"],
  #   max_age: 86400,
  #   credentials: true
  # }
end

# Usage — apply to API routes
fn route(conn, method, ["api" | rest]) do
  conn
  |> Bastion.Security.CORS.allow(%{
    origins: ["https://frontend.myapp.com"],
    methods: [:get, :post, :put, :delete],
    headers: ["content-type", "authorization"],
    credentials: true
  })
  |> MyApp.API.Router.route(method, rest)
end

# Handle preflight requests
fn route(conn, :options, ["api" | _rest]) do
  conn
  |> Bastion.Security.CORS.allow(%{origins: ["https://frontend.myapp.com"]})
  |> send_resp(204, "")
end
```

---

## Rate Limiting (Explicit Configuration)

Rate limiting is **off by default** and requires explicit configuration. It uses Vault for storing counters (fast, per-node, no external dependencies):

```march
mod Bastion.Security.RateLimit do
  # Sliding window rate limiter backed by Vault
  fn limit(conn: Conn, opts: RateLimitOpts) -> Result(Conn, Conn)
  # opts: %{
  #   key: fn(Conn) -> String,
  #   limit: Int,
  #   window: Int,           # time window in milliseconds
  #   vault_table: Atom
  # }
end

# Rate limit login attempts by IP
fn route(conn, :post, ["login"]) do
  case Bastion.Security.RateLimit.limit(conn, %{
    key: fn c -> c.remote_ip end,
    limit: 5,
    window: 60_000,          # 5 attempts per minute
    vault_table: :rate_limits
  }) do
    Ok(conn) -> MyApp.AuthHandler.login(conn)
    Error(conn) -> conn |> send_resp(429, "Too many requests")
  end
end
```

---

## Request Size Limits

Bastion enforces a maximum request body size to prevent denial-of-service via oversized payloads:

```march
# Default: 1MB max body size
fn call(conn) do
  conn
  |> Bastion.Middleware.max_body_size(1_048_576)   # 1MB default
  |> parse_body()
  |> MyApp.Router.route()
end

# Override per-route for file uploads
fn route(conn, :post, ["uploads"]) do
  conn
  |> Bastion.Middleware.max_body_size(50_000_000)   # 50MB for uploads
  |> handle_upload()
end
```

Requests exceeding the limit receive a `413 Payload Too Large` response before the body is fully read.

---

## HTTPS Redirect

In production, Bastion automatically redirects HTTP requests to HTTPS:

```march
mod Bastion.Security.SSL do
  fn force_ssl(conn: Conn) -> Conn do
    case {conn.scheme, Bastion.env()} do
      {:http, :prod} ->
        conn
        |> put_resp_header("strict-transport-security", "max-age=63072000; includeSubDomains")
        |> redirect("https://#{conn.host}#{conn.request_path}")
        |> halt()
      _ ->
        conn
    end
  end
end
```

HSTS is set with a two-year max-age. In development, SSL redirect is disabled automatically.
