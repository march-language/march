# Abstract Refinements Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** an abstract refinement can be instantiated from a **named predicate**, a **callback parameter** passed through, or a **`let`-bound lambda**, as well as from an inline lambda. `List.find`, `Option.filter` and `List.take_while` also carry `p`.

**Architecture:** every instantiation path goes through one function, `instantiate_abstract` (`lib/refinecheck/refine_check.ml`). It returns `(param, predicate)` or a reason it can't. Phase 3 widens what it accepts, and nothing downstream changes:
- **Named callable:** read its *proved* return `{Bool | _ == e}` (or `e == _`) over its single parameter, from `callee_sig`. That function already returns only proved returns, which probe r5 confirmed.
- **Callback parameter:** its signature's `ret`, which PR A rewrote over `$cb_arg`.
- **`let`-bound lambda:** the `lets` channel also records `name → ELam` (it already records `name → EApp` and copies aliases forward). Its one other consumer, `alias_withdrawal_cause`, is restricted to application entries.
- **Inline lambda that is just a call `fn y -> g(y)`:** eta-reduced to `g`.

The three stdlib functions need only their signatures changed (probes r2–r4), plus a natural-style rewrite of `take_while`, which TRMC turns into a loop.

**Tech Stack:** OCaml 5.3 (dune), z3, alcotest.

