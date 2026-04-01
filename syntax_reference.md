# March Syntax Quick Reference

A terse example of every construct. See `lib/parser/parser.mly` for authoritative grammar.

---

## Comments

```march
-- line comment

{- block comment
   (nestable: {- inner -}) -}
```

---

## Module

```march
mod MyApp do
  ...
end
```

Every file must start with a module declaration. Dotted names and nesting are supported:

```march
mod A.B.C do ... end           -- dotted module name

mod Outer do
  mod Inner do ... end         -- nested module
end
```

---

## Functions

```march
fn add(x: Int, y: Int): Int do
  x + y
end

pfn helper(x) do              -- pfn = private
  x * 2
end
```

Multi-head pattern matching — consecutive clauses with the same name are merged:

```march
fn len(Nil) do 0 end
fn len(Cons(_, t)) do 1 + len(t) end
```

Function clause guard:

```march
fn abs(n) when n < 0 do -n end
fn abs(n) do n end
```

Return-type annotation is optional (`fn f(x: Int): Bool do ... end`).

Default argument values (Elixir-style `\\`):

```march
fn greet(name, greeting \\ "Hello") do
  greeting ++ ", " ++ name ++ "!"
end

greet("World")           -- "Hello, World!"
greet("World", "Hi")    -- "Hi, World!"
```

Multiple defaults — all must be trailing parameters:

```march
fn make(x, y \\ 10, z \\ 20) do x + y + z end
make(1)          -- 31  (uses y=10, z=20)
make(1, 5)       -- 26  (uses z=20)
make(1, 5, 6)    -- 12  (all explicit)
```

Local function inside a block:

```march
fn outer() do
  fn inner(x) do x + 1 end
  inner(5)
end
```

---

## Lambdas

```march
fn x -> x + 1                 -- single param
fn _ -> 42                    -- wildcard (1-arg, NOT zero-arg)
fn (a, b) -> a + b            -- multiple params
fn () -> compute()            -- ZERO-ARG: must use fn () -> ...
```

Multi-statement lambda bodies are supported with leading `let` bindings followed by
a final expression — identical to match arm block bodies:

```march
fn x ->
  let y = x + 1
  let z = y * 2
  z

fn (a, b) ->
  let sum = a + b
  sum * 2

fn () ->
  let x = compute()
  let y = x + 1
  y
```

The body is: zero or more `let`/`linear let` bindings, then a final expression.
Single-expression lambdas are unchanged — no `let` bindings means no `EBlock` wrapper.

**`fn -> expr` is a PARSE ERROR.** Zero-arg lambdas require `fn () -> expr`.

---

## Let Bindings

Block-level `let` — no `in`; subsequent exprs in the block see the binding:

```march
fn main() do
  let x = 42
  let y = x + 1
  y
end
```

With type annotation:

```march
let count: Int = 0
```

Linear let (must be consumed exactly once):

```march
linear let handle: Handle = open_file("foo.txt")
```

Module-level `let`:

```march
let pi = 3.14159
```

---

## Types

Variant (ADT) — no leading `|`:

```march
type Color = Red | Green | Blue
type Shape = Circle(Float) | Rect(Float, Float)
```

Generic variant:

```march
type Option(a) = None | Some(a)
type Result(a, b) = Ok(a) | Err(b)
```

Record:

```march
type Point = { x: Float, y: Float }
type User = { name: String, age: Int }
```

Private type (type and constructors both private):

```march
ptype Internal = Foo | Bar(Int)
```

Opaque type (type name public, constructors private):

```march
opaque type Handle = Handle(Int)
-- Inside the module: can construct and pattern-match Handle
-- Outside the module: type name visible, constructors hidden
```

Use opaque types to hide implementation details while keeping the type name usable in signatures:

```march
mod Token do
  opaque type Token = Token(String)
  fn make(s) do Token(s) end
  fn value(Token(s)) do s end
end
-- Outside: can call Token.make/Token.value, cannot use Token(_) directly
```

---

## Type Syntax

```march
Int                       -- concrete type
List(Int)                 -- generic application
(Int, String)             -- tuple type
()                        -- unit type
Int -> Bool               -- function type (right-associative)
a -> b -> c               -- curried: a -> (b -> c)
Mod.Type                  -- qualified type
linear Handle             -- linear type (must use exactly once)
affine Handle             -- affine type (use at most once)
```

In `nat`-level arithmetic (for sized arrays):

```march
type Arr(n) = Array(n * 2)
```

