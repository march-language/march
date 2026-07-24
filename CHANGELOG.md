# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change — including everything that shipped
before this file existed — lives in `specs/progress.md` and `specs/todos.md`;
git log is authoritative for exact commits.

## [Unreleased]

### Added

- As-patterns: `Some(x) as whole -> ...` binds a name to the entire matched
  value while the inner pattern continues to destructure it. Works in match
  arms, `let` bindings, and function parameters. `PatAs` had been implemented
  in the AST, interpreter, and typechecker since the beginning but had no
  grammar production.

- Record patterns: `match r do { x, y: b } -> ... end`, `let { x, y } = r`, and
  `fn area({ w, h })`. `{ x }` is shorthand for `{ x: x }`. `PatRecord` had
  existed in the AST and interpreter since the beginning but had no grammar
  production, and neither TIR lowering path handled it.

- Record patterns may mention a subset of a record's fields: `{ code: 404 }`
  matches any record with a `code` field equal to 404, whatever else it has.
  Naming a field the record does not have is a compile error.

### Changed

- `dune runtest` no longer runs `test/test_properties.exe`. That one binary
  was ~86% of the suite's wall-clock (652s of 756s measured in CI) because its
  QCheck property groups push generated programs through the whole compiler
  pipeline hundreds of times each, and alcotest runs cases sequentially with
  no parallelism to offer. CI now runs it as its own parallel, sharded job.
  It is still built (so compile errors there still fail the build); run it
  locally with `dune build @test/property_tests`, or a subset with
  `./_build/default/test/test_properties.exe test '<group-regex>'`.

