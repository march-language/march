# Session Types Correctness Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close five live correctness/soundness holes in March's session-type checker (dropped post-`choose` protocol steps, non-recursive `loop`, `Chan.new` on non-binary protocols, unrefined `Chan.offer` continuations, false/missing offer-label exhaustiveness), plus the diagnostic noise and stale reference text around them.

**Architecture:** Every fix lands in `lib/typecheck/typecheck.ml` — projection (`project_steps`), protocol registration (the `Ast.DProtocol` arm), the `Chan.*` operation arms of `infer_expr`, and the `match` exhaustiveness path. No runtime, lowering, or codegen change is required: the channel runtime is untyped (crossed FIFO queues in `runtime/march_extras.c`), so all of these are compile-time-only. Each task is verified three ways — an Alcotest unit test in `test/test_compiler.ml`, a conformance witness in `specs/lang/types/{accept,reject}/`, and (where behavior changes for a running program) the `specs/lang/golden/` interp-vs-compiled corpus.

**Tech Stack:** OCaml 5.3.0, dune, Alcotest, menhir/ocamllex, the `specs/lang/` conformance corpora (`check_types.sh`, `verify.sh`).

## Global Constraints

- **Work in this worktree only.** Build with `dune build --root .` from `/Users/80197052/code/march/.claude/worktrees/session-types-review-b097b6`. A bare `dune build` walks up to the main repo and builds the wrong tree. **Never `git stash`** — the stash stack is shared across all worktrees on this machine.
- **Never use `git add -A` / `git add .` / `git commit -am`.** Stage files explicitly by name (project rule, `CLAUDE.md`).
- **No `Co-Authored-By` lines** in commit messages.
- **Every task's final commit must also update** `specs/todos.md` (move the finding to Done), `specs/progress.md` (feature/fix bullet), and `CHANGELOG.md` under `## [Unreleased]` (`### Fixed`) when the change is user-visible. This is a repo rule, not optional.
- **Test invocation:** use `scripts/run-tests.sh` or direct binaries — never bare `dune runtest` (stale RPC daemon). Judge by `$?`, not by tail output.
- **Conformance scripts must stay green:** `specs/lang/types/check_types.sh` and `specs/lang/golden/verify.sh` both exit 0 at the end of every task that touches those corpora.
- **Reject-corpus format:** every `specs/lang/types/reject/*.march` starts with `-- EXPECT-ERROR: <substring of the live message>` on line 1, and every new corpus file gets a row in `specs/lang/types/INDEX.md`.
- **Role-name hygiene in corpus programs:** until Task 6 lands, declare each protocol role as its own nullary type (`type Client = Client`) to keep the F8 participant HINT out of golden output.

---

## File Structure

| File | Responsibility in this plan |
|---|---|
| `lib/typecheck/typecheck.ml` | All five semantic fixes: `project_steps` (Tasks 1, 2), `DProtocol` validation (Task 2), `Chan.new`/`Chan.offer`/`Chan.send`/`recv`/`close`/`choose` arms (Tasks 3, 4), `env` record + `make_env` (Task 4), exhaustiveness path (Task 5), participant hint + `MPST.*` fallthrough (Task 6) |
| `test/test_compiler.ml` | Alcotest unit tests, all registered in the existing `session` suite list (~line 8548) |
| `specs/lang/types/accept/*.march`, `reject/*.march`, `INDEX.md` | `--check`-anchored conformance witnesses |
| `specs/lang/golden/g39_chan_choose_offer.march` | Migrated in Task 4 (offer result must be matched) |
| `specs/lang/session-types.md`, `specs/lang/core-march-types.md`, `specs/lang/core-march.md` | Reference text reconciliation (Task 7) |
| `specs/todos.md`, `specs/progress.md`, `CHANGELOG.md` | Ledger updates (every task) |

**Out of scope — file follow-up plans, do not build here:**
- `MPST.choose` / `MPST.offer` (multiparty branching is undriveable; Task 6 only makes the failure legible).
- F6, the no-scheduler `recv`-before-`send` deadlock boundary.
- F7's residual: abandoning a channel *mid*-protocol.

---

### Task 1: Steps after a `choose … end` block are dropped from every projection

`project_steps`' `ProtoChoice` arm projects each branch with `cont` — the continuation of the whole projection call, which is `SEnd` at top level — and never with `rest_ty ()`, the steps that actually follow the choice block. Both roles lose the tail consistently, so duality still passes and a program that skips the trailing message typechecks and runs clean. In MPST it is worse: the send/recv-pair consistency check doesn't descend into `SOffer`, so a legal 3-role protocol with a choice followed by another message is *rejected* with a spurious `role A should receive from C` error.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:7361-7386` (the `Ast.ProtoChoice` arm of `project_steps`)
- Test: `test/test_compiler.ml` (new tests + registration ~line 8548)
- Create: `specs/lang/types/reject/t91_choice_tail_step_required.march`
- Modify: `specs/lang/types/INDEX.md`

**Interfaces:**
- Consumes: nothing from earlier tasks (this is the first task).
- Produces: post-`choose` protocol tails are present in every role's projection. Tasks 4 and 5 write corpus programs with branching protocols and rely on this being correct.

- [ ] **Step 1: Write the failing structural test**

Add to `test/test_compiler.ml`, immediately after `test_session_binary_choice_identical_branches` (~line 1463):

```ocaml
(** Steps that follow a `choose ... end` block must appear in EVERY branch of
    every role's projection.  Pre-fix, [project_steps]' ProtoChoice arm passed
    the OUTER continuation (SEnd at top level) into each branch instead of
    [rest_ty ()], silently dropping the tail from both roles — consistently
    enough that duality still passed and the protocol's trailing message was
    simply unenforceable. *)
let test_session_choice_tail_survives_projection () =
  let (ctx, env) = typecheck_full {|mod Test do
    type Client = Client
    type Server = Server
    protocol Tail do
      choose by Server:
        ok  -> Server -> Client : Bool
        err -> Server -> Client : Bool
      end
      Client -> Server : String
    end
  end|} in
  Alcotest.(check bool) "protocol with post-choice tail: no errors" false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "Tail" env.March_typecheck.Typecheck.protocols in
  let client_ty = List.assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  (* Client offers; each branch must be Recv(Bool, Send(String, End)) — the
     trailing `Client -> Server : String` step is part of every branch. *)
  (match client_ty with
   | March_typecheck.Typecheck.SOffer branches ->
     Alcotest.(check int) "two offer branches" 2 (List.length branches);
     List.iter (fun (lbl, sty) ->
         match sty with
         | March_typecheck.Typecheck.SRecv
             (_, March_typecheck.Typecheck.SSend (_, March_typecheck.Typecheck.SEnd)) -> ()
         | other ->
           Alcotest.fail (lbl ^ ": expected Recv(_, Send(_, End)) but got " ^ pp_sty other))
       branches
   | other -> Alcotest.fail ("expected SOffer but got " ^ pp_sty other))
