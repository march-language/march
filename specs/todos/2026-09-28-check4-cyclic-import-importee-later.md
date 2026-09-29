# Check 4 is still skipped for mutually importing siblings when the importee is declared later

**Filed:** 2026-09-28. This is the residual of
`specs/progress/2026-09-28-check4-importee-declared-later.md`.

The module sort now adds an edge for `import Sibling`, but only when that
edge closes no cycle. That keeps the existing order of mutually importing
modules (`test_cyclic_modules_still_enforce`). In a cycle, though, one module
is always checked before the other, and when the one checked first imports
the later one, Check 4 has no capabilities to look up for it:

```march
mod CapOrdRoot do
  mod CapOrdProbeAlpha do
    import CapOrdProbeBeta
    fn alpha_pure(x : Int) : Int do x + 1 end
    fn alpha_uses(m : String) do capordprobebeta_noisy(m) end
  end
  mod CapOrdProbeBeta do
    needs IO.Console
    import CapOrdProbeAlpha
    fn capordprobebeta_noisy(m : String) do print(m) end
  end
  fn main() : Int do 0 end
end
```

`march --check` (2026-09-28) reports two ``Module ... not found`` errors and an
unused-import warning, but no `imports CapOrdProbeBeta which requires
Cap(IO.Console)` error. Swapping the two modules makes it fire.

It is masked today, because the same-file `import Sibling` form also reports
``Module `X` not found``, so this program does not compile anyway.

## Direction

Run Check 4 for an import whose target had not been analysed yet after the
whole module run has been checked. The catch: the importer's bare references
to the not-yet-checked sibling filed no import-tracker entry, so the demand-driven set is
unavailable. A deferred check would fall back to the sibling's whole
capability set, which is stricter than the other order for a pure-only
reference. Decide whether that asymmetry is acceptable (fail-closed) or
whether the importer must be re-checked.

## Acceptance

- The program above reports the Check-4 error in both orders.
- `test_cyclic_modules_still_enforce` and
  `test_check4_importee_declared_later` still pass.
