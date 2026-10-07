# Abstract Refinements Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `sum_pos(List.filter(ys, fn y -> y > 0))` proves, where `sum_pos` wants `List({Int | _ > 0})`. Today it is a `parametric-source-unproved` skip.

**Architecture:** Two PRs. **PR A** fixes how a callback's argument name is handled. A callback type's codomain can name its domain's argument (`({x : Int | true}) -> {Bool | _ == (x > 0)}`), and three places never rename that name. Because of this, a guard `if keep(h)` gives no fact today, and neither does a lambda or named function passed for `keep`. PR A also exempts a callback that *defines* an abstract refinement from the pass-site codomain check. Without that exemption, changing `List.filter`'s signature would add a skip, or a `cap verified` error, at every call. PR A changes no stdlib signature. **PR B** is the design's phase 2:
- an uninterpreted `$abs_p` symbol inside the defining function, so its body proves;
- substituting the lambda's body for `p` at a call that has a demand on the result, with the decision "lambda body implies demand" recorded as proved or as a skip, never as a violation;
- combining with the input list's own element fact, and the `let`-bound result;
- then `List.filter`'s new signature, which keeps its existing `subset` contract.

**Tech Stack:** OCaml 5.3 (dune), z3 (CI uses 4.8.12; local builds are usually 4.16), alcotest. The refinement checker is `lib/refinecheck/` and the SMT layer is `lib/refine/`.

**Design this implements:** `specs/2026-09-20-abstract-refinements-design.md` (sections 2-5 and 7). Phase 1 landed 2026-09-21 (`7b31f6551`, `lib/refinecheck/refine_abstract.ml`).

## Global Constraints

- Build and test from the worktree with `--root .` (`dune build --root . …`). A bare `dune build` inside `.claude/worktrees/*` targets the main checkout.
- `z3` must be on PATH. `gated` test cases report `[SKIP]` and still exit 0 when it is missing, so check `command -v z3` before trusting a green run.
- Never `eval $(opam env)`. `dune` and `opam` are on PATH.
- Stage files by name. Never `git add -A`, `git add .`, or `git commit -a`. No `Co-Authored-By` or other attribution lines.
- Every new rule lands with a fixture that FAILS without it. Assert ledger triples or verdict lists, never exit codes. An accept-only witness cannot tell a working rule from one that checks nothing, so every positive case gets a negative control.
- Definite-failure stance: a weaker lambda predicate (`y >= 0` against `_ > 0`) is a **skip** (`abstract-refinement-too-weak`), **never** a violation. This is design decision 9.2: `filter([], …)` is fine.
- CI ratchet: the `(user + stdlib)` skipped count of `--check --stdlib-source --refine-report stdlib/list.march` must stay **≤ 42** (`.github/workflows/ci.yml:426`). It may only go down. The `--refine-audit` unenforced count must stay **0**.
- Do not run `scripts/run-tests.sh` while any other `dune build` of this worktree is running. Its `dune shutdown` kills that build.
- Run probes and oracles under a private `HOME` (`HOME=$SCRATCH/home`). `~/.cache/march` is shared across worktrees.
- Language reference: edit `specs/lang/refinement-types.md`, then run `scripts/gen-lang-docs.py`, then commit both. Never hand-edit `docs/refinement-types.md`.
- Each PR includes a `CHANGELOG.md` bullet under `## [Unreleased]`, a `specs/progress/2026-MM-DD-*.md` file, and any `specs/todos/` closure, all in the same commit as the code.

## Where things stand (probed 2026-10-06 on `24c7eb543`)

All probes ran with `HOME=<private> _build/default/bin/main.exe --check --refine-report --refine-report-sites`.

| Probe | Program shape | Today |
|---|---|---|
| a2 | `keep_pos(xs)` returning `List({Int \| _ > 0})`, body `if h > 0 do Cons(h, keep_pos(t)) …` | return **proved** (3 proved) |
| a4 | same, but guard `if keep(h)` with `keep : ({x : Int \| true}) -> {Bool \| _ == (x > 0)}` | return-of **skipped ×3**; lambda pass `fn y -> y > 0` is `solver-undecided` |
| a1 | phase-1 signature `myfilter(xs : List(a), keep : ({x : a \| true}) -> {Bool \| _ == p(x)}) : List({a \| p(_)})`, called `sum_pos(myfilter(ys, fn y -> y > 0))` | 4 skipped: 2× `unreflectable-predicate keep _ == p(x)` (the recursive forwards), 1× `postcondition <lambda> _ == p(x)`, 1× `parametric-source-unproved sum_pos` |
| a3 | return `{List({a \| p(_)}) \| subset(elts(_), elts(xs))}` | parses; the `subset` half **proves** |
| b1/b2 | a1's signature in a `cap verified` module, passing a plain named fn or a lambda | **build error** "cannot verify the expected codomain refinement `_ == p(x)` on `keep`" |
| b3 | `cap verified` calling today's `List.filter` | 0 obligations, exit 0 |

**Root causes**, verified in code:

1. `callback_sig_of_ty` (`lib/refinecheck/refine_scope.ml:831`) names the callback's parameter `$cb_arg` but keeps the codomain predicate as written, still mentioning the domain's argument name `x`.
   - `postcond_of` (`refine_resolve.ml:263-310`) runs `classify_pred "_" ["$cb_arg"]`. That marks the predicate `Unusable` because `x` is neither the result binder nor a parameter, so it returns `None`.
   - The guard fallback in `check_call` (`refine_call.ml:2457-2469`) then reflects `keep(h)` to nothing, and the path fact is dropped without any message.
2. `check_pass_sites`' lambda arm (`refine_check.ml:455-476`) verifies the lambda against `cod` without renaming `x` to the lambda's parameter `y`. In `check_post`, `x` becomes a fresh unconstrained constant (`refine_post.ml:420-423`).
3. `check_pass_sites`' `EVar` arm (`refine_check.ml:477-489`) puts a named function's proved return `rq` in scope as written, mentioning *its own* parameter name, while the goal mentions `x`. Nothing identifies the two names.
4. Nothing exempts an abstract-refinement definer. `_ == p(x)` is an ordinary codomain obligation with an untranslatable `p`.

**Facts the plan relies on:**
- `subst_params env e` (`refine_encode.ml:592`) does simultaneous substitution and leaves application heads alone, so `p($cb_arg)` keeps its head `p`.
- The VC cache key is BLAKE3 of the preamble plus the full assertion text (`lib/refine/vc_cache.ml:6-7`). An instantiated predicate is inlined text, so different lambdas get different keys automatically.
- `smt.ml`'s `assertion_block` emits only `declare-const`. Function symbols come from preamble strings, so `$abs_p` needs a preamble `declare-fun`.
- `Element_domain` refutations are *definite*, i.e. violations (`refine_call.ml:2755`). That is why the call-site discharge runs in a scratch ledger and records its own verdict, as `demand_flow` does (`refine_check.ml:1010-1031`).
- `Witness.free_vars` has no `ELam` arm, so the lambda capture test at `refine_check.ml:475` never fires. This is filed separately as a session task. This plan does **not** reuse that check: it decides capture with `classify_pred y [] body = Closed`.

## File map

| File | PR | Responsibility / change |
|---|---|---|
| `lib/refinecheck/refine_scope.ml` | A | `dom_binder`; `callback_sig_of_ty` renames the domain binder to `$cb_arg` in `ret` |
| `lib/refinecheck/refine_check.ml` | A, B | A: lambda- and named-callable binder renaming; definer exemption in `check_pass_sites`; `callee_abstracts`. B: `current_abstracts` set in `visit_fn`; `entry_mentions`; `declared_elem_return` exclusion; `abstract_flow`; hooks in `check_elements` |
| `lib/refinecheck/refine_abstract.ml` | B | `definer_index`; `positive_base` |
| `lib/refinecheck/refine_encode.ml` | B | `current_abstracts`, `abs_sym`, `is_abs_sym`, `abs_apps`, `abstract_preamble`; sort arms in `mentions_str`/`wellsorted`/`resolve_sorts_exact` |
| `lib/refinecheck/refine_call.ml`, `refine_post.ml` | B | append `abstract_preamble vc` to each query preamble; reason-match arms |
| `lib/refinecheck/obligation.ml` | B | reasons `Abstract_too_weak`, `Abstract_uninstantiated` |
| `stdlib/list.march` | B | `List.filter`'s signature |
| `test/test_refinecheck.ml` | A, B | suites `callback-binder`, `abstract-pass-sites`, `abstract-phase2`; update phase-1 row-n case |
| `specs/lang/types/{accept,reject}/t296_*`, `t297_*`, `INDEX.md` | B | conformance pair over the real `List.filter` |
| `specs/lang/refinement-types.md` (+ regenerated `docs/`) | A, B | language reference |
| `specs/2026-09-20-abstract-refinements-design.md` | A | corrections from the probes |
| `test/refine_audit/corpus.baseline` | B | regenerated |

Test command used throughout. A group name is the string registered in the `Alcotest.run` list:

```bash
dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test <group>
```

---

# PR A — callback argument binders and the definer exemption

Branch: `claude/callback-binder-pass-sites`, from `origin/main`.

### Task A0: Record the refinement oracle baseline

**Files:** none (scratch only)

- [ ] **Step 1: Build main and record the baseline**

```bash
SCRATCH=/private/tmp/$(basename $PWD)-arA; mkdir -p $SCRATCH
dune build --root . bin/main.exe && scripts/refine-oracle.sh baseline $SCRATCH/oracle
```
Expected: it finishes with a `refine.txt` of more than 50 lines in `$SCRATCH/oracle`. It takes about 6 minutes.

### Task A1: Rename the domain binder in a callback's return predicate

**Files:**
- Modify: `lib/refinecheck/refine_scope.ml`, in `callback_sig_of_ty` (around line 831) plus a new `dom_binder` above it
- Test: `test/test_refinecheck.ml`, new suite `callback_binder_suite`, registered as `("callback-binder", callback_binder_suite)` immediately before `("z3-well-formed", z3_wellformed_suite)`. That one must stay last.

**Interfaces:**
- Produces: `Refine_scope.dom_binder : A.ty -> string option`. It returns `Some x` for a domain spelled `{x : T | …}` with `x <> "_"`, otherwise `None`.
- Produces: test helpers `typed_obligations : string -> (string * string * string) list` (callee, verdict slug, reason slug or `""`) and `verdicts_of : string -> string -> string list`.
- Contract: after this task, a callback `fn_sig`'s `ret` predicate mentions `$cb_arg` (`callback_param_name`) wherever the source mentioned the domain binder.

