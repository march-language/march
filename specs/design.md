# March Language Design

March is a statically-typed functional programming language built for safe concurrency, fast compilation, and excellent developer tooling. The compiler is implemented in OCaml 5.

## Goals

1. **Fast compilation** — query-based compiler architecture with content-addressed caching; no gratuitous passes
2. **Good error messages** — provenance-tracked types, bidirectional checking, typed hole error recovery
3. **Fast execution** — whole-program defunctionalization and monomorphization with unboxed representations
4. **Safe concurrency** — actors with multi-party session types and capability-secure messaging
5. **LLM-friendly tooling** — typed holes, canonical formatter, MCP server, type-directed completion, semantic search by type signature

## Core Language

- **Paradigm**: Functional-first, expression-oriented, immutable by default
- **Syntax style**: ML/Elixir hybrid — ML type system with Elixir-style `do/end` blocks
- **Comments**: `--` line comments, `{- -}` nested block comments
- **Literals**: integers, floats, strings, booleans, atoms (`:ok`, `:error`)
- **Blocks**: `do ... end` — explicit delimiters, not indentation-sensitive
- **Functions**: `fn name(x, y) do ... end` — named, parenthesized arguments
- **Lambdas**: `fn x -> x + 1` or `fn(x, y) -> body` — `fn` keyword avoids ambiguity with expressions
- **Pipes**: `x |> f |> g` — left-to-right data flow
- **Pattern matching**: `match expr do | Pat -> body end`
- **Let bindings**: `let x = expr` — block-scoped, no `in` keyword needed
- **Type annotations**: Optional everywhere except where inference fails (recursive functions, ambiguous overloads). Top-level signatures are encouraged but not required.
- **Typed holes**: `?name` or `?` — the compiler reports the expected type, enabling type-directed development and LLM completion
- **Atoms**: `:name` — lightweight runtime tags used for messaging and symbol comparisons. Not type constructors — ADTs use capitalized constructors instead.
- **Function head matching**: Multiple `fn` clauses with the same name are grouped into one function with pattern-matched heads (Elixir-style). Desugared into a single function with a `match` immediately after parsing (before type checking), so the type checker and backend each handle one representation.
- **Guards**: `when` clauses on function heads and match branches
- **Sigils**: `~H"..."` or `~H"""..."""` — domain-specific string literals. `~X` prefix where X is an uppercase letter. Supports interpolation (`${expr}`). Desugars to `Sigil.x(content)` call. `~H` for HTML templates returns `IOList` for fast wire transfer.
- **No algebraic effects**: Concurrency is via actors and message passing, not resumable continuations. Side effects are tracked via capability types, not an effect system.

### Syntax Examples

```march
-- Named function with type annotation
fn greet(name : String) : String do
  "Hello, " ++ name
end

-- Pattern matching
fn factorial(n : Int) : Int do
  match n do
  | 0 -> 1
  | n -> n * factorial(n - 1)
  end
end

-- Function head matching (Elixir-style)
fn factorial(0) : Int do 1 end
fn factorial(n) : Int do n * factorial(n - 1) end

-- With guards
fn classify(n : Int) : String when n < 0 do "negative" end
fn classify(0) : String do "zero" end
fn classify(_) : String do "positive" end

-- Pipes and lambdas (fn keyword for lambdas)
fn process(data : List(String)) : List(Int) do
  data
  |> filter(fn s -> s != "")
  |> map(fn s -> parse_int(s))
  |> filter(fn r -> r != :error)
end

-- Let bindings (block-scoped, last expression is the return value)
fn example() : Int do
  let x = 42
  let y = x + 1
  y * 2
end

-- ADTs use capitalized constructors; atoms remain lightweight runtime tags
type Result(a, e) = Ok(a) | Err(e)
type Option(a) = Some(a) | None

fn safe_div(a : Int, b : Int) : Result(Int, String) do
  match b do
  | 0 -> Err("division by zero")
  | _ -> Ok(a / b)
  end
end

-- Typed holes
fn handle_input(input : String) : Result(Int, String) do
  let parsed = ?parse_step
  ?validate_step
end

-- Linear types and capabilities
fn send_file(cap : linear Cap(Server), file : linear File) do
  send(cap, Upload(file))
end
```

## Built-in Types

### Primitives (compiler-known, optimized codegen)

| Type | Description |
|---|---|
| `Int` | 64-bit signed integer, the default numeric type |
| `Float` | 64-bit IEEE 754 floating point |
| `Byte` | 8-bit unsigned, for IO and binary data |
| `Bool` | `true` / `false` |
| `String` | UTF-8, immutable |
| `Char` | Single Unicode scalar value (not a byte) |

### Standard Library Numeric Types

| Type | Description |
|---|---|
| `BigInt` | Arbitrary precision integers |
| `Decimal` | Fixed-point exact decimals (money, finance — no floating-point bugs) |
| `Ratio` | Exact rational numbers |

Numeric abstraction uses interfaces, not a proliferation of primitive sizes:

```march
interface Num(a) do
  fn add(x : a, y : a) : a
  fn mul(x : a, y : a) : a
  fn neg(x : a) : a
  fn from_int(n : Int) : a
end

interface Fractional(a) : Num(a) do
  fn div(x : a, y : a) : a
end
```

