# JS FFI — Full `extern` Support on `--target js`

**Status:** spec, 2026-06-22

## Problem

`--target js` (the `lib/tir/js_emit.ml` backend) supports exactly one FFI shape
today: `extern "node:..."` / `extern "npm:..."` / relative-path imports, lowered
to ES `import { sym } from "spec"`. Tested by `test/native/js_extern_import.march`.

Everything else either silently miscompiles or is ignored:

1. **`blocking` externs** — `ed_blocking` is never read by `js_emit.ml`. The call
   is emitted as an ordinary synchronous call. A JS binding that does real I/O
   returns a `Promise`, so the March code receives a pending promise instead of
   the value. No error, no `await`.
2. **`raises` externs** — `ed_raises` is never read by `js_emit.ml`. A JS binding
   that signals failure by `throw` propagates the exception straight through the
   March stack instead of producing `Err(e)`. The declared `Result(T,E)` return
   is never constructed.
3. **C/runtime-backed externs on the JS target** — an `extern "rt"` / `extern "m"`
   (any non-JS-module lib name) emits `const <name> = <c_symbol>;`
   ([js_emit.ml:787-797](../../lib/tir/js_emit.ml)) referencing a C symbol that
   does not exist in `march_runtime.mjs`. The output is a `ReferenceError` at load
   time with no compile-time diagnostic.
4. **No JS test coverage for any of the above** — the `ffi_*.mjs` files in
   `test/native/` are stale checked-in stubs with **no dune rule** generating or
   running them. Only `js_extern_import` and `js_dom_available` have live JS rules
   ([test/dune:1309-1337](../../test/dune)).

The JIT and native targets already handle all four; this spec is **`js_emit.ml`
only** (plus its test wiring and the CLI/dev-server diagnostic path).

---

## Ground-truth references

Read these before implementing. Every design decision below is anchored here.

| What | Where |
|------|-------|
| Extern bridge emission (imports + consts + `$clo`) | [js_emit.ml:756-812](../../lib/tir/js_emit.ml) |
| `is_js_module` (JS-spec vs C-lib classification) | [js_emit.ml:749-754](../../lib/tir/js_emit.ml) |
| Extern call-site emit + `used_externs` tracking | [js_emit.ml:358-365](../../lib/tir/js_emit.ml) |
| First-class extern ref tracking (`emit_atom`/`EDefunId`) | [js_emit.ml:146-159](../../lib/tir/js_emit.ml) |
| `$clo` wrapper for first-class extern use | [js_emit.ml:800-808](../../lib/tir/js_emit.ml) |
| `emit_module` preamble assembly + exports + `main()` | [js_emit.ml:880-940](../../lib/tir/js_emit.ml) |
| `extern_decl` (`ed_blocking`, `ed_raises`, `ed_ret`, …) | [tir.ml:83-93](../../lib/tir/tir.ml) |
| Constructor JS layout `{$:"Ctor",_0,_1}` | [js_emit.ml:5-6,405-422](../../lib/tir/js_emit.ml) |
| Function-decl emit (`function name(...)` + `$clo`) | [js_emit.ml:658-690](../../lib/tir/js_emit.ml) |
| `emit_module` call site + map writing (driver) | [bin/main.ml:1260-1300](../../bin/main.ml) |
| Live JS test rules (pattern to copy) | [test/dune:1309-1337](../../test/dune) |
| No-panic transitive call-graph analysis (pattern to mirror for async) | search `check_no_panic_module` / `calls_in_expr` in `lib/typecheck` |

### Value representation on JS (why there is no marshal layer)

March values are emitted as **native JS values** — there is no `march_value`
int64 encoding on this target:

| March | JS |
|-------|-----|
| `Int`, `Float` | `number` |
| `Bool` | `boolean` |
| `String`, `Bytes` | `string` |
| tuple | `{ _0, _1, … }` |
| record | `{ field0, field1, … }` |
| ADT / `Some`/`Ok`/… | `{ $: "Ctor", _0, _1, … }` |

So a JS-module extern's args and return **pass through untouched**. The only
bridging needed for chunks A/B is *control flow* (promise `await`,
`try`/`catch` → `Result`), not data marshalling. This is the fundamental reason
the JS work is ~10% the size of the native interpreter FFI work.

---

## Scope

