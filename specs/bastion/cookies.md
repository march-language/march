# Bastion: Signed and Encrypted Cookies with Key Rotation

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Bastion provides two cookie security tiers built on `secret_key_base` from Config:

- **Signed cookies** — tamper-proof (HMAC-SHA256). The value is readable but any modification is detected.
- **Encrypted cookies** — tamper-proof *and* secret (AES-256-GCM). The value is opaque to the browser.

Key rotation is automatic: new keys sign/encrypt new cookies, but old keys are still accepted during a configurable grace period so rolling deploys don't invalidate existing sessions.

---

## Configuration

```march
# config/config.march
fn cookies() do
  %{
    secret_key_base: Env.fetch!("SECRET_KEY_BASE"),   # >= 64 bytes of entropy
    signing_keys: [
      # Most recent key first — used for new cookies
      %{key: Env.fetch!("COOKIE_KEY_V2"), inserted_at: "2026-03-01"},
      # Previous key — still accepted during grace period
      %{key: Env.fetch!("COOKIE_KEY_V1"), inserted_at: "2025-12-01"}
    ],
    key_rotation_grace_period: 7 * 24 * 60 * 60 * 1000   # 7 days in ms
  }
end
```

`secret_key_base` is the master secret. Individual signing and encryption keys are derived from it using HKDF with distinct salts — you never use `secret_key_base` directly as a cookie key.

---

## Signed Cookies

Signed cookies append an HMAC-SHA256 digest to the serialised value. The browser can read the value but cannot forge or modify it without the secret.

```march
mod Bastion.Cookies do
  # Set a signed cookie
  fn put_signed(conn: Conn, name: String, value: Any, opts: CookieOpts) -> Conn

  # Read and verify a signed cookie — returns None if missing or tampered
  fn get_signed(conn: Conn, name: String) -> Option(String)

  # Delete a cookie
  fn delete(conn: Conn, name: String) -> Conn
end

# Usage in a handler
fn remember_preference(conn, theme: String) do
  conn
  |> Bastion.Cookies.put_signed("user_pref", theme, %{max_age: 365 * 86400})
end

fn load_preference(conn) do
  case Bastion.Cookies.get_signed(conn, "user_pref") do
    Some(theme) -> conn |> assign(:theme, theme)
    None -> conn |> assign(:theme, "light")
  end
end
```

Wire order: `get_signed` tries keys newest-first; if the oldest key that matches is beyond the grace period the cookie is rejected as if it had been tampered with.

---

## Encrypted Cookies

Encrypted cookies use AES-256-GCM. The ciphertext is base64url-encoded and stored in the cookie. The browser sees an opaque blob — neither the value nor the key version leaks.

```march
mod Bastion.Cookies do
  # Set an encrypted cookie
  fn put_encrypted(conn: Conn, name: String, value: Any, opts: CookieOpts) -> Conn

  # Decrypt and return the value — returns None if missing, expired, or tampered
  fn get_encrypted(conn: Conn, name: String) -> Option(String)
end

# Encrypted cookies for sensitive data (e.g., flash messages with internal state)
fn set_flash(conn, level: Atom, message: String) do
  conn
  |> Bastion.Cookies.put_encrypted("_flash", %{level: level, message: message}, %{
    max_age: 60,        # flash lives for 60 seconds
    same_site: :strict
  })
end

fn read_flash(conn) do
  case Bastion.Cookies.get_encrypted(conn, "_flash") do
    Some(flash) -> {conn, Some(flash)}
    None -> {conn, None}
  end
end
```

---

## Key Derivation

Keys are never used raw. Bastion derives purpose-specific keys from `secret_key_base` using HKDF-SHA256:

```march
mod Bastion.Keys do
  # Derive a purpose-specific key from the master secret
  # Each purpose gets a different 32-byte key even from the same base
  fn derive(secret_key_base: String, purpose: String, salt: String) -> Bytes

  # Convenience: derive the active signing key for a given cookie name
  fn signing_key(config: CookieConfig, cookie_name: String) -> Bytes

  # Convenience: derive the active encryption key for a given cookie name
  fn encryption_key(config: CookieConfig, cookie_name: String) -> Bytes
end
```

Example derivation contexts:
- `"bastion cookie signing v1 _session"` → session signing key
- `"bastion cookie encryption v1 _flash"` → flash encryption key

The cookie name is included in the derivation context so a signing key for `_session` cannot be used to forge an `_admin` cookie even if an attacker somehow controls cookie names.

---

## Key Rotation

Key rotation works without a maintenance window:

1. Generate a new key and add it as the first entry in `signing_keys` / `encryption_keys`.
2. Deploy. New cookies are signed/encrypted with the new key.
3. Old cookies signed with previous keys are still verified during the grace period.
4. After `key_rotation_grace_period` has elapsed, remove the old key from config and redeploy.

```march
# Step 1: new key added to front, old key still present
fn cookies() do
  %{
    signing_keys: [
      %{key: "new-key-abc", inserted_at: "2026-04-01"},
      %{key: "old-key-xyz", inserted_at: "2026-03-01"}
    ],
    key_rotation_grace_period: 7 * 24 * 60 * 60 * 1000
  }
end

# Step 2: after grace period, drop old key
fn cookies() do
  %{
    signing_keys: [
      %{key: "new-key-abc", inserted_at: "2026-04-01"}
    ],
    key_rotation_grace_period: 7 * 24 * 60 * 60 * 1000
  }
end
```

Bastion emits a `Bastion.Telemetry` event when a cookie is verified with a non-primary key — this gives an observable signal to confirm the rotation window has passed before removing the old key.

---

## Cookie Options

```march
type CookieOpts = %{
  max_age: Int,           # seconds; omit for session cookie
  domain: Option(String), # default: current host
  path: String,           # default: "/"
  secure: Bool,           # default: true in prod, false in dev
  http_only: Bool,        # default: true
  same_site: :lax | :strict | :none   # default: :lax
}
```

Sensible defaults are applied automatically — you only override what you need.

---

## Session Store

`Bastion.Session` uses encrypted cookies under the hood by default. See [auth.md](auth.md) for the session store API and the `:depot` server-side session alternative.

---

## Open Questions

- Should key rotation be automatic on a schedule (via a Vault-backed background actor) rather than requiring a manual config redeploy?
- What is the right default grace period? 7 days is conservative; some deployments may want 1 day.
