# March Syntax Quick Reference

> Part of the March Language Reference; see [specs/lang/index.md](index.md)

A terse example of every construct. See `lib/parser/parser.mly` for authoritative grammar, or [`grammar.md`](grammar.md) for the normative, resolved grammar reference (precedence/associativity made explicit, the lexer + `token_filter` preprocessing layers formalized, backed by a parse/reject conformance corpus).

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

Multi-head pattern matching: consecutive clauses with the same name are merged:

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

Multiple defaults: all must be trailing parameters:

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
fn -> compute()               -- zero-arg short form
fn () -> compute()            -- zero-arg explicit form (identical)
```

Multi-statement lambda bodies are supported with leading `let` bindings followed by
a final expression, identical to match arm block bodies:

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
Single-expression lambdas are unchanged: no `let` bindings means no `EBlock` wrapper.

Both `fn -> expr` and `fn () -> expr` are valid zero-arg lambdas; they are identical.

---

## Let Bindings

Block-level `let`: no `in`; subsequent exprs in the block see the binding:

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

## Result Propagation (`let?`)

`let? p = e` binds the `Ok` payload of a `Result` expression and short-circuits on `Err`:

```march
fn parse_and_add(a: String, b: String): Result(Int, String) do
  let? x = int_from_string(a)   -- propagates Err(msg) immediately
  let? y = int_from_string(b)   -- only reached if previous succeeded
  Ok(x + y)
end
```

Rules:
- The right-hand side must be `Result(T, E)`.
- The pattern binds the `T` (Ok payload).
- The code after the `let?` must also produce `Result(R, E)`; the error type `E` must match across all `let?` bindings in the block.
- `let?` cannot be the last expression in a block (there must be something after it).

Works in function bodies, match arms, and lambda bodies:

```march
fn process(items: List(String)): List(Result(Int, String)) do
  List.map(items, fn s ->
    let? n = parse(s)
    Ok(n * 2))
end
```

---

## Types

Variant (ADT), no leading `|`:

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

Phantom label type (`tag`, a zero-arg type used as a state or resource marker):

```march
tag ConnTag    -- equivalent to: type ConnTag = ConnTag
tag Open       -- equivalent to: type Open = Open
tag Closed     -- equivalent to: type Closed = Closed
```

Always-linear type (every binding is automatically tracked as linear; no per-site annotation needed):

```march
always_linear type Handle(r, s) = Handle(Int)
-- Binding a Handle without consuming it is a compile-time error.
-- Double-use is also an error.
```

Combining `tag` + `always_linear type` for typestate handles:

```march
mod Connection do
  tag ConnTag
  tag Open
  tag Closed

  always_linear type Conn(r, s) = Conn(Int)

  fn connect(_host : String) : Conn(ConnTag, Closed) do Conn(0) end
  fn open(h : Conn(ConnTag, Closed)) : Conn(ConnTag, Open) do
    match h do Conn(raw) -> Conn(raw) end
  end
  fn close(h : Conn(ConnTag, Open)) : Unit do
    match h do Conn(_) -> () end
  end
end
-- Wrong-state calls are caught at compile time.
-- Dropped handles are caught at compile time.
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

## Refinement Types

A base type plus a predicate, checked by an SMT solver (Z3) at compile time.
`_` is the value being refined; a named binder (`v : T`) is required to reach
fields or pass the value to a measure.

```march
{Int | _ >= 0}                     -- a non-negative Int
{Int | _ != 0}                     -- a non-zero Int
{v : Int | v >= 0 && v < 100}      -- named binder form
{String | len(_) > 0}              -- a non-empty String
{String | _ != ""}                 -- literal equality
{Bool | _ == true}                 -- a Bool (operator form; `not _` won't parse)
{Float | _ >= 0.0}                 -- a Float, via Z3's IEEE-754 theory
{Float | _ != 0.0}                 -- a safe divisor (`-0.0` is rejected too)
{Option(Int) | is_Some(_)}         -- an ADT constructor tag
{v : Cfg | v.port >= 1}            -- a record field
{v : Cfg | v.port > v.retries}     -- one field against another
{v : Tree | size(v) < 100}         -- a @[measure] over a structure
```

The predicate fragment is `+ - *` (literal coefficients), the comparisons
`== != < <= > >=`, the connectives `&& || not`, literals, field projection,
`len`, `is_<Ctor>` testers, and `@[measure]` functions. A predicate may also
mention **another parameter**, which makes it *relational*:

