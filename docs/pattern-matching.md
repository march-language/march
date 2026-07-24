---
layout: docs
title: Pattern Matching
nav_order: 5.2
permalink: /docs/pattern-matching/
---

# Pattern Matching

Pattern matching in March is exhaustive, nested, and deeply integrated with the type system. The compiler verifies that every possible shape of a value is handled.

---

## Basic Match

```march
match expr do Pattern -> result end
match do Bool -> result end          -- cond form: no scrutinee, each arm is a boolean
```

Full form:

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
-- March has no hexadecimal integer-literal syntax (`0xFF0000` is a lex
-- error — `0` followed by an unrelated identifier `xFF0000`); use decimal.
match color do
  Red   -> 16711680
  Green -> 65280
  Blue  -> 255
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

A record pattern destructures a record's fields directly in a `match` arm,
a `let` binding, or a function parameter:

```march
type Point = { x : Float, y : Float }

fn describe_point(p : Point) : String do
  match p do
    { x: 0.0, y: 0.0 } -> "origin"
    { x: x, y: 0.0 }   -> "on x-axis at " ++ float_to_string(x)
    { x: x, y: y }     -> "at " ++ float_to_string(x) ++ ", " ++ float_to_string(y)
  end
end
```

A field written as a bare name is shorthand — punning — for `name: name`,
mirroring record-literal punning: `{ x, y }` binds `x` and `y` to the
record's `x` and `y` fields, exactly like `{ x: x, y: y }`. The example
above could equally be written `{ x: x, y: y } -> ...` or, punned, as
`fn describe_point({ x, y })` if the whole function dispatched on the
struct shape rather than matching in the body.

**Field lists are open in a `match` arm** — a pattern need only name the
fields it cares about. `{ x: a }` matches any record with (at least) an `x`
field, whatever else it has; fields the pattern doesn't mention are simply
not bound. The y-axis check above, for instance, doesn't need to mention `y`
at all:

```march
match p do
  { x: 0.0 } -> "on y-axis"
  _          -> "elsewhere"
end
```

Naming a field the record does **not** have is a compile error
(`unknown_record_field`), not a silent no-op — a typo like `{ xx: a }`
against `{ x: Float, y: Float }` is rejected rather than matching nothing:

```
This record has no field `xx`.
  Available fields: x, y
```

A function parameter gets the same openness when it dispatches through an
explicit `match`, since a single-clause function whose parameter is a
non-trivial pattern desugars through the same match-lowering path:

```march
fn area({ w: w, h: h }) : Int do w * h end   -- full destructure, unaffected
```

Two positions remain **closed** to exactly the fields named, because neither
has an independent expected type for the pattern to open against:

- **A `let` binding**: `let { x: px } = p` still requires naming every field
  of `p`'s type. `infer_pattern` only receives an expected type when the
  caller already has one to offer (a `match`'s scrutinee, a constructor
  argument, a tuple element); a `let` pattern's binding is exactly the thing
  establishing the type, so there is nothing to drive it from yet.
- **A bare pattern used directly as a function parameter**, e.g.
  `fn get_w({ w: w }) : Int do w end` — a pattern in that grammar position
  cannot itself carry a type annotation (only `name : Type` can), so its type
  has no source but the pattern itself and is inferred as exactly `{ w : Int
  }`. `get_w` above rejects a wider record such as `{ w: 8, h: 9 }`. To open
  a parameter's field list, annotate the parameter with a name and
  destructure it in the body instead, which routes it back through
  `match`'s open-field-list handling:

```march
fn get_w2(r : { w : Int, h : Int }) : Int do
  match r do
    { w: w } -> w    -- r may have any other fields too
  end
end
```

### Atom Patterns

Atoms are named constants written with a leading colon — each atom is its own type (see the Type System page for a full introduction).

```march
match status do
  :ok      -> "success"
  :error   -> "failure"
  :pending -> "in progress"
end
```

### Qualified Constructor Patterns

When multiple modules define constructors with the same name, qualify them
(`TypeName.Ctor` also works — the diagnostic below suggests that spelling —
but the module-qualified form shown here is equally valid). Note a single
`match` can only ever see ONE of the colliding constructors per scrutinee (a
scrutinee has one concrete type), so — unlike the sketch above might suggest —
qualification shows up as two separate matches over two separately-typed
values, not as alternate arms of the same match:

```march
mod Http do
  type HResult = Ok(String) | Err(String)
end
mod Json do
  type JResult = Ok(String) | Err(String)
end

fn describe_http(x : Http.HResult) : String do
  match x do
    Http.Ok(resp) -> handle_http(resp)
    Http.Err(_)   -> "http error"
  end
end

fn describe_json(x : Json.JResult) : String do
  match x do
    Json.Ok(data) -> handle_json(data)
    Json.Err(_)   -> "json error"
  end
end
```

> **Known compiler bug, compiled backend only:** the qualified form
> is only reliably safe here because both colliding `Ok`/`Err` constructors
> above carry a `String` payload (same runtime representation). If the two
> colliding types' same-named constructor carries payloads with a *different*
> representation (e.g. one module's `Ok(Int)` vs another's `Ok(String)`), the
> compiled backend nondeterministically crashes (`march: out of memory`) or
> returns garbage data even though every reference is correctly
> module-qualified and the interpreter is always correct. Minimal repro:
> nest `mod A do type TA = Ok(Int) | Err(String) end` and
> `mod B do type TB = Ok(String) | Err(String) end` in one file, then compile
> and run a function that pattern-matches `B.Ok(data) -> data` on a
> `B.Ok("hi")` value — the same-shape-payload case (both `Ok(Int)`, or both
> `Ok(String)`, as above) is unaffected.

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

## As Patterns

`p as name` binds `name` to the **entire** matched value while `p` still
destructures it, so a branch can use both the whole value and pieces of it
without matching it twice:

```march
match o do
  Some(x) as whole ->
    -- `x` is the payload; `whole` is the entire `Some(x)` value
    println(whole)
    x
  None -> 0
end
```

The inner pattern can be anything — a bare variable (`x as y` binds both `x`
and `y` to the same value), a literal, a tuple, or an arbitrarily nested
constructor pattern. As-patterns work in `match` arms, `let` bindings (`let
(n as whole) = compute()`), and function parameters, since all three desugar
through the same pattern grammar.

Chaining aliases directly (`p as a as b`) is a parse error. Parenthesize to
bind two names to the same value — `(x as a) as b` is accepted — though one
alias per pattern is almost always what you want.

Note the parentheses in the `let` example above: `let` takes a *simple*
pattern, so `let n as whole = ...` does not parse. `let (n as whole) = ...`
does.

---

## Guards

Guards add a boolean condition to a pattern arm with `when`:

```march
match n do
  x when x < 0     -> "negative"
  x when (x == 0)  -> "zero"
  x when x < 100   -> "small positive"
  _                -> "large positive"
end
```

> **Note (resolved):** an earlier version of this document warned that a
> guard expression using `==`/`!=`/`>=`/`<=`/`&&`/`||`/`++` needed
> parenthesizing when followed by another guarded arm, due to a parser
> arm-boundary-lookahead limitation. Verified live: this no longer
> reproduces — chained guards using any of these operators, with no
> parens, parse and evaluate correctly. The parens in the example above
> are harmless but no longer necessary.

Guards on function heads work the same way:

```march
fn classify(n) when n < 0   do "negative" end
fn classify(n) when n == 0  do "zero" end
fn classify(n)              do "positive" end
```

---

## Exhaustiveness Checking

The compiler verifies that every possible value is matched. If you miss a
case, you get a diagnostic pointing at exactly what's missing — verified
live, it is currently a **warning**, not a hard compile error (the program
still typechecks at exit 0 and still runs; a value that actually hits the
missing case panics at runtime, same as any other non-exhaustive match):

```march
type Color = Red | Green | Blue

-- WARNING: Non-exhaustive pattern match — missing case: Blue
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

**Why this matters — refactoring safety.** Exhaustiveness turns "add a variant"
from a silent hazard into a guided checklist. Add a `Blue` case to a `Color` that
already had `Red` and `Green`, and the compiler flags **every** `match` in the
codebase that forgot to handle it — each one a precise diagnostic (currently a
warning, not a hard error — see above) pointing at the spot to update. (The LSP
even offers an "Add all N missing cases" quick fix.) A stale match arm doesn't
fail the build, but it also can't hide silently; the type that changed pulls
every dependent decision back into view.

---

## Nested Patterns

Patterns can be nested arbitrarily deep:

```march
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))

