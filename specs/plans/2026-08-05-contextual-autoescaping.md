# Contextual Auto-Escaping for `~H` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `~H`'s single context-blind escaper with a table-driven contextual escaper that picks the correct encoding for PCDATA, attribute, URL, CSS and script contexts — resolved entirely at compile time, with compile-time diagnostics for interpolations that cannot be made safe.

**Architecture:** A declarative transition table (`specs/security/html-contexts.tbl`) is the single source of truth. A codegen step emits both an OCaml table (`lib/ctxesc/table_data.ml`) and a March table (`stdlib/ctx_table.march`) from it. The desugarer walks the static chunks of a `~H` sigil through the automaton at compile time and emits a *direct, monomorphic escaper call* per hole — no runtime automaton, no accumulator. This is sound because the paper establishes that an interpolation is a single transition whose successor context depends only on the predecessor context, never on the interpolated value, and because March's `~H` has no in-template control flow (no `if`/`for`), so there are no join points and no fixed point to compute.

**Tech Stack:** OCaml 5.3.0 / dune, March stdlib, C runtime (escapers), alcotest.

## Status (updated 2026-08-06)

| task | state |
|---|---|
| 0 — ADT misread (XSS + SIGSEGV) | **landed** — #192, `37d1e166` |
| 1–2 — table + automaton | **landed** — #194, `6cfdc005` |
| 3–5 — escapers, builtin, desugar fold | **landed** — #202, `a8707c78` |
| 6 — context-indexed `Html.Trusted` | open |
| 7 — codegen + drift guard | **mostly obsolete** — see the task |
| 8 — corpus validation | open — highest remaining value |
| 9 — `Html.tag` non-sigil path | open — **added 2026-08-06**, newly found |

`~H` escapes by parse context on `main`. Recommended order for what remains:
**8, then 9, then 6.** Task 8 converts two unverified assumptions into evidence
and should not wait behind design work.

## Source

Samuel, Palmer, Summa & Grayson, *Compile-time Security Analysis and Optimization of Sensitive String Producers* (Temper Systems), arXiv:2605.16561v1. Sections 4.6 (substitutions) and the transition-table figures are the normative reference for table semantics.

## Global Constraints

- OCaml switch is `march`. **Never** prefix commands with `eval $(opam env ...)`.
- Run tests with `scripts/run-tests.sh` (not bare `dune runtest` — stale RPC daemons block runs).
- Every feature commit must add a `CHANGELOG.md` bullet under `## [Unreleased]`. **This plan file is the `specs/` record for all of it** — no separate `specs/todos/` entry is filed, because Task 0's measured behaviour and root cause are recorded here rather than in a stub. On completion, add one `specs/progress/2026-08-05-contextual-autoescaping.md` summarising what shipped and link back to this file.
- After changing the desugarer or TIR shape, regenerate TIR snapshots deliberately: `UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e`, then review `git diff test/snapshots/` — that diff *is* the review artifact.
- After editing `runtime/*.c`, build a target that restages the runtime (`dune build --root .`); a targeted `dune build bin/main.exe` does **not** refresh `_build/default/runtime`, and the CAS cache key is computed over the *staged* runtime.
- **Non-breaking:** the existing `Html.Safe = Safe(String)` and `html_auto_escape` must keep working unchanged for the whole of this plan. New context-indexed types are added *alongside* and the old ones are marked deprecated in docstrings only.
- Use `forge search` before grepping when looking for March modules/functions/types.

---

## Scope

**In scope (this plan):** HTML plus the subsidiary automata HTML *requires* — URL (for `href`/`src`), CSS (for `<style>` and `style=`), and JS-string (for `<script>` and `on*=` handlers).

**Also in scope, and landing first:** Task 0, an existing XSS and memory-safety defect in `~H` that is unrelated to context-sensitivity but sits in the same code path. It ships on its own branch ahead of the rest.

**Out of scope (follow-up plan, outlined at the end):** the March-side runtime accumulator API (Layer A), generic accumulator-based desugaring for non-`~H` sigils, and standalone `~SQL` / `~SH` sigils.

**Deliberate simplification — no regex engine.** The paper's tables use regular expressions to consume fixed input. Implementing and cross-validating a regex engine in both OCaml and March is disproportionate here. This plan uses a fixed, closed pattern vocabulary sufficient for HTML (see Task 1). If a future content language needs true regex, that is a table-format version bump, not a rewrite.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/tir/llvm_emit.ml` | **Task 0.** Generalise the `Html.Safe` type-directed dispatch to all types (existing file, lines 1559-1575) |
| `runtime/march_extras.c` | **Task 0.** Turn the unreachable `tag >= 0 → IOList` fallback into an abort (existing file, lines 2437-2443) |
| `specs/security/README.md` | Table format spec — the document a security engineer reads |
| `specs/security/html-contexts.tbl` | **Source of truth.** Declarative transition table |
| `lib/ctxesc/dune` | New OCaml library `march_ctxesc` |
| `lib/ctxesc/context.ml` | The 4-tuple context type + escaper-id enum |
| `lib/ctxesc/tbl_parse.ml` | Parser for the `.tbl` format (no new deps) |
| `lib/ctxesc/table_data.ml` | **Generated.** The table as OCaml data |
| `lib/ctxesc/automaton.ml` | `consume_literal`, `consume_interp`, `is_valid_terminal` |
| `lib/ctxesc/emit_tables.ml` | Emitter executable → `table_data.ml` + `stdlib/ctx_table.march` |
| `lib/desugar/desugar.ml` | Modify `html_interp_to_iolist` to fold contexts (existing file, ~line 456) |
| `runtime/march_ctx_escape.c` | The escaper implementations |
| `stdlib/html.march` | Add `Ctx` type + context-indexed `Safe`; deprecate old |
| `test/test_ctxesc.ml` | Automaton unit tests |
| `test/stdlib/test_html_ctx.march` | End-to-end escaping behaviour |

---

## Task 0: Fix the ADT-flattening hole — live XSS + SIGSEGV

> **Land this on its own branch, before Tasks 1–8.** It is independent of the contextual-escaping
> work and fixes two defects that exist in the shipped compiler today. It is also the reason this
> plan does not need a separate `specs/todos/` entry: the measured behaviour, the root cause, and
> the fix are recorded here.

**Files:**
- Modify: `lib/tir/llvm_emit.ml:1559-1575` (generalise the existing `Safe` special case)
- Modify: `runtime/march_extras.c:2437-2443` (turn the unreachable fallback into an abort)
- Test: `test/test_codegen.ml`, plus an interpreter/compiled parity test

### Measured behaviour (2026-08-05, `_build/default/bin/main.exe`)

`march_html_auto_escape` ends with *"Constructor with tag >= 0: treat as IOList and flatten
verbatim"* and delegates to `mh_iolist_size`/`mh_iolist_copy`
(`runtime/march_extras.c:2369-2407`), which branch on `tag == 1` → read field 0 as
`march_string*`, and `tag == 2` → walk field 0 as a cons list. Constructor tags are numbered
**per type** starting at 0, so any ADT collides with `IOList = Empty | Str(String) |
Segments(List(IOList))`. Compiled results, all of which are correct when interpreted:

| Interpolated into `~H"<p>${x}</p>"` | Compiled result |
|---|---|
| `Point(1, 2)` — tag 0, two fields | `<p></p>` — silently empty |
| `B("<script>")` — tag 1, String field | `<p><script></p>` — **raw, unescaped: XSS** |
| `C("xx", "yy")` — tag 2 | **SIGSEGV** (exit 139) |
| `M2(7, 9)` — tag 2, Int fields | **SIGSEGV** |

**CORRECTED 2026-08-05 by measurement.** This plan originally claimed `Option`/`Result` were
niche-optimised and therefore safe. That holds only for `Some(x)`. `None`, `Ok` and `Err` are
ordinary boxed constructors and collided exactly like any user ADT — `Err("<b>")` rendered
`<p><b></p>`, raw and unescaped. Since `Result` is pervasive, that was the widest instance of
the bug, not an exempt case.

### The spike is already answered — do not re-run it

`llvm_emit.ml:1543-1558` states the root cause outright: *"every Boxed ADT's constructor tags
are numbered independently starting at 0, so the runtime has no way to tell a bare tag-0 heap
cell apart from the other."* The runtime **cannot** decide this. `Html.Safe` was already
patched at `llvm_emit.ml:1559-1569` by dispatching on the argument's static TIR type. The fix
is to generalise that existing special case to cover every type, not to add a runtime check.

Note also that the existing `Safe` patch has an escape hatch: when `"Safe"` collides with
another module's short type name it deliberately falls through to the generic runtime path —
which is the broken one. Under the generalised dispatch, the unknown/ambiguous case must route
to `to_string` + escape, so a collision degrades to "renders the ADT" instead of "silently
empty".

- [ ] **Step 1: Write the failing tests**

In `test/test_codegen.ml`:

```ocaml
("~H renders a multi-field ADT instead of dropping it", `Quick, fun () ->
  let out = compile_and_run {|
    type Point = Point(Int, Int)
    fn main() do
      let p = Point(1, 2)
      IO.puts(IOList.to_string(~H"<p>${p}</p>"))
    end
  |} in
  check_contains out "Point(1, 2)");

("~H escapes a tag-1 ADT string field instead of emitting it raw", `Quick, fun () ->
  let out = compile_and_run {|
    type Multi = A | B(String)
    fn main() do
      let b = B("<script>")
      IO.puts(IOList.to_string(~H"<p>${b}</p>"))
    end
  |} in
  check_not_contains out "<script>";
  check_contains out "&lt;script&gt;");

("~H does not crash on a tag-2 ADT", `Quick, fun () ->
  let out = compile_and_run {|
    type Multi = A | B(String) | C(String, String)
    fn main() do
      let c = C("xx", "yy")
      IO.puts(IOList.to_string(~H"<p>${c}</p>"))
    end
  |} in
  check_contains out "xx");
```

And a parity test in the interpreter/compiled parity group (these are `Slow`-marked in
`run_stdlib`) asserting the three programs above produce byte-identical output interpreted and
compiled. The parity framing matters: the interpreter was correct the whole time, so parity is
the property that would have caught this.

- [ ] **Step 2: Run to verify they fail**

```bash
scripts/run-tests.sh codegen
```
Expected: test 1 FAILs with empty output, test 2 FAILs with raw `<script>`, test 3 **crashes the
test runner with SIGSEGV**. If the runner aborts rather than reporting, run the third case
standalone via `--compile` to confirm the signal before proceeding.

- [ ] **Step 3: Generalise the emitter dispatch**

Replace the two `html_auto_escape` cases at `llvm_emit.ml:1559-1575` with a single
type-directed dispatch on `atom_tir_ty a`:

- `TCon ("Safe", _)`, non-colliding → load field 0, emit verbatim (existing behaviour, keep)
- `TCon ("IOList", _)` → call `march_html_auto_escape` (its IOList path is correct *when the
  value really is an IOList*)
- `TCon ("String", _)` → call the string escaper directly
- immediates (`Int`, `Float`, `Bool`, `Char`) → existing tagged-ptr coercion path
- **everything else, including the `Safe`-collision case** → emit `march_to_string(v)` then
  escape the resulting string. This is the missing arm that currently misreads as an IOList.

Keep the scalar re-tagging comment at `llvm_emit.ml:1531-1542` intact — that hazard is
unrelated and still live.

- [ ] **Step 4: Turn the runtime fallback into an abort**

In `runtime/march_extras.c:2437-2443`, replace *"Constructor with tag >= 0: treat as IOList and
flatten verbatim"* with a hard abort carrying the observed tag. After Step 3 this arm is
unreachable from `~H`; making it loud means a future caller that reintroduces the polymorphic
path fails immediately instead of silently emitting unescaped bytes. Defense in depth — the
emitter is the real fix.

- [ ] **Step 5: Rebuild with the runtime restaged, then verify**

The runtime changed, so a targeted `dune build bin/main.exe` is **not** sufficient:

```bash
dune build --root .
scripts/run-tests.sh
```
Expected: PASS, including the parity tests. Confirm no SIGSEGV in the runner output.

- [ ] **Step 6: Reproduce and cover the `Safe`-collision fallback**

The existing patch at `llvm_emit.ml:1559-1563` deliberately declines to fire when `"Safe"` is a
same-short-name collision with another module's type, falling through to the generic path — the
broken one. So `Html.raw` in any program that also defines its own `Safe` type should render
empty today.

This was read from the code, **not** measured — it needs two modules to trigger, and the probe
runs in this task were single-module. Build the two-module case, confirm the behaviour, and pin
it:

```march
mod Other do
  type Safe = Safe(Int)
end

mod CollisionProbe do
  fn main() do
    let s = Html.raw("<b>x</b>")
    IO.puts(IOList.to_string(~H"<p>${s}</p>"))
  end
end
```

Expected before the fix: `<p></p>`. Expected after: `<p><b>x</b></p>`, because the generalised
dispatch routes the ambiguous case to `march_to_string` + escape rather than to the IOList
misread — degraded (the wrapper is no longer verbatim) but safe and non-empty.

If the collision case turns out **not** to reproduce, say so in the commit message and delete
this step's test rather than leaving an assertion that passes for the wrong reason.

- [ ] **Step 7: Sweep forgepm for exposed interpolations**

The exposure is any boxed constructor reaching a `~H` hole: user-defined ADTs with two or more
constructors, **and** `None` / `Ok` / `Err` (only `Some(x)` is niche-optimised away). Check both. forgepm has 153 `~H` sites. Find the
ones at risk:

```bash
forge search --callers to_string
```

then check each `~H` interpolation in `lib/forgepm/web/pages.march`,
`lib/forgepm/web/search_island.march`, `lib/forgepm/forgepm_router.march`,
`lib/forgepm/web/web_router.march` and `lib/forgepm/orgs/org.march` for a hole whose expression
has a user-defined multi-constructor ADT type.

Any hit is a live XSS or crash in production and must be recorded in `specs/progress/` with the
file and line. A clean sweep is also a result worth recording — it bounds the incident.

**This is not Task 8.** Task 8 validates the new *contextual* analysis against the whole corpus;
this step answers the narrower and more urgent question of whether the tag-collision bug is
currently reachable in deployed code.

- [ ] **Step 8: Commit**

```bash
git add lib/tir/llvm_emit.ml runtime/march_extras.c test/test_codegen.ml test/stdlib
git commit -m "fix(codegen): ~H misread non-IOList ADTs as IOList (XSS + SIGSEGV)