```march
fn slice(lo : Int, hi : {Int | _ > lo}) : Int do hi end
fn get(t : Tree, i : {Int | _ >= 0 && _ < size(t)}) : Int do i end
fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do ... end
```

Used as parameter (precondition) or return (postcondition) types. A return
refinement the checker can **prove** propagates to call sites, so
`takepos(neg())` is rejected when `neg` promises `{Int | _ < 0}`.

A `@[measure]` function (total, terminating, pure, recursive by structure) may
be used in predicates:

```march
@[measure]
fn size(t : Tree(a)) : Int do
  match t do
    Leaf          -> 0
    Node(l, x, r) -> 1 + size(l) + size(r)
  end
end
```

Checking is definite-failure: it flags only what can *never* hold, so there
are no false positives, and silence means "not disproved", never "verified".
It runs only when `z3` is on `PATH`. A predicate calling a name the checker
does not know produces a **warning** rather than silently enforcing no check at all.

`Float` predicates are **comparisons only**; float *arithmetic* in a predicate
(`_ +. 1.0 > 0.0`) is out of scope and makes the obligation skipped rather than
guessed at. They are discharged through Z3's bit-precise IEEE-754 theory, never
by modelling floats as reals: over reals `not (x >= 0.0) && not (x <= 0.0)` is
unsatisfiable and correct code would be flagged, while over floats it is
satisfiable (witness: `NaN`) and correctly stays silent.

See the [Refinement Types guide](refinement-types.md) for the full story and
the exact limitations (float arithmetic, float record fields and special-value
predicates are out of scope; strings support only `len` and literal equality;
higher-order checking covers refined callback types and local aliases but not
unrefined callbacks or `interface` dispatch).

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
Some(x) as whole          -- as-pattern: binds `whole` to the entire value
                          --   while `x` destructures it
{ x: a, y: b }            -- record pattern: destructures fields x, y
{ x, y }                  -- punned: shorthand for { x: x, y: y }
1 | 2 | 3                 -- or-pattern: matches any of the alternatives
Red | Green               -- or-pattern over nullary constructors
```

In a `match` arm, a record pattern's field list is open: `{ x: a }` matches
any record with (at least) an `x` field, whatever else it has, and fields it
doesn't mention are simply not bound. Naming a field the record lacks is a
compile error. A `let` binding and a bare record-pattern function parameter
still require naming every field of the scrutinee, since neither has an
independent expected type to open the pattern against:

```march
match point do
  { x: 0 } -> "on y-axis"   -- y need not be named
  _        -> "elsewhere"
end
let { x: px, y: py } = point   -- let: every field still required
fn area({ w: w, h: h }) do w * h end   -- fn param: every field still required
```

An or-pattern's alternatives may **not** bind variables: `A(x) | B(x) -> x`
is a compile error, because every alternative shares one arm body:

```march
match n do
  1 | 2 | 3 -> "small"   -- OK: no alternative binds anything
  _         -> "big"
end

match e do
  A(x) | B(x) -> x * 10   -- OK: every alternative binds `x` at the same type
end

match e do
  A(x) | B(y) -> x + y    -- REJECTED: alternatives must bind the same names
end
```

Split into separate arms, or match the common shape and test the difference
with a `when` guard, instead.

---

## Match

```march
match expr do
  Nil        -> "empty"
  Cons(h, _) -> h
end
```

Arms separated by newlines. Multi-statement arms need no wrapper:

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
else
  "non-positive"
end
```

Both branches can be multi-statement:

```march
if x > 0 do
  let msg = "positive"
  print(msg)
else
  print("non-positive")
end
```

`else` is **mandatory**; omitting it is a parse error:

```
March `if` expressions always need an `else` branch:
```

There is no `then` keyword; `if c then e1 else e2` is rejected with a targeted parse error:

```
I don't recognize `then` here — March uses do/end blocks instead.
```

---

## Operators

Integer arithmetic: `+`, `-`, `*`, `/`, `%`
Float arithmetic: `+.`, `-.`, `*.`, `/.`
String/list concat: `++`
Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
Logic: `&&`, `||`, `!` (prefix not), unary `-` (negate)

