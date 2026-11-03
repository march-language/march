---
layout: docs
title: "cap_ceiling"
permalink: /docs/errors/cap_ceiling/
---

# `cap_ceiling`: a module uses a capability its `needs` lines do not declare

Each module declares, with `needs`, the capabilities its code may use. This
error reports a module whose code (a function body, or a module-level `let`)
reaches a capability above that ceiling, here a nested module whose parent
declares the capability but which does not. The code carries the capability
after a colon (`cap_ceiling:IO.FileRead`), and the fix inserts the missing
`needs` line. When `cap_needs` reports the same gap at the call, only that error is
shown.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  needs IO.FileRead
  mod Config do
    needs IO.Console
    fn motd() : String do
      match File.read("/etc/motd") do
        Ok(s) -> s
        Err(_) -> ""
      end
    end
  end

  fn main(_c : Cap(IO.Console), _r : Cap(IO.FileRead)) do
    println(Config.motd())
  end
end
```

## The fix

Declare the capability in the module whose code uses it. The outer module's
`needs IO.FileRead` does not cover `Config`: each module declares its own.

```march
mod Main do
  needs IO.Console
  needs IO.FileRead
  mod Config do
    needs IO.Console
    needs IO.FileRead
    fn motd() : String do
      match File.read("/etc/motd") do
        Ok(s) -> s
        Err(_) -> ""
      end
    end
  end

  fn main(_c : Cap(IO.Console), _r : Cap(IO.FileRead)) do
    println(Config.motd())
  end
end
```

## Why the rule exists

A module's header is its declaration of authority: a reviewer can read the
`needs` lines and know every capability its code can exercise without reading
the bodies. Code that exceeds them would make the header a lie.

See also: [the language reference](../capabilities.md).
