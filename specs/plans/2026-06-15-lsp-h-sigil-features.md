# `~H` HTML-Sigil LSP Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the March LSP understand `~H` HTML templates the way it understands code — validating islands, navigating/completing components, editing tag pairs as a unit, richer HTML linting, and (Tier 4) full language intelligence inside `${…}` interpolations.

**Architecture:** Every feature is anchored on ONE shared traversal (`collect_h_sigils`) that yields each `~H` sigil's raw content plus the byte offsets needed to map an *in-content* position back to an LSP position via the existing `ofs_to_pos`/`pos_to_ofs` helpers. Tiers 1–3 are pure text-scan + existing-analysis lookups (no parser changes). Tier 4 needs a new position↔interpolation-expr map and is specified as a design + sub-plan seed because writing line-exact code against the interpolation desugar requires reading `lib/parser/parser.mly` + `lib/desugar/desugar.ml` first.

**Tech Stack:** OCaml 5.3.0, `linol`/`linol-lwt` (LSP transport), `dune`, `alcotest`. March compiler libs (`march_parser`, `march_desugar`, `march_typecheck`). The LSP lives in `lsp/lib/` (`analysis.ml` = analysis + feature logic; `server.ml` = JSON-RPC server). Tests: `lsp/test/test_lsp.ml`.

**Build/test (run from the worktree):**
- `PATH=/Users/80197052/.opam/march/bin:$PATH dune build --root .` (judge by exit code 0)
- `PATH=/Users/80197052/.opam/march/bin:$PATH dune build @lsp/test/runtest --root .` (exit 0)
- Never use `eval $(opam env)`.

---

## Execution status (2026-06-15)

**Tiers 0–3 implemented** via subagent-driven development (14 feature commits + 1 review-fix commit). 292 `march-lsp` tests, full suite green.