---

## Patterns

```march
_                         -- wildcard
x                         -- variable binding
42                        -- int literal
3.14                      -- float literal
"hi"                      -- string literal
true / false              -- bool literals
Nil                       -- nullary constructor
Some(x)                   -- constructor with args
Cons(h, t)                -- nested constructor
(a, b)                    -- tuple
(a, b, c)                 -- triple
[a, b, c]                 -- list (sugar for Cons chains)
[]                        -- empty list (Nil)
:ok                       -- atom
:error(msg)               -- atom with args
Mod.Con(x)                -- qualified constructor (disambiguation)
-5                        -- negative int literal
```

---

## Match

```march
match expr do
  Nil        -> "empty"
  Cons(h, _) -> h
end
```

Arms separated by newlines or `|`. Multi-statement arms need no wrapper:

```march
match result do
  Ok(v)  ->
    let s = to_string(v)
    print(s)
  Err(e) -> print(e)
end
```

Guard on a match arm:

```march
match n do
  x when x > 0 -> "positive"
  x when x < 0 -> "negative"
  _             -> "zero"
end
```

Cond (pattern-free multi-way if):

```march
match do
  x > 10  -> "big"
  x > 0   -> "small"
  _       -> "non-positive"
end
```

---

## With Expressions

Elixir-style monadic chaining for `Result`/`Option` types:

```march
with Ok(x) <- f(),
     Ok(y) <- g(x) do
  x + y
end
```

With an `else` handler for failed patterns:

```march
with Ok(x) <- fetch_user(id),
     Ok(y) <- fetch_data(x) do
  process(x, y)
else
  Err(e) -> handle_error(e)
end
```

Each `pat <- expr` binding: if `expr` matches `pat`, continue; otherwise fall through to `else` arms (or propagate the non-matching value if no `else`). Multiple bindings are separated by commas.

---

## If / Else

```march
if x > 0 do
  "positive"
end
```

With optional `else` block (both branches can be multi-statement):

```march
if x > 0 do
  let msg = "positive"
  print(msg)
else
  print("non-positive")
end
```

`else` is optional — `if` without `else` returns `()`. There is no `then` keyword.

---

## Operators

Integer arithmetic: `+`, `-`, `*`, `/`, `%`
Float arithmetic: `+.`, `-.`, `*.`, `/.`
String/list concat: `++`
Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
Logic: `&&`, `||`, `!` (prefix not), unary `-` (negate)

---

## Pipe

```march
[1, 2, 3]
|> List.map(fn x -> x * 2)
|> List.filter(fn x -> x > 2)
```

`|>` threads the left value as the first argument of the right expression.

---

## Literals

```march
42                        -- Int
3.14                      -- Float
"hello"                   -- String
true / false              -- Bool
:ok                       -- Atom
:error("msg")             -- Atom with args
```

Triple-quoted strings preserve newlines:

```march
let s = """
  multi
  line
"""
```

String interpolation:

```march
let greeting = "Hello, ${name}!"
let info = "x = ${to_string(x)}"
```

---

## Sigils

```march
~H"<p>Hello</p>"          -- HTML sigil (produces IOList)
~H"<p>${name}</p>"        -- sigil with interpolation
~H"""
  <div>multi-line</div>
"""                       -- triple-quoted sigil
```

Any uppercase letter can be a sigil prefix (`~H`, `~R`, etc.).

---

## Tuples

```march
(1, "two", true)          -- 3-tuple
(x, y)                    -- 2-tuple (pair)
()                        -- unit
```

---

## Lists

```march
[]                        -- empty list (Nil)
[1, 2, 3]                 -- list literal (sugar for Cons chains)
Cons(1, Cons(2, Nil))     -- explicit cons
```

## List Comprehensions

```march
[expr for pat in list]              -- map: apply expr to each element
[expr for pat in list, pred]        -- filter-map: only elements where pred is true

-- Examples:
[x * 2 for x in [1, 2, 3]]         -- [2, 4, 6]
[x for x in nums, x % 2 == 0]      -- only even numbers
[x + 1 for x in [10, 20, 30]]      -- [11, 21, 31]
```

Desugars to `List.map` / `List.filter` + `List.map`. Requires `List` in scope.

---

## Records

Literal:

```march
let p = { x = 1.0, y = 2.0 }
```

Field access:

```march
p.x
```

Functional update:

```march
{ p with x = 3.0 }
{ state with count = state.count + 1, name = "new" }
```

---

## Function Calls & Field Access

