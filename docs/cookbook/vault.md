---
layout: cookbook
title: "Cookbook: Vault"
permalink: /docs/cookbook/vault/
---

# Vault

`Vault` is an in-memory key-value store — think ETS from Erlang. Values are shared across all actors in a process and persist across function calls. Good for caches, counters, session state, and coordination between concurrent tasks.

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

`Vault.update` applies a function atomically — no race between get and set:

```march
let counter = Vault.new("counters")
Vault.set(counter, "hits", 0)

Vault.update(counter, "hits", fn n -> n + 1)
```

Multiple actors can call `update` concurrently without conflict.

---

## TTL (time-to-live)

Set a key to expire automatically after N milliseconds:

```march
Vault.set(v, "token", "abc123")
Vault.set_ttl(v, "token", 60000)   -- expires in 60 seconds
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
      Vault.update(store, key, fn n ->
        match n do
          None    -> 1
          Some(c) -> c + 1
        end
      )
      if count == 0 do
        Vault.set_ttl(store, key, 60000)
      end
      true
    end
  end

  fn handle(conn) do
    let ip = HttpServer.get_req_header(conn, "x-forwarded-for")
              |> Option.unwrap_or("unknown")
    if check(ip, 100) do
      HttpServer.text(conn, 200, "ok")
    else
      HttpServer.text(conn, 429, "rate limit exceeded")
    end
  end
end
```
