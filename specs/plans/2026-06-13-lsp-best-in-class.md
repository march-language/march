# Best-in-Class March LSP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `march-lsp` from a per-file, encoding-incorrect, full-recompile-per-keystroke analyzer into a correct, fast, IDE-grade language server that is *also* runnable standalone (stateless CLI query mode) so any editor — or an LLM/CI script — can drive it.

**Architecture:** Keep the existing compiler-pipeline-backed analysis (it produces *real* types, not heuristics), but (1) fix the position-encoding and error-recovery foundations every feature stands on, (2) kill the per-keystroke stdlib reparse with a content-hashed memo (the March CAS pattern, lifted upstream of typecheck), (3) make analysis versioned/debounced/cancellable, (4) extract a transport-agnostic `Query` core so the same logic backs both the linol JSON-RPC server *and* a new stateless `march-lsp query` CLI, and (5) stage the deeper architectural reworks — sound symbol identity, context-aware completion, and a CAS-primitive-based incremental engine — as focused sub-plans built on the now-correct foundation.

**Tech Stack:** OCaml, `linol`/`linol-lwt` (LSP transport), `dune`, `alcotest` (tests), the March compiler libs (`march_parser`, `march_desugar`, `march_typecheck`, `march_tir`), and the existing CAS subsystem (`lib/cas/`: `Blake3`, `Serialize`, `Hash`, `Scc`, `Pipeline`).

---

## Rewritten Priority List

The review surfaced a stack of issues; this is the order to fix them, with the *reason* each comes when it does. Phases 0–2 are fully specified as TDD tasks below. Phases 3–5 are the deep architectural reworks — each is specified here as objective + design + interfaces + test-plan checklist, and each ends with an explicit trigger to spawn its own focused implementation plan (writing line-exact OCaml against the typechecker/TIR internals requires reading those modules first; this plan does not fabricate it).

| # | Phase | Why here | Status in this doc |
|---|-------|----------|--------------------|
| **0** | Hygiene + **position/UTF-16 foundation** | Every position-sensitive feature (hover, def, rename, semantic tokens, diagnostics) is silently wrong on any non-ASCII line. Nothing else is trustworthy until this is fixed. Cheap. | **Full TDD tasks** |
| **1** | **Latency & correctness** — stdlib memo, error-resilient analysis, versioned/debounced/cancellable analysis | These three give the "IDE feel": instant response, features that survive a half-typed buffer, no stale-diagnostic flicker, no server crash from a background fiber. Highest effort-to-payoff. | **Full TDD tasks** |
| **2** | **Query-core extraction + standalone CLI + editor conformance/docs** | Satisfies the "runnable standalone so an LLM can use it" and "portable to any editor" requirements. The extraction also yields a transport-free test harness for everything above. | **Full TDD tasks** |
| **3** | **Sound symbol identity** (fixes def/refs/rename shadowing) | The name-keyed `def_map`/`use_map`/`refs_map` make rename actively corrupt code. Must precede completion and the incremental engine, both of which want real symbols. | **Design + checklist + sub-plan trigger** |
| **4** | **Context-aware completion** | The headline UX gap (flat dump, position ignored). Depends on symbol identity (scope-precise locals) and the line index (Phase 0). | **Design + checklist + sub-plan trigger** |
| **5** | **Incremental typecheck engine** (CAS primitives) + workspace model | The real scalability fix and the foundation for cross-file/workspace intelligence (workspace symbols, cross-file refs). Largest; depends on symbol identity. | **Design + checklist + sub-plan trigger** |

**On the CAS:** the existing CAS caches *backend codegen* keyed by a *TIR* hash — downstream of the typecheck that dominates LSP latency, so wiring it in as-is helps only the perf-insights `run_tir_pass` path (Phase 5, Task 5.5). Its *value to the LSP is its primitives*: `Blake3` + canonical `Serialize` for content hashing, the `sig_hash`/`impl_hash` invalidation firewall (`lib/cas/hash.ml`), and `Scc` for the dependency graph. Phases 1 and 5 reuse the *pattern and primitives*, lifted one phase upstream (AST→typecheck instead of TIR→codegen).

---

## File Structure

**Created:**
- `lsp/lib/utf16.ml` — pure UTF-8 ↔ UTF-16 column conversion + per-document line index. One responsibility: byte-column ↔ LSP-character mapping. (~120 lines)
- `lsp/lib/stdlib_cache.ml` — content+compiler-identity-keyed memo of parsed/desugared stdlib decls. (~80 lines)
- `lsp/lib/query.ml` — transport-agnostic query facade: takes a URI/src + position, returns plain OCaml result records. Wraps `Analysis` so both `Server` and the CLI share one code path. (~200 lines)
- `lsp/bin/query_cli.ml` — the `march-lsp query <feature> <file> --line N --col M` stateless CLI, emits JSON to stdout. (~180 lines)
- `lsp/test/test_utf16.ml`, `lsp/test/test_query_cli.ml` — new test executables.
- `lsp/docs/editors.md` — copy-paste setup for Neovim, Helix, Zed, Emacs (eglot), VS Code (generic LSP), plus the `march-lsp query` reference.
- `specs/plans/2026-06-13-lsp-symbol-identity.md`, `…-completion.md`, `…-incremental-engine.md` — the three sub-plans (created when their phase starts; Phases 3–5 below are their seeds).

**Modified:**
- `lsp/lib/position.ml` — re-expressed in terms of `Utf16` (inbound LSP→byte-col, outbound span→UTF-16). Internal `Analysis` logic stays in byte-columns (which is what March spans already are) so the change is localized to the two boundaries.
- `lsp/lib/analysis.ml` — add a `line_index`/`doc` to `t`; make `analyse` error-resilient (populate maps from a partial parse); route stdlib loading through `Stdlib_cache`.
- `lsp/lib/server.ml` — convert positions via `Utf16` at the boundary; add document versions, debounce, stale-result rejection, and crash isolation for the TIR fiber; negotiate `positionEncoding`.
- `lsp/bin/main.ml` — `Printexc.record_backtrace true`; dispatch to `query_cli` when invoked as `march-lsp query …`.
- `lsp/bin/dune`, `lsp/test/dune` — wire new modules/tests.
- `specs/features/lsp-server.md` — rewrite (currently stale: wrong branch, wrong file layout, wrong build commands, undercounted features).
- **Delete:** `bin/march_lsp.ml` (890-line orphan; not in any dune target).

---

## Phase 0: Hygiene + Position/UTF-16 Foundation

### Task 0.1: Remove dead code and fix the stale spec

**Files:**
- Delete: `bin/march_lsp.ml`
- Modify: `specs/features/lsp-server.md`

- [ ] **Step 1: Confirm the orphan is unreferenced**

Run: `grep -rn "march_lsp" /Users/80197052/code/march/bin/dune /Users/80197052/code/march/dune-project`
Expected: no output (the file is in no build target).

- [ ] **Step 2: Delete it**

```bash
git rm bin/march_lsp.ml
```

- [ ] **Step 3: Rewrite the stale spec header**

In `specs/features/lsp-server.md`, replace the "Implementation Status" and "Key Files" sections with the truth:

```markdown
## Implementation Status

Live and installed as `march-lsp` (built from `lsp/`). Transport: `linol`/`linol-lwt`.

### Key Files
```
lsp/
├── bin/main.ml          # entry point (stdio LSP; `query` CLI subcommand)
├── bin/query_cli.ml     # stateless CLI query mode
├── lib/server.ml        # linol Server subclass: handlers + capabilities
├── lib/analysis.ml      # compiler-pipeline-backed analysis engine
├── lib/query.ml         # transport-agnostic query facade
├── lib/position.ml      # span ↔ LSP range (via Utf16)
├── lib/utf16.ml         # UTF-8 ↔ UTF-16 column mapping + line index
├── lib/stdlib_cache.ml  # content-hashed stdlib memo
├── lib/forge_config.ml  # project root + import path discovery
└── test/                # alcotest suites
```

Build: `dune build lsp/bin/main.exe`. Install: `dune install march-lsp`.
```

- [ ] **Step 4: Build to confirm nothing depended on the deleted file**

Run: `cd /Users/80197052/code/march && dune build lsp/bin/main.exe 2>&1 | tail -5`
Expected: builds clean.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore(lsp): delete orphaned bin/march_lsp.ml, fix stale spec"
```

---

### Task 0.2: UTF-16 column conversion + line index

The core fix. March spans use **byte columns** (`pos_cnum - pos_bol`). LSP `character` is **UTF-16 code units**. We add a `Utf16` module that converts between them against the document text, and a line index for O(1) line lookup. Strategy: convert **inbound** LSP positions to byte-columns at the boundary (so `Analysis`'s existing byte-column logic becomes *correct* unchanged), and convert **outbound** spans from byte-columns to UTF-16.

**Files:**
- Create: `lsp/lib/utf16.ml`
- Create: `lsp/test/test_utf16.ml`
- Modify: `lsp/test/dune`

- [ ] **Step 1: Write the failing test**

`lsp/test/test_utf16.ml`:

```ocaml
module U = March_lsp_lib.Utf16

(* "let x = 1\nlet é = 2\n😀 after" — é is 2 UTF-8 bytes / 1 UTF-16 unit;
   😀 is 4 UTF-8 bytes / 2 UTF-16 units. *)
let src = "let x = 1\nlet \xc3\xa9 = 2\n\xf0\x9f\x98\x80 after"

let test_line_index () =
  let d = U.build src in
  (* line 0 starts at byte 0; line 1 after first '\n' (byte 10);
     line 2 after second '\n'. *)
  Alcotest.(check int) "line0 start" 0 (U.line_start d 0);
  Alcotest.(check int) "line1 start" 10 (U.line_start d 1)

let test_utf16_after_2byte_char () =
  let d = U.build src in
  (* On line 1, "let é = 2": the '=' is at UTF-16 column 6 (l,e,t,space,é,space)
     but byte column 7 (é occupies 2 bytes). Conversion must reconcile them. *)
  let byte_col = U.lsp_char_to_byte_col d ~line:1 ~utf16_char:6 in
  Alcotest.(check int) "utf16 6 -> byte 7" 7 byte_col;
  let utf16 = U.byte_col_to_lsp_char d ~line:1 ~byte_col:7 in
  Alcotest.(check int) "byte 7 -> utf16 6" 6 utf16

let test_astral_char_two_units () =
  let d = U.build src in
  (* On line 2, "😀 after": the space after 😀 is UTF-16 column 2 (surrogate
     pair = 2 units) but byte column 4. *)
  let byte_col = U.lsp_char_to_byte_col d ~line:2 ~utf16_char:2 in
  Alcotest.(check int) "astral utf16 2 -> byte 4" 4 byte_col

let test_ascii_identity () =
  let d = U.build src in
  Alcotest.(check int) "ascii utf16==byte" 4
    (U.lsp_char_to_byte_col d ~line:0 ~utf16_char:4)

let () =
  Alcotest.run "utf16"
    [ "conv",
      [ Alcotest.test_case "line index" `Quick test_line_index;
        Alcotest.test_case "2-byte char" `Quick test_utf16_after_2byte_char;
        Alcotest.test_case "astral char" `Quick test_astral_char_two_units;
        Alcotest.test_case "ascii identity" `Quick test_ascii_identity ] ]
```

Add to `lsp/test/dune` a second test stanza:

```lisp
(test
 (name test_utf16)
 (libraries march_lsp_lib alcotest))
```

(The existing `(test (name test_lsp) ...)` stanza stays; dune allows multiple test names via separate stanzas — if the existing form uses `(names ...)`, add `test_utf16` there instead.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_utf16.exe 2>&1 | tail -20`
Expected: FAIL — `Unbound module March_lsp_lib.Utf16`.

- [ ] **Step 3: Implement `Utf16`**

`lsp/lib/utf16.ml`:

```ocaml
(** UTF-8 (March byte columns) ↔ UTF-16 (LSP character) conversion,
    plus a per-document line-start index.

    March spans use byte columns (pos_cnum - pos_bol).
    LSP Position.character counts UTF-16 code units.
    These differ on any line containing a non-ASCII character. *)

type doc = {
  src : string;
  line_starts : int array;  (** byte offset of the start of each 0-indexed line *)
}

let build (src : string) : doc =
  let starts = ref [0] in
  String.iteri (fun i c -> if c = '\n' then starts := (i + 1) :: !starts) src;
  { src; line_starts = Array.of_list (List.rev !starts) }

let line_count (d : doc) = Array.length d.line_starts

let line_start (d : doc) (line : int) : int =
  if line < 0 then 0
  else if line >= Array.length d.line_starts then String.length d.src
  else d.line_starts.(line)

let line_end (d : doc) (line : int) : int =
  if line + 1 < Array.length d.line_starts then d.line_starts.(line + 1) - 1
  else String.length d.src

(* Decode the UTF-8 codepoint starting at byte [i]; return (codepoint_byte_len).
   Treats malformed bytes as length 1 so we never loop forever. *)
let utf8_len (src : string) (i : int) : int =
  let c = Char.code src.[i] in
  if c < 0x80 then 1
  else if c < 0xE0 then 2
  else if c < 0xF0 then 3
  else 4

(* UTF-16 units a codepoint of byte-length [len] contributes: astral (4-byte
   UTF-8, i.e. > U+FFFF) needs a surrogate pair = 2 units; else 1. *)
let utf16_units_of_len = function 4 -> 2 | _ -> 1

(** Byte column within [line] for a given UTF-16 [character] column. *)
let lsp_char_to_byte_col (d : doc) ~line ~utf16_char : int =
  let ls = line_start d line and le = line_end d line in
  let rec loop byte_i units =
    if units >= utf16_char || byte_i >= le then byte_i - ls
    else
      let len = utf8_len d.src byte_i in
      loop (byte_i + len) (units + utf16_units_of_len len)
  in
  if utf16_char <= 0 then 0 else loop ls 0

(** UTF-16 character column for a given byte column within [line]. *)
let byte_col_to_lsp_char (d : doc) ~line ~byte_col : int =
  let ls = line_start d line and le = line_end d line in
  let target = min (ls + byte_col) le in
  let rec loop byte_i units =
    if byte_i >= target then units
    else
      let len = utf8_len d.src byte_i in
      loop (byte_i + len) (units + utf16_units_of_len len)
  in
  loop ls 0
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_utf16.exe 2>&1 | tail -20`
Expected: PASS — 4 cases green.

- [ ] **Step 5: Commit**

```bash
git add lsp/lib/utf16.ml lsp/test/test_utf16.ml lsp/test/dune
git commit -m "feat(lsp): UTF-8<->UTF-16 column conversion + line index"
```

---

### Task 0.3: Thread `Utf16` through `position.ml`, `analyse`, and the server boundary

Convert inbound LSP positions to byte-columns and outbound spans to UTF-16 ranges, and advertise `utf-8` as the preferred encoding (correctness is guaranteed regardless, since we convert against text).

