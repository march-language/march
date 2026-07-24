# Pattern-Matching Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four known gaps in March's pattern matcher — record patterns, as-patterns, or-patterns, and a redundancy-warning bug that silences unreachable-arm diagnostics for every function with a declared return type.

**Architecture:** Three of the four gaps are "the AST node exists, the parser can't build it." `PatRecord` and `PatAs` are already implemented in the interpreter, typechecker, formatter, LSP, and span-remapper; they are unreachable only because `lib/parser/parser.mly` has no production that constructs them. So most of the work is (a) grammar productions, (b) the two TIR lowering paths that currently `failwith` or silently drop bindings, and (c) retiring the spec fixtures that currently *pin the rejection as correct*. Or-patterns are the one genuinely new AST node. The redundancy bug is a one-line omission.

**Tech Stack:** OCaml 5.3.0, menhir (LR parser), ocamllex, dune, alcotest. Opam switch `march`; `dune`/`opam` are already on PATH — never prefix commands with `eval $(opam env)`.

## Global Constraints

- **Work in this worktree.** Build and test with `dune build --root .` / `dune runtest --root .` from `/Users/80197052/code/march/.claude/worktrees/record-matching-gaps-cf6350`. A bare `dune build` resolves to the main repo and will fail with "Don't know how to build".
- **Never `git stash`.** The stash stack is shared across every worktree of this repo; a stash here silently mutates other concurrent sessions. Swap files by copying instead.
- **Never `git add -A` / `git add .` / `git commit -am`.** Stage files explicitly by name.
- **No `Co-Authored-By` lines** in commit messages.
- **Judge `dune runtest` by `$?`, not by tail output.** Rule failures print *above* a green alcotest summary.
- Prefer `scripts/run-tests.sh` over `dune runtest` when a stale dune RPC daemon might be present. `dune shutdown` unsticks it.
- **Every task updates `specs/todos.md` and `specs/progress.md` in the same commit** (project rule in `CLAUDE.md`), and adds a `CHANGELOG.md` bullet under `## [Unreleased]` for user-visible changes.
- **The published docs site and the internal reference are TWO copies that must stay in sync.** `docs/pattern-matching.md` (permalink `/docs/pattern-matching/`) is a live near-duplicate of `specs/lang/pattern-matching.md`, not a redirect stub. Any statement about pattern-matching capability edited in one must be edited in the other in the same commit. `scripts/check-docs.sh` lints both trees and must exit 0 before every commit.
- **Never pipe `march --compile` output** (`| tail` wedges — the compiler child holds the pipe open). Redirect to a file, judge by `$?`, read the file separately.
- Use the scratchpad `/private/tmp/claude-502/-Users-80197052-code-march--claude-worktrees-record-matching-gaps-cf6350/85e56205-0abd-4850-821a-d29f48f8d96c/scratchpad` for temp files, and suffix temp binaries with the worktree slug to avoid collisions with concurrent sessions.

## Verified Facts (do not re-derive)

These were established by direct experiment before this plan was written. Trust them.

1. **The grammar additions introduce ZERO new menhir conflicts.** All three productions (record pattern in `simple_pattern`, as-pattern wrapping `pattern`, or-pattern via `PIPE`) were applied experimentally and `menhir --explain` reported the same 9 shift/reduce conflicts, involving the same tokens, as the unmodified grammar. In particular the feared `PIPE`-as-`arm_sep` versus `PIPE`-as-or-pattern overlap is a non-issue: `arm_sep` only ever follows a *complete* branch, so LR(1) can distinguish them.
2. **`fn f({x, y})` needs no separate work.** A single-clause function whose params include a non-`PatVar` `FPPat` falls through `desugar.ml`'s two fast paths (`desugar.ml:702` and `desugar.ml:711` both exclude `FPPat _`) into the general path at `desugar.ml:745`, which builds an `EMatch`. Function parameter patterns therefore ride the match-lowering path.
3. **There are TWO lowering sites, not one.** `lib/tir/lower_match.ml` (match arms + fn params) fails loudly with `failwith`. `lib/tir/lower.ml:196-280` handles irrefutable `let` patterns with its own `bind_subpat`, whose catch-all at `lower.ml:266` returns `inner` unchanged — it drops the bindings **silently**. `let {x, y} = r` would compile to code where `x` and `y` are unbound.
4. **Guards already work end-to-end** (parser `when_guard` at `parser.mly:409`, `desugar.ml:768`, `eval.ml:8275`, `lower_match.ml:574`). Nothing in this plan touches them.
5. **Guarded matches suppressing the non-exhaustive warning is deliberate**, documented at `typecheck.ml:4056-4070`: coverage is computed over guardless branches only and the span is recorded for `cap no_panic` promotion, without a global warning. Do not "fix" this.
6. **Three spec fixtures currently pin these features as *correctly rejected*** and must be moved from `reject/` to `parse/`: `specs/lang/grammar/reject/r02_record_pattern_in_arm_unreachable.march`, `r07_record_pattern_in_let_unreachable.march`, `r08_as_pattern_unreachable.march`. They are referenced by `specs/lang/grammar/INDEX.md` lines 51, 68, 69, 99 and by `specs/lang/grammar.md` §6.3.
7. **`is_pattern_start` in `lib/parser/token_filter.ml:165` must gain `Parser.LBRACE`** for record patterns (as-patterns and or-patterns need no filter change — `AS` and `PIPE` are not bail-out tokens in `lookahead_is_new_arm`, and `LBRACE`/`RBRACE` already participate in its depth tracking at `token_filter.ml:233-239`).

## Design Decisions

**Record patterns are OPEN (partial field lists allowed, no `..` marker).** `{x}` matches any record having at least field `x`. Rationale: March records are structurally typed with no width subtyping (`typecheck.ml:2789` requires exact field-set equality), so a closed reading would make record patterns useless for anything but full destructuring — which `let` already does better. This matches Elixir/Erlang map patterns. Consequence: `PatRecord` needs no new "open" flag on the AST, and exhaustiveness stays `SPWild` (safe: records are single-constructor, so a top-level record pattern is irrefutable).

**Or-pattern alternatives may not bind variables** in this pass. `1 | 2`, `:get | :head`, `Red | Blue` are supported; `Cons(x, _) | Other(x)` is rejected at typecheck with a clear diagnostic. Rationale: sharing an arm body across alternatives uses `lower_match.ml`'s existing 0-arg join point (`hoist_fallback_jp`, `lower_match.ml:249`); supporting bound variables requires n-ary join points, which is a separate piece of work. Duplicating the body per alternative instead would reintroduce exactly the exponential TIR blowup that `hoist_fallback_jp` exists to prevent.

## File Structure

**Modified — parser/AST layer:**
- `lib/parser/parser.mly` — three new pattern productions (Tasks 2, 3, 5)
- `lib/parser/token_filter.ml` — `LBRACE` in `is_pattern_start` (Task 3)
- `lib/ast/ast.ml` — `PatOr` constructor (Task 5)

**Modified — semantic layer:**
- `lib/typecheck/typecheck.ml` — redundancy call site (Task 1); expected-driven record field lookup (Task 4); `PatOr` inference + exhaustiveness row expansion (Task 5)
- `lib/eval/eval.ml` — `PatOr` matching + stale "unreachable" comments (Tasks 2, 3, 5)

**Modified — lowering layer:**
- `lib/tir/lower_match.ml` — as-pattern column stripping (Task 2), record column expansion (Task 3), or-pattern row splitting + body hoisting (Task 5)
- `lib/tir/lower.ml` — `PatRecord` arm in `bind_subpat` for `let` bindings (Task 3)

**Modified — mechanical `PatOr` arms (Task 5 only; the OCaml compiler's exhaustiveness checker enumerates every one):**
`lib/ast/span_remap.ml`, `lib/desugar/desugar.ml`, `lib/dump/ast_json.ml`, `lib/format/format.ml`, `lib/refactor/refactor.ml`, `lib/refinecheck/refine_check.ml`, `lsp/lib/analysis.ml`, `lsp/lib/workspace.ml`

**Tests:**
- `test/test_compiler.ml` — parser + typecheck tests
- `test/test_eval.ml` — interpreter semantics tests
- `test/dune` — native golden rules
- `test/native/*.march` + `*.expected` — compiled-path goldens
- `specs/lang/grammar/parse/`, `specs/lang/grammar/reject/` — conformance corpus

**Docs — internal reference (`specs/lang/`):**
`specs/lang/grammar.md`, `specs/lang/grammar/INDEX.md`, `specs/lang/pattern-matching.md`, `specs/lang/core-march-types.md`, `specs/lang/surface-syntax.md`, `.claude/skills/march-lang/SKILL.md`

**Docs — published site (`docs/`, Jekyll):**
- `docs/pattern-matching.md` — a live 494-line page at permalink `/docs/pattern-matching/`, **not** a redirect stub. It is a near-duplicate of `specs/lang/pattern-matching.md` (the "Record Patterns" section sits at lines 126-135 in both, the multi-head-clause note at 448-455 in both). Every edit made to the `specs/lang/` copy must be mirrored here, or the published site keeps telling users the feature does not exist.
- `docs/types.md:119` — "**Record patterns are not yet supported by the parser** (`{ x, y } -> ...` in …)". Retired by Task 3.

`scripts/check-docs.sh` lints `docs/**/*.md` alongside `specs/lang/`, so both copies are gated by the same freshness check. Run it before every commit that touches either.

**Bookkeeping:** `specs/todos.md`, `specs/progress.md`, `CHANGELOG.md`

---

### Task 1: Restore redundant-arm warnings in checking mode

`check_redundant_arms` is called from the inference-mode match path (`typecheck.ml:5510`) but not from the checking-mode path (`typecheck.ml:5324-5339`). Any function with a declared return type puts its body in checking position, so unreachable arms go unreported in the overwhelmingly common case.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:5339`
- Test: `test/test_compiler.ml`
- Docs: `CHANGELOG.md`, `specs/todos.md`, `specs/progress.md`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Write the failing test**

Add to `test/test_compiler.ml`, just above the `compiler_suites` definition at line 8292:

```ocaml
(* A match in CHECKING position (function with a declared return type) must
   still get redundant-arm warnings.  check_expr's EMatch arm called only
   check_exhaustiveness, never check_redundant_arms, so every match inside an
   annotated function silently skipped the analysis. *)
let test_redundant_arm_in_checking_position () =
  let ctx = typecheck {|mod T do
    fn f(o : Option(Int)) : Int do
      match o do
        _ -> 9
        Some(x) -> x
        None -> 0
      end
    end
  end|} in
  let has_redundant =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.code = Some "redundant_arm")
      (March_errors.Errors.diagnostics ctx)
  in
  Alcotest.(check bool) "redundant arm reported in checking position" true
    has_redundant

