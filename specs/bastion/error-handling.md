# Bastion: Error Handling

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## HTTP Request Errors

HTTP request handlers use pattern matching for expected errors and supervised crash recovery for unexpected ones:

```march
mod MyApp.UserHandler do
  fn show(conn, id) do
    case MyApp.Users.get(conn.assigns.db, id) do
      Ok(user) ->
        conn |> html(~H"""<UserDetail user={user} />""")
      Error(:not_found) ->
        conn |> send_resp(404, "User not found")
      Error(:db_error(reason)) ->
        Bastion.Logger.error("DB error fetching user #{id}: #{reason}")
        conn |> send_resp(500, "Internal server error")
    end
  end
end
```

If a request handler crashes (unhandled exception), Bastion catches it at the middleware boundary and returns a 500 response. The process was going to terminate after the response anyway, so there's nothing to restart.

---

## Custom Error Pages

```march
mod MyApp.ErrorHandler do
  import Bastion.Template

  fn call(conn, status: Int, message: String) do
    case status do
      404 -> conn |> html(~H"""
        <PageLayout title="Not Found">
          <h1>404</h1>
          <p>{message}</p>
        </PageLayout>
      """)
      500 -> conn |> html(~H"""
        <PageLayout title="Error">
          <h1>Something went wrong</h1>
          <p>We've been notified and are looking into it.</p>
        </PageLayout>
      """)
      _ -> conn |> send_resp(status, message)
    end
  end
end

# In API context, return JSON errors
mod MyApp.API.ErrorHandler do
  fn call(conn, status: Int, message: String) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode(%{error: message, status: status}))
  end
end
```

---

## WebSocket / Channel Errors

WebSocket connections are supervised. When a connection actor crashes:

1. The supervisor restarts the connection actor
2. The client-side Bastion runtime detects the dropped WebSocket and auto-reconnects (with exponential backoff)
3. On reconnect, the server creates a fresh connection actor
4. The client-side WASM islands retain their local state (they run independently of the WebSocket) and re-sync with the server

```march
mod MyApp.ChannelSupervisor do
  import Bastion.Supervisor

  # Restart strategy: if a connection actor crashes, restart just that actor
  fn child_spec() do
    %{
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 10
    }
  end
end
```

---

## WASM Island Errors

If a client-side WASM island crashes (e.g., a bug in the `update` function), Bastion's client runtime:

1. Catches the error at the island boundary
2. Logs the error (and optionally reports to the server)
3. Re-initializes the island with its original props (graceful reset)
4. If the island crashes repeatedly, renders a fallback UI

---

## Dev Error Overlay

When a request handler crashes in development, Bastion renders a rich error page instead of a generic 500. The overlay shows:

- The exception type and message
- A full stack trace with source code context
- The conn state at the time of the crash (method, path, headers, params, assigns)
- The middleware pipeline stage where the error occurred
- Timing information

```march
# Automatically enabled in dev, disabled in prod
# config/dev.march
fn error_handler() do
  Bastion.Dev.ErrorOverlay  # rich HTML error page
end

# config/prod.march
fn error_handler() do
  MyApp.ErrorHandler         # custom production error handler
end
```

The error overlay is never shown in production — Bastion verifies the environment before rendering it.
