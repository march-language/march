---
layout: docs
title: Capabilities
nav_order: 5.6
permalink: /docs/capabilities/
---

> Part of the March Language Reference — see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Capabilities

March makes side effects **visible in your types** — zero runtime overhead, enforced at compile time. This guide explains what capabilities are, when to reach for each kind, when to leave them alone, and how they compose.

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

March's capability system addresses all three. Effects appear in the type, and the compiler traces them through the call graph — with one honesty caveat worth stating up front: the *absence* of a capability declaration is a machine-verified, build-breaking guarantee **wherever `Cap(X)` flows through a signature** (a function/actor/extern parameter, or a transitive `use` of another module that requires one) — that surface is enforced as a hard error. A module that calls an IO builtin directly in a function *body*, without ever threading a `Cap(X)` through any signature, is instead flagged with a warning-level hint: informative, but `--check` still exits 0. See "What the compiler tells you," below, for both sides of that line, live-verified.

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

The compiler enforces this transitively **when the capability flows through a signature** — Check 4: `Server.listen` takes `Cap(IO.Network)` as a parameter, so any module that `use`s `Server` and calls `listen` must itself declare `needs IO.Network` (directly or via a broader ancestor, e.g. `needs IO`), or the build fails with a clear message telling you which import requires which cap (verified live: a `Caller` module `use`ing `Server` without `needs IO.Network` gets `` module `Caller` imports `Server` which requires `Cap(IO.Network)`, but `IO.Network` is not declared in `needs`. ``, exit 1). This ERROR-level guarantee is the signature/`use`/extern surface (Checks 1, 4, and 5) — see "What the compiler tells you," below, for the separate, weaker case where a module reaches for an IO builtin directly in a function body without ever putting `Cap(X)` in a signature.

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
│   │   └── IO.Database — database connections (declaration-only; child of NetConnect)
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

There are two severities, and which one you get depends on *where* the uncovered capability shows up — this honest distinction matters, so it's stated explicitly rather than glossed over.

**Signature, transitive `use`, or `extern` — a build-breaking ERROR (`--check` exits 1).** If `Cap(X)` appears in a function/actor/extern parameter, or you `use` a module that itself needs a capability you haven't declared, there is no way to ship without fixing it:

```
$ march --check caller.march   # `use`s a module needing Cap(IO.Network), no `needs IO.Network` of its own
-- ERROR --
module `Caller` imports `Server` which requires `Cap(IO.Network)`, but `IO.Network` is not declared in `needs`.
help: add `needs IO.Network` to the module body.
$ echo $?
1
```

**A direct body call to an IO builtin, with no `Cap(X)` anywhere in a signature — a WARNING (`--check` exits 0).** The compiler still tells you exactly what's missing and how to fix it — this is genuinely useful, actionable feedback — but it does not fail the build:

```
$ march --check reader.march   # fn slurp(path) : Result(String, String) do file_read(path) end — no needs
-- HINT --    call to `file_read` requires `needs IO.FileRead` — add `needs IO.FileRead` to module `Reader`
-- WARNING -- function body calls a builtin that requires `Cap(IO.FileRead)` but `Reader` does not declare `needs IO.FileRead`.
$ echo $?
0
```

Follow the hint either way — it's always correct, and cleaning up the warning keeps a module's `needs` list an accurate account of what it does. But **don't rely on the warning to block a merge or a release**: it won't. If you need "this module absolutely cannot read files" as a hard, CI-enforced guarantee, thread `Cap(IO.FileRead)` through the relevant signatures so the violation lands on the ERROR side of this line, not the WARNING side.

### When *not* to use IO caps

**Pure functions need nothing.** If a function hashes a string, parses JSON, sorts a list, or formats a number, write no `needs`. The absence of `needs` is a machine-verified guarantee of the ERROR-level kind above **only for the signature/`use`/`extern` surface** — the compiler cannot force you to declare a capability that never appears in a signature and is never transitively required by an import, so this guarantee is strongest when the functions in question actually take `Cap(X)` parameters (or `use` something that does). A module with no `needs` that calls IO builtins purely in function bodies will typecheck (`--check` exits 0) with only advisory warnings, not a rejection — see above.

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

