# Diagnostics Depth — Plan

**Date:** 2026-11-02
**Status:** Proposed.
**Builds on:** `specs/plans/diagnostics-and-triage-plan.md` (Part D: D0–D7 landed — one parse
entry point, open-construct tracking, codes and `--explain`, mechanical fixes, provided-side
origin, did-you-mean, the golden corpus `test/errors/`). D8 (the one-turn metric) was never
built; this plan picks it up as M1. The older `specs/plans/archive/elm-style-errors-plan.md`
audited message *wording*; that pass is done.

---

## 1. Where we are

The beginner tier is good. A typo'd variable gets "Did you mean `count`?", a missing `else if`
`end` names the `if` that needs it, a wrong-arity call shows the definition, and `Int` vs
`Float` explains itself with a conversion. 302 programs in `test/errors/` pin that.

What is not good is everything past the first mistake a newcomer makes:

- **The caret lands on the outer expression, not the wrong part.** Inference reports where
  unification failed, which for anything nested is the whole call or literal.
- **One mistake becomes three reports.** Follow-on errors are not suppressed, so the real
  error competes with noise (35 corpus programs carry a stray `cap_grant`).
- **Some hints are wrong.** A hint that names the wrong fix is worse than no hint.
- **Core features talk in compiler internals.** Choreography errors name generated states
  (`S_recv_Msg_Prod_Cons_1`), actor errors name the state record instead of the actor,
  refinement errors show `$cb_arg`, session errors show `Send(T, ...)` and a bare `a`.
- **The house style breaks in places.** Some errors go through a different printer
  (`file:line:col: error:`), some quote with `'…'`, 21 of ~181 codes have an `--explain` page.

The standard is unchanged from the triage plan §3: every error says **where** it went wrong,
**what** was expected versus seen, **the fix**, and **why** the rule exists. The acceptance
test is unchanged too: given only the error text, a model fixes the program in one turn (M1).

This plan has two parts. **Part X** is cross-cutting machinery every feature needs. **Part F**
is per-feature work for capabilities, actors, choreography and sessions, refinements,
linearity and interfaces. Part F items mostly *use* Part X; they are listed separately because
each needs feature-specific wording and fixes that no general mechanism supplies.

Every item lands with at least one new `test/errors/<slug>_<n>.march` case whose `.expected`
shows the target output, added through `scripts/seed-error-corpus.sh`.

---

# Part X — Cross-cutting machinery

## X1. Put the blame on the subterm that is wrong

**Evidence** (all `--check`, 2026-11-02):

```march
fn f(xs : List(Int)) : List(String) do
  List.map(xs, fn x -> x + 1)          -- caret: all of `List.map(...)`
end                                     -- blamed: the declared return type

fn mk() : Result(List(Cfg), String) do  -- one bad field in the 2nd record:
  Ok([{ name: "a", ports: [1], ... }, { name: "b", ports: ["x"], ... }])
end                                     -- caret: the whole 90-col list
                                        -- note: "Argument to constructor `Cons`."

fn parse(s : String) : Result(Int, String) do
  Ok(string_to_int(s))                  -- blamed: the return type, not Ok's argument
end
```

**Target.** The caret sits on `x + 1`, `"x"` and `string_to_int(s)` respectively, and the
message says how the expectation reached there:

```
-- TYPE MISMATCH ------------------------------------------------- f.march

The function passed to `List.map` returns `Int`, but it needs to return `String`:

3 |   List.map(xs, fn x -> x + 1)
                           ^^^^^

`f` promises a `List(String)` (line 2), so each element `List.map` produces
must be a `String`.

hint: `int_to_string(x + 1)` converts it.
```

**Mechanism.** Check mode has to go deeper. Today the expected type is pushed into function
arguments, but not into:

1. lambda bodies when the lambda is an argument of a call whose result type is already known
   (needs the result type to flow back through the callee's signature to its callback's
   return type before the lambda is checked);
