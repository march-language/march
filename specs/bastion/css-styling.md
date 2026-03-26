# Bastion: CSS and Styling

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Approach

Bastion supports both **global stylesheets** and **scoped per-island CSS**. It does not impose a specific CSS methodology or build tool — developers bring their own CSS pipeline (Tailwind CLI, PostCSS, Sass, vanilla CSS, etc.) and Bastion serves the output.

---

## Global Stylesheets

Global CSS files live in `priv/static/css/` and are included in layout templates like any standard web application:

```march
fn PageLayout(title: String, children: Fragment) do
  ~H"""
  <!DOCTYPE html>
  <html>
    <head>
      <title>{title}</title>
      <link rel="stylesheet" href="/static/css/app.css" />
    </head>
    <body>
      {children}
      <script src="/static/bastion.js"></script>
    </body>
  </html>
  """
end
```

This works for overall page layout, typography, theme variables, and any styles shared across the application.

---

## Scoped Island CSS

Each WASM island can declare its own CSS that is automatically scoped to that island's DOM subtree. This prevents style leakage between islands and between islands and the rest of the page.

```march
mod MyApp.Islands.SearchBar do
  import Bastion.Island

  # Island-scoped styles
  fn styles() do
    ~CSS"""
    .search-bar {
      display: flex;
      gap: 8px;
      padding: 12px;
    }

    .search-bar input {
      flex: 1;
      border: 1px solid var(--border-color);
      border-radius: 4px;
      padding: 8px;
    }

    .results {
      list-style: none;
      padding: 0;
    }

    .results li {
      padding: 8px;
      border-bottom: 1px solid var(--border-color);
    }
    """
  end

  # ... init, update, view as before
end
```

Bastion scopes these styles at build time by:

1. Generating a unique attribute for each island (e.g., `data-b-search-bar`)
2. Prefixing all CSS selectors with that attribute selector
3. Adding the attribute to the island's root DOM element

The compiled output:

```css
/* search_bar.scoped.css */
[data-b-search-bar] .search-bar { display: flex; gap: 8px; padding: 12px; }
[data-b-search-bar] .search-bar input { flex: 1; ... }
[data-b-search-bar] .results { list-style: none; padding: 0; }
[data-b-search-bar] .results li { padding: 8px; ... }
```

```html
<div data-bastion-island="MyApp.Islands.SearchBar" data-b-search-bar>
  <!-- island content -->
</div>
```

---

## CSS Variables for Theming

Scoped island styles can reference global CSS custom properties, enabling consistent theming across islands and the rest of the page:

```css
/* priv/static/css/app.css — global theme */
:root {
  --primary: #3b82f6;
  --border-color: #e5e7eb;
  --text: #1f2937;
  --bg: #ffffff;
}

@media (prefers-color-scheme: dark) {
  :root {
    --primary: #60a5fa;
    --border-color: #374151;
    --text: #f9fafb;
    --bg: #111827;
  }
}
```

Island styles reference these variables, so theme changes propagate to all islands automatically without any island-specific code.

---

## No Built-In CSS Build Step

Bastion does **not** include its own CSS preprocessor, PostCSS pipeline, or Tailwind integration for v1. The reasoning:

- CSS tooling is mature and developers have strong preferences
- Adding a CSS pipeline is a large maintenance surface for marginal benefit
- Forge already handles WASM compilation — adding CSS compilation increases build complexity
- External tools (Tailwind CLI, Lightning CSS, Sass) can run alongside `forge dev` via a simple script or `forge.toml` hook

The recommended workflow is to configure external CSS tooling to output to `priv/static/css/`, and Bastion serves it from there. Forge can be configured to run CSS build commands as part of `forge dev` and `forge build`:

```toml
# forge.toml
[hooks]
before_build = "npx tailwindcss -i src/css/app.css -o priv/static/css/app.css --minify"
dev_watch = "npx tailwindcss -i src/css/app.css -o priv/static/css/app.css --watch"
```