**Files:**
- Modify: `lsp/lib/analysis.ml` (add `doc : Utf16.doc` to `t`; build it in `analyse`)
- Modify: `lsp/lib/position.ml`
- Modify: `lsp/lib/server.ml`
- Test: `lsp/test/test_lsp.ml` (add a non-ASCII hover test)

- [ ] **Step 1: Write the failing test** in `lsp/test/test_lsp.ml` (append to the hover section):

```ocaml
let test_hover_after_unicode () =
  (* 'name' is bound on a line that contains a 2-byte char before the cursor.
     With correct UTF-16 mapping, hovering the identifier returns its type;
     with the old byte-column bug the position lands one column off. *)
  let src = "fn f() -> Int do\n  let é_n = 41\n  é_n + 1\nend\n" in
  let a = An.analyse ~filename:"t.march" ~src in
  (* UTF-16 column of 'é_n' use on line 2 (0-indexed): leading 2 spaces, then é. *)
  let ty = An.query_type_at a ~line:2 ~utf16_char:2 in
  Alcotest.(check bool) "type found after unicode"
    true (ty <> None)
```

Note: this test calls a new `An.query_type_at ~line ~utf16_char` wrapper (added in Step 3) that does the UTF-16→byte conversion internally, so tests express positions the way an editor does.

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'hover' 2>&1 | tail -20`
Expected: FAIL — `query_type_at` unbound.

- [ ] **Step 3: Add `doc` to `Analysis.t` and a UTF-16-aware query wrapper.**

In `lsp/lib/analysis.ml`, add to the `type t` record:

```ocaml
  doc : Utf16.doc;
  (** Line index + source for UTF-16<->byte column conversion. *)
```

In `analyse`, build it once and include it in every constructed `t` (both `make_empty_with` and the success record):

```ocaml
  let doc = Utf16.build src in
```

(add `doc;` to the `make_empty_with` record and the main return record).

Add public wrappers near the existing `type_at`:

```ocaml
(* Convert an editor (UTF-16) position to the internal byte column, then query. *)
let query_type_at (a : t) ~line ~utf16_char =
  let character = Utf16.lsp_char_to_byte_col a.doc ~line ~utf16_char in
  type_at a ~line ~character

let query_definition_at (a : t) ~line ~utf16_char =
  let character = Utf16.lsp_char_to_byte_col a.doc ~line ~utf16_char in
  definition_at a ~line ~character
```

(Repeat the one-line wrapper for `doc_name_at`, `perf_insight_at`, `actor_info_at`, `completions_at`, `references_at`, `rename_at`, `signature_help_at`. Each is a two-line wrapper; write them all — do not leave any un-wrapped, or that feature keeps the byte-column bug.)

- [ ] **Step 4: Make `position.ml` convert spans to UTF-16 on output.**

`lsp/lib/position.ml` — change `span_to_lsp_range` to take the doc:

```ocaml
let span_to_lsp_range (d : Utf16.doc) (sp : span) : Lsp.Types.Range.t =
  let open Lsp.Types in
  let s_char = Utf16.byte_col_to_lsp_char d ~line:(sp.start_line - 1) ~byte_col:sp.start_col in
  let e_char = Utf16.byte_col_to_lsp_char d ~line:(sp.end_line - 1) ~byte_col:sp.end_col in
  Range.create
    ~start:(Position.create ~line:(sp.start_line - 1) ~character:s_char)
    ~end_:(Position.create ~line:(sp.end_line - 1) ~character:e_char)
```

Update every caller of `span_to_lsp_range` (grep them) to pass the doc: `Pos.span_to_lsp_range a.doc sp`. `span_contains`/`span_size` stay byte-column (they are only ever compared against byte-columns now).

- [ ] **Step 5: Convert positions at the server boundary + advertise encoding.**

In `lsp/lib/server.ml`, replace `Pos.lsp_pos_to_pair pos` usages with a UTF-16-aware conversion that uses the cached doc. Add a helper:

```ocaml
let pos_to_byte (a : Analysis.t) pos =
  let line = pos.Lsp.Types.Position.line in
  let utf16_char = pos.Lsp.Types.Position.character in
  (line, Utf16.lsp_char_to_byte_col a.Analysis.doc ~line ~utf16_char)
```

and use it inside each handler that has an analysis in hand (hover/definition/completion/etc.), e.g. in `on_req_hover`:

```ocaml
| Some a ->
  let (line, character) = pos_to_byte a pos in
  ...
```

In `config_modify_capabilities`, advertise UTF-8 support (clients that accept it skip the surrogate math; clients that don't still get correct results because we always convert against text):

```ocaml
ServerCapabilities.positionEncoding = Some Lsp.Types.PositionEncodingKind.UTF8;
```

(If the installed `lsp` package predates `positionEncoding`, omit this line — the text-based conversion is already correct for the default UTF-16 clients; leave a `(* TODO: advertise utf-8 once lsp pkg supports it *)` only if the field genuinely doesn't exist.)

- [ ] **Step 6: Run the test + full LSP suite**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe 2>&1 | tail -20`
Expected: PASS including `test_hover_after_unicode`; no regressions.

- [ ] **Step 7: Commit**

```bash
git add lsp/lib/analysis.ml lsp/lib/position.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "fix(lsp): correct UTF-16 position encoding end-to-end"
```

---

## Phase 1: Latency & Correctness

### Task 1.1: Stdlib memoization (CAS pattern, upstream of typecheck)

`analyse` calls `load_stdlib ()` which `Sys.readdir`s and re-parses + re-desugars **every** stdlib `.march` file from disk on **every keystroke**. The stdlib changes only when its files or the compiler change. Memoize the parsed/desugared decls, keyed by a content+compiler hash — the exact invalidation discipline the CAS already uses (`Cas.compiler_identity`).

**Files:**
- Create: `lsp/lib/stdlib_cache.ml`
- Modify: `lsp/lib/analysis.ml` (`load_stdlib` delegates to the cache)
- Test: `lsp/test/test_lsp.ml`

- [ ] **Step 1: Write the failing test** (append to `test_lsp.ml`):

```ocaml
let test_stdlib_cache_memoizes () =
  (* Two analyses in the same process must reuse the cached stdlib decls:
     the second call returns the physically same list value. *)
  let d1 = March_lsp_lib.Stdlib_cache.load () in
  let d2 = March_lsp_lib.Stdlib_cache.load () in
  Alcotest.(check bool) "same cached decls" true (d1 == d2)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'stdlib' 2>&1 | tail -20`
Expected: FAIL — `Stdlib_cache` unbound.

- [ ] **Step 3: Implement the cache.**

`lsp/lib/stdlib_cache.ml`:

```ocaml
(** Process-lifetime memo of parsed+desugared stdlib declarations.

    The stdlib is invariant across keystrokes; re-reading and re-parsing it
    per analyse (the previous behaviour) dominated LSP latency. We cache the
    decls in-process, keyed by a content hash of all stdlib *.march files plus
    the compiler identity (so a rebuilt compiler busts the cache) — the same
    invalidation discipline used by the CAS (March_cas.Cas.compiler_identity). *)

let cache : (string, March_ast.Ast.decl list) Hashtbl.t = Hashtbl.create 1

(* Hash of (sorted filename + content) over every stdlib .march file. *)
let content_key (dir : string) : string =
  let files =
    try
      Sys.readdir dir |> Array.to_list
      |> List.filter (fun f -> Filename.check_suffix f ".march")
      |> List.sort String.compare
    with Sys_error _ -> []
  in
  let buf = Buffer.create (1 lsl 16) in
  List.iter (fun f ->
    Buffer.add_string buf f; Buffer.add_char buf '\x00';
    (try
       let ic = open_in_bin (Filename.concat dir f) in
       Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
         let n = in_channel_length ic in
         let b = Bytes.create n in really_input ic b 0 n;
         Buffer.add_bytes buf b)
     with _ -> ());
    Buffer.add_char buf '\x00'
  ) files;
  March_cas.Blake3.hash_string (Buffer.contents buf)

(* [load_raw] is injected by Analysis (it owns the parse/desugar of one file)
   to avoid a dependency cycle; defaults to a no-op until set. *)
let loader : (unit -> March_ast.Ast.decl list) ref = ref (fun () -> [])
let set_loader f = loader := f
let stdlib_dir : (unit -> string option) ref = ref (fun () -> None)
let set_stdlib_dir f = stdlib_dir := f

let load () : March_ast.Ast.decl list =
  match (!stdlib_dir) () with
  | None -> []
  | Some dir ->
    let key = content_key dir ^ "\x00" ^ Lazy.force March_cas.Cas.compiler_identity in
    (match Hashtbl.find_opt cache key with
     | Some decls -> decls
     | None ->
       let decls = (!loader) () in
       Hashtbl.replace cache key decls;
       decls)
```

- [ ] **Step 4: Wire `Analysis` into it.** In `analysis.ml`, after the existing `load_stdlib` definition, register the loader and route through the cache. Replace the call site `let stdlib_decls = load_stdlib () in` (line ~1213) with `let stdlib_decls = Stdlib_cache.load () in`, and at module init:

```ocaml
let () =
  Stdlib_cache.set_stdlib_dir find_stdlib_dir;
  Stdlib_cache.set_loader load_stdlib
```

Add `march_cas` to `lsp/lib/dune`'s `(libraries ...)`.

- [ ] **Step 5: Run to verify it passes** (and add a timing sanity check)

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'stdlib' 2>&1 | tail -10`
Expected: PASS — `d1 == d2`.

- [ ] **Step 6: Commit**

```bash
git add lsp/lib/stdlib_cache.ml lsp/lib/analysis.ml lsp/lib/dune lsp/test/test_lsp.ml
git commit -m "perf(lsp): memoize stdlib parse/desugar (CAS-pattern content+compiler key)"
```

---

### Task 1.2: Error-resilient analysis

Today, on any lex/parse error, `analyse` returns `make_empty_with` — **empty** type/def/use maps — so hover/completion/def/symbols/semantic-tokens all go dark the instant the buffer doesn't parse (i.e. on most keystrokes mid-token). Best-in-class IDE feel requires serving stale-but-useful results from the last good parse, and ideally a recovering parse. Minimal-risk first step: **retain the last successful analysis per document** and fall back to it (with the *new* parse error surfaced as the only diagnostic) when the current text doesn't parse.

**Files:**
- Modify: `lsp/lib/analysis.ml` (add `analyse_resilient`)
- Modify: `lsp/lib/server.ml` (use it; keep a per-URI "last good" map)
- Test: `lsp/test/test_lsp.ml`

- [ ] **Step 1: Write the failing test:**

```ocaml
let test_resilient_keeps_last_good () =
  let good = "fn f() -> Int do\n  41\nend\n" in
  let a_good = An.analyse ~filename:"t.march" ~src:good in
  (* A broken edit (unterminated 'do'): parse fails. Resilient analysis must
     still answer hover for 'f' using the last good maps, and report the error. *)
  let broken = "fn f() -> Int do\n  41\nend\nfn g(" in
  let a = An.analyse_resilient ~prev:(Some a_good) ~filename:"t.march" ~src:broken in
  Alcotest.(check bool) "diagnostics present" true (a.An.diagnostics <> []);
  Alcotest.(check bool) "def map retained from last good"
    true (Hashtbl.mem a.An.def_map "f")
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'resilient' 2>&1 | tail -20`
Expected: FAIL — `analyse_resilient` unbound.

- [ ] **Step 3: Implement.** In `analysis.ml`:

```ocaml
(* If [src] does not parse, reuse [prev]'s maps (last good analysis) but
   carry the current parse diagnostics and the current src/doc so positions
   for the error are correct. Otherwise behave like [analyse]. *)
