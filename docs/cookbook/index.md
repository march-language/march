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
| [HTTP](http/) | Making requests, handling responses, simple servers |
| [Concurrency](concurrency/) | `Task.async`/`await`, actors, channels |
| [Capabilities](capabilities/) | The capability system, `needs`, proof caps |
| [Linear Types](linear-types/) | `linear type`, `always_linear`, typestate handles |
| [Vault](vault/) | In-memory key-value store: CRUD, TTL, namespacing |
| [HTML](html/) | `~H` sigil, `Html` module, CSRF, layouts |

---

## New to March?

Start with one of these orientation guides:

- [Coming from Python or TypeScript](../coming-from-python/) — maps familiar concepts to March idioms
- [Coming from Haskell, Elixir, or OCaml](../coming-from-fp/) — syntax cheatsheet and key differences

---

## Using this cookbook

Every `march` code block has **copy** and **run** buttons that appear on hover. Clicking **run** opens the interactive interpreter panel on the right and evaluates the snippet immediately. You can edit the code in the panel and press **run** again to try variations.

The panel is lazy — the interpreter bundle only loads on your first **run** click.