- [ ] **Step 1: Add the test helpers and the failing tests**

Add next to `typed_ledger` (around line 55):

```ocaml
(* Every obligation of a TYPED check as (callee, verdict slug, reason slug or
   ""), in record order.  For asserting on ONE callee's verdicts when the
   whole-module triple would hide which obligation moved. *)
let typed_obligations (src : string) : (string * string * string) list =
  March_refinecheck.Obligation.reset ();
  ignore (has_refine_error_typed src);
  List.map
    (fun (o : March_refinecheck.Obligation.t) ->
      let open March_refinecheck.Obligation in
      ( o.callee
      , verdict_name o.verdict
      , match o.verdict with Skipped r -> reason_name r | _ -> "" ))
    (March_refinecheck.Obligation.all ())

let verdicts_of (src : string) (callee : string) : string list =
  List.filter_map (fun (c, v, _) -> if c = callee then Some v else None) (typed_obligations src)
```

Add the suite before the `Alcotest.run` list:

```ocaml
(* A callback's codomain may name its domain's binder:
   `keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}`.  [callback_sig_of_ty]
   names the parameter `$cb_arg` but kept `x` in the return predicate, so
   [postcond_of] classified it Unusable and a guard `if keep(h)` taught
   nothing.  CB1 is the flagship (RED before: every "return of keep_pos" is
   skipped); CB2 is its negative bracket — the fact is used only on the
   branch where the guard holds. *)
let callback_binder_suite =
  [ gated "a guard calling a callback learns its codomain fact" (fun () ->
        let vs =
          verdicts_of
            {|mod CB1 do
  fn keep_pos(xs : List(Int), keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}) : List({Int | _ > 0}) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> if keep(h) do Cons(h, keep_pos(t, keep)) else keep_pos(t, keep) end
    end
  end
end|}
            "return of keep_pos"
        in
        Alcotest.(check bool) "some return obligation" true (vs <> []);
        Alcotest.(check (list string)) "all proved" (List.map (fun _ -> "proved") vs) vs);

    gated "the fact holds only on the guarded branch" (fun () ->
        let vs =
          verdicts_of
            {|mod CB2 do
  fn keep_pos(xs : List(Int), keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}) : List({Int | _ > 0}) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> if keep(h) do keep_pos(t, keep) else Cons(h, keep_pos(t, keep)) end
    end
  end
end|}
            "return of keep_pos"
        in
        Alcotest.(check bool) "not all proved" true (List.exists (fun v -> v <> "proved") vs);
        Alcotest.(check bool) "never violated" false (List.mem "violated" vs)) ]
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test callback-binder`
Expected: case 0 FAILS with `all proved`, because at least one verdict is `skipped`. Case 1 may already pass, which is fine: it is the control.

- [ ] **Step 3: Implement**

In `refine_scope.ml`, directly above `callback_sig_of_ty`:

```ocaml
(* The name a callback's DOMAIN gives its argument (`x` in `({x : Int | …})
   -> …`), when it gives one.  The codomain may mention it; the synthesized
   signature names its one parameter [callback_param_name], so the codomain
   is rewritten to match (see [callback_sig_of_ty]). *)
let dom_binder (dom : A.ty) : string option =
  match unlinear dom with
  | A.TyRefine (_, Some n, _) when n.A.txt <> "_" -> Some n.A.txt
  | _ -> None
```

(`unlinear` is the same helper `return_refine_sorted` applies a few lines above. If the compiler reports it unbound at this point, move `dom_binder` below `return_refine_sorted`.)

In `callback_sig_of_ty`, replace the `let ret, ret_sort = … in` binding's *use* by adding a rename right after it:

```ocaml
    (* The codomain names the argument by the DOMAIN's binder; the signature
       names it [callback_param_name].  Rename, so [postcond_of] sees a
       relational return over the one parameter and substitutes the actual
       (`keep(h)` then reflects to `keep$ret == (h > 0)`).  A codomain binder
       spelled like the domain's shadows it: leave that predicate alone. *)
    let ret =
      match ret, dom_binder dom with
      | Some (b, p), Some x when x <> b ->
        Some (b, subst_params [ (x, A.EVar { A.txt = callback_param_name; A.span = A.dummy_span }) ] p)
      | r, _ -> r
    in
```

Leave `ret_ty = Some cod` unchanged. Container-codomain consumers read it, and a container codomain that names the domain binder is not `Closed`, so it is unaffected.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./_build/default/test/test_refinecheck.exe test callback-binder` (after the `dune build` above)
Expected: both cases PASS.

- [ ] **Step 5: Run the nearby suites for regressions**

Run: `./_build/default/test/test_refinecheck.exe test 'arrow-codomain|demand-flow|abstract-refinements|hof'`. If alcotest rejects the regex, run the groups one by one; list the group names with `./_build/default/test/test_refinecheck.exe list | awk '{print $2}' | sort -u`.
Expected: everything passes. If an `arrow-codomain` case changes, read it before touching anything. A predicate that used to be `Unusable` and is now relational can legitimately turn a skip into a proof. Update the expectation only if the new verdict is a correct proof, and note it in the commit message.

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/refine_scope.ml test/test_refinecheck.ml
git commit -m "fix(refinecheck): a callback codomain naming its domain binder yields a fact"
```

### Task A2: An inline lambda is checked against the codomain under its own parameter name

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`, `check_pass_sites` lambda arm (around lines 455-476)
- Test: `test/test_refinecheck.ml`, append to `callback_binder_suite`

**Interfaces:**
- Consumes: `Refine_scope.dom_binder` (Task A1).

- [ ] **Step 1: Write the failing tests**

Append to `callback_binder_suite`:

```ocaml
    (* The expected codomain names the argument `x`; the lambda calls it `y`.
       RED before: `solver-undecided` on `<lambda>` — `x` was a free constant. *)
    gated "a lambda meets a codomain over its own parameter name" (fun () ->
        Alcotest.(check (list string)) "proved" [ "proved" ]
          (verdicts_of
             {|mod CB3 do
  fn ap(keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}, v : Int) : Bool do keep(v) end
  fn go() : Bool do ap(fn y -> y > 0, 3) end
end|}
             "<lambda>"));

    gated "a lambda that disagrees with the codomain is not proved" (fun () ->
        let vs =
          verdicts_of
            {|mod CB4 do
  fn ap(keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}, v : Int) : Bool do keep(v) end
  fn go() : Bool do ap(fn y -> y >= 0, 3) end
end|}
            "<lambda>"
        in
        Alcotest.(check bool) "not proved" false (List.mem "proved" vs));
```

- [ ] **Step 2: Run and confirm CB3 fails**

Run: `./_build/default/test/test_refinecheck.exe test callback-binder`
Expected: CB3 FAILS with `["skipped"]`. CB4 passes.

- [ ] **Step 3: Implement**

In the `A.ELam (ps, body, lsp)` arm, after the `let ps = … in` binding, add:

```ocaml
              (* The expected codomain names the argument by the DOMAIN's
                 binder; this lambda calls it [y].  Rename so the body is
                 checked against a goal about its own parameter — otherwise
                 the binder is a fresh unconstrained constant and a correct
                 lambda is undecided. *)
              let cod =
                match ps, cod with
                | [ p ], A.TyRefine (base, cbind, pred) ->
                  let y = p.A.param_name.A.txt in
                  (match dom_binder dom with
                   | Some x
                     when x <> y && (match cbind with Some n -> n.A.txt <> x | None -> true) ->
                     A.TyRefine (base, cbind, subst_params [ (x, A.EVar p.A.param_name) ] pred)
                   | _ -> cod)
                | _ -> cod
              in
```

`run ()` already passes `(Some cod)` to `local_fn_def`. Because the new `cod` binding shadows the old one, it picks up the renamed codomain.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./_build/default/test/test_refinecheck.exe test callback-binder`
Expected: all four cases PASS. CB4 is expected to be `violated` (a witness `y = 0`) or `skipped`, but never `proved`.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "fix(refinecheck): check a passed lambda against the codomain under its own parameter"
```

### Task A3: A named callable's proved return is read under the same argument name

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`, `check_pass_sites` `A.EVar { A.txt = g; _ }` arm (around lines 477-489)
- Test: `test/test_refinecheck.ml`, append to `callback_binder_suite`

**Interfaces:**
- Consumes: the Task A1 contract. The expected codomain `p` mentions `$cb_arg`.

- [ ] **Step 1: Write the failing tests**

```ocaml
    (* `is_pos`'s proved return names ITS parameter `n`; the expected codomain
       names `$cb_arg` (after A1).  RED before: skipped — the two never meet. *)
    gated "a named callable's proved return meets the codomain" (fun () ->
        Alcotest.(check (list string)) "proved" [ "proved" ]
          (verdicts_of
             {|mod CB5 do
  fn ap(keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}, v : Int) : Bool do keep(v) end
  fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end
  fn go() : Bool do ap(is_pos, 3) end
end|}
             "is_pos"
          |> List.rev |> (function last :: _ -> [ last ] | [] -> [])));

    gated "a named callable with a different predicate is not proved" (fun () ->
        let vs =
          verdicts_of
            {|mod CB6 do
  fn ap(keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}, v : Int) : Bool do keep(v) end
  fn is_nonneg(n : Int) : {Bool | _ == (n >= 0)} do n >= 0 end
  fn go() : Bool do ap(is_nonneg, 3) end
end|}
            "is_nonneg"
        in
        Alcotest.(check bool) "pass site not proved" true
          (List.exists (fun v -> v <> "proved") vs));
```

`verdicts_of src "is_pos"` also contains `is_pos`'s own postcondition obligation, which is recorded first because the function is visited before `go`. CB5 therefore checks only the **last** verdict, the pass-site one. If the ledger order turns out different, filter with `typed_obligations` on reason/kind instead. Keep the assertion that the pass-site obligation is `proved`.

- [ ] **Step 2: Run and confirm CB5 fails**

Run: `./_build/default/test/test_refinecheck.exe test callback-binder`
Expected: CB5 FAILS with `["skipped"]` or `["solver-undecided"]`-shaped output.

- [ ] **Step 3: Implement**

Replace the first arm of the `EVar` match:

