# `--emit-core-ast` — march-side work for Stage A0 (Lean conformance bridge)

> Parent design doc: `march-lean` repo's `specs/plans/2026-07-18-lean-conformance-bridge-stage-a.md`
> §3 ("March-side work — the JSON AST seam"). This plan covers ONLY the
> `march`-repo tasks for milestone A0. Do not implement A1 (`elaborated` field)
> — that field is explicitly out of scope here.

## Global Constraints

- `format_version` is a JSON integer, currently `1`.
- Output of `--emit-core-ast <file.march>` is a SINGLE JSON document to
  stdout: `{"format_version":1,"verdict":"accept"|"reject","diagnostics":[...],"module":{...}}`.
  No `"elaborated"` key in A0.
- `verdict` MUST be computed via the exact same pipeline `--check`/`--check-json`
  use today (`check_module_full` + `Refine_check` + `Division_safety` +
  `No_alloc` + `Cap_infer`, all writing into the same `Err.ctx`) — do not
  reimplement or approximate the accept/reject decision. If march produces a
  parse or desugar error before typecheck is even reached, that's `"reject"`
  too (with those diagnostics).
- `diagnostics` array elements are the existing per-diagnostic JSON objects
  already produced by `March_errors.Errors.render_diagnostic_json`, filtered
  to user files exactly like `--check-json` does (`is_user_file`). Reuse that
  function directly — do not hand-roll a second diagnostic-to-JSON encoder.
- `module` is the desugared, `qualify_module_refs`'d, default-injected AST for
  the SINGLE input file — i.e. the `user_ast` binding in `bin/main.ml`'s
  `compile` function (captured right after `desugar_module`, BEFORE
  `resolve_imports`/stdlib injection). Do NOT serialize the stdlib-injected
  `desugared` binding — that would dump the entire stdlib on every invocation.
- The AST serializer must be TOTAL: one JSON encoding per OCaml constructor,
  for every one of `Ast.literal`, `Ast.pattern`, `Ast.expr`, `Ast.ty`,
  `Ast.nat_op`, `Ast.decl`, and the auxiliary record/variant types in the same
  recursive group (`param`, `binding`, `branch`, `test_def`, `app_def`,
  `use_decl`, `alias_decl`, `use_selector`, `fn_def`, `fn_clause`, `fn_param`,
  `type_def`, `variant`, `field`, `restart_strategy`, `supervise_field`,
  `supervise_config`, `actor_def`, `actor_handler`, `protocol_def`,
  `protocol_step`, `interface_def`, `assoc_type_decl`, `method_decl`,
  `impl_def`, `sig_def`, `extern_def`, `extern_fn`). Use exhaustive pattern
  matches with NO wildcard `_ ->` catch-all branch anywhere in the serializer,
  so a future new constructor is a compile error here, not a silent gap.
- Every node that carries a `span` in the AST must include it in its JSON as
  `"span":{"file":...,"start_line":...,"start_col":...,"end_line":...,"end_col":...}`.
- Reuse `lib/dump/dump.ml`'s existing `json_string` / `json_obj` / `json_list`
  helpers (hand-built JSON-as-strings, no `Yojson`/typed-JSON dependency) —
  this is the one precedent in the codebase for this style and `bin/dune`
  already depends on `march_dump`. If they're not exposed outside `dump.ml`
  (check for an `.mli`), either expose them or add the new serializer to
  `lib/dump/` so it's in the same compilation unit.
- No changes to the existing behavior of `--check`, `--check-json`, or
  `--dump-phases`. `--emit-core-ast` is a new, independent, mutually-exclusive
  one-shot output mode, short-circuiting similarly to `--check-json`.
- Exit code of `--emit-core-ast`: `0` if verdict is `"accept"`, `1` if
  `"reject"` (mirrors `--check`'s convention).

## Recon reference (read for exact file:line pointers, do not re-derive)

- CLI flags/dispatch: `bin/main.ml` — flag refs ~515-539, flag table ~2799-2837,
  `compile filename` at line 1082, parse at 1190-1201, desugar at 1220-1221
  (`user_ast` binding right after — confirm exact line when you read it),
  `resolve_imports`/stdlib injection at 1229-1271, `check_module_full` call at
  1289, refinecheck passes 1289-1297, verdict booleans ~1329-1334,
  `--check-json` branch (the pattern to mirror) at 1308-1314.
- `check_module_full` / `check_module_core`: `lib/typecheck/typecheck.ml`
  ~7672-8014, module `March_typecheck.Typecheck`.
- AST types: `lib/ast/ast.ml` (427 lines), module `March_ast.Ast`. `span` at
  line 7, `literal` at 32, `pattern` at 40, `expr`+aux at 51-91, `ty` at
  115-129, `nat_op` at 132, `decl`+aux at 146-354, `module_` at 354.
  `show_ty`/`show_expr` (lines 374-427) are exhaustive pattern-match skeletons
  to model the serializer's structure on (not JSON, but same exhaustiveness
  shape).
