# Object capabilities for March

**Date:** 2026-11-10
**Status:** approved by the owner 2026-11-10
**Supersedes:** `specs/2026-11-09-dependency-grants-and-restrict-design.md` and
`specs/plans/2026-11-09-grants-restrict-roadmap.md`. Their `forge.toml` grants, `restrict`
blocks, path-scope rules and run-time context carry over; what changes is listed in §16.
**Builds on:** `specs/2026-11-09-host-scoped-network-capabilities-design.md` (host, path
and method scopes) and `specs/2026-11-09-narrow-capabilities-design.md` (scopes for every
other kind). Neither changes.

Lines marked **(owner)** are the owner's decisions from the 2026-11-10 discussion. Lines
marked **(my call)** are mine and are collected in §19 for the owner to check.

```march
mod Weather do
  needs IO.NetConnect                       -- an upper limit; it grants nothing

  type Client = Client(fetch : String -> Result(Forecast, Error))

  fn new() : Client do                      -- the closure captures the caller's authority
    Client(fn city -> HttpClient.get_json("https://api.weather.com/v1/" ++ city))
  end
end

mod Main do
  fn main() : () needs IO.Console, IO.NetConnect("api.weather.com/", "stats.example.com") do
    let weather = restrict IO.NetConnect("api.weather.com/v1/", methods(get)) do
      Weather.new()                         -- a client that can reach one path, GET only
    end
    Report.print(weather)                   -- Report needs no network line: it was handed the client
  end
end
```

---

## 1. Why

March's capabilities today are a manifest. A module's `needs` line says which kinds of
outside-world operation its own code may perform, the compiler checks it, and that is all:
any module that writes the line has the authority. There is nothing to hand to someone
else, nothing to hold back, and nothing that says where a piece of code got its authority
from. The owner wants March to move to a proper capability system (owner): authority is
something a piece of code *has been given*, it can pass on a narrower version, and code
that was given nothing can do nothing.

The dependency-grants design was a step there, but it kept "write `needs` and you have it"
as the base rule and bolted narrowing on top, with a separate capability-value feature
(`cap_narrow`, `Cap(X)` parameters) for libraries. That feature forces authority through
parameter lists, which the owner has ruled out twice (the removed per-function ceiling,
and again here). This design replaces the base rule instead.

## 2. Goals, non-goals, anti-goals

**Goals**

- **Authority is given, not declared.** It starts at `main`, granted by whoever launches
  the program, and reaches other code only by a call, a function value, an actor or a
  handle (§3).
- **`needs` is an upper limit and nothing else** (owner). Writing it grants nothing.
- **No threading and no parameterised modules** (owner). Authority follows calls on its
  own; nobody adds a parameter to pass it along.
- **Every capability kind**, not only network clients (owner): files, sockets, listeners,
  processes, foreign libraries, tables, environment, console, tasks.
- **Objects carry authority.** A closure, an actor and a handle each carry exactly the
  authority they were created with, and handing one to other code hands over that
  authority and no more.
- **One scope language** in four places: `needs`, `restrict`, `forge.toml` grants, and
  scope values (§8).
- **A static layer**: function types say what they capture, so the compiler can show where
  authority goes and reject what it can see (owner: "acceptable", with `needs c` on public
  higher-order signatures) (§13).

**Non-goals**

- Linear handles. The existing typestate `Handle(r, s)` and `always_linear` stay as they
  are; the handles here are ordinary values.
- Revocation. Nothing in this design takes authority back from a value that already has
  it (§9 says how to build that from an actor when wanted).
- Constraining C reached through `extern`, or cluster peers. A node trusts the nodes it
  is clustered with; pids and messages arriving from them are the runtime's.
- Proof capabilities (`proof cap`, `mint_cap`). A separate feature; unchanged (§14).

**Anti-goals**

- Any way to gain authority: by writing a `needs` line, building a string, forging an
  integer handle or pid, looking something up by name without a check, or calling a
  function value.
