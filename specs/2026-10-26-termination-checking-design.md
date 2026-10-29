# Design: termination checking, and the induction hypothesis it pays for

**Date:** 2026-10-26
**Status:** design. Nothing built. Phases 0-5 below, one PR each.
**Base commit:** `c918d14ca` (origin/main, "docs(stdlib): regenerate API docs from stdlib source").
**Probe environment:** compiler `_build/default/bin/main.exe` built from that commit with
`dune build --root . bin/main.exe` on 2026-10-26; z3 4.16.0 on PATH (CI has 4.8.12);
macOS (Darwin 25.6), load average 2-4. Every checker row was run as
`HOME=$(mktemp -d) main.exe --check --refine-report --refine-report-sites probe.march`.
A row that says a program "loops" ran it as `main.exe probe.march` (interpreted) and as
`main.exe --compile -o prog probe.march && ./prog` (compiled), each under a 10 s timeout.
Two **scratch builds**, never committed, supplied measurements no flag can give:
- **COUNT:** a counting pass in `typecheck_tailcall.ml`, behind `MARCH_TERM_COUNT=1`. It classifies every recursive call's arguments and every recursive function, and feeds §0.5 and §7.
- **IH:** `gate_unverified_posts` assumes a function's own return at its self-calls, behind `MARCH_TERM_IH=1`. That is the Phase 3 hook with *no* termination gate. It feeds rows r1-r4 and c1-c3.

