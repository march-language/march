---
layout: cookbook
title: "Cookbook: DOM"
permalink: /docs/cookbook/dom/
---

# DOM

March can target the browser via `--target js`. The `Js.Dom` stdlib module exposes
the browser's Document Object Model as typed March functions, no JavaScript
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
it runs after the DOM is parsed; no `DOMContentLoaded` listener needed.

You also need two runtime files alongside the `.mjs`:

| File | Where to get it |
|------|----------------|
| `march_runtime.mjs` | `runtime/march_runtime.mjs` in the March repo |
| `march_dom.mjs` | `runtime/march_dom.mjs` in the March repo |

Copy them next to your `index.html`. The build script in
`demo_app/dom_demo/build.sh` does this automatically.

---

## Querying the DOM

`Js.Dom.find` looks up an element by `id` and returns `Option(Node)`:

```march
match Js.Dom.find("my-button") do
  None    -> ()
  Some(btn) -> Js.Dom.set_text(btn, "Ready")
end
```

`Js.Dom.select` takes any CSS selector:

```march
match Js.Dom.select(".active") do
  None    -> ()
  Some(el) -> Js.Dom.add_class(el, "highlight")
end
```

`Js.Dom.select_all` returns every matching element as a `List(Node)`:

```march
let items = Js.Dom.select_all("li.todo")
-- items : List(Node)
```

---

## Creating elements

Build a node tree with `Js.Dom.create`, set it up, then attach it:

```march
let div = Js.Dom.create("div")
Js.Dom.add_class(div, "card")
Js.Dom.set_text(div, "Hello!")
Js.Dom.set_style(div, "color", "royalblue")

match Js.Dom.find("root") do
  None         -> ()
  Some(root) -> Js.Dom.append(root, div)
end
```

`Js.Dom.text_node` creates a bare text node when you want to mix text and
elements without wrapping them in a container.

---

## Tree operations

| Function | What it does |
|----------|-------------|
| `Js.Dom.append(parent, child)` | Add `child` as the last child |
| `Js.Dom.prepend(parent, child)` | Add `child` as the first child |
| `Js.Dom.remove(el)` | Detach `el` from its parent |
| `Js.Dom.remove_child(parent, child)` | Remove a known direct child |
| `Js.Dom.clear(el)` | Remove all children |
| `Js.Dom.parent(el)` | `Option(Node)`: parent or `None` |
| `Js.Dom.children(el)` | `List(Node)`: direct element children |
| `Js.Dom.clone(el)` | Deep-copy a node |

Moving a node is just `remove` + `append`, or only `append` if you
know the parent (the browser removes it from the old position automatically):

```march
-- Move the last tile to the front
match Js.Dom.find("board") do
  None -> ()
  Some(board) ->
    match Js.Dom.last_child(board) do
      None       -> ()
      Some(tile) -> Js.Dom.prepend(board, tile)
    end
end
```

---

## Attributes, classes, and styles

```march
-- Attributes
Js.Dom.set_attr(el, "href", "#section-2")
Js.Dom.set_attr(el, "aria-hidden", "true")
let href = Js.Dom.get_attr(el, "href")  -- Option(String)

-- CSS classes
Js.Dom.add_class(el, "active")
Js.Dom.remove_class(el, "inactive")
Js.Dom.toggle_class(el, "open")
let is_open = Js.Dom.has_class(el, "open")  -- Bool

-- Inline styles
Js.Dom.set_style(el, "background", "#3498db")
Js.Dom.set_style(el, "transform", "scale(1.05)")
Js.Dom.set_style(el, "transform", "")   -- empty string removes the property
```

---

## Events

`Js.Dom.listen` attaches a handler that receives the `Event`:

```march
Js.Dom.listen(btn, "click", fn ev ->
  Js.Dom.prevent_default(ev)
  -- ...
)
```

The handler is a regular March lambda, so it can close over local variables:

```march
fn add_item(list, label: String) : Unit do
  let li = Js.Dom.create("li")
  Js.Dom.set_text(li, label)
  Js.Dom.listen(li, "click", fn _ev ->
    Js.Dom.remove(li)
  )
  Js.Dom.append(list, li)
end
```

Common events: `"click"`, `"input"`, `"change"`, `"keydown"`, `"keyup"`,
`"submit"`, `"mouseover"`, `"mouseout"`, `"focus"`, `"blur"`.

To read back the element that fired the event:

```march
Js.Dom.listen(container, "click", fn ev ->
  let target = Js.Dom.event_target(ev)
  Js.Dom.add_class(target, "selected")
)
```

`Js.Dom.event_key` reads the key that triggered a `"keydown"`/`"keyup"` event
(e.g. `"ArrowLeft"`, `"a"`, `" "` for space):

```march
Js.Dom.listen(Js.Dom.body(), "keydown", fn ev ->
  match Js.Dom.event_key(ev) do
    "ArrowLeft"  -> move_left()
    "ArrowRight" -> move_right()
    _            -> ()
  end
)
```

---

## Form inputs

```march
match Js.Dom.find("search-box") do
  None -> ()
  Some(input) ->
    Js.Dom.listen(input, "input", fn _ev ->
      let query = Js.Dom.get_value(input)
      run_search(query)
    )
end
```

`Js.Dom.set_value` writes back to the input's `.value` property.

---

## Timers and animation

```march
-- Run once after 500 ms
Js.Dom.set_timeout(500, fn _ ->
  Js.Dom.set_text(status, "Done!")
)

-- Run every 1 s
Js.Dom.set_interval(1000, fn _ ->
  tick()
)

-- Smooth animation at 60 fps
fn animate(el) : Unit do
  Js.Dom.on_frame(fn _ ->
    let cur = Js.Dom.get_style(el, "opacity")
    let next = float_to_string(Option.unwrap_or(string_to_float(cur), 1.0) -. 0.02)
    let _ = Js.Dom.set_style(el, "opacity", next)
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
    match Js.Dom.parent(tile) do
      None    -> ()
      Some(p) ->
        Js.Dom.remove(tile)
        Js.Dom.append(p, tile)
    end
  end

  fn add_tile(board, label: String, color: String) : Unit do
    let tile = Js.Dom.create("div")
    Js.Dom.add_class(tile, "tile")
    Js.Dom.set_style(tile, "background", color)
    Js.Dom.set_text(tile, label)
    Js.Dom.listen(tile, "click", fn _ev ->
      move_to_end(tile)
    )
    Js.Dom.append(board, tile)
  end

  fn main() : Unit do
    match Js.Dom.find("board") do
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
can be spelled as `Js.Dom.Node` (or bare `Node`) in type annotations:

```march
fn highlight(el: Js.Dom.Node) : Unit do
  Js.Dom.add_class(el, "selected")
end
```

Letting inference handle it works too, if you'd rather not annotate:

```march
fn highlight(el) do
  Js.Dom.add_class(el, "selected")
end
```

**`main` is the entry point.** The emitted `.mjs` calls `<ModuleName>_main()`
at module load time. Name your entry function `main` and it runs automatically.

**All DOM calls are JS-only.** `Js.Dom` functions panic at runtime if the binary
was compiled without `--target js`. Keep DOM logic in files that are never
imported by a native build.