2. constructor arguments (`Ok(e)` checked against `Result(Int, _)` checks `e` against `Int`);
3. list, tuple and record literal elements;
4. `if` / `match` arms against a known expected type (the `if` case already partly does).

Each push records a **blame path** (`return of f` → `element of List.map's result` →
`return of the lambda`). The renderer turns the path into the one sentence that explains
the expectation. This replaces the generic "the expected type comes from here" label when a
path is available.

**Acceptance.** The three programs above, plus one per literal kind, produce a caret no wider
than the wrong subterm. `scripts/types-oracle.sh` shows no change to inferred types; only
diagnostic text moves.

## X2. Structural type diffs

When the two types are large, "expected `X` but got `Y`" with both printed in full is
unreadable. Render the **difference**:

```
This `Cfg` record has the wrong type in its `ports` field:

    { name : String, ports : List(Int), tags : … }
                              ^^^ expected `Int`, found `String`
```

Rules: elide subtrees that are equal (`…`), keep the path to every difference, name record
fields and constructor positions, and keep type variables apart (`a` and `b` in one message
mean different things). Never print a constructor the user did not write (`Cons`).

**Acceptance.** A record, a nested `Result(List(_))` and a function type each get a diff case
in the corpus.

## X3. One root cause, one report

**Evidence:**

| Program | Reports | Should be |
|---|---|---|
| `coutn + 1` with param `count` | unbound `coutn` **and** "unused variable `count`" | just the first |
| `List.filter(fn (x, y) -> …)` | `callback_arity_mismatch` **and** a `type_mismatch` on the same lambda | just the first |
| Any type error in a program whose `main()` does IO | the error **and** `cap_grant` | just the type error |
| `file_write` reached from `main(c : Cap(IO.Console))` | `cap_needs` + a `HINT` chain + `cap_grant_exceeded` | one report |
| An IO call in a module with no `needs` | `cap_ceiling` **and** `cap_needs` | one report |
| A role taking a protocol step out of order | `type_mismatch` **and** `linear_used_twice` | just the first |
| A wrong `Chan.send` | three `session_state_mismatch` | just the first |

**Mechanism.**

1. **Poison.** A binding or expression whose type check failed gets an error type that unifies
   with everything and reports nothing. Linearity, exhaustiveness and session-state checks skip
   bindings that touch poison.
2. **Error-suppression rules** in one table next to `lib/errors/code.ml`: `(primary code,
   suppressed code, scope)`. The examples above are the first rows. `unused_binding` is
   suppressed for a binder within edit distance 2 of an unbound name in the same function.
   `cap_grant` and `cap_root_broad` are suppressed when any type error exists (the program is
   not yet a program).
3. **Merging.** Capability findings about the same fact (`cap_ceiling`, `cap_needs`, the reach
   chain, `cap_grant_exceeded`) merge into one diagnostic whose labels carry the others' spans
   and whose fix covers both edits (see F1).

**Acceptance.** Every `test/errors/` case with more than one `-- ERROR` (103 today) is
reviewed. Each must either have errors with genuinely independent causes, or shrink to one
error. Record the per-case verdict in the PR.

## X4. Hints must be correct, and never leak internals

**Evidence:**

- `xs |> List.filter(fn (x, y) -> x > 0)` says "Pass a curried function instead:
  `fn a -> fn b -> …`". `filter`'s `pred` takes one argument; the fix is `fn x -> …`.
- `x(x)` stacks four notes, one says the type is infinitely recursive and another asks
  "Did you mean to pass this as a callback?".
- `refinement_violated_2`: "argument `$cb_arg` of `f`", and the guard it suggests is
  `if _ >= 0 do …`, the predicate's placeholder, not the argument `-3`.
- `cap_root_broad` on a *type* (`type Loot = Loot(Cap(IO))`) says "this function takes".
- `missing_impl` for `String + …` says "only Int and Float do", but the caret is on
  `fn main()`.

**Mechanism.**