- A limit that a closure, a task or an actor created under it escapes later.
- A cost for programs that use no scopes, `restrict` or grants beyond one thread-local
  read per capability operation.
- A program restricted differently depending on how it runs (compiled, interpreter, REPL,
  JIT, JS).

## 3. The model

**Authority** is a set of scopes in the existing scope language, for example
`IO.Console, IO.NetConnect("api.weather.com/v1/", methods(get)), IO.FileRead("./data/")`.
Every running piece of code has a *current authority*. Every capability operation
(a builtin that touches the outside world) checks its target against the current authority
and returns `Err(CapError)` when it is outside.

**Where it starts.** `main` runs with what the launcher granted (§11). Nothing else creates
authority.

**How it moves.** Four ways, and no others:

| By | What the receiver gets |
|---|---|
| A direct call to a named function | The caller's current authority, narrowed by the callee's own `needs` clause if it has one |
| A function value (closure, named function used as a value, partial application) | The authority current where the value was made (§5) |
| An actor | Holding its pid is the right to send to it; the actor runs under the authority current where it was spawned (§7) |
| A handle | The one resource it names, for the operations the handle type offers (§6) |

**How it shrinks.** One operation: intersection with a list of scopes. Allowlists
intersect, limits such as `IO.Spawn(max(n))` take the smaller number, and an unscoped kind
survives only when both sides allow it. Three things perform it on the current authority,
and what they set holds for everything reached by direct calls from inside:

- a function's `needs` clause, around that function;
- a `restrict ... do ... end` block, around the block;
- a `forge.toml` grant, around every function in the dependency's package.

These are the same thing at three sizes (my call). A module's `needs` line is different
(owner, 2026-11-10): it limits only the operations the module's own code performs (§4)
and does not change the current authority. Nothing ever widens the current authority.

## 4. `needs` as a limit

```march
mod Uploader do
  needs IO.FileRead("./outbox/"), IO.NetConnect("files.example.com")
  fn push(name : String) : Result((), Error) do ... end
end
```

- An operation written in `Uploader` must pass two checks: it is inside the current
  authority (what the caller had), and it is inside `Uploader`'s `needs`. If the caller
  had no network authority, `Uploader.push` has none either, whatever its `needs` says.
- **A module's `needs` limits the module's own operations only** (owner, 2026-11-10).
  This is today's rule: the operations its code performs, including the ones it performs
  through the stdlib, which are charged to the calling module as now. A module that calls
  `Uploader.push` needs no line for it, an interface method is charged to the impl's
  module and not to the generic code between, and stdlib modules need no new lines.
- So `needs ()` on a module says "this module's code performs no outside-world operation
  itself", not "calling it is harmless". The transitive boundaries are a function's
  `needs` clause, `restrict` and grants.
- **A function's `needs` clause stays transitive**, as today: it bounds everything the
  function reaches by direct calls.
- **Function values are charged to nobody who calls them.** A function value runs under
  its own captured authority (§5). This is today's rule for per-function bounds
  ("callbacks are charged to whoever supplies them") made general, and it is how objects
  carry authority through code that declares nothing: `Report.print(weather)` in the
  opening example.
- A module with no `needs` line may perform no operation of its own, as today.
- The compile-time checks are today's ceiling and per-function-bound checks. Today's
  refusal of "untraceable" calls under a narrow function bound goes away: a call through
  a function value is never charged, so there is nothing to trace.
- At run time a module's scoped `needs` is checked only where the target is computed (the
  compiler has proved the literal ones); a module line never needs a frame on the
  current authority.
- Broad limits are cheap to write because they grant nothing. `needs IO.NetConnect` on an
  HTTP library lets it do whatever its caller allows.

## 5. Function values

A function value captures the current authority **at the point it becomes a value** and
runs under exactly that whenever and wherever it is called (my call on the details):