- ✅ **Task 0** — `collect_h_sigils` + position mapping; `collect_html_issues` refactored onto it.
- ✅ **Tier 1** — 1.1 parse `<island>`, 1.2 validate (**conservative**: only flags a loaded module missing `create`/`render`, not unknown names — per-file analysis can't see cross-file components, so flagging unknowns would false-positive), 1.3 go-to-def, 1.4 completion. **1.5 (props typecheck / hover) deferred** behind Tier 4.
- ✅ **Tier 2** — 2.1 tag-pair highlight (`tag_pairs_in_sigil`), 2.2 linked editing, 2.3 folding, 2.4 auto-close on `>` (`onTypeFormatting`).
- ✅ **Tier 3** — 3.1 unknown-tag (Levenshtein), 3.2 duplicate-attr, 3.3 void/self-closing, 3.4 unsafe-interpolation. **3.5 (a11y) not done** (optional).
- ⏸️ **Tier 4** — still a sub-plan seed (full `${…}` interpolation intelligence). Not started.

- ✅ **Scanner unification (done)** — the ~6 hand-written HTML tag scanners (`scan_html_unclosed`, `open_tags_in_sigil`, `dup_attrs_in_sigil`, `void_misuse_in_sigil`, `unsafe_interpolation_in_sigil`, `tag_pairs_in_sigil`) now fold over ONE event tokenizer `tokenize_h_content : string -> html_event list` (`HEOpenTag`/`HECloseTag`/`HEInterp`) — the single source of truth for the skip rules (including the 3 patched edge cases). Scanner region −232 lines (analysis.ml −213 net). All 292 LSP / 1446 full tests unchanged + green. `islands_in_sigil` and `autoclose_tag_at` intentionally left as-is (they need intra-tag offsets / operate on a content prefix; behavior-identical, fixes preserved).
- The review's 3 correctness bugs (autoclose/dup-attr/island `>`-in-attr) + 2 nits (exact `~H` match, no AST re-walk) were patched surgically (`62211d0`) before the unification.

## Background: how `~H` works today

- `~H"…"` is an HTML template sigil (`Ast.ESigil ("H", interp_expr, span)`). It desugars (`lib/desugar/desugar.ml:105+`) to an IOList. `${expr}` interpolations are auto-escaped (`html_auto_escape`). `<island name='Counter' props=${e} />` tags desugar to `IslandView.island_ssr("Counter", Json.to_string(to_json(Counter.create(e))), IOList.to_string(Counter.render(Counter.create(e))))` — i.e. the island contract is the module functions **`create`** and **`render`** (NOT `init`).
- **String-span caveat (critical):** March string-literal spans cover only the opening quote, so the sigil content cannot be sliced from the `ESigil` span. The existing `~H` linter recovers content *textually* from `src` by byte offset (`extract_h_content`). Every feature here follows that approach.

### Existing infra to build on (all in `lsp/lib/analysis.ml`)

| Symbol | Line | What it gives you |
|--------|------|-------------------|
| `type html_issue` | 69 | `{hi_open_span; hi_tag; hi_insert_span; hi_closer}` — the unclosed-tag record |
| `html_void_elements` | 1682 | void-tag list (`br`,`img`,`input`,…) |
| `scan_html_unclosed` | 1690 | `string -> (tag * ofs) list`, the tag balancer |
| `extract_h_content` | 1758 | `src -> start_ofs -> name_len -> (content * content_base_ofs * close_quote_ofs) option` |
| `ofs_to_pos` | 1778 | byte offset → `(1-line, 0-col)` (Ast.span convention) |
| `pos_to_ofs` | 1787 | `(1-line, 0-col)` → byte offset |
| `collect_html_issues` | 1794 | the ESigil walker that finds every `~H` and runs the balancer |
| html_issues → diagnostics | 2627 | how `html_issue`s become `Diagnostic.t` + the `html/unclosed-tag` code |
| `html_close_actions` (quickfix) | ~6178 | the "Close unclosed tag(s)" code action |
| `module_index : (string * string list) list` | 200 | (module name → member names) — for island validation/completion |
| `module_index_of_vars` | 952 | builds the above from the typecheck env |
| `def_map : (string, Ast.span) Hashtbl.t` | — | name → definition span (go-to-def) |
| `document_highlights_at` | 3700 | existing highlight handler to extend |
| `linked_editing_ranges_at` | 3720 | existing linked-edit handler to extend |
| `document_symbols` | 3518 | outline handler |
| `completions_at` | 3211 | completion handler |
| `byte_col_of` / `Pos.*` | — | UTF-16 ↔ byte column conversion at the server boundary |

---

## File Structure

- **`lsp/lib/analysis.ml`** — all detection/feature logic. New: `collect_h_sigils` (Task 0), island parsing + validation (Tier 1), tag-pair pairing (Tier 2), extra lint passes (Tier 3). Add new fields to the `Analysis.t` record (`h_sigils`, and per-tier issue lists) and populate them in `analyse`.
- **`lsp/lib/server.ml`** — wire new requests/capabilities: definition + completion inside islands (Tier 1), documentHighlight/linkedEditingRange/foldingRange extensions (Tier 2), `documentOnTypeFormattingProvider` + handler (Tier 2), diagnostics for the new lint passes (Tier 3).
- **`lsp/test/test_lsp.ml`** — alcotest cases per task; register each in the suite list near the bottom.
- **`specs/plans/2026-06-15-lsp-h-sigil-interpolation.md`** — created when Tier 4 starts (seeded by the Tier-4 section here).

Keep `specs/todos.md` + `specs/progress.md` updated as tiers land (per `CLAUDE.md`).

---

## Task 0 (FOUNDATION): one shared sigil traversal with position mapping

Every tier needs "find each `~H` sigil; map an in-content byte offset to an LSP-style span." Factor that once so the tiers don't each re-walk the AST.

**Files:**
- Modify: `lsp/lib/analysis.ml` (add type + function near line 1755, before `collect_html_issues`; add field to `t` near line 219; populate in `analyse` near line 2627)
- Test: `lsp/test/test_lsp.ml`

- [ ] **Step 1: Write the failing test**

```ocaml
let test_h_sigils_collected () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div>${name}</div>"
  end
end|} in
  let a = An.analyse src in
  Alcotest.(check int) "one ~H sigil found" 1 (List.length a.An.h_sigils);
  let s = List.hd a.An.h_sigils in
  Alcotest.(check bool) "content captured" true
    (An.contains_sub s.An.hs_content "<div>");
  (* in-content offset of '<' maps to the right source line (line 3) *)
  let (l, _c) = An.ofs_to_pos src (s.An.hs_base_ofs + 0) in
  Alcotest.(check int) "content base maps to the sigil's line" 3 l
```

(`An.contains_sub` already exists as a test helper. If `ofs_to_pos`/`hs_*` aren't exposed, the test references the public record fields you add below.)

- [ ] **Step 2: Run it, verify it fails**

Run: `PATH=/Users/80197052/.opam/march/bin:$PATH dune build @lsp/test/runtest --root .`
Expected: compile error — `h_sigils` is not a field of `An.t`.

- [ ] **Step 3: Add the type + field**

In `analysis.ml`, just before `extract_h_content` (~line 1755):

```ocaml
(** One ~H sigil, with the byte offsets needed to map an in-content offset
    back to a source position via [ofs_to_pos src (hs_base_ofs + o)]. *)
type h_sigil = {
  hs_content   : string;    (** raw text between the quotes (interpolation + tags verbatim) *)
  hs_base_ofs  : int;       (** byte offset in src of hs_content.[0] *)
  hs_close_ofs : int;       (** byte offset of the closing quote *)
  hs_span      : Ast.span;  (** the ESigil span (start = the `~`) *)
}
```

Add to the `t` record (near line 219, beside `html_issues`):

```ocaml
  h_sigils : h_sigil list;
  (** Every ~H sigil in the file, for HTML-aware features. *)
```

- [ ] **Step 4: Implement `collect_h_sigils`**

Place after `extract_h_content`/`ofs_to_pos`/`pos_to_ofs` (~line 1792), reusing the exact ESigil walker shape from `collect_html_issues`:

```ocaml
(* Every ~H sigil in [decls], with content recovered textually from [src]. *)
let collect_h_sigils ~(src : string) (decls : Ast.decl list) : h_sigil list =
  let acc = ref [] in
  let consider name (sp : Ast.span) =
    if String.uppercase_ascii name = "H" then begin
      let start_ofs = pos_to_ofs src sp.Ast.start_line sp.Ast.start_col in
      match extract_h_content src start_ofs (String.length name) with
      | None -> ()
      | Some (content, cbase, close_ofs) ->
        acc := { hs_content = content; hs_base_ofs = cbase;
                 hs_close_ofs = close_ofs; hs_span = sp } :: !acc
    end
  in
  let rec ex (e : Ast.expr) =
    (match e with Ast.ESigil (name, _, sp) -> consider name sp | _ -> ());
    match e with
    | Ast.EApp (f, args, _) -> ex f; List.iter ex args
    | Ast.ECon (_, es, _) | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) -> List.iter ex es
    | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s; List.iter (fun (br : Ast.branch) -> ex br.Ast.branch_body) brs
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EIf (c, t, f, _) -> ex c; ex t; ex f
    | Ast.EPipe (a2, b2, _) | Ast.ESend (a2, b2, _) -> ex a2; ex b2
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (e2, fs, _) -> ex e2; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e2, _, _) | Ast.EAnnot (e2, _, _) | Ast.ESpawn (e2, _)
    | Ast.EAssert (e2, _) | Ast.ESigil (_, e2, _) | Ast.EDbg (Some e2, _) -> ex e2
    | _ -> ()
  in
  let rec dl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) -> List.iter (fun (cl : Ast.fn_clause) -> ex cl.Ast.fc_body) fn.Ast.fn_clauses
    | Ast.DMod (_, _, ds, _) | Ast.DDescribe (_, ds, _) -> List.iter dl ds
    | Ast.DLet (_, b, _) -> ex b.Ast.bind_expr
    | _ -> ()
  in
  List.iter dl decls; List.rev !acc
```

> Refactoring note (DRY): once this lands, `collect_html_issues` should iterate `collect_h_sigils` instead of duplicating the walker — do that in Step 6.

Populate the field in `analyse` (near line 2627, where `html_issues` is computed):

```ocaml
    let h_sigils = collect_h_sigils ~src user_decls in
```

and add `h_sigils;` to the `t` record literal in the success path, and `h_sigils = [];` to the error/empty-analysis literal (near line 2013). The compiler enforces both — build to confirm.

- [ ] **Step 5: Expose the helpers the tests/handlers need**

There is no `.mli` in `lsp/lib`, so `ofs_to_pos`, `h_sigil`, and `collect_h_sigils` are already public. No export step needed; just confirm the test compiles.

- [ ] **Step 6: Refactor `collect_html_issues` onto `collect_h_sigils`** (DRY)

Replace its inline walker with `List.iter (fun s -> …) (collect_h_sigils ~src decls)`, using `s.hs_content`, `s.hs_base_ofs`, `s.hs_close_ofs` in place of the local `content/cbase/close_ofs`. Behavior identical — the existing `html/unclosed-tag` tests are your oracle.

- [ ] **Step 7: Run tests, verify pass**

Run: `PATH=/Users/80197052/.opam/march/bin:$PATH dune build @lsp/test/runtest --root .`
Expected: PASS (new test + all existing `~H` tests).

- [ ] **Step 8: Commit**

```bash
git add lsp/lib/analysis.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): shared ~H sigil traversal (collect_h_sigils) + position mapping"
```

---

## Tier 1 — Island intelligence (highest leverage, March-unique)

A typo'd `<island name='X'>` silently breaks SSR/hydration. After desugar these are real `X.create`/`X.render` calls, so the type info exists — we surface it at the sigil.

### Task 1.1: parse island tags out of a sigil

**Files:** Modify `lsp/lib/analysis.ml`; Test `lsp/test/test_lsp.ml`

- [ ] **Step 1: Failing test**

```ocaml
let test_island_parse () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<island name='Counter' />"
  end
end|} in
  let a = An.analyse src in
  let islands = List.concat_map An.islands_in_sigil a.An.h_sigils in
  Alcotest.(check int) "one island" 1 (List.length islands);
  let isl = List.hd islands in
  Alcotest.(check string) "module name" "Counter" isl.An.isl_name
```

- [ ] **Step 2: Run, verify fail** (`islands_in_sigil`/`isl_name` undefined).

- [ ] **Step 3: Implement the parser**

```ocaml
type island_ref = {
  isl_name      : string;     (** module name from name='…' *)
  isl_name_span : Ast.span;   (** span of the NAME text (for def/diag/highlight) *)
  isl_has_props : bool;       (** props= present *)
}

(* Find every <island name='X' …> in one sigil, with the name's source span. *)
let islands_in_sigil (s : h_sigil) : island_ref list =
  let c = s.hs_content and n = String.length s.hs_content in
  let out = ref [] in
  let i = ref 0 in
  let find_from pat start =          (* byte offset of [pat] at/after [start], or -1 *)
    let pl = String.length pat and sl = n in
    let rec go k = if k + pl > sl then -1
      else if String.sub c k pl = pat then k else go (k+1) in go start in
  while !i < n do
    if !i + 7 < n && String.sub c !i 7 = "<island" then begin
      let tag_end = (match find_from ">" !i with -1 -> n | e -> e) in
      (* name='…' or name="…" within [!i, tag_end) *)
      let name_at q =
        let p = "name=" ^ String.make 1 q in
        let k = find_from p !i in
        if k < 0 || k > tag_end then None
        else
          let vs = k + String.length p in
          let ve = (match find_from (String.make 1 q) vs with -1 -> tag_end | e -> e) in
          let nm = String.sub c vs (ve - vs) in
          (* map value start → source span *)
          let (l1, c1) = ofs_to_pos "" 0 in ignore (l1, c1);  (* placeholder, replaced below *)
          Some (nm, vs, ve)
      in
      (match (match name_at '\'' with None -> name_at '"' | r -> r) with
       | Some (nm, vs, ve) ->
         (* NOTE: ofs_to_pos needs the WHOLE src, not "". The caller passes src in;
            see Step 3b — islands_in_sigil takes ~src. *)
         ignore (nm, vs, ve)
       | None -> ());
      i := tag_end + 1
    end else incr i
  done;
  List.rev !out
```

- [ ] **Step 3b: Fix the signature so spans are real**

`ofs_to_pos` needs the full `src`. Change the signature to `islands_in_sigil ~(src:string) (s : h_sigil)` and build each name span from the *absolute* offset `s.hs_base_ofs + vs`:

```ocaml
let islands_in_sigil ~(src : string) (s : h_sigil) : island_ref list =
  (* …as above, but inside name_at, after computing (nm, vs, ve): *)
  let (l, col) = ofs_to_pos src (s.hs_base_ofs + vs) in
  let span = { Ast.file = ""; start_line = l; start_col = col;
               end_line = l; end_col = col + String.length nm } in
  let has_props = find_from "props=" !i >= 0 && find_from "props=" !i < tag_end in
  out := { isl_name = nm; isl_name_span = span; isl_has_props = has_props } :: !out
```

Update the test to call `An.islands_in_sigil ~src`.

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): parse <island> tags in ~H sigils`

### Task 1.2: diagnostic — island name must resolve to a component

**Files:** Modify `analysis.ml` (new issue list + populate + diagnostic), `server.ml` (none — uses existing diagnostics path); Test `test_lsp.ml`

- [ ] **Step 1: Failing test**

```ocaml
let test_island_unknown_module () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<island name='Nope' />"
  end
end|} in
  let a = An.analyse src in
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with Some (`String "html/unknown-island") -> true | _ -> false)
    a.An.diagnostics in
  Alcotest.(check bool) "unknown island flagged" true has
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement validation.** Add a field `island_issues : (Ast.span * string) list` to `t` (span + message), populate in `analyse`:

```ocaml
let island_issues =
  List.concat_map (fun s ->
    List.filter_map (fun (isl : island_ref) ->
      let members = try List.assoc isl.isl_name (module_index_of_vars vars_list)
                    with Not_found -> [] in
      let has m = List.mem m members in
      if members = [] then
        Some (isl.isl_name_span,
          Printf.sprintf "Island component `%s` is not a known module." isl.isl_name)
      else if not (has "create" && has "render") then
        Some (isl.isl_name_span,
          Printf.sprintf "`%s` is not a valid island: it must define `create` and `render`." isl.isl_name)
      else None)
      (islands_in_sigil ~src s))
    h_sigils
```

Emit as diagnostics where `html_issues` are emitted (near line 2627), code `html/unknown-island`, severity Warning, range from the span via the same span→range path the unclosed-tag diagnostics use.

- [ ] **Step 4: Run, verify pass** (and add a positive test: a `mod Counter do fn create… fn render… end` island is NOT flagged).
- [ ] **Step 5: Commit** `feat(lsp): validate <island> components resolve to create/render modules`

### Task 1.3: go-to-definition on an island name

**Files:** Modify `server.ml` `on_req_definition` (or the analysis `definition_at`); Test `test_lsp.ml`

- [ ] **Step 1: Failing test** — cursor on `Counter` in `name='Counter'` returns the def span of module `Counter` (use `def_map` entry for `"Counter.create"` or the module decl span).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** In the definition path, before the normal lookup, check whether `(line, col)` falls inside any `isl_name_span` of `islands_in_sigil ~src` over `a.h_sigils`; if so, look up `Hashtbl.find_opt a.def_map (name ^ ".create")` (fall back to `name ^ ".render"`, then the bare module decl) and return that span. Reuse the existing span→`Location` conversion.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): go-to-definition on <island> component names`

### Task 1.4: completion of component names after `name='`

**Files:** Modify `completions_at` (analysis.ml); Test `test_lsp.ml`

- [ ] **Step 1: Failing test** — completion at the cursor right after `<island name='` offers `Counter` (a module exposing create+render), tagged `CompletionItemKind.Class`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** In `completions_at`, detect the island-name context: the cursor's byte offset lies inside an `~H` sigil (use `a.h_sigils`), and the text immediately to the left matches `name='` / `name="` within a `<island …` tag. When so, return module names from `module_index` whose member list contains both `create` and `render`, as `CompletionItem`s. Return early so the generic completion list doesn't dilute it.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): complete <island> component names`

### Task 1.5 (design only): props type checking + hover

The desugar already wires `props=${e}` into `X.create(e)`, so a type mismatch is *detected* by the typechecker but reported at a confusing location. Re-anchoring it to the island tag requires correlating the diagnostic's span with the sigil — defer to the Tier-4 position↔interpolation map (the props expr is an interpolation). Hover on `<island name='X'>` showing `X.create`'s param type can land once 1.3's name-span hit-test exists; add it opportunistically. **No code here — tracked as a follow-up after Tier 4.**

---

## Tier 2 — Structural editing (reuses existing infra)

### Task 2.1: documentHighlight the matching open/close tag pair

**Files:** Modify `document_highlights_at` (analysis.ml:3700); Test `test_lsp.ml`

- [ ] **Step 1: Failing test** — cursor on `<div>` in `~H"<div><span></span></div>"` returns 2 highlights (the `<div>` and `</div>` tag-name ranges).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Add `tag_pairs_in_sigil ~src (s:h_sigil) : (Ast.span * Ast.span) list` — a variant of `scan_html_unclosed`'s stack walk that, on a successful close, records `(open_name_span, close_name_span)` (both mapped via `ofs_to_pos src (hs_base_ofs + ofs)`). In `document_highlights_at`, if `(line,col)` is inside a `~H` sigil and inside one of a pair's two spans, return both as `DocumentHighlight`s (kind `Text`). Otherwise fall through to the existing identifier-highlight logic.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): highlight matching ~H tag pairs`

### Task 2.2: linked editing of a tag pair

**Files:** Modify `linked_editing_ranges_at` (analysis.ml:3720); Test `test_lsp.ml`

- [ ] **Step 1: Failing test** — cursor on the `div` of `<div>` returns both the open and close `div` name spans (so an editor renames them together).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Reuse `tag_pairs_in_sigil`. If the cursor is inside either name span of a pair, return `[open_name_span; close_name_span]`; else fall through to the existing symbol logic.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): linked editing for ~H tag pairs`