1. **Hint selection is exclusive.** A type mismatch gets at most one "likely cause" hint. The
   rule chooser picks the most specific one and drops the rest. The infinite-type
   note pre-empts all others.
2. **A hint that proposes code is checked.** Where a hint carries a `fix`, the corpus already
   records "after fix: exit N". Extend `run_errors` so a case with a fix whose
   result is not exit 0 (or a strictly later error) fails, unless the case is marked
   `-- EXPECT-FIX-PARTIAL:`.
3. **An internals lint in `run_errors`.** Fail on `$`, on generated module or state names
   (`_Msg`, `S_`, `_Run.`, `_Cons.` prefixes from `desugar_endpoints`), on constructor names
   the program didn't write (`Cons`, `Nil` in "argument to constructor"), and on a bare type
   variable that isn't introduced by the message. An allowlist file handles the legitimate
   ones.

## X5. One renderer, one house style

**Evidence.** `endpoints_label_invalid` and `remote_actor_unroutable` print
`errors/x.march:12:12: error: …` (a positioned `Failure` from lowering or desugar, printed
raw by `bin/main.ml` around line 4232). `actor_handler_state_type` uses `'Poke'` quotes,
lowercase, and an indented `expected:/got:` block with no explain pointer. `role_needs_invalid`
and `protocol_invalid` put the caret on the role or `protocol` keyword, not the step.

**Mechanism.**

1. Every positioned `Failure` site in desugar and lowering raises a structured diagnostic
   (`Errors.Diagnostic_exn of diagnostic`) caught once in the driver and printed by the
   standard renderer. The string-sniffing for `": error: "` goes away.
2. A style lint in `run_errors` over rendered output: backticks not quotes, first word
   capitalized or a backticked name, terminal period on prose lines, no "I got" for type
   mismatches.
3. The header line names the category (Elm's `-- TYPE MISMATCH --`, `-- CAPABILITY --`,
   `-- PROTOCOL --`) from a `category` field on each code in `code.ml`, instead of the bare
   `ERROR`.

## X6. `--explain` for every error that ships

21 of ~181 codes have a page in `specs/lang/errors/`. Priority: every code that appears as a
primary error in the corpus (about 80), core-feature codes first (Part F). Each page has: the
rule in one paragraph, why it exists, the smallest failing program, the fixed program, and
links to the reference chapter.

Add doc-lint check H: every code with `severity = Error` that appears in a `test/errors/`
`.expected` file has a page. Ratchet: the check reads an allowlist of pending codes that may
only shrink.

## X7. Render "reached from" chains as spans

Capability grants, role grants, `no_panic`, `pure`, `deterministic`, `no_alloc` all report a
call chain as prose: "(reached from `main`: main → greet → save)". Render it as a trace
whose every hop has a span:

```
-- CAPABILITY --------------------------------------------------- app.march

`main` is granted only `IO.Console`, but this writes a file:

5 |     file_write("/tmp/x", int_to_string(n))
        ^^^^^^^^^^

It is reached from `main` through:

9 |     log(int_to_string(step(1)))
                          ^^^^ `main` calls `step`

fix: grant `main` the file capability too:

-  fn main(c : Cap(IO.Console)) do
+  fn main(c : Cap(IO.Console), _fw : Cap(IO.FileWrite)) do
```

The **primary** span is the use (the thing that needs the capability), not `main`'s
signature. `main` is a label. One shared helper (`Errors.with_trace`) for every chain-walking
check, capped at 4 hops shown with "… N more".

## X8. Suggestions that use types, refinements and capabilities

Today every "did you mean" is spelling only. The checker knows much more at an error site: the
argument types, the expected result type, the facts the refinement checker holds, and which
capabilities are in scope. Suggestions should use all of it, in three tiers.

**Evidence:**

- `send(a, Pokee(1))` suggests `Post` (of `Method`) and `Pong` (of `WsFrame`) ahead of `Poke`,
  the only message actor `A` accepts. `LinearMapRep` suggests `LiveProcess`.