(* Control: the same match in INFERENCE position (no return annotation) already
   warned before this fix.  Pins that the fix does not regress it. *)
let test_redundant_arm_in_inference_position () =
  let ctx = typecheck {|mod T do
    fn f(o) do
      match o do
        _ -> 9
        Some(x) -> x
        None -> 0
      end
    end
  end|} in
  let has_redundant =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.code = Some "redundant_arm")
      (March_errors.Errors.diagnostics ctx)
  in
  Alcotest.(check bool) "redundant arm reported in inference position" true
    has_redundant
```

Then register them by adding a new group as the FIRST entry of the `compiler_suites` list at `test/test_compiler.ml:8293` (immediately after the opening `[`):

```ocaml
      ( "match_diagnostics",
        [
          Alcotest.test_case "redundant arm warned in checking position" `Quick
            test_redundant_arm_in_checking_position;
          Alcotest.test_case "redundant arm warned in inference position" `Quick
            test_redundant_arm_in_inference_position;
        ] );
```

- [ ] **Step 2: Run the test to verify it fails**

(`ctx.March_errors.Errors.diagnostics` is a record field, not a function — this is the idiom existing tests use, e.g. `test/test_compiler.ml:484`. No accessor lookup needed.)

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe test match_diagnostics
```

Expected: the "checking position" case FAILS (`Expected true, got false`); the "inference position" case PASSES.

- [ ] **Step 3: Write the fix**

In `lib/typecheck/typecheck.ml`, change line 5339 from:

```ocaml
    check_exhaustiveness env msp scrut_ty branches
```

to:

```ocaml
    check_exhaustiveness env msp scrut_ty branches;
    check_redundant_arms env scrut_ty branches
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe test match_diagnostics
```

Expected: both cases PASS.

- [ ] **Step 5: Run the full suite — this fix will surface pre-existing redundant arms**

```bash
scripts/run-tests.sh
```

Expected: PASS. If any *existing* test now fails because a fixture in `test/` or `stdlib/` contains a genuinely unreachable arm, that is a true positive — fix the fixture (delete the dead arm), do not weaken the check. If a fixture's arm is intentionally dead for a reason, reorder it rather than suppressing the warning.

- [ ] **Step 6: Update docs**

Add to `CHANGELOG.md` under `## [Unreleased]`, in a `### Fixed` section (create it if absent, ordered after `### Changed`):

```markdown
- Unreachable match arms are now reported inside functions with a declared
  return type. `check_redundant_arms` ran only on the type-inference path, so
  any `match` in checking position — which is every `match` in a function with
  a return annotation, i.e. most of them — silently skipped the analysis.
```

In `specs/todos.md`, add to the "Done" section:

```markdown
- **Redundant-arm warnings restored in checking position** (2026-07-24) —
  `lib/typecheck/typecheck.ml`'s `check_expr` `EMatch` arm called
  `check_exhaustiveness` but not `check_redundant_arms`; only the `infer_expr`
  path ran both. Every `match` inside a return-annotated function therefore
  skipped unreachable-arm analysis. One-line fix + two regression tests
  (`match_diagnostics` group in `test/test_compiler.ml`) pinning both the
  checking and inference paths.
```

In `specs/progress.md`, add to the feature bullet list:

```markdown
- Redundant (unreachable) match-arm warnings on both the inference and
  checking typecheck paths
```

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml CHANGELOG.md specs/todos.md specs/progress.md && git commit -m "fix(typecheck): report redundant match arms in checking position"
```

---

### Task 2: As-patterns (`p as name`)

`PatAs` is fully implemented in `eval.ml:1193`, `typecheck.ml:3554`, `lower.ml:240` (the `let` path), and `lower_match.ml:61` (the trivial-pattern path). Two things are missing: a grammar production, and handling in the match matrix compiler for a **non-trivial** inner pattern — `pat_tag_and_subs` returns `None` for `PatAs` (`lower_match.ml:212`), which routes into the fail-loudly branch at `lower_match.ml:377`.

**Files:**
- Modify: `lib/parser/parser.mly:1441` (the `pattern` production)
- Modify: `lib/tir/lower_match.ml` (new `strip_as_column`, called from `compile_matrix_impl`)
- Modify: `lib/eval/eval.ml:1193` (stale comment)
- Test: `test/test_eval.ml`, `test/native/as_pattern.march` + `.expected`, `test/dune`
- Move: `specs/lang/grammar/reject/r08_as_pattern_unreachable.march` → `specs/lang/grammar/parse/p29_as_pattern.march`
- Docs: `specs/lang/grammar.md`, `specs/lang/grammar/INDEX.md`, `specs/lang/pattern-matching.md`, `specs/lang/core-march-types.md`, `specs/lang/surface-syntax.md`, `.claude/skills/march-lang/SKILL.md`, `CHANGELOG.md`, `specs/todos.md`, `specs/progress.md`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `pattern: pattern_no_as AS lower_name` grammar shape. Task 5 rewrites `pattern_no_as` to add the or-pattern layer beneath it; keep the nonterminal name `pattern_no_as` so Task 5 can slot in without renaming.

- [ ] **Step 1: Write the failing interpreter test**

Add to `test/test_eval.ml`, above the `eval_suites` definition at line 4497:

```ocaml
(* As-patterns: `p as n` binds n to the whole matched value while p continues
   to destructure it.  PatAs existed in the AST, interpreter, and typechecker
   from the start but had no grammar production. *)
let test_eval_as_pattern_binds_whole () =
  let env = eval_module {|mod T do
    fn f(o) do
      match o do
        Some(x) as whole ->
          match whole do
            Some(y) -> x + y
            None -> 0
          end
        None -> 0
      end
    end
  end|} in
  let v = call_fn env "f"
      [March_eval.Eval.VCon ("Some", [March_eval.Eval.VInt 21])] in
  Alcotest.(check int) "Some(21) as whole -> 21 + 21" 42
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* An as-pattern over a TRIVIAL inner pattern takes lower_match's
   bind_trivial_pat path; over a NON-TRIVIAL inner it takes the new
   strip_as_column path.  Cover the trivial one too. *)
let test_eval_as_pattern_trivial_inner () =
  let env = eval_module {|mod T do
    fn f(n) do
      match n do
        x as y -> x + y
      end
    end
  end|} in
  let v = call_fn env "f" [March_eval.Eval.VInt 5] in
  Alcotest.(check int) "x as y -> x + y" 10
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")
```

Register as the first entry of the `eval_suites` list at `test/test_eval.ml:4498`:

```ocaml
      ( "as_patterns",
        [
          Alcotest.test_case "as-pattern binds the whole value" `Quick
            test_eval_as_pattern_binds_whole;
          Alcotest.test_case "as-pattern over a trivial inner pattern" `Quick
            test_eval_as_pattern_trivial_inner;
        ] );
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune build --root . test/run_eval.exe && ./_build/default/test/run_eval.exe test as_patterns
```

Expected: both FAIL with a parse error mentioning ``I was expecting `->` in the match arm here``.

- [ ] **Step 3: Add the grammar production**

In `lib/parser/parser.mly`, replace the `pattern:` production header at line 1441:

```
pattern:
  | con = qualified_upper; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatCon (con, ps) }
```

with:

```
(* An as-pattern layer wrapping the ordinary pattern forms.  Written as
   `pattern_no_as AS lower_name` rather than left-recursively on `pattern`
   so that `p as a as b` is a parse error rather than a silent nesting, and
   so no precedence declaration is needed for AS.  Uses `lower_name`, not
   `soft_lower_name`: `soft_lower_name` accepts AS itself as an identifier
   (parser.mly:1491), and allowing `x as as` buys nothing. *)
pattern:
  | p = pattern_no_as; AS; n = lower_name
    { PatAs (p, n, mk_span ($loc)) }
  | p = pattern_no_as { p }

pattern_no_as:
  | con = qualified_upper; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatCon (con, ps) }
```

Leave the remaining alternatives of the original `pattern` rule (the nullary `qualified_upper`, both `ATOM` forms, and `| p = simple_pattern { p }`) exactly where they are — they now belong to `pattern_no_as`.

- [ ] **Step 4: Verify the grammar introduces no new conflicts**

The baseline is **9 shift/reduce conflicts**. Confirm you did not add any:

```bash
menhir --explain lib/parser/parser.mly -b /tmp/asconf-record-matching-gaps-cf6350 2>&1 | grep -i conflict
```

Expected: `Warning: 9 states have shift/reduce conflicts.` — the same count as before. If the number rose, stop and re-read the production; do not proceed.

- [ ] **Step 5: Run the interpreter test again**

```bash
dune build --root . test/run_eval.exe && ./_build/default/test/run_eval.exe test as_patterns
```

Expected: both PASS. (The interpreter needs no change — `eval.ml:1193` already handles `PatAs`.)

- [ ] **Step 6: Write the failing compiled test**

Create `test/native/as_pattern.march`:

```march
mod AsPattern do
fn describe(o : Option(Int)) : String do
  match o do
    Some(x) as whole ->
      match whole do
        Some(y) -> "some " ++ int_to_string(x + y)
        None -> "impossible"
      end
    None -> "none"
  end
end

fn main() : Unit do
  println(describe(Some(21)))
  println(describe(None))
end
end
```

Create `test/native/as_pattern.expected`:

```
some 42
none
```

Add to `test/dune`, immediately after the `native_signal_watch` diff rule (around line 956):

```
; ── As-patterns (`p as n`) must compile ──────────────────────────────
; PatAs existed in the AST/interpreter/typechecker but had no grammar
; production.  With the production added, lower_match's pat_tag_and_subs
; returns None for PatAs, which routes a NON-TRIVIAL inner pattern into the
; fail-loudly "unhandled pattern kind" branch.  strip_as_column rewrites the
; row instead.  Compile natively, run, diff against the interpreter's output.
(rule
 (targets native_as_pattern native_as_pattern.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/as_pattern.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_as_pattern
        native/as_pattern.march)
   (with-stdout-to native_as_pattern.out
        (system "./native_as_pattern")))))

(rule
 (alias runtest)
 (action (diff native/as_pattern.expected native_as_pattern.out)))
```

- [ ] **Step 7: Run the compiled test to verify it fails**

```bash
dune build --root . @runtest 2>&1 | grep -A 5 as_pattern; echo "EXIT=$?"
```

Expected: FAIL with `lower: unhandled pattern kind in match compilation at …` from `lower_match.ml:377`.

- [ ] **Step 8: Implement `strip_as_column` in the matrix compiler**

In `lib/tir/lower_match.ml`, add this immediately after `is_atomic_fallback` (which ends at line 235):

```ocaml
(** Strip a first-column as-pattern: bind the alias to the current scrutinee
    and continue matching on the inner pattern.

    [is_trivial_pat] already routes an as-pattern over a TRIVIAL inner
    (`x as y`) into the default rows, where [bind_trivial_pat] binds both
    names.  Only a NON-TRIVIAL inner (`Some(x) as s`) reaches the ctor-row
    path, where [pat_tag_and_subs] returns None for PatAs and the row would
    hit the fail-loudly "unhandled pattern kind" branch.  Rewriting the row
    here keeps the alias binding and lets the inner pattern dispatch
    normally. *)
