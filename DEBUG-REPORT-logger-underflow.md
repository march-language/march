# RC-underflow in the conduit logger path — root-cause report

**Status: FIXED.** The "RC underflow" is **not a Perceus/RC bug**. It was a downstream
*symptom* of a **name-resolution bug in lowering**: in the multi-package forgepm build,
conduit's 1-argument `Logger.debug(msg)` call (typechecked against the stdlib
`Logger.debug/1`) was **re-resolved at lowering** to the **2-argument**
`Bastion.Logger.debug/2`, leaving the second argument (`meta`) an *uninitialized
register*. `Logger.do_log` then `dec_rc`s that garbage pointer → `RC underflow` (or
SIGSEGV once the garbage is a mid-object interior pointer).

`perceus.ml` and friends are **correct** and untouched.

---

## FIX (commit on rc-underflow-fix)

### Exact drop point
`lib/tir/lower_state.ml`, function `resolve_use_alias` (the lowering-side callee
name resolver, re-exported as `Lower.resolve_use_alias` and applied to every
`EVar` callee in `lower.ml`). The offending line was the **program-global**
`_use_aliases` fallback:

```ocaml
| None ->
  match Hashtbl.find_opt !_use_aliases name with   (* <-- consulted for DOTTED names too *)
```

`_use_aliases` is a single process-global table populated by **every** module's
bulk imports. `bastion/lib/http/bastion_server.march:16` does `import Bastion`
(UseAll); `register_aliases` (lower.ml ~1252) strips only the `Bastion.` prefix,
registering the **dotted** short name `"Logger.debug" -> "Bastion.Logger.debug"`
program-wide. When lowering `Conduit.Worker.start_workers` (a module that never
imported Bastion — its `current_module_aliases` miss), the global fallback fired
and rewrote the qualified `Logger.debug` to `Bastion.Logger.debug`. Confirmed
live: instrumenting `resolve_use_alias` printed
`[ALIAS-DBG] `Logger.debug` -> `Bastion.Logger.debug`` **81×** in the forgepm
build. The typechecker never diverges because its import scoping is per-module
(conduit binds stdlib `Logger.debug/1`); only lowering's global table leaks.

### The fix (surgical, +1 guard)
Restrict the global `_use_aliases` fallback to **unqualified (dot-free)** names.
A module-qualified reference like `Logger.debug` is only ever legitimately
rewritten by (a) the current module's OWN import table (`current_module_aliases`,
checked first — the importing module registers the dotted alias there too, so it
still resolves) or (b) the explicit `alias … as Short` `_module_aliases` prefix
rewrite (checked after). This matches the typechecker's per-module scoping:

```ocaml
match (if String.contains name '.' then None
       else Hashtbl.find_opt !_use_aliases name) with
```

This is the "carry typecheck's resolution" intent realized as a minimal lowering
guard (no cross-pass field plumbing needed): a qualified callee the typechecker
resolved per-module is no longer re-bound by another module's global import.

### Evidence
- **Minimal mechanism repro** (`/tmp/hijack`, forge multi-file): module
  `Bastion.Server` does `import Bastion`; unrelated `Conduit.Worker.go` calls bare
  `Logger.debug(msg)`. Pre-fix: `Conduit.Worker.go` emits `bl _Bastion.Logger.debug`
  (no `_Logger.debug` symbol). Post-fix: it emits `bl _Logger.debug`; the importing
  `Bastion.Server` still resolves ITS `Logger.debug` to `Bastion.Logger.debug/2`.
  (The compiled crash itself is register-content dependent, so the regression test
  asserts the resolution invariant directly rather than relying on a SIGABRT.)
- **Regression test**: `test/test_codegen.ml` →
  `name_resolution / "qualified call not hijacked by another module's global import"`
  (`test_qualified_alias_no_cross_module_hijack`). Drives `resolve_use_alias`
  directly: a non-importing module's `Logger.debug` must stay `Logger.debug`; an
  importing module's stays `Bastion.Logger.debug`; unqualified global aliases still
  apply. **FAILS pre-fix** (returns `Bastion.Logger.debug`), passes post-fix.
- **Suites**: `run_codegen` 406/406 pass; `run_eval` 232/232 pass. The failures
  seen under `dune runtest` (`forge check: qualified-call cycle`, refactor
  `introduce parameter object`, LSP code-action quickfixes, format `record literal`,
  and the QCheck `generated programs`/`type soundness` generator flakiness) are
  **pre-existing** — verified identical with the fix stashed, and none of those
  paths invoke `Lower.resolve_use_alias`.
