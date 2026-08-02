# `forge search --callers`: reverse-reference search

Date: 2026-08-01
Status: approved

## Problem

`forge search` (`lib/search/search.ml`, `forge/lib/cmd_search.ml`) already indexes March
declarations (name, module, kind, signature, doc, file, line) via a real typecheck pass
(`Search.typecheck_decls` → `TC.check_module`), and supports name search, type-signature
search, and doc-keyword search. It has no notion of *references*: there is no way to ask
"what calls `Foo.bar`?" or "what uses this constructor/type?" without falling back to grep,
which produces false positives whenever a name is reused across modules and misses
qualified-vs-bare-name variance.

This matters most for ownership/RC-style audits (e.g. auditing every call site of a runtime
closure-drop function across the compiler) and for general "is this still used anywhere"
questions before deleting a declaration.

## Scope (v1)

- **Precision**: exact, resolution-based — not a textual/name-heuristic scan. A reference is
  only recorded when it resolves to a specific declaration, using the same resolution logic
  (`lookup_ctor`, current-module preference, etc.) the typechecker already applies. This
  means reverse-reference search inherits the existing ambiguous-ctor disambiguation
  behavior for free, rather than reimplementing it.
- **Reference kinds tracked**: function/value calls (`EVar` in call position), constructor
  uses (`ECon`), and type-annotation references. Not just calls — matches the ownership-audit
  use case, where a wildcard-decl walk or a type reference matters as much as a call.
- **Index integration**: extends the existing `Search.index` / `.march/search-index.json`
  cache, built in the same typecheck pass that already produces `type_map`. One cache, one
  `--rebuild` flag, one `forge search` command.
- **Traversal depth**: direct references only. No `--depth N` / transitive closure in v1 —
  that can be layered on top later by repeatedly querying direct callers, or added as a
  follow-up once direct lookup is proven useful.
- **Corpus**: same as today's `forge search` — stdlib + project dependencies resolved via
  `Project.load()` and `dep_source_dirs`. No new directory-walking logic.

## Non-goals (v1)

- Transitive/"reachability" queries (`--depth N`).
- Indexing references inside non-March artifacts (TIR dumps, snapshot goldens).
- A standalone command separate from `forge search`.

## Design

### Typecheck: emit resolved references

`Search.typecheck_decls` currently calls `TC.check_module` and keeps only the returned
`type_map : (Ast.span, TC.ty) Hashtbl.t`. `TC.check_module` will additionally return (or
accept an output accumulator for) a list of resolved references:

```ocaml
type ref_record = {
  callee   : string;  (* qualified name of the referenced declaration *)
  caller   : string;  (* qualified name of the enclosing declaration *)
  ref_kind : [ `Call | `Ctor | `TypeRef ];
  file     : string;
  line     : int;
}
```

These are populated at the same resolution points that already exist in
`lib/typecheck/typecheck.ml`:

- The `EVar` call-position handler near `record_use` (`typecheck.ml:4698`), which already
  resolves a bare/qualified name against `env` — extended to also emit a `ref_record` when
  resolution succeeds.
- The `ECon` constructor resolution paths (`lookup_ctor`, `lookup_ctor_same_module`,
  `lookup_ctor_in_type`, `lookup_ctor_in_type_unique` — `typecheck.ml:912-1004`), which
  already implement the current-module-preference logic from the ambiguous-ctor fix; each
  successful resolution emits a `ref_record` with `ref_kind = `Ctor`.
- Type-annotation resolution (wherever `Ast.TyCon` names are resolved against the type
  environment) emits `ref_record` with `ref_kind = `TypeRef`.

No new AST walk is introduced — this piggybacks on resolution work the typechecker already
performs, so it stays consistent with what actually compiles (unlike a separate best-effort
resolver that could drift from real semantics).

The "enclosing declaration" (`caller`) is tracked via a small stack/current-decl reference
threaded through `check_module`'s existing per-declaration dispatch — pushed on entering a
top-level `fn`/`impl` method body, popped on exit.

### Search index

`Search.index` gains a references table:

```ocaml
type index = {
  entries      : entry list;
  references   : (string, (string * string * int * string) list) Hashtbl.t;
    (* callee qualified name -> [(caller qualified name, file, line, kind); ...] *)
  version      : int;
  generated_at : string;
}
```

Built in `Search.build_index`/`build_stdlib_index`/`build_index_from_dirs` alongside
`entries`, from the `ref_record list` now returned by `typecheck_decls`. Serialized in the
same JSON cache (`index_to_json`/`index_from_json`), bumping `version` since existing cache
files won't have a `references` field (missing field → empty table on load, triggering a
rebuild path consistent with how `--rebuild` already works).

### Query layer

`Search.search_combined` gains an optional `?callers:string` parameter. When present:

1. Resolve the given name to a qualified declaration name using the same lookup the
   existing name-search path uses (so `--callers bar` and `--callers Foo.bar` both work when
   unambiguous, matching existing UX for `--type`/name queries).
2. Look up `references` for that qualified name; return the `(caller, file, line, kind)`
   list as the result set.

### CLI

`forge/lib/cmd_search.ml`: new `--callers NAME` flag, parsed and threaded through exactly
like `--type`/`--doc` today. Reuses `load_or_build_index`, `--rebuild`, `--json`, `--plain`,
`--limit`. Output formatting (`format_results_plain`/`format_results_colored`) gets a
reference-result variant (`caller — file:line (kind)`).

### Error handling

An unresolvable or unreferenced name is not an error — same "no results" UX as today's name
search when nothing matches. This is consistent with the existing command's behavior and
avoids introducing a new error path.

## Testing

Extend `test/test_search.ml`:

- One fixture per reference kind (call, constructor use, type reference) — assert the
  expected `(caller, file, line, kind)` entries appear for a known callee.
- A regression test pinning ambiguous-ctor resolution for references: two modules
  defining the same bare constructor name, verify `--callers` on the current-module ctor
  only returns references that actually resolve to it (not the other module's ctor) —
  directly guards against the class of bug recorded in
  `project_ambiguous_ctor_current_module.md`.
- A "no references" case for a declaration that exists but is never called/used, confirming
  it returns an empty result rather than an error.
- A cache round-trip test: build index with references, serialize to JSON, reload, confirm
  `references` survives `index_to_json`/`index_from_json`.

## Follow-ups (explicitly out of scope here)

- `--depth N` transitive closure.
- Extending resolution to interface-impl references (a type implementing an interface,
  independent of any explicit call), which the RC-audit use case may eventually want but
  wasn't part of this design's approved scope.