let strip_as_column (env : Lower_state.env) (scrut : Tir.atom)
    (rows : (Ast.pattern list * Tir.expr) list)
  : (Ast.pattern list * Tir.expr) list =
  List.map (fun (pats, body) ->
    match pats with
    | Ast.PatAs (inner, n, _) :: rest when not (is_trivial_pat inner) ->
      let v : Tir.var = {
        v_name = n.Ast.txt;
        v_ty   = Lower_state.ty_of_span env n.Ast.span;
        v_lin  = Tir.Unr;
      } in
      (inner :: rest, Tir.ELet (v, Tir.EAtom scrut, body))
    | _ -> (pats, body)) rows
```

Then in `compile_matrix_impl`, at the `| scrut :: rest_scruts ->` arm (line 320 area), insert the rewrite as the first thing in that arm, before the `let rec split_at_trivial` definition:

```ocaml
    | scrut :: rest_scruts ->
      let rows = strip_as_column env scrut rows in
      (* Split rows into a front block of non-trivial first-column rows and
         a (possibly empty) suffix starting at the first trivial first-column
         row.  The suffix becomes the default for all ECase branches. *)
      let rec split_at_trivial acc = function
```

Also register the alias in `collect_pat_names` — verify `lower_match.ml:505` already does (`| Ast.PatAs (p, n, _) -> (n.txt, n.span) :: collect_pat_names p`). It does; no change needed.

- [ ] **Step 9: Run the compiled test to verify it passes**

```bash
dune build --root . @runtest 2>&1 | grep -A 5 as_pattern; echo "EXIT=$?"
```

Expected: no diff output, `EXIT=0`.

- [ ] **Step 10: Move the conformance fixture from reject/ to parse/**

The corpus currently pins as-pattern rejection as *correct behavior*. `parse/` programs must be well-typed and exit 0 under `march --check`; they carry no `EXPECT-ERROR` line.

```bash
git rm specs/lang/grammar/reject/r08_as_pattern_unreachable.march
```

Create `specs/lang/grammar/parse/p29_as_pattern.march`:

```march
mod P29AsPattern do
  fn main() do
    match 1 do
      x as y -> x + y
    end
  end
end
```

Verify it checks clean:

```bash
dune build --root . bin/main.exe && ./_build/default/bin/main.exe --check specs/lang/grammar/parse/p29_as_pattern.march; echo "EXIT=$?"
```

Expected: `EXIT=0`, no output.

- [ ] **Step 11: Run the grammar conformance corpus**

```bash
dune build --root . @grammar-check; echo "EXIT=$?"
```

Expected: `EXIT=0`.

- [ ] **Step 12: Update the specs**

In `specs/lang/grammar/INDEX.md`: delete the `r08` table row (line 69) and add a `p29` row to the parse table:

```markdown
| [`parse/p29_as_pattern.march`](parse/p29_as_pattern.march) | §6.2 — `pattern`'s as-pattern layer | `match 1 do x as y -> y end` — `pattern: pattern_no_as AS lower_name` builds `PatAs`. Was `reject/r08` until as-patterns were implemented (2026-07-24); the reachability gap it documented is closed. |
```

Update the INDEX.md header line 1 to mention `p29`, and amend line 99's sentence about "two new `PatRecord`/`PatAs` reachability witnesses" to note that the `PatAs` witness has been retired.

In `specs/lang/grammar.md` §6.3 (lines 1364-1420): rewrite the section so it covers only `PatRecord` (Task 3 retires it entirely), remove the `r08` bullet at line 1410, and update the cross-references at lines 8, 59, 1264, 2395, and 2452 to stop claiming `PatAs` is unreachable. Per `CLAUDE.md`'s doc-freshness rule, say so in words ("as-patterns became reachable in 2026-07-24; this section now covers only `PatRecord`") rather than deleting the history silently.

In `specs/lang/core-march-types.md`: replace the "No `(P-As)` rule either" block at lines 1021-1043 with an actual `(P-As)` rule matching the style of the neighbouring `(P-Atom)`/`(P-Tuple)` rules, and update the summary note at line 904.

In `specs/lang/pattern-matching.md`: add an "As Patterns" section documenting `p as name`.

In **`docs/pattern-matching.md`** (the published Jekyll page — a near-duplicate of the file above, not a stub): add the same "As Patterns" section. Keep the two copies in sync section-for-section.

In `specs/lang/surface-syntax.md` and `.claude/skills/march-lang/SKILL.md`: add `Some(x) as whole` to the pattern-matching quick reference.

Verify the published page still lints clean:

```bash
scripts/check-docs.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`.

In `lib/eval/eval.ml:1193`, update the stale comment — replace `(* match(PatAs) — §4.3, unreachable from surface syntax per §4.3.1 *)` with `(* match(PatAs) — §4.3 *)`.

- [ ] **Step 13: Update CHANGELOG / todos / progress**

`CHANGELOG.md`, under `## [Unreleased]` → `### Added`:

```markdown
- As-patterns: `Some(x) as whole -> ...` binds a name to the entire matched
  value while the inner pattern continues to destructure it. Works in match
  arms, `let` bindings, and function parameters. `PatAs` had been implemented
  in the AST, interpreter, and typechecker since the beginning but had no
  grammar production.
```

`specs/todos.md` Done section and `specs/progress.md` feature list: add corresponding entries.

- [ ] **Step 14: Run the full suite and commit**

```bash
scripts/run-tests.sh && dune build --root . @grammar-check && dune build --root . @types-check; echo "EXIT=$?"
```

Expected: `EXIT=0`.

```bash
git add lib/parser/parser.mly lib/tir/lower_match.ml lib/eval/eval.ml test/test_eval.ml test/dune test/native/as_pattern.march test/native/as_pattern.expected specs/lang/grammar/parse/p29_as_pattern.march specs/lang/grammar/INDEX.md specs/lang/grammar.md specs/lang/core-march-types.md specs/lang/pattern-matching.md specs/lang/surface-syntax.md docs/pattern-matching.md .claude/skills/march-lang/SKILL.md CHANGELOG.md specs/todos.md specs/progress.md && git commit -m "feat(parser): as-patterns (p as name)"
```

---

### Task 3: Record patterns — grammar, match lowering, and `let` lowering

This task lands record patterns end-to-end for the case where the pattern's field list is **exactly** the record's field list. Partial field lists are Task 4. Grammar and both lowering paths must land together: adding the grammar alone would make `let {x, y} = r` compile to code with unbound variables (`lower.ml:266` returns `inner` unchanged for `PatRecord`), which is a silent miscompile, not a loud failure.

**Files:**
- Modify: `lib/parser/parser.mly` (`simple_pattern` + new `record_field_pat`)
- Modify: `lib/parser/token_filter.ml:165` (`is_pattern_start` gains `LBRACE`)
- Modify: `lib/tir/lower_match.ml` (record column expansion)
- Modify: `lib/tir/lower.ml:196-280` (`bind_subpat` `PatRecord` arm + outer dispatch)
- Modify: `lib/eval/eval.ml:1178,1192` (stale comments)
- Test: `test/test_eval.ml`, `test/native/record_pattern.march` + `.expected`, `test/dune`
- Move: `reject/r02_record_pattern_in_arm_unreachable.march` → `parse/p30_record_pattern_in_arm.march`; `reject/r07_record_pattern_in_let_unreachable.march` → `parse/p31_record_pattern_in_let.march`
- Docs: same set as Task 2, plus `specs/lang/grammar.md` §3.4

**Interfaces:**
- Consumes: `pattern_no_as` from Task 2 (the record production goes into `simple_pattern`, which `pattern_no_as` reaches via its `| p = simple_pattern` alternative — no change to Task 2's shape).
- Produces: `record_field_pat : (Ast.name * Ast.pattern)` grammar nonterminal, supporting both `name: pat` and punned `name`. Task 4 consumes the resulting `Ast.PatRecord` nodes.

- [ ] **Step 1: Write the failing interpreter tests**

Add to `test/test_eval.ml` above `eval_suites`:

```ocaml
(* Record patterns in a match arm, with the field list exactly matching the
   record's fields.  PatRecord existed in the AST and interpreter but had no
   grammar production. *)
let test_eval_record_pattern_match () =
  let env = eval_module {|mod T do
    fn f() do
      let r = { x: 3, y: 4 }
      match r do
        { x: a, y: b } -> a * b
      end
    end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "{x: 3, y: 4} -> 3 * 4" 12
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Punned field patterns: `{ x, y }` is shorthand for `{ x: x, y: y }`. *)
let test_eval_record_pattern_punned () =
  let env = eval_module {|mod T do
    fn f() do
      let r = { x: 3, y: 4 }
      match r do
        { x, y } -> x + y
      end
    end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "{x, y} punned -> 3 + 4" 7
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Record pattern in an irrefutable `let` binding — a DIFFERENT lowering path
   (lower.ml's bind_subpat) from the match matrix compiler. *)
let test_eval_record_pattern_let () =
  let env = eval_module {|mod T do
    fn f() do
      let r = { x: 3, y: 4 }
      let { x: a, y: b } = r
      a * b + 1
    end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "let {x: a, y: b} = r" 13
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Record pattern as a function parameter.  desugar.ml routes a single clause
   with a non-PatVar FPPat through the general path, which builds an EMatch —
   so this rides the match-lowering path, not a third one. *)
let test_eval_record_pattern_fn_param () =
  let env = eval_module {|mod T do
    fn area({ w: w, h: h }) do w * h end
    fn f() do area({ w: 6, h: 7 }) end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "fn area({w, h})" 42
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* A REFUTABLE sub-pattern inside a record pattern forces the matrix compiler
   to actually dispatch on a projected field rather than just destructure. *)
let test_eval_record_pattern_refutable_field () =
  let env = eval_module {|mod T do
    fn f(r) do
      match r do
        { code: 404, msg: m } -> m
        { code: c, msg: _ }   -> "other " ++ int_to_string(c)
      end
    end
    fn g() do f({ code: 404, msg: "gone" }) end
    fn h() do f({ code: 200, msg: "ok" }) end
  end|} in
  Alcotest.(check string) "404 arm" "gone"
    (match call_fn env "g" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "fallthrough arm" "other 200"
    (match call_fn env "h" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString")
```

Register the group as the first entry of `eval_suites`:

```ocaml
      ( "record_patterns",
        [
          Alcotest.test_case "record pattern in a match arm" `Quick
            test_eval_record_pattern_match;
          Alcotest.test_case "punned record field patterns" `Quick
            test_eval_record_pattern_punned;
          Alcotest.test_case "record pattern in a let binding" `Quick
            test_eval_record_pattern_let;
          Alcotest.test_case "record pattern as a function parameter" `Quick
            test_eval_record_pattern_fn_param;
          Alcotest.test_case "refutable sub-pattern inside a record pattern" `Quick
            test_eval_record_pattern_refutable_field;
        ] );