Constructor tags are per-type, so any user ADT collided with IOList's
Empty|Str|Segments tags. tag-1 ADTs with a String field were emitted raw
and unescaped; tag-2 ADTs crashed walking field 0 as a cons list; tag-0
multi-field ADTs rendered empty. Interpreted output was correct throughout.

Generalises the existing Html.Safe type-directed dispatch in llvm_emit to
cover all types, and makes the now-unreachable runtime fallback abort."
```

---

## Carried over from Task 0 (merged as #192, `37d1e166`)

Task 0 was not just a bug fix — it established a rule the rest of this plan must respect:

1. **No runtime dispatch on a heap tag, ever.** Constructor tags are per-type, so the runtime
   cannot identify a value's type from its cell. Every escaper decision is made in `llvm_emit`
   from the static TIR type, and C escapers receive an already-normalised String.
2. **`TVar` is undecidable and must fail safe.** A value reaching a `~H` hole through a closure
   stored in a container is not specialised by mono. Neither flattening nor stringifying is
   correct for it; stringifying is merely not a vulnerability. Any new escaper path must make
   the same choice, and Task 6's `Trusted` must be handled explicitly in the emitter rather
   than left to a runtime check.
3. **Compiled ADT rendering is `#<tag:N>`.** Two follow-ups are filed and unfixed:
   `specs/todos/2026-08-05-compiled-to-string-adt-ctor-names.md` and
   `specs/todos/2026-08-05-boxed-adt-type-id.md`. The second is the one that would let a
   polymorphic hole become *correct* rather than merely safe; if it lands first, revisit
   rule 2.

---

## Task 1: Table format + parser

**Files:**
- Create: `specs/security/README.md`, `specs/security/html-contexts.tbl`
- Create: `lib/ctxesc/dune`, `lib/ctxesc/context.ml`, `lib/ctxesc/tbl_parse.ml`
- Test: `test/test_ctxesc.ml` (new), registered in `test/dune`

**Interfaces:**
- Produces:
  ```ocaml
  (* context.ml *)
  type state = Pcdata | RcData | TagOpen | TagName | BeforeAttrName | AttrName
             | AfterAttrName | BeforeAttrValue | AttrValue | AfterAttrValue
             | Comment | Doctype
  type element = ElNormal | ElScript | ElStyle | ElTextarea | ElTitle
  type attr    = AtNormal | AtUrl | AtStyle | AtScript
  type delim   = DlNone | DlSingle | DlDouble | DlUnquoted | DlDoubleSubst
  type t = { state : state; element : element; attr : attr; delim : delim }
  val initial : t
  type escaper = EscHtml | EscAttr | EscUrlComponent | EscUrlWhole
               | EscCss | EscJsString | EscNone | EscReject of string
  val escaper_id : escaper -> int   (* stable ids shared with the C runtime *)

  (* tbl_parse.ml *)
  type pattern = PLit of string | PClass of char list | PClassPlus of char list
               | PInterp | PUntil of string
  type row = { from_pat : Context.t option_pat; pat : pattern;
               subst : string option; succ : Context.t option_pat;
               diag : string option }
  val parse_file : string -> (row list, string) result
  ```

`DlDoubleSubst` is the paper's substitution mechanism: an unquoted attribute value that we forcibly quoted. It is a distinct delimiter so the automaton knows to emit the closing `"` on exit.

- [ ] **Step 1: Write the format spec**

Create `specs/security/README.md` documenting the `.tbl` grammar. One row per line, `|`-separated, `#` starts a comment:

```
# from-context | pattern | substitution | successor-context | diagnostic
# Context is state,element,attr,delim — `*` means "any", and `=` in the
# successor means "unchanged from the source context".
pcdata,*,*,*        | lit:"<"       |     | tagopen,=,=,=      |
pcdata,*,*,*        | interp        |     | =,=,=,=            |
beforeattrvalue,*,*,unquoted | interp | "\"" | attrvalue,=,=,doublesubst |
attrname,*,*,*      | interp        |     | =,=,=,=            | Cannot interpolate an attribute name
```

- [ ] **Step 2: Write the failing parser test**

In `test/test_ctxesc.ml`:

```ocaml
let test_parse_minimal () =
  let tmp = Filename.temp_file "tbl" ".tbl" in
  let oc = open_out tmp in
  output_string oc "# comment\npcdata,*,*,* | lit:\"<\" |  | tagopen,=,=,= |\n";
  close_out oc;
  match March_ctxesc.Tbl_parse.parse_file tmp with
  | Error e -> Alcotest.failf "parse failed: %s" e
  | Ok rows ->
    Alcotest.(check int) "one row" 1 (List.length rows);
    let r = List.hd rows in
    Alcotest.(check bool) "literal pattern" true
      (r.March_ctxesc.Tbl_parse.pat = March_ctxesc.Tbl_parse.PLit "<")

let test_parse_rejects_unknown_state () =
  let tmp = Filename.temp_file "tbl" ".tbl" in
  let oc = open_out tmp in
  output_string oc "notastate,*,*,* | lit:\"<\" |  | pcdata,=,=,= |\n";
  close_out oc;
  match March_ctxesc.Tbl_parse.parse_file tmp with
  | Ok _ -> Alcotest.fail "should have rejected unknown state"
  | Error e ->
    Alcotest.(check bool) "names the bad state" true
      (Astring.String.is_infix ~affix:"notastate" e)
```

- [ ] **Step 3: Run to verify it fails**

```bash
scripts/run-tests.sh ctxesc
```
Expected: FAIL — library `march_ctxesc` does not exist.

- [ ] **Step 4: Implement `context.ml`, `tbl_parse.ml`, `lib/ctxesc/dune`**

`lib/ctxesc/dune`:
```
(library
 (name march_ctxesc)
 (modules context tbl_parse table_data automaton))
```

Implement the types in the Interfaces block above. `parse_file` splits on `|`, trims, parses each context field against a fixed name table, and returns `Error` with the offending line number and token for anything unrecognised. **Unknown names must be a hard error, never a silent skip** — a typo'd state name in a security table that silently drops a row is the worst possible failure mode.

- [ ] **Step 5: Run tests to verify they pass**

```bash
scripts/run-tests.sh ctxesc
```
Expected: PASS.

