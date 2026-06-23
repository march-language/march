---
layout: cookbook
title: "Cookbook: Basics"
permalink: /docs/cookbook/basics/
---

# Basics

March is expression-oriented: almost everything returns a value. This chapter covers the building blocks you'll use in every program.

---

## Functions

`fn name(params) do ... end` defines a named function. The last expression in the body is the return value — no `return` keyword.

```march
fn add(x : Int, y : Int) : Int do
  x + y
end
```

Type annotations are optional everywhere — the compiler infers them:

```march
fn add(x, y) do x + y end
```

### Private functions

`pfn` makes a function private to its module. The compiler rejects calls from outside:

```march
mod Auth do
  pfn hash(s : String) : String do
    Crypto.sha256(s)
  end

  fn verify(plain, stored) do
    hash(plain) == stored
  end
end
```

---

## Let bindings

`let` binds a name. No `in` keyword — subsequent expressions in the block see the binding automatically:

```march
fn run() do
  let x = 10
  let y = x * 2
  y + 1
end
```

Type annotation is optional:

```march
let count : Int = 0
```

---

## Algebraic data types

`type` defines a sum type. Constructors are capitalized; no leading `|` on the first case:

```march
type Shape =
  Circle(Float)
  | Rect(Float, Float)
  | Point
```

Create values by applying constructors:

```march
let c = Circle(3.14)
let r = Rect(4.0, 6.0)
```

Record types use named fields:

```march
type User = { name : String, age : Int }

let u = { name: "Alice", age: 30 }
let name = u.name
let older = { u with age: 31 }
```

---

## Pattern matching

`match` inspects a value and dispatches on its shape. The compiler rejects non-exhaustive patterns:

```march
fn area(s : Shape) : Float do
  match s do
    Circle(r)    -> 3.14159 *. r *. r
    Rect(w, h)   -> w *. h
    Point        -> 0.0
  end
end
```

Guards narrow a pattern with a `when` condition:

```march
match n do
  x when x > 100 -> "big"
  x when x > 0   -> "small"
  _               -> "non-positive"
end
```

`match do` without a subject is a cond — works like chained if/else:

```march
match do
  score >= 90 -> "A"
  score >= 80 -> "B"
  _           -> "C"
end
```

---

## Result propagation with `let?`

`let? p = e` binds the `Ok` payload and short-circuits on `Err`, returning the error from the enclosing function immediately:

```march
fn load_config(path : String) : Result(Config, String) do
  let? src  = File.read(path)
  let? toml = Toml.parse(src)
  Ok(toml)
end
```

Without `let?` this is a nested match pyramid. With it, the happy path reads top-to-bottom. The RHS must be a `Result`; all `let?` in one block must share the same error type; `let?` cannot be the last expression in a block.

---

## Modules

Every file has exactly one top-level `mod`. Nest modules with `mod Inner do ... end`:

```march
mod MyApp do
  mod Utils do
    fn clamp(n, lo, hi) do
      match do
        n < lo -> lo
        n > hi -> hi
        _      -> n
      end
    end
  end

  fn main() do
    println(int_to_string(Utils.clamp(42, 0, 10)))
  end
end
```

---

## Complete example: a small calculator

```march
mod Calc do
  type Expr =
    Num(Float)
    | Add(Expr, Expr)
    | Mul(Expr, Expr)
    | Div(Expr, Expr)

  fn eval(e : Expr) : Result(Float, String) do
    match e do
      Num(n)    -> Ok(n)
      Add(a, b) ->
        let? x = eval(a)
        let? y = eval(b)
        Ok(x +. y)
      Mul(a, b) ->
        let? x = eval(a)
        let? y = eval(b)
        Ok(x *. y)
      Div(a, b) ->
        let? x = eval(a)
        let? y = eval(b)
        if y == 0.0 do
          Err("division by zero")
        else
          Ok(x /. y)
        end
    end
  end

  fn main() do
    let expr = Div(Add(Num(10.0), Num(2.0)), Num(3.0))
    match eval(expr) do
      Ok(v)  -> println("result: " ++ float_to_string(v))
      Err(e) -> println("error: " ++ e)
    end
  end
end
```
