# Bastion: Testing

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Bastion provides test helpers that let developers test their web application without starting an HTTP server. Tests run in-process, executing the full middleware pipeline and routing against simulated requests. This is fast (no network overhead) and deterministic.

---

## HTTP Request Testing

The primary test module simulates HTTP requests through the application:

```march
mod MyApp.RouterTest do
  import Bastion.Test
  import Bastion.Test.Conn

  fn test "GET / returns the home page"() do
    conn = build_conn(:get, "/")
    |> MyApp.Endpoint.call()

    assert conn.status == 200
    assert conn.resp_body |> String.contains("Welcome")
    assert get_resp_header(conn, "content-type") == "text/html; charset=utf-8"
  end

  fn test "GET /users/:id returns user JSON"() do
    user = TestFixtures.create_user(%{name: "Alice"})

    conn = build_conn(:get, "/api/users/#{user.id}")
    |> put_req_header("accept", "application/json")
    |> MyApp.Endpoint.call()

    assert conn.status == 200
    body = JSON.decode(conn.resp_body)
    assert body.name == "Alice"
  end

  fn test "POST /users requires authentication"() do
    conn = build_conn(:post, "/users")
    |> put_req_body(JSON.encode(%{name: "Bob", email: "bob@test.com"}))
    |> put_req_header("content-type", "application/json")
    |> MyApp.Endpoint.call()

    assert conn.status == 401
  end

  fn test "POST /users creates a user when authenticated"() do
    user = TestFixtures.create_user(%{role: :admin})

    conn = build_conn(:post, "/users")
    |> put_req_body(JSON.encode(%{name: "Bob", email: "bob@test.com"}))
    |> put_req_header("content-type", "application/json")
    |> authenticate_as(user)      # test helper that sets session
    |> MyApp.Endpoint.call()

    assert conn.status == 201
  end
end
```

---

## Conn Builder API

```march
mod Bastion.Test.Conn do
  # Build a simulated request
  fn build_conn(method: Atom, path: String) -> Conn
  fn build_conn(method: Atom, path: String, body: String) -> Conn

  # Set request properties
  fn put_req_header(conn: Conn, key: String, value: String) -> Conn
  fn put_req_body(conn: Conn, body: String) -> Conn
  fn put_req_cookie(conn: Conn, key: String, value: String) -> Conn
  fn put_query_params(conn: Conn, params: Map(String, String)) -> Conn

  # Auth helpers
  fn authenticate_as(conn: Conn, user: User) -> Conn  # injects session with user
  fn with_api_token(conn: Conn, token: String) -> Conn

  # Response assertions
  fn assert_status(conn: Conn, status: Int) -> Conn
  fn assert_header(conn: Conn, key: String, value: String) -> Conn
  fn assert_json(conn: Conn, expected: Map) -> Conn
  fn assert_html_contains(conn: Conn, text: String) -> Conn
  fn assert_redirected_to(conn: Conn, path: String) -> Conn
end
```

---

## Middleware Pipeline Testing

Test individual middleware functions or sub-pipelines in isolation:

```march
mod MyApp.MiddlewareTest do
  import Bastion.Test.Conn

  fn test "CSRF protection rejects form POST without token"() do
    conn = build_conn(:post, "/submit")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_body("name=test")
    |> Bastion.Middleware.parse_body()
    |> Bastion.Middleware.load_session(test_session_config())
    |> Bastion.Security.CSRF.protect()

    assert conn.status == 403
    assert conn.halted == true
  end

  fn test "CSRF protection allows JSON API requests"() do
    conn = build_conn(:post, "/api/data")
    |> put_req_header("content-type", "application/json")
    |> put_req_body(JSON.encode(%{key: "value"}))
    |> Bastion.Middleware.parse_body()
    |> Bastion.Middleware.load_session(test_session_config())
    |> Bastion.Security.CSRF.protect()

    assert conn.halted == false
  end

  fn test "rate limiter blocks after threshold"() do
    conn = build_conn(:post, "/login")
    |> put_remote_ip("1.2.3.4")

    # First 5 requests succeed
    List.each(1..5, fn _ ->
      result = Bastion.Security.RateLimit.limit(conn, %{
        key: fn c -> c.remote_ip end,
        limit: 5,
        window: 60_000,
        vault_table: :test_rate_limits
      })
      assert result |> Result.is_ok()
    end)

    # 6th request is blocked
    result = Bastion.Security.RateLimit.limit(conn, %{
      key: fn c -> c.remote_ip end,
      limit: 5,
      window: 60_000,
      vault_table: :test_rate_limits
    })
    assert result |> Result.is_error()
  end
end
```

---

## WASM Island Testing

Island logic can be tested in pure March without a browser. Since islands use the `init/update/view` pattern, each function is independently testable:

```march
mod MyApp.Islands.SearchBarTest do
  import Bastion.Test.Island

  fn test "init sets empty state"() do
    state = MyApp.Islands.SearchBar.init(%{users: []})
    assert state.query == ""
    assert state.results == []
    assert state.loading == false
  end

  fn test "UpdateQuery updates the query"() do
    state = %{query: "", results: [], loading: false}
    {new_state, cmd} = MyApp.Islands.SearchBar.update(state, UpdateQuery("alice"))

    assert new_state.query == "alice"
    assert cmd == Cmd.none()
  end

  fn test "SubmitSearch sets loading and fires HTTP request"() do
    state = %{query: "alice", results: [], loading: false}
    {new_state, cmd} = MyApp.Islands.SearchBar.update(state, SubmitSearch)

    assert new_state.loading == true
    assert Bastion.Test.Island.cmd_type(cmd) == :http_get
  end

  fn test "view renders search input and results"() do
    state = %{query: "alice", results: [%{name: "Alice", email: "a@b.com"}], loading: false}
    fragment = MyApp.Islands.SearchBar.view(state)

    assert Bastion.Test.Island.render_to_string(fragment)
    |> String.contains("alice")
  end
end
```

---

## Depot Integration Testing

Tests that need a database use a sandboxed Depot connection that rolls back after each test:

```march
mod MyApp.UsersTest do
  import Bastion.Test
  import Bastion.Test.Depot

  # Each test runs in a transaction that's rolled back after the test
  @setup fn ->
    Bastion.Test.Depot.checkout(MyApp.Repo.pool())
  end

  fn test "create_user inserts a user"() do
    result = MyApp.Users.create(test_db(), %{
      name: "Alice",
      email: "alice@test.com",
      password: "secret123"
    })

    assert result |> Result.is_ok()
    user = Result.unwrap(result)
    assert user.name == "Alice"
    assert user.password_hash != "secret123"
  end
end
```

---

## Channel Testing

Test WebSocket channel handlers without a real WebSocket connection — see [channels.md](channels.md) for examples.

---

## Running Tests

```bash
# Run all tests
forge test

# Run a specific test file
forge test test/handlers/user_handler_test.march

# Run with verbose output
forge test --verbose

# Run only tests matching a pattern
forge test --filter "authentication"

# Run with coverage report
forge test --coverage
```

Tests run in parallel by default (each test gets its own sandboxed Depot transaction). Vault tables are cleared between tests.
