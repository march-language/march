# Bastion: Reversible Routing and Compile-Time Route Verification

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Routes are defined once. The compiler guarantees that every link helper, redirect, and form action points to a real route — dead links become compile-time errors. Route helpers are auto-generated from the router definition, and March's type system enforces correctness at every call site.

This is "reversible routing" in the Phoenix/Rails sense, but with compile-time verification instead of runtime lookup.

---

## Route Helpers

Given a router definition, Bastion generates a companion `Routes` module with typed path helpers:

```march
# lib/my_app/router.march
mod MyApp.Router do
  import Bastion.Router

  fn route(conn, :get, []) do
    conn |> render("home.html")
  end

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

  fn route(conn, :get, ["posts", post_id, "comments", comment_id]) do
    MyApp.CommentHandler.show(conn, post_id, comment_id)
  end
end
```

The compiler generates:

```march
# AUTO-GENERATED — do not edit. Re-run `forge routes` to regenerate.
mod MyApp.Routes do
  fn home_path() -> String = "/"
  fn users_path() -> String = "/users"
  fn user_path(id: String) -> String = "/users/#{id}"
  fn post_comment_path(post_id: String, comment_id: String) -> String
    = "/posts/#{post_id}/comments/#{comment_id}"
end
```

---

## Using Route Helpers in Templates

```march
~H"""
<nav>
  <a href={MyApp.Routes.home_path()}>Home</a>
  <a href={MyApp.Routes.users_path()}>Users</a>
  <a href={MyApp.Routes.user_path(user.id)}>View Profile</a>
</nav>

<form method="post" action={MyApp.Routes.users_path()}>
  <!-- form fields -->
</form>
"""
```

If `user_path` is removed from the router and the template is not updated, the compiler reports an error:

```
error: MyApp.Routes.user_path/1 does not exist
  → lib/my_app/templates/user/show.html.march:8
  |
8 |   <a href={MyApp.Routes.user_path(user.id)}>View Profile</a>
  |            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  |
  hint: Route GET /users/:id was removed. Update the link or restore the route.
```

---

## Using Route Helpers in Handlers

```march
fn create(conn) do
  case MyApp.Users.create(parse_params(conn)) do
    Ok(user) ->
      conn
      |> put_flash(:info, "User created!")
      |> redirect(to: MyApp.Routes.user_path(user.id))
    Error(changeset) ->
      conn |> render("new.html", changeset: changeset)
  end
end
```

The `redirect(to: ...)` call accepts a `String` from a route helper. The compiler checks the arity and type of the helper at the call site.

---

## Named Routes

Routes can be given explicit names to decouple the helper name from the path structure:

```march
mod MyApp.Router do
  import Bastion.Router

  # Explicitly named route — helper will be Routes.dashboard_path() not Routes.home_path()
  fn route(conn, :get, [], name: :dashboard) do
    conn |> render("dashboard.html")
  end

  # Nested resource with explicit naming
  fn route(conn, :get, ["api", "v1", "users", id], name: :api_user) do
    MyApp.API.UserHandler.show(conn, id)
  end
end
```

Generated helpers:

```march
mod MyApp.Routes do
  fn dashboard_path() -> String = "/"
  fn api_user_path(id: String) -> String = "/api/v1/users/#{id}"
end
```

---

## URL Generation with Query Parameters

Route helpers accept an optional keyword list of query parameters:

```march
# Generates /users?page=2&per_page=50
MyApp.Routes.users_path(query: %{page: 2, per_page: 50})

# Generates /users/42
MyApp.Routes.user_path("42")

# Generates /users/42?ref=email
MyApp.Routes.user_path("42", query: %{ref: "email"})
```

---

## Route Introspection

The `Routes` module also exposes a `all/0` function for route listing (used by the dev dashboard and CLI):

```march
# forge routes — prints all routes
MyApp.Routes.all()
# => [
#   %{method: :get, path: "/", name: :home, arity: 0},
#   %{method: :get, path: "/users", name: :users, arity: 0},
#   %{method: :get, path: "/users/:id", name: :user, arity: 1},
#   ...
# ]
```

---

## Compile-Time Verification Rules

The March compiler enforces:

1. **No dangling helpers** — any call to `MyApp.Routes.foo_path(...)` where `foo_path` does not exist in the generated module is a compile error.
2. **Arity mismatch** — calling `user_path()` (no args) when the route has a dynamic segment `:id` is a type error.
3. **Unreachable routes** — if two `route` function heads match the same method + path pattern, the second is flagged as unreachable (already enforced via pattern overlap detection in [routing.md](routing.md)).
4. **Missing catch-all** — if no catch-all `fn route(conn, _method, _path)` arm exists, the compiler emits a warning that unmatched requests will crash the handler.

---

## Dev Dashboard Integration

The development dashboard (`/__bastion__/routes`) renders a live route table with:

- Method badges (GET/POST/PUT/DELETE)
- Path patterns with named segments highlighted
- Generated helper name and arity
- Clickable links for GET routes (navigates directly in the browser)

---

## Open Questions

- Should route helpers produce typed path structs (`UserPath(id)`) instead of plain `String` values, to enable stricter type checking beyond arity?
- How do scoped/nested routers (delegated sub-routers) affect helper generation? Should `MyApp.API.V1.Routes` be a separate module or merged into `MyApp.Routes`?
