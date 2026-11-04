# Allocation bounds (`@[alloc_bound(...)]`): design

## Scope

Extend the allocation contract (`@[no_alloc]`, design
`specs/2026-09-03-allocation-contracts-design.md`, implementation
`lib/tir/alloc_contract.ml`) from a yes/no verdict to a count: the function, and
everything it calls, performs **at most N heap allocations per call**. The check
runs on the same final TIR as `@[no_alloc]`, after Perceus, escape analysis and
TRMC, so reused and stack-promoted cells are not counted.

This document covers two forms, each landing as its own PR:

- **Phase 1, constant bounds**: `@[alloc_bound(N)]`. No recursion in the call graph
  below the function.
- **Phase 1.5, per-activation bounds**: `@[alloc_bound(per_call: N)]`. At most N
  allocations per activation of a recursive function, not counting what its
  recursive calls do.

**Phase 2, symbolic bounds** (`@[alloc_bound(3 * len(input))]`, proved by the
refinement checker) is sketched at the end but **not designed here**. It gets its
own spec once phases 1 and 1.5 show which real functions they can't express.

Nothing here adds a TIR node, changes a pass, or changes any program's IR. The
check only reads the TIR.

### Why

- **Denial-of-service bounds on parsers and protocol handlers.** The stdlib parsers
  have already been rewritten once because of hand-measured allocation rates
  (`specs/progress/2026-07-27-json-parse-allocated-2-heap-strings-per-input-byte-*`,
  and the toml, yaml, xml, uri and regex siblings dated 2026-07-28). Nothing stops
  those rates from creeping back. A checked bound does.
- **A regression gate with no timing noise.** `bench-gate` checks outputs, not time
  (`specs/lang/claim-performance.md`, "Gate"), and allocation-count gates are listed
  there as planned. A count checked by the compiler is exact on every run.
- **FBIP code that allocates a little.** `@[no_alloc]` covers zero allocations;
  most in-place transforms allocate a small constant per step. There is no way to
  pin that today.

### Non-goals

- **Bytes.** The bound counts allocation *events*, not sizes. A function that
  allocates one string whose length depends on its input satisfies
  `@[alloc_bound(1)]`. Bounding bytes needs allocation sizes as symbolic
  expressions, which is phase-2 work or later.
- **Live memory or leaks.** That is `@[no_alloc(transient)]` (net retained) and
  `march_live_allocs` (leaks). `@[alloc_bound]` is about allocation volume per call.
- **Time.** No claim about cycles or wall clock.
- **Interpreter and `--check`.** Same as `@[no_alloc]`: these modes don't lower to
  TIR, so the attribute is reported unchecked (the existing `no_alloc_unchecked`
  path).

## Surface syntax

```march
@[alloc_bound(3)]                    -- at most 3 allocations per call
fn parse_pair(s : String) : (String, String) do ... end

@[alloc_bound(3, warn)]              -- warning instead of error on violation
fn render_row(r : Row) : String do ... end

@[alloc_bound(1, assume)]            -- trusted, never checked; callers use 1
fn wrap_c(buf : Buffer) : Bytes do ... end

@[alloc_bound(per_call: 2)]          -- per activation of a recursive function
fn map_inc(xs : List(Int)) : List(Int) do ... end

@[alloc_bound(per_call: 2, warn)]
```

N is a non-negative integer literal. `alloc_bound(0)` means the same thing as
`@[no_alloc]` and is checked identically. `forge fix` never generates it.

### Parser

The `fn_attr` rule in `lib/parser/parser.mly` already has the two payload shapes
these forms need:

- `@[name(e, ...)]` with an expression list, currently accepted only for
  `decreases` (other names get a single bare identifier, or an error).
- `@[name(key: INT)]`, currently accepted only for `reflect(fuel: N)`.

The change is in those two semantic actions only. They now also accept
`alloc_bound` and encode it in the existing `name:value` string convention, so
`fn_attrs` stays a `string list` and `Alloc_contract.form_of_attrs` reads it like
the other forms:

| Written | Stored in `fn_attrs` |
|---|---|
| `@[alloc_bound(3)]` | `alloc_bound:3` |
| `@[alloc_bound(3, warn)]` | `alloc_bound:3:warn` |
| `@[alloc_bound(3, assume)]` | `alloc_bound:3:assume` |
| `@[alloc_bound(per_call: 2)]` | `alloc_bound:per_call:2` |
| `@[alloc_bound(per_call: 2, warn)]` | `alloc_bound:per_call:2:warn` |

The last row needs a new production: the labelled form followed by
`, LOWER_IDENT`. Everything else is a parse error naming the accepted shapes:
a negative or non-literal N, `transient` (a keyword, so it never reaches these
rules anyway), `per_call` without a count, or a second `alloc_bound` on the same
function. As with `@[no_alloc]`, the attribute is rejected on actors, types and
`extern` declarations.

**Combining with `@[no_alloc]`.** `@[no_alloc]` together with any `alloc_bound` is
an error: they contradict each other unless N is 0, and then one is redundant.
`@[no_alloc(transient)]` together with `alloc_bound` is allowed: one bounds how much
is allocated, the other forbids keeping any of it.

**Tree-sitter.** `tree-sitter-march/grammar.js` already accepts both shapes
generically (`attribute`: `'[' identifier '(' identifier ':' integer ')' ']'` and
`'[' identifier '(' commaSep(_expr) ')' ']'`). The new `per_call: N, warn` shape is
not covered: either extend the first alternative with an optional
`',' identifier`, or list its fixture in `known-failures.txt` with a todo, per
CLAUDE.md. `alloc_bound` and `per_call` are identifiers, not keywords, so
`keyword-allowlist.txt` doesn't change.

## The count

### What is counted

One allocation is one site in `Alloc_contract.direct_reason`'s table, so the
existing classification of every TIR node is reused unchanged: `EAlloc` (not
elided), `EAllocHole (None, …)`, non-empty `ETuple`, `ERecord`, `EUpdate`, a
non-static closure struct, a boxed Float or boxed aggregate at an erased slot,
and an allocating builtin. `EReuse`, `EAllocHole (Some _, …)`, `EStackAlloc`, RC
operations, `EFree`, `ESetField`, field reads and scalars count 0. The
`panic_` / `march_decrc_freed` exemptions carry over.

A node that triggers two of these (an `EReuse` that also boxes a Float into an
erased slot) counts each box separately. `direct_reason` stops at the first
reason; the counter must not.

### Builtins

`named_builtin_allocates : Builtin_name.t -> bool` becomes a total function to a
count:

```ocaml
type cost = Zero | Fixed of int | Unbounded
val named_builtin_cost : Builtin_name.t -> cost
```

It stays total with no wildcard arm, so adding a builtin without classifying it
still fails to compile the compiler. `named_builtin_allocates b` becomes
`named_builtin_cost b <> Zero`, which keeps `@[no_alloc]`'s verdicts unchanged.

- `Zero`: everything that returns `false` today.
- `Fixed 1`: builtins that allocate exactly their result: the `*_to_string`
  family, `String_concat_n` (one result string at any arity, per the existing
  comment), the escapes.
- `Unbounded`: builtins whose number of allocations depends on their input or on
  runtime state: `Vault_reap` (builds a list), `Record_from_list`, the
  task-spawn and channel family (runtime-side scheduling structures), and any
  builtin whose C implementation isn't obviously constant. **The default for
  anything unclear is `Unbounded`**, matching the existing "unclear means
  allocating" rule.

The fallback list for builtins that aren't dispatched through `Builtin_name`
(`scalar_builtins`, with everything not listed treated as allocating) gets the
same treatment. Listed means `Zero`, everything else is `Unbounded`, and a new
`fixed_one_builtins` list holds the audited single-result ones.

Auditing this table against `runtime/*.c` is the largest single work item in
phase 1. It decides how many stdlib functions can carry a bound at all.

### Combining counts over the final TIR

`cost(e)` is a value of the `cost` type above, with `Unbounded` absorbing
everything it's added to:

