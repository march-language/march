# LSP Context-Aware Completion — Implementation Plan (Phase 4)

> REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Replace the flat "dump every keyword/var/type" completion with context-aware results — starting with dot-completion of a receiver's members.

**Background (verified):** `completions_at` (`lsp/lib/analysis.ml`) ignored the cursor and returned keywords + all in-scope vars + types + ctors + interfaces + sigils. `Tc.ty` carries `TRecord of (string*ty) list`, so a record receiver's fields are directly available from the inferred type (`type_at`/`ty_at`). Error-resilient analysis (Phase 1) means that when the in-progress buffer (`r.`) doesn't parse, the last-good maps still carry `r`'s type, so dot-completion works mid-edit.

## Task 1: Dot-completion for record fields  — DONE in this branch

- `ty_at : t -> line:int -> character:int -> Tc.ty option` (raw type; `type_at` now pp-wraps it).
- `dot_completions`: scan left of the cursor; if the form is `receiver.<prefix>` with a single-identifier receiver whose `ty_at` is `TRecord flds`, return one `Field` completion per field (with its type as detail); otherwise `None`.
- `completions_at` uses the cursor: dot-context → member list; else the existing general list.
- [x] Test: completing in `r.x` (r : `{x:Int,y:Int}`) offers exactly `[x; y]`; a non-dot position still returns the general list.

## Follow-ups (not in this task)
- Named record types (`TCon(name,_)` where `name` is a user record) — needs a `record_fields` map built from `DType TDRecord`.
- Module-qualified completion (`List.` → that module's members).
- Scope-precise locals first, with `sortText` ranking (reuse Phase 3 `collect_scoped` scope-at-position).
- Chained receivers (`a.b.`), method/interface members.
- Thread the trigger char from the server `~ctx` (currently dot-context is detected from source text, which is more robust than the trigger anyway).