1. **Panic-surface check** — every call that could panic must be ruled out. Which of two mechanisms does the ruling out depends on whether the name has a refinement contract to check against:

   - **Syntactic ban** (`check_no_panic_module`, `lib/typecheck/typecheck.ml`) for names with no contract: explicit `panic`/`panic_`/`todo_`/`unreachable_` (no precondition could ever make them safe) and `Array.get`/`Array.set`/`Array.pop` (no contract exists for them, and the 2026-08-05 feasibility gate found none can currently be discharged — `Array.length` is a scalar constructor-field read, which call-site reflection erases). Direct *and* transitive: a local helper that calls one of these makes every local caller of that helper panicky too, computed as a fixpoint over the module's own functions, and each caller gets its own error.
   - **Proof-based check** (`lib/refinecheck/panic_surface_by_proof.ml`) for names that carry a real refinement precondition: the prelude partials (`unwrap`, `expect`, `head`, `tail`, `last`) and the contracted stdlib partials (`List.nth`, `List.head`, `List.last`, `List.tail`, `List.maximum_int`, `List.minimum_int`, `Option.unwrap`, `Option.expect`, `Result.unwrap`, `Result.expect`, `Result.unwrap_err`, `Random.normal`, `Random.exponential`, `Random.bernoulli`, `Random.choice`, `Random.choice_weighted`, `DateTime.fixed_zone`, `DateTime.fixed_zone_hm`, `Stats.mean`, `Stats.min_val`, `Stats.max_val`). A call to one of these is checked against its declared precondition:

     ```march
     mod Safe do
       cap no_panic
       -- Accepted: the guard proves `len(xs) > 0`, which is List.tail's contract.
       fn rest(xs : List(Int)) : List(Int) do
         if List.length(xs) > 0 do List.tail(xs) else xs end
       end
     end
     ```

     The check does not discharge anything itself — building a second VC generator would let it drift from the real one. It reads the per-call-site verdict `Refine_check` already recorded (`Obligation.obligations_at`, filtered to `Precondition` obligations for that callee, folded weakest-wins), which is why the pass runs after `Refine_check.check_module` rather than inside the typechecker: the verdict index does not exist until then. `bin/main.ml` calls it right after `Division_safety.check_module`.

     **Only `Proved` is silent.** `Violated`, any `Skipped`, `Trusted`, and "no obligation was recorded at this site" all produce the panic-surface error, with the same message text the syntactic ban uses. `cap no_panic` is a guarantee, so fail-closed is the only sound direction — this deliberately inverts the definite-failure stance the refinement checker uses elsewhere. `Trusted` (an `@[trusted]` assertion, which `cap verified` does accept) is on the error side on purpose: honouring an unchecked assertion inside a capability whose purpose is to guarantee no panics would hollow out the guarantee.

     **Not every panic on a covered name is covered.** `Random.choice_weighted`'s contract, `{List((a, Float)) | len(_) > 0}`, refines only the empty-list panic — the one structural precondition the type system can express. The same function also panics when every weight is zero (weights sum to zero) or when any weight is negative; both are data-dependent, turning on the *values* inside the list rather than a structural property like its length, so no measure exists that could express them, and they are deliberately left out of scope. A `cap no_panic` module that calls `Random.choice_weighted` with a proven-non-empty but all-zero-weight list still compiles clean and still panics at runtime — the capability's guarantee covers only the empty-list case. `Stats.linear_regression`'s zero-variance panic and `Stats.correlation`'s zero-stddev panic are the same shape and, for the same reason, are not on the contracted-names list at all.

   **Which mechanism applies is a per-pipeline decision, controlled by `Typecheck.proof_based_panic_surface`.** March has three check pipelines and only two run refinecheck:

   | pipeline | runs `Refine_check`? | contracted names |
   |---|---|---|
   | `bin/main.ml` compile / `--check`, and `run_test_cmd` (`march test`) | yes | checked by proof |
   | `bin/main.ml` `run_check_cmd` (`march check`, `march caps`) | no — package-level, typecheck-only, seeded from a cached stdlib env | banned by name, with transitive blame (pre-2026-08-05 behavior) |
   | the LSP (`lsp/lib`) | no — it does not link `march_refinecheck` | same as above |

   The LSP's coverage is uneven in a way worth knowing before reading too much into an absent squiggle. `Analysis` goes through `Typecheck.check_module_with_env`, which — unlike `check_module_core` — does **not** call `check_no_panic_module` on the **entry** module, so a top-level `cap no_panic` module gets no panic-surface diagnostic from the editor for *any* name, `panic` included. A **nested** `mod` does: `check_decl`'s `DMod` branch calls `check_no_panic_module` on the inner declarations. So editor squiggles for the contracted names exist for nested modules only, and it is the `proof_based_panic_surface` default above that keeps them there — the LSP has no verdict index and so must ban by name. Pinned by the `cap no_panic diagnostics` group in `lsp/test/test_lsp.ml`, whose fixtures are nested for exactly this reason.

   The flag **defaults to false** (ban by name) and the two proof-capable paths opt in, so a pipeline that forgets to opt in gets the conservative answer. `cap no_panic` is a guarantee, so a checker with no verdict index must reject rather than stay silent. The visible consequence: `march check` reports a guarded `List.tail` that `march --check` accepts. That is the old behavior preserved, not a new restriction.

   **Behavior changes (2026-08-05, Task 3 of the no-panic proof-based plan)**, in the proof-capable pipelines:

   - **Contract-covered names no longer seed the transitive fixpoint.** An unprovable `List.tail(xs)` inside a helper used to produce one error at the helper and one at every local caller; it now produces exactly ONE error, at the real call site, matching how `Division_safety` has always reported. Removing these names from the ban list alone would not have achieved that — they had to be removed from what SEEDS `check_no_panic_module`'s fixpoint, *and* from the `local_fns` set that fixpoint walks: `bin/main.ml` unwraps prelude into the entry module, so prelude's own `fn tail`/`head`/`last`/`unwrap`/`expect` are `DFn`s of the module under check, and their bodies call `panic`. Left in, they blamed every caller of a bare spelling transitively — rejecting calls the proof pass had just proved safe, since a transitive verdict never consults one. If an error appears to have "moved" from a caller to the callee, this is why. `panic`/`panic_`/`todo_`/`unreachable_` and `Array.get`/`Array.set`/`Array.pop` keep their fixpoint unchanged.
   - **One error per call site, not per function.** `check_no_panic_module`'s `site_map` held a single site per function, so at most one panic-surface error was reported per function. The proof-based pass decides each call independently, so a function with two unprovable `List.tail` calls now reports two errors where it reported one. Nothing new is rejected; every offending call is simply named at once.