**Prior designs this continues:**
- the Tier 2 structural induction (`specs/lang/refinement-types.md:5277-5343`);
- `specs/2026-09-18-parametric-element-flow-design.md` §3.2 (**EF §3.2**: the element-return self-call hypothesis; it defers "the relaxation" of its structural rule to "elsewhere"; this design is that elsewhere);
- `specs/progress/2026-10-24-refine-demand-chains.md` (C1 call tails; the gate as a fixpoint);
- `specs/progress/2026-10-24-refine-local-fn-option-return.md` (**O1**: a local `fn`'s structural self-call hypothesis).

Today, March checks **stack safety**, not termination. It accepts `fn spin(n : Int) : Int do spin(n) end` in silence. It also accepts a
non-tail `grow(n - (0 - 1))` as "structurally recursive" (row t9b). The refinement checker
stays sound by never assuming an unproved recursive return. The cost is every proof that
needs the induction hypothesis (IH) at a non-structural call: `sum_to`
cannot prove `{Int | _ >= 0}`.

A termination proof is the licence for that IH. This design:
- builds the proof: SCC call graph, structural and metric `@[decreases]`, SMT obligations through `check_call`;
- grants the IH only to SCCs it certifies;
- leaves every other function exactly where it is today.

---

## 0. Where things stand (probed 2026-10-26 on `c918d14ca`)

### 0.1 Recursion shapes: what is accepted today

| Row | Program | Today (measured) | After |
|---|---|---|---|
| t1 | `fn spin(n : Int) : Int do spin(n) end` | accepted, no diagnostic, 0 obligations | **unproved** (no metric: the argument is the parameter) in the report; `@[diverges]` declares it (phase 4) |
| t2 | `fn up(n : Int) : Int do if n == 100 do 0 else up(n + 1) end end`, `up(200)` | accepted, no diagnostic | unproved. The path has `n != 100`, which bounds nothing. With guard `n >= 100`, the metric `100 - n` proves (annotated phase 2, inferred phase 5) |
| t3 | mutual `ev`/`od` on `n - 1`, exit `n == 0`, `ev(0 - 3)` | accepted, no diagnostic | unproved: `0 <= n - 1` is refuted by `n = -1`. Proved with `n : {Int \| _ >= 0}` on both (phase 2, one SCC) |
| t4 | `fn down(n : Int) : Int do if n == 0 do 0 else down(n - 1) end end`, `down(0 - 1)` | accepted, no diagnostic. **Loops**: no result in 10 s, interpreted and compiled | unproved, witness `n = -1` (phase 2) |
| t5 | `fib`, exit `n < 2`, calls `fib(n - 1) + fib(n - 2)` | 2 warnings `non_tail_recursion` ("structurally recursive but not tail-recursive") | **proved**, metric `n` (`n >= 2` on the path); the stack warnings are unchanged |
| t6 | `sum_to(n : Int) : Int`, exit `n == 0`, `n + sum_to(n - 1)`, `sum_to(0 - 1)` | 1 warning `non_tail_recursion`. **Loops** (10 s, both modes) | unproved, witness `n = -1` |
| t7 | `len2(xs : List(Int)) : Int`, `Cons(_, t) -> 1 + len2(t)` | 1 warning (stack) | proved structural (phase 1) |
| t7b | same shape on `xs` itself: `Cons(_, _) -> 1 + bad(xs)` | **error** `non_tail_recursion` | unchanged error; unproved |
| t8 | Ackermann, exits `m == 0` / `n == 0`, `ack(m - 1, ack(m, n - 1))` | 1 warning (stack); `@[decreases(m, n)]` is a **syntax error** (probe p18) | `@[decreases(m, n)]` parses (phase 2). Unproved with `== 0` exits (witness `m = -1`); proved with `<= 0` exits |
| t9 | `bits(n / 2)`, exit `n <= 0` | 1 warning (stack) | proved, metric `n` |
| t9b | `bits1(n / 1)`, `same(n - 0)`, `grow(n - (0 - 1))`, all non-tail | each **accepted as "structurally recursive"** (warning only). `grow(1)` **loops** | unproved; each obligation refuted (e.g. `n = 1`) |
| t10 | local `fn go(i : Int) : Int do go(i + 1) end` in a non-recursive `f` | accepted, no diagnostic | unproved |
| t10b | local non-tail `1 + go3(i + 1)` in a non-recursive `h` | **no diagnostic at all**: the stack check never runs (F3) | unproved; the stack gap is filed in phase 0 |
| t11 | `fn h(x : Int) : Int do apply2(h, x) end`, where `apply2(g, x) = g(x)` | accepted, no diagnostic; no call-graph edge | unproved: a reference edge `h → h` with unknown arguments (phase 1) |
| t11b | `viafold(n) = List.fold_left([n], 0, fn (acc, x) -> acc + viafold(x))` | accepted, no diagnostic | unproved: a lambda edge, `x` unrelated to `n` |
| t11c | `type Fix = Fix(Fix -> Int)`; `w(f) = match f do Fix(g) -> g(f) end`; `omega() = w(Fix(w))` | accepted, no diagnostic, **no syntactic recursion anywhere**. Compiled: SIGBUS (stack guard page); interpreted: no result in 10 s | `w` unproved: it calls a value of a non-positive type (phase 2, §3.6) |
| t12 | actor handler `on Spin(n) do { state with value: spin(n) } end`; `on Again(k) do send(self(), Again(k + 1)) … end`; top-level `serve(n)` printing and calling `serve(n + 1)` | handlers are never visited by the tail pass (F3); `serve` accepted | `Spin`: "may not return" in the report. `Again`: no recursion (a message loop). `serve`: unproved until `@[diverges]` (phase 4) |
| t13 | `while` / `for` loops | **do not exist**. No `while` token in `lexer.mll`. `loop` is a session-protocol keyword only (`parser.mly:1189`) | n/a: iteration is recursion |
| t14 | `@[decreases(n)]`, `@[diverges]`, `@[totally_made_up]` on a `fn` | parse, **silently ignored** (no unknown-attribute check, probes p17/p19) | the first two mean something (phases 2, 4); D6 |

### 0.2 The payoff: proofs the IH would buy

| Row | Program | Today (measured) | IH scratch build (measured) | After |
|---|---|---|---|---|
| r1 | `sum_to(n : {Int \| _ >= 0}) : {Int \| _ >= 0}`, let form `let r = sum_to(n - 1)` then `n + r`; caller `need_nn(sum_to(k))` | return skip `solver-undecided`; caller skip `unreflectable-subject` | **5/5 proved**, caller included | proved (phase 3) |
| r2 | same contract, nested form `n + sum_to(n - 1)` | return skip `unreflectable-subject` | **still skip**: a call nested in arithmetic never reflects (F8) | proved (phase 3 adds nested-call reflection) |
| r3 | `sum_to : {Int \| _ >= n}` (let form); `need_ge(sum_to(10))`, `need_ge : {Int \| _ >= 10}` | return skip `solver-undecided`; caller skip | **5/5 proved** | proved (phase 3) |
| r4 | `len2(xs : List(Int)) : {Int \| _ >= 0}`, `1 + len2(t)`; `need_nn(len2(xs))` | return skip `unreflectable-subject`; caller skip | **still skip** (nested form, as r2) | proved (phase 3; structural phase 1) |
| r5 | `apply2(xs, ys) : {List(Int) \| len(_) == len(xs) + len(ys)}`, `Cons(h, apply2(t, ys))` | **proved** (Tier 2 structural IH) | proved | unchanged |

### 0.3 Why the IH needs a gate: the soundness controls

| Row | Program | Today (measured) | IH scratch build, no termination gate (measured) | After |
|---|---|---|---|---|
| c1 | `loopy(x : Int) : {Int \| _ < 0} do loopy(x) end`; `need_pos(loopy(k))` | both skip `unreflectable-subject` | `loopy` **"proved"**. The call is a **false violation**: "does not satisfy precondition `_ > 0` (e.g. loopy() can return -1)". `loopy` returns nothing | unchanged from today: not terminating, so no IH |
| c2 | `down(n : Int) : {Int \| _ == 0}` (t4's body); `need_nn(down(0 - 1) - 1)` | both skip | `down` "proved"; the call **violated**. `down(-1)` never returns | unchanged from today |
| c3 | `loopy(x) : {Int \| _ > 0 && _ < 0}` (an unsatisfiable return); `need_neg(loopy(k))` | both skip | **2/2 proved**: the unsatisfiable return is "proved", and so is the call | unchanged |
| c4 | mutual `@[measure] ma`/`mb` on `Nat`, cycle `ma(Z) → mb(Z) → ma(Z) + 1` (`mb` marked `@[no_warn_recursion]`) | **no `invalid_measure`**: the gate checks self-calls only (F5). Not exploitable today, since `ma(n)` does not reflect (skip) | — | `invalid_measure`: the SCC is not structural (phase 1) |
| c5 | m1/m3: `@[measure] bad(n : Nat)`, `Z -> bad(n) + 1` | `invalid_measure` + `non_tail_recursion` errors | — | unchanged |

### 0.4 Real divergences in the standard library (found by the COUNT sweep)

| Row | Call | Today (measured) | Why |
|---|---|---|---|
| s1 | `List.range_step(5, 0, 0)` | **loops** (10 s, both modes) | `range_step_go` (`list.march:107-113`) with `step = 0` and `i > stop` recurses on the same `i` |
| s2 | `Range.to_list({start: 5, stop: 0, step: 0})` | **loops** (both modes) | `Range.new_step` guards `step != 0`, but the type is a plain record, so a literal bypasses it (`range.march:43-47, 63-70`) |
| s3 | `Control.chunks("abcdef", 0)` | **loops** (both modes) | `chunks_from(…, off + size, …)` with `size = 0` (`control.march:1979-1988`); there is no precondition |
| s4 | `Duration.format(Duration(0 - 4611686018427387903 - 1))` | interpreted: loops. Compiled: **SIGBUS**, stack overflow | `ms < 0 -> format(Duration(-ms))` (`duration.march:221-224`); `-min_int` is `min_int` |

### 0.5 How much recursion a check would reject today (COUNT sweep)

The sweep ran `--check` over all 135 `stdlib/*.march` and all 417 `test/native/*.march` and
deduplicated by declaration site. The units:
- **Unit** = a recursive function: a top-level function in a recursive SCC, a self-recursive local `fn`, or a function that passes or captures its own name.
- **Structural** = some argument position holds a pattern sub-component (the tail pass's `smaller` set) at every recursive call of the function.
- **Int metric** = a position holds `p - k` / `p / k` / `p + k` with a positive literal `k` (`k >= 2` for `/`) at every call.
- **Bounded** = the parameter also appears in a comparison or a `{Int | _ >= …}` refinement in the function. This split is a regex over the source, not SMT, so treat B/C as ±10%.
- **Hand classification**: every function with no syntactic metric (127 in stdlib, 22 in native) was classified by reading its body.

| Class | stdlib (762) | test/native (522) | Passes |
|---|---|---|---|
| A structural | **465** (61%) | 74 | phase 1 |
| B Int metric, guard bounds it | 85 | **346** | phase 2 (default metric) |
| C Int metric candidate, no bound on the path (diverges on some input, e.g. `if i == 0 … go(i - 1)`; or the bound is indirect, e.g. `string_byte_at` returning -1 past the end) | 54 | 80 | needs a guard/precondition, or a builtin contract |
| D lexicographic: 6 syntactic, plus 18 mutual recursive-descent parsers that call a member at the **same** input position (`json`, `toml`, `yaml`) | 24 | 0 | phase 2 with `@[decreases(remaining, rank)]` |
| E intentional divergence / external-event loop (servers, `recv_*`, `await_*`, `accept_loop`, `heartbeat`, EOF-driven readers) | 41 | 8 | phase 4 `@[diverges]` |
| F recursion through a closure or a function value (12 pass their own name, 13 recurse only inside a lambda) | 25 | 0 | not in scope (§3.6) |
| G metric through a helper's result (`advance(st)`, `Deque.pop_front`, `split_at`, `pair_up`, `decode_one`: `len` falls only by the helper's postcondition) | 29 | 14 | phase 2 + a helper `len` contract |
| H Int metric not syntactic (step variable, `let next = …`, `n / base()`, hash-level `shift + 5`) | 33 | 0 | phase 2 annotation / phase 5 |
| I no metric (`Random.next_float_open` rejection sampling, `Plot` float stepping, Aho-Corasick fail links, `Duration.format`, `Seq` streams) | 6 | 0 | `@[diverges]` or a rewrite |
| **Fails a plain structural-or-obvious-metric check (C+D+E+F+G+H+I)** | **212 (28%)** | **102 (20%)** | |

Context:
- 401 of the stdlib units are top-level, 349 local, 12 value-recursive.
- 47 stdlib units are mutual-SCC members; 16 in native.
- `@[no_warn_recursion]`: 8 stdlib, 7 native.
- Only **11** recursive stdlib functions carry a refinement in their signature (10 structural, 1 class F).
- No stdlib module is `cap verified`; 21 conformance/native files are.

### 0.6 Facts the design rests on, each verified on `c918d14ca`

- **F1. The tail pass checks stack depth, never termination.**
  - A call in tail position is never examined (`if not in_tail`, `typecheck_tailcall.ml:380`). Hence t1-t3.
  - A non-tail call passes if **one** argument is "structurally smaller" (`List.exists`, `:384-386`).
- **F2. "Structurally smaller" on Int is purely syntactic.** `is_structurally_smaller` (`typecheck_tailcall.ml:261-274`) accepts:
  - `v - e` and `v / e` for **any** `e`;
  - every nullary constructor ("structurally minimal");
  - `List.nth`/`List.hd` of a smaller list.

  There is no lower bound. Hence t4/t6 loop, and t9b's `n - 0`, `n / 1` and `n - (0 - 1)` are each accepted as structural. This heuristic must never be read as a termination proof (§3.1).
- **F3. The tail pass runs on fewer bodies than it seems to.**
  - Only a `DFn` in a recursive SCC is checked, and only one with a single clause (`:723-735`).
  - A local `fn` is checked only when it sits inside such a function (`:551-556`). That is t10b.
  - Actor handlers are never visited: the declaration match has only `DFn`/`DMod` arms (`:723-776`). That is t12.
  - `@[no_warn_recursion]` skips the whole check (`:735`).
- **F4. The call graph has no edge for a lambda or for a function used as a value.** `collect_direct_fn_calls` returns empty for `ELam`/`ELetFn` (`:160-161`), and an `EVar` in argument position is a leaf (`:194`). So t11/t11b have no SCC, and t11c has no recursion at all.
- **F5. The `@[measure]` termination gate checks self-calls only.** `measure_gate_errors` (`refine_encode.ml:4252-4320`) iterates `EApp (EVar self, …)` and requires a single `EVar` argument in `structural_subvars` (`:4277-4296`). A call to another measure is not looked at (c4). The gate is emitted at `refine_check.ml:7891-7898`; the shape gate is at `:7774-7786`. Measures are the one place where non-termination is unsound *today* (the M-b comment, `refine_encode.ml:4070-4081`).
- **F6. `structural_subvars` is the shared structural certificate** (`refine_encode.ml:4141-4229`). It is trusted by name, with a fixpoint that drops a name bound non-structurally anywhere (the `copy(xs, ys)` false proof). Its consumers:
  - the measure gate;
  - Tier 2's IH: `ih_arg`, `refine_post.ml:1676`, computed at `:2065`;
  - the element-return IH: `hyp_applies`, `refine_check.ml:931-946`, with `elem_ret_hyp` at `refine_param.ml:215`;
  - O1's local IH: `local_elem_hyp`, `refine_check.ml:956-985`.

  It knows nothing about Int.
- **F7. Scalar returns get no IH at all.** `gate_unverified_posts` (`refine_post.ml:2469-2545`) clears every pending return (`{ sg with ret = None }`) and admits it only once proved, in monotone rounds. Its `check` (`:2516-2527`) installs `postcond_of ctx defs` as the lookup, so a self-call sees no contract (t6, r1-r3). The demand-chains note measured the perturbation: keeping `ret` during the gate turns the recursion, mutual and unproved-callee controls RED.
- **F8. A post tail reflects a call only as a bare tail or a `let` binding.** The two forms:
  - a bare tail: `scalar_call`, `refine_post.ml:842-870`;
  - a `let r = f(…)` in force: `let_call_const`, `:719-770`.

  Both read `!post_lookup`. A call nested in arithmetic, `n + sum_to(n - 1)`, stays unreflectable even when the IH is present (r2 under the IH build).
- **F9. The obligation ledger has three kinds:** `Precondition | Postcondition | Division` (`obligation.ml:181`).
  - `Division` is separate because "both `cap verified` escalation and `--refine-report` branch on kind" (`:170-180`).
  - `check_call` hard-codes `kind = Obligation.Precondition` (`refine_call.ml:831`) and words its messages by `check_subject` (`:585-615`).
  - Kinds are counted at `bin/main.ml:683, 710`.
- **F10. An attribute payload is one lower-case identifier.**
  - Grammar: `fn_attr` (`parser.mly:514-525`); stored as `fn_attrs : string list` (`ast.ml:251`).
  - `@[decreases(n)]` therefore parses (as `"decreases:n"`), while `@[decreases(m, n)]` is a syntax error (p18).
  - Unknown names are accepted in silence (p19).
  - `tree-sitter-march/grammar.js:111-114` already accepts `@[name(expr, …)]`. Measured with a freshly built grammar: `@[decreases(n)]`, `@[decreases(len(xs) - i)]`, `@[decreases(m, n)]` and `@[diverges]` all parse with no ERROR.
- **F11. March is call-by-value** (`specs/lang/core-march.md:376`), with strict `&&`/`||` (§4.4.1). There is no lazy binding whose refinement is assumed unevaluated, and no erased ghost code. So partial correctness alone already makes an IH-derived fact sound **for proofs**. EF §3.2 says so (`parametric-element-flow-design.md:245-248`). What partial correctness does *not* give is honest refutations (c1, c2) and consistent logic functions (F5). §1 is built on this.
- **F12. The witness interpreter is fuel-limited.** `per_call_fuel = 100_000` and a 1,000,000 module wall budget (`witness.ml:46-51`). A diverging function costs budget; it cannot hang the checker.
- **F13. A per-call-site verdict index exists.** `Obligation.by_span` (`obligation.ml:220`) is keyed on the call expression's span and populated in `record` (`:262`). Phase 3 reads a call's precondition verdict from it.
- **F14. The LSP re-implements the tail hint** (`lsp/lib/analysis.ml:1391-1400`, `tco_check_fn`). Termination diagnostics must come through the compiler's `Err` ctx, not a third copy.

---

## 1. Options compared

| | O1: partial-correctness IH, no termination | O1': O1, but IH facts used only to *prove* | **O2: termination certificate gates the IH** | O3: termination required everywhere (LH default) |
|---|---|---|---|---|
| sum_to (r1-r3) | proved | proved | proved (phase 3) | proved |
| loopy / down (c1, c2) | **false violations** with fabricated witnesses ("loopy() can return -1") | no false violation, but the ledger says **"proved"** for `loopy : {Int \| _ < 0}` and for `{Int \| false}` (c3) | skip, as today | rejected |
| measures (F5, c4) | not helped | not helped | the gate becomes the SCC check | same |
| `cap verified` | "verified" admits a function that never returns | same | total for every proof that used the IH | total |
| Cost | a three-line lookup wrapper in `gate_unverified_posts` (the IH build) | two assumption sets in `check_call`, one for proving and one for refuting, so the solver runs twice wherever IH facts are present; every post carries a "partial" bit through `defs`, `elem_ret_proved` and the lookup | a termination pass (phases 0-2), then the same one-line hook | O2, plus 212 stdlib / 102 native units to fix or annotate before anything builds |
| Breakage | none, but false errors appear | none | none: unproved means today's skip | 28% of stdlib recursion |

**Recommendation: O2.**
- O1 reports bugs in code that cannot reach them (c1, c2).
- O1' fixes that, but leaves a ledger that calls `{Int | false}` proved. `--refine-report` and `cap verified` exist to stop that kind of lie (the `obligation.ml` header).
- Both leave the measure gate and any future reflection unsolved. O2 needs termination there regardless.
- O3 is O2 with the severity of §8 phase 4 switched on everywhere. §0.5 says the stdlib is not ready, so O3 is a later severity flip (D2), not a design.

---

## 2. Surface syntax

### 2.1 `@[decreases(e1, …, en)]` (phase 2)

```march
@[decreases(m, n)]
fn ack(m : {Int | _ >= 0}, n : {Int | _ >= 0}) : Int do … end

@[decreases(len(xs) - i)]
fn scan(xs : List(Int), i : Int) : Int do … end
```

- Each `ei` is an Int expression over the function's **parameters**, Int literals, `+ - *`, `/` by a positive literal, `@[measure]`s and the built-in `len` (the refinement fragment, so `smt_of` translates it).
- n ≥ 2 is a lexicographic tuple, compared left to right (§3.3).
- A structural component is written as a measure (`size(t)`). A bare ADT parameter is not a metric. That is an `invalid_decreases` error, whose fix text suggests a measure.
- **Parser:** the `fn_attr` payload rule (`parser.mly:516-518`) becomes `LOWER_IDENT LPAREN separated_nonempty_list(COMMA, expr) RPAREN`. The action keeps today's `"name:value"` string when the list is a single `EVar` (so `@[no_alloc(warn)]` and friends are unchanged). Otherwise it stores the expressions in a new `fn_def` field, `fn_attr_args : (string * expr list) list`. Only `decreases` may take a non-identifier payload; any other name with one is a parse error naming the attribute. The `TRANSIENT` special case (`:519-525`) stays. The menhir conflict count is asserted unchanged.
- **Tree-sitter:** no `grammar.js` change (F10). No new keyword: `decreases` is a `LOWER_IDENT`. `scripts/check-tree-sitter.sh` must be green with no `known-failures.txt` entry.

### 2.2 `@[diverges]` (phase 4)

```march
@[diverges]
fn accept_loop(node : Cap(ClusterNode.Live), …) : Unit do … accept_loop(node, …) end
```

It means "not claimed to terminate":
- no termination obligation is filed;
- no IH is given (exactly today's behaviour);
- the report lists the function under `diverges`, not `unproved`.

Errors, code `diverges_conflict`:
- `@[diverges]` together with `@[decreases]`, or with `@[measure]`;
- a `@[measure]` that calls a `@[diverges]` function.

Callers are **not** required to carry the attribute (D4). "May diverge" is inferred upward through the call graph for the report and for `cap total`.

### 2.3 No new syntax for actors, `main` or callbacks

These follow rules in §3.6-§3.7. Nothing is written.

---

## 3. The checking algorithm (`lib/refinecheck/refine_term.ml`, new)

### 3.1 Separation from the tail pass (question 8)

- Stack safety stays in `typecheck_tailcall.ml`, unchanged in meaning.
- Termination is a new pass in `lib/refinecheck`, because its obligations are SMT queries through `check_call` (§3.4).
- They share **only** the call graph. `collect_direct_fn_calls`, `find_sccs`, the shadowing scope and the two-prefix qualification (`typecheck_tailcall.ml:604-652`) move to `lib/typecheck/callgraph.ml` and are used by both. The termination pass adds the edges of §3.6 on its own copy.
- `is_structurally_smaller` and the tail pass's `smaller` set are **never** consulted by the termination pass (F2). A test pins it: t9b's `grow(n - (0 - 1))` must stay unproved while the stack warning still calls it "structurally recursive".

### 3.2 Units and SCCs

- A **unit** is a top-level function (every clause, after desugaring, which already merges clauses into one), a local `fn`, or an actor handler.
- The graph has one node per top-level function and per local `fn`. The node set is scoped exactly as the tail pass scopes it: a local shadows a global, and an arm binder retires a name.
- Edges:
  1. a direct call `f(args)`, with its argument list and its path conditions;
  2. a call inside a lambda or a `let*` continuation in `f`'s body. This is a **lambda edge**: the arguments are the call's own, the path is the lambda's own, and the lambda's parameters are unknown values;
  3. a function name used as a value. This is a **reference edge**, with no arguments.
- SCCs are found by Tarjan, as today.
- Every non-recursive unit is trivially terminating *modulo its callees* (§3.6).

### 3.3 Metrics

Each function `f` in an SCC gets a metric `M_f`, a tuple of Int expressions over its parameters (possibly a 1-tuple), or the **structural** metric `S(i)`: "the i-th argument is a pattern sub-component of the i-th parameter".

| Source | Phase | Rule |
|---|---|---|
| structural | 1 | For a self-recursive unit: some position `i` where every intra-SCC call's argument `i` is in `structural_subvars` of parameter `i`. Same-function only. No arithmetic, no nullary constructors, no `List.nth`. For a mutual SCC: every member matches on a parameter of the **same ADT** and every edge passes a component of it. |
| `@[decreases(e…)]` | 2 | as written |
| default | 2 | the first Int parameter, as a 1-tuple (LH's default) |
| inferred | 5 | a search (§3.5) |

**Obligation per intra-SCC edge** `f → g` at a call `g(a1..an)` under path `P`, with `f`'s scope facts (parameter refinements, `let` facts: the `call_ctx` channels):

```
P ∧ facts  ⊨  M_g[params_g := args]  <lex  M_f
```

where `x <lex y` is defined as

```
(x1, …, xk) <lex (y1, …, yk)  :=  (0 <= x1 && x1 < y1)  ||  (x1 == y1 && (x2, …) <lex (y2, …))
```

All metrics of one SCC have the same length; a mismatch is `invalid_decreases` (my call; Dafny pads instead, §10). A structural metric is discharged syntactically, with no query. A mixed structural and Int tuple is phase 5.

- **Mutual recursion (question 3): one metric per function, compared across each edge.** For ev/od, the default `M = (n)` serves both members. A recursive-descent parser writes `@[decreases(len(s) - i, 1)]` on `parse_value` and `@[decreases(len(s) - i, 0)]` on `parse_array`:
  - `parse_value → parse_array` at the same `i` falls on the second component;
  - `parse_array → parse_value` after consuming `[` falls on the first.

  One shared metric is the special case where all members use the same tuple. Per-edge metrics (a metric for each edge rather than each function) are not sound without a cycle argument; rejected.
- **Precondition at the call:** the metric query assumes only what reaches the call. A recursive call whose own precondition fails is not "decreasing" by fiat. Its precondition obligation is the usual one, and §4.2 rule (a) makes the IH need both.

### 3.4 Discharge: through `check_call`, a new kind, a new subject (question 2)

- The obligation is phrased as a call to a synthetic one-parameter signature `$decreases_f`:
  - its parameter is refined by `{Int | 0 <= _ && _ < M_f}` (1-tuple), or by the lex formula over `$d0 … $dk` (k-tuple, the relational-signature trick of the abstract-refinements design §2.5);
  - its actual is `M_g[params_g := args]`.

  `check_call` then supplies everything for free: path facts, scope facts, `let` laundering, the VC cache, counterexample models and the `cap verified` escalation.
- **New `Obligation.kind` `Termination`**, not a `Precondition` with a callee label. That is the `Division` argument verbatim (F9): `cap verified` and the report branch on kind, and folding termination into Precondition would change both for every module with recursion.
- **New `check_subject` `Decreases`**, for wording: "the recursive call `down(n - 1)` is not shown to decrease `n`: e.g. `n = -1`".
- `check_call` takes `?kind` (default `Precondition`), and `note` records it instead of the hard-coded constructor (`refine_call.ml:831`).
- A refuted termination obligation is the warning `termination_unproved` with the model as witness, **never** `refinement_violated`. Recursion that is not shown to decrease is not a runtime contract failure.

### 3.5 Defaults and inference (phases 2, 5)

Phase 2 tries, in order, until every edge of the SCC proves:
1. structural;
2. `@[decreases]` if written (then only that);
3. the first Int parameter.

Phase 5 adds candidates, at most 8 per SCC, each fully checked, never trusted:

| Candidate | Catches (§0.5) |
|---|---|
| each Int parameter, in order | B |
| `b - i` for an Int parameter `i` passed as `i + k` and a guard `i < b` / `i >= b` on the exit path, `b` built from parameters passed unchanged around the SCC | B (`up`), H |
| `len(x)` for a `List` parameter, through helper posts (`split_at`, `pop_front`) | G |
| 2-tuples of the above in parameter order | D |

### 3.6 Calls through function values (question 4)

A unit is **terminating modulo its function-valued inputs**: it terminates whenever every function value it calls terminates. Ordinary calls compose this for free. The invariant that makes "every function value terminates" true is that every *named* function a value can denote is itself checked. Three ways it breaks, and each one's rule:

| Break | Rule |
|---|---|
| a function passes **itself** (t11) | reference edge: the SCC has an edge with no arguments, so no metric can be checked, so it is unproved |
| a lambda recurses into its enclosing function (t11b, a rose tree's `List.map(children, fn c -> size(c))`) | lambda edge. Its arguments are checked like any other, so `size(c)` with `c` a lambda parameter is unproved. Element-of-a-component reasoning (EF element facts) is filed, not built |
| a **non-positive datatype** (t11c: `Fix(Fix -> Int)`) | a strict positivity check on every `type` declaration (beside `check_nonregular_types`, `typecheck.ml:9275`): a constructor field whose type mentions the type being declared to the **left** of an arrow is *non-positive*. A unit that calls a function value whose static type mentions a non-positive type is unproved. This is the only rule that catches t11c; LH's equivalent is marked "unsure" in §10 |

- An `extern` or builtin call is assumed to terminate (trusted, listed in the report's `trusted` count).
- `panic`/`todo` terminate: they abort, which is not divergence, and the measure gate polices them separately.

### 3.7 Intentional divergence, actors, `main` (question 5)

| Unit | Rule |
|---|---|
| `@[diverges]` function | no obligation, no IH; listed as `diverges` |
| caller of a `@[diverges]` function | inferred "may diverge"; nothing written; no IH for an SCC whose proof crosses into one |
| actor handler | terminates **per message**: the body is a non-recursive unit, so its status is that of its callees. The report says "handler `Spin` may not return" (t12). A `send(self(), …)` is not an edge (the mailbox is not a call). Never an error, except under `cap total` |
| `main` | exempt: implicitly allowed to diverge |
| `Seq` streams, session `loop` protocols | a `Seq` producer is a closure (§3.6). A protocol `loop` is a type, not code |

---

## 4. Feeding the refinement checker (the payoff)

### 4.1 Scope: which functions must terminate (question 1)

| Context | Termination is | Why | Cost if wrong |
|---|---|---|---|
| `@[measure]` (and any future reflection or erased lemma) | **required**: `invalid_measure` | evaluated in the logic, not at runtime; a diverging definition is an inconsistent axiom (F5, m1) | unsound everywhere |
| a function whose post / element return / local return proof needs the IH | **computed, gates the IH** | a proved post is assumed when *refuting* at call sites (c1, c2) | false violations; "proved" on vacuous contracts |
| `cap verified` module | every termination obligation a proof *relied on* escalates | the cap asks for every obligation discharged | a "verified" function that hangs |
| `cap total` (opt-in, phase 4, D2) | required for every unit | asked for | — |
| everything else | report only | §0.5: 28% of stdlib recursion fails even a good check | warning noise that teaches users to ignore it |

### 4.2 The hook

Phase 3 changes four IH sites and the gate's rounds. Each IH site widens "argument is a structural subvariable" to "**or** the call is an intra-SCC call of a certified SCC, and rule (a) holds".

| Site | Today | After |
|---|---|---|
| `gate_unverified_posts` `check`, `refine_post.ml:2516-2527` | lookup = `postcond_of ctx defs`, own `ret` cleared | lookup = `fun f args -> if certified_member scc f then ret_instance (sig_of f) args else postcond_of ctx defs f args`. This is the one line the IH build measured (r1, r3) |
| `rounds`, `:2528-2545` | admits one function per proof | admits a certified SCC **atomically**: every member is checked under all members' IH, and all are admitted iff all prove. A member that fails sinks the SCC this round; it is retried when a callee is proved |
| Tier 2 `ih_arg`, `:1676-1690` | IH iff the matched-position argument ∈ `sset` | also iff certified intra-SCC call |
| `hyp_applies`, `refine_check.ml:931-946` | some argument ∈ `structural_subvars`, definers unchanged | the definer condition is unchanged; the structural condition widens as above |
| `local_elem_hyp`, `refine_check.ml:956-985` | the physical signature plus a structural argument | widens the same way, for a certified local SCC |

**Rule (a): the IH at a call needs that call's termination obligation and precondition obligations proved.**
- The certificate of §3.4 proved the call's termination under its path.
- The call's preconditions are checked by the termination pass in `Obligation.with_scratch` and recorded per call span (F13).
- An IH from a call whose precondition failed would assume a post the function never promised for that input.

**Rule (b), nested calls (F8):** `scalar` in `check_post` gains a call resolver. A sub-term `f(args)` with `!post_lookup f args = Some _` becomes a fresh `f$retN` carrying the contract, as `scalar_call` does for a bare tail. Without it, r2/r4 stay skips even with the IH.

The **demand-chains controls stay RED-correct**:
- `f(x) = f(x)` is not certified (t1), so it gets no IH;
- an unproved callee is still absent from `defs`;
- a mutual cycle gets the IH only if the cycle is certified.

Any existing fixture whose cycle *is* certifiable changes deliberately; the phase 3 progress note lists each one.

### 4.3 `sum_to`, worked

```march
fn sum_to(n : {Int | _ >= 0}) : {Int | _ >= 0} do
  if n == 0 do 0 else n + sum_to(n - 1) end
end
```

| Step | Query (path `n != 0`, scope `n >= 0`) | Verdict |
|---|---|---|
| precondition of `sum_to(n - 1)` | `n - 1 >= 0` | proved (today too) |
| termination, default metric `(n)` | `0 <= n - 1 && n - 1 < n` | proved |
| IH (rules a, b) | `sum_to$ret1 >= 0` | assumed |
| post | `n + sum_to$ret1 >= 0` | proved |
| caller `need_nn(sum_to(k))` | `sum_to$ret >= 0 ⊨ _ >= 0` | proved |

Measured: the let-form equivalents (r1, r3) prove 5/5 under the IH build. The termination row is phase 2's addition, and the nested form is rule (b).

### 4.4 What stays unsound if the termination proof is wrong

A certificate admitted for a diverging SCC re-creates c1/c2:
- a vacuous post is "proved";
- callers get false violations with fabricated witnesses;
- in a measure, an inconsistent axiom proves anything.

So the certificate rules are deliberately narrow. Each is a soundness row in §5 with a REJECT control in §8:
- no syntactic Int heuristic (F2);
- no nullary constructor counted as smaller;
- `structural_subvars`' fixpoint is kept;
- reference and lambda edges;
- strict positivity;
- atomic SCC admission;
- rule (a).

---

## 5. Soundness

| New assumption | Justified by | Guarded by |
|---|---|---|
| a structural SCC terminates | well-founded sub-term order | `structural_subvars` (by-name fixpoint, F6); same ADT across mutual members; nullary constructors excluded; a control test (`copy(xs, ys)`, `f(Nil) = f(Nil)`) |
| a metric SCC terminates | lexicographic `<` on tuples of naturals is well-founded | each component `0 <=` on the descending position (§3.3); the path and scope facts are `check_call`'s own channels (shadow discipline); a refuted query is never a proof |
| per-function metrics across a mutual SCC | every cycle crosses edges, each strictly decreasing in one order | every intra-SCC edge obliged; one tuple length per SCC |
| function values terminate | every named function checked; lambda/reference edges | strict positivity (§3.6); a non-positive type blocks |
| externs and builtins terminate | trust | counted `trusted`; listed in the report |
| the IH at an intra-SCC call | induction on the certified metric | rule (a): that call's termination **and** precondition proved; atomic SCC admission; `@[diverges]` never certified |
| a nested call term carries its callee's post | the same as a bare tail (`scalar_call`) | only `!post_lookup` answers (proved or IH-certified contracts) |
| a handler terminates per message | its callees do | report only; never assumed by the refinement checker |

**Deliberately not claimed.**
- Termination modulo function-valued inputs means a call passing a `@[diverges]` function as a callback may diverge while the callee's post is still used at that site. That call hangs at runtime, so a refutation there still names a real defect, at the wrong place.
- Stack depth. A terminating `sum_to(10_000_000)` can still overflow the stack. That stays the tail pass's job.
- Liveness of actors, schedulers or the network.

---

## 6. Interaction with existing features

| Feature | Interaction |
|---|---|
| `typecheck_tailcall.ml` | unchanged; shares `callgraph.ml` (§3.1). Its F3 gaps (t10b local `fn`s, actor handlers) are a stack-safety todo filed in phase 0, not fixed here |
| `@[no_warn_recursion]` | silences the stack check only; no effect on termination |
| `@[measure]` gate (F5) | `measure_gate_errors`' self-call rule is replaced by "the measure's SCC is certified structural" (phase 1); message text unchanged; c4 becomes an error |
| Tier 2, EF §3.2, O1 hypotheses | widened per §4.2; their structural rule remains the phase 1 certificate |
| `@[assume]` / `@[trusted]` | an assumed function's termination is trusted, like its post; a termination skip under `@[trusted]` becomes `Trusted`, as a precondition skip does |
| `cap verified` | escalates every `Termination` skip whose IH a recorded proof used, plus every annotated `@[decreases]` that fails; unannotated, unused recursion does not escalate (D2) |
| `--refine-report` | a fourth kind in `by kind:` (`bin/main.ml:683, 710`); a `termination` block (proved structural / proved metric / unproved / diverges / trusted) from phase 2 |
| witness interpreter (F12) | unchanged; phase 4 may skip witness runs for units the certificate marks `may diverge`, which saves wall budget |
| VC cache / determinism oracle | synthetic names (`$decreases_f`, `$d0…`) are fixed strings; no counter |
| `--refine-infer` (question 9) | phase 5 proposes `@[decreases(…)]` for an SCC whose IH would have closed a skipped post; `--refine-infer-apply` inserts it like `forge fix --contracts` inserts `@[no_alloc]` (the `DOC; attrs; fn_decl` rule, `parser.mly:572-590`) |
| LSP | diagnostics via `Err` (F14). Code actions in `code_actions_diag.ml`: "add `@[decreases(<inferred>)]`", "add `@[diverges]`", and, when the witness is negative and the exit guard is `x == 0`, "change `x == 0` to `x <= 0`" |
| error corpus | new slugs `termination_unproved` (warning; error under `cap verified`/`cap total`), `invalid_decreases`, `diverges_conflict`. Seeded by `scripts/seed-error-corpus.sh` (`test/errors/<slug>_1.march`, `--explain` pages in `specs/lang/errors/`) |
| tree-sitter | no grammar change; no keyword (§2.1) |
| language reference | `specs/lang/refinement-types.md`: a new "Termination" section; "The measure soundness gate" (`:1640`) names the SCC rule; the Tier 2 "non-structural recursion" bullet (`:5337-5343`) points at it; then `scripts/gen-lang-docs.py` |

---

## 7. Standard library impact

| Group (§0.5 class) | stdlib | What it takes |
|---|---|---|
| A structural | 465 | nothing (phase 1) |
| B bounded Int | 85 | nothing (phase 2 default) |
| C unbounded Int | 54 | per function: a `{Int \| _ >= 0}` precondition, a `<= 0` exit guard, or a builtin contract (`string_byte_at` past the end, for scanners); not swept, since no proof needs them |
| D lexicographic parsers | 24 | `@[decreases(len - i, rank)]` only if a contract ever needs it; not swept |
| E external-event loops | 41 | `@[diverges]`, swept in phase 4 (`cluster_node`, `session_node`, `net_kernel`, `topology`, `node_call`, `http_transport`, `file`, `csv`, `seq`, …) |
| F closures | 25 | out of scope (§3.6) |
| G helper metrics | 29 | helper `len` posts (`split_at`, `pop_front`); filed |
| H non-syntactic Int | 33 | phase 5 inference, or annotation on demand |
| I no metric | 6 | `@[diverges]` (`Random.next_float_open`, `Seq`), or a fix (s4) |
| s1-s4 divergences | 4 | D5 |

The 11 refined recursive stdlib functions are 10 structural and 1 closure-recursive. So phase 3 changes no stdlib verdict until a contract is added. The phase 3 oracle diff on the stdlib should be empty, and any line in it must be explained.

---

## 8. Phases, one PR each

Conventions, as in the template:
- `test_refinecheck.exe` green at every step;
- every new rule lands with a fixture that goes RED without it;
- ledger triples asserted, never exit codes;
- `--root .`, z3 on PATH, CI's z3 4.8.12 noted;
- `scripts/refine-oracle.sh` and `scripts/ir-oracle.sh` under a private `HOME`, every diff line explained.

Each phase adds a `specs/progress/2026-MM-DD-termination-phaseN.md` and a `CHANGELOG.md` `[Unreleased]` bullet:
- phase 0 `### Added` (report flag);
- phases 1, 4 `### Changed`;
- phases 2, 3, 5 `### Added`.

Each phase also updates `specs/lang/refinement-types.md` and runs `scripts/gen-lang-docs.py`.

### Phase 0: measurement, inert

- `refine_term.ml` with the §3.2 graph (direct, lambda and reference edges) and the COUNT classifier (§0.5's classes A-I, the hand-classified ones by heuristic plus `?`).
- A flag `--termination-report` prints one row per unit. Nothing else reads the result.
- Files the todos: the tail-pass gaps (F3: t10b, handlers) and s1-s4.

**RED tests** (group `termination-report`):

| Test | Asserts | Red without |
|---|---|---|
| t1, t2, t3, t4, t5, t7, t8, t9, t9b, t11, t11b | each row's class (`none`, `int-asc`, `int-dec` mutual, …) | the classifier |
| t9b | `grow` is `none`, though the stack pass calls it structural | §3.1 separation |
| shadowing | prelude `length`'s local `go` forges no edge to a user `go` (`typecheck_tailcall.ml:100-106`) | scoped names |
| nested `mod` | a recursive `fn` one `mod` deeper is found (`:611-652`) | two prefixes |
| inert | `refine-oracle`, `ir-oracle` IDENTICAL; `--refine-report` output byte-identical | — |

### Phase 1: structural termination over SCCs

The certificate of §3.3 (structural only), in the report. `measure_gate_errors` uses it.

**RED tests** (group `termination-structural`):

| Test | Asserts | Red without |
|---|---|---|
| t7 | `len2` certified structural | — |
| `nil_not_smaller` | `f(Nil) = f(Nil)` (accepted by the tail pass via F2) **not** certified | nullary rule |
| `copy_shadow` | `copy(xs, ys)` with an inner `Cons(_, t)` of `ys` not certified | `structural_subvars` fixpoint |
| `mutual_nat` | `even(S(m)) -> odd(m)`, `odd(S(m)) -> even(m)` certified | SCC structural |
| `mutual_two_adts` | members matching different ADTs: not certified | same-ADT rule |
| c4 | mutual measure cycle → `invalid_measure` | SCC measure gate |
| c5 | m1/m3 unchanged | — |
| t11 / t11b | reference / lambda edge: not certified | edges |
| oracle | refine-oracle changes only on fixtures with mutual measures (expected: none) | — |

### Phase 2: metrics, `@[decreases]`, SMT obligations, positivity

The rest of §2.1, §3.3-§3.6:
- the parser change;
- `Obligation.Termination`, `check_subject Decreases`, `check_call ?kind`;
- the default metric;
- strict positivity;
- `invalid_decreases`;
- `termination_unproved` for an **annotated** unit only.

**RED tests** (group `termination-metric`):

| Test | Asserts | Red without |
|---|---|---|
| t5 `fib` | certified, metric `n`; 2 `Termination` obligations proved | default metric |
| t4 `down` | unproved; ledger `skip … termination … down`; model `n = -1` | `0 <=` component |
| `down_le` | `if n <= 0` exit: certified | — |
| t3 ev/od | refined `{Int \| _ >= 0}` both: certified as one SCC; unrefined: unproved | per-edge obligations |
| t8 `ack` | `@[decreases(m, n)]` with `<= 0` exits certified; with `== 0` exits unproved | lex formula |
| t9 / t9b | `bits` certified; `bits1`, `same`, `grow` refuted (`n = 1`) | no heuristic |
| t2 `up` | `@[decreases(100 - n)]` with guard `n >= 100` certified; with `== 100` unproved | — |
| parser | p18 parses; `@[no_alloc(warn)]` unchanged; `@[foo(1 + 2)]` parse error naming `foo`; conflicts unchanged | §2.1 action |
| `invalid_decreases` | metric naming a local, a `Float`, a bare ADT parameter: one error each | checks |
| t11c omega | `w` unproved (non-positive `Fix`); a positive `type T = T(Int -> Int)` does not block | positivity |
| `cap_verified_annotated` | annotated + unproved under `cap verified`: error; unannotated: no error | escalation scope |
| `kind_counted` | `by kind:` prints `N termination` | `bin/main.ml` |
| `cache` | `@[decreases(n)]` vs `@[decreases(n + 1)]`: independent verdicts | — |

**Grammar corpus:** `specs/lang/grammar/parse/pNN_decreases_attribute.march`; INDEX counts.
`scripts/check-tree-sitter.sh` green, with no entries.

### Phase 3: the induction hypothesis (the payoff)

§4.2's four IH sites, rule (a), rule (b), atomic SCC admission.

**RED tests** (group `termination-ih`):

| Test | Asserts | Red without |
|---|---|---|
| r2 / §4.3 | nested `sum_to` return proved; caller proved | IH + rule (b) |
| r1 / r3 | let form; `_ >= n` + `need_ge(sum_to(10))` proved | IH |
| r4 | `len2 : {Int \| _ >= 0}` and caller proved | rule (b) |
| c1 / c2 / c3 | unchanged skips: **no** violation, **no** proved post | the gate (perturb: drop the certificate check, and these go RED) |
| `pre_fails` | `f(n : {Int \| _ >= 0}) : {Int \| _ >= 0}` calling `f(n - 2)` under `n != 0`: the call's precondition is violated at `n = 1`, so no IH and the return skips | rule (a) |
| `scc_atomic` | ev/od posts, one false: neither admitted; both true: both admitted | atomic rounds |
| `elem_widened` | `replicate(x : {Int \| _ > 0}, n : {Int \| _ >= 0}) : List({Int \| _ > 0})`, `Cons(x, replicate(x, n - 1))`, proved (no structural argument); a structural one still proves | `hyp_applies` widening |
| `local_widened` | O1's `go(t, i + 1)` with a bounded `i` proved; O1 control 3 (`go(lst, i + 1)`, `lst` unchanged, unbounded) still skips | `local_elem_hyp` |
| `diverges_in_scc` | an SCC calling a phase 4-style `@[diverges]` member is not certified | inference upward |
| demand-chains | group passes; any changed control is listed | — |

**Oracle:** stdlib empty (§7); corpus changes only on newly provable recursive posts, each listed.

### Phase 4: `@[diverges]`, actors, the stdlib sweep, severity

- §2.2.
- §3.7's handler rows.
- `cap total` (if D2 is accepted).
- LSP code actions.
- The class-E sweep: 41 stdlib + 8 native `@[diverges]`.
- D5's fixes, as separate PRs.

**RED tests** (group `termination-diverges`):

| Test | Asserts | Red without |
|---|---|---|
| t1 `@[diverges]` | listed `diverges`, no obligation | attribute |
| `conflict` | `@[diverges]` + `@[measure]` / + `@[decreases]`; a measure calling one: `diverges_conflict` | checks |
| t12 handlers | `Spin` "may not return"; `Go` calling a certified `countdown` (`<= 0` exit) clean; `Again` clean | per-message rule |
| `cap_total` | an unproved unit is an error; `main` exempt | cap |
| `ratchet` | `--termination-report` over `stdlib/`: zero class-E units without `@[diverges]` | sweep |
| LSP | the three code actions round-trip (apply, re-check: the diagnostic is gone) | — |

### Phase 5: inference

The §3.5 candidate search; `--refine-infer` proposals; the LSP "add `@[decreases(…)]`" action filled in.

**RED tests** (group `termination-infer`):

| Test | Asserts | Red without |
|---|---|---|
| t2 guarded | `100 - n` inferred | guard candidate |
| `scanner` | `json.skip_ws(s, i + 1)` inferred `string_byte_length(s) - i` iff a builtin contract exists; otherwise unproved (named) | — |
| `chunks` | `List.chunks`' `go` (class G) with `split_at`'s `len` post: `len(lst)` inferred | `len` candidate |
| `proposal_checked` | every proposal's obligations proved before it is offered | — |
| `cap` | > 8 candidates: stops at 8, unproved (named) | budget |

---

## 9. Performance

- **Phases 0-1:** syntactic, linear in call sites. The stdlib has 1,052 recursive call sites (COUNT).
- **Phase 2:** one query per non-structural intra-SCC call site, but **demand-driven**: only for an SCC that
  - holds a `@[measure]`,
  - has a pending refined return in the gate,
  - carries `@[decreases]`, or
  - is under `--termination-report`, `cap verified` or `cap total`.

  The upper bound if everything were checked is the B+C+D+H call sites, ≈ 340 small QF-LIA queries. Phase 5 multiplies by at most 8.

Budget, cold, private `HOME`, against the pre-change compiler (baseline measured here: `--check --refine-report stdlib/list.march` 1.88-1.93 s, `stdlib/json.march` 1.84-1.89 s, 3 runs each, load 2-4):

| Mode | Budget |
|---|---|
| default `--check` (phases 0-3) | **≤ 105%** |
| `--termination-report` / `cap total` (phases 2, 5) | ≤ 150% |

Protocol as `specs/2026-10-18-abstract-refinements-multi-arg-design.md` §10: interleaved A/B, five runs, median, load average recorded, `.march/cas/vc` cleared once. Warm runs hit the VC cache, since names are fixed.

---

## 10. Prior art (question 10; from memory, no browsing)

- **Liquid Haskell** checks termination by default. Its defaults:
  - the default metric is the first argument with a size (the `len`-style measure of an ADT, or an Int's value with a non-negativity obligation);
  - `/ [e1, e2]` on a signature gives a lexicographic metric;
  - `{-@ lazy f @-}` switches the check off for `f`;
  - `--no-termination` switches it off globally.

  Termination is required for `reflect`ed functions and for measures, because Haskell is lazy: an unevaluated diverging binder's refinement would otherwise be assumed. I believe mutual recursion needs metrics comparable across the SCC. I am **unsure** whether LH enforces strict positivity of data types today.
- **Dafny**:
  - `decreases` clauses, defaulting to the lexicographic tuple of parameters;
  - well-founded orders per type: naturals, datatype rank, sequence length, set subset;
  - comparison across a mutually recursive call, padding a shorter tuple ("I believe": I recall a top element, and am unsure of the details);
  - `decreases *` lets a *method* (never a function) diverge, and its callers must say so too.
- **F\***:
  - `decreases` with the `<<` precedes relation;
  - divergence as an effect (`Dv`/`ML` versus `Tot`);
  - only `Tot` code may appear in specifications.
- **What March copies:**
  - Dafny's and F\*'s `decreases` name and lexicographic tuples;
  - LH's structural and first-Int defaults;
  - the rule that only terminating code reaches the logic: measures now, reflection later.
- **What it changes:**
  - March is call-by-value (F11), so partial correctness already protects *proofs*; termination is needed for refutations, logic functions and `cap verified`'s meaning. That is why it can be report-level and demand-driven rather than LH's default-on error.
  - `@[diverges]` does not propagate as a required annotation (unlike Dafny's `decreases *`, D4).
  - Metrics live in an attribute, not in the type (D3).

---

## 11. Decisions

Settled here (my calls, each revisitable without reopening the design):

1. **O2**, a termination certificate gating the IH, over the partial-correctness IH (O1, O1') and over default-on enforcement (O3) (§1).
2. **Separate passes.** The tail pass keeps stack safety; termination lives in `lib/refinecheck/refine_term.ml`; they share only `callgraph.ml`. `is_structurally_smaller` is never termination evidence (§3.1).
3. **No syntactic Int certificate.** Every Int decrease is an SMT obligation with a `0 <=` component. Nullary constructors are not smaller (§3.3).
4. **One metric per function, compared across each edge** of the SCC. Per-edge metrics are rejected (§3.3).
5. **A new obligation kind `Termination` and a new subject `Decreases`**, through `check_call ?kind`. Not a callee label (§3.4, F9).
6. **A refuted termination obligation is `termination_unproved`**, never `refinement_violated` (§3.4).
7. **IH rule (a):** termination *and* precondition proved at that call (§4.2).
8. **Certified SCCs are admitted atomically** in the gate (§4.2).
9. **Function values:** termination modulo function-valued inputs, with reference edges, lambda edges and strict positivity (§3.6).
10. **Externs and builtins are trusted to terminate** and counted; `@[assume]` extends to termination.
11. **Actor handlers:** per-message, report only. `send(self(), …)` is not recursion. `main` is exempt (§3.7).
12. **Termination is demand-driven** in default mode (§9).
13. **The F3 stack gaps and s1-s4 are filed, not fixed,** by this design (phase 0).

Open for the user, each with a recommendation, in the order they block:

- **D1. O2 over O1' (§1).** O1' gets `sum_to` without any termination machinery, at the cost of "proved" ledger entries on vacuous contracts (c3) and two solver runs wherever IH facts appear. **Recommended: O2.** The ledger's honesty is the point of `--refine-report`, and measures need termination anyway. If speed matters more, O1' could ship first as phase 3a and be gated later; that re-litigates every "proved" it issued.
- **D2. Severity and rollout (question 7).**
  - **Recommended:**
    - never a default-on warning in phases 0-4;
    - `termination_unproved` fires only for an annotated `@[decreases]`, or where a skipped post would have proved with the IH (actionable);
    - `cap verified` escalates only the obligations a proof relied on;
    - a new opt-in module cap `cap total` requires every unit (phase 4).
  - Revisit a default-on warning once the phase 4 ratchet shows zero unannotated class-E units and class C has a story. Today a default-on warning would fire on **212 stdlib and 102 native units** (§0.5).
  - Alternatives: a `cap verified` that requires every unit (the 21 existing `cap verified` fixtures would need re-auditing for recursion); default-on now.
- **D3. Metric syntax: an attribute with an expression payload (§2.1, a parser change) versus a signature form (`… : Int / [m, n]`, LH-style, a type-grammar change).** **Recommended: the attribute.** Tree-sitter already parses it (F10), `forge fix` already inserts attributes, and the type grammar stays untouched.
- **D4. `@[diverges]`: the name, and whether callers must repeat it (Dafny's `decreases *`).** **Recommended:** `@[diverges]`, with "may diverge" inferred upward and nothing required of callers. Requiring it would touch every caller of the 41 class-E functions, for no proof gained. `@[lazy]` (LH) is misleading in a strict language; `@[may_diverge]` is more exact but longer.
- **D5. The four stdlib divergences (s1-s4).** **Recommended:** one PR each, adding a precondition plus the runtime guard the sibling already has:
  - `List.range_step`'s `step : {Int | _ != 0}` with a panic, as `Range.new_step` has;
  - `Range.to_list`: panic on `step == 0`;
  - `Control.chunks`' `size : {Int | _ > 0}`;
  - `Duration.format`: handle `ms < 0` without negating `min_int`.

  Each is a behaviour change (a hang becomes a panic or a refinement error). That is why this is yours, and why it is not part of the termination PRs.
- **D6. Unknown attributes are accepted silently (t14).** `@[decrease(n)]` would be ignored, and the checker would look as if it had found no metric. **Recommended:** in phase 2, warn on any `fn` attribute name not in the compiler's list (a new `unknown_attribute` warning with a did-you-mean). The alternative is to warn only on near-misses of `decreases`/`diverges`.

---

## Decisions settled by the user (2026-10-27)

D1-D6 accepted as recommended:
- **D1.** The induction hypothesis is gated on a termination certificate. It is never used as an unchecked partial-correctness assumption.
- **D2.** Warnings are off by default. Warn only on `@[decreases]` or where the hypothesis would have closed a proof. `cap verified` escalates the termination obligations a proof relied on. `cap total` is opt-in.
- **D3.** The metric is an attribute with an expression: `@[decreases(e, ...)]`.
- **D4.** `@[diverges]`, inferred upward through callers, with no burden on them.
- **D5.** The four stdlib hangs (s1-s4) get preconditions plus runtime guards, one PR each.
- **D6.** Unknown attribute names warn.