let analyse_resilient ~prev ~filename ~src : t =
  let fresh = analyse ~filename ~src in
  let parsed_ok =
    Hashtbl.length fresh.type_map > 0
    || fresh.vars <> [] || Hashtbl.length fresh.def_map > 0
  in
  match prev with
  | Some p when not parsed_ok ->
    (* Keep p's symbol maps; swap in current source/doc + the new diagnostics. *)
    { p with src; filename; doc = Utf16.build src;
             diagnostics = fresh.diagnostics }
  | _ -> fresh
```

(Note: `parsed_ok` is a heuristic proxy for "the parse produced usable maps." Once Phase 5's incremental engine exists, replace this with a recovering parser that returns partial maps directly. Documented as such in the function comment.)

- [ ] **Step 4: Use it in the server.** In `server.ml`, change `analyse_and_cache` to read the previous cached analysis and pass it as `~prev`:

```ocaml
let analyse_and_cache uri src =
  let filename = try Lsp.Types.DocumentUri.to_path uri
                 with _ -> Lsp.Types.DocumentUri.to_string uri in
  let key = Lsp.Types.DocumentUri.to_string uri in
  let prev = Hashtbl.find_opt doc_cache key in
  let analysis = Analysis.analyse_resilient ~prev ~filename ~src in
  Hashtbl.replace doc_cache key analysis;
  analysis
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'resilient' 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lsp/lib/analysis.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): error-resilient analysis (retain last good maps on parse failure)"
```

---

### Task 1.3: Versioned, debounced, crash-isolated analysis

Three coupled stability bugs in `server.ml`'s `did_open`/`did_change`:
1. The background `Lwt.async` TIR fiber does an **unconditional** `Hashtbl.replace` + `send_diagnostic` with **no version guard** — a slow fiber for edit *N* can overwrite/flicker edit *N+1*'s results.
2. No **debounce** — every keystroke runs a full analyse synchronously + spawns a fiber.
3. The fiber has **no exception handler** — a raise in `run_tir_pass` hits the global async hook and can kill the server.

Fix: stamp each document with a monotonically increasing version; have the fiber re-check the version before publishing; wrap the fiber body in a catch; and debounce the change handler.

**Files:**
- Modify: `lsp/lib/server.ml`
- Test: `lsp/test/test_lsp.ml` (unit-test the version guard logic via a small helper)

- [ ] **Step 1: Write the failing test** for the guard helper:

```ocaml
let test_version_guard () =
  let open March_lsp_lib.Server in
  let vt = make_version_table () in
  bump_version vt "u" ; (* v=1 *)
  bump_version vt "u" ; (* v=2 *)
  (* A fiber that started at v=1 must NOT publish once current is v=2. *)
  Alcotest.(check bool) "stale rejected" false (is_current vt "u" 1);
  Alcotest.(check bool) "current accepted" true  (is_current vt "u" 2)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'version' 2>&1 | tail -20`
Expected: FAIL — `make_version_table` unbound.

- [ ] **Step 3: Implement the version table + guarded fibers.** In `server.ml`, near `doc_cache`:

```ocaml
(* Monotonic per-document version; a background fiber only publishes if the
   document hasn't advanced since the fiber started. *)
let make_version_table () : (string, int) Hashtbl.t = Hashtbl.create 16
let versions = make_version_table ()
let bump_version vt uri =
  let v = (match Hashtbl.find_opt vt uri with Some n -> n | None -> 0) + 1 in
  Hashtbl.replace vt uri v; v
let is_current vt uri v =
  match Hashtbl.find_opt vt uri with Some n -> n = v | None -> false
```

Rewrite the `did_change` fiber spawn (and the identical `did_open` one) to capture the version, guard, and catch:

```ocaml
method on_notif_doc_did_change ~notify_back vdoc _changes ~old_content:_ ~new_content =
  let uri = vdoc.Lsp.Types.VersionedTextDocumentIdentifier.uri in
  let uri_str = Lsp.Types.DocumentUri.to_string uri in
  let v = bump_version versions uri_str in
  let a = analyse_and_cache uri new_content in
  notify_back#send_diagnostic a.Analysis.diagnostics;
  Lwt.dont_wait
    (fun () ->
       (* Only this fiber's edit is still current → publish TIR insights. *)
       if is_current versions uri_str v then begin
         let a2 = Analysis.run_tir_pass a in
         if is_current versions uri_str v then begin
           Hashtbl.replace doc_cache uri_str a2;
           notify_back#send_diagnostic a2.Analysis.diagnostics
         end
       end;
       Lwt.return_unit)
    (fun exn ->
       (* A TIR-pass bug must not take down the server. *)
       Printf.eprintf "march-lsp: TIR fiber error: %s\n%!"
         (Printexc.to_string exn))
```

**Debounce:** since linol's handler is invoked per notification, add a lightweight debounce by recording a timestamp and, before running the synchronous analyse, checking whether another change arrived within a small window. The simplest robust form for the cooperative Lwt loop: coalesce by version — keep the synchronous AST analyse (it's the cheap, must-be-fresh part once Task 1.1 lands) but gate the *expensive* `run_tir_pass` behind the version check above (already done). Document that true time-based debounce of the AST pass lands with the incremental engine (Phase 5), where it becomes cheap enough not to need it.

- [ ] **Step 4: Record backtraces in `main.ml`.** Add as the first line of `let () =` in `lsp/bin/main.ml`:

```ocaml
  Printexc.record_backtrace true;
```

(so the fatal-error backtrace it already prints is non-empty).

- [ ] **Step 5: Run to verify it passes**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'version' 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 6: Build the server**

Run: `cd /Users/80197052/code/march && dune build lsp/bin/main.exe 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add lsp/lib/server.ml lsp/bin/main.ml lsp/test/test_lsp.ml
git commit -m "fix(lsp): version-guard + crash-isolate background TIR fiber; record backtraces"
```

---

## Phase 2: Query-Core Extraction, Standalone CLI, Editor Portability

### Task 2.1: Extract a transport-agnostic `Query` facade

Today, request logic is split between typed linol handlers and a hand-rolled JSON `on_unknown_request`. Extract one pure facade — input: cached `Analysis.t` + UTF-16 position; output: plain OCaml records — so the server *and* the CLI share exactly one code path, and so the query layer is testable without JSON-RPC.

**Files:**
- Create: `lsp/lib/query.ml`
- Modify: `lsp/lib/dune` (no new deps)
- Test: `lsp/test/test_lsp.ml`

- [ ] **Step 1: Write the failing test:**

```ocaml
let test_query_hover_record () =
  let src = "fn f() -> Int do\n  41\nend\n" in
  let a = An.analyse ~filename:"t.march" ~src in
  let r = March_lsp_lib.Query.hover a ~line:0 ~utf16_char:3 in  (* on 'f' *)
  Alcotest.(check bool) "hover has type" true (r.March_lsp_lib.Query.h_type <> None)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe -- test 'query_hover' 2>&1 | tail -20`
Expected: FAIL — `Query` unbound.

- [ ] **Step 3: Implement the facade** in `lsp/lib/query.ml`:

```ocaml
(** Transport-agnostic query facade over [Analysis].
    Positions are UTF-16 (editor) columns; conversion to byte columns happens
    here so callers (LSP server, CLI) never touch encoding. *)

type hover_result = {
  h_type : string option;
  h_doc  : string option;
  h_perf : string option;
}

type location = { loc_uri : string; loc_range : (int * int * int * int) }
(* loc_range = (start_line, start_char, end_line, end_char) in UTF-16 *)

let hover (a : Analysis.t) ~line ~utf16_char : hover_result =
  { h_type = Analysis.query_type_at a ~line ~utf16_char;
    h_doc  = Analysis.query_doc_name_at a ~line ~utf16_char;
    h_perf = Analysis.query_perf_insight_at a ~line ~utf16_char }

let definition (a : Analysis.t) ~line ~utf16_char : location option =
  match Analysis.query_definition_at a ~line ~utf16_char with
  | None -> None
  | Some (l : Lsp.Types.Location.t) ->
    let r = l.range in
    Some { loc_uri = Lsp.Types.DocumentUri.to_string l.uri;
           loc_range =
             (r.start.line, r.start.character, r.end_.line, r.end_.character) }

let diagnostics (a : Analysis.t) : Lsp.Types.Diagnostic.t list = a.Analysis.diagnostics
let completions (a : Analysis.t) ~line ~utf16_char =
  Analysis.query_completions_at a ~line ~utf16_char
let references (a : Analysis.t) ~include_declaration ~line ~utf16_char =
  Analysis.query_references_at a ~include_declaration ~line ~utf16_char
```

(Add the `Lsp` module alias at the top: `module Lsp = Linol_lsp.Lsp`.)

- [ ] **Step 4: Re-point the server handlers** at `Query` where trivial (hover, definition) so the two code paths converge. Keep behaviour identical; this is a refactor — the existing hover test must still pass.

- [ ] **Step 5: Run to verify it passes + no regressions**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_lsp.exe 2>&1 | tail -15`
Expected: PASS — including `test_query_hover_record` and all prior tests.

- [ ] **Step 6: Commit**

```bash
git add lsp/lib/query.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "refactor(lsp): transport-agnostic Query facade shared by server + CLI"
```

---

### Task 2.2: `march-lsp query` — stateless CLI for editors, scripts, and LLMs

A one-shot, stateless command: read a file (or stdin), run analysis, answer one query, emit JSON, exit. No JSON-RPC handshake, no server lifecycle. This is the "runnable standalone so an LLM can use it" deliverable.

**CLI contract:**
```
march-lsp query hover       <file> --line N --col M      [--stdin]
march-lsp query definition  <file> --line N --col M
march-lsp query references  <file> --line N --col M
march-lsp query completions <file> --line N --col M
march-lsp query diagnostics <file>
```
`--line`/`--col` are **0-indexed UTF-16** (LSP convention). `--stdin` reads source from stdin (so an LLM can pipe unsaved buffers). Output is a single JSON object on stdout; exit 0 on success, 2 on usage error.

**Files:**
- Create: `lsp/bin/query_cli.ml`
- Modify: `lsp/bin/main.ml` (dispatch `query` → `query_cli`)
- Modify: `lsp/bin/dune`
- Create: `lsp/test/test_query_cli.ml`
- Modify: `lsp/test/dune`

- [ ] **Step 1: Write the failing test** (`lsp/test/test_query_cli.ml`):

```ocaml
(* Drive the CLI by calling its pure entry directly, asserting on the JSON. *)
let run args ~src =
  Query_cli.run_to_string args ~src_override:(Some src)

let test_cli_diagnostics_json () =
  let src = "fn f() -> Int do\n  true\nend\n" in  (* type error: Bool vs Int *)
  let out = run ["query"; "diagnostics"; "t.march"] ~src in
  Alcotest.(check bool) "json has diagnostics array"
    true (Astring.String.is_infix ~affix:"\"diagnostics\"" out)

let test_cli_hover_json () =
  let src = "fn f() -> Int do\n  41\nend\n" in
  let out = run ["query"; "hover"; "t.march"; "--line"; "0"; "--col"; "3"] ~src in
  Alcotest.(check bool) "json has type field"
    true (Astring.String.is_infix ~affix:"\"type\"" out)

let () =
  Alcotest.run "query_cli"
    [ "cli",
      [ Alcotest.test_case "diagnostics" `Quick test_cli_diagnostics_json;
        Alcotest.test_case "hover" `Quick test_cli_hover_json ] ]
```

Add to `lsp/test/dune`:
```lisp
(test
 (name test_query_cli)
 (libraries march_lsp_lib query_cli_lib alcotest astring))
```

(To make `Query_cli` testable, put its logic in a library `query_cli_lib` under `lsp/bin/` or a small `lsp/lib/` module — simplest: define the logic in `lsp/lib/query_cli.ml` and have `lsp/bin/query_cli.ml` be a 1-line `let () = exit (March_lsp_lib.Query_cli.main Sys.argv)`. Use that arrangement; update paths accordingly.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_query_cli.exe 2>&1 | tail -20`
Expected: FAIL — `Query_cli` unbound.

- [ ] **Step 3: Implement** `lsp/lib/query_cli.ml`:

```ocaml
(** Stateless one-shot CLI: analyse one file, answer one query, print JSON.
    Designed for editors without a persistent client, scripts, and LLMs
    (which can pipe an unsaved buffer via --stdin). *)

module Lsp = Linol_lsp.Lsp

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let n = in_channel_length ic in
    let b = Bytes.create n in really_input ic b 0 n; Bytes.to_string b)

let read_stdin () =
  let buf = Buffer.create 4096 in
  (try while true do Buffer.add_channel buf stdin 4096 done with End_of_file -> ());
  Buffer.contents buf

(* tiny JSON emitter to avoid a dep; values are already simple *)
let jstr s = "\"" ^ String.concat "" (List.map (function
  | '"' -> "\\\"" | '\\' -> "\\\\" | '\n' -> "\\n" | c -> String.make 1 c)
  (List.init (String.length s) (String.get s))) ^ "\""

let opt_field name = function None -> name ^ ":null"
  | Some s -> name ^ ":" ^ jstr s

let find_flag argv name =
  let rec go = function
    | a :: b :: _ when a = name -> Some b
    | _ :: rest -> go rest
    | [] -> None
  in go (Array.to_list argv)

let int_flag argv name default =
  match find_flag argv name with Some s -> int_of_string s | None -> default

(* [src_override] lets tests inject source without touching the filesystem. *)
let run_to_string (args : string list) ~src_override : string =
  let argv = Array.of_list args in
  match args with
  | _ :: feature :: file :: _ ->
    let src = match src_override with
      | Some s -> s
      | None -> if Array.exists ((=) "--stdin") argv then read_stdin ()
                else read_file file in
    let a = Analysis.analyse ~filename:file ~src in
    let line = int_flag argv "--line" 0 and col = int_flag argv "--col" 0 in
    (match feature with
     | "hover" ->
       let r = Query.hover a ~line ~utf16_char:col in
       "{" ^ opt_field "\"type\"" r.Query.h_type ^ ","
           ^ opt_field "\"doc\"" r.Query.h_doc ^ ","
           ^ opt_field "\"perf\"" r.Query.h_perf ^ "}"
     | "definition" ->
       (match Query.definition a ~line ~utf16_char:col with
        | None -> "{\"definition\":null}"
        | Some l ->
          let (sl, sc, el, ec) = l.Query.loc_range in
          Printf.sprintf
            "{\"definition\":{\"uri\":%s,\"range\":{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}}}}"
            (jstr l.Query.loc_uri) sl sc el ec)
     | "diagnostics" ->
       let ds = Query.diagnostics a in
       let one (d : Lsp.Types.Diagnostic.t) =
         let r = d.range in
         Printf.sprintf
           "{\"message\":%s,\"range\":{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}}}"
           (jstr d.message) r.start.line r.start.character r.end_.line r.end_.character
       in
       "{\"diagnostics\":[" ^ String.concat "," (List.map one ds) ^ "]}"
     | "completions" ->
       let items = Query.completions a ~line ~utf16_char:col in
       let label (it : Lsp.Types.CompletionItem.t) = jstr it.label in
       "{\"completions\":[" ^ String.concat "," (List.map label items) ^ "]}"
     | "references" ->
       let locs = Query.references a ~include_declaration:true ~line ~utf16_char:col in
       let one (l : Lsp.Types.Location.t) =
         let r = l.range in
         Printf.sprintf
           "{\"uri\":%s,\"range\":{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}}}"
           (jstr (Lsp.Types.DocumentUri.to_string l.uri))
           r.start.line r.start.character r.end_.line r.end_.character
       in
       "{\"references\":[" ^ String.concat "," (List.map one locs) ^ "]}"
     | other -> "{\"error\":" ^ jstr ("unknown query: " ^ other) ^ "}")
  | _ -> "{\"error\":\"usage: march-lsp query <feature> <file> [--line N --col M] [--stdin]\"}"

let main (argv : string array) : int =
  let out = run_to_string (Array.to_list argv) ~src_override:None in
  print_string out; print_newline ();
  if String.length out >= 9 && String.sub out 0 9 = "{\"error\":" then 2 else 0
```

(Note: `Query.references`/`Query.completions` return the LSP types — keep those return types as-is from Task 2.1; the CLI only reads `.label`/`.range`. If `Query.references` was defined to return `location` records instead, adjust the emitter to match. Keep the two consistent.)

- [ ] **Step 4: Dispatch from `main.ml`.** Make `lsp/bin/main.ml` branch on `argv.(1)`:

```ocaml
let () =
  Printexc.record_backtrace true;
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "query" then
    exit (March_lsp_lib.Query_cli.main Sys.argv)
  else begin
    (* ... existing stdio LSP server startup ... *)
  end
```

Add `query.ml`/`query_cli.ml` to `lsp/lib/dune`'s modules (they're picked up automatically) and ensure `march_lsp_lib` exposes them.

- [ ] **Step 5: Run the CLI tests**

Run: `cd /Users/80197052/code/march && dune exec lsp/test/test_query_cli.exe 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 6: Smoke-test the real binary end-to-end**

```bash
cd /Users/80197052/code/march && dune build lsp/bin/main.exe
printf 'fn f() -> Int do\n  true\nend\n' > /tmp/t.march
./_build/default/lsp/bin/main.exe query diagnostics /tmp/t.march
```
Expected: a JSON object with a non-empty `diagnostics` array (the `Bool` vs `Int` mismatch).

- [ ] **Step 7: Commit**

```bash
git add lsp/lib/query_cli.ml lsp/bin/main.ml lsp/bin/query_cli.ml lsp/bin/dune lsp/test/test_query_cli.ml lsp/test/dune
git commit -m "feat(lsp): stateless 'march-lsp query' CLI (editor/script/LLM-friendly, JSON out)"
```

---

### Task 2.3: Editor conformance + setup docs

The LSP is already protocol-portable; the gap is (a) the conformance fixes from Phases 0–1 and (b) copy-paste configs. No bespoke extension (per scope decision).

**Files:**
- Create: `lsp/docs/editors.md`
- Modify: `lsp/README.md` (link to it; correct the feature table)

- [ ] **Step 1: Write `lsp/docs/editors.md`** with working snippets for each editor. Content (verbatim, fill the install path):

````markdown
# Using march-lsp in your editor

`march-lsp` speaks LSP over stdio. Build it with `dune build lsp/bin/main.exe`
and put the binary on your PATH (or use the absolute `_build/...` path below).

## Neovim (built-in LSP, nvim 0.11+)
```lua
vim.lsp.config.march = {
  cmd = { "march-lsp" },
  filetypes = { "march" },
  root_markers = { "forge.toml" },
}
vim.lsp.enable("march")
vim.filetype.add({ extension = { march = "march" } })
```

## Helix (`~/.config/helix/languages.toml`)
```toml
[[language]]
name = "march"
scope = "source.march"
file-types = ["march"]
roots = ["forge.toml"]
language-servers = ["march-lsp"]

[language-server.march-lsp]
command = "march-lsp"
```

## Zed (`~/.config/zed/settings.json` + a small extension, or via generic LSP)
```json
{ "lsp": { "march-lsp": { "binary": { "path": "march-lsp" } } } }
```

## Emacs (eglot)
```elisp
(add-to-list 'eglot-server-programs '(march-mode . ("march-lsp")))
```

## VS Code (generic LSP client, e.g. via a 10-line client or an existing
generic-LSP extension)
Point the client `serverOptions` at `{ command: "march-lsp", transport: stdio }`
and set `documentSelector` to `{ language: "march" }`.

## Standalone / LLM / scripting (no editor)
```
march-lsp query hover       file.march --line 10 --col 4
march-lsp query definition  file.march --line 10 --col 4
march-lsp query references  file.march --line 10 --col 4
march-lsp query completions file.march --line 10 --col 4
march-lsp query diagnostics file.march
cat buffer.march | march-lsp query diagnostics buffer.march --stdin
```
All positions are 0-indexed UTF-16. Output is one JSON object on stdout.
````

- [ ] **Step 2: Correct the README feature table** — mark Code Actions ✅ (not "stub"), add References/Rename/Signature Help/Folding/Code Lens/Perf insights rows, and add a "Standalone CLI" row pointing at `editors.md`.

- [ ] **Step 3: Commit**

```bash
git add lsp/docs/editors.md lsp/README.md
git commit -m "docs(lsp): editor setup guide (Neovim/Helix/Zed/Emacs/VS Code) + CLI reference"
```

---

## Phase 3: Sound Symbol Identity *(design + checklist + sub-plan trigger)*

**Problem.** `def_map : (string, span)`, `use_map : (span, string)`, `refs_map : (string, span list)` are **name-keyed**. Shadowing collapses (`Hashtbl.replace`, last-writer-wins). Consequences: go-to-def on a local can jump to an unrelated same-named binding; **rename rewrites every same-named identifier in scope regardless of which binding it refers to** (silent code corruption); references are incomplete/incorrect.

**Objective.** Replace name identity with **binder identity**: every binding occurrence gets a unique `symbol_id`; every use resolves (through the typechecker's scope) to the `symbol_id` it refers to. Def/refs/rename then operate on `symbol_id`, not strings.

**Design.**
- Introduce `type symbol_id = int` allocated per binding site during the typecheck/resolve walk that already populates the maps (`collect_expr`/`collect_decl` in `analysis.ml`).
- New maps: `def_by_id : (symbol_id, span)`, `use_to_id : (span, symbol_id)`, `id_to_uses : (symbol_id, span list)`, `id_name : (symbol_id, string)`.
- Resolution: when walking an `EVar`/`ECon`/qualified `EField`, look up the *current scope* (the resolver/typechecker already threads an environment — reuse it) to get the binder's `symbol_id`, not the raw string.
- `definition_at`/`references_at`/`rename_at` become: find use-span under cursor → `symbol_id` → its def span / all use spans. `rename_at` additionally adds `prepareRename` validation (reject if the cursor isn't on a renameable binder, or the binder is in stdlib/not owned by this file).

**Why it must precede Phases 4–5.** Context-aware completion wants scope-precise locals (same scope info); the incremental engine keys invalidation on symbols, not names.

**Implementation checklist (for the sub-plan):**
- [ ] Read `lib/typecheck/*.ml` (or `lib/resolver/*.ml`) to find the scope environment threaded during inference; confirm it exposes (or can expose) a stable binder identity.
- [ ] Add `symbol_id` allocation at binding sites (let, fn param, lambda param, match-arm binders, top-level decls).
- [ ] Build the four `*_by_id` maps in `analyse`; keep the old name-keyed maps temporarily for non-rename consumers, or migrate them all.
- [ ] Rewrite `definition_at`, `references_at`, `rename_at` over `symbol_id`.
- [ ] Add `prepare_rename_at` + wire `renameProvider.prepareProvider = true` in `config_modify_capabilities`.
- [ ] **Tests** (TDD, each red→green): shadowing — `let x = 1 in let x = 2 in x` renames only the inner binding; a top-level `x` and a local `x` are distinct; rename refuses a stdlib symbol; references exclude same-named-but-different-binder occurrences; go-to-def on a shadowed local lands on the nearest enclosing binder.
- [ ] Regression: all Phase 0–2 tests still green.

**Trigger:** at Phase 3 start, write `specs/plans/2026-06-13-lsp-symbol-identity.md` from this seed after reading the typecheck/resolver scope modules, then execute it.

---

## Phase 4: Context-Aware Completion *(design + checklist + sub-plan trigger)*

**Problem.** `completions_at (a:t) ~line:_ ~character:_` **ignores the cursor** and returns a flat concatenation of every keyword, in-scope var, type, ctor, interface, and three hard-coded sigils — no dot-completion, no scope-precision, no import-awareness, no ranking. The server also drops the trigger char (`~ctx:_`).

**Objective.** Make completion position- and context-aware: (1) **dot-completion** — typing `expr.` completes the fields/methods of `expr`'s *type*; (2) **scope-precise locals** at the cursor (depends on Phase 3 symbol scopes); (3) **qualified completion** — `List.` → that module's members; (4) **ranking** via `sortText` (locals > current-module > imported > stdlib) and `filterText`; (5) thread the trigger char through the server.

**Design.**
- Plumb the real position into `completions_at` (remove the `_` on `~line`/`~character`) and pass `~trigger` from the server's `~ctx`.
- Classify completion *context* from the text immediately left of the cursor using the **line index** (Phase 0) + a small lexer-backed scan (not regex): are we after a `.`? after a `Module.`? at statement start? The scan reuses `Utf16` for the cursor's byte offset.
- Dot-completion: find the receiver expression's span ending just before the `.` via the typed `type_map`; get its type; enumerate fields (records) / interface methods / variants; build items with the *member's* type as detail.
- Scope-precise locals: from Phase 3's scope at the cursor's `symbol_id` environment.
- Ranking: assign `sortText` buckets; set `filterText = label`; attach `CompletionItem.detail` (rendered type) and `documentation` (doc string) — pulling docs through the symbol, fixing the name-collision doc bug noted in review.

**Implementation checklist (for the sub-plan):**
- [ ] Read how record/interface/variant member sets are represented in `Tc` so dot-completion can enumerate them.
- [ ] Implement `completion_context_at : doc -> byte_offset -> [ `Dot of span | `Qualified of string | `Toplevel | `Expr ]`.
- [ ] Implement dot-completion off `type_map`.
- [ ] Implement qualified-module completion off the import/module table.
- [ ] Scope-precise locals (after Phase 3).
- [ ] `sortText`/`filterText`/`detail`/`documentation` on every item.
- [ ] Thread `~trigger` from `on_req_completion` (`~ctx`).
- [ ] **Tests:** `record.<TAB>` offers only that record's fields; `List.<TAB>` offers `map/filter/...`; a local bound 2 lines up is offered, an out-of-scope top-level name is *not* offered inside a narrower scope where shadowed; trigger `.` produces member items; ranking puts locals first.

**Trigger:** at Phase 4 start, write `specs/plans/2026-06-13-lsp-completion.md` from this seed; depends on Phase 3.

---

## Phase 5: Incremental Engine (CAS primitives) + Workspace Model *(design + checklist + sub-plan trigger)*

**Problem.** `analyse` re-runs lex→parse→desugar→typecheck on the whole file every change; `run_tir_pass` re-runs the *entire* TIR pipeline a second time; there is no project/dependency model (each open doc analyzed in isolation; editing A doesn't re-check B that imports A; no workspace symbols; no cross-file refs). `forge_config.ml` (which discovers import paths) is never even called by the server.

**Objective.** A demand-driven incremental engine keyed by **content hashes of definitions**, with the `sig_hash`/`impl_hash` invalidation firewall, plus a workspace model that tracks the dependency graph and serves cross-file queries.

**Design — reuse the CAS *primitives*, lifted upstream of typecheck.**
- **Def content hashing at the AST/desugared level** (not TIR — TIR is too late, it's downstream of the typecheck we want to skip). Extend `March_cas.Serialize` to canonically serialize a *desugared* `decl`; hash with `March_cas.Blake3`. Compute `sig_hash` (signature only) and `impl_hash` (full) per the existing `Hash` discipline.
- **Invalidation firewall:** cache *typecheck results* (the typed maps for a def) keyed by `impl_hash`. On edit, re-hash changed defs. If a dependency's **`sig_hash` is unchanged**, its dependents need *no* re-typecheck (their types can't change) — only `sig_hash` changes propagate downstream. This is the rust-analyzer red-green / separate-compilation idea, and the CAS already encodes the discipline.
- **Dependency graph via `March_cas.Scc`** — reuse SCC computation to know what to invalidate downstream and to order re-checking.
- **Workspace model:** wire `forge_config.ml` in at last (`initialize`); build the import graph; register `didChangeWatchedFiles` so on-disk dependency edits invalidate dependents; maintain a global symbol index for **workspace symbols** and **cross-file references**.
- **CAS the `run_tir_pass` path (Task 5.5):** the perf-insights pipeline *does* run mono→defun→codegen-ish lowering — route it through `Cas.Pipeline.compile_scc` to skip unchanged SCCs. This is the one place the *existing* CAS helps directly.

**Implementation checklist (for the sub-plan):**
- [ ] Read `lib/cas/serialize.ml`, `hash.ml`, `scc.ml`, `pipeline.ml`, and the typecheck entry (`Tc.check_module_full`) to find the cleanest seam to cache per-def typecheck results.
- [ ] Add AST/desugared-level canonical serialization + `sig_hash`/`impl_hash` for `decl`.
- [ ] Build a per-def typecheck-result cache; implement sig-hash-gated downstream invalidation.
- [ ] Replace the whole-file `analyse` with a query that recomputes only changed defs + dependents (keep `analyse` as the cold-start path).
- [ ] Wire `forge_config` into `initialize`; build the import/dependency graph; register `didChangeWatchedFiles`.
- [ ] Implement `workspace/symbol` and cross-file `references`/`definition`.
- [ ] Route `run_tir_pass` through `Cas.Pipeline.compile_scc`.
- [ ] Add time-based debounce of the AST pass (now cheap) in the change handler.
- [ ] **Tests:** editing a function *body* (sig unchanged) does not invalidate callers' cached types; editing a *signature* re-checks direct dependents; a 200-def file edit re-typechecks O(changed) not O(file) (assert via an instrumented counter); workspace symbol finds a symbol in an unopened file; cross-file references span two files; a `didChangeWatchedFiles` on a dependency refreshes the dependent's diagnostics.
- [ ] Add **JSON-RPC integration tests** (the entire `server.ml`/`main.ml` layer is currently untested): spawn the binary, send `initialize`/`didOpen`/`hover`/`definition` over stdio, assert responses. This closes the largest test-coverage hole.

**Trigger:** at Phase 5 start, write `specs/plans/2026-06-13-lsp-incremental-engine.md`; depends on Phase 3.

---

## Overall Testing Strategy

- **Unit (alcotest), transport-free:** every analysis/query feature is tested by calling `Analysis.*`/`Query.*` directly with UTF-16 positions (the new `query_*` wrappers). This is the bulk and runs fast.
- **CLI (alcotest):** `Query_cli.run_to_string` asserts on emitted JSON with injected source — no filesystem, no process spawn.
- **Integration (Phase 5):** spawn the real binary, speak JSON-RPC over stdio, assert protocol responses — the one layer unit tests can't reach.
- **Encoding:** dedicated `test_utf16` suite with 2-byte, astral (surrogate-pair), and ASCII-identity cases; plus a non-ASCII hover test in the main suite.
- **Regression gate:** after every task, `dune build lsp/bin/main.exe && dune runtest lsp/` must be green before committing.
- **Anti-tautology rule:** no `check bool ... true true`, no `match _ -> true` smoke assertions. Every test asserts a *specific* expected value. (The current suite has ~10–12 tautological tests; new tests must not add to that, and touched ones should be tightened.)

---

## Self-Review

**Spec coverage vs. the rewritten priority list:**
- Priority 0 (hygiene + UTF-16) → Tasks 0.1–0.3. ✅
- Priority 1 (stdlib memo, error recovery, versioned/debounced/cancellable) → Tasks 1.1–1.3. ✅
- Priority 2 (query core + CLI + editor portability) → Tasks 2.1–2.3. ✅ (satisfies "standalone so an LLM can use it" via stateless CLI, and "portable to any editor" via conformance + `editors.md`).
- Priority 3 (symbol identity), 4 (completion), 5 (incremental + workspace) → Phases 3–5 design seeds with checklists and explicit sub-plan triggers. ✅
- CAS question → addressed: primitives reused in Phases 1 & 5; existing store wired into `run_tir_pass` (Task 5.5). ✅

**Placeholder scan:** Phases 0–2 contain complete, compilable code against verified symbols (`Analysis.t` fields, `analyse`, `find_stdlib_dir`, `server.ml` handlers, `Cas.compiler_identity`/`Blake3`). Phases 3–5 deliberately provide *interfaces, design, and test checklists* rather than line-exact OCaml, because that code depends on typecheck/TIR internals not yet read — each is gated behind a "read X, then write the sub-plan" trigger rather than fabricated. This is a scoping decision, not a TODO.

**Type consistency:** `query_*` wrappers in `analysis.ml` (Task 0.3) are consumed by `Query` (2.1) and `Query_cli` (2.2) under consistent names (`query_type_at`, `query_definition_at`, `query_completions_at`, `query_references_at`, `query_doc_name_at`, `query_perf_insight_at`). `Utf16` function names (`build`, `line_start`, `lsp_char_to_byte_col`, `byte_col_to_lsp_char`) are used identically in `utf16.ml`, `position.ml`, `analysis.ml`, and `server.ml`. `Query.hover_result`/`location` record fields (`h_type`/`h_doc`/`h_perf`, `loc_uri`/`loc_range`) match between `query.ml` and `query_cli.ml`. The one cross-task caveat flagged inline: `Query.references`/`Query.completions` return LSP types — the CLI emitter reads `.label`/`.range`; if those signatures change, update both together (noted in Task 2.2 Step 3).