```

- [ ] **Step 2: Run to verify they fail**

```bash
dune build --root . test/run_eval.exe && ./_build/default/test/run_eval.exe test record_patterns
```

Expected: all FAIL with `I got stuck here` at the `{`.

- [ ] **Step 3: Add the grammar production**

In `lib/parser/parser.mly`, at the top of `simple_pattern` (line 1452), add as the first alternative:

```
simple_pattern:
  (* Record pattern: { x, y: p }.  Field lists are OPEN — a pattern need not
     mention every field of the record it matches (see typecheck's
     expected-type-driven field lookup).  Punned `{ x }` is shorthand for
     `{ x: x }`, mirroring the record-literal shorthand. *)
  | LBRACE; fields = separated_nonempty_list(COMMA, record_field_pat); RBRACE
    { PatRecord (fields, mk_span ($loc)) }
  | UNDERSCORE { PatWild (mk_span ($loc)) }
```

And add `record_field_pat` immediately above the existing `record_field_expr` rule (line 1396):

```
record_field_pat:
  | name = lower_name; COLON; p = pattern { (name, p) }
  | name = lower_name                     { (name, PatVar name) }

record_field_expr:
```

- [ ] **Step 4: Teach the token filter that `{` can start a pattern**

`lookahead_is_new_arm` (`token_filter.ml:200`) is only consulted when `is_pattern_start` returns true for the token after a newline. `LBRACE` is currently absent — deliberately, per `specs/lang/grammar.md` §3.4, because no pattern production began with it. That is no longer true.

In `lib/parser/token_filter.ml:170`, change:

```ocaml
    | Parser.LPAREN | Parser.LBRACKET | Parser.MINUS
```

to:

```ocaml
    | Parser.LPAREN | Parser.LBRACKET | Parser.LBRACE | Parser.MINUS
```

No change is needed inside `lookahead_is_new_arm`: it already tracks `LBRACE`/`RBRACE` depth at `token_filter.ml:233-239`, so `{ x } -> body` sees `ARROW` at depth 0 (new arm) while a record literal `{ x: 1 }` on its own line in an arm body sees `NL` at depth 0 (body continuation).

- [ ] **Step 5: Verify no new grammar conflicts**

```bash
menhir --explain lib/parser/parser.mly -b /tmp/recconf-record-matching-gaps-cf6350 2>&1 | grep -i conflict
```

Expected: still `Warning: 9 states have shift/reduce conflicts.`

- [ ] **Step 6: Run the interpreter tests**

```bash
dune build --root . test/run_eval.exe && ./_build/default/test/run_eval.exe test record_patterns
```

Expected: all PASS. The interpreter's `match_pattern` already handles `PatRecord` (`eval.ml:1178`), and with exact field lists the typechecker's synthesized closed `TRecord` (`typecheck.ml:3544`) unifies fine.

- [ ] **Step 7: Write the failing compiled test**

Create `test/native/record_pattern.march`:

```march
mod RecordPattern do
fn area({ w: w, h: h }) : Int do w * h end

fn classify(r : { code : Int, msg : String }) : String do
  match r do
    { code: 404, msg: m } -> m
    { code: c, msg: _ }   -> "other " ++ int_to_string(c)
  end
end

fn main() : Unit do
  let r = { x: 3, y: 4 }
  match r do
    { x: a, y: b } -> println(int_to_string(a * b))
  end

  let { x: p, y: q } = r
  println(int_to_string(p + q))

  println(int_to_string(area({ w: 6, h: 7 })))
  println(classify({ code: 404, msg: "gone" }))
  println(classify({ code: 200, msg: "ok" }))
end
end
```

Create `test/native/record_pattern.expected`:

```
12
7
42
gone
other 200
```

Add to `test/dune`, after Task 2's `native_as_pattern` diff rule, a rule block identical in shape to Task 2 Step 6's but with every `as_pattern` replaced by `record_pattern` and this comment:

```
; ── Record patterns must compile ─────────────────────────────────────
; PatRecord had no grammar production, so neither lowering path handled it:
; lower_match.ml:205 failed loudly, and lower.ml's bind_subpat catch-all
; returned the body unchanged — SILENTLY dropping every binding, which would
; leave x/y as undefined global fn references.  Covers all three entry points
; (match arm, `let`, fn param) plus a refutable sub-pattern that forces real
; dispatch on a projected field.
```

- [ ] **Step 8: Run to verify it fails**

```bash
dune build --root . @runtest 2>&1 | grep -B 2 -A 6 record_pattern; echo "EXIT=$?"
```

Expected: FAIL with `lower: record patterns are not yet compilable` from `lower_match.ml:206`.

- [ ] **Step 9: Implement record column expansion in the matrix compiler**

A record has no constructor tag, so it cannot be dispatched by `pat_tag_and_subs`. It is irrefutable at the top level: the right move is to **project** each mentioned field into a fresh variable and replace the single record column with one column per field, then recurse. This is the standard treatment and it handles refutable sub-patterns for free, because those sub-patterns end up in ordinary columns.

In `lib/tir/lower_match.ml`, delete the `Ast.PatRecord (_, sp) -> failwith ...` arm at lines 205-211 and replace it with:

```ocaml
  (* Records carry no tag — they are expanded into per-field columns by
     [expand_record_column] before tag dispatch is ever reached, so
     [pat_tag_and_subs] never sees one. *)
```

(that is, remove the arm entirely; `PatRecord` then falls into the final `| Ast.PatWild _ | Ast.PatVar _ | Ast.PatAs _ -> None` arm — so extend that arm's pattern list to include `| Ast.PatRecord _`.)

Add these two functions immediately after `strip_as_column` (added in Task 2):

```ocaml
(** The sorted union of field names mentioned by every [PatRecord] in the
    first column, or [None] if no row has a record pattern there.

    The union (not any single row's list) is what makes every row expand to
    the same arity, which the matrix invariant requires. *)
let record_fields_in_column (rows : (Ast.pattern list * Tir.expr) list)
  : string list option =
  let names =
    List.concat_map (function
      | (Ast.PatRecord (fs, _) :: _, _) ->
        List.map (fun ((n : Ast.name), _) -> n.Ast.txt) fs
      | _ -> []) rows
  in
  if names = [] then None
  else Some (List.sort_uniq String.compare names)

(** Replace a first-column record pattern with one column per field.

    Binds [ELet(f_<name>, EField(scrut, name), …)] around the recursive call
    so each field is projected exactly once and shared by every row.

    Field types matter: a field var left at [Lower_types.unknown_ty] makes
    Perceus treat an unboxed scalar as RC-managed (the same hazard documented
    on [infer_pattern]'s PatWild arm in typecheck.ml).  Prefer the scrutinee's
    own structural [TRecord] type; fall back to the typechecker's recorded
    type for the sub-pattern's span; only then give up and use [unknown_ty]. *)
let rec expand_record_column
    (env         : Lower_state.env)
    (scrut       : Tir.atom)
    (rest_scruts : Tir.atom list)
    (fields      : string list)
    (rows        : (Ast.pattern list * Tir.expr) list)
    (fallback    : Tir.expr option)
  : Tir.expr =
  let scrut_field_ty name =
    match scrut with
    | Tir.AVar { Tir.v_ty = Tir.TRecord fs; _ } -> List.assoc_opt name fs
    | _ -> None
  in
  (* First span the typechecker recorded for a sub-pattern of this field. *)
  let span_field_ty name =
    let rec search = function
      | [] -> None
      | (Ast.PatRecord (fs, _) :: _, _) :: more ->
        (match List.find_opt (fun ((n : Ast.name), _) -> n.Ast.txt = name) fs with
         | Some (_, Ast.PatVar vn)  -> Some (Lower_state.ty_of_span env vn.Ast.span)
         | Some (_, Ast.PatWild sp) -> Some (Lower_state.ty_of_span env sp)
         | _ -> search more)
      | _ :: more -> search more
    in
    search rows
  in
  let field_ty name =
    match scrut_field_ty name with
    | Some t -> t
    | None ->
      (match span_field_ty name with
       | Some t -> t
       | None -> Lower_types.unknown_ty)
  in
  let field_vars =
    List.map (fun name ->
      let v : Tir.var = {
        v_name = Lower_state.fresh_name ("f_" ^ name);
        v_ty   = field_ty name;
        v_lin  = Tir.Unr;
      } in
      (name, v)) fields
  in
  let new_scruts =
    List.map (fun (_, v) -> Tir.AVar v) field_vars @ rest_scruts in
  let expand_row (pats, body) =
    match pats with
    | Ast.PatRecord (fs, _) :: rest ->
      let sub name =
        match List.find_opt (fun ((n : Ast.name), _) -> n.Ast.txt = name) fs with
        | Some (_, p) -> p
        | None -> Ast.PatWild Ast.dummy_span   (* field not mentioned by this row *)
      in
      Some (List.map (fun (name, _) -> sub name) fields @ rest, body)
    | fp :: rest when is_trivial_pat fp ->
      (* A wildcard/var row in a record column matches every record; bind its
         name to the whole record and wildcard out every field column. *)
      let body' = bind_trivial_pat env scrut fp body in
      Some (List.map (fun _ -> Ast.PatWild Ast.dummy_span) fields @ rest, body')
    | _ ->
      (* Unreachable: the column's static type is a record, so no other
         discriminating pattern kind can appear here. *)
      None
  in
  let rows' = List.filter_map expand_row rows in
  let inner = compile_matrix env new_scruts rows' fallback in
  List.fold_right (fun (name, v) acc ->
    Tir.ELet (v, Tir.EField (scrut, name), acc)) field_vars inner
```

`expand_record_column` calls `compile_matrix`, so it must join the existing `let rec compile_matrix … and compile_matrix_impl …` group: change its `let rec` to `and`, and move it below `compile_matrix_impl`. Then wire it in at the top of `compile_matrix_impl`'s `| scrut :: rest_scruts ->` arm, after Task 2's `strip_as_column` line:

```ocaml
    | scrut :: rest_scruts ->
      let rows = strip_as_column env scrut rows in
      (match record_fields_in_column rows with
       | Some fields ->
         expand_record_column env scrut rest_scruts fields rows fallback
       | None ->
      (* … existing body, unchanged, from `let rec split_at_trivial` onward … *)
      )
```

Indent-only change to the existing body; do not otherwise alter it.

- [ ] **Step 10: Implement `let`-binding record destructure**

In `lib/tir/lower.ml`, `bind_subpat` (defined at line 233) currently falls through for records at line 264-267. Replace that catch-all:

```ocaml
         | _ ->
           (* Records / refutable sub-patterns in an irrefutable `let` are not
              decomposed here (unchanged from prior behaviour — a bare `let`
              with such a pattern falls through to the catch-all arm below). *)
           inner
```

with:

```ocaml
         | Ast.PatRecord (fs, _) ->
           (* let { x: a, y: b } = r  →  let a = r.x; let b = r.y; …
              Mirrors the PatTuple arm above: each field gets its concrete
              type so scalar fields are loaded with the right tagging, and
              compound sub-patterns recurse through a fresh intermediate. *)
           let field_ty name =
             match scrut_ty with
             | Tir.TRecord fts ->
               (match List.assoc_opt name fts with
                | Some t -> t
                | None -> unknown_ty)
             | _ -> unknown_ty
           in
           List.fold_right (fun ((n : Ast.name), sub) acc ->
             let fname_txt = n.Ast.txt in
             match sub with
             | Ast.PatWild _ -> acc   (* wildcard field → no binding *)
             | Ast.PatVar vn ->
               let fty =
                 match field_ty fname_txt with
                 | t when t = unknown_ty -> ty_of_span env vn.Ast.span
                 | t -> t
               in
               let fv : Tir.var =
                 { v_name = vn.Ast.txt; v_ty = fty; v_lin = Tir.Lin } in
               Tir.ELet (fv, Tir.EField (scrut, fname_txt), acc)
             | _ ->
               let fty = field_ty fname_txt in
               let tmp = fresh_name "p" in
               let fv : Tir.var =
                 { v_name = tmp; v_ty = fty; v_lin = Tir.Lin } in
               Tir.ELet (fv, Tir.EField (scrut, fname_txt),
                 bind_subpat (Tir.AVar fv) fty sub acc)
           ) fs inner
         | _ ->
           (* Refutable sub-patterns in an irrefutable `let` are still not
              decomposed here — such a `let` is a type error upstream. *)
           inner
```

Then route record patterns into this path. At `lower.ml:209`, change:

```ocaml
     | Ast.PatTuple (_, _) ->
```

to:

```ocaml
     | Ast.PatTuple (_, _) | Ast.PatRecord (_, _) ->
```

The surrounding code binds the RHS to a fresh `$p` var typed by `rhs_tuple_ty` (which is just "the RHS's type" — for a record binding that is the `TRecord`), then calls `bind_subpat`. Rename nothing; the local is misnamed for records but renaming it would balloon the diff. Add a one-line comment noting it now carries the record case too.

- [ ] **Step 11: Run the compiled test**

```bash
dune build --root . @runtest 2>&1 | grep -B 2 -A 6 record_pattern; echo "EXIT=$?"
```

Expected: no diff output, `EXIT=0`. If the `let` line prints a wrong number, the field type fell back to `unknown_ty` — dump the TIR with `MARCH_DUMP_TXT=1` and check whether the scrutinee's type reached lowering as `TRecord` or as a `TCon` naming a record type alias.

- [ ] **Step 12: Move both conformance fixtures**

```bash
git rm specs/lang/grammar/reject/r02_record_pattern_in_arm_unreachable.march specs/lang/grammar/reject/r07_record_pattern_in_let_unreachable.march
```

Create `specs/lang/grammar/parse/p30_record_pattern_in_arm.march`:

```march
mod P30RecordPatternInArm do
  fn main() do
    let r = { x: 1 }
    match r do
      { x } -> x
    end
  end
end
```

Create `specs/lang/grammar/parse/p31_record_pattern_in_let.march`:

```march
mod P31RecordPatternInLet do
  fn main() do
    let r = { x: 1 }
    let { x } = r
    x
  end
end
```

(The originals matched `1` against `{ x }`, which parses but is a type error; `parse/` programs must be well-typed, hence the record scrutinee.)

```bash
dune build --root . bin/main.exe && for f in p30_record_pattern_in_arm p31_record_pattern_in_let; do ./_build/default/bin/main.exe --check specs/lang/grammar/parse/$f.march; echo "$f EXIT=$?"; done
```

Expected: `EXIT=0` for both.

- [ ] **Step 13: Run the grammar corpus**

```bash
dune build --root . @grammar-check; echo "EXIT=$?"
```

Expected: `EXIT=0`.

- [ ] **Step 14: Update the specs**

`specs/lang/grammar/INDEX.md`: delete the `r02` (line 51) and `r07` (line 68) rows; add `p30`/`p31` rows describing them as the former reject fixtures, retired 2026-07-24. Update the header line and line 99.

`specs/lang/grammar.md`: §6.3 was the reachability section for `PatRecord`/`PatAs` — with Task 2 having already retired the `PatAs` half, §6.3 can now be rewritten as a short historical note ("both were unreachable until 2026-07-24; both now have productions — see §6.1/§6.2"). Update §3.4's claim that `LBRACE` is correctly absent from `is_pattern_start`: it is now correctly *present*. Update the cross-references at lines 8, 59, 2395, 2452.

`specs/lang/core-march-types.md`: replace the "No `(P-Record)` rule" block at lines 1008-1019 with an actual `(P-Record)` rule; update the summary at line 904.

`specs/lang/pattern-matching.md`: rewrite the "Record Patterns" section (line 128) — it currently says record patterns are unsupported and recommends field access as a workaround. Document the real syntax, punning, and the open-field-list semantics. Also fix line 453-454's parenthetical claim.

**`docs/pattern-matching.md` (the published page): make the identical two edits.** Its "Record Patterns" section is at line 126-135 and the multi-head-clause parenthetical at line 451-452 — the same stale text as the `specs/lang/` copy. Leaving this one behind means the public site at `/docs/pattern-matching/` still tells users to work around a feature that now exists.

**`docs/types.md:119`**: delete or rewrite the bolded claim "**Record patterns are not yet supported by the parser** (`{ x, y } -> ...` in …)".

`specs/lang/surface-syntax.md` and `.claude/skills/march-lang/SKILL.md`: add record patterns to the quick reference.

`lib/eval/eval.ml:1178` and `:1192`: drop `, unreachable from surface syntax per §4.3.1` from the comments.

Run the doc lint. Note that `specs/lang/grammar/INDEX.md`'s header line asserts the corpus counts (`p01–p28 parse, r01–r15 reject`) and `check-docs.sh` verifies them against the actual file counts — moving two fixtures from `reject/` to `parse/` changes both numbers, so the header must be updated or the lint fails.

```bash
scripts/check-docs.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`.

- [ ] **Step 15: Update CHANGELOG / todos / progress**

`CHANGELOG.md` → `### Added`:

```markdown
- Record patterns: `match r do { x, y: b } -> ... end`, `let { x, y } = r`, and
  `fn area({ w, h })`. `{ x }` is shorthand for `{ x: x }`. Field lists are
  open — a pattern need not mention every field. `PatRecord` had existed in the
  AST and interpreter since the beginning but had no grammar production, and
  neither TIR lowering path handled it.
```

Add matching entries to `specs/todos.md` Done and `specs/progress.md`.

- [ ] **Step 16: Run everything and commit**

```bash
scripts/run-tests.sh && dune build --root . @grammar-check && dune build --root . @types-check && scripts/check-docs.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`.

```bash
git add lib/parser/parser.mly lib/parser/token_filter.ml lib/tir/lower_match.ml lib/tir/lower.ml lib/eval/eval.ml test/test_eval.ml test/dune test/native/record_pattern.march test/native/record_pattern.expected specs/lang/grammar/parse/p30_record_pattern_in_arm.march specs/lang/grammar/parse/p31_record_pattern_in_let.march specs/lang/grammar/INDEX.md specs/lang/grammar.md specs/lang/core-march-types.md specs/lang/pattern-matching.md specs/lang/surface-syntax.md docs/pattern-matching.md docs/types.md .claude/skills/march-lang/SKILL.md CHANGELOG.md specs/todos.md specs/progress.md && git commit -m "feat: record patterns in match arms, let bindings, and fn params"
```

---

### Task 4: Partial record patterns

After Task 3, `{ x }` against a `{x: Int, y: Int}` record is a **type error**: `infer_pattern`'s `PatRecord` arm (`typecheck.ml:3544`) synthesizes a closed `TRecord` from only the mentioned fields, and `unify` (`typecheck.ml:2789`) demands exact field-set equality. That makes record patterns useful only for full destructuring, which `let` already does. This task makes them open.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:3544` (`infer_pattern`'s `PatRecord` arm)
- Test: `test/test_compiler.ml`, `test/test_eval.ml`, `test/native/record_pattern_partial.march` + `.expected`, `test/dune`
- Docs: `specs/lang/pattern-matching.md`, `specs/lang/core-march-types.md`, `CHANGELOG.md`, `specs/todos.md`, `specs/progress.md`

**Interfaces:**
- Consumes: `Ast.PatRecord` nodes produced by Task 3's grammar; `expand_record_column` from Task 3 (no change needed — it already tolerates rows that mention different field subsets, via its `sub name` fallback to `PatWild`).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_compiler.ml`, and register in the `match_diagnostics` group created in Task 1:

```ocaml
(* A record pattern need not mention every field.  infer_pattern used to
   SYNTHESIZE a closed TRecord from the mentioned fields only, and unify
   requires exact field-set equality, so `{ x }` against {x, y} was a type
   error.  Drive the field types from the EXPECTED type instead. *)
let test_partial_record_pattern_typechecks () =
  let ctx = typecheck {|mod T do
    fn f(r : { x : Int, y : Int }) : Int do
      match r do
        { x: a } -> a
      end
    end
  end|} in
  Alcotest.(check bool) "partial record pattern: no errors" false (has_errors ctx)

(* A field the record does not have must still be an error. *)
let test_record_pattern_unknown_field_rejected () =
  let ctx = typecheck {|mod T do
    fn f(r : { x : Int, y : Int }) : Int do
      match r do
        { zzz: a } -> a
      end
    end
  end|} in
  Alcotest.(check bool) "unknown field: error reported" true (has_errors ctx)
```

Add to `test/test_eval.ml`'s `record_patterns` group:

```ocaml
(* Partial record patterns must also RUN, not merely typecheck: the matrix
   compiler projects the union of mentioned fields across rows, so two arms
   mentioning different subsets must both work. *)
let test_eval_record_pattern_partial () =
  let env = eval_module {|mod T do
    fn f(r) do
      match r do
        { code: 404 } -> "gone"
        { msg: m }    -> m
      end
    end
    fn g() do f({ code: 404, msg: "unused" }) end
    fn h() do f({ code: 200, msg: "ok" }) end
  end|} in
  Alcotest.(check string) "first arm matches on code alone" "gone"
    (match call_fn env "g" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "second arm matches on msg alone" "ok"
    (match call_fn env "h" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString")
```

- [ ] **Step 2: Run to verify they fail**

```bash
dune build --root . test/run_compiler.exe test/run_eval.exe && ./_build/default/test/run_compiler.exe test match_diagnostics; ./_build/default/test/run_eval.exe test record_patterns
```

Expected: `test_partial_record_pattern_typechecks` FAILS (type mismatch between the 1-field and 2-field records); `test_record_pattern_unknown_field_rejected` PASSES already (for the wrong reason — a field-set mismatch, not a missing-field diagnostic); `test_eval_record_pattern_partial` FAILS.

- [ ] **Step 3: Make `infer_pattern` expected-type-driven for records**

`infer_pattern` already takes `?expected` (used today only for constructor disambiguation) and `expand_record_tycon` (`typecheck.ml:3152`) already expands a nominal record `TCon` to its structural `TRecord`. Replace the `PatRecord` arm at `typecheck.ml:3544-3552`:

```ocaml
  | Ast.PatRecord (flds, _) ->
    let bindings = ref [] in
    let fld_tys = List.map (fun (name, pat) ->
        let bs, t = infer_pattern env pat in
        bindings := bs @ !bindings;
        (name.Ast.txt, t)
      ) flds
    in
    let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys in
    !bindings, TRecord sorted
```

with:

```ocaml
  | Ast.PatRecord (flds, sp) ->
    (* Record patterns have OPEN field lists: `{ x }` matches any record with
       at least an `x`.  Since [unify] requires exact field-set equality
       (no width subtyping, no row variables), we cannot synthesize the
       pattern's type from the mentioned fields and unify — that rejects every
       partial pattern.  Drive the sub-patterns from the EXPECTED type
       instead, and return the expected type unchanged so the caller's unify
       is a no-op.

       With no expected type available (an unannotated scrutinee whose type is
       still a fresh var), fall back to the old closed-record synthesis: it is
       the only thing that can constrain the scrutinee at all, and it matches
       the pre-existing behaviour for full destructures. *)
    let expected_rec =
      match expected with
      | Some t -> expand_record_tycon env (repr t)
      | None -> None
    in
    (match expected_rec with
     | Some (TRecord expected_flds) ->
       let bindings = ref [] in
       List.iter (fun ((name : Ast.name), pat) ->
         match List.assoc_opt name.Ast.txt expected_flds with
         | Some fty ->
           let bs, pty = infer_pattern ~expected:fty env pat in
           unify env ~span:name.Ast.span ~reason:(Some (RMatchArm sp)) fty pty;
           bindings := bs @ !bindings
         | None ->
           Err.report env.errors
             { Err.severity = Error; span = name.Ast.span;
               message =
                 Printf.sprintf "This record has no field `%s`." name.Ast.txt;
               labels = [];
               notes  =
                 [Printf.sprintf "Available fields: %s"
                    (String.concat ", " (List.map fst expected_flds))];
               code = Some "unknown_record_field";
               fix  = None }
       ) flds;
       !bindings, TRecord expected_flds
     | _ ->
       let bindings = ref [] in
       let fld_tys = List.map (fun ((name : Ast.name), pat) ->
           let bs, t = infer_pattern env pat in
           bindings := bs @ !bindings;
           (name.Ast.txt, t)
         ) flds
       in
       let sorted =
         List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys in
       !bindings, TRecord sorted)
```

The `Err.report` record shape above matches `check_redundant_arms` at `typecheck.ml:4042-4050` verbatim (`severity`, `span`, `message`, `labels`, `notes`, `code`, `fix`). `expand_record_tycon` is at `typecheck.ml:3152` and returns `ty option`, yielding `Some (TRecord …)` for both a structural record and a nominal `TCon` naming one.

- [ ] **Step 4: Thread the expected type through nested record patterns**

`infer_pattern`'s `PatCon` arm already passes `~expected:arg_ty` when recursing into constructor arguments (`typecheck.ml` — the `infer_pattern ~expected:arg_ty env pat` call). The `PatTuple` arm at `typecheck.ml:3410` does **not**:

```ocaml
  | Ast.PatTuple (ps, _) ->
    let bs_tys  = List.map (infer_pattern env) ps in
```

Change it to pass each element's expected type when one is available:

```ocaml
  | Ast.PatTuple (ps, _) ->
    (* Thread per-element expected types so a nested record pattern inside a
       tuple pattern — which is what desugar builds for multi-param fns —
       still gets an expected type to open its field list against. *)
    let elem_expected =
      match expected with
      | Some t -> (match repr t with TTuple ts -> ts | _ -> [])
      | None -> []
    in
    let bs_tys =
      List.mapi (fun i p ->
        match List.nth_opt elem_expected i with
        | Some et -> infer_pattern ~expected:et env p
        | None    -> infer_pattern env p) ps
    in
```

This matters because `fn area({ w })` desugars to a match on a 1-tuple/scrutinee; without it, a partial record pattern in a function parameter falls into the closed-synthesis fallback.

- [ ] **Step 5: Run the tests**

```bash
dune build --root . test/run_compiler.exe test/run_eval.exe && ./_build/default/test/run_compiler.exe test match_diagnostics; ./_build/default/test/run_eval.exe test record_patterns
```

Expected: all PASS, and `test_record_pattern_unknown_field_rejected` now fails for the *right* reason (an `unknown_record_field` diagnostic).

- [ ] **Step 6: Add the compiled golden**

Create `test/native/record_pattern_partial.march`:

```march
mod RecordPatternPartial do
fn classify(r : { code : Int, msg : String }) : String do
  match r do
    { code: 404 } -> "gone"
    { msg: m }    -> m
  end
end

fn width({ w: w }) : Int do w end

fn main() : Unit do
  println(classify({ code: 404, msg: "unused" }))
  println(classify({ code: 200, msg: "ok" }))
  println(int_to_string(width({ w: 8, h: 9 })))
end
end
```

Create `test/native/record_pattern_partial.expected`:

```
gone
ok
8
```

Add a `native_record_pattern_partial` rule pair to `test/dune`, same shape as Task 3 Step 7's, with this comment:

```
; ── Partial record patterns must compile ─────────────────────────────
; Two arms mentioning DIFFERENT field subsets force expand_record_column to
; project the union of mentioned fields and wildcard the ones a given row
; omits.  `width({ w })` additionally checks that the expected type reaches a
; record pattern nested inside the param tuple desugar builds.
```

```bash
dune build --root . @runtest 2>&1 | grep -B 2 -A 6 record_pattern_partial; echo "EXIT=$?"
```

Expected: no diff output, `EXIT=0`.

- [ ] **Step 7: Update docs**

`specs/lang/pattern-matching.md` **and `docs/pattern-matching.md`** (both copies — the second is the published page at `/docs/pattern-matching/`): in the "Record Patterns" section written in Task 3, document that field lists are open, that an unmentioned field is simply not bound, and that a field the record does not have is a compile error (`unknown_record_field`).

`specs/lang/core-march-types.md`: extend the `(P-Record)` rule added in Task 3 to state the open-field-list semantics and that the pattern's type is the *expected* record type, not a synthesized one.

`CHANGELOG.md` → `### Added`:

```markdown
- Record patterns may mention a subset of a record's fields: `{ code: 404 }`
  matches any record with a `code` field equal to 404, whatever else it has.
  Naming a field the record does not have is a compile error.
```

Add matching `specs/todos.md` / `specs/progress.md` entries.

- [ ] **Step 8: Run everything and commit**

```bash
scripts/run-tests.sh && dune build --root . @types-check && dune build --root . @grammar-check && scripts/check-docs.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`.

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml test/test_eval.ml test/dune test/native/record_pattern_partial.march test/native/record_pattern_partial.expected specs/lang/pattern-matching.md specs/lang/core-march-types.md docs/pattern-matching.md CHANGELOG.md specs/todos.md specs/progress.md && git commit -m "feat(typecheck): open field lists in record patterns"
```

---

### Task 5: Or-patterns (`p1 | p2`), non-binding alternatives

The only gap needing a new AST node. Alternatives that bind variables are rejected with a clear diagnostic — see the Design Decisions section for why.

**Files:**
- Modify: `lib/ast/ast.ml:48` (add `PatOr`)
- Modify: `lib/parser/parser.mly` (`pattern_no_as` gains the or layer)
- Modify: `lib/typecheck/typecheck.ml` (`infer_pattern`, `norm_pat` → row expansion, `span_of_pat`, `collect_pattern_vars`, `free_vars_pattern`, the ctor-owner walker at line 7728)
- Modify: `lib/eval/eval.ml` (`match_pattern`)
- Modify: `lib/tir/lower_match.ml` (`span_of_pat`, `collect_pat_names`, row splitting, body hoisting)
- Modify (mechanical, one arm each): `lib/ast/span_remap.ml`, `lib/desugar/desugar.ml`, `lib/dump/ast_json.ml`, `lib/format/format.ml`, `lib/refactor/refactor.ml`, `lib/refinecheck/refine_check.ml`, `lsp/lib/analysis.ml`, `lsp/lib/workspace.ml`
- Test: `test/test_eval.ml`, `test/test_compiler.ml`, `test/native/or_pattern.march` + `.expected`, `test/dune`, `specs/lang/grammar/parse/p32_or_pattern.march`, `specs/lang/grammar/reject/r16_or_pattern_binding_rejected.march`
- Docs: the full set

**Interfaces:**
- Consumes: `pattern_no_as` from Task 2 — the or layer is inserted *beneath* the as layer so `1 | 2 as n` parses as `(1 | 2) as n`.
- Produces: `Ast.PatOr of pattern list * span`.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_eval.ml` above `eval_suites`:

```ocaml
(* Or-patterns: alternatives separated by `|` in a single arm. *)
let test_eval_or_pattern_literals () =
  let env = eval_module {|mod T do
    fn f(n) do
      match n do
        1 | 2 | 3 -> "small"
        _         -> "big"
      end
    end
  end|} in
  Alcotest.(check string) "1 -> small" "small"
    (match call_fn env "f" [March_eval.Eval.VInt 1] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "3 -> small" "small"
    (match call_fn env "f" [March_eval.Eval.VInt 3] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "9 -> big" "big"
    (match call_fn env "f" [March_eval.Eval.VInt 9] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

let test_eval_or_pattern_nullary_ctors () =
  let env = eval_module {|mod T do
    type Color = Red | Green | Blue
    fn warm(c) do
      match c do
        Red | Green -> true
        Blue        -> false
      end
    end
  end|} in
  Alcotest.(check bool) "Red is warm" true
    (match call_fn env "warm" [March_eval.Eval.VCon ("Red", [])] with
     | March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool");
  Alcotest.(check bool) "Blue is not warm" false
    (match call_fn env "warm" [March_eval.Eval.VCon ("Blue", [])] with
     | March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool")
```

Register as an `or_patterns` group at the head of `eval_suites`.

Add to `test/test_compiler.ml`, registered in the `match_diagnostics` group:

```ocaml
(* Or-pattern alternatives may not bind variables in this pass: sharing an arm
   body across alternatives uses lower_match's 0-arg join point, which cannot
   pass per-alternative bindings.  The rejection must be a clear diagnostic,
   not a lowering crash. *)
let test_or_pattern_binding_rejected () =
  let ctx = typecheck {|mod T do
    type E = A(Int) | B(Int)
    fn f(e : E) : Int do
      match e do
        A(x) | B(x) -> x
      end
    end
  end|} in
  Alcotest.(check bool) "binding or-pattern rejected" true (has_errors ctx)

let test_or_pattern_nonbinding_accepted () =
  let ctx = typecheck {|mod T do
    fn f(n : Int) : String do
      match n do
        1 | 2 -> "small"
        _     -> "big"
      end
    end
  end|} in
  Alcotest.(check bool) "non-binding or-pattern accepted" false (has_errors ctx)

(* Exhaustiveness must see THROUGH an or-pattern: `Red | Green` plus `Blue`
   covers Color, so no warning; dropping `Blue` must warn. *)
let test_or_pattern_exhaustiveness () =
  let ctx_full = typecheck {|mod T do
    type Color = Red | Green | Blue
    fn f(c : Color) : Int do
      match c do
        Red | Green -> 1
        Blue        -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "or-pattern covers its alternatives" false
    (has_errors ctx_full);
  let ctx_partial = typecheck {|mod T do
    type Color = Red | Green | Blue
    fn f(c : Color) : Int do
      match c do
        Red | Green -> 1
      end
    end
  end|} in
  let missing_blue =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.severity = March_errors.Errors.Warning)
      (March_errors.Errors.diagnostics ctx_partial)
  in
  Alcotest.(check bool) "missing Blue still warns" true missing_blue
```

Adjust the diagnostics accessor to whatever Task 1 Step 2 established.

- [ ] **Step 2: Run to verify they fail**

```bash
dune build --root . test/run_eval.exe test/run_compiler.exe && ./_build/default/test/run_eval.exe test or_patterns; ./_build/default/test/run_compiler.exe test match_diagnostics
```

Expected: the or-pattern cases FAIL with ``I was expecting `->` in the match arm here``.

- [ ] **Step 3: Add the AST constructor**

In `lib/ast/ast.ml`, after line 48:

```ocaml
  | PatAs of pattern * name * span    (** As pattern: pat as name *)
  | PatOr of pattern list * span      (** Or pattern: p1 | p2 | p3 *)
```

- [ ] **Step 4: Build and let the compiler enumerate every site that must change**

```bash
dune build --root . 2>&1 | grep -E "^File|not exhaustive|PatOr" | head -60
```

Expected: a list of non-exhaustive `match` warnings-as-errors across `lib/ast/span_remap.ml`, `lib/desugar/desugar.ml`, `lib/dump/ast_json.ml`, `lib/format/format.ml`, `lib/refactor/refactor.ml`, `lib/refinecheck/refine_check.ml`, `lib/typecheck/typecheck.ml`, `lib/tir/lower_match.ml`, `lib/eval/eval.ml`, `lsp/lib/analysis.ml`, `lsp/lib/workspace.ml`. Work the list top to bottom. Each is a one-liner that mirrors the neighbouring `PatTuple` arm — recurse into the sub-pattern list. For example, in `lib/ast/span_remap.ml` after line 81:

```ocaml
  | Ast.PatOr (ps, sp) ->
    Ast.PatOr (List.map (remap_pattern tbl) ps, remap_span tbl sp)
```

in `lib/format/format.ml` after line 248, printing alternatives joined by `" | "`; in `lib/dump/ast_json.ml` after line 272, emitting `("kind", Dump.json_string "PatOr")` with a `patterns` array; and so on. Do not stub any of them with `_ -> ()`; the point of the new constructor is that every walker sees it.

- [ ] **Step 5: Add the grammar production**

In `lib/parser/parser.mly`, restructure Task 2's `pattern_no_as` to add an or layer beneath it:

```
pattern_no_as:
  (* Or-patterns: `1 | 2 | 3`.  PIPE is also `arm_sep` (parser.mly:1407), but
     an arm separator only ever follows a COMPLETE branch — one that has
     already consumed its ARROW and body — so LR(1) distinguishes the two uses
     without a conflict.  Verified: adding this production leaves menhir's
     conflict count unchanged at 9. *)
  | p = pattern_alt; PIPE; ps = separated_nonempty_list(PIPE, pattern_alt)
    { PatOr (p :: ps, mk_span ($loc)) }
  | p = pattern_alt { p }

pattern_alt:
  | con = qualified_upper; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatCon (con, ps) }
```

The remaining alternatives that Task 2 left under `pattern_no_as` (nullary `qualified_upper`, both `ATOM` forms, `simple_pattern`) move down to `pattern_alt`.

- [ ] **Step 6: Verify no new conflicts**

```bash
menhir --explain lib/parser/parser.mly -b /tmp/orconf-record-matching-gaps-cf6350 2>&1 | grep -i conflict
```

Expected: still `Warning: 9 states have shift/reduce conflicts.` Stop if it rose.

- [ ] **Step 7: Implement typechecking**

In `lib/typecheck/typecheck.ml`'s `infer_pattern`, add before the `PatAs` arm:

```ocaml
  | Ast.PatOr (alts, sp) ->
    (* Every alternative must have the same type.  Bindings are rejected: the
       arm body is shared across alternatives via a 0-arg join point in
       lowering, which has nowhere to put per-alternative bindings. *)
    let results = List.map (fun p -> (p, infer_pattern ?expected env p)) alts in
    (match results with
     | [] -> [], fresh_var env.level
     | (_, (_, t0)) :: rest ->
       List.iter (fun (_, (_, t)) ->
         unify env ~span:sp ~reason:(Some (RMatchArm sp)) t0 t) rest;
       let binders =
         List.concat_map (fun (p, (bs, _)) ->
           List.map (fun (n, _) -> (n, span_of_pat p)) bs) results
       in
       (match binders with
        | [] -> ()
        | (n, bsp) :: _ ->
          Err.report env.errors
            { Err.severity = Error; span = bsp;
              message =
                Printf.sprintf
                  "Or-pattern alternatives cannot bind variables (`%s`)." n;
              labels = [];
              notes  =
                ["Every alternative of `p1 | p2` shares one arm body, so a \
                  name bound in one alternative would be undefined when \
                  another matches.";
                 "Split this into separate arms, or match the common shape \
                  and test the difference in a `when` guard."];
              code = Some "or_pattern_binding";
              fix  = None });
       [], t0)
```

Copy the exact `Err.report` field set from a neighbouring call site (e.g. `typecheck.ml:4042`) rather than trusting the shape above.

Add the mechanical arms the build flagged in Step 4: `span_of_pat` (`typecheck.ml:3957`) → `| Ast.PatOr (_, sp) -> sp`; `collect_pattern_vars` (`typecheck.ml:9525`) and `free_vars_pattern` (`typecheck.ml:5888`) → union over alternatives; the ctor-owner walker (`typecheck.ml:7728`) → `| Ast.PatOr (ps, _) -> List.iter pat ps`.

- [ ] **Step 8: Make exhaustiveness and redundancy see through or-patterns**

`norm_pat` (`typecheck.ml:3619`) returns a single `spat`, but an or-pattern is genuinely several rows. Add a row-expanding wrapper immediately after `norm_pat`:

```ocaml
(** Expand a pattern into the set of [spat] rows it covers.  An or-pattern
    contributes one row per alternative; every other pattern contributes
    exactly one.  Nested or-patterns (inside a constructor argument or tuple
    element) are normalised to [SPWild] by [norm_pat] — conservative, so
    coverage is under-reported rather than over-reported. *)
let norm_pat_rows (p : Ast.pattern) : spat list =
  match p with
  | Ast.PatOr (alts, _) -> List.map norm_pat alts
  | _ -> [norm_pat p]
```

Add `| Ast.PatOr _ -> SPWild` to `norm_pat` itself (next to the existing `| Ast.PatRecord _ -> SPWild   (* conservative *)`), with the same "conservative" comment.

Then in `check_exhaustiveness` (`typecheck.ml:4071`), change both matrix constructions from `[norm_pat br.branch_pat]` to a flat-mapped expansion:

```ocaml
    let guardless_matrix =
      List.concat_map
        (fun (br : Ast.branch) ->
          match br.branch_guard with
          | None   -> List.map (fun r -> [r]) (norm_pat_rows br.branch_pat)
          | Some _ -> [])
        branches
    in
```

and

```ocaml
    let matrix =
      List.concat_map
        (fun (br : Ast.branch) ->
          List.map (fun r -> [r]) (norm_pat_rows br.branch_pat))
        branches
    in
```

In `check_redundant_arms` (`typecheck.ml:4034`), an arm is redundant only if *every* alternative is subsumed:

```ocaml
    let arm_rows = List.map (fun r -> [r]) (norm_pat_rows br.branch_pat) in
    if br.branch_guard = None then begin
      if not (List.exists (fun row -> is_useful env [scrut_ty] !prefix row) arm_rows)
      then begin
        (* … existing warning body, unchanged … *)
      end;
      prefix := !prefix @ arm_rows
    end
```

- [ ] **Step 9: Implement interpreter matching**

In `lib/eval/eval.ml`'s `match_pattern`, add before the `PatAs` arm at line 1193:

```ocaml
  | PatOr (alts, _), _ ->  (* match(PatOr) — §4.3, first matching alternative wins *)
    let rec try_alts = function
      | [] -> None
      | p :: rest ->
        (match match_pattern v p with
         | Some bs -> Some bs
         | None -> try_alts rest)
    in
    try_alts alts
```

- [ ] **Step 10: Run the interpreter and typecheck tests**

```bash
dune build --root . test/run_eval.exe test/run_compiler.exe && ./_build/default/test/run_eval.exe test or_patterns; ./_build/default/test/run_compiler.exe test match_diagnostics
```

Expected: all PASS.

- [ ] **Step 11: Write the failing compiled test**

Create `test/native/or_pattern.march`:

```march
mod OrPattern do
type Color = Red | Green | Blue

fn size(n : Int) : String do
  match n do
    1 | 2 | 3 -> "small"
    _         -> "big"
  end
end

fn warm(c : Color) : Bool do
  match c do
    Red | Green -> true
    Blue        -> false
  end
end

fn main() : Unit do
  println(size(1))
  println(size(3))
  println(size(9))
  println(bool_to_string(warm(Red)))
  println(bool_to_string(warm(Blue)))
end
end
```

Create `test/native/or_pattern.expected`:

```
small
small
big
true
false
```

Add a `native_or_pattern` rule pair to `test/dune` in the same shape as Task 2 Step 6's, with this comment:

```
; ── Or-patterns must compile ─────────────────────────────────────────
; compile_matrix splits a row whose first column is a PatOr into one row per
; alternative.  The arm body is hoisted into a shared 0-arg join point first,
; so N alternatives do not emit N copies of the body — the same blowup
; hoist_fallback_jp exists to prevent for fallbacks.
```

```bash
dune build --root . @runtest 2>&1 | grep -B 2 -A 6 or_pattern; echo "EXIT=$?"
```

Expected: FAIL with `lower: unhandled pattern kind in match compilation at …`.

- [ ] **Step 12: Implement lowering**

In `lib/tir/lower_match.ml`:

Add `| Ast.PatOr (_, sp) -> sp` to `span_of_pat` (line 79 area) and
`| Ast.PatOr (ps, _) -> List.concat_map collect_pat_names ps` to `collect_pat_names` (line 505 area). Add `| Ast.PatOr _` to `pat_tag_and_subs`'s final `-> None` arm — or-patterns are split before tag dispatch, so it never sees one.

Add the row splitter next to `strip_as_column`:

```ocaml
(** Split a row whose first column is an or-pattern into one row per
    alternative.  Alternatives bind no variables (enforced at typecheck), so
    the rows can share one body expression. *)
let expand_or_rows (rows : (Ast.pattern list * Tir.expr) list)
  : (Ast.pattern list * Tir.expr) list =
  List.concat_map (fun (pats, body) ->
    match pats with
    | Ast.PatOr (alts, _) :: rest ->
      List.map (fun a -> (a :: rest, body)) alts
    | _ -> [(pats, body)]) rows
```

Call it in `compile_matrix_impl`'s `| scrut :: rest_scruts ->` arm, before `strip_as_column`:

```ocaml
    | scrut :: rest_scruts ->
      let rows = expand_or_rows rows in
      let rows = strip_as_column env scrut rows in
```

Then share the body. In `lower_match`'s no-guard fast path (`lower_match.ml:532-536`), an arm whose pattern contains an or would otherwise have its lowered body duplicated once per alternative. Hoist it:

```ocaml
    (* An or-pattern's arm body is referenced once per alternative after
       [expand_or_rows] splits the row.  Hoist it into a shared 0-arg join
       point first (alternatives bind no variables, so nothing needs to be
       passed) rather than emitting N copies. *)
    let rec pat_has_or : Ast.pattern -> bool = function
      | Ast.PatOr _ -> true
      | Ast.PatAs (p, _, _) -> pat_has_or p
      | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) ->
        List.exists pat_has_or ps
      | Ast.PatRecord (fs, _) -> List.exists (fun (_, p) -> pat_has_or p) fs
      | Ast.PatWild _ | Ast.PatVar _ | Ast.PatLit _ -> false
    in
    let wraps = ref [] in
    let rows = List.map (fun (br : Ast.branch) ->
        let body = lower_branch_body_with_pat env br.branch_pat br.branch_body in
        if pat_has_or br.branch_pat then begin
          let (clo_var, lambda_expr) = hoist_fallback_jp body in
          wraps := (clo_var, lambda_expr) :: !wraps;
          ([br.branch_pat], Tir.EApp (clo_var, []))
        end else ([br.branch_pat], body)) branches in
    let tree = compile_matrix env [scrut] rows None in
    List.fold_left (fun acc (clo_var, lambda_expr) ->
      Tir.ELet (clo_var, lambda_expr, acc)) tree !wraps
```

replacing the existing `let rows = … in compile_matrix env [scrut] rows None`.

The guarded path (`lower_match.ml:560` onward) calls `compile_matrix_impl` per arm; `expand_or_rows` runs inside it, and each arm's `body` is already a single lowered expression shared by every split row. Apply the same hoist there by wrapping `body` when `pat_has_or br.branch_pat`, immediately after `let body = lower_expr env br.branch_body in` at `lower_match.ml:574`.

- [ ] **Step 13: Run the compiled test**

```bash
dune build --root . @runtest 2>&1 | grep -B 2 -A 6 or_pattern; echo "EXIT=$?"
```

Expected: no diff output, `EXIT=0`.

- [ ] **Step 14: Add conformance fixtures**

Create `specs/lang/grammar/parse/p32_or_pattern.march`:

```march
mod P32OrPattern do
  fn main() do
    match 1 do
      1 | 2 -> 10
      _     -> 0
    end
  end
end
```

The binding-rejection fixture belongs in the **types** corpus, not the grammar one: `specs/lang/grammar/reject/` pins *parse* diagnostics only (`specs/lang/grammar/INDEX.md` forbids type errors there), and `A(x) | B(x)` parses fine — it fails to typecheck. `specs/lang/types/{accept,reject}/` is the right home; its fixtures are named `t<NN>_<name>.march` and reject fixtures carry a `-- EXPECT-ERROR: <substring>` first line. The highest existing number is `t81`, so create `specs/lang/types/reject/t82_or_pattern_binding.march`:

```march
-- EXPECT-ERROR: Or-pattern alternatives cannot bind variables
mod M do
  type E = A(Int) | B(Int)
  fn f(e : E) : Int do
    match e do
      A(x) | B(x) -> x
    end
  end
  fn main() do () end
end
```

Add its row to `specs/lang/types/INDEX.md` following that file's existing table format.

```bash
dune build --root . bin/main.exe && ./_build/default/bin/main.exe --check specs/lang/grammar/parse/p32_or_pattern.march; echo "EXIT=$?"
dune build --root . @grammar-check && dune build --root . @types-check; echo "EXIT=$?"
```

Expected: `EXIT=0` throughout.

- [ ] **Step 15: Update docs**

`specs/lang/pattern-matching.md` **and `docs/pattern-matching.md`** (both copies): add an "Or Patterns" section — syntax, the first-match-wins semantics, and the no-bindings restriction with the recommended workarounds (separate arms, or a guard).

`specs/lang/core-march-types.md`: add a `(P-Or)` rule alongside `(P-Record)`/`(P-As)`.

`specs/lang/grammar.md`: document the `pattern` → `pattern_no_as` → `pattern_alt` layering and record the finding that `PIPE` serves double duty as `arm_sep` and or-separator without conflict, since a future reader will otherwise assume it must.

`specs/lang/grammar/INDEX.md`: add the `p32` row (and `r16`, if it landed in this corpus).

`specs/lang/surface-syntax.md`, `.claude/skills/march-lang/SKILL.md`: add or-patterns to the quick reference, including the no-bindings restriction.

`CHANGELOG.md` → `### Added`:

```markdown
- Or-patterns: `1 | 2 | 3 -> "small"` matches an arm against several
  alternatives. Alternatives may not bind variables — every alternative shares
  one arm body, so a name bound in one would be undefined when another
  matches; use separate arms or a `when` guard instead.
```

Add matching `specs/todos.md` / `specs/progress.md` entries, and file the follow-up in `specs/todos.md`:

```markdown
- **Or-patterns with bindings** — `A(x) | B(x) -> x` is rejected today because
  `lower_match.ml` shares an or-arm's body through the 0-arg join point built
  by `hoist_fallback_jp`, which cannot pass per-alternative bindings. Lifting
  the restriction means n-ary join points: hoist the body as a function of the
  bound variables and have each split row call it with its own bindings.
```

- [ ] **Step 16: Run everything and commit**

```bash
scripts/run-tests.sh && dune build --root . @grammar-check && dune build --root . @types-check && scripts/check-docs.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`.

Then run the benchmarks that exercise pattern-heavy lowering, per `CLAUDE.md`'s post-change rule — compiled, never interpreted:

```bash
./_build/default/bin/main.exe --compile --opt 2 bench/tree_transform.march -o /tmp/tree_transform-record-matching-gaps-cf6350 && /tmp/tree_transform-record-matching-gaps-cf6350
```

```bash
./_build/default/bin/main.exe --compile --opt 2 bench/list_ops.march -o /tmp/list_ops-record-matching-gaps-cf6350 && /tmp/list_ops-record-matching-gaps-cf6350
```

Compare wall-clock against `specs/benchmarks.md`'s recorded figures; a regression means `expand_or_rows`/`strip_as_column` is running on hot paths it should be a no-op for (both should return the input list unchanged when no or/as pattern is present — verify they do).

```bash
git add lib/ast/ast.ml lib/parser/parser.mly lib/typecheck/typecheck.ml lib/eval/eval.ml lib/tir/lower_match.ml lib/ast/span_remap.ml lib/desugar/desugar.ml lib/dump/ast_json.ml lib/format/format.ml lib/refactor/refactor.ml lib/refinecheck/refine_check.ml lsp/lib/analysis.ml lsp/lib/workspace.ml test/test_eval.ml test/test_compiler.ml test/dune test/native/or_pattern.march test/native/or_pattern.expected specs/lang/grammar/parse/p32_or_pattern.march specs/lang/types/reject/t82_or_pattern_binding.march specs/lang/types/INDEX.md specs/lang/grammar/INDEX.md specs/lang/grammar.md specs/lang/core-march-types.md specs/lang/pattern-matching.md specs/lang/surface-syntax.md docs/pattern-matching.md .claude/skills/march-lang/SKILL.md CHANGELOG.md specs/todos.md specs/progress.md && git commit -m "feat: or-patterns (p1 | p2) with non-binding alternatives"
```

---

## Not in scope

Deliberately excluded, with reasons:

- **Guards.** Already work end-to-end. Verified.
- **Guarded matches suppressing the non-exhaustive warning.** A documented policy decision (`typecheck.ml:4056`), not a bug: coverage is computed over guardless branches and the span is recorded so `cap no_panic` modules reject it. Revisiting it is a separate conversation about defaults.
- **Nested exhaustiveness through record patterns.** `norm_pat` maps `PatRecord` to `SPWild`, so `{ code: 404 }` contributes nothing to coverage analysis. Safe (under-reports rather than over-reports) and orthogonal to everything here.
- **Or-patterns that bind variables.** Filed as a follow-up in Task 5 Step 15.
- **Range patterns (`1..5`) and string-prefix patterns.** Neither exists anywhere in the AST or grammar; both are new language features rather than gaps between an implemented AST node and the parser.
