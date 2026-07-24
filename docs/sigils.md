---
layout: docs
title: Sigils & Templating
nav_order: 5.9
permalink: /docs/sigils/
---

# Sigils & Templating

Some kinds of text aren't really "just a string" — a chunk of TOML, an HTML template, an
XML document. March's **sigils** let you write that text as a literal, right in your
source, and have the compiler hand it to a parser or template builder instead of
treating it as a plain `String`. The most-used one, `~H`, builds safe, auto-escaping
HTML templates — the rest of this page starts with the general mechanism, then goes deep
on `~H` specifically.

---

## The general mechanism

A sigil is written `~Name"..."` (or `~Name"""...multi-line..."""` for longer content).
The uppercase (or lowercase-word) name right after the `~` selects which handler runs:

```march
~toml"""
port = 8080
host = "localhost"
"""
```

Under the hood, `~Name"content"` is sugar for a plain function call: `~toml"..."`
becomes `Sigil.toml("...")`, `~xml"..."` becomes `Sigil.xml("...")`, and so on — a
sigil is just a call with unusual syntax around the argument, not a separate kind of
value. That means you can always see exactly what a sigil does by looking up
`Sigil.<name>` in the stdlib.

March ships three general-purpose sigils out of the box:

| Sigil | Calls | Returns |
|---|---|---|
| `~toml"..."` | `Toml.parse_exn` | a `TomlValue` |
| `~xml"..."` | `Xml.parse_exn` | a parsed XML document |
| `~yaml"..."` | `Yaml.parse_exn` | a parsed YAML document |

All three **panic if the content doesn't parse** — they're meant for literals you
control (embedding a known-good config as source, not parsing untrusted input at
runtime). If you need to handle a malformed document gracefully, parse a runtime string
with the ordinary `Toml.parse`/`Xml.parse`/`Yaml.parse` functions instead, which return
a `Result` rather than panicking.

```march
let config = ~toml"""
port = 8080
host = "localhost"
"""
-- config : TomlValue, built at the call site — a typo here panics immediately,
-- which is exactly what you want for a literal baked into your source
```

---

## The `~H` sigil: HTML templates

`~H` is the one sigil with genuinely special treatment: instead of calling a
`Sigil.h` function at runtime, the compiler builds the HTML directly into an efficient
multi-segment structure (an `IOList`) at compile time — there's no intermediate string
concatenation, even for a template with many interpolated pieces.

```march
let name = "<script>alert(1)</script>"
let html = ~H"<p>Hello, ${name}!</p>"
-- renders: <p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;!</p>
```

**Interpolation is `${expr}`, and it's auto-escaped.** Any value you interpolate is run
through `Html.escape` before it lands in the output — the string above is safe to render
even though it contains `<script>`, because `~H` escaped it for you. This is the
headline reason to use `~H` instead of building HTML with plain string concatenation:
you'd have to remember to escape every interpolated value yourself, and forgetting even
once is exactly how HTML injection bugs happen.

Multi-line templates use triple quotes, exactly like triple-quoted strings elsewhere in
March:

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

### Trusted content: `Html.raw`

Sometimes you *want* to interpolate real markup — an icon's `<svg>`, or HTML you already
sanitized elsewhere. `Html.raw` marks a string as pre-trusted, so `~H` skips escaping it:

```march
let icon = Html.raw("<svg>...</svg>")
let html = ~H"<button>${icon} Click me</button>"
```

Only reach for `Html.raw` on content you generated or verified yourself — never on user
input, since that's exactly the escaping `~H` exists to give you automatically.

### Composing templates

A `~H` template returns an `IOList`, and an `IOList` interpolates cleanly into another
`~H` template without being re-escaped or double-wrapped — so partials compose the way
you'd expect:

```march
fn render_user(u : User) : IOList do
  ~H"""
  <li class="user-row">
    <strong>${u.name}</strong>
    <span class="email">${u.email}</span>
  </li>
  """
end

fn render_list(users : List(User)) : IOList do
  let items = Html.list(users, render_user)   -- IOList of all the rendered rows
  ~H"""
  <ul class="user-list">${items}</ul>
  """
end
```

There's no template-level `for` loop inside `~H` itself — `Html.list` (map a render
function over a list, producing one combined `IOList`) is the idiomatic way to render a
collection, and ordinary recursion works too for anything more custom. See [HTML
cookbook]({{ site.baseurl }}/docs/cookbook/html/) for a complete worked example
(layouts, partials, a full user-list page) built entirely from these pieces.

### A gotcha worth knowing: CSRF injection

If you're building a web app with March's HTTP framework, `~H` automatically injects a
CSRF protection tag into `<form method="post|put|patch|delete">` tags it emits — but
**only when a `conn` binding is lexically in scope** at that `~H` call site. If you're
rendering a form outside of a request-handling context (no `conn` in scope), the tag
isn't injected and you won't get a compile error about it — so if you rely on this
protection, make sure the form-rendering function actually has `conn` available, rather
than assuming every `~H` form is automatically protected.

---

## Next Steps

- [HTML cookbook]({{ site.baseurl }}/docs/cookbook/html/) — this page covers the
  mechanism; the cookbook shows you how to build a full page with it (layouts, partials,
  a complete example).
- [Type System](types.md) — what `TomlValue` and friends look like as ordinary ADTs.
- [Capabilities]({{ site.baseurl }}/docs/capabilities/) — the permission system that
  guards the file/network access templating code often sits next to.