```

Register it in the session suite list (~line 8550, next to `session binary choice identical branches`):

```ocaml
          Alcotest.test_case "session choice tail survives projection" `Quick test_session_choice_tail_survives_projection;
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session choice tail survives projection"
```

Expected: FAIL — `ok: expected Recv(_, Send(_, End)) but got Recv(Bool, End)`.

- [ ] **Step 3: Fix the projection**

In `lib/typecheck/typecheck.ml`, in the `Ast.ProtoChoice` arm of `project_steps`, change the branch projection to use the post-choice continuation:

```ocaml
     | Ast.ProtoChoice (chooser, branches) ->
       (* Every branch rejoins the protocol tail, so each arm is projected with
          the steps that FOLLOW this choice block as its continuation — not the
          outer [cont], which at top level is just SEnd and silently truncates
          the protocol. *)
       let after_choice = rest_ty () in
       let branch_tys = List.map (fun (lbl, arm_steps) ->
           let arm_ty = project_steps env ~proto_name ~multiparty arm_steps role after_choice in
           (lbl.Ast.txt, arm_ty)
         ) branches in
```

Leave the rest of the arm (chooser → `SChoose`, merge rule, `SOffer`) exactly as it is.

- [ ] **Step 4: Run the test and verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session choice tail survives projection"
```

Expected: PASS.

- [ ] **Step 5: Add the reject conformance witness**

Create `specs/lang/types/reject/t91_choice_tail_step_required.march`:

```march
-- EXPECT-ERROR: Chan.close: channel is at
mod Main do
  -- Session types: a step AFTER a `choose ... end` block is part of every
  -- branch's continuation (project_steps' ProtoChoice arm, 2026-07-24 fix).
  -- Pre-fix the trailing `Client -> Server : String` was dropped from BOTH
  -- roles' projections — consistently, so duality still passed — and this
  -- program (which closes instead of sending the trailing String) was
  -- wrongly ACCEPTED. Post-fix `cc4` is at `Send(String, End)` and closing
  -- it is a session-state error.
  needs IO.Console
  type Client = Client
  type Server = Server

  protocol Tail do
    Client -> Server : Int
    choose by Server:
      ok  -> Server -> Client : Bool
      err -> Server -> Client : Bool
    end
    Client -> Server : String
  end

  fn main() do
    let (cc, sc) = Chan.new(Tail)
    let cc2 = Chan.send(cc, 1)
    let (n, sc2) = Chan.recv(sc)
    let sc3 = Chan.choose(sc2, :ok)
    let sc4 = Chan.send(sc3, true)
    let (lbl, cc3) = Chan.offer(cc2)
    match lbl do
      :ok ->
        let (b, cc4) = Chan.recv(cc3)
        Chan.close(cc4)
      :err ->
        let (b, cc4) = Chan.recv(cc3)
        Chan.close(cc4)
    end
  end
end
```

- [ ] **Step 6: Verify the witness rejects for the stated reason**

```bash
dune build --root . bin/main.exe && ./_build/default/bin/main.exe --check specs/lang/types/reject/t91_choice_tail_step_required.march; echo "exit=$?"
```

Expected: `exit=1`, and the output contains ``Chan.close: channel is at `Send(String, End)` but I expected `End`.``
If the message text differs, update the `-- EXPECT-ERROR:` line to a substring of the LIVE message — do not edit the compiler to match the annotation.

- [ ] **Step 7: Index the witness**

Add a row to the reject table in `specs/lang/types/INDEX.md` (same format as the `t74_offer_wrong_branch_drive` row):

```markdown
| `t91_choice_tail_step_required` | **(post-`choose` tail projection, 2026-07-24)** — `project_steps`' `ProtoChoice` arm now projects each branch with the steps that FOLLOW the choice block (`rest_ty ()`) instead of the outer continuation. Pre-fix the trailing `Client -> Server : String` vanished from both roles' projections and closing early was wrongly ACCEPTED | `` Chan.close: channel is at `` |
```

- [ ] **Step 8: Run the full conformance + unit suites**

```bash
specs/lang/types/check_types.sh; echo "types=$?"; specs/lang/golden/verify.sh; echo "golden=$?"; scripts/run-tests.sh; echo "tests=$?"
```

Expected: all three exit 0. If an existing `accept/` witness now fails, it was relying on the dropped tail — inspect it; a protocol with steps after a choice must now drive those steps.

- [ ] **Step 9: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/types/reject/t91_choice_tail_step_required.march specs/lang/types/INDEX.md specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "fix(session): project post-choose protocol steps into every branch"
```

---

### Task 2: `loop` protocols don't loop

`project_steps`' `ProtoLoop` arm builds the body with an `SVar` back-reference and then calls `subst_svar rec_var after_loop inner`, replacing that back-reference with the *post-loop continuation*. The `SRec` binder it wraps around the result therefore contains no `SVar`: the projection is one unrolled iteration. A second iteration is rejected with ``channel is at `End` ``. The existing guard test only asserts `SRec (_, SSend _)`, which still holds after the recursion has been destroyed — it is vacuous.

The fix is the standard µ-type encoding: `loop do S end` projects to `Rec X. S[X]`, which never terminates, so any steps written after a `loop` block are unreachable and become a protocol-declaration error.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:7349-7360` (the `Ast.ProtoLoop` arm of `project_steps`)
- Modify: `lib/typecheck/typecheck.ml:8749-8778` (the `Ast.DProtocol` validation block — add the unreachable-tail check)
- Modify: `test/test_compiler.ml:1494-1511` (de-vacuum `test_session_loop_projection`) + new tests
- Create: `specs/lang/types/accept/t92_loop_protocol_two_iterations.march`
- Create: `specs/lang/types/reject/t93_steps_after_loop_unreachable.march`
- Modify: `specs/lang/types/INDEX.md`

**Interfaces:**
- Consumes: nothing from Task 1 (independent arms of the same function; if both land, `rest_ty ()` is already evaluated in the choice arm and unused in the loop arm).
- Produces: `SRec (x, body)` projections whose `body` contains `SVar x`; `unfold_srec` (`typecheck.ml:4128`) already re-wraps on each unfold, so channel state cycles indefinitely with no further changes.

- [ ] **Step 1: De-vacuum the existing loop test and add the iteration test**

Replace `test_session_loop_projection` (`test/test_compiler.ml:1494-1511`) with:

```ocaml
let test_session_loop_projection () =
  (* A protocol with a loop projects to a GENUINE recursive binder: the body
     must end in a back-reference (SVar) to the binder, not in SEnd.  The old
     assertion (`SRec (_, SSend _)`) held even after `subst_svar` had replaced
     the back-reference with the post-loop continuation — i.e. it passed while
     `loop` was silently a single unrolled iteration. *)
  let (ctx, env) = typecheck_full {|mod Test do
    type Source = Source
    type Sink = Sink
    protocol Stream do
      loop do
        Source -> Sink : Int
      end
    end
  end|} in
  Alcotest.(check bool) "loop protocol: no errors" false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "Stream" env.March_typecheck.Typecheck.protocols in
  let source_ty = List.assoc "Source" pi.March_typecheck.Typecheck.pi_projections in
  (match source_ty with
   | March_typecheck.Typecheck.SRec (x, March_typecheck.Typecheck.SSend
       (_, March_typecheck.Typecheck.SVar y)) when x = y ->
     Alcotest.(check bool) "source loop projection is Rec(X, Send(Int, X))" true true
   | other ->
     Alcotest.fail ("expected SRec(X, SSend(_, SVar X)) but got: " ^ pp_sty other))

