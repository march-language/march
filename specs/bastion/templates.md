# Bastion: Templates and Rendering

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## The `~H` Sigil

Bastion templates use a `~H` sigil that embeds HTML with March expressions. The template is parsed and compiled to March AST at compile time, producing efficient IO list construction. All expressions inside the template are type-checked by the March compiler.

**Language requirement**: This requires adding sigil support to March's lexer/parser. The parser hands off the sigil body as a raw string to the template compiler, which parses the HTML and embedded expressions, then produces March AST nodes.

---

## Template Syntax

The syntax is an HTML-like hybrid of HEEx and JSX: HTML structure with March expressions in curly braces, components as function calls.

```march
mod MyApp.UserHandler do
  import Bastion.Conn
  import Bastion.Template

  fn index(conn: Conn(Authenticated)) do
    users = MyApp.Users.list_all(conn.assigns.db)

    conn |> html(~H"""
    <div class="container">
      <h1>Users ({List.length(users)})</h1>

      <ul>
        {List.map(users, fn user ->
          <li class="user-card">
            <UserCard user={user} />
          </li>
        end)}
      </ul>

      <Island module={MyApp.Islands.SearchBar} props={%{users: users}} />
    </div>
    """)
  end
end
```

---

## Components as Functions

Components are regular March functions that return template fragments. Props are function arguments, type-checked at the call site:

```march
mod MyApp.Components do
  import Bastion.Template

  fn UserCard(user: User) do
    ~H"""
    <div class="card">
      <img src={user.avatar_url} alt={user.name} />
      <h3>{user.name}</h3>
      <p>{user.email}</p>
      {case user.role do
        :admin -> <span class="badge badge-admin">Admin</span>
        :moderator -> <span class="badge badge-mod">Mod</span>
        _ -> <span></span>
      end}
    </div>
    """
  end

  fn PageLayout(title: String, children: Fragment) do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <title>{title} — MyApp</title>
        <link rel="stylesheet" href="/static/app.css" />
      </head>
      <body>
        <nav><NavBar /></nav>
        <main>{children}</main>
        <footer><Footer /></footer>
        <script src="/static/bastion.js"></script>
      </body>
    </html>
    """
  end
end
```

---

## Template Compilation Pipeline

```
~H"""...""" sigil
    │
    ▼
Template Parser (HTML + March expressions)
    │
    ▼
Template AST (typed tree of elements, expressions, components)
    │
    ▼
Type Checker (verifies all expressions, component props)
    │
    ▼
March AST (IO list construction: ["<div class=\"card\">", user.name, "</div>"])
    │
    ▼
Compiled March Function (efficient binary/string concatenation)
```

At runtime, rendering a template is just calling a function that returns an IO list — no parsing, no interpretation. This gives sub-millisecond render times for typical pages.

---

## Compile-Time Type Safety

The template compiler ensures:

- All variables referenced in `{expr}` are in scope and well-typed
- Component calls like `<UserCard user={user} />` match the component function's type signature
- Missing required props are a compile-time error
- Type mismatches (passing an `Int` where `String` is expected) are a compile-time error

```march
# This is a compile-time error:
fn broken_template(user: User) do
  ~H"""
  <UserCard user={42} />
  """
  # ERROR: UserCard expects `user: User`, got `Int`
end
```

---

## XSS Prevention

All expressions inside `~H` templates are **HTML-escaped by default**:

```march
# Safe — user input is escaped
~H"""<p>{user.bio}</p>"""
# If user.bio is "<script>alert('xss')</script>", renders as:
# <p>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</p>

# For trusted HTML content (e.g., sanitized Markdown output), use raw()
~H"""<div class="post-body">{raw(sanitized_html)}</div>"""
```

The `raw()` function is the only way to bypass escaping. It serves as a clear signal in code review. The template compiler can optionally emit a warning when `raw()` is used:

```toml
# forge.toml
[bastion.security]
warn_on_raw_html = true   # default: true in dev, false in prod
```
