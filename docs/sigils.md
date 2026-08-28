---
layout: docs
title: Sigils & Templating
nav_order: 5.9
permalink: /docs/sigils/
---

# Sigils & Templating

Some kinds of text aren't really "just a string": a chunk of TOML, an HTML template, an
XML document. March's **sigils** let you write that text as a literal, right in your
source, and have the compiler hand it to a parser or template builder instead of
treating it as a plain `String`. The most-used one, `~H`, builds HTML with
**contextual auto-escaping**: every interpolation is escaped for the exact place it
lands, worked out at compile time. The rest of this page starts with the general
mechanism, then goes deep on `~H`.

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
becomes `Sigil.toml("...")`, `~xml"..."` becomes `Sigil.xml("...")`, and so on; a
sigil is just a call with unusual syntax around the argument, not a separate kind of
value. That means you can always see exactly what a sigil does by looking up
`Sigil.<name>` in the stdlib.

March ships three general-purpose sigils out of the box:

| Sigil | Calls | Returns |
|---|---|---|
| `~toml"..."` | `Toml.parse_exn` | a `TomlValue` |
| `~xml"..."` | `Xml.parse_exn` | a parsed XML document |
| `~yaml"..."` | `Yaml.parse_exn` | a parsed YAML document |

All three **panic if the content doesn't parse**: they're meant for literals you
control (embedding a known-good config as source, not parsing untrusted input at
runtime). If you need to handle a malformed document gracefully, parse a runtime string
with the ordinary `Toml.parse`/`Xml.parse`/`Yaml.parse` functions instead, which return
a `Result` rather than panicking.

**They do not accept interpolation.** `~toml`, `~xml` and `~yaml` hand their content to
a parser, so a `${...}` hole would be spliced into the source text *before* parsing and
could change the parsed structure rather than appear as a value in it; an interpolated
`</name><admin>true</admin><name>` would add a whole element. That is a compile error:

```march
~xml"<user><name>${v}</name></user>"
-- error: Cannot interpolate into a ~xml sigil. Its content is parsed, so an
-- interpolated value would be spliced into the source text and could change
-- the parsed structure rather than appear as a value in it.
```

Build the value programmatically instead (parse a literal document and set fields on
it), so the value arrives as *data* rather than as source text. `~H` is the exception,
and the next section explains why it can afford to be.

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

`~H` is the one sigil with truly special treatment: instead of calling a
`Sigil.h` function at runtime, the compiler builds the HTML directly into an efficient
multi-segment structure (an `IOList`) at compile time; there's no intermediate string
concatenation, even for a template with many interpolated pieces.

```march
let name = "<script>alert(1)</script>"
let html = ~H"<p>Hello, ${name}!</p>"
-- renders: <p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;!</p>
```

**Interpolation is `${expr}`, and you never choose how it is escaped.** The compiler
works out where in the HTML each hole lands and applies the escaping that position
needs. That is the headline reason to use `~H` over string concatenation: with
concatenation you have to remember to escape every value *and* pick the right escaping
for its position, and getting either wrong is how injection bugs happen.

### What happens where

The same `${name}` is treated differently depending on where you put it:

| Where the hole is | What `~H` does |
|---|---|
| element content: `<p>${x}</p>` | HTML entity-encoding |
| an attribute value: `<div class="${x}">` | entity-encoding, plus a backtick |
| the start of a URL attribute: `<a href="${x}">` | **URL scheme allowlist** |
| later in a URL: `<a href="/s?q=${x}">` | percent-encoding |
| a `style` attribute: `<div style="color:${x}">` | CSS escaping, allowlisted functions |
| a CSS `url()`: `style="background:url(${x})"` | URL rules that also survive CSS |
| inside `<script>`: `<script>var n="${x}"</script>` | JavaScript string escaping |

Worked through:

```march
let u = "javascript:alert(1)"
~H"<a href=\"${u}\">x</a>"        -- <a href="about:invalid#zSoyz">x</a>

let q = "a b&c"
~H"<a href=\"/s?q=${q}\">x</a>"   -- <a href="/s?q=a%20b%26c">x</a>

let col = "var(--accent)"
~H"<div style=\"color:${col}\">"  -- <div style="color:var(--accent)">
```

A URL that fails the scheme allowlist becomes `about:invalid#zSoyz`: inert, and
visible in the page source so the problem is obvious rather than silent. `http`,
`https`, `mailto`, `tel`, `ftp` and any relative reference are allowed.

**Unquoted attributes are quoted for you.** `<div class=${x}>` emits
`<div class="...">`, so a value containing a space cannot start a new attribute.

### What will not compile