| Expression | Cost |
|---|---|
| A counted node (table above) | 1 per allocation it performs |
| `ELet (_, e1, e2)`, `ESeq (e1, e2)` | `cost e1 + cost e2` |
| `ECase (_, branches, default)` | maximum over the branches and the default |
| `EApp (g, _)`, `g` a user function | `bound g` (next section), plus any Float or aggregate boxing at the call |
| `EApp (g, _)`, `g` a builtin | `named_builtin_cost g` |
| `EApp (g, _)`, `g` an extern | `Unbounded`, unless the enclosing function is `assume` |
| `ECallPtr` | `Unbounded`, unless the enclosing function is `assume` |
| `ELetRec (fns, body)` | `cost body`; a local function that survives to the final TIR is treated like a top-level function of the same name |

March has no loops; iteration is recursion, including tail calls that TCO turns
into jumps. A function's only unbounded behaviour therefore comes from a cycle
in the call graph, an opaque call, or an `Unbounded` builtin.

### Bounds across the call graph

Over `m.tm_fns`, compute the strongly connected components of the call graph
(`EApp` edges only, the same edges `allocating_fns` follows):

- **A function outside any cycle** (not in a recursive SCC):
  `bound f = cost (body f)`. Callees are computed first, in reverse topological
  order. It's a single pass, with no fixpoint.
- **A function in a recursive SCC**: `bound f = Unbounded` for phase 1's constant
  form. For phase 1.5, see the next section.
- **A function marked `assume`**: `bound f = N` as written, whatever its body.
  `assume` is the only way across an extern or closure call, as with
  `@[no_alloc(assume)]`.

A constant contract `@[alloc_bound(N)]` on `f` holds iff `bound f` is `Fixed k`
with `k <= N`. `Unbounded` always fails.

