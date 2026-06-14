# LSP Sound Symbol Identity — Implementation Plan (Phase 3)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]` checkboxes.

**Goal:** Make go-to-definition, find-references, and rename resolve to the *binding a name actually refers to*, not "every identifier with that text" — fixing the shadowing unsoundness where rename can silently corrupt code.

**Architecture:** Add a scope-aware resolution pass over the desugared AST in `analysis.ml`. Local bindings (let in a block, fn/lambda params, match-arm binders) get a unique `symbol_id` and resolve through a lexical scope stack; top-level/stdlib names keep name-based resolution (they are effectively globally unique by qualified name). Route `definition_at`/`references_at`/`rename_at` through the scoped resolver first, falling back to the existing name maps. Add `prepareRename` validation.

**Tech Stack:** OCaml, the existing `Analysis` module, `alcotest`.

---

## Background (verified against current code)

`collect_decl`/`collect_expr`/`collect_pat_defs` (`lsp/lib/analysis.ml:284-479`) walk the AST and populate:
- `def_map : (string, span) Hashtbl` — binding name → span, `Hashtbl.replace` (last writer wins).
- `use_map : (span, string) Hashtbl` — use-site span → name.
- `refs_map : (string, span list)` — inverted index name → all use spans (built later).

The walk threads **no scope**. So `definition_at`/`references_at`/`rename_at` (which key on the name string) cannot distinguish two different bindings that share a name. Binding forms in the AST:
- `Ast.ELet (bind, _)` — **no body field**; the binding is visible to *subsequent* exprs in the enclosing `Ast.EBlock (exprs, _)`.
- `Ast.ELetFn (name, params, _, body, _)` and `Ast.ELam (params, body, _)` — params scoped to `body`.
- `Ast.EMatch (subj, branches, _)` — each `branch.branch_pat` binds for that branch's guard + body.
- `fn` clause params (`DFn`/`DImpl`) scoped to the clause body.
- `Ast.PatVar`/`Ast.PatAs` introduce binders inside patterns.

Top-level defs (`DFn`, `DType` variants/fields, `DActor`, interface methods, …) and stdlib decls populate `def_map` by (optionally module-qualified) name; that resolution is fine and stays.

---

## Design

A new scoped pass produces, for **local** binders only:

```
type symbol_id = int
sym_defs   : (symbol_id, span) Hashtbl      (* binder occurrence -> its span *)
sym_uses   : (span, symbol_id) Hashtbl      (* use-site span -> resolved binder *)
sym_id_uses: (symbol_id, span list) Hashtbl (* binder -> all its use spans *)
sym_name   : (symbol_id, string) Hashtbl    (* binder -> name (for rename validation) *)
```

The walk threads a `scope = (string * symbol_id) list list` (a stack of frames; innermost frame first). Resolution of a use name = first match scanning frames inner→outer. Unresolved uses are *not* locals (top-level/stdlib) and are left to the existing name maps.