(** A loop protocol must permit MORE THAN ONE iteration.  Pre-fix the second
    iteration was rejected with "channel is at `End`". *)
let test_session_loop_two_iterations_ok () =
  let ctx = typecheck {|mod Test do
    type Prod = Prod
    type Cons = Cons
    protocol Str do
      loop do
        Prod -> Cons : Int
        Cons -> Prod : Bool
      end
    end
    fn main() do
      let (cc, pp) = Chan.new(Str)
      let pp2 = Chan.send(pp, 1)
      let (x, cc2) = Chan.recv(cc)
      let cc3 = Chan.send(cc2, true)
      let (ack, pp3) = Chan.recv(pp2)
      let pp4 = Chan.send(pp3, 2)
      let (y, cc4) = Chan.recv(cc3)
      let cc5 = Chan.send(cc4, false)
      let (ack2, pp5) = Chan.recv(pp4)
      println(int_to_string(x + y))
    end
  end|} in
  Alcotest.(check bool) "two loop iterations typecheck" false (has_errors ctx)

(** Steps written AFTER a `loop` block are unreachable — the loop never exits —
    and are now a protocol-declaration error rather than silently reachable. *)
let test_session_steps_after_loop_error () =
  let ctx = typecheck {|mod Test do
    type A = A
    type B = B
    protocol Bad do
      loop do
        A -> B : Int
      end
      B -> A : Bool
    end
  end|} in
  Alcotest.(check bool) "steps after loop: error" true (has_errors ctx)
```

Note the endpoint order in `test_session_loop_two_iterations_ok`: `Chan.new` returns endpoints ordered by **alphabetically sorted role name** (`Cons` before `Prod`), which is why the pair destructures as `(cc, pp)`.

Register the two new cases next to the existing `session loop projection` entry (~line 8552):

```ocaml
          Alcotest.test_case "session loop two iterations ok" `Quick test_session_loop_two_iterations_ok;
          Alcotest.test_case "session steps after loop error" `Quick test_session_steps_after_loop_error;
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session loop projection" && ./_build/default/test/run_compiler.exe -e test "session loop two iterations ok"
```

Expected: `session loop projection` FAILs with `expected SRec(X, SSend(_, SVar X)) but got: Rec(Stream_loop, Send(Int, End))`; `session loop two iterations ok` FAILs (errors present); `session steps after loop error` FAILs (no error yet).

- [ ] **Step 3: Make the loop recursive**

Replace the `Ast.ProtoLoop` arm in `project_steps` (`lib/typecheck/typecheck.ml:7349`) with:

```ocaml
     | Ast.ProtoLoop inner_steps ->
       (* `loop do S end` is the µ-type `Rec X. S[X]` — the body's continuation
          IS the binder's back-reference, so the loop repeats indefinitely.
          (Substituting the post-loop continuation into the back-reference, as
          this arm used to do, produced a vacuous SRec with no SVar in it: one
          unrolled iteration.  Steps after a `loop` are unreachable and are
          rejected at protocol-declaration time.) *)
       let rec_var = proto_name ^ "_loop" in
       let inner = project_steps env ~proto_name ~multiparty inner_steps role (SVar rec_var) in
       (match inner with
        | SVar _ ->
          (* Role not involved in the loop at all — skip the binder entirely. *)
          rest_ty ()
        | _ -> SRec (rec_var, inner))
```

`subst_svar` stays in the file — it is still referenced by the `and`-chain; if the compiler now reports it unused, prefix it with `_` rather than deleting it, and note that in the commit message.

- [ ] **Step 4: Reject steps after a loop**

In the `Ast.DProtocol` arm (`lib/typecheck/typecheck.ml`, in the `validate_step` region around line 8749-8778), add a check over the top-level step list before `List.iter validate_step pdef.proto_steps;`:

```ocaml
    (* A `loop` never exits (its projection is `Rec X. S[X]`), so any step that
       follows one at the same nesting level is unreachable. *)
    let rec check_unreachable_after_loop steps =
      match steps with
      | Ast.ProtoLoop inner :: rest ->
        check_unreachable_after_loop inner;
        if rest <> [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: the steps after this `loop` can never run — \
                a `loop` block repeats forever, so it must be the last step."
               name.txt)
      | Ast.ProtoChoice (_, branches) :: rest ->
        List.iter (fun (_, arm) -> check_unreachable_after_loop arm) branches;
        check_unreachable_after_loop rest
      | _ :: rest -> check_unreachable_after_loop rest
      | [] -> ()
    in
    check_unreachable_after_loop pdef.proto_steps;
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e 2>&1 | tail -5; echo "exit=$?"
```

Expected: `exit=0`, all three loop tests green.

- [ ] **Step 6: Add the conformance witnesses**

Create `specs/lang/types/accept/t92_loop_protocol_two_iterations.march`:

```march
mod Main do
  -- Session types: `loop do ... end` projects to the µ-type `Rec X. S[X]`
  -- (2026-07-24 fix), so a channel may run the body any number of times.
  -- Pre-fix the projection substituted the post-loop continuation into the
  -- recursion variable, giving ONE unrolled iteration: the second `send`
  -- below was rejected with "channel is at `End`".  A looping channel never
  -- reaches `End`, so it is never closed — dropping mid-protocol is legal
  -- (the must-close check fires only at `End`).
  needs IO.Console
  type Prod = Prod
  type Cons = Cons

  protocol Str do
    loop do
      Prod -> Cons : Int
      Cons -> Prod : Bool
    end
  end

  fn main() do
    let (cc, pp) = Chan.new(Str)
    let pp2 = Chan.send(pp, 1)
    let (x, cc2) = Chan.recv(cc)
    let cc3 = Chan.send(cc2, true)
    let (ack, pp3) = Chan.recv(pp2)
    let pp4 = Chan.send(pp3, 2)
    let (y, cc4) = Chan.recv(cc3)
    let cc5 = Chan.send(cc4, false)
    let (ack2, pp5) = Chan.recv(pp4)
    println(int_to_string(x + y))
  end