### Task 2.3: folding ranges for element subtrees

**Files:** Modify the foldingRange handler (find it in `server.ml`/`analysis.ml`); Test `test_lsp.ml`

- [ ] **Step 1: Failing test** — a multi-line `~H` with a `<ul> … </ul>` spanning ≥2 lines yields a folding range covering the element.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** From `tag_pairs_in_sigil`, emit a `FoldingRange` from the open tag's line to the close tag's line for each pair whose lines differ. Append to the existing folding ranges.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): folding ranges for ~H elements`

### Task 2.4: auto-close tag on typing `>` (onTypeFormatting)

**Files:** Modify `server.ml` (new capability + handler); Test `test_lsp.ml`

- [ ] **Step 1: Failing test (analysis-level helper)** — a pure `autoclose_at ~src ~h_sigils ~line ~col : TextEdit.t option` returns an edit inserting `</div>` when the just-typed `>` closes a `<div>` open tag that isn't void/self-closing.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement the helper** in `analysis.ml`: locate the sigil containing `(line,col)`; from the content up to that offset, find the nearest unclosed `<tag` immediately to the left; if non-void and not already closed, return a `TextEdit` inserting `</tag>` at the cursor.
- [ ] **Step 4: Wire the capability + handler** in `server.ml`: add `documentOnTypeFormattingProvider = Some (DocumentOnTypeFormattingOptions.create ~firstTriggerCharacter:">" ())` in `config_modify_capabilities`; add a `"textDocument/onTypeFormatting"` branch in `on_unknown_request` that converts the inbound position via `byte_col_of`, calls `autoclose_at`, and returns `[edit]` (remapped to UTF-16) or `[]`.
- [ ] **Step 5: Run, verify pass.**
- [ ] **Step 6: Commit** `feat(lsp): auto-close ~H tags on typing >`

---

## Tier 3 — Richer HTML linting (extends the balancer)

Each pass appends to a single new `t` field `html_lint : (Ast.span * string * string) list` (span, message, diagnostic-code) emitted alongside `html_issues`. One traversal of `a.h_sigils`.

### Task 3.1: unknown / misspelled tag names

**Files:** Modify `analysis.ml` (known-elements set + pass), `server.ml` (none — diagnostics path); Test `test_lsp.ml`

- [ ] **Step 1: Failing test** — `~H"<dvi></dvi>"` produces an `html/unknown-tag` diagnostic mentioning `div` as the suggestion.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Add `html_known_elements` (a list of standard HTML5 tag names + `island`). Scan each sigil's open tags (reuse the open-tag scan from `scan_html_unclosed`, exposing tag + name span); for any tag not in the set and not containing `-` (custom elements/web components are allowed), emit `html/unknown-tag`. Compute the closest known tag by Levenshtein distance ≤2 for the "did you mean" message. (Quickfix to apply the suggestion is a follow-up code action — out of scope for this task to keep it bite-sized.)
- [ ] **Step 4: Run, verify pass** (+ negative test: `<my-widget>` is NOT flagged).
- [ ] **Step 5: Commit** `feat(lsp): flag unknown/misspelled HTML tags in ~H`

### Task 3.2: duplicate attributes

- [ ] **Step 1: Failing test** — `~H"<input type='a' type='b'>"` → `html/duplicate-attr` on the second `type`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Per open tag, scan attribute names (the `name=` tokens before the tag's `>`, respecting quotes); flag the second+ occurrence of a name with its span.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): flag duplicate attributes in ~H`

