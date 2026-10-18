# Design: the four element-flow follow-ups (scalar demands, multi-parameter domain facts, local container returns, relational element returns)

**Date:** 2026-10-18
**Status:** phase 0 landed 2026-10-18 (`specs/progress/2026-10-18-relational-element-refinement-scope.md`,
which records where it departs from §1); phase 1 landed 2026-10-18
(`specs/progress/2026-10-18-element-flow-phase1-multiparam-lambda-domains.md`, which records where
it departs from §4); phase 2 landed 2026-10-18
(`specs/progress/2026-10-18-element-flow-phase2-scalar-demands.md`, which records where it departs
from §3 and §7: it also hooks return tails); phases 3-4 are design only. Probed on `ba8db5805` (0.6.0 + docs), z3 4.16.0, with the
compiler already built in this worktree (`_build/default/bin/main.exe`, Oct 18 10:12).
**Closes, when phase 4 lands:** items 1-4 of `specs/todos/2026-09-18-refine-element-flow-followups.md`
(items 5 and 6 are already closed). Each phase strikes its item there and removes its bullet from
`specs/lang/refinement-types.md`, "What element refinements do not do" (`:2267-2276`).
**Prior designs this continues:** `specs/2026-09-18-parametric-element-flow-design.md` (§4: sources,
P1/P2, `demand_flow`; its §4.5 deferred items 1 and 2) and its plan
`specs/plans/2026-09-18-parametric-element-flow-plan.md` (which deferred items 3 and 4);
`specs/2026-09-20-abstract-refinements-design.md` (the format, and the "refuted is skip" stance,
its §3.3 and decision 9.2).

**Sibling designs written at the same time, and where the line falls:**

