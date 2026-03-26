# Bastion: Pattern-Matched Routing

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Routes are defined by pattern matching on HTTP method and path segments in function heads. No router DSL, no macros — just March functions.

---

## Pattern-Matched Routes

```march
mod MyApp.Router do
  import Bastion.Router
  import Bastion.Conn

  # Static pages
  fn route(conn, :get, []) do
    conn |> render("home.html")
  end

  fn route(conn, :get, ["about"]) do
    conn |> render("about.html")
  end

  # Users resource
  fn route(conn, :get, ["users"]) do
    MyApp.UserHandler.index(conn)
  end

  fn route(conn, :get, ["users", id]) do
    MyApp.UserHandler.show(conn, id)
  end

  fn route(conn, :post, ["users"]) do
    MyApp.UserHandler.create(conn)
  end

  fn route(conn, :put, ["users", id]) do
    MyApp.UserHandler.update(conn, id)
  end

  fn route(conn, :delete, ["users", id]) do
    MyApp.UserHandler.delete(conn, id)
  end

  # API namespace
  fn route(conn, method, ["api", "v1" | rest]) do
    conn
    |> put_resp_content_type("application/json")
    |> MyApp.API.V1.Router.route(method, rest)
  end

  # Static files
  fn route(conn, :get, ["static" | path]) do
    Bastion.Static.serve(conn, path)
  end

  # Catch-all 404
  fn route(conn, _method, _path) do
    conn |> send_resp(404, "Not Found")
  end
end
```

---

## Route Delegation

Routers can delegate to other routers by passing the remaining path segments. This enables modular route namespacing without a DSL:

```march
mod MyApp.API.V1.Router do
  fn route(conn, :get, ["posts"]) do
    MyApp.PostHandler.index_json(conn)
  end

  fn route(conn, :get, ["posts", id]) do
    MyApp.PostHandler.show_json(conn, id)
  end

  fn route(conn, _method, _path) do
    conn |> send_resp(404, JSON.encode(%{error: "not found"}))
  end
end
```

---

## Route Compilation

The March compiler can optimize pattern-matched routes into an efficient dispatch table at compile time. Since all routes are known statically (they're function heads), the compiler can:

1. Build a trie of path segments for O(n) lookup where n is the path depth
2. Warn on overlapping or unreachable routes at compile time
3. Generate optimized binary pattern matching for path segments