- **End-to-end (compiled forgepm worker)**: pre-fix aborted right after
  `WORKER-REPRO: starting conduit workers/cron`. **Post-fix it runs clean**:
  ```
  WORKER-REPRO: starting conduit workers/cron
  [DEBUG] conduit: start_workers queue=docs count=2     <- the crashing log now works
  [DEBUG] conduit: start_workers queue=email count=2
  WORKER-REPRO: running
  WORKER-REPRO: exit
  ```
  The Logger RC underflow is gone; the worker progresses to completion.

### Follow-up fix: entry-file top-level bulk imports (`lib/tir/lower.ml`)
Restricting the global `_use_aliases` fallback to unqualified names exposed a
latent gap: the three TOP-LEVEL `DUse` arms (`lower.ml` ~1338/1346/1359 — the
entry file's own imports) wrote ONLY the global table, never the entry module's
`current_module_aliases` (unlike the nested-import path at ~1258, which writes
both). Post-fix, an entry file that does `import Foo` (UseAll, `Foo` has a
sub-module `Foo.Sub`) and then calls the partial-qualified `Sub.fn(...)` — the
normal post-bulk-import form, which the typechecker binds per-module to
`Foo.Sub.fn` — would lowering-diverge: the dotted `Sub.fn` skips the now
dot-free-only global fallback, misses `current_module_aliases`, and emits an
undefined `_Sub.fn` symbol (same failure direction as the original bug, for a
legitimate import). Reproduced live (`/tmp/entryimp`): `Undefined symbols:
"_Sub.greet"`.

Fix: mirror the nested handler — the top-level `DUse` arms now register each
alias into BOTH `!_use_aliases` and `env.current_module_aliases` (via a shared
`register` helper, first-wins). The entry file then resolves the partial form
per-module like both typecheck and the nested path, without reopening the
global-hijack hole. Verified leak-free: an entry file that `import Bastion`
followed by a *separate* module's bare `Logger.debug` does NOT hijack that other
module (it still binds stdlib `Logger.debug/1`). Regression test:
`test/test_codegen.ml` name_resolution → "entry-file bulk import resolves
partial-qualified call" (asserts the emitted IR calls `@Foo.Sub.greet`, not a
bare unresolved `@Sub.greet(`). Fails pre-this-fix, passes post-fix. Suites
re-verified: `run_codegen` 406/406, `run_eval` 232/232; forgepm worker still
reaches `WORKER-REPRO: running`/`exit`.

## Follow-up (out of scope — sibling bug of the same family)

`_module_aliases` (`lib/tir/lower_state.ml` ~332-339, the dotted-prefix rewrite
fallback in `resolve_use_alias`) is the **same cross-module-global-hijack class**
as the bug fixed here. An `alias X.Y as Short` in one module registers
`Short -> X.Y` process-wide (`lower.ml` ~1284/1384); a colliding `Short.member`
reference in an unrelated module would be rewritten by that global entry even
though the typechecker scopes `alias` per-module. Not triggered by forgepm today
(no such colliding `alias`), so left out of scope for this commit — but it should
get the same per-module-scoping treatment (register the alias into the declaring
module's own table and stop consulting the global `_module_aliases` across
modules) in a follow-up.

---

## 1. Where it aborts (ground truth from the compiled forgepm worker)

