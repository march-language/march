# Compiler: `pfn` unreachable from a sibling in the same NESTED module (OPEN, 2026-07-24)


- [ ] **A public `fn` in a nested `mod` cannot call a `pfn` declared beside it
  in that same module** — reported as `Module `X` does not export `y``.
  Top-level modules are unaffected. Since the project convention is exactly
  one top-level `mod` per file, nested modules are the normal way to have
  several modules, so this breaks ordinary private-helper code. Minimal repro:

  ```march
  mod Outer do
    mod Crypto do
      fn encode(x : Int) : Int do scramble(x) end
      pfn scramble(x : Int) : Int do x * 31 end
    end
  end
  -- Module `Crypto` does not export `scramble`.
  ```

  Found by the differential oracle: `examples/modules.march` (whose Part 3 is
  a deliberate pub-vs-`pfn` demonstration) now fails to typecheck at all, so
  it reports `INTERP_FAIL` and reddens the sweep. Suspected interaction
  between the 0.2.0 "Module does not export" diagnostic change and the
  intra-module qualification pass (`specs/2026-06-23-desugar-intra-module-qualification.md`)
  rewriting the bare call to a qualified one before the export check runs.
