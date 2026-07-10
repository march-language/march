# Debug report: same-module constructor precedence

Branch: `same-module-precedence` (worktree), based on main @ `a3d7ebfa`.

## Symptom

In the `bastion` package, compiling `lib/islands/island_socket.march` (module
`IslandSocket`) fails ~15× with `expected \`Descriptor\` but got \`IslandHandler\``
(and the mirror `expected \`IslandHandler\` but got \`Descriptor\`` in
`islands.march`) at the `Registry(Cons(IslandHandler(...), handlers))` sites.

- `IslandSocket` defines `type Registry = Registry(List(IslandHandler))` and does
  **not** import `Islands`.
- Sibling `Islands` (same dir/package) defines a **different**
  `type Registry = Registry(List(Descriptor))`.

An unqualified reference to `Registry` inside `IslandSocket` was resolving to the
sibling `Islands.Registry` (element type `Descriptor`) instead of its own.

## Root cause (confirmed by instrumentation)

March keys **nominal types by bare name**: `env.types` stores only an arity, so
`IslandSocket.Registry` and `Islands.Registry` are the *same* `TCon("Registry")`
at the type level. The two types are distinguishable **only** by their
constructors' argument types (`List(IslandHandler)` vs `List(Descriptor)`).

Constructors live in `env.ctors : ctor_info list StrMap.t`, keyed by bare name.
When two sibling modules define a same-named constructor, the bare key
`"Registry"` holds a **list of both candidates**, and `add_ctor` **prepends**
(`ci :: lst`). `lookup_ctor` returns the **head** ("most-recently-registered
wins"). This head is a single **global** winner shared by *every* module,
independent of which module's body is being checked.

d95fe942 (`order-independent multi-module name resolution`) seeds every module's
bare constructor keys up front in Pass-1 prebind. A side effect: when a module's
own `DType` is re-processed in Pass-2, `add_ctor` finds the sibling's identical-keyed
entry already present and the head is left as whatever prebind/export order
produced — so a module's own definition is **not** promoted to the head.

The two constructor-resolution sites that pick the winner both ignored the
current module:

- **Expression** `Ast.ECon` (typecheck.ml ~3972): used `lookup_ctor name env`
  — the raw head. This is where `Registry(Cons(IslandHandler(...)))` picked the
  wrong `Registry`, giving the arg type `List(Descriptor)` and the
  `expected Descriptor but got IslandHandler` unification failure.
- **Pattern** `Ast.PatCon` (typecheck.ml ~2816): preferred the expected/scrutinee
  type via `lookup_ctor_in_type name type_name env` — but since *both* candidates
  carry the bare `ci_type = "Registry"`, `List.find_opt` still returns the head.

Instrumentation confirmed the shared global list: in **both** `IslandSocket` and
`Islands` bodies the `"Registry"` ctor list was
`[Registry(List(IslandHandler)); Registry(List(Descriptor))]` — head fixed for
everyone. The module whose ctor sits at the head resolves correctly; the other
(and any consumer) gets the wrong element type. This exactly explains the
symmetric `Descriptor`/`IslandHandler` errors in both files.

This required the full package (14 lib dirs) to reproduce: a bare 2-module case
only collides once `MARCH_LIB_PATH` is set (as forge always does) so both
modules' bodies are checked against the shared prebound env.

## Why this is a compiler bug, not a source problem

`IslandSocket` defines `Registry` locally and does not import `Islands`. A
module's own top-level definition must outrank a same-named definition from a
sibling it does not even import. Pre-d95fe942 this happened to work by
resolution ordering; d95fe942's order-independence removed that accidental win
without establishing explicit same-module precedence.

## Fix (minimal)

`lib/typecheck/typecheck.ml`. Prebind already seeds a module-qualified key
`Module.Ctor` (with the bare `ci_type`) for every module's public constructors,
present in every module's env. New helper:

```ocaml
let lookup_ctor_same_module name env =
  if env.current_module = "" || String.contains name '.' then None
  else lookup_ctor (env.current_module ^ "." ^ name) env
```

For an **unqualified** constructor reference, both the expression (`ECon`) and
pattern (`PatCon`) sites now consult `lookup_ctor_same_module` **first**, then
fall back to the existing resolution chain.

- If the current module defines the constructor, `current_module ^ "." ^ name`
  is a key and its own candidate wins — same-module precedence.
- If it does not (imported names, or a genuine cross-module bare reference whose
  `current_module` prefix does not match the definer, e.g. d95fe942's
  Core/Facade/Worker cycle), the key is absent and behavior is unchanged —
  preserving imports, qualified refs, and d95fe942's order-independence.

The returned `ci_type` is the bare type name (as prebind seeds it), so nominal
types and codegen keys are unaffected.

## Test evidence

### Regression test (in suite)
`test/test_stdlib_suite.ml`: `test_tc_same_module_ctor_precedence`
(module-system group, alongside the d95fe942 order-independence tests). Two
sibling modules `AMod`/`BMod` each define a distinct `type Reg` with different
element types and construct/retrieve via bare `Reg`. **Fails pre-fix**
(`expected Bar but got Foo`), **passes post-fix**. Verified by stash/rebuild.
Module-system group: `same-module ctor precedence [OK]`, 56 tests run.

### march suite (`dune runtest --root .`)
No new failures. stdlib suite 808 tests pass (incl. the new test);
run_compiler/run_eval/run_codegen all green. Pre-existing failures only:
- LSP quickfixes (code-actions/match-stubs/annotation), refactor bundles,
  `basic` record-literal formatter, doctests needing `timeout`/`gtimeout`.
- QCheck `parse+typecheck 2` and `type soundness + eval 0` — **confirmed
  identical on the pre-fix baseline** (stash + same seed 401167503).
- forge `check: qualified-call cycle` — shells out to the *installed* `march`
  binary, independent of this compiler change; the same 3-file scenario resolves
  cleanly with the freshly-built compiler.
- test_scheduler_runner / test_scheduler_mt_runner wedge (killed per known issue).

### Minimal fixture
Two files `a_mod.march` / `b_mod.march` (sibling modules, colliding `Reg`,
neither imports the other), run with `MARCH_LIB_PATH` set: **fails pre-fix**
(`expected Bar but got Foo` in both entries), **compiles clean post-fix**.

### Real instance (bastion)
After `dune build @install && dune install` of this toolchain, then
`forge clean && forge build` in `/Users/80197052/code/bastion`:
- `grep -c "expected .Descriptor"` → **0** (was ~15)
- `grep -c "expected .IslandHandler"` → **0**
- island_socket.march errors → **0**

Remaining bastion errors are the pre-existing unrelated WIP (`Unknown module
\`Pool\``, `Unknown module \`Config\``) noted in the task.
