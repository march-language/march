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
keyed by the **accumulated, entry-unwrapped module path**. New helper:

```ocaml
let lookup_ctor_same_module name env =
  let self = if env.cap_qual_prefix <> "" then env.cap_qual_prefix
             else env.current_module in
  if self = "" || String.contains name '.' then None
  else lookup_ctor (self ^ "." ^ name) env
```

**Module identity (Finding 2).** The prebind key is the accumulated path with
the TIR entry-unwrapping convention: a top-level sibling `Islands` seeds
`Islands.Registry`; a module one level under the unwrapped entry seeds
`Inner.Registry`; a module under a non-entry wrapper seeds `Outer.Inner.Registry`.
`cap_qual_prefix` tracks exactly that accumulated path (empty at the unwrapped
entry, where prebind instead uses the entry name held by `current_module`), so
`cap_qual_prefix`-else-`current_module` matches the key for **top-level,
dotted-single-decl, AND arbitrarily nested** modules. (The first cut used the
leaf `current_module`, which only matches for top-level / entry+1 nesting; the
3-level `Top>Outer>Inner` case needs the accumulated path.)

If the current module does not define the constructor, the key is absent and we
fall through to the existing chain — preserving imports, qualified refs, and
d95fe942's order-independence for genuine cross-module bare references whose
module path does not match the definer's (e.g. the Core/Facade/Worker cycle).

**Resolution precedence at each site.**

- **Expression `ECon`** (no expected-type context): `lookup_ctor_same_module`
  first, then the raw head / qualified resolution.