- A lambda captures where the `fn` expression is evaluated.
- A named function used as a value (`List.map(paths, File.read)`) captures where the name
  is used as a value, and then runs under that authority narrowed by its own limits. It
  behaves as `fn p -> File.read(p)` would.
- A partial application captures where it is formed.
- The caller's authority at the call plays no part: not added, not intersected. Calling a
  function value is using authority someone handed you.

Consequences, all intended:

- **A callback you pass to a dependency runs with your authority**, not the dependency's
  grant. This reverses the superseded design, which ran callbacks under the dependency's
  grant because it could not tell callbacks apart. Capture makes the difference visible.
- **A closure made inside a `restrict` block keeps the narrowed authority after the block
  ends.** That is how attenuated objects are made (the `weather` client above).
- **A closure made outside a `restrict` block and called inside it keeps its outside
  authority.** Passing it in was a deliberate handover. To stop it, do not pass it in.
- Stored function values (in a record, a list, a table, an actor's state) keep their
  authority. A named table that holds closures is therefore a channel for authority, and
  is guarded by the check on opening the table by name (§6).

**Cost.** A function value whose body reaches no capability operation and no spawn stores
nothing extra. One that does stores a reference to its captured authority and enters it in
its own prologue, so call sites pay nothing. Representation is the builder's.

## 6. Handles

Every operation that opens a resource returns an opaque value that only that operation can
produce. Using the handle needs no `needs` line and no check against the current
authority: the open was checked.

| Kind | Open (checked against current authority) | Handle | Uses that need no authority |
|---|---|---|---|
| Files | `File.open(path, mode)` | `File.Handle` | read, write, seek, close |
| Directories | `File.open_dir(path)` | `File.Dir` | open or list beneath it (my call) |
| Outbound connections | `Tcp.connect`, the HTTP client's connection | `Socket` | send, receive, close |
| Listening | `Tcp.listen(addr)` | `Listener` | accept (yields a `Socket`), close |
| Child processes | `Process.spawn(...)` | `Process` | wait, kill, its pipes |
| Foreign libraries | `Foreign.open(lib)` | `Library` | the symbols the scope admitted |
| Named tables | `Vault.new(name)`, `Vault.whereis(name)` | `Vault(v)` (already typed) | get, put, delete |
| Actors | `spawn` | `Pid(a)` | send (§7) |
| Environment, console, clock, random | none: each use is checked | — | — |

- **Path-based conveniences stay** (`File.read(path)`, `File.write(path, s)`): they are an
  open, a use and a close, checked as an open.
- **A directory handle is authority over its subtree** (my call): `File.open_in(dir, rel)`
  opens beneath `dir` with no `needs`, refusing any path that leaves it (same path rules
  and symlink handling as scopes). A module with `needs ()` that is handed a `File.Dir`
  can work in that folder and nowhere else.
- **Representation** (my call): a reference-counted box holding the descriptor and a
  closed flag. A use after close returns `Err`. The raw integer builtins become
  stdlib-only (the existing `check_stdlib_only_refs` gate).
- **Names must not collide** with the stdlib's typestate `Handle(r, s)`; the new types are
  `File.Handle`, `File.Dir`, `Socket`, `Listener`, `Process`, `Library`.
- **Scoped opens.** `File.with_open(path, mode, fn h -> ...)` closes at the end; the
  static layer (§13) makes letting `h` out of the callback a compile error, and before
  that layer exists a use after the close is a run-time `Err`.
- **Handles are not sendable to another node** (my call). Within a node, sending a handle
  in a message shares it.
- **Lookups by name are opens.** `Vault.whereis("sessions")` is checked against
  `IO.Mut("sessions")` (narrow-capabilities §7). `actor_whereis`, `actor_register` and
  `actor_registered` are checked against a new kind `IO.Registry("name", prefix("..."))`
  (my call): finding an actor by name is gaining a capability by string, and registering a
  name can impersonate one.

## 7. Actors and pids

- **A pid is a capability** (my call). Holding a `Pid(a)` is the right to send it
  messages; a send checks nothing else. A closure that captures a pid captures the pid,
  not the actor's authority.
- **An actor runs under the authority current at its `spawn`**; its handlers'
  operations are charged to the module that defines it. A message does not carry the sender's authority (owner,
  2026-11-09: actors are their own principals). So a restricted block can log through an
  unrestricted logger actor it was handed, and a worker spawned inside `restrict` is
  restricted for life.