Each `++` allocates and copies both operands into a new string/list. A chain
of them (`a ++ b ++ c`) is collapsed into three-way concats by the compiler, so
k parts cost `ceil((k-1)/2)` allocations rather than k-1. But using `++` as a
loop accumulator (`acc = acc ++ x`) still copies `acc` again on every iteration,
which is O(n²) overall. String interpolation (`"${a}${b}"`) desugars to exactly
the same `++` chain and gets the same treatment. For accumulating many segments
across loop iterations, use `IOList` (`stdlib/iolist.march`), which builds a
tree and defers concatenation to a single O(n) pass at the end.

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
let p = { x: 1.0, y: 2.0 }
```

Field access:

```march
p.x
```

Functional update:

```march
{ p with x: 3.0 }
{ state with count: state.count + 1, name: "new" }
```

---

## Function Calls & Field Access

```march
List.map(xs, fn x -> x + 1)   -- module-qualified call
String.byte_size(s)
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

### Allocation contracts

```march
@[no_alloc]           -- error if the compiled function, or anything it calls, allocates
fn inc_leaves(t : Tree) : Tree do ... end

@[no_alloc(warn)]     -- same check, reported as a warning

@[no_alloc(transient)] -- weaker: allocations are allowed, but none may SURVIVE the call
fn frame(w : World) : Int do ... end

@[no_alloc(assume)]   -- never checked; callers trust it (for closure/extern wrappers)
```

Checked on the final compiled form, after reference counting and escape
analysis, so a constructor the compiler reuses in place (`♻`) and a value it
promotes to the stack (`⚡`) both pass. The check is transitive over callees and
needs no annotation on them; the one exception is a call through an unknown
closure or an `extern`, which fails unless the enclosing function is
`assume`. `fn` and `pfn` only — on an actor or with any other payload it is a
parse error. A `doc` string comes FIRST, then the attributes, then the
declaration (`doc "..."` / `@[no_alloc]` / `fn f() ...`); the reverse order is
a parse error. The interpreter and `march --check` ignore the attribute. See
[memory model](memory-model.md) for how to make a function pass, and
[capabilities](capabilities.md) for how this differs from `cap no_alloc`.

`transient` asks a different question: not "did it allocate" but "does anything
it allocated outlive the call". A function fails it when it returns something
it allocated, writes one into an object it did not allocate, or hands one to an
actor, a `Vault`, a spawned task, an `extern` or an unknown closure — and when
anything it calls does. It passes when a callee allocates freely and the
annotated function drops the result before returning, which is exactly the case
the bare form rejects. An amortized growth path (a buffer that reallocates its
storage and keeps the new storage) is *retained*, so `transient` rejects it too
— it is not a way to bless growable buffers.

---

## Interfaces (Typeclasses)

```march
interface Eq(a) do
  fn eq: a -> a -> Bool
  fn neq: a -> a -> Bool do  -- default implementation
    fn (x, y) -> !eq(x, y)  -- default body's type is the FULL arrow type, not the return type
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
needs LibC, IO.Foreign

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
  init { count: 0 }

  on Increment() do
    { state with count: state.count + 1 }
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
  state { w : Int }
  init { w: 0 }
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
  Supervisor.spec(:one_for_one, [worker(Worker)])
end
```

---

## Tasks (structured concurrency)

Spawn a task and await its result:

```march
let t = Task.async(fn () -> expensive_computation())
Task.await(t)               -- Ok(result) or Err(reason)
Task.await_unwrap(t)        -- unwrap, panic on Err
```

Parallel map:

```march
let results = Task.async_stream([1, 2, 3], fn n -> n * n)
-- [Ok(1), Ok(4), Ok(9)]
```

Structured combinators:

```march
-- First to finish wins; the rest are cancelled
Task.race([t1, t2, t3])

-- First Ok wins; all-Err returns Err(list_of_reasons)
Task.any([t1, t2, t3])

-- Collect every result; never short-circuits
Task.all_settled([t1, t2, t3])   -- [Ok(v1), Err(e2), Ok(v3)]

-- Cancel any tasks still running when the scope exits
Task.scope(fn () ->
  let t = Task.async(fn () -> fetch_data())
  Task.await_unwrap(t)
)
```

Cancellation tokens:

```march
let tok = task_cancel_token_new()
task_is_cancelled(tok)                          -- false

let t = task_spawn_with_cancel(fn _ -> work(), tok)
task_cancel(tok)                                -- mark cancelled
Task.await(t)                                   -- Err("cancelled")

-- Cancel a running task by its handle
task_cancel_by_id(t)
```

---

## Session Type Protocols