- `march --compile` no longer recompiles the whole C runtime from source on
  every invocation. The ~20 `runtime/*.c` files are now compiled once per
  (runtime-source, C-toolchain, compile-flags) combination, cached under
  `~/.march/cache/runtime-objs/`, and reused on subsequent builds — only the
  generated LLVM IR for your own program is compiled per invocation. Measured
  locally, this cuts the clang portion of a small program's build from ~1.5s
  to ~0.3s (a ~5x reduction on that step; ~45% off end-to-end, the remainder
  now being March's own frontend). The saving compounds anywhere many
  programs are compiled in sequence — test suites, the differential oracle,
  `forge build` over a multi-file project.

  The cache key covers the runtime sources' content, the C compiler's own
  version, and the full compile-flag string, so editing a runtime `.c`/`.h`,
  bumping clang, or switching optimization/sanitizer/debug flags each get
  their own object set rather than silently reusing a stale one. Builds that
  bake per-invocation defines into the runtime — cross-compilation,
  `--compile-so`, `--hot-reload` with `--signing-pubkey`, and
  `MARCH_HTTP_EVLOOP=1` — automatically fall back to the previous
  single-command compile. `MARCH_NO_RUNTIME_CACHE=1` forces that fallback.

### Fixed

- Unreachable match arms are now reported inside functions with a declared
  return type. `check_redundant_arms` ran only on the type-inference path, so
  any `match` in checking position — which is every `match` in a function with
  a return annotation, i.e. most of them — silently skipped the analysis.

### Documentation

- Migrated 14 language-reference chapters (Type System, Pattern Matching,
  Modules, Interfaces, Linear Types, Refinement Types, Capabilities, Safety
  by Construction, Memory Model, Actors, Parallel Collections, Supervision,
  Session Types, Clustering) from `specs/lang/` into real, styled pages on
  march-lang.org (`/docs/<topic>/`). These previously rendered as blank,
  unstyled `/<topic>.html` stub pages ("this topic has moved") that every
  site page linking to them — the homepage, the language tour, Getting
  Started, the stdlib guide, the FFI guide, and the "coming from X" guides —
  pointed at. Content was adapted for a general-programmer reader rather
  than copied verbatim: `specs/lang/` keeps the full conformance-ledger
  detail (source citations, golden-test IDs, dated findings) for compiler
  contributors, while the published pages state each caveat once, in plain
  language, without implementation citations.

## [0.2.0] - 2026-07-23

### Fixed

- A module could not reference a same-name-prefixed sibling module in a
  multi-file project — e.g. entry `mod MyApp` calling into a sibling
  `mod MyApp.Router` declared in its own file (the documented
  "one mod per file" multi-file convention), via `MyApp.Router.dispatch(...)`,
  `use MyApp.Router` + bare `Router.dispatch(...)`, or (previously the only
  working spelling) `alias MyApp.Router as R`. The first two failed with
  `Unknown module \`Router\`.` — the entry-module-self-qualification stripping
  pass matched by string prefix only, so `MyApp.Router.dispatch` (which
  merely starts with the entry's own name, `MyApp.`) was wrongly mangled to
  `Router.dispatch` as if `Router` were one of the entry's own members. A
  related gap in `use`/`alias` resolution (taking only the first segment of a
  dotted import path) and in `use`'s bare-name binding for dotted paths are
  also fixed. Referencing an unrelated-named sibling module always worked and
  still does.

- Fork-join workloads using `task_spawn`/`task_await`/`task_await_unwrap`
  under high task concurrency (thousands of simultaneously in-flight tasks)
  could hit a severe performance cliff — `bench/par_fib.march`
  (`par_fib(40, 20)`) went from a fraction of a second to 54+ minutes past a
  certain task-count threshold. An earlier pass bounded the worst case with
  a spin-then-sleep backoff (cutting wasted CPU) but the workload still
  didn't complete; `task_await` now parks the awaiting green thread and
  wakes it explicitly on completion (mirroring the existing actor-mailbox
  park/wake pattern), which eliminates both the wasted context-switch
  overhead and a LIFO dispatch-starvation interaction that was compounding
  it. The scheduler's separate internal wake-on-parked-proc spin also keeps
  its own generous-grace-period sleep fallback from the earlier pass, so
  neither wait can peg an OS thread at 100% CPU forever with no possibility
  of self-recovery. Compiled `--compile` programs only; the interpreter was
  unaffected.

- Compiled `Csv.read_all`/`Csv.each_row_with_header` could crash
  (nondeterministic SIGBUS/SIGSEGV) or silently return zero rows. A
  builtin-call argument coercion added to fix an unrelated tagging bug
  (`Some((top, _)) -> int_to_string(top)` printing `7` instead of `3`) was
  incorrectly tagging opaque native-pointer handles — Csv/File/Tcp handles
  are represented as plain `Int` in March's type system by convention, but
  are raw C pointers at runtime — whenever they were passed to a builtin
  whose C signature declares the parameter as `ptr`. Restricted the
  coercion to the direction it was actually meant for.

- The browser cookbook/playground REPL's bundled stdlib was missing
  `Vault` — the docs/cookbook/vault.md examples errored with `no member
  'new' in module 'Vault'` because `vault.march` wasn't in either
  `js/march_browser.ml`'s `browser_stdlib_files` load-list or
  `scripts/gen-browser-stdlib.py`'s `FILES` list used to generate
  `docs/assets/march_stdlib.js`. Added it to both and regenerated the
  bundled assets.

### Documentation

- The "sandboxed plugin runner" example in docs/cookbook/capabilities.md
  called a `sandbox_eval` function that never existed anywhere in the
  compiler or stdlib — it was illustrative pseudocode, so running the
  example in the cookbook REPL errored with `unbound variable:
  sandbox_eval`. Replaced it with a trivial inline stub so the snippet
  actually compiles and runs; the example's real point (the `PluginCap`
  gate) is unaffected.

- A qualified call to a real module's genuinely nonexistent member (e.g.
  `String.length(...)` — `String` has no `length`; the real API is
  `byte_size`/`codepoint_count`/`grapheme_count`) silently fell through to an
  unrelated same-named binding elsewhere (e.g. the prelude's generic
  `List.length`) instead of reporting "Module `String` does not export
  `length`". The EVar dot-suffix fallback — meant only to resolve
  multi-component local/app-module paths like `Conduit.Storage.workflow_load`
  down to `Storage.workflow_load` — didn't distinguish that case from a
  qualifier that is already a confirmed, loaded stdlib module. Now, once the
  qualifier's first component resolves to a real registered module, a missing
  member always reports the clean "does not export" diagnostic instead of
  falling through to the bare-name search.
- A user-defined interface impl with a compositional `when` constraint (e.g.
  `impl MyEq(Wrap(a)) when MyEq(a) do fn eq(w1, w2) do ... eq(x, y) ... end
  end` — the same shape as the stdlib's own `Eq(List(a)) when Eq(a)`) whose
  body recursively called its own method name on the constrained inner value
  dispatched incorrectly. Interpreted, the recursive call re-entered the SAME
  impl instead of the inner type's impl, producing a wrong answer (or a
  non-exhaustive-match panic). Compiled, it crashed with an internal compiler
  error ("has no runtime-tag rows") whenever the constrained type happened to
  share a method name with an unrelated interface. Both are fixed: the
  recursive call now dispatches by the runtime type of its own arguments on
  both backends, regardless of impl declaration order or nesting depth.
