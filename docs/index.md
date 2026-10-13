---
layout: landing
title: March Lang
nav_order: 1
permalink: /
---

<div style="text-align: center; margin: 2rem 0 1.5rem;">
  <img src="{{ site.baseurl }}/assets/logo.webp" alt="March logo" width="120" height="120" style="display: inline-block;">
</div>

# March

**ML's types. Capabilities for every effect. BEAM-style actors, compiled to native code.**

March is a statically typed functional language for programs built from actors. It takes message passing and supervision from the BEAM and algebraic data types from ML, and compiles the result to a native binary through LLVM. Memory is managed by Perceus reference counting with in-place reuse, so there is no garbage collector and no pauses, and functional code runs at Rust-like speed.

Safety is the compiler's job, not the test suite's. Side effects are part of the type: a module declares the capabilities it needs, so what any piece of code can touch is visible in its signature, bounded by what `main` was granted, and auditable across every dependency you pull in. Linear types make a resource that is used out of order, twice, or never a compile error. Refinement types reject a value a function cannot accept before it runs. A message protocol is checked on both sides, a crashed actor is restarted the way you declared, and a running node takes new code without a restart.

---

## What makes March different

### The whole program is bounded by `main`'s signature

`main`'s capability parameter is the program's grant, and everything the program can
reach has to fit under it: every helper, every stdlib call, every dependency. Declare
`Cap(IO.Console)` and the build fails the moment anything in that closure opens a file
or a socket, naming the chain that got there.

```march
mod Report do
  needs IO.Console

  fn main(cap : Cap(IO.Console)) : () do
    println("report done")      -- fine
    save_to_disk()              -- a helper that calls file_write
  end
end
```

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.FileWrite`
(reached from `main`: main → save_to_disk). The grant is a ceiling on the WHOLE
program — declaring `needs IO.FileWrite` does not raise it.
help: add a `Cap(IO.FileWrite)` parameter to `main`, or widen the grant to `Cap(IO)`,
or remove the use.
```

Every module also declares what it touches with `needs`, and the compiler checks that
the declaration is honest against the code it actually emits, so a dependency that
reads `/etc/passwd` behind a `needs IO.Console` fails your build without the
publisher's cooperation. See [Capabilities]({{ site.baseurl }}/docs/capabilities/).

### Three safety layers on one function

Capabilities say *what resources* code may touch. Linear types and typestate say *how
many times, and in what order*, a resource is used. Refinement types say *with what
values* a function may be called. They are independent, they compose on the same
function, and all three fire at compile time.

```march
mod ChunkReader do
  needs IO.FileRead                          -- (1) may read files

  always_linear type File(s) = File(Int)     -- (2) a handle used exactly once,
  tag Open                                   --     tracked Open vs Closed
  tag Closed

  fn open(cap : Cap(IO.FileRead), path : String) : File(Open) do ... end

  fn read_chunk(
    f      : File(Open),
    offset : {Int | _ >= 0},                 -- (3) checked by an SMT solver
    size   : {Int | _ > 0 && _ <= 4096}
  ) : (String, File(Open)) do ... end

  fn close(f : File(Open)) : File(Closed) do ... end
end
```

A module without `needs IO.FileRead` cannot call `open`. Reading from a handle after
`close`, or closing it twice, is a type error. `read_chunk(f, -1, 8192)` is rejected
with the failing predicate quoted back. See
[Safety by Construction]({{ site.baseurl }}/docs/safety-by-construction/).

### Typed protocols, for two parties or twenty

Write a conversation once, from the point of view of the whole system. For two parties
the compiler checks that each side's view is the dual of the other's. Mark the protocol
`@[endpoints]` and it generates a typed module per role, so a role that sends out of
turn, receives twice, or stops halfway does not compile, and a runner that connects the
roles over the network, each role its own program on its own machine.

```march
@[endpoints]
protocol Fan do
  number:  A -> C : Int
  second:  B -> C : Int
  verdict: C -> A : Bool
end

-- Role B, as the compiler types it: send, then close. Nothing else typechecks.
pfn role_b(s : Cap(Session.Live), st : Fan_B.Entry) : Fan_B.Yield do
  Fan_B.close(s, Fan_B.send_Second(s, st, 9))
end
```

