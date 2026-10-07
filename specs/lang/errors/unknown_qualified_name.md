---
layout: docs
title: "unknown_qualified_name"
permalink: /docs/errors/unknown_qualified_name/
---

# `unknown_qualified_name`: a qualified name does not exist in that module

A qualified reference `Module.name` names a module that exists but does not
export `name`. When a close match exists the message suggests it.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  fn main(_console : Cap(IO.Console)) do
    println(int_to_string(List.size([1, 2, 3])))
  end
end
```

## The fix

Use the name the module actually exports. `forge search <name>` and the
module's stdlib page list what is there.

```march
mod Main do
  needs IO.Console
  fn main(_console : Cap(IO.Console)) do
    println(int_to_string(List.length([1, 2, 3])))
  end
end
```

## Why the rule exists

Qualified names are resolved statically; there is no dynamic lookup and
no fallback to a global of the same name, so a misspelled or missing export
is reported at the reference instead of failing at run time.

See also: [the language reference](../modules.md).
