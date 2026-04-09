---
layout: page
title: Pattern Matching
nav_order: 7
---

# Pattern Matching

Pattern matching in March is exhaustive, nested, and deeply integrated with the type system. The compiler verifies that every possible shape of a value is handled.

---

## Basic Match

```march
match expr do
  Pattern1 -> result1
  Pattern2 -> result2
  _        -> default
end
```

The `_` wildcard matches anything and discards the value.

---

## Pattern Catalog

### Wildcards and Variables

```march
_                   -- match anything, discard
x                   -- match anything, bind to x
```

### Literal Patterns

```march
match n do
  0 -> "zero"
  1 -> "one"
  _ -> "other"
end

match b do
  true  -> "yes"
  false -> "no"
end

match s do
  "hello" -> "greeting"
  "bye"   -> "farewell"
  other   -> "unknown: " ++ other
end
```

### Constructor Patterns

```march
type Shape = Circle(Float) | Rect(Float, Float)

match shape do
  Circle(r)    -> 3.14159 *. r *. r
  Rect(w, h)   -> w *. h
end
```

Nullary constructors match with no parens:

```march
match color do
  Red   -> 0xFF0000
  Green -> 0x00FF00
  Blue  -> 0x0000FF
end
```

### Option and Result

```march
match opt do
  None    -> "nothing"
  Some(v) -> "got: " ++ to_string(v)
end

match result do
  Ok(v)  -> "success: " ++ to_string(v)
  Err(e) -> "error: " ++ e
end
```

### Tuple Patterns

```march
match pair do
  (0, _) -> "starts with zero"
  (_, 0) -> "ends with zero"
  (a, b) -> int_to_string(a + b)
end
```

### List Patterns

```march
match xs do
  []           -> "empty"
  [x]          -> "one: " ++ to_string(x)
  [x, y]       -> "two elements"
  Cons(h, t)   -> "head is " ++ to_string(h)
  _            -> "longer"
end
```

`[]` desugars to `Nil`. `[a, b, c]` desugars to `Cons(a, Cons(b, Cons(c, Nil)))`.

### Record Patterns

```march
type Point = { x : Float, y : Float }

match p do
  { x = 0.0, y = 0.0 } -> "origin"
  { x = x, y = 0.0 }   -> "on x-axis at " ++ float_to_string(x)
  { x = x, y = y }     -> "at " ++ float_to_string(x) ++ ", " ++ float_to_string(y)
end
```

### Atom Patterns

```march
match status do
  :ok      -> "success"
  :error   -> "failure"
  :pending -> "in progress"
end
```

### Qualified Constructor Patterns

When multiple modules define constructors with the same name, qualify them:

```march
match x do
  Http.Ok(resp)  -> handle_http(resp)
  Json.Ok(data)  -> handle_json(data)
  _              -> ()
end
```

### Negative Integer Patterns

```march
match n do
  -1 -> "minus one"
  0  -> "zero"
  1  -> "one"
  _  -> "other"
end
```

---

## Guards

Guards add a boolean condition to a pattern arm with `when`:

```march
match n do
  x when x < 0   -> "negative"
  x when x == 0  -> "zero"
  x when x < 100 -> "small positive"
  _               -> "large positive"
end
```

Guards on function heads work the same way:

```march
fn classify(n) when n < 0   do "negative" end
fn classify(n) when n == 0  do "zero" end
fn classify(n)              do "positive" end
```

---

## Exhaustiveness Checking

The compiler verifies that every possible value is matched. If you miss a case, you get a compile-time error:

```march
type Color = Red | Green | Blue

-- compile error: pattern match not exhaustive — missing case: Blue
match color do
  Red   -> "red"
  Green -> "green"
end
```

Add a wildcard or the missing case to fix it:

```march
match color do
  Red   -> "red"
  Green -> "green"
  Blue  -> "blue"
end
```

Exhaustiveness extends to nested patterns. The compiler understands which combinations are possible.

---

## Nested Patterns

Patterns can be nested arbitrarily deep:

```march
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))

fn depth(t : Tree(a)) : Int do
  match t do
    Leaf             -> 0
    Node(Leaf, _, Leaf) -> 1
    Node(l, _, r)    -> 1 + max(depth(l), depth(r))
  end
end
```

Nested Option:

```march
match (opt_a, opt_b) do
  (Some(a), Some(b)) -> a + b
  (Some(a), None)    -> a
  (None,    Some(b)) -> b
  (None,    None)    -> 0
end
```

---

## Multi-Expression Arms

Match arms support multiple expressions — any number of `let` bindings followed by a final expression:

```march
match result do
  Ok(data) ->
    let trimmed = String.trim(data)
    let upper   = String.upcase(trimmed)
    println(upper)
    true
  Err(msg) ->
    println("Error: " ++ msg)
    false
end
```

A `do ... end` wrapper also works for clarity:

```march
match xs do
  Cons(h, t) -> do
    let doubled = h * 2
    Cons(doubled, t)
  end
  Nil -> Nil
end
```

---

## Cond (Pattern-Free Multi-Way If)

When you just need multiple boolean conditions, use `match` without a scrutinee:

```march
match do
  score >= 90 -> "A"
  score >= 80 -> "B"
  score >= 70 -> "C"
  score >= 60 -> "D"
  _           -> "F"
end
```

This is equivalent to a chain of `if/else` but reads more cleanly.

---

## With (Monadic Pattern Matching)

`with` is for chaining `Result`/`Option` bindings without nesting:

```march
with Ok(user)    <- authenticate(credentials),
     Ok(profile) <- fetch_profile(user.id),
     Ok(data)    <- load_data(profile.key) do
  render(user, profile, data)
else
  Err(AuthFailed)        -> reply(401, "Unauthorized")
  Err(NotFound(kind))    -> reply(404, kind ++ " not found")
  Err(Timeout)           -> reply(503, "Service unavailable")
end
```

Each `<-` binding: if the expression matches the pattern, execution continues with the binding in scope. On mismatch, control passes to the `else` block (or the non-matching value propagates if there's no `else`).

---

## Patterns in Let Bindings

Patterns work directly in `let`:

```march
let (a, b) = some_pair()
let Some(x) = might_be_some()    -- panics if None
let Cons(h, t) = nonempty_list
```

And in function parameters:

```march
fn fst((a, _)) do a end
fn snd((_, b)) do b end

fn add_points({ x = x1, y = y1 }, { x = x2, y = y2 }) do
  { x = x1 +. x2, y = y1 +. y2 }
end
```

---

## Multi-Head Functions (Pattern Dispatch)

Consecutive `fn` declarations with the same name and compatible arities are merged into a single function. The compiler dispatches to the first matching clause:

```march
fn fact(0) do 1 end
fn fact(n) do n * fact(n - 1) end

fn describe(Nil)        do "empty list" end
fn describe(Cons(x, _)) do "starts with " ++ to_string(x) end
```

This is syntactic sugar — the compiler desugars to a single function with an internal match.

---

## Next Steps

- [Type System](types.md) — the types you're matching against
- [Tour](tour.md) — language overview with more examples
- [Interfaces](interfaces.md) — polymorphic dispatch with `interface`
