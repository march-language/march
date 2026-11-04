# Reflection phase 5: function values — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** a call `g(xs, fn x -> e)` of a higher-order function gets a logic function of its own,
`g$k`, which is `g`'s body with the lambda put in place of the function parameter. Then a
function that calls `List.filter` or `List.map` with a lambda is reflected, and
`let r = List.filter(xs, fn x -> x > 0)` tells stage 2 what `r` is.

**Spec:** `specs/2026-10-29-refinement-reflection-design.md` §10 "Phase 5" (decision D10), with
§2.1 R7, §3.1 (symbols) and §9.2 (the parity net).

**Base:** branch `claude/reflection-phase5-fnvalues`, cut from `origin/main` (`0a2077574`).
Phase 3 (`claude/reflection-phase3-stdlib-list`) edits `stdlib/list.march`,
`Refine_call.resolve_measure_app`/`reflect_dt` and `Refine_encode.resolve_sorts`. This phase
touches none of those functions: the call-site consumers get a one-line argument rewrite each.

## Global constraints

- Stage 1 is unchanged, byte for byte. Everything new runs in stage 2 or in the reflection
  analysis.
- A specialisation is a theorem only if `g` is total given a total function argument and the
  argument is total and pure. Every rule below exists to keep that true.
- Nothing here guesses a name. A function argument is accepted only when the termination graph
  resolved it: a lambda literal, or a name the graph resolved at that site to a top-level unit.
- The oracle gate is monotone. Run `scripts/oracle-base.sh refine ir`; the IR oracle must be
  IDENTICAL (this phase touches no code generation).
- Docs: `specs/lang/refinement-types.md` then `scripts/gen-lang-docs.py`; a CHANGELOG bullet;
  `specs/progress/2026-11-03-reflection-phase5-fnvalues.md`.

## Rulings made while planning

1. **Which `g` can be specialised.** A unit `g` whose only §2.1 blockers are R7 events about its
   own function-typed parameters `P`, with:
   - every occurrence of a parameter `p ∈ P` in the body either the head of a call `p(args)`
     (with no `p` in `args`) or the argument at `p`'s own position in a direct call of `g`
     itself (the graph resolved that call to `g`);
   - no binder anywhere in the body named like a parameter in `P` (no shadowing to reason about);
   - no refinement inside the argument types of a `p`'s arrow type (a lambda's body could rely on
     it; the result's abstract refinement `Bool[p]` is fine);
   - `g`'s SCC is `g` alone (self-recursion or none);
   - every other rule (R1-R6, R8, R9, R11 on the other parameters, the fixpoint) as today.

   Such a `g` is **specialised**, not reflected: it has no logic symbol of its own, and a
   predicate cannot name it.
2. **Which arguments are accepted.** At a call site of a specialised `g`, each argument in a `P`
   position must be:
   - a lambda literal with exactly the arrow's arity, no parameter type annotation carrying a
     refinement, and a body that passes R3-R7 on its own (no effect, no failure, exhaustive
     matches, no nested lambda, no call through a value), whose calls are reflected functions,
     lemmas, constructors or table builtins, and whose `/` and `%` divide by a non-zero literal;
   - or a name the graph resolved at that site to a reflected top-level function of the right
     arity (`List.filter(xs, is_pos)`).

   A `let`-bound lambda, a local `fn`, a parameter holding a function, or a call returning one is
   not accepted (the value's definition is not fixed by the site). Follow-up, not this phase.
3. **Captures.** A lambda's free variables that are not functions (the graph has no site for
   them) are its captures. They become extra parameters of `g$k`, after `g`'s own non-function
   parameters, and the call passes their values. A capture with no sort makes the site
   unspecialised.
4. **Symbols.** One symbol per call site:
   `|r:<origin>:<g path>#<file>:<line>:<col>$spec:<caller>#<file>:<line>:<col>|`, the caller
   part naming the call's position. The §3.1 duplicate check covers it. The signature's sorts come
   from the call site's argument and result types (type variables of the caller are `SParam`).
5. **The template.** `g`'s single clause translated with `g`'s non-function parameters bound to
   `$rp<i>`, each `p ∈ P` bound to a sentinel, captures to the trailing `$rp<j>`. A call `p(a)` is
   the lambda's body with its parameters bound to the translated `a` and its captures to the
   capture parameters (lexical scope: the lambda's body never sees `g`'s names). The self call
   `g(t, p)` is `g$k(t, captures)`. Anything else that meets a sentinel declines. The domain guard
   is `g`'s parameter refinements; the fuel is `g`'s.