Running the compiled worker (origin-test toolchain = this worktree's `march`) aborts
right after `WORKER-REPRO: starting conduit workers/cron`, on the FIRST
`Logger.debug` in `Conduit.Worker.start_workers`:

```
march: RC underflow (rc was 0) at 0x105f6b200 tag=1008799104 — aborting
  seq=1159 prev_rc=0 tag=1008799104 caller=… march_decrc_local
   go$apply$1798            (+204)   <- map_pairs_to_fields's `go`, Nil branch: `dec_rc lst`
   Logger.do_log           (+664)
   Bastion.Logger.debug    (+144)    <- 2-ARG wrapper, reached from a 1-arg call site
   Conduit.Worker.start_workers$R_database…$String$Int$Int (+456)
   Conduit.API.start …
```

- `tag=1008799104` (=0x3C240000) is **garbage** — not a valid `march_hdr` tag
  (strings=-1, ADT tags ≥0). `rc` reads 0. The pointer has exactly **one** record in
  the RC ring (the fatal dec): it was never `march_alloc`'d / `inc`'d as a real object.
  → the value being `dec_rc`'d is an **uninitialised register value** reinterpreted as
  a heap list pointer, not a double-freed object.

## 2. Disassembly proof of the arity mismatch

`Conduit.Worker.start_workers` call site (forgepm binary), crash return = base+456:

```
…0168440  bl _march_decrc_local     ; clobbers x0..x17 (incl. x1)
…016844c  bl _march_decrc_local     ; clobbers x1 again
…0168474  str x9,[x8]               ; x9 = msg
…0168478  ldr x0,[x8]               ; x0 = msg          <-- ONLY arg0 set
…016847c  bl _Bastion.Logger.debug  ; x1 (meta) = leftover garbage from the decrc
```

Contrast a **correct** 2-arg call (`Bastion.Logger.debug("x", Nil)`), which DOES set x1:

```
…str x0,[x8] ; ldr x1,[x8]          ; x1 = meta (Nil)   <-- arg1 set
…bl _Bastion.Logger.debug
```

`_Bastion.Logger.debug` itself is fine — it saves x1 and forwards it to
`Logger.do_log` as `extra`; `do_log`'s `map_pairs_to_fields` then `dec_rc`s that
`extra` (garbage) in its `Nil` branch. Everything downstream is a correct consumer of
a corrupt input.

## 3. Why this is a resolution bug, not RC

- Conduit source (`/Users/80197052/code/conduit/lib/conduit/worker.march:32`) is
  `Logger.debug("conduit: start_workers queue=" ++ …)` — **one arg**, intended for
  stdlib `Logger.debug/1`. Conduit does **not** depend on bastion.
- march **forbids** 1-arg calls to 2-arg fns (verified: "March has no partial
  application — a call must supply all arguments"). So typecheck must have bound to
  stdlib `Logger.debug/1`. Yet **codegen emitted a call to `Bastion.Logger.debug`**.
- The forgepm binary has `_Logger.do_log` and `_Bastion.Logger.debug` but **no
  `_Logger.debug`** at all — stdlib `Logger.debug/1` was never emitted; conduit's
  calls were redirected to `Bastion.Logger.debug/2`. This is a typecheck-vs-lowering
  divergence: the reference `Logger` (→ stdlib) was mangled/linked to the
  suffix-matching module `Bastion.Logger` present in the whole-program build.
- Class match: the **"d95fe942 resolution fallout"** family (`Logger` vs
  `Bastion.Logger` is a 4th instance). Fix belongs in name resolution / symbol
  mangling (`lib/typecheck` name resolution and/or `lib/tir/lower*` function-symbol
  lookup), **not** `lib/tir/perceus*.ml`.

## 4. Minimal repro status (the one gap)

I could NOT reduce this to a standalone compiler-suite fixture. Every isolated
reproduction — single-file nested `App.Logger`, and a faithful forge workspace with
`Bastion.Logger` (debug/2) + `Conduit.Worker` (bare `Logger.debug/1`) as separate
path-dep packages — **resolves correctly to stdlib `_Logger.debug`** and runs clean.
The mis-resolution only manifests with forgepm's full module graph (conduit + bastion
+ depot + forgepm + stdlib together), so it is load-order / module-count sensitive.
The resolver assembles all modules as top-level sibling `DMod`s
(`lib/resolver/resolver.ml:251-255`, which itself warns about name-mangling
collisions from module nesting); the collision is downstream of that, in the
`Logger.debug` → symbol binding.

## 5. Options for the fix (compiler-team follow-up)

1. **Make lowering's function-symbol lookup use the SAME resolved binding typecheck
   produced** (carry the fully-qualified home module of the callee from typecheck into
   TIR, instead of re-resolving the short name at lowering). This is the surgical fix
   and prevents the whole class.
2. **Reject/ði­agnose ambiguous module short-name binding** (`Logger` matching both
   stdlib `Logger` and a loaded `*.Logger`) at resolve/typecheck time rather than
   silently letting codegen pick a different module.
3. Defensive-only (not a fix): have `do_log`/`Bastion.Logger` treat `extra`/`meta`
   defensively — does not address the corrupt call and other suffix collisions remain.

## 6. Repro harness / evidence artifacts

- Instrumented RC ring + underflow dump lives in
  `~/.march/versions/origin-test/runtime/march_runtime.c` (alloc/local-free recording
  + temporal window + `dbg_report`). This is diagnostic only; the worktree
  `runtime/march_runtime.c` is reverted to clean.
- Compiled forgepm worker still underflows/segfaults at the same point
  (`WORKER-REPRO: starting conduit workers/cron` → abort) — this bug blocks it; the
  two prior fixes on this branch (f2b67001, 9c6d2f7c) still hold and are untouched.
- forgepm/conduit WORKER-REPRO + PoolConfig instrumentation preserved;
  `/Users/80197052/code/forgepm/.march-version` restored to `deploy-fix`.