- `root_cap()` — calling the root capability like a function instead of
  referencing it bare (`root_cap`) — typechecked cleanly with `--check` and
  then crashed at runtime: `applied non-function value` interpreted, or an
  `Undefined symbols ... _root_cap` link error compiled. `root_cap` is a
  plain value, not a function; calling it with `()` is now rejected at
  check/compile time with a diagnostic explaining why.
- `File.read` and related I/O builtins (`file_write/append/delete/copy/rename/stat/open`,
  `Dir.list/mkdir/mkdir_p/rmdir/rm_rf`, `Csv.open`, and the TCP/TLS/HTTP/process
  builtins) had their `Result` error type registered as fully polymorphic, so a
  function declaring an incompatible error type (e.g. `Result(_, String)` for
  `File.read`, whose real error is `FileError`) typechecked with zero
  diagnostics and then panicked at runtime the moment the error value was used
  as the wrong type. These builtins' error types are now pinned to their real
  concrete type, so a mismatched declaration is now a compile-time error
  instead of a runtime panic.
- `Actor.call`'s reply value was silently corrupted when compiled: an `Int`
  (or `Bool`/`Unit`) reply came back as its raw tagged-immediate bit pattern
  instead of the real value (e.g. a handler replying with `5` was observed as
  `11` by the caller). `int_to_string`/`bool_to_string`/`float_to_string` are
  the only scalar-consuming builtins that had no dedicated argument coercion,
  so a value arriving through `Actor.call`'s necessarily type-erased reply
  channel was passed straight through with a declared-signature mismatch
  instead of being untagged first.
- The same underlying gap — builtin call arguments never coerced to the
  builtin's own declared native parameter type, only to a user-defined
  function's — also reached compiled output through an unrelated path: a
  scalar bound by a tuple or constructor pattern (e.g. `Some((top, rest)) ->
  int_to_string(top)`, or even a plain top-level `(top, rest) ->
  int_to_string(top)`) passed to any compiler builtin with a native scalar
  parameter (`math_sqrt`, `float_abs`, and ~50 more beyond the three fixed
  above) printed the raw internal tagged-integer encoding instead of the real
  value (`7` instead of `3` for the example above). Call-argument coercion
  now also derives each builtin's declared parameter types directly from its
  own preamble `declare` signature, so every builtin gets the same coercion
  user-defined functions already had — not just the three fixed individually
  above.
- `self()` inside an actor handler was typechecked as a plain `Int` instead
  of that actor's own `Pid`, so passing it anywhere a `Pid` was expected
  (`is_alive(self())`, a typed `Pid` message field) failed to typecheck with
  "expected `Pid` but got `Int`" even though it is a valid `Pid` at runtime.
  `self()` now resolves to the same `Pid[state]` type `spawn` produces for
  that actor.
- A general user interface implemented by two same-short-name types declared
  in different modules (e.g. `NA.Thing` and `NB.Thing` both `impl
  Speak(Thing)`) could have an ambiguous call site resolved, at compile time,
  to whichever impl happened to be declared first — a latent miscompile risk
  rather than an always-reproducing bug, since an unrelated dispatch guard
  happened to mask it for most call shapes. Interface dispatch on same-named
  colliding types is now always deferred to the collision-aware runtime
  dispatch added for this feature, with no first-match shortcut.
- An all-caps acronym stdlib module name (e.g. `RRB`, declared in
  `rrb_vec.march`) failed to resolve in a type annotation with "Unknown module
  `RRB`", even though its functions worked fine as values. The lazy
  qualified-name resolver guessed a module's filename by inserting `_` before
  every uppercase letter (`ConsistentHash` -> `consistent_hash.march`), which
  mangles an acronym into a filename that doesn't exist (`r_r_b.march`).
  Falls back to a lazily-built index of the stdlib directory keyed by each
  file's real declared module name when the naming-convention guess misses.
  Fixing this exposed a second, related bug: a qualified reference to an
  opaque type (`RRB.Vec(Int)`) failed to unify with real values of that type
  (`expected 'RRB.Vec(Int)' but got 'Vec(r3)'`) because the qualified name
  wasn't canonicalized to its bare form when the type's module was being
  loaded for the first time. Both are fixed together.