**Prerequisite:** [march-language/march#844](https://github.com/march-language/march/pull/844) (phase 2, including §3.5 and the 2026-10-07 pressure-test fixes) merged to `main`. Branch `claude/abstract-refinements-phase3` from `origin/main` after it merges.

## Global Constraints

- Build and test with `--root .` from the worktree, and use `scripts/run-tests.sh` for suites. `z3` must be on PATH (`command -v z3`).
- After editing `stdlib/*.march`, restage it before probing the CLI: `dune build --root . bin/main.exe $(ls stdlib/*.march | tr '\n' ' ')`. A targeted `bin/main.exe` build does NOT refresh `_build/default/stdlib/` (found 2026-10-06).
- Probe with a **fresh** private `HOME` after a stdlib change; a warm `~/.cache/march` serves the old stdlib.
- Capture an exit code immediately: `cmd; e=$?`. Never write `$?` after a `$(…)` in the same `echo`, which resets it (found 2026-10-06).
- `use`, `loop`, `init`, `within`, `app`, `opaque` are keywords. Don't name probe functions after them.
- Element obligations are recorded under the **argument's** name (`pos`, `xs`, `filt(…)`), not the callee's. Assert whole-module `typed_ledger` triples for single-call fixtures, or filter `typed_obligations` by source line (see test SN).
- Every new rule has a fixture that FAILS without it. Prove it with a one-line perturbation, then restore. Assert triples or verdict lists, never exit codes alone.
- Definite-failure stance: an instantiated predicate too weak for a **result** demand is a skip (`abstract-refinement-too-weak`), never a violation. A **parameter** demand (§3.5) uses ordinary element subtyping, where a definite failure is a violation.
- CI ratchet: `(user + stdlib)` skipped for `stdlib/list.march` ≤ 42 (37 today); `--refine-audit` unenforced = 0.
- Stage files by name; no attribution lines. Each PR ships its CHANGELOG bullet, progress note and todo closure in the same commit set. Edit `specs/lang/`, run `scripts/gen-lang-docs.py`, commit both.

## Pressure test (2026-10-07, branch tip `a9a0c4b3d`)

Every row was run with the CLI under a private `HOME`. Probe sources are in the session scratchpad; the fixtures below restate them.

| # | Program | Today | Phase 3 target | Notes |
|---|---|---|---|---|
| q01 | `filt(ys, is_pos)`, `is_pos(n) : {Bool \| _ == (n > 0)}` proved | uninstantiated | **proved** (C1) | |
| q02 | same, `is_pos : Bool` (no contract) | uninstantiated | uninstantiated | no inference |
| q03 | `{Bool \| (n > 0) == _}` (flipped) | uninstantiated | **proved** (C1) | both orientations |
| q04 | `keep_pos(ys, k : ({x : Int \| true}) -> {Bool \| _ == (x > 0)}) = sum_pos(filt(ys, k))` | uninstantiated | **proved** (C1) | callback sig `ret` is over `$cb_arg` (PR A) |
| q05 | `let f = fn y -> y > 0` then `filt(ys, f)` | uninstantiated | **proved** (C2) | |
| q06 | `fn y -> gt(y, 0)`, two-parameter `gt` | uninstantiated (was a false *too-weak* before `a9a0c4b3d`) | uninstantiated | only a bare `g(y)` eta-reduces |
| q07 | `fn y -> is_pos(y)` | uninstantiated (was false too-weak) | **proved** (C1, eta) | |
| q09b | §3.5 with `List({String \| len(_) > 0})` | **was a false VIOLATION**, fixed in `a9a0c4b3d` | proved | regression guard |
| q10 | `filt(ys, fn s -> String.byte_size(s) > 0)` against `List({String \| len(_) > 0})` | proved | proved | String sorts work on the result path |
| r1 | concrete `Option({Int \| _ > 0})` return, natural recursion | proved | — | Option slots already work |
| r2 | user `find` with abstract sig: own body, `y > 0` call, `y >= 0` call | proved / proved / too-weak | same | `List.find` needs only its signature |
| r3 | user `Option.filter` copy: direct and combined with an incoming fact | proved / proved | same | `Option.filter` needs only its signature |
| r4 | natural-style `take_while` with abstract sig, body and call | proved / proved | same | the current accumulator body cannot prove (local `go` + `reverse`) |
| r5 | `is_pos` whose return is NOT proved (calls an unrefined helper) | pass-site skip "declares no proved return" | never used to instantiate | `callee_sig` hides unproved returns |
| tw | `take_while` natural vs accumulator, compiled `--opt 2`, 60 × 150k prefix of 200k | — | — | `TRMCXFORM tw_nat -> tw_nat$dps`; after warm-up natural **0.13–0.15 s** vs accumulator **0.18–0.19 s** |

**Out of scope, with reasons:**
- `Deque.filter` (internal representation; would need `@[assume]` plus a runtime test).
- `List.partition` (`p` inside a tuple and under `not`, neither designed).
- `drop_while` (no element fact).
- `Map.filter`, and `fold_left`'s accumulator (two-argument predicates; `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md`).
- `Seq.*` (untyped).
- A named predicate with more than one parameter, or one whose return is not exactly `_ == e`.
- Inferring a contract for an unannotated predicate.
- Phase 4 shorthand `a[p]`.

## File map

| File | Change |
|---|---|
| `lib/refinecheck/refine_check.ml` | `instantiate_abstract` takes `~named` and `~local_lambda` lookups; new `named_predicate`; `abstract_flow` / `abstract_param_entry` / `check_arg_elements` pass them; `visit`'s `lets` fold records `ELam` RHS |
| `lib/refinecheck/refine_call.ml` | `alias_withdrawal_cause` reads only application entries of `lets` |
| `lib/refinecheck/refine_scope.ml` | the `launder` channel comment |
| `stdlib/list.march` | `find`, `take_while` (natural style) signatures + doc line |
| `stdlib/option.march` | `filter` signature + doc line |
| `test/test_refinecheck.ml` | suite `abstract-phase3` |
| `test/stdlib/test_list.march` | `take_while` edge cases (the body is rewritten) |
| `specs/lang/types/{accept,reject}/tNNN_*` + `INDEX.md` | conformance pair over the three stdlib functions |
| `test/refine_audit/*.baseline` | regenerated |
| `specs/lang/refinement-types.md` (+ `docs/`) | the abstract-refinements section |

Test command: `dune build --root . test/test_refinecheck.exe 2>&1 | head -30 && ./_build/default/test/test_refinecheck.exe test abstract-phase3`

---

### Task C0: Baselines

- [ ] **Step 1:** Build and record the oracle baseline and timing on the `origin/main` that contains #844.

```bash
SCRATCH=/private/tmp/$(basename $PWD)-ar3; mkdir -p $SCRATCH
dune build --root . bin/main.exe $(ls stdlib/*.march | tr '\n' ' ') && scripts/refine-oracle.sh baseline $SCRATCH/oracle
cp _build/default/bin/main.exe $SCRATCH/main-base.exe   # for the B/A timing in C5
```
Expected: `baseline recorded … (N lines over 468+ fixtures)`.

### Task C1: Named predicates, callback parameters, and eta-reduced calls

**Files:** `lib/refinecheck/refine_check.ml` (`instantiate_abstract`, new `named_predicate`, call sites in `abstract_flow` and `abstract_param_entry`); `test/test_refinecheck.ml` (new suite `abstract_phase3_suite`, registered before `z3-well-formed`).

**Interfaces:**
- Produces `named_predicate : (string -> fn_sig option) -> string -> (string * A.expr) option`. Given a resolver for a callable's signature, it returns `(param, e)` when that callable has exactly one parameter and a proved return `{Bool | _ == e}` or `{Bool | e == _}` whose `e` mentions only that parameter.
- `instantiate_abstract` gains `~(named : string -> (string * A.expr) option)`.

- [ ] **Step 1: Write the failing tests**

Add the suite. `ar2_filt` (the phase-2 fixture: `filt` plus `sum_pos`) is reused.

```ocaml
(* Phase 3 (plan specs/plans/2026-10-07-abstract-refinements-phase3-plan.md):
   the instantiating actual may be a named predicate with a PROVED
   `{Bool | _ == e}` return, a callback parameter, a let-bound lambda, or
   `fn y -> g(y)`.  Each row's "today" is the 2026-10-07 pressure test. *)
let abstract_phase3_suite =
  let sumpos src = List.filter_map (fun (c, v, r) -> if c = "sum_pos" then Some (v, r) else None)
      (typed_obligations ("mod Q do\n" ^ ar2_filt ^ src ^ "end\n")) in
  [ gated "q01: a named predicate with a proved return instantiates p" (fun () ->
        Alcotest.(check (list (pair string string))) "proved" [ ("proved", "") ]
          (sumpos "  fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, is_pos)) end\n"));
    gated "q03: either orientation of the equality" (fun () ->
        Alcotest.(check (list (pair string string))) "proved" [ ("proved", "") ]
          (sumpos "  fn is_pos(n : Int) : {Bool | (n > 0) == _} do n > 0 end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, is_pos)) end\n"));
    gated "a weaker named predicate is too weak, not violated" (fun () ->
        Alcotest.(check (list (pair string string))) "too weak"
          [ ("skipped", "abstract-refinement-too-weak") ]
          (sumpos "  fn nonneg(n : Int) : {Bool | _ == (n >= 0)} do n >= 0 end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, nonneg)) end\n"));
    gated "q02: a named predicate with no contract instantiates nothing" (fun () ->
        Alcotest.(check (list (pair string string))) "uninstantiated"
          [ ("skipped", "abstract-refinement-uninstantiated") ]
          (sumpos "  fn is_pos(n : Int) : Bool do n > 0 end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, is_pos)) end\n"));
    (* r5: a return the definition does NOT prove never reaches a caller,
       so it must not instantiate either. *)
    gated "r5: an unproved return instantiates nothing" (fun () ->
        Alcotest.(check (list (pair string string))) "uninstantiated"
          [ ("skipped", "abstract-refinement-uninstantiated") ]
          (sumpos "  fn helper(n : Int) : Bool do n > 0 end\n\
                   \  fn is_pos(n : Int) : {Bool | _ == (n > 0)} do helper(n) end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, is_pos)) end\n"));
    gated "q04: a callback parameter passes its contract through" (fun () ->
        Alcotest.(check (list (pair string string))) "proved" [ ("proved", "") ]
          (sumpos "  fn go(ys : List(Int), k : ({x : Int | true}) -> {Bool | _ == (x > 0)}) : Int do sum_pos(filt(ys, k)) end\n"));
    gated "a callback parameter with no codomain contract instantiates nothing" (fun () ->
        Alcotest.(check (list (pair string string))) "uninstantiated"
          [ ("skipped", "abstract-refinement-uninstantiated") ]
          (sumpos "  fn go(ys : List(Int), k : ({x : Int | true}) -> Bool) : Int do sum_pos(filt(ys, k)) end\n"));
    gated "q07: fn y -> g(y) is g" (fun () ->
        Alcotest.(check (list (pair string string))) "proved" [ ("proved", "") ]
          (sumpos "  fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> is_pos(y))) end\n"));
    gated "q06: a two-parameter call stays uninstantiated" (fun () ->
        Alcotest.(check (list (pair string string))) "uninstantiated"
          [ ("skipped", "abstract-refinement-uninstantiated") ]
          (sumpos "  fn gt(n : Int, m : Int) : {Bool | _ == (n > m)} do n > m end\n\
                   \  fn go(ys : List(Int)) : Int do sum_pos(filt(ys, fn y -> gt(y, 0))) end\n"));
    (* §3.5 through a named predicate: the parameter path uses the same
       instantiation. *)
    gated "a named predicate at a parameter slot" (fun () ->
        let p, v, s, _ =
          typed_ledger
            {|mod QN do
  fn need(xs : List({a | p(_)}), keep : ({x : a | true}) -> {Bool | _ == p(x)}) : Int do 0 end
  fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end
  fn go(pos : List({Int | _ > 0})) : Int do need(pos, is_pos) end
end|}
        in
        (* is_pos's own postcondition (1) + the element obligation (1). *)
        Alcotest.(check (triple int int int)) "proved" (2, 0, 0) (p, v, s)) ]
```

Register `("abstract-phase3", abstract_phase3_suite);` immediately before `("z3-well-formed", z3_wellformed_suite)`.

- [ ] **Step 2: Run and confirm which fail**

Run the test command.
Expected FAIL (6): q01, q03, q04, q07, "a weaker named predicate" (today `uninstantiated`, target `too-weak`), and "a named predicate at a parameter slot" (today `(1, 0, 1)`).
Expected PASS already (4), because their target equals today's behaviour: q02, r5, "no codomain contract", q06. If any of the six passes before the change, the fixture is wrong; fix it before implementing.

- [ ] **Step 3: Implement `named_predicate`**

Above `instantiate_abstract`:

```ocaml
(* A named callable as an abstract refinement's instantiation (phase 3): its
   proved return `{Bool | _ == e}` (either orientation) over its ONE parameter,
   as [(param, e)].  [sig_of] must return only PROVED returns — [callee_sig]
   does (an unproved postcondition never reaches a caller; probe r5) — so an
   assumed-but-unproved contract can never instantiate [p].  A callback
   parameter's signature names its parameter [callback_param_name] and its
   return was rewritten over it ([callback_sig_of_ty]), so it needs no special
   case. *)
let named_predicate (sig_of : string -> fn_sig option) (g : string) : (string * A.expr) option =
  match sig_of g with
  | Some { param_names = [ n ]; ret = Some (b, A.EApp (A.EVar { A.txt = "=="; _ }, [ l; r ], _)); ret_sort; _ }
    when ret_sort = Some bool_sort ->
    let is_b = function A.EVar { A.txt; _ } -> txt = b || txt = "_" | _ -> false in
    let e = if is_b l then Some r else if is_b r then Some l else None in
    Option.bind e (fun e ->
        match classify_pred b [ n ] e with
        | Closed | Relational [ _ ] -> Some (n, e)
        | _ -> None)
  | _ -> None
```

`ret_sort = Some bool_sort` is what `return_refine_sorted` (`refine_scope.ml`, the `is_bool_base` arm) produces for a `Bool` return, for a named function and a callback signature alike.

- [ ] **Step 4: Thread it through `instantiate_abstract`**

Change the signature to `instantiate_abstract ~(named : string -> (string * A.expr) option) (fd : A.fn_def) (p : string) (args : A.expr list)` and add two arms:

```ocaml
  | Some (A.EVar { A.txt = g; _ }) ->
    (match named g with
     | Some (n, e) -> Ok (n, e)
     | None ->
       Error
         (Printf.sprintf
            "`%s`, passed for `%s`, has no proved `{Bool | _ == …}` return over one parameter" g p))
```

In the inline-lambda arm, before the `opaque_call` check, eta-reduce:

```ocaml
    (match body with
     | A.EApp (A.EVar { A.txt = g; _ }, [ A.EVar { A.txt = y'; _ } ], _)
       when y' = y && not (known_predicate_fn g) ->
       (match named g with
        | Some (n, e) -> Ok (n, e)
        | None -> Error (Printf.sprintf "the lambda passed for `%s` calls `%s`, which has no proved `{Bool | _ == …}` return" p g))
     | _ -> (* existing Closed / opaque_call / Ok (y, body) logic *))
```

The `| Some _ ->` "not an inline one-parameter lambda" arm stays for anything else.

Call sites: in `abstract_flow` pass `~named:(named_predicate (callee_sig ctx defs cb))`. `abstract_param_entry` needs `defs` and `cb`; add them as parameters and pass them from `check_arg_elements`, which has both.

- [ ] **Step 5: Run; all C1 cases pass; then perturb**

Run the test command. Expected: all `abstract-phase3` cases PASS, and `abstract-phase2` stays 20/20.
Non-vacuity: replace `named_predicate`'s body with `ignore sig_of; ignore g; None`. Rebuild, and confirm q01/q03/q04/q07/parameter-slot FAIL. Restore, rebuild, all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/refinecheck/refine_check.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): a named predicate, a callback parameter, or fn y -> g(y) instantiates an abstract refinement (phase 3)"
```

### Task C2: `let`-bound lambdas

**Files:** `lib/refinecheck/refine_check.ml` (`visit`'s `lets'` fold around line 1715; `instantiate_abstract` gains `~local_lambda`); `lib/refinecheck/refine_call.ml` (`alias_withdrawal_cause`, about line 304); `lib/refinecheck/refine_scope.ml` (the `launder` comment, about line 1283); tests.

**Interfaces:** `instantiate_abstract ~named ~(local_lambda : string -> A.expr option)`. `local_lambda f` returns the `ELam` that `lets` maps `f` to.

- [ ] **Step 1: Write the failing tests** (append to `abstract_phase3_suite`)

```ocaml
    gated "q05: a let-bound lambda instantiates p" (fun () ->
        Alcotest.(check (list (pair string string))) "proved" [ ("proved", "") ]
          (sumpos "  fn go(ys : List(Int)) : Int do\n    let f = fn y -> y > 0\n    sum_pos(filt(ys, f))\n  end\n"));
    gated "an alias of a let-bound lambda instantiates p" (fun () ->
        Alcotest.(check (list (pair string string))) "proved" [ ("proved", "") ]
          (sumpos "  fn go(ys : List(Int)) : Int do\n    let f = fn y -> y > 0\n    let g = f\n    sum_pos(filt(ys, g))\n  end\n"));
    gated "rebinding the lambda's name retires it" (fun () ->
        Alcotest.(check bool) "not proved" false
          (List.mem ("proved", "")
             (sumpos "  fn go(ys : List(Int), h : ({x : Int | true}) -> Bool) : Int do\n    let f = fn y -> y > 0\n    let f = h\n    sum_pos(filt(ys, f))\n  end\n")));
    gated "a let-bound lambda that captures is uninstantiated" (fun () ->
        Alcotest.(check (list (pair string string))) "uninstantiated"
          [ ("skipped", "abstract-refinement-uninstantiated") ]
          (sumpos "  fn go(ys : List(Int), m : Int) : Int do\n    let f = fn y -> y > m\n    sum_pos(filt(ys, f))\n  end\n"));
```

- [ ] **Step 2: Run.** Expected: the first two FAIL (`uninstantiated`); the last two PASS already.

- [ ] **Step 3: Record lambdas in `lets`**

In `visit`'s `lets'` fold, add an arm before the `A.PatVar n, A.EVar` alias arm:

```ocaml
                | A.PatVar n, (A.ELam _ as rhs) -> (n.A.txt, rhs) :: lets
```

The existing alias arm already copies any recorded RHS forward, so `let g = f` works. `launder_shadow` retires the entry when `f` is rebound, or when a name the lambda mentions is rebound. That is conservative for a closed lambda (it only mentions its own parameter) and is the same rule `let zs = filter(…)` relies on.

- [ ] **Step 4: Keep `alias_withdrawal_cause` application-only**

In `refine_call.ml`'s `alias_withdrawal_cause`, the `List.exists (fun (m, rhs) -> …) lets` consults every entry. Filter it to application entries, so a lambda can never be read as a laundered guard:

```ocaml
      || List.exists
           (fun (m, rhs) ->
             (match rhs with A.EApp _ -> true | _ -> false)
             && expr_mentions_free m cond && expr_applies_to_free w.wd_spelling sn.A.txt rhs)
           lets
```

Update the `launder` comment in `refine_scope.ml` to say the channel also carries `name → lambda`, read only by abstract-refinement instantiation.

- [ ] **Step 5: Wire `local_lambda`**

In `instantiate_abstract`, the new `A.EVar g` arm first tries `local_lambda g`. On `Some (A.ELam _ as lam)`, recurse on the lambda by running the inline-lambda logic on `lam`. Factor that logic into a local `of_lambda` used by both arms. Otherwise fall back to `named g`. Pass `~local_lambda:(fun f -> match List.assoc_opt f lets with Some (A.ELam _ as l) -> Some l | _ -> None)` from `abstract_flow` and `abstract_param_entry`, both of which have `lets`. Order matters: a local lambda shadows a top-level function of the same name, so check `local_lambda` first.

- [ ] **Step 6: Run all, then the alias suites**

Run `abstract-phase3`, `abstract-phase2`, and every group whose name contains `alias` or `launder`:

```bash
./_build/default/test/test_refinecheck.exe list 2>&1 | awk '{print $1}' | sort -u | grep -iE 'alias|launder|withdraw'
```
Expected: all pass. Non-vacuity: delete the new `ELam` arm in step 3, rebuild, and confirm q05 and the alias case FAIL; restore.

- [ ] **Step 7: Commit**

```bash
git add lib/refinecheck/refine_check.ml lib/refinecheck/refine_call.ml lib/refinecheck/refine_scope.ml test/test_refinecheck.ml
git commit -m "feat(refinecheck): a let-bound lambda instantiates an abstract refinement"
```

### Task C3: `List.find`, `Option.filter`, `List.take_while`

**Files:** `stdlib/list.march` (`find` about line 505, `take_while` about line 623); `stdlib/option.march` (`filter` about line 111); `test/stdlib/test_list.march`; `specs/lang/types/accept/tNNN_refine_abstract_stdlib_phase3.march`, `specs/lang/types/reject/tMMM_refine_abstract_find_too_weak.march`; `specs/lang/types/INDEX.md`.

`NNN`/`MMM` are the next two free ids in the shared pool **at the time**. Check with `ls specs/lang/types/accept specs/lang/types/reject | sed -E 's/^t([0-9]+)_.*/\1/' | sort -n | tail -1`; main took t296–t307 in parallel last time.

- [ ] **Step 1: Pin `take_while`'s behaviour before rewriting its body**

Append to `test/stdlib/test_list.march`, in its existing style (read the file's `describe`/`test` helpers first and match them):

```march
  test("take_while: empty list", fn () -> assert(List.take_while([], fn x -> x > 0) == []))
  test("take_while: stops at the first failure", fn () -> assert(List.take_while([1, 2, 0, 3], fn x -> x > 0) == [1, 2]))
  test("take_while: all pass", fn () -> assert(List.take_while([1, 2, 3], fn x -> x > 0) == [1, 2, 3]))
  test("take_while: first fails", fn () -> assert(List.take_while([0, 1], fn x -> x > 0) == []))
```

Run `scripts/run-tests.sh stdlib_march`. Expected: PASS on the *current* body. This is the behaviour contract the rewrite must keep.

- [ ] **Step 2: Write the conformance pair (fails until Step 3)**

`accept/tNNN_refine_abstract_stdlib_phase3.march`:

```march
-- Abstract refinements, phase 3: List.find, Option.filter and List.take_while
-- carry their predicate, instantiated from an inline lambda, a named
-- predicate with a proved `{Bool | _ == …}` return, or a let-bound lambda.
-- Under `cap verified`, exit 0 means every demand PROVED.  Reject companion:
-- reject/tMMM.
mod AbsStdlib3 do
  cap verified
  fn sum_pos(xs : List({Int | _ > 0})) : Int do List.length(xs) end
  fn one_pos(o : Option({Int | _ > 0})) : Int do 0 end
  fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end
  fn f1(ys : List(Int)) : Int do one_pos(List.find(ys, fn y -> y > 0)) end
  fn f2(o : Option(Int)) : Int do one_pos(Option.filter(o, is_pos)) end
  fn f3(ys : List(Int)) : Int do sum_pos(List.take_while(ys, is_pos)) end
  fn f4(ys : List(Int)) : Int do
    let keep = fn y -> y > 0
    sum_pos(List.filter(ys, keep))
  end
end
```

`reject/tMMM_refine_abstract_find_too_weak.march`:

```march
-- EXPECT-ERROR: abstract-refinement-too-weak
-- Abstract refinements, phase 3: a named predicate whose proved return is
-- weaker than the demand (`n >= 0` admits 0).  A too-weak skip, which
-- `cap verified` makes this error.  Accept companion: accept/tNNN.
mod AbsFindWeak do
  cap verified
  fn one_pos(o : Option({Int | _ > 0})) : Int do 0 end
  fn nonneg(n : Int) : {Bool | _ == (n >= 0)} do n >= 0 end
  fn weak(ys : List(Int)) : Int do one_pos(List.find(ys, nonneg)) end
end
```

Restage the stdlib, then with a fresh `HOME` run both. Expected before Step 3: tNNN exit 1 (f1–f3 not verifiable; f4 proves after C2), tMMM exit 1 *without* the too-weak text.

- [ ] **Step 3: Change the three signatures**

`stdlib/list.march`:

```march
  doc "Returns the first element satisfying `pred`, or None. The element, when present, satisfies `pred` (an abstract refinement `p`; see `filter`)."
  fn find(xs : List(a), pred : ({x : a | true}) -> {Bool | _ == p(x)}) : Option({a | p(_)}) do
    match xs do
    Nil        -> None
    Cons(h, t) -> if pred(h) do Some(h) else find(t, pred) end
    end
  end
```

```march
  doc "Returns the longest prefix of elements satisfying `pred`. Every element of the result satisfies `pred` (an abstract refinement `p`; see `filter`)."
  fn take_while(xs : List(a), pred : ({x : a | true}) -> {Bool | _ == p(x)}) : List({a | p(_)}) do
    -- Natural style on purpose: TRMC makes it a single-traversal loop, and
    -- the element contract is proved through the self-call (an accumulator
    -- through a local helper and `reverse` proves nothing).
    match xs do
    Nil        -> Nil
    Cons(h, t) -> if pred(h) do Cons(h, take_while(t, pred)) else Nil end
    end
  end
```

`stdlib/option.march`:

```march
  doc "Returns None if the value does not satisfy `pred`. A `Some` result satisfies `pred` (an abstract refinement `p`; see `List.filter`)."
  fn filter(opt : Option(a), pred : ({x : a | true}) -> {Bool | _ == p(x)}) : Option({a | p(_)}) do
```

- [ ] **Step 4: Verify everything that can move**

```bash
dune build --root . bin/main.exe test/test_refinecheck.exe $(ls stdlib/*.march | tr '\n' ' ')
H=$(mktemp -d); for f in specs/lang/types/accept/tNNN_*.march specs/lang/types/reject/tMMM_*.march; do HOME=$H ./_build/default/bin/main.exe --check $f > $SCRATCH/$(basename $f).out 2>&1; e=$?; echo "$(basename $f) exit=$e"; done
grep -c abstract-refinement-too-weak $SCRATCH/tMMM_*.out
HOME=$H bash specs/lang/types/check_types.sh 2>&1 | grep '=== core'
scripts/run-tests.sh stdlib stdlib_march
rm -rf .march/cas/artifacts-v2; HOME=$H ./_build/default/bin/main.exe --check --stdlib-source --refine-report stdlib/list.march 2>&1 | grep 'user + stdlib'
HOME=$H ./_build/default/bin/main.exe --check --stdlib-source --refine-audit stdlib/list.march 2>&1 | grep unenforced
```
Expected: tNNN exit 0; tMMM exit 1 with count ≥ 1; corpus all passing; stdlib suites green including the four new `take_while` cases; skipped ≤ 37 (no new stdlib skips; the bodies prove); 0 unenforced. If a stdlib skip appears, list it with `--refine-report-sites` and trace it before continuing. The intended count of new stdlib skips is zero.

- [ ] **Step 5: Audit baselines, INDEX, oracle**

```bash
UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e 'audit-baseline' >/dev/null; ./_build/default/test/test_refinecheck.exe test audit-baseline >/dev/null; echo $?
git diff test/refine_audit/ | grep '^[-+][^-+]' | sed -E 's/^([-+])[^:]+: (coverage audit.*)/\1 \2/' | sort | uniq -c
scripts/refine-oracle.sh check $SCRATCH/oracle
```
Expected: the audit diff is a uniform `+k enforced` on every line. Write down k (one per new contract slot) and explain it. The oracle diff is a uniform `+j proved` on every count line, from the new definition-side proofs; classify every changed line with the phase-2 script (progress note `2026-10-06-abstract-refinements-phase2.md`) and confirm skipped/violated/trusted never move. Update `INDEX.md`: header ids, file counts, the two `currently N/N` / `Result:` lines, and one row per file in the existing table style.

- [ ] **Step 6: Commit**

```bash
git add stdlib/list.march stdlib/option.march test/stdlib/test_list.march specs/lang/types/accept/tNNN_refine_abstract_stdlib_phase3.march specs/lang/types/reject/tMMM_refine_abstract_find_too_weak.march specs/lang/types/INDEX.md test/refine_audit/corpus.baseline test/refine_audit/holes.baseline
git commit -m "feat(stdlib): List.find, Option.filter and List.take_while carry their predicate"
```

### Task C4: Performance and ecosystem

- [ ] **Step 1: `take_while` benchmark, base vs branch**

Compile the pressure-test benchmark against each compiler. It is a 200k list taking a 150k prefix, 60 times, through `List.take_while` this time:

```march
mod TwBench do
  needs IO.Console
  fn rep(xs : List(Int), n : Int, acc : Int) : Int do
    if n == 0 do acc else rep(xs, n - 1, acc + List.length(List.take_while(xs, fn x -> x < 150000))) end
  end
  fn main(c : Cap(IO.Console)) do println(int_to_string(rep(List.range(0, 200000), 60, 0))) end
end
```

Build with `--compile --opt 2` using `$SCRATCH/main-base.exe` and the branch compiler (redirect output to a file; never pipe `--compile`). Run each 5 times, interleaved, and discard the first run of each (warm-up). Expected: the branch is not slower; the pressure test measured about 25% faster. Then run `bench/list_ops.march` compiled, both ways (closure/HOF benchmark per CLAUDE.md), and expect no regression beyond noise.

- [ ] **Step 2: Cold `--check` timing**, interleaved base vs branch, 5 runs each, `stdlib/list.march` (the phase-2 protocol). Expected: within 110%.

- [ ] **Step 3: Ecosystem sweep.** Run `--check --refine-report` over every `conduit/lib` and `depot/lib` file with `MARCH_LIB_PATH` set, base vs branch (the phase-2 `eco.sh`). Expected: identical exit codes; report lines identical apart from skip→proved changes. Neither repo has a `cap verified` module.

### Task C5: Full verification, docs, PR

- [ ] **Step 1:** `uptime; scripts/run-tests.sh > $SCRATCH/full.log 2>&1; echo $?`. Expected `0`, `All suites passed.`
- [ ] **Step 2:** In `specs/lang/refinement-types.md`'s "Abstract refinements" section:
  - add a paragraph listing what instantiates `p`: an inline lambda; `fn y -> g(y)`; a named function with a proved `{Bool | _ == …}` return over one parameter; a callback parameter with such a codomain; a `let`-bound closed lambda.
  - list the three new stdlib functions;
  - in "What it does not do", replace the "only an inline one-parameter lambda" bullet with the remaining limits: a predicate with no proved contract, more than one parameter, a lambda mentioning another name, a body calling anything other than a single eta-reducible call;
  - run `python3 scripts/gen-lang-docs.py`.
- [ ] **Step 3:** Progress note `specs/progress/2026-MM-DD-abstract-refinements-phase3.md`: the pressure-test table before and after, each task's commit, the oracle and audit `+j`/`+k` explained, timings, the ecosystem result, and what stays open (`Deque.filter`, `partition`, `drop_while`, arity > 1, phase 4). Design doc status line: phase 3 landed. CHANGELOG `### Added` bullet. Run `scripts/check-docs.sh`.
- [ ] **Step 4:** Commit the docs; `git fetch origin && git merge origin/main` (resolve CHANGELOG by union, renumber corpus ids if taken, regenerate audit baselines); re-run `refinecheck compiler stdlib`; push; `gh pr create`; report the URL.

## Risks found while planning, and how each is contained

| Risk | Containment |
|---|---|
| An unproved named return instantiates `p` (unsound) | `named_predicate` reads only `callee_sig`, which hides unproved returns (r5). Test r5 pins it. |
| A named predicate's proved return mentions other names (globals, constants) | `classify_pred b [n] e` must be `Closed` or `Relational [n]`; anything else declines. |
| The `lets` channel's other consumer reads a lambda as a laundered guard | C2 step 4 filters `alias_withdrawal_cause` to application entries; the alias suites are run. |
| A local lambda vs a top-level function of the same name | `local_lambda` is consulted first, matching lexical shadowing; the rebinding test pins retirement. |
| The rewritten `take_while` changes behaviour | Four edge-case runtime tests pinned on the old body first (C3 step 1). |
| `take_while` gets slower | TRMC-transformed, measured about 25% faster; re-measured in C4. |
| New stdlib contracts add skips past the ratchet | The three bodies prove (r2–r4); C3 step 4 asserts skipped ≤ 37, and any new skip is traced. |
| Corpus id collision with parallel work | Pick ids at C3 time; renumber on merge if needed (happened in phase 2). |
| String/ADT element sorts | The result path takes the sort from the demand (q10 proves); the parameter path from the argument's type (fixed in `a9a0c4b3d`, test q09b). Add a String row to the conformance file if C1 passes q10-style. |