```march
List.map(xs, fn x -> x + 1)   -- module-qualified call
String.length(s)
p.x                            -- field access
a.b.c                          -- chained field/module access
```

Constructor application:

```march
Some(42)
Ok("result")
Cons(1, Nil)
```

---

## Block Expression

`do ... end` is usable as an expression anywhere:

```march
let result = do
  let a = compute()
  a + 1
end
```

---

## Typed Holes

```march
?                             -- anonymous hole (compiler fills / reports type)
?name                         -- named hole
```

Useful for type-directed search.

---

## Visibility & Doc/Attrs

```march
fn pub_fn() do ... end        -- public (default)
pfn priv_fn() do ... end      -- private

doc "Returns the length of a list."
fn length(xs) do ... end

@[deprecated]
fn old_api() do ... end
```

---

## Interfaces (Typeclasses)

```march
interface Eq(a) do
  fn eq: a -> a -> Bool
  fn neq: a -> a -> Bool do  -- default implementation
    !eq(x, y)
  end
end

interface Ord(a) requires Eq(a) do
  fn cmp: a -> a -> Int
end
```

---

## Implementations

```march
impl Eq(Int) do
  fn eq(x, y) do x == y end
end

impl Eq(List(a)) when Eq(a) do
  fn eq(xs, ys) do ... end
end
```

---

## Derive

```march
derive Json, Eq for MyType
derive Show for Color
```

---

## Module Imports

```march
use List.*                    -- import all from List
use List.{map, filter}        -- import specific names
use List.map                  -- import single name
use A.B.C.*                   -- dotted path, all names

import String                 -- Elixir-style, all names
import String, only: [length, split]
import String, except: [dangerous_fn]
import String.{length, split} -- dot-brace form
```

---

## Alias

```march
alias Very.Long.Module as Short
alias Very.Long.Module, as: Short   -- comma-colon form
alias Very.Long.Module              -- alias to last segment
```

---

## Signatures

```march
sig MyCollection do
  type Elem
  fn insert: Int -> List -> Int
end
```

---

## FFI (Extern)

```march
extern "libc": Cap(LibC) do
  fn malloc(n: Int): Int
  fn free(ptr: Int): ()
end
```

---

## Capabilities

```march
needs IO.Network, IO.Clock
```

Declares capability requirements for the module.

---

## Actors

```march
actor Counter do
  state { count: Int }
  init { count = 0 }

  on Increment() do
    { state with count = state.count + 1 }
  end

  on GetCount(reply_to) do
    send(reply_to, state.count)
    state
  end
end
```

Spawn an actor and send messages:

```march
let pid = spawn(Counter)
send(pid, Increment())
```

Supervision block inside an actor:

```march
actor App do
  state {}
  init {}
  supervise do
    strategy one_for_one
    max_restarts 3 within 60
    Worker w
  end
end
```

---

## Application Entry Point

```march
app MyApp do
  on_start do
    Logger.info("starting")
  end
  on_stop do
    Logger.info("stopping")
  end
  Supervisor.spec(:one_for_one, [Worker])
end
```

---

## Session Type Protocols

```march
protocol Transfer do
  Client -> Server : Request(String)
  Server -> Client : Response(Int)
  loop do
    Client -> Server : More(String)
    Server -> Client : Ack()
  end
end

protocol Negotiation do
  choose by Client:
    | accept -> Client -> Server : Accept()
    | reject -> Client -> Server : Reject()
  end
end
```

---

## Linear / Affine Types

```march
fn consume(linear h: Handle): () do
  close(h)
end

type Resource = { linear fd: FileDesc }
```

---

## Testing

```march
test "addition works" do
  assert (1 + 1 == 2)
end

describe "arithmetic" do
  setup do
    -- runs before each test in this describe block
  end

  setup_all do
    -- runs once before all tests
  end

  test "multiply" do
    assert (2 * 3 == 6)
  end
end
```

---

## Debugger

```march
dbg()                         -- unconditional breakpoint
dbg(some_expr)                -- trace / conditional
```

---

## Complete Module Example

```march
mod Main do

use List.*

type Shape = Circle(Float) | Rect(Float, Float)

fn area(Circle(r)) do
  3.14159 *. r *. r
end
fn area(Rect(w, h)) do
  w *. h
end

fn main() do
  let shapes = [Circle(1.0), Rect(2.0, 3.0)]
  let areas  = shapes |> map(fn s -> area(s))
  print(to_string(areas))
end

end
```