end
```

Create `specs/lang/types/reject/t93_steps_after_loop_unreachable.march`:

```march
-- EXPECT-ERROR: can never run
mod Main do
  -- Session types: a `loop` block repeats forever (`Rec X. S[X]`), so steps
  -- written after it at the same level are unreachable and rejected at
  -- protocol-declaration time (2026-07-24).
  type A = A
  type B = B

  protocol Bad do
    loop do
      A -> B : Int
    end
    B -> A : Bool
  end

  fn main() do
    println("unused")
  end
end
```

- [ ] **Step 7: Verify both witnesses and run the corpora**

```bash
dune build --root . bin/main.exe
./_build/default/bin/main.exe --check specs/lang/types/accept/t92_loop_protocol_two_iterations.march; echo "accept=$?"
./_build/default/bin/main.exe --check specs/lang/types/reject/t93_steps_after_loop_unreachable.march; echo "reject=$?"
specs/lang/types/check_types.sh; echo "types=$?"
```

Expected: `accept=0`, `reject=1`, `types=0`.

- [ ] **Step 8: Confirm the accept witness also RUNS on both backends**

```bash
./_build/default/bin/main.exe specs/lang/types/accept/t92_loop_protocol_two_iterations.march
./_build/default/bin/main.exe --compile specs/lang/types/accept/t92_loop_protocol_two_iterations.march -o /tmp/t92_sesswt && /tmp/t92_sesswt
```

Expected: both print `3`. (This is a sanity check, not a golden — do not add it to `specs/lang/golden/` unless Task 7 decides to.)

- [ ] **Step 9: Index and commit**

Add `t92`/`t93` rows to `specs/lang/types/INDEX.md` describing the µ-type fix and the unreachable-tail rule, then:

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/types/accept/t92_loop_protocol_two_iterations.march specs/lang/types/reject/t93_steps_after_loop_unreachable.march specs/lang/types/INDEX.md specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "fix(session): make loop protocols genuinely recursive; reject unreachable post-loop steps"
```

---

### Task 3: `Chan.new` on a protocol with 3+ roles silently returns two endpoints

The `Chan.new` arm has an explicit `(* 3+ roles: just return first two as a pair *)` fallback (`typecheck.ml:4314-4320`) that hands back the first two roles' projections — which are not duals of each other — with no diagnostic. `MPST.new` has the mirror-image guard (`requires at least 3`); this one is missing.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:4300-4320` (the `Chan.new` arm)
- Test: `test/test_compiler.ml` (new test + registration)
- Create: `specs/lang/types/reject/t94_chan_new_multiparty_protocol.march`
- Modify: `specs/lang/types/INDEX.md`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: `Chan.new` accepts exactly-2-role protocols only. Corpus programs in Tasks 4-5 all use binary protocols, so nothing downstream changes.

- [ ] **Step 1: Write the failing test**

Add to `test/test_compiler.ml` after `test_session_chan_new_unknown_proto_error` (~line 1635):

```ocaml
(** `Chan.new` on a 3+-role protocol used to silently return the first two
    roles' (non-dual) endpoints.  It must error and point at `MPST.new`. *)
let test_session_chan_new_multiparty_error () =
  let ctx = typecheck {|mod Test do
    type A = A
    type B = B
    type C = C
    protocol Tri do
      A -> B : Int
      B -> C : Int
      C -> A : Bool
    end
    fn main() do
      let (x, y) = Chan.new(Tri)
      println("unused")
    end
  end|} in
  Alcotest.(check bool) "Chan.new on 3-role protocol: error" true (has_errors ctx)
```

Register it beside the other `Chan.new` cases (~line 8562):

```ocaml
          Alcotest.test_case "session Chan.new multiparty error" `Quick test_session_chan_new_multiparty_error;
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session Chan.new multiparty error"
```

Expected: FAIL — `Chan.new on 3-role protocol: error` expected `true`, got `false`.

- [ ] **Step 3: Replace the silent fallback with an error**

In the `Chan.new` arm of `infer_expr`, replace the final `| _ -> (* 3+ roles: just return first two as a pair *) ...` case with:

```ocaml
             | projs ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "Chan.new: protocol `%s` has %d roles but Chan.new needs \
                     exactly 2. Use MPST.new for multi-party protocols."
                    pname (List.length projs));
               TError
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session Chan.new multiparty error"
```

Expected: PASS.

- [ ] **Step 5: Add the reject witness and index it**

Create `specs/lang/types/reject/t94_chan_new_multiparty_protocol.march`:

```march
-- EXPECT-ERROR: Chan.new: protocol `Tri` has 3 roles
mod Main do
  -- Session types: `Chan.new` is the BINARY constructor.  Pre-fix (2026-07-24)
  -- a 3+-role protocol fell through a silent "just return first two as a pair"
  -- fallback, handing back two endpoints that are not duals of each other.
  type A = A
  type B = B
  type C = C

  protocol Tri do
    A -> B : Int
    B -> C : Int
    C -> A : Bool
  end

  fn main() do
    let (x, y) = Chan.new(Tri)
    println("unused")
  end
end
```

Add the matching `INDEX.md` row.

- [ ] **Step 6: Verify and run the corpora**

```bash
dune build --root . bin/main.exe && ./_build/default/bin/main.exe --check specs/lang/types/reject/t94_chan_new_multiparty_protocol.march; echo "exit=$?"; specs/lang/types/check_types.sh; echo "types=$?"
```

Expected: `exit=1` with the annotated substring present, `types=0`.

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/types/reject/t94_chan_new_multiparty_protocol.march specs/lang/types/INDEX.md specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "fix(session): reject Chan.new on a protocol with more than two roles"
```

---

### Task 4: An unrefined `Chan.offer` continuation is a live soundness hole

The 2026-07-15 F5 fix made `match`-on-the-label refine the offer channel per arm — but only when such a `match` exists. Without it, `Chan.offer` still hands back the **first** branch's continuation (`typecheck.ml:4452-4478`). Live repro, verified on both backends today:

```march
choose by S:
  ok  -> S -> C : Int
  err -> S -> C : String
end
```

Server chooses `:err` and sends a String; the client offers, skips the `match`, and `Chan.recv`s — the checker types the payload `Int`. Interpreted, this dies dynamically. **Compiled it prints `4328203745`** — the String's heap pointer read as an `Int` and used in arithmetic. Silent type confusion in the feature whose headline is "if it compiles, the protocol holds."

Fix: when an offer's branch continuations are **not all identical**, the returned channel is unusable until a `match` on the paired label refines it. When they are identical (the merge-safe case) nothing changes.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:663-682` (`env` record: add `offer_unrefined`), `:714` (`make_env`)
- Modify: `lib/typecheck/typecheck.ml:4452-4494` (`Chan.offer` arm), and the `Chan.send`/`recv`/`close`/`choose` arms (`:4322`, `:4354`, `:4382`, `:4409`)
- Modify: `lib/typecheck/typecheck.ml:5453-5467` (`with_offer_refinement`)
- Test: `test/test_compiler.ml` (two new tests + registration)
- Create: `specs/lang/types/reject/t95_offer_unrefined_continuation.march`
- Modify: `specs/lang/types/accept/t43_choose_offer_roundtrip.march`, `specs/lang/golden/g39_chan_choose_offer.march`, `specs/lang/types/INDEX.md`, `specs/lang/golden/INDEX.md`

