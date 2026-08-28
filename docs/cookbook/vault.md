---
layout: cookbook
title: "Cookbook: Vault"
permalink: /docs/cookbook/vault/
scrollmd: true
---

# Vault

`Vault` is an in-memory key-value store; think ETS from Erlang. Values are shared across all actors in a process and persist across function calls. Good for caches, counters, session state, and coordination between concurrent tasks.

---

## Basic CRUD

```march
let v = Vault.new("my-store")

Vault.set(v, "name", "Alice")
Vault.get(v, "name")    -- Some("Alice")
Vault.get(v, "missing") -- None
Vault.drop(v, "name")
Vault.get(v, "name")    -- None
```

---

## Atomic update

`Vault.update` applies a function to the current value atomically: no race between get and set. The callback receives the unwrapped value and is only called when the key exists:

```march
let counter = Vault.new("counters")
Vault.set(counter, "hits", 0)

Vault.update(counter, "hits", fn n -> n + 1)
```

Multiple actors can call `update` concurrently without conflict. If the key doesn't exist, the update is a no-op.

---

## TTL (time-to-live)

`Vault.set_ttl` sets a key with an expiry. It takes `(store, key, value, ttl_secs)`; TTL is in **seconds**:

```march
Vault.set_ttl(v, "token", "abc123", 60)   -- expires after 60 seconds
```

---

## Namespacing

Different store names isolate keys completely:

```march
let user_cache    = Vault.new("users")
let session_store = Vault.new("sessions")
let rate_limits   = Vault.new("rate-limits")
```

---

## Listing keys

```march
let store = Vault.new("config")
Vault.set(store, "host", "localhost")
Vault.set(store, "port", "8080")

let keys = Vault.keys(store)    -- ["host", "port"]
```

---

## Complete example: request rate limiter

```march
mod RateLimit do
  needs IO.Mut
  needs IO.Console
  let store = Vault.new("rate-limit")

  fn check(client_ip : String, limit : Int) : Bool do
    let key = "hits:" ++ client_ip
    let count = match Vault.get(store, key) do
      None    -> 0
      Some(n) -> n
    end
    if count >= limit do
      false
    else
      if count == 0 do
        -- First hit: set with TTL to auto-expire the window after 60s
        Vault.set_ttl(store, key, 1, 60)
      else
        -- Subsequent hits: increment (key already exists)
        Vault.update(store, key, fn n -> n + 1)
      end
      true
    end
  end

  fn main(_cap_console : Cap(IO.Console), _cap_mut : Cap(IO.Mut)) do
    let ip = "192.0.2.1"
    let limit = 3
    println("hit 1: " ++ bool_to_string(check(ip, limit)))
    println("hit 2: " ++ bool_to_string(check(ip, limit)))
    println("hit 3: " ++ bool_to_string(check(ip, limit)))
    println("hit 4 (over limit): " ++ bool_to_string(check(ip, limit)))
  end
end
```
