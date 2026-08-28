---
layout: cookbook
title: "Cookbook: HTML"
permalink: /docs/cookbook/html/
scrollmd: true
---

# HTML

March's `~H` sigil generates HTML with **contextual auto-escaping**: every `${...}` is escaped for the exact place it lands (element content, an attribute, a URL, CSS, or JavaScript), worked out at compile time. You never pick an escaper. The `Html.trust_*` functions opt out for content you produced yourself. See [Sigils & Templating]({{ site.baseurl }}/docs/sigils/) for the full picture.

---

## The `~H` sigil

```march
let name = "<script>alert(1)</script>"
let html = ~H"<p>Hello, ${name}!</p>"
-- renders: <p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;!</p>
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

## Escaping follows the position

The same value is treated differently depending on where you put it:

```march
let u = "javascript:alert(1)"
~H"<a href=\"${u}\">x</a>"        -- <a href="about:invalid#zSoyz">x</a>

let q = "a b&c"
~H"<a href=\"/s?q=${q}\">x</a>"   -- <a href="/s?q=a%20b%26c">x</a>

let col = "var(--accent)"
~H"<div style=\"color:${col}\">"  -- <div style="color:var(--accent)">
```

A URL that fails the scheme allowlist becomes `about:invalid#zSoyz`. Positions no
escaping can make safe (an attribute name, an element name, inside a comment) are
compile errors.

## Trusted HTML

`Html.trust_html` marks a string as real markup, so `~H` inserts it verbatim:

```march
let icon = Html.trust_html("<svg>...</svg>")
let html = ~H"<button>${icon} Click me</button>"
```

**Trust names a context and does not travel out of it.** The same value in an `href` is
still escaped, because trusting something as HTML makes no claim about it being a safe
URL. Use `Html.trust_url`, `trust_css`, `trust_js` or `trust_attr` when the target is
one of those.

Use these only for content you verified or generated yourself, never for user input.

> `Html.raw` still works and behaves as HTML trust, but it is deprecated: being
> context-free, it cannot say *where* the content is trusted. Prefer `Html.trust_html`.

---

## Layouts and partials

```march
fn layout(title : String, body : IOList) : IOList do
  ~H"""
  <!DOCTYPE html>
  <html>
    <head><title>${title}</title></head>
    <body>${body}</body>
  </html>
  """
end

fn page() : IOList do
  layout("Home", ~H"<h1>Welcome</h1>")
end
```

---

## Complete example: a user list page

```march
mod UserList do
  needs IO.Console
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
