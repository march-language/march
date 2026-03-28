# Bastion: CSP Nonce Injection

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Content Security Policy (CSP) nonces make inline `<script>` and `<style>` tags safe by requiring a per-request secret that attackers cannot predict. Bastion generates a fresh cryptographic nonce for each request and automatically injects it into every `<script>` and `<style>` tag produced by the `~H` sigil. The corresponding `Content-Security-Policy` header is set on the response without any manual wiring.

Security by default, zero configuration required.

---

## How It Works

1. The CSP plug generates a per-request nonce at the start of the pipeline and stores it in `conn.assigns.csp_nonce`.
2. The `~H` compiler transforms `<script>` and `<style>` tags at compile time to inject the runtime nonce from the assign.
3. The CSP plug sets the `Content-Security-Policy` header on the response, referencing the same nonce.

All three steps happen automatically. Application code never touches the nonce directly.

---

## Per-Request Nonce

```march
mod Bastion.Security.CSP do
  # Plug: generates a nonce and attaches it to the conn
  # Called automatically when Bastion.Security.CSP is in the pipeline
  fn assign_nonce(conn: Conn) -> Conn do
    nonce = Crypto.random_bytes(16) |> Base.encode64()
    conn |> assign(:csp_nonce, nonce)
  end

  # Plug: sets the Content-Security-Policy header using the assigned nonce
  fn set_header(conn: Conn) -> Conn do
    nonce = conn.assigns.csp_nonce
    policy = build_policy(nonce, Bastion.Config.csp())
    conn |> put_resp_header("content-security-policy", policy)
  end

  # Convenience: combine nonce assignment + header in one plug
  fn protect(conn: Conn) -> Conn do
    conn |> assign_nonce() |> set_header()
  end
end
```

---

## ~H Sigil: Automatic Nonce Injection

The `~H` compiler rewrites `<script>` and `<style>` tags at compile time. Given:

```march
~H"""
<script>
  console.log("hello from #{user.name}");
</script>
<style>
  .highlight { color: red; }
</style>
<script src="/assets/app.js"></script>
"""
```

The compiler emits the equivalent of:

```march
~H"""
<script nonce={@csp_nonce}>
  console.log("hello from #{user.name}");
</script>
<style nonce={@csp_nonce}>
  .highlight { color: red; }
</style>
<script nonce={@csp_nonce} src="/assets/app.js"></script>
"""
```

`@csp_nonce` refers to `conn.assigns.csp_nonce`, threaded through the template context automatically. No template author needs to remember to add `nonce={@csp_nonce}` — it is injected by the compiler.

If a `<script>` or `<style>` tag already has a `nonce` attribute, the compiler leaves it unchanged (the explicit value wins).

---

## Islands Runtime Script

The `Islands.bootstrap_script/1` function (which emits the `<script>` tag for the client-side island runtime) also picks up the nonce automatically:

```march
mod Islands do
  fn bootstrap_script(conn: Conn) -> Html.Safe do
    nonce = conn.assigns[:csp_nonce] |> Option.unwrap_or("")
    Html.raw("""
    <script nonce="#{nonce}" type="module" src="/assets/march_islands.js"></script>
    """)
  end
end
```

---

## Default CSP Policy

When no custom policy is configured, Bastion uses a strict default:

```march
mod Bastion.Security.CSP do
  pfn build_policy(nonce: String, overrides: Map(String, String)) -> String do
    defaults = %{
      "default-src": "'self'",
      "script-src": "'self' 'nonce-#{nonce}'",
      "style-src": "'self' 'nonce-#{nonce}'",
      "img-src": "'self' data: https:",
      "font-src": "'self'",
      "connect-src": "'self' wss:",
      "worker-src": "'self' blob:",
      "wasm-unsafe-eval": "",          # required for WASM islands
      "frame-ancestors": "'self'",
      "base-uri": "'self'",
      "form-action": "'self'"
    }

    Map.merge(defaults, overrides)
      |> Map.to_list()
      |> List.map(fn {k, v} ->
        if v == "" then k else "#{k} #{v}" end
      end)
      |> String.join("; ")
  end
end
```

Note: `wasm-unsafe-eval` is required for WASM island execution. As the CSP spec adds more granular WASM directives, Bastion will adopt them.

---

## Configuration

Override individual directives in config. Unspecified directives use the defaults above:

```march
# config/config.march
fn csp() do
  %{
    # Allow images from a CDN
    "img-src": "'self' data: https://cdn.myapp.com",

    # Allow Stripe.js for payment forms
    "script-src": "'self' 'nonce-#{nonce}' https://js.stripe.com",

    # Allow Stripe Connect frame
    "frame-src": "https://js.stripe.com"
  }
end
```

For routes that need a different policy (e.g., a widget meant to be embedded in iframes):

```march
fn route(conn, :get, ["embed", "widget"]) do
  conn
  |> Bastion.Security.CSP.protect(overrides: %{
    "frame-ancestors": "*"
  })
  |> render_widget()
end
```

---

## Disabling CSP

CSP can be disabled globally (not recommended) or per-route:

```march
# Per-route opt-out (e.g., for a legacy page that uses inline event handlers)
fn route(conn, :get, ["legacy", "page"]) do
  conn
  |> Bastion.Security.CSP.disable()
  |> render("legacy.html")
end
```

Disabling CSP in production emits a `Bastion.Logger.warn` to make the opt-out visible in logs.

---

## Report-Only Mode

During migration of existing applications, use report-only mode to observe violations without blocking content:

```march
fn csp() do
  %{
    mode: :report_only,     # sets Content-Security-Policy-Report-Only instead of CSP
    report_uri: "/__bastion__/csp-reports"
  }
end
```

Violation reports are collected by the built-in `/__bastion__/csp-reports` endpoint and displayed in the dev dashboard. In production, configure `report_uri` to point to a real collector.

---

## Open Questions

- Should the `~H` compiler warn at compile time if it finds a `<script>` block with `unsafe-inline` in a string literal (which would indicate the nonce is being bypassed)?
- Should Bastion support CSP hashes (`'sha256-...'`) as an alternative to nonces for truly static inline scripts?
- When `mode: :report_only`, should violations also be surfaced in the request waterfall in the dev dashboard?
