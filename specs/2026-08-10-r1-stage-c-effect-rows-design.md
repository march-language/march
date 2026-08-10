# R1 stage C — per-function effect rows: design

Status: DESIGN, nothing built. Written 2026-08-10, after stages A/B shipped
(#236, `specs/progress/2026-08-09-r1-grant-check-stages-ab.md`). Parent design:
`specs/2026-08-08-r1-no-ambient-io-design.md` (stage C section and the
"interactions to design for" list, all of which this doc answers).

## Goal, restated precisely

Stages A/B check ONE row against ONE grant: the whole-program transitive
capability closure (`fn_transitive_capability_closures_tbl`, keyed `"main"`)
against `main`'s capability parameter. Stage C makes the same guarantee
compose per function: any function that takes a concrete `Cap(P)` parameter
becomes a discharge point — its transitive row must sit under `P` — and rows
must be *effect-polymorphic* so a higher-order function's row is the row of
the function it is given, not a fiction (today: an empty set) and not a
whole-program union.

The claim certified at a discharge point is conditional and must be stated
honestly: **"this function's static reach fits under `P`, plus whatever
function values you hand it"** — the "plus" components are charged to each
caller at each call site, and the chain of discharge points from `main`
downward closes the loop.

## What already exists, and what it gets right

Load-bearing facts from the current machinery (all in
`lib/typecheck/typecheck.ml` unless noted):

- `fn_transitive_capability_closures_tbl` (~8294): per-function fixpoint over
  `env.fn_refs`, seeded from `own_cap_closures` (sig caps + body builtin caps
  + extern caps). Keys use TIR's qualified-name convention; values are
  lattice-normalized cap-path lists.
- **Edges come from `free_vars_expr`, not from calls** (~8592 comment): every
  free `EVar`, with the clause's own parameters seeding the bound list. Two
  consequences that stage C must preserve:
  1. A function's own *parameters never contribute edges* — so `List.map`'s
     entry is `∅`, NOT a union over call sites. The "union over every
     argument" failure mode does not exist in the current table.
  2. A callback passed *by name* is charged to the passer via the passer's own
     `EVar` edge. First-order and direct-lambda higher-order code is already
     charged soundly and precisely at every caller.
- **Signature caps are seeded into a function's own row** (~8808–8810), so a
  `Cap(P)` parameter propagates to callers as a *requirement* through the
  closure — exactly the R4 direction. This is different from (and must not be
  confused with) #225's exclusion of signature-only caps from the TIR
  *ceiling's used-set* (`bin/main.ml` ~2832), which stays untouched.
- `check_main_grant` (~12682): grant from the `Cap` param via
  `Cap_surface_ty.caps_in_ty`, subsumption via `Cap_lattice.cap_subsumes`,
  `IO.Foreign` refused under narrow grants, non-IO roots (`Ffi`, `LibC`)
  skipped, one-hop `(reached in \`f\`)` attribution via a BFS over `fn_refs`.
  Called only from `check_module_core` — shared by interpreter, compile, test
  and LSP paths; the REPL path (`check_module_with_env`) never reaches it.

**The actual hole stage C closes** is therefore narrow: a function that
*receives* a function value (parameter, or extracted from data) and invokes it
has a row that understates its dynamic extent. At whole-program granularity
this is invisible (the closure's creator is charged, and `main` reaches the
creator). At per-function discharge it is unsound: `fn worker(cap :
Cap(IO.Console), job)` invoking `job()` would certify as console-only while
`job` does network IO. Rows exist to make that either *accounted for* (the
polymorphic component, charged at the call site that supplies `job`) or
*refused* (unknown provenance — see below).

## Approaches considered

### A — rows in the type system proper (textbook R1b)

Add an effect slot to `TArrow` (`TArrow of ty * ty * row` with row variables),
unify rows, generalize row variables at `let`, subsume against the lattice at
discharge points.

- Pro: uniform precision through arbitrary data flow (closures in lists,
  records, refs get row-typed element types); the "right" long-term
  formulation.
- Con: `ty` has eleven constructors and every recursive function over it is
  deliberately exhaustive (occurs, generalize's collect/copy, instantiate,
  unify, `pp_ty`, …) across a ~13k-line file. Rows would interact with Rémy
  levels, the generalize deep-copy (which exists to break ref aliasing),
  `TError` absorption, session types, and the `cap_producer_ivars` hook in
  `unify`'s TVar arm. They would surface in `pp_ty` — REPL `:t`, hover, and
  every mismatch diagnostic — unless suppressed. Curried `TArrow` needs a
  convention for which arrow carries the row. This is the "largest single
  risk" the sequencing analysis named, concentrated in the most load-bearing
  code in the compiler.

### B — dedicated row-scheme inference beside the type system (RECOMMENDED)

Keep `ty` untouched. Upgrade the *value domain* of the closure analysis from
flat cap set to a row scheme, computed by the same style of fixpoint over the
same recorded per-function data, in a new pure module. A function's row is:

```
row(f) = { caps : C_f            -- concrete cap paths (today's flat set)
         ; deps : D_f            -- params of f whose value may be invoked
         ; unknown : U_f }       -- f's extent may run function values the
                                 --   analysis cannot trace to a creator
```

- Pro: no unification/generalization changes, no printed-type changes, no
  `ty` churn; interpreter/compile parity for free (typecheck-side, discharged
  from `check_module_core` next to `check_main_grant`); testable as a pure
  standalone module; today's flat table stays byte-identical for its three
  existing consumers.
- Con: precision is bounded by what a creation-site-charging, syntactic
  analysis can see. Closures laundered through mutable refs or arriving
  inside data structures whose construction site the function cannot name are
  not traced — they set `U` and are *refused* at discharge, not silently
  passed. (Approach A would type some of these; B refuses them.)

### C — B now, with an engine-swap path to A

Not a third design — it is B with the discharge surface (grant params, the
check, the diagnostics) specified independently of the inference engine, so a
later in-`ty` row system can replace `cap_rows` without changing user-visible
semantics. Recorded here so the module boundary is drawn accordingly.

**Decision: B**, with C's boundary discipline. A is not rejected forever; it
is rejected as the *first* implementation because its risk is concentrated
exactly where this codebase has the least margin (HM core), while B delivers
the guarantee with sound refusal semantics at the precision frontier.

## The row calculus (approach B, precise)

### Recording (during the existing per-module scan)

Alongside `record_fn_refs`, record per function:

- `d_seeds` — parameters applied as functions in the body, directly or via a
  local `let` alias chain (below).
- `u_seed : bool` — the body applies a head the rules below cannot classify.
- `call_args` — for each application whose head resolves to a known function
  name `g`: the positional *shapes* of its arguments, where a shape is one of
  `AParam of string` (a parameter of `f`), `AName of string` (a resolvable
  top-level name), `AOpaque` (anything else: nested application result, field
  of non-param, `ref_get`, …), `AInline` (lambda literal or literal structure
  — already charged to `f` by the body walk, contributes nothing extra).

Head classification for an application `h(args)` in the body of `f`:

| head `h` | effect |
|---|---|
| builtin / resolvable top-level name | edge (existing) + record `call_args` |
| parameter of `f` | `d_seeds ∪= {h}` |
| lambda literal | body already walked; nothing extra |
| local `let`-bound name | classify its RHS transitively: params free in the RHS chain join `d_seeds`; an unclassifiable RHS sets `u_seed` |
| anything else (field access on non-param, application result, match-binder of unknown origin, …) | `u_seed := true` |

`d_seeds` deliberately admits non-function-typed parameters (e.g. `cfg` in
`cfg.handler(x)`): membership in `D` means "the value bound to this parameter
may be invoked (possibly a component of it)", and instantiation below makes
that meaningful without needing type information in this pass.

### Fixpoint (new pure module, `lib/caps/cap_rows.ml`)

Inputs: the recorded seeds, `own_cap_closures` (C seeds — including signature
caps, preserving requirement propagation), `fn_refs` edges, `call_args`, and
the resolver used by the existing fixpoint (owner-prefixed then bare). Iterate
to fixpoint:

- `C_f ∪= C_g` for every edge `f → g` — **identical to today's computation**,
  so the C-projection of the row table equals the flat table by construction.
  This is a pinned property (test below), not an aspiration.
- For each recorded call `g(shapes)` in `f` where `row(g).deps` marks
  position `i`:
  - `AParam p` → `D_f ∪= {p}` (effect polymorphism composes: `f` passes its
    own parameter into an effect position, so `f`'s callers owe that row).
  - `AName h` → if `D_h = ∅`, `C_f ∪= C_h` (usually redundant with `f`'s own
    edge to `h`, harmless); if `D_h ≠ ∅`, the callee will invoke `h` with
    arguments supplied *inside `g`*, which `f` cannot see → `U_f := true`.
  - `AOpaque` → `U_f := true` (the callee will invoke a value this analysis
    cannot trace to a creation site).
  - `AInline` → nothing (already charged).
- `U_g` propagates along edges like a capability: `U_f ∪= U_g`.
- Provenance: for every element added to `C_f` (and for `U_f`), record the
  witness edge `(via : string, span)` that introduced it, first-writer-wins.
  This is the typecheck-side replacement for `cap_attrib`'s "who reaches what
  through whom" — `cap_attrib` itself is NOT reused: it is a TIR pass, runs
  compile-only, and gating diagnostics on it would recreate the interpreter/
  compile divergence the parent design forbids.

Charging at *supply* sites, not invocation sites, is what makes partial
application sound: `let m = map(g)` charges `row(g)` where `g` is supplied;
the later `m(xs)` adds nothing (and, via the local-let rule, does not set
`U`).

### Discharge (new check in `check_module_core`, beside `check_main_grant`)

A **discharge point** is any function with ≥1 parameter of *concrete*
`Cap(P)` type (`caps_in_ty` non-empty; `Cap(a)` with a type variable
contributes nothing and creates no discharge point — `cap_narrow`-style
plumbing stays polymorphic). The grant set `G` is all cap paths across all
its parameters — unlike `main` (exactly one cap param, unchanged), a helper
may take several narrow caps (corpus: `t57_cap_all_hierarchy_args`).

For each `c` in the function's transitive `C` row, reusing stage B's decision
ladder verbatim:

1. non-IO-rooted `c` (FFI roots) → skipped, as in stage B;
2. `c` under `IO.Foreign` and no `g ∈ G` equal to `IO` → refusal with stage
   B's "linked C code, whose behavior the capability lattice cannot bound"
   message;
3. otherwise error unless some `g ∈ G` has `cap_subsumes g c`.

Additionally, stage C's own refusal: if the transitive `U` flag is set, the
function cannot be certified under a narrow grant — error, message naming the
witness site ("invokes a function value whose origin the capability analysis
cannot trace — cannot certify a narrow grant over it; grant `Cap(IO)` or
restructure so the invoked function is named or passed as a parameter").
Refusal, never a silent pass: same philosophy as the `IO.Foreign` rule.

`D_f` components are NOT checked at `f`'s own discharge point — they are the
conditional part of the claim. They are checked at every *call site* by
construction: the supplier's row absorbed the argument's row where the
argument was supplied, and the supplier is in turn under some discharge point
on the chain from `main` (or under no gate at all, ambient — unchanged
adoption contract).

`main` keeps `check_main_grant` unchanged (its closure lookup may later read
the row table's C-projection; not required and not part of this change).

### Diagnostics

The stage B message shape, extended from one hop to a chain by following
provenance witnesses from the discharge function to a direct holder:

```
`worker` is granted `Cap(IO.Console)`, but reaches `IO.Network`
(via `fetch` -> `Http.get`). The grant is a ceiling on everything
`worker` can reach — declaring `needs IO.Network` does not raise it.
```

Chains render at most ~4 hops then elide (`… -> Http.get`). Witnesses are
recorded during the fixpoint, so the chain costs nothing extra at error time
and exists identically on the interpreter path.

## Answers to the parent design's open questions

**Row syntax: none, in stage C.** Rows are inferred-only and never printed.
The discharge surface is the *existing* `Cap(P)` parameter syntax — the
stage A/B corpus (#225/#236 migration, `examples/capabilities.march`, corpus
t45–t61) shows every boundary declaration is already written as a cap
parameter, and a second surface (`! {IO.FileRead}` annotations) would be a
redundant spelling of the same fact. An optional annotation/ascription
surface remains a possible stage D if per-dependency budgets want written
contracts; nothing in this design precludes it.

**Generalization: sidestepped, by construction.** In approach B there is no
interaction with HM let-generalization — the polymorphic component (`D`) is
structural (per parameter, per function definition), not a quantified
variable in `ty`. This retires the project's largest named risk. The cost is
bounded precision (the `U` refusals) rather than unsoundness.

**Upgrade in place vs parallel pass: both, precisely.** The recording extends
the existing scan in place (new fields beside `record_fn_refs`); the fixpoint
is a NEW pure module and a NEW table; `fn_transitive_capability_closures_tbl`
and its three consumers (Check 4, unused-`needs` suppression,
`check_main_grant`) are not touched. The C-projection ≡ flat-table property
is pinned by test, so the two cannot drift silently. No feature flag is
needed for the *analysis* (it emits nothing by itself); the *check*'s
staging is below.

**Signature-only capabilities: requirements, preserved.** Sig caps stay
seeded into `C` (they already are), so callers inherit them as requirements —
and a discharge point's own grant params trivially satisfy themselves
(`cap_subsumes P P`). The #225 exclusion lives in the TIR ceiling's used-set
and is untouched; the two mechanisms are documented as distinct here so
nobody "fixes" one by breaking the other.

**`IO.Foreign`: stage B's refusal, verbatim, at every discharge point.**

**Interpreter parity: structural.** Recording, fixpoint, and check all live
in typecheck and are reached from `check_module_core` — the same single
place `check_main_grant` runs — so `march f.march` and `march --compile
f.march` reject identically, and the REPL/JIT path keeps its existing
exemption by never calling `check_module_core`. Test bodies are unaffected:
the new check fires at *definition* sites of cap-param functions, not at
call sites, and R2's test-body rootlessness is about call sites.

**Migration cost: zero signature changes, zero printed-type changes.** The
stdlib defines no cap-parameter functions (only extern-block caps, which are
not discharge points). The observable change is confined to *existing
non-`main` functions with concrete cap params*: `examples/capabilities.march`
(5 functions) and the corpus accept files (t45–t61 family) start being
checked. Every one was written to be honest, so the expected new-error count
is zero — but that is a claim the sweep must prove, not assume (below). The
parent design's "only in inferred (unwritten) types" survives: it is in fact
strengthened to "no type surface changes at all".

## Enforcement staging and the U-rate gate

1. **Analysis lands first, inert** — recording + `cap_rows` fixpoint + a
   debug dump (`--dump-cap-rows` or env var, following `MARCH_DUMP_TXT`
   precedent). No diagnostics. Pinned by: unit tests on the pure module
   (map-shaped `D`, composition through two HOF layers, `U` seeding and
   propagation, partial-application charging) and the C-projection golden
   equality test.
2. **Measure `U` across the corpus** before choosing refusal severity: dump
   rows for stdlib + examples/ + bench/ + test/native/ + the types corpus and
   count functions whose *transitive* `U` is set. If `U`-poisoning is rare
   (expected: dispatch through refs/data is uncommon in March style), the
   refusal ships as specified. If it poisons broad stdlib strata, the refusal
   needs re-scoping (e.g. `U` tracked per-origin so only genuinely-reaching
   paths poison) BEFORE the check ships — this is a design gate, recorded
   here so it cannot be skipped silently.
3. **The discharge check lands default-on only after the full sweep is
   clean**: `specs/lang/types/check_types.sh`, plus compiling examples/,
   bench/, test/native/, test/stdlib/ — the real binary against the real
   stdlib-prepended shape (the cap-shadowing postmortem's lesson,
   `specs/progress/2026-08-09-cap-shadowing-false-positive.md`: green
   alcotest from `parse_and_desugar` helpers proves nothing for this class
   of change). If the sweep finds violations in real corpus functions, each
   is triaged (real bug in the fixture vs. precision gap in the analysis);
   only a clean sweep ships default-on — stage A/B's zero-migration
   precedent, else the check goes behind `--cap-fn-grants` while fixtures
   are fixed, with default-on as a fast follow.

## Testing plan (RED first, per convention)

- `test_compiler.ml`, new `cap_fn_grant` group: accept (narrow grant
  honored; HOF under grant with pure callback supplied by caller under its
  own grant; multi-cap-param grant set; `Cap(a)` param creates no gate),
  reject (direct violation; violation through a helper, chain named;
  callback whose row exceeds the SUPPLIER's grant, error at the supplier;
  `IO.Foreign` refusal; `U` refusal), and at least one test exercising the
  real stdlib-prepended shape (via the flattened-prelude helper or the real
  binary), not only `parse_and_desugar`.
- `cap_rows` unit tests (pure module, standalone).
- Golden: C-projection ≡ `fn_transitive_capability_closures_tbl` over a
  fixture set that includes HOFs, defaults (`f$0` mangling), impl methods,
  actor handlers, and DLet bodies — every key shape the flat table handles.
- Corpus: new accept/reject pairs under `specs/lang/types/` (numbered after
  t167), including the "declaring does not grant" pin at function level.
- Full suite + corpus sweep + examples/bench/native/stdlib compile before
  merge, per the verification-discipline section above.

## Out of scope, recorded

- Removing the flat closure's over-approximation (a function charged for a
  callback it references but provably never invokes) — sound today, stays.
- Per-dependency budgets in `forge.toml` (Tier 2 of the loose-ends plan) —
  rows are the substrate it needs; wiring forge to them is its own item.
- In-`ty` rows (approach A) as a future engine swap — the `cap_rows`
  module boundary and this doc's discharge semantics are the contract such a
  swap must preserve.
- `forge` `grant = [...]` manifest sugar — still deferred, unchanged from
  the parent design.