- **A supervisor restart restores the authority of the first spawn**, kept on the child's
  runtime record.
- **Tasks** (`Task.async` and the rest) take a function value, so they run under what it
  captured.
- **Pids cannot be forged.** `pid_of_int` is already stdlib-only. `Actor.pid_from_int`,
  which today takes a `Cap(Actor.Introspect)`, becomes a checked operation under the kind
  `Actor.Introspect` (my call), for debuggers and observers.
- **Own-behalf authority** (a logger that writes its file whoever calls it, a cache with
  its own table) is an actor or a closure created where that authority exists and handed
  to the code that should use it. There is no way to lend authority to a *module*.

## 8. The scope language and scope values

The grammar is the `needs` grammar with every form from the two scope designs
(`IO.NetConnect("host/path/", methods(get))`, `IO.Env(prefix("WEATHER_"))`,
`IO.Exec("git", args(...))`, `IO.Spawn(max(16))`, ...). It appears in:

1. module `needs` lines and function `needs` clauses;
2. `restrict` blocks;
3. `forge.toml` `grant` strings, and launcher grants (§11);
4. **scope values**:

```march
let build_tools = IO.Exec("cc", "ar") + IO.FileRead("./src/") + IO.FileWrite("./_build/")

restrict build_tools do
  Builder.run(target)
end
```

- A scope value has type `Scope`. It is data: a description of a limit. Holding one grants
  nothing; its only use is as the argument of `restrict` (and of `mock`, §12).
- `+` is union of two scope values. Arguments may be computed
  (`IO.FileRead(project_dir ++ "/src/")`); a computed argument is validated when the value
  is built, and an invalid one (a path with `..`, a malformed host) makes the constructor
  return `Err` (my call: `IO.FileRead(e)` with a non-literal `e` has type
  `Result(Scope, ScopeError)`; with literals only it is a `Scope`).
- A `restrict` with a computed scope is checked at run time only; with literals the
  compiler also checks the block's static reach, as before.

## 9. `restrict`

Syntax and meaning are the superseded design's §5, unchanged: `restrict` is a new keyword
(parser, tree-sitter grammar, keyword allowlist); the argument is a comma-separated scope
list, `()` for none, or an expression of type `Scope`; the body is a `do ... end` block
and the whole is an expression. The block and everything it reaches by direct calls run
under the intersection. Nested blocks intersect. Any code may restrict itself.

What is new follows from §5: function values, tasks and actors **created** inside keep the
narrowed authority; function values and pids **brought in** from outside keep theirs.

- `IO.Spawn(max(n))` in a `restrict` is a separate budget for tasks started under that
  block, in addition to any outer limit (my call).
- **No revocation.** When the block ends, values created inside keep what they captured.
  This is sound because it is never more than the creator had. Code that wants to take
  access back hands out a pid to a forwarding actor and stops the actor.

## 10. Dependency grants

`forge.toml` syntax and meaning carry over from the superseded design's §4:

```toml
[deps]
weather  = { version = "2.0", grant = ['IO.NetConnect("api.weather.test/v1/", methods(get))'] }
uploader = { git = "...", grant = ['IO.NetConnect("files.example.com")', 'IO.FileRead("/srv/uploads")'] }
legacy   = { path = "../legacy" }          # no grant: only its own `needs` limits it
```

- A grant is a limit around every function defined in the dependency's package. Reached
  code only; a reached violation the compiler can see is a build error naming the
  dependency, the `forge.toml` line, the target and the call chain; unreached code costs
  nothing.
