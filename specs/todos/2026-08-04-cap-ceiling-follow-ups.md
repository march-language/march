# `--cap-strict` capability ceiling — follow-ups

Shipped 2026-08-04: `--cap-strict` checks each module's attributed capability
use against its own `needs`. See
`specs/progress/2026-08-04-cap-ceiling-strict.md`.

- [ ] **`println` does not trip Check 1b in a plain function body, but
  `file_exists` does.** Found while sizing the ceiling work, NOT root-caused.
  Both are in `builtin_cap_table`, both are collected by `calls_in_expr`
  (which does descend into match arms), `declared_needs` is empty in both
  cases, and no `IO.Console` exemption exists anywhere in `typecheck.ml`.

  Measured, same module and same shape:

  ```march
  mod P3 do
    fn emit(s : String) : () do println(s) end          -- NO warning
    fn touch(p : String) : Bool do
      match file_exists(p) do true -> true  false -> false end   -- warns
    end
  end
  ```

  A test at `test/test_compiler.ml:3291` asserts `IO.Console` DOES warn for
  actor handler bodies, so the diagnostic is not globally suppressed. This
  inconsistency is invisible under `--cap-strict` (which derives from emitted
  code and correctly requires `needs IO.Console`), but it means the default
  build's warnings are not a reliable preview of what strict will demand.

- [ ] **`ECallPtr`'s callee is still not statically known.** The atom scan now
  attributes a builtin handed out as a value, which closed the common case,
  but a capability reached only through a genuinely dynamic dispatch — a
  closure selected at runtime from a table — has no owner. `Cap_ceiling`
  reports these as `Unattributed` and fails closed.

  Not yet verified: whether any construct in real March code actually produces
  an `Unattributed` row today. The unit test covers the rule; there is no
  end-to-end witness, so that path is currently exercised by construction
  only. Worth finding a real witness or establishing that none exists.

- [ ] **`--cap-strict` is compile-only, not available to `--check`.** The
  check needs TIR, and `--check` stops after typecheck, so editors and
  `forge check` cannot preview ceiling violations. Either lower far enough
  under a flag, or accept that strict is a build gate and say so in the docs.

- [ ] **No `forge cap inspect --strict`.** The artifact carries per-module
  attribution markers and the compiler knows each module's `needs`, but the
  binary does not carry the declarations, so the ceiling cannot currently be
  re-checked from an artifact alone. Embedding declared needs per module in
  the manifest blob would let a consumer verify a ceiling on a binary they did
  not build.

- [ ] **Migration story.** `--cap-strict` rejects most existing code, including
  this repo's own `examples/`, because `needs IO.Console` is almost never
  declared. The existing `warning_with_fix`/`FInsert` machinery already emits
  the right autofix for Check 1b; wiring a `forge fix`-style bulk apply driven
  by ceiling violations would make adoption mechanical rather than manual.

- [ ] **Per-dependency budgets in `forge.toml`** (the original motivation) are
  now unblocked: attribution names the module and the ceiling check proves the
  module stays inside its declaration. What remains is the module→package
  mapping, which `forge/lib/cap_package.ml` already computes from source.
