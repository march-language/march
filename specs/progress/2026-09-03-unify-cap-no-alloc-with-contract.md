`[P3]` - [x] **Unify `cap no_alloc` with the `@[no_alloc]` contract.**

Filed 2026-09-03, when the contract landed
(`specs/progress/2026-09-03-allocation-contracts.md`).

March now has two allocation checks with different answers:

- `cap no_alloc` (`lib/refinecheck/no_alloc.ml`) is syntactic and
  pre-optimisation. It walks the AST of every function in a `cap no_alloc`
  module and rejects tuple, record, boxed-constructor and lambda expressions.
  It runs in every mode, the interpreter included.
- `@[no_alloc]` (`lib/tir/alloc_contract.ml`) is a per-function contract
  checked on the final TIR, after Perceus and escape analysis, and is
  transitive over callees. It has no answer at all under the interpreter or
  `--check`, which never lower to TIR.

So the cap rejects code the contract accepts (a constructor Perceus reuses in
place) and accepts code the contract rejects (a call into an allocating
callee). Both behaviours are defensible in isolation; having both under two
spellings is not.

The blocker is the interpreter: `cap no_alloc` is the only allocation check
available where no TIR exists, and dropping it would leave `forge run` with
nothing. Deciding this needs an answer to "what should an allocation
guarantee mean under the interpreter" — plausibly a third verdict
("unchecked in this mode") rather than either of today's two.

When it is resolved, `specs/lang/capabilities.md` and its `docs/` copy each
carry a paragraph describing the split that should collapse into one
description.

---

**Landed 2026-09-15.** Design: `specs/2026-09-15-refinement-remaining-designs.md` §C.
The "unchecked in this mode" verdict is what the interpreter got.

What changed:

- `Alloc_contract.collect` turns `cap no_alloc` into a module-wide contract:
  every function the module declares, recursively (nested modules, impl
  methods, actor handlers), is `Hard`, with `d_cap` recording the module so the
  diagnostic reads "`f` is in `cap no_alloc` module `M` but allocates". An
  explicit per-function form (`warn`/`assume`/`transient`) wins. Coverage is
  scoped to the file the `cap` line is in, so a cap at the top of the entry
  file does not claim the prelude and resolved imports the driver splices into
  the same top-level list, and derive-generated impl methods (synthetic
  `<none>` spans) are left out. Impl methods are keyed by `Lower`'s
  `Iface$Type.method` symbol; the module-qualified spelling `Lower` uses for a
  colliding type name is resolved against the lowered module
  (`Alloc_contract.resolve_names`, first thing in `Contract_pipeline.run`).
  Impl methods are displayed as `impl Iface(Type).method`.
- `Contract_pipeline.check_contracts` lowers and runs the build's post-lower
  pipeline with no emission, only when the user's decls carry an obligation
  (opt follows `--no-opt`, default on, like the LSP's `opt:true`). A lowering
  or pass exception becomes one `no_alloc_unchecked` warning per obligation.
  `march --check` (in `compile`) and `march check` (`run_check_cmd`) call it;
  `--check-json`, `--emit-core-ast` and `march caps` do not.
- The interpreter, `--jit` (both in `compile`), the REPL (`run_simple` and
  `run_tui`) and `march test` (`run_test_cmd`) give one `no_alloc_unchecked`
  hint. `lib/refinecheck/no_alloc.ml` and its two driver calls are deleted.
- CAS: the `--check` early cache is never consulted or written for sources
  that mention `no_alloc` (the existing `raise Exit` in `early_cas`, confirmed),
  and a run that printed a contract diagnostic is not cached either.

Measured `--check` cost (same box, load avg 13-15, compiler built at
origin/main `d39ab433` in a separate worktree vs this change, 7 runs each):
`specs/lang/types/accept/t55_cap_no_alloc_arithmetic.march` 0.37-0.43 s
before, 1.28-1.33 s after (about +0.9 s: lowering the stdlib-prepended program
plus the pipeline). cube_forge (`lib/cube_forge.march`, 72 `@[no_alloc]`
uses): 3.2-3.4 s before, 9.5-9.6 s after. A program with neither form is
unchanged.

cube_forge: `--check` before and after print byte-identical output (3039
lines, rc 0, zero `no_alloc` diagnostics), matching `--compile` at the base,
which reports no contract failure either (it stops at the link, which needs
forge's FFI flags). Non-vacuous: a copy of the lib with one added
`@[no_alloc] fn leak_probe(x : Int) : List(Int) do Cons(x, Nil) end` is
rejected by the new `--check`. `bench/steady_state_ring.march` compiles clean
with `--compile --opt 2` and `--check`; adding a tuple-returning function to
its `Hot` module is rejected.

Tests: the seven `No_alloc` verdict cases in `test/test_compiler.ml` are gone
(the two surface-syntax cases, `cap no_alloc` lexing and `cap verified`
parsing, stay). `test/test_alloc_contract.ml` gains ten cap-driven cases
(collect marks the module; allocating callee rejected; reused constructor
accepted, compiled output matches the interpreter; tuple rejected; arithmetic
accepted; nested module and impl method covered; explicit `warn` opts out;
interpreter hints exactly once; `march check` judges the cap; an unlowerable
program is reported unchecked, not rejected), and the two "ignores" tests are
flipped to "`--check` judges the attribute" and "interpreter hints once and
runs", plus "`--check` without contracts is silent". t43 keeps rejecting (its
EXPECT-ERROR now pins the contract's message) and t55 keeps accepting.

RED evidence: with the cap never marking functions in `collect`, the collect,
allocating-callee, tuple, nested/impl, interpreter-hint and `march check` cases
fail (6) and t43 is accepted; with both check-path calls given no obligations,
"`--check` judges the attribute", the `--check` half of the callee and tuple
cases, `march check` and the unlowerable case fail (5). Both restored.

Found while landing: a pattern `Tree.Leaf(n)` on a nested module's
`type T = Leaf(Int) | Node(T, T)`, matched from outside the module,
miscompiles (compiled `panic: non-exhaustive pattern match`, the checker
reporting a missing `LWWRegister`) with or without the cap; the interpreter
prints the right answer. The cap test uses other constructor names.