- `List.fodl(xs, 0, fn (a, b) -> a + b)` gets no suggestion at all: `fold_left` is 5 edits
  away. The call's shape (`List(Int)`, `Int`, a function, result `Int`) singles it out.
- `List.head(xs) + 1` on an unconstrained `xs` warns that `f([])` panics, but doesn't mention
  `List.head_opt`, the same function without the precondition (likewise `nth` / `nth_opt`).

### Tier 1: rank spelling candidates by type fit

For an unknown name, constructor, field or message, keep the spelling candidates (distance
≤ 2, or ≤ 1/3 of the length), then rank them by:

1. whether the candidate's type unifies with what this position needs: the pid's message
   type, the annotated or expected type, the record's field type;
2. same module or actor;
3. edit distance.

A candidate that fits is shown alone. Stdlib-internal modules are dropped unless nothing else
is in range.

**Mechanism.** A **trial unification**: unify a fresh instance of the candidate's scheme against
the call-site shape and roll back. `typecheck_unify.ml` has no rollback today; add a trail of
the mutable links set during the trial (union-find with undo). A cheaper fallback for the first
cut is an occurs-free structural match on `pp_ty_canonical` strings, as `lib/search` does.

### Tier 2: search by type when spelling finds nothing

When no spelling candidate fits, search the names in scope (the qualifier's module for
`List.fodl`, otherwise the module, its imports and the prelude) for functions whose type
unifies with the call shape `(List(Int), Int, ?) -> Int`. This is Hoogle's query run against the
error site, using the typechecker's real types rather than `lib/search`'s strings.

```
-- UNKNOWN NAME ------------------------------------------------- f.march

`List` has no function `fodl`.

3 |     List.fodl(xs, 0, fn (a, b) -> a + b)
             ^^^^

These `List` functions take these arguments:

    List.fold_left(xs : List(a), acc : b, f : b -> a -> b) : b
    List.fold_right(xs : List(a), acc : b, f : a -> b -> b) : b
```

**Near-fits count.** Score a candidate by how many argument positions unify, not all-or-nothing.
In the example the lambda is `(a, b) -> …` and both folds want a curried `b -> a -> b`. A
candidate with one mismatching argument is still the answer; the next error (curried callback,
X4) explains that argument. Also try **argument permutations** of the user's own function when
the name resolves but the arguments don't fit: `List.map(f, xs)` → "the arguments are the
other way round", as a fix.

**Missing conversions.** The same search with arity 1 replaces the hard-coded conversion
hints ("Use `int_to_string(x)`…"). For a mismatch `expected T, got S`, look for in-scope
functions `S -> T` (and `S -> Option(T)` / `Result(T, _)` when the context can take them),
ranked by module and doc tags. One candidate is shown as a fix; several as a list.
The hand-written hints stay as overrides where the search would pick badly.

**Bounds.** Search only on an error path; cap candidates scanned (the in-scope set, not the
whole stdlib index) and shown (3). Results must be deterministic for the golden corpus: order by
score, then module, then name.

### Tier 3: use refinements and capabilities

The refinement checker runs after typechecking, and knows things the type tier can't:

1. **Total twins.** When a call fails a precondition (`refinement_violated`,
   `undeclared_requirement`), look for a function with the same arguments, no precondition, and
   the result wrapped in `Option` / `Result`: `head` → `head_opt`, `nth` → `nth_opt`. Suggest it
   with the `match` it needs. Precompute the twin table from the stdlib index at build time
   (same module, name stem, signature shape) so this needs no solver call. A `@[total_twin(f)]`
   attribute covers pairs the naming convention misses.
2. **Discharging guards.** The violated precondition, instantiated at the call (`len(xs) > 0`,
   not `len(_) > 0`), is a candidate guard. Check it with the solver *under the current path
   facts*: if the instantiated guard makes the obligation valid, offer
   `if len(xs) > 0 do … else … end` as the fix (F4 point 2). If not (the value is a
   literal that can never satisfy it), say so instead of suggesting a dead guard.
