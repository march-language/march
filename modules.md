---
layout: page
title: Module System
nav_order: 8
---

# Module System

March has an Elixir-inspired module system. Modules are the primary unit of code organization, and all definitions live inside a module.

---

## Declaring a Module

Every March file begins with a `mod` declaration:

```elixir
mod MyApp do
  -- definitions here
end
```

Modules can be dotted for hierarchical organization:

```elixir
mod MyApp.Router do
  -- router logic
end

mod MyApp.Templates.Layout do
  -- layout templates
end
```

Modules can also be nested inline:

```elixir
mod Outer do
  mod Inner do
    fn greet() do println("from Inner") end
  end

  fn main() do
    Inner.greet()    -- qualified access
  end
end
```

---

## Visibility

By default, all definitions are **public** (accessible from outside the module). To make something private, use `pfn` for functions or `ptype` for types:

```elixir
mod Passwords do
  -- Public API:
  fn verify(plain : String, stored : String) : Bool do
    hash(plain) == stored
  end

  -- Private implementation detail:
  pfn hash(s : String) : String do
    Crypto.sha256(s)
  end
end
```

`pfn` functions cannot be called from outside their module. `ptype` makes both the type name and its constructors private.

For types that should expose the name but hide the constructors, use `opaque`:

```elixir
mod Token do
  opaque type Token = Token(String)

  fn make(raw : String) : Token do Token(raw) end
  fn value(t : Token) : String do
    match t do Token(s) -> s end
  end
end

-- Outside Token: can use Token as a type, but cannot construct Token(_) directly
fn process(t : Token.Token) : () do
  println(Token.value(t))
end
```

---

## Qualified Access

Call functions or access types from another module using `.`:

```elixir
mod Math do
  fn square(n : Int) : Int do n * n end
  fn cube(n : Int) : Int do n * n * n end
end

mod Main do
  fn main() do
    let s = Math.square(4)   -- 16
    let c = Math.cube(3)     -- 27
    println(int_to_string(s + c))
  end
end
```

Nested module access chains:

```elixir
MyApp.Router.dispatch(conn, request)
```

---

## import

`import` brings names from a module into the current scope. It works like Elixir's `import`:

```elixir
-- Import all public names from MathUtils:
import MathUtils

fn demo() do
  let s = square(5)   -- no module prefix needed
  let c = cube(3)
  s + c
end
```

Import only specific names:

```elixir
import MathUtils, only: [square, cube]
import String, only: [length, split, upcase]
```

Import everything except specific names:

```elixir
import String, except: [dangerous_fn]
```

Dotted import with brace selector:

```elixir
import String.{length, split}
import MyApp.Utils.{format, parse}
```

`import` statements can appear anywhere inside a module body. Their scope is the rest of the module from that point.

---

## use

`use` is the other import mechanism. It brings names into scope but is more explicit about source:

```elixir
use List.*                    -- import all from List
use List.{map, filter}        -- import specific names
use List.map                  -- import single name
use A.B.C.*                   -- dotted path, all names
```

The difference between `use` and `import` is primarily stylistic — `import` is Elixir-style with keyword options (`only:`, `except:`), while `use` is ML-style with glob and brace selectors.

---

## alias

`alias` gives a module a shorter name for the rest of the scope:

```elixir
alias Very.Long.Module.Name as Short

fn demo() do
  Short.do_something()
end
```

Elixir-style comma form:

```elixir
alias Very.Long.Module.Name, as: Short
```

Auto-alias to last segment:

```elixir
alias MyApp.Data.Repository
-- Now Repository is available as the alias
```

Aliases are useful when a module name is long or conflicts with another name in scope.

---

## A Full Example

From [examples/modules.march](../examples/modules.march):

```elixir
mod Example do

  mod MathUtils do
    fn square(x : Int) : Int do x * x end
    fn cube(x : Int) : Int do x * x * x end
    fn abs_val(n : Int) : Int do
      if n < 0 do 0 - n else n end
    end
  end

  mod Greet do
    fn prefix() : Int do 1000 end
  end

  -- 1. Qualified access
  fn demo_qualified() : Int do
    let a = MathUtils.square(4)
    let b = MathUtils.cube(3)
    a + b      -- 43
  end

  -- 2. Import all
  import MathUtils

  fn demo_import_all() : Int do
    square(5) + cube(2)   -- 33
  end

  -- 3. Import specific names only
  import MathUtils, only: [abs_val]

  fn demo_import_only() : Int do
    abs_val(0 - 7)   -- 7
  end

  -- 4. Alias
  alias MathUtils, as: M

  fn demo_alias() : Int do
    M.square(6)   -- 36
  end

  fn main() : Int do
    demo_qualified() + demo_import_all() + demo_import_only() + demo_alias()
  end

end
```

---

## Module Signatures

A `sig` declaration defines an abstract interface for a module — a named signature separate from the implementation:

```elixir
sig Collection do
  type Elem
  fn insert : Elem -> List(Elem) -> List(Elem)
  fn member : Elem -> List(Elem) -> Bool
end
```

Signatures are used for compile-time abstraction and caching — downstream code that depends on a `sig` only needs to recompile when the signature changes, not when the implementation changes.

---

## Multi-File Projects

In a `forge` project, each file typically contains one module. Files are discovered automatically via `MARCH_LIB_PATH`.

```
my_app/
├── src/
│   ├── my_app.march          -- mod MyApp do ... end
│   ├── my_app/router.march   -- mod MyApp.Router do ... end
│   └── my_app/templates.march-- mod MyApp.Templates do ... end
```

Build with:
```sh
MARCH_LIB_PATH=src ./_build/default/bin/main.exe --compile -o my_app src/my_app.march
```

`forge build` handles this automatically.

Module names map to file paths by convention: `MyApp.Router` → `my_app/router.march`, `MyApp.Templates.Layout` → `my_app/templates/layout.march`.

---

## Module-Level Constants

`let` at module level defines a constant accessible throughout the module and (if public) from outside:

```elixir
mod Config do
  let version   = "1.0.0"
  let max_items = 1000
  let base_url  = "https://api.example.com"
end

-- Access from outside:
println(Config.version)
```

---

## Next Steps

- [Interfaces](interfaces.md) — `interface` and `impl` for ad-hoc polymorphism
- [Getting Started](getting-started.md) — creating a project with forge
- [Standard Library](stdlib.md) — modules you get for free