```march
protocol Transfer do
  Client -> Server : String
  Server -> Client : Int
  loop do
    Client -> Server : String
    Server -> Client : Bool
  end
end

protocol Negotiation do
  choose by Client:
    | accept -> Client -> Server : Bool
    | reject -> Client -> Server : Bool
  end
end

-- `stop` exits an enclosing `loop` instead of repeating it; legal only
-- inside a `loop` body, directly or inside a `choose` branch nested in one.
protocol Stream do
  loop do
    Prod -> Cons : Int
    choose by Cons:
      more -> Cons -> Prod : Bool
      done -> Cons -> Prod : Bool
              stop
    end
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

-- setup/setup_all are module-level declarations, not nested inside describe
setup do
  -- runs before each test
  ()
end

setup_all do
  -- runs once before all tests
  ()
end

describe "arithmetic" do
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

## Semantics notes

Behaviors real users hit that aren't obvious from the syntax above. Each was
verified against HEAD with a runnable probe program, not brought over from
an older finding without re-checking.

### Top-level `let` RHS: re-evaluated once per referencing function (compiled), once total (interpreter)

A module-level `let name = rhs` is a single binding in source, but the two
backends give it different evaluation counts when `rhs` has a side effect and
multiple functions reference `name`. The interpreter evaluates `rhs` exactly
once (during module env construction) and every function sees the same
value. The compiled backend has no shared module-init step for top-level
lets; instead, the top-level-let injection post-pass in `lib/tir/lower.ml`
(the `fn_body_uses` scan, marked by the comment "Inject top-level let
bindings into function bodies that reference them") walks each function body
and, for every top-level let it references, injects a fresh
`ELet (v, rhs, body)` at the top of *that function*. If two functions and
`main` all reference the binding, the compiled binary re-evaluates `rhs`
three times, once per injection site.

```march
mod Main do
  let shared = do
    println("evaluating shared RHS")
    42
  end

  fn use_a() do
    println("use_a sees: " ++ int_to_string(shared))
  end

  fn use_b() do
    println("use_b sees: " ++ int_to_string(shared))
  end

  fn main() do
    use_a()
    use_b()
    println("main sees: " ++ int_to_string(shared))
  end
