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
  (a, b) -> String.from_int(a + b)
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
    { x: x, y: 0.0 }   -> "on x-axis at " ++ String.from_float(x)
    { x: x, y: y }     -> "at " ++ String.from_float(x) ++ ", " ++ String.from_float(y)
  end
end
```

A field written as a bare name is shorthand (punning) for `name: name`,
mirroring record-literal punning: `{ x, y }` binds `x` and `y` to the
record's `x` and `y` fields, exactly like `{ x: x, y: y }`. The example
above could equally be written `{ x: x, y: y } -> ...` or, punned, as
`fn describe_point({ x, y })` if the whole function dispatched on the
struct shape rather than matching in the body.

#### Field lists are open

A record pattern need only name the fields it cares about. `{ x: a }` matches
any record that has (at least) an `x` field, whatever else it includes; fields
the pattern doesn't mention are simply not bound. The y-axis check above, for
instance, needn't mention `y` at all:

```march
match p do
  { x: 0.0 } -> "on y-axis"
  _          -> "elsewhere"
end

let { x: px } = p            -- `p` may have any number of other fields
let? { x: px } = fetch()     -- likewise, against the Ok payload's type
```

This works wherever the pattern is matched against a value with a type that is
already known: a `match` scrutinee, a `let` or `let?` right-hand side, a
constructor argument, a tuple element.

Naming a field the record does **not** have is a compile error, not a silent
no-op, so a typo is caught rather than invisibly matching no values:

```
This record has no field `xx`.
  Available fields: x, y
```

#### Composing with other patterns

Record patterns nest anywhere a pattern can appear, which is where they earn
their keep. A record inside a record:

```march
type Origin = { host : String, port : Int }
type Route  = { origin : Origin, secure : Bool }

fn where_to(r : Route) : String do
  match r do
    { origin: { host: "localhost", port: p } } -> "local:" ++ String.from_int(p)
    { origin: { host: h } }                    -> "remote:" ++ h
  end
end
```

A record inside a constructor payload, the common shape when a record comes
back wrapped in `Option` or `Result`:

```march
type Reply = { status : Int, body : String }

fn handle(r : Option(Reply)) : String do
  match r do
    Some({ status: 200, body: b }) -> "ok " ++ b
    Some({ status: s })            -> "http " ++ String.from_int(s)
    None                           -> "no response"
  end
end
```

As or-pattern alternatives, binding the same name from either side:

```march
match reply do
  { status: 404, body: b } | { status: 410, body: b } -> "gone: " ++ b
  { body: b }                                         -> b
end
```

Under an `as` pattern, to name the whole record while still destructuring it:

```march
match reply do
  { status: 500 } as whole -> "ALERT " ++ whole.body
  { body: b }              -> b
end
```

With a guard, when the interesting condition is a range rather than a value:

```march
match reply do
  { status: s } when s >= 500 -> "server error"
  { status: s } when s >= 400 -> "client error"
  _                           -> "ok"
end
```

And inside a tuple, which is how you dispatch on two values at once:

```march
match (reply, retries) do
  ({ status: 200 }, _) -> "done"
  (_, 0)               -> "giving up"
  (_, n)               -> "retrying, " ++ String.from_int(n) ++ " left"
end
```

#### The one exception: a bare pattern as a parameter

A pattern written directly as a parameter (`fn get_w({ w: w })`) is the one
place a record pattern is *closed*, matching exactly the fields it names.
Parameter patterns can't carry a type annotation (only `name : Type` can), so
the pattern is the sole source of its own type: `get_w` is inferred as taking
exactly `{ w : Int }` and rejects a wider `{ w: 8, h: 9 }`.

Give the parameter a name and a type, then destructure in the body, and the
field list opens as everywhere else:

```march
fn get_w(r : { w : Int, h : Int }) : Int do
  match r do
    { w: w } -> w      -- open: `r` may carry other fields too
  end
end
```

#### Coverage

Record arms take part in exhaustiveness and redundancy checking like any
other pattern. A record has one shape, so the checker treats it much as it
treats a tuple: one column per field, recursing into each field's
sub-pattern. A match that handles only some values of a field is reported
non-exhaustive rather than failing at runtime:

```march
match p do
  { code: 404 } -> "gone"
end
-- warning: Non-exhaustive pattern match — missing case: { code: _, msg: _ }
```

Arms naming different subsets of the fields still line up, because the field
list comes from the record's type and any field an arm omits counts as a
wildcard for that arm. Redundancy follows the same rule, so a record arm
already covered by an earlier one is reported unreachable.

### Atom Patterns

Atoms are named constants written with a leading colon; each atom is its own type (see the Type System page for a full introduction).

```march
match status do
  :ok      -> "success"
  :error   -> "failure"
  :pending -> "in progress"
end
```

### Qualified Constructor Patterns

When multiple modules define constructors with the same name, qualify them
(`TypeName.Ctor` also works; the diagnostic below suggests that spelling,
but the module-qualified form shown here is equally valid). Note a single
`match` can only see ONE of the colliding constructors per scrutinee (a
scrutinee has one concrete type), so, unlike the sketch above might suggest,
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

The qualified form above is reliably safe because both colliding `Ok`/`Err`
constructors carry a `String` payload (same runtime representation). When the
colliding constructors carry payloads of *different* representations, the
compiled backend has an open bug; see [Known limitations](#known-limitations)
at the end of this page.

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

The inner pattern can be anything: a bare variable (`x as y` binds both `x`
and `y` to the same value), a literal, a tuple, or an arbitrarily nested
constructor pattern. As-patterns work in `match` arms, `let` bindings (`let
(n as whole) = compute()`), and function parameters, since all three desugar
through the same pattern grammar.

Chaining aliases directly (`p as a as b`) is a parse error. Parenthesize to
bind two names to the same value (`(x as a) as b` is accepted), though one
alias per pattern is almost always what you want.

Note the parentheses in the `let` example above: `let` takes a *simple*
pattern, so `let n as whole = ...` does not parse. `let (n as whole) = ...`
does.

---

## Or Patterns

`p1 | p2 | p3` matches an arm against several alternatives, trying each in
order and running the shared arm body on the first one that matches:

```march
match n do
  1 | 2 | 3 -> "small"
  _         -> "big"
