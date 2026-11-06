---
layout: docs
title: "copy_shared"
permalink: /docs/errors/copy_shared/
---

# `copy_shared`: a function builds a new copy because the value is still shared

March updates a list or tree in place when the function rebuilding it holds the
only reference to it: `List.map` over a list nobody else holds rewrites its
cells instead of allocating new ones (see
[the memory model]({{ site.baseurl }}/docs/memory-model/#when-reuse-fires-vs-falls-back)).
When something else still holds the value, the function quietly allocates a
fresh copy instead. The program is still correct, only slower, with more memory.

This warning comes only from `march --why-copies FILE` (or `--why-copies-json`).
It names the call that copies, the value it could not reuse, and why the value
was still shared:

- it is **used again afterwards** in the same function;
- it is **also passed to the enclosing call**, which holds it until it runs;
- a **closure captured it**, and a closure keeps its own reference.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  fn inc_all(xs : List(Int)) : List(Int) do
    let ys = List.map(xs, fn x -> x + 1)
    let n = List.length(xs)
    List.append(ys, [n])
  end

  fn main(c : Cap(IO.Console)) do
    println(int_to_string(List.length(inc_all([1, 2, 3]))))
  end
end
```

`xs` is used by `List.length` after `List.map` runs, so `List.map` cannot reuse
its cells.

## The fix

Make the call the value's last use. Here, take the length first:

```march
mod Main do
  needs IO.Console

  fn inc_all(xs : List(Int)) : List(Int) do
    let n = List.length(xs)
    let ys = List.map(xs, fn x -> x + 1)
    List.append(ys, [n])
  end

  fn main(c : Cap(IO.Console)) do
    println(int_to_string(List.length(inc_all([1, 2, 3]))))
  end
end
```

When moving the later `let` is safe (it is the only later use, it calls only
functions with no side effects, and it uses nothing bound in between), the
warning carries this move as a fix that `forge fix` can apply. When the value
is used several more times, or a closure captured it, there is no mechanical
fix: decide whether the copy matters, and restructure if it does.
