# Design: March → JavaScript Backend (`--target js`)

**Date:** 2026-06-21
**Status:** Approved (design); implementation not started

## Overview

A new compiler backend that emits readable, idiomatic ES modules from March
source, targeting **DOM-interactive browser applications**: UI logic that
handles events, manipulates the DOM through a JavaScript FFI, and `await`s
asynchronous operations such as `fetch` and timers.

The JS backend sits **alongside** the existing WebAssembly target
(`--target wasm32-unknown-unknown`); it does not replace it. The two serve
different purposes and are expected to coexist long-term:

- **JS target** — interactive UI logic: DOM access, awaiting async work,
  holding live JS object references, debuggable output, tiny payloads for
  small programs.
- **WASM target** — compute-heavy, boundary-light kernels (e.g. the
  `native_int_arr` / `native_float_arr` SIMD-style paths) where raw numeric
  throughput and full language fidelity (scheduler, deterministic RC) matter.

### Why JS rather than WASM for this use case

The two product decisions that frame this work — **async/await** as the
concurrency model and a **JS FFI for the DOM** — are precisely where WASM is
weakest:

- WASM has no native async; it requires Asyncify (≈2× binary, slow stack
  unwinding) or JSPI (new, uneven browser support). JS `async`/`await` *is*
  the language.
- WASM cannot hold DOM nodes or JS objects in linear memory; every DOM call
  crosses the JS↔WASM boundary with an `externref`/handle table and string
  marshalling. The JS backend has no boundary.
- WASM ships its own allocator + RC (or WasmGC); the JS backend gets GC for
  free and skips reference counting entirely.

WASM still wins for numeric throughput and full-fidelity concurrency, so it
remains the right tool for a *different* shape of program. This spec does not
remove or modify the WASM path.

## Goals

Compile the following March subset to ES modules that run in browsers and
under Node:

- ADTs (variants), pattern matching, records, tuples
- First-class closures, recursion, mutual recursion
- Strings, `List`, `Option`, `Result`, and the numeric / string / comparison
  builtins currently lowered inline by `llvm_emit.ml`
- `js_extern` FFI for calling browser / JS APIs (synchronous and async)
- An `async`/`await` concurrency model derived by static effect coloring
- A `main` entry point plus named exports callable from host JavaScript

## Non-Goals (v1)

Explicitly deferred. These are out of scope and the emitter should produce a
clear "unsupported in JS target" diagnostic if encountered, rather than
silently miscompiling:

