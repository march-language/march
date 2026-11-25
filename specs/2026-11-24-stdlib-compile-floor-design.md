# Cutting the per-compile stdlib floor: lemma erasure, then a pre-mono prune

**Date:** 2026-11-24. **Status:** approved; Part 1 implemented (lemma erasure, single walk), Part 2 not started.
**Context:** `specs/plans/incremental-codegen-cas-plan.md` §3 (the ~2.4 s small-program floor that
per-unit codegen would not remove), and `specs/todos/2026-11-19-ocap-authority-mono-compile-cost.md`
(the measurement that pointed here).

## Why

Every compile, even of hello world, pays roughly 2.2 s before LLVM emission. Most of that is
work on stdlib code the program never uses. Shrinking that floor speeds up `forge test`,
`forge watch`, `--check`-adjacent builds and CI, and the incremental-compilation plan's B3–B5 can't
touch it. Success means hello world's time to the `cas-hash` stamp drops by roughly 0.6 s, the
emitted program is unchanged, and no new class of "the prune dropped something live" bug ships.

## Where the time goes (measured 2026-11-24)

Warm hello world (`needs IO.Console`), `--compile --opt 2 --timings`, current `main`, with
temporary stamps inside the driver's `lower` bucket:

| step | time |
|---|---|
| typecheck | ~1.15 s (out of scope here) |
| `erase_lemmas` over the whole program (`bin/main.ml:877`) | **0.43 s**, of which `Lemma_erase.erase_module` is 0.39 s and `Ghost.erase` 0.04 s |
| `Lower.lower_module` | 0.30 s |
| `Mono.monomorphize` (~4 480 fns in, ~7 100 out) | 0.24 s |
| fusion + defun | 0.13 s |
| early DCE onward (Perceus … cas-hash) | ~0.06 s |

The existing early DCE (`contract_pipeline.ml:189–221`) already prunes right after defun. That
is why the passes from Perceus onward cost almost nothing.

## Part 1: lemma erasure (a small change)

**Cause.** `Lemma_erase.drop_unreferenced` (`lib/desugar/lemma_erase.ml`) calls
`mentions fd.fn_name.txt whole` once per `@[lemma]` declaration. Each call walks every
expression of the whole program. The stdlib has 128 `@[lemma]` attributes, so the cost is
lemmas × program size.

**Change.** Walk the erased program once and collect the set of names any expression mentions,
each reduced to its last segment as `mentions` spells it. Then drop a lemma when its name isn't in
the set. `mentions` keeps its exact traversal (the same `children` cases, the same declaration
kinds), so the set is the union of what every `mentions n` call would have seen. That makes the
result identical by construction. `drop_unreferenced` has two callers (`erase_module_with` and
`Ghost.erase`, `ghost.ml:807`), and both get the fix.

**Proof it's unchanged:** `scripts/types-oracle.sh` and `scripts/ir-oracle.sh` show no diff
against a baseline from the merge base; the lemma and refinement suites
(`test_refine_lemma`, `test_refine_infer_lemma`, `refinecheck`) pass. A unit test pins
`drop_unreferenced` on a program where one lemma is mentioned only from inside a nested module
and another only from an impl method, the two traversal cases most likely to be missed.

**Expected:** about 0.35 s off every compile and every `--check` that erases lemmas.

## Part 2: prune unreachable functions before mono (a project)

### Goal and non-goals

- **Goal:** mono, fusion and defun see only functions reachable from the program's roots, instead
  of the whole prepended stdlib. Ceiling ~0.37 s on hello world.
- **Non-goals:** pruning before lowering (option 2 in the discussion; ceiling ~0.67 s, much
  riskier) and changing what the early or final DCE keep.
- **Anti-goal:** a prune that drops a function something still reaches. That is a link error at
  best and a silent behaviour change at worst, as with a missing interface impl. Correctness beats
  the last 10% of the saving.

### Approaches considered

1. **A reachability prune between lowering and mono (chosen).** It's a separate pass, so it's
   easy to switch off and to check. It reuses `Dce`'s reachability with one extra kind of edge.
2. **Make mono demand-driven** (seed only the roots, not every monomorphic function). It would
   save the same, but it changes mono's core worklist, which other passes and the HCR identity
   machinery depend on, and it can't be switched off independently. (Approach 1 still touches
   mono, but only at its edges: one extracted function for its implicit callees and one lookup
   helper. The worklist is unchanged.)
3. **Prune before lowering, on the AST.** Higher ceiling, but it duplicates reachability rules
   that lowering's tables, derives, actors and impl registration encode implicitly. Deferred.

### Design