3. **Rank by provability.** When several spelling or type candidates fit, a candidate whose
   precondition is provable at this call ranks above one whose precondition isn't.
4. **Rank by capability.** A candidate that needs a capability not in scope here ranks lower,
   and its line says so ("needs `Cap(IO.FileWrite)`, which `main` doesn't grant").

**Bounds.** Solver work happens only after an error, with a per-diagnostic budget (at most 3
candidates × the existing VC timeout). A timeout means no suggestion, never a different one.
Use the VC cache's stored verdicts where present, and remember that a warm VC cache
changes counterexample text (`scripts/refine-oracle.sh` runs each fixture from a fresh cwd for
this reason). The corpus must run cold too.

**Acceptance.** Corpus cases: `Pokee` → `Poke` alone; `List.fodl` → the two folds;
`List.map(f, xs)` → swap fix; `List.head(xs)` → `head_opt` with a `match`; a `nth(xs, 5)` on a
3-element literal → "can never hold", no guard.

## X9. Two bugs found while surveying

1. **`Lsit.length([1,2])` passes `--check`** and fails at run time with
   "unbound variable: Lsit.length". `Lsit.nope(...)` is correctly rejected with "Did you
   mean `List`?", so qualified resolution falls back to the unqualified builtin when the last
   segment names one. This is a soundness hole as well as a message bug.
2. The run-time stack trace for that program names line 7, not line 4.

Both go first; neither depends on anything else here.

---

# Part F — Core features

## F1. Capabilities

**Evidence:**

```march
fn read(c : Cap(IO.FileRead)) : String do "x" end
fn main(c : Cap(IO.Console)) do println(read(c)) end
```

gives `cap_grant_exceeded` on `main` **and** "expected `IO.FileRead` but got `IO.Console`",
a type mismatch that reads like two unrelated types.

An actor handler calling `println` in a module without `needs` reports `cap_ceiling` with
the caret on `mod Main`, and `cap_needs` on `main`'s parameter. Neither names the handler or
the `println`.

**Target.**

1. **A capability mismatch is its own message**, not a type mismatch: "`read` needs file-read
   access, but `c` is the console capability." Then one line of the lattice: "`IO.Console` and
   `IO.FileRead` are both parts of `IO`; neither contains the other." Then the fix: thread a
   `Cap(IO.FileRead)` from `main`, as an `FReplace` on the signature.
2. **One report per missing authority** (X3 merging). The `needs` line and the grant edit are
   two hunks of one fix.
3. **The primary span is the use.** Every capability error points at the call that needs the
   authority, with the `needs` declaration or grant as a label (X7).
4. **Name the context.** "This handler of actor `A` prints", "the body of role `Cons`
   writes a file".
5. **Explain pages for the core codes:** `cap_grant`, `cap_grant_exceeded`, `cap_needs`,
   `cap_ceiling`, `cap_widen`, `cap_root_broad`, `cap_deserialize`, `proof_cap_return`,
   `proof_cap_mint_private`, `io_not_allowed`, each with a lattice diagram.
6. `cap_root_broad` says "this field" / "this type" when it is on a type, and is suppressed
   while errors exist (X3).

## F2. Actors

**Evidence:**

| Mistake | Today |
|---|---|
| Typo'd message `Pokee` | `unknown_constructor` ranking `Post`, `Pong` above `Poke` (X8) |
| `Poke("one")` where `Poke(k : Int)` | "Argument to constructor `Poke`", no mention that this is actor `A`'s message or where its handler is |
| Handler returns `Int` | `actor_handler_state_type`: `'Poke'` quotes, `expected:` block, no explain (X5) |
| `{ state with count: … }` | "This record does not have a field called `count`" without saying it is `A`'s state |
| Message to the wrong actor | names the pid's actor as "an actor whose state is `{ s : String }`" |
| IO in a handler | see F1 |