### String Types

```march
String              -- UTF-8, immutable, the workhorse
Char                -- single Unicode scalar value
Rope                -- stdlib: large string manipulation (editors, log assembly)
Regex               -- stdlib: compiled regex pattern
```

**String interpolation** uses `${}` syntax, desugared to `++` and `to_string` chains:

```march
let msg = "Hello, ${name}! You have ${count} items."
-- desugars to: "Hello, " ++ to_string(name) ++ "! You have " ++ to_string(count) ++ " items."
```

The lexer emits `INTERP_START` / `INTERP_MID` / `INTERP_END` tokens; the desugar pass builds the concatenation chain. Any value with a `to_string` conversion can appear in `${}`.

**String interface** for polymorphic operations:

```march
interface Textual(a) do
  fn length(s : a) : Int
  fn slice(s : a, start : Int, len : Int) : a
  fn concat(a : a, b : a) : a
  fn to_string(s : a) : String
end
```

### Collections

| Type | Description |
|---|---|
| `List(a)` | Linked list — good for pattern matching, cons/uncons |
| `Array(a)` | Fixed-size, contiguous, cache-friendly, O(1) indexed access |
| `Map(k, v)` | Immutable key-value map |
| `Set(a)` | Immutable set |
| `Option(a)` | `Some(a) \| None` |
| `Result(a, e)` | `Ok(a) \| Err(e)` |

`Array` interacts with linear types for true in-place mutation:

```march
-- Immutable: returns a new array
let ys = Array.set(xs, 42, 3.14)

-- Linear: in-place mutation, zero copies
linear let buf = Array.create(1024, 0.0)
linear let buf = Array.set!(buf, 0, 1.0)   -- buf consumed and rebound
```

### Sized Vectors and N-Dimensional Arrays

Length and shape are encoded in the type via **type-level naturals**, catching dimension mismatches at compile time.

**`Vector(n, a)`** — length-indexed:

```march
let v1 : Vector(3, Float) = vec [1.0, 2.0, 3.0]
let v2 : Vector(3, Float) = vec [4.0, 5.0, 6.0]

-- dot product requires same length — compile-time check
fn dot(a : Vector(n, Float), b : Vector(n, Float)) : Float do
  sum(zipWith(mul, a, b))
end

-- type error: Vector(2, Float) vs Vector(3, Float)
let bad = dot(vec [1.0, 2.0], vec [1.0, 2.0, 3.0])
```

Type-level arithmetic supports `+` and `*`:

```march
fn concat(a : Vector(n, a), b : Vector(m, a)) : Vector(n + m, a)
fn head(v : Vector(n + 1, a)) : a                -- non-empty!
fn tail(v : Vector(n + 1, a)) : Vector(n, a)
```

**`NDArray(shape, a)`** — multi-dimensional:

```march
type alias Matrix(m, n, a) = NDArray([m, n], a)

fn matmul(a : Matrix(m, n, Float), b : Matrix(n, p, Float))
    : Matrix(m, p, Float)

fn transpose(m : Matrix(r, c, a)) : Matrix(c, r, a)

-- Reshape: total elements must match
fn reshape(arr : NDArray(s1, a)) : NDArray(s2, a)
    where Product(s1) = Product(s2)
```

### Concurrency Types (compiler-known, runtime-supported)

| Type | Description |
|---|---|
| `Pid(a)` | Typed, location-transparent actor reference |
| `Cap(a)` | Unforgeable capability token (non-linear, reusable) |
| `Future(a)` | Async computation result |
| `Stream(a)` | Async sequence of values |
| `Task(a)` | Lightweight parallel computation (structured concurrency) |
| `Node` | Cluster node reference |

**`Pid(a)`** is location-transparent (Erlang model) — you don't know or care which node an actor lives on. The runtime handles routing.

**`Future(a)`** — async results from actor interactions:

```march
let result : Future(Int) = ask(counter, GetCount)
let total  : Future(Int) = map2(result1, result2, fn (a, b) do a + b end)
let value  : Int = await(result)
```

**`Stream(a)`** — ongoing async sequences (logs, metrics, events, pub/sub):

```march
actor Sensor do
  pub stream readings : Stream(Float)
end

subscribe(sensor.readings, fn (reading) do
  if reading > threshold do alert() end
end)
```

**`Task(a)`** — structured parallel concurrency (lighter than actors, no mailbox, no state):

```march
let t1 = spawn_task(fn do expensive_compute(data1) end)
let t2 = spawn_task(fn do expensive_compute(data2) end)
let (r1, r2) = await_all(t1, t2)
```

Tasks are scoped — they must complete before the enclosing scope exits. No leaked goroutines.

### Constraints (compiler-derived)

**`Sendable(a)`** — marks types that can cross node/thread boundaries. The compiler derives it automatically for types composed entirely of sendable parts. It refuses to derive it for closures, mutable references, linear pointers, and capabilities (caps are node-local).

```march
-- Actor messages enforce Sendable automatically
actor Worker do
  on Process(data : a) where Sendable(a) do ... end
end

-- Parallel operations require Sendable
fn par_map(items : List(a), f : a -> b) : List(b)
    where Sendable(a), Sendable(b)
```

### FFI Types

