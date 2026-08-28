---
layout: docs
title: Module System
nav_order: 5.0
permalink: /docs/modules/
---

# Module System

March has an Elixir-inspired module system. Modules are the primary unit of code organization, and all definitions live inside a module.

---

## Declaring a Module

Every March file begins with a `mod` declaration:

```march
mod MyApp do
  -- definitions here
end
```

Modules can be dotted for hierarchical organization. **Each of these lives in
its own file** (a `.march` file may have only one top-level `mod`), so this
is two files' contents shown together, not one file to paste verbatim (see
"Multi-File Projects" below for the name-to-filename convention):

```march
-- my_app/router.march
mod MyApp.Router do
  -- router logic
end
```

```march
-- my_app/templates/layout.march
mod MyApp.Templates.Layout do
  -- layout templates
end
```

Modules can also be nested inline:

```march
mod Outer do
  mod Inner do
  needs IO.Console
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

```march
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

`pfn` functions (and private module-level `let` values) cannot be called or
referenced from outside their declaring module: a qualified cross-module
reference to one is a hard typecheck error, `` Function `name` is private to
module `Mod`. `` This is enforced identically whether the private member lives
in the same file (a nested `mod`) or a separate file reached by qualification.

**`ptype` hides less than the name suggests, and does not hide the constructor
at all.** A `ptype`'s bare type NAME is always usable in a cross-module type
annotation regardless of its declared visibility. And a plain `ptype`'s
constructor is **not private either**: every variant defaults to public
visibility unless you use the separate `opaque type` form (below), which does
force its variants private. In practice, a plain `ptype` and a public `type`
are today observably identical to code outside the module. Use `opaque type`
if hiding the constructor is the actual goal.

For types that should expose the name but hide the constructors, use `opaque`:

```march
mod Main do
  needs IO.Console
  mod Token do
    opaque type Token = Token(String)

    fn make(raw : String) : Token do Token(raw) end
    fn value(t : Token) : String do
      match t do Token(s) -> s end
    end
  end

  -- Outside Token: values flow through the module's own functions. Callers
  -- use `Token.make` to build one and `Token.value` to read it, rather than
  -- constructing `Token(_)` directly.
  fn process(t) do
    println(Token.value(t))
  end

  fn main() do
    process(Token.make("hi"))    -- prints "hi"
  end
end
```

