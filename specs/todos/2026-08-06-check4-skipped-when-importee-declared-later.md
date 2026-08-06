# Check 4 is skipped when a same-file sibling module is `import`ed before it is declared

**Filed:** 2026-08-06, found while building the cyclic-module witness for
demand-driven Check 4 propagation
(`specs/progress/2026-08-06-demand-driven-cap-propagation.md`).

**PRE-EXISTING — not a regression from that branch.** Reproduced identically on
a binary built at the base commit `fd73127b`. See the matrix below.

**Distinct from** `2026-08-06-record-fn-caps-misses-dlet-and-methods.md`. That
one is a `caps_of_name` lookup miss — the closure table is incomplete. This one
is a processing-order gap: the imported module has not been analyzed at all when
Check 4 runs, so there is nothing to look up.

## Observation

For **same-file nested sibling modules**, `import Sibling` (bare `UseAll`)
followed by bare-name references does **not** fire Check 4 when `Sibling` is
declared *after* the importing module. Declared *before*, it fires.

The qualified form — `use Sibling` + `Sibling.f(...)` — fires in **both**
orders, so this is specific to the bare-import route.

## Reproduction

Two nested siblings in one file. `CapOrdProbeBeta` declares `needs IO.Console`;
`CapOrdProbeAlpha` declares nothing and references its impure function, so
Check 4 owes an error.

```march
mod CapOrdRoot do
  mod CapOrdProbeAlpha do
    import CapOrdProbeBeta                        -- swap for `use CapOrdProbeBeta`
    fn alpha_uses(m) do capordprobebeta_noisy(m) end
  end
  mod CapOrdProbeBeta do                          -- declared AFTER the importer
    needs IO.Console
    fn capordprobebeta_noisy(m) do print(m) end
  end
  fn main() : Int do 0 end
end
```

Count of `` `...` which requires `Cap(IO.Console)` `` diagnostics from
`march --check`:

| form | importee declared | base `fd73127b` | with demand-driven Check 4 |
|---|---|---|---|
| `import` (bare) | **after** the importer | **0** | **0** |
| `import` (bare) | before the importer | 1 | 1 |
| `use` (qualified) | after the importer | 1 | 1 |
| `use` (qualified) | before the importer | 1 | 1 |

Identical on both binaries in all four rows. The demand-driven change is
orthogonal to this.

## Likely mechanism — HYPOTHESIS, not traced to a failing line

Nothing gives the module topological sort an edge for a `DUse` + bare-name
reference:

- `module_refs_in_decls` (`lib/typecheck/typecheck.ml`) collects only
  **qualified** `Mod.x` references. That is why the `use Sibling` +
  `Sibling.f` form works in both orders — the qualified reference *is* an edge.
- `unqualified_module_deps` (same file) collects only names resolved through
  `type_owner` / `ctor_owner` — types and constructors, not functions.
- `Ast.DUse` itself appears in neither walk.

So with `import Sibling` and bare calls the sort sees no dependency, keeps
declaration order, and `check_decl` reaches the importer first. At that point
the sibling's members are not yet in `env.vars`, so `UseAll`'s `matching` is
empty, no import-tracker entry is filed, and `env.module_caps` has no entry for
the sibling either — Check 4's lookup misses and it silently does nothing.

Consistent with the observed matrix, but **not** confirmed by instrumenting the
sort. Someone picking this up should verify with `MARCH_DEBUG_ORDER=1` (the
existing debug hook in the ordering code) before acting on it.

## Why it matters

The declared capability set is supposed to be a hard floor for capability-passing
code — Check 4 is an ERROR, not a warning, precisely because of that. Here it is
fail-open, and invisible to anyone who happens to write their modules in the
other order: the same two modules, same code, reordered, enforce differently.

**Current mitigating factor, and why it should not be relied on:** the affected
configuration also emits a separate ``Module `X` not found (looked for
`x.march` in the source directory)`` error, exit 1, so it does not compile clean
today. But that diagnostic appears in *both* orders — including every row where
Check 4 *does* fire — so it is not a signal that anything was skipped. If that
(unrelated, and arguably wrong) same-file-sibling resolution diagnostic is ever
fixed, this capability gap becomes completely silent.

Not reproduced in the multi-file `MARCH_LIB_PATH` case: a two-module lib where
the importer sorts alphabetically first still fired Check 4 correctly, so the
registry's on-demand load path appears unaffected. The scope above is same-file
nested siblings.

## Scope note

**Do not fix as part of the demand-driven propagation work.** This is an
ordering/resolution question that may interact with the topological sort's
hard/soft-edge design (`unqualified_module_deps` + the Kahn recomputation) and
deserves its own design pass. Adding a `DUse` edge would also change module
processing order globally, which is not a strictly-loosening change.

## Pointer

`test/test_compiler.ml`, `test_cyclic_modules_still_enforce` — its comment
records the measured order-sensitivity and points here. That test deliberately
does **not** assert this behavior: asserting it would pin a bug as correct.