2. **Division safety** (`lib/refinecheck/division_safety.ml`) proves every integer divisor is non-zero via the Z3 SMT solver — a separate pass from (1), gated on the same `cap no_panic` flag. Both literal divisors (`a / 0` → immediate error) and variable divisors are handled:
   - Variable with an Int refinement `{v | pred}`: Z3 discharges `pred ⊢ v ≠ 0`; fast syntactic short-circuit for common patterns (`v > 0`, `v >= 1`, `v != 0`, `v < 0`).
   - Let-bound variable: Z3 discharges `var = rhs ⊢ var ≠ 0` with param assumptions injected.
   - **Enclosing `if` guards count**, on either branch (`path_proves_nonzero`, a syntactic check that runs before any VC is built, so the obvious cases still discharge with no solver present): `if d != 0 do n / d else 0 end` needs no refinement at all, and neither does the `else` side of `if d == 0 do 0 else n / d end`. Guards are read through `&&`, `||` and `not`, carrying polarity by De Morgan — a conjunctive fact is discharged by either side, a disjunctive one only when *both* sides prove the divisor non-zero independently. So `if p > 0 && d > 0 do n / d` and `if p <= 0 || d <= 0 do 0 else n / d end` discharge, while `if p > 0 || d > 0 do n / d` correctly does not. Note the z3 route cannot substitute for this: a bare-`Int` divisor never reaches a VC, and in the refined arm `consts_declared` drops any path condition mentioning an unrefined parameter.
   - No refinement or unsupported expression: conservative error.