```ocaml
               | Some ({ ret = Some (rb, rq); ret_sort = rsrt; _ } as gsg) ->
                 (* The callable's return names ITS parameter; the expected
                    codomain names [callback_param_name] (see
                    [callback_sig_of_ty]).  Rename the former so both speak of
                    one argument: the implication is then checked for an
                    arbitrary argument value, as covariance requires.  A
                    forwarded callback's sig already names [callback_param_name]
                    (the rename is the identity). *)
                 let rq =
                   match gsg.param_names with
                   | [ gp ] when gp <> callback_param_name ->
                     subst_params [ (gp, A.EVar { A.txt = callback_param_name; A.span = asp }) ] rq
                   | _ -> rq
                 in
                 let sc = ("$r", (rb, rq, rsrt)) :: scope_shadow sc [ "$r" ] in
```

The rest of the arm (`let cx = …`, `check_call … Callback_codomain …`) stays as it is.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./_build/default/test/test_refinecheck.exe test callback-binder`
Expected: all six cases PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "fix(refinecheck): read a named callable's return under the codomain's argument"
```

### Task A4: A callback that defines an abstract refinement owes no codomain obligation

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`:
  - a new `callee_abstracts` above `check_pass_sites`;
  - a new `~callee_name` parameter on `check_pass_sites`;
  - its one caller at about line 1185;
  - the codomain branch;
  - a reset of the memo table at the start of `check_module` (next to `enclosing_fn := None`, about line 3636).
- Test: `test/test_refinecheck.ml`, new suite `abstract_pass_sites_suite`, registered as `("abstract-pass-sites", …)` before `z3-well-formed`.

**Interfaces:**
- Produces: `callee_abstracts : rctx -> string -> string list`, the abstract refinement names the resolved callee declares (`[]` when it does not resolve to a known `fn_def`). Task B4 and Task B5 reuse it.
- Produces: `check_pass_sites … ~callee_name:string …`.

- [ ] **Step 1: Write the failing tests**

```ocaml
(* A definer (`keep : ({x : a | true}) -> {Bool | _ == p(x)}`) is satisfied by
   ANY callable: `p` is, by definition, whatever the callable returns.  Before
   this, every pass — the body's own recursive forward, a lambda, a named fn —
   was an `unreflectable-predicate` skip, and a hard error under
   `cap verified` (probes b1/b2, 2026-10-06).  AP3 pins that the exemption is
   for DEFINERS only: a concrete codomain still obliges a plain named fn. *)
let ap_filt =
  {|  fn filt(xs : List(a), keep : ({x : a | true}) -> {Bool | _ == p(x)}) : List({a | p(_)}) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> if keep(h) do Cons(h, filt(t, keep)) else filt(t, keep) end
    end
  end
|}

let abstract_pass_sites_suite =
  [ gated "passing a lambda or a named fn for a definer records nothing" (fun () ->
        let obs =
          typed_obligations
            ("mod AP1 do\n" ^ ap_filt
           ^ {|  fn is_even(n : Int) : Bool do n % 2 == 0 end
  fn go(ys : List(Int)) : Int do List.length(filt(ys, fn y -> y > 0)) + List.length(filt(ys, is_even)) end
end|})
        in
        Alcotest.(check (list string)) "no definer skips" []
          (List.filter_map
             (fun (c, v, _) -> if v = "skipped" && List.mem c [ "keep"; "<lambda>"; "is_even" ] then Some c else None)
             obs));

    gated "a cap verified caller of a definer compiles" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_typed
             ("mod AP2 do\n  cap verified\n" ^ ap_filt
            ^ {|  fn is_even(n : Int) : Bool do n % 2 == 0 end
  fn go(ys : List(Int)) : Int do List.length(filt(ys, fn y -> y > 0)) + List.length(filt(ys, is_even)) end
end|})));

    gated "a concrete codomain still obliges a plain named fn" (fun () ->
        Alcotest.(check bool) "still an error" true
          (has_refine_error_typed
             {|mod AP3 do
  cap verified
  fn ap(keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}, v : Int) : Bool do keep(v) end
  fn is_even(n : Int) : Bool do n % 2 == 0 end
  fn go() : Bool do ap(is_even, 3) end
end|})) ]
```

- [ ] **Step 2: Run and confirm AP1 and AP2 fail**

Run: `./_build/default/test/test_refinecheck.exe test abstract-pass-sites`
Expected: AP1 FAILS, listing `keep`, `<lambda>`, and `is_even`. AP2 FAILS with `true`. AP3 passes.

- [ ] **Step 3: Implement**

Above `check_pass_sites`:

```ocaml
(* The abstract refinements a call's callee declares (design §1), memoised per
   definition key for the module.  [] for anything that is not a resolvable
   top-level definition: a callback parameter, a local, an unknown name. *)
let abstracts_tbl : (string, string list) Hashtbl.t = Hashtbl.create 64

let callee_abstracts (ctx : rctx) (fname : string) : string list =
  match resolve_key ctx fname with
  | None -> []
  | Some key ->
    (match Hashtbl.find_opt abstracts_tbl key with
     | Some ns -> ns
     | None ->
       let ns =
         match Hashtbl.find_opt fn_defs_tbl key with
         | Some (_, fd) -> Refine_abstract.names ~is_known:known_predicate_fn fd
         | None -> []
       in
       Hashtbl.replace abstracts_tbl key ns;
       ns)
```

Add `~(callee_name : string)` to `check_pass_sites`' parameters, right after `~(span : A.span)`. In the codomain branch, wrap the existing `(match a with … )` like this:

```ocaml
         | Some { ret = Some (b, p); ret_sort = srt; _ } ->
           let abs = callee_abstracts ctx callee_name in
           if abs <> []
              && List.exists (fun (n, _, _) -> List.mem n abs) (Refine_abstract.applications p)
           then
             (* A DEFINER: the callable passed here fixes what the abstract
                refinement means at this call (design §2b), so it satisfies
                the codomain by construction.  Nothing to oblige; the facts
                it yields are drawn at the call by [abstract_flow]. *)
             ()
           else begin
             let cod_sig = elem_sig ~name:"$r" (b, p, srt) in
             let rp = List.hd cod_sig.refined in
             (match a with
              (* … existing ELam / EVar / _ arms unchanged … *)
             )
           end
```

At the caller (around line 1185), pass the name the call resolved by:

```ocaml
       check_pass_sites ~root errctx defs ctx path lets sc re cb ~span:sp ~callee_name:fname sg args;
```

In `check_module`, next to `enclosing_fn := None;`, add `Hashtbl.reset abstracts_tbl;`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `./_build/default/test/test_refinecheck.exe test abstract-pass-sites && ./_build/default/test/test_refinecheck.exe test abstract-refinements`
Expected: all PASS. The phase-1 inert case ("phase 1 is inert: row n still skips") must still pass with `proved = 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "fix(refinecheck): a callable passed for an abstract-refinement definer owes no codomain obligation"
```

### Task A5: Verify, document, and open PR A

**Files:**
- Modify: `specs/lang/refinement-types.md` (section "Callbacks and user-written combinators" around line 1966; and the "Two higher-order shapes are checked" Limitations bullet around line 3249), regenerated `docs/refinement-types.md`
- Modify: `specs/2026-09-20-abstract-refinements-design.md` (§0, §4.1, §7)
- Create: `specs/progress/2026-10-06-callback-binder-pass-sites.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the full refinement and compiler suites**

```bash
scripts/run-tests.sh refinecheck compiler > $SCRATCH/suite.log 2>&1; echo exit=$?; grep -E 'tests run|\[FAIL\]' $SCRATCH/suite.log
```
Expected: `exit=0` and two `Test Successful` lines. This takes 5-25 minutes depending on machine load; check `uptime` first.

- [ ] **Step 2: Run the oracle and explain every changed line**

```bash
dune build --root . bin/main.exe && scripts/refine-oracle.sh check $SCRATCH/oracle; echo exit=$?
```
Expected: either `REFINEMENT DIAGNOSTICS IDENTICAL`, or a diff in which each changed line is a skip that became `proved` at a callback codomain or guard. Write each changed line and its reason into the progress note. A new `violated` anywhere is a STOP: investigate it before going further.

- [ ] **Step 3: Check the CI ratchet**

```bash
rm -rf .march/cas/artifacts-v2; HOME=$SCRATCH/home ./_build/default/bin/main.exe --check --stdlib-source --refine-report stdlib/list.march > $SCRATCH/ratchet.txt 2>&1; grep 'user + stdlib' $SCRATCH/ratchet.txt
```
Expected: the skipped count is ≤ 42.

- [ ] **Step 4: Write the docs**

In `specs/lang/refinement-types.md`, "Callbacks and user-written combinators", add a paragraph:

```markdown
A callback type's codomain may name the domain's argument:
`keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}`. Inside the higher-order
function, a guard `if keep(h)` then establishes `h > 0`, and a `let b =
keep(h)` binds `b == (h > 0)`. At a pass site the callable is checked under
its own parameter name: `fn y -> y > 0` and a named
`is_pos(n : Int) : {Bool | _ == (n > 0)}` both satisfy that codomain, and
`fn y -> y >= 0` does not.
```

Then run `python3 scripts/gen-lang-docs.py`.

In the design doc:
- In §0, add a dated "Probed 2026-10-06" note listing root causes 1-4 above.
- In §4.1, replace "with no new proof rule" with: "with no new proof rule *once* `callback_sig_of_ty` renames the domain binder (PR A, 2026-10-06); before that, a guard calling a callback yielded no fact".
- In §7, record that phase 2 is preceded by PR A, and that the CI ceiling is 42, not 46.

- [ ] **Step 5: Write the progress note and the CHANGELOG bullet**

`specs/progress/2026-10-06-callback-binder-pass-sites.md`: what landed (Tasks A1-A4), the probe table rows a4/a1/b1/b2 before and after, the oracle diff explained line by line, and the tests (CB1-CB6, AP1-AP3).

`CHANGELOG.md` under `## [Unreleased]` → `### Fixed`:

```markdown
- **A callback contract that names its argument is now usable.** With
  `keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}`, a guard `if keep(h)`
  establishes `h > 0`, and a lambda or a named function with a matching
  proved return now satisfies the contract where it is passed (it used to be
  skipped). A callback that defines an abstract refinement (`_ == p(x)`) is
  no longer a skip, or a `cap verified` error, at every call.
```

- [ ] **Step 6: Lint, commit, push, open the PR**

```bash
scripts/check-docs.sh; echo docs-exit=$?
git add specs/lang/refinement-types.md docs/refinement-types.md specs/2026-09-20-abstract-refinements-design.md specs/progress/2026-10-06-callback-binder-pass-sites.md CHANGELOG.md
git commit -m "docs(refinecheck): callback argument binders; abstract-refinements design corrections"
git push -u origin claude/callback-binder-pass-sites
gh pr create --repo march-language/march --base main --title "fix(refinecheck): callback argument binders and abstract-refinement definers at pass sites" --body-file <(sed -n '1,200p' specs/progress/2026-10-06-callback-binder-pass-sites.md)
```
Expected: `docs-exit=0` and a PR URL.