A role that fails cancels only the roles that were waiting on it, and a protocol can
say which roles may crash and what the conversation does then. See
[Session Types]({{ site.baseurl }}/docs/session-types/) and
[Choreography]({{ site.baseurl }}/docs/choreography/).

### Deploy to a running node, and only what it is allowed to do

`forge deploy hot` ships just the functions that changed into a live process. Actors
keep running; one with a changed state shape finishes the messages it already has on
the old code, then runs your `migrate_state` and carries on. Each patched function
brings its own capabilities, and a patch that reaches for more than the running version
had stops at the deploy tool until you authorise it by name:

```
$ forge deploy hot --so v2.so
Deploying 1 changed function(s)...
error: hot deploy would add authority not held by the running version
  running version caps:  IO.Console
  new version adds:      IO.FileWrite (from Server.handle)
  A hot deploy may only narrow authority. To authorize this widening, re-run with:
      forge deploy hot --grant-cap IO.FileWrite
error: capability widening — deploy aborted
```

Grant it, and the node still has the last word: a node whose policy forbids
`IO.FileWrite` rejects the activation and rolls the batch back, whoever signed it. See
[Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/).

### Actors with supervision trees

March's concurrency model is the actor model: share-nothing, message-passing processes, as on the BEAM. Actors are first-class: spawn them, monitor them, and organize them into supervision trees that automatically restart failed processes.

```march
actor Counter do
  state { count : Int }
  init  { count: 0 }

  on Increment(n : Int) do
    { state with count: state.count + n }
  end
end

actor Logger do
  state { entries : Int }
  init  { entries: 0 }

  on Log(msg : String) do
    { state with entries: state.entries + 1 }
  end
end

actor WorkerSup do
  state { counter : Int, logger : Int }
  init  { counter: 0, logger: 0 }

  supervise do
    strategy one_for_one
    max_restarts 5 within 60
    Counter counter
    Logger  logger
  end
end
```

The type system enforces actor isolation: you cannot accidentally share mutable state between processes. A spawned actor's handlers count against `main`'s grant like any other code, so a program granted only the console cannot smuggle a file write into a handler. See [Actors]({{ site.baseurl }}/docs/actors/) and [Supervision]({{ site.baseurl }}/docs/supervision/).

### Perceus reference counting + FBIP

March uses **Perceus reference counting**: deterministic memory management with no stop-the-world GC pauses. But the real story is **FBIP (Functional But In-Place)**: when a value has exactly one owner, March rewrites it in-place instead of freeing and reallocating. Recursive tree transformations, list maps, and structural recursion patterns run with **zero heap allocations** after the initial build.

```march
-- This runs with zero allocations on each recursive call (FBIP fires automatically)
fn inc_leaves(t : Tree) : Tree do
  match t do
    Leaf(n)    -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
```

On a depth-20 binary tree (1M leaves), 100 passes of a transformation like this:

| | Time |
|---|---|
| C (`malloc`/`free`) | 8.8 s |
| Rust (`Box`) | 9.5 s |
| **March (FBIP)** | **1.3 s** |