6. **Where a specialisation is used.** In a reflected caller's template (the call translates to
   `g$k(args, captures)`) and at program call sites (the `let` call-result fact, a subject, a
   path condition) through `Reflect_state.call_sym` plus a new `Reflect_state.site_args`: the
   expressions the symbol is applied to. The consumers apply `site_args` before translating.
7. **A caller containing an accepted lambda** loses only the R7 "contains a lambda" (or "names
   f as a value") event for that argument. The lambda's own events stay the caller's, and the
   call is a fixpoint dependency on `g` being specialised and, for a named argument, on that
   function being reflected.
8. **`@[reflect]` on a specialised `g`** is accepted (it asserts the logic has it), and
   `@[reflect(fuel: N)]` sets the fuel of its specialisations.
9. **D17, HCR, LSP.** Each `g$k` gets a logic hash over `g`'s source, the lambda's source and
   the template. Its origin is `g`, and `g`'s display name gets a `logic_by_name` entry, so a
   hot patch of `g`'s body is refused when a proof used one of its specialisations.
10. **The parity net** compares each specialisation: the program side evaluates
    `g(args, <the lambda>)` with the captures bound, in the interpreter.
11. **`--reflect-report`** prints a specialised `g` as `specialised` with the number of
    specialised call sites, and the caller as `reflected` as before.

## Soundness table (each row: a test, and the perturbation that turns it RED)

| Case | The danger | Rule | Test | RED control |
|---|---|---|---|---|
| captures | `g$k` depends on a value that is not among its arguments; `above(xs, 3)` and `above(xs, 7)` get one definition | ruling 3 | `spec_capture`: `above([5], 7) == [5]` must not prove; `above([5], 3) == [5]` and `above([5], 7) == []` prove | `MARCH_REFLECT_PERTURB=spec-capture-zero` (captures read as 0) proves it |
| function-value identity (partial application) | two different function values share one definition | ruling 4: one symbol per call site; ruling 2: only a literal lambda or a resolved name | `spec_identity`: `pos([1]) == neg([1])` must not prove; `spec_by_name`: a local `is_pos` shadowing the top-level one is not specialised | `spec-key-by-callee` (one symbol per `g`); `spec-by-spelling` (a named argument looked up by bare name) |
| recursion through the value | `bad(n) = hd0(map([n], fn x -> bad(x) + 1))` gives `bad(0) = bad(0) + 1` | R2: the lambda's calls are the caller's (termination LAMBDA edges) | `spec_recursion`: `bad` not reflected; a predicate over `bad(0)` does not prove | `spec-lambda-own-unit` (R2 ignores a cycle made only of lambda edges) proves it |
| a function parameter passed in the wrong place | `alt(t, g, f)` swaps the two functions; one `g$k` for both orders is wrong | ruling 1: each `p` only at its own position | `spec_swap`: `alt` is not specialised | `spec-any-position` |
| an impure or failing lambda at a non-reflected caller | `let r = map(xs, fn x -> noisy(x))` would give `r = g$k(xs)` for a lambda with no value | ruling 2, checked per lambda | `spec_effect`: no fact, the obligation skips | `spec-skip-lambda-check` proves it |
| the parity net per specialisation | a wrong translation of the inlined body | ruling 10 | `spec_parity`: every specialisation of the fixtures agrees | `swap-arms` gives a MISMATCH naming the specialisation |
| Y-combinator, `p` as a value | `app(f, x) = f(f, x)` | ruling 1 | `spec_selfapp`: `app` not specialised | (no translation exists: defence in depth, behaviour test only) |

## Tasks

### Task 1: analysis (`Refine_reflect.analyze`)

- Specialisable units (ruling 1) and accepted arguments (ruling 2), the R7 suppression and the
  fixpoint dependency (ruling 7), a new verdict `Specialised`.
- Per accepted lambda, its own verdict for non-reflected callers: the caller's events and
  dependencies whose span lies inside the lambda.
- Tests: `spec_filter` (a user `keep` and `List.filter` are specialised, `pos` is reflected),
  `spec_map`, `spec_named`, and the not-specialised rows.

### Task 2: symbols, templates, consumers (`install`, `Reflect_state`)

- Rulings 3-6, 8, 9. `site_args` applied in the four consumers.
- Tests: `need_one(pos([1, -2]))` style proofs, `let r = List.filter(xs, ..)` facts, the
  soundness rows.

### Task 3: parity, report, docs, oracles, review

- Rulings 10, 11. Reference section, CHANGELOG, progress note. Flip `sound_fnvalue` on purpose
  (`twice` is now reflected; `apply` is specialised).
- Full refinecheck suite, golden diagnostics, `-q compiler`, `oracle-base.sh refine ir`.
- A fresh soundness review, focused on name resolution of function arguments and captures.