Scope rules:
- Entering a fn clause / lambda / let-fn: push a frame with the params' binders, walk the body, pop.
- `EBlock`: fold the exprs left→right carrying a *growing* current frame; an `ELet` adds its pattern's binders to that frame so later siblings see them.
- `EMatch` branch: push a frame with the pattern binders for guard+body, pop.
- A binder occurrence allocates a fresh `symbol_id` (global counter), records `sym_defs`/`sym_name`, and binds `name -> id` in the current frame (shadowing any outer binding of the same name within this frame's view).
- A use (`EVar`; pattern `PatCon` constructors are uses too but resolve as ctors, not locals) records `sym_uses[span] = id` and appends to `sym_id_uses[id]` **iff** the name resolves to a local binder.

Resolution routing:
- `definition_at`: if the cursor's use span is in `sym_uses` → `sym_defs[id]`. Else if the cursor is *on* a local binder span → that binder. Else existing `def_map` lookup.
- `references_at` / `rename_at`: if the cursor resolves to a local `symbol_id` (via a use span or a binder span) → return exactly `sym_defs[id] :: sym_id_uses[id]`. Else fall back to the existing name-based path (top-level/stdlib).
- `prepare_rename_at`: return the identifier range if the cursor is on a local binder/use OR a user-file top-level def the file owns; return `None` (reject) on stdlib symbols, keywords, literals.

This is **additive**: the existing maps and their behavior for non-shadowed and top-level names are unchanged; we only override when a local binder is involved, which is exactly the broken case.

---

## File Structure

- Modify: `lsp/lib/analysis.ml` — add the four `sym_*` tables to `type t`; add `collect_scoped` (the scoped walk); populate in `analyse`; add `local_symbol_at`, and reroute `definition_at`/`references_at`/`rename_at`; add `prepare_rename_at`.
- Modify: `lsp/lib/server.ml` — set `renameProvider` with `prepareProvider = true`; handle `textDocument/prepareRename`.
- Modify: `lsp/test/test_lsp.ml` — shadowing/scoping tests.

---

## Task 1: Scoped resolver core (no routing yet)

**Files:** Modify `lsp/lib/analysis.ml`; Test `lsp/test/test_lsp.ml`.

- [ ] **Step 1: Failing test** — the scoped resolver distinguishes shadowed locals. Add to `test_lsp.ml`:

```ocaml
let test_scoped_shadow_distinct () =
  (* Two distinct 'x' bindings; the inner use must resolve to the inner binder. *)
  let src =
    "mod M do\n\
    \  fn f() : Int do\n\
    \    let x = 1\n\
    \    let g = fn () -> (let x = 2\n\
    \                      x)\n\
    \    x\n\
    \  end\n\
    end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  (* The outer 'x' use on the 'x' line (line 5, col 4) and the inner 'x' use
     (line 4) must resolve to DIFFERENT binder spans. *)
  let outer = An.local_symbol_at a ~line:5 ~character:4 in
  let inner = An.local_symbol_at a ~line:4 ~character:22 in
  Alcotest.(check bool) "outer x resolves to a local" true (outer <> None);
  Alcotest.(check bool) "inner x resolves to a local" true (inner <> None);
  Alcotest.(check bool) "inner and outer x are different binders"
    true (outer <> inner)
```

(Adjust the line/col to the actual identifier positions after writing the source; verify with a throwaway probe that the two `x` uses sit where the test claims. The assertion that matters is `outer <> inner`.)

- [ ] **Step 2: Run, expect FAIL** (`local_symbol_at` unbound).
  Run: `dune exec lsp/test/test_lsp.exe -- test 'scoped'`

- [ ] **Step 3: Implement.** Add to `type t` (after `refs_map`):

```ocaml
  sym_defs    : (int, Ast.span) Hashtbl.t;
  sym_uses    : (Ast.span, int) Hashtbl.t;
  sym_id_uses : (int, Ast.span list) Hashtbl.t;
  sym_name    : (int, string) Hashtbl.t;
```

Initialize them (empty) in `make_empty_with` and the success record. Implement `collect_scoped` as a recursive walk mirroring `collect_expr` but threading `scope`, plus a global `int ref` counter. Provide:

```ocaml
(* Smallest binder/use span containing the cursor -> its symbol_id. *)
let local_symbol_at (a : t) ~line ~character : int option = ...
```

`local_symbol_at` scans `sym_uses` (use spans) and `sym_defs` (binder spans) for the smallest span containing `(line, character)` and returns its id.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(lsp): scope-aware local symbol resolver`.

## Task 2: Route definition/references/rename through symbol identity

- [ ] **Step 1: Failing test** — rename of a shadowed local touches only its own occurrences:

```ocaml
let test_rename_respects_shadowing () =
  let src =
    "mod M do\n\
    \  fn f() : Int do\n\
    \    let x = 1\n\
    \    let y = (let x = 2\n\
    \             x + x)\n\
    \    x\n\
    \  end\n\
    end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  (* Rename the INNER x (its use at line 4) -> edits must cover only the inner
     binder + its two uses (3 edits), NOT the outer x. *)
  let edits = An.rename_at a ~line:4 ~character:13 ~new_name:"z" in
  Alcotest.(check int) "inner rename touches exactly 3 spots" 3 (List.length edits)
```

(Probe the exact positions; the invariant is "inner rename count < total x occurrences".)

- [ ] **Step 2: Run, expect FAIL** (current name-based rename returns all `x`).
- [ ] **Step 3: Implement** the routing in `definition_at`, `references_at`, `rename_at`: when `local_symbol_at` returns `Some id`, use `sym_defs[id] :: sym_id_uses[id]`; else current behavior.
- [ ] **Step 4: Run, expect PASS** + full suite green (no regression in existing rename/refs tests).
- [ ] **Step 5: Commit** `fix(lsp): scope-correct definition/references/rename (no more shadow corruption)`.

## Task 3: prepareRename

- [ ] **Step 1: Failing test** — `prepare_rename_at` returns a range on a local, `None` on a stdlib symbol/keyword.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `prepare_rename_at` + wire `renameProvider` with `prepareProvider=true` and a `textDocument/prepareRename` handler in `server.ml`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(lsp): prepareRename validation (reject stdlib/keyword rename)`.

---

## Testing Strategy
- Unit tests at the `Analysis` level (UTF-16-free byte columns are fine here since these tests use ASCII identifiers; positions are byte=utf16).
- Each test asserts a *specific* invariant (binder distinctness, exact edit count), never `true true`.
- Full suite green after each task; the existing rename/references tests must continue to pass (they use non-shadowed names → fall through to the name-based path unchanged).

## Self-Review checklist
- [ ] Shadowed local rename touches only its binding (Task 2 test).
- [ ] Non-shadowed and top-level rename/refs unchanged (existing tests green).
- [ ] prepareRename rejects stdlib symbols (Task 3 test).
- [ ] `EBlock` let-threading verified (Task 1 source exercises let-in-block).