---

# PR B — abstract refinements, phase 2

Branch: `claude/abstract-refinements-phase2`, from `origin/main` **after PR A has merged**.

### Task B0: Baselines

- [ ] **Step 1: Record the oracle baseline and the cold-check time on the PR A merge base**

```bash
SCRATCH=/private/tmp/$(basename $PWD)-arB; mkdir -p $SCRATCH
dune build --root . bin/main.exe && scripts/refine-oracle.sh baseline $SCRATCH/oracle
for i in 1 2 3; do rm -rf .march/cas/vc .march/cas/artifacts-v2; H=$(mktemp -d); /usr/bin/time -p env HOME=$H ./_build/default/bin/main.exe --check --stdlib-source stdlib/list.march > /dev/null 2> $SCRATCH/time.$i; grep real $SCRATCH/time.$i; done
uptime
```
Write down the median `real` and the load average. The perf budget (Task B8) is the median plus 10%, measured at a similar load.

### Task B1: New obligation reasons

**Files:**
- Modify: `lib/refinecheck/obligation.ml` (`type reason` at about lines 10-127, `reason_name` at about 275, `reason_detail` at about 299)
- Modify: `lib/refinecheck/refine_call.ml`, the exhaustive reason matches at about lines 854-891 (the compiler will point at any others)
- Test: `test/test_refinecheck.ml`, new suite `abstract_phase2_suite`, registered as `("abstract-phase2", abstract_phase2_suite)` before `z3-well-formed`

**Interfaces:**
- Produces: `Obligation.Abstract_too_weak of string` (slug `abstract-refinement-too-weak`) and `Obligation.Abstract_uninstantiated of string` (slug `abstract-refinement-uninstantiated`).

- [ ] **Step 1: Write the failing test**

```ocaml
let abstract_phase2_suite =
  [ Alcotest.test_case "the two new reasons have stable slugs" `Quick (fun () ->
        let open March_refinecheck.Obligation in
        Alcotest.(check (pair string string)) "slugs"
          ("abstract-refinement-too-weak", "abstract-refinement-uninstantiated")
          (reason_name (Abstract_too_weak "w"), reason_name (Abstract_uninstantiated "u"))) ]
```

- [ ] **Step 2: Run and confirm it fails to compile**

Run: `dune build --root . test/test_refinecheck.exe 2>&1 | head`
Expected: an error, "Unbound constructor Abstract_too_weak".

- [ ] **Step 3: Implement**

In `type reason`:

```ocaml
  (* A call to a combinator with an abstract refinement (design 2026-09-20 §3.3):
     the instantiated predicate does not imply the demand.  Never a violation —
     whether a weaker predicate ever admits a bad element depends on the data. *)
  | Abstract_too_weak of string
  (* The abstract refinement could not be instantiated at this call: an opaque
     or named callable, a capturing lambda, or a callee whose own body is not
     proved (§3.1). *)
  | Abstract_uninstantiated of string
```

In `reason_name`: `| Abstract_too_weak _ -> "abstract-refinement-too-weak" | Abstract_uninstantiated _ -> "abstract-refinement-uninstantiated"`.
In `reason_detail`: `| Abstract_too_weak w -> w | Abstract_uninstantiated w -> w`.
Add the same constructors to every exhaustive match the compiler flags. In `refine_call.ml:854-891`, group them with `Parametric_source_unproved`, which has the same "not about the predicate's syntax" classification.

- [ ] **Step 4: Run and confirm it passes**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/obligation.ml lib/refinecheck/refine_call.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): abstract-refinement obligation reasons"
```

### Task B2: `$abs_p` inside the defining function: translation, sorts, preamble

**Files:**
- Modify: `lib/refinecheck/refine_encode.ml`: new definitions near `strlen_fn` (about line 108), plus arms in `mentions_str` (about 224), `wellsorted` (about 258), and `resolve_sorts_exact`'s `infer` (about 3071); and a new `abs_apps` and `abstract_preamble` after `wellsorted`
- Modify: `lib/refinecheck/refine_scope.ml`, a new arm in `smt_of_r_marked` (around line 307, before the measure arm)
- Modify: `lib/refinecheck/refine_check.ml`, `visit_fn` (save, set, and restore around lines 2510-2530)
- Modify: `lib/refinecheck/refine_call.ml`, the preamble assembly (about lines 2701-2730); and `lib/refinecheck/refine_post.ml`, the preamble (about line 688)
- Test: `test/test_refinecheck.ml`, `abstract_phase2_suite`

**Interfaces:**
- Produces in `Refine_encode`: `current_abstracts : string list ref`, `abs_sym : string -> string` (`"$abs_" ^ p`), `is_abs_sym : string -> bool`, `abstract_preamble : Smt.vc -> string`.

- [ ] **Step 1: Write the failing tests (design rows n5, n6)**

Add a shared fixture next to the suite:

```ocaml
let ar2_filt =
  {|  fn filt(xs : List(a), keep : ({x : a | true}) -> {Bool | _ == p(x)}) : List({a | p(_)}) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> if keep(h) do Cons(h, filt(t, keep)) else filt(t, keep) end
    end
  end
  fn sum_pos(xs : List({Int | _ > 0})) : Int do 0 end
|}
```

Append to `abstract_phase2_suite`:

```ocaml
    (* n5: the definition side.  `keep(h)` reflects (PR A) to
       `keep$ret == $abs_p(h)`; the Cons tail's goal is `$abs_p(h)`; the
       recursive tails take the structural hypothesis. *)
    gated "n5: filter's own body proves its abstract element return" (fun () ->
        let vs = verdicts_of ("mod N5 do\n" ^ ar2_filt ^ "end\n") "return of filt" in
        Alcotest.(check bool) "some" true (vs <> []);
        Alcotest.(check (list string)) "all proved" (List.map (fun _ -> "proved") vs) vs);

    (* n6: returning the input proves nothing about `p`. *)
    gated "n6: a body that ignores the callback does not prove" (fun () ->
        let vs =
          verdicts_of
            {|mod N6 do
  fn bad(xs : List(a), keep : ({x : a | true}) -> {Bool | _ == p(x)}) : List({a | p(_)}) do xs end
end|}
            "return of bad"
        in
        Alcotest.(check bool) "not proved" false (List.mem "proved" vs);
        Alcotest.(check bool) "not violated" false (List.mem "violated" vs));
```

- [ ] **Step 2: Run and confirm n5 fails**

Run: `dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: n5 FAILS with `skipped` verdicts (`unreflectable-predicate` on `p(_)`). n6 passes.

- [ ] **Step 3: Implement the symbol and sort machinery in `refine_encode.ml`**

Next to `strlen_fn`:

```ocaml
(* Abstract refinements (design 2026-09-20 §2a).  Inside the definition that
   declares `p`, `p(e)` is the uninterpreted Bool function [abs_sym p] over the
   element sort.  [current_abstracts] is the declaring function's set, set by
   [visit_fn] for the duration of its walk and empty everywhere else, so a
   call site never translates `p` (it is instantiated there, §2b).  The `$`
   prefix keeps the symbol out of the March namespace, as for [strlen_fn]. *)
let current_abstracts : string list ref = ref []
let abs_prefix = "$abs_"
let abs_sym (p : string) : string = abs_prefix ^ p
let is_abs_sym (f : string) : bool =
  String.length f > String.length abs_prefix
  && String.sub f 0 (String.length abs_prefix) = abs_prefix
```

In `mentions_str`, beside the `strlen_fn` arm: `| Smt.App (f, [ _ ]) when is_abs_sym f -> false`. The result is Bool; the argument's sort is `abstract_preamble`'s concern.

In `wellsorted`, beside the `strlen_fn` arm: `| Smt.App (f, [ _ ]) when is_abs_sym f -> true`.

In `resolve_sorts_exact`'s `infer`, beside the `strlen_fn` arm: `| Smt.App (f, [ a ]) when is_abs_sym f -> ignore (infer a); IBool`.

After `wellsorted`, add the collector and the preamble. `abs_apps` mirrors `mentions_str`'s full constructor list, so any constructor added later is a compile error here too:

```ocaml
(* Every abstract-refinement application in [t], with its argument. *)
let rec abs_apps (t : Smt.term) : (string * Smt.term) list =
  let m = abs_apps in
  match t with
  | Smt.App (f, [ a ]) when is_abs_sym f -> (f, a) :: m a
  | Smt.App (_, args) | Smt.Ctor (_, _, args) -> List.concat_map m args
  | Smt.IsCtor (_, a) | Smt.IsCtorAt (_, _, _, a) -> m a
  | Smt.Const _ | Smt.IntLit _ | Smt.BoolLit _ | Smt.FloatLit _ -> []
  | Smt.Not a | Smt.Neg a | Smt.MulLit (_, a) | Smt.DivLit (a, _) | Smt.ModLit (a, _) -> m a
  | Smt.Ite (c, a, b) -> m c @ m a @ m b
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Mul (a, b) | Smt.Div (a, b) | Smt.Mod (a, b)
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) | Smt.Eq (a, b) | Smt.Ne (a, b)
  | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b)
  | Smt.FpEq (a, b) | Smt.FpLt (a, b) | Smt.FpLe (a, b) | Smt.FpGt (a, b) | Smt.FpGe (a, b) ->
    m a @ m b
  | Smt.SetEmpty _ -> []
  | Smt.SetSng (_, a) | Smt.SetCard (_, a) -> m a
  | Smt.SetMem (_, a, b) | Smt.SetUnion (_, a, b) | Smt.SetInter (_, a, b)
  | Smt.SetDiff (_, a, b) | Smt.SetSub (_, a, b) -> m a @ m b

(* One `declare-fun` per abstract symbol the query mentions, at the sort of
   its argument (a declared constant: well-formedness rule 2 makes the
   argument the element binder, which always reflects to a constant; anything
   else defaults to Int, the element sort of an erased type variable).
   Emitted LAST in the preamble: a `$Str` or datatype argument sort must
   already be declared. *)
