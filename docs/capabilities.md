---
layout: docs
title: Capabilities
nav_order: 5.6
permalink: /docs/capabilities/
---

# Capabilities: March's Effect & Capability System

March is a **capability-based language**: side effects are **visible in your types** — zero runtime overhead, enforced at compile time. This guide explains what capabilities are, when to reach for each kind, when to leave them alone, and how they compose.

---

## The problem they solve

In most languages, a function's signature tells you what data flows in and out. It says nothing about what the function *does to the world*:

```python
# Does this read a file? Call the network? Write to a database?
# You have to read the implementation to find out.
def compute_price(product_id: str) -> float:
    ...
```

That invisibility causes three recurring problems:

**Accidental effects.** A function you thought was pure secretly calls a logger, which opens a file, which fails in a read-only sandbox. You find out at runtime.

**Unclear contracts.** "Does this library ever write files?" requires reading all the source. No amount of documentation fully substitutes for a machine-checked declaration.

**Audit blind spots.** Answering "which modules talk to the network?" in a large codebase means grepping and hoping — unless the compiler tracks it.

March's capability system addresses all three. Effects appear in the type, and the compiler traces them through the call graph. An uncovered capability is a hard, build-breaking error — whether `Cap(X)` flows through a signature or a function body simply calls an IO builtin directly (the latter was advisory until 2026-08-06). What that does and does not guarantee is stated once, canonically, under ["What the compiler tells you"](#what-the-compiler-tells-you) below; the rest of this page just refers back to it. To *audit* what a dependency or a compiled binary actually holds — rather than what a module declares — see [Capability Audit]({{ site.baseurl }}/docs/capability-audit/).

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
| Guarantee a function is pure | Declare nothing — absence enforces it |
| Prove initialization ran before dependent code | Proof caps (`proof cap`) |
| Prove a specific value has been processed | Opaque refined type (`ptype`) |
| Track a resource's open/closed/consumed lifecycle | Typestate (`always_linear type` + `transitions`) |
| Exclude allocation/IO from a realtime callback | Specialization tag (`Tagged(X, Realtime)`) |
| Thread many capabilities without parameter explosion | Capability environment record |

---

## IO capabilities

Every module that touches external resources declares `needs`:

```march
mod Server do
  needs IO.Network

  fn listen(cap : Cap(IO.Network), port : Int) : () do
    ...
  end
end
```