**Interfaces:**
- Consumes: Task 1's corrected branch continuations (an offer's branch map now includes the post-choice tail).
- Produces: `env.offer_unrefined : session_ty ref list ref` — the registry of offer continuations awaiting refinement. Task 5 reads `env.offer_labels` (already present) but not this field.

- [ ] **Step 1: Write the two failing tests**

Add to `test/test_compiler.ml` after `test_session_offer_at_wrong_state_error` (~line 1715):

```ocaml
(** An `offer` whose branches continue DIFFERENTLY may not be driven without a
    `match` on the returned label: the checker would otherwise assume the first
    branch.  Live pre-fix behavior: the peer chose `:err` (String) and the
    compiled binary read that String pointer as an Int. *)
let test_session_offer_unrefined_continuation_error () =
  let ctx = typecheck {|mod Test do
    type C = C
    type S = S
    protocol D2 do
      choose by S:
        ok  -> S -> C : Int
        err -> S -> C : String
      end
    end
    fn main() do
      let (cc, sc) = Chan.new(D2)
      let sc2 = Chan.choose(sc, :err)
      let sc3 = Chan.send(sc2, "boom")
      Chan.close(sc3)
      let (lbl, cc2) = Chan.offer(cc)
      let (v, cc3) = Chan.recv(cc2)
      Chan.close(cc3)
      println(int_to_string(v))
    end
  end|} in
  Alcotest.(check bool) "unrefined offer continuation: error" true (has_errors ctx)

(** When every branch continues IDENTICALLY the first-branch continuation is
    exact, so driving the offer without a `match` stays legal. *)
let test_session_offer_identical_branches_no_match_ok () =
  let ctx = typecheck {|mod Test do
    type C = C
    type S = S
    protocol Same do
      choose by S:
        ok  -> S -> C : Int
        err -> S -> C : Int
      end
    end
    fn main() do
      let (cc, sc) = Chan.new(Same)
      let sc2 = Chan.choose(sc, :err)
      let sc3 = Chan.send(sc2, 7)
      Chan.close(sc3)
      let (lbl, cc2) = Chan.offer(cc)
      let (v, cc3) = Chan.recv(cc2)
      Chan.close(cc3)
      println(int_to_string(v))
    end
  end|} in
  Alcotest.(check bool) "identical-branch offer without match: no error" false (has_errors ctx)
```

Register both beside the existing offer cases (~line 8570):

```ocaml
          Alcotest.test_case "session offer unrefined continuation error" `Quick test_session_offer_unrefined_continuation_error;
          Alcotest.test_case "session offer identical branches no match ok" `Quick test_session_offer_identical_branches_no_match_ok;
```

- [ ] **Step 2: Run the tests and verify the first fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session offer unrefined continuation error"
```

Expected: FAIL (`expected true, got false`) — the unsound program typechecks today. The identical-branches test should already PASS; run it too to confirm it does not regress later.

- [ ] **Step 3: Add the `offer_unrefined` registry to `env`**

In the `env` record (`lib/typecheck/typecheck.ml`, immediately after the `offer_labels` field's doc comment, ~line 682):

```ocaml
  offer_unrefined : session_ty ref list ref;
  (** Offer continuations awaiting per-arm refinement (F5 residual, 2026-07-24).
      [Chan.offer] registers the session ref it hands back here IFF the offer's
      branch continuations are not all identical — in that case the returned
      channel's real state depends on which label the peer chose at runtime, so
      operating on it before a `match` on the paired label refines it would type
      the channel at the FIRST branch (silent type confusion: compiled, a
      String payload gets read as an Int).  [with_offer_refinement] transiently
      removes the ref while checking a refined arm; the [Chan.*] operation arms
      reject any channel still listed here.  A shared mutable ref for the same
      reason [offer_conts] is one. *)
```

In `make_env` (~line 714), beside `offer_conts = ref [];`:

```ocaml
  offer_unrefined = ref [];
```

- [ ] **Step 4: Register unrefined offers and reject operations on them**

In the `Chan.offer` arm, inside the `(_, sty) :: _` case, right after `env.offer_conts := (cont_ref, branches) :: !(env.offer_conts);`:

```ocaml
               (* If the branches continue differently, the first-branch type is
                  a GUESS — mark the ref as needing a `match`-driven refinement
                  before any operation may use it. *)
               (match branches with
                | (_, first) :: rest
                  when not (List.for_all (fun (_, s) -> session_ty_exact_equal s first) rest) ->
                  env.offer_unrefined := cont_ref :: !(env.offer_unrefined)
                | _ -> ());
```

Add this helper just above `infer_expr`'s `Chan.new` arm region (top-level, near `unfold_srec`):

```ocaml
(** Reject a [Chan.*] operation on a channel whose session ref came from an
    [offer] with differing branch continuations and has not been refined by a
    `match` on the paired label (F5 residual). *)
let offer_unrefined_error env span (r : session_ty ref) op =
  if List.exists (fun r' -> r' == r) !(env.offer_unrefined) then begin
    Err.error env.errors ~span
      (Printf.sprintf
         "%s: this channel came from `Chan.offer`, and the protocol's branches \
          continue differently, so I don't know which one the peer chose.\n\
          Match on the label first — `match lbl do :ok -> ... :err -> ... end` — \
          and use the channel inside each arm."
         op);
    true
  end else false
```

In each of the `Chan.send`, `Chan.recv`, `Chan.close`, `Chan.choose`, and `Chan.offer` arms, immediately after the `| TChan r ->` match lands and before inspecting `unfold_srec !r`, guard:

```ocaml
       | TChan r when offer_unrefined_error env sp r "Chan.send" -> TError
```

(one such guard clause per arm, with the operation name spelled to match).

- [ ] **Step 5: Clear the mark while checking a refined arm**

In `with_offer_refinement` (`typecheck.ml:5453`), extend the `Some (r, saved)` path so the ref is also unmarked for the duration of the arm:

```ocaml
  match applied with
  | Some (r, saved) ->
    let saved_unrefined = !(env.offer_unrefined) in
    env.offer_unrefined := List.filter (fun r' -> not (r' == r)) saved_unrefined;
    Fun.protect
      ~finally:(fun () -> r := saved; env.offer_unrefined := saved_unrefined)
      f
  | None            -> f ()
```

- [ ] **Step 6: Run the tests and verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session offer unrefined continuation error" && ./_build/default/test/run_compiler.exe -e test "session offer identical branches no match ok"
```

