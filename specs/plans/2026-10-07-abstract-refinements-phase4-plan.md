# Abstract Refinements Phase 4 Implementation Plan (the `a[p]` / `Bool[p]` shorthand)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** let users write `filter(xs : List(a), pred : a -> Bool[p]) : List(a[p])` instead of the spelled-out phase-1 form `pred : ({x : a | true}) -> {Bool | _ == p(x)}` and `List({a | p(_)})`. The shorthand must mean *exactly* the spelled-out form. The checker, typechecker and tooling see the same AST they see today.

**Architecture:** this is a pure parser desugaring. Two cases:
- **`T[p]`** is a postfix on a type atom. It parses to `TyRefine (T, Some "_", p(_))`.
  - The binder `Some "_"` is an **unforgeable marker**: users cannot write `{_ : T | …}`; it's a syntax error today (probe u).
  - It means the same as `{T | p(_)}`, because `binder_name (Some "_") = "_"`.
  - It lets `show_ty` print the shorthand back.
- **An arrow whose codomain is the marked `Bool[p]`** is rewritten in the `ty ARROW ty` action to the definer form `({$x : D | true}) -> {Bool | _ == p($x)}`. If the domain already names a binder, that binder is reused.

Phase 4 also removes the type parse from two error-only rules (`let? x : T`, `let* x : T`). That rule is what made the postfix conflict, and taking it out lowers the menhir conflict count from **11 to 7**.

**Tech Stack:** menhir (via dune, `--explain`), OCaml 5.3, tree-sitter CLI **0.26.7** (installed at `/opt/homebrew/bin/tree-sitter`; CI requires this exact version), z3.