- [ ] **Step 6: Write the real HTML table**

Populate `specs/security/html-contexts.tbl` with the full HTML automaton: PCDATA, tag open/name, attribute name/value in all four delimiter modes, comments, and the `script`/`style`/`textarea`/`title` RCDATA and raw-text elements. Attribute classification (`AtUrl` for `href`/`src`/`action`/`formaction`/`poster`, `AtStyle` for `style`, `AtScript` for `on*`) is assigned on the `attrname → afterattrname` transition.

Rows that must carry a diagnostic (interpolation is unsafe at any encoding):
- `tagname` — cannot interpolate an element name
- `attrname` — cannot interpolate an attribute name
- `comment` — cannot interpolate inside a comment
- `beforeattrname` — cannot interpolate where an attribute name is expected

- [ ] **Step 7: Commit**

```bash
git add specs/security lib/ctxesc test/test_ctxesc.ml test/dune
git commit -m "feat(ctxesc): declarative HTML context transition table + parser"
```

---

## Task 2: The automaton

**Files:**
- Create: `lib/ctxesc/automaton.ml`
- Modify: `test/test_ctxesc.ml`

**Interfaces:**
- Consumes: `Context.t`, `Tbl_parse.row` from Task 1.
- Produces:
  ```ocaml
  type step_out = {
    emit : string;          (* the literal text to emit, incl. substitutions *)
    ctx  : Context.t;
  }
  val consume_literal : Context.t -> string -> (step_out, string * int) result
  (* Error (message, byte_offset_into_literal) *)

  val consume_interp : Context.t -> (Context.escaper * string * Context.t, string) result
  (* Ok (escaper, substitution_prefix, successor_context) | Error diagnostic *)

  val is_valid_terminal : Context.t -> bool
  val describe : Context.t -> string   (* for diagnostics: "inside an unquoted attribute value" *)
  ```

- [ ] **Step 1: Write the failing tests**

Append to `test/test_ctxesc.ml`:

```ocaml
let ctx_after s =
  match Automaton.consume_literal Context.initial s with
  | Ok o -> o.ctx
  | Error (m, _) -> Alcotest.failf "unexpected error: %s" m

let test_pcdata_stays_pcdata () =
  Alcotest.(check bool) "plain text" true
    ((ctx_after "hello world").state = Context.Pcdata)

let test_enters_double_quoted_attr () =
  let c = ctx_after "<a href=\"" in
  Alcotest.(check bool) "in attr value" true (c.state = Context.AttrValue);
  Alcotest.(check bool) "double delim"  true (c.delim = Context.DlDouble);
  Alcotest.(check bool) "url attr"      true (c.attr  = Context.AtUrl)

let test_script_body_is_js () =
  let c = ctx_after "<script>" in
  Alcotest.(check bool) "script element" true (c.element = Context.ElScript)

let test_interp_in_url_attr_picks_url_escaper () =
  let c = ctx_after "<a href=\"" in
  match Automaton.consume_interp c with
  | Ok (esc, _, _) ->
    Alcotest.(check bool) "url escaper" true (esc = Context.EscUrlWhole)
  | Error e -> Alcotest.failf "unexpected reject: %s" e

let test_interp_in_attr_name_is_rejected () =
  let c = ctx_after "<div " in
  match Automaton.consume_interp c with
  | Ok _ -> Alcotest.fail "attribute-name interpolation must be rejected"
  | Error _ -> ()

let test_unquoted_attr_gets_substituted_quote () =
  let c = ctx_after "<div class=" in
  match Automaton.consume_interp c with
  | Ok (_, subst, c') ->
    Alcotest.(check string) "opening quote substituted" "\"" subst;
    Alcotest.(check bool) "delim marked substituted" true
      (c'.delim = Context.DlDoubleSubst)
  | Error e -> Alcotest.failf "unexpected reject: %s" e

let test_unterminated_tag_is_invalid_terminal () =
  Alcotest.(check bool) "open tag is not a valid end state" false
    (Automaton.is_valid_terminal (ctx_after "<div"))
```

- [ ] **Step 2: Run to verify they fail**

```bash
scripts/run-tests.sh ctxesc
```
Expected: FAIL — `Automaton` unbound.

- [ ] **Step 3: Implement `automaton.ml`**

`consume_literal` walks the string byte by byte, at each position selecting the first table row whose `from_pat` matches the current context and whose `pattern` matches at that position (longest literal first). It accumulates `emit`, applying any `subst`. On no matching row, return `Error` with the byte offset.

`consume_interp` selects the row whose pattern is `PInterp`; if that row carries a `diag`, return `Error diag`. Otherwise return the escaper implied by the successor context, the substitution prefix, and the successor.

When a `DlDoubleSubst` attribute value is exited, `consume_literal` must emit a closing `"` before the whitespace or `>` that ends it.

- [ ] **Step 4: Run tests to verify they pass**

```bash
scripts/run-tests.sh ctxesc
```
Expected: PASS, all seven.

- [ ] **Step 5: Commit**

```bash
git add lib/ctxesc/automaton.ml test/test_ctxesc.ml
git commit -m "feat(ctxesc): HTML context automaton with substitutions"
```

---

## Task 3: Escaper implementations in the C runtime

**Files:**
- Create: `runtime/march_ctx_escape.c`, `runtime/march_ctx_escape.h`
- Test: `test/test_ctx_escape.c` + a `test/dune` rule modelled on the "HCR capability-lattice C table unit test" at `test/dune:176-191`

**Interfaces:**
- Produces:
  ```c
  /* escaper ids must match Context.escaper_id in lib/ctxesc/context.ml */
  #define MARCH_ESC_HTML          0
  #define MARCH_ESC_ATTR          1
  #define MARCH_ESC_URL_COMPONENT 2
  #define MARCH_ESC_URL_WHOLE     3
  #define MARCH_ESC_CSS           4
  #define MARCH_ESC_JS_STRING     5
  #define MARCH_ESC_NONE          6
  void *march_html_escape_ctx(int64_t escaper_id, void *v);
  ```