- `let x : T = e` type annotations silently accepted ANY resolution failure
  in `T` and fell back to inferring the type from `e` alone with zero
  diagnostics — e.g. `let e : Vec(Int) = "not a vec"` typechecked cleanly.
  This was meant to tolerate a phantom/typestate tag used in type position
  (`let h : Handle(Open) = ...`, where `Open` is a data constructor, not a
  type name) but was too broad, silently discarding genuinely broken
  annotations (an unresolvable module, a typo'd or renamed type) too.
  Narrowed to only tolerate the phantom-tag case (an unresolved name that IS
  a known data constructor); any other resolution failure now surfaces as a
  real diagnostic.
- An inline lambda passed directly as a call argument (e.g. `Dom.on_frame(fn _
  -> ...)`) failed to parse if its body had a plain statement (not a `let`
  binding) immediately followed by another expression — e.g. a function call
  followed by an `if`/`else` — even though the identical body worked fine as a
  named function or a lambda wrapped in `do...end`. Symptom: `I got stuck here`
  at the following token. Inline lambda call arguments now accept bare
  statements before the final expression, matching `do...end` block bodies.
- A linear or `always_linear`-typed value *acquired* through `let? p = e` or
  `with Ok(p) <- e do ... end` — rather than bound by a plain `let` or a
  function parameter — was never tracked as linear at all, so consuming it
  twice (e.g. passing the same handle to two separate calls, each behind its
  own `let?`) went completely undetected. The identical double-use was
  already correctly rejected when the value came from an ordinary `let` or a
  function parameter. Affects any code acquiring a linear resource through a
  Result-returning `let?`/`with` chain.
- A self-tail-recursive function forwarding a freshly-built value as its own
  next argument (e.g. an accumulator built via `String.join`/`String.split`)
  could silently corrupt that value in compiled programs — freed one
  instruction before it was reused for the next iteration. Symptom: wrong
  answers with no crash or error, e.g. `stdlib/toml.march`'s integer parsing
  (`Toml.get_int` on `"port = 9000"`) returned `9` instead of `9000` compiled
  while the interpreter was correct. Affects any compiled program using this
  accumulator-recursion shape over a value not extracted from an
  already-borrowed container (a list/tree traversal passing along an existing
  field, e.g. `Cons(_, t) -> go(t, ...)`, was unaffected).
- Interfaces implemented separately for two same-short-name types declared in
  different modules (e.g. two modules each with their own `impl Speak(Thing)`)
  now dispatch to the correct implementation at runtime, in both the
  interpreter and the native backend. Previously the wrong implementation's
  body could run silently: the interpreter took whichever impl was registered
  last regardless of the value's actual type, and native code could miscompile
  via colliding constructor tags or value representation. Built-in interfaces
  (`Eq`, `Ord`, `Show`, `Hash`) were already correct and are unaffected. (#57)
- `string_to_float` and `String.to_float` crashed (segfault) in compiled
  programs whenever the parsed `Float` was actually used — e.g.
  `match string_to_float(s) do Some(f) -> ... end`. Fine in the interpreter;
  native code stored the parsed value in a representation the rest of the
  compiler didn't expect. Affects any compiled program parsing floats from
  strings, including `stdlib/toml.march`'s float handling.
- `Html.raw(...)` content silently disappeared when interpolated into a `~H`
  sigil in compiled programs — e.g. `~H"<button>${Html.raw("hi")}</button>"`
  rendered `<button></button>`. Fine in the interpreter. Affects the
  documented layout/partial-nesting pattern
  (`~H"<body>${Html.raw(IOList.to_string(body))}</body>"`) as well.
- `Option.or_else` and `Option.unwrap_or_else` crashed at runtime
  (`arity mismatch: expected 0 args, got 1`) when called with a genuine
  zero-argument callback — `fn -> ...`, the natural spelling for their
  declared `() -> a` parameter. Both functions invoked the callback as
  `f(())` (passing an explicit unit value) instead of `f()`, which only
  matched a 1-arg-discard closure (`fn _ -> ...`). Fixed to call `f()`;
  affects both the interpreter and compiled programs.
- `pfn` (private function) visibility could be silently bypassed when a
  same-file nested module's private function shared its bare name with an
  unrelated global (e.g. a function named `hash`, colliding with the `Hash`
  interface's built-in method). The call typechecked without error, ran
  correctly in the interpreter, and produced a garbage value in compiled
  programs — a privacy violation that also corrupted the result, not just a
  missing diagnostic. Now correctly rejected at `--check` and `--compile`
  with the same "is private to module" error other privacy violations
  already produced.
- `RRB.push`/`Array.push` crashed compiled on the second `Float` element
  pushed (`RRB.push(RRB.push(RRB.empty(), 1.5), 2.5)`). A discarded
  (wildcard-matched) field of a list cell never got the special-casing a
  *named* field already had, so the compiler treated it as reference-counted
  even when the concrete element type (`Float`) doesn't need that — freeing
  memory that was never actually heap-allocated. (Reading a pushed `Float`
  back out — `Array.get`/`RRB.get` — had a separate, sibling bug; see below.)
- `task_spawn`/`Task.async` with a `Float`-returning callback, followed by
  `task_await_unwrap`/`Task.await_unwrap`/`Task.await`, failed to compile
  with an internal LLVM type error. Affects `Parallel.preduce`/`psum_float`,
  which spawn one task per worker chunk.
- A tail-recursive function combining a `Float` accumulator with a
  heap-value parameter (e.g. an `Array`/`List`) — the shape `RRB.fold`'s
  internal loop uses — returned a wrong answer or crashed
  (`RC underflow (rc was 0)`) in compiled programs, blocking
  `Parallel.preduce`/`psum_float`'s worked example
  (`docs/cookbook/parallel-data.md`) end-to-end even after the task-boundary
  fix above. Two independent causes: a constructor field discarded via a
  wildcard pattern (`Cons(_, t)`) kept an internal type placeholder that
  made the compiler treat an unboxed `Float` as a heap pointer needing
  reference counting, corrupting memory; and a value read out of a generic
  container field was passed to some function calls without converting it
  to that function's expected native representation, so the callee silently
  read `0.0` instead of the real value. Both fixed. Affects any compiled
  program building or reading a `List`/`Array` of `Float` through a generic
  helper (`Array.from_list`, `Array.get`, and therefore `RRB`'s `Float`
  operations) or wildcard-discarding an element of a `Float` container.
- `Dom.clone`, `Dom.first_child`, and `Dom.last_child` were declared as
  extern runtime builtins but never got a public stdlib wrapper, like every
  other DOM function — so they were unreachable from March code
  ("Module `Dom` does not export ...") despite being documented.
- `fn main(cap : Cap(IO)) : ()` — the documented pattern for receiving the
  initial IO capability — never actually worked: in the interpreter it
  silently no-oped (the program appeared to exit successfully having done
  nothing), and compiled programs crashed (SIGBUS) on startup. Both backends
  now run it correctly; any other `main` arity or parameter type is now
  rejected at compile time with a clear error instead of misbehaving.
- WebSocket connections in the interpreter (`forge run`, plain `march
  file.march`, and any tool built on it, including `forge scroll.serve`)
  disconnected almost immediately whenever the client went quiet — an open
  connection would flip to closed within milliseconds of the server having
  nothing to read, sometimes before the client's very first message was even
  processed. A raw handshake with no further traffic got an instant
  server-initiated close. The server's WebSocket handler was reading from a
  socket still configured for the (unrelated) HTTP accept loop's internal
  bookkeeping, which made an ordinary "no data yet" condition look
  indistinguishable from the client disconnecting. Compiled (`--compile`)
  WebSocket servers had a milder version of the same bug: an idle connection
  would be dropped after 10 seconds instead of staying open. Both are fixed;
  idle WebSocket connections now stay open as expected in both backends.
- `Vault.update` crashed (segfault) in compiled programs, for both an inline
  lambda and a named function callback — e.g.
  `Vault.update(store, "hits", fn n -> n + 1)`. Fine in the interpreter.
  Affects the documented atomic-update pattern and the rate-limiter cookbook
  example.
- Corrected stale claims and two tutorial code blocks in the top-level
  `README.md` that no longer matched the compiler: linear/affine types and
  `kill`/`is_alive` are fully supported (were marked "in progress" /
  "interpreter only"); the higher-order-function and actor examples now
  typecheck and run as written; the project-layout map now lists `stdlib/`,
  `forge/`, `lsp/`, and `test/`, previously omitted entirely.
- Corrected the `install.sh` `MARCH_VERSION` pin-example comment.
- Audited every March code example across the docs site (guides, the
  language tour, the cookbook, and the stdlib reference) against the current
  compiler and fixed everything that no longer typechecked, ran, or matched
  its claimed output — including a large number of stale API references in
  `docs/stdlib.md` (wrong module names, argument order, arity, or return
  types across `String`, `Math`, `JSON`, `HTTP`, `Vault`, `URI`, `Dom`, and
  more), the REPL transcript in `docs/getting-started.md` (real prompt is
  numbered, `= value` output by default), and dozens of smaller fixes across
  `docs/cookbook/*`. Several real compiler/stdlib bugs surfaced along the way
  (silent wrong answers and crashes, mostly compiled-only) that are outside a
  docs fix's scope and were filed separately rather than papered over in the
  docs.
- `docs/cookbook/linear-types.md`'s Typestate section and its "safe socket
  lifecycle" example — left unfixed by the docs audit above pending a design
  decision — didn't compile as written and were internally inconsistent
  (`via` transition functions shown returning `Result`/tuples, an acquisition
  function listed as a transition despite not taking a handle, a socket type
  missing its state parameter). Rewritten so each resource's lifecycle splits
  into an ordinary Result-returning acquisition function outside
  `transitions` plus pure `Handle -> Handle` transitions declared inside it,
  matching the working pattern in `specs/lang/capabilities.md`. Every code
  block was verified against the compiler, including that a wrong-order
  transition call is correctly rejected.
- Audited every March code example across `specs/lang/` (the authoritative
  language reference, ~341 code blocks across 21 files) against the current
  compiler, the same way as the docs/ sweep above. Several sections described
  an interface-dispatch architecture superseded by the impl-coherence and FQN
  dispatch-identity work that landed 2026-07-17 through 2026-07-21 (rewritten
  with live-verified current behavior); the Operator Reference table in
  `type-system.md` had `+ - * /` and the dotted `+. -. *. /.` operators
  backwards (the plain operators are the polymorphic Int/Float ones, not the
  dotted ones); several "known limitation" notes across `pattern-matching.md`
  and `session-types.md` described parser/linearity gaps already fixed. Around
  70 real example/prose bugs fixed in total. `specs/lang/grammar.md`'s
  `parser.mly`/`token_filter.ml` line citations have drifted (~15 of ~294
  fixed; the rest need a dedicated re-grep pass). Several real compiler bugs
  surfaced along the way and were filed separately, most notably a
  currently-live regression where compiled `Actor.call`/`Actor.reply` returns
  the raw tagged value instead of untagging it — it breaks an existing pinned
  golden test wired into `dune runtest`, just not caught because the fast
  test runner bypasses that lane.

## [0.1.1] - 2026-07-21

First tagged release.

### Added

- **Type system**: Hindley-Milner inference with bidirectional checking at
  function boundaries; algebraic data types and pattern matching; records
  with functional update (`{ r with field: value }`); polymorphic functions
  monomorphized at compile time; linear and affine types for ownership, safe
  mutation, and actor message-passing isolation; interfaces (`interface`/
  `impl`) with default methods and conditional impls (`when` constraints);
  type-level naturals for dimension-checked `Vector`/`Matrix`/`NDArray`;
  refinement types (`{T | predicate}`) with a Z3-backed verification bridge
  (in progress).
- **Memory management**: Perceus reference counting (deterministic, no GC
  pauses) with FBIP (Functional But In-Place) — pattern-matched values with
  a unique reference count are rewritten in place instead of freed and
  reallocated; escape analysis promotes allocations to the stack where
  possible; defunctionalization compiles closures to structs with no
  indirect-call overhead.
- **Concurrency**: actor model with share-nothing message passing, `spawn`,
  `send`, capability-secured references, location-transparent `Pid`;
  supervision trees and a distributed/clustering layer with node discovery;
  structured concurrency via `Task` (`async`/`await`/`race`/`any`/
  `all_settled`/`scope`, cancellation tokens); `Future` and `Stream`.
- **Backends**: native compilation via LLVM/clang, including cross-compilation
  to Linux (amd64/arm64) from any host via `zig cc`; `--target wasm64-wasi`
  for WebAssembly and a JS backend; a tree-walking interpreter and a
  JIT-backed REPL.
- **Tooling**: `forge` package manager and build tool (`new`, `build`, `run`,
  `test`, `deps`, `publish`, `watch`, `bench`, ...) with content-addressed
  dependency versioning; an LSP server (diagnostics, hover, goto-definition,
  completions, code actions); a 111-module standard library (collections,
  `BigInt`/`Decimal`/`Ratio`, HTTP client/server, JSON/MessagePack/TOML,
  crypto, DataFrame, distributed-OTP actors, and more); FFI for C interop,
  hot code reload, and a `--check-json` machine-readable diagnostics mode.

[Unreleased]: https://github.com/march-language/march/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/march-language/march/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