Some positions cannot be made safe by escaping at all; an attacker-chosen attribute
name like `onerror` contains no character an encoder could touch. Those are compile
errors rather than silently-wrong output:

```march
~H"<div ${attr}=1>x</div>"   -- error: Cannot interpolate where an attribute name
                             --        is expected...
~H"<${tag}>x</${tag}>"       -- error: Cannot interpolate an element name...
~H"<!-- ${x} -->"            -- error: Cannot interpolate inside an HTML comment...
~H"<div class=\"${x}"         -- error: This ~H template does not end in a
                             --        well-formed state...
```

The last one catches a template that stops mid-tag or mid-attribute: whatever you
concatenate after it would be spliced into that position.

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

### Trusted content, and why trust does not travel

Sometimes you *want* to interpolate real markup: an icon's `<svg>`, or HTML you
produced yourself. The `Html.trust_*` functions say so, and each names the context the
trust applies to:

```march
let icon = Html.trust_html("<svg>...</svg>")
~H"<button>${icon} Click me</button>"     -- <button><svg>...</svg> Click me</button>
```

**The context matters, and this is the part worth internalising.** Trusting a string as
HTML states no fact about whether it is a safe URL, so the same value in an `href` is
still escaped:

```march
let h = Html.trust_html("<em>ok</em>")
~H"<p>${h}</p>"                  -- <p><em>ok</em></p>          verbatim
~H"<a href=\"${h}\">x</a>"        -- href="&lt;em&gt;ok&lt;/em&gt;"  escaped
```

Trust does not travel between contexts. Use the one that matches where the value is
going:

| Function | Trusted in |
|---|---|
| `Html.trust_html` | element content |
| `Html.trust_attr` | an ordinary attribute value |
| `Html.trust_url` | a URL attribute; **bypasses the scheme allowlist** |
| `Html.trust_css` | a `style` attribute or `<style>` body |
| `Html.trust_js` | inside `<script>` |

Each has a matching `Html.untrust_*` to get the plain `String` back.

Only reach for these on content you generated or verified yourself, never on user
input, since that is exactly the escaping `~H` exists to give you automatically. Most
templates need none of them.

> **`Html.raw` is deprecated.** It still works and is treated as HTML trust, so
> `Html.raw` in element content behaves as it always did. But it is context-free (it
> cannot say *where* the content is trusted), so `Html.raw("javascript:...")` in an
> `href` is escaped to `about:invalid#zSoyz` rather than inserted. Prefer
> `Html.trust_html`, which states what it means.

> **`Html.tag` is deprecated too.** It builds markup outside the sigil, so it never gets
> this analysis and has to validate at runtime instead: it will not accept element
> and attribute names it cannot prove safe, and rejects `on*` handlers entirely. Use `~H`.

### Composing templates

A `~H` template returns an `IOList`, and an `IOList` interpolates cleanly into another
`~H` template without being re-escaped or double-wrapped, so partials compose the way
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

There's no template-level `for` loop inside `~H` itself; `Html.list` (map a render
function over a list, producing one combined `IOList`) is the idiomatic way to render a
collection, and ordinary recursion works too for anything more custom. See [HTML
cookbook]({{ site.baseurl }}/docs/cookbook/html/) for a complete worked example
(layouts, partials, a full user-list page) built entirely from these pieces.

### A gotcha worth knowing: CSRF injection

If you're building a web app with March's HTTP framework, `~H` automatically injects a
CSRF protection tag into `<form method="post|put|patch|delete">` tags it emits, but
**only when a `conn` binding is lexically in scope** at that `~H` call site. If you're
rendering a form outside of a request-handling context (no `conn` in scope), the tag
isn't injected and you won't get a compile error about it; so if you rely on this
protection, make sure the form-rendering function actually has `conn` available, rather
than assuming every `~H` form is automatically protected.

**Do not add your own token as well.** Injection is automatic, so writing
`${CSRF.tag(conn)}` inside the form used to emit two hidden inputs. `~H` now notices an
explicit token and skips its own injection, warning that yours is redundant, but the
clean form is simply to leave it out:

```march
~H"<form method=\"post\">...</form>"    -- token injected for you
```

Explicit token helpers are for markup built *outside* `~H`, by string concatenation,
where no content is injected.

---

## Next Steps

- [HTML cookbook]({{ site.baseurl }}/docs/cookbook/html/): this page covers the
  mechanism; the cookbook shows you how to build a full page with it (layouts, partials,
  a complete example).
- [Type System](types.md): what `TomlValue` and friends look like as ordinary ADTs.
- [Capabilities]({{ site.baseurl }}/docs/capabilities/): the permission system that
  guards the file/network access templating code often sits next to.