let abstract_preamble (vc : Smt.vc) : string =
  let seen : (string, Smt.sort) Hashtbl.t = Hashtbl.create 4 in
  List.iter
    (fun (f, a) ->
      if not (Hashtbl.mem seen f) then
        let s =
          match a with
          | Smt.Const c -> (match List.assoc_opt c vc.Smt.decls with Some s -> s | None -> Smt.SInt)
          | _ -> Smt.SInt
        in
        Hashtbl.replace seen f s)
    (List.concat_map abs_apps (vc.Smt.goal :: vc.Smt.assumptions));
  Hashtbl.fold
    (fun f s acc -> acc ^ Printf.sprintf "(declare-fun %s (%s) Bool)\n" f (Smt.string_of_sort s))
    seen ""
```

The `Set*` constructor arities above are written from `mentions_str`'s list. If the compiler disagrees on a constructor's arity, follow `smt.ml`'s `type term` (line 64): the match must be exhaustive and must recurse into every sub-term.

- [ ] **Step 4: Add the translation arm in `smt_of_r_marked` (`refine_scope.ml`)**

Insert before the measure arm (the one beginning `| A.EApp (A.EVar { A.txt = m0; _ }, [ a ], _) when is_measure_app m0`):

```ocaml
  (* An abstract refinement of the function being checked: uninterpreted
     (design 2026-09-20 §2a).  Only inside its declaring definition —
     [current_abstracts] is empty everywhere else. *)
  | A.EApp (A.EVar { A.txt = p; _ }, [ a ], _) when List.mem p !current_abstracts ->
    Result.map (fun t -> Smt.App (abs_sym p, [ t ])) (r a)
```

- [ ] **Step 5: Set `current_abstracts` in `visit_fn` (`refine_check.ml`)**

Next to `let saved_enclosing = !enclosing_fn in` add `let saved_abstracts = !current_abstracts in`. Next to `enclosing_fn := Some fd;` add:

```ocaml
  current_abstracts := Refine_abstract.names ~is_known:known_predicate_fn fd;
```

In the `Fun.protect ~finally` block, add `current_abstracts := saved_abstracts;`.

- [ ] **Step 6: Emit the declarations in both preamble sites**

In `refine_call.ml`, change the final expression of the `let preamble = …` block from

```ocaml
         mas
         ^ set_preamble ~elem_declared:(contains mas "(declare-sort Elem 0)")
             ~str_declared:(s <> "") ~measure_attached:(m <> "") vc
```
to
```ocaml
         mas
         ^ set_preamble ~elem_declared:(contains mas "(declare-sort Elem 0)")
             ~str_declared:(s <> "") ~measure_attached:(m <> "") vc
         ^ abstract_preamble vc
```

In `refine_post.ml`, after `let vc = { Smt.decls; assumptions; goal } in`, change the `let preamble = str_pre ^ …` expression to append `^ abstract_preamble vc` at the end. Wrap the existing `if … else ""` in parentheses so the append applies to both branches.

- [ ] **Step 7: Run and confirm n5 and n6 pass, and that every query is well-formed**

Run: `dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test abstract-phase2 && ./_build/default/test/test_refinecheck.exe test z3-well-formed`
Expected: all PASS. If n5 still shows a `sort-conflict` skip, check that the element constant's decl sort and the `declare-fun` argument sort agree. Print `Smt.assertion_block` together with the preamble for that query and compare.

- [ ] **Step 8: Commit**

```bash
git add lib/refinecheck/refine_encode.ml lib/refinecheck/refine_scope.ml lib/refinecheck/refine_check.ml lib/refinecheck/refine_call.ml lib/refinecheck/refine_post.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): abstract refinements are uninterpreted inside their definition (phase 2, §2a)"
```

### Task B3: Locate the definer and the element type variable

**Files:**
- Modify: `lib/refinecheck/refine_abstract.ml` (append)
- Test: `test/test_refinecheck.ml`, `abstract_phase2_suite`

**Interfaces:**
- Produces: `Refine_abstract.definer_index : is_known:(string -> bool) -> A.fn_def -> string -> int option`, the position (counting `FPPat` too) of the parameter whose type defines `p`.
- Produces: `Refine_abstract.positive_base : is_known:(string -> bool) -> A.fn_def -> string -> string option`, the `occ_base` of `p`'s first Positive occurrence (the element type, e.g. `"a"`).

- [ ] **Step 1: Write the failing test**

```ocaml
    Alcotest.test_case "definer_index and positive_base find filt's parts" `Quick (fun () ->
        let m = parse ("mod DI do\n" ^ ar2_filt ^ "end\n") in
        let fd =
          List.find_map
            (function
              | March_ast.Ast.DFn (fd, _) when fd.March_ast.Ast.fn_name.March_ast.Ast.txt = "filt" -> Some fd
              | _ -> None)
            m.March_ast.Ast.mod_decls
          |> Option.get
        in
        let is_known _ = false in
        Alcotest.(check (option int)) "index" (Some 1)
          (March_refinecheck.Refine_abstract.definer_index ~is_known fd "p");
        Alcotest.(check (option string)) "base" (Some "a")
          (March_refinecheck.Refine_abstract.positive_base ~is_known fd "p"));
```

`parse` (`test/test_refinecheck.ml:5`) returns an `Ast.module_` (`{ mod_name; mod_decls }`, `lib/ast/ast.ml:482`); `ret_refinement_of` (about line 2298) walks `DFn (fd, _)` the same way.

- [ ] **Step 2: Run and confirm it fails**

Run: `dune build --root . test/test_refinecheck.exe 2>&1 | head`
Expected: "Unbound value definer_index".

- [ ] **Step 3: Implement (append to `refine_abstract.ml`)**

```ocaml
(* Which parameter's type DEFINES abstract refinement [p] (holds its Definer
   occurrence)?  Counted over the first clause's parameters, patterns
   included, so the index lines up with a call's argument list. *)
let definer_index ~(is_known : string -> bool) (fd : A.fn_def) (p : string) : int option =
  if not (List.mem p (names ~is_known fd)) then None
  else
    match fd.A.fn_clauses with
    | [] -> None
    | c :: _ ->
      let defines (fp : A.fn_param) =
        match fp with
        | A.FPNamed prm | A.FPDefault (prm, _) ->
          let acc = ref [] in
          Option.iter (fun t -> walk_ty ~role:Negative t acc) prm.A.param_ty;
          List.exists (fun o -> o.occ_name = p && o.occ_role = Definer) !acc
        | A.FPPat _ -> false
      in
      let rec find i = function
        | [] -> None
        | fp :: rest -> if defines fp then Some i else find (i + 1) rest
      in
      find 0 c.A.fc_params

(* The element type [p] is applied at in the RETURN (its first Positive
   occurrence's base), e.g. "a" for `List({a | p(_)})`. *)
let positive_base ~(is_known : string -> bool) (fd : A.fn_def) (p : string) : string option =
  match List.assoc_opt p (collect ~is_known fd) with
  | None -> None
  | Some occs ->
    List.find_map (fun o -> if o.occ_role = Positive then Some o.occ_base else None) occs
```

The clause-parameter constructor names come from `signature_occurrences` (`A.FPNamed p | A.FPDefault (p, _)`, `A.FPPat _`); keep them identical.

- [ ] **Step 4: Run and confirm it passes**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: PASS. If `positive_base` returns a key other than `"a"` (`base_key` may render a type variable differently), make the test expect whatever `base_key (TyVar a)` returns. That key is what Task B5 passes to `parametric_ok`, so check that `parametric_ok`'s `vs` uses the same spelling (`refine_param.ml:463`).

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_abstract.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): locate an abstract refinement's definer and element type"
```

### Task B4: A declared abstract element return is not a call-site fact

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`: a new `entry_mentions` above `container_entry_of_expr` (about line 640); `declared_elem_return` (about lines 666-687)
- Test: `test/test_refinecheck.ml`, `abstract_phase2_suite`

**Interfaces:**
- Produces: `entry_mentions : string list -> string * elem option list -> bool`.
- Consumes: `callee_abstracts` (Task A4).

Why: once `filt` is in `elem_ret_proved` (Task B2 makes its body prove), `declared_elem_return` offers `{a | p(_)}` at every call. At a call site `p` has no translation, so every demand would become an `unreflectable-predicate` skip *before* Task B5's rule can run.

- [ ] **Step 1: Write the failing test**

```ocaml
    (* Before B5 lands, the call is a skip either way; what this pins is the
       REASON: not the call-site `p(_)` leaking through declared_elem_return. *)
    gated "a declared p(_) return is not offered as a call-site fact" (fun () ->
        let obs =
          typed_obligations
            ("mod DE do\n" ^ ar2_filt
           ^ "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y > 0)) end\nend\n")
        in
        Alcotest.(check bool) "no unreflectable-predicate on sum_pos" false
          (List.exists (fun (c, _, r) -> c = "sum_pos" && r = "unreflectable-predicate") obs));
```

- [ ] **Step 2: Run and confirm it fails**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: FAILS with `true`. If it passes, check that n5 really put `filt` in `elem_ret_proved`, and keep the test as a guard.

- [ ] **Step 3: Implement**

Above `container_entry_of_expr`:

```ocaml
(* Does an element entry's predicate apply any of [names]?  An entry naming a
   callee's abstract refinement (`{a | p(_)}`) is not a fact at a call site —
   `p` means something different at every call, and is instantiated there by
   [abstract_flow], never read from the declaration. *)
let entry_mentions (names : string list) ((_, slots) : string * elem option list) : bool =
  let rec slot = function
    | None -> false
    | Some (Refined (_, p, _)) ->
      List.exists (fun (n, _, _) -> List.mem n names) (Refine_abstract.applications p)
    | Some (Container (_, inner)) -> List.exists slot inner
  in
  names <> [] && List.exists slot slots
```

In `declared_elem_return`'s `Hashtbl.mem elem_ret_proved key` branch, change the guard `Some entry when entry_is_closed entry -> Some entry` to:

```ocaml
          | Some entry
            when entry_is_closed entry && not (entry_mentions (callee_abstracts ctx fname) entry) ->
            Some entry
```

`callee_abstracts` is defined above `check_pass_sites`, which comes before this function in the file. If OCaml reports it unbound, move `abstracts_tbl` and `callee_abstracts` up to just above `container_entry_of_expr`; both only need `resolve_key`, `fn_defs_tbl`, and `known_predicate_fn`. Leave the self-call hypothesis tier (`elem_ret_hyp`) alone: inside the definition, `p` does translate.

