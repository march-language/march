---
layout: docs
title: Capabilities
nav_order: 5.6
permalink: /docs/capabilities/
---

> Part of the March Language Reference: see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Capabilities: March's Effect & Capability System

March makes side effects **visible in your types**: zero runtime overhead, enforced at compile time. This guide explains what capabilities are, when to reach for each kind, when to do without them, and how they compose.

> **A note on the name.** "Effect" here is used in the everyday sense: something
> that touches the outside world, not the academic
> "effect system" sense. This is not Koka, Eff, or OCaml 5's effect
> handlers: there are no algebraic effects, no effect handlers, no
> resumable computations, and no user-defined custom effects with
> row-polymorphic inference. What exists is a fixed, closed lattice of
> IO/behavioral capabilities (`IO.Network`, `IO.FileWrite`, `cap pure`, …),
> checked in structural terms by tracing which of them a function's reachable call
> graph touches. A true per-function effect-row system is intentionally **not**
> built: it would make a `Cap(X)` parameter an upper limit over everything a
> function reaches, forcing every caller to thread capabilities it does not
> otherwise need, the opposite of March's module-scoped design. See
> [The grant](#the-grant--mains-parameter-bounds-the-whole-program), below.

---

## The problem they solve

In most languages, a function's signature tells you what data flows in and out. It states no fact about what the function *does to the world*:

```python
# Does this read a file? Call the network? Write to a database?
# You have to read the implementation to find out.
def compute_price(product_id: str) -> float:
    ...
```

That invisibility causes three recurring problems:

**Accidental effects.** A function you thought was pure secretly calls a logger, which opens a file, which fails in a read-only sandbox. You find out at runtime.

**Unclear contracts.** "Does this library write files at any point?" requires reading all the source. No amount of documentation fully substitutes for a machine-checked declaration.

**Audit blind spots.** Answering "which modules talk to the network?" in a large codebase means grepping and hoping, unless the compiler tracks it.

March's capability system addresses all three. Effects appear in the type, and the compiler traces them through the call graph. Leaving out a capability declaration is a machine-verified, build-breaking guarantee, whether `Cap(X)` flows through a signature (a function/actor/extern parameter, or a transitive `use`) or a function body calls an IO builtin directly (a warning until 2026-08-06, an error since). A call routed through a stdlib wrapper (`File.read` rather than `file_read`) slips past *this particular* check, but not the system: the **capability upper limit** catches it. The upper-limit check runs over emitted code on the compile path (on by default since 2026-08-07) and, since 2026-08-17, a sound SUBSET of it also runs under `--check`/`--check-json`, enough to catch the common stdlib-mediated route without lowering. `--compile`'s upper-limit check remains the complete one. See "What the compiler tells you," below.

```march
mod Price do
  -- No `needs`, and every parameter here is an ordinary value — no `Cap(X)`
  -- anywhere in the signature. This module cannot be forced to declare a
  -- capability it doesn't have, and calling into it can never trigger a
  -- signature-level cap error.
  fn compute(base : Float, discount : Float) : Float do
    base * (1.0 - discount)
  end
end
```

---

## Which tool do I need?

| Problem | Tool |
|---------|------|
| Control what external resources a module may touch | IO caps (`needs` / `Cap(X)`) |
| Guarantee a function is pure | Declare no capability: absence enforces it |
| Prove initialization ran before dependent code | Proof caps (`proof cap`) |
| Prove a specific value has been processed | Opaque refined type (`ptype`) |
| Track a resource's open/closed/consumed lifecycle | Typestate (`always_linear type` + `transitions`) |
| Exclude allocation/IO from a realtime callback | Specialization tag (`Tagged(X, Realtime)`) |
| Thread many capabilities without parameter explosion | Capability environment record |

---

## IO permission caps

Every module that touches external resources declares `needs`:

```march
mod Server do
  needs IO.Network

  fn listen(cap : Cap(IO.Network), port : Int) : () do
    ...
  end
end
```

The compiler enforces this transitively **when the capability flows through a signature** (Check 4). `Server.listen` takes `Cap(IO.Network)` as a parameter, so any module that `use`s `Server` and calls `listen` must itself declare `needs IO.Network` (directly, or via a broader ancestor like `needs IO`), or the build fails naming exactly what's missing. A `Caller` module that `use`s `Server` without `needs IO.Network` gets `` module `Caller` imports `Server` which requires `Cap(IO.Network)`, but `IO.Network` is not declared in `needs`. ``, exit 1. This ERROR-level guarantee covers the signature/`use`/extern surface (Checks 1, 4, and 5). See "What the compiler tells you," below, for the separate, weaker case where a module reaches for an IO builtin directly in a function body without at any point putting `Cap(X)` in a signature.

**Check 4 is demand-driven: an importer inherits only what it actually references.**
Importing a module costs the capabilities of the *functions the importer references
from it*, not the imported module's whole set: importing `List` to call `map`
costs no capability even though `List.pmap` spawns tasks, and you owe `needs IO.Spawn`
only if you actually reference `pmap`. The demand set comes from the import
tracker's per-reference record (`ie_used_names`, populated by `record_use` as it
resolves each `EVar`), resolved against the per-function transitive capability
closure `caps(f) = own(f) ∪ ⋃ { caps(g) | g ∈ refs(f) }`. Reference edges are
free-variable edges, so a function passed as a *value* counts, and a capability
reached only through a private helper still counts. It is computed per import site:
two modules importing the same library can owe different capabilities.

The result is always a **subset** of what the older module-granular rule required,
by construction: the demand set filters the imported module's declared `needs`, it
never adds to it. So this rule can only require less, and no module that
compiles today can start failing because of it. One conservative carve-over errs
toward requiring more: an import with a target that has not been analyzed yet, because
the two modules import each other cyclically, falls back to the imported module's
whole declared set (the module topological sort tolerates cycles rather than
rejecting them).

**Coverage of `own(...)`.** `record_fn_caps` records an entry for every
declaration form that can hold an expression: `DFn` signatures, bodies and
guards, default-argument expressions, actor handlers, `DExtern`s, module-level
`DLet` bodies, `DInterface` default-method bodies and `DImpl` method bodies. The
last four were added 2026-08-06 (see
`specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md`); before
that they had no entry, so a `DFn` that reached a capability *exclusively*
through one of them had a silently truncated closure and Check 4 could drop
a capability it required before demand-driven propagation landed.

Keying determines whether Check 4 actually works, so it matters:

- a `DLet` is keyed like a `DFn` of the same name, for each name its pattern
  binds, so an ordinary reference to it resolves;
- a `DImpl` method is keyed by TIR's `Iface$Ty.method` mangling, and a
  `DInterface` default body by the parallel `Iface$default.method`. Neither can
  collide with a `DFn` (an ordinary qualified name never contains `$`), nor with
  another impl of the same method for a different type. In both cases the bare
  method name additionally becomes a *dispatch node* with an edge to each
  implementation (the union over them, the sound reading of a name with a target
  chosen by type), emitted **only when the module declares no `DFn` of that
  name**, so a plain function's identity can never be absorbed. That guard
  isn't just tidiness. Skip it and a module that legally declares an
  interface method with a default body *and* a top-level `fn` of the same
  name gets a bug: the pure `fn` silently inherits the default body's
  capabilities on the hot-deploy manifest, which reads the own-caps table
  unfiltered;