- A transitive dependency reached by direct calls from a granted one runs under that grant
  (it is inside the limit), and under its own grant too if the consumer gives one.
- An `extern` reached in a granted dependency needs `IO.Foreign` in the grant.
- A module belongs to the package whose library directory its file's real path is in;
  the same module name in two packages is a build error under any grant.
- `forge audit` and `forge.caps.lock` show and record grants. The grant set is part of
  every cache key that can skip a check (compile CAS, `check_all_cache_key`,
  `build_islands`, the per-file type-environment cache).
- **Changed:** a callback you pass to a granted dependency runs with your authority (§5),
  and an object the dependency hands back (a closure, a pid, a handle) carries the
  dependency's narrowed authority wherever it goes.
- **Changed:** with authority now given rather than declared, a dependency with no grant
  still cannot exceed its caller. A grant is for holding it to *less* than the code that
  calls it.

## 11. `main` and the launcher

- **`main`'s own `needs` clause is what the program asks for** (my call):

  ```march
  fn main() : () needs IO.Console, IO.FileRead("./data/") do ... end
  ```

  This is the existing function-level syntax. A `main` with no clause asks for what its
  module's `needs` line says; with neither, nothing. The whole program's static reach must
  sit under it, which is today's `cap_grant_exceeded` check.
- **`fn main(cap : Cap(IO.Console))` is retired** in favour of the clause. `forge fix`
  rewrites it; the old form is accepted with a deprecation warning for one release.