- **Pattern `PatCon`** (a scrutinee type may be known — **Finding 1**): a KNOWN
  scrutinee type that *uniquely* identifies the constructor wins first, via the
  new `lookup_ctor_in_type_unique` (returns a match only when exactly one
  candidate's `ci_type` equals the expected type name). This lets a module that
  locally defines `Local = Reg(Int)` still match an imported `Remote = Reg(String)`
  value via bare `Reg(s)` — the differently-named expected type selects `Remote`.
  Only when the expected type name is itself *shared* by several candidates (two
  sibling `Registry` types — so `lookup_ctor_in_type_unique` is ambiguous → `None`)
  does same-module precedence take over, then the legacy order-dependent
  expected-type head, then the raw head.

The returned `ci_type` is the bare type name (as prebind seeds it), so nominal
types and codegen keys are unaffected.

## Test evidence

### Regression tests (in suite)
`test/test_stdlib_suite.ml`, module-system group (alongside the d95fe942
order-independence tests). All three **pass post-fix**; each **fails on the
relevant baseline**:
- `test_tc_same_module_ctor_precedence` — two sibling `AMod`/`BMod` with distinct
  same-named `Reg`. Fails at the base a3d7ebfa (`expected Bar but got Foo`).
- `test_tc_expected_type_beats_same_module` (Finding 1) — `Consumer` locally
  defines `Local = Reg(Int)` and pattern-matches an imported `RemoteMod.Remote =
  Reg(String)` via bare `Reg(s)` with the scrutinee type annotated. Fails at the
  first-cut same-module-first commit 5a7566dc (`expected Local but got Remote` /
  `expected String but got Int`).
- `test_tc_same_module_ctor_precedence_nested` (Finding 2) — `Inner`/`Sib` two
  levels deep under a non-entry `Outer`. Fails at 5a7566dc (leaf `current_module`
  misses the `Outer.Inner.Reg` key → 3 mismatches).

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

---

## Follow-up 2: opaque/ptype gap (commit after d78af16a)

### Symptom
Building forgepm's full dependency stack (`forge test`, which invokes `march
check`/compile with **all** packages' modules loaded together) surfaced 11
errors the earlier fix did not cover:
- 6× `Constructor \`Gate\` expects 5 argument(s) but I got 3` + 4× the pattern
  variant, in `bastion/lib/security/gate.march` (`mod Gate`, `opaque type Gate =
  Gate(3 args)`), where its own `Gate(...)` resolved to depot's unrelated
  `mod Depot.Gate`'s regular `type Gate = Gate(5 args)`.
- 1× `I cannot find \`DbConstraint\`` at `depot/lib/data/depot_gate.march:56`,
  where a `type Gate` field references the same file's `ptype DbConstraint`.

Reproduces only when a **consumer** is the entry (e.g. `--check
bastion/lib/testing/test_auth.march` with the full forgepm+bastion+depot+
march_doc lib path); with `gate.march` itself as the entry its own Pass-2 add
masks the gap.

### Root cause (confirmed by instrumentation)
`opaque type` parses to a `DType` with **Public** type visibility but **Private
constructor** variants; `ptype` parses to a **Private** `DType`.

The reported failure is NOT that opaque ctors are unseeded — prebind's
module-qualified `qctor` (`Module.Ctor`) is seeded unconditionally, so
`Gate.Gate` *is* present. The bug is a **key-namespace collision**:
`lookup_ctor_same_module` looks up `self ^ "." ^ name` = `Gate.Gate`, but that
same string is ALSO prebind's `Type.Ctor` disambiguation key. Depot's regular
`type Gate` (in `mod Depot.Gate`) seeds the disambiguation key `Gate.Gate` (type
`Gate` + ctor `Gate`) with its 5-arg ctor. So the `Gate.Gate` bucket holds BOTH
bastion's module-qualified opaque ctor (3-arg) and depot's type-qualified
regular ctor (5-arg); `lookup_ctor` returned the order-dependent head (depot's
5-arg). Instrumentation at the `Gate` ECon site with `test_auth` as entry:
`cm=Gate cqp=Gate Gate.Gate present=true same_module=5 bare_head_args=3` — the
bare head is correctly bastion's 3-arg; only the polluted qualified key is wrong.

The `DbConstraint` "cannot find" is **cascading**, not a distinct mechanism:
the fix touches only constructor resolution (`lookup_ctor_same_module`), yet
`DbConstraint` (a *type* error) also cleared — depot_gate's module check simply
recovers once the `Gate` constructor collision no longer corrupts it. `ptype`
therefore needs no separate prebind change (a standalone `ptype` same-module
collision fixture resolves correctly already: its private-type ctor is added to
the bare key by its own Pass-2 check and wins the head).

### Fix (minimal)
`lib/typecheck/typecheck.ml`, `lookup_ctor_same_module`: only trust the
`Module.Ctor` key when it resolves to a **single** candidate; on an ambiguous
(polluted) bucket, return `None` and fall through. For an opaque type the module's
own bare-`Ctor` head (set by its Pass-2 check, never displaced because the
private ctor is not prebind-seeded into the bare key) is the correct fallback.
The original clean cases (`IslandSocket.Registry`, nested `Outer.Inner.Reg`) have
a single candidate and are unaffected.

```ocaml
else match StrMap.find_opt (self ^ "." ^ name) env.ctors with
  | Some [ci] -> Some ci
  | _ -> None
```

### Test evidence
- New `test_tc_same_module_opaque_ctor_precedence` (module-system group): `mod
  Gate` opaque `type Gate(3)` + sibling `OtherPkg` regular `type Gate(5)`,
  ordered so OtherPkg's `Type.Ctor` form heads the `Gate.Gate` bucket. **Fails
  pre-fix** (2× "expects 5 argument(s)" — construction + pattern), passes
  post-fix. Original 3 same-module tests still pass (module group 59 tests).
- Authoritative repro: `rm -rf ~/.cache/march && forge test` in forgepm →
  `grep -cE "expects 5 argument|cannot find .DbConstraint"` = **0** (was 11).
  forgepm now COMPILES cleanly; the remaining `forge test` exit 1 is 2 unrelated
  runtime UI-test assertion failures (`SearchIsland.render_results`,
  `Pages.home_page` — search-form/link content), plus benign `LenMin`/`LenMax`
  "defined by multiple types" hints. Out of scope (a further layer, per task).
- march suite `dune runtest --root .`: no new failures vs baseline.
