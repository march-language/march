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

### Fixed

- `Dom.clone`, `Dom.first_child`, and `Dom.last_child` were declared as
  extern runtime builtins but never got a public stdlib wrapper, like every
  other DOM function — so they were unreachable from March code
  ("Module `Dom` does not export ...") despite being documented.

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
