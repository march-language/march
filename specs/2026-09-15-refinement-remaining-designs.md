# Design: the remaining refinement todos

Written 2026-09-15, after the four P3s of
`specs/2026-09-13-refinement-p3-designs.md` landed (the last,
`Array.get`/`set`/`pop` bounds contracts, in #460). What is open on
refinements, and who holds it:

| Item | Todo | Held by |
|------|------|---------|
| A. `Array` follow-ups from #460 | `specs/todos/2026-09-15-array-contract-followups.md` | this design |
| B. Caller values of unknown sort declared `Int` | `specs/todos/2026-09-14-refine-caller-values-default-to-int.md` | this design |
| C. `cap no_alloc` vs `@[no_alloc]` | `specs/todos/2026-09-03-unify-cap-no-alloc-with-contract.md` | this design |
| Set refinements phases 3 (`card`) and 4 (`SortedSet`) | `specs/todos/2026-09-14-set-refinements-strengthening.md` | the set-refinements session; not designed here |
| Perceus RC / refinement docs widening | `specs/todos/2026-07-11-p2-compiler-docs-perceus-rc-refinement-types-core-march-widening.md` | blocked on compiler work that does not exist |

A, B and C are independent; each is one PR with its own oracle run against
a compiler built at that PR's base. B stacks on the set-refinements Phase 2
PR (#469), which rewrites the call sites B touches. Every PR that changes a
stdlib contract re-measures `--refine-report stdlib/list.march` on a cold
`.march/cas/artifacts-v2` (CI ratchets its skip count) and runs
`test_refinecheck.exe` under z3 4.8.12 as well as the local 4.16 (CI's
Ubuntu z3 segfaults on some queries 4.16 answers).

---

## A. `Array` follow-ups

### A1. Diagnostics spell the private measure

`Array.get(v, -1)` reports

```
refinement violation: argument `idx` of `Array.get` does not satisfy precondition `_ >= 0 && _ < pvec_length(v)` (e.g. negate = 0)
note: guard the call (e.g. `if _ >= 0 && _ < pvec_length(v) do …`) …
```

Two defects. `pvec_length` is the private measure behind the contract;
users cannot write it, and the guard the note suggests does not compile.
The checker already knows the public spelling: `measure_alias` maps
`Array.length` → `pvec_length`.

**Design (as landed).** `Refine_encode.display_measures` rewrites
`pvec_length(` to `Array.length(` in finished message text, at an identifier
boundary, only while `array_length_is_stdlib` holds (the alias's own gate),
at every call-site diagnostic in `refine_call.ml`: the violation message and
its label, the unverified hint including a `Partial_conjunct`'s held/missing
split, the `cap verified` error and the propagation warning. A text rewrite
rather than a `pred_str` mode, because the held/missing strings are produced
by `pred_str` far from the message and compared back against it. The
ledger's `Obligation.predicate` keeps the raw spelling, so `--refine-report`,
the audit baselines and the oracles keep a stable identity.

### A2. The counterexample names `negate`

`-1` parses as `EApp (EVar "negate", [1])`. `Witness.free_vars` adds the
application's head to the variable set, `decode_scope_var` decodes the
unknown `negate` to `0`, and the "example" is `negate = 0`.

**Design.** `free_vars` does not add the head of an `EApp` whose head is
an `EVar`: a callee is not a value the example can assign. A local closure
called as a head would be unrenderable anyway. With a closed argument the
render set is empty and `confirm_precond` returns `None`; the site then
falls back to `format_cx`. For a closed argument that is literally the
value the message already shows, the example adds nothing, so the
fallback prints no example when `free_vars arg = []`.

### A3. `Array.from_list` (and friends) give no length fact

`Array.get(Array.from_list([1, 2, 3]), 7)` is skipped, not reported: the
checker has no postcondition relating the array's `pvec_length` to
anything. `Array.get(v, -1)` is reported only because `_ >= 0` fails on its
own.

**Design.** Length postconditions on the constructors and the
length-preserving operations, over the same private measure:

```march
fn empty() : {PVec(a) | pvec_length(_) == 0}
fn push(v : PVec(a), elem) : {PVec(a) | pvec_length(_) == pvec_length(v) + 1}
fn set(v : PVec(a), idx : …, val) : {PVec(a) | pvec_length(_) == pvec_length(v)}
fn from_list(xs : List(a)) : {PVec(a) | pvec_length(_) == len(xs)}
fn map(v : PVec(a), f) : {PVec(a) | pvec_length(_) == pvec_length(v)}
```

`pop` returns a tuple, and tuple-component postconditions are outside the
supported fragment; it is left without one and says so in its doc.

Try to PROVE each before assuming it. `empty` is a bare constructor
application (proved with no induction, per the relational-postcondition
bullet in `specs/lang/refinement-types.md`). `push` and `set` construct
`PVec(n + 1, …)` / `PVec(n, …)` in arms of a `match` on `v` that binds
`n`; with the `define-fun` encoding from #460, `pvec_length(PVec(n+1, …))`
is `n + 1` by definition and the arm's pattern fact gives
`pvec_length(v) = n`, so both are expected to prove (verify; `push`'s
second arm goes through a nested `match` on `push_leaf`'s tuple). Anything
that does not prove (`from_list` recurses through a local `go` with an
accumulator; `map` goes through `to_list`) is marked `@[assume]`, and every
assumed contract gets a runtime property witness in
`test/stdlib/test_array.march`, as the `Set`/`Map` contracts have in
`test_set.march`/`test_map.march`.

**Soundness.** A proved postcondition is sound by construction. An
assumed one is the documented `@[assume]` trust boundary; the witness
checks it on generated inputs, including lengths across the 32-element
tail/trie boundary (0, 1, 31, 32, 33, 1025).

**Blast radius.** New facts can only turn skips into proofs or into
violations. A violation in the corpus is either a real out-of-bounds read
or a false positive, and either blocks landing. Re-run the #460 sweep
(`stdlib/`, `test/native/`, `test/stdlib/`, the eighteen ecosystem repos)
baseline-vs-new, and the refine oracle; review every moved obligation.

**Tests.** A1: the violation text contains `Array.length(v)` and not
`pvec_length`; a user module defining its own `@[measure] pvec_length`
sees its own name. A2: `Array.get(v, -1)`'s message contains no `negate`;
a non-closed argument (`i - 1` under `i >= 0`) still gets an `(e.g. i = 0)`
example. A3: `Array.get(Array.from_list([1, 2, 3]), 7)` is a violation and
`…, 2)` proves; the same through `push` on `empty()`; `set` preserves it;
REJECT controls for each (an index equal to the length).

---

## B. Caller values of unknown sort are declared `Int`

### Where it stands

A caller-side variable reaches the solver at `Int` unless the callee
declared the parameter it is passed to `Bool` or `Float`:
`scalar_sort_of_param_ty` (`refine_scope.ml`), `caller_scalar` /
`caller_scalar_of` (`refine_call.ml`), `scalar_sort_or_int`
(`refine_encode.ml`), plus the siblings `scalar_at_idx` /
`scalar_of_name` (`refine_call.ml`) and `scalar_of` / `var_const`
(`refine_post.ml`), and `reflect_scalar`'s `?(sort = SInt)` default. A
`String`, datatype or set value declared `Int` there meets its real sort
in the same VC; `sort_conflict` (on the declarations) or `resolve_sorts`
(on the goal) then skips the whole obligation as `sort-conflict`. It is a
silent skip, not an unsoundness: an ill-sorted VC is never sent.

Programs that skip today and should prove, all against
`fn need_a(xs : {List(String) | member("a", elts(_))}) : Int`:

```march
fn p(s : String) : Int do need_a(["a", s]) end                  -- parameter
fn l(t : String) : Int do let s = t
  need_a(["a", s]) end                                           -- let binder
fn m(o : Option(String)) : Int do
  match o do Some(s) -> need_a(["a", s]) None -> 0 end end        -- pattern var
fn r(s : {String | len(_) > 0}) : Int do need_a(["a", s]) end    -- refinement binder
```

and, through a path condition, a datatype:
`fn e(o : Option(Int), p : {Option(Int) | is_Some(_)}) : Int do if o == p do unwrap(o) else 0 end end`
(the guard declares `o` Int, `reflect_dt` declares it `M_Option`).

No call-result or constructor-payload shape reaches the default: a call is
unreflectable in a list head (a different skip) and `reflect_field` gives a
payload its field's own sort.

### Design

**B1. One translator, `Refine_types.sort_of_tc_ty : Typecheck.ty -> Smt.sort option`.**
After `repr`, strip `TLin`/`TRefine`; `Int` → `SInt`, `Bool` → `SBool`,
`Float` → `SFloat`, `String` → the `Str` sort, a registered datatype
`TCon (name, args)` → its instance sort via the Phase 1 instance machinery
(`instance_sort_of_ty`'s logic, lifted to `Typecheck.ty`), `Set(t)` →
`SSet (sort t)`. Everything else is `None`: `TVar`, `TError`, `Char`,
tuples, arrows, channels, unit, and records (records keep going through
`is_recvar`/`recenv`). `None` means "keep today's behaviour", i.e. `Int`.

**B2. A caller-sort lookup that reads the type_map at binding sites.**
`Refine_call.caller_sort_of name : Smt.sort option` resolves `name` to its
BINDING span, from the scope/path bookkeeping that already records where a
parameter, `let` binder, pattern variable or refinement binder was
introduced, and looks that span up in `call_type_map`. Never look up an
occurrence span on a synthesised `EVar`: those reuse the call's span
(`refine_call.ml`'s path-var and guard synthesis) and would return the
call's result type. `call_type_map` is reset at the top of `check_module`
so a stale map from a previous module cannot leak into a caller that
passes none (`precond_infer`, `postcond_infer`, `division_safety`, most
unit tests); with no map every lookup is `None`.

**B3. Route by sort, never widen `caller_scalar`.**
`caller_scalar_of`'s `<> SInt` tests (the three measure-refusal guards)
must keep meaning "a non-Int scalar", or list variables start refusing
their `elts`/`len` facts. So the new lookup feeds three consumers
separately:

- a `Str` sort → `reflect_str` and `str_names` (what a `String` parameter
  already gets), in `reflect_set_head`, `foreign_var` and `resolve_var`;
- a datatype or set sort → `reflect_dt` (datatype) or the set-head
  reflection, in `path_resolve_var` and `foreign_var`;
- `SBool`/`SFloat` → `caller_scalar` exactly as a `Bool`/`Float`
  parameter would, so a `Bool` guard dropped today becomes usable.

`reflect_scalar` is never handed a non-scalar sort.

**B4. One origin per commit.** Parameters, then `let` binders, then
pattern variables, then refinement binders, then path-condition
variables; each lands with its skip → proved fixture and its oracle diff
explained line by line, because a site that switches from `Int` to the
real sort can also expose a VC where a DIFFERENT name still defaults (a
proof turning into a skip). Such a regression blocks that origin until its
partner site is converted.

### Soundness

Declaring a name at its true sort instead of `Int` only removes
ill-sorted declarations: every VC that was sent before is sent with the
same or strictly more well-sorted facts. The risks are about
completeness, not soundness: a newly usable `Bool`/`String` guard can
turn a skip into a genuine violation (a real report), and a Float
comparison that was consistent at `Int` can move to `float-sort-gate`.
Both show in the oracle diff and are reviewed per origin.

### Tests

A typed ledger helper (typecheck, pass the `type_map`, return
proved/violated/skipped with skip reasons; today only
`has_refine_error_typed` passes a map). For each origin: the skip →
proved fixture above, a REJECT twin (`need_a(["b", s])` violated where the
element is known, or still skipped where it is not), and a control that a
`TVar`-typed value stays at its current verdict. The test at
`test_refinecheck.ml` that relies on a String guard being declared `Int`
and dropped keeps its count; fix its comment.

---

## C. `cap no_alloc` and `@[no_alloc]`: one answer

### Where it stands

Two checks with different answers:

- `cap no_alloc` (`lib/refinecheck/no_alloc.ml`): a syntactic walk of the
  `DFn`s directly in a module (not nested modules, impls or actors),
  rejecting non-empty tuples, records, constructors with arguments and
  lambdas. It never looks at callees and lets record update, `++` and
  interpolation through. It runs in `compile` (interpreter, `--jit`,
  `--check`, `--compile`) and `march test`, but not in `march check`
  (`run_check_cmd`) or the LSP.
- `@[no_alloc]` (`lib/tir/alloc_contract.ml`): checked on final TIR after
  Perceus and escape analysis, transitive over callees, with a builtin
  whitelist. It runs in `--compile`, `--emit-llvm`, `--dump-tir`,
  `--report-contracts`, `forge build`/`forge test`, and the LSP. It is
  silent under the interpreter, `--jit` and `--check` (pinned by two tests).

So `forge run` rejects a reused constructor `forge build` accepts, and
accepts a call into an allocating helper `forge build` rejects. `march
check` runs neither.

Usage: `cap no_alloc` appears only in `bench/steady_state_ring.march` and
two conformance fixtures (t43 reject, t55 accept); zero uses in the stdlib
or the ecosystem. `@[no_alloc]` has 72 uses, all in cube_forge.

### Decision

**The cap becomes a module-wide contract.** `cap no_alloc` means every
function in the module (nested modules, impl methods and actor handlers
included) carries a hard `@[no_alloc]`, judged by `Alloc_contract` on TIR.
Wherever the contract is judged, the cap is judged identically.

**`--check` and `march check` judge it too, by lowering on demand.** When
the program contains a `cap no_alloc` module or any `@[no_alloc]`
function, the check paths run lowering plus `Contract_pipeline` (no
emission), as the LSP already does. Programs that mention neither pay
nothing. If lowering itself fails on an interpreter-only program, the
result is a `no_alloc_unchecked` warning per affected function, not a
rejection.

**The interpreter, `--jit` and the REPL say so.** They cannot run the
contract without lowering on every `forge run`, so a module or function
under either form gets one `no_alloc_unchecked` hint ("allocation
guarantees are checked by `march --check`, `forge build` and the editor,
not when interpreting"). The syntactic walk is deleted: a check that
answers differently from the real one is worse than a stated absence.

Options considered and not taken: keep the walk as an interpreter-only
fallback (keeps two answers, now per mode); lower before every
interpreted run (makes `forge run` pay for a guarantee it cannot use).

### Work

1. `Alloc_contract.collect`: a `DMod` with `cap no_alloc` marks every
   function in it (recursively) `Hard`; an explicit per-function form
   (`warn`/`assume`/`transient`) inside such a module wins, so a module
   can still opt one helper out visibly. The diagnostic names the cap when
   that is where the obligation came from ("`f` is in `cap no_alloc`
   module `M` but allocates …").
2. `bin/main.ml`: the `--check` path and `run_check_cmd` lower and run the
   contract pipeline when either form is present; the interpreter/JIT/REPL
   paths and `run_test_cmd` emit the hint. Remove the `No_alloc` calls and
   `lib/refinecheck/no_alloc.ml`. Keep the `--check` CAS short-circuit
   correct: the cache key already covers the sources, and a warning-only
   result must not be cached as clean if it would suppress the warning.
3. `--no-opt` already downgrades a hard contract failure to a warning;
   `--check` does not optimise, so it must lower with the same pipeline
   options `--compile` uses by default, or reused constructors would fail
   under `--check` and pass compiled. Match the LSP's `opt:true`.
4. Docs: collapse the "different checks" paragraph in
   `specs/lang/capabilities.md` and `docs/capabilities.md` into one
   description; fix the claim that nullary constructors are free (`Nil` is a
   16-byte cell, per `specs/progress/2026-09-03-allocation-contracts.md`);
   update the realtime guidance rows. Note the change in CHANGELOG under
   Changed (a program with an allocating helper in a `cap no_alloc` module
   is now rejected; one relying on a reused constructor is now accepted).

### Tests

- The 9 `No_alloc` unit tests in `test/test_compiler.ml` are replaced by
  `test/test_alloc_contract.ml` cases driven through the cap: an allocating
  callee rejected (new), a constructor reused in place accepted (new), a
  tuple rejected, arithmetic accepted, nested module and impl method
  covered, an explicit `@[no_alloc(warn)]` opt-out inside the module.
- `--check` now answers for both forms: flip the two "`--check` ignores"
  tests to assert the error; t43 (reject) and t55 (accept) keep their
  verdicts under `check_types.sh`, now through the contract. Measure the
  `--check` wall-clock on t55 with and without the lowering to record the
  cost in the progress file.
- Interpreter: running a `cap no_alloc` program prints the hint once and
  runs.
- `bench/steady_state_ring.march` compiles clean under the new rule.
- cube_forge's 72 `@[no_alloc]` uses: `march --check` over its entry must
  report the same set of contract failures `forge build` does today (it
  should be empty); run it before and after.

---

## Order

A (one day plus the sweep) → C (one day) → B (two to three days, one
origin per commit, stacked on #469). A and C touch no common file and can
proceed in parallel; B waits for #469 to merge or rebases onto it.
