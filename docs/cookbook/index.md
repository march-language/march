---
layout: cookbook
title: Cookbook
permalink: /docs/cookbook/
---

# March Cookbook

Practical recipes for getting things done in March. Each chapter covers one topic with short runnable snippets and longer copy-and-run examples. Click **run** on any code block to try it in the interactive panel on the right.

---

## Chapters

| Chapter | What you'll learn |
|---------|------------------|
| [Basics](basics/) | Functions, types, pattern matching, `let?`, modules |
| [Strings](strings/) | Concatenation, interpolation, parsing, formatting |
| [CLI](cli/) | Reading args, flag parsing, files, exit codes |
| [HTTP](http/) | Making requests, handling responses, simple servers |
| [JSON API](json-api/) | Calling an API and decoding the JSON response |
| [Files](files/) | Reading a CSV, aggregating columns, walking a directory |
| [Config](config/) | Parsing TOML/YAML with environment overrides |
| [Concurrency](concurrency/) | `Task.async`/`await`, actors, channels |
| [Capabilities](capabilities/) | The capability system, `needs`, proof caps |
| [Linear Types](linear-types/) | `linear type`, `always_linear`, typestate handles |
| [Vault](vault/) | In-memory key-value store: CRUD, TTL, namespacing |
| [HTML](html/) | `~H` sigil, `Html` module, CSRF, layouts |
| [DOM](dom/) | Browser DOM with `--target js`: elements, events, animation |
| [Parallel Data](parallel-data/) | `RRB.Vec` + `Parallel` module: pmap, preduce, psum, pcount |
| [Numeric Data](numeric-data/) | `NativeArray` + `Simd`: fast numeric loops, narrow widths, dot product, byte scanning |

---

## New to March?

Start with one of these orientation guides:

- [Coming from Python](../coming-from-python/): dynamic to static typing, no exceptions, no classes
- [Coming from TypeScript](../coming-from-typescript/): sum types, `Result` vs `try/catch`, modules instead of classes
- [Coming from Haskell, Elixir, or OCaml](../coming-from-fp/): syntax cheatsheet and key differences

---

## Using this cookbook

Every `march` code block has **copy** and **run** buttons that appear on hover. Clicking **run** opens the interactive interpreter panel on the right and evaluates the snippet immediately. You can edit the code in the panel and press **run** again to try variations.

The panel is lazy: the interpreter bundle only loads on your first **run** click.