fn depth(t : Tree(a)) : Int do
  match t do
    Leaf             -> 0
    Node(Leaf, _, Leaf) -> 1
    Node(l, _, r)    -> 1 + Math.max_int(depth(l), depth(r))
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
    let upper   = String.to_uppercase(trimmed)
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

When `match` has no scrutinee expression, each arm is a boolean guard — this is equivalent to `cond` in other languages:

```march
match do
  (score >= 90) -> "A"
  (score >= 80) -> "B"
  (score >= 70) -> "C"
  (score >= 60) -> "D"
  _             -> "F"
end
```

> **Note (resolved):** an earlier version of this document warned that each
> condition needed parenthesizing when chaining two or more cond arms using
> a comparison/logical operator (`>=`, `<=`, `==`, `!=`, `&&`, `||`, `++`),
> citing an arm-boundary-lookahead parser limitation. Verified live: this no
> longer reproduces for any of these operators, chained or mixed, with or
> without a trailing wildcard arm. The parens above are harmless but no
> longer necessary.

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
  Err(AuthFailed) -> reply(401, "Unauthorized")
  Err(AuthNotFound(kind)) -> reply(404, kind ++ " not found")
  Err(AuthTimeout) -> reply(503, "Service unavailable")
end
```

> **Note (resolved):** an earlier version of this document warned that
> multiple `else` arms had to be crammed onto **one line**, separated by
> `|`, because splitting them across lines (as above) failed to parse.
> Verified live: multi-line `else` arms parse and dispatch correctly now —
> each of the three arms above is independently reachable and gives the
> right reply for its error case.

Each `<-` binding: if the expression matches the pattern, execution continues with the binding in scope. On mismatch, control passes to the `else` block (or the non-matching value propagates if there's no `else`).

---

## Patterns in Let Bindings

Patterns work directly in `let` — but a bare constructor pattern needs an
extra pair of parens (`let Some(x) = ...` is a parse error; `let (Some(x)) =
...` is not). A tuple pattern doesn't need the extra parens,
since `let (a, b) = ...` is its own grammar production:

```march
let (a, b) = some_pair()
let (Some(x)) = might_be_some()    -- panics if None
let (Cons(h, t)) = nonempty_list
```

And in function parameters:

```march
fn fst((a, _)) do a end
fn snd((_, b)) do b end

fn add_points(p1 : Point, p2 : Point) : Point do
  { x: p1.x +. p2.x, y: p1.y +. p2.y }
end
```

---

## Multi-head Functions

A function can have multiple clauses that pattern-match directly in the parameter list. Consecutive definitions with the same name are merged by the compiler into a single function that tries each clause in order:

```march
fn factorial(0) : Int do 1 end
fn factorial(n) : Int do n * factorial(n - 1) end
```

```march
fn describe(0) : String do "zero" end
fn describe(1) : String do "one" end
fn describe(n) : String do
  if n < 0 do "negative" else "many" end
end
```

Clauses are checked top to bottom; the first matching clause wins. The compiler warns if later clauses are unreachable.

Multi-head functions work with any pattern in the parameter list that `match`
itself supports — constructors, literals, tuples, and record patterns
(see "Record Patterns" above):

```march
fn head(Cons(x, _)) : a do x end
fn head(Nil)        : a do panic("empty list") end

fn first((x, _)) : a do x end
```

### `when` Guards

Add a `when` clause to a function head (or match arm) to add a boolean condition beyond the pattern:

```march
fn classify(n : Int) : String when n < 0  do "negative" end
fn classify(n : Int) : String when n == 0 do "zero" end
fn classify(n : Int) : String             do "positive" end
```

Guards can also appear on match arms:

```march
match score do
  n when (n >= 90) -> "A"
  n when (n >= 80) -> "B"
  n when (n >= 70) -> "C"
  _                -> "F"
end
```

> See the note under "Guards" above — parenthesizing `>=`/`<=`/`==`/etc.
> guards when chaining more than one is no longer required (fixed).

A guard that fails causes the clause to be skipped and the next clause is tried. A function with no matching clause (after guards) panics at runtime — make the last clause unconditional or use a wildcard to ensure exhaustiveness.

---

## Next Steps

- [Type System](types.md) — the types you're matching against
- [Tour](../../docs/tour.md) — language overview with more examples
- [Interfaces](interfaces.md) — polymorphic dispatch with `interface`
