---
layout: docs
title: Module System
nav_order: 5.0
permalink: /docs/modules/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md)

# Module System

March has an Elixir-inspired module system. Modules are the primary unit of code organization, and all definitions live inside a module.

> **Normative cross-references.** This chapter is the tutorial-level
> introduction. The conformance-tested core references cover the same ground
> with implementation citations and a runnable corpus: `specs/lang/core-march.md`
> §4.7 ("Module declaration, nesting, and name resolution") and §4.7.1
> (`use`/`import`/`alias` selectors and the file-based resolver pre-pass)
> document the OPERATIONAL rules; `specs/lang/core-march-types.md` §2.5
> ("Module visibility, the opaque-type imbalance, and the
> no-per-module-type-namespace design point") documents the TYPING rules,
> including the precise visibility enforcement described below and the
> opaque-type constructor-hiding gap noted in the "Opaque Types" section.

---

## Declaring a Module

Every March file begins with a `mod` declaration:

```march
mod MyApp do
  -- definitions here
end
```

Modules can be dotted for hierarchical organization. **Each of these lives in
its own file** (one top-level `mod` per file, see "One-mod-per-file" via
`core-march.md` §4.7, so this is two files' contents shown together, not one
file to paste verbatim; see "Multi-File Projects" below for the
name-to-filename convention):

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
module `Mod`. `` (`load_module_into_env`'s `ex_public` gate,
`lib/typecheck/typecheck.ml:657–692`; cross-referenced in full, with the
exact commit that landed the enforcement, in `core-march-types.md` §2.5).
This is enforced identically whether the private member lives in the same
file (a nested `mod`) or a separate file reached by qualification.

**`ptype` hides the type from OUTSIDE annotation use less than the name
above suggests, and does not hide the constructor at all.** Specifically, per
live verification (`core-march-types.md` §2.5): a `ptype`'s bare type NAME is
never gated (`ExType` is intentionally left with no gate in `load_module_into_env`,
so it remains usable in a cross-module annotation regardless of `Public`/
`Private`); this is the "opaque-type imbalance" the typing reference names
explicitly. And a plain `ptype`'s constructor is **not actually private
either**: the grammar defaults every variant's own visibility (`var_vis`) to
`Public` regardless of the enclosing type's `Private` marking; only the
separate `opaque type` form (below) forces `var_vis = Private` on its
variants. So a plain `ptype`'s privacy currently only affects whether the
bare type name is added to its module's `pub_set` (which the `ExType` gate
ignores anyway), meaning a plain `ptype` and a public `type` are, today,
observably identical to code outside the module. Use `opaque type` (below)
if hiding the constructor is the actual goal.

For types that should expose the name but hide the constructors, use `opaque`:

```march
mod Main do
  mod Token do
    opaque type Token = Token(String)

    fn make(raw : String) : Token do Token(raw) end
    fn value(t : Token) : String do
      match t do Token(s) -> s end
    end
  end

  -- Outside Token: the INTENT is that values flow only through the module's
  -- own functions and Token(_) itself is inaccessible outside the defining
  -- module — see the enforcement gap noted below, which currently allows it.
  fn process(t) do
    println(Token.value(t))
  end

  fn main() do
    process(Token.make("hi"))    -- prints "hi"
  end
end
```

> **Resolved:** an explicit qualified annotation like `t : Token.Token` in a
> caller outside the `Token` module now unifies correctly with the bare
> `Token` type `Token.make` returns, in both directions (`9001e4c0`,
> `core-march-types.md` §2.5's "Qualified-type-path unification"). Writing
> the qualified annotation explicitly is no longer necessary to work around
> a unification failure; either form works.

> **Known enforcement gap (logged, not fixed; `specs/todos/`):**
> `opaque type`'s constructor-hiding is intended (and, for a same-file
> reference, believed correct) but is **not actually enforced against a
> qualified reference to the constructor from a separate file** reached via
> `MARCH_LIB_PATH`/auto-discovery. Live-verified: `OqToken.Token("bypass")`
> from an unrelated sibling file typechecks and runs, constructing a real
> value, even though `Token`'s constructor is declared with `opaque type`
> (`test/imports/opaque_qual/`). Root cause: a same-compilation-unit
> forward-reference pass (`prebind_mod_members`, `typecheck.ml:8032–8087`)
> registers the qualified constructor key unconditionally on `var_vis`,
> before the later, correctly `ci_vis`-filtered `DMod` export step's result
> is merged in; the same class of bug the cross-module `pfn`/value gate
> above was fixed for, but on a different registration path and for the
> `ExCtor`/`ci_vis` check instead of `ExFn`/`ExValue`. See
> `core-march-types.md` §2.5 for the full trace.

---

## Qualified Access

Call functions or access types from another module using `.`:

```march
mod Main do
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
only **one** top-level `mod`; see "A Full Example" below, and
`core-march.md` §4.7's "One-mod-per-file" rule, for the precise grammar-level
rejection this produces if two top-level `mod`s appear in the same file.
Two truly separate, same-named-at-top-level modules like `Math` and `Main`
would instead each live in their own file, resolved via `MARCH_LIB_PATH`;
see "Multi-File Projects" below.)

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

A companion, narrower example lives at `examples/modules.march` (qualified
access + two-level nesting + `pfn` visibility, no `import`/`use`/`alias`).
The example below is intentionally different from that file: it demonstrates
qualified access **together with** `import`/`alias`, which means it must
respect the file-vs-in-file resolver distinction (`core-march.md` §4.7.1):
`import`/`use`/`alias` only resolve an actual `.march` FILE, never an
in-file nested `mod`, so `MathUtils` (nested inside `Example` here) can only
be reached by qualification; the `import`/`alias` demos below instead target
`List`, a real stdlib module (any real file works identically):

```march
mod Example do

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

```march
mod Main do
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

## Next Steps

- [Interfaces](interfaces.md): `interface` and `impl` for ad-hoc polymorphism
- [Getting Started](../../docs/getting-started.md): creating a project with forge
- [Standard Library](../../docs/stdlib.md): modules you get for free