| Sibling | Owns | This design |
|---|---|---|
| `specs/2026-10-18-fold-accumulator-invariants-design.md` | The **accumulator invariant**: inside a `Src_cod` discharge, a callback parameter typed with the *demanded* variable `b` (`acc` in `fn (acc, x) -> …`) may assume the demand. That is an inductive argument about a negative occurrence. | Gives each callback parameter the **element/domain fact** of a variable whose every source is an element (`x : a` gets `xs`'s `q`), and builds the **scalar demand entry point**. It never gives a parameter typed `b` the demand: `acc` stays unconstrained here. §4.3 states the boundary. The sibling's design assumes this one lands first and names the two interfaces it consumes (§3.2 and §4.2 below spell them out). |
| two-argument abstract predicates (`p(k, v)`, `Map.filter`) | `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md` | Disjoint. Nothing here touches `Refine_abstract`. |

**The headline finding.** Item 4 ("make relational element returns facts") turns out to sit on top of
five **live soundness bugs** in the shipped element rule, all one mistake: an element predicate that
names a *parameter* (`List({Int | _ < n})`) is read in whatever namespace it lands in, never
substituted, never retired, never checked for capture. Today the rule `entry_is_closed` keeps such an
entry from being a fact at a call site, but nothing keeps it from being a *demand*, a *stored fact* or
a *lambda's domain fact*. Each of the five proves something false (or rejects something true) on this
commit (§0, rows z1-z5). Phase 0 fixes them before anything widens. It's the smallest phase and the one
that matters most.

---

## 0. Where things stand (probed 2026-10-18 on `ba8db5805`)

Each row is a scratch program under a private `HOME`, run as
`march --check --refine-report --refine-report-sites probe.march` from the scratch directory (so the
worktree's `.march/cas` is not consulted), and the `user code` slice read. "P/V/S" is
proved/violated/skipped for the user code. "P0"-"P4" in the After column name the phase (§8) that
changes the row. Every row becomes a test in that phase. The probe sources are the `p*.march` files
named in parentheses; each is a few lines and is restated in the row.

### 0.1 Item 1: a scalar demand on a single-element result

| Row | Program (body of a `fn go`) | Today | After |
|---|---|---|---|
| s1 | `need_pos(Option.unwrap_or(o, 1))`, `o : Option({Int \| _ > 0})` | 0/0/1, `unreflectable-subject` ("the argument `Option.unwrap_or(o, 1)` could not be translated to SMT") | **proved** (P2) |
| s2 | `need_pos(Option.unwrap_or(o, 0))`, same `o` | 0/0/1, `unreflectable-subject` | **skip**, `parametric-source-unproved` ("argument 2 of `Option.unwrap_or` can fail it for some input"). Never a violation (§3.4). |
| s3 | `need_pos(Option.unwrap_or(o, 1))`, `o : Option(Int)` unrefined | 0/0/1, `unreflectable-subject` | skip, `parametric-source-unproved` (the elements of argument 1) |
| s4 | `need_pos(Option.unwrap_or(o, k))`, `k : {Int \| _ > 0}` | 0/0/1 | **proved** (P2) |
| s5 | `need_pos(Option.unwrap_or(o, Option.unwrap_or(p, 2)))` (nested) | 0/0/1 | **proved** (P2, the hook recurses) |
| s6 | `sum_pos([Option.unwrap_or(o, 1)])` (an element of a literal) | 0/0/1, `unreflectable-subject` | **proved** (P2) |
| s7 | `need_pos(Option.unwrap_or_else(o, fn () -> 1))` | 0/0/1 | **proved** (P2, a `Src_cod` source) |
| s8 | `need_pos(List.fold_left(xs, 1, fn (acc, x) -> x))`, `xs : List({Int \| _ > 0})` | 0/0/1, `unreflectable-subject` | **proved** (P2 + P1: `x` gets `xs`'s fact) |
| s9 | `need_pos(List.fold_left(xs, 1, fn (acc, x) -> acc + x))` | 0/0/1 | **skip**, `parametric-source-unproved`: `acc` is unconstrained here. The sibling's invariant design proves it. |
| s10 | `need_pos(List.head(xs))`, `xs : {List({Int \| _ > 0}) \| len(_) > 0}` | 1/0/1 (the `len` precondition proves, `need_pos` is `unreflectable-subject`) | 2/0/0 (P2) |
| s11 | the same, but `let h = List.head(xs)` then `need_pos(h)` | **2/0/0, already proved** | same |
| s12 | `need_pos(List.head(xs) + 1)` | 1/0/1, `unreflectable-subject` | 2/0/0 (P2, the *assumption* route, §3.5) |
| s13 | `let x : {Int \| _ > 0} = Option.unwrap_or(o, 1)` then `need_pos(x)` | 0/0/2 | 2/0/0 (P2) |
| s14 | `fn go(o) : {Int \| _ > 0} do Option.unwrap_or(o, 1) end` (a return tail) | 0/0/1, `unreflectable-subject`, postcondition | **unchanged** here. See §7: return tails go to the sibling's phase 1. |

Rows s10/s11 show item 1 is **partly done**. The `let` walker already turns
`let h = List.head(xs)` into a scope fact through `parametric_return`'s `` `Scalar `` arm
(`refine_check.ml:1822-1833`), but the same call written inline gets nothing, because
`check_call`'s `postcond` (`refine_resolve.ml:263-305`) never consults `parametric_return`.

### 0.2 Item 2: domain facts for multi-parameter lambdas

| Row | Program | Today | After |
|---|---|---|---|
| m1 | `sum_pos(List.zip_with(xs, ys, fn (x, y) -> x + y))`, both `List({Int \| _ > 0})` | 0/0/1, `parametric-source-unproved` | **proved** (P1) |
| m2 | the same with `fn (x, y) -> x - y` | 0/0/1, `parametric-source-unproved` | **skip**, same reason, now "the results of the function passed as argument 3 … can fail it for some input". Never a violation. |
| m3 | `List.zip_with(xs, ys, fn (x, y) -> need_pos(x) + need_pos(y))` (body obligations) | 0/0/2, `unconstrained-subject` ×2 | 2/0/0 (P1) |
| m4 | `List.fold_left(xs, 0, fn (acc, x) -> acc + need_pos(x))` | 0/0/1, `unconstrained-subject` | 1/0/0 (P1) |
| m5 | `List.fold_left(xs, 0, fn (acc, x) -> need_pos(acc) + x)` | 0/0/1, `unconstrained-subject` | **unchanged skip**: the boundary row. `acc : b` has a non-element source. |
| m6 | `List.sort_by(xs, fn (a, b) -> need_pos(a) < need_pos(b))`, return `List({Int \| _ > 0})` | 1/0/2 (the return proves, both `need_pos` skip) | 3/0/0 (P1: `a -> a -> Bool`, both positions) |
| m7 | `List.map(xs, fn x -> need_pos(x))` (one parameter, the baseline) | **1/0/0, proved** | same |

### 0.3 Item 3: a local `fn` with a container return

| Row | Program | Today | After |
|---|---|---|---|
| l1 | `fn two(n : {Int \| _ > 0}) : List({Int \| _ > 0}) do [n, n + 1] end` (local), then `sum_pos(two(k))` | 1/0/1: `two(k)`'s precondition proves, `sum_pos` is `unreflectable-subject` | **4/0/0**: `two(k)`'s precondition, two tail elements, and `sum_pos` (P3) |
| l2 | local `fn bad(n : Int) : List({Int \| _ > 0}) do [n, 0] end`, used | **0/0/0**: no obligation is even filed for the tails | **violated** at `0` (plus a skip for `n`) (P3) |
| l3 | local `fn pass(zs : List(Int)) : List({Int \| _ > 0}) do zs end`, `sum_pos(pass(ys))` | 0/0/1 | the tail skips; `sum_pos(pass(ys))` stays a skip (unproved locals lend nothing) |
| l4 | l1 with a `let m = n + 1` before the tail `[n, m]`, and `let ys = two(k)` then `sum_pos(ys)` | 1/0/1 | 4/0/0 (P3: in-walk tails see the `let`) |
| l5 | `outer(b, k) : List({Int \| _ > 0})`: `if b do [0] else (local `one`) one(k) end`, then `sum_pos(outer(true, k))` | 2/1/2: `[0]` violated, `one(k)` tail `unreflectable-subject`, `sum_pos` skip | `[0]` still violated, `one(k)` proved, **`sum_pos(outer(…))` still a skip**. The pin for the flag-isolation guard (§5.3, G3-2). |
| l6 | top-level twin of l1 (`fn top(k) : List({Int \| _ > 0}) do [k] end`) | 3/0/0, proved | same (the reference behaviour item 3 copies) |

### 0.4 Item 4: relational element returns

| Row | Program | Today | After |
|---|---|---|---|
| r1 | `fn below(n : Int) : List({Int \| _ < n}) do [n - 1, n - 2] end`; `sum_small(below(10))`, `sum_small : List({Int \| _ < 10})` | 2/0/1: both tails proved, the call `unreflectable-subject` | **3/0/0** (P4) |
| r2 | the same into `List({Int \| _ < 5})` | 2/0/1 | **violated** (`_ < 10` does not imply `_ < 5`, the ordinary element-subtyping definite failure, as `p4i` below) |
| r3 | `below` with tails `[n - 1, n]` | 1/1/0, `n` violates `_ < n` (witness `n = 0`) | same (the definition side already works) |
| r4 | `let ys = below(k)` with `k : {Int \| _ <= 10}`, then `sum_small(ys)` | 2/0/1 | 3/0/0 (P4) |
| r5 | `sum_small(below(n))`, `n : Int` unrefined | 2/0/1 | **violated** (`_ < n ⇏ _ < 10` for a large `n`), through the ordinary element-subtyping arm, exactly as r2. **Decision D2** asks whether this should be a skip instead. |
| r6 | `fn clamp(xs : List(Int), n : Int) : List({Int \| _ <= n})`, structurally recursive (`Cons(h, clamp(t, n))`) | 2/0/2: both self-call tails `unreflectable-subject` (no hypothesis: `entry_is_closed` at `refine_check.ml:2990`) | 4/0/0 (P4: the hypothesis substitutes the self-call's actuals) |

### 0.5 Live soundness bugs: relational element predicates in the wrong namespace

| Row | Program | Today | Truth | After (phase 0) |
|---|---|---|---|---|
| **z1** | `fn need_lt(xs : List({Int \| _ < n}), n : Int)`; caller `fn go2(ys : List({Int \| _ < 60})) do let n = 1000; need_lt(ys, 10) end` (`p4n`) | **1/0/0, PROVED** | false: `ys = [59]` breaks it | **violated** (`_ < 60 ⇏ _ < 10`) |
| z1′ | the same, the caller's `n` a parameter `{Int \| _ > 100}` and the call guarded by `if n > 1000` (`p4k`) | **PROVED** | false | violated |
| z1″ | `need_lt(ys, 200)` with `ys : List({Int \| _ < 5})` (`p4j`) | **0/1/0, VIOLATED** (witness `n = 0`) | true | **proved** |
| z1‴ | `need_lt([5], 10)` / `need_lt([50], 10)` (`p4g`) | both `solver-undecided` | true / false | proved / **violated** |
| **z2** | `fn below(n : Int) : List({Int \| _ < n}) do let n = 100; [50] end` (`p4l`) | **1/0/0, PROVED** | false: `below(10) = [50]` | skip, "the return expression … rebinds `n`" |
| z2 (scalar twin) | `fn below1(n : Int) : {Int \| _ < n} do let n = 100; 50 end` (`p4m`) | violated | correct today | same (the precedent being copied) |
| **z3** | `fn f(n : Int, xs : List({Int \| _ < n})) do let n = 0; match xs do Cons(h, _) -> need_neg(h) …` (`p4o`) | **1/0/0, PROVED** | false: `f(5, [3])` | skip (`solver-undecided`, as the control) |
| z3 control | the same without `let n = 0` (`p4p`) | 0/0/1, `solver-undecided` | | same |
| **z4** | `fn f(n : Int, xs : List({Int \| _ < n})) do List.map(xs, fn n -> need_neg(n)) end` (`p4q`) | **1/0/0, PROVED** (the lambda's `n` is given `{Int \| _ < n}` about *itself*: `n < n`, false, so everything follows) | false | skip (domain fact declined) |
| z4 control | `fn y -> need_neg(y)` (`p4r`) | 0/0/1, `solver-undecided` | | same |
| **z5** | `need_lt(List.map(ys, fn n -> n - 1), 10)`, `ys : List(Int)` (`p4s`) | **1/0/0, PROVED** (demand `_ < n` read under the lambda's `n`: `n - 1 < n`) | false: `ys = [100]` | skip, `parametric-source-unproved` |
| z5 control | `fn y -> y - 1` (`p4t`) | 0/0/1, `parametric-source-unproved` | | same |

z1, z2, z3, z4 and z5 are false proofs. Under `cap verified` ("if it compiles, it is proved") each one
compiles a broken contract. z1″/z1‴ are false or missed rejections of the same cause. Mechanisms, each
verified in the code:

- **z1, z5**: `check_arg_elements` (`refine_check.ml:1433-1456`) takes the callee parameter's
  `elem_refinement t` as the demand and hands it to `check_elements` unsubstituted. The slot's
  predicate names the *callee's* `n`. `check_call` then resolves `n` against the *caller's* scope
  (z1: the caller's `let n = 1000`), or finds it free (z1″: witness `n = 0`). In z5 the demand reaches
  `demand_flow`'s `lambda_ok` (`:1288-1306`), which shadows the lambda's parameter `n` in every
  channel but cannot shadow the demand's own text. The scalar path has never had this bug:
  `check_call` resolves a predicate's sibling parameter names to the call's own actuals by position
  (`name_pos` and `actual_of_name`, `refine_call.ml:704-714`).
- **z2**: the in-walk tail check (`visit`, `refine_check.ml:1573-1578`, armed by `visit_fn`
  `:3003-3013`) checks a tail with the environment *at that point*, where `let n = 100` has rebound
  `n` (and pushed `n == 100` as a path fact). The demand still says `_ < n`, now meaning the local.
  The fallback parameter-only check (`:3014-3027`) has the same flaw for a tail that mentions the
  rebound name. The scalar post engine already skips exactly this tail
  (`refine_post.ml:1651-1677`, via `tails_bound`'s `bound` list, `:78-111`).
- **z3**: `cont_shadow` (`refine_scope.ml:1395-1396`) retires an entry only by its *key*.
  `scope_shadow` (`:1187-1193`), `path_shadow` (`:1231`) and `launder_shadow` (`:1304-1309`) all also
  retire anything whose predicate *mentions* a rebound name. `xs`'s entry `_ < n` survives
  `let n = 0` and is read as a fact about the new `n` when `match` hands `h` its slot.
- **z4**: `lambda_domain_params` (`refine_check.ml:786-804`) puts `q` on the lambda's parameter
  without checking that `q` does not mention that parameter's own name.

Two more observations, both outside the four items:

- **A record whose only refinements are element slots is never obliged.**
  `type Box = { n : Int, xs : List({Int | _ > 0}) }` with `{ n: 10, xs: [0 - 5] }` files **zero**
  obligations (`p4v`). Adding a scalar refined field (`n : {Int | _ > 0}`) makes the same `[0 - 5]` a
  violation (`p4w`). `collect_ctor_sigs` (`refine_scope.ml:1963`) has no `has_elem_param`
  counterpart for record fields (`has_elem_param`, `:1740`, covers functions only).
- **Timing today.** `--check --refine-report stdlib/list.march`, private `HOME`, three runs:
  1.17 / 1.19 / 1.19 s. That is **not** the baseline the budget uses (§9): the worktree's
  `.march/cas/vc` was warm and shared, and the load average was ~6.5.

---

## 1. Phase 0: one namespace rule for relational element predicates

### 1.1 The rule

An element slot's predicate `(b, p, srt)` is in the namespace of the **declaration it came from**.
Before it is used anywhere else, it is moved into the user's namespace by exactly the rule
`postcond_of` applies to a scalar relational return (`refine_resolve.ml:263-305`):

- `classify_pred b param_names p` (`refine_encode.ml:588`). `Closed` → unchanged. `Unusable` → no
  fact, or a recorded skip for a demand. `Relational ps` → every `n ∈ ps` must have a positional
  actual (a formal recorded as `"_"` never counts), and the actuals are substituted
  **simultaneously** with `subst_params` (`refine_encode.ml:635-657`).
- **The binder first.** A named binder (`{x : Int | x < n}`) is renamed to `_` before the
  substitution, so an actual that mentions a caller variable `x` cannot be captured. Precedent:
  `refine_scope.ml:1940`.

One new function, in `refine_check.ml` next to `declared_elem_return`:

```ocaml
(* [entry] declared by a signature with formals [formals], moved into the
   caller's namespace at a call with actuals [args].  [`Stable]: every
   substituted actual must be a variable, a literal, or a [let_equality_rhs]
   shape over them (the entry may be STORED in [contenv] and outlive the
   call's program point); [`Any]: the entry is used once, here, as a demand.
   A slot that cannot be moved becomes [None] (assumption side: no fact)
   or the whole call is reported (demand side: [Error why]). *)
val instantiate_entry :
  mode:[ `Stable | `Any ] -> formals:string list -> args:A.expr list
  -> string * elem option list -> (string * elem option list, string) result
```

Why `` `Any `` is sound for a demand: the substituted predicate is evaluated at the call, where every
actual denotes exactly the value the callee receives. An actual that is a call reflects as a fresh
constant carrying that callee's proved postcondition (`refine_call.ml:1317-1345`). Proving
`∀elem. elem < c` from `post(c)` holds for the real value too. Why a stored fact needs
`` `Stable ``: a stored entry is read again later. A fresh constant per reflection keeps it sound but
useless, and a non-deterministic actual (`below(rand())`) would invite a future cache to identify two
calls. Stable actuals avoid the question.

### 1.2 The five fixes

| Bug | Fix | Hook |
|---|---|---|
| z1, z1′, z1″, z1‴ | the demand a parameter's element slot puts on its actual is `instantiate_entry ~mode:`Any ~formals:sg.param_names ~args` of `elem_refinement t`; `Error why` is a `record_elem_skip` naming the parameter | `check_arg_elements` (`refine_check.ml:1433-1456`), the `None ->` arm (the abstract arm above it is closed by construction) |
| z5 | (z1's substitution, which puts the demand in the caller's namespace, then) a **capture guard**: a lambda whose parameter names intersect the demand's free names (other than its binder) is `` `U `` with "the lambda's parameter `n` shadows a name the demanded refinement mentions" | `demand_flow`'s `lambda_ok` (`:1288-1306`), and the lambda arm of `check_pass_site_elements` (`:1484-1530`) |
| z2 | a return tail whose `bound` list (`tails_bound`, `refine_post.ml:78`) contains a name the demand's predicates mention is a **skip**, never checked: `Unreflectable_subject "the return expression of `f` under an inner binding that rebinds `n`"`, and `last_elem_return_proved := false` | `visit_fn` carries `(tail, bound)` pairs in `ret_elem_demand`'s remaining list (`:1556`) instead of bare tails; `visit`'s check (`:1573-1578`) and the fallback (`:3014-3027`) both consult it |
| z3 | `cont_shadow` also retires an entry any of whose slot predicates `expr_mentions` (`refine_scope.ml:996`) a rebound name, the same rule as `scope_shadow` | `refine_scope.ml:1395` |
| z4 | `lambda_domain_params` declines when `q` mentions any of the lambda's parameter names | `refine_check.ml:786-804` |

Record fields are the third consumer of a declared element slot (`check_field_elements`,
`:1458-1477`). There a slot predicate naming a sibling field has no formal/actual pairing at all.
**My call:** a non-`Closed` field slot is a recorded skip ("a field's element refinement names
another field"), never read. Today it files nothing (`p4u`), so this is a skip where there was
silence, not a lost proof. The pass-site codomain arm (`check_pass_site_elements`, the expected
codomain naming the domain binder) gets the same treatment: non-closed → skip.

### 1.3 What phase 0 does not change

- No new fact anywhere. Every closed predicate takes exactly today's path. The refine oracle's diff
  must be confined to fixtures with a relational element slot, and each line must be explained.
- The definition side of a relational element return is unchanged except for z2. r3 stays a
  violation, r1's tails stay proved.

---

## 2. Item 4 (phase 4): relational element returns as call-site facts

### 2.1 The judgment

A call `g(args)` to a function whose declared container return was **proved** (`elem_ret_proved`,
`refine_param.ml:151`, filled by `gate_elem_returns`, `refine_check.ml:3965-4010`) carries
`instantiate_entry ~mode:`Stable ~formals:g's param names ~args entry` instead of nothing. That is
the element mirror of `postcond_of`'s `Relational ps` arm.

`declared_elem_return` (`refine_check.ml:750-776`) gains `?args`:

- called with `~args` (from `container_entry_of_expr`'s call arm, `:725-745`): `entry_is_closed`
  (`:760`, `:770`) is replaced by "instantiates under `` `Stable ``". A slot that does not instantiate
  becomes `None`, which is weaker and sound;
- called without (a named callable passed as a value: `demand_flow`'s `Src_cod` arm `:1351-1356`,
  `check_pass_site_elements`' named arm): unchanged, closed only. A function passed as a value has no
  actuals to substitute.

The `entry_mentions (callee_abstracts …)` guard (`:771`) stays, and runs before instantiation.

### 2.2 Stored facts

`let ys = below(k)` stores `_ < k` in `contenv` under `ys` (`refine_check.ml:1871-1883`). Phase 0's
`cont_shadow` retires it the moment `k` is rebound, which is why phase 0 is a hard prerequisite: with
today's `cont_shadow`, `let ys = below(k); let k = 0; …` would carry a stale `_ < k` exactly as z3
does.

### 2.3 The self-call hypothesis

`visit_fn` builds the structural hypothesis only for a closed entry (`entry_is_closed er`,
`refine_check.ml:2990`), and `container_entry_of_expr`'s hypothesis arm (`:729-737`) returns `entry`
as-is. With the same instantiation the arm returns `instantiate_entry ~mode:`Stable ~formals ~args`
of the self-call's own actuals, and the closedness test becomes "closed or relational over `self`'s
own parameters". The structural restriction (`structural_subvars`, own name only, not a callback or
local) is unchanged. So `clamp(t, n)` gets `_ <= n`, and r6 proves.

Soundness: the hypothesis is "a structurally smaller call of `self` meets `self`'s contract *at its
own actuals*". With a closed contract the actuals don't matter. With a relational one they are exactly
what the substitution supplies. Phase 0's z2 guard applies inside the body as well: a tail under a
binder that rebinds a name the entry mentions is skipped before any hypothesis is consulted.

### 2.4 Verdicts

A relational entry that fails to imply the demand is reported through the **existing**
element-subtyping arm of `check_elements` (`:1132-1161`, `Element_domain`), with its existing
definite-failure rule, so r2 is a violation. That is today's behaviour for a *variable* with the same
entry (`p4i`, a violation). Decision D2 below asks whether a call should be softened to a skip (the
`demand_flow` stance). My recommendation is no: the entry is a proved contract, not an inferred
demand, and a variable and a call holding the same entry should get the same verdict.

### 2.5 Tests (group `elemflow-relational`, phase 4)

RED first, each confirmed red on `ba8db5805`:

1. r1 proves: ledger `(3, 0, 0)`.
2. r4 (`let`-bound, `k` refined) proves.
3. r6 (`clamp`) proves: both self-call tails are `Proved`, and `clamp` is in `elem_ret_proved` (assert
   through a caller `sum_le10(clamp(ys, 10))`, which proves).
4. A caller variable named like the callee's parameter: `let n = 3; sum_small(below(10))` proves, and
   `let n = 3; sum_lt5(below(10))` is **violated**, not proved. Read in the caller's namespace,
   `_ < n` would be `_ < 3` and imply `_ < 5`, so this pins the substitution.

Controls (must stay skip or violation):

5. r2 is violated.
6. `below(f(x))` with `f` unrefined: the actual is not `` `Stable ``, so no fact and a skip.
7. Stale-fact pin: `k : {Int | _ <= 100}`, then `let ys = below(k); let k = 5; sum_lt5(ys)` is **not
   proved** (`ys` may hold 99). A stale `_ < k` would read as `_ < 5` and prove it. With phase 0's
   `cont_shadow` the entry is retired, and the call skips.
8. A named binder: `fn below2(n : Int) : List({x : Int | x < n})` called as `below2(x)` with a caller
   `x : {Int | _ <= 10}` proves `sum_small`. No capture.
9. VC-cache pin: `sum_small(below(10))` then `sum_small(below(50))` in one module. The second is
   violated and does not inherit the first's proof (the instantiated predicate is part of the query
   text, so the key differs; the test is the proof of that).
10. An unproved relational return (r3's `below`) lends nothing: `sum_small(below(10))` stays a skip.

---

## 3. Item 1 (phase 2): the scalar demand entry point

### 3.1 The judgment

Given a scalar obligation `D = (b0, p, srt)` on a subject expression `e = g(args)`, where:

- `postcond` (the call's proved, declared return) has nothing for `g(args)`, so `check_call`'s
  self-reflection failed (`refine_call.ml:2536-2542`, recorded at `:2612-2618`);
- `g`'s declared return, refinement-stripped, is a bare type variable `v`;
- `parametric_ok ctx g [v]` (`refine_param.ml:463-472`: P1 + P2);
- `D` is `Closed` (`classify_pred b0 [] p = Closed`). **My call for v1.** A relational precondition
  (`nth(xs, Option.unwrap_or(o, 0))` against `_ < len(xs)`) falls through to today's skip. Extending
  it is the same substitution as §1.1 plus the z5 capture guard, and is filed;

then `D` holds of the call's result if every source of `v` (`sources_of`, `refine_param.ml:540-561`)
satisfies it. That's `demand_flow`'s judgment with `pairs = [(v, Refined D)]`. §4.1-4.3 of the 2026-09-18
design argue it, and nothing changes in the argument: by parametricity every `v` the result can hold
entered through a source.

### 3.2 Where it hooks (and the interface the sibling consumes)

**Refactor first, no behaviour change (its own commit).** `demand_flow` (`refine_check.ml:1227-1395`)
splits into:

```ocaml
(* The source discharge, given the demanded (variable, demand) pairs. *)
and discharge_pairs ~root errctx defs ctx path lets sc re cb ce ~span ~callee
    (g : string) (sg : fn_sig) (args : A.expr list) (pairs : (string * elem) list)
  : [ `Proved | `Unproved of string ]
and demand_flow … =   (* unchanged contract: computes [pairs] from the container return, then [discharge_pairs] *)
and scalar_demand ~root errctx defs ctx path lets sc re cb ce ~span ~callee
    (d : string * A.expr * string option) (e : A.expr)
  : [ `Na | `Proved | `Unproved of string ]
```

`scalar_demand` answers `` `Na `` unless §3.1's conditions hold. Otherwise it returns
`discharge_pairs … [(v, Refined d)]`. The sibling's `invariant_params` overlays its hypothesis inside
`discharge_pairs`' `lambda_ok`, so both designs share one discharge and one scratch-ledger discipline.

**The hook is inside `check_call`**, because every scalar obligation reaches `check_call`: arguments
(`visit` `:1587-1588`), constructor and handler arguments (`:1625-1633`), annotated `let`s
(`check_let_annotation`, `:134-170`), elements of a literal (`check_elements`' `check_one`,
`:1082-1087`) and `demand_flow`'s own `scalar_ok` (`:1274-1281`), which makes s5's nesting work with
no extra code. `check_call` lives in `refine_call.ml`, below `refine_check.ml`, so the hook is a
closure carried by the context it already receives:

```ocaml
(* refine_call.ml, call_ctx (:647-676), one new field *)
  demand : (call_ctx -> A.expr -> string * A.expr * string option
            -> [ `Na | `Proved | `Unproved of string ]) option;
      (* A scalar demand on an unreflectable CALL subject, discharged over the
         callee's sources (design 2026-10-18 §3).  [None] where no element env
         exists (a unit fixture, a scratch check).  Takes [cx] so the closure
         reads the very channels [check_call] was given: a [check_let_annotation]
         context is shadowed by the bound names, and a closure that captured
         the unshadowed ones would disagree with the goal it discharges. *)
```

`check_call`, at the `` `Other when self_reflection_failed `` arm (`:2615`), when the subject actual
is `EApp (EVar g, gargs)` and `cx.demand = Some f`, calls `f cx subject (rp.binder, rp.pred, rp.sort)`:

- `` `Na ``: the existing `Unreflectable_subject` skip, byte-identical;
- `` `Proved ``: `note Obligation.Proved`;
- `` `Unproved w ``: `note (Skipped (Parametric_source_unproved w))`. `note` already escalates under
  `cap verified`.

Recording through `note` keeps the ledger at one entry per obligation and keeps `verdict_out`
callers (`check_one`, `scalar_ok`, `check_let_annotation`) working unchanged.

**A constructor for `call_ctx` comes first.** It's built by hand in about ten places (`grep "postcond = postcond_of"`).
Phase 2's first commit adds
`cx_of ~root errctx ctx defs path lets sc re cb ce : call_ctx` in `refine_check.ml`, which fills
`postcond` and `demand`, and converts every site that has a `contenv` in scope. Sites without one
(`check_let_annotation` is called without `cb`/`ce`, `:1683` and `:3112`; the scratch checks) pass `demand = None`
or, for `check_let_annotation`, gain the `cb`/`ce` parameters its caller already has. That's the
builder's call, and it should be stated in the progress note.

### 3.3 Termination and cost

`scalar_demand` on `g(args)` discharges sources that are `args` or tails of a lambda in `args`, all
strict subexpressions, so recursion through the hook is structural and terminates. Cost: one
discharge per source per unreflectable call subject. `Option.unwrap_or` has two sources and
`fold_left` two.

### 3.4 Verdicts

Unchanged from the 2026-09-18 design §4.3 and the abstract design's decision 9.2: a **refuted
source is a skip with a witness hint, never a violation** (s2). Whether the failing source runs
depends on the caller's data (`unwrap_or(Some(5), 0)` is fine).

### 3.5 The assumption route (s10, s12): the inline twin of the `let` arm

The `let` walker already admits `let h = List.head(xs)` as a scope fact (`:1822-1833`). The same
fact for an inline call goes through `postcond`. `cx_of` builds `postcond` as

```ocaml
fun g args ->
  match postcond_of ~cb ctx defs g args with
  | Some r -> Some r                      (* a proved declared return always wins *)
  | None ->
    (match parametric_return ~entry_of:(container_entry_of_expr ctx defs cb ce) ctx defs cb g args with
     | Some (`Scalar r) -> Some r
     | _ -> None)
```

and the special `let` arm (`:1822-1833`) is deleted, since `scope_add_binding ~postcond` now gets the
same fact. `parametric_return`'s `` `Scalar `` requires every source to be an element agreeing on one
slot (`agreed_elem_slot`, `:601`), so this route never fires for `unwrap_or` (a bare source). That
case is §3.1's job. Soundness is the shipped `let` arm's, with no name in between.

### 3.6 Tests (group `elemflow-scalar`, phase 2)

RED first (each currently `unreflectable-subject`): s1, s4, s5, s6, s7, s10, s12, s13 prove; s8 proves
once phase 1 is in (phase 2 lands after it).

Controls:

- s2 is a skip with reason `parametric-source-unproved` **and** ledger `(0, 0, 1)`. It must not be
  violated.
- s3 is a skip.
- s9 is a skip (the sibling's boundary).
- A callee that is not parametric (`fn mk(o : Option(a), d : a) : a` whose body returns a literal
  `0`, so P1 fails as in row z of 2026-09-18) skips with the "not known to be parametric" text.
- A callee with an interface bound on `a` skips (P2).
- A relational demand (`nth(xs, Option.unwrap_or(o, 0))`) keeps today's skip text, byte for byte
  (the `` `Na `` path).
- `cap verified`: s2 is a hard `refinement_unverified` error, s1 compiles.
- Ledger-count pin: s5 records exactly **one** obligation for the outer `need_pos` (the nested
  discharge is scratch).

---

## 4. Item 2 (phase 1): a domain fact for every parameter of a multi-parameter lambda

### 4.1 The judgment

At a call `g(args)` with a lambda `fn (p1, …, pk) -> body` at argument `i`, where `g`'s parameter
`i` is declared `d1 -> … -> dk -> r` (`arrow_chain`, `refine_param.ml:522`, gives exactly `k`
domains): for each position `j` whose `dj` is, refinement-stripped, a type variable `aj` with
`agreed_elem_slot … aj = Some (Refined qj)` (`refine_check.ml:601`), parameter `pj` may assume
`qj`. That is §4.4 of the 2026-09-18 design applied position by position. Every `aj` value `g` hands
the lambda at position `j` came from a source of `aj`, and every source holds `qj`. The argument
never used the parameter count.

### 4.2 Code (and the interface the sibling consumes)

`lambda_domain_params` (`:786-804`) becomes two functions:

```ocaml
(* Arrow-chain positions of parameter [i] of [g] whose domain variable has an
   agreed element fact: [(j, q)].  Independent of the lambda's shape, so the
   sibling's curried-lambda peeling (its §3.3) can map positions onto nested
   ELam parameters with the same facts. *)
val lambda_domain_facts : rctx -> defs -> cbenv -> contenv -> string -> fn_sig
  -> A.expr list -> int -> (int * (string * A.expr * string option)) list

(* A flat lambda's parameters with those facts put back; [None] if no position
   has one, or a guard below declines. *)
val lambda_domain_params : … -> A.param list option
```

Its two consumers are unchanged in shape: `visit`'s `EApp` arm (`:1612-1617`, body obligations: m3,
m4, m6) and `demand_flow`'s `lambda_ok` (`:1289`, tail obligations: m1, s8).

### 4.3 Guards, and the boundary with the accumulator design

| Guard | Why |
|---|---|
| G2-1. Lambda parameter count = arrow-chain length; a nested `ELam` is not peeled (my call for v1) | a partial application has no position map. Peeling for `Enum.fold`'s `fn a -> fn x -> …` belongs to the sibling (its §3.3), which reuses `lambda_domain_facts`. |
| G2-2. **Any** parameter carrying its own `TyRefine` declines the whole lambda | `visit_lambda ~assume:true` assumes *every* parameter's annotation. Today's one-parameter rule declines exactly this case, so lifting it per lambda keeps the "never assume an unchecked annotation" invariant. A plainly typed parameter (`TyCon`) is fine, as today. |
| G2-3. A `qj` that mentions any of the lambda's parameter names declines (phase 0's z4 guard, now per position) | capture |
| G2-4. The fact comes only from `agreed_elem_slot`, which requires **every** source of `aj` to be an element (`refine_check.ml:601-673`) | **This is the line with the accumulator design.** A variable that a callback can *produce* (`b` in `f : b -> a -> b`) always has a `Src_cod` source, and an accumulator parameter `b` has a `Src_bare` one too, so it never gets an agreed slot. `acc` therefore gets nothing here (m5 stays a skip). Assuming the *demand* on `acc` is an inductive invariant over a negative occurrence, with its own soundness argument, owned by `specs/2026-10-18-fold-accumulator-invariants-design.md`. |
| G2-5. Same type variable at two positions (`sort_by`'s `a -> a -> Bool`) | both get `q`. Sound: both values came from sources of `a`. |
| G2-6. A domain that is not a bare variable (`Int`, `List(a)`) | that parameter gets nothing. A container domain fact (`cont_add_param`) is a possible extension, not v1 (my call). |

### 4.4 Tests (group `elemflow-multiparam`, phase 1)

RED first: m1, m3, m4, m6 prove (ledger triples as in §0.2's After column).

Controls:

- m2 skips (`parametric-source-unproved`), never violated.
- m5 skips (the boundary pin; a comment names the sibling design).
- G2-2: `fn (x : {Int | _ > 100}, y) -> need_big(x)` gets **no** fact on either parameter, and
  `need_big(x)` stays a skip.
- G2-3: a lambda `fn (n, y) -> need_neg(n)` over `xs : List({Int | _ < n})` stays a skip (z4's
  multi-parameter twin).
- `zip_with(xs, us, …)` with `us` unrefined: `x` gets the fact and `y` none. A body `need_pos(y)`
  skips while `need_pos(x)` proves.
- m7 (one parameter) stays `(1, 0, 0)`.

---

## 5. Item 3 (phase 3): a local `fn` with a container return

### 5.1 The judgment

A block-level `fn n(ps) : R do body end` whose `R` carries an element refinement `er` gets what
`visit_fn` gives a top-level one. Every tail is an element obligation, checked in-walk with the
facts in scope at the tail, and the tails nobody reached are checked afterwards. If every tail is
**proved** and `er` is closed (or, after phase 4, relational over `ps` only), later calls `n(args)`
in the same block carry `er` (instantiated, after phase 4) as their container entry.

### 5.2 Code

`visit_local_fn` (`refine_check.ml:2246-2290`) today runs under `with_no_ret_demand` (`:2250`).
It changes to:

1. `match elem_refinement ret_ty with Some er -> …`: compute `tails_bound` over `body` (phase 0's
   `(tail, bound)` shape), arm `ret_elem_demand := Some ("return of n", er, sp, remaining)` for the
   body walk, and check the leftovers afterwards with the walk's env, as `visit_fn:3014-3027` does.
   A `None` return keeps `with_no_ret_demand`. A `let g = fn …` lambda (`ret_ty = None`, `:1673`) is
   untouched.
2. The verdict is a **local** boolean. `last_elem_return_proved` is a module-global cell
   (`:1562`) that `gate_elem_returns` reads for the *enclosing* top-level function. The local saves it,
   sets it to `true`, walks, reads its own verdict, and **restores the saved value exactly** (G3-2).
3. On a proved verdict, the returned `fn_sig` (the value the `EBlock` loop puts into `cbenv`,
   `:1847-1866`) is registered in a lexically harmless side table:
   `local_elem_ret_proved : fn_sig list ref`, consulted by `declared_elem_return`'s `cbenv` arm with
   `List.memq`. **My call** over a new `fn_sig` field: the marker idiom already exists
   (`param_names = [callback_param_name]`, `:758`), and physical identity can't be forged by an alias
   (`cb_add_binding`, `refine_resolve.ml:228-237`, copies a *global's* signature, never a local's).
   The table is reset with the other per-module tables (`reset_param_tables`, `refine_param.ml:195`).
   Stale entries from a finished block are unreachable, because nothing can name that signature again.

### 5.3 Guards

| Guard | Why |
|---|---|
| G3-1. The escape rule decides the walk's parameter env (`escapes`, `:2261`): stripped when the local escapes, assumed when every call is obliged | the tails are checked under exactly the facts every call establishes, the same reasoning as the return-refinement verdict a few lines below |
| G3-2. `last_elem_return_proved` is saved and restored around the local | without it, a local whose tails prove would **reset** the enclosing function's flag to `true` after an earlier failing tail and admit the enclosing function to `elem_ret_proved` falsely. l5 is the pin: `outer`'s `[0]` must keep `sum_pos(outer(…))` a skip. |
| G3-3. No self-call hypothesis for a local (v1, my call) | `elem_ret_hyp`'s arm refuses a name in `ctx.locals` (`:732`). A recursive local whose tail calls itself is a skip and lends nothing. Lifting this is the same structural rule plus scoping and is filed. |
| G3-4. An `er` that mentions the enclosing function's abstract refinements (`current_abstracts`) is checked but never lent | `p` means `$abs_p` only inside the enclosing walk. Lending it is probably sound there but buys nothing anyone has asked for. |
| G3-5. An `er` that mentions a captured outer variable is `Unusable` to `classify_pred` over `ps`, so it lends nothing (and its tails are checked in place, which is correct) | namespace |
| G3-6. Phase 0's z2 rule inside the local | the same rebinding hazard |

### 5.4 Tests (group `elemflow-local`, phase 3)

RED first: l1 `(4, 0, 0)`; l2 `(0, 1, 1)`, violated at the `0` (today it files nothing); l4 proves; l5's `one(k)`
tail proves.

Controls:

- l5's `sum_pos(outer(true, k))` stays a skip. G3-2's pin: disable the save/restore and it must
  turn **proved**, which is the perturbation that proves the test live.
- l3: the tail skips and the caller skips.
- An escaping local (`apply(two, k)` somewhere in the block) with a tail that needs its parameter
  fact (`[n]`): the tail skips. G3-1.
- A recursive local `fn go(xs : List(Int)) : List({Int | _ > 0})` with tail `go(t)`: skip, and lends
  nothing. G3-3.
- A local named like a top-level function with a proved element return: the local's (unproved)
  return wins, and the call skips. Name resolution (`local_shadow`) must not reach the global.
- Ledger-count pin: each local tail is recorded exactly once, so the in-walk check and the leftover
  check never both fire.

---

## 6. Soundness table

| New assumption | Justified by | Guarded by |
|---|---|---|
| a parameter's element demand, substituted with the call's actuals (phase 0) | the callee's contract talks about *its* `n`; at the call that is the actual | `classify_pred`; every mentioned formal has an actual; binder renamed first; skip otherwise |
| no in-walk or fallback tail check under a rebinding of a demanded name (phase 0) | the tail's value is not about the declared parameter | `tails_bound`'s `bound`; precedent `refine_post.ml:1651-1677` |
| stored element entries retire on a mentioned name's rebinding (phase 0) | the fact is about the old binding | `cont_shadow` by mention, as `scope_shadow` |
| `pj : {T \| qj}` for each position of a multi-parameter lambda (phase 1) | parametricity: every `aj` value handed to position `j` came from a source holding `qj` | `agreed_elem_slot` (P1, P2, every source an element, all agreeing); arity = chain length; no own-annotated parameter; no capture |
| a scalar demand on `g(args)` holds if every source of `g`'s bare return variable meets it (phase 2) | parametricity (2026-09-18 §4.1) | P1, P2, at least one source, every source proved, closed demand only, `` `Na `` falls through to today's skip |
| `g(args)`'s scalar fact from agreeing element sources, inline (phase 2) | the shipped `let` arm, unnamed | `agreed_elem_slot`; a proved declared return takes precedence |
| a local `fn`'s container return at its later call sites (phase 3) | every tail was proved under the facts every call establishes | escape rule; save/restore of the enclosing flag; `memq` on the exact signature; closed or own-parameter-relational only |
| a relational element return at a call site, instantiated (phase 4) | the definition proved it for all values of its parameters | `elem_ret_proved`; `` `Stable `` actuals; phase 0's `cont_shadow` retirement; abstract-name guard |
| the structural self-call hypothesis at the self-call's actuals (phase 4) | induction on structure (Tier 2's rule) | `structural_subvars`, own name only, phase 0's rebinding rule |

Every row has a REJECT or SKIP control in its phase's tests, because an accept-only witness cannot
tell a working rule from one that checks nothing (`specs/lang/refinement-types.md`, "Conformance
status").

---

## 7. Scope

In scope: the four items as above, and phase 0's fixes.

Out of scope, each named in a todo so nobody reads a guarantee into its absence:

- **A scalar demand at a return tail** (s14, `fn f(o) : {Int | _ > 0} do Option.unwrap_or(o, 1) end`).
  The post engine (`check_post`, `refine_post.ml`) builds its own VCs from the parameters and never
  calls `check_call` for a tail, so the hook does not reach it, and a second ledger entry for the same
  tail would double-count. The sibling (its §3.1 row 3) plans to add the tail hook in its phase 1
  over `scalar_demand`. If it doesn't, this is its own todo. **My call:** not here.
- **A relational scalar demand** (`_ < len(xs)` on an `unwrap_or` subject): §3.1. Same substitution
  as phase 0, plus the z5 capture guard on lambda sources.
- **Curried lambdas** (`fn a -> fn x -> …`) for domain facts in the *body* walk. The sibling peels
  them for tail discharge using `lambda_domain_facts`.
- **A container domain fact** for a parameter typed `List(a)` (G2-6).
- **A local `fn`'s structural self-call hypothesis** (G3-3).
- **A record whose only refinements are element slots is never obliged** (`p4v` vs `p4w`, §0.5). A
  live enforcement hole of its own (and a silent one under `cap verified`). File it as a P2 todo.
  It's a registration fix in `collect_ctor_sigs`, unrelated to the four items.
- **The accumulator invariant**: the sibling design.

---

## 8. Phases, one PR each

Conventions as the element-flow and abstract-refinement plans: every step keeps `test_refinecheck.exe`
green; every new rule lands with a fixture that is RED without it (record the pre-change ledger in
the progress note); ledger triples (`ledger_counts3`, `test/test_refinecheck.ml:292`) and skip
reasons are asserted, never exit codes; `--root .` from a worktree; z3 on PATH (CI's z3 4.8.12, local
4.16.0); run `scripts/refine-oracle.sh baseline|check` under a private `HOME` and explain every line
of the diff; regenerate the audit baselines only where a count moves on purpose. Docs per phase: strike
the item in the todo and remove its bullet from `specs/lang/refinement-types.md` "What element
refinements do not do", run `scripts/gen-lang-docs.py`, commit both; add a `CHANGELOG.md` bullet under
`[Unreleased]` (phase 0 `### Fixed`, the others `### Added`); one `specs/progress/` file per phase.
Phase 4's PR `git mv`s the todo to `specs/progress/` (items 5 and 6 are already closed). New conformance
fixtures go under `specs/lang/types/{accept,reject}/` with the INDEX counts updated (doc-lint checks them).

Order is by risk, and also by dependency (the sibling needs phases 1 and 2).

**Phase 0: one namespace for relational element predicates (`### Fixed`).** §1. Tests (group
`elemflow-namespace`), each red on `ba8db5805` as recorded in §0.5: z1 and z1′ violated; z1″ proved;
z1‴ proved/violated; z2 skipped with the rebinding reason; z3 not proved; z4 not proved; z5 not
proved. Controls: z3/z4/z5's controls keep today's verdicts. A closed-slot regression set: every
fixture in the `element-flow`, `callback-elements` and `demand-flow` groups (`:18863-18865`) unchanged.
A non-closed record-field slot is a recorded skip. Conformance: one reject fixture per false proof
(z1, z2, z3, z4, z5). Oracle: the diff touches only fixtures with a relational element slot. Smallest
diff, highest stakes. Land it first, alone.

**Phase 1: item 2, multi-parameter domain facts.** §4. Smallest new rule: the judgment is unchanged,
generalised over positions. Tests §4.4.

**Phase 2: item 1, the scalar demand entry point.** §3. Commit 1: `cx_of` and `call_ctx.demand = None`
everywhere, oracle identical. Commit 2: `discharge_pairs` split out of `demand_flow`, oracle identical.
Commit 3: `scalar_demand` and the hook. Commit 4: the §3.5 assumption route, deleting the `let` arm.
Tests §3.6. This is the phase the sibling's phase 1 builds on. Tell its owner the interface landed.

**Phase 3: item 3, local `fn` container returns.** §5. Riskier than it looks, because of the global
`last_elem_return_proved` cell (G3-2). Tests §5.4.

**Phase 4: item 4, relational element returns.** §2. Needs phase 0 (`instantiate_entry`,
`cont_shadow`), and makes phase 3's locals relational-capable for free. The full sweep (`stdlib`,
`test/native`, `test/stdlib`, the ecosystem repos), because a new fact can turn a skip into a
violation. Tests §2.5.

One PR instead? No. Phase 0 is a soundness fix that should ship even if the rest stalls, and each
later phase has its own oracle diff to explain.

---

## 9. Performance

Protocol, as before: cold `--check` of `stdlib/list.march`, private `HOME`, `.march/cas/vc` cleared
once before the first run, three runs, median. Measure the baseline on the pre-phase-0 commit in the
builder's own worktree. Today's 1.18 s (§0.5) was taken with a warm shared VC cache under load and
is not the baseline.

| Phase | New solver work | Budget |
|---|---|---|
| 0 | none; fewer queries where a slot now declines | within 2% (noise) |
| 1 | none; more facts in existing queries | within 5% |
| 2 | one discharge per source per unreflectable call subject with a bare type-variable return; nested subjects multiply by nesting depth only | within 10%, plus the `elemflow-scalar` group's wall time within 2× the `demand-flow` group's |
| 3 | one element check per tail of a local `fn` with a container return (stdlib has none today: `zip_with`'s `go` returns an unrefined `List(c)`) | within 2% |
| 4 | none; facts that were dropped are now instantiated | within 5% |

Plus `scripts/refine-oracle.sh check`'s total wall time within 10% of its baseline at each phase.

---

## 10. Decisions

### Settled here (my calls)

1. Phase 0 is its own PR, first. The five bugs are live and independent of the features.
2. A scalar demand is v1 **closed only**. Relational demands fall through to today's skip (§3.1).
3. The scalar hook lives inside `check_call`, through a `call_ctx.demand` closure that takes the
   context it is called with (§3.2), not a global forward reference.
4. Return tails are not covered here (§7). The sibling or a follow-up adds the post-engine hook.
5. The multi-parameter rule declines a lambda in which **any** parameter carries its own refinement
   (G2-2), and does not peel nested lambdas (G2-1).
6. A local `fn`'s proved element return is marked with a `memq` side table, not a new `fn_sig` field
   (§5.2). No self-call hypothesis for locals in v1.
7. A stored relational fact admits only `` `Stable `` actuals. A demand admits any (§1.1).
8. A non-closed record-field or codomain element slot is a recorded skip (§1.2).
9. The record-without-scalar-refinement hole (`p4v`) is filed separately, not fixed here.

### Open (for the user)

- **D1. Ship phase 0 as a patch release?** It fixes five false proofs, and `cap verified` users of
  relational element parameters are affected today. Recommendation: yes, if any downstream project
  uses a relational element slot (`grep` finds none in `stdlib/`). Otherwise it can ride the next
  minor release.
- **D2. A relational element return that fails to imply a demand at a call: violation or skip?**
  (§2.4, r2/r5.) Recommendation: **violation**, the same verdict a variable with the same entry gets
  today (`p4i`). The entry is a proved contract, unlike `demand_flow`'s inferred demand, where
  "refuted is skip" was decided (abstract design 9.2).

---

## Decisions settled by the user (2026-10-18)

- **D1:** phase 0 ships in the next minor release, not as a patch (`stdlib/` has no relational element slots).
- **D2:** a relational element return that fails to imply a call's demand is a **violation**, not a skip.