| Type | Description |
|---|---|
| `linear Ptr(a)` | Foreign pointer — linear ensures freed exactly once |
| `Cap(LibC)` etc. | Per-library FFI capability |

## Type System

### Hindley-Milner with Bidirectional Checking

The core is standard HM type inference. At function boundaries (top-level definitions, lambdas with annotations), we switch to **bidirectional type checking** — the expected type flows inward, giving the type checker information about what was intended vs. what was found.

- **Inference**: Works inside function bodies where types flow naturally
- **Checking**: Kicks in at annotated positions, propagating the expected type downward
- **No dependent types**: Keeps type checking decidable and compilation fast

### Provenance-Tracking Types

Every type constraint carries a *reason* — not just a source span, but *why* the constraint exists. When unification fails, the error shows the chain of reasoning:

> Expected `Int` here because it was passed to `+` (line 5), which requires `Int` on both sides. But this expression has type `String` because `name` was bound as `String` on line 3.

Implementation: each type in the constraint solver is paired with a `provenance` value recording which syntactic construct or inference rule introduced it. On unification failure, walk both provenance chains to construct the explanation.

### Error Recovery via Typed Hole Injection

When the parser or type checker encounters an error, it injects a **typed hole** rather than aborting or inserting a generic error node. The rest of the program type-checks around the hole. This unifies two systems:

- **Error recovery**: Errors become holes; the compiler continues and reports multiple diagnostics
- **Typed holes for development**: `?` in user code is the same mechanism — the compiler reports the expected type and available bindings

A hole's type is inferred from context (bidirectional checking flows the expected type into it). Provenance tracking explains *why* that type is expected.

### Algebraic Data Types

Sum and product types with capitalized constructors:

```march
type Option(a) = Some(a) | None
type List(a)   = Cons(a, List(a)) | Nil
type Point      = { x : Float, y : Float }
type Result(a, e) = Ok(a) | Err(e)
```

Atoms (`:name`) are distinct — they are lightweight runtime symbols used in messaging and pattern matching, not ADT constructors. Standard library types like `Result` and `Option` use capitalized constructors.

### Linear and Affine Types

Values can be qualified with linearity annotations:

- **Unrestricted** (default): Normal values, can be copied and discarded freely
- **Linear**: Must be used exactly once — enables safe resource management, unique ownership
- **Affine**: Must be used at most once — like linear but allows discarding

