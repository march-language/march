---
layout: cookbook
title: "Cookbook: HTML"
permalink: /docs/cookbook/html/
---

# HTML

March's `~H` sigil generates safe HTML. String interpolations inside `~H` are auto-escaped — user input can't inject markup. `Html.raw` opts out for trusted content you've already sanitized.

---

## The `~H` sigil

```march
let name = "<script>alert(1)</script>"
let html = ~H"<p>Hello, ${name}!</p>"
-- renders: <p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;</p>
```

Multi-line templates with triple quotes:

```march
fn render_card(title : String, body : String) : IOList do
  ~H"""
  <div class="card">
    <h2>${title}</h2>
    <p>${body}</p>
  </div>
  """
end
```

---

## Trusted HTML

`Html.raw` marks a string as already safe — `~H` won't escape it:

```march
let icon = Html.raw("<svg>...</svg>")
let html = ~H"<button>${icon} Click me</button>"
```

Use `Html.raw` only for content you've verified or generated yourself, never for user input.

---

## Layouts and partials

```march
fn layout(title : String, body : IOList) : IOList do
  ~H"""
  <!DOCTYPE html>
  <html>
    <head><title>${title}</title></head>
    <body>${Html.raw(IOList.to_string(body))}</body>
  </html>
  """
end

fn page() : IOList do
  layout("Home", ~H"<h1>Welcome</h1>")
end
```

---

## CSRF protection

`~H` automatically injects CSRF tokens into forms with `method="post"`:

```march
fn login_form() : IOList do
  ~H"""
  <form method="post" action="/login">
    <input name="email" type="email" placeholder="Email">
    <input name="password" type="password" placeholder="Password">
    <button>Log in</button>
  </form>
  """
end
```

The hidden `_csrf_token` field is injected automatically. Validate it server-side with `CSRF.protect(conn)` middleware.

---

## Complete example: a user list page

```march
mod UserList do
  type User = { name : String, email : String, admin : Bool }

  fn render_badge(u : User) : IOList do
    if u.admin do
      ~H"<span class='badge badge-admin'>admin</span>"
    else
      ~H""
    end
  end

  fn render_user(u : User) : IOList do
    let badge = render_badge(u)
    ~H"""
    <li class="user-row">
      <strong>${u.name}</strong>
      <span class="email">${u.email}</span>
      ${badge}
    </li>
    """
  end

  fn render(users : List(User)) : IOList do
    let items = Html.list(users, render_user)
    let count = int_to_string(List.length(users))
    ~H"""
    <h1>Users (${count})</h1>
    <ul class="user-list">${items}</ul>
    """
  end

  fn main() do
    let users = [
      { name: "Alice", email: "alice@example.com", admin: true },
      { name: "Bob", email: "bob@example.com", admin: false }
    ]
    print(IOList.to_string(render(users)))
  end
end
```