### Task 3.3: void/self-closing misuse

- [ ] **Step 1: Failing tests** — `~H"<br>text</br>"` → `html/void-with-children`; `~H"<div/>"` → `html/self-closing-nonvoid` (Hint).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Extend the tag scan: a `</tag>` for a void `tag` → `void-with-children`; a self-closing (`/>`) non-void, non-`island` element → `self-closing-nonvoid`.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): flag void/self-closing misuse in ~H`

### Task 3.4: XSS lint — interpolation in raw contexts

- [ ] **Step 1: Failing test** — `~H"<script>${x}</script>"` → `html/unsafe-interpolation` Warning (auto-escape doesn't make JS safe).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Track when the scanner is inside a `<script>`/`<style>` element (push/pop on the tag stack); if a `${` interpolation start occurs while inside one, flag its span.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(lsp): warn on interpolation inside <script>/<style> in ~H`

### Task 3.5 (optional): a11y lints

`<img>` without `alt`, `<label>` without `for`/wrapped control, duplicate `id` within a template → `html/a11y-*` Hints. Same per-tag scan. Implement only if Tiers 1–3 land with budget to spare; one task per rule, same TDD shape as 3.2.

---

## Tier 4 — Language intelligence inside `${…}` (DESIGN + SUB-PLAN SEED)

**Objective:** hover, type-at, go-to-definition, completion, and diagnostics for the code written inside `${expr}` interpolations — i.e. treat interpolations as first-class March code.

**Why it's a separate sub-plan (not line-exact tasks here):** the analysis maps (`type_map`, `def_map`, `use_map`) are keyed by `Ast.span`, but the interpolation sub-expressions come from the sigil-content desugar (`lib/desugar/desugar.ml:105+`, parser `desugar_interp` at `lib/parser/parser.mly:965-968`). Whether those sub-exprs carry *accurate source spans* — and not the known string-span artifact — must be verified by reading those modules. Writing fabricated OCaml against an unverified span model would violate this plan's no-placeholder rule. So this tier is specified as objective + interface + checklist, and ends by spawning its own plan.

**Design:**
1. **Position↔interpolation index.** For each `h_sigil`, scan `hs_content` for `${ … }` ranges (brace-depth aware — copy the `${` skip from `scan_html_unclosed:1700`). This yields, per sigil, a list of `(content_start_ofs, content_end_ofs)` interpolation byte ranges → absolute source spans via `ofs_to_pos src (hs_base_ofs + o)`.
2. **Correlate ranges with AST exprs.** The parser builds `~H` interpolation as a `++` chain of `to_string(eI)` parts (`desugar.ml:114 decompose_concat`). In source order, the Nth `${…}` range corresponds to the Nth interpolated `eI`. Build `(absolute_span_of_range, eI)` pairs.
3. **Route the standard handlers.** Add an early check in `hover`/`definition`/`completions_at`/diagnostics: if the cursor span falls inside an interpolation range, resolve against the correlated `eI`'s span using the existing `type_map`/`def_map` (the `eI` already has analysis data because the desugared program was typechecked). For completion inside `${…}`, run the normal scope-aware completion at that expr's position.
4. **Fallback.** If span correlation proves unreliable (string-span artifact), fall back to a re-parse of the interpolation substring as an expression with a base-offset shift — heavier, documented as plan B in the sub-plan.

**Interfaces to add (in the sub-plan):**
```ocaml
type interp_slot = { is_span : Ast.span; is_expr : Ast.expr }
val interp_slots_in_sigil : src:string -> h_sigil -> interp_expr_source -> interp_slot list
val interp_slot_at : t -> line:int -> character:int -> interp_slot option
```

**Checklist (the sub-plan must cover):**
- [ ] Read `parser.mly:965-968` + `desugar.ml:105-360`; document whether interpolated sub-exprs carry accurate spans. Decide span-correlation vs re-parse.
- [ ] Build the position↔interpolation index per sigil; unit-test offset→span mapping on a multi-`${}` line.
- [ ] `interp_slot_at` hit-test; wire hover (type at slot), definition, completion, and diagnostics.
- [ ] Re-anchor the Tier-1.5 island `props=` type mismatch onto the props interpolation slot.
- [ ] Handle nested/adjacent interpolations and `${}` inside attribute values.
- [ ] Tests: hover shows the interpolation expr's type; go-to-def jumps to a local bound outside the sigil; completion lists in-scope locals inside `${}`.

**Trigger:** when Tier 4 starts, create `specs/plans/2026-06-15-lsp-h-sigil-interpolation.md` from this section and execute it as its own plan.

---

## Self-Review

**Spec coverage (the 4 tiers from the review):**
- Tier 1 (island intelligence) → Tasks 1.1–1.4 (parse, validate, go-to-def, completion); 1.5 props/hover deferred behind Tier 4 with rationale. ✅
- Tier 2 (structural editing) → 2.1 highlight, 2.2 linked editing, 2.3 folding, 2.4 onTypeFormatting auto-close. ✅
- Tier 3 (richer linting) → 3.1 unknown tags, 3.2 dup attrs, 3.3 void/self-closing, 3.4 XSS, 3.5 a11y (optional). ✅
- Tier 4 (interpolation intelligence) → design + interfaces + checklist + sub-plan trigger (deep, parser-dependent). ✅
- Foundation → Task 0 (`collect_h_sigils`) underpins all tiers. ✅

**Placeholder scan:** Tasks 0–3 contain real code/tests grounded in existing helpers (`extract_h_content`, `ofs_to_pos`, `scan_html_unclosed`, `module_index_of_vars`, `def_map`). The one deliberate `placeholder` marker in Task 1.1 Step 3 is fixed in Step 3b (signature correction) — keep both steps. Tier 4 is intentionally design-only per the repo's "deep phases get a sub-plan" convention (mirrors `2026-06-13-lsp-best-in-class.md`).

**Type consistency:** `h_sigil` fields (`hs_content`/`hs_base_ofs`/`hs_close_ofs`/`hs_span`) are used identically across tiers; `island_ref` (`isl_name`/`isl_name_span`/`isl_has_props`) is consistent in 1.1–1.4; the island contract is `create`+`render` everywhere (matching the desugar, NOT `init`).

**Integration note:** all tiers add fields to the `Analysis.t` record — every `t` construction site (success + error/empty paths) must initialize them or the build fails (OCaml enforces this; it's the safety net).

---

## Execution Handoff

Tiers are independent and individually shippable. Recommended order: **Task 0 → Tier 1 → Tier 2 → Tier 3 → (sub-plan) Tier 4**. Tiers 1/2/3 can run as parallel subagents *after* Task 0 lands (they share `collect_h_sigils` but otherwise touch disjoint regions — though each adds a `t` field, so integrate sequentially to avoid record-literal conflicts).

Two execution options:
1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.
2. **Inline Execution** — execute tasks in this session with checkpoints.