| Chunk | Feature | In scope | Deferred |
|-------|---------|----------|----------|
| **0** | Shared call-emission seam | factor call-site + `$clo` into one routed function | — |
| **C** | C-extern diagnostic | clear compile error on `--target js` for non-JS-module externs | runtime polyfills for C builtins |
| **B** | `raises` externs | `try`/`catch` → `Ok`/`Err`; `E = String` error marshalling | non-`String` `E` (best-effort `.message`); `raises` on first-class refs |
| **A** | `blocking` externs | viral `async`/`await` over the call graph; direct calls; top-level `await main()` | `blocking`/`async` fns used *first-class* (ECallPtr) → diagnostic |
| **D** | Test coverage | dune rules + `.march`/`.expected` fixtures running under `node` | — |

**Permanent non-goals:** changing March's surface syntax; an async type
discipline (async stays an emit-time inference, invisible in the type system);
marshalling C-ABI `march_value`s in JS (chunk C rejects instead).

---

## Architecture

### Dependency graph (what blocks what)

```
        ┌─────────────┐
        │  Chunk 0    │  (small seam refactor; merge-friendly base)
        │ call seam   │
        └──────┬──────┘
       ┌───────┼───────┐
       ▼       ▼       ▼
   ┌──────┐┌──────┐┌──────┐
   │ A    ││ B    ││ C    │   ← fully parallel after 0 lands
   │block ││raises││diag  │
   └──┬───┘└──┬───┘└──┬───┘
      └───────┼───────┘
              ▼
          ┌──────┐
          │ D    │   ← fixtures authored in parallel; rules wired as A/B/C land
          │tests │
          └──────┘
```

**Chunk 0 is the only sequential prerequisite** and is deliberately tiny (one
refactor, no behaviour change). After it merges, A, B, and C edit *disjoint
branches* of the same routed function and disjoint helpers, so they do not
conflict. D's fixtures can be written from this spec immediately; only the dune
`(rule …)` wiring for a given feature waits on that feature landing.

### Chunk 0 — the shared call-emission seam

**Why:** A and B both need to change (a) how an extern is *called* at a direct
call site ([js_emit.ml:358-365](../../lib/tir/js_emit.ml)) and (b) the `$clo`
wrapper body ([js_emit.ml:800-808](../../lib/tir/js_emit.ml)). If each chunk
edits both raw sites independently they collide. Factor both through one
function first.

**Files:** `lib/tir/js_emit.ml` only.

Introduce a single classifier and a single invocation emitter:

```ocaml
(* Classify an extern for the JS target. *)
type js_extern_kind =
  | JsModuleSync     (* import { sym } from "spec"  — current happy path *)
  | JsModuleBlocking (* same, but await the result (Chunk A) *)
  | JsModuleRaises   (* same, but try/catch -> Result (Chunk B) *)
  | CBacked          (* non-JS-module lib name — unsupported (Chunk C) *)

let classify_js_extern (ed : Tir.extern_decl) : js_extern_kind =
  if not (is_js_module ed.Tir.ed_lib_name) then CBacked
  else if ed.Tir.ed_blocking then JsModuleBlocking
  else if ed.Tir.ed_raises   then JsModuleRaises
  else JsModuleSync
```

Route the direct call site through one helper. Today
[js_emit.ml:358-365](../../lib/tir/js_emit.ml) does:

```ocaml
| _, _ ->
  if Hashtbl.mem ctx.extern_fns name then
    Hashtbl.replace ctx.used_externs name ();
  emit ctx (mangle name ^ "(");
  List.iteri (...) args;
  emit ctx ")"
```

Replace the body with a dispatch on `extern_fns`:

```ocaml
| _, _ ->
  (match Hashtbl.find_opt ctx.extern_fns name with
   | Some ed ->
     Hashtbl.replace ctx.used_externs name ();
     emit_extern_call ctx ed args         (* <- new single seam *)
   | None ->
     emit ctx (mangle name ^ "(");
     List.iteri (...) args;
     emit ctx ")")
```

For Chunk 0, `emit_extern_call` reproduces today's behaviour exactly (plain
`mangle name (args…)`) for every kind — **no observable change**. A, B, and C
each add their `match` arm to `emit_extern_call` and to the `$clo`-wrapper
builder (also extracted in Chunk 0 as `emit_extern_clo ctx ed`).

