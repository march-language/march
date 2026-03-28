# Bastion: Request Sandboxing for Tests

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Each test gets an isolated environment: a test `Conn`, a checked-out Depot connection running inside a transaction that rolls back after the test, a private Vault namespace, and an isolated PubSub. No test leaks state into another test. No global setup/teardown dance.

This generalizes the Phoenix/Ecto SQL sandbox pattern to all of Bastion's stateful subsystems, not just the database.

---

## The Sandbox

```march
mod Bastion.Test.Sandbox do
  # Check out an isolated environment for a test
  # Returns a SandboxEnv that can be passed to build_conn/1 and used directly
  fn checkout(app: Atom) -> SandboxEnv

  # Release the sandbox — rolls back the Depot transaction,
  # drops the Vault namespace, unsubscribes from PubSub
  fn release(env: SandboxEnv) -> :ok
end

type SandboxEnv = %{
  conn_base: Conn,            # pre-configured test Conn
  db: Depot.SandboxConn,      # transaction-wrapped DB connection
  vault: Vault.Namespace,     # isolated Vault namespace
  pubsub: Atom               # isolated PubSub instance for this test
}
```

---

## Setup in a Test Module

```march
mod MyApp.UserHandlerTest do
  import Bastion.Test
  import Bastion.Test.Sandbox

  setup do
    env = Bastion.Test.Sandbox.checkout(MyApp)
    {env: env}
  end

  teardown %{env: env} do
    Bastion.Test.Sandbox.release(env)
  end

  test "GET /users returns 200", %{env: env} do
    conn = env
      |> build_conn(:get, "/users")
      |> MyApp.Endpoint.call()

    assert conn.status == 200
    assert conn.resp_body |> String.contains?("Users")
  end

  test "POST /users creates a user", %{env: env} do
    conn = env
      |> build_conn(:post, "/users", %{name: "Alice", email: "alice@test.com"})
      |> MyApp.Endpoint.call()

    assert conn.status == 302
    # The insert happened in a sandboxed transaction — it is visible within this test
    user = Depot.query(env.db, "SELECT * FROM users WHERE email = $1", ["alice@test.com"])
    assert List.length(user) == 1
  end
end
```

`build_conn/2-4` builds a test `Conn` pre-wired with the sandbox's `db`, `vault`, and `pubsub`. The conn flows through the full endpoint pipeline — middleware, router, handler — in exactly the same code path as a real request.

---

## Depot Sandbox

The Depot sandbox checks out a connection from the pool, begins a transaction, and makes that single connection available for the duration of the test. All queries in that test (including those made inside handlers) run through this connection and therefore see each other's writes. The transaction is rolled back on `release` — nothing persists to the database.

```march
mod Depot.Sandbox do
  # Begin a sandboxed transaction on a pool connection
  fn checkout(pool: Depot.Pool) -> Depot.SandboxConn

  # Rollback and release the connection back to the pool
  fn release(conn: Depot.SandboxConn) -> :ok
end
```

The sandbox connection is passed through the request lifecycle via `conn.assigns.db`, the same as in production. Handlers, context modules, and Depot queries require no changes — they use whatever DB connection is in `conn.assigns.db`.

### Async Tests with Shared Sandbox

For tests that spawn actors or run concurrent operations, the sandbox connection can be "allowed" to additional processes:

```march
test "background job runs in sandbox", %{env: env} do
  # Allow MyApp.ExportWorker to use the same sandboxed connection
  Depot.Sandbox.allow(env.db, MyApp.ExportWorker)

  MyApp.ExportWorker.enqueue(env.db, %{user_id: "42", format: :csv})
  Process.sleep(100)   # wait for async work

  # Export result is visible in the same transaction
  results = Depot.query(env.db, "SELECT * FROM exports WHERE user_id = $1", ["42"])
  assert List.length(results) == 1
end
```

---

## Vault Sandbox

The Vault sandbox creates a private namespace (key prefix) for each test. All Vault reads and writes through the sandbox go to `__test_{test_id}:original_key` under the hood. The namespace is cleared on `release`.

```march
mod Vault.Namespace do
  # All puts/gets through this namespace are prefixed and isolated
  fn put(ns: Vault.Namespace, table: Table, key: k, value: v) -> :ok
  fn get(ns: Vault.Namespace, table: Table, key: k) -> Option(v)
  fn delete(ns: Vault.Namespace, table: Table, key: k) -> :ok
  fn clear(ns: Vault.Namespace) -> :ok
end
```

