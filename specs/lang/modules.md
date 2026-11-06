---
layout: docs
title: Module System
nav_order: 5.0
permalink: /docs/modules/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md)

# Module System

A module is a named group of functions, types and constants. Every March file holds
one top-level module, declared with `mod Name do ... end`, and every definition lives
inside a module. Code in another module reaches a definition by its qualified name,
`Math.square(4)`, or brings the name into scope with `import`, `use` or `alias`.

Everything in a module is public unless you mark it private: `pfn` for a function,
`ptype` for a type. `opaque type` keeps a type's name public and hides its
constructors, so other modules can hold a value of the type but can only build or read
one through the module's own functions. A dotted name such as `MyApp.Router` maps to a
file path, `my_app/router.march`, which is how the compiler and `forge` find a module.

This page covers declaring modules, visibility, the ways to bring names into scope,
multi-file projects and module signatures. The formal rules are in
[`core-march.md`](core-march.md) §4.7 (declaration, nesting and name resolution) and
[`core-march-types.md`](core-march-types.md) §2.5 (visibility); this page teaches the
surface syntax.

## On this page

**Start here**

- [Which form do I need?](#which-form-do-i-need)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)

**Everyday modules**

- [Declaring a Module](#declaring-a-module)
- [Qualified Access](#qualified-access)
- [Visibility](#visibility): `pfn`, `ptype` and `opaque type`
- [Module-Level Constants](#module-level-constants)

**Bringing names into scope**

- [`import`](#import)
- [`use`](#use)
- [`alias`](#alias)
- [A Full Example](#a-full-example)

**Projects**

- [Multi-File Projects](#multi-file-projects)
- [Module Signatures](#module-signatures)

**Reference**

- [Errors you'll see](#errors-youll-see)
- [See also](#see-also)

## Which form do I need?

| You want | Write |
|---|---|
| A group of related functions and types | `mod Name do ... end`, one top-level `mod` per file |
| A function from another module | Its qualified name: `Math.square(4)` |
| A helper only this module can call | `pfn helper(...)` |
| A type other modules cannot name at all | `ptype T = ...` |
| A type other modules can name but not build or take apart | `opaque type T = ...` |
| A constant the whole module shares | A module-level `let`: `let max_items = 1000` |
| Another module's names without the prefix | `import Mod`, or `import Mod, only: [f, g]` |
| The same, with glob and brace selectors | `use Mod.*`, `use Mod.{f, g}` |
| A shorter name for a long module path | `alias Very.Long.Name, as: Short` |
| A program split across files | `mod MyApp.Router` in `my_app/router.march`; `forge build` finds it |

## How it fits with the rest of March

| Concept | Where modules meet it | Chapter |
|---|---|---|
| **Type system** | `ptype` and `opaque type` decide which types and constructors other modules see; a type from another module is written `Http.Method`. | [Type System]({{ site.baseurl }}/docs/types/#opaque-types) |
| **Capabilities** | A module lists the capabilities its code uses with `needs IO.Console`, and the compiler checks the module's code against that list. `cap no_panic` and the other module caps restrict what a whole module may do. | [Capabilities]({{ site.baseurl }}/docs/capabilities/) |
| **Interfaces** | An `interface` and its `impl`s are declared inside modules like functions are, and a type's `derive` line sits in the module that declares the type. | [Interfaces]({{ site.baseurl }}/docs/interfaces/) |
| **Standard library** | Every stdlib module is reachable by its qualified name with no import; `import List, only: [map]` works on it like on your own files. | [Stdlib Guide]({{ site.baseurl }}/docs/stdlib-guide/) |
| **Tooling** | `forge build` maps module names to files for you; `forge search` finds a function across modules by name or type. | [Tooling]({{ site.baseurl }}/docs/tooling/) |

---

## Declaring a Module

Every March file begins with a `mod` declaration:

```march
mod MyApp do
  -- definitions here
end
```

Module names can be dotted to group related modules. A file holds only one top-level
`mod`, so the two blocks below are two files, not one file to paste;
[Multi-File Projects](#multi-file-projects) has the name-to-file convention:

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

`Math` is nested inside `Main` here because a file can hold only one top-level `mod`;
two top-level modules in one file is a parse error. Two top-level modules go in two
files, found through `MARCH_LIB_PATH`; see [Multi-File Projects](#multi-file-projects).

Nested module access chains:

```march
MyApp.Router.dispatch(conn, request)
```

A misspelled module name is a compile error that suggests the closest module:
``Unknown module `Lsit`. Did you mean `List`?``

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

A `pfn` function, or a private module-level `let` value, cannot be called or referenced
from outside its module. A qualified reference to one is a compile error,
``Function `hash` is private to module `Passwords`.``, whether the module is nested in
the same file or lives in another file.

**What `ptype` hides depends on where the type is declared.**

- **In a module compiled from your source** (a nested `mod`, or a file found through
  `MARCH_LIB_PATH`): other modules can neither name the type nor use its
  constructors. Naming it in an annotation gives a misleading ``Unknown module `T`.``
  rather than a message about privacy; using a constructor gives
  ``I don't know a constructor called `T.Tok`.``
- **In a stdlib module:** `ptype` hides nothing. `stdlib/bigint.march` declares
  `ptype BigInt`, yet user code can write `BigInt.BigInt` in an annotation and build
  one with `BigInt.BigInt(true, [1])`. `core-march-types.md` §2.5 calls this the
  opaque-type imbalance.

Use `opaque type` when the goal is to hide the constructors. No stdlib module declares
an `opaque type` today.

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
  -- use `Token.make` to build one and `Token.value` to read it; `Token(_)`
  -- itself is not accessible outside the defining module.
  fn process(t) do
    println(Token.value(t))
  end

  fn main() do
    process(Token.make("hi"))    -- prints "hi"
  end
end
```

Outside `Token`, a caller can write the type as `Token.Token` or as the bare `Token`
that `Token.make` returns; both are the same type. The constructor stays hidden from
other files too: `Token.Token("bypass")` in an unrelated file that reaches `Token`
through `MARCH_LIB_PATH` is rejected.

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

`import`, `use` and `alias` only find a module that has its own `.march` file. A `mod`
nested in the same file is reached by its qualified name instead; `import Inner` on
one reports ``Module `Inner` not found (looked for `inner.march` in the source directory).``

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

`examples/modules.march` is a smaller example: qualified access, two levels of nesting
and `pfn`. The example below adds `import` and `alias`, so it follows the rule from
[`import`](#import): those only resolve a module with its own file, never a `mod`
nested in the same file. It reaches its nested `MathUtils` by qualified name, and
points `import` and `alias` at the stdlib's `List`:

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

  -- 1. Qualified access: the only way to reach an in-file nested module
  fn demo_qualified() : Int do
    let a = MathUtils.square(4)
    let b = MathUtils.cube(3)
    a + b      -- 43
  end

  -- 2. Import specific names only. This must target a module with its own
  -- file (here, the stdlib's List); `import MathUtils` would be rejected
  -- with `` Module `MathUtils` not found (looked for `math_utils.march` …) ``
  -- even though MathUtils is declared a few lines up, in this same file.
  import List, only: [length]

  fn demo_import_only() : Int do
    length([1, 2, 3, 4, 5, 6, 7])   -- 7
  end

  -- 3. Alias: the same file rule as import
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

`forge build` handles this automatically; see [Tooling]({{ site.baseurl }}/docs/tooling/).

Module names map to file paths by convention: `MyApp.Router` → `my_app/router.march`, `MyApp.Templates.Layout` → `my_app/templates/layout.march`.

---

## Module Signatures

A `sig` declaration defines an abstract interface for a module, a named signature separate from the implementation:

```march
sig Collection do
  type Elem
  fn insert : Elem -> List(Elem) -> List(Elem)
  fn member : Elem -> List(Elem) -> Bool
end
```

Signatures are used for compile-time abstraction and caching: downstream code that depends on a `sig` only needs to recompile when the signature changes, not when the implementation changes.

---

## Errors you'll see

The [Error Messages tour]({{ site.baseurl }}/docs/error-messages/) walks through what the compiler prints for these mistakes, each with a program you can edit and re-check in the browser:

- [A misspelled module name, and the "did you mean" that follows]({{ site.baseurl }}/docs/error-messages/#misspelled-module)
- [A function that uses a capability its module's `needs` lines leave out]({{ site.baseurl }}/docs/error-messages/#missing-needs)

These codes have their own page, the same text `march --explain` prints:

- [`unknown_qualified_name`]({{ site.baseurl }}/docs/errors/unknown_qualified_name/): a qualified name the module does not have, or a private function called from outside its module
- [`module_keyword`]({{ site.baseurl }}/docs/errors/module_keyword/): `module Name do` instead of `mod Name do`
- [`cap_needs`]({{ site.baseurl }}/docs/errors/cap_needs/): a module uses a capability it does not declare with `needs`

---

## See also

- [Type System](type-system.md): `opaque type`, `ptype` and qualified type names
- [Capabilities](capabilities.md): the `needs` lines at the top of a module, and module caps such as `cap no_panic`
- [Interfaces](interfaces.md): `interface` and `impl` for ad-hoc polymorphism
- [Stdlib Guide](../../docs/stdlib.md): the modules March ships with
- [Getting Started](../../docs/getting-started.md): creating a project with forge
- [`core-march.md`](core-march.md) §4.7: the formal rules for declaring, nesting and resolving modules