**Acceptance for Chunk 0:** `dune build` clean; the `js_extern_import` and
`js_dom_available` outputs are *byte-identical* to before (golden check — see
Chunk D's snapshot helper, or diff against the committed `.mjs`).

---

### Chunk C — diagnostic for C-backed externs

**Goal:** A non-JS-module extern compiled with `--target js` must produce a
clear, actionable compile error instead of a `ReferenceError` at JS load time.

**Files:** `lib/tir/js_emit.ml`, and the error surface in `bin/main.ml` (and the
dev-server build path if it has its own error formatting).

**Design.** In `emit_extern_bridges` the `rt_externs` branch
([js_emit.ml:787-797](../../lib/tir/js_emit.ml)) currently emits a dangling
`const alias = c_symbol`. Replace silent emission with collection of offending
externs, and fail the JS emit with a diagnostic listing each:

```
error: extern "rt" function `dbl` cannot be called on the JavaScript target.
       The JS backend supports only JS-module externs:
         extern "node:fs"   extern "npm:lodash"   extern "./local.mjs"
       `dbl` is bound to the C symbol `ffi_test_dbl`, which has no JS runtime
       implementation. To call it from JS, wrap it in a JS module, or build a
       native/wasm target.
```

**Mechanism options (pick one during impl):**

- **Preferred:** have `emit_module` return `(string * string option, diagnostics)`
  or raise a dedicated `Js_emit_error of string list`. The driver
  ([bin/main.ml:1260-1300](../../bin/main.ml)) catches it and prints via the
  standard error path, exiting non-zero. This keeps `js_emit.ml` pure-ish and
  routes through existing error formatting.
- **Simpler interim:** `failwith`/`eval_error`-style raise with the formatted
  message; driver already surfaces uncaught compile failures.

**Edge cases:**
- Only externs that are *actually used* (`used_externs`) should error — an unused
  C-backed extern in a module otherwise targeting JS should not block the build
  (mirrors the existing lazy-bridge filter at
  [js_emit.ml:897-899](../../lib/tir/js_emit.ml)). Decide explicitly and test
  both: used → error, unused → silent.
- `march_*`-prefixed builtins that the JS runtime *does* provide (e.g.
  `march_print`, `march_string_byte_length`) are not user externs — they go
  through `use_runtime`, not `extern_fns`, so they are unaffected. Confirm none
  leak into the C-backed branch.

**Tests (Chunk D wires these):** a `.march` with a used C-backed extern compiled
`--target js` exits non-zero with the message; the same extern unused compiles
clean.

---

### Chunk B — `raises` externs

**Goal:** `raises fn f(args) : Result(T, E) = "jsExport"` from a JS module
becomes a call that turns a JS `throw` into `Err` and a normal return into `Ok`.

**Files:** `lib/tir/js_emit.ml` (the `JsModuleRaises` arms of `emit_extern_call`
and `emit_extern_clo`).

**Semantics.** On native, a `raises` binding's C symbol returns the **bare `T`**
and routes errors through `march_env`. The JS analogue: the imported JS function
returns the bare `T` and signals failure by **throwing**. The wrapper builds the
`Result`:

```js
// direct call site for  f(a, b)
(() => { try { return { $: "Ok", _0: jsExport(a, b) }; }
         catch (e) { return { $: "Err", _0: __js_err_to(e) }; } })()
```

and the first-class `$clo`:

```js
const f$clo = { _0: ($_, p0, p1) => {
  try { return { $: "Ok", _0: jsExport(p0, p1) }; }
  catch (e) { return { $: "Err", _0: __js_err_to(e) }; }
} };
```

**Error marshalling `__js_err_to(e)`** — driven by the `E` type in
`ed_ret = Result(T, E)`:
- `E = String` (the common, in-scope case): `String(e?.message ?? e)`.
- Other leaf `E`: best-effort — emit `String(e?.message ?? e)` and **warn at
  compile time** that non-`String` error types receive the JS message string.
  (Full structured-error marshalling is deferred; document it.)

**`ed_ret` shape — RESOLVED.** `ed_ret` holds the **full declared
`Result(T, E)`** (`ed_ret = lower_ty ef.ef_ret_ty` at
[lower.ml:2162,2177,2186,2201](../../lib/tir/lower.ml)). Confirmed by the native
backend, which extracts `T` via `ok_payload_ty ed.ed_ret` at
[llvm_emit.ml:5444](../../lib/tir/llvm_emit.ml). So Chunk B:
- `Ok` payload is pass-through (the JS fn returns the bare `T` value already in
  native JS representation — no extraction of `T` needed for the *value*, only
  the `Ok` wrapper around it).
- `E` for the error marshaller = the **second type argument of `ed_ret`**.
  Reuse/imitate `ok_payload_ty` to destructure `Result(T,E)` and read `E`.

**Helper placement.** `__js_err_to` is a single emitted helper; add it to the
preamble alongside `builtin_wrappers` ([js_emit.ml:864-874](../../lib/tir/js_emit.ml))
**only when at least one `raises` extern is used** (gate like the runtime
wrappers).

**Interaction with A:** a binding that is *both* `blocking` and `raises` →
`async` wrapper with `try`/`catch` around an `await`ed call. Spec the combined
arm but it can land in whichever of A/B merges second (the second one adds the
`JsModuleBlocking && raises` case). Until then, reject the combination with a
diagnostic so neither chunk silently mishandles it.

**Tests (Chunk D):** `parse_int_or_throw(s) : Result(Int,String)` over a JS
module that throws on bad input — assert both `Ok` and `Err` branches print
correctly under `node`.

---

### Chunk A — `blocking` externs (viral async)

**Goal:** `blocking fn f(...) : T = "jsAsyncExport"` whose JS export returns a
`Promise` is `await`ed, and every March function that (transitively) reaches such
a call is emitted as an `async function`, all the way up to `main`.

**Files:** `lib/tir/js_emit.ml`. Adds one analysis pass + emit changes; no TIR
type changes.

**Why viral async.** March has no async type. The JS export is `async`
(returns a Promise). To get the *value* the March program expects, the call must
be `await`ed, which forces the enclosing JS function to be `async`, which forces
its callers to `await`, etc. This is a standard async-colouring propagation.

**The analysis — mirror `check_no_panic_module`** (the codebase already has a
seed + fixpoint over `calls_in_expr`; reuse the shape):

1. **Seed:** a TIR function is async if its body contains a direct call to a
   `blocking` JS-module extern. (Reuse `extern_fns` + `classify_js_extern =
   JsModuleBlocking`.) Build the per-function call set from the TIR body
   (analogous to `calls_in_expr` but over `Tir.expr`/`Tir.atom`).
2. **Fixpoint:** a function is async if it calls any async function. Iterate to a
   fixed point over `tm_fns`.
3. Store the async set in `ctx` (`async_fns : (string, unit) Hashtbl.t`),
   populated in `emit_module` *before* `List.iter (emit_fn_decl ctx) tm_fns`.

**Emit changes:**
- `emit_fn_decl_impl` ([js_emit.ml:658-690](../../lib/tir/js_emit.ml)): if
  `Hashtbl.mem ctx.async_fns fn.fn_name`, emit `async function …`. The `$clo`
  wrapper's `_0` arrow for an async fn becomes `async ($_, …) => …`.
- `emit_extern_call` `JsModuleBlocking` arm: wrap the call in `(await jsExport(…))`.
  (Parenthesise so it composes inside larger expressions.)
- Call sites to **async user functions**: prefix with `await`. The call-site
  emitter must know the callee is async — for direct calls
  ([js_emit.ml:358-365](../../lib/tir/js_emit.ml)) check `ctx.async_fns`.
- **Top level:** `main` becomes async; the trailing `main();`
  ([js_emit.ml:923-925](../../lib/tir/js_emit.ml)) becomes `await main();`
  (valid: ES module top-level await) or `main().catch(e => { … process.exit?
  })`. Pick top-level `await main();` for simplicity; note the Node version
  requirement (top-level await needs `"type":"module"`, which the `[js_deps]`
  package.json already sets).

**Scoping decision (keeps the chunk bounded):** support `blocking`/`async`
functions only when called **directly** (`EApp`). If an async function or a
`blocking` extern is used **first-class** (captured, passed to `ECallPtr`
dispatch `f._0(f, …)` at [js_emit.ml:440](../../lib/tir/js_emit.ml)), the await
point is not statically known. For v1, **detect and reject** this with a clear
diagnostic ("a blocking/async extern cannot be used as a first-class value on the
JS target; call it directly"). Full first-class async (await-at-dispatch via
always-`await`ing every `ECallPtr`, or runtime promise detection) is deferred.

**Correctness note — over-awaiting is safe but avoid it.** `await x` on a
non-promise is a no-op in JS, so a coarser "await every user call" would be
*correct* but would make every function async and tank performance. The fixpoint
keeps `async` minimal — only functions that actually need it.

**Tests (Chunk D):** `sleep_ms`-style async JS export + a March chain
`main → a → b → blocking_extern`; assert all four become async in the output and
the program prints the awaited value in order.

---

### Chunk D — test coverage

**Goal:** live, run-under-`node` tests for A/B/C, plus lock in Chunk 0's
no-change guarantee.

**Files:** `test/native/js_ffi_*.march` + `.expected` + `.mjs` JS module fixtures
+ `test/dune` rules. Mirror the existing pattern at
[test/dune:1309-1337](../../test/dune):

```
(rule
 (targets js_ffi_raises.mjs)
 (deps (file native/js_ffi_raises.march) native/js_ffi_helper.mjs march_runtime.mjs)
 (action (run %{exe:../bin/main.exe} --target js -o js_ffi_raises.mjs
              native/js_ffi_raises.march)))
(rule
 (targets js_ffi_raises.out)
 (deps js_ffi_raises.mjs native/js_ffi_helper.mjs march_runtime.mjs)
 (action (with-stdout-to js_ffi_raises.out (run node js_ffi_raises.mjs))))
(rule (alias runtest) (action (diff native/js_ffi_raises.expected js_ffi_raises.out)))
```

Fixtures to author (independent of impl; write from this spec now):
- `js_ffi_raises.march` + `js_ffi_helper.mjs` exporting a throwing fn → Chunk B.
- `js_ffi_blocking.march` + async helper export → Chunk A.
- `js_ffi_cbacked.march` (uses `extern "rt"`) → Chunk C; this is a
  **negative** test: a dune rule asserting the compile *fails* with the
  diagnostic (use a rule that captures stderr and diffs, or `(with-accepted-exit-codes …)`).
- Chunk 0 guard: keep `js_extern_import` / `js_dom_available` green (they already
  exist) — no new fixture, just don't regress them.

**Cleanup:** delete the stale, unreferenced `test/native/ffi_*.mjs` stubs (they
are checked-in artifacts with no rule and mislead readers into thinking JS FFI is
tested). Confirm none are `(deps …)` of any rule before removing
(`grep ffi_.*\.mjs test/dune`).

---

## Implementation order & parallelism

1. **Chunk 0** (one engineer, ~half a day): land the seam. Blocks A/B but not C
   or D-fixtures.
2. **A, B, C in parallel** once 0 is merged. Each is a separate branch touching
   disjoint arms of `emit_extern_call`/`emit_extern_clo` + its own helper. C can
   even start before 0 (it only needs `classify_js_extern`, which is the smallest
   slice of 0 — or C can inline the `is_js_module` check it already has).
3. **D fixtures** authored in parallel with 1–2 from this spec. **D rules**
   merged per-feature as A/B/C land (each feature PR includes its own dune rule +
   fixture, with the negative C-test gated on C).

Each chunk is independently shippable and adds rows to `specs/todos.md` +
`specs/progress.md` in the same commit (per CLAUDE.md).

---

## Open questions / risks

- **`ed_ret` for `raises`** (Chunk B): confirm whether it is `Result(T,E)` or
  unwrapped `T`; the `E`-marshaller selection depends on it. Resolve before B
  starts; record the answer here.
- **First-class async** (Chunk A): v1 rejects `blocking`/`async` used via
  `ECallPtr`. If a real program needs it, the follow-up is either always-`await`
  at dispatch (perf cost) or a runtime `instanceof Promise` check at the
  dispatch site.
- **`blocking && raises`** combination: spec'd as async-wrapper-with-try/catch;
  lands with whichever of A/B merges second. Until both land, reject the combo.
- **Top-level await Node support** (Chunk A): requires ESM (`"type":"module"`),
  already guaranteed by the `[js_deps]` package.json generator and the `.mjs`
  extension. No extra work, but note it in the docs update.
- **Non-`String` error types** (Chunk B): best-effort `.message` with a compile
  warning; full structured error marshalling deferred.
- **Docs:** update `docs/tooling.md`'s "JS FFI" section with `blocking`/`raises`
  examples and the C-extern limitation once A/B/C land.