- [ ] **Step 4: Run and confirm it passes**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: all PASS. n5 must still pass, since the self-call hypothesis is untouched.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): an abstract element return is never read as a call-site fact"
```

### Task B5: Instantiate at a call, then discharge (design rows n, n2, n4)

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`: a new `abstract_flow` and `record_abstract_verdict` after `declared_elem_return`; a hook in `check_elements`' `A.EApp (A.EVar g, args, _)` arm (about line 840)
- Modify: `test/test_refinecheck.ml`: `abstract_phase2_suite`; update the phase-1 case "phase 1 is inert: row n still skips, nothing proves" (about line 17031)

**Interfaces:**
- Consumes: `callee_abstracts`, `entry_mentions`, `Refine_abstract.definer_index` / `positive_base`, the reasons from B1, and `parametric_ok ctx g vs` (`refine_param.ml:463`).
- Produces: `abstract_flow … : [ \`Proved | \`Too_weak of string | \`Uninstantiated of string | \`Undecided ] option`. `None` means "the callee declares no abstract element return; fall through to `demand_flow`".

- [ ] **Step 1: Write the failing tests**

```ocaml
    (* n: the flagship.  RED before: `parametric-source-unproved`. *)
    gated "n: an inline lambda instantiates p and proves the demand" (fun () ->
        Alcotest.(check (list string)) "proved" [ "proved" ]
          (verdicts_of
             ("mod N do\n" ^ ar2_filt
            ^ "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y > 0)) end\nend\n")
             "sum_pos"));

    (* n2: weaker lambda — a skip with the new reason, never a violation. *)
    gated "n2: a weaker lambda is too-weak, not violated" (fun () ->
        let obs =
          typed_obligations
            ("mod N2 do\n" ^ ar2_filt
           ^ "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y >= 0)) end\nend\n")
        in
        Alcotest.(check (list (pair string string))) "too weak"
          [ ("skipped", "abstract-refinement-too-weak") ]
          (List.filter_map (fun (c, v, r) -> if c = "sum_pos" then Some (v, r) else None) obs));

    (* n4: an opaque callable instantiates nothing. *)
    gated "n4: an opaque callback is uninstantiated" (fun () ->
        let obs =
          typed_obligations
            ("mod N4 do\n" ^ ar2_filt
           ^ "  fn go(ys : List(Int), k : ({x : Int | true}) -> Bool) : Int do sum_pos(filt(ys, k)) end\nend\n")
        in
        Alcotest.(check (list string)) "reason" [ "abstract-refinement-uninstantiated" ]
          (List.filter_map (fun (c, _, r) -> if c = "sum_pos" then Some r else None) obs));

    (* A lambda mentioning an outer name is declined, not mis-instantiated. *)
    gated "a capturing lambda is uninstantiated" (fun () ->
        let obs =
          typed_obligations
            ("mod NC do\n" ^ ar2_filt
           ^ "  fn go(ys : List(Int), m : Int) : Int do sum_pos(filt(ys, fn y -> y > m)) end\nend\n")
        in
        Alcotest.(check (list string)) "reason" [ "abstract-refinement-uninstantiated" ]
          (List.filter_map (fun (c, _, r) -> if c = "sum_pos" then Some r else None) obs));

    (* n6 at the call site: a callee whose body does not prove lends nothing. *)
    gated "an unproved definition lends nothing at its call" (fun () ->
        let obs =
          typed_obligations
            {|mod NB do
  fn bad(xs : List(a), keep : ({x : a | true}) -> {Bool | _ == p(x)}) : List({a | p(_)}) do xs end
  fn sum_pos(xs : List({Int | _ > 0})) : Int do 0 end
  fn go(ys : List(Int)) : Int do sum_pos(bad(ys, fn y -> y > 0)) end
end|}
        in
        Alcotest.(check bool) "not proved" false
          (List.exists (fun (c, v, _) -> c = "sum_pos" && v = "proved") obs));

    gated "cap verified: a proved demand compiles, a too-weak one is an error" (fun () ->
        let m body = "mod CV do\n  cap verified\n" ^ ar2_filt ^ body ^ "end\n" in
        Alcotest.(check bool) "proved compiles" false
          (has_refine_error_typed (m "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y > 0)) end\n"));
        Alcotest.(check bool) "too-weak errors" true
          (has_refine_error_typed (m "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y >= 0)) end\n")));
```

Update the phase-1 case at about line 17031. It calls `filt(zs, k)` with `k` an opaque parameter, so after this task it is the n4 shape. Rename it to `"opaque callback: row n4 stays unproved"` and keep its assertion `proved = 0, violated = 0`.

- [ ] **Step 2: Run and confirm n, n2, n4, and the capture case fail**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: those four FAIL, with reason `parametric-source-unproved`. NB and CV may already pass, or fail in the "proved compiles" half.

- [ ] **Step 3: Implement `abstract_flow` and `record_abstract_verdict`**

Place both after `declared_elem_return` and before the `let rec … check_elements` group. If they must reference something defined later in that group, define them as `and` members of it instead.

```ocaml
(* Design 2026-09-20 §3: a call [g(args)] to a combinator whose return is
   `List({a | p(_)})`, with a demand [slots] on its result.  Instantiate `p`
   from the actual at its definer position, then decide `q(v) ⇒ D(v)` for a
   fresh element `v` — one query, in a scratch ledger so a refutation is
   reported as too-weak rather than as a definite violation (§3.3, decision
   9.2).  [None]: [g] declares no abstract element return; the caller falls
   through to [demand_flow]. *)
let abstract_flow ~root defs (ctx : rctx) path lets sc re (cb : cbenv)
    ~(span : A.span) ~(callee : string) ((_, slots) : string * elem option list)
    (g : string) (args : A.expr list)
  : [ `Proved | `Too_weak of string | `Uninstantiated of string | `Undecided ] option =
  let abs = callee_abstracts ctx g in
  match resolve_key ctx g with
  | None -> None
  | Some key ->
    (match Hashtbl.find_opt fn_defs_tbl key, slots with
     | Some (_, fd), [ Some (Refined demand) ] ->
       (match elem_refinement fd.A.fn_ret_ty with
        | Some ((_, [ Some (Refined (rb, rpred, _)) ]) as ret_entry) when entry_mentions abs ret_entry ->
          let is_known = known_predicate_fn in
          (match rpred with
           | A.EApp (A.EVar { A.txt = p; _ }, [ A.EVar { A.txt = v; _ } ], _)
             when List.mem p abs && (v = rb || v = "_") ->
             let uninst w = Some (`Uninstantiated w) in
             if not (Hashtbl.mem elem_ret_proved key) then
               uninst (Printf.sprintf "`%s`'s own body is not proved to return elements satisfying `%s`" g p)
             else
               (match Refine_abstract.positive_base ~is_known fd p with
                | Some a when not (parametric_ok ctx g [ a ]) ->
                  uninst (Printf.sprintf "`%s` is not known to be parametric in `%s`" g a)
                | _ ->
                  (match Option.bind (Refine_abstract.definer_index ~is_known fd p) (List.nth_opt args) with
                   | Some (A.ELam ([ prm ], body, _)) ->
                     let y = prm.A.param_name.A.txt in
                     if classify_pred y [] body <> Closed then
                       uninst "the lambda mentions a name other than its own parameter"
                     else
                       let ((_, dpred, dsort) as d) = demand in
                       let sg = elem_sig ~name:"$elem" d in
                       let rp = List.hd sg.refined in
                       let sc' = ("$elem", (y, body, dsort)) :: scope_shadow sc [ "$elem" ] in
                       let cx =
                         { root; errctx = Err.create (); postcond = postcond_of ~cb ctx defs; path; lets
                         ; sc = sc'; re; binds = ctx.binds }
                       in
                       let out = ref None in
                       let saved_strict = !strict_verified and saved_hinted = !unverified_hinted in
                       Fun.protect
                         ~finally:(fun () ->
                           strict_verified := saved_strict;
                           unverified_hinted := saved_hinted)
                         (fun () ->
                           Obligation.with_scratch (fun () ->
                               strict_verified := false;
                               check_call cx ~span ~callee ~subject:Element_domain ~verdict_out:out sg
                                 [ A.EVar { A.txt = "$elem"; A.span = span } ] rp));
                       (match !out with
                        | Some Obligation.Proved -> Some `Proved
                        | Some Obligation.Violated ->
                          Some
                            (`Too_weak
                              (Printf.sprintf "`fn %s -> %s` does not imply `%s`" y (pred_str body)
                                 (pred_str dpred)))
                        | _ -> Some `Undecided)
                   | Some (A.ELam _) -> uninst "the lambda does not take exactly one parameter"
                   | Some _ ->
                     uninst "the predicate is not an inline one-parameter lambda (named functions: phase 3)"
                   | None -> uninst "no argument at the definer position"))
           | _ -> Some (`Uninstantiated "the element return is not exactly `p(_)`"))
        | _ -> None)
     | _ -> None)

