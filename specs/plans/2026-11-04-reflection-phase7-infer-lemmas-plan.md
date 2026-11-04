# Reflection phase 7: `--refine-infer` proposes lemma calls — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** at an obligation that reflection could not finish, `--refine-infer` proposes a call to
an existing lemma that closes it, or a lemma skeleton whose statement would, and checks every
proposal with the real checker before offering it.

**Spec:** `specs/2026-10-29-refinement-reflection-design.md` §10 "Phase 7" (decision D19):
"At a skipped obligation whose stage-2 query failed with a recursive frontier term, propose a
call to an existing lemma whose post mentions that term, or offer a lemma skeleton. Every
proposal is checked before it is offered, as TERM phase 5 does for metrics."

**Base:** branch `claude/reflection-phase7-infer-lemmas`, cut from `origin/main` (312175620).

## Rulings

1. **Which obligations.** A user-code **precondition** whose final verdict is `skip:reflect-fuel` or
   `skip:reflect-budget`. (Planned with postconditions too; built without them: a function's own
   postcondition is checked without the facts of the lemma calls in its body, todo
   `2026-11-03-return-contract-ignores-block-facts`, so no call can close one. Measured:
   `List.len_reverse(xs)` written above a returned `List.reverse(xs)` leaves
   `len(_) == len(xs)` `solver-undecided`.) Those are exactly the obligations where stage 2 ran and stopped with a
   reflected call left unfolded (`Reflect_stage.two_stage`'s relabel). Any other skip has no
   frontier evidence, and lemma inference stays out of it.
2. **Frontier terms come from the source, not from the SMT query.** A proposal has to be
   spelled in the user's program, and stage 2's left-unfolded `(f, args)` pairs are SMT terms
   after substitution, with no way back to source text. The pool of terms is the call subterms
   of what the obligation is about:
   - a precondition: the call's arguments;
   - in both cases, the right-hand side of every `let` in scope whose name the pool mentions,
     transitively.
3. **Which lemmas.** Every valid lemma the module can call (`Refine_check.lemma_defs`, user and
   stdlib). A lemma is a candidate when some call subterm of its theorem matches a pool term by
   first-order matching. Heads match by last name segment, the lemma's parameters are the
   pattern variables, and every parameter must be bound. At most 8 candidates are checked per
   obligation (the metric search's cap). Name matching may be loose because ruling 5 is the
   oracle: a wrong match fails its check and is never offered.
4. **Where the call goes.** A statement `L(args)` (the only position that gives facts today; see
   todo `lemma-facts-from-non-statement-calls`) is placed directly before the innermost block
   statement containing the obligation.
   - An argument may name only what is in scope there: the function's parameters, earlier
     `let`s of the enclosing blocks, and the variables of enclosing match arms and lambdas.
   - An arm body that is not a block is wrapped in one in the tree.
   - The textual edit is written only when the statement starts its own line. Otherwise the
     proposal is `apply-by-hand`.
5. **The check.** A candidate is offered only if all of the following hold when it is
   installed in the tree and the module is re-checked (`Refine_check.check_module`, as
   `infer_decreases` does):
   - the target obligation is proved;
   - every obligation at the inserted call (the lemma's preconditions) is proved;
   - no user obligation that was proved before is now unproved;
   - no new error appears.

   Proposals from different obligations are then confirmed together by one more re-check, and a
   proposal that no longer closes its obligation is dropped. Up to 3 retries, as metrics have.
6. **Skeletons.** An obligation for which no lemma call is offered gets a skeleton
   `@[lemma] fn <fn>_lemma_<n>(params) : {Unit | goal}`.
   - The goal is the callee's predicate with the formals replaced by the actuals. `let`-bound
     locals are replaced by their right-hand sides until only the function's parameters remain.
   - The parameters are those variables, with their declared types.
   - **Checked:** with `assert <goal>` inserted before the statement, the target is proved and
     no proof is lost. (Planned as "install the skeleton with body `()` and call it"; built with
     the `assert`, because an unproved lemma's call gives no fact, `lemma_unproved`.) So the
     skeleton is exactly the statement whose proof closes the obligation.
   - Not offered when the goal cannot be stated over the parameters, or contains a shape the
     printer does not know.
   - **Never written by `--refine-infer-apply`:** it is an unproved lemma, so applying it would
     trade one skip for another.
7. **Output.**
   - Text: an `inferred lemma calls: N proposed, M not inferred` block after the metrics, one
     line per proposal, one per obligation with none, and under it the skeleton when one
     was checked.
   - JSON: `"lemma_calls"` and `"lemma_none"` keys (each `lemma_none` entry has a
     `"skeleton"`), present only when there is something to say, as for `"decreases"`.
   - `--refine-infer-apply` and `-diff` write the lemma-call insertions. The predicted counts
     include them, because the confirmation re-check's ledger becomes `after`.
8. **Kinds.** `--refine-infer-kinds=lemma` selects it. It also runs when no kinds are given,
   like `decreases`.

## Tasks

### Task 1: the candidate search (`lib/refinecheck/infer_lemma.ml`)
- `targets : is_user -> Obligation.t list -> Obligation.t list` (ruling 1).
- `locate : A.decl list -> A.span -> site option`, where a site is the enclosing fn, the block
  path, the statement index, the scope names and the `let` environment (rulings 2 and 4).
- `pool : site -> Obligation.t -> A.expr list` (ruling 2).
- `matches : lemma -> A.expr list -> (string * A.expr) list list` (ruling 3).
- `insert : A.decl list -> site -> A.expr -> A.decl list` (ruling 4).
- **Test (reflect-infer-lemma):** `reverse(reverse(xs))` passed to a parameter refined
  `== xs`, plus a user lemma `rr`, proposes `rr(xs)`.

### Task 2: checking, confirmation and skeletons (`infer_lemma.ml`, `refine_infer.ml`)
- `infer_lemmas ~root ~is_user ~applicable m decls -> lproposal list * lskeleton list * ledger option`
  (rulings 5 and 6), called from `Refine_infer.run` before `infer_decreases`, which then
  re-checks the tree with the calls in it.
- **Tests:**
  - a lemma whose precondition the call cannot prove is NOT proposed (REJECT control);
  - a lemma whose theorem doesn't help is NOT proposed;
  - stdlib `List.reverse_reverse` is proposed in user code;
  - a postcondition is not a target (ruling 1);
  - a `let`-bound pool term;
  - an arm body on the arrow's line: wrapped in a block in the tree, `apply by hand`;
  - a skeleton when no lemma exists (text and JSON).

### Task 3: report, JSON, apply (`bin/main.ml`, `infer_json.ml`)
- Ruling 7, plus the edit helper `insert_statement` in `lib/refactor/refine_edit.ml`.
- **Tests:**
  - a CLI `--refine-infer-apply` writes the call, and the re-check matches the prediction;
  - `-json` carries `lemma_calls` with an edit and `lemma_none` with the skeleton.

### Task 4: docs, specs, changelog
- `specs/lang/refinement-types.md` "Lemmas" and "Module-wide inference" sections, then
  `scripts/gen-lang-docs.py`.
- Lemma guide `docs/lemmas/`, if it lists inference as future work.
- Spec §10 phase 7 "Built" note.
- Progress note, CHANGELOG `### Added`.

## Review Focus
- A proposal whose argument names a variable bound inside the statement it is inserted before
  (lambda parameter, arm variable of a nested match): ruling 4's scope check must refuse it.
- Two obligations in one statement proposing the same call: the call is inserted once.
- A lemma call inserted where it reaches the induction hypothesis instead (inside the
  lemma's own SCC): never proposed inside a lemma body (v1).
- Stdlib obligations are never targets (`is_user`).
- `--refine-infer` on a program with no reflected skips: no new output and no re-check (cost).