Monomorphized clones resolve to their declaration through
`Tir_names.strip_specialization_suffix`, exactly as `decl_of` does now. **The
contract must hold for every clone.** The diagnostic names the worst-case clone
when they differ (a `Float` instance can box where an `Int` instance doesn't).

### Per-activation bounds (phase 1.5)

For `f` in a recursive SCC `S`:

```
activation f = cost (body f), counting each EApp to a member of S as 0
```

`@[alloc_bound(per_call: N)]` holds iff `activation f` is `Fixed k` with `k <= N`.
A call out of the SCC still adds the callee's whole bound, so that callee must be
outside any cycle or `assume`. Each member of a mutually recursive SCC is checked
independently against its own attribute. A member with no attribute contributes
nothing, because the per-activation count of `f` excludes every edge into `S`.

This form says nothing about the *total*. It doesn't know how many activations
happen. That is deliberate: the total is the number of recursive calls times N,
the number of calls is exactly what the termination checker reasons about, and
connecting the two is phase 2. The documentation must state it in these terms:
"at most N per step; how many steps is the job of `@[decreases]`."

A per-call contract on a function outside any cycle is accepted and checked as a
constant bound, and the diagnostic hints that the plain form says the same thing.

## Where the check runs

`Alloc_contract.check` (called from `Contract_pipeline`, after the last pass
before LLVM emission) gains a third verdict next to `allocating_fns` and
`retaining_fns`:

```ocaml
val alloc_bounds :
  ?k_table:Kind.table -> decls:decl_info list -> Tir.tir_module
  -> (string, bound * witness) Hashtbl.t
```

`decl_info.d_form` grows a `Bound of { per_call : bool; n : int; severity }` case.
`is_obligation` treats it like `Hard`/`Warn`. The LSP gets the verdict for free,
because it already runs `Contract_pipeline`.

**Cost.** The SCC pass and the bottom-up sum are linear in the module, and
`allocating_fns` already walks every body. Compute bounds only when some
`decl_info` carries a `Bound` form, or when `--report-contracts` is on, so builds
that don't use the feature pay nothing.

**Naming.** `perceus_core.ml` already has a field `oc_alloc_bound` (variables
bound by an allocation). It's unrelated. Use `alloc_bound_*` names only inside
`alloc_contract.ml` to avoid confusing grep results.

### Build configuration

Exactly the `@[no_alloc]` rules ("Build configuration" in the 2026-09-03 design):
under `--no-opt` a hard failure becomes a warning that names the flag, and the
TRMC-eligible hint fires when TRMC is off. TRMC has been on by default since
2026-09-09, so in practice that hint only appears under an explicit opt-out.

## Diagnostics

A failure says what was found, not just that the bound was exceeded. The
`witness` is the worst path: the list of allocation reasons along the
maximizing branch choices, each with its count. TIR nodes don't carry source
spans (provenance is per function, `lib/tir/provenance.ml`), so the witness
names node kinds and callees, like `describe` does now, and the diagnostic sits
on the function's name span.

```
error: `parse_pair` is marked @[alloc_bound(3)] but can allocate 5 times per call.
  On its worst path:
    calls `String.split`, which allocates up to 2 times
    a tuple is allocated here
    string concatenation (2 times)
  [alloc_bound]

error: `tokenize` is marked @[alloc_bound(4)] but has no fixed bound.
  `tokenize` calls itself, so the number of allocations depends on how many
  times it recurses.
  hint: @[alloc_bound(per_call: N)] bounds each step instead.

error: `walk` is marked @[alloc_bound(2)] but has no fixed bound.
  `walk` calls `Vault.reap`, whose number of allocations depends on its input.

error: `process` is marked @[alloc_bound(1)] but calls through an unknown
  closure `f`. I can't see what `f` allocates. If you know, mark `process`
  @[alloc_bound(N, assume)].
```

New error code `alloc_bound` in `lib/errors/code.ml` (registered in the code list
and given an `--explain` page through `scripts/seed-error-corpus.sh`). The
contradiction error for `@[no_alloc]` together with `alloc_bound` gets its own
code, `alloc_bound_conflict` (there's no general invalid-attribute code to reuse).

## Reporting and generation

- **`--report-contracts`** prints the inferred bound for every function in scope,
  annotated or not: `Fixed k`, `per_call k` for SCC members, or `unbounded`, with
  the first reason. This is the inference half, and arguably the first useful
  deliverable: it shows where the stdlib stands before anyone writes an attribute.
- **`forge fix --contracts`** inserts `@[alloc_bound(k)]` only for functions
  matching an opt-in glob in `forge.toml` (`[contracts] alloc_bound = ["Json.*"]`),
  with k set to the inferred bound. The default scope is empty: unlike
  `@[no_alloc]`, a bound on every function would just record the status quo.
  Inserting the inferred k pins the current behaviour; tightening it is a human
  decision.
- **LSP:** a code lens `✓ alloc ≤ 3` on a holding contract, next to the existing
  `✓ no_alloc` lens, and a quick fix "Add `@[alloc_bound(k)]`" under the same
  glob scope as `forge fix`.

## Testing

All cases compile with `--compile` and check the exit code and diagnostic text.
Accept cases also run the binary against the interpreter (compiled-parity
convention). New reject programs go in the golden diagnostic corpus
(`test/errors/alloc_bound_<n>.march`, added through
`scripts/seed-error-corpus.sh`).

Accept:
- Exact equality: a function with exactly 3 allocations under `alloc_bound(3)`.
- Maximum over branches: 1 allocation on one arm and 3 on the other passes
  `alloc_bound(3)`.
- A reused cell is not counted (an FBIP transform with one reuse and one fresh
  allocation passes `alloc_bound(1)`).
- Transitive: `f` calls `g` twice, `g` is bounded by 1, `f` has one allocation of
  its own, so `alloc_bound(3)` passes.
- `per_call: 1` on a `List.map`-shaped function with TRMC on (each step reuses
  the cons cell or allocates exactly one).
- `assume` on a wrapper around an extern, with a bounded caller.
- `alloc_bound(0)` gives the same verdict as `@[no_alloc]` on the whole accept
  corpus of the 2026-09-03 design.

Reject:
- One allocation over the bound, with the witness listing every reason.
- A bound that only fails on the worse branch (the witness follows that branch).
- A self-recursive function with a constant bound (the "calls itself" message
  and `per_call` hint).
- A call to an `Unbounded` builtin.
- `ECallPtr` without `assume`.
- A monomorphized clone that boxes Floats where the `Int` clone doesn't (the
  diagnostic names the `Float` clone).
- Parse errors: a negative N, a non-literal N, `per_call` without N, two
  `alloc_bound`s, `@[no_alloc]` together with `alloc_bound`.

Behaviour:
- The `warn` form exits 0 and prints the warning.
- `--no-opt` downgrades a hard failure.
- `--report-contracts` prints `Fixed`, `per_call` and `unbounded` lines.

Proofs the check isn't vacuous (CLAUDE.md: an oracle must go red before a green
counts):
- **Count parity with the runtime.** For every accept case, build with
  `--rc-trace`, run under `MARCH_TRACE_GC=1`, count the allocation events inside
  a single call of the annotated function, and assert the count is ≤ the inferred
  bound. `march_live_allocs` can't be used: it's a net gauge (allocations minus
  frees), so a function that allocates and frees reads 0. Then mutate one case to
  allocate more and see the parity test fail. This is the test that keeps the
  builtin table honest.