(* Record an [abstract_flow] verdict at the demanding call; escalate a skip
   under `cap verified` the way [record_param_skip] does.  Returns whether the
   demand was proved, as [check_elements]' arms do. *)
let record_abstract_verdict errctx ~(span : A.span) ~(callee : string) ~(predicate : string) v : bool =
  let verdict =
    match v with
    | `Proved -> Obligation.Proved
    | `Too_weak w -> Obligation.Skipped (Obligation.Abstract_too_weak w)
    | `Uninstantiated w -> Obligation.Skipped (Obligation.Abstract_uninstantiated w)
    | `Undecided -> Obligation.Skipped Obligation.Solver_undecided
  in
  Obligation.record { Obligation.span; callee; predicate; verdict; kind = Obligation.Precondition };
  (match verdict with
   | Obligation.Skipped r when !strict_verified ->
     Err.error errctx ~span
       (Printf.sprintf
          "`cap verified` module: cannot verify element refinement `%s` on `%s` (%s: %s)\n\
           note: pass a predicate that implies the refinement, or remove `cap verified` from this module"
          predicate callee (Obligation.reason_name r) (Obligation.reason_detail r))
   | _ -> ());
  verdict = Obligation.Proved
```

Names to confirm against the current code before compiling (the compiler will flag a mismatch):
- `pred_str` (used in `check_pass_sites`);
- the `call_ctx` field set (`root; errctx; postcond; path; lets; sc; re; binds`, as at `refine_check.ml:437`);
- `Closed` (constructor of `pred_scope`, as used by `entry_is_closed`);
- `elem_sig ~name` (`refine_scope.ml:1428`).

- [ ] **Step 4: Hook it into `check_elements`**

In the `| A.EApp (A.EVar { A.txt = g; _ }, args, _) ->` arm (about line 840), wrap the existing `demand_flow` match:

```ocaml
        | A.EApp (A.EVar { A.txt = g; _ }, args, _) ->
          (match
             abstract_flow ~root defs ctx path lets sc re cb ~span:xsp ~callee (container, slots) g args
           with
           | Some v -> record_abstract_verdict errctx ~span:xsp ~callee ~predicate:(first_slot_pred slots) v
           | None ->
             (match
                demand_flow ~root errctx defs ctx path lets sc re cb ce ~span ~callee (container, slots) g args
              with
              (* … the three existing arms, unchanged … *)))
```

- [ ] **Step 5: Run and confirm everything passes**

Run: `dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test abstract-phase2 && ./_build/default/test/test_refinecheck.exe test abstract-refinements && ./_build/default/test/test_refinecheck.exe test demand-flow`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): instantiate an abstract refinement from an inline lambda at its call (phase 2, §3)"
```

### Task B6: Conjunction with the input's own element fact (design row n1)

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`, `abstract_flow`, the inline-lambda branch
- Test: `test/test_refinecheck.ml`, `abstract_phase2_suite`

- [ ] **Step 1: Write the failing tests**

```ocaml
    (* n1: the lambda alone (`y < 100`) does not give `> 0`; the input's own
       element fact does.  RED before: too-weak. *)
    gated "n1: the input's element fact conjoins with the lambda" (fun () ->
        Alcotest.(check (list string)) "proved" [ "proved" ]
          (verdicts_of
             ("mod N1 do\n" ^ ar2_filt
            ^ "  fn go(ys : List({Int | _ > 0})) : Int do sum_pos(filt(ys, fn y -> y < 100)) end\nend\n")
             "sum_pos"));

    gated "n1 control: an unrefined input lends nothing" (fun () ->
        let obs =
          typed_obligations
            ("mod N1C do\n" ^ ar2_filt
           ^ "  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> y < 100)) end\nend\n")
        in
        Alcotest.(check (list string)) "too weak" [ "abstract-refinement-too-weak" ]
          (List.filter_map (fun (c, _, r) -> if c = "sum_pos" then Some r else None) obs));
```

- [ ] **Step 2: Run and confirm n1 fails**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: n1 FAILS (too-weak). The control passes.

- [ ] **Step 3: Implement**

In `abstract_flow`, just before `let ((_, dpred, dsort) as d) = demand in`, compute the incoming fact and replace `body` in the scope entry with `body'`:

```ocaml
                       (* §3.4: an element of the result is an element of the
                          input it came from, so the input's own element fact
                          holds of it too.  Only through a source the
                          parametric rule accepts (already gated above), and
                          only for a single [Src_elem] source. *)
                       let body' =
                         match
                           Option.bind (resolve_call ctx defs g |> Option.join) (fun sg ->
                               Option.bind (Refine_abstract.positive_base ~is_known fd p) (sources_of sg))
                         with
                         | Some [ Src_elem (j, _) ] ->
                           (match
                              Option.bind (List.nth_opt args j) (container_entry_of_expr ctx defs cb ce)
                            with
                            | Some (_, [ Some (Refined (b0, q0, _)) ]) ->
                              A.EApp
                                ( A.EVar { A.txt = "&&"; A.span = span }
                                , [ subst_params [ (b0, A.EVar { A.txt = y; A.span = span }) ] q0; body ]
                                , span )
                            | _ -> body)
                         | _ -> body
                       in
```

Then use `(y, body', dsort)` in `sc'`. `abstract_flow` now needs `ce : contenv`. Add it to the signature after `cb`, and pass `ce` at the hook in `check_elements`. Confirm before compiling:
- `resolve_call ctx defs g` returns `fn_sig option option` (it is used that way in `callee_sig`);
- `sources_of`'s signature is `fn_sig -> string -> source list option` (`refine_param.ml:540`), with `Src_elem of int * _`.

Adjust the `Option.bind` plumbing to the real types. The rule stays the same: exactly one `Src_elem` source, and that argument's entry must be a single `Refined` slot.

- [ ] **Step 4: Run and confirm all pass**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): conjoin the input's element fact with an instantiated abstract refinement (§3.4)"
```

### Task B7: The `let`-bound result

**Files:**
- Modify: `lib/refinecheck/refine_check.ml`, `check_elements`' `A.EVar _` no-entry arm (about line 836)
- Test: `test/test_refinecheck.ml`, `abstract_phase2_suite`

Why: `let zs = filt(ys, fn y -> y > 0)` and then `sum_pos(zs)` is the common spelling. Task B4 keeps `{a | p(_)}` out of `ce`, so `zs` has no entry. The `lets` channel already records `zs -> filt(…)` for a `let` whose right-hand side is an application (`refine_check.ml:1390`). `launder_shadow` already retires that record when `zs`, or any name its right-hand side mentions, is rebound. So the call can be re-examined soundly at the use.

- [ ] **Step 1: Write the failing tests**

```ocaml
    gated "a let-bound filter result carries the instantiated fact" (fun () ->
        Alcotest.(check (list string)) "proved" [ "proved" ]
          (verdicts_of
             ("mod NL do\n" ^ ar2_filt
            ^ "  fn go(ys : List(Int)) : Int do\n    let zs = filt(ys, fn y -> y > 0)\n    sum_pos(zs)\n  end\nend\n")
             "sum_pos"));

    gated "rebinding the name retires it" (fun () ->
        Alcotest.(check bool) "not proved" false
          (List.mem "proved"
             (verdicts_of
                ("mod NLR do\n" ^ ar2_filt
               ^ "  fn go(ys : List(Int)) : Int do\n    let zs = filt(ys, fn y -> y > 0)\n    let zs = ys\n    sum_pos(zs)\n  end\nend\n")
                "sum_pos")));

    gated "rebinding the input retires it" (fun () ->
        Alcotest.(check bool) "not proved" false
          (List.mem "proved"
             (verdicts_of
                ("mod NLI do\n" ^ ar2_filt
               ^ "  fn go(ys : List(Int), ws : List(Int)) : Int do\n    let zs = filt(ys, fn y -> y > 0)\n    let ys = ws\n    sum_pos(zs)\n  end\nend\n")
                "sum_pos")));
