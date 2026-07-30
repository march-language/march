# LSP Incremental Typecheck Engine — Implementation Plan (Phase 5, final increment)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop re-typechecking the entire stdlib (and forge deps) on every keystroke. Typecheck the invariant prefix (stdlib, then deps) **once**, cache the resulting typing environment, and on each edit typecheck **only the user file's declarations** layered on top — then finish the remaining Phase 5 workspace items (disk-watch invalidation, debounce, JSON-RPC integration tests).

**Architecture:** The dominant per-keystroke LSP cost is `Analysis.analyse` concatenating `stdlib_decls @ extra_decls @ user_decls` into one module and running `Tc.check_module_full` (= `check_module_core`) over the whole thing (`lsp/lib/analysis.ml:1396-1398`). The compiler already has an incremental entry point — `Tc.check_module_with_env` — that the REPL JIT uses to typecheck user input against a pre-built stdlib env without re-checking stdlib. We lift that pattern into the LSP: a content-keyed memo of the *typed environment* (the salsa "base inputs" idea, one layer above Phase 1's parse-only stdlib memo). The CAS's *value here is its discipline* (content hashing for invalidation), reused at the env layer; its TIR-keyed artifact store stays where it is (`run_tir_pass`).

**Why not AST-level sig/impl hashing (the original Phase-5 seed):** the existing `March_cas.Serialize`/`Hash` operate exclusively on **TIR** (`fn_def`/`expr`/`ty`), downstream of the typecheck we want to skip. A per-def AST firewall would require canonical serialization of the entire surface `decl`/`expr`/`pattern` algebra (large, high-risk) to recover a cost that is dominated by the stdlib prefix anyway. Caching the typed env captures that dominant cost with the *existing* incremental typechecker and ~no new serialization surface. Per-def in-file invalidation is documented as a deferred follow-up (Increment G).

**Tech Stack:** OCaml, the March compiler libs (`march_typecheck`, `march_ast`, `march_cas`, `march_tir`), `linol`/`linol-lwt`, `alcotest`. Build with `dune build --root .` from the worktree (worktrees nest inside the parent repo, so plain `dune` walks up).

---

## File Structure

**Created:**
- `lsp/lib/typecheck_cache.ml` — process-lifetime memo of the typed base env (stdlib, then stdlib+deps), keyed by a content hash of the inputs + compiler identity. One responsibility: hand back a reusable `Tc.env` with the invariant prefix already checked. (~120 lines)
- `lsp/test/test_incremental.ml` — focused alcotest suite for the cache + equivalence + watch/debounce helpers.

**Modified:**
- `lib/typecheck/typecheck.ml` — add `check_module_with_env_full` returning `(Err.ctx * type_map * env)` (the existing `check_module_with_env` discards its `_final_env`, which the LSP needs for completions/ctor enumeration).
- `lsp/lib/analysis.ml` — `analyse` builds/reuses the cached base env and layers user(+deps) decls via the incremental checker; add a `run_tir_pass` source-hash memo.
- `lsp/lib/server.ml` — register `didChangeWatchedFiles` (invalidate workspace + env-deps caches on disk edits) and add a coalescing debounce to `did_change`.
- `lsp/bin/main.ml` / `lsp/lib/dune` / `lsp/test/dune` — wire the new module/tests.
- `specs/features/lsp-server.md`, `specs/progress.md`, `specs/todos.md` — record shipped state.

---

## Increment 0: `check_module_with_env_full` (env-returning incremental check)

The LSP consumes `final_env` (ctors/vars/types/interfaces/impls — `analysis.ml:1487,1939-1963`). `check_module_with_env` already computes the final env (`typecheck.ml:6341`) but throws it away. Expose it.

**Files:** Modify `lib/typecheck/typecheck.ml`; Test `lsp/test/test_incremental.ml`.

- [ ] **Step 1: Failing test** (`test_incremental.ml`) — checking a tiny module against a base env yields the same `f` type as the whole-module checker:

```ocaml
module Tc = March_typecheck.Typecheck

let parse src =
  let lb = Lexing.from_string src in
  March_desugar.Desugar.desugar_module
    (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lb)

let test_with_env_full_returns_env () =
  let base = parse "fn helper(x: Int) -> Int do\n  x + 1\nend\n" in
  let (_e, _tm, base_env) = Tc.check_module_full base in
  let user = parse "fn g() -> Int do\n  helper(41)\nend\n" in
  let (_errs, _tm2, final_env) =
    Tc.check_module_with_env_full base_env user in
  (* g is now bound in the layered env; helper carried over from the base. *)
  Alcotest.(check bool) "g bound"      true (Tc.StrMap.mem "g" final_env.Tc.vars);
  Alcotest.(check bool) "helper bound" true (Tc.StrMap.mem "helper" final_env.Tc.vars)
```

- [ ] **Step 2: Run, expect FAIL** — `Unbound value Tc.check_module_with_env_full`.
  `dune build --root . @lsp/runtest 2>&1 | tail`
- [ ] **Step 3: Implement.** In `typecheck.ml`, refactor `check_module_with_env` to delegate to a new `_full` variant. Add directly after `check_module_with_env` (≈line 6344):

```ocaml
(** Like [check_module_with_env] but also returns the final typing env.
    The LSP needs the env (ctors/vars/types) for completion + ctor enumeration. *)
let check_module_with_env_full (env : env) (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  let (errs, tm) = check_module_with_env env m in
  (errs, tm, !last_with_env_final)
```

Simplest robust form: make `check_module_with_env` store its `_final_env` so the wrapper can return it. Change `let _final_env = ...` (line 6341) to bind a module-level ref:

```ocaml
let last_with_env_final : env ref = ref (make_env (Err.create ()) (Hashtbl.create 0))
...
  let final_env = List.fold_left check_decl pre_env (reorder_decls m.Ast.mod_decls) in
  last_with_env_final := final_env;
```

(Declare `last_with_env_final` immediately above `check_module_with_env`.)

- [ ] **Step 4: Run, expect PASS.** Add `test_incremental` stanza to `lsp/test/dune`:

```lisp
(test
 (name test_incremental)
 (modules test_incremental)
 (libraries march_ast march_parser march_lexer march_desugar
            march_typecheck march_lsp_lib linol.lsp alcotest))
```

- [ ] **Step 5: Commit** — `git add lib/typecheck/typecheck.ml lsp/test/test_incremental.ml lsp/test/dune && git commit -m "feat(typecheck): check_module_with_env_full returns final env (for incremental LSP)"`

---

## Increment A: Cached stdlib base env

Build the stdlib-typechecked env once; per analysis, derive a copy with **fresh mutable fields** (so user decls don't pollute the cached env) and layer user+deps via `check_module_with_env_full`.

**Mutable fields that MUST be reset per analysis** (from `typecheck.ml:359-391`): `errors`, `type_map`, `pending_constraints`, `import_tracker`. Functional `StrMap` fields (`vars/types/ctors/records/interfaces/sigs/impls/local_fns/...`) are immutable and reused safely. `type_map` is *copied* (not emptied) so stdlib span→type entries survive for cross-stdlib hover.

**Files:** Create `lsp/lib/typecheck_cache.ml`; Modify `lsp/lib/analysis.ml`, `lsp/lib/dune`; Test `lsp/test/test_incremental.ml`.

- [ ] **Step 1: Failing test** — base env reused across calls is physically the same, and a derived env has an independent `type_map`:

```ocaml
let test_base_env_memoized () =
  let e1 = March_lsp_lib.Typecheck_cache.base_env () in
  let e2 = March_lsp_lib.Typecheck_cache.base_env () in
  Alcotest.(check bool) "same cached base env" true (e1 == e2)

let test_derive_isolates_type_map () =
  let base = March_lsp_lib.Typecheck_cache.base_env () in
  let d = March_lsp_lib.Typecheck_cache.derive base in
  Alcotest.(check bool) "fresh type_map" true (d.Tc.type_map != base.Tc.type_map)
```

- [ ] **Step 2: Run, expect FAIL** (`Typecheck_cache` unbound).
- [ ] **Step 3: Implement `typecheck_cache.ml`:**

```ocaml
(** Process-lifetime memo of the typed stdlib environment.

    Phase 1 memoized the *parse/desugar* of stdlib; this memoizes its
    *typecheck* — the dominant per-keystroke LSP cost, since [analyse]
    previously re-ran the whole-module typechecker over stdlib + user on
    every edit. Keyed by the same content+compiler discipline the CAS uses. *)

module Tc = March_typecheck.Typecheck
module Err = March_errors.Errors

(* The stdlib decls (already content-memoized by Stdlib_cache) typechecked
   into a base env, cached for the process lifetime. *)
let cache : (string, Tc.env) Hashtbl.t = Hashtbl.create 1

let key () =
  (* Stdlib_cache.load already keys on stdlib content; reuse the compiler
     identity so a rebuilt compiler busts this env too. *)
  Lazy.force March_cas.Cas.compiler_identity

let base_env () : Tc.env =
  let k = key () in
  match Hashtbl.find_opt cache k with
  | Some env -> env
  | None ->
    let stdlib_decls = Stdlib_cache.load () in
    let m : March_ast.Ast.module_ =
      { March_ast.Ast.mod_name = None; mod_decls = stdlib_decls; mod_docstring = None } in
    let (_errs, _tm, env) = Tc.check_module_full m in
    Hashtbl.replace cache k env;
    env

(* Derive a per-analysis env: reuse the (immutable) stdlib bindings but give
   fresh mutable state so layering user decls cannot mutate the shared base.
   [type_map] is COPIED so stdlib span->type entries are preserved. *)
let derive (base : Tc.env) : Tc.env =
  { base with
    errors              = Err.create ();
    type_map            = Hashtbl.copy base.Tc.type_map;
    pending_constraints = ref [];
    import_tracker      = ref [] }
```

> Verify the `module_` record field names (`mod_name`/`mod_decls`/`mod_docstring`) against `lib/ast/ast.ml` before building; adjust the literal if they differ.

- [ ] **Step 4: Rewire `analyse`.** In `lsp/lib/analysis.ml`, replace the stdlib-concatenation block (`analysis.ml:1394-1398`):

```ocaml
    let desugared =
      { desugared with
        Ast.mod_decls = stdlib_decls @ extra_decls @ desugared.Ast.mod_decls }
    in
    let (errors, type_map, final_env) = Tc.check_module_full desugared in
```

with the incremental layering:

```ocaml
    (* Incremental typecheck: stdlib is checked once into a cached base env;
       only deps + this file's decls are checked per edit. *)
    let base = Typecheck_cache.(derive (base_env ())) in
    let layered : Ast.module_ =
      { desugared with
        Ast.mod_decls = extra_decls @ desugared.Ast.mod_decls } in
    let (errors, type_map, final_env) =
      Tc.check_module_with_env_full base layered in
```

`stdlib_decls` is still bound above (line 1373) — it remains needed for `collect_docs`/def_map population (lines 1425,1444-1447). Leave those untouched.

- [ ] **Step 5: Add `Typecheck_cache` to the lib.** No dune change (same library auto-picks up the module). Confirm `march_cas` is already in `lsp/lib/dune` (it is).
- [ ] **Step 6: Run the FULL existing LSP suite — the regression gate.** This is the critical step: the 159 existing tests assert hover/def/completion/diagnostics behavior that must be byte-identical.

  `dune build --root . @lsp/runtest 2>&1 | tail -20` — expect **all green** (159 + new).

  If any fail, the layering diverged from `check_module_core` (likely a pass-1 prebinding gap for qualified names). Debug against the failing test's source; do NOT weaken the test.

- [ ] **Step 7: Equivalence test** — diagnostics for a representative file match between old and new paths. Add to `test_incremental.ml`:

```ocaml
module An = March_lsp_lib.Analysis
let test_incremental_matches_diagnostics () =
  let src = "fn f() -> Int do\n  true\nend\n" in  (* Bool vs Int *)
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "type error still reported" true (a.An.diagnostics <> []);
  let ok = "fn f() -> Int do\n  41\nend\n" in
  let b = An.analyse ~filename:"t.march" ~src:ok in
  Alcotest.(check bool) "clean file no errors" true
    (List.for_all (fun (d:Linol_lsp.Lsp.Types.Diagnostic.t) ->
       d.severity <> Some Linol_lsp.Lsp.Types.DiagnosticSeverity.Error) b.An.diagnostics)
```

- [ ] **Step 8: Commit** — `git add lsp/lib/typecheck_cache.ml lsp/lib/analysis.ml lsp/test/test_incremental.ml && git commit -m "perf(lsp): cache typed stdlib env; typecheck only user file per edit"`

---

## Increment B: Cache the deps layer too

Big forge deps (e.g. conduit) are re-checked every edit in Increment A. Cache an env = stdlib + deps, keyed by a content hash of the resolved dep decls, so only the user file is checked per edit.

**Files:** Modify `lsp/lib/typecheck_cache.ml`, `lsp/lib/analysis.ml`; Test `lsp/test/test_incremental.ml`.

- [ ] **Step 1: Failing test** — env for the same dep set is reused; a different dep set produces a different env:

```ocaml
let test_deps_env_memoized () =
  let base = March_lsp_lib.Typecheck_cache.base_env () in
  let deps = [] (* parse [] -> no extra decls *) in
  let e1 = March_lsp_lib.Typecheck_cache.deps_env base ~deps in
  let e2 = March_lsp_lib.Typecheck_cache.deps_env base ~deps in
  Alcotest.(check bool) "deps env memoized" true (e1 == e2)
```

- [ ] **Step 2: Run, expect FAIL** (`deps_env` unbound).
- [ ] **Step 3: Implement `deps_env`** in `typecheck_cache.ml`. Hash the dep decls by serializing their *desugared* form. Reuse a cheap structural key: `Marshal.to_string deps [Marshal.No_sharing]` hashed with Blake3 (decls contain no closures → marshalable):

```ocaml
let deps_cache : (string, Tc.env) Hashtbl.t = Hashtbl.create 8

let deps_key (deps : March_ast.Ast.decl list) : string =
  let payload =
    try Marshal.to_string deps [Marshal.No_sharing] with _ -> "" in
  March_cas.Blake3.hash_string (key () ^ "\x00" ^ payload)

(* stdlib + deps env, memoized by dep content. Mutable fields reset (derive). *)
let deps_env (base : Tc.env) ~(deps : March_ast.Ast.decl list) : Tc.env =
  if deps = [] then base
  else
    let k = deps_key deps in
    match Hashtbl.find_opt deps_cache k with
    | Some env -> env
    | None ->
      let scratch = derive base in
      let m : March_ast.Ast.module_ =
        { March_ast.Ast.mod_name = None; mod_decls = deps; mod_docstring = None } in
      let (_e, _tm, env) = Tc.check_module_with_env_full scratch m in
      Hashtbl.replace deps_cache k env;
      env
```

- [ ] **Step 4: Rewire `analyse`** to layer only user decls on top of the deps env:

```ocaml
    let base   = Typecheck_cache.base_env () in
    let with_deps = Typecheck_cache.deps_env base ~deps:extra_decls in
    let scratch = Typecheck_cache.derive with_deps in
    let (errors, type_map, final_env) =
      Tc.check_module_with_env_full scratch desugared in
```

(`desugared` here is the *user* module — drop `extra_decls` from its `mod_decls`; they live in the deps env now.)

- [ ] **Step 5: Regression gate** — `dune build --root . @lsp/runtest 2>&1 | tail -20`. All green. Also re-run the bastion/conduit cross-file ref tests if present.
- [ ] **Step 6: Commit** — `git add lsp/lib/typecheck_cache.ml lsp/lib/analysis.ml lsp/test/test_incremental.ml && git commit -m "perf(lsp): cache stdlib+deps env keyed by dep content (only user file rechecked)"`

---

## Increment C: `run_tir_pass` source-hash memo

`run_tir_pass` (`analysis.ml:2007`) re-lexes/parses the source and runs the full TIR pipeline to produce *insights* (not artifacts) — so `Cas.Pipeline.compile_scc` (returns artifact paths) does not fit. Cheap correct win: memo the computed insight fields by a hash of the user source, so a background fiber re-firing for unchanged text returns instantly.

**Files:** Modify `lsp/lib/analysis.ml`; Test `lsp/test/test_incremental.ml`.

- [ ] **Step 1: Failing test** — two `run_tir_pass` calls on the same source reuse the cached insight list (physical equality):

```ocaml
let test_tir_pass_memoized () =
  let src = "fn f(x: Int) -> Int do\n  x + 1\nend\n" in
  let a = An.analyse ~filename:"t.march" ~src in
  let a1 = An.run_tir_pass a in
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "tir insights memoized"
    true (a1.An.tir_fn_insights == a2.An.tir_fn_insights)
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Add a module-level memo above `run_tir_pass`:

```ocaml
let tir_pass_cache :
  (string, tir_fn_insight list * code_lens_item list * perf_insight list) Hashtbl.t
  = Hashtbl.create 16
```

At the top of `run_tir_pass` (after the `has_errors` guard), compute `let k = March_cas.Blake3.hash_string a.src in` and return the cached triple if present (splice the three fields into `a`). On miss, run the pipeline as today and `Hashtbl.replace` before returning.

- [ ] **Step 4: Run, expect PASS.** Regression gate green.
- [ ] **Step 5: Commit** — `git add lsp/lib/analysis.ml lsp/test/test_incremental.ml && git commit -m "perf(lsp): memoize run_tir_pass insights by source hash"`

---

## Increment D: `didChangeWatchedFiles`

The workspace index + deps env only refresh on `didSave` of an *open* doc (`server.ml:298`). Editing a dependency on disk (outside the editor, or a non-open file) leaves them stale. Register file watching and invalidate on change.

**Files:** Modify `lsp/lib/server.ml`; Test `lsp/test/test_incremental.ml` (invalidation helper).

- [ ] **Step 1: Failing test** for an invalidation hook exposed from `server.ml`:

```ocaml
let test_watched_invalidates () =
  let open March_lsp_lib.Server in
  invalidate_workspace_index ();   (* must not raise; resets cached index *)
  Alcotest.(check bool) "index cleared" true (workspace_index_is_empty ())
```

- [ ] **Step 2: Run, expect FAIL** (`invalidate_workspace_index`/`workspace_index_is_empty` unbound).
- [ ] **Step 3: Implement.** In `server.ml`, expose the existing workspace-index cache reset as `invalidate_workspace_index` and a `workspace_index_is_empty` predicate. Advertise watcher registration in `config_modify_capabilities` (or `on_initialized` via `client/registerCapability` for `workspace/didChangeWatchedFiles` with a `**/*.march` glob — use static `workspace.fileOperations`/`DidChangeWatchedFilesRegistrationOptions` if the linol version exposes it; otherwise rely on the client default and just handle the notification). Add:

```ocaml
method! on_notif_doc_did_change_watched_files ~notify_back:_ _params =
  invalidate_workspace_index ();
  Typecheck_cache.clear_deps ();   (* dep on disk changed -> drop deps env *)
  Lwt.return_unit
```

Add `let clear_deps () = Hashtbl.clear deps_cache` to `typecheck_cache.ml` and expose it. (If linol's class lacks that method name, handle `workspace/didChangeWatchedFiles` in the JSON `on_notification` fallback used elsewhere in `server.ml`.)

- [ ] **Step 4: Run, expect PASS.** Build the server: `dune build --root . lsp/bin/main.exe`.
- [ ] **Step 5: Commit** — `git add lsp/lib/server.ml lsp/lib/typecheck_cache.ml lsp/test/test_incremental.ml && git commit -m "feat(lsp): didChangeWatchedFiles invalidates workspace + deps caches"`

---

## Increment E: Debounce `did_change`

Coalesce bursts of keystrokes so the synchronous analyse + TIR fiber don't run per character. Version-coalescing already gates the *TIR fiber* (Phase 1.3); add a short time-window debounce of the AST analyse using Lwt.

**Files:** Modify `lsp/lib/server.ml`; Test `lsp/test/test_incremental.ml`.

- [ ] **Step 1: Failing test** for the debounce decision helper (pure, time injected):

```ocaml
let test_debounce_coalesces () =
  let open March_lsp_lib.Server in
  let st = make_debounce_state () in
  (* two edits within the window: only the later one should "win" *)
  Alcotest.(check bool) "first superseded" false
    (debounce_should_run st ~uri:"u" ~now:0.0 ~window:0.05 ~scheduled_at:0.0
       ~latest:0.02);
  Alcotest.(check bool) "settled run proceeds" true
    (debounce_should_run st ~uri:"u" ~now:0.06 ~window:0.05 ~scheduled_at:0.06
       ~latest:0.06)
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `make_debounce_state`/`debounce_should_run` (a `should_run` returns true only when no newer edit arrived within the window). Wire `did_change` to record the edit time and `Lwt.bind (sleep window)` before running analyse, bailing if a newer edit superseded it. Keep diagnostics correctness: the *latest* edit always runs.
- [ ] **Step 4: Run, expect PASS.** Build server.
- [ ] **Step 5: Commit** — `git add lsp/lib/server.ml lsp/test/test_incremental.ml && git commit -m "feat(lsp): debounce did_change AST analyse (coalesce keystroke bursts)"`

---

## Increment F: JSON-RPC integration tests

The entire `server.ml`/`main.ml` transport layer is untested (unit tests call `Analysis`/`Query` directly). Spawn the real binary, speak LSP over stdio, assert protocol responses — the one layer unit tests can't reach.

**Files:** Create `lsp/test/test_jsonrpc.ml`; Modify `lsp/test/dune`.

- [ ] **Step 1: Failing test** — start `_build/.../lsp/bin/main.exe`, send `initialize` + `initialized` + `textDocument/didOpen` + `textDocument/hover`, parse the framed responses, assert the hover result contains a type. Use a small Content-Length framing helper over a `Unix.open_process_full` pipe. Diagnostics arrive as a `textDocument/publishDiagnostics` notification on didOpen — assert it carries the expected error for a type-mismatch buffer.
- [ ] **Step 2: Run, expect FAIL** (binary path or handler).
- [ ] **Step 3: Implement** the framing client + the test. Add stanza to `lsp/test/dune`:

```lisp
(test
 (name test_jsonrpc)
 (modules test_jsonrpc)
 (libraries unix yojson alcotest)
 (deps %{exe:../bin/main.exe}))
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git add lsp/test/test_jsonrpc.ml lsp/test/dune && git commit -m "test(lsp): JSON-RPC integration tests over stdio (initialize/didOpen/hover/diagnostics)"`

---

## Increment H: Specs + docs

- [ ] Update `specs/features/lsp-server.md` "Remaining (Phase 5)" → mark the incremental engine, didChangeWatchedFiles done; note per-def AST firewall deferred (Increment G).
- [ ] Update `specs/progress.md` Current State (test count) and feature list (incremental typecheck env).
- [ ] Move the Phase 5 item to Done in `specs/todos.md`.
- [ ] Commit — `git add specs/features/lsp-server.md specs/progress.md specs/todos.md && git commit -m "docs(lsp): record Phase 5 incremental engine shipped"`

---

## Increment G (DEFERRED): per-def in-file typecheck firewall

A genuine AST-level `sig_hash`/`impl_hash` cache for the *user file's own* defs (skip re-checking a function whose desugared body+sig is unchanged across edits, sig-gated downstream invalidation via `Scc`). Deferred because: (1) requires canonical serialization of the full surface `decl`/`expr`/`pattern` algebra (none exists — `Serialize` is TIR-only), a large high-risk surface; (2) the dominant cost (stdlib+deps prefix) is already removed by Increments A–B, leaving only the user file (typically tens of defs) per edit. Revisit if profiling shows large single-file edits are the new bottleneck. Seed: extend `March_cas.Serialize` with `write_ast_decl`, hash per `DFn`, key a `(impl_hash -> typed maps)` cache, invalidate dependents whose `sig_hash` changed using `Scc.compute_sccs` over an AST-level dep graph.

---

## Overall Testing Strategy

- **Regression gate (critical):** after Increments A and B, the full existing 159-test LSP suite must stay green — it pins hover/def/completion/diagnostics semantics that the layered checker must reproduce exactly. Run `dune build --root . @lsp/runtest` after every increment; judge by exit code (`echo $?`), not tail output (rule failures hide above a green alcotest summary).
- **Unit (alcotest), transport-free:** cache memoization (physical equality), env isolation (independent `type_map`), incremental-vs-whole-module diagnostic equivalence.
- **Integration (Increment F):** spawn the binary, real JSON-RPC over stdio.
- **Anti-tautology rule:** every test asserts a specific expected value; no `check bool ... true true`.

## Self-Review

- **Spec coverage:** incremental engine → Increments 0/A/B; CAS-discipline reuse → content keys in A/B; `run_tir_pass` → C (source-hash memo, with rationale for not using `compile_scc`); `didChangeWatchedFiles` → D; debounce → E; JSON-RPC integration tests → F; workspace symbols/cross-file refs → already shipped (5.1–5.3); per-def firewall → G deferred with rationale.
- **Placeholder scan:** the two spots requiring a pre-build check are flagged inline (the `module_` record field names; the linol watched-files method name) — these are verifications against existing source, not TODOs.
- **Type consistency:** `Typecheck_cache.base_env : unit -> Tc.env`, `derive : Tc.env -> Tc.env`, `deps_env : Tc.env -> deps:decl list -> Tc.env`, `clear_deps : unit -> unit`; `Tc.check_module_with_env_full : env -> module_ -> Err.ctx * type_map * env`. Mutable-field reset list (`errors`/`type_map`/`pending_constraints`/`import_tracker`) matches `typecheck.ml:359-391`.