Expected: both PASS. Then run the whole session group and confirm `accept/t79`-style per-arm refinement still works:

```bash
./_build/default/bin/main.exe --check specs/lang/types/accept/t79_offer_branch_dependent_continuation.march; echo "t79=$?"
```

Expected: `t79=0`.

- [ ] **Step 7: Migrate the corpus programs that relied on the guess**

Find every offer-without-match program:

```bash
grep -rln "Chan.offer" specs/lang test stdlib
```

Two are known to need migration — `specs/lang/types/accept/t43_choose_offer_roundtrip.march` and `specs/lang/golden/g39_chan_choose_offer.march` — both drive the offer directly on an `Int`/`String` two-branch protocol. Rewrite each offering side to match on the label, keeping printed output byte-identical. For `g39`, replace the offering half of `main` with:

```march
    let (lbl, sc2) = Chan.offer(sc)
    match lbl do
      :ok ->
        let (n, sc3) = Chan.recv(sc2)
        Chan.close(sc3)
        println(lbl)
        println(int_to_string(n))
      :err ->
        let (s, sc3) = Chan.recv(sc2)
        Chan.close(sc3)
        println(lbl)
        println(s)
    end
```

and update the file's header comment: the offer no longer types at the first branch by approximation — it is refined per arm, and driving it unrefined is now an error. Apply the same shape to `accept/t43` (its trailing `println`s move inside the arms).

- [ ] **Step 8: Verify both corpora are green and g39's output is unchanged**

```bash
dune build --root . bin/main.exe
./_build/default/bin/main.exe specs/lang/golden/g39_chan_choose_offer.march
specs/lang/golden/verify.sh; echo "golden=$?"
specs/lang/types/check_types.sh; echo "types=$?"
```

Expected: g39 prints `:ok` then `43` (unchanged from before the migration — check it against `git show HEAD:specs/lang/golden/g39_chan_choose_offer.march` run output if unsure), `golden=0`, `types=0`.

- [ ] **Step 9: Add the reject witness, index it, run the full suite**

Create `specs/lang/types/reject/t95_offer_unrefined_continuation.march` with the `-- EXPECT-ERROR: came from `Chan.offer`` annotation and the Step 1 program body (roles declared as nullary types, `needs IO.Console`), add `INDEX.md` rows for `t95` plus a note on the `t43`/`g39` migration, then:

```bash
./_build/default/bin/main.exe --check specs/lang/types/reject/t95_offer_unrefined_continuation.march; echo "exit=$?"
scripts/run-tests.sh; echo "tests=$?"
```

Expected: `exit=1`, `tests=0`.

- [ ] **Step 10: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/types/reject/t95_offer_unrefined_continuation.march specs/lang/types/accept/t43_choose_offer_roundtrip.march specs/lang/golden/g39_chan_choose_offer.march specs/lang/types/INDEX.md specs/lang/golden/INDEX.md specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "fix(session): reject unrefined Chan.offer continuations (F5 residual soundness hole)"
```

---

### Task 5: Offer-label `match` exhaustiveness is backwards

Matching an offer label goes through the ordinary `Atom` exhaustiveness path, and `Atom` is an open universe — so a `match` that handles **every** protocol branch still warns `Non-exhaustive pattern match — missing case: _`. Correct code warns; genuinely unhandled branches produce the same warning and never an error. The one signal that should mean "you forgot a protocol branch" is noise.

Fix: when the scrutinee is an offer label variable (already tracked in `env.offer_labels`), check the arms against the protocol's **closed** label set instead: covering all labels (with or without a catch-all) is exhaustive and silent; a missing label with no catch-all is an error naming the branch.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:5339` and `:5509` (the two `check_exhaustiveness env … scrut_ty branches` call sites), plus a new helper above them
- Test: `test/test_compiler.ml` (two new tests + registration)
- Create: `specs/lang/types/reject/t96_offer_missing_branch_arm.march`
- Modify: `specs/lang/types/INDEX.md`

**Interfaces:**
- Consumes: `env.offer_labels : (string * (session_ty ref * (string * session_ty) list)) list` (existing), Task 4's requirement that differing-branch offers be matched at all.
- Produces: no new exported names.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_compiler.ml` after the Task 4 tests:

```ocaml
(** A `match` covering every offer label is exhaustive — no warning.  It used
    to warn "missing case: _" because Atom is an open universe. *)
let test_session_offer_all_labels_no_warning () =
  let (ctx, _env) = typecheck_full {|mod Test do
    type C = C
    type S = S
    protocol D3 do
      choose by S:
        ok  -> S -> C : Int
        err -> S -> C : String
      end
    end
    fn main() do
      let (cc, sc) = Chan.new(D3)
      let sc2 = Chan.choose(sc, :ok)
      let sc3 = Chan.send(sc2, 7)
      Chan.close(sc3)
      let (lbl, cc2) = Chan.offer(cc)
      match lbl do
        :ok ->
          let (n, cc3) = Chan.recv(cc2)
          Chan.close(cc3)
        :err ->
          let (s, cc3) = Chan.recv(cc2)
          Chan.close(cc3)
      end
    end
  end|} in
  Alcotest.(check bool) "all offer labels handled: no errors" false (has_errors ctx);
  Alcotest.(check bool) "all offer labels handled: no exhaustiveness warning"
    false (has_exhaust_warning ctx)

(** An offer `match` that omits a protocol branch (and has no catch-all) is an
    ERROR naming the branch — not the generic Atom warning. *)
let test_session_offer_missing_label_error () =
  let ctx = typecheck {|mod Test do
    type C = C
    type S = S
    protocol D4 do
      choose by S:
        ok  -> S -> C : Int
        err -> S -> C : String
      end
    end
    fn main() do
      let (cc, sc) = Chan.new(D4)
      let sc2 = Chan.choose(sc, :ok)
      let sc3 = Chan.send(sc2, 7)
      Chan.close(sc3)
      let (lbl, cc2) = Chan.offer(cc)
      match lbl do
        :ok ->
          let (n, cc3) = Chan.recv(cc2)
          Chan.close(cc3)
      end
    end
  end|} in
  Alcotest.(check bool) "missing offer branch arm: error" true (has_errors ctx)
```

Register both in the session suite list.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session offer all labels no warning" && ./_build/default/test/run_compiler.exe -e test "session offer missing label error"
```

Expected: the first FAILs on the warning assertion; the second FAILs (warning only, no error).

- [ ] **Step 3: Add the offer-label exhaustiveness check**

Add above `infer_match` (near `offer_arm_label`, `typecheck.ml:5440`):