- JSON helpers: `lib/dump/dump.ml:21-43` (`json_string`/`json_obj`/`json_list`).
- Diagnostics: `lib/errors/errors.ml` — `diagnostic`/`severity`/`label`/
  `fix_kind` types at 10-34, `ctx` at 37, `Err.sorted` at 122-127,
  `render_diagnostic_json` at 250-289 (exact fields it emits — use this, don't
  re-derive), `is_user_file` at `bin/main.ml:1304-1306`.
- Test infra: Alcotest, flat `test/` dir, `test/test_helpers.ml` has
  `parse_and_desugar`/`typecheck_full` (bare desugar, no imports — fine for
  single-file corpus programs). `test/test_oracle.ml:1-56` is the only
  subprocess-based test precedent (`MARCH_BIN`/`MARCH_ROOT` env vars,
  `Unix.realpath`, path-walking to find the built binary) — model M3's golden
  test on this idiom since it needs the real CLI binary, not library calls.
- Corpus: `specs/lang/types/{accept,reject}/*.march` + `specs/lang/types/INDEX.md`
  (172 files total incl. INDEX.md), only on `origin/main` — this worktree is
  branched from `origin/main` so it's present. NOT present on other
  branches/worktrees in this repo (e.g. `hcr-dispatch-race`) — don't be
  surprised if you `git log` around and see it missing elsewhere.

---

## Task 1: AST → JSON serializer

**Files:** new file `lib/dump/ast_json.ml` (mirror `dump.ml`'s existing
module/library wiring in `lib/dump/dune`); read `lib/ast/ast.ml` and
`lib/dump/dump.ml` first.

**Steps:**

1. Read `lib/ast/ast.ml` in full to get the exact constructor lists, field
   names, and types for every type named in the Global Constraints' totality
   list above (the recon numbers — 27 `expr` ctors, 24 `decl` ctors, etc. —
   are approximate; use the actual source as ground truth).
2. Read `lib/dump/dump.ml:21-43` for the `json_string`/`json_obj`/`json_list`
   helper signatures, and check whether they're exposed (no `.mli` present =
   exposed by default in this codebase's convention; if `lib/dump/dune`
   references an `.mli`, check it).
