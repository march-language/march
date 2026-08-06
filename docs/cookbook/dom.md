---
layout: cookbook
title: "Cookbook: DOM"
permalink: /docs/cookbook/dom/
scrollmd: true
---

# DOM

March can target the browser via `--target js`. The `Dom` stdlib module exposes
the browser's Document Object Model as typed March functions — no JavaScript
required on your side.

---

## Project setup

Create a forge project:

```sh
forge new my_app
cd my_app
```

The default `forge.toml` works as-is. Build to JavaScript with:

```sh
forge build --target=js
```

The output lands at `.march/build/debug/my_app.mjs`.

---

## The HTML wrapper

March compiles to an ES module. Wire it into your page with a single script tag
and a call to the exported `main` function:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>My App</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="my_app.mjs"></script>
</body>
</html>
```

Your `main` function runs when the module loads. Because it is a module,
it runs after the DOM is parsed — no `DOMContentLoaded` listener needed.

You also need two runtime files alongside the `.mjs`:

| File | Where to get it |
|------|----------------|
| `march_runtime.mjs` | `runtime/march_runtime.mjs` in the March repo |
| `march_dom.mjs` | `runtime/march_dom.mjs` in the March repo |

Copy them next to your `index.html`. The build script in
`demo_app/dom_demo/build.sh` does this automatically.

---

## Querying the DOM

`Dom.find` looks up an element by `id` and returns `Option(Node)`:

```march
match Dom.find("my-button") do
  None    -> ()
  Some(btn) -> Dom.set_text(btn, "Ready")
end
```

`Dom.select` takes any CSS selector:

```march
match Dom.select(".active") do
  None    -> ()
  Some(el) -> Dom.add_class(el, "highlight")
end
```

`Dom.select_all` returns every matching element as a `List(Node)`:

```march
let items = Dom.select_all("li.todo")
-- items : List(Node)
```

---

## Creating elements

Build a node tree with `Dom.create`, set it up, then attach it:

```march
let div = Dom.create("div")
Dom.add_class(div, "card")
Dom.set_text(div, "Hello!")
Dom.set_style(div, "color", "royalblue")

match Dom.find("root") do
  None         -> ()
  Some(root) -> Dom.append(root, div)
end
```

`Dom.text_node` creates a bare text node when you want to mix text and
elements without wrapping them in a container.

---

## Tree operations

| Function | What it does |
|----------|-------------|
| `Dom.append(parent, child)` | Add `child` as the last child |
| `Dom.prepend(parent, child)` | Add `child` as the first child |
| `Dom.remove(el)` | Detach `el` from its parent |
| `Dom.remove_child(parent, child)` | Remove a known direct child |
| `Dom.clear(el)` | Remove all children |
| `Dom.parent(el)` | `Option(Node)` — parent or `None` |
| `Dom.children(el)` | `List(Node)` — direct element children |
| `Dom.clone(el)` | Deep-copy a node |

Moving a node is just `remove` + `append` — or `append` alone if you
know the parent (the browser removes it from the old position automatically):

```march
-- Move the last tile to the front
match Dom.find("board") do
  None -> ()
  Some(board) ->
    match Dom.last_child(board) do
      None       -> ()
      Some(tile) -> Dom.prepend(board, tile)
    end
end
```

---

## Attributes, classes, and styles

<!-- scroll:skip -->
```march
-- Attributes
Dom.set_attr(el, "href", "#section-2")
Dom.set_attr(el, "aria-hidden", "true")
let href = Dom.get_attr(el, "href")  -- Option(String)

-- CSS classes
Dom.add_class(el, "active")
Dom.remove_class(el, "inactive")
Dom.toggle_class(el, "open")
let is_open = Dom.has_class(el, "open")  -- Bool

-- Inline styles
Dom.set_style(el, "background", "#3498db")
Dom.set_style(el, "transform", "scale(1.05)")
Dom.set_style(el, "transform", "")   -- empty string removes the property
```

---

## Events

`Dom.listen` attaches a handler that receives the `Event`:

<!-- scroll:skip -->
```march
Dom.listen(btn, "click", fn ev ->
  Dom.prevent_default(ev)
  -- ...
)
```

The handler is a regular March lambda, so it can close over local variables:

<!-- scroll:skip -->
```march
fn add_item(list, label: String) : Unit do
  let li = Dom.create("li")
  Dom.set_text(li, label)
  Dom.listen(li, "click", fn _ev ->
    Dom.remove(li)
  )
  Dom.append(list, li)