- **The launcher grants what `main` asks for, or less, never more.** `march run`,
  `forge run` and a compiled binary grant the request in full by default. An operator
  narrows it with `--grant 'IO.NetConnect("api.weather.com/")'` on `march run` and
  `forge run`, and with the `MARCH_GRANT` environment variable for a compiled binary
  (my call: a binary's own arguments belong to the program). A narrowed launch is a
  run-time limit: an operation outside it returns `Err`.
- The OS sandbox (`--sandbox`, the narrow-capabilities per-child narrowing) stays as the
  outer layer and is derived from the granted authority, not the requested one.
- `IO.Foreign` still requires an unnarrowed launch unless scoped
  (narrow-capabilities §6).

## 12. Tests: `mock`

```march
test "forecast parses" do
  mock IO.NetConnect("api.weather.com/") with FakeWeather.handler do
    let c = Weather.new()
    assert(c.fetch("oslo") == Ok(Forecast(...)))
  end
end
```

- `mock SCOPE with HANDLER do ... end` (my call) replaces `with_cap` and `cap_impl` on IO
  capabilities. Inside the block, an operation whose target falls in the scope goes to the
  handler instead of the outside world, and the block has authority for that scope whether
  or not the test was launched with it.
- It follows the same capture rule as everything else: closures, tasks and actors created
  inside keep the mock.
- Test builds only (`march test`, `--test`); a compile error elsewhere.
- The handler's shape per kind follows today's operation dictionaries (`cap_ops`); the
  builder's. `vault_*` operations become mockable through this route, which they are not
  today.

## 13. The static layer: capture checking

The run-time rules above are complete on their own. The static layer makes them visible in
types and turns what the compiler can see into build errors. **It gets its own design
document before it is built**; this section fixes the surface the owner agreed to and what
earlier phases must not rule out.

- **Function types carry what they capture**: `String -> () needs IO.FileWrite("./out/")`.
  A handle is named directly: `() -> String needs h`.
- **Higher-order functions are polymorphic in it**:

  ```march
  fn map(xs : List(a), f : a -> b needs c) : List(b) needs c
  ```

  A public signature must write this (owner). A bare `a -> b` in a public signature means
  a function that captures nothing. Private functions and local values are inferred.
- **Data that holds function values**: the capture set attaches to the value's type, not
  to a type parameter (my call). With `type Client = Client(fetch : String -> Forecast)`,
  the value `Weather.new()` has type
  `Client needs IO.NetConnect("api.weather.com/v1/", methods(get))`.
- **Escape is an error**: a scoped handle (`File.with_open`'s `h`) cannot leave its
  callback, by itself or inside a closure.
- **What stays at run time**: any scope whose argument is computed, and launcher
  narrowing.

Earlier phases must keep this possible: the run-time capture rule (§5) is exactly what the
types will describe, and stdlib higher-order functions must not inspect or alter the
authority of the function values they are given.

## 14. What is retired and what stays

**Retired**

- `Cap(IO.*)` values and parameters, including on `main`.
- `cap_narrow`, and the superseded design's phase 8 (capability values for libraries).
- `with_cap` and `cap_impl` on IO capabilities, replaced by `mock`.
- "A module that writes `needs X` has X."
- "Callbacks run under the dependency's grant."
- The refusal of untraceable calls under a narrow per-function bound.

**Stays**

- The scope language and every scope form in both scope designs.
- Per-function `needs` clauses and the compile-time ceiling, now with one meaning (§4).
- Proof capabilities: `proof cap`, `mint_cap`, dictionaries on a program's own
  capabilities. They prove protocol facts and never touched IO.
- Typestate `Handle(r, s)`, `always_linear`, linear types.
- The OS sandbox.

## 15. Refusals, every runtime, cost

- **Refusal is an error value**: every capability operation returns `Result(T, CapError)`
  (owner, 2026-11-09). `CapError` names the refused scope and the limit that refused it
  (which `restrict`, module, grant or launch).
- **Every runtime the same** (owner, 2026-11-09): the C runtime, the interpreter, the JIT
  and the JS runtime implement the current authority, capture and the checks, and one
  conformance suite runs every enforcement test on all of them, the way
  `test/run_test_reports.exe` pins identical output today. The compile-time checks run
  under `march --check`, the interpreter and the REPL, not only `--compile`.
- **The stdlib's own connections**: as the superseded design. The check sits at the
  stdlib's public entry points, which know host, path and method; the raw primitives
  beneath are stdlib-only variants that do not re-check; a test lists every public
  function that reaches one and fails when a new one lacks a check.
- **Files**: every open checks its path at run time; relative paths resolve against the
  current directory at the call; `openat2(RESOLVE_BENEATH)` on Linux, `realpath` plus
  `O_NOFOLLOW` on macOS (best effort, documented).
- **Cost.** The current authority is one reference per green thread. A capability
  operation reads it and, when it is the launch authority with no scope on that kind,
  passes at once. A limit needs a run-time frame only where it is scoped and the code
  under it performs an operation of that kind with a target the compiler cannot see;
  everywhere else the compile-time check already proved it and no frame is emitted
  (my call). Entering the limit already in force is a no-op, and a tail call replaces the
  frame entry rather than stacking one. A program with no scopes, `restrict`, grants or
  narrowed launch therefore pays one thread-local read per operation and nothing per call.

## 16. What changes from the superseded design

| Superseded design | This design |
|---|---|
| A module's `needs` gives it that authority | `needs` only limits; authority comes from the caller |
| A module's `needs` covers its own operations | The same; unchanged (owner, 2026-11-10) |
| Callbacks run under the dependency's grant | Function values run under the authority they captured |
| Lambdas inside `restrict` enter its frame | Every function value captures where it is made (same result inside `restrict`, now general) |
| `Cap(X)` parameters and `cap_narrow` for libraries | Closures, actors and handles; no capability parameters |
| Opaque file and socket handles | Handles for every kind that opens something; directory handles |
| `main`'s grant is its `Cap` parameters | `main`'s `needs` clause, narrowed by the launcher |
| Test mocks through `with_cap` | `mock ... with ... do` |
| No static story for function values | Capture checking (§13) |

Everything else in that document (path-scope rules, `restrict` syntax, grant syntax,
`forge audit`, caches, packages, symlinks, `Result` everywhere, every runtime) holds.

## 17. Migration and phasing

**Migration.** Breaking, pre-1.0, each step with a `forge fix` rewrite and a
`### Changed` CHANGELOG entry (my call on the list):

- Module `needs` lines do not change. A program whose `main` asks for less than its
  modules use gets a diagnostic naming the operation and the chain.
- `fn main(cap : Cap(X))` becomes `fn main() : () needs X`; `Cap(IO.*)` parameters that
  were only passed along are removed.
- Integer file, socket and process handles become the handle types.
- `with_cap` tests become `mock` blocks.
- With the static layer: `needs c` is added to public higher-order signatures, the
  stdlib's (`List`, `Map`, `Seq`, `Task`, `HttpServer` handlers) in the same change.

**Phases.** Each ships on its own.

| # | Phase | Depends on | Old roadmap # |
|---|---|---|---|
| 1 | Every capability operation returns `Result` | — | 2 |
| 2 | Handles for every kind (§6), raw integer builtins stdlib-only, name lookups checked | — | 3, widened |
| 3 | Compile-time checks under `--check`, the interpreter and the REPL | — | 5 |
| 4 | Run-time authority in every runtime: current authority, limits as intersection, capture by function values, spawn and restart, `main`'s `needs` and launcher narrowing, the conformance suite | 1, 2 | 4, widened |
| 5 | `restrict` and scope values | 3, 4 | 6 |
| 6 | Dependency grants | 3, 4 | 7 |
| 7 | `mock`; retire `Cap(IO.*)`, `cap_narrow`, `with_cap`; `Actor.Introspect` as a kind | 4 | replaces 8 |
| 8 | Capture checking (own design document first; that document can start now) | 4 | new |

Old phase 1 (path scopes) is done. The narrow-capabilities design refers to "phase 2"
(`Result`) and "phase 4" (run-time context); those are phases 1 and 4 here.

## 18. Testing (shape)

- **No authority from a declaration**: a module with `needs IO.NetConnect` called from a
  caller without it is refused, at build time when the chain is visible and at run time
  when it is not. A module with `needs ()` may call a module that does IO; a generic
  `needs ()` module may call an interface method whose impl logs.
- **Capture**: a closure made under `restrict` and called outside is still narrowed; one
  made outside and called inside is not; a named function used as a value behaves as the
  equivalent lambda; a partial application likewise; a closure stored in a record, a list
  and a table keeps its authority.
- **Callbacks**: a callback passed to a granted dependency keeps the caller's authority;
  a closure the dependency returns has the grant's.
- **Handles**: a handle works in a module with `needs ()`; an integer cannot be turned
  into one (type error); use after close is `Err`; `File.open_in` refuses `..`, an
  absolute path and a symlink leaving the directory; a lookup by name outside the scope is
  refused.
- **Actors**: sending to a handed-in pid needs nothing; an actor spawned under `restrict`
  stays narrowed across a supervisor restart; `Actor.pid_from_int` without
  `Actor.Introspect` is refused.
- **`main` and the launcher**: reach beyond `main`'s `needs` is a build error; `--grant`
  and `MARCH_GRANT` narrower than the request refuse at run time; one wider than the
  request is an error at launch.
- **Scope values**: union, a computed argument, an invalid computed argument is `Err`.
- **`mock`**: the handler is reached from a closure and an actor created inside; a `mock`
  outside a test build is a compile error.
- **Carried over** from the superseded design's §9: path scopes, `restrict`, grants,
  files, with the callback case reversed.
- **Every enforcement test on every backend** with the same outcome.
- **No-scope programs**: IR unchanged apart from the per-operation check
  (`scripts/ir-oracle.sh`), `bench/` HTTP and file benchmarks within noise, and
  `bench/list_ops.march` (closures) within noise.

## 19. My calls, for the owner to check

Most important first.

1. **Module-level code** (§21): top-level `let`s run under the launch authority narrowed
   by the module's `needs` and its package's grant; a function value created there
   captures nothing. (The earlier first item, transitive module limits, was decided by
   the owner on 2026-11-10: own operations only, §4.)
2. **A function value runs under its captured authority alone** (§5), which makes
   callbacks into dependencies run with the caller's authority.
3. **`main`'s `needs` clause is the program's request; the launcher may narrow it**
   (`--grant`, `MARCH_GRANT`) (§11).
4. **Pids are capabilities**, and `Actor.pid_from_int` becomes a checked `Actor.Introspect`
   operation (§7).
5. **Name lookups are checked**: a new `IO.Registry` kind for `actor_whereis`,
   `actor_register`, `actor_registered` (§6).
6. **Directory handles** as authority over a subtree (§6).
7. **`mock SCOPE with HANDLER do ... end`** replaces `with_cap` on IO capabilities;
   proof capabilities are untouched (§12, §14).
8. **Scope values**: type `Scope`, `+` for union, a computed argument yields a `Result`
   (§8).
9. **Capture sets attach to a value's type**, not to a type parameter (§13).
10. **No revocation**; `IO.Spawn(max(n))` in a `restrict` is a separate budget (§9).
11. **Handles**: reference-counted box with a closed flag; not sendable across nodes (§6).
12. **Frames only where the compiler could not prove the limit** (§15).
13. **The migration list and the phase order** (§17).

## 20. Left to the builder

How a captured authority is represented and when a function value can skip storing one;
the encoding of an authority and of a frame; where each builtin's check sits (C runtime or
the March wrapper); the forge → compiler channel for grants; the `mock` handler shape per
kind; diagnostic codes and wording; `CapError`'s variants; the exact names of the handle
operations; how long the deprecated `main(cap : Cap(X))` form is accepted.

## 21. Revisions after the builder check

A fresh reader asked five questions. One went to the owner and is decided; the rest are
settled here as my calls.

**Decided by the owner (2026-11-10)**

- **A module's `needs` limits its own operations only.** The first draft made it
  transitive over direct calls. The check showed what that cost: an interface method
  called from a generic `needs ()` module would have been refused when its impl logs
  (the reverse of today's rule), about 100 of the 139 stdlib modules would have needed
  `needs` lines or an exemption, and every intermediate module would have gained a line.
  §3, §4, §16, §17 and §18 now describe the own-operations rule.

**Settled (my calls)**

- **Module-level code.** A module's top-level `let`s run under the launch
  authority narrowed by the module's `needs` and its package's grant, so existing
  top-level effects keep working; but a function value created there captures nothing and
  behaves as a named function (it runs under its caller's authority). Otherwise a
  dependency could park a closure holding launch authority at top level, and any
  `restrict`ed caller could use it. An actor spawned at top level does keep that
  authority: it is the own-behalf service of §7, bounded by the grant.
- **Launches without a `main`.** A test file's request is its module's `needs` line, and
  `march test` grants it; doctests likewise; an `app` declaration's request is its
  module's `needs`; the REPL runs with the full authority of the person at the terminal.
  `--grant` narrows all of them.
- **Interface methods** are direct calls to named functions: an impl runs under its
  caller's authority, and its operations are charged to the impl's module. The generic
  module in between does not bound it.
- **Other consumers of `Cap(IO)`.** A choreography `role R needs ...` becomes a limit
  around the role's body, with no generated `Cap` parameters; `--dump-role-authority`
  stays. The functions that take `Cap(IO)` as a composition-root witness (`Actor.debug`,
  `Actor.introspect`, `Session.attach`, `ClusterNode.attach`, `ClusterNode.start`) become
  checked operations, each under its own kind requested in `main`'s `needs`
  (`Actor.Debug`, `Actor.Introspect`, and one for sessions and clustering; names are the
  builder's). The non-IO capabilities they return stay as they are. This is phase 7.
- **Across nodes.** An authority travels as its scope list. A function value, task or
  actor that arrives on or is started on another node runs under the sender's authority
  intersected with the receiving node's launch authority. Path scopes are re-resolved on
  the receiver. So one hop never widens anything. Phase 4 includes the wire format.
