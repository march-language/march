# Bastion — Templates

**Status:** Design. Not yet implemented.

## Overview

Bastion templates produce HTML strings on the server. They compose with the Islands library: template functions call `Islands.wrap` to embed interactive islands in otherwise static HTML.

The template layer is deliberately simple:
- No special template syntax — templates are plain March functions returning `String`.
- String interpolation (`${}`) and `++` concatenation handle most cases.
- `IOList` (a list of string chunks) is used for efficient large-page assembly.

## Pattern: function-based templates

```march
mod Layout do

  -- Base page layout
  fn base(title, head_extra, body) do
    "<!DOCTYPE html>" ++
    "<html lang=\"en\">" ++
    "<head>" ++
    "  <meta charset=\"utf-8\">" ++
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ++
    "  <title>${title}</title>" ++
    head_extra ++
    "</head>" ++
    "<body>" ++
    body ++
    "</body>" ++
    "</html>"
  end

  fn with_islands(title, base_url, body) do
    let script = Islands.bootstrap_script(base_url)
    base(title, script, body)
  end

end
```

## Pattern: IOList for large pages

For pages with many fragments, use `IOList` to avoid O(n²) string concatenation:

```march
mod PageTemplate do

  fn render_items(items) do
    let chunks = List.map(items, fn item -> "<li>${item}</li>")
    let inner = String.join(chunks, "\n")
    "<ul>${inner}</ul>"
  end

  fn render_page(items) do
    let body = render_items(items)
    Layout.with_islands("Item List", "/_march", body)
  end

end
```

## Pattern: islands in templates

```march
mod CounterPage do

  fn render(initial_count) do
    let state_json = "{\"count\":${int_to_string(initial_count)}}"
    let island_html = Islands.wrap(
      "Counter",
      Islands.Eager,
      state_json,
      "<span>${int_to_string(initial_count)}</span>"
    )
    Layout.with_islands("Counter Demo", "/_march",
      "<main>" ++
      "<h1>Counter</h1>" ++
      island_html ++
      "</main>"
    )
  end

end
```

## Planned: HTML escaping

User-supplied strings should be escaped before embedding in HTML. A planned `Html` stdlib module will provide:

```march
-- Planned stdlib/html.march
mod Html do
  fn escape(s : String) : String do
    s
    |> String.replace_all("&", "&amp;")
    |> String.replace_all("<", "&lt;")
    |> String.replace_all(">", "&gt;")
    |> String.replace_all("\"", "&quot;")
    |> String.replace_all("'", "&#39;")
  end

  -- Wrap a pre-escaped or trusted HTML string
  type Safe = Safe(String)

  fn safe(s : String) : Safe do Safe(s) end

  fn to_string(s : Safe) : String do
    match s do
    | Safe(inner) -> inner
    end
  end
end
```

Until `Html` lands, use `String.replace_all` directly for any user-supplied content inserted into HTML.

## Planned: template macros

A future `@template` annotation will allow string interpolation with auto-escaping:

```march
-- Future syntax (not yet implemented):
@template
fn greeting(name : String) : Html.Safe do
  -- ${name} is auto-escaped; #{name} inserts raw HTML (explicit opt-in)
  <div class="greeting">Hello, ${name}!</div>
end
```

## Integration with HttpServer

Templates return `String` and plug directly into `HttpServer.html`:

```march
fn handle_counter(conn) do
  let count = 0
  let page = CounterPage.render(count)
  HttpServer.html(conn, 200, page)
end
```
