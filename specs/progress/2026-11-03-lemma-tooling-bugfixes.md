# Lemma tooling: three bugs and the interface-law leftovers (2026-11-03)

## Bugs found while building interface laws

- **A default method of an impl in another file was unbound at run time.**
  `Desugar.inject_defaults` runs per file, so `impl Sem(Int)` in `run.march` never got
  `Sem`'s default `twice` from `lib/alg.march`: the check passed, the interpreter said
  "unbound variable: twice". `Desugar.link_program` (replacing the direct
  `Interface_laws.expand_program` calls in `bin/main.ml` and the LSP) injects defaults
  program-wide by the interface's bare name, then expands laws. Same-file impls already had
  theirs, so it is a no-op for them. Test: `run_eval` `march_test_cli` "default method of
  an impl in another file" (interpreted and compiled print 42).
- **`use M.*` whose only use was an interface of `M` read as unused.** The tracker counted
  the functions and values the `use` rebinds, not interfaces, and an `impl` or a `when`
  constraint recorded no use. Now the `use` also tracks `M`'s interfaces, and `DImpl` (its
  interface and `when` constraints), function bounds and `when` guards call `record_use`.
  An interface-only module that nothing uses now warns; before, it had no tracker entry.
  Tests: `run_stdlib` "module system" (an impl, a `when`, an unused interface-only module).
- **"`k` is not a measure or known predicate" for a function over a user `Tree`.** The real
  cause: `OrderedMap` declares `Tree` too, the encoder marks the short name ambiguous
  (`Refine_encode.ambiguous_adts`), and the call is never resolved. Renamed, the lemma
  proves. The warning now names the clash (`Refine_check.conflated_param_type`,
  `Refine_encode.conflated_declarants`). The encoder fix is filed:
  `specs/todos/2026-11-03-reflect-type-name-clash-with-stdlib.md`. Test: `reflect-lemma`
  `conflated_type`.

## Interface-law leftovers

- **The compiled side of `--lemma-test`.** A generated lemma has no source text, so the
  harness skipped it. `Lemma_test.generated_parts` takes the law's theorem as written in
  the interface, with the generated lemma's (the impl's) parameter types, and `use`s the
  interface's module: in the compiled program the method calls dispatch to the real impl.
  Test: `iface_law_lemma_test` (`holds … compiled`, and `COMPILED-FALSE` under the
  perturbation).
- **Generated proofs for derived impls: nothing to generate.** `derive` produces impls of
  the built-in interfaces only (`Eq`, `Ord`, `Show`, `Hash`, `Json`), and those declare no
  laws; a user interface cannot be derived. `satisfy` impls are expanded before the laws, so
  they are checked like hand-written ones. Should the built-in interfaces get laws, a law
  over `Eq` meets D7 (`==` in the logic is structural). Closed, not deferred.