**Prerequisite:** phase 3, [march-language/march#863](https://github.com/march-language/march/pull/863), merged (its four stdlib signatures are migrated in D6). Branch `claude/abstract-refinements-phase4` from `origin/main` after it merges.

## Global Constraints

- **Conflict count is a ratchet.** Measure with `menhir --explain lib/parser/parser.mly` run on a scratch copy; its `Warning: N shift/reduce conflicts` line is the number. Today it is **11** (the design doc's "9" is stale). After D1 it is **7**, and D2/D3 must keep it at **7**. Any rise is a STOP.
- **Tree-sitter rule (CLAUDE.md):** a PR changing `parser.mly` extends `tree-sitter-march/grammar.js` (preferred, D5) or lists its fixtures in `known-failures.txt`. Regenerate with tree-sitter **0.26.7** under a private `HOME`, and commit `src/parser.c`, `src/grammar.json` and `src/node-types.json`. `scripts/check-tree-sitter.sh` must pass. No new keyword is involved (`[`/`]` are punctuation).
- **Pure sugar:** after the stdlib migration (D6), the refinement oracle and the audit baselines must be **byte-identical** to before. That's the equivalence proof, and any diff is a STOP.
- Build with `--root .`; restage the stdlib before CLI probes (`dune build --root . bin/main.exe $(ls stdlib/*.march | tr '\n' ' ')`); use a fresh private `HOME`; capture an exit code immediately (`cmd; e=$?`).
- Keywords to avoid as probe names: `use`, `loop`, `init`, `within`, `app`, `opaque`.
- Every new rule gets a fixture that fails without it, shown by a one-line perturbation. Stage files by name; no attribution lines. Language reference: edit `specs/lang/`, run `scripts/gen-lang-docs.py`, commit both.

## Pressure test (2026-10-07, `origin/main` `d9fbbf179`)

| # | Probe | Result |
|---|---|---|
| m0 | `menhir --explain` on today's `parser.mly` | **11** conflicts |
| m1 | add `ty_post := ty_atom \| ty_atom "[" lower_name "]"` | **13**: both new conflicts on `LBRACKET` after `LET (STAR\|QUESTION) simple_pattern COLON ty_atom` |
| m2 | those two rules are **error-only** ("a `let*`/`let?` binding can't have a type annotation"); make them stop at the `:` instead of parsing a type | **7** with the postfix; **7** without it. The fix alone removes 4 pre-existing conflicts, and the postfix adds **0**. |
| e1 | where the error caret lands for `let? x : Int = …` (`test/errors/parse_error_2/9/10`) | already at the `:` (`type_annot` starts with `COLON`), so `$startpos($4)` should keep every `.expected` identical. D1 verifies this. |
| t1 | tree-sitter: add `abstract_refinement_type: prec(2, seq(base, '[', identifier, ']'))` to `_type_atom` | `tree-sitter generate` OK (its "unnecessary conflicts" warning is pre-existing); corpus 69/69; a sugar file parses with 2 `abstract_refinement_type` nodes and 0 ERROR, including a `[1, 2]` list literal on the next line |
| u | `{_ : Int \| _ > 0}` written by a user | `I got stuck here`, so `Some "_"` is an unforgeable marker |
| s | `show_ty` (`lib/ast/ast.ml:524`) prints `TyRefine (b, Some v, _)` as `{ v : T \| ... }` | D4 adds an arm printing the marker as `T[p]` |

**Behaviour decided here** (each has a test):
- `T[p]` anywhere is element/value sugar `{T | p(_)}`. That includes `Bool[p]` outside an arrow codomain, e.g. `List(Bool[p])`.
- `D -> Bool[p]`, where `D` is not a tuple, is the definer `({x : D | true}) -> {Bool | _ == p(x)}`. If `D` is `{y : E | q}`, its binder `y` is reused. If `D` is `{E | q}` with the `_` binder, the parser rejects it, telling the user to name the binder. A tuple domain `(A, B) -> Bool[p]` is rejected ("a one-argument callback"), as are `T[]` and `T[p, q]`.
- Curried `a -> b -> Bool[p]` rewrites the *inner* arrow only. Nothing instantiates it (a curried callback is not modelled), and it never proves anything. A test pins that it is safe.

## File map

| File | Change |
|---|---|
| `lib/parser/parser.mly` | D1: the two error rules; D2: `ty_post`; D3: the arrow action plus header helpers; conflict-count comments |
| `lib/ast/ast.ml` | D4: `show_ty` arm |
| `tree-sitter-march/grammar.js`, `src/{parser.c,grammar.json,node-types.json}`, `test/corpus/types.txt` | D5 |
| `test/test_refinecheck.ml` | D2–D4: suite `abstract-sugar` |
| `specs/lang/grammar/{parse,reject}/` + `INDEX.md`, `specs/lang/grammar.md` | grammar corpus and reference |
| `specs/lang/types/{accept,reject}/` + `INDEX.md` | a sugar conformance pair |
| `stdlib/list.march`, `stdlib/option.march` | D6: the four signatures |
| `specs/lang/refinement-types.md` (+ `docs/`), design doc, progress, CHANGELOG | D7 |

Test command: `dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test abstract-sugar`

---

### Task D0: Baselines

- [ ] **Step 1:** Record everything D6 compares against, plus the conflict count:

```bash
SCRATCH=/private/tmp/$(basename $PWD)-ar4; mkdir -p $SCRATCH
dune build --root . bin/main.exe $(ls stdlib/*.march | tr '\n' ' ')
scripts/refine-oracle.sh baseline $SCRATCH/oracle
cp test/refine_audit/corpus.baseline test/refine_audit/holes.baseline $SCRATCH/
mkdir -p $SCRATCH/mh && cp lib/parser/parser.mly $SCRATCH/mh/ && (cd $SCRATCH/mh && menhir --explain parser.mly 2>&1 | grep 'conflicts were')
```
Expected: `Warning: 11 shift/reduce conflicts were arbitrarily resolved.` Write a small helper you'll reuse after every grammar edit:

```bash
conflicts() { mkdir -p $SCRATCH/mh && cp lib/parser/parser.mly $SCRATCH/mh/ && (cd $SCRATCH/mh && menhir --explain parser.mly 2>&1 | sed -n 's/^Warning: \([0-9]*\) shift\/reduce conflicts were.*/\1/p'); }
```

### Task D1: The `let?` / `let*` annotation errors stop at the `:` (11 → 7 conflicts)

**Files:** `lib/parser/parser.mly`, the two productions at about lines 1507 and 1516.

- [ ] **Step 1:** Replace

```ocaml
  | LET; QUESTION; _p = simple_pattern; ty = type_annot; _e = preceded(EQUALS, expr)?
    { let _ = ty in
      error_raise … $startpos(ty) }
```
with

```ocaml
  (* Stops at the `:`: the rule exists only to report this error, and parsing
     the type made it ambiguous with a statement that follows a bare
     annotation (4 of the grammar's shift/reduce conflicts, and 2 more once a
     type may end in `[p]`).  The caret is unchanged: [type_annot] began at the
     same COLON. *)
  | LET; QUESTION; _p = simple_pattern; COLON
    { error_raise … $startpos($4) }
```
Keep the message string verbatim. Do the same for `LET; STAR; …`.

- [ ] **Step 2:** Verify:

```bash
conflicts                                           # expect 7
dune build --root . bin/main.exe test/run_errors.exe 2>&1 | head
scripts/run-tests.sh errors                          # parse_error_2/9/10 .expected must be unchanged
bash specs/lang/grammar/check_grammar.sh | tail -2   # all pass
git diff --stat test/                                # empty: no snapshot changed
```
Also check `test/emit_core_ast/fixtures/t70_letq_type_annotation.expected.json` still matches; its runner is in `scripts/run-tests.sh` or `dune runtest --root . test/emit_core_ast`, so use whichever the file's `dune` stanza names. If an `.expected` changes **only** in column, stop and explain: e1 says it shouldn't.

- [ ] **Step 3:** Fix the stale conflict-count comments: `parser.mly` (the "10 → 11" note at the `proof_cap_dict` rule, about line 1205, and the "unchanged at 9" note at `pattern_no_as`, about line 1985). Say what the count is now and why. Commit:

```bash
git add lib/parser/parser.mly
git commit -m "parser: the let?/let* annotation errors stop at the colon (11 -> 7 shift/reduce conflicts)"
```

### Task D2: `T[p]` parses to an abstract-refinement slot

**Files:** `lib/parser/parser.mly` (`ty_app`'s last arm, and a new `ty_post`); `test/test_refinecheck.ml` (new suite `abstract_sugar_suite`, registered before `z3-well-formed`); `specs/lang/grammar/parse/p42_abstract_refinement_sugar.march`; `specs/lang/grammar/reject/r18_abstract_refinement_sugar_two_names.march`.

- [ ] **Step 1: Failing tests.** In `test_refinecheck.ml`, using the existing `parse` helper and a small finder for a function's `fn_def` (copy the shape of `ret_refinement_of`, about line 2298):

```ocaml
(* Phase 4 (plan specs/plans/2026-10-07-abstract-refinements-phase4-plan.md):
   the shorthand must mean exactly the spelled-out form.  Equivalence is
   checked where it matters: [Refine_abstract.collect] (the names and roles)
   and the refinement ledger. *)
let fd_of (src : string) (name : string) : March_ast.Ast.fn_def =
  let m = parse src in
  List.find_map
    (function
      | March_ast.Ast.DFn (fd, _) when fd.March_ast.Ast.fn_name.March_ast.Ast.txt = name -> Some fd
      | _ -> None)
    m.March_ast.Ast.mod_decls
  |> Option.get

let roles src name =
  let open March_refinecheck.Refine_abstract in
  List.map
    (fun (p, occs) ->
      (p, List.sort compare (List.map (fun o -> match o.occ_role with Definer -> "D" | Positive -> "+" | Negative -> "-") occs)))
    (collect ~is_known:(fun _ -> false) (fd_of src name))

let abstract_sugar_suite =
  let long = {|mod L do
  fn filt(xs : List(a), keep : ({x : a | true}) -> {Bool | _ == p(x)}) : List({a | p(_)}) do xs end
end|} in
  let short = {|mod S do
  fn filt(xs : List(a), keep : a -> Bool[p]) : List(a[p]) do xs end
end|} in
  [ Alcotest.test_case "a[p] and Bool[p] declare the same abstract refinement" `Quick (fun () ->
        Alcotest.(check (list (pair string (list string)))) "same roles"
          (roles long "filt") (roles short "filt"));
    Alcotest.test_case "a[p] alone is element sugar" `Quick (fun () ->
        let fd = fd_of {|mod E do
  fn f(xs : List(a[p]), keep : a -> Bool[p]) : Int do 0 end
end|} "f" in
        match fd.March_ast.Ast.fn_clauses with
        | c :: _ ->
          (match c.March_ast.Ast.fc_params with
           | March_ast.Ast.FPNamed { param_ty = Some (March_ast.Ast.TyCon (_, [ March_ast.Ast.TyRefine (March_ast.Ast.TyVar _, Some b, _) ])); _ } :: _ ->
             Alcotest.(check string) "marker binder" "_" b.March_ast.Ast.txt
           | _ -> Alcotest.fail "List(a[p]) did not parse to List({_ : a | p(_)})")
        | [] -> Alcotest.fail "no clause") ]
```
Register `("abstract-sugar", abstract_sugar_suite);` before `z3-well-formed`. Copy the exact `FPNamed` / `param_ty` constructor and field names from `Refine_abstract.signature_occurrences` (`refine_abstract.ml`), which pattern-matches the same structure.

Grammar corpus: `p42` (parses) contains the `short` module above, plus a function whose body has `let ys = [1, 2]` on the line after a `let`. `r18` contains `fn f(xs : List(a[p, q])) : Int do 0 end`, with `-- EXPECT-ERROR: I got stuck here`. Check the exact menhir message by running it, and pin that substring.

- [ ] **Step 2:** Run. Expected: both cases FAIL (`a[p]` is a syntax error today), `p42` FAILS in `check_grammar.sh`, and `r18` passes already. That's fine: it pins that two names stay rejected.

- [ ] **Step 3: The rule.** In `ty_app`, replace the final `| t = ty_atom { t }` with `| t = ty_post { t }` and add:

```ocaml
(* `T[p]`: an abstract refinement applied to a type, `{T | p(_)}`.  The binder
   is the marker `Some "_"`: a user cannot write `{_ : T | …}` (`_` is not a
   [lower_name]), so the shorthand stays recognisable — [show_ty] prints it
   back, and an arrow whose codomain is `Bool[p]` reads it as a definer
   ([abstract_definer_arrow]).  Semantically identical to `{T | p(_)}`. *)
ty_post:
  | t = ty_atom { t }
  | t = ty_atom; LBRACKET; p = lower_name; RBRACKET
    { let u = mk_name "_" $loc in
      TyRefine (t, Some u, EApp (EVar p, [ EVar u ], mk_span $loc)) }
```
Check the `EApp`/`EVar` constructor shapes against `lib/ast/ast.ml` (`EApp of expr * expr list * span`, `EVar of name`).

- [ ] **Step 4:** `conflicts` must print **7**. Run the suite (both PASS) and `check_grammar.sh` (`p42` and `r18` PASS). Perturb: change `ty_post`'s second arm to require `LBRACKET; LBRACKET`, rebuild, confirm both cases FAIL, restore.

- [ ] **Step 5:** Add `p42`/`r18` rows to `specs/lang/grammar/INDEX.md` (header ranges and the counts line) and a `ty_post` line to `specs/lang/grammar.md`'s type grammar block (about line 1505). Commit.

### Task D3: `D -> Bool[p]` is a definer

**Files:** `lib/parser/parser.mly` (the header `%{ … %}` and `ty`'s arrow action); tests.

- [ ] **Step 1: Failing tests** (append to `abstract_sugar_suite`). The roles test from D2 already compares definers; it FAILS until this task because `Bool[p]` is still element-shaped. Add:

```ocaml
    gated "sugar filt proves and instantiates like the long form" (fun () ->
        let src body = "mod SF do\n  fn filt(xs : List(a), keep : a -> Bool[p]) : List(a[p]) do\n    match xs do\n    Nil -> Nil\n    Cons(h, t) -> if keep(h) do Cons(h, filt(t, keep)) else filt(t, keep) end\n    end\n  end\n  fn sum_pos(xs : List({Int | _ > 0})) : Int do 0 end\n" ^ body ^ "end\n" in
        let at body = List.filter_map (fun (c, v, r) -> if c = "sum_pos" then Some (v, r) else None) (typed_obligations (src body)) in
        Alcotest.(check (list (pair string string))) "n" [ ("proved", "") ]
          (at "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y > 0)) end\n");
        Alcotest.(check (list (pair string string))) "n2" [ ("skipped", "abstract-refinement-too-weak") ]
          (at "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y >= 0)) end\n"));
    Alcotest.test_case "a named domain binder is reused" `Quick (fun () ->
        Alcotest.(check (list (pair string (list string)))) "same as long form"
          (roles {|mod L2 do
  fn f(xs : List(Int), k : ({v : Int | v > 0}) -> {Bool | _ == p(v)}) : List(Int[p]) do xs end
end|} "f")
          (roles {|mod S2 do
  fn f(xs : List(Int), k : ({v : Int | v > 0}) -> Bool[p]) : List(Int[p]) do xs end
end|} "f"));
    Alcotest.test_case "Bool[p] over a two-argument callback is rejected" `Quick (fun () ->
        Alcotest.(check bool) "parse error" true
          (try ignore (parse {|mod T do
  fn f(xs : List(a), k : (a, a) -> Bool[p]) : List(a[p]) do xs end
end|}); false with _ -> true));
    (* Curried: the inner arrow is rewritten, nothing instantiates it, and
       nothing is proved — pinned as SAFE, not as a feature. *)
    gated "a curried Bool[p] proves nothing" (fun () ->
        let p, v, _, _ =
          typed_ledger {|mod C do
  fn need(xs : List(Int[p]), k : Int -> Int -> Bool[p]) : Int do 0 end
  fn go(ys : List(Int)) : Int do need(ys, fn a -> fn b -> a > 0) end
end|}
        in
        Alcotest.(check (pair int int)) "nothing proved, nothing violated" (0, 0) (p, v));
```

How the existing `parse` helper reports a menhir error is a fact to check: it either raises, or returns a module with an error recorded. Read `parse`'s definition (`test_refinecheck.ml:5`) and `March_parser.Parse.module_of_lexbuf`, and adapt the "rejected" assertion. Add `specs/lang/grammar/reject/r19_bool_sugar_two_argument_callback.march` with the tuple-domain program and its pinned message.

- [ ] **Step 2:** Run. Expected FAIL: the roles test from D2 (definer missing), "sugar filt proves…", "named domain binder", r19. Expected PASS: curried (nothing proves today either).

- [ ] **Step 3: The rewrite.** In the parser header (`%{ … %}`), after `mk_name`/`error_raise` are defined:

```ocaml
(* `D -> Bool[p]` (the marker from [ty_post] on `Bool`) is the definer form of
   an abstract refinement: `({x : D | true}) -> {Bool | _ == p(x)}` (design
   2026-09-20 §1).  A domain that already names its binder keeps it; one
   refined over `_` cannot be referred to, so it is rejected with the fix; a
   tuple domain is a several-argument callback, which cannot define one
   (§9.3).  Anything else is returned unchanged. *)
let abstract_definer_arrow (dom : ty) (cod : ty) (pos : Lexing.position) : ty =
  match cod with
  | TyRefine ((TyCon ({ txt = "Bool"; _ }, []) as b), Some { txt = "_"; _ },
              EApp (EVar p, [ EVar _ ], sp)) ->
    let x, dom' =
      match dom with
      | TyTuple _ ->
        error_raise
          "`Bool[p]` defines an abstract refinement from a ONE-argument callback; this one takes several."
          (Some "keep : a -> Bool[p]") pos
      | TyRefine (_, Some x, _) when x.txt <> "_" -> (x, dom)
      | TyRefine (_, _, _) ->
        error_raise
          "`Bool[p]` needs to name the callback's argument: write the domain as `{x : T | …}`."
          (Some "keep : ({x : Int | x > 0}) -> Bool[p]") pos
      | d ->
        let x = { p with txt = "$x" } in
        (x, TyRefine (d, Some x, ELit (LitBool true, sp)))
    in
    let u = { p with txt = "_" } in
    TyArrow (dom', TyRefine (b, None, EApp (EVar { p with txt = "==" }, [ EVar u; EApp (EVar p, [ EVar x ], sp) ], sp)))
  | _ -> TyArrow (dom, cod)
```

Check the real names and shapes before compiling: `error_raise`'s signature (used in the `let?` rule: message, hint option, position); `name`'s record fields (`txt`, `span`); `ELit (LitBool …, span)`. The `==` app shape must match what the parser builds for `_ == e` (see the `expr_cmp` action), or `named_predicate`'s pattern (phase 3) won't see it. Parse `{Bool | _ == p(x)}` in a test and compare structurally. In `ty`:

```ocaml
ty:
  | t = ty_nat_add ARROW u = ty { abstract_definer_arrow t u $startpos(u) }
  | t = ty_nat_add { t }
```

- [ ] **Step 4:** `conflicts` → **7**. Run `abstract-sugar` (all pass), `abstract-phase2`, `abstract-phase3`, and `check_grammar.sh` (r19 passes). Perturb: make `abstract_definer_arrow` return `TyArrow (dom, cod)` unconditionally, and confirm the roles/proves/binder tests FAIL; restore. Commit.

### Task D4: Show the shorthand back

**Files:** `lib/ast/ast.ml` (`show_ty`, about line 524); a test.

- [ ] **Step 1:** Test (append): `show_ty` of the parsed `List(a[p])` param type is `List(a[p])`. Of the spelled-out `List({a | p(_)})`, it is still `List({ a | ... })`, so explicit spelling is not prettified.
- [ ] **Step 2:** Add the arm **before** the generic `Some v` arm:

```ocaml
  | TyRefine (base, Some { txt = "_"; _ }, EApp (EVar p, [ EVar { txt = "_"; _ } ], _)) ->
    Printf.sprintf "%s[%s]" (show_ty base) p.txt
```
- [ ] **Step 3:** Run, perturb (delete the arm and confirm it fails), restore. `grep -rn 'show_ty' lsp/lib | head` and add one LSP hover assertion if `test_lsp` has a hover-on-signature helper. If it doesn't, note in the progress file that hovers use `show_ty`. Commit.

### Task D5: Tree-sitter

**Files:** `tree-sitter-march/grammar.js`, `src/parser.c`, `src/grammar.json`, `src/node-types.json`, `test/corpus/types.txt`.

- [ ] **Step 1:** Add to `_type_atom`'s choice, and define (prototyped as t1):

```js
    // `a[p]`, `Bool[p]`: an abstract refinement applied to a type
    // (parser.mly `ty_post`).
    abstract_refinement_type: $ => prec(2, seq(
      field('base', choice($.type_variable, $.type_constructor, $.type_application, $.qualified_type)),
      '[', field('predicate', $.identifier), ']',
    )),
```
- [ ] **Step 2:** Add a corpus case to `test/corpus/types.txt`: `mod Foo do fn f(xs : List(a[p]), k : a -> Bool[p]) : Int do 1 end end`, with its expected tree. Generate it by running `tree-sitter parse`, then check the output by eye before pasting.
- [ ] **Step 3:** `cd tree-sitter-march && H=$(mktemp -d) HOME=$H tree-sitter generate && HOME=$H tree-sitter test`. Expected: generate OK; 70/70. Then `scripts/check-tree-sitter.sh` from the repo root must pass all five steps (freshness, corpus, queries, ratchet over every `.march` including the new `p42`, keywords). Run `scripts/check-tree-sitter.sh --self-test` once too. Commit grammar.js and the three generated files together.

### Task D6: Migrate the stdlib signatures to the shorthand (equivalence proof)

**Files:** `stdlib/list.march` (`filter`, `find`, `take_while`), `stdlib/option.march` (`filter`).

- [ ] **Step 1:** Rewrite the four signatures:

```march
  fn filter(xs : List(a), pred : a -> Bool[p]) : {List(a[p]) | subset(elts(_), elts(xs))} do
  fn find(xs : List(a), pred : a -> Bool[p]) : Option(a[p]) do
  fn take_while(xs : List(a), pred : a -> Bool[p]) : List(a[p]) do
  fn filter(opt : Option(a), pred : a -> Bool[p]) : Option(a[p]) do
```
Bodies and docstrings are unchanged, so line numbers don't move.

- [ ] **Step 2: The proof.** Restage, then:

```bash
scripts/refine-oracle.sh check $SCRATCH/oracle             # expect REFINEMENT DIAGNOSTICS IDENTICAL
UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e 'audit-baseline' >/dev/null
cmp test/refine_audit/corpus.baseline $SCRATCH/corpus.baseline && cmp test/refine_audit/holes.baseline $SCRATCH/holes.baseline && echo AUDIT IDENTICAL
HOME=$(mktemp -d) bash specs/lang/types/check_types.sh | tail -1
scripts/run-tests.sh stdlib stdlib_march
```
Every line must be identical. If the oracle differs, the sugar is **not** equivalent. Find the first differing obligation, compare the two ASTs, and fix D2/D3 rather than accepting the diff. (One known risk: a diagnostic that prints a predicate could show `p($x)` where it showed `p(x)`; phase 2's pass-site exemption means none is printed today. Confirm.)

- [ ] **Step 3:** Commit.

### Task D7: Verify, document, PR

- [ ] **Step 1:** Full `scripts/run-tests.sh`; `scripts/check-tree-sitter.sh`; `specs/lang/grammar/check_grammar.sh`; `specs/lang/types/check_types.sh`; `scripts/check-docs.sh`. Check `df -h` first, since the dune cache filled the disk on 2026-10-07; trim with `dune cache trim --size 20GB` if it's low.
- [ ] **Step 2:** In `specs/lang/refinement-types.md`'s abstract-refinements section, make the shorthand the primary spelling: show `filter(xs : List(a), pred : a -> Bool[p]) : List(a[p])`. Explain the long form as what it means, state the rules from "Behaviour decided here" (tuple and `_`-binder domains rejected, curried inert, `T[p]` elsewhere is `{T | p(_)}`), and remove "**No shorthand**" from the limitations. Run `scripts/gen-lang-docs.py`. Add a typing-corpus pair if useful (next free ids; e.g. an accept file using the sugar under `cap verified`, mirroring t308).
- [ ] **Step 3:** Progress note `specs/progress/2026-MM-DD-abstract-refinements-phase4.md` (the pressure table, conflict counts 11 → 7, the D6 identity proof). Design doc status "phase 4 landed" and correct its "9 conflicts". CHANGELOG `### Added` (the shorthand) and `### Changed` (if any user-visible parse message moved; e1 says none). Merge `origin/main` (resolve CHANGELOG by union; renumber corpus ids if taken); re-run `refinecheck compiler` and both corpora; push; `gh pr create`.

## Risks and containment

| Risk | Containment |
|---|---|
| Conflict count rises | Measured in the pressure test: 11 → 7 → 7. `conflicts` runs after every grammar edit; any rise is a STOP. |
| D1 changes a pinned error caret | e1: `type_annot` began at the same COLON; D1 Step 2 diffs every errors snapshot and the emit-core-ast fixture. |
| Sugar not exactly equivalent | D2/D3 role-equivalence tests; D6 requires the oracle and audit baselines **byte-identical** after migrating the stdlib. |
| `Bool[p]` silently means something else | Only the marker (`Some "_"`, unforgeable) triggers the definer rewrite; explicit `{Bool \| p(_)}` is untouched. Tuple and `_`-binder domains are parse errors with a fix-it. |
| `[` after a type misparses a following list literal | `p42` puts `let ys = [1, 2]` after a `let`; the error rules that caused the ambiguity no longer parse a type (D1). |
| Tree-sitter drift | D5 extends grammar.js (prototyped: generate OK, corpus 69/69, sugar parses); `check-tree-sitter.sh` incl. self-test. |
| `$x` leaks into a user-facing message | It appears only as a synthesized domain binder; phase 2's definer exemption means no pass-site message prints the codomain. D6's identical oracle confirms no message changed. |
| Curried callbacks | Not modelled before or after; a test pins "proves nothing, violates nothing". |