Linearity enables:
- Safe mutation through uniqueness (if you're the only owner, mutation is safe)
- Actor message-passing isolation (send a linear value = transfer ownership)
- Resource management without garbage collection overhead for critical resources
- FFI safety: foreign pointers enter as linear values that must be freed

### Type-Level Naturals

Natural numbers can appear as type parameters, enabling compile-time dimension checking for vectors, matrices, and n-dimensional arrays. This is a limited form of dependent types — not full term-level dependency, just natural number indices with arithmetic.

The type checker includes:
- A `TNat` type descriptor for literal naturals and nat variables
- Type-level `+` and `*` operators
- Structural unification of nat expressions (e.g., `n + m` unifies with `n + m` but does not simplify `1 + 2` to `3`)

A full constraint solver for equations like `n + m = k` is not yet implemented — type-level arithmetic unifies structurally rather than algebraically.

```march
-- Length in the type
fn concat(a : Vector(n, a), b : Vector(m, a)) : Vector(n + m, a)

-- Non-empty guarantee
fn head(v : Vector(n + 1, a)) : a

-- Shape preservation
fn matmul(a : Matrix(m, n, Float), b : Matrix(n, p, Float)) : Matrix(m, p, Float)

-- Element count preservation
fn reshape(arr : NDArray(s1, a)) : NDArray(s2, a) where Product(s1) = Product(s2)
```

Type-level naturals do not extend to general dependent types. Only `Nat` can appear in type-level positions, and only `+`, `*`, and equality are supported as type-level operations. This keeps type checking decidable.

### Unboxed Types / Representation Polymorphism

The compiler chooses whether values are **boxed** (heap-allocated, behind a pointer) or **unboxed** (inline, stack/register) based on usage:

- Polymorphic functions are monomorphized, so the compiler knows the concrete representation at every call site
- Small types (`Int`, `Float`, `Bool`, pairs of unboxed types) are unboxed by default
- The programmer can influence this with annotations when needed
- This is a backend optimization — invisible to the type checker

Linearity interaction: unboxing is a representation choice made *after* linearity checking. The linearity checker operates on the typed IR where all values are abstract. No friction.

## Module System

### Namespaces

`mod` groups related definitions into a named namespace. Definitions are private by default; `pub` exports them:

```march
mod Collections do
  -- private: callers cannot see or depend on this
  fn rebalance(tree) do ... end

  pub fn insert(x, tree) do ... end
  pub fn lookup(x, tree) do ... end
  pub type Tree(a) = Leaf | Node(a, Tree(a), Tree(a))
end
```

Importing:

```march
use Collections.{insert, lookup}   -- named imports
use Collections.*                  -- all public names
Collections.insert(x, tree)        -- qualified, no import needed
```

### Signatures

A `sig` declares a module's public interface explicitly, decoupling the contract from the implementation:

```march
sig Collections do
  type Tree(a)
  fn insert : (a, Tree(a)) -> Tree(a)
  fn lookup : (a, Tree(a)) -> Option(a)
end
```

The compiler verifies the module satisfies its sig. Downstream code depends on the sig — not the implementation — so internal refactors don't invalidate downstream caches or force recompilation.

### Interfaces (Typeclasses)

Abstraction over types uses `interface` declarations, not module functors:

```march
interface Eq(a) do
  fn eq(x : a, y : a) : Bool
  fn neq(x : a, y : a) : Bool do not eq(x, y) end  -- default implementation
end

impl Eq(Int) do
  fn eq(x, y) do x == y end
end

impl Eq(a) for List(a) when Eq(a) do
  fn eq(xs, ys) do
    match (xs, ys) do
    | (Nil, Nil)           -> true
    | (Cons(x, xs), Cons(y, ys)) -> eq(x, y) and eq(xs, ys)
    | _                    -> false
    end
  end
end
```

Interfaces can have **associated types**, covering the cases where ML functors are typically used:

```march
interface Collection(f) do
  type Elem
  fn empty : f
  fn insert : (Elem, f) -> f
  fn member : (Elem, f) -> Bool
end

impl Collection(List(Int)) do
  type Elem = Int
  fn empty do Nil end
  fn insert(x, xs) do Cons(x, xs) end
  fn member(x, xs) do List.contains(x, xs) end
end
```

### Standard Interfaces and Auto-Derivation

Four standard interfaces cover the most common boilerplate: `Eq`, `Ord`, `Show`, and `Hash`. ADTs can automatically derive these with a `derive` annotation:

```march
type Color = Red | Green | Blue
derive [Eq, Show] for Color

type Point = { x : Int, y : Int }
derive [Eq, Ord, Show, Hash] for Point
```

Derived implementations use structural equality (field-by-field for records, tag then fields for variants), lexicographic ordering for `Ord`, a `"TypeName(field, ...)"` format for `Show`, and a FNV-style mix for `Hash`.

Superclass constraints are enforced: `Ord` requires `Eq`, and `Hash` requires `Eq`. The compiler verifies these at the `impl` site.

### Interface Coherence

An `impl` is only valid in the module that defines the **type** or the **interface** — not both from elsewhere. Orphan instances (implementing someone else's interface for someone else's type) are forbidden.

This ensures:
- At most one `impl` of any interface for any type, globally
- No coherence conflicts when two libraries are combined
- Decidable instance resolution without global program knowledge

### Content-Addressed Versioning

Every definition has a hash. Names are aliases pointing to hashes. **Signatures get their own hash**, separate from implementations — this is the stable dependency surface.

- Changing a private function: impl hash changes, sig hash unchanged, downstream caches unaffected
- Changing a public type or function signature: sig hash changes, dependents are recompiled
- No version numbers: the hash *is* the version

```march
-- import by name: resolves to current hash at build time
use Collections.insert

-- import pinned to exact hash: frozen, reproducible
use sha256:a3f4b2c1... as insert
```

The build system records resolved hashes in a lockfile automatically. "Publishing a library" means registering a mapping from human-readable names to hashes in a shared namespace registry — no separate package versioning scheme needed.

**No dependency conflicts**: two libraries can depend on different hashes of the same function. They're different hashes; both coexist in the content-addressed store. The diamond dependency problem does not exist.

## Actors & Concurrency

### Actor Model

Share-nothing message-passing concurrency. Actors are isolated processes with private state.

```march
actor Counter do
  state { count : Int }
  init { count = 0 }

  on Increment() do
    { state with count = state.count + 1 }
  end

  on GetCount() do
    respond(state.count)
  end
end
```

Actor message handlers return a new state value using record spread syntax: `{ state with field = new_value }`. This is a functional update — it produces a new record with the named fields replaced, all others unchanged. The type checker verifies the result matches the declared state type.

**Isolation guarantees**:
- Linear types ensure messages are transferred, not shared (sending = ownership transfer)
- Actor state is private and only accessible within the actor
- No shared mutable state between actors

### Session Types (Binary, v1)

Typed two-party protocols verified at compile time. Each end of a channel has a dual type — if one side sends, the other must receive; if one side offers a choice, the other must select.

```march
protocol FileTransfer do
  Client -> Server : Open(String)
  Server -> Client : Ready | Err(String)
  loop do
    Client -> Server : Chunk(Bytes) | Done
  end
end
```

What this catches at compile time:
- **Deadlocks**: If both sides wait to receive, the protocol is ill-formed
- **Protocol violations**: Sending the wrong message type at the wrong time is a type error
- **Missing cases**: Not handling a message variant the protocol says you'll receive

Multi-party session types (global choreography + projection to local types) are deferred to post-v1.

### Capability-Secure Messaging

Actors can only send messages to actors they hold a **capability reference** to. References are unforgeable values — you can't conjure a reference to an actor you weren't given.

`Cap(A, e)` is **non-linear** — it is an unforgeable reference, not an ownership token. An actor may copy, share, and use a `Cap` multiple times without consuming it. The epoch parameter `e` tracks the actor's generation; using a stale `Cap` after the actor has been restarted is detected at the call site (type error when statically detectable; `DeadActor` error at runtime otherwise).

For supervision, `ActorId(A)` provides a stable epoch-free identity used to restart actors and set up monitors. See `specs/gc_design.md` (supervision model section) for the full epoch/supervision design.

```march
-- spawn returns a stable identity and an epoch-0 capability
let (counter_id, counter) = spawn(Counter)

-- sending requires the capability; does not consume it
send(counter, Increment())

-- the same cap can be used again
send(counter, Increment())

-- to transfer exclusive access, wrap the cap in a message — the runtime does not enforce exclusivity
-- (use linear session types via Chan for protocols requiring strict turn-taking)
send(other_actor, TransferControl(counter))
```

Combined with capability security:
- **No ambient authority**: An actor can't reach out to arbitrary other actors — it can only talk to actors it was explicitly given access to
- **Unforgeable references**: Capabilities cannot be guessed or synthesized; they must be received through legitimate channels
- **Testability**: In tests, substitute mock actors by providing different capabilities

### Content-Addressed Message Schemas

Messages between distributed actors reference their schema by content hash. A receiving node can verify it has the correct deserializer before accepting data. Schema evolution is explicit: new hash = new schema = explicit migration function required.

## Content-Addressed Code

Every definition is identified by the hash of its complete AST (whole-definition hashing). Names are aliases that point to hashes.

### How It Works

1. After parsing and type checking, each definition's AST is serialized and hashed (e.g., SHA-256)
2. The hash becomes the definition's identity
3. Names in the codebase are human-readable aliases pointing to hashes
4. Recursive definitions use a special "self" reference placeholder (cannot contain their own hash)

### What This Enables

- **Reproducible builds**: Same code = same hash = same output, always
- **Incremental compilation**: If a definition's hash hasn't changed, reuse the cached compilation result. The query-based compiler architecture makes this automatic.
- **No dependency conflicts**: Two libraries using different versions of a function can coexist — they're different hashes
- **Safe distributed actor migration**: Actors can be serialized and moved between nodes; the code they need is identified by hash and can be fetched
- **Semantic code search**: Find all definitions with a given type signature across the entire content-addressed store
- **Defunctionalization caching**: Monomorphized/defunctionalized code is cached by hash — same polymorphic function at the same type = same output

### Trade-offs

- Renaming a variable inside a function changes its hash (whole-definition, not interface-based) — simpler to implement correctly
- Tooling must maintain the name-to-hash mapping

## FFI

### Capability Model

Each foreign library has its own capability type. You cannot call a foreign function without holding the corresponding capability in scope. Capabilities are created at program entry (or by a trusted wrapper module) and passed down explicitly — no ambient access to foreign libraries.

```march
-- A library binding declares its capability type
extern "libc" : Cap(LibC) do
  fn malloc(size : Int) : linear Ptr(a)
  fn free(ptr : linear Ptr(a)) : Unit
  fn strlen(s : Ptr(Byte)) : Int
end

-- Calling foreign functions requires the cap explicitly
fn allocate(cap : Cap(LibC), size : Int) : linear Ptr(a) do
  malloc(cap, size)
end
```

The capability is not consumed by calls (it's unrestricted, not linear) — you hold it for as long as you need access to that library. This mirrors how actor capabilities work: you hold a reference to an actor and can message it repeatedly.

### Foreign Pointer Types

Foreign pointers enter the type system as `linear Ptr(a)`. Linear enforces that they are freed exactly once. `a` is a phantom type carrying C-side type information. The type checker ensures:

- No double-free (linearity)
- No use-after-free (linearity — pointer is consumed at last use)
- No cross-actor pointer sharing (linear values cannot be aliased)

### Unsafe Blocks

Certain operations cannot be statically verified — pointer casting, raw address arithmetic, reinterpreting memory. These require an explicit `unsafe` block:

```march
fn cast_ptr(p : linear Ptr(a)) : linear Ptr(b) do
  unsafe do
    reinterpret_cast(p)
  end
end
```

`unsafe` blocks are:
- Visible in code review and tooling (searchable, auditable)
- Required for: pointer casts, raw arithmetic, calling `extern` functions that return untyped pointers
- Not required for: normal calls to typed `extern` functions with `Cap` in scope

### Marshaling via `CRepr`

Types that cross the FFI boundary implement the `CRepr` interface:

```march
interface CRepr(a) do
  type Raw       -- the C-level representation
  fn to_c   : a -> Raw
  fn from_c : Raw -> a
end
```

Built-in implementations are provided for primitives:

| March type | C type |
|---|---|
| `Int` | `int64_t` |
| `Float` | `double` |
| `Bool` | `int` (0/1) |
| `Ptr(a)` | `void*` |

Strings, arrays, and structs require explicit `impl CRepr(T)` — the programmer decides layout and encoding. There is no implicit marshaling that silently copies or converts.

## Compiler Backend

### Whole-Program Monomorphization

All polymorphic functions are specialized to their concrete type arguments (like Rust/MLton). No runtime type dispatch, no dictionary passing. Content-addressed code makes this tractable:

- The full program is available (all dependencies resolved by hash)
- Monomorphized specializations are cached by (function hash, type arguments) — never recomputed

### Defunctionalization

Higher-order functions are transformed into a tagged union of all possible function values plus a dispatch `apply` function. This eliminates:

- Closure allocation (no heap-allocated function objects)
- Indirect calls (the `apply` dispatch is a known switch)

Combined with monomorphization, this means the generated code is first-order and fully specialized. The content-addressed store provides the whole-program call graph needed for defunctionalization.

**Pass ordering**:
1. Desugar multi-head functions into single functions with match (immediately after parsing)
2. Type check (bidirectional, provenance-tracked, linearity)
3. Session type verification (on actor/protocol code)
4. Strip provenance metadata (not needed past diagnostics)
5. Monomorphize (resolve representation polymorphism, specialize all polymorphic code)
6. Defunctionalize (closures → tagged unions + dispatch)
7. Code generation

### Perceus Reference Counting and FBIP

Memory management in March uses **deterministic reference counting** with compile-time RC insertion, augmented by an optimization called **FBIP (Functional But In-Place)**.

#### How Perceus RC works

Every heap-allocated value (ADT constructor, closure, string) has a reference count in a header word. The Perceus pass — running over the TIR after monomorphization and defunctionalization — inserts `IncRC` and `DecRC` operations statically, without any GC scanner or write barrier:

1. **Backwards liveness analysis**: The pass computes which variables are live before each expression by propagating liveness backwards through the IR. A variable is "last used" at the point where it leaves the live set.
2. **RC insertion**: Non-last uses of a heap variable get `IncRC` before the use (to prevent premature collection). Last uses get nothing — the existing reference is consumed. Dead let-bindings get `DecRC` at the point of death.
3. **Cancel-pair elision**: Adjacent `IncRC v` / `DecRC v` pairs are removed as a peephole pass. These arise when a value is passed to a function and immediately returned — the net RC change is zero.
4. **Runtime behavior**: `DecRC` calls the runtime, which decrements the count. If it reaches zero, the object is freed (and its children are recursively decremented). `IncRC` increments the count. Linear and affine values are `free`'d directly without counting. (Atomic RC for multi-threaded access is a planned upgrade; the current implementation is non-atomic, safe for single-threaded and actor-per-thread patterns where explicit borrowing is used at thread boundaries.)

The result is fully deterministic memory management: memory is freed exactly when the last reference is dropped, with no GC pauses, no conservative scanning, and no write barriers on the hot path.

#### FBIP — reusing destructured values in-place

The key insight behind FBIP: if a function pattern-matches a heap value and then immediately allocates a new value of the same constructor shape, _and_ the original value has RC == 1 (uniquely owned), the new allocation is unnecessary. The old memory can be overwritten in-place do the new field values.

Consider the tree transformation in `bench/tree_transform.march`:

```march
fn inc_leaves(t : Tree) : Tree do
  match t do
  | Leaf(n)    -> Leaf(n + 1)
  | Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
```

Without FBIP, each call allocates a fresh `Leaf` or `Node` and frees the original — 2^depth allocator calls per pass.

**How FBIP detects the opportunity**: After RC insertion, each match branch gets a `DecRC(t)` at the branch head (since `t` is consumed by the match and not live after). The Perceus FBIP sub-pass then scans for the pattern `DecRC(v); ...; EAlloc(same_shape)` and, when found, replaces the pair do a single `EReuse(v, shape, new_fields)` node. The `...` in between may be a chain of `ELet` bindings, as long as `v` itself is not referenced in any of the intermediate RHS expressions (otherwise sinking the decrement past them would be unsound).

**What the generated code does at runtime**: `EReuse(v, shape, args)` compiles to a conditional:

```
rc = load v.header
if rc == 1:
    v.tag   = new_tag          -- overwrite in-place
    v.field0 = args[0]
    ...
    result = v                 -- return the same pointer
else:
    march_decrc(v)             -- release our reference
    result = march_alloc(...)  -- allocate fresh
    result.tag   = new_tag
    result.field0 = args[0]
    ...
```

The RC == 1 path writes directly into the existing allocation and returns the same pointer — no allocator call, no free. The RC > 1 path handles the shared case correctly.

#### The shape_matches bug and fix

The Perceus pass annotates each branch's `DecRC` with the **concrete constructor type** — e.g. type `TCon("Leaf", [])` for the `Leaf` branch — so `shape_matches` can verify that the downstream `EAlloc` has the same shape. However, the lowering pass emits `EAlloc` do a **qualified** constructor key:

```ocaml
(* lower.ml — ECon case *)
let ctor_key = match ty_of_span span do
  | Tir.TCon (type_name, _) -> type_name ^ "." ^ tag   (* e.g. "Tree.Leaf" *)
  | _ -> tag
in
Tir.EAlloc (Tir.TCon (ctor_key, []), arg_atoms)
```

The qualification (`"Tree.Leaf"` rather than `"Leaf"`) is necessary to prevent collisions in the LLVM emitter's constructor-info table when two different ADTs define constructors with the same name (e.g. `List.Cons` vs `Tree.Cons`). The LLVM emitter already has a `qualified_br_key` helper that applies this same transformation when looking up constructors during ECase emission.

The Perceus pass was tagging the scrutinee's `DecRC` with the bare branch tag `"Leaf"`. `shape_matches` uses exact string equality:

```ocaml
| Tir.TCon (n1, _), Tir.TCon (n2, _) -> String.equal n1 n2
```

So `"Leaf" ≠ "Tree.Leaf"` — `shape_matches` always returned false, and `EReuse` was never generated. FBIP was silently disabled for every ADT in the language.

The fix is a single change in `add_scrutinee_free_for`:

```ocaml
(* Before *)
let ctor_v = { v with Tir.v_ty = Tir.TCon (ctor_tag, []) } in

(* After — mirror qualified_br_key from llvm_emit.ml *)
let qualified_tag = match v.Tir.v_ty do
  | Tir.TCon (type_name, _) -> type_name ^ "." ^ ctor_tag
  | _ -> ctor_tag
in
let ctor_v = { v with Tir.v_ty = Tir.TCon (qualified_tag, []) } in
```

#### Benchmark: `bench/tree_transform.march`

The benchmark builds a depth-20 binary tree (2^20 = 1,048,576 leaves) and runs 100 passes of `inc_leaves`. With FBIP active, passes 2–100 do zero allocations: every `Leaf` and `Node` is overwritten in-place.

| Implementation | Time | Notes |
|---|---|---|
| March (before fix) | 11.0 s | FBIP silently disabled; 200M alloc+free ops |
| C (`malloc`/`free`) | 8.8 s | 200M allocator calls, explicit |
| Rust (`Box`) | 9.5 s | 200M heap allocations |
| OCaml (GC) | ~3.65 s | Generational GC amortizes allocation cost |
| **March (after fix)** | **1.3 s** | Zero allocations after pass 1; 7× faster than C |

The 7× speedup over C is not paradoxical. C's `malloc` and `free` have real runtime cost — bookkeeping, potential lock acquisition, cache misses on the allocator metadata. For a 1M-node tree over 100 passes, that is 100 × 2 × 1M = 200 million allocator calls. March's FBIP eliminates all 199 × 2 × 1M of them (all passes after the first), replacing them with direct field stores.

#### Generalization

FBIP fires automatically — no source annotations required — whenever:

1. A function pattern-matches a heap value it uniquely owns (RC == 1 at runtime).
2. The matching arm immediately produces a new value of the same constructor.
3. The original scrutinee is not retained anywhere in the arm's computation.

This covers the standard recursive structural patterns over trees and lists:

- `map` over a linked list: each `Cons(h, t)` → `Cons(f(h), map(f, t))` reuses the `Cons` cell in-place
- Any tree transformation where the old tree is not needed alongside the new one
- Recursive descent transformations like `inc_leaves`, `scale`, `normalize`

Functions where the old value IS retained (e.g. a function that both traverses and separately stores the original) correctly fall through to the RC > 1 path, which allocates fresh and decrements the original — correct, just not in-place.

The optimization interacts correctly with the rest of the Perceus analysis: `IncRC`/`DecRC` cancel-pair elision runs before FBIP, so the cancel pairs introduced by passing uniquely-owned values into recursive calls are already removed by the time FBIP looks for the `DecRC + EAlloc` pattern.

### Compilation Target

**LLVM**. Mature, excellent optimization, broad platform support, and the obvious choice for a language targeting native code with unboxed representations and no GC write barriers on the hot path.

### Tail-Call Optimization (TCO) — Loop Transformation

March guarantees O(1) stack space for tail-recursive functions via a loop transformation in LLVM IR emission (`lib/tir/llvm_emit.ml`).

#### How it works

For a self-tail-recursive function, the emitter:

1. **Detects** self-tail-recursion in the TIR body using `has_self_tail_call` — a simple structural traversal that follows tail-position expressions (ELet body, ESeq second operand, ECase branch bodies).

2. **Transforms** the LLVM IR from a recursive call into a loop:
   - Emits `entry: → br label %tco_loop` after parameter allocas
   - Emits a `tco_loop:` header block
   - At each tail-self-call site, stores the new argument values into the parameter alloca slots and emits `br label %tco_loop` instead of a `call` instruction
   - Opens a dead block for any instructions that the calling context emits after the branch (e.g., `emit_case`'s store-to-result-slot) — these are unreachable but keep the IR structurally valid

3. **Relies on LLVM's mem2reg + DCE** to promote the alloca slots to registers and eliminate the dead blocks, producing tight loop IR equivalent to a hand-written while loop.

The transformation uses the existing alloca-based parameter representation — no phi nodes are required in the emitted IR; LLVM's mem2reg promotes them automatically.

#### Example

```march
@[no_warn_recursion]
fn factorial(n : Int, acc : Int) : Int do
  if n == 0 then acc
  else factorial(n - 1, n * acc)
end
```

Emits (schematically):
```llvm
define i64 @factorial(i64 %n.arg, i64 %acc.arg) {
entry:
  %n.addr   = alloca i64
  store i64 %n.arg,   ptr %n.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  br label %tco_loop1
tco_loop1:
  ; ... evaluate condition, emit branch/case ...
  ; false branch — tail self-call → back-edge:
  store i64 %new_n,   ptr %n.addr
  store i64 %new_acc, ptr %acc.addr
  br label %tco_loop1
  ; true branch → ret i64 %acc_val
}
```

#### Scope

- **Supported**: Direct self-recursion (function calls itself in tail position)
- **Not yet supported**: Mutual recursion (requires Continuation Passing Style or a shared trampoline — deferred post-v1)
- **Interaction with Perceus**: RC operations inserted before the tail call (e.g., `ESeq(EDecRC(xs), EApp(go, ...))`) are emitted before the back-edge store, so reference counting is correct

## Compiler Architecture

### Query-Based / Demand-Driven

The compiler is **not** a traditional pipeline. It's a query system:

- Compilation is a graph of queries: "give me the type of function X" triggers parsing and type checking of X and its dependencies
- Results are memoized by content hash
- Incremental recompilation falls out naturally: only recompute queries whose inputs changed
- Inspired by Rust's `rustc` query system and Salsa

### Error Strategy

- **Provenance**: Every type constraint carries a reason chain, not just a source span
- **Expected vs. found**: Errors frame mismatches do full provenance: "expected X because of Y, but found Z because of W"
- **Hole injection**: Errors become typed holes; the compiler continues past them
- **No cascades**: Holes have a special error type that suppresses further errors downstream
- **Multiple diagnostics**: The type checker recovers from errors (holes absorb mismatches; checking continues). The parser currently stops at the first syntax error — multi-error parser recovery is planned.

## Tooling & LLM Integration

### Code Formatter (`march fmt`)

A canonical formatter ships with the compiler. One true format — no style debates, deterministic output, smaller diffs for LLM-generated code:

```sh
march fmt file.march           # reformat in-place
march fmt --check file.march   # CI mode: exit 1 if not formatted
march --fmt file.march         # format then compile
```

**Implementation:** `lib/format/format.ml` — pretty-printer over the parsed AST.

### Language Server Protocol (LSP)

`march-lsp` provides full IDE support via the LSP protocol (VS Code, Neovim, Helix, Zed, etc.):

- Diagnostics (type errors and parse errors in real-time)
- Hover (show inferred type at cursor)
- Go-to-definition via content-addressed lookup
- Type-directed completion (keywords, in-scope names, stdlib)
- Inlay hints (inferred types on `let` bindings)
- Semantic tokens (richer syntax highlighting)
- Actor info (mailbox state on `Pid` hover)

**Implementation:** `lsp/march_lsp.ml` using the `linol` OCaml LSP framework.

### LLM-Specific Features

- **Typed holes as prompts**: `?` in code becomes a structured query — the compiler provides the expected type, available bindings, and capability context. An LLM can fill the hole with a type-correct expression.
- **MCP server**: Direct integration point for LLMs to query the compiler (type at position, available completions, capability context). Planned post-LSP.
- **Content-addressed search**: Find existing code by type signature — "is there already a function `List a -> Int`?" — enabling LLMs to reuse rather than rewrite
- **Capability boundaries**: Capability types give LLMs clear contracts about what resources a function can access

### Tree-sitter Grammar

A Tree-sitter grammar for incremental parsing in editors (`tree-sitter-march/`), enabling:
- Syntax highlighting (used by the Zed extension today)
- Structural editing
- Fast re-parsing on edit

## Implementation Language

**OCaml 5.x** — chosen for:
- Native pattern matching (natural for compiler passes)
- Strong type system catches compiler bugs at compile time
- Multicore support via Domains (parallel compilation)
- Pragmatic: mutation where needed, good performance, mature ecosystem
- `menhir` for parser generation, `ppx_deriving` for boilerplate reduction

## Resolved Design Decisions (reference)

- **FFI**: Per-library capability caps (`Cap(LibC)` etc.). Foreign pointers as `linear Ptr(a)`. `unsafe` blocks for unverifiable operations. Explicit `CRepr` interface for marshaling — no implicit conversion.
- **MPST scope**: Binary session types for v1. Multi-party (global choreography + projection) deferred post-v1.
- **Standard library**: "Some batteries" — collections, strings, IO, Result/Option, basic math, actors/messaging primitives. Third-party ecosystem handles the rest.
- **GC strategy**: Stratified model — see `specs/gc_design.md`.
- **Compilation target**: LLVM.
- **Orphan instances**: Forbidden. `impl` must be in the module defining the type or the interface.
- **Pony-style capabilities**: No. Linear/affine is the ceiling.
- **Module system**: Namespaces + interfaces with associated types. No ML functors.
- **Sig hashing**: Sigs have their own hash, separate from impl hashes.
- **Match syntax**: `match expr do | Pat -> body end` (Elixir-style `do` keyword, not ML-style `with`).
- **Pipe operator**: `a |> f(b)` desugars to saturated call `f(a, b)` — piped value is the **first** argument (Elixir convention, not Haskell `&`).
- **Standard interfaces**: `Eq`, `Ord`, `Show`, `Hash` with `derive` auto-derivation. Superclass constraints enforced at `impl` site.
- **String interpolation**: `${}` desugars to `++` / `to_string` chains at desugar time, not via an `Interpolatable` typeclass.
- **No algebraic effects**: Concurrency is actors + message passing. Side effects tracked via capability types, not an effect system.
- **Atoms**: `:name` are runtime tags, not ADT constructors. ADTs use capitalized names (`Ok`, `Err`, `Some`, `None`).
- **Exhaustiveness checking**: Not yet implemented. Non-exhaustive patterns produce runtime `Match_failure`. Planned for v1 completion.
- **Multi-level `use` paths**: `use A.*` works; `use A.B.*` deferred (grammar ambiguity). Single-level for now.