March wins not because C is slow, but because FBIP eliminates 200M allocator calls entirely. The benchmark is [`bench/tree_transform.march`](https://github.com/march-language/march/blob/main/bench/tree_transform.march); current numbers are in [`bench/RESULTS.md`](https://github.com/march-language/march/blob/main/bench/RESULTS.md). See the [Memory Model]({{ site.baseurl }}/docs/memory-model/).

---

## A taste of March

```march
mod Chat do
  needs IO.Console

actor Room do
  state { members : List(String) }
  init  { members: [] }

  on Enter(name) do
    { state with members: Cons(name, state.members) }
  end

  on Say(from, text) do
    let line = from ++ ": " ++ text
    state.members |> List.each(fn m -> println(m ++ " sees: " ++ line))
    state
  end

  on Leave(name) do
    { state with members: List.filter(state.members, fn m -> m != name) }
  end
end

fn main() do
  let room = spawn(Room)
  send(room, Enter("alice"))
  send(room, Enter("bob"))
  send(room, Say("alice", "hello!"))
  send(room, Leave("bob"))
end

end
```

---

## Feature overview

### Concurrency
- **Actor model**: share-nothing message passing, isolated by the type system
- **Supervision trees**: `one_for_one`, `one_for_all`, `rest_for_one` restart strategies, restart budgets and backoff
- **Session types**: typed two-party protocols; a send out of turn is a compile error
- **Choreographies**: one protocol, many roles, each role compiled to its own program on its own node
- **Structured concurrency** via `Task.async`, `await_many`, `race` and `scope`
- **Hot code reload**: deploy to a running node; actors migrate their state in place

### Runtime and performance
- **Perceus reference counting**: deterministic, no tracing collector; freeing is inline work at a point you choose ([memory model]({{ site.baseurl }}/docs/memory-model/))
- **FBIP**: in-place reuse of memory when the compiler can prove unique ownership
- **LLVM backend**: whole-program monomorphization, defunctionalization, native binaries
- **SIMD & native arrays**: auto-vectorized `NativeArray` numeric loops plus explicit 128-bit `Simd` vector types, competitive with NumPy on the operations that vectorize ([guide]({{ site.baseurl }}/docs/simd/))
- **Work-stealing scheduler**: cooperative + preemptive, scales across cores
- **WebAssembly target**: compile to `.wasm` via `--target wasm64-wasi`
- **Linux cross-compilation**: build `linux/amd64` + `linux/arm64` binaries from any host via `zig cc`, Go's `GOOS=linux` style ([guide](tooling.md#cross-compiling-to-linux))

### Language
- **Algebraic data types**: `type Shape = Circle(Float) | Rect(Float, Float)`
- **Pattern matching** with exhaustiveness checking and guards
- **Pipe operator**: `list |> map(f) |> filter(g) |> sum`
- **Multi-head functions**: clause dispatch on patterns in the parameter list
- **`with` expressions**: monadic chaining for `Result`/`Option`
- **`let?` propagation**: `let? x = e` binds `Ok(x)` and returns `Err` immediately
- **Linear and affine types**: ownership tracking for resource safety
- **String interpolation**: `"Hello, ${name}!"`
- **List comprehensions**: `[x * 2 for x in nums, x > 0]`

### Type system
- **Type inference**: types flow through without annotation boilerplate
- **Generics**: `List(a)`, `Map(k, v)`, `Result(a, e)`
- **Interfaces**: `interface`, `impl`, `derive`
- **Type-level naturals**: `Vector(n, a)` with compile-time dimension checking

### Tooling
- **REPL**: two-pane TUI, tab completion, syntax highlighting, `:type` / `:doc` queries, the full standard library
- **LSP server**: diagnostics, hover, go-to-definition, completions
- **`forge` build tool**: new, build, test, Hoogle-style search, deploy, observe, and more ([reference]({{ site.baseurl }}/docs/tooling/))
- **Tree-sitter grammar** for Zed editor syntax highlighting
- **Time-travel debugger**: step backward through execution history

---

## Documentation

### Start here

| Guide | What it covers |
|-------|---------------|
| [Installation](installation.md) | Prebuilt binaries (recommended); building from source |
| [Getting Started](getting-started.md) | Hello world, compiling, running the REPL |
| [Language Tour](tour.md) | Variables, functions, types, pipes: the essentials |
| [Try It Out](playground.md) | A March interpreter in the browser; no install |
| [Build a CLI Tool](build-a-cli.md) | Start-to-finish: scaffold, args, files, test, build |
| [Cookbook](cookbook/) | Goal-oriented recipes: CLI, HTTP, JSON, files, config |
| [Examples](examples.md) | Runnable programs in `examples/`, one feature each |
| Coming from [Python](coming-from-python.md) · [TypeScript](coming-from-typescript.md) · [Haskell/Elixir/OCaml](coming-from-fp.md) | Mental-model maps for newcomers |

### The language

| Guide | What it covers |
|-------|---------------|
| [Type System](types.md) | ADTs, records, generics, Option, Result |
| [Pattern Matching](pattern-matching.md) | Match, guards, exhaustiveness, `with`, multi-head functions |
| [Module System](modules.md) | `mod`, `use`, `import`, `alias`, visibility |
| [Interfaces](interfaces.md) | `interface`, `impl`, `derive` |
| [Sigils & Templating](sigils.md) | `~H`, `~T` and friends: typed literals for HTML, TOML and more |
| [Parsing](parsing.md) | The `Parse` combinator library |
| [Standard Library](stdlib.md) | List, Map, String, Option, Result, and more |
| [Coding Standards](coding-standards.md) | Style, safety and idiom rules, and `forge lint` |

### Safety at compile time

| Guide | What it covers |
|-------|---------------|
| [Safety by Construction](safety-by-construction.md) | Which layer catches which bug: capabilities, linearity, refinements |
| [Capabilities](capabilities.md) | IO permission caps, the upper limit, the grant, proof caps, typestate |
| [Linear Types](linear-types.md) | Ownership, linear and affine qualifiers, `LinearMap`, `RingBuf` |
| [Refinement Types](refinement-types.md) | `{T \| pred}` predicates checked by Z3, `cap verified`, `cap no_panic` |
| [Capability Enforcement](capability-enforcement.md) | Turning declared capabilities into an OS sandbox and a deploy gate |
| [Capability Audit](capability-audit.md) | `forge audit` on dependency updates; `forge cap inspect` on a binary |
| [Memory Model](memory-model.md) | Perceus RC, FBIP in-place reuse, allocation-free code |

### Concurrency

| Guide | What it covers |
|-------|---------------|
| [Actors](actors.md) | Spawn, send, receive, monitoring, named actors, mailbox limits |
| [Supervision](supervision.md) | Supervision trees, restart strategies, budgets and backoff |
| [Parallelism](parallelism.md) | `pmap` and friends on the M:N work-stealing scheduler |
| [Flow](flow.md) | Backpressure pipelines for streaming work |
| [Overload & Resilience](overload-resilience.md) | Bounded mailboxes, load shedding and backoff, withstanding thundering herds |
| [Session Types](session-types.md) | Typed two-party protocols; a send out of turn is a compile error |
| [Choreography](choreography.md) | One protocol, many roles, each role its own program on its own node |
| [SIMD & Native Arrays](simd-vectorization.md) | Auto-vectorised numeric loops and explicit vector types; [benchmarks](simd-benchmarks.md) |

### Distribution and operations

| Guide | What it covers |
|-------|---------------|
| [Clustering](clustering.md) | Nodes, membership, the global registry, typed remote messages, RPC |
| [Cluster Certificates](cluster-certificates.md) | Admitting nodes by certificate: issuing, renewing, revoking |
| [Topology](topology.md) | `topology.toml`: which pool serves which role, and on which hosts |
| [Hot Code Reload](hot-code-reload.md) | Deploy to a running node; state migration, capability-safe deploys |
| [Observing a running node](observe.md) | The observe socket, `forge status` / `diagnose` / `top`, the remote shell |
| [Multi-host Lab](lab.md) | What happens to a real multi-host deployment when it is cut, restarted and failed over |

### Tooling

| Guide | What it covers |
|-------|---------------|
| [Tooling](tooling.md) | `forge` command reference: build, test, search, deploy, and more |
| [LSP & Editors](lsp.md) | `march-lsp` features, editor setup, the DAP debugger |
| [REPL](repl.md) | Interactive session guide |
| [Property Testing](property-testing.md) | `Check.all` generators and shrinking |
| [FFI](ffi.md) | Bind C/Rust libraries: `extern`, ownership, codecs, the `march` crate |
| [Value Representation](value-representation.md) | Compiler internals: how values are laid out in memory |

### Upgrading

| Guide | What it covers |
|-------|---------------|
| [Upgrading to 0.4.0](upgrading-to-0-4-0.md) | No breaking source changes; what moved |
| [Upgrading to 0.3.0](upgrading-to-0-3-0.md) | The breaking changes in 0.3.0, one by one |