An explicit qualified annotation like `t : Token.Token` in a caller outside the `Token`
module unifies correctly with the bare `Token` type `Token.make` returns, so you can
write either form. (One caveat on cross-file enforcement is in
[Known limitations](#known-limitations) below.)

---

## Qualified Access

Call functions or access types from another module using `.`:

```march
mod Main do
  needs IO.Console
  mod Math do
    fn square(n : Int) : Int do n * n end
    fn cube(n : Int) : Int do n * n * n end
  end

  fn main() do
    let s = Math.square(4)   -- 16
    let c = Math.cube(3)     -- 27
    println(int_to_string(s + c))    -- 43
  end
end
```

(`Math` is nested inside `Main` here because a single `.march` file may have
only **one** top-level `mod`; see "A Full Example" below. Two truly
separate, same-named-at-top-level modules like `Math` and `Main` would
instead each live in their own file, resolved via `MARCH_LIB_PATH`; see
"Multi-File Projects" below.)

Nested module access chains:

```march
MyApp.Router.dispatch(conn, request)
```

---

## import

`import` brings names from a module into the current scope. It works like Elixir's `import`:

```march
-- Import all public names from MathUtils:
import MathUtils

fn demo() do
  let s = square(5)   -- no module prefix needed
  let c = cube(3)
  s + c
end
```

Import only specific names:

```march
import MathUtils, only: [square, cube]
import String, only: [trim, split, to_uppercase]
```

Import everything except specific names:

```march
import String, except: [dangerous_fn]
```

Dotted import with brace selector:

```march
import String.{trim, split}
import MyApp.Utils.{format, parse}
```

`import` statements can appear anywhere inside a module body. Their scope is the rest of the module from that point.

---

## use

`use` is the other import mechanism. It brings names into scope but is more explicit about source:

```march
use List.*                    -- import all from List
use List.{map, filter}        -- import specific names
use List.map                  -- import single name
use A.B.C.*                   -- dotted path, all names
```

The difference between `use` and `import` is primarily stylistic: `import` is Elixir-style with keyword options (`only:`, `except:`), while `use` is ML-style with glob and brace selectors.

---

## alias

`alias` gives a module a shorter name for the rest of the scope:

```march
alias Very.Long.Module.Name as Short

fn demo() do
  Short.do_something()
end
```

Elixir-style comma form:

```march
alias Very.Long.Module.Name, as: Short
```

Auto-alias to last segment:

```march
alias MyApp.Data.Repository
-- Now Repository is available as the alias
```

Aliases are useful when a module name is long or conflicts with another name in scope.

---

## A Full Example

This example demonstrates qualified access **together with** `import`/`alias`. One
subtlety to know: `import`/`use`/`alias` only resolve an actual `.march` FILE, never
an in-file nested `mod`, so the nested `MathUtils` below can only be reached by
qualification, and the `import`/`alias` demos instead target `List`, a real stdlib
module:

```march
mod Example do
  needs IO.Console

  mod MathUtils do
    fn square(x : Int) : Int do x * x end
    fn cube(x : Int) : Int do x * x * x end
    fn abs_val(n : Int) : Int do
      if n < 0 do 0 - n else n end
    end
  end

  -- 1. Qualified access — the ONLY way to reach an in-file nested module
  fn demo_qualified() : Int do
    let a = MathUtils.square(4)
    let b = MathUtils.cube(3)
    a + b      -- 43
  end

  -- 2. Import specific names only — MUST target a real file (here, the
  -- stdlib's List module); `import MathUtils` here would reject with
  -- `` Module `MathUtils` not found (looked for `math_utils.march` …) ``
  -- even though MathUtils plainly exists a few lines up, in this same file.
  import List, only: [length]

  fn demo_import_only() : Int do
    length([1, 2, 3, 4, 5, 6, 7])   -- 7
  end

  -- 3. Alias — same file-resolution rule as import
  alias List, as: L

  fn demo_alias() : Int do
    L.length([1, 2, 3, 4, 5, 6])   -- 6
  end

  fn main() : Int do
    let total = demo_qualified() + demo_import_only() + demo_alias()
    println(int_to_string(total))   -- 56
    total
  end

end
```

---

## Module Signatures

A `sig` declaration defines an abstract interface for a module: a named signature separate from the implementation:

```march
sig Collection do
  type Elem
  fn insert : Elem -> List(Elem) -> List(Elem)
  fn member : Elem -> List(Elem) -> Bool
end
```

Signatures are used for compile-time abstraction and caching: downstream code that depends on a `sig` only needs to recompile when the signature changes, not when the implementation changes.

---

## Multi-File Projects

In a `forge` project, each file typically contains one module. Files are discovered automatically via `MARCH_LIB_PATH`.

```
my_app/
├── lib/
│   ├── my_app.march          -- mod MyApp do ... end
│   ├── my_app/router.march   -- mod MyApp.Router do ... end
│   └── my_app/templates.march-- mod MyApp.Templates do ... end
```

Build with:
```sh
MARCH_LIB_PATH=lib march --compile -o my_app lib/my_app.march
```

`forge build` handles this automatically.

Module names map to file paths by convention: `MyApp.Router` → `my_app/router.march`, `MyApp.Templates.Layout` → `my_app/templates/layout.march`.

---

## Module-Level Constants

`let` at module level defines a constant accessible throughout the module and (if public) from outside:

```march
mod Main do
  needs IO.Console
  mod Config do
    let version   = "1.0.0"
    let max_items = 1000
    let base_url  = "https://api.example.com"
  end

  -- Access from outside:
  fn main() do
    println(Config.version)   -- "1.0.0"
  end
end
```

---

## Known limitations

**`opaque type` doesn't stop a cross-file bypass.** Constructor-hiding is enforced
for a same-file reference, but not yet against a qualified reference to the
constructor from a *separate* file reached via `MARCH_LIB_PATH`/auto-discovery;
e.g. `OqToken.Token("bypass")` from an unrelated sibling file will typecheck and
construct a real value today, even though `Token`'s constructor is declared
`opaque`. Don't rely on `opaque type` by itself for encapsulation across a multi-file
project until this is closed.

---

## Next Steps

- [Interfaces](interfaces.md): `interface` and `impl` for ad-hoc polymorphism
- [Getting Started](getting-started.md): creating a project with forge
- [Standard Library](stdlib.md): modules you get for free