3. Write `lib/dump/ast_json.ml` with one function per type, e.g.:
   - `span_to_json : Ast.span -> string`
   - `literal_to_json : Ast.literal -> string`
   - `pattern_to_json : Ast.pattern -> string`
   - `ty_to_json : Ast.ty -> string`
   - `expr_to_json : Ast.expr -> string`
   - `decl_to_json : Ast.decl -> string`
   - `module_to_json : Ast.module_ -> string`
   - plus one function per auxiliary type in the same recursive group,
     called from the constructors that reference them.
   Each function pattern-matches EVERY constructor of its type (no `_ ->`
   catch-all — the compiler must error if a constructor is later added and
   this file isn't updated). Encode each constructor as
   `json_obj [("kind", json_string "ConstructorName"); ...fields...]`,
   recursively calling the appropriate `_to_json` function for sub-terms and
   `json_list` for `List.map ... |> json_list` over list-typed fields.
   Include `"span"` in every node that carries one.
4. Do NOT modify `bin/main.ml` in this task — that's Task 2. This task is a
   pure, self-contained library addition.
5. Add `ast_json` to `lib/dump/dune`'s `modules` stanza if the dune file lists
   modules explicitly (check first — some dune stanzas auto-include all `.ml`
   files in the directory).

**Verification:**
- `dune build` succeeds with zero warnings related to non-exhaustive matches
  (if the project's dune profile treats warnings as errors, this is enforced
  automatically — check `dune-project`/`lib/dump/dune` for `(flags ...)`; if
  warnings aren't fatal in this profile, manually confirm every match has no
  wildcard case by inspection before reporting done).
- Add a small Alcotest suite, `test/test_ast_json.ml`, with a handful of
  direct unit tests: parse+desugar a couple of tiny inline `.march` snippets
  (reuse `test_helpers.parse_and_desugar`) covering at least one of each of:
  a literal, a pattern (e.g. from a `match`), a record type/expr, an ADT
  `decl`, a function `decl` — and assert the resulting JSON string contains
  the expected `"kind":"..."` markers (substring checks are fine here; this
  is a smoke test, not the golden test — that's Task 3). Wire this suite into
  whichever `test/dune` stanza runs the other fast unit suites.
- Run `dune test` (or the specific runner) and confirm the new suite passes.

---

## Task 2: `--emit-core-ast <file.march>` CLI flag

**Depends on:** Task 1 (needs `March_dump.Ast_json.module_to_json` or
equivalent).

**Files:** `bin/main.ml`.

**Steps:**

1. Add `let emit_core_ast_file = ref None` near the other flag refs (~515-539).
2. Add to the flag table (~2799-2837):
   `("--emit-core-ast", Arg.String (fun f -> emit_core_ast_file := Some f), " <file.march>  Emit desugared core AST + verdict + diagnostics as JSON to stdout");`
3. Read `bin/main.ml:1082` (`compile filename`) through at least line ~1340 in
   full before editing, to see exactly how `user_ast`, `desugared`, `errors`,
   `diags`, and the accept/reject booleans are named and computed in this
   version of the file (line numbers from recon are approximate).
4. After the point where `errors`/`diags` are fully populated (i.e. after the
   refinecheck passes — same point `--check-json`'s branch reads from), add:
   ```
   if !emit_core_ast_file <> None then begin
     let verdict = if <the same accept/reject condition --check uses> then "reject" else "accept" in
     let diagnostics_json =
       diags |> List.filter is_user_file
             |> List.map March_errors.Errors.render_diagnostic_json
             |> json_list   (* or March_dump.Dump.json_list — use whichever module you put json_list in *)
     in
     let module_json = March_dump.Ast_json.module_to_json user_ast in
     let doc = json_obj [
       ("format_version", "1");
       ("verdict", json_string verdict);
       ("diagnostics", diagnostics_json);
       ("module", module_json);
     ] in
     print_string doc;
     exit (if verdict = "accept" then 0 else 1)
   end;
   ```
   (Adjust names/order to match what you actually find in the file — this is
   illustrative, not a literal patch. Place it so it's mutually exclusive with
   `--check-json`'s branch, e.g. immediately before or after it, both using
   `exit` so only one ever fires per invocation.)
5. Make sure `user_ast` (the pre-import, post-desugar/qualify/default-inject
   binding) is in scope at this point — if `compile` doesn't currently keep
   it bound long enough, extend its scope minimally (don't restructure the
   function).
6. `format_version`, `json_string`, `json_obj`, `json_list` should reference
   Task 1's location for these helpers (`March_dump.Dump.json_*` or wherever
   Task 1 landed them) — do not duplicate them into `bin/main.ml`.

**Verification:**
- `dune build` succeeds.
- Manually run, e.g.:
  `dune exec march -- --emit-core-ast specs/lang/types/accept/t01_literals.march`
  and confirm valid JSON comes out on stdout with `"format_version":1`,
  `"verdict":"accept"`, an empty or near-empty `"diagnostics"`, and a non-trivial
  `"module"` tree. Then try a file from `specs/lang/types/reject/` and confirm
  `"verdict":"reject"` with a non-empty `"diagnostics"` array, and that the
  process exit code is `1` (check with `echo $?`).
- Confirm `march --check` and `march --emit-core-ast` agree on verdict for a
  handful of spot-checked files from both `accept/` and `reject/` (this is
  the same invariant the Lean-side harness will check later — worth catching
  a mismatch now rather than in CI).
- Confirm existing `--check`, `--check-json`, `--dump-phases` behavior is
  unchanged (run the existing test suite: `dune test`).

---

## Task 3: Golden test for `--emit-core-ast`

**Depends on:** Task 2.

**Files:** new `test/test_emit_core_ast.ml` (or similar name matching this
repo's naming convention — check what Task 1/2 established), new fixture
files under e.g. `test/emit_core_ast/fixtures/`.

**Steps:**

1. Read `test/test_oracle.ml:1-56` in full — this is the only existing
   subprocess-based test in the repo (locates the built `march` binary via
   `MARCH_BIN` env var or `_build/default/bin/main.exe`, uses
   `Unix.realpath`/path-walking for `MARCH_ROOT`). Model this task's test on
   that idiom, since `--emit-core-ast`'s verdict computation lives in
   `bin/main.ml` (an executable), not a library function — testing the real
   CLI binary end-to-end is the point, not re-deriving pipeline logic inline.
2. Choose 3 representative files from `specs/lang/types/{accept,reject}/`
   (use `specs/lang/types/INDEX.md` to pick ones exercising varied
   constructs — at minimum: one simple accept case, one accept case touching
   records/ADTs/generics, one reject case). Reference the corpus files
   in-place by path — do not copy/duplicate the `.march` source into the new
   fixtures directory.
3. For each chosen file, run the built `march --emit-core-ast <file>` once
   (during test-authoring, not at test-run time) and save its stdout verbatim
   as the golden fixture, e.g. `test/emit_core_ast/fixtures/t01_literals.expected.json`.
4. Write the new Alcotest suite: for each (corpus file, fixture file) pair,
   subprocess-invoke `march --emit-core-ast <corpus file>`, capture stdout,
   and assert it equals the fixture's contents exactly (byte-for-byte, or
   parse both as JSON and structurally compare if byte-for-byte proves too
   brittle across environments — prefer byte-for-byte first, only fall back
   if you hit a real nondeterminism, e.g. path handling).
5. Add a short comment at the top of the test file explaining that these
   fixtures pin the `--emit-core-ast` JSON format — if the format changes
   deliberately (e.g. `format_version` bump), regenerate by re-running step 3
   and reviewing the diff, don't just silence the test.
6. Wire the new suite into the appropriate `test/dune` stanza.

**Verification:**
- `dune test` passes, including the new suite.
- Deliberately break the golden test once to confirm it actually catches
  drift: temporarily edit one fixture file (e.g. flip `"verdict":"accept"` to
  `"verdict":"reject"`) and confirm `dune test` fails with a clear diff, then
  revert the edit before finishing.
- Confirm the fixture files are committed (not `.gitignore`d).