Application code that uses `Vault.put/:get` directly bypasses the namespace. Code that goes through `conn.assigns.vault` (the Bastion-idiomatic API) is automatically sandboxed.

---

## PubSub Sandbox

Each test gets an isolated `Bastion.PubSub.Local` instance. Broadcasts in one test never reach subscribers in another test, and broadcasts from the application under test are visible within the same test:

```march
test "user update broadcasts cache invalidation", %{env: env} do
  # Subscribe to the topic in this test's isolated PubSub
  Bastion.PubSub.subscribe(env.pubsub, "cache:invalidate:user:*")

  conn = env
    |> build_conn(:put, "/users/42", %{name: "Alice Updated"})
    |> MyApp.Endpoint.call()

  assert conn.status == 200

  # The handler called PubSub.broadcast — we can assert it arrived
  assert_receive {:pubsub_message, "cache:invalidate:user:42", :invalidate}
end
```

`assert_receive` is a test helper that checks the current actor's mailbox, matching on pattern within a configurable timeout.

---

## Session Sandbox

Test sessions are pre-populated via `put_session` helpers. No cookie jar or browser state needed:

```march
test "requires authentication", %{env: env} do
  conn = env
    |> build_conn(:get, "/dashboard")
    |> MyApp.Endpoint.call()

  assert conn.status == 302
  assert conn |> get_resp_header("location") == "/login"
end

test "shows dashboard when logged in", %{env: env} do
  user = insert!(env.db, MyApp.User, %{name: "Alice", role: "admin"})

  conn = env
    |> build_conn(:get, "/dashboard")
    |> put_session("user_id", user.id)
    |> MyApp.Endpoint.call()

  assert conn.status == 200
end
```

---

## Test Factories

The `insert!/3` helper is a test-only convenience that inserts a struct directly via the sandbox DB connection, bypassing changeset validation (for speed in test setup):

```march
mod Bastion.Test.Factory do
  # Insert a struct with given attrs, returning the inserted struct
  # Uses the sandbox DB connection; inserts are visible within the test's transaction
  fn insert!(db: Depot.SandboxConn, schema: t, attrs: Map(Atom, Any)) -> t

  # Build a struct without inserting (for unit tests)
  fn build(schema: t, attrs: Map(Atom, Any)) -> t
end

# Usage
test "lists all users", %{env: env} do
  _alice = insert!(env.db, MyApp.User, %{name: "Alice", email: "alice@test.com"})
  _bob   = insert!(env.db, MyApp.User, %{name: "Bob",   email: "bob@test.com"})

  conn = env
    |> build_conn(:get, "/users")
    |> MyApp.Endpoint.call()

  assert conn.status == 200
  assert conn.resp_body |> String.contains?("Alice")
  assert conn.resp_body |> String.contains?("Bob")
end
```

---

## Full Example: Controller Test

```march
mod MyApp.PostHandlerTest do
  import Bastion.Test
  import Bastion.Test.Sandbox
  import Bastion.Test.Factory

  setup do
    env = Bastion.Test.Sandbox.checkout(MyApp)
    user = insert!(env.db, MyApp.User, %{name: "Alice", email: "a@test.com", role: "user"})
    {env: env, user: user}
  end

  teardown %{env: env} do
    Bastion.Test.Sandbox.release(env)
  end

  test "authenticated user can create a post", %{env: env, user: user} do
    conn = env
      |> build_conn(:post, "/posts", %{title: "Hello", body: "World"})
      |> put_session("user_id", user.id)
      |> MyApp.Endpoint.call()

    assert conn.status == 302

    posts = Depot.query(env.db, "SELECT * FROM posts WHERE user_id = $1", [user.id])
    assert List.length(posts) == 1
    assert List.first(posts).title == "Hello"
  end

  test "unauthenticated user gets 302 to login", %{env: env} do
    conn = env
      |> build_conn(:post, "/posts", %{title: "Hello", body: "World"})
      |> MyApp.Endpoint.call()

    assert conn.status == 302
    assert get_resp_header(conn, "location") == "/login"
  end
end
```

---

## Open Questions

- How does the Vault namespace interact with global Vault tables that are not request-scoped (e.g., a global rate limit table)? Should there be an explicit opt-out for tables that should not be sandboxed?
- Should `insert!/3` apply default values from a schema definition, or require all fields to be passed explicitly?
- How does sandbox mode interact with `Bastion.PubSub.Redis` when running tests in CI? Should the sandbox adapter always be `Local`, overriding whatever the application configures?