A new step in `Contract_pipeline.run`, immediately before `Mono.monomorphize`. It sits after
TRMC and the wasm-island export marking, because those exports are roots.

- **Reachability:** BFS over `tm_fns` from the roots. A function's edges are its body's
  `Dce.free_vars` intersected with `tm_fns` names (which, before defun, also sees lambdas nested
  as `ELetRec`), plus **mono's implicit callees** for each free name (next bullet). Two functions
  can share a name before mono (`tir_verify.ml:34–35`), so a reached name follows the edges of
  **every** function with that name, not only the last one registered.
- **Mono's implicit callees: one function both use.** Mono calls functions the TIR doesn't
  name. It resolves interface methods to impls (`find_iface_impls`, `mono.ml:762, 945`, plus
  `$single_impl$` and return-position dispatch). It also rewrites `<`/`<=`/`>`/`>=` on tuples,
  ADTs and records into `__ord_lt`/`__ord_le`/`__ord_gt`/`__ord_ge` (`mono.ml:895–913`). A rule
  copied by hand into the prune would drift. Worse, the ord rewrite **falls back silently** when the
  helper is missing: `if Hashtbl.mem fn_table h then Some h else None` drops to the old comparison
  that returns 0 (issue #1172). So: factor mono's implicit-callee rules into one exported
  `Mono.implicit_callees : iface_methods -> name -> string list`. It's conservative across types:
  every impl of an interface, and all four ord helpers whenever an ordering operator appears. Mono's
  rewrite and the prune both call it.
- **Tripwire in mono.** The prune hands mono the set of names it removed. Every `fn_table` lookup in
  mono goes through one helper, and a lookup of a pruned name is an internal compiler error that
  names the caller and the callee. It's always on, not only under `--verify-tir`: it costs one set
  probe per miss. This turns a missed edge into a loud failure at the exact site, including the
  silent-fallback cases (the ord helpers). A missed edge can only surface as such a lookup, because a
  pruned function is gone from `fn_table` and can't come back.
- **Roots:** the early DCE's roots, computed the same way. That's `Dce.root_names` (main /
  `*.main`, setup, migrate stubs, `tm_exports`, `tm_tests`), plus `extra_roots`, plus
  `Dce.remote_ref_targets`, plus every function with a no-alloc policy, plus the `__rpc_stub`
  functions (currently pinned just after mono; the prune must keep them before that).
- **Gating:** exactly when the early DCE runs (`opt`, no hot reload, not JS), behind a new
  `Pass_switch` name `dce-pre-mono` so `--disable-pass` and `--bisect-pass` can turn it off.
  `dce_fail_open` is passed through as the early DCE passes it.
- **Order:** the step filters `tm_fns` and keeps the survivors' relative order. Mono's **output**
  order is its worklist order (`mono.ml:1591–1643`), and pruned functions used to enqueue
  specializations early, so nearly every program's function order will change. Names can change
  too: `Fusion.run_nativearr` numbers `$nafuse_lam<N>` with a counter that runs across the whole
  module (`fusion.ml:829–831`). **My call: accept reorders and that renumbering.** They change
  CAS keys once (a cache miss, not a fault), and hot reload, the one consumer of identity, is
  already excluded. One order dependence is real: the emitter's unqualified-name fallback keeps
  the first same-named function (`mono.ml:638–641`). So the canonicalising comparison below must
  also show that no unqualified-fallback resolution changed target.
- **Spike result** (throwaway, reverted): hello world reaches 35 of 4 479 functions before mono,
  and `tree_transform` 39 of 4 483, even with every impl of each interface it calls followed.

### The safety argument, and how it's checked

The prune is safe if no stage after it looks up a function it removed. Any pass after the early
DCE that calls a stdlib function by name would already break today if that function weren't
reachable after defun. So the only new exposure is between the prune and the early DCE: mono,
fusion and defun.

A check that "every survivor traces back to a pre-mono survivor" would be vacuous: a pruned
function can't survive, so it is always true. The guards are these instead:

- **The mono tripwire** (above): a lookup of a pruned name is an internal error.
- **Fusion and defun:** check them for calls they mint to existing stdlib functions by name. Any
  found goes into `implicit_callees` or gets its own tripwire. The plan's first task is that audit,
  with the evidence written down.
- **Verifier:** `Tir_verify` check 1 catches a reference to a missing function, apart from bare
  interface-method names and the emitter's unqualified fallback (`tir_verify.ml:17–27`). That's why
  the tripwire, not the verifier, is the primary guard.
- **Prove it red:** remove the ord-helper rule from `implicit_callees` and show the tripwire fires on
  a program comparing two tuples with `<`. Remove the interface rule and show it fires on any `show`
  program.
- **Emitted program:** `scripts/ir-oracle.sh` against a merge-base baseline, compared with
  canonicalisation in the style B1 used: sort functions by name, map `$nafuse_lam<N>` and SSA
  numbers to placeholders. Every program must be identical after canonicalisation. The comparison
  also checks that unqualified-fallback targets didn't change. `scripts/determinism-oracle.sh` must
  stay green. Snapshot goldens that change only by order or renumbering are regenerated, and the PR
  says so.
- **Suites:** full `scripts/run-tests.sh`, the oracle lane, `test_jit` (REPL fragments go through
  their own path; confirm it's untouched).
- **Timing:** `scripts/compile-time-bench.sh --corpus small` and the hello world probe, before and
  after, alternating the two builds.

### Left to the builder

- The full list of mono's implicit callees beyond interface impls and the ord helpers. Candidates:
  the `record_to_typename` and `enqueue_specialized_impl` paths, `$single_impl$`, and
  return-position dispatch. The tripwire catches any that are missed. `Dispatch_registry` is
  filled by mono, so it's empty before it.
- `ADefRef` is ignored by `Dce.free_vars`, but nothing produces it today
  (`tir_verify.ml:29–30`). If something starts to, the prune must follow it.
- Callers with no `iface_methods` (e.g. `test_snapshots.ml:381`): the prune follows no impl edges,
  and mono resolves none either, so they agree.
- The LSP calls `Contract_pipeline` with `dce_fail_open:false`. It gets the same prune, and its
  tests decide.

## Order of work

Part 1 lands alone first: a todo entry moved to `specs/progress/` and a CHANGELOG line ("compiles
are ~0.35 s faster"). Part 2 follows as its own PR.

## Implicit-callee audit (2026-11-24, plan Task 2)

Every place in mono, fusion and defun that introduces a call, or looks up a function, by a name
that is not a free variable of the body being rewritten. Kinds: (a) an interface impl reached
through `Tir_names.find_iface_impls`; (b) a fixed helper name; (c) a function the pass creates
itself, or a builtin (no edge needed).

| site | name or rule | kind |
|---|---|---|
| `mono.ml` `ensure_atom_fns` (~568) | a function used as a value; the name is a free variable | none (ordinary edge) |
| `mono.ml` `enqueue_specialized_impl` (~659) | the mangled impl name handed in by the resolvers below | (a) |
| `mono.ml` `iface_target` / `iface_impl_name` (~762) | impls of the called method, no `to_string` alias | (a) |
| `mono.ml` `return_position_single_impl` (~818) | the single impl of a return-dispatched method (`from_json`) | (a) |
| `mono.ml` `resolve_iface_value` (~832) | an interface method used as a value; impls of that free name | (a) |
| `mono.ml` `try_collision_dispatch` (~697) | every colliding impl of the method; the `__march_ifdispatch$…` sentinel is minted | (a) + (c) |
| `mono.ml` ord rewrite (~895–913) | `<` `<=` `>` `>=` on a tuple/ADT/record → `__ord_lt` `__ord_le` `__ord_gt` `__ord_ge`; **silent fallback when the helper is absent** | (b) |
| `mono.ml` unresolved-method branch (~945) | impls of the method, with `to_string` aliased to `show`, module prefixes stripped | (a) |
| `mono.ml` same branch (~1038) | `show` with no impl → `to_string` | (c) builtin |
| `mono.ml` name-collision branch (~1059) and the `ELetRec` twin (~1170–1208) | impls of a method that shares a name with a user function | (a) |
| `fusion.ml` list fusion | `$fused_<…>` functions it builds; calls to producers already named in the body | (c) |
| `fusion.ml` `run_nativearr` | `$nafuse_<…>` lambdas it builds; `native_<w>_arr_<op>`, `int_and`, `int_xor` | (c) builtins |
| `defun.ml` | apply functions and lifted closures it builds; its string lists are builtin-name sets | (c) |

Conclusions for Tasks 3 and 4:

- `implicit_callees iface_methods name` returns every impl symbol
  `Tir_names.find_iface_impls iface_methods name` lists (alias on, which is a superset of the
  alias-off lookups), plus all four `__ord_*` helpers when `name` is an ordering operator. The
  helpers' own bodies call `compare`, so the `Ord` impls follow from the first rule.
- There is no kind-(b) site outside mono, so fusion and defun need no tripwire of their own.
- The mono tripwire covers lookups at ~568, 659, 818, 907, 915 and 1170. The test at ~835 only
  asks whether a name is a user function; a pruned name there would silently change the answer,
  so it goes through the same helper.
