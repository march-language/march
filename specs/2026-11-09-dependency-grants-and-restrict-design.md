# Dependency grants and `restrict` blocks

**Date:** 2026-11-09
**Status:** superseded 2026-11-10 by `specs/2026-11-10-object-capability-design.md` (its §16 lists what changed and what carries over)
**Builds on:** `specs/2026-11-09-host-scoped-network-capabilities-design.md` (host and
method scopes on `IO.NetConnect`, PR march-language/march#1213).

Two ways for the code that *uses* a dependency to decide what that dependency may do:

```toml
# forge.toml: the whole dependency, once
[deps]
vendor_sdk = { version = "1.4", grant = ['IO.NetConnect("api.vendor.test", methods(get, post))'] }
```

```march
-- in code: one call, narrower still
restrict IO.NetConnect("api.vendor.test/foo/", methods(get)) do
  VendorSdk.report("daily")
end
```

---

## 1. Why

Today a dependency's authority is whatever its own `needs` lines say. A hostile or careless
library declares `needs IO.NetConnect` unscoped and the program's author has no say short
of not using it. The owner's goal is granular control over how any code, especially code
they did not write, talks to the outside world (owner, 2026-11-09). Three concrete cases
drive this design (owner):

- **An API client dependency**, limited to one path and GET only.
- **A future dependency that does many web things**, limited to a subset.
- **A dependency that may GET and POST in general**, with one of its functions limited at
  the call to `GET /foo`.

## 2. Goals, non-goals, anti-goals

**Goals**

- **Per-dependency grants in `forge.toml`.** The dependency is compiled as if the grant
  were its whole authority (owner: "compile in the dep with only the granted authority").
  Every capability, not only network.
- **`restrict ... do ... end` blocks in code** that run a block, and everything it reaches,
  under a narrower authority (owner chose the block form over a `with_scope(...)` call, to
  match existing `do ... end` syntax).
- **Path scopes on `IO.NetConnect`**, below the host: `api.vendor.test/v1/weather/`.
  Needed by both features (owner's API-client case).
- **Reached code only.** A dependency's code the program reaches and that needs authority
  outside the grant is a **build error** naming the dependency, the call chain and the
  destination, including a hardcoded URL (owner). Code the program does not reach is not
  compiled in and costs nothing (owner).
- **No capability threading.** `restrict` needs no capability value in hand: narrowing
  never grants anything, so any code may restrict itself (owner agreed). This keeps
  March's rule that a capability parameter is never required just to satisfy the checker
  (the "R1 stage C" per-function ceiling was removed for forcing threading).
- **Capability values for libraries that want them.** A library may take a
  `Cap(IO.NetConnect)` parameter; the caller hands it a narrowed one with
  `cap_narrow(net, IO.NetConnect("..."))`, and the library holds exactly that authority.
  Opt-in for library authors; same machinery underneath.
- Opt-in per dependency: a dependency with no grant behaves as today.

**Non-goals**

- Per-function entries in `forge.toml` (owner: "could be messy"). Per-call limits live in
  code, with `restrict`.
- Widening. A grant or a `restrict` only narrows; it never gives a dependency or a block
  more than it would otherwise have.
- Constraining C reached through `extern` (outside the compiler's view; the OS-level egress
  proxy is a separate proposal).
- A scope on `main`'s grant (phase 2 of host scopes); this design should make it a thin
  layer, but does not ship it.

**Anti-goals**

- A grant that a dependency can escape by building a URL at run time, reading config,
  following a redirect, starting a task or an actor, or handing a closure back.
- A `restrict` whose limit silently disappears for a closure created inside it and called
  later.
- Making unrestricted code slower or making existing programs fail.

## 3. Path scopes (shared)

A host pattern may carry a path prefix: `api.vendor.test/v1/weather/`. Everything else
from the host-scope design (ports, `*.domain`, options) is unchanged.

- **Matching is by whole segment.** `/v1/weather/` admits `/v1/weather` and
  `/v1/weather/today`, not `/v1/weatherman`. The query string and fragment never count.
- **Normalization, then refusal.** Before matching, the request path is checked: any `.`
  or `..` segment, any `%2e`/`%2E`/`%2f`/`%2F`/`%5c`/`%5C`, any `\`, and any `//` make the
  request **refused**, not normalized (a server may normalize differently from us, which is
  how prefix checks get bypassed). A path scope is itself rejected at declaration if it
  contains any of these.
- **Run time always checks the path.** A literal prefix proves the host at compile time,
  but not the path: `"https://api.vendor.test/v1/weather/" ++ "../admin"` keeps the
  literal prefix and leaves the scope. So under a path scope every request is checked at
  send time by the guard (§6), and the compiler reports only the violations it can see
  (a literal URL or literal path outside the prefix).
- Raw connections (`tcp_connect`) show no path: like a method scope, a path-scoped host
  admits no raw connection.

## 4. Dependency grants (`forge.toml`)

```toml
[deps]
weather = { version = "2.0", grant = ['IO.NetConnect("api.weather.test/v1/", methods(get))'] }
uploader = { git = "...", grant = [
  'IO.NetConnect("files.example.com", methods(get, put))',
  'IO.FileRead("/srv/uploads")',
] }
legacy = { path = "../legacy" }          # no grant: held to its own `needs`, as today
```

- `grant` is a list of capability strings in `needs` syntax (the same parser), including
  host, path and method scopes and filesystem path scopes. `grant = []` grants nothing.
- **Meaning.** Every module of the dependency's package is compiled with the grant as its
  effective `needs`. The dependency's own declarations stay a sanity check: a capability
  the grant names but the dependency never declares is a warning ("granted but not
  needed"); a capability the dependency declares but the grant omits is fine unless
  reached.
- **Transitive dependencies.** Code of package B that runs because granted package A
  called it runs under A's grant too (§6): A cannot launder authority through B. B's own
  grant, if the consumer gives one, also applies (both hold). A transitive dependency the
  consumer does not mention gets no grant of its own.
- **The stdlib** reached from a granted dependency runs under that grant (it is how the
  dependency reaches the world).
- **Callbacks.** A function of yours that the dependency calls back runs under the
  dependency's grant too (it runs inside the dependency's call). It can only lose
  authority, never gain it. (My call: the alternative, restoring your authority for
  callbacks, needs the compiler to know which values are callbacks across the boundary.)
- **Errors.** A reached violation the compiler can see is a build error naming the
  dependency, the `forge.toml` line, the destination or capability, and the call chain
  from your code into the dependency:

  ```
  -- CAPABILITY -- forge.toml:4
  `weather` is granted IO.NetConnect("api.weather.test/v1/", methods(get)), but
  `Weather.Telemetry.ping` connects to `stats.weather.test`
  (Main.run → Weather.forecast → Weather.Telemetry.ping).
  hint: widen the grant, or stop calling `Weather.forecast`.
  ```

- **How forge passes it.** `forge build`/`run`/`test` already put each dependency's
  library directory on `MARCH_LIB_PATH`. It additionally passes each granted directory and
  its grant to the compiler (an environment variable or repeated
  `--dep-grant DIR=CAPS` flag; the builder's call). The compiler maps a module to its
  package by the source file's directory. The grant is part of the build's cache key.
- **`forge audit`** shows each dependency's grant beside what it declares, and
  `forge.caps.lock` records grants so a changed grant is visible in review.

## 5. `restrict` blocks

```march
restrict IO.NetConnect("api.vendor.test/foo/", methods(get)) do
  VendorSdk.report("daily")
end

restrict IO.NetConnect("files.example.com", methods(get)), IO.FileRead("/srv/in") do
  Sync.pull()
end

restrict () do           -- no capability at all: a pure region
  Parser.parse(untrusted)
end
```

- **Syntax.** `restrict` is a new keyword; the capability list is the `needs` grammar
  (`scoped_cap_path`, comma-separated, `()` for none); the body is a `do ... end` block and
  the whole is an expression whose value is the block's value. Allowed anywhere an
  expression is (owner chose this form). Needs a parser change, the tree-sitter grammar and
  the keyword allowlist.
- **Meaning.** The block, and everything it reaches while it runs, has the intersection
  of the current authority and the listed capabilities. Nested `restrict` blocks intersect.
- **Inside a granted dependency** too: a dependency may restrict itself.
- **Capability values.** `cap_narrow(c, IO.NetConnect("..."))` produces a narrowed value
  for libraries that take capabilities as parameters; inside the library its authority is
  that value's (the library's calls on it run under it as if in a `restrict`).

## 6. How the authority follows code (my call; the owner should check this)

Static checking alone cannot follow a callback passed in, a closure called after the block
ends, a URL built at run time, or a task or actor started inside. So both features use the
same two-part mechanism:

**1. A run-time authority context.** Each green thread carries a stack of authority
frames (encoded scopes, as the host-scope guard's spec string, extended to every
capability). **Every capability builtin and the stdlib network guard check the stack**
before acting: the effective authority is the intersection of the frames. With an empty
stack the check is one thread-local read and nothing changes, so unrestricted programs pay
almost nothing.

Frames attach to **code, not to call sites** (my call, after the builder check: call-site
push/pop missed function references, impl methods reached through generic code, actors a
dependency defines but the app spawns, and anything the inliner folds):

- **Every function defined in a granted package** enters its package's grant frame in its
  prologue unless that frame is already on top. So a dependency function runs under its
  grant however it is reached: called directly, passed as a value (`Dep.f`, a partial
  application), dispatched through an interface, run as an actor handler, or called back
  by a timer, a signal handler or an HTTP server. Inserted before `Opt.run`, so inlining
  carries the frame entry with the body.
- **A `restrict` block** pushes its frame for the block's dynamic extent, and **every
  lambda written inside it** enters the same frame in its prologue, so a closure that
  outlives the block still runs restricted (the anti-goal). A named function written
  elsewhere and called inside runs restricted only while inside.
- **Tail calls keep working.** Entering a frame from a tail call replaces the caller's
  frame-entry instead of stacking a new one, and entering the frame already on top is a
  no-op, so a loop that tail-calls back and forth across a package boundary stays constant
  in stack and frames (my call).
- **Actors are their own principals** (owner, 2026-11-09). A message does not carry the
  sender's frames: a handler runs under the actor's own context, which is the stack it was
  spawned with plus its defining package's grant. Sending to an actor you were handed is
  using authority whoever handed you its pid delegated to you, the same rule as a function
  passed in as a parameter. So a `restrict` block can still log through an unrestricted
  logger actor it holds; to stop that, don't hand it the pid. To get a restricted worker,
  spawn it inside the `restrict` block.
- **Spawned tasks and actors** start with the spawning thread's stack, and an actor's
  handler additionally enters its defining package's grant (above). A supervisor respawn
  restores the stack the child was first spawned with, kept on the child's runtime record.
  This is new runtime work: nothing existing threads a context across spawns (the
  test-mock capture in `lib/tir/cap_passing.ml` is a compile-time, off-by-default
  mechanism and is not reused).
- **Refusal is an error value**, never a crash or a silent no-op, so a dependency that
  handles errors carries on. **Every capability operation returns a `Result`** (owner,
  2026-11-09: "we're pre 1.0"). The ones that return a plain value today (`println` and
  the console family, clock and random reads, spawning, the `IO.Mut` table operations,
  signal registration) change type to `Result(T, CapError)`, where `CapError` names the
  refused capability and the frame that refused it. This is a breaking change: it ships
  with a `forge fix` rewrite for the common call shapes and a `### Changed` CHANGELOG
  entry (migration tooling is the builder's call).

**2. The compile-time check**, reusing `lib/tir/net_scope.ml` and the capability ceiling:
the static reach of a `restrict` block, and of a granted dependency's reached code, is
checked against its authority, and every violation the compiler can see (a literal URL,
host, path or method; a builtin of an ungranted capability) is a build error. This is the
owner's "the compiler errors" requirement; the run-time context is what makes the rest
sound.

Why not static specialization instead (compile each function once per authority that can
reach it)? It cannot follow function values whose origin is unknown, would multiply code
size, and still needs a run-time check for computed URLs. Its one advantage, no run-time
cost, is small next to a syscall.

### The stdlib's own connections

The stdlib builds HTTP on `tcp_connect`, which a path or method scope refuses as a raw
connection. So the frame check sits at the **stdlib's public network entry points**, which
know the host, path and method, and the raw primitives they use are called through a
stdlib-only variant the frame does not re-check (the existing stdlib-only builtin gate,
`check_stdlib_only_refs`, keeps user and dependency code off it). Every public stdlib
function that reaches that variant must do its own frame check; a test lists them and
fails when a new one appears without one (my call).

### `extern` in a granted dependency

A grant is the dependency's whole authority (owner), so an `extern` block counts like any
other capability: a reached `extern` in a granted dependency is a build error unless the
grant lists `IO.Foreign` (my call, from the owner's rule; granting `IO.Foreign` is an
explicit "this dependency may run unchecked C").

### Modules and packages

A module belongs to the package whose library directory its source file is in, decided
from the parsed file's real path, not the module name. Two packages (or the app and a
package) defining the same module name, or a path dependency nested inside the project's
own library directory, is a build error under any grant, since the grant could attach to
the wrong code (my call).

### Caches

The grant set is part of every cache that can skip a check: the compile CAS key,
`check_all_cache_key` and `build_islands` in `forge/lib/cmd_build.ml` (which hash only
`MARCH_LIB_PATH` today), and the per-file type-environment cache under `~/.cache/march`.

### Every way of running a program

The same program must be restricted the same way however it runs (owner, 2026-11-09:
"it needs to be the same everywhere"): compiled native binaries, the interpreter
(`march file.march`, `forge run` where it interprets), the REPL, the JIT and the JS target.

- **The run-time context** is implemented in each runtime: the C runtime
  (`runtime/`), the interpreter (`lib/eval/`, its builtins in `eval_builtins` / `eval_net`),
  the JIT (which links the C runtime) and the JS runtime (`runtime/march_runtime.mjs`).
  One conformance suite runs every enforcement test on every backend and requires the
  same outcome, the way `test/run_test_reports.exe` already pins identical output across
  the interpreter, compiled code and JS.
- **The compile-time checks** (the capability ceiling, host scopes, grants, `restrict`)
  move off the `--compile`-only path so `march --check`, the interpreter and the REPL run
  them too. Today both the ceiling and the host-scope check run only under `--compile`;
  moving them is part of this work, not a follow-up.

### Files and folders

Grants and `restrict` cover filesystem capabilities the same way as network ones (owner,
2026-11-09):

```toml
uploader = { version = "1.0", grant = ['IO.FileRead("/srv/uploads")', 'IO.FileWrite("/srv/uploads/out")'] }
```

```march
restrict IO.FileRead("/srv/in") do
  Importer.load(name)        -- reads under /srv/in only, whatever path it builds
end
```

- **Read and write** are the existing split (`IO.FileRead`, `IO.FileWrite`, parent
  `IO.FileSystem`); path scopes are the existing ones (`lib/caps/cap_scope.ml`: absolute,
  segment-wise, lexically normalized).
- **Every file operation checks its path at run time** against the frames. This closes
  today's gap where a computed path passes the static check and is left to the opt-in OS
  sandbox. Relative paths are resolved against the current directory at the moment of the
  call.
- **Symlinks.** The check resolves the path at open time. On Linux it opens with
  `openat2(RESOLVE_BENEATH)` from the scope directory, which is race-free. Where that is
  unavailable (macOS) it resolves with `realpath` and opens with `O_NOFOLLOW` on the final
  component: best-effort against a symlink swapped in between, and the docs say so; the OS
  sandbox stays the strong layer there.
- **Module-level path scopes become run-time enforced too.** A module's own
  `needs IO.FileRead("/etc/app")` enters a frame for that module's functions, exactly as a
  grant does for a package (my call: one mechanism for all three; it also makes host scopes
  hold under the interpreter).
- **Handles.** File handles and sockets are plain integers today, so a handle opened
  under one frame can be forged by code under another. They become opaque types that only
  an opening operation produces (`File.Handle`, `Socket`), and a handle-taking operation
  needs no path check because the open was checked. A prerequisite for files; it also lifts
  the host-scope refusal of stdlib server APIs in scoped modules.

## 7. Diagnostics

New codes (names the builder's call): `dep_grant_exceeded` (reached dependency code needs
more than its grant), `restrict_exceeded` (a `restrict` block's reach needs more), plus
the existing `cap_host_scope` / `cap_host_unproven` family where the destination is a
network one. Each names the chain from the restricting point (the `forge.toml` line or the
`restrict` keyword) to the offending call. `invalid_cap_scope` grows the path-scope
declaration errors.

## 8. Phasing

1. **Path scopes** on `IO.NetConnect` (algebra, compile-time literal check, run-time path
   check in the guard; `HttpTransport.simple_get` gets a guarded twin like `HttpClient`).
2. **Every capability operation returns `Result`**, with the `forge fix` migration
   (breaking; owner's call).
3. **Opaque file and socket handles.**
4. **The run-time authority context** in every runtime (C, interpreter, JS), with spawn
   inheritance and the cross-backend conformance suite; no surface yet. Module-level
   scoped `needs` become frames here.
5. **Compile-time checks under `--check`, the interpreter and the REPL.**
6. **`restrict` blocks**: syntax, lambda frame entry, compile-time check.
7. **Dependency grants**: `forge.toml`, forge → compiler channel, function-prologue frames,
   compile-time check, `forge audit` and `forge.caps.lock`.
8. **Capability values** (`cap_narrow` to a scope, library parameters).

Each phase ships on its own and is honest: `restrict` (6) is useful without grants (7).
Phases 2 to 5 are prerequisites the owner's answers made explicit; they are most of the
work.

## 9. Testing (shape)

- Path scopes: segment matching, every refused encoding, the `"/v1/weather/" ++ "../admin"`
  case refused at run time, query ignored.
- `restrict`: a literal violation inside is a build error; a computed URL inside is refused
  at run time; a closure created inside and called after is still refused; a callback
  passed in and called inside is refused; a task spawned inside is refused; nested blocks
  intersect; `restrict ()` refuses any capability.
- Grants: the owner's three cases end to end (API client to one path with GET; a
  many-feature dependency limited to a subset, unreached features free; a hardcoded
  telemetry URL reached → build error naming it); a transitive dependency reached through
  a granted one is held to the grant; a dependency with no grant is unchanged; changing a
  grant changes the cache key.
- Every enforcement test above runs on every backend (compiled, interpreter, JIT, JS) with
  the same expected outcome.
- Files: a computed path outside the scope refused at run time; a symlink inside the scope
  pointing out refused on Linux; `..` escapes refused; a forged integer handle impossible
  (type error) once handles are opaque.
- Actors: a restricted block sending to a handed-in unrestricted actor succeeds (own
  principal); an actor spawned inside `restrict` is restricted, and stays so after a
  supervisor restart.
- Unrestricted programs: IR unchanged apart from the empty-stack check
  (`scripts/ir-oracle.sh`), and benchmark time within noise (`bench/` HTTP and file ones).

## 10. Left to the builder

The forge → compiler channel's spelling; the encoding of a frame; where exactly the
run-time check sits for each builtin (C runtime or the March wrapper); diagnostic codes and
wording; the error variants each capability's refusal uses.