- a default argument is traversed directly when the module is undesugared, and via
  an alias from desugar's arity-mangled `f$N` declarations onto the base name
  `f` on the production path (`expand_defaults_decl` moves the default into
  `f$0`'s body but leaves call sites saying `f`).

Because the demand set is *filtered* against the imported module's declared
`needs`, no addition to `own(...)` can make Check 4 stricter than the
pre-demand-driven module-granular rule.

### Capability hierarchy

`Cap(IO)` is the root. Sub-capabilities narrow what is allowed:

```
IO
├── IO.Console          — stdout/stderr (println, print)
├── IO.FileSystem
│   ├── IO.FileRead     — read files, list directories
│   └── IO.FileWrite    — write, delete, rename files/dirs
├── IO.Network
│   ├── IO.NetConnect   — outbound TCP
│   │   ├── IO.NetConnect.TLS  — encrypted transport (tls_connect, tls_accept, …)
│   │   ├── IO.Database — database connections (declaration-only; child of NetConnect)
│   │   └── IO.WebSocket — WebSocket connections (declaration-only; child of NetConnect)
│   └── IO.NetListen    — bind + listen on a port
├── IO.Process          — env vars, child processes, process exit
├── IO.Clock            — wall clock, monotonic time
├── IO.Random           — CSPRNG (random_bytes, uuid_v4)
├── IO.Signal           — OS-signal watchers (Signal.watch/unwatch/raise)
├── IO.Spawn            — task spawning (task_spawn, task_spawn_link, …)
├── IO.Mut              — shared mutable state (Vault tables)
├── IO.Telemetry        — telemetry/observability emission (declaration-only)
└── IO.Foreign          — calling unverified C (extern blocks)
    └── IO.Foreign.Blocking — blocking extern (spawns OS thread)
```

Declaring a capability is a compile-time claim. To see it become a *runtime* boundary (a compiled binary actually denying the syscalls a withheld capability gates), see [OS-level enforcement](#os-level-enforcement--sandboxing-the-compiled-binary), including the [full capability-to-OS-primitive map](#os-primitives-capability-by-capability).

This `IO` lattice is closed: every `IO`-rooted path in a `needs` declaration must appear in it. An unrecognized `IO`-rooted path (wrong case, a typo) or a bare leaf standing in for a real capability (`needs Network` instead of `needs IO.Network`) is a compile-time error with a did-you-mean suggestion, rather than being silently accepted and only surfacing later as a confusing "no function requires it" warning or an unrelated missing-`needs` error. Capability roots outside the `IO` lattice (e.g. `needs Ffi`, a dotted namespace like `needs Db.Migrated`, or an FFI extern's `Cap(LibC)`) are intentionally not in this table and stay free-form. The one exception is a *bare, single-segment* name with a spelling that collides with a real capability's leaf case-insensitively: `needs Network` is rejected in favor of `needs IO.Network`, since that's almost always a real capability written without its `IO.` path rather than an actual FFI root. A dotted non-`IO` path is never subject to that check, even if its last segment happens to coincide with an `IO` capability's leaf (`needs MyLib.Clock`, `needs Vendor.Random`): the dot makes it unambiguously its own namespace.

A module that declares `needs IO` can pass `Cap(IO)` to any function that requires a narrower cap. Use `cap_narrow` to produce a sub-capability: it's free, compile-time only:

```march
fn start(cap : Cap(IO)) : () do
  let net_cap  : Cap(IO.Network)        = cap_narrow(cap)
  let tls_cap  : Cap(IO.NetConnect.TLS) = cap_narrow(cap)
  Server.listen(net_cap, 8080)
end
```

### Choosing the right level

Use the **narrowest capability that accurately describes what the code actually does**. Narrower declarations make stronger claims; the compiler verifies them.

| What the code does | Declare |
|--------------------|---------|
| No external state, no I/O | *(no `needs` line: pure by declaration)* |
| Print to stdout/stderr | `needs IO.Console` |
| Read files or directories | `needs IO.FileRead` |
| Write, delete, or rename files | `needs IO.FileWrite` |
| Read **and** write files | `needs IO.FileSystem` |
| Outbound TCP | `needs IO.NetConnect` |
| Outbound HTTPS only, no plaintext TCP | `needs IO.NetConnect.TLS` |
| WebSocket connections only | `needs IO.WebSocket` |
| Accept inbound connections | `needs IO.NetListen` |
| Vault tables (shared mutable state) | `needs IO.Mut` |
| Spawn green tasks | `needs IO.Spawn` |
| Wall clock or sleep | `needs IO.Clock` |
| Random number generation | `needs IO.Random` |
| Watch OS signals (`Signal.watch`) | `needs IO.Signal` |
| Environment variables, child processes | `needs IO.Process` |
| Calling C via `extern` | `needs IO.Foreign` |
| Blocking C calls (OS threads) | `needs IO.Foreign` + `needs IO.Foreign.Blocking` |
| Application entry point or top-level composition | `needs IO` |

**In libraries, prefer narrow caps.** A library that only reads config files should declare `needs IO.FileRead`, not `needs IO`. Callers can then hand it a read-only view, statically proving it cannot secretly write.

**In entry points, `needs IO` is fine.** The interesting precision lives in the libraries. Application main modules compose everything; they don't need to obsess over narrowing.

### What the compiler tells you

An uncovered capability is a **build-breaking ERROR** (`--check` exits 1). Which
route it takes to being uncovered no longer changes the severity: that changed
on 2026-08-06; before then a direct builtin call in a function body was only a
warning.

**Signature, transitive `use`, or `extern`.** If `Cap(X)` appears in a
function/actor/extern parameter, or you `use` a module and reference a function
from it that needs a capability you haven't declared:

```
$ march --check caller.march   # `use`s a module needing Cap(IO.Network), no `needs IO.Network` of its own
-- ERROR --
module `Caller` imports `Server` which requires `Cap(IO.Network)`, but `IO.Network` is not declared in `needs`.
help: add `needs IO.Network` to the module body.
$ echo $?
1
```

(Note the scope: it is the functions you *reference* that count, not the
imported module as a whole. See ["Propagation is demand-driven"](#propagation-is-demand-driven).)

**A direct body call to an IO builtin**, with no `Cap(X)` anywhere in a
signature, is now the same severity:

```
$ march --check reader.march   # fn slurp(path) do file_read(path) end — no needs
-- ERROR -- function bodies in `Reader` call builtins that require `Cap(IO.FileRead)`, but `Reader` declares no matching `needs`.
hint: add these to the module body —
        needs IO.FileRead
$ echo $?
1
```

The error includes a machine-applicable fix, so `forge fix` will insert the
`needs` line for you. Every offending capability in the module is collapsed
into **one** diagnostic, not one per call site: a `main` that touches four
undeclared capabilities gets a single error naming all four once, with one
fix that inserts all four `needs` lines at once:

```
-- ERROR -- function bodies in `Main` call builtins that require `Cap(IO.Console)`, `Cap(IO.FileWrite)`, `Cap(IO.Random)`, `Cap(Time.Clock)`, but `Main` declares no matching `needs`.
hint: add these to the module body —
        needs IO.Console
        needs IO.FileWrite
        needs IO.Random
        needs Time.Clock
```

The result is one message rather than four separate errors, each with its own single-line fix and
its own restatement of the capability that was missing.

#### What this does and does not guarantee

The error above is easy to over-read, so let's be precise about what it actually covers:

- It catches a **direct** call to a capability builtin: `file_read(p)`.
- It does **not** catch, on its own, the same operation routed through a stdlib
  wrapper: `File.read(p)`. That call is invisible to *this* check. It is caught
  by the **capability upper limit** instead, which, since 2026-08-17, runs a sound
  subset under `--check` too (not only `--compile`), so `--check` now exits 1 on
  the common stdlib-mediated case rather than 0.
- The complete check is the **capability upper limit**, below, which works on
  **emitted code** and therefore cannot be evaded by re-routing through a
  helper. It is on by default, but it runs on the compile path, so `--check`
  on its own catches the common stdlib-mediated call as of 2026-08-17 (a subset of
  the upper-limit check now runs under `--check`); `--compile` remains the complete check.

So `needs` is a **mandatory, mechanically-verified manifest** of the builtins a
module calls directly, not, on its own, proof that a module cannot reach a
capability. That comes from the upper-limit check, which means it comes from `march
--compile`, not from `--check`.

There's also a distinction hiding in the word "capability" here: this
check makes you *declare* what you touch. It does not make anyone *grant* it:
`needs` is a self-declaration, and any module may write any `needs` line. IO
builtins take no capability argument.

#### Capabilities are inferred from the call graph, not threaded through parameters

The compiler figures out what a function touches by walking its call graph
at compile time (the same closure computation Check 4 uses above:
`caps(f) = own(f) ∪ ⋃ { caps(g) | g ∈ refs(f) }`). It doesn't need the
capability passed to it as a value to know that. (This is a different
mechanism from the [Capability inference hints](#capability-inference-hints)
below, which just suggests a missing `needs` line. The walk described here
is the actual check, used everywhere on this page.)

Here's what that means in practice. `log` and `log_error` below take no
`Cap` parameter at all, and the write still succeeds. The compiler follows
the call graph down to `file_write` and finds that the *module* `Logger`
declares `needs IO.FileWrite`:

```march
mod Logger do
  needs IO.Console
  needs IO.FileWrite

  fn log(msg : String) : Unit do
    let _ = file_write("/var/log/app.log", msg)
    ()
  end

  fn log_error(msg : String) : Unit do
    log("ERROR: " ++ msg)
  end

  fn main(_console : Cap(IO.Console), _write : Cap(IO.FileWrite)) : Unit do
    log_error("disk full")
  end
end
```

This compiles as-is. Delete `needs IO.FileWrite` and it fails. But look at
*how* it fails: not a missing-parameter error, but the compiler walking the
call graph and naming the whole path:

```
function bodies in `Logger` call builtins that require `Cap(IO.FileWrite)`, but
`Logger` declares no matching `needs`.
...
reached from `main`: main → log_error → log
```

If you've used an object-capability language, this probably looks wrong.
In Wyvern, E, or Newspeak's capability subset, authority exists *only* as a
value: a function that never receives the write capability as a parameter
verifiably cannot write, full stop. There's no "the module can write" without
something proving it. `log` there would need a signature like
`log(write : WriteCap, msg : String)`, and every caller above it would need
to hold and forward that same value.

March gives you a different, coarser guarantee: not "this function received
the authority as data," but "the compiler checked the module's entire
reachable call graph, however many private helpers deep, and none of it
goes beyond what the module declared." It's still a real, mechanically
checked guarantee (`--check` exits 1 on the deleted-`needs` version above),
just a coarser one than "authority is exactly what flows through
parameters."

March does still require capabilities to flow as explicit values in one
place: across module boundaries. Look back at the very first example on
this page: `Server.listen` takes `Cap(IO.Network)` as a parameter, so any
*other* module that imports `Server` and calls `listen` has to hold that
capability itself, or the build fails naming the missing `needs` (Check 4,
above). Inside a single module, no rule forces that: `needs` already covers
everything the module can reach. Cross a module boundary, though, and a
`Cap(X)` parameter behaves exactly like it would in an object-capability
language: authority only gets in if it's passed in.

### The capability upper limit: on by default

`needs` is an upper limit as well as a floor: the build fails if **any** module's
emitted code uses a capability that module did not declare. This is the
default as of 2026-08-07; `--no-cap-strict` opts out, and `--cap-strict` is
still accepted if you would rather say it explicitly.

```
$ march --compile -o app app.march
-- CAPABILITY CEILING --
module `HostileDep` uses `IO.FileRead` but does not declare `needs IO.FileRead`

1 capability ceiling violation(s). Every module's emitted code must stay
within its own `needs`.
Add the missing `needs` line to the module named above, or pass
`--no-cap-strict` to build without this check.
```

Three things make it stronger than the warnings above.

**It covers every route to a capability.** The check runs against the code the
compiler is about to emit, not the surface syntax, so a direct builtin call, a
call through a stdlib wrapper like `File.write`, and a builtin given out as a
value all collapse into the same rule. Re-routing a call through a helper does
not evade it. (The stdlib-mediated route produced no diagnostic at all before
this shipped: the import check walks `use` declarations, and stdlib modules
are ambiently available without one.)

**It applies per module, including dependencies that never opted in.** March
dependencies ship as source, so the check runs on your build of their code. A
dependency declaring only `needs IO.Console` with a helper that reads `/etc/passwd`
fails your build. You do not need the publisher's cooperation.

**It fails closed.** A capability the compiler cannot attribute to any module
(reached only through an indirect call) is reported as a violation rather than
passed, because that is exactly the route an attacker would use.

Because attribution charges a stdlib-mediated call to the *calling* module, the
standard library's own declarations are not involved: the module that called
`File.write` is the one required to declare `needs IO.FileWrite`.

It is strict, and turning it on by default is a breaking change for code
written before it: a module that reaches a capability through the stdlib now
has to say so, `needs IO.Console` most commonly. The compiler names the module
and the capability, so each fix is one line. `--no-cap-strict` unblocks a build
you do not want to migrate yet.

`IO.Foreign` is excluded: `extern` blocks are already an error when undeclared,
and what linked C code does is outside the capability model entirely.

The same upper limit can be re-checked on a compiled binary with
`forge cap inspect --strict`, which reads each module's declared and measured
capability sets out of the artifact.

### The grant: `main`'s parameter bounds the whole program
{: #the-grant--mains-parameter-bounds-the-whole-program}

Everything above verifies the *manifest*: `needs` must be present and truthful,
end to end. None of it stops anything: a module that declares
`needs IO.Network` and exfiltrates passes every check, because the declaration
is true. The grant is the point where March enforces a **no**.

`main`'s capability parameter is the program's grant, and the program's whole
transitive capability closure must sit under it:

```march
mod Report do
  needs IO.Console

  fn main(cap : Cap(IO.Console)) : () do
    println("report done")
  end
end
```

`Cap(IO.Console)` here is a machine-checked claim: this program (every helper,
every stdlib call, every dependency `main` reaches) touches no resource beyond the
console. Add a `save` helper that calls `file_write` anywhere in that closure
and the build fails, naming the chain from `main` down to the frame that
actually possesses the capability:

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.FileWrite`
(reached from `main`: main → save). The grant is a ceiling on the WHOLE program —
declaring `needs IO.FileWrite` does not raise it.
help: add a `Cap(IO.FileWrite)` parameter to `main` (e.g.
`fn main(…, _cap_filewrite : Cap(IO.FileWrite))`), or widen the whole grant to
`Cap(IO)`, or remove the use.
```

The help names the **precise** capability to add as a parameter before the
broad `Cap(IO)` escape hatch: least privilege is the default the diagnostic
steers you toward, not the widest grant.

**Actors are inside the grant.** A message handler's body counts against
`main`'s grant exactly like any other reachable code: an actor with a handler that
calls `file_write` is charged the moment the program `spawn`s it, so a program
granted only `Cap(IO.Console)` cannot smuggle a file write into a handler. An
actor that is *defined but never spawned* costs no capability, the same
dead-code-is-free rule the rest of the grant follows.

Three signatures, three meanings:

| `main` signature | grant |
|---|---|
| `fn main()` | **empty**: a build error the moment the program's closure reaches any capability; only a program that truly touches no IO compiles with it |
| `fn main(cap : Cap(IO))` | full IO: the established entry-point convention |
| `fn main(cap : Cap(IO.Console))` | narrow: the closure must sit under it |
| `fn main(a : Cap(IO.Console), b : Cap(IO.Spawn))` | union of the parameters: for when the program needs two narrow grants without widening to `Cap(IO)` |

A parameterless `main` used to be ambient (any pre-grant program kept
compiling under it); as of the grant shipping, it means the opposite:
`fn main() : () do file_write(...) end` is a compile error naming the exact
grant to add (`` `main` performs IO but declares no grant. The program
reaches `IO.FileWrite`... ``), and `forge fix` writes the missing parameter
for you.

Two intentional edges:

- **`IO.Foreign` cannot sit under a narrow grant.** What linked C code does is
  invisible to the capability lattice, so a program with a closure that reaches an
  `extern` block is not accepted under any grant narrower than `Cap(IO)`, since the
  check will not certify a bound it cannot see.
- **The grant bounds what `main` reaches, not what the file contains.** Dead
  code costs no capability, the same reachability the upper limit uses. (Its `needs`
  line is still required: the manifest checks are unchanged and orthogonal.)

The grant is `needs`' missing complement: `needs` states what a *module*
touches; the grant bounds what the *program* may. Sandbox ladder stages A/B/D
are shipped (`specs/2026-08-08-r1-no-ambient-io-design.md`). Per-function
grants (effect rows) are stage C and intentionally **not** built: making a
`Cap(X)` parameter an upper limit over everything a function reaches would force
every caller to thread capabilities it does not otherwise need, which is the
opposite of March's module-scoped design. A `Cap(X)` parameter is an authority
marker at a module boundary; the *checks* are `needs`, the module upper limit, and
`main`'s grant.

### When *not* to use IO caps

**Pure functions need no declaration.** If a function hashes a string, parses JSON, sorts a list, or formats a number, write no `needs`. The absence of `needs` is a machine-verified guarantee of the ERROR-level kind above **only for the signature/`use`/`extern` surface**: the compiler cannot force you to declare a capability that never appears in a signature and is never transitively required by an import, so this guarantee is strongest when the functions in question actually take `Cap(X)` parameters (or `use` something that does). Since 2026-08-06 a module with no `needs` that calls IO builtins directly in function bodies is REJECTED (`--check` exits 1), not just warned. A stdlib-mediated call is outside *this* check but, since 2026-08-17, is caught by the upper-limit subset that now runs under `--check`. See above.

**Don't over-narrow to look principled.** Declaring `needs IO.FileRead` when your function also writes is a lie the compiler will catch. If a function reads and writes, `needs IO.FileSystem` is correct even if it feels "less precise." Accurate beats narrow-but-wrong.

**Don't use IO caps for pure domain concepts.** A function that validates an email address or checks a constraint has no business with capabilities. Capabilities exist for external state, not for logic.

**Don't use capabilities for per-value guarantees.** `Cap(IO.FileRead)` proves a module is *allowed* to read files; it states no fact about whether a specific string value came from a trusted source. For per-value guarantees, use an opaque refined type.

**Small scripts: just use `needs IO`.** For a 50-line script you'll run once, fine-grained capability declarations add more friction than value. Use `needs IO` at the top and move on. The value of narrow caps emerges in larger codebases with multiple contributors over time.

---

## Specific IO capabilities

### IO.Mut: shared mutable state

`IO.Mut` covers Vault tables: process-global shared mutable hash maps. A module with no `needs IO.Mut` is statically proven never to touch shared mutable state:

```march
mod Cache do
  needs IO.Mut

  fn store(key : String, val : Int) : () do
    let tbl = Vault.new("app_cache")
    Vault.set(tbl, key, val)
  end
end
```

This is especially useful for library code that should have no hidden state.

**Reads need no capability.** A Vault table is in-memory: no part of what a `Vault.get`/`Vault.size`/`Vault.keys` lookup does escapes the process, so it exercises no ambient authority and needs no `needs IO.Mut`. What IS authority is turning a NAME into a table handle (`Vault.new`/`Vault.whereis`, the `File.open(path)` shape) and mutating state other actors observe (`Vault.set`, `Vault.set_ttl`, `Vault.drop`, `Vault.update`); those keep `needs IO.Mut`. Accepted trade-off: a read of shared mutable state is non-deterministic (it observes another actor's writes), so `needs` no longer signals "this function is not pure" for a reader. Authority stays auditable at the boundary, since some module still had to name the table and declare the capability to create or write it.

### IO.NetConnect.TLS: encrypted transport only

`IO.NetConnect.TLS` is a child of `IO.NetConnect`. Declaring it (without `IO.NetConnect`) proves the module uses *only* encrypted connections, no plaintext TCP. Declaring `needs IO.NetConnect` covers both.

```march
mod HttpsClient do
  needs IO.NetConnect.TLS  -- plaintext TCP is statically excluded

  fn fetch(fd, h, host) do
    tls_connect(fd, h, host)
  end
end
```

### IO.Telemetry: observability annotation

`IO.Telemetry` is declaration-only: the compiler accepts it as a semantic annotation but does not scan for specific builtins. Use it to make telemetry visible in a module's surface contract so callers know this module emits observability data:

```march
mod Metrics do
  needs IO.Telemetry

  fn record_request(duration : Int) : () do
    ...
  end
end
```

### IO.Foreign: calling unverified C
{: #ioforeign--calling-unverified-c}

`IO.Foreign` is a meta-capability triggered by the **presence of an `extern` block**, not by any specific builtin call. C code bypasses every March type guarantee, so the compiler requires you to acknowledge this explicitly.

```march
mod Bindings do
  needs IO.Foreign
  needs IO.FileSystem  -- the specific cap the C code uses

  extern "libc": Cap(IO.FileSystem) do
    fn read(fd : Int, buf : String, n : Int) : Int
  end
end
```

The `blocking` modifier spawns an OS thread. Declare both caps when any extern function is blocking:

```march
mod Bindings do
  needs IO.Foreign
  needs IO.Foreign.Blocking
  needs IO.FileSystem

  extern "libc": Cap(IO.FileSystem) do
    blocking fn slow_read(fd : Int) : Int
  end
end
```

`needs IO.Foreign` on its own subsumes `IO.Foreign.Blocking` (parent covers child), so one declaration suppresses both warnings if you prefer coarser annotations.

---

## Behavioral module caps: `cap no_panic`, `cap no_alloc`, `cap no_extern`, `cap pure`, `cap deterministic`

Beyond IO permission caps and proof caps, March has five *behavioral* capability declarations that trigger static analysis passes rather than IO-permission accounting. They share only the `cap` keyword with `needs`/`Cap(X)`: a module can declare `cap no_panic` and separately declare `needs IO.Network`, and the two mechanisms never interact. Each lives as a bare `cap <name>` statement in the module body.

### `cap no_panic`: guaranteed panic-free

```march
mod SafeMath do
  cap no_panic

  fn divide(a : {v : Int | v >= 0}, d : {v : Int | v > 0}) : Int do
    a / d
  end
end
```

A module with `cap no_panic` must not contain any expression that can panic at runtime. Three checks enforce that, covering three different ways code panics: an unsafe call, an unsafe division, and an unhandled `match` case.

**1. Unsafe calls.** Some functions can panic: `panic` itself, `List.tail` on an empty list, `Option.unwrap` on `None`. The compiler splits these into two groups:

- **Always banned, no way around it**: `panic`/`panic_`/`todo_`/`unreachable_`, and `Array.get`/`Array.set`/`Array.pop`. No code you write can make these safe, so `cap no_panic` simply forbids calling them, directly or through a local helper that calls them (a helper that panics makes every one of its own callers unsafe too, and each gets its own error).
- **Allowed if you prove it's safe**: partial functions that come with a refinement precondition: `List.nth`, `List.tail`, `List.head`, `Option.unwrap`, `Result.unwrap`, `Random.choice_weighted`, `Stats.percentile`, and similar. Guard the call with something that proves the precondition, and it's accepted:

  ```march
  mod Safe do
    cap no_panic
    -- Accepted: the guard proves `len(xs) > 0`, which is List.tail's contract.
    fn rest(xs : List(Int)) : List(Int) do
      if List.length(xs) > 0 do List.tail(xs) else xs end
    end
  end
  ```

  This reuses the same proof the refinement checker already produces elsewhere on the page: it doesn't derive anything a second time, so the two can't drift apart. Only a full proof counts: an unproven guard, a skipped check, or an `@[trusted]` assertion all still produce the panic error. (`@[trusted]` in particular is intentional: a capability with "guaranteed no panics" as its whole point can't accept, with no visible sign, an unchecked assertion as if it were a proof.)

  **Not every panic on a guarded function is covered.** The precondition only expresses what the *type system* can see: usually "the list isn't empty." `Random.choice_weighted` also panics if every weight is zero or any weight is negative, but that depends on the actual `Float` values in the list, not its length, so no refinement can rule it out. A `cap no_panic` module that calls it with a proven-non-empty, all-zero-weight list compiles clean and still panics at runtime. `Stats.correlation` and `Stats.linear_regression` have the same gap: their length preconditions are checked, but a zero-variance input still panics. If you're relying on `cap no_panic` for one of these functions, know which panic you're actually protected from.

**2. Unsafe division.** Every integer division needs its divisor proven non-zero: via the Z3 SMT solver for anything non-obvious, with fast syntactic shortcuts for common patterns (`v > 0`, `v != 0`, and so on) so the obvious cases don't need a solver at all. An enclosing `if` guard counts as proof on the branch it protects: `if d != 0 do n / d else 0 end` needs no refinement, and neither does the safe side of `if d == 0 do 0 else n / d end`. Guards combined with `&&`/`||`/`not` are read correctly: an `&&` guard is proven by either side, an `||` guard only when *both* sides independently rule out zero. Anything left over (no refinement, no guard, an expression the checker doesn't recognize) is a conservative error. If Z3 itself is unavailable, the check stays conservative rather than skipping: an unverified division is still treated as an error, not silently allowed.

Use `Math.checked_div` / `Math.checked_mod` when you can't prove the divisor is non-zero statically: they return `Option(Int)` instead of panicking.

**3. Non-exhaustive `match`.** In an ordinary module, a `match` that doesn't cover every constructor is a warning: the build still succeeds. Under `cap no_panic` it's an error: an uncovered case is a runtime panic waiting to happen ("no matching clause"), and excluding that is exactly what the capability promises.

One tooling caveat worth knowing: `march check` (the fast, package-level command) doesn't run the same proof infrastructure as `march --compile`/`--check`, so for the "allowed if you prove it" functions above it falls back to banning them by name rather than checking your guard. That means `march check` can reject a call that `march --compile` accepts. It's being more conservative, not wrong. The LSP has the same limitation inside a top-level module (nested modules get full proof-based squiggles).

### `cap no_alloc`: no heap allocation

```march
mod RealTimeDSP do
  cap no_alloc

  fn mix(a : Float, b : Float, gain : Float) : Float do
    (a + b) * gain
  end
end
```

`no_alloc.ml` walks every function body and flags heap-allocating expressions:

| Allocating expression | Error |
|-----------------------|-------|
| `ETuple` with ≥1 items | tuple construction allocates |
| `ERecord` | record construction allocates |
| `ECon` with ≥1 args (e.g. `Some(x)`) | boxed constructor allocates |
| `ELam` | lambda/closure allocates |

Nullary constructors (`None`, `True`, `False`, custom zero-arg tags) and unit `()` are safe: they compile to immediate integer tags with no heap allocation.

The check recurses into sub-expressions inside `if`, `match`, `let`, blocks, etc.

### `cap no_extern`: no foreign calls

```march
mod NoFFIService do
  cap no_extern
  needs IO.Network

  fn ping(_cap : Cap(IO.Network), host : String) : Int do
    string_length(host)
  end
end
```

A module with `cap no_extern` may not contain an `extern` block and may not declare `needs IO.Foreign`: either one is an immediate error. Useful for a module that must stay pure C-free code, e.g. because it needs to run somewhere `extern`'s FFI trust boundary isn't available.

### `cap pure`: no side effects at all

```march
mod PureMath do
  cap pure

  fn add(a : Int, b : Int) : Int do
    a + b
  end
end
```

A module with `cap pure` bans every call to a builtin that performs any side effect (file IO, network IO, spawning, sending, vault access, console output, randomness, the clock), as well as `spawn`/`send`/`exit`. The banned set is derived from the same authoritative builtin-to-capability table (`builtin_cap_table`) the ordinary IO-cap body-scan check consults, so it stays in sync with the real builtin surface: a module declaring `cap pure` and calling `file_write` is rejected:

```
$ march --check leaky_pure.march   # cap pure; fn write(...) : Result(Unit, String) do file_write(path, contents) end
-- ERROR -- `write` in `mod LeakyPure` (declared `cap pure`) calls `file_write`, which has side effects.
$ echo $?
1
```

### `cap deterministic`: no clock, no randomness

```march
mod DeterministicSim do
  cap deterministic

  fn checksum(bytes : String) : Int do
    string_length(bytes)
  end
end
```

`cap deterministic` is **strictly weaker than `cap pure`**: it bans only the two nondeterminism sources (wall-clock/monotonic-clock reads and random-number generation), so a `cap deterministic` module may still perform ordinary IO such as `file_read`, as long as it never touches the clock or an RNG:

```
$ march --check clock_leak.march   # cap deterministic; calls unix_time_ms(())
-- ERROR -- `now` in `mod DetLeak` (declared `cap deterministic`) calls `unix_time_ms`, which is non-deterministic.
$ echo $?
1
```

**A fix landed in this reference's widening slice:** both `cap pure`'s and `cap deterministic`'s banned-builtin sets used to be hand-maintained name lists that referenced builtins spelled wrong or that never existed (e.g. `write_file`, `random_int`, `now_ms`) while missing the real ones (`file_write`, `random_bytes`, `unix_time_ms`), so `cap pure`/`cap deterministic` silently failed to catch the most common effectful calls. Both sets are now derived from the compiler's single authoritative effect map, closing that gap; the fix does not change either cap's intended meaning, only which calls it actually catches.

### Choosing among the five

| I want to… | Use |
|------------|-----|
| Prove no integer division can panic, and rule out non-exhaustive matches | `cap no_panic` + Int refinements on divisor params |
| Guarantee safe use in a realtime audio callback | `cap no_alloc` (+ `Tagged(DSP, Realtime)` for the calling site) |
| Keep a module free of C/FFI trust-boundary crossings | `cap no_extern` |
| Guarantee a module has zero side effects, not just no IO caps declared | `cap pure` |
| Guarantee reproducible output (no clock, no RNG) while still allowing ordinary IO | `cap deterministic` |
| Both: pure, panic-free, zero-alloc | `cap no_panic` and `cap no_alloc` together |

All five declarations can coexist in the same module. Each is checked by its own independent pass, and none of them subsumes or implies any other.

---

## Capability inference hints

If you call a function that requires a `needs X` declaration but your module doesn't have one, the compiler emits a **hint** (not an error) pointing to the call site:

```
hint: this call uses IO.FileRead but mod Config does not declare `needs IO.FileRead`.
hint: add `needs IO.FileRead` to the module body.
```

This is informational, and it is **not necessarily backed by a type error**. Do not assume one is coming. The hint pass (`cap_infer.ml`) runs after typechecking and shares the same underlying builtin-capability table as the typechecker's own body-scan check, but that check is *itself* warning-level for a direct body call (see "What the compiler tells you," above): the type checker enforces `needs` as a hard error only for `Cap(X)` reaching a signature, a transitive `use`, or an `extern` block. A `cap_infer.ml` hint attached to a plain body call to an IO builtin, with no `Cap(X)` in any signature, can appear on a program that `--check`s clean (exit 0): the hint and the warning are the whole story in that case, not a preview of a rejection.

---

## Putting it together

Here's how capability declarations compose across a small web application. Reading the `needs` list of each module answers "what does this module do to the world?" without opening the implementation:

```march
mod AppConfig do
  -- Note: named `AppConfig`, not `Config` — `Config` is already a stdlib
  -- module (`stdlib/config.march`), and a user module of the same name
  -- would collide with it once this file joins a real multi-file build.
  needs IO.FileRead          -- reads one config file, nothing else

  type AppConfig = AppConfig

  fn load(path : String) : AppConfig do ... end
end

mod Metrics do
  needs IO.Telemetry         -- makes observability a visible architectural concern

  fn record(event : String, duration : Int) : () do ... end
end

mod Api do
  -- Likewise `WebServer`/`ConnCtx` here, not `HttpServer`/`Conn` — those
  -- names are already taken by stdlib's `HttpServer` module.
  use WebServer

  needs IO.NetListen         -- binds a port
  needs IO.NetConnect.TLS    -- outbound HTTPS only — no plaintext TCP
  needs IO.Mut               -- session vault

  fn start(io : Cap(IO.NetListen), tls : Cap(IO.NetConnect.TLS),
           mut : Cap(IO.Mut)) : () do
    WebServer.new()
    |> WebServer.plug(fn conn -> handle(conn, tls, mut))
    |> WebServer.run(io, 8080)
  end
end

mod Main do
  use AppConfig
  use Api

  needs IO

  -- The initial Cap(IO) is provided implicitly by the runtime to `main()` —
  -- there is no `root_cap()` call in user code.
  fn main(cap : Cap(IO)) : () do
    let config  = AppConfig.load("/etc/myapp/config.toml")
    let io_cap  : Cap(IO.NetListen)      = cap_narrow(cap)
    let tls_cap : Cap(IO.NetConnect.TLS) = cap_narrow(cap)
    let mut_cap : Cap(IO.Mut)            = cap_narrow(cap)
    Api.start(io_cap, tls_cap, mut_cap)
  end
end
```

`AppConfig` is verifiably read-only. `Api` cannot read files and cannot use plaintext TCP. If `AppConfig.load` at any point called a network function, the build would fail until `needs IO.NetConnect` was added: no audit needed.

---

## Runtime behaviour

A `Cap(X)` is a **nullable pointer**. By default it is null — compiling to `null` in LLVM IR and `VUnit` in the interpreter, with no allocation, no indirection and no overhead — and that is what every capability is unless something explicitly attaches a [runtime dictionary](#runtime-dictionaries-swapping-what-a-capability-does) to it. Enforcement of the capability *types* is purely at compile time. Enforcement of the capability *types* is purely at compile time, but a compiled binary can additionally turn its declared set into a kernel-enforced sandbox at startup; see [OS-level enforcement](#os-level-enforcement--sandboxing-the-compiled-binary) below.

---

## OS-level enforcement: sandboxing the compiled binary
{: #os-level-enforcement--sandboxing-the-compiled-binary}

FFI is the part of this the compiler can never see: an `extern` C call, a `dlopen`, or a raw syscall runs past the point where capability types apply, no matter how good the checker gets. That's the [`IO.Foreign`](#ioforeign--calling-unverified-c) boundary, and the gap [`forge audit`]({{ site.baseurl }}/docs/capability-audit/#what-this-does-and-does-not-prove) is explicit about not closing. But `--cap-sandbox` isn't only about FFI. It's also a safety net for ordinary March code: a capability-inference bug, or a dependency that's wrong, with no visible sign, about what it touches, gets caught the same way an opaque C call does. March can close both cases at the OS level, turning the declared capability set into an actual confinement.

**How much assurance do you actually get, and what does it cost you?** From least to most:

| Option | What you do | What you get | Caveat |
|---|---|---|---|
| No extra step (only the type system) | Just write March; `needs`/`Cap(X)` are required to reach any IO builtin | Compile-time proof of what the *code* can reach, for anything flowing through a signature or a direct body call | Proves no property of the running binary. `extern`/FFI C code is invisible past `IO.Foreign`. A call routed through a stdlib wrapper (`File.read` rather than `file_read`) is caught by the capability upper limit: `march --compile`'s check completely, and since 2026-08-17 a sound subset also under `--check`. |
| [`forge cap inspect`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary) | Run it against a compiled binary | An audit of what capabilities the binary appears to need | Read-only: reports, does not confine. |
| `--cap-sandbox` (below) | Add the flag at compile time | The binary sandboxes *itself* at startup, from its own declared/used capabilities | Self-imposed and opt-in: a binary built without it is simply unconfined. Protects against your own bugs and compromised dependencies, not a hostile publisher. |
| `forge cap run ./binary` (below) | Run through forge instead of directly | Forge installs the sandbox from *outside* the process, before it starts | Policy still derives from the binary's own claimed capabilities: an under-reporting binary gets an under-scoped policy. |
| `forge cap run --allow-only X ./binary` | Run through forge and state the policy yourself | The strongest option: confinement chosen entirely by you, independent of what the binary claims | You have to know what to allow. Doesn't stop misuse *within* an allowed capability. |

The rule of thumb: the type system is the foundation everything else sits on. `--cap-sandbox` is for code you trust, deployed somewhere forge isn't the launcher. `forge cap run` (especially `--allow-only`) is for code you don't trust, whenever you *can* be the launcher.

There are two OS-level mechanisms: one imposed on the process from outside, one built into it.

### `forge cap run`: externally imposed (the stronger one)

`forge cap run` launches a binary under a sandbox that *forge* installs before the program gets control:

```
$ forge cap run ./build/myapp                        # policy from the binary's own claim
$ forge cap run --allow-only IO.Console ./untrusted   # policy YOU choose
```

For a binary you do **not** trust, pass `--allow-only`: deriving the policy from the binary's own claim only tells you what it concedes, which is worthless against code trying to hide. Where a capability cannot be enforced by the platform's available primitive, `forge cap run` reports it as **advisory** per capability rather than pretending to enforce it. This is the stronger of the two mechanisms, because the launcher, not the code being confined, chooses the policy.

### `--cap-sandbox`: self-imposed (defense in depth)

Compiling with `--cap-sandbox` embeds a **deny-default** profile, derived from *this program's own* declared capabilities, that the binary installs on itself at startup before any user code runs:

```
$ march --compile --cap-sandbox -o build/myapp app.march
```

- **macOS**: a Seatbelt (SBPL) profile via `sandbox_init()`. Deny-default, then each declared capability opens a specific hole: `IO.FileWrite` allows writes (narrowed to the path scopes you declared, otherwise blanket), `IO.Network` allows the `network*` operation class, `IO.Process` allows `process-fork`. `IO.FileRead` is **advisory** here: dyld must map system libraries before any user code exists, so the baseline allows reads unconditionally and a scoped read rule would be decorative.
- **Linux**: an unprivileged in-process **seccomp-bpf** filter (`PR_SET_NO_NEW_PRIVS` + `PR_SET_SECCOMP`). One syscall class is denied per *withheld* capability: no `IO.Network` blocks `socket`/`socketpair`, no `IO.Process` blocks `execve`/`execveat`, no `IO.FileWrite` blocks the write path; denied calls return `EPERM`. `IO.FileRead` is not enforced here either, because seccomp filters syscall *numbers*, not paths; path-scoped reads come from `forge cap run`'s mount namespace instead.

Installation **fails closed**: if the sandbox cannot be installed, the program will not run rather than continue unconfined.

`--cap-sandbox` is **opt-in defense-in-depth**, not a guarantee against a hostile *publisher*: the party building the binary chooses whether to compile it in, so a malicious author simply omits it. Its purpose is a binary *you* built and trust, deployed somewhere `forge` is not the launcher (under systemd, a supervisor, a container entrypoint), the exact case `forge cap run` cannot reach. When you control the launcher, prefer `forge cap run`.

Because both mechanisms confine the **whole process**, they bound even the code the compiler cannot see: `extern` C, `dlopen`, raw syscalls. They are the enforcement counterpart to [`forge cap inspect`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary): `inspect` *reads* what a binary possesses; these *enforce* what it may do.

**Two platform asymmetries, confirmed against real running binaries rather than assumed from source:**

- On macOS, `IO.Network`'s `network*` grant does not gate `socket()` creation itself: only the actual network operation, `bind()`/`connect()`. A withheld `IO.Network` still lets a program open a socket; it just can't do anything with it. Linux denies `socket`/`socketpair` entirely.
- On macOS, `IO.Process`'s `process-fork` grant gates `fork()` only: `process-exec` is unconditionally allowed in the baseline regardless of capability, so a withheld `IO.Process` still lets a program `execve()` a new one. Linux is the reverse: `execve`/`execveat` are denied, `fork`/`clone` never are (the scheduler needs threads). Tracked as an open question, not settled behavior: [specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md](https://github.com/march-language/march/blob/main/specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md).

### OS primitives, capability by capability

The prose above names the operation classes; this is the full map, including capabilities not mentioned above because they're advisory on every backend. For what each capability means and when to declare it, see the [Capability hierarchy](#capability-hierarchy) above. Both enforcement mechanisms were verified against real compiled/running binaries. See `test/test_cap_sandbox_runtime.ml` (`--cap-sandbox`) and `forge/lib/cap_sandbox.ml`'s header comment (`forge cap run`), which record exactly how each row was measured.

**`--cap-sandbox` (self-imposed):**

| Capability | macOS (Seatbelt) | Linux (seccomp-bpf) |
|---|---|---|
| `IO.Network` | `network*`: gates `bind`/`connect`, **not** `socket()` creation | denies `socket`, `socketpair` entirely |
| `IO.Process` | `process-fork`: gates `fork()` only; `process-exec` always allowed | denies `execve`, `execveat`; `fork`/`clone` never gated |
| `IO.FileWrite` | `file-write*` (blanket, or `subpath`-scoped to a declared `@[scope]`) | denies write-flagged `openat` (`O_WRONLY`/`O_RDWR`/`O_CREAT`/`O_TRUNC`/`O_APPEND`) plus the unambiguous mutators (`unlink*`, `rename*`, `mkdir*`, `rmdir`, `truncate*`, `chmod*`) |
| `IO.FileRead` | Advisory: baseline unconditionally allows `file-read*`/`file-read-metadata` (dyld needs it before user code exists) | Advisory: seccomp filters syscall *numbers*, not path arguments |

**`forge cap run` (externally imposed):**

| Capability | macOS (`sandbox-exec` / SBPL) | Linux (bubblewrap) |
|---|---|---|
| `IO.FileWrite` / `IO.FileSystem` | `file-write*` | `--ro-bind / /` (whole tree read-only) unless granted, then full read-write |
| `IO.Network` / `IO.NetConnect` / `.TLS` / `IO.WebSocket` / `IO.Database` | `network*` | `--unshare-net` (network namespace) |
| `IO.NetListen` | Folded into `network*`: Enforced, no separate bind/listen split | Advisory: a network namespace isolates rather than denies: `bind()` still succeeds, it's just unreachable |
| `IO.Process` | `process-fork` (Enforced overall, but exec of the target itself can't be denied: same underlying gap as `--cap-sandbox`) | `--unshare-pid` |
| `IO.FileRead` | Advisory: dyld must read system libraries before user code runs | Enforced: an allow-list mount namespace (`--ro-bind-try` on only the loader's paths and the binary); anything else is *absent*, not just forbidden |
| `IO.Clock`, `IO.Spawn`, `IO.Console`, `IO.Random`, `IO.Foreign`(`.Blocking`) | Advisory everywhere, both platforms: no way to tell each one from the runtime's own baseline traffic (`clock_gettime`, thread creation, stdout/stderr needed to report violations, `/dev/urandom` read at startup, foreign C code being outside the capability model entirely) | (same) |

---

## Hot-deploy authorization: node-local admission control

When using `forge deploy hot` to upgrade a running application, the node has a second opportunity to enforce capability discipline at deployment time: after signature verification, before the new code is loaded.

> This section covers the **node-side policy gate**. There is also a **client-side monotonicity gate**: a deploy that widens a function's authority beyond the running version aborts unless you pass `--grant-cap`. Both gates, with a full worked example (a console-only handler that gains `file_write`, and how each gate responds), are in the [Hot Code Reload guide → Capability-safe deploys]({{ site.baseurl }}/docs/hot-code-reload/#capability-safe-deploys).

### How it works

A hot deploy activates only the **functions that changed** (each is sent as a separate signed activation message). For **each activated function**, `forge deploy hot` embeds that function's own inferred IO capabilities (the capabilities its own body actually requires) in the message. Admission is checked per activated function, not over the whole artifact. (This granularity matters: `--hot-reload` links the entire standard library, so a *whole-artifact* capability set would be dominated by the stdlib's footprint and identical for every app: useless for a policy. Gating on the changed function's own caps is what makes the policy discriminating.) The trust boundary is: the **base server binary is trusted** (the operator built and started it, with a policy), and each **hot-patched function** is what the gate governs.

The receiving node, for each activated function:

1. **Recomputes the capability set**: normalizes the function's declared caps and hashes them with BLAKE3, reproducing the digest that was signed during the deploy.
2. **Tamper-checks**: compares its computed digest to the signed value; a mismatch (`ERR cap_tamper`) aborts before dlopen. The tamper check is **unconditional** even when the function declares no capabilities: a truly cap-free function has the fixed digest `blake3("")`, so a stripped capability field on a signed message is detected rather than silently admitted.
3. **Applies the deployment policy**: if `MARCH_DEPLOY_POLICY` is set (a file path), the node verifies that every capability the activated function declares is subsumed by a capability listed in the policy; a capability outside policy (`ERR cap_policy <cap>`) aborts.

### Configuring the policy

Set the `MARCH_DEPLOY_POLICY` environment variable to a file path:

```bash
export MARCH_DEPLOY_POLICY=/etc/march/deploy-policy.txt
```

The policy file is line-delimited. Each non-empty, non-comment line is a permitted capability path:

```
# /etc/march/deploy-policy.txt
IO
IO.FileRead
IO.NetConnect.TLS
IO.Clock
```

An empty policy file or absent `MARCH_DEPLOY_POLICY` ⇒ permissive (all activations admitted). This is the default for backward compatibility. A policy constrains what *hot-patched* functions may do; it does not retroactively constrain the trusted base binary the operator already deployed.

### Threat model and scope

The policy is **authorization on a self-reported manifest**: a defense-in-depth layer, not a sandbox. A party with the signing key can lie about what capabilities the code uses. The node admission gate proves:

- The artifact was signed by the expected entity (Phase 4 ed25519 signature).
- The declared capability set has not been tampered with in transit (BLAKE3 tamper-check).
- The declared capabilities are within a static policy envelope (subsumption check).

It does **not** prove that the code actually *uses* only those capabilities: only that the manifest claims it does, and the claim is signed and untampered. Runtime enforcement via `cap no_panic`, `cap no_alloc`, FFI sandboxing, or OS-level confinement can provide stronger guarantees. For most deployments, the combination of compile-time capability verification + signed manifests + policy gates is sufficient.

---

## Proof caps: encoding initialization order

IO caps control *which resources* a module may touch. Proof caps control *when* dependent code may run. They're separate concerns.

### The problem they solve

Some operations must happen before others:

```march
-- What stops someone calling this before run_migrations?
fn query(sql : String) : List(Row) do ... end
```

A proof cap makes "migrations have run" part of the type:

```march
mod Db do
  proof cap Migrated
  needs IO

  fn run_migrations(cap : Cap(IO)) : Cap(Db.Migrated) do
    -- do the real migration work using the IO capability, then mint the proof.
    -- `mint_cap` is the sanctioned way to construct a proof cap; it typechecks
    -- ONLY here — inside a public `fn` of the declaring module. Runtime-erased.
    mint_cap(cap)
  end

  fn query(m : Cap(Db.Migrated), sql : String) : List(Row) do
    -- cannot be called without migration proof
    ...
  end
end
```

`Cap(Db.Migrated)` is **unforgeable**: every claim below is compiler-enforced (widening slice 6, 2026-07-08):
- `cap_narrow` cannot produce it. This is enforced, not just "not in the IO hierarchy": `cap_narrow`'s result may never be a nominal proof cap in *any* expression position (it only attenuates IO caps).
- The runtime-provided `Cap(IO)` in `main()` cannot produce it: the only mint is `mint_cap`, and `mint_cap` is gated.
- Only public (`fn`) functions of `mod Db` can `mint_cap` it: private (`pfn`) functions may pass it through but cannot construct one.
- External code can pass it through, but cannot construct one, and no polymorphic launder through a nested unannotated helper can erase the cap type either (the deeper forge, closed by the nested-module soundness fix).

Any module that accepts `Cap(Db.Migrated)` must declare `needs Db.Migrated`. Forgery is a compile error:

```march
mod Sys do
  mod Db do
    proof cap Migrated
  end

  mod App do
    needs IO
    needs Db.Migrated

    -- ERROR: only public functions of `Db` can construct `Cap(Db.Migrated)`.
    -- `mint_cap` outside the declaring module is rejected (here, by Check 6,
    -- because the mint sits in the declared return position).
    fn bad(cap : Cap(IO)) : Cap(Db.Migrated) do mint_cap(cap) end

    -- ERROR: cap_narrow can no longer forge a proof cap in any position.
    fn steal(cap : Cap(IO)) : Cap(Db.Migrated) do cap_narrow(cap) end

    -- OK: pass-through is allowed
    fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
  end
end
```

> **Resolved (widening slice 6, 2026-07-08).** Earlier releases had two gaps here: the documented mint idiom didn't typecheck (a bare `()` at the end of a `Cap(Db.Migrated)`-returning body was rejected `expected Cap(Db.Migrated) but got ()`), and the mechanism that *did* work (`cap_narrow`, with a polymorphic return `Cap(a)` that instantiated to any proof cap at the call site) was unrestricted, so any holder of an ordinary `Cap(IO)` could mint any proof cap by name with no covering `needs`. Both are now closed. The sanctioned mint is the gated **`mint_cap`** primitive (typechecks only inside a public `fn` of the declaring module; runtime-erased); **`cap_narrow` can no longer produce a proof cap** in any position; and the general nested-module type-erasure hole the deepest forge relied on (`consume(id(cap))`, laundering through a nested unannotated helper) is closed by the intra-module reference-soundness fix. See `specs/lang/core-march-types.md` §2.8.13 (proof-cap minting/forging/unforgeability) and §2.5.1 (`(T-QualRef)`) for the rule-numbered treatment and corpus witnesses. One narrow residual stays open: a `cap_narrow` result wrapped in a container through a polymorphic factory can still forge in some shapes (the taint tagger is non-recursive); tracked in `specs/todos/` under "Compiler: Capabilities/effects".

### When to use proof caps

Proof caps suit **ambient, payload-independent facts**: things true about the *system*, not about a specific value:

| Proof cap | Meaning |
|-----------|---------|
| `Cap(Db.Migrated)` | Database migrations have run |
| `Cap(Auth.Authenticated)` | The current request has a verified identity |
| `Cap(App.Initialized)` | Application startup has completed |
| `Cap(Config.Loaded)` | Configuration has been validated |

The key test: **is there a single, well-defined place in the codebase that produces this capability?** If yes, a proof cap works cleanly. If initialization is diffuse, conditional, or happens in multiple places, a proof cap will feel awkward. Use a runtime flag instead.

### When *not* to use proof caps

**Don't use proof caps for per-value facts.** If the guarantee must be tied to a specific value ("this `String` has been sanitized"), use an opaque refined type:

```march
mod Sanitize do
  ptype Sanitized = Sanitized(String)   -- private constructor

  fn sanitize(raw : String) : Sanitized do
    Sanitized(escape_html(raw))
  end

  fn render(s : Sanitized) : String do
    let (Sanitized(text)) = s
    text
  end
end
```

A `Cap(Sanitized)` would prove "some string was sanitized somewhere," but not that the string you're about to render *is* the one that was sanitized. The opaque type ties proof and data together: you physically cannot pass an unsanitized string to `render`.

**Don't use proof caps when there's no single mint point.** Unforgeability is only meaningful when the minting surface is small and auditable. If the initialization is spread across many code paths, the cap gives a false sense of safety.

---

## Typestate: tracking resource lifecycle

IO caps answer "is this module allowed to open a file?" Typestate answers "is *this specific handle* currently open or closed?"

### `Handle(R, S)` from the standard library

`stdlib/handle.march` ships a canonical typestate handle:

```march
always_linear type Handle(r, s) = Handle(Int)
```

The `r` parameter is a phantom *resource tag* and `s` is the current *state*. Because `Handle` is `always_linear`, dropping it without consuming it, or consuming it twice, are both compile-time errors.

```march
tag ConnTag
tag Closed
tag Open

fn connect(cap : Cap(IO.Network)) : Handle(ConnTag, Closed) do ... end
fn open(h : Handle(ConnTag, Closed)) : Handle(ConnTag, Open) do ... end
fn query(h : Handle(ConnTag, Open), sql : String) : (List(Row), Handle(ConnTag, Open)) do ... end
fn close(h : Handle(ConnTag, Open)) : Handle(ConnTag, Closed) do ... end
```

The wrong call order is a type error:

```march
let h0 = connect(net_cap)
let h1 = query(h0, "SELECT 1")  -- ERROR: expected Handle(ConnTag, Open), got Handle(ConnTag, Closed)
let h2 = open(h0)               -- OK
let (rows, h3) = query(h2, "SELECT 1")
let h4 = close(h3)
```

### Declaring transitions

A `transitions` block names every valid state transition. The compiler verifies each `via` function exists with the right signature, and warns about functions that look like transitions but aren't declared:

```march
mod Db do
  transitions Handle do
    ConnTag: Closed -> Open   via open
    ConnTag: Open   -> Closed via close
  end
end
```

### `always_linear type` for your own handles

```march
always_linear type FileHandle(s) = FileHandle(Int)

tag FileClosed
tag FileOpen

fn open_file(path : String) : FileHandle(FileClosed) do ... end
fn read_file(h : FileHandle(FileOpen)) : (String, FileHandle(FileOpen)) do ... end
fn close_file(h : FileHandle(FileOpen)) : FileHandle(FileClosed) do ... end
```

### `tag`: zero-arg phantom label types

`tag Foo` is shorthand for `type Foo = Foo`: a zero-argument phantom type for state labels and resource tags:

```march
tag ConnTag
tag Closed
tag Open
```

### When to use typestate

Use typestate when:
- A resource has a finite, well-defined lifecycle (closed → open → consumed)
- Calling operations in the wrong order is a programmer error worth preventing statically
- The resource must not be dropped without being explicitly released

Don't use it for:
- Simple flags or booleans that change frequently at runtime: the type parameter overhead isn't worth it
- Cases where the lifecycle state is dynamic and not known until runtime

The LSP shows typestate hover: hovering any `Handle(R, S)` expression displays the current state and all declared transitions from it.

---

## Runtime dictionaries: swapping what a capability *does*
{: #runtime-dictionaries-swapping-what-a-capability-does}

A capability proves permission. A **dictionary** attached to one also decides
what the permitted operations *do*, so an implementation can be swapped at a
binding site — for mocking in tests, for tracing, or for pointing a transport
somewhere else.

### Your own capabilities

Declare the dictionary type on the capability, then attach one:

```march
mod Session do
  type Ops = { emit : (String) -> Int }
  proof cap Live with Ops
  needs IO

  fn boot(c : Cap(IO)) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { emit: fn s -> String.length(s) })
  end

  fn emit(c : Cap(Session.Live), s : String) : Int do
    match cap_dict(c) do
      Some(d) -> d.emit(s)
      None    -> String.length(s)   -- no dictionary: the ambient behaviour
    end
  end
end
```

`cap_dict` yields an `Option`, and `None` means "no dictionary — use the
ambient implementation". That is what every capability written before
dictionaries existed reads as, which is why the default path stays visible in
the source rather than being implied.

`cap_narrow` carries a dictionary across attenuation: a narrowed capability is
the same authority, reduced. `mint_cap` does **not** — a mint produces a *new*
capability, so inheriting the dictionary of the `Cap(IO)` it was minted from
would give it operations belonging to something else.

**Who may attach one.** Supplying a dictionary decides what a capability does,
which is at least as much authority as minting one, so it is gated exactly like
[`mint_cap`](#proof-caps-encoding-initialization-order): only a public `fn` of
the declaring module, with the capability fixed at the call site. A supplier
whose result type is left polymorphic is rejected — it could re-implement every
capability at once.

### Mocking an IO capability in tests

IO capabilities have no declaring module, so the rule above has nothing to bind
to; attaching a dictionary to one is admitted **only in a test build**. There
is also nothing to hand-write: an IO capability's dictionary is derived from the
compiler's own tables, one field per interceptable operation, each an `Option`
that is `None` when not overridden. `march --emit-io-ops` prints the shapes.

```march
fn main(c : Cap(IO.Console)) do
  let mock = cap_impl(c, { cap_ops_empty(c) with
    print_line: Some(fn s -> print("MOCK[" ++ s ++ "]\n")) })
  with_cap(mock, fn _ -> code_under_test())
end
```

`cap_ops_empty(c)` is the all-`None` base to override one field of — March
records unify exactly, so without it every mock would have to spell out every
operation. `with_cap(mock, fn _ -> …)` is the binding site: inside that lambda
the mock is in force, and nowhere else.

The code under test needs no capability parameter and names no capability. A
cap-requiring builtin does not take its capability as an argument — the
requirement is checked against `needs`, not passed — so in a test build the
compiler threads one in for you and routes the operation through the
dictionary. Outside a test build none of this runs and the program is exactly
what it always was.

### What cannot be intercepted

Each of these costs interception, never correctness: an operation that is not
intercepted behaves exactly as it does today.

| Not interceptable | Why |
|---|---|
| Polymorphic builtins — all of `vault_*`, so `IO.Mut` entirely | A dictionary field would need rank-2 types |
| `println`, `random_bytes` | Shadowed by a stdlib March function, so the builtin is dead — intercept the `print_line` it delegates to |
| Operations inside actor handlers | The scheduler invokes a handler, so there is no caller to thread a capability from |
| Functions used as values rather than called directly | Their arity cannot change |

Fully mockable today: `IO.Console`, `IO.Clock`, `IO.Random`, `IO.FileRead`,
`IO.FileWrite`, `IO.NetConnect`, `IO.NetConnect.TLS`, `IO.WebSocket`,
`IO.Signal`, `IO.FileSystem`, `IO.Network`.

---

## Advanced patterns

### Specialization tags: realtime exclusion

`Tagged(X, T)` annotates a capability with a policy. The key narrowing rule: a function taking `Tagged(_, Realtime)` is in a realtime context and cannot also hold `Cap(Alloc)`, `Cap(IO)`, or `Cap(Panic)`. The compiler rejects mixed signatures:

```march
type DSP = DSP
type Realtime = Realtime

-- ERROR: realtime functions cannot take Cap(IO)
fn bad(cap : Tagged(DSP, Realtime), io : Cap(IO)) : () do () end

-- OK: statically proven — no allocation, no IO, no panic
fn process(cap : Tagged(DSP, Realtime), buf : Buffer(Float32, 256)) : Buffer(Float32, 256) do
  ...
end
```

`Tagged` also covers type-indexed specialization (SIMD widths, buffer sizes): monomorphization handles these for free:

```march
fn fft(cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
-- monomorphization produces fft_256, fft_1024, etc.
```

### Capability environment records: reducing parameter count

When many functions need the same bundle of capabilities, threading individual `Cap(X)` parameters everywhere is tedious. Bundle them into a record instead:

```march
type RuntimeEnv = {
  io    : Cap(IO),
  clock : Cap(IO.Clock),
  net   : Cap(IO.Network)
}

fn run(env : RuntimeEnv, data : Input) : Output do ... end
```

Narrow to a restricted set by constructing a smaller record: the type system enforces what the callee can do through record structure:

```march
type PluginEnv = { clock : Cap(IO.Clock) }

fn run_plugin(env : RuntimeEnv, plugin : Plugin) do
  plugin.run({ clock: env.clock })  -- plugin structurally cannot use IO or network
end
```

Each env module should provide named narrowing functions:

```march
mod RuntimeEnv do
  fn narrow_for_plugin(env : RuntimeEnv) : PluginEnv do
    { clock: env.clock }
  end
end
```

### Testing with capability environment records

This pattern predates [runtime dictionaries](#runtime-dictionaries-swapping-what-a-capability-does) and is still the right tool when you want the swap to be **visible in the signature** — a `LogEnv` parameter says outright that the caller chooses the logger. Reach for a dictionary instead when you want the swap to be invisible: a function taking `Cap(IO.Console)` can be mocked without changing its type.

Pair the cap with a function field for swappable runtime behaviour:

```march
type LogEnv = {
  log_cap : Cap(IO.Console),  -- compile-time gate, erased at runtime
  write   : (String) -> ()    -- runtime behaviour — swappable in tests
}

fn test_process() do
  let captured = Vault.new("test_capture")
  Vault.set(captured, "lines", Nil)
  let env : LogEnv = {
    log_cap: test_logger_cap(),
    write:   fn line ->
      match Vault.get(captured, "lines") do
      Some(xs) -> Vault.set(captured, "lines", Cons(line, xs))
      None     -> Vault.set(captured, "lines", Cons(line, Nil))
      end
  }
  let result = process(env, test_input)
  let lines = match Vault.get(captured, "lines") do
    Some(xs) -> xs
    None     -> Nil
    end
  Test.assert_true(List.any(lines, fn l -> String.contains(l, "expected message")), "should have captured the message")
end
```

---

## Quick decision guide

| I want to… | Use |
|------------|-----|
| Prove a module never touches the network | Declare only non-network caps: compiler enforces absence |
| Guarantee a function is completely pure | Declare no `needs`: the compiler verifies it |
| Let a plugin only read the clock | `cap_narrow` to `Cap(IO.Clock)` at the call site |
| Guarantee migrations run before any query | `proof cap Migrated` in `mod Db` |
| Prove a specific string has been sanitized | Opaque refined type (`ptype`), not a proof cap |
| Track that a file handle is open vs closed | `always_linear type` + `transitions` (typestate) |
| Exclude allocation/IO from a realtime callback | `Tagged(DSP, Realtime)` |
| Thread many caps without adding parameters | Capability environment record |
| Prove integer division can never panic | `cap no_panic` + Int refinements on divisor params |
| Guarantee zero heap allocation (realtime/embedded) | `cap no_alloc` |
| Small script, just want it to work | `needs IO`: don't overthink it |
