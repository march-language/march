# Lazy-stdlib Step 3: close it, unless a consumer appears

**Date:** 2026-09-18
**Status:** design / recommendation.
**Scope:** Step 3 of
`specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md`
— *"give lazy modules real inference"* — the last open part of that `[P1]`.

**Recommendation: close Step 3, and with it the todo.** Steps 1 and 2 have
already turned the class bug from *silent wrong value* into *cannot ship
without a compile error*. Step 3 would make a lazily-loaded module work instead
of fail loudly. It has, today, no consumer to make work.

---

## 1. Where the three steps leave the class bug

The class: a stdlib module outside the eager manifest is read for export
**shapes** only, so monomorphization reaches its calls with the return type
unresolved, emits the generic boxed body, and a caller at a concrete
niche-eligible type reads the wrong bits.

| step | what it does | status |
|---|---|---|
| 1 | a test fails the build if any `stdlib/*.march` is outside the manifest (bar an explicit allowlist) | landed 2026-08-03 |
| 2 | mono refuses an unspecializable call whose caller and callee disagree about the return representation | landed 2026-09-18 (#511) |
| 3 | lazily-loaded modules get real type inference, so the call specializes | **open** |

After Step 2 the failure is a compile error naming the call and the fix, in
every compiled path. Mono is shared by the native compiler and the REPL/JIT
(`Contract_pipeline` → `Mono.monomorphize`), so there is no compiled path it
does not cover.

## 2. Who still takes the lazy path

`Module_registry.ensure_loaded` parses and desugars a module for its exports and
nothing more. Its callers are typecheck's qualified-name resolution and REPL
completion. It only fires for a module that is **not already registered**, and
every manifest module is registered up front. It only looks in the stdlib
directory (`find_stdlib_file`), so user libraries on `MARCH_LIB_PATH` never
reach it.

So the lazy parse runs for exactly:

- **`lazy_niche_probe.march`** — the allowlist's only entry, a regression
  fixture that exists to keep the lazy path exercised. It works:
  `test/native/lazy_niche.march` prints `42 / 99`.
- **`dom.march`, `canvas.march`, `audio.march`** — JS-only modules, if a
  native build references them.

Step 2's measurement agrees from the other direction: 2,204 unspecializable
calls across 316 programs, **zero** representation disagreements. The class does
not occur in the corpus once the manifest is exhaustive.

## 3. Why not build it anyway

- **It solves a problem nobody has.** The only realistic way to reintroduce the
  bug is adding a stdlib module without adding it to the manifest, and Step 1
  fails the build when that happens.
- **It works against the reason lazy loading exists.** The lazy path is cheap
  because it does no inference. Running real inference in it — on demand, in the
  caller's context, recursing through whatever the lazy module references — makes
  it about as expensive as eager loading, without eager loading's predictability.
  The todo's own Step 3 text calls this *"the expensive one, and it partially
  defeats the purpose of lazy loading"*.
- **The failure is no longer silent.** The case for Step 3 was that the failure
  produced garbage with no diagnostic. It now produces a compile error that says
  what to do.

## 4. If a consumer does appear

The trigger would be a real need for a module that must load lazily AND be
called from compiled code at a niche-eligible type — for example a large,
rarely-used stdlib module kept out of the manifest to save startup time.

The simpler option then is not Step 3 as written, but **eager loading on demand
in compiled builds only**: when a compiled build resolves a lazily-registered
module, promote it to a full load — the same path manifest modules take —
instead of shape-extraction. Interactive tools (REPL completion, LSP) keep the
cheap path, since the class bug is compiled-only and they never emit the
miscompile. That gets the correctness of Step 3 without doing inference inside
the lazy loader.

Only if even that is too slow is inference inside `ensure_loaded` worth building.

## 5. Proposed disposition

- Move the todo to `specs/progress/` with Steps 1–2 recorded as the fix and
  Step 3 recorded as **not built, with reasons** — this document.
- Keep `lazy_niche_probe.march` and its test. It is what proves the lazy path
  still works, and it would notice if the eager-on-demand option above were
  ever built and broke it.
- If the §4 trigger ever happens, reopen as a new todo scoped to that module.