Semantics per escaper:
- `HTML` — `& < > " '` to entities (matches today's behaviour).
- `ATTR` — as HTML, plus backtick, for IE attribute-delimiter quirks.
- `URL_COMPONENT` — percent-encode everything outside RFC 3986 unreserved.
- `URL_WHOLE` — scheme allowlist. `http`, `https`, `mailto`, and scheme-relative or path-relative URLs pass through percent-normalised; **everything else, notably `javascript:` and `data:`, is replaced with `about:invalid#zSoyz`.** This is the fix for the live `href` hole.
- `CSS` — allow only `[a-zA-Z0-9_.#%-]` and safe string content; replace anything else with `\` + hex escape.
- `JS_STRING` — JSON-string escaping plus `</`, `<!--`, U+2028, U+2029.

- [ ] **Step 1: Write the failing C test**

`test/test_ctx_escape.c` — a plain C main asserting on each escaper. The critical cases:

```c
assert_esc(MARCH_ESC_URL_WHOLE, "javascript:alert(1)", "about:invalid#zSoyz");
assert_esc(MARCH_ESC_URL_WHOLE, "JaVaScRiPt:alert(1)", "about:invalid#zSoyz");
assert_esc(MARCH_ESC_URL_WHOLE, "  javascript:alert(1)", "about:invalid#zSoyz");
assert_esc(MARCH_ESC_URL_WHOLE, "java\tscript:alert(1)", "about:invalid#zSoyz");
assert_esc(MARCH_ESC_URL_WHOLE, "https://example.com/a?b=c", "https://example.com/a?b=c");
assert_esc(MARCH_ESC_URL_WHOLE, "/relative/path", "/relative/path");
assert_esc(MARCH_ESC_JS_STRING, "</script>", "\\u003c/script\\u003e");
assert_esc(MARCH_ESC_ATTR, "a\" onload=\"x", "a&quot; onload=&quot;x");
assert_esc(MARCH_ESC_CSS, "expression(alert(1))", /* neutralised */ ...);
```

The scheme check must be done **after** stripping leading whitespace and control characters, and case-insensitively — that is what the three `javascript:` variants above pin.

- [ ] **Step 2: Add the dune rule and run to verify failure**

Add to `test/dune`, mirroring lines 176–191:

```
; ── contextual escaper unit test ──────────────────────────────────────────
(rule
 (targets test_ctx_escape_runner)
 (deps    test_ctx_escape.c
          ../runtime/march_ctx_escape.c
          ../runtime/march_ctx_escape.h)
 (action  (run %{cc}
               -std=gnu11 -Wall -Wextra -I../runtime
               -o %{targets}
               test_ctx_escape.c ../runtime/march_ctx_escape.c)))

(rule
 (alias   runtest)
 (deps    (file test_ctx_escape_runner))
 (action  (run ./test_ctx_escape_runner)))
```

```bash
dune build --root . 2>&1 | head -20
```
Expected: FAIL — `march_ctx_escape.c` does not exist.

- [ ] **Step 3: Implement the escapers**

Write `runtime/march_ctx_escape.c`. For the value→string normalisation, reuse the existing immediate/string/IOList handling from `march_html_auto_escape` (`runtime/march_extras.c:2409`) — but **do not copy its `tag >= 0 → treat as IOList` fallback**. That fallback is the XSS-and-SIGSEGV bug measured in Task 0; propagating it into a second escaper would double the blast radius. `march_html_escape_ctx` must never dispatch polymorphically on a heap tag: the caller (Task 5's desugar fold, via Task 0's type-directed emitter dispatch) is responsible for handing it a String, and anything else is a hard abort.

**Task 0 lands before this task**, so the correct dispatch already exists to copy.

- [ ] **Step 4: Run to verify it passes**

```bash
dune build --root . && ./_build/default/test/test_ctx_escape_runner
```
Expected: exit 0, no assertion failures.

- [ ] **Step 5: Commit**

```bash
git add runtime/march_ctx_escape.c runtime/march_ctx_escape.h test/test_ctx_escape.c test/dune
git commit -m "feat(runtime): contextual escapers incl. URL scheme allowlist"
```

---

## Task 4: Wire `html_escape_ctx` into typecheck, TIR and eval

**Files:**
- Modify: `lib/typecheck/typecheck.ml:2587` (builtin type table)
- Modify: `lib/tir/llvm_builtins.ml:106-107`, `lib/tir/llvm_emit.ml:1559-1574`, `lib/tir/defun.ml:140`
- Modify: `lib/eval/eval.ml:4259` (interpreter builtin)
- Test: `test/test_codegen.ml`, `test/test_eval.ml`

**Interfaces:**
- Consumes: `march_html_escape_ctx` from Task 3.
- Produces: a March-visible builtin `html_escape_ctx : Int -> a -> String`, callable from desugared code.

> **Constraint carried over from Task 0 — do not weaken it.** The March-level type stays
> polymorphic (`a`) so the desugarer can emit the call without knowing the hole's type, but
> `march_html_escape_ctx` **must never dispatch on a heap tag**. Constructor tags are numbered
> per type, so a heap-tag dispatch cannot distinguish `IOList.Str` from any other tag-1
> constructor — that was the XSS and the SIGSEGV fixed in
> `specs/progress/2026-08-05-h-sigil-adt-misread.md`. `llvm_emit` must reuse the same
> type-directed dispatch Task 0 installed for `html_auto_escape`: stringify anything that is
> not a String, an immediate, or a statically-known real `IOList` — **including `TVar`**, the
> undecidable case — and hand the C function a real String. Anything else in the C function is
> a hard abort, not a guess.

This task mirrors, line for line, the existing wiring of `html_auto_escape` — read all five call sites listed above first; each needs an analogous entry for the two-argument form. Note `llvm_emit.ml:1531-1548` documents a real hazard: the emitter special-cases the call because a scalar `i64` argument must be re-tagged before being passed as a generic `ptr`. The two-argument version has the same hazard on its *second* argument; the first (the escaper id) is a genuine `i64`.

- [ ] **Step 1: Write the failing eval test**

In `test/test_eval.ml`, alongside the existing `html_auto_escape` coverage:

```ocaml
let test_html_escape_ctx_url () =
  check_eval_string
    {| html_escape_ctx(3, "javascript:alert(1)") |}
    "about:invalid#zSoyz"

let test_html_escape_ctx_attr () =
  check_eval_string
    {| html_escape_ctx(1, "a\" onload=\"x") |}
    "a&quot; onload=&quot;x"
```

- [ ] **Step 2: Run to verify failure**

```bash
scripts/run-tests.sh -q eval
```
Expected: FAIL — unbound `html_escape_ctx`.

- [ ] **Step 3: Add the builtin to all five sites**

Typecheck (`typecheck.ml`, next to the `html_auto_escape` entry):
```ocaml
("html_escape_ctx", poly1 (fun a -> TArrow (t_int, TArrow (a, t_string))));
```
Then `llvm_builtins.ml` declaration, `llvm_emit.ml` emission (including the scalar re-tag path for arg 2), `defun.ml` known-name list, and the `eval.ml` `VBuiltin` case.

- [ ] **Step 4: Run to verify it passes**

```bash
scripts/run-tests.sh -q eval codegen
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/typecheck lib/tir lib/eval test/test_eval.ml test/test_codegen.ml
git commit -m "feat: html_escape_ctx builtin wired through typecheck/TIR/eval"
```

---

## Task 5: Compile-time context folding in the desugarer

**Files:**
- Modify: `lib/desugar/desugar.ml:456-500` (`html_interp_to_iolist`)
- Modify: `lib/desugar/dune` (add `march_ctxesc` to libraries)
- Test: `test/test_codegen.ml` ("~H sigil codegen" group, `test/test_codegen.ml:13385`), `test/stdlib/test_html_ctx.march`

**Interfaces:**
- Consumes: `Automaton.consume_literal`, `Automaton.consume_interp`, `Context.escaper_id` (Tasks 1–2); `html_escape_ctx` (Task 4); `desugar_expr_error` (`desugar.ml:520`).
- Produces: `~H` desugars to `IOList.from_strings([...])` where each hole is `html_escape_ctx(<id>, e)` rather than `html_auto_escape(e)`.

This replaces the "Third pass" at `desugar.ml:465-481`. The island and CSRF passes run first and are unchanged; both inject markup that is only valid in PCDATA, so the fold must assert the context is `Pcdata` at those points and emit a diagnostic otherwise.

- [ ] **Step 1: Write the failing codegen tests**

In `test/test_codegen.ml`, in the `"~H sigil codegen"` group:

```ocaml
("~H picks URL escaper inside href", `Quick, fun () ->
  let out = compile_and_run {|
    let url = "javascript:alert(1)"
    IO.println(IOList.to_string(~H"<a href=\"${url}\">x</a>"))
  |} in
  check_contains out "about:invalid#zSoyz";
  check_not_contains out "javascript:");

("~H quotes an unquoted attribute", `Quick, fun () ->
  let out = compile_and_run {|
    let cls = "a b onmouseover=alert(1)"
    IO.println(IOList.to_string(~H"<div class=${cls}>x</div>"))
  |} in
  check_contains out "class=\"a b onmouseover=alert(1)\"");

("~H uses JS escaping inside script", `Quick, fun () ->
  let out = compile_and_run {|
    let payload = "</script><script>alert(1)"
    IO.println(IOList.to_string(~H"<script>var x = \"${payload}\";</script>"))
  |} in
  check_not_contains out "</script><script>");

("~H still escapes PCDATA as before", `Quick, fun () ->
  let out = compile_and_run {|
    let s = "<b>&"
    IO.println(IOList.to_string(~H"<p>${s}</p>"))
  |} in
  check_contains out "<p>&lt;b&gt;&amp;</p>");
```

- [ ] **Step 2: Run to verify they fail**

```bash
scripts/run-tests.sh codegen
```
Expected: FAIL — the URL test prints `javascript:alert(1)` (this is the current live vulnerability, now pinned by a test).

- [ ] **Step 3: Implement the fold**

Replace the third pass in `html_interp_to_iolist`:

```ocaml
let ctx = ref March_ctxesc.Context.initial in
let parts = List.concat_map (fun part ->
  match part with
  | ELit (LitString s, sp) ->
    (match March_ctxesc.Automaton.consume_literal !ctx s with
     | Ok o -> ctx := o.ctx; [ELit (LitString o.emit, sp)]
     | Error (msg, _off) ->
       desugar_expr_error ~sp msg; [part])
  | EApp (EVar { txt = "to_string"; _ }, [inner], psp) ->
    (match March_ctxesc.Automaton.consume_interp !ctx with
     | Ok (esc, subst, ctx') ->
       ctx := ctx';
       let id = March_ctxesc.Context.escaper_id esc in
       let call =
         EApp (EVar { txt = "html_escape_ctx"; span = psp },
               [ELit (LitInt id, psp); inner], psp) in
       if subst = "" then [call]
       else [ELit (LitString subst, psp); call]
     | Error diag ->
       desugar_expr_error ~sp:psp diag
         ~hint:(Printf.sprintf "This interpolation is %s, where no escaping can make \
                                untrusted input safe. Move the dynamic part into a \
                                value position instead."
                  (March_ctxesc.Automaton.describe !ctx));
       [part])
  | other ->
    (* island_ssr / CSRF injections: valid only in PCDATA *)
    if !ctx.March_ctxesc.Context.state <> March_ctxesc.Context.Pcdata then
      desugar_expr_error ~sp
        "Template fragments can only be inserted in element content, not inside a tag.";
    [other]
) parts in
if not (March_ctxesc.Automaton.is_valid_terminal !ctx) then
  desugar_expr_error ~sp
    "This ~H template does not end in a well-formed state — a tag or attribute is left open."
```

Preserve the existing unique-span discipline documented at `desugar.ml:483-495` verbatim; the substitution segments are *new* nodes and each needs its own distinct span or the type map will be clobbered.

- [ ] **Step 4: Run to verify they pass**

```bash
scripts/run-tests.sh codegen
```
Expected: PASS, all four.

- [ ] **Step 5: Regenerate TIR snapshots and review the diff**

```bash
UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e
git diff test/snapshots/
```
Expected: `html_auto_escape` calls become `html_escape_ctx` calls with an explicit id. Read every changed line — an id that looks wrong for its context is a security bug, and this diff is where it is visible.

- [ ] **Step 6: Run the full suite**

```bash
scripts/run-tests.sh
```
Expected: PASS. `test/stdlib/test_sigil.march` must still pass unchanged — its PCDATA assertions pin the no-regression property.

- [ ] **Step 7: Commit**

```bash
git add lib/desugar test/test_codegen.ml test/snapshots
git commit -m "feat(desugar): compile-time contextual escaping for ~H sigils"
```

---

## Task 6: Context-indexed `Safe`, added alongside the old one

**Files:**
- Modify: `stdlib/html.march:14` (add, do not change, `Safe`)
- Test: `test/stdlib/test_html_ctx.march`

**Interfaces:**
- Produces:
  ```march
  type Ctx = CtxPcdata | CtxAttr | CtxUrl | CtxCss | CtxJs
  type Trusted = Trusted(Ctx, String)

  fn trust(ctx : Ctx, s : String) : Trusted
  fn untrust(t : Trusted) : String
  fn trusted_ctx(t : Trusted) : Ctx
  ```

`Html.Safe`/`Html.raw` keep their exact current behaviour and signatures. Their docstrings gain a deprecation note pointing at `Trusted`, explaining that `Safe` is context-free and therefore trusted everywhere once trusted anywhere. **Do not remove them** — `bastion` is published at 0.2.3 and external consumers may depend on them.

- [ ] **Step 1: Write the failing March test**

`test/stdlib/test_html_ctx.march`:

```march
mod TestHtmlCtx do

describe "context-indexed trust" do
  test "trusted markup is inserted verbatim in its own context" do
    let t = Html.trust(Html.CtxPcdata, "<b>bold</b>")
    let out = ~H"<p>${t}</p>"
    assert (IOList.to_string(out) == "<p><b>bold</b></p>")
  end

  test "trusted PCDATA is NOT trusted in an href" do
    let t = Html.trust(Html.CtxPcdata, "javascript:alert(1)")
    let out = ~H"<a href=\"${t}\">x</a>"
    assert (String.contains(IOList.to_string(out), "about:invalid"))
  end

  test "legacy Html.raw still works" do
    let s = Html.raw("<i>x</i>")
    assert (Html.unwrap(s) == "<i>x</i>")
  end
end

end
```

The second test is the whole point of the change: trust must not be transitive across contexts.

- [ ] **Step 2: Run to verify it fails**

```bash
scripts/run-tests.sh -q stdlib
```
Expected: FAIL — `Html.trust` undefined.

- [ ] **Step 3: Implement `Trusted` in `stdlib/html.march`, and teach `march_html_escape_ctx` about it**

An escaper receiving a `Trusted(ctx, s)` emits `s` verbatim **only** when `ctx` matches the escaper's own context; otherwise it escapes `s` as untrusted.

- [ ] **Step 4: Run to verify it passes**

```bash
scripts/run-tests.sh -q stdlib
```

- [ ] **Step 5: Commit**

```bash
git add stdlib/html.march test/stdlib/test_html_ctx.march
git commit -m "feat(stdlib): context-indexed Html.Trusted alongside legacy Safe"
```

---

## Task 7: Codegen wiring, drift guard, and docs — MOSTLY OBSOLETE

> **Revised 2026-08-06.** The OCaml half landed inside Task 5 out of necessity —
> the desugarer needs the table at compile time and an installed `march` has no
> `specs/` directory. `lib/ctxesc/dune` `cat`s the `.tbl` into a generated
> module, which makes drift **structurally impossible**: dune regenerates from
> the source of truth on every build, so there is nothing for a freshness check
> to catch. That is strictly better than the emitter-plus-diff design below.
>
> What remains is only `stdlib/ctx_table.march` — the March-side copy — and it
> has no consumer unless the runtime accumulator is built. See the revised
> follow-up section: the recommendation is now to **drop it** rather than defer
> it. Do not build this task speculatively.
>
> The steps below are kept for the record and for the case where a March-side
> consumer does appear.

**Files:**
- Create: `lib/ctxesc/emit_tables.ml`
- Modify: `lib/ctxesc/dune`, `test/dune`, `CHANGELOG.md`

Up to this point `table_data.ml` may be hand-written. This task makes the `.tbl` file the real source of truth and adds the anti-drift check, modelled on `lib/caps/emit_c_table.ml` + the freshness rule at `test/dune:176`.

- [ ] **Step 1: Write the emitter**

`lib/ctxesc/emit_tables.ml` — reads `specs/security/html-contexts.tbl`, writes `lib/ctxesc/table_data.ml` and `stdlib/ctx_table.march`. Header comment on both generated files: *"GENERATED — do not edit. Regenerate with `./_build/default/lib/ctxesc/emit_tables.exe`."*

- [ ] **Step 2: Add the freshness rule to `test/dune`**

Regenerate into a temp prefix and diff against the committed copies; fail with the regeneration command in the message if they differ.

- [ ] **Step 3: Verify the guard actually catches drift**

Deliberately edit one row of `specs/security/html-contexts.tbl` without regenerating, run `scripts/run-tests.sh`, and confirm it fails. Revert.

Expected: FAIL before revert, PASS after. A drift guard that has never been seen to fail is not known to work.

- [ ] **Step 4: Update docs and tracking**

- `CHANGELOG.md` under `## [Unreleased]` → `### Fixed`: note that `~H` now escapes by parse context, that `javascript:` URLs in `href` are neutralised, and that unquoted attribute values are auto-quoted. This is a **behaviour change** for existing templates and must be listed as such.
- `specs/security/README.md`: add the regeneration command.
- `git mv` the todo file to `specs/progress/`.
- Run `scripts/check-docs.sh` — it gates CI on stale stdlib module counts, and this plan adds stdlib modules.

- [ ] **Step 5: Full suite + benchmark check**

```bash
scripts/run-tests.sh
scripts/check-docs.sh
```

Then confirm no template-rendering regression, compiled (never interpreted):
```bash
march --compile --opt 2 bench/list_ops.march -o /tmp/list_ops && /tmp/list_ops
```

- [ ] **Step 6: Commit**

```bash
git add lib/ctxesc test/dune CHANGELOG.md specs
git commit -m "feat(ctxesc): generate tables from spec file + CI drift guard"
```

---

## Task 8: Validate against forgepm's 153 real templates

**Files:** none in this repo — this is a validation gate.

forgepm has 153 `~H` sites and exactly one `Html.raw`. It is the only real-world corpus available and the only way to find out how many existing templates the new diagnostics reject.

- [ ] **Step 1: Build forgepm against the new compiler**

```bash
cd /Users/80197052/code/march && MARCH_LIB_PATH=/Users/80197052/code/forgepm/lib \
  ./_build/default/bin/main.exe --compile -o /tmp/forgepm_check \
  /Users/80197052/code/forgepm/lib/forgepm.march
```

- [ ] **Step 2: Triage every new diagnostic**

For each one, classify: (a) a genuine template bug the analysis correctly caught — fix the template; (b) a table gap — fix the table and add a row-level test in `test_ctxesc.ml`; (c) a false positive from the pattern-vocabulary simplification — record it in `specs/security/README.md` under a "Known limitations" heading.

**Do not silence a diagnostic by widening a table row without a test pinning the widening.** That is how these systems rot.

- [ ] **Step 3: Diff the rendered output of the admin request-detail modal**

That page renders untrusted `user_agent` and `path`. Render it before and after and diff. Expect changed output *only* where the old escaping was wrong.

- [ ] **Step 4: Record findings in `specs/progress/` and commit any table fixes**

---

## Task 9: Close the non-sigil composition path (`Html.tag`)

> **Added 2026-08-06**, after Tasks 3–5 landed. Not in the original plan — found
> while asking whether any of this still belongs in a March library. It is the
> characteristic blind spot of a compile-time-only design: the analysis sees
> `~H` templates and nothing else.

**Files:**
- Modify: `stdlib/html.march:113` (`escape_attr`), `:134` (`tag`)
- Test: `test/native/h_tag_attr_context.march` + `.expected`, `test/dune`

### The gap

`Html.tag` composes HTML **outside** the sigil, so it never reaches the context
automaton. Its attribute escaping is:

```march
fn escape_attr(s : String) : String do
  escape(s)     -- HTML entity-encoding, and nothing else
end
```

Entity-encoding does not touch a colon, so:

```march
Html.tag("a", [("href", "javascript:alert(1)")], body)
```

emits `href="javascript:alert(1)"` — exactly the hole Task 5 closed for `~H`,
still open on this path.

*(Read from the source, not executed. The two functions are short and
unambiguous, but Step 1 below should confirm it by running.)*

**Not currently live.** The only real call site is
`bastion/lib/security/csrf.march:96`, `Html.tag("form", [("method", "post")], …)`
— a constant. But the API's shape invites the bug back, and an API that is safe
only because nobody has used it yet is not safe.

### Why fix rather than deprecate

`Html.tag` is one call site away from removable, so deprecation is tempting. It
is the wrong call: the machinery to make it correct now exists, the fix is small,
and leaving a known-unsafe constructor in the stdlib while shipping "~H is
contextually safe" invites exactly the wrong conclusion about the rest of the
module.

- [ ] **Step 1: Write the failing test, and confirm the gap is real**

`test/native/h_tag_attr_context.march`, a compiled/interpreted golden diff like
`h_escape_ctx_builtin.march`:

```march
mod HTagAttrContext do
  fn main() : Unit do
    let bad = "javascript:alert(1)"
    println("href=" ++ IOList.to_string(
      Html.tag("a", [("href", bad)], IOList.from_string("x"))))
    println("src=" ++ IOList.to_string(
      Html.tag("img", [("src", bad)], IOList.empty())))
    -- an ordinary attribute must keep entity-encoding, unchanged
    println("class=" ++ IOList.to_string(
      Html.tag("div", [("class", "a\"b")], IOList.empty())))
    -- a legitimate URL must survive intact
    println("ok=" ++ IOList.to_string(
      Html.tag("a", [("href", "/packages/bastion?tab=readme")], IOList.empty())))
  end
end
```

Expected BEFORE the fix: `href="javascript:alert(1)"` passes through verbatim.
**Record that output in the commit message** — it is the evidence the gap was
real, and the test is worthless without it.

- [ ] **Step 2: Classify the attribute name, then escape by class**

`escape_attr` currently ignores its key. Give `tag` the same classification the
table already performs, reusing `[attrs]` from
`specs/security/html-contexts.tbl` rather than a second hand-written list — a
duplicate list is precisely the hazard this plan keeps tripping over.

The classification lives OCaml-side (`Tbl_parse.classify`), and `Html.tag` is
March, so the escaping must go through the builtin:
`html_escape_ctx(<id>, value)` with the id chosen from the attribute's class.
That needs the class computed at runtime from a `String` key, which the compile
time analysis cannot do — so this path necessarily pays a small runtime cost the
sigil path does not. That is acceptable: it is a handful of attributes per tag,
and correctness beats a saved comparison.

Simplest sound implementation: a `Html.attr_escaper_id(name : String) : Int`
in March mirroring the `[attrs]` rules (`on*` → script, `href`/`src`/… → url,
`style` → style, else normal), then `html_escape_ctx(id, v)`.

**If that mirroring is written by hand, it is a fourth copy of the attribute
classification.** Prefer generating it from the `.tbl` — this is the one place a
`stdlib/ctx_table.march` fragment genuinely earns its keep, and it would revive
the useful half of Task 7 with a real consumer.

- [ ] **Step 3: Verify and pin**

`href`/`src` with `javascript:` → `about:invalid#zSoyz`; `class` unchanged from
today; a legitimate URL intact. Regenerate `.expected` and confirm
interpreted == compiled.

- [ ] **Step 4: Sweep the rest of the `Html` module**

`tag` is the one this task fixes, but the same question applies to every function
that emits markup from untrusted parts: `list`, `join`, `render_partial`,
`render_collection`, `layout`. Check each for a path that concatenates a
caller-supplied `String` into markup without going through a context. Record the
result — a clean sweep is worth writing down, since it bounds the audit.

- [ ] **Step 5: Commit**

Include the before/after output from Step 1, and state plainly that `Html.tag`
was reachable-but-unreached rather than a live vulnerability.

---

## Follow-up plan — REVISED 2026-08-06: recommend dropping

**"Runtime accumulator + generic sigils"** (Layer A) was to port the automaton to
March (`stdlib/ctx_accumulator.march` over a generated `stdlib/ctx_table.march`)
and change `desugar.ml`'s non-`~H` sigil path to pass segments instead of a
pre-concatenated string.

**The recommendation is now to drop it**, on evidence gathered while building
Tasks 1–5. Both original justifications weakened:

- *"An escape hatch for dynamic composition that today has none."* The corpora do
  not need one. All 121 `~H` templates across bastion and forgepm go through the
  sigil; `Html.escape` appears in application code **zero** times (every apparent
  hit was the stdlib function inside generated `.ll` files); `Html.tag` has
  exactly one real call site. There is no demand for `~SQL`/`~SH` either.

- *"A differential test oracle — the March automaton and the OCaml folder read
  the same tables and must agree."* This was oversold. A two-implementation
  cross-check already exists and is enforced: `lib/ctxesc/escape.ml` (interpreter)
  against `runtime/march_ctx_escape.c` (compiled), pinned by
  `test/native/h_escape_ctx_builtin.march` as a golden parity diff. A March copy
  would make **three** implementations of the same escaping logic.

That last point is the deciding one. This plan has already been bitten twice by
the same failure mode — the same information duplicated across places with
nothing forcing agreement:
`specs/todos/2026-08-05-runtime-source-list-duplication.md` (six hand-maintained
runtime source lists) and the golden LLVM preamble, which went stale twice. A
third copy of the escaping logic buys a weaker check than the one already in
place, at the cost of exactly the maintenance hazard that keeps causing problems
here.

**What would change the answer:** a concrete consumer — a `~SQL`/`~SH` sigil
someone actually wants, genuine dynamic HTML composition, or a March-implemented
tool (formatter, LSP feature) that needs the tables at runtime. Until one of
those exists, this is speculative work.

Note also the original performance caveat, which still holds and argues the same
way: the runtime accumulator pays a per-character scan over fixed chunks that the
compile-time fold does not. It could never be the front door for `~H`.

---

## Self-Review

**Spec coverage.** Transition tables → Tasks 1, 7. Non-sigil composition → Task 9 (added after the fact; the original plan assumed `~H` was the only way markup got built, which was wrong). Context tuple → Task 1. Subsidiary automata (URL/CSS/JS) → Tasks 1, 3. Epsilon transitions with substitutions → Tasks 1, 2, 5. Escaper selection + accumulator erasure → Task 5 (erasure is total here, by constant folding). Compile-time diagnostics → Tasks 2, 5. `isValidTerminalContext` → Tasks 2, 5. Merge at join points → **deliberately not implemented**: `~H` has no in-template control flow, so no join points exist. If in-template `if`/`for` is ever added to `~H`, `Automaton.merge` becomes required and this is the gap to close first.

**Type consistency.** `Context.t` field names (`state`/`element`/`attr`/`delim`) are used identically in Tasks 1, 2 and 5. `escaper_id` ids in `context.ml` and the `MARCH_ESC_*` C defines in Task 3 must agree — Task 7's drift guard covers the OCaml↔March pair but **not** the OCaml↔C pair. Add that assertion to Task 3's C test.

**Task ordering.** Task 0 was measured after this plan was first drafted and turned out to be a
live XSS plus a SIGSEGV in the shipped compiler, independent of everything else here — hence its
promotion to the front and its own branch. Task 3 then copies its type-directed dispatch rather
than the broken polymorphic one. Order: 0, then 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8.

**Known risk.** The `Repr` decision of which single-field ADTs are newtype-erased versus Boxed
is load-bearing for Task 0's dispatch and for Task 6's `Trusted`. A user-defined
`MySafe(String)` is newtype-erased to a bare String (measured), while `Html.Safe(String)` is
Boxed — same declared shape, different representation. Task 6 must establish which side
`Trusted(Ctx, String)` lands on *before* writing the escaper's verbatim-insertion path; a
two-field constructor is unambiguously Boxed, which is one reason to prefer that shape over a
phantom-typed single-field wrapper.