end
```

Common events: `"click"`, `"input"`, `"change"`, `"keydown"`, `"keyup"`,
`"submit"`, `"mouseover"`, `"mouseout"`, `"focus"`, `"blur"`.

To read back the element that fired the event:

<!-- scroll:skip -->
```march
Dom.listen(container, "click", fn ev ->
  let target = Dom.event_target(ev)
  Dom.add_class(target, "selected")
)
```

`Dom.event_key` reads the key that triggered a `"keydown"`/`"keyup"` event
(e.g. `"ArrowLeft"`, `"a"`, `" "` for space):

<!-- scroll:skip -->
```march
Dom.listen(Dom.body(), "keydown", fn ev ->
  match Dom.event_key(ev) do
    "ArrowLeft"  -> move_left()
    "ArrowRight" -> move_right()
    _            -> ()
  end
)
```

---

## Form inputs

<!-- scroll:skip -->
```march
match Dom.find("search-box") do
  None -> ()
  Some(input) ->
    Dom.listen(input, "input", fn _ev ->
      let query = Dom.get_value(input)
      run_search(query)
    )
end
```

`Dom.set_value` writes back to the input's `.value` property.

---

## Timers and animation

<!-- scroll:skip -->
```march
-- Run once after 500 ms
Dom.set_timeout(500, fn _ ->
  Dom.set_text(status, "Done!")
)

-- Run every 1 s
Dom.set_interval(1000, fn _ ->
  tick()
)

-- Smooth animation at 60 fps
fn animate(el) : Unit do
  Dom.on_frame(fn _ ->
    let cur = Dom.get_style(el, "opacity")
    let next = float_to_string(Option.unwrap_or(string_to_float(cur), 1.0) -. 0.02)
    let _ = Dom.set_style(el, "opacity", next)
    if Option.unwrap_or(string_to_float(next), 0.0) > 0.0 do animate(el) else () end
  )
end
```

---

## Complete example

A row of colored tiles that move when clicked:

**`lib/my_app.march`**

```march
mod MyApp do

  fn move_to_end(tile) : Unit do
    match Dom.parent(tile) do
      None    -> ()
      Some(p) ->
        Dom.remove(tile)
        Dom.append(p, tile)
    end
  end

  fn add_tile(board, label: String, color: String) : Unit do
    let tile = Dom.create("div")
    Dom.add_class(tile, "tile")
    Dom.set_style(tile, "background", color)
    Dom.set_text(tile, label)
    Dom.listen(tile, "click", fn _ev ->
      move_to_end(tile)
    )
    Dom.append(board, tile)
  end

  fn main() : Unit do
    match Dom.find("board") do
      None -> ()
      Some(board) ->
        add_tile(board, "A", "#e74c3c")
        add_tile(board, "B", "#3498db")
        add_tile(board, "C", "#2ecc71")
        add_tile(board, "D", "#f39c12")
        add_tile(board, "E", "#9b59b6")
    end
  end

end
```

**`index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Tiles</title>
  <style>
    #board { display: flex; gap: 1rem; padding: 1rem; }
    .tile  { width: 64px; height: 64px; border-radius: 8px;
             display: flex; align-items: center; justify-content: center;
             font-size: 1.5rem; color: white; cursor: pointer; }
  </style>
</head>
<body>
  <div id="board"></div>
  <script type="module" src="my_app.mjs"></script>
</body>
</html>
```

Build and open:

```sh
bash build.sh
open index.html
```

The full runnable version lives in `demo_app/dom_demo/`.

---

## Tips

**`Node` can be annotated directly.** Resource types from an external module
can be spelled as `Dom.Node` (or bare `Node`) in type annotations:

<!-- scroll:skip -->
```march
fn highlight(el: Dom.Node) : Unit do
  Dom.add_class(el, "selected")
end
```

Letting inference handle it works too, if you'd rather not annotate:

<!-- scroll:skip -->
```march
fn highlight(el) do
  Dom.add_class(el, "selected")
end
```

**`main` is the entry point.** The emitted `.mjs` calls `<ModuleName>_main()`
at module load time. Name your entry function `main` and it runs automatically.

**All DOM calls are JS-only.** `Dom` functions panic at runtime if the binary
was compiled without `--target js`. Keep DOM logic in files that are never
imported by a native build.