- `spawn` / actors / green threads / supervision trees
- `Chan` / MPST session channels
- Blocking OS-thread externs (`blocking fn` in a C `extern` block)
- The full native stdlib — only builtins with a JS shim are supported
- True 64-bit `Int` (see [Integer Semantics](#integer-semantics)); v1 uses
  safe 53-bit integers
- WasmGC interop

## Architecture

### Pipeline integration

The native/WASM compile path today is (`bin/main.ml`):

```
Lower → Mono → Defun → Perceus → Opt → Llvm_emit
```

The JS target branches **after Mono**, skipping Defun and Perceus:

```
Lower → Mono ─┬─ (native / wasm) → Defun → Perceus → Opt  → Llvm_emit
              └─ (js)             → Opt' → AsyncColor → Js_emit
```

- **Skip Defun.** JavaScript has first-class closures, so March closures
  emit as native JS closures. The defunctionalized `ECallPtr` /
  closure-struct representation is never produced; a native `EApp` on a
  closure value lowers to a direct JS call.
- **Skip Perceus.** JavaScript is garbage-collected, so no reference-counting
  nodes (`EIncRC`, `EDecRC`, `EAtomicIncRC`, `EAtomicDecRC`, `EFree`,
  `EReuse`) are ever inserted. The JS emitter treats any such node as a
  no-op for defensiveness, but in the normal path they are absent.
- **Opt'** reuses the existing `Opt.run` passes (join-points, known-call,
  inline, cprop, fold, simplify, fusion, dce), which operate on
  RC-free TIR. See [Risk: Opt without Perceus](#risks).

### New module

`lib/tir/js_emit.ml`, a sibling of `lib/tir/llvm_emit.ml`, consuming the same
`Tir.tir_module`. A new target variant `Js` is added to
`Llvm_emit.target_config` (or a shared target type if that proves cleaner —
see Open Questions), threaded through `bin/main.ml`'s `parse_target` and the
CAS target label.

## TIR → JavaScript Lowering

The TIR is ANF-based: function arguments are atoms, every binding is
explicitly typed. After Mono there are no type variables. The mapping:

| TIR node | JavaScript |
|----------|-----------|
| `EAtom (ALit l)` | literal |
| `EAtom (AVar v)` | identifier |
| `EApp (f, args)` | `f(a0, a1, …)` |
| `ELet (v, e1, e2)` | `const v = <e1>;` then `<e2>` |
| `ELetRec (fns, body)` | hoisted `function` declarations + `<body>` |
| `ECase (x, brs, def)` | `switch (x.$) { case "Ctor": …; default: … }` |
| `ETuple [a; b]` | `[a, b]` |
| `ERecord [("x", a)]` | `{ x: a }` |
| `EField (r, "x")` | `r.x` |
| `EUpdate (r, [("x", a)])` | `{ ...r, x: a }` |
| `EAlloc ("Foo", [a; b])` | `{ $: "Foo", _0: a, _1: b }` |
| `EStackAlloc (…)` | identical to `EAlloc` (the stack hint is irrelevant under GC) |
| `ESeq (e1, e2)` | `<e1>;` then `<e2>` |
| `ECallPtr` | not produced (Defun skipped); if present, error |

Notes:

- **Constructor tag** lives in the `$` field. March identifiers cannot
  contain `$`, so it can never collide with a user record field or
  constructor-argument slot. Constructor arguments are positional `_0`, `_1`,
  ….
- **ANF → const chain.** Because TIR is ANF, the natural emission is a
  straight-line sequence of `const` bindings inside the enclosing function,
  with `ECase` / `ELetRec` introducing nested blocks or hoisted declarations
  as needed.
- **Closures.** A TIR function value emits as a JS arrow function capturing
  its free variables lexically. No closure struct, no environment record.
- **Entry points.** `main` emits as an exported `main()`. Names in
  `tm_exports` emit as named ES exports.
- **Structural equality.** ADT structural `==` reuses the same per-type
  equality logic the LLVM path generates (`emitted_eq_fns`), ported to emit a
  recursive JS comparison function per monomorphic type.
- **Name mangling.** Cross-module qualified TIR names (e.g.
  `Crypto.base64_encode`) are mangled to valid, collision-free JS identifiers
  via a deterministic scheme (`Crypto$base64_encode`). The mangler must be a
  total, injective function over the set of TIR names in the module.

## Runtime Shim — `march_runtime.js`

A small, hand-written ES module providing the builtins that `llvm_emit.ml`
currently lowers to LLVM instructions or runtime calls. The emitted module
imports the subset it uses. Contents:

- Arithmetic / comparison — mostly inlined as native JS operators at emit
  time; the shim holds only those needing helper logic (e.g. integer
  division/modulo semantics, see Integer Semantics).
- String builtins — `string_concat`, length, slice, comparison, etc.
- Collection constructors / helpers — `List` (cons/nil), `Option`, `Result`.
- `print` → `console.log`.
- Generic structural-equality helper, if a shared one is cleaner than
  per-type generated functions.

Target size ≈ 300–400 lines. Lives in the repo as a source asset and is
copied (or referenced by relative import) next to emitted output.

## Async Coloring (`AsyncColor` pass)

A new TIR pass implementing the async/await concurrency model. It computes,
by fixpoint over the call graph, which functions are **async**:

1. A function is async if it directly calls an async `js_extern`.
2. A function is async if it transitively calls an async function.
3. Iterate to fixpoint.

Emission consequences:

- Async functions emit as `async function` / `async (…) =>`.
- Calls **to** an async function emit `await f(…)`.
- Purely synchronous functions and call sites are unaffected.

This pass replaces, for the JS target, the native handling of `blocking`
externs (which dispatch on an OS thread via `march_run_blocking_*`). In the
JS world "blocking" becomes "awaitable".

Constraint: an async function cannot be called from a context that the
coloring did not mark async — by construction the fixpoint prevents this, but
the pass must assert it and emit a clear diagnostic if an async value escapes
into a synchronous position (e.g. stored in a data structure and later called
synchronously). v1 may conservatively reject such programs.

## JavaScript FFI — `js_extern`

A JS-specific FFI form so a binding can declare its JS target symbol and
whether it is asynchronous. This is distinct from the existing C `extern`
block.

### Surface syntax (proposed)

```
js_extern "dom" : Cap(Dom) do
  fn query(selector: String): Node = "querySelector"
  async fn fetch_text(url: String): String = "fetchText"
end
```

- `"dom"` names the JS module/namespace the bindings resolve against.
- `async fn` marks the binding as asynchronous (seeds `AsyncColor`).
- The string after `=` is the JS symbol name; defaults to the March name.

### Touch points

| Layer | Change |
|-------|--------|
| `lib/ast/ast.ml` | Extend `extern_fn` with an optional `ef_js` binding (`{ js_module : string option; js_symbol : string; js_async : bool }`), or add a parallel `DJsExtern` decl. Decision recorded in Open Questions. |
| Parser | Surface syntax for `js_extern` blocks and `async fn`. |
| `lib/typecheck/typecheck.ml` | Same `Cap` / `needs` capability checking as C externs (Checks 1 and 5). Record the async flag for `AsyncColor`. |
| `lib/tir/lower.ml` | Carry JS binding info into `Tir.extern_decl` (new `ed_js_symbol` / `ed_async`, or a JS-specific extern record). |
| `lib/tir/js_emit.ml` | Emit `import { querySelector as query } from "./imports/dom.js"` (or `globalThis`-based resolution) and wire async bindings into `AsyncColor`. |

### Curated bindings

Ship a `march_dom.js` (and `Console`, `Timer`) providing the common DOM,
console, and timer surface so users have a working FFI immediately without
writing their own JS. Arbitrary user-supplied imports maps are also
supported by resolving against a provided module path.

## Integer Semantics

March `Int` is 64-bit; JavaScript `number` is an IEEE-754 double, exact only
to 2^53 − 1. **v1 uses safe 53-bit integers** (`number`):

- Rationale: typical UI logic (indices, counts, lengths, enum tags) never
  approaches 2^53. `BigInt` is viral (infects every arithmetic site), slower,
  and degrades output readability.
- The limitation is documented and the boundary is explicit.
- **Future:** a `--js-bigint` flag (M4) switches `Int` to `BigInt` for
  programs that genuinely need full 64-bit range.

Integer division and modulo emit through shim helpers that reproduce March's
semantics (truncation toward zero, sign of modulo) rather than relying on raw
JS `/` and `%`.

## CLI / Build / Caching

- `--target js` (aliases `javascript`) → the `Js` target variant in
  `parse_target`.
- Output filename: `<basename>.mjs`. The runtime shim is copied or
  referenced by relative import alongside it.
- No native toolchain is invoked — the backend emits text and writes the
  file. (Contrast: native/WASM invoke `clang` / `wasm-ld`.)
- CAS: `target_label = "js"`, folded into the existing
  `Cas.compilation_hash` logic so JS builds cache and short-circuit like
  native/WASM builds.
- Lands directly on `--target js` (no feature flag).

## Testing Strategy

- **Golden tests.** TIR → JS string snapshots for each construct (ADT,
  pattern match, record, tuple, closure, recursion, async coloring).
- **Execution tests.** Compile sample `.march` programs to `.mjs`, run under
  Node, assert stdout / return values. Reuse existing example programs that
  fall within the v1 subset.
- **FFI / async test.** A Node harness supplying a fake imports map (stubs or
  jsdom) exercises `js_extern` and async coloring end-to-end — a sync DOM
  binding and an `async fetch_text`.
- Wire all of the above into `forge test` / CI.

## Milestones

### M1 — Pure core
`--target js`, `lib/tir/js_emit.ml`, the pipeline branch (skip Defun /
Perceus), `march_runtime.js`. Supports pure functions, ADTs, pattern
matching, records, tuples, closures, recursion, strings, `List` / `Option` /
`Result`. Node golden + execution tests. **No FFI, no async.**

Includes the validation task: confirm no `Opt.run` pass assumes Perceus ran.

### M2 — `js_extern` (synchronous)
FFI plumbing through parser → typecheck → lower → emit. `march_dom.js` with
synchronous DOM / console bindings. Capability checking on `js_extern`.

### M3 — Async
`AsyncColor` pass; `async fn` in `js_extern`; `fetch` / timer bindings;
async-position escape diagnostics.

### M4 — Polish
Source-map comments, `--js-bigint` flag, broader stdlib shims, dead-export
elimination, ergonomics of the imports-map resolution.

## Risks and Open Questions

### Risks

- **Opt without Perceus.** `Opt.run` currently runs *after* Perceus on the
  native path, and a comment notes some passes target "cases revealed after
  Perceus." The JS path runs Opt on RC-free TIR. **Validation task (M1):**
  confirm every Opt pass is correct (and ideally still useful) on a module
  that contains no RC nodes. If any pass assumes RC nodes exist, gate it off
  for the JS target.
- **Async escape.** A first-class async function stored in a data structure
  and later invoked from a synchronous position breaks the await coloring.
  v1 conservatively rejects this with a diagnostic; a fuller solution
  (uniformly async-typing such values) is deferred.
- **Name-mangling collisions.** The qualified-name → JS-identifier mangler
  must be injective over the module's name set. A prior march bug
  (cross-module ctor-tag collision) shows this class of problem is real;
  the mangler needs a collision check, not just a substitution scheme.

### Open Questions

1. **Extern representation:** extend `extern_fn` with an optional `ef_js`
   field, or introduce a separate `DJsExtern` declaration? Leaning toward
   extending `extern_fn` to keep one capability-checking path.
2. **Target type location:** add `Js` to `Llvm_emit.target_config` (where it
   is a slightly awkward fit, since it bypasses LLVM), or introduce a
   shared `backend_target` type that both `Llvm_emit` and `Js_emit` consume?
   Leaning toward a shared type to avoid `Llvm_emit` owning a non-LLVM
   variant.
3. **Import resolution:** resolve `js_extern` symbols against
   `globalThis`, against ES module imports, or both (configurable)? Default
   proposal: relative ES module imports for curated bindings, with a
   documented escape hatch.