3. **Non-exhaustive `match` ban** — a `cap no_panic` module containing a `match` that does not cover every constructor is now (as of this widening slice's F3 fix) also an ERROR, not just the ordinary non-blocking exhaustiveness warning every other module gets: an uncaught pattern is a runtime panic ("no matching clause"), and `cap no_panic` exists precisely to rule that class of failure out. The fix wires the exhaustiveness checker's own verdict into `check_no_panic_module`, so a plain (non-`cap no_panic`) module's non-exhaustive match is untouched — still a warning, still `--check` exit 0.

When Z3 is absent, `cap no_panic` is still conservatively enforced — `Unverified` outcomes are treated as errors.

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

`no_alloc.ml` walks every function body and flags heap-allocating expressions:

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

**A fix landed in this reference's widening slice:** both `cap pure`'s and `cap deterministic`'s banned-builtin sets used to be hand-maintained name lists that referenced builtins spelled wrong or that never existed (e.g. `write_file`, `random_int`, `now_ms`) while missing the real ones (`file_write`, `random_bytes`, `unix_time_ms`) — so `cap pure`/`cap deterministic` silently failed to catch the most common effectful calls. Both sets are now derived from the compiler's single authoritative effect map, closing that gap; the fix does not change either cap's intended meaning, only which calls it actually catches.

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

This is informational, and it is **not necessarily backed by a type error** — do not assume one is coming. The hint pass (`cap_infer.ml`) runs after typechecking and shares the same underlying builtin-capability table as the typechecker's own body-scan check, but that check is *itself* warning-level for a direct body call (see "What the compiler tells you," above): the type checker enforces `needs` as a hard error only for `Cap(X)` reaching a signature, a transitive `use`, or an `extern` block. A `cap_infer.ml` hint attached to a plain body call to an IO builtin, with no `Cap(X)` in any signature, can appear on a program that `--check`s clean (exit 0) — the hint and the warning are the whole story in that case, not a preview of a rejection.

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

All `Cap(X)` values are **runtime-erased**. They compile to `null` in LLVM IR and to `VUnit` in the interpreter. No allocation, no indirection, no overhead. Enforcement of the capability *types* is purely at compile time — but a compiled binary can additionally turn its declared set into a kernel-enforced sandbox at startup; see [OS-level enforcement](#os-level-enforcement--sandboxing-the-compiled-binary) below.

---

## OS-level enforcement — sandboxing the compiled binary

Capability *types* are checked at compile time and then erased (above). That verifies your March code, but it says nothing about what the process may do once it is running: an `extern` C call, a `dlopen`, or a raw syscall is past the point the compiler can see. This is the [`IO.Foreign`](#ioforeign--calling-unverified-c) boundary, and the gap [`forge audit`]({{ site.baseurl }}/docs/capability-audit/#what-this-does-and-does-not-prove) is explicit about not closing. March can close it at the OS level, turning the declared capability set into an actual confinement.

There are two mechanisms — one imposed on the process from outside, one built into it.

### `forge cap run` — externally imposed (the stronger one)

`forge cap run` launches a binary under a sandbox that *forge* installs before the program gets control:

```
$ forge cap run ./build/myapp                        # policy from the binary's own claim
$ forge cap run --allow-only IO.Console ./untrusted   # policy YOU choose
```

For a binary you do **not** trust, pass `--allow-only`: deriving the policy from the binary's own claim only tells you what it admits to, which is worthless against code trying to hide. Where a capability cannot be enforced by the platform's available primitive, `forge cap run` reports it as **advisory** per capability rather than pretending to enforce it. This is the stronger of the two mechanisms, because the launcher — not the code being confined — chooses the policy.

### `--cap-sandbox` — self-imposed (defense in depth)

Compiling with `--cap-sandbox` embeds a **deny-default** profile, derived from *this program's own* declared capabilities, that the binary installs on itself at startup before any user code runs:

```
$ march --compile --cap-sandbox -o build/myapp app.march
```

- **macOS** — a Seatbelt (SBPL) profile via `sandbox_init()`. Deny-default, then each declared capability opens a specific hole: `IO.FileWrite` allows writes (narrowed to the path scopes you declared, otherwise blanket), `IO.Network` allows sockets, `IO.Process` allows fork. `IO.FileRead` is **advisory** here — dyld must map system libraries before any user code exists, so the baseline allows reads unconditionally and a scoped read rule would be decorative.
- **Linux** — an unprivileged in-process **seccomp-bpf** filter (`PR_SET_NO_NEW_PRIVS` + `PR_SET_SECCOMP`). One syscall class is denied per *withheld* capability: no `IO.Network` blocks `socket`/`socketpair`, no `IO.Process` blocks `execve`/`execveat`, no `IO.FileWrite` blocks the write path — denied calls return `EPERM`. `IO.FileRead` is not enforced here either, because seccomp filters syscall *numbers*, not paths; path-scoped reads come from `forge cap run`'s mount namespace instead.

Installation **fails closed**: if the sandbox cannot be installed, the program refuses to run rather than continue unconfined.

`--cap-sandbox` is **opt-in defense-in-depth**, not a guarantee against a hostile *publisher* — whoever builds the binary chooses whether to compile it in, so a malicious author simply omits it. Its purpose is a binary *you* built and trust, deployed somewhere `forge` is not the launcher — under systemd, a supervisor, a container entrypoint — the exact case `forge cap run` cannot reach. When you control the launcher, prefer `forge cap run`.

Because both mechanisms confine the **whole process**, they bound even the code the compiler cannot see — `extern` C, `dlopen`, raw syscalls. They are the enforcement counterpart to [`forge cap inspect`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary): `inspect` *reads* what a binary holds; these *enforce* what it may do.

---

## Hot-deploy authorization — node-local admission control

When using `forge deploy hot` to upgrade a running application, the node has a second opportunity to enforce capability discipline at deployment time — after signature verification, before the new code is loaded.

> This section covers the **node-side policy gate**. There is also a **client-side monotonicity gate** — a deploy that widens a function's authority beyond the running version aborts unless you pass `--grant-cap`. Both gates, with a full worked example (a console-only handler that gains `file_write`, and how each gate responds), are in the [Hot Code Reload guide → Capability-safe deploys]({{ site.baseurl }}/docs/hot-code-reload/#capability-safe-deploys).

### How it works

A hot deploy activates only the **functions that changed** (each is sent as a separate signed activation message). For **each activated function**, `forge deploy hot` embeds that function's own inferred IO capabilities — the capabilities its own body actually requires — in the message. Admission is checked per activated function, not over the whole artifact. (This granularity matters: `--hot-reload` links the entire standard library, so a *whole-artifact* capability set would be dominated by the stdlib's footprint and identical for every app — useless for a policy. Gating on the changed function's own caps is what makes the policy discriminating.) The trust boundary is: the **base server binary is trusted** — the operator built and started it, with a policy — and each **hot-patched function** is what the gate governs.

The receiving node, for each activated function:

1. **Recomputes the capability set** — normalizes the function's declared caps and hashes them with BLAKE3, reproducing the digest that was signed during the deploy.
2. **Tamper-checks** — compares its computed digest to the signed value; a mismatch (`ERR cap_tamper`) aborts before dlopen. The tamper check is **unconditional** even when the function declares no capabilities: a genuinely cap-free function has the fixed digest `blake3("")`, so a stripped capability field on a signed message is detected rather than silently admitted.
3. **Applies the deployment policy** — if `MARCH_DEPLOY_POLICY` is set (a file path), the node verifies that every capability the activated function declares is subsumed by a capability listed in the policy; a capability outside policy (`ERR cap_policy <cap>`) aborts.

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

The policy is **authorization on a self-reported manifest** — a defense-in-depth layer, not a sandbox. A party with the signing key can lie about what capabilities the code uses. The node admission gate proves:

- The artifact was signed by the expected entity (Phase 4 ed25519 signature).
- The declared capability set has not been tampered with in transit (BLAKE3 tamper-check).
- The declared capabilities are within a static policy envelope (subsumption check).

It does **not** prove that the code actually *uses* only those capabilities — only that the manifest claims it does, and the claim is signed and untampered. Runtime enforcement via `cap no_panic`, `cap no_alloc`, FFI sandboxing, or OS-level confinement can provide stronger guarantees. For most deployments, the combination of compile-time capability verification + signed manifests + policy gates is sufficient.

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

`Cap(Db.Migrated)` is **unforgeable** — every claim below is compiler-enforced (widening slice 6, 2026-07-08):
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

> **Resolved (widening slice 6, 2026-07-08).** Earlier releases had two gaps here: the documented mint idiom didn't typecheck (a bare `()` at the end of a `Cap(Db.Migrated)`-returning body was rejected `expected Cap(Db.Migrated) but got ()`), and the mechanism that *did* work — `cap_narrow`, whose polymorphic return `Cap(a)` instantiated to any proof cap at the call site — was unrestricted, so any holder of an ordinary `Cap(IO)` could mint any proof cap by name with no covering `needs`. Both are now closed. The sanctioned mint is the gated **`mint_cap`** primitive (typechecks only inside a public `fn` of the declaring module; runtime-erased); **`cap_narrow` can no longer produce a proof cap** in any position; and the general nested-module type-erasure hole the deepest forge relied on (`consume(id(cap))`, laundering through a nested unannotated helper) is closed by the intra-module reference-soundness fix. See `specs/lang/core-march-types.md` §2.8.13 (proof-cap minting/forging/unforgeability) and §2.5.1 (`(T-QualRef)`) for the rule-numbered treatment and corpus witnesses. One narrow residual stays open — a `cap_narrow` result wrapped in a container through a polymorphic factory can still forge in some shapes (the taint tagger is non-recursive); tracked in `specs/todos/` under "Compiler: Capabilities/effects".

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