```

The third case is deliberately conservative. Rebinding `ys` does not change `zs`'s elements, but `launder_shadow` retires the record anyway. That is safe, so assert "not proved" and comment that it is a known precision loss, not a soundness requirement.

- [ ] **Step 2: Run and confirm the first case fails**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: the let-bound case FAILS (`skipped`). The other two pass.

- [ ] **Step 3: Implement**

Replace the `| A.EVar _ -> record_elem_skip …; false` arm with:

```ocaml
        | A.EVar { A.txt = xv; _ } ->
          (* A name let-bound to a call with an abstract element return
             (`let zs = List.filter(ys, fn y -> y > 0)`): re-examine that call
             here.  The [lets] channel retires the record when [xv] or any
             name the call mentions is rebound, so the call still denotes
             [xv]'s value. *)
          let via_let =
            match List.assoc_opt xv lets with
            | Some (A.EApp (A.EVar { A.txt = g; _ }, args, _)) ->
              abstract_flow ~root defs ctx path lets sc re cb ce ~span:xsp ~callee (container, slots) g args
            | _ -> None
          in
          (match via_let with
           | Some v -> record_abstract_verdict errctx ~span:xsp ~callee ~predicate:(first_slot_pred slots) v
           | None ->
             record_elem_skip errctx ~span:xsp ~callee ~predicate:(first_slot_pred slots)
               ~what:(Printf.sprintf "the elements of `%s` are not known to satisfy it (no declared element refinement in scope)" x);
             false)
```

Check the type of `lets`: if it is `launder` (`(string * A.expr) list`), `List.assoc_opt` works as written. The `lets` comment (`refine_scope.ml:1249-1267`) says the channel "carries NO solver-visible fact". Update it: it now also lets [check_elements] re-examine an abstract-refinement call. Keep that comment change in this commit.

- [ ] **Step 4: Run and confirm all pass**

Run: `./_build/default/test/test_refinecheck.exe test abstract-phase2`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml lib/refinecheck/refine_scope.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): a let-bound abstract-refinement result is re-examined at its use"
```

### Task B8: `List.filter` declares `p`; conformance pair; sweeps

**Files:**
- Modify: `stdlib/list.march:297` (`filter`)
- Create: `specs/lang/types/accept/t296_refine_abstract_filter_proves.march`, `specs/lang/types/reject/t297_refine_abstract_filter_too_weak.march`
- Modify: `specs/lang/types/INDEX.md` (header counts and two rows)
- Modify: `test/refine_audit/corpus.baseline` (regenerated)

- [ ] **Step 1: Write the conformance pair (fails until the signature changes)**

`accept/t296_refine_abstract_filter_proves.march`:

```march
-- Abstract refinements, phase 2 (specs/2026-09-20-abstract-refinements-design.md
-- rows n, n1 and the let-bound result): `List.filter` instantiates its abstract
-- refinement `p` from an inline lambda at each call, so its result's elements
-- satisfy the lambda.  Under `cap verified` every obligation must be PROVED,
-- so exit 0 here means each demand proved, not skipped.  Reject companion:
-- reject/t297 (a weaker lambda).
mod AbsFilter do
  cap verified
  fn sum_pos(xs : List({Int | _ > 0})) : Int do List.fold_left(xs, 0, fn (a, b) -> a + b) end
  fn direct(ys : List(Int)) : Int do sum_pos(List.filter(ys, fn y -> y > 0)) end
  fn conj(ys : List({Int | _ > 0})) : Int do sum_pos(List.filter(ys, fn y -> y < 100)) end
  fn bound(ys : List(Int)) : Int do
    let zs = List.filter(ys, fn y -> y > 0)
    sum_pos(zs)
  end
end
```

`reject/t297_refine_abstract_filter_too_weak.march`:

```march
-- EXPECT-ERROR: abstract-refinement-too-weak
-- Abstract refinements, phase 2 (design row n2): `fn y -> y >= 0` admits 0,
-- which `{Int | _ > 0}` does not.  Not a violation (an empty input is fine);
-- a too-weak skip, which `cap verified` turns into this error.  Accept
-- companion: accept/t296.
mod AbsFilterWeak do
  cap verified
  fn sum_pos(xs : List({Int | _ > 0})) : Int do List.fold_left(xs, 0, fn (a, b) -> a + b) end
  fn weak(ys : List(Int)) : Int do sum_pos(List.filter(ys, fn y -> y >= 0)) end
end
```

`sum_pos`'s body forwards `xs` to `List.fold_left`, whose callback `(a, b) -> a + b` has two parameters; it owes no element obligation. If either file reports an obligation from that body, replace the body with `0` and an unused-parameter-safe spelling (`fn sum_pos(_xs : …) : Int do 0 end`).

- [ ] **Step 2: Run the pair and confirm both fail**

```bash
dune build --root . bin/main.exe && for f in specs/lang/types/accept/t296_*.march specs/lang/types/reject/t297_*.march; do HOME=$SCRATCH/home ./_build/default/bin/main.exe --check $f > $SCRATCH/$(basename $f).out 2>&1; echo "$f exit=$?"; done
```
Expected: t296 exits 1 (`cap verified` cannot verify, reason `parametric-source-unproved`). t297 exits 1 but without the `abstract-refinement-too-weak` text. Both are wrong until Step 3.

- [ ] **Step 3: Change `List.filter`'s signature**

In `stdlib/list.march`:

```march
  fn filter(xs : List(a), pred : ({x : a | true}) -> {Bool | _ == p(x)})
      : {List({a | p(_)}) | subset(elts(_), elts(xs))} do
```

The body is unchanged. Add one docstring paragraph above the existing doctests:

```
  The result's elements satisfy the predicate: with `sum_pos(xs : List({Int | _ > 0}))`,
  `sum_pos(List.filter(ys, fn y -> y > 0))` is proved. `p` is an abstract
  refinement, instantiated from the lambda at each call.
```

If the parser rejects a signature split across two lines here, keep it on one line.

- [ ] **Step 4: Run the pair and confirm both pass**

Run the Step 2 loop again, then `grep -c abstract-refinement-too-weak $SCRATCH/t297_*.out`.
Expected: t296 `exit=0`; t297 `exit=1`, with a grep count ≥ 1. Then run `bash specs/lang/types/check_types.sh | tail -3`; expected: every program behaves as declared.

- [ ] **Step 5: Update `specs/lang/types/INDEX.md`**

In the header, change `t01–t293 accept, t01–t295 reject` to `t01–t296 accept, t01–t297 reject`, and the file counts `175 accept, 241 reject` to `176 accept, 242 reject`. Add a row for each file, in the same table style as the `t75`/`t76` rows. Then run `scripts/check-docs.sh`: Check C validates these counts.

- [ ] **Step 6: Stdlib and ratchet checks**

```bash
scripts/run-tests.sh stdlib stdlib_march > $SCRATCH/stdlib.log 2>&1; echo exit=$?
rm -rf .march/cas/artifacts-v2; HOME=$SCRATCH/home ./_build/default/bin/main.exe --check --stdlib-source --refine-report stdlib/list.march > $SCRATCH/ratchet.txt 2>&1; grep 'user + stdlib' $SCRATCH/ratchet.txt
HOME=$SCRATCH/home ./_build/default/bin/main.exe --check --stdlib-source --refine-audit stdlib/list.march 2>&1 | grep -i unenforced
```
Expected: `exit=0`; skipped ≤ 42; unenforced 0. If the skipped count rose, list the new sites with `--refine-report-sites` and trace each one to its cause before going further. The intended behaviour is zero new skips, because every `List.filter` call without a demand records nothing (Task A4 / B4).

- [ ] **Step 7: Regenerate the audit baselines and run the oracle**

```bash
UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe test audit-baseline; ./_build/default/test/test_refinecheck.exe test audit-baseline
git diff --stat test/refine_audit/
scripts/refine-oracle.sh check $SCRATCH/oracle; echo exit=$?
```
Expected: the audit diff is only "enforced" counts rising by the new `filter` contract. The oracle diff contains only skip→proved changes at `List.filter` demands, or skip-reason changes from `parametric-source-unproved` to an `abstract-refinement-*` reason. **Any new `violated` line is a STOP.** Put each changed line and its reason in the progress note.

- [ ] **Step 8: Ecosystem sweep**

For each of `/Users/80197052/code/conduit` and `/Users/80197052/code/depot` that exists, run its `--check` with `MARCH_LIB_PATH` set (see CLAUDE.md "Multi-file compilation"), once with a main-built compiler and once with this branch's. Compare the `--refine-report` lines.
Expected: identical outcomes, apart from skip→proved changes. Neither repo has a `cap verified` module (checked 2026-10-06), so no exit code may change.

- [ ] **Step 9: Cache and performance**

Run t296 twice with a warm VC cache, then t297 right after:

```bash
for f in specs/lang/types/accept/t296_*.march specs/lang/types/accept/t296_*.march specs/lang/types/reject/t297_*.march; do HOME=$SCRATCH/home ./_build/default/bin/main.exe --check $f > /dev/null 2>&1; echo "$f exit=$?"; done
```
Expected: 0, 0, 1. The second lambda's query must not inherit the first's verdict; the cache key is the full query text, and this confirms it. Then rerun the Task B0 timing loop. Expected: the median is within 110% of the B0 median, at a comparable load average. Record both numbers in the progress note.

- [ ] **Step 10: Commit**

```bash
git add stdlib/list.march specs/lang/types/accept/t296_refine_abstract_filter_proves.march specs/lang/types/reject/t297_refine_abstract_filter_too_weak.march specs/lang/types/INDEX.md test/refine_audit/corpus.baseline
git commit -m "feat(stdlib): List.filter's result carries its predicate (abstract refinement p)"
```

### Task B9: Full verification, documentation, PR B

**Files:**
- Modify: `specs/lang/refinement-types.md` (+ regenerated `docs/refinement-types.md`)
- Modify: `specs/todos/2026-09-18-refine-element-flow-followups.md` (close item 6)
- Modify: `specs/2026-09-20-abstract-refinements-design.md` (status line)
- Create: `specs/progress/2026-MM-DD-abstract-refinements-phase2.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Full suites**

```bash
uptime; scripts/run-tests.sh > $SCRATCH/full.log 2>&1; echo exit=$?; grep -E 'tests run|\[FAIL\]|All suites' $SCRATCH/full.log
```
Expected: `exit=0`, `All suites passed.` If something fails, compare against `origin/main` before attributing it to this branch: some suites fail on main itself.

- [ ] **Step 2: Language reference**

In `specs/lang/refinement-types.md`:
- Delete the bullet "**`filter` does not produce a refinement it was not given.**" in "What element refinements do not do".
- Add a subsection `### Abstract refinements: \`filter\` keeps what its predicate says` after "Callbacks and user-written combinators". Cover:
  - the signature;
  - rows n, n1, n2, n4 as examples;
  - the reasons `abstract-refinement-too-weak` and `abstract-refinement-uninstantiated`;
  - what v1 does not do: named-function predicates (phase 3), arity > 1 (`Map.filter`, `fold_left`), `p` over a bare scalar, `impl` dispatch, the `a[p]` shorthand (phase 4), and a capturing lambda.

Then run `python3 scripts/gen-lang-docs.py`.

- [ ] **Step 3: Close the todo item and note the design status**

In `specs/todos/2026-09-18-refine-element-flow-followups.md`, strike item 6 the same way item 5 is struck (`~~…~~ **Closed 2026-MM-DD**`), pointing at the progress note. Leave the file in `todos/`: items 1-4 are still open. In the design doc's header, add `**Status:** phase 1 landed 2026-09-21; phase 2 landed 2026-MM-DD (PR A + PR B).`

- [ ] **Step 4: Progress note and CHANGELOG**

The progress note records:
- what landed, per task;
- the probe table before and after;
- the oracle and audit diffs, explained;
- the ratchet count;
- the timing numbers and load;
- the deviations from the design: let-bound lambdas and named predicates are not instantiated (phase 3); the too-weak detail names the lambda and the demand, with no witness value; the let-bound result is handled through the `lets` channel rather than `ce`.

`CHANGELOG.md` → `### Added`:

```markdown
- **`List.filter` keeps what its predicate says.** `sum_pos(List.filter(ys, fn y -> y > 0))`
  now proves a `List({Int | _ > 0})` demand, directly or through a `let`, and
  combines with the input's own element refinement. A predicate too weak for
  the demand is reported as `abstract-refinement-too-weak` (an error only under
  `cap verified`). This is the first abstract refinement (a refinement
  parameterised by a predicate); see "Abstract refinements" in the refinement
  types reference.
```

- [ ] **Step 5: Lint, commit, push, open the PR**

```bash
scripts/check-docs.sh; echo docs-exit=$?
git add specs/lang/refinement-types.md docs/refinement-types.md specs/todos/2026-09-18-refine-element-flow-followups.md specs/2026-09-20-abstract-refinements-design.md specs/progress/2026-MM-DD-abstract-refinements-phase2.md CHANGELOG.md
git commit -m "docs: abstract refinements phase 2"
git push -u origin claude/abstract-refinements-phase2
gh pr create --repo march-language/march --base main --title "feat(refinecheck): abstract refinements phase 2 — List.filter keeps its predicate" --body-file specs/progress/2026-MM-DD-abstract-refinements-phase2.md
```
Expected: `docs-exit=0` and a PR URL.

---

## Self-review against the design

| Design item | Task |
|---|---|
| §2a uninterpreted `$abs_p`, declaration, sort acceptance | B2 |
| §3.1 instantiation from an inline lambda | B5 |
| §3.1 instantiation from a `let`-bound lambda via `cbenv` | **deferred to phase 3**: `cbenv` stores a signature, not a body (recorded as a deviation in B9) |
| §3.2 substitution; P1/P2 gate on `a` | B5 (`parametric_ok`), B4 (declared entry excluded) |
| §3.3 discharge `q ⇒ D`; refuted → too-weak skip; undecided → skip | B5 |
| §3.4 conjunction with the incoming fact | B6 |
| §3.5 negative occurrences | not exercised by any phase-2 stdlib function; the design says "tests cover it with a fixture" → **gap**: add a fixture in B5 if `check_arg_elements` reaches it, otherwise file it in the phase-2 progress note as open |
| §3.6 warning exemption | landed in phase 1 |
| §4 definition-side proof; §4.3 negative | B2 (n5, n6), B5 (NB at the call site) |
| §5 every new assumption has a reject/skip control | CB2, CB4, CB6, AP3, n6, NB, n2, NC, N1C, NLR, t297 |
| §7 phase 2: oracle diff explained, full sweep, audit regen | B8 Steps 6-8 |
| §8 cache key includes `q`; perf ≤ 110% | B8 Step 9 |
| Existing `subset` contract on `filter` kept | B8 Step 3 (combined return; probe a3) |
| CI ratchet ≤ 42 | A5 Step 3, B8 Step 6 |