**Target.**

1. **Say "actor"**. A message type mismatch reads "`Poke` is a message of actor `A`; its handler
   (line 6) takes `k : Int`". It labels the handler's parameter.
2. **Name actors, not state records.** `send_wrong_actor` says "this pid is an actor `B`
   (spawned on line 24)". It lists `B`'s messages as did-you-means. A `Pid` carries its actor
   name for diagnostics even if its type is the state record.
3. **Handler result.** "The handler for `Poke` must return `A`'s new state, a
   `{ n : Int }`, but returns an `Int`." Hint when the body is an expression over one field:
   `{ state with n: state.n + k }` as a fix.
4. **State field typos** name the actor and offer the field: "`A`'s state has no field
   `count`. Did you mean `n`?" (the only field, but the same rule for longer records).
5. **Survey the remaining actor checks** (call/reply type, `spawn` of a non-actor, supervision
   specs, `migrate_state`, `@[remote]` routing, `pid_serialize`, `codec_missing`) for the same
   four questions, one corpus case each. `remote_actor_unroutable` moves onto the standard
   renderer (X5).

## F3. Choreography and session types

Choreography is where March is most ahead of other languages and where the errors are
furthest behind. The user writes a protocol, then writes role bodies against **generated**
names, so any error in a role body speaks in generated terms.

**Evidence:** a `Cons` role that calls `choose_done` before receiving:

```
expected `S_choose_more_done` but got `S_recv_Msg_Prod_Cons_1`. [type_mismatch]
    Both are states of a generated protocol role: ...
```

then a second error, `linear_used_twice` on `st`, which follows from the first.

A wrong `Chan.send` gives three errors. One is "expected a channel endpoint but got `a`",
and the first says "I expected `Send(T, ...)`".

`protocol_invalid` puts the caret on `protocol Q do`, not the step at fault.
`role_needs_invalid` asks "what does `I` do if `C` crashes before sending?" but offers no
code.

**Target.**

```
-- PROTOCOL ----------------------------------------------------- app.march

Role `Cons` chooses `done` here, but the protocol says it must first receive an
`Int` from `Prod`:

30 |     Stream_Cons.close(s, Stream_Cons.choose_done(s, st, true))
                              ^^^^^^^^^^^^^^^^^^^^^^^

Protocol `Stream`, as `Cons` sees it:

15 |       Prod -> Cons : Int          <- `Cons` is here
16 |       choose by Cons:
17 |         more -> ...
18 |         done -> ...

hint: receive first with `Stream_Cons.recv_Msg_Prod_Cons_1(s, st, fn (n, st1) -> ...)`,
then choose with `st1`.
```

**Mechanism.**