The compiler enforces this transitively **when the capability flows through a signature**:
`Server.listen` takes `Cap(IO.Network)` as a parameter, so any module that `use`s
`Server` and calls `listen` must itself declare `needs IO.Network` (directly or via a
broader ancestor, e.g. `needs IO`), or the build fails with a clear message telling you
which import requires which cap — e.g. a `Caller` module `use`ing `Server` without
`needs IO.Network` gets `` module `Caller` imports `Server` which requires
`Cap(IO.Network)`, but `IO.Network` is not declared in `needs`. `` (This signature/`use`/`extern`
surface is the hard-error side of the line drawn in ["What the compiler tells you"](#what-the-compiler-tells-you).)

### Propagation is demand-driven

You inherit only what you actually reference.
Importing a module costs you the capabilities of the *functions you reference from
it*, not the imported module's whole set. So importing `List` to call `map` costs
nothing, even though `List.pmap` spawns tasks; you would only owe `needs IO.Spawn`
if you actually referenced `pmap`. The reference set is exact — a function passed as
a value counts, and a capability a referenced function reaches only through a private
helper still counts — and it is computed per import site, so two modules importing
the same library can owe different capabilities.

This rule only ever requires **less** than the older module-granular one, so no
module that compiles today can start failing because of it. One conservative
carve-over errs toward requiring more: an import whose target has not been
analyzed yet, because the two modules import each other cyclically, falls back
to the imported module's whole declared set.

**What counts as a capability's source.** Every declaration form that can hold
an expression is recorded, not just `fn` bodies: `fn` signatures and bodies,
guards, default-argument expressions, actor handlers, `extern` blocks,
module-level `let` bindings, interface default methods, and `impl` methods. So a
function whose only impure act is to read a module-level `let` that prints does
owe `IO.Console`, and so does anything that imports it for that function. Any
path through an ordinary function or a builtin call is counted as well. (Before
2026-08-06 the last four forms had no per-function record, which could silently
drop a capability along a transitive path; see
`specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md`.)

### Capability hierarchy

`Cap(IO)` is the root. Sub-capabilities narrow what is allowed:

```
IO
├── IO.Console          — stdout/stderr (println, print)
├── IO.FileSystem
│   ├── IO.FileRead     — read files, list directories
│   └── IO.FileWrite    — write, delete, rename files/dirs
├── IO.Network
│   ├── IO.NetConnect   — outbound TCP, WebSocket
│   │   ├── IO.NetConnect.TLS  — encrypted transport (tls_connect, tls_accept, …)
│   │   └── IO.Database †  — database connections (child of NetConnect)
│   └── IO.NetListen    — bind + listen on a port
├── IO.Process          — env vars, child processes, process exit
├── IO.Clock            — wall clock, monotonic time
├── IO.Random           — CSPRNG (random_bytes, uuid_v4)
├── IO.Signal           — OS-signal watchers (Signal.watch/unwatch/raise)
├── IO.Spawn            — task spawning (task_spawn, task_spawn_link, …)
├── IO.Mut              — shared mutable state (Vault tables)
├── IO.Telemetry †      — telemetry/observability emission
└── IO.Foreign          — calling unverified C (extern blocks)
    └── IO.Foreign.Blocking — blocking extern (spawns OS thread)
```

**†  declaration-only** — the compiler accepts the `needs` as a surface-contract
annotation but does not scan for specific builtins behind it (there is no dedicated
builtin set to attribute to it). It makes the concern visible to callers; it is not
enforced by a body scan the way the other capabilities are.

A module that declares `needs IO` can pass `Cap(IO)` to any function that requires a narrower cap. Use `cap_narrow` to produce a sub-capability — it's free, compile-time only:

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
| No external state, no I/O | *(nothing — pure by declaration)* |
| Print to stdout/stderr | `needs IO.Console` |
| Read files or directories | `needs IO.FileRead` |
| Write, delete, or rename files | `needs IO.FileWrite` |
| Read **and** write files | `needs IO.FileSystem` |
| Outbound TCP or WebSocket | `needs IO.NetConnect` |
| Outbound HTTPS only — no plaintext TCP | `needs IO.NetConnect.TLS` |
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
route it takes to being uncovered no longer changes the severity — that changed
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
imported module as a whole — see ["Propagation is demand-driven"](#propagation-is-demand-driven).)

**A direct body call to an IO builtin**, with no `Cap(X)` anywhere in a
signature, is now the same severity:

```
$ march --check reader.march   # fn slurp(path) do file_read(path) end — no needs
-- ERROR -- function body calls a builtin that requires `Cap(IO.FileRead)` but `Reader` does not declare `needs IO.FileRead`.
help: add `needs IO.FileRead` to the module body.
$ echo $?
1
```

The error carries a machine-applicable fix, so `forge fix` will insert the
`needs` line for you.

#### What this does and does not guarantee

Worth being precise about, because the error above invites a stronger reading
than it earns:

- It catches a **direct** call to a capability builtin — `file_read(p)`.
- It does **not** catch the same operation routed through a stdlib wrapper —
  `File.read(p)`. That call is invisible to this check, and `--check` exits 0.
- The complete check is the **capability ceiling**, below, which works on
  **emitted code** and therefore cannot be evaded by re-routing through a
  helper. It is on by default, but it runs on the compile path — so `--check`
  alone still exits 0 on the stdlib-mediated call.

So `needs` is a **mandatory, mechanically-verified manifest** of the builtins a
module calls directly — not, on its own, proof that a module cannot reach a
capability. That comes from the ceiling, which means it comes from `march
--compile`, not from `--check`.

It is also worth separating two things the word "capability" covers here: this
check makes you *declare* what you touch. It does not make anyone *grant* it —
`needs` is a self-declaration, and any module may write any `needs` line. IO
builtins take no capability argument.

### The capability ceiling — on by default
{#cap-strict}

`needs` is a ceiling as well as a floor: the build fails if **any** module's
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
call through a stdlib wrapper like `File.write`, and a builtin handed out as a
value all collapse into the same rule. Re-routing a call through a helper does
not evade it.

**It applies per module, including dependencies that never opted in.** March
dependencies ship as source, so the check runs on your build of their code. A
dependency declaring only `needs IO.Console` whose helper reads `/etc/passwd`
fails your build. You do not need the publisher's cooperation.

**It fails closed.** A capability the compiler cannot attribute to any module —
reached only through an indirect call — is reported as a violation rather than
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

To re-check the same ceiling on a binary you did not build, see
[`forge cap inspect --strict`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary).

### When *not* to use IO capabilities

**Pure functions need nothing.** If a function hashes a string, parses JSON, sorts a list, or formats a number, write no `needs`. Since 2026-08-06 the absence of `needs` is machine-verified for direct builtin calls as well as the signature/`use`/`extern` surface — a module calling an IO builtin in a body without declaring it is rejected, not warned. The one route still outside that check is a stdlib-mediated call; see ["What the compiler tells you"](#what-the-compiler-tells-you).

**Don't over-narrow to look principled.** Declaring `needs IO.FileRead` when your function also writes is a lie the compiler will catch. If a function reads and writes, `needs IO.FileSystem` is correct even if it feels "less precise." Accurate beats narrow-but-wrong.

**Don't use IO caps for pure domain concepts.** A function that validates an email address or checks a constraint has no business with capabilities. Capabilities exist for external state, not for logic.

**Don't use capabilities for per-value guarantees.** `Cap(IO.FileRead)` proves a module is *allowed* to read files; it says nothing about whether a specific string value came from a trusted source. For per-value guarantees, use an opaque refined type.

**Small scripts: just use `needs IO`.** For a 50-line script you'll run once, fine-grained capability declarations add more friction than value. Use `needs IO` at the top and move on. The value of narrow caps emerges in larger codebases with multiple contributors over time.

---

## Specific IO capabilities

### IO.Mut — shared mutable state

`IO.Mut` covers Vault tables — process-global shared mutable hash maps. A module with no `needs IO.Mut` is statically proven never to touch shared mutable state:

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

### IO.NetConnect.TLS — encrypted transport only

`IO.NetConnect.TLS` is a child of `IO.NetConnect`. Declaring it (without `IO.NetConnect`) proves the module uses *only* encrypted connections — no plaintext TCP. Declaring `needs IO.NetConnect` covers both.

```march
mod HttpsClient do
  needs IO.NetConnect.TLS  -- plaintext TCP is statically excluded

  fn fetch(fd, h, host) do
    tls_connect(fd, h, host)
  end
end
```

### IO.Telemetry — observability annotation

`IO.Telemetry` is declaration-only: the compiler accepts it as a semantic annotation but does not scan for specific builtins. Use it to make telemetry visible in a module's surface contract so callers know this module emits observability data:

```march
mod Metrics do
  needs IO.Telemetry

  fn record_request(duration : Int) : () do
    ...
  end
end
```

### IO.Foreign — calling unverified C

`IO.Foreign` is a meta-capability triggered by the **presence of an `extern` block** — not by any specific builtin call. C code bypasses every March type guarantee, so the compiler requires you to acknowledge this explicitly.

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

`needs IO.Foreign` alone subsumes `IO.Foreign.Blocking` (parent covers child), so one declaration suppresses both warnings if you prefer coarser annotations.

---

## Behavioral module caps — `cap no_panic`, `cap no_alloc`, `cap no_extern`, `cap pure`, `cap deterministic`

Beyond IO permission caps and proof caps, March has five *behavioral* capability declarations that trigger static analysis passes rather than IO-permission accounting. They share only the `cap` keyword with `needs`/`Cap(X)` — a module can declare `cap no_panic` and separately declare `needs IO.Network`, and the two mechanisms never interact. Each lives as a bare `cap <name>` statement in the module body.

### `cap no_panic` — guaranteed panic-free

```march
mod SafeMath do
  cap no_panic

  fn divide(a : {v : Int | v >= 0}, d : {v : Int | v > 0}) : Int do
    a / d
  end
end
```

A module with `cap no_panic` must not contain any expression that can panic at runtime. The compiler enforces this with three sub-checks:

1. **Panic-surface check** — every call that could panic must be ruled out. How a given name is ruled out depends on whether it has a refinement contract to check against:

   - **No contract possible → unconditional ban, with transitive blame.** `panic`, `panic_`, `todo_`, `unreachable_` panic by definition; no precondition could ever make them safe, so calling one is an error wherever it appears. This ban is *transitive*: a local helper that calls one makes every local caller of that helper panicky too, and each caller gets its own error.
   - **No contract yet → unconditional ban, with transitive blame.** `Array.get` / `Array.set` panic out of bounds and `Array.pop` panics on an empty vector; none carries a refinement today, so all three are still banned by name exactly as above. (`Array.pop` was missing from this list until 2026-08-05 and compiled clean inside `cap no_panic` — a call that can genuinely panic passing a capability that promised it cannot.)
   - **Has a contract → checked by proof.** The prelude partials (`unwrap`, `expect`, `head`, `tail`, `last`) and the contracted stdlib partials (`List.nth`, `List.head`, `List.last`, `List.tail`, `List.maximum_int`, `List.minimum_int`, `Option.unwrap`, `Option.expect`, `Result.unwrap`, `Result.expect`, `Result.unwrap_err`, `Random.normal`, `Random.exponential`, `Random.bernoulli`, `Random.choice`, `Random.choice_weighted`, `DateTime.fixed_zone`, `DateTime.fixed_zone_hm`, `Stats.mean`, `Stats.min_val`, `Stats.max_val`, `Stats.percentile`, `Stats.quantile`, `Stats.quantiles`, `Stats.five_number_summary`, `Stats.variance`, `Stats.mode`, `Stats.covariance`, `Stats.correlation`, `Stats.linear_regression`) each declare a refinement precondition that says exactly when they panic. A call to one of these is checked against that precondition, by the same solver and the same verdicts that discharge division safety — no separate proof mechanism. If the call site's precondition is **proved**, the call compiles clean:

     ```march
     mod Safe do
       cap no_panic
       -- Accepted: the guard proves `len(xs) > 0`, which is List.tail's contract.
       fn rest(xs : List(Int)) : List(Int) do
         if List.length(xs) > 0 do List.tail(xs) else xs end
       end
     end
     ```

     Anything short of proved is an error — refuted, undecided, unreflectable, or no obligation recorded at all. `cap no_panic` is a *guarantee*, so "the checker could not tell" is a rejection, not silence (this is the opposite of the definite-failure stance refinement checking uses elsewhere). An `@[trusted]` annotation does **not** count as proof here either: it is an unchecked assertion, and `cap no_panic` promises more than disclosure.

     `Random.choice_weighted`'s contract, `{List((a, Float)) | len(_) > 0}`, only covers the *empty-list* panic. The same function also panics if every weight is zero or if any weight is negative — both depend on the *values* in the list rather than a structural property like length, so no measure can express them, and they stay outside `cap no_panic`'s proof-based check (a call whose weights the checker cannot see can still panic at those two conditions even when `cap no_panic` accepts the call). The same split runs through `Stats.covariance`, `Stats.correlation` and `Stats.linear_regression`: their two *structural* panics are contracted (`xs : {List(Float) | len(_) >= 2}` and `ys : {List(Float) | len(_) == len(xs)}` — the second is a precondition on one parameter that references a sibling parameter's measure, the same shape `List.nth`'s `n : {Int | _ >= 0 && _ < len(xs)}` already uses), while `Stats.correlation`'s zero-standard-deviation panic and `Stats.linear_regression`'s zero-variance panic are data-dependent and stay outside the check. A `cap no_panic` module calling `Stats.correlation` with two proven-equal-length lists of 2+ constant elements compiles clean and still panics at runtime.

     `Stats.percentile` and `Stats.quantile` each carry **two** independent preconditions — the `xs : {List(Float) | len(_) > 0}` added here alongside a pre-existing range check on the second parameter (`p ∈ [0, 100]` or `q ∈ [0, 1]`). Both must be proved at a call site; guarding only one still errors. The two are checked and reported independently (one obligation per refined parameter), so a call that guards the list length but not the probability, or vice versa, gets exactly the error naming the unguarded one. (`Stats.quantiles`'s second parameter, `qs`, is a plain unrefined `List(Float)` — a batch of levels validated per-element by a runtime `panic` inside `List.map`, not a type-level precondition — so `quantiles` carries only the one `xs` precondition added here.)

   **`march check` and `march caps` are deliberately more conservative than `march --compile` / `march --check` for the contracted names.** Proving a call safe requires the refinement checker, and `march check` is a package-level, typecheck-only pass that does not run it (nor does the editor/LSP). With nothing to consult, "cannot prove" has to mean "reject", so those tools keep banning the contracted names by name — including the transitive blame described below. A guarded `List.tail` therefore compiles clean under `march --check` and is still reported by `march check`. This is the pre-2026-08-05 behavior preserved, not a new restriction: nothing that used to pass `march check` fails it now. Use `march --check <file>` when you want the proof-based answer.

   The same applies to editor squiggles, with one wrinkle: the language server reports panic-surface errors for a `cap no_panic` module **nested** inside another `mod`, but not for a top-level one — that gap predates this change and is unrelated to it. Where the editor does report, it reports the conservative answer, so a guarded `List.tail` can be underlined in your editor and still compile clean. Trust `march --check`, not the squiggle, for the contracted names.

   **Behavior changes (2026-08-05).** Both apply to the contract-covered names, in the pipelines that run the proof-based check:

   - **No more transitive blame.** Before, an unprovable `List.tail(xs)` inside a helper produced one error at the helper *and* one at every local caller of it. Now it produces exactly ONE error, at the real call site — matching how division safety has always reported. If you are wondering why an error you used to see on a caller has "moved" to the callee, this is why. `panic`/`panic_`/`todo_`/`unreachable_` and `Array.get`/`Array.set`/`Array.pop` keep their transitive blame unchanged.
   - **One error per call site, not per function.** The old check reported at most one panic-surface error per function, whichever call it happened to find first. The proof-based check decides each call on its own, so a function containing two unprovable `List.tail` calls now reports two errors instead of one. Nothing new is being rejected — the same function was already rejected — you simply see every offending call at once instead of fixing them one round-trip at a time.
2. **Division safety** — proves every integer divisor is non-zero via the Z3 SMT solver. The rule of thumb: a divisor is discharged by a literal, by an enclosing `if`/`when` guard (read through `&&`/`||`/`not`, on either branch), or by an `Int` refinement on the parameter it came from; anything the solver can't settle is a conservative error. The precise guard semantics (how conjunctive and disjunctive facts discharge, let-bound divisors, rebinding) live in [Refinement Types → `cap no_panic`]({{ site.baseurl }}/docs/refinement-types/#cap-no_panic--divisions-that-cant-panic).
3. **Non-exhaustive `match` ban** — inside a `cap no_panic` module, a `match` that doesn't cover every constructor is an ERROR, not just the ordinary non-blocking exhaustiveness warning every other module gets: an uncaught pattern is a runtime panic ("no matching clause"), and `cap no_panic` exists precisely to rule that class of failure out.

When Z3 is absent, `cap no_panic` is still conservatively enforced — unverifiable divisions are treated as errors.

**Use `Math.checked_div` / `Math.checked_mod`** when you cannot prove the divisor non-zero statically; they return `Option(Int)` instead of panicking.

### `cap no_alloc` — no heap allocation

```march
mod RealTimeDSP do
  cap no_alloc

  fn mix(a : Float, b : Float, gain : Float) : Float do
    (a + b) * gain
  end
end
```

`cap no_alloc` walks every function body and flags heap-allocating expressions:

| Allocating expression | Error |
|-----------------------|-------|
| `ETuple` with ≥1 items | tuple construction allocates |
| `ERecord` | record construction allocates |
| `ECon` with ≥1 args (e.g. `Some(x)`) | boxed constructor allocates |
| `ELam` | lambda/closure allocates |

Nullary constructors (`None`, `True`, `False`, custom zero-arg tags) and unit `()` are safe — they compile to immediate integer tags with no heap allocation.

The check recurses into sub-expressions inside `if`, `match`, `let`, blocks, etc.

### `cap no_extern` — no foreign calls

```march
mod NoFFIService do
  cap no_extern
  needs IO.Network

  fn ping(_cap : Cap(IO.Network), host : String) : Int do
    string_length(host)
  end
end
```

A module with `cap no_extern` may not contain an `extern` block and may not declare `needs IO.Foreign` — either one is an immediate error. Useful for a module that must stay pure C-free code, e.g. because it needs to run somewhere `extern`'s FFI trust boundary isn't available.

### `cap pure` — no side effects at all

```march
mod PureMath do
  cap pure

  fn add(a : Int, b : Int) : Int do
    a + b
  end
end
```

A module with `cap pure` bans every call to a builtin that performs any side effect — file IO, network IO, spawning, sending, vault access, console output, randomness, the clock — as well as `spawn`/`send`/`exit`. The banned set is derived from the same authoritative builtin-to-capability table (`builtin_cap_table`) the ordinary IO-cap body-scan check consults, so it stays in sync with the real builtin surface — a module declaring `cap pure` and calling `file_write` is rejected:

```
$ march --check leaky_pure.march   # cap pure; fn write(...) : Result(Unit, String) do file_write(path, contents) end
-- ERROR -- `write` in `mod LeakyPure` (declared `cap pure`) calls `file_write`, which has side effects.
$ echo $?
1
```

### `cap deterministic` — no clock, no randomness

```march
mod DeterministicSim do
  cap deterministic

  fn checksum(bytes : String) : Int do
    string_length(bytes)
  end
end
```

`cap deterministic` is **strictly weaker than `cap pure`**: it bans only the two nondeterminism sources — wall-clock/monotonic-clock reads and random-number generation — so a `cap deterministic` module may still perform ordinary IO such as `file_read`, as long as it never touches the clock or an RNG:

```
$ march --check clock_leak.march   # cap deterministic; calls unix_time_ms(())
-- ERROR -- `now` in `mod DetLeak` (declared `cap deterministic`) calls `unix_time_ms`, which is non-deterministic.
$ echo $?
1
```

### Choosing among the five

| I want to… | Use |
|------------|-----|
| Prove no integer division can panic, and rule out non-exhaustive matches | `cap no_panic` + Int refinements on divisor params |
| Guarantee safe use in a realtime audio callback | `cap no_alloc` (+ `Tagged(DSP, Realtime)` for the calling site) |
| Keep a module free of C/FFI trust-boundary crossings | `cap no_extern` |
| Guarantee a module has zero side effects, not just no IO caps declared | `cap pure` |
| Guarantee reproducible output — no clock, no RNG — while still allowing ordinary IO | `cap deterministic` |
| Both — pure, panic-free, zero-alloc | `cap no_panic` and `cap no_alloc` together |

All five declarations can coexist in the same module. Each is checked by its own independent pass, and none of them subsumes or implies any other.

---

## Capability inference hints

If you call a function that requires a `needs X` declaration but your module doesn't have one, the compiler emits a **hint** (not an error) pointing to the call site:

```
hint: this call uses IO.FileRead but mod Config does not declare `needs IO.FileRead`.
hint: add `needs IO.FileRead` to the module body.
```

This is informational and **not necessarily backed by a type error** — a hint on a
plain body call can appear on a program that otherwise checks clean, so it is the whole
story in that case, not a preview of a rejection. See ["What the compiler tells
you"](#what-the-compiler-tells-you) for exactly when a hint is instead backed by a hard
error.

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

`AppConfig` is provably read-only. `Api` cannot read files and cannot use plaintext TCP. If `AppConfig.load` ever called a network function, the build would fail until `needs IO.NetConnect` was added — no audit needed.

---

## Runtime behaviour

All `Cap(X)` values are **runtime-erased**. They compile to `null` in LLVM IR and to `VUnit` in the interpreter. No allocation, no indirection, no overhead. Enforcement of the capability *types* is purely at compile time — but a compiled binary can additionally turn its declared set into a kernel-enforced sandbox at startup, and a running node can gate hot deploys against it. Both live on their own page: see [Capability Enforcement]({{ site.baseurl }}/docs/capability-enforcement/) (OS-level sandboxing via `forge cap run` / `--cap-sandbox`, and node-local hot-deploy admission control).

---

## Proof caps — encoding initialization order

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

`Cap(Db.Migrated)` is **unforgeable** — every claim below is compiler-enforced:
- `cap_narrow` cannot produce it — enforced, not merely "not in the IO hierarchy": `cap_narrow`'s result may never be a nominal proof cap in *any* expression position (it only attenuates IO caps).
- The runtime-provided `Cap(IO)` in `main()` cannot produce it — the only mint is `mint_cap`, and `mint_cap` is gated.
- Only public (`fn`) functions of `mod Db` can `mint_cap` it — private (`pfn`) functions may pass it through but cannot construct one.
- External code can pass it through, but cannot construct one — and no polymorphic launder through a nested unannotated helper can erase the cap type either (the deeper forge, closed by the nested-module soundness fix).

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
    -- `mint_cap` outside the declaring module is rejected.
    fn bad(cap : Cap(IO)) : Cap(Db.Migrated) do mint_cap(cap) end

    -- ERROR: cap_narrow can no longer forge a proof cap in any position.
    fn steal(cap : Cap(IO)) : Cap(Db.Migrated) do cap_narrow(cap) end

    -- OK: pass-through is allowed
    fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
  end
end
```

The sanctioned way to mint a proof cap is the gated `mint_cap` primitive, which only
typechecks inside a public `fn` of the declaring module and is erased at runtime;
`cap_narrow` can never produce a proof cap, in any position, since it only attenuates
ordinary IO caps.

> **Known gap:** a `cap_narrow` result wrapped in a container through a polymorphic
> factory function can still forge a proof cap in some shapes. This is narrow and not
> yet closed — avoid laundering a narrowed IO cap through a generic container factory
> if you're relying on proof-cap unforgeability for a security-sensitive boundary.

### When to use proof caps

Proof caps suit **ambient, payload-independent facts** — things true about the *system*, not about a specific value:

| Proof cap | Meaning |
|-----------|---------|
| `Cap(Db.Migrated)` | Database migrations have run |
| `Cap(Auth.Authenticated)` | The current request has a verified identity |
| `Cap(App.Initialized)` | Application startup has completed |
| `Cap(Config.Loaded)` | Configuration has been validated |

The key test: **is there a single, well-defined place in the codebase that produces this capability?** If yes, a proof cap works cleanly. If initialization is diffuse, conditional, or happens in multiple places, a proof cap will feel awkward — use a runtime flag instead.

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

A `Cap(Sanitized)` would prove "some string was sanitized somewhere," but not that the string you're about to render *is* the one that was sanitized. The opaque type ties proof and data together — you physically cannot pass an unsanitized string to `render`.

**Don't use proof caps when there's no single mint point.** Unforgeability is only meaningful when the minting surface is small and auditable. If the initialization is spread across many code paths, the cap gives a false sense of safety.

---

## Typestate — tracking resource lifecycle

IO caps answer "is this module allowed to open a file?" Typestate answers "is *this specific handle* currently open or closed?"

### `Handle(R, S)` from the standard library

`stdlib/handle.march` ships a canonical typestate handle:

```march
always_linear type Handle(r, s) = Handle(Int)
```

The `r` parameter is a phantom *resource tag* and `s` is the current *state*. Because `Handle` is `always_linear`, dropping it without consuming it — or consuming it twice — are both compile-time errors.

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

### `tag` — zero-arg phantom label types

`tag Foo` is shorthand for `type Foo = Foo` — a zero-argument phantom type for state labels and resource tags:

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
- Simple flags or booleans that change frequently at runtime — the type parameter overhead isn't worth it
- Cases where the lifecycle state is dynamic and not known until runtime

The LSP shows typestate hover — hovering any `Handle(R, S)` expression displays the current state and all declared transitions from it.

---

## Advanced patterns

### Specialization tags — realtime exclusion

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

`Tagged` also covers type-indexed specialization (SIMD widths, buffer sizes) — monomorphization handles these for free:

```march
fn fft(cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
-- monomorphization produces fft_256, fft_1024, etc.
```

### Capability environment records — reducing parameter count

When many functions need the same bundle of capabilities, threading individual `Cap(X)` parameters everywhere is tedious. Bundle them into a record instead:

```march
type RuntimeEnv = {
  io    : Cap(IO),
  clock : Cap(IO.Clock),
  net   : Cap(IO.Network)
}

fn run(env : RuntimeEnv, data : Input) : Output do ... end
```

Narrow to a restricted set by constructing a smaller record — the type system enforces what the callee can do structurally:

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

`Cap(X)` values are runtime-erased, so you cannot swap them in tests. Pair the cap with a function field for swappable runtime behaviour:

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
| Prove a module never touches the network | Declare only non-network caps — compiler enforces absence |
| Guarantee a function is completely pure | Declare no `needs` — the compiler verifies it |
| Let a plugin only read the clock | `cap_narrow` to `Cap(IO.Clock)` at the call site |
| Guarantee migrations run before any query | `proof cap Migrated` in `mod Db` |
| Prove a specific string has been sanitized | Opaque refined type (`ptype`), not a proof cap |
| Track that a file handle is open vs closed | `always_linear type` + `transitions` (typestate) |
| Exclude allocation/IO from a realtime callback | `Tagged(DSP, Realtime)` |
| Thread many caps without adding parameters | Capability environment record |
| Prove integer division can never panic | `cap no_panic` + Int refinements on divisor params |
| Guarantee zero heap allocation (realtime/embedded) | `cap no_alloc` |
| Small script, just want it to work | `needs IO` — don't overthink it |