end

match color do
  Red | Green -> "warm"
  Blue        -> "cool"
end
```

Alternatives can be literals, nullary/atom constructors, or any other
pattern shape, and they **may bind variables**, provided every alternative
binds the same names at the same types:

```march
type E = A(Int) | B(Int) | C

match e do
  A(x) | B(x) -> x * 10   -- `x` comes from whichever alternative matched
  C           -> 0
end
```

All alternatives share ONE arm body, which reaches its binders as parameters,
so the names have to line up. Two ways they can fail to:

```march
match e do
  A(x) | B(y) -> x + y    -- REJECTED: "Or-pattern alternatives must bind the
end                       --            same variables." `y` would be unbound
                          --            whenever `A` matched.
```

```march
type E2 = A(Int) | B(String)

match e2 do
  A(x) | B(x) -> 0        -- REJECTED: `x` cannot be both Int and String
end
```

If alternatives truly need to bind different things, split them into
separate arms:

```march
match e do
  A(x) -> f(x)
  B(s) -> g(s)
end
```

Exhaustiveness and redundancy checking see through or-patterns at **any**
nesting depth: `Red | Green` followed by a `Blue` arm is exhaustive for a
three-constructor `Color`, `Some(1 | 2)` covers exactly `Some(1)` and
`Some(2)` (so a match with only that arm and `None` is still reported
non-exhaustive), and an arm that only repeats alternatives already covered
by an earlier arm is flagged as unreachable exactly as any other redundant
arm would be. An arm with nested alternatives that multiply out to a
pathologically large number of shapes (more than a few hundred) falls back
to being treated as a wildcard for coverage purposes, which can only
suppress a diagnostic, never invent one.

An or-pattern nests beneath `as`: `1 | 2 as n` parses as `(1 | 2) as n`
(binding `n` to the whole matched value, alongside anything the alternatives
themselves bind).

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

Guards on function heads work the same way:

```march
fn classify(n) when n < 0   do "negative" end
fn classify(n) when n == 0  do "zero" end
fn classify(n)              do "positive" end
```

---

## Exhaustiveness Checking

The compiler verifies that every possible value is matched. If you miss a
case, you get a diagnostic pointing at exactly what's missing. Verified
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

**Why this matters: refactoring safety.** Exhaustiveness turns "add a variant"
from a silent hazard into a guided checklist. Add a `Blue` case to a `Color` that
already had `Red` and `Green`, and the compiler flags **every** `match` in the
codebase that forgot to handle it, each one a precise diagnostic (currently a
warning, not a hard error; see above) pointing at the spot to update. (The LSP
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

Match arms support multiple expressions: any number of `let` bindings followed by a final expression:

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

When `match` has no scrutinee expression, each arm is a boolean guard; this is equivalent to `cond` in other languages:

```march
match do
  (score >= 90) -> "A"
  (score >= 80) -> "B"
  (score >= 70) -> "C"
  (score >= 60) -> "D"
  _             -> "F"
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
  Err(AuthFailed) -> reply(401, "Unauthorized")
  Err(AuthNotFound(kind)) -> reply(404, kind ++ " not found")
  Err(AuthTimeout) -> reply(503, "Service unavailable")
end
```

Each `<-` binding: if the expression matches the pattern, execution continues with the binding in scope. On mismatch, control passes to the `else` block (or the non-matching value propagates if there's no `else`).

---

## Patterns in Let Bindings

Patterns work directly in `let`, but a bare constructor pattern needs an
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
itself supports: constructors, literals, tuples, and record patterns
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

A guard that fails causes the clause to be skipped and the next clause is tried. A function with no matching clause (after guards) panics at runtime; make the last clause unconditional or use a wildcard to ensure exhaustiveness.

---

## Known limitations

**Qualified constructor patterns with differently-shaped payloads (compiled
backend).** When two modules define a same-named constructor with payloads that have
*different* runtime representations (e.g. one module's `Ok(Int)` versus another's
`Ok(String)`), the compiled backend has an open bug: matching the qualified
constructor nondeterministically crashes (`march: out of memory`) or returns
garbage data, even though every reference is correctly module-qualified. The
interpreter is always correct. Minimal repro: nest
`mod A do type TA = Ok(Int) | Err(String) end` and
`mod B do type TB = Ok(String) | Err(String) end` in one file, then compile and
run a function that pattern-matches `B.Ok(data) -> data` on a `B.Ok("hi")` value.
The same-shape-payload case (both `Ok(Int)`, or both `Ok(String)`) is unaffected,
so the qualified patterns shown earlier on this page are safe.

---

## Next Steps

- [Type System](types.md): the types you're matching against
- [Tour](../../docs/tour.md): language overview with more examples
- [Interfaces](interfaces.md): polymorphic dispatch with `interface`