end
```

Interpreter output, one evaluation:

```
evaluating shared RHS
use_a sees: 42
use_b sees: 42
main sees: 42
```

Compiled (`--compile`): `evaluating shared RHS` prints **three times**, one
per referencing function (verified with `| grep -c`). The exact interleaving
of the injected evaluations relative to the other output lines is not
guaranteed and has been observed to differ across builds; the invariant is
the *count*: one evaluation per function that references the binding, versus
exactly one total in the interpreter.

Only pure top-level lets are safe across both backends; a side-effecting or
non-idempotent top-level `let` RHS will observably run more times in compiled
code.

### Newline-glom: a continuation token on the next line joins the previous expression

Outside `match` bodies, `lib/parser/token_filter.ml`'s NL filter
unconditionally swallows newline tokens (the `NL` dispatch arm with a fallback that
reads `next lexbuf  (* outside match body — swallow *)`); the parser never
sees them. Statement separation inside `block_body` (the
`block_body: nonempty_list(block_expr)` production in
`lib/parser/parser.mly`) is therefore purely a side effect of where
Menhir's grammar happens to close one `expr` and open the next. A line that
*starts* with a token that can continue the prior expression, `(` (call/tuple),
`-` (binary minus), or any infix operator (`++`, `+`, etc.), gloms onto the
previous line instead of starting a new statement.

```march
-- `- 1` on its own line binds to the previous let, not a new statement:
let a = 10
let b = a
- 1
-- desugars to `let b = a - 1`  (b = 9), not two statements
```

```march
-- a `(...)` line is parsed as a call on the preceding expression:
let f = identity
(5)
-- desugars to `let f = identity(5)`  (f = 5), not `f = identity` then a bare `(5)`
```

The sharpest trap is when the previous line's value isn't callable: the
error surfaces far from the real mistake:

```march
let a = 5
println("a = " ++ int_to_string(a))
let b = 10
(negate(b))
println("...")
```

fails to typecheck with `This is not a function — it has type Int`, pointing
at `let b = 10`, because `let b = 10 \n (negate(b))` glommed into
`let b = 10(negate(b))`. The fix is to make the continuation impossible:
start the next line with something that cannot extend an expression (another
`let`, a bare identifier call with no leading operator/paren ambiguity), or
parenthesize/terminate the prior expression so the next line can't attach.

### Derived `Ord`/`Hash` ignore constructor payloads

(The compiled-crash part of this section, named `eq`/`compare`/`hash` on
`Newtype`-repr variants SIGSEGV'ing or panicking, was fixed 2026-07-04; see
`specs/progress/` for the root cause and fix. The
payload-ignoring `Ord`/`Hash` *semantics* below are unchanged and intentional.)

**Semantics (interpreter, and compiled where it doesn't crash):** `derive Ord
for T` and `derive Hash for T` on a variant type only look at the
constructor's declared index, never its payload fields. `expand_derive` in
`lib/desugar/desugar.ml` builds the derived `compare` body (its `"Ord"` case)
as `ctor_index(a) - ctor_index(b)`, matching each constructor with wildcard
patterns (`PatWild`) that discard the arguments; the derived `hash` body (the
`"Hash"` case) does the same, returning the bare constructor index. Two
values built from the *same* constructor always compare equal and hash equal,
regardless of payload. Derived `Eq` is different: it IS payload-aware
(`eq(Wrap(1), Wrap(2))` is `false`), so a type deriving both `Eq` and `Ord`
reports `eq(a, b) == false` yet `compare(a, b) == 0` for same-constructor
values with different payloads.

```march
mod Main do
  type Wrap = Wrap(Int)
  derive Ord for Wrap
  derive Hash for Wrap

  fn main() do
    println(int_to_string(compare(Wrap(1), Wrap(2))))  -- 0, not -1
    println(int_to_string(hash(Wrap(1))))               -- 0
    println(int_to_string(hash(Wrap(2))))               -- 0 (same as Wrap(1))
  end
end
```

Interpreter output: `0` / `0` / `0`, payload ignored. Compiled output is
identical (this used to crash on single-ctor single-field (`Newtype`-repr)
variants; fixed 2026-07-04, see `specs/progress/`).

Records are unaffected: derived `Ord`/`Hash` for `TDRecord` compares/hashes
field-by-field as expected. Do not rely on derived `Ord`/`Hash` for any
variant type with constructors that include payload data that should affect
ordering or hashing; write a manual `impl` instead.

### Nested-module default-arg functions (fixed 2026-07-15)

Nested default-arg functions used to silently drop their default values (a
`fn f(x, y \\ default)` inside a nested `mod ... do ... end` took a fast
desugar path that stripped every default down to a required parameter), and
separately, a default-arg function's own bare name couldn't be resolved from
source at any arity (`I cannot find `add`` under `--check`). Both were fixed
in the same slice (`specs/todos/`, 2026-07-15, open-items plan Phase 7.1):
`expand_defaults_decl` now recurses into nested modules, and the typechecker
redirects an unbound `foo(args)` call to its arity-specific variant. Nested
default-arg functions now behave identically to top-level ones, on both
backends:

```march
mod Main do
  mod Inner do
    fn add(x, y \\ 10, z \\ 20) do x + y + z end
  end

  fn main() do
    println(int_to_string(Inner.add(1)))         -- 31
    println(int_to_string(Inner.add(1, 5)))       -- 26
    println(int_to_string(Inner.add(1, 5, 6)))    -- 12
  end
end
```

### Reserved soft-keyword imbalance: bindable but not referenceable

A handful of identifiers double as keywords elsewhere in the grammar
(`init`, `loop`, `on`, `state`, `protocol`, `app`, `as`, `with`, `when`, `use`,
`in`, `for`) and are listed in the `soft_lower_name` production
(`lib/parser/parser.mly`) so they can be used in *binding* positions:
function params, patterns, and `let` bindings. They are **not** listed in
the primary-expression rule for a bare variable reference (the
`id = LOWER_IDENT { EVar (mk_name id $loc) }` production in the same file),
so referencing one of them in expression position (even a bare reference,
not just inside an arithmetic expression) is a parse error:

```march
let init = 3           -- parses: `init` accepted as a binding name
println(int_to_string(init))       -- "I got stuck here" — `init` rejected as an expr
println(int_to_string(init + 1))   -- same error
```

The same restriction blocks declaring a function named `init` (`fn init(x)
do ... end`: function names use the plain `lower_name` rule, not
`soft_lower_name`, so this is also a parse error); it is the identical root
cause as the expression-position gap, not a separate bug.

`tag` is the one exception: commit `4bb0e87c` promoted it to a full soft
keyword by adding it to *both* the `lower_name` production (declarations,
dot-access, record fields) and the primary-expression variable-reference
rule, so `let tag = 3` followed by `tag + 1` works end-to-end. The other
soft keywords above have not received the same treatment; the imbalance is
current behavior, not a stale finding.

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