1. **A state-name map.** `desugar_endpoints` records, for each generated state type, the
   protocol step that produces it (protocol, role, step span, the step's prose: "receive an
   `Int` from `Prod`", "choose `more` or `done`", "close"). `typecheck` consults it whenever
   both sides of a mismatch are states of one role and emits a `protocol_step_order` diagnostic
   in protocol terms. The renderer shows the protocol excerpt with a "you are here" marker.
2. **Suppress the linearity follow-on** (X3 poison): the state value in a mis-stepped call is
   poisoned.
3. **Session channels the same way**: `Chan.send` on a `Recv(Int, End)` channel reads
   "This channel is waiting to **receive** an `Int` here, so it can't send". It names the line
   where the channel's protocol was declared. A channel whose type is already broken is
   poisoned, so `Chan.close` doesn't report `a`.
4. **Protocol well-formedness errors point at the step.** `protocol_invalid`,
   `role_needs_invalid`, `endpoints_label_invalid`, `protocol_same_participants` take the
   offending step's span as primary and the `protocol` header as a label.
   `role_needs_invalid` gets an `FInsert` of the `or crash do … end` skeleton.
5. **Role-body mistakes beyond step order**, one corpus case each: wrong payload type for a
   step (name the step and the declared payload), wrong role (body written for `Prod` run as
   `Cons`), a `choose` missing a branch (list them with a fix), using `st` after `close`.
6. **Explain pages** for every protocol code, linking `specs/lang/choreography.md` sections.

## F4. Refinements and contracts

1. **No internal binder names** (`$cb_arg`): name the parameter as the user wrote it, or
   "the argument" with a span.
2. **The guard suggestion uses the real expression**: `if n >= 0 do f(n) else …`, not
   `if _ >= 0`. When the argument is a literal (`-3`), say the literal can never satisfy it.
3. **Show the counterexample** the solver found when the call is not a literal: "fails when
   `n = -1`". The VC cache stores it already; the message should print it.
4. **Show where the failing value came from**: a label on the binding or the parameter
   whose refinement is too weak, with the suggestion to strengthen that one
   (`undeclared_requirement` already does this partly: "but f([]) panics").

## F5. Linearity

`linear_used_twice` already shows the first consumption. Extend it to **paths**: when the
first consumption is in one `match` arm or `if` branch, say so, and when the value is consumed
in a loop body say "each iteration consumes it". `linear_never_used` on an early return names
the return. Poison (X3) stops linearity errors from following a type error on the same binder.

## F6. Interfaces and impls

1. `missing_impl` puts the caret on the operator or call that needed the impl (`a < b`), not
   on the enclosing function.
2. When the type is the user's and the interface is derivable, the fix is
   `derive Ord for V` (`FInsert` after the type declaration).
3. For a constraint arising inside generic code, show the chain: "`sort` needs `Ord(a)`,
   because it calls `compare` (line N); here `a` is `V`."

---

# Measurement

## M1. The one-turn metric

Build `scripts/error-one-turn.sh` as triage plan D8 specifies. For every `test/errors/` case
plus this plan's new ones, give a model the program and the rendered error and ask for a fix.
Score it fixed if the result passes `--check` and keeps the program's intent (the case's
`-- EXPECT-FIXED-BY:` hint, or a reviewer).

Not a CI gate. Run it before and after each Part X item and quote the delta in the PR.
Report it per code, so the worst classes are visible.

---

# Order

| # | Item | Depends on | Size |
|---|---|---|---|
| 1 | X9 bugs | — | small |
| 2 | M1 metric | — | ½ session |
| 3 | X3 poison + suppression table | — | medium |
| 4 | X5 one renderer + style lint | — | medium |
| 5 | X4 hint exclusivity + internals lint | X5 | small |
| 6 | X1 blame paths | — | large |
| 7 | X2 type diffs | X1 | medium |
| 8 | X7 traces | X5 | small |
| 9 | X8 tiers 1–2 (type-directed) | trial unify | medium |
| 9b | X8 tier 3 (refinements, caps) | X8 tiers 1–2, F4 | medium |
| 10 | F1 capabilities | X3, X7 | medium |
| 11 | F3 choreography + sessions | X3 | large |
| 12 | F2 actors | X8 | medium |
| 13 | F4, F5, F6 | X1, X3 | medium each |
| — | X6 explain pages | ongoing, alongside each F item | — |

X3 and X5 come before the large items because both change most `.expected` files. Landing them
first keeps later diffs readable.

## Risks

- **Corpus churn.** X3, X5 and the header change touch hundreds of `.expected` files. Land
  each as its own PR whose diff is only regenerated goldens plus the mechanism.
- **Check-mode changes can change inference.** X1 must keep `scripts/types-oracle.sh` green on
  the inference tier. Only the diagnostic tier may move.
- **The LSP shows the same diagnostics.** Multi-span traces and protocol excerpts need a
  sensible `relatedInformation` mapping. Check each in `lsp/test/` as it lands.
- **Generated-name map drift.** F3's state map lives next to the generator, and a corpus case
  per step kind pins it.
