# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change — including everything that shipped
before this file existed — lives in `specs/progress.md` and `specs/todos.md`;
git log is authoritative for exact commits.

## [Unreleased]

### Fixed

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
  memory that was never actually heap-allocated. Also fixes the same class of
  bug in `Array.get`/`RRB.get`: reading back a pushed `Float` previously
  returned a silently wrong value (e.g. `0.` instead of `1.5`) rather than the
  correct one. Verified with a 100-element round trip (push then read back
  every index) at both optimization levels, no mismatches.
- `task_spawn`/`Task.async` with a `Float`-returning callback, followed by
  `task_await_unwrap`/`Task.await_unwrap`/`Task.await`, failed to compile
  with an internal LLVM type error. Affects `Parallel.preduce`/`psum_float`,
  which spawn one task per worker chunk. Note: fixing this did **not** make
  `Parallel.psum_float` usable end-to-end — a separate, pre-existing bug in
  tail-recursive functions that combine a `Float` accumulator with a
  heap-value parameter (which `RRB.fold`'s internal loop does) still returns
  wrong answers or crashes compiled; tracked separately.

### Fixed

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

### Documentation

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

[Unreleased]: https://github.com/march-language/march/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