- **No IR change.** `scripts/ir-oracle.sh` must be green: the feature only reads
  the TIR.

## Work breakdown and estimates

Estimates for one engineer who already knows `alloc_contract.ml`.

| PR | Contents | Estimate |
|---|---|---|
| 1 | `cost` type; `named_builtin_cost` and the fallback lists, audited against `runtime/*.c`; `named_builtin_allocates` rewritten in terms of it (no verdict changes, proved by the existing `@[no_alloc]` tests). | 3–4 days |
| 2 | Parser forms, `Bound` decl form, SCC pass, `alloc_bounds`, witness, diagnostics, error code, golden corpus, `--report-contracts` output, runtime count-parity test. | 4–5 days |
| 3 | `per_call` (phase 1.5): per-activation cost, the SCC-member rules, tree-sitter update, docs. | 3–4 days |
| 4 | LSP lens and quick fix, `forge fix --contracts` glob scope. | 2–3 days |

That's 2.5–3.5 weeks in total. PR 1 is the riskiest: the builtin audit decides how
much of the stdlib comes out `Unbounded`, and an optimistic classification is
caught only by the parity test.

## Documentation and bookkeeping

- `specs/lang/surface-syntax.md`: attribute reference entry, then
  `scripts/gen-lang-docs.py`.
- `specs/lang/memory-model.md`, "Writing allocation-free code": add the bound as
  the way to pin "allocates a little" FBIP code, with the per-call caveat in
  plain words.
- `specs/features/compiler-pipeline.md`: note the third verdict under the
  contract check.
- `CHANGELOG.md`: one `### Added` bullet per user-visible PR (2, 3, 4).
- `specs/todos/2026-11-04-alloc-bound-contract.md` is filed with this spec and
  moved to `specs/progress/` by the PR that lands phase 1.5.

## Phase 2 (sketch, not designed)

Goal: `@[alloc_bound(3 * len(input) + 2)]`, where the bound is an expression over
parameters and refinement measures, proved by `lib/refinecheck/`.

The core problem is that the two halves live in different places. Allocation
counts only exist on the final TIR, after mono, defun, inlining, TRMC and
Perceus. Measures, `@[decreases]` metrics and the SMT encoding live in
`lib/refinecheck/`, which works on the source-level program. Two options:

1. **Extract a recurrence from the TIR and map it back.** For each recursive
   SCC, phase 1.5 already computes the per-activation cost and the recursive call
   sites. Map each call's arguments back to source parameters and emit a
   verification condition like
   `bound(xs) >= activation + sum over recursive calls of bound(arg)`, using the
   source-level facts (`xs = Cons(h, t)` gives `len(t) = len(xs) - 1`), with the
   function's `@[decreases]` metric as the induction. The missing piece is the
   TIR-to-source variable map: provenance is per function today, and inlining
   and defunctionalization rename freely.
2. **Count at source level and prove the compiler adds nothing.** Encode
   allocations per source constructor in the refinement VC (sound but loose,
   because reuse only lowers the real count). Then add a TIR-side check that every
   allocation the compiler introduced (closure records, boxed Floats, fresh
   `Nil`s) traces back to a source site that was counted. This needs node-level
   provenance on allocation sites only, which is narrower than option 1's map.

Option 2 looks more tractable, but neither is decided. What to measure first:
after phases 1 and 1.5 land, run `--report-contracts` over the stdlib parsers
and count how many functions are `per_call`-bounded but have no symbolic
statement anyone can check. That number decides whether phase 2 is worth its
estimated 4–8 weeks.
