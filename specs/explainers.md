# PLT Concepts — Explained for Elixir Programmers

Short companions to the reading list. No math, no Greek letters.

---

## 1. Hindley-Milner Type Inference

In Elixir, types don't exist at compile time — Dialyzer guesses at them after the fact. In a statically typed language, you'd expect to write type annotations on everything. HM is the algorithm that makes that unnecessary.

The insight is that types can be *inferred* from how values are used. If you write `x + 1`, the compiler knows `x` must be a number without you saying so. If you pass `x` to a function that returns a `String`, the compiler knows the whole expression is a `String`. HM formalizes this as a constraint-solving problem: generate equations from how each value is used, then solve for the types.

The surprising result (Milner's theorem) is that this always produces the *most general* type — `map(list, f)` is inferred as "works for any list element type and any compatible function," without you writing a type signature at all. March uses this as its core and only adds annotations at the boundaries where inference needs a hint.

---

## 2. Bidirectional Type Checking

Pure HM inference works bottom-up: figure out the type of each sub-expression, combine upward. Bidirectional checking adds a downward pass too.

The Elixir analogy: imagine `@spec` annotations actually influenced how the compiler checked your function body, not just what Dialyzer complains about afterward. If you annotate `:: String`, the type checker *uses* that expectation when checking what's inside — so it can catch mismatches earlier and give better error messages ("expected String here because of your annotation on line 3" instead of "inferred Int, doesn't match").

In March, annotations on function signatures switch the checker into "checking mode": the expected type flows inward. Without an annotation, it's in "inference mode": types flow outward. The two modes hand off to each other at every boundary. This is also what makes typed holes (`?`) work — the expected type flows *in* to the hole, so the compiler can tell you what type you need to fill it with.

---

## 3. Linear and Affine Types

In Elixir, data is always copyable and always shareable. When you `send(pid, data)`, the data gets copied to the other process's heap — you still have your copy. This is fine for immutable data but means resources like file handles can't be safely modeled as values.

Linear types add a rule to the type system: some values must be used *exactly once*. After you use a linear value, it's gone — the compiler won't let you use it again. This is the compile-time version of Elixir's `File.close/1` convention, except the compiler enforces it.

```
-- This is a compile error in March:
let f = open_file("log.txt")   -- f is linear
write(f, "hello")              -- f is consumed here
write(f, "world")              -- ERROR: f already used
```

Affine types are the relaxed version: used *at most once* (you can drop it without using it, but can't use it twice). March uses both. The key payoff: linear values can be safely mutated in place (if you're the only owner, there's no aliasing), passed between actors without copying (ownership transfers), and guaranteed-freed at their last use — no GC needed for that value.

---

## 4. Algebraic Data Types and Pattern Matching

You already use these in Elixir — you just don't call them that. `{:ok, value} | {:error, reason}` is an algebraic data type. A two-element tuple `{name, age}` is a product type (has both). The `|` union is a sum type (has one or the other).

What Elixir lacks is the formal declaration. When you write `case result do {:ok, v} -> ...` in Elixir, the compiler doesn't know that `{:ok, _}` and `{:error, _}` are the only possibilities — it can't warn you if you forget a branch. March's `type Result(a, e) = Ok(a) | Err(e)` is a closed declaration: the compiler knows every constructor, checks exhaustiveness, and can optimize the representation.

The word "algebraic" just means "closed under combination": you can build arbitrarily complex types by combining sums and products, the same way you build complex Elixir data from tuples, maps, and atoms.

---

## 5. Typeclasses / Interfaces

This is Elixir's `Protocol`, made stricter and more powerful.

Elixir protocols let you define a behaviour (`Enumerable`, `String.Chars`) and implement it for any type, including types from other libraries. March's `interface` is the same idea — a named set of functions that a type must implement — but with two important differences.

First, orphan instances are forbidden. In Elixir you can implement `MyProtocol` for `DateTime` even though you wrote neither. In March, you can only write an `impl` in the module that defines the type *or* the module that defines the interface. This prevents two libraries from implementing the same interface for the same type in conflicting ways.

Second, interfaces can have *associated types* — type-level slots that each implementation fills in differently. Elixir protocols can't do this cleanly. In March you can say "this `Collection` interface has an `Elem` type, and each implementation gets to declare what that is."

---

## 6. Module Systems and Signatures

Elixir modules are namespaces with functions. ML-style module systems add a second concept: the *signature*, which is the public interface of a module, separate from its implementation.

Think of it like `@behaviour` on steroids. A signature in March (`sig`) declares exactly which types and functions are public and what their types are, independently of how they're implemented. The compiler checks that the module satisfies its signature.

The big payoff for March is caching. The build system hashes *signatures* separately from *implementations*. If you refactor the internals of a module but its signature doesn't change, everything that depends on it sees the same signature hash — no recompilation. In Elixir/Mix, changing any file in a dependency chain triggers recompilation of everything downstream.

---

## 7. Session Types

In Elixir, you communicate with a GenServer like this:

```elixir
GenServer.call(server, :increment)
GenServer.call(server, :get_count)
```

The compiler has no idea if `:increment` is a valid message for this server, what order messages must be sent in, or what comes back. You find out at runtime, or from documentation.

Session types describe the *protocol* between two communicating parties as a type. For the file transfer example in March:

```
Client -> Server : Open(filename)
Server -> Client : Ready | Err(reason)
loop:
  Client -> Server : Chunk(bytes) | Done
```

Both ends get a typed channel. If the client tries to send `Chunk` before receiving `Ready`, it's a compile error. If the server tries to receive a second message but the client sent `Done`, it's a compile error. The type system enforces the protocol at both ends.

This is like having a formal contract between two GenServers that the compiler verifies, instead of relying on documentation and hope.

---

## 8. Actor Model and Capability Security

The actor model is exactly what you know from Elixir: isolated processes, message passing, no shared memory. March is doing the same thing.

The new concept is capability security. In Elixir, if you have a PID, you can send any message to it. There's no access control — knowing the PID *is* the permission. This is called "ambient authority."

Capability security replaces this with unforgeable tokens. In March, `Cap(Actor)` is a value you must receive explicitly — you can't manufacture it from a PID or guess it. If you don't hold a cap, you cannot send to that actor. Period.

This sounds like a minor change but it has big consequences: you can fully control what a piece of code can reach. If you spawn an untrusted computation and don't give it a cap to your database actor, it provably cannot touch your database — not because of runtime checks, but because there's no way to even construct the right type.

---

## 9. Supervision Trees and Fault Tolerance

You already know supervision trees from OTP. The design in March is intentionally the same: `one_for_one`, `one_for_all`, `rest_for_one` work identically to Erlang's strategies.

The additions are about what happens at the type level when an actor crashes. In Elixir, if a GenServer crashes and you hold its PID, you won't find out until you try to `call` it and get `{:exit, :noproc}`. March's epoch system makes this typed: capabilities carry an epoch number, and using a stale cap after the actor restarted is surfaced as a `Dead` result rather than a runtime crash.

The other addition: when an actor crashes, any linear values it held (open channels, file handles) need cleanup. March's drop handlers are the typed equivalent of Elixir's `terminate/2` callback — except the compiler enforces that linear values must have a cleanup path.

---

## 10. Perceus Reference Counting and FBIP

The BEAM uses per-process garbage collection. Each process has its own heap and a tracing GC runs when it fills up. This works well but has overhead: the GC has to scan memory, and write barriers track pointer updates.

Perceus is a different strategy. Instead of a runtime GC, the *compiler* analyzes where each value's last use is and inserts `free` calls there — like Rust's ownership but without you writing any ownership annotations. Most of the reference-count increments and decrements cancel out statically and are simply removed.

FBIP (Functional But In-Place) is the clever part. In Elixir, transforming a list always allocates a new list — the old one is garbage collected eventually. With FBIP, if the old list's reference count is about to hit zero (you're about to free it) at the same moment you're allocating a new list of the same shape, the runtime reuses the memory in place. From the language's perspective the operation is pure and immutable. From the hardware's perspective it's an in-place update with no allocator round-trip. You get the correctness of immutability with the performance of mutation.

---

## 11. Defunctionalization

In Elixir, anonymous functions are closures — they capture their environment and live on the heap as objects. When you do `Enum.map(list, fn x -> x + 1 end)`, that `fn` is a heap-allocated object passed around as a value.

Defunctionalization is a whole-program transformation that eliminates closure objects entirely. The compiler looks at every anonymous function in the entire program and turns them all into variants of a tagged union:

```
-- Conceptually, the compiler generates:
type AnonFn =
  | AddOne
  | MultiplyBy(Int)    -- captured the Int from the environment
  | FilterNonEmpty

fn apply(f, x):
  match f with
  | AddOne          -> x + 1
  | MultiplyBy(n)   -> x * n
  | FilterNonEmpty  -> x != ""
```

Every call to a function-as-value becomes a call to `apply`. No heap allocation for the closure, no indirect call through a function pointer — just a known switch statement. Combined with monomorphization, the compiler often inlines the right branch entirely.

---

## 12. Whole-Program Monomorphization

In Elixir, `Enum.map/2` works for any list at runtime because everything is dynamically typed. In a typed language, the equivalent generic function needs to work for `List(Integer)`, `List(String)`, etc.

One approach (Haskell, Java) is *dictionary passing*: pass a runtime object that knows how to handle each type. Generic functions carry an invisible extra argument describing the type, and operations on the type go through that dictionary. There's overhead.

Monomorphization is the other approach: generate a separate, specialized copy of the function for every concrete type it's called with. `map` for integers generates one function, `map` for strings generates another. No runtime dispatch, no dictionaries — just normal function calls. It's what C++ templates do, and what Rust and March do.

The tradeoff is binary size (more specialized copies) and compile time (more work to do). March's content-addressed cache mitigates this: a monomorphized specialization of `(function hash, type args)` is computed once and cached forever.

---

## 13. Type-Level Naturals (Sized Types)

In Elixir, if you're doing matrix multiplication, nothing stops you from passing a 3×4 matrix where a 4×3 is expected. You find out at runtime.

Sized types put numbers *into* the type. Instead of `Matrix`, you write `Matrix(3, 4, Float)` — the dimensions are part of the type. Now `matmul` has this signature:

```
fn matmul(a : Matrix(m, n, Float), b : Matrix(n, p, Float)) : Matrix(m, p, Float)
```

The compiler unifies `n` from both arguments. If you pass a `Matrix(3, 4, Float)` and a `Matrix(3, 4, Float)`, the inner dimensions don't match (`4 ≠ 3`) and it's a compile error — no runtime check needed.

This is a carefully limited form of dependent types (types that depend on values). March only allows natural numbers in type positions, with `+` and `*` as the only operations — enough for dimension checking and length-indexed vectors, but not so general that type checking becomes undecidable.

---

## 14. Query-Based / Demand-Driven Compiler Architecture

Mix recompiles files. If you change `lib/foo.ex`, Mix recompiles `foo.ex` and every module that `use`s or `import`s it. This is file-level granularity.

A query-based compiler operates at the level of *questions*: "What is the type of `Foo.bar/2`?" The compiler answers these on demand and caches the answers. The key: if the answer to a question hasn't changed (the type of `Foo.bar` is still the same), nothing that depends on that answer needs to be recomputed — even if the implementation of `Foo.bar` changed internally.

Think of it like a spreadsheet. Cells contain formulas that reference other cells. When you change a cell, only the cells that (transitively) depend on it recalculate. The query-based compiler does the same thing for compilation: change a private function's implementation, and only the module hash changes — not the signature hash, so nothing downstream recompiles.

---

## 15. Content-Addressed Code

In Elixir/Mix, dependencies are identified by name and version: `{:phoenix, "~> 1.7"}`. Two packages depending on different versions of Phoenix cause a conflict.

Content-addressing identifies code by a hash of its content. There is no "version" — the hash *is* the identity. Two different implementations of the same function are simply two different hashes; both can coexist in the store without conflict. Diamond dependency problems don't exist because each dependency is pinned to an exact hash, and two different hashes of the same function name can coexist.

The closest thing you've seen is probably Docker layers or git objects — a git commit SHA is a content hash, and git never has "version conflicts" between commits. Unison is a programming language built entirely on this idea, and March borrows it for both code storage and the build cache.

---

## 16. Error Recovery and Typed Holes

In Elixir, if you have a syntax error, the compiler tells you about it and stops. You fix it, recompile, find the next error, fix it, etc.

March's error recovery works differently: when the compiler hits a broken expression, it replaces it with a *typed hole* — a placeholder that participates in type checking. The rest of the file type-checks around the hole. You get all the errors from the whole file in one pass.

The same mechanism is used intentionally with `?`:

```march
fn handle(input : String) : Result(Int, String) do
  let parsed = ?parse_step
  ?validate_step
end
```

The compiler sees `?parse_step` needs to be something that fits the expected type, and reports: "this hole needs type `Result(Int, String)`, you have these bindings available: `input : String`." It's like asking the type checker "what do I need to write here?" — useful when you're not sure what type a sub-expression should have, and essential for LLM-based completion.

---

## 17. Provenance Tracking in Type Errors

Elixir's Dialyzer gives you errors like "the type atom() is not a valid return for the specified type." Not very helpful.

Good type error messages need to explain *why* the type checker expected something, not just *what* it expected. Provenance tracking threads a reason chain through every type constraint.

Instead of: `Expected Int, got String`

You get: `Expected Int here (line 8) because it's the argument to + (which requires Int), because calculate/1 was annotated as returning Int on line 3, but this expression is String because name was bound as a String parameter on line 1.`

The implementation: every type in the constraint solver carries a small record saying which syntactic construct or inference rule introduced it. When two types fail to unify, you walk both provenance chains and construct an explanation. March tracks this throughout the entire type checking pass.

---

## 18. FFI Design and Capability-Based Safety

In Elixir, a NIF (Native Implemented Function) is a C function linked directly into the BEAM. A bug in a NIF — double-free, use-after-free, buffer overflow — crashes the entire VM, not just the process. NIFs bypass all of the BEAM's isolation guarantees.

March's FFI design uses two layers of protection:

**Capabilities**: you can't call a foreign function without holding `Cap(LibC)` (or whatever library). This token is created at program entry and passed down explicitly. A piece of code without the cap literally cannot call into C — there's no ambient access.

**Linear pointers**: foreign memory enters the type system as `linear Ptr(a)`. Linear enforces: used exactly once (no use-after-free), must be freed (no leak), cannot be copied across actors (no data races). The compiler inserts the `free` call at the last use point.

`unsafe` blocks exist for the operations that can't be statically verified (pointer casts, raw arithmetic) but are isolated and searchable in code review.

---

## 19. Representation Polymorphism / Unboxed Types

In the BEAM, every value is "boxed" — wrapped in a tagged word that says what type it is. An integer is stored as a tagged pointer or an immediate with type bits. This makes the runtime generic and GC-friendly, but it means numeric-heavy code is doing extra work.

In March, after monomorphization every type is concrete. The compiler knows it's dealing with a `Float`, not "some value that might be a Float." So it can store the `Float` directly in a CPU register or on the stack with no wrapping — the same as C's `double`.

This is invisible to the programmer; you write the same code either way. It matters for performance-sensitive code: matrix operations, tight loops, numeric algorithms. March's design is specifically that this optimization happens *after* linearity checking (which operates on abstract types), so the two systems don't interfere with each other.