```ocaml
(** Exhaustiveness for a `match` whose scrutinee is an OFFER LABEL variable.
    The label's universe is the protocol's branch set — closed — not the open
    `Atom` universe the generic checker assumes.  Returns [true] when this
    specialised check ran (so the caller skips the generic one). *)
and check_offer_label_exhaustiveness env span scrut (branches : Ast.branch list) =
  match scrut with
  | Ast.EVar name ->
    (match List.assoc_opt name.txt env.offer_labels with
     | None -> false
     | Some (_r, proto_branches) ->
       let has_catch_all =
         List.exists (fun (br : Ast.branch) ->
             match br.branch_pat with
             | Ast.PatWild _ | Ast.PatVar _ -> br.branch_guard = None
             | _ -> false) branches
       in
       let handled =
         List.filter_map (fun (br : Ast.branch) ->
             if br.branch_guard = None then offer_arm_label br else None) branches
       in
       let missing =
         List.filter (fun (lbl, _) -> not (List.mem lbl handled)) proto_branches
       in
       (if not has_catch_all && missing <> [] then
          Err.error env.errors ~span
            (Printf.sprintf
               "This `match` doesn't handle every branch the peer can choose — \
                missing: %s.\n\
                The protocol's `offer` branches are: %s."
               (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) missing))
               (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) proto_branches))));
       true)
  | _ -> false
```

`PatWild`/`PatVar` constructor names must match `lib/ast/ast.ml` — check them and adjust if they differ.

At both call sites, replace the bare call with the guarded pair. At `typecheck.ml:5339`:

```ocaml
    if not (check_offer_label_exhaustiveness env msp scrut branches) then
      check_exhaustiveness env msp scrut_ty branches
```

At `typecheck.ml:5509`:

```ocaml
  if not (check_offer_label_exhaustiveness env span scrut branches) then
    check_exhaustiveness env span scrut_ty branches;
  check_redundant_arms env scrut_ty branches;
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e 2>&1 | tail -5; echo "exit=$?"
```

Expected: `exit=0`. In particular `reject/t74`'s wrong-branch drive must still be rejected (it has a `_ -> println("other")` catch-all, so the new check stays silent and the type error still fires):

```bash
dune build --root . bin/main.exe && ./_build/default/bin/main.exe --check specs/lang/types/reject/t74_offer_wrong_branch_drive.march; echo "t74=$?"
```

Expected: `t74=1`.

- [ ] **Step 5: Add the reject witness, index, and run the corpora**

Create `specs/lang/types/reject/t96_offer_missing_branch_arm.march` (annotation: `-- EXPECT-ERROR: doesn't handle every branch`) using the Step 1 second program, add its `INDEX.md` row, then:

```bash
specs/lang/types/check_types.sh; echo "types=$?"; specs/lang/golden/verify.sh; echo "golden=$?"; scripts/run-tests.sh; echo "tests=$?"
```

Expected: all 0.

- [ ] **Step 6: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/types/reject/t96_offer_missing_branch_arm.march specs/lang/types/INDEX.md specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "fix(session): check offer-label matches against the protocol's closed label set"
```

---

### Task 6: Diagnostics — participant HINT noise and the `MPST.*` fallthrough

Two message-quality problems, no semantic change:

1. **F8:** every protocol role that isn't also a declared type or actor emits `Protocol X: participant Alice is not a known actor or type` — including the roles in this repo's own tutorial example. Roles are their own namespace; the hint is wrong by construction, and corpus programs work around it by declaring `type Client = Client`.
2. `MPST.choose` / `MPST.offer` don't exist (multiparty branching is unimplemented), so they fall through to the generic qualified-name path and produce ``Unknown module `MPST`. Did you mean `List`?`` — which sends the reader hunting for an import.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:8787-8796` (participant hint)
- Modify: `lib/typecheck/typecheck.ml` (a new catch-all arm after the last `MPST.*` arm, ~line 4662)
- Test: `test/test_compiler.ml` (two new tests + registration)

**Interfaces:**
- Consumes: nothing from Tasks 1-5.
- Produces: no new exported names. Note for Task 7: corpus programs no longer *need* `type Client = Client` role declarations, but leave the existing ones alone — churning them adds diff noise for no behavior change.

- [ ] **Step 1: Write the failing tests**

```ocaml
(** Protocol roles live in their own namespace — an undeclared role name must
    not produce the "not a known actor or type" hint (F8). *)
let test_session_no_participant_hint () =
  let (ctx, _env) = typecheck_full {|mod Test do
    protocol Echo do
      Alice -> Bob : String
      Bob -> Alice : String
    end
  end|} in
  Alcotest.(check bool) "no participant hint" false
    (has_warning_with ctx "is not a known actor or type");
  Alcotest.(check bool) "undeclared roles: no errors" false (has_errors ctx)

(** `MPST.choose` is not implemented; the diagnostic must say so instead of
    claiming the MPST module doesn't exist. *)
let test_session_mpst_choose_unsupported_message () =
  let ctx = typecheck {|mod Test do
    protocol Tri do
      A -> B : Int
      B -> C : Int
      C -> A : Bool
    end
    fn main() do
      let (ea, eb, ec) = MPST.new(Tri)
      let eb2 = MPST.choose(eb, :yes)
      println("unused")
    end
  end|} in
  Alcotest.(check bool) "MPST.choose: error" true (has_errors ctx)
```

