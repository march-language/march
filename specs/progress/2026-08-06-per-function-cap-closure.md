# Per-function transitive capability closure (analysis only)

**Landed:** 2026-08-06. Step 2 of
`specs/2026-08-06-per-function-capability-closure-design.md`.

## What landed

```
caps(f) = own(f) ∪ ⋃ { caps(g) | g ∈ refs(f) }
```

computed to fixpoint and exposed as

```ocaml
Typecheck.fn_transitive_capability_closures : env -> (string * string list) list
```

sorted by key, mirroring `fn_own_capability_closures`.

**Nothing consumes it yet.** No diagnostic, no propagation, no CLI output reads
it, so no observable behavior changed and there is no CHANGELOG entry. Step 3
of the design wires it into import propagation.

## Edge basis: `free_vars_expr`, not the call-walker

`env.fn_refs : (string, string list) Hashtbl.t` records, per function, every
name its body (and its clause guards) references, collected with
`free_vars_expr`.

Using `March_ast.Calls` here would have been **fail-open**: it collects only
`EApp` callees, so a function passed as a *value* — `apply_to(noisy, m)` —
contributes no edge and its capabilities silently vanish from the caller's
closure. `test_transitive_cap_through_value_reference` is the witness: `shout`
*calls* only the pure `apply_to`; `IO.Console` arrives solely because `noisy`
is mentioned as an argument.

`free_vars_expr` also respects shadowing, so an inner binding that happens to
share a top-level function's name does not manufacture a spurious edge.

## Built on `own_cap_closures`, not `cap_closures`

`cap_closures` folds in `module_wide_caps`, which itself contains the
module-granularly propagated import caps this work exists to remove. Deriving
the closure from it would be circular *and* would reintroduce the
over-approximation (importing `List` to call `map` inheriting `pmap`'s
`IO.Spawn`). `own_cap_closures` is the module-wide-free projection, and is what
the fixpoint seeds from.

## Observed key shapes

Verified against the existing cap-closure tests and `bin/main.ml`'s
`own_caps_of_this_module`, not assumed:

- a top-level function of the **entry** module is keyed **bare**
  (`"public_reader"`) — `check_module_core` passes `~cap_qname_prefix:""` for
  it, mirroring TIR's unwrapping of the entry module;
- a nested `DMod`'s function is keyed by its dotted path relative to the entry
  (`"Lib.probe"`, `"Lib.Sub.f"`);
- an actor handler is keyed `"<ActorBareName>_<Msg>"`.

Reference names arrive already **desugared**: `qualify_module_refs` rewrites a
bare intra-module reference inside a nested `DMod` to the dotted form
(`"Lib.touch"`), and desugar's `EField` arm flattens `A.B.c` into a single
dotted `EVar` — while the entry module's own top-level bodies keep bare names.
So `resolve` tries the owner-module-prefixed form first, then the raw name.

## Termination bug found and fixed during implementation

`Cap_lattice.normalize` drops caps *subsumed* by another, but its filter skips
the `other <> c` case, so it does **not** drop an exact duplicate. Without a
`List.sort_uniq` before it, `own @ from_refs` grew by one copy of each
already-held cap on every sweep, never compared equal to the previous value,
and the fixpoint spun forever — observed as a hang on the very first test case.

## Load-bearing evidence (Step 7 mutation)

With the `from_refs` term disabled (`merged = normalize own`):

| Case | Result |
|---|---|
| cap via a private helper | **FAIL** |
| pure sibling unaffected (REJECT control) | pass |
| cap through a value reference | **FAIL** |
| mutual-recursion fixpoint | **FAIL** |
| dotted nested-module reference | **FAIL** |
| union == module level (anti-drift) | pass |

The anti-drift case passing under the mutation is expected and worth
recording: it is a *no-loss* check (the union over a module's functions must
still equal the module-level answer), not a transitivity check. It catches an
over-approximating or under-reporting closure; the four accept cases catch a
missing transitive term. Both halves are needed.

## Known coverage gap (inherited, not introduced)

`record_fn_caps` — and therefore `record_fn_refs`, which is recorded at exactly
its call sites — covers `DFn` (signature + body) and actor handlers, and
records `IO.Foreign` for `extern` functions. It does **not** cover:

- **`DLet` bodies** — the body scan produces Check 1b diagnostics for them but
  calls no `record_fn_caps`, so a top-level binding has no `own(...)` entry;
- **interface methods (`DInterface`) and impl methods (`DImpl`)** — not walked
  at all by `check_module_needs`.

A reference edge pointing at one of those contributes nothing, which is
fail-open. Harmless while nothing consumes the table; **must be closed before
this closure is made load-bearing for enforcement** (design doc's open
question). Recorded in the accessor's doc comment as well.

## Files

- `lib/typecheck/typecheck.ml` — `env.fn_refs` field + init, `record_fn_refs`
  and its two call sites, `fn_transitive_capability_closures`.
- `test/test_compiler.ml` — the `cap-closure` suite (6 cases).