`has_warning_with` lives in `test/test_helpers.ml:1677` — the hint is reported through the same diagnostic list; if hints carry a severity other than `Warning`, extend the helper usage accordingly (check `lib/errors/errors.ml`'s `Err.hint`).

Register both cases.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test "session no participant hint"
```

Expected: FAIL on the hint assertion.

- [ ] **Step 3: Delete the participant hint**

Remove the `List.iter` block at `lib/typecheck/typecheck.ml:8787-8796` that emits the hint, and leave a comment in its place:

```ocaml
    (* Protocol roles are their own namespace — they are NOT type or actor
       names, so no "unknown participant" hint is emitted (F8, removed
       2026-07-24: it fired on every ordinary protocol, including the
       reference chapter's own Echo example). *)
```

Check `test_protocol_unknown_participant_hint` (`test/test_compiler.ml:1368`) still passes — it only asserts *no errors*, so it should. If it asserts the hint's presence, rewrite it to assert absence and rename it `test_protocol_unknown_participant_no_hint`.

- [ ] **Step 4: Add the `MPST.*` catch-all arm**

After the `MPST.close` arm in `infer_expr` (~line 4662), before the generic `EApp` fallthrough:

```ocaml
    (* Any other `MPST.*` / `Chan.*` spelling: these are compiler builtins, not
       library modules, so falling through to the qualified-name path produces a
       misleading "Unknown module `MPST`".  Name the real problem instead. *)
    | Ast.EApp (Ast.EVar ({ txt = op; _ } as n), _, sp)
      when (String.length op > 5 && String.sub op 0 5 = "MPST.")
        || (String.length op > 5 && String.sub op 0 5 = "Chan.") ->
      Err.error env.errors ~span:sp
        (Printf.sprintf
           "`%s` is not a session-channel operation I know, or it was called \
            with the wrong number of arguments.\n\
            Binary channels: Chan.new/send/recv/close/choose/offer. \
            Multi-party: MPST.new/send/recv/close — multi-party `choose`/`offer` \
            are not implemented yet."
           n.txt);
      TError
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e 2>&1 | tail -5; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 6: Confirm the golden corpus output is unchanged**

The hint printed to stderr and `verify.sh` compares interp stdout against compiled stdout+stderr, so removing it can only reduce noise — but confirm:

```bash
specs/lang/golden/verify.sh; echo "golden=$?"; specs/lang/types/check_types.sh; echo "types=$?"; scripts/run-tests.sh; echo "tests=$?"
```

Expected: all 0.

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "fix(session): drop the bogus protocol-participant hint; name unsupported MPST ops"
```

---

### Task 7: Reconcile the reference chapters with reality

Three of the session-type chapters' load-bearing claims are now wrong (Tasks 1-6 changed them) and one was already wrong before this plan: `specs/lang/session-types.md:18` states that **every** `MPST.*` program segfaults compiled (exit 139, finding F3). Verified today on this worktree's compiler: a 3-role and a 4-role MPST program (Int/Bool/String payloads) both compile, run, and print output identical to the interpreter, exit 0.

**Files:**
- Modify: `specs/lang/session-types.md` (guarantees section, `Chan` API table, F3 paragraph, new `loop` + endpoint-ordering sections)
- Modify: `specs/lang/core-march-types.md` (§2.7.4-§2.7.9 projection/offer text, §4.1 findings list)
- Modify: `specs/lang/core-march.md` (§4.11.5-§4.11.6 MPST status)
- Modify: `specs/todos.md`, `specs/progress.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: the behavior established in Tasks 1-6.
- Produces: nothing code-facing.

- [ ] **Step 1: Re-verify F3 and record the transcript**

```bash
dune build --root . bin/main.exe
cat > /tmp/mpst3_sessplan.march <<'EOF'
mod DMpst do
  protocol Three do
    A -> B : Int
    B -> C : Int
    C -> A : Bool
  end
  fn main() do
    let (ea, eb, ec) = MPST.new(Three)
    let ea2 = MPST.send(ea, B, 7)
    let (v, eb2) = MPST.recv(eb, A)
    let eb3 = MPST.send(eb2, C, v + 1)
    let (w, ec2) = MPST.recv(ec, B)
    let ec3 = MPST.send(ec2, A, w > 0)
    let (b, ea3) = MPST.recv(ea2, C)
    MPST.close(ea3)
    MPST.close(eb3)
    MPST.close(ec3)
    println(int_to_string(w))
  end
end
EOF
./_build/default/bin/main.exe /tmp/mpst3_sessplan.march; echo "interp=$?"
./_build/default/bin/main.exe --compile /tmp/mpst3_sessplan.march -o /tmp/mpst3_sessplan.bin && /tmp/mpst3_sessplan.bin; echo "compiled=$?"
```

Expected: both print `8`; `interp=0`, `compiled=0`. Paste the transcript into the `specs/todos.md` entry.

- [ ] **Step 2: Update `specs/lang/session-types.md`**

Make these edits:
- **Line 18 (the backend-parity paragraph):** replace the "every `MPST.*` program segfaults compiled (exit 139)" claim with the re-verified status: MPST send/recv/close round-trips run correctly on both backends as of 2026-07-24 (transcript in `specs/todos.md`); what remains unimplemented is multiparty `choose`/`offer`, and MPST still has no golden witness.
- **The `Chan` API table (line 65-72):** add a row-note that `Chan.new(Proto)` returns endpoints ordered by **alphabetically sorted role name**, not declaration order, and that it now rejects protocols with more than two roles (Task 3).
- **The `choose`/`offer` section (line 135-171):** replace the "a missing arm is only a warning" paragraph — a `match` on an offer label is now checked against the protocol's closed label set: covering every branch is silent, omitting one without a catch-all is an error (Task 5). Add that an offer whose branches continue differently **must** be matched before the channel is used (Task 4), with the pre-fix compiled type-confusion repro as motivation.
- **The guarantees section (line 175-190):** move "every offered case is handled" from the not-a-guarantee list into the guarantees list; keep the mid-protocol-abandonment gap (F7 residual) and the no-scheduler `recv` boundary (F6) as the remaining caveats.
- **New section, after "Choice":** document `loop do … end` — it projects to `Rec X. S[X]`, repeats indefinitely, must be the last step in a protocol, and a looping channel never reaches `end` so it is never closed.

- [ ] **Step 3: Update `specs/lang/core-march-types.md`**

- §2.7.4/§2.7.5 projection prose: `ProtoChoice` now projects branches with the post-choice tail; `ProtoLoop` keeps its back-reference (delete the `subst_svar` sentence and say what replaced it).
- §2.7.9 (F5): mark the residual hole CLOSED by Task 4 and describe the new rule.
- §4.1 findings list: F3 → re-verified, no longer reproducing (cite the Step 1 transcript); F5 → FIXED; add finding entries for the post-`choose` tail drop, the non-recursive `loop`, and the `Chan.new` multiparty fallback, each marked FIXED with its task and witness ids.

- [ ] **Step 4: Update `specs/lang/core-march.md`**

§4.11.5/§4.11.6: same F3 status correction; keep F6 (no scheduler) exactly as it is — nothing in this plan changes it. State plainly that multiparty `choose`/`offer` remain unimplemented and are now a clear compile error rather than an "Unknown module" message.

- [ ] **Step 5: Run the doc-freshness lint and the full suite**

```bash
scripts/check-docs.sh; echo "docs=$?"; specs/lang/types/check_types.sh; echo "types=$?"; specs/lang/golden/verify.sh; echo "golden=$?"; scripts/run-tests.sh; echo "tests=$?"
```

Expected: all 0. `check-docs.sh` will flag any compiler-source line reference that moved during Tasks 1-6 — fix the pointer, don't suppress the lint.

- [ ] **Step 6: Commit**

```bash
git add specs/lang/session-types.md specs/lang/core-march-types.md specs/lang/core-march.md specs/todos.md specs/progress.md CHANGELOG.md
git commit -m "docs(session): reconcile session-type references with the 2026-07-24 fixes; re-verify F3"
```

---

## Follow-up plans (not in scope here)

1. **Multiparty `choose`/`offer`** — `MPST.choose`/`MPST.offer` typing arms, the projection-side merge rule for bystander roles across a choice, runtime label routing, and the corresponding corpus. This is a feature, not a fix, and it interacts with the MPST send/recv-pair consistency check (which currently does not descend into `SOffer`).
2. **Scheduler-backed `Chan.recv` (F6)** — would let the two-function `client`/`server` shape in the tutorial actually run concurrently instead of requiring hand-interleaving.
3. **Mid-protocol channel abandonment (F7 residual)** — full linear consumption for endpoints that never reach `End`.
