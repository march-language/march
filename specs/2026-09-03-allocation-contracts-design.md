# Allocation contracts (`@[no_alloc]`) — design

## Scope

Add a per-function contract, `@[no_alloc]`, that the compiler checks on the
final TIR: the function, and everything it calls, performs no heap allocation
at runtime. The check runs after Perceus and escape analysis, so a function
whose constructors were all reused in place (FBIP) or stack-promoted passes.
The contract surfaces in three places: the compiler, the language server, and
`forge fix`, which can insert the attribute on functions the compiler has
verified.

This is the first of five items borrowed from OxCaml's design (see the
roadmap section at the end). It does not add `@[in_place]`, does not change
`cap no_alloc`, and does not add any new TIR node or representation.

Origin: OxCaml's `[@zero_alloc]` checker. March's version is simpler because
March compiles whole programs: transitivity is computed, not annotated.

## Surface syntax

Three forms, parsed by the existing `fn_attr` rule and stored in
`Ast.fn_def.fn_attrs` as the strings `no_alloc`, `no_alloc:warn`, and
`no_alloc:assume`, matching the `vectorize` / `vectorize:warn` convention.

```march
@[no_alloc]
fn inc_leaves(t : Tree) : Tree do ... end      -- hard error on violation

@[no_alloc(warn)]
fn hot_path(xs : List(Int)) : Int do ... end   -- warning on violation

@[no_alloc(assume)]
fn wrap_c(buf : Buffer) : Int do ... end       -- never checked; trusted by callers
```

The attribute goes on `fn` and `pfn` declarations. It is rejected with a
parse-time error on actors, types, and `extern` declarations. `assume` is the
only form that changes how *callers* are checked; `warn` and the bare form
differ only in severity.

There is no `opt` or `strict` payload. See "Build configuration" for why.

## What counts as an allocation

The checker walks the final TIR of each function immediately before LLVM
emission. On the final TIR, the following are allocations:

| TIR node | Verdict |
|---|---|
| `EAlloc` | allocation |
| `EAllocHole (None, ...)` | allocation (TRMC cell with no reuse token) |
| `ETuple`, `ERecord`, `EUpdate` | allocation |
| Closure struct construction (`EAlloc` of a `TDClosure` type) | allocation |
| `EApp` to a builtin in the allocating set | allocation |
| `EApp` to a user function in the allocating set (see Transitivity) | allocation |
| `ECallPtr` (unknown closure) | allocation unless the enclosing function is `assume` |
| `EApp` to an `extern` | allocation unless the enclosing function is `assume` |
| `EReuse` | not an allocation |
| `EAllocHole (Some _, ...)` | not an allocation (reuses when unique, same discipline as `EReuse`) |
| `EStackAlloc` | not an allocation |
| Nullary constructors, scalars, atoms, RC ops, `ESetField`, `EFree` | not an allocation |

The allocating-builtin set is a total function over the closed
`Builtin_name.t` variant, so adding a builtin without classifying it fails to
compile the compiler. Classification is by what the runtime does: string
concatenation, list and map construction, `to_string` conversions, float
boxing helpers, and every builtin that returns a fresh heap value allocate;
comparisons, arithmetic, field reads, and predicates do not. The first
version of the table is conservative: when a builtin's runtime behaviour is
not obvious from its C implementation, it is classified as allocating.

Float boxing is included deliberately. A Float that crosses an erased slot
(a task trampoline, an apply wrapper) is boxed via `march_alloc_float`; that
is a real allocation and the checker reports it as one. This makes some
Float-heavy code fail the contract until the unboxed-layout item lands, and
that is the correct verdict for the code as it compiles today.

## Transitivity

After monomorphisation the whole program is one `Tir.tir_module`, so the set
of allocating functions is computed by a fixpoint over `tm_fns`, exactly as
`Policy_dce.panicky_fns_of_module` does for panics:

1. Seed: every function whose own body contains a direct allocation per the
   table above, plus every function that contains an `ECallPtr` or extern
   call and is not `assume`.
2. Iterate: a function that calls an allocating function is allocating.
3. A function marked `no_alloc:assume` is removed from the set regardless of
   its body, and is never checked.

A contract on function `f` fails iff `f` is in the final set. The diagnostic
names the first offending node or callee on a path, so a transitive failure
reads "`f` calls `g`, which allocates (in `g`: constructor `Cons`)".

`assume` is therefore the only annotation ever needed on a callee, and only
for the two opaque call shapes. No signature-level annotation exists or is
planned.

## Where the check runs

A new module `lib/tir/alloc_contract.ml` exposes:

```ocaml
val check : Tir.tir_module -> March_errors.Errors.diagnostic list
```

`bin/main.ml` calls it as the last TIR pass before `Llvm_emit`, after
`Native_map_inline` (currently the last snapshot, `tir-native-map-inline`).
Diagnostics go through the ordinary error printer so they carry source spans;
a hard failure exits 1 before any object file is written.

Attribute and span information reach the TIR check the same way
`Vectorize_mark` does it: a pre-mono pass records, per function name, the
attribute form and the declaration's name span, keyed so that monomorphised
clones (`f$Int`) resolve back to `f`.

`Policy_dce.check_noalloc` (the `Tagged(_, NoAlloc)` and `Realtime` policies)
is replaced by a call into the same allocating-set computation. This only
widens what those policies accept: a policy-tagged function whose
allocations Perceus reused now passes, and stack allocation is no longer a
violation. `Policy_dce` keeps its position for the `NoPanic` and `NoIO`
checks, but its `NoAlloc` arm defers its verdict to `Alloc_contract` at the
later position.

### Shared pipeline tail

The language server runs its own TIR pipeline per file
(`lsp/lib/analysis.ml`, currently lower, mono, defun, known-call, borrow,
Perceus, escape). It does not run Fusion, the `Opt.run` loop, or TRMC, so its
TIR can differ from the build's, and the contract verdict with it.

To keep one verdict per program, the passes the checker depends on are
extracted into one function in `lib/tir`:

```ocaml
val Contract_pipeline.run : opt:bool -> trmc:bool -> Tir.tir_module -> Tir.tir_module
```

covering everything after lowering: TRMC (which runs before mono), mono,
defun, and every pass through the last one before emit. `bin/main.ml` and
the LSP both call it. The LSP calls it with the same `opt` and `trmc`
values `forge build` would use, so the editor reports the verdict the build
will produce. This is a mechanical extraction of code that already exists in
`bin/main.ml`; it moves no behaviour.

## Build configuration

March has two knobs that could change the verdict and one that cannot.

- `--opt N` is passed to clang and never read by a TIR pass. It cannot affect
  the check.
- `--no-opt` skips Fusion, Known_call, Beta_adt, Join_points, Simplify, and
  `Opt.run`. Perceus, Drop, and Escape run regardless. A pass that is skipped
  can leave an `EAlloc` that the full build would have reused or removed.
  Under `--no-opt`, a hard `@[no_alloc]` failure is downgraded to a warning
  whose text says the build skipped TIR optimisation. `forge build`, CI, and
  the LSP never pass `--no-opt`.
- `--trmc` is off by default. For `Cons(h, f(t))`, TRMC turns a post-call
  `EAlloc` into a pre-call `EAllocHole` that FBIP can attach a reuse token
  to. Without TRMC the same function fails the contract (and also overflows
  the stack on real input). When a contract fails, TRMC is off, and
  `Trmc.report` classifies the function as `eligible`, the diagnostic adds
  one line pointing at `--trmc`. When the on-by-default plan lands the hint
  stops firing on its own.

No payload selects a configuration. The rule is: the checker sees the TIR the
build emits, and the two flags above are handled by the two rules above.

## Interpreter and `--check`

Interpreted runs and `--check` do not lower to TIR, and the attribute is
ignored there with no diagnostic, matching `@[vectorize]`. `cap no_alloc`
keeps its current AST-level, pre-optimisation semantics because it is the
only allocation check available in those modes. Its documentation gains one
paragraph stating that `cap no_alloc` is syntactic and pre-optimisation while
`@[no_alloc]` is checked on the compiled program, and a todo is filed to
unify them once an interpreter-mode answer exists.

## Language server

Three additions, all driven by the shared checker:

1. **Diagnostic.** A failing contract is reported at the function's name span
   with the same severity and text as the build.
2. **Code lens.** Next to the existing `⚡ N stack-allocated · ♻ N in-place`
   lens, a function carrying `@[no_alloc]` shows `✓ no_alloc` when the
   contract holds. A failing contract shows nothing extra; the diagnostic
   covers it.
3. **Quick fix.** On a function without the attribute that the checker
   verifies clean and that meets the generation scope below, a code action
   "Add `@[no_alloc]`" inserts the attribute on the line above the
   declaration. The edit is a single insert at the declaration's start
   column, the same shape as the pmap conversion action.

The LSP uses `Contract_pipeline.run` in place of its hand-rolled pass list.

## Forge generation

`forge fix` already applies JSON fix items (`insert`, `delete`, `replace`)
that the compiler emits. Generation reuses that path:

- The compiler gains `--report-contracts`, valid with `--compile`. After the
  checker runs it emits one `--check-json`-shaped line per function that is
  verified allocation-free, lacks the attribute, and is in scope, with an
  `insert` fix placing `@[no_alloc]` on the line before the declaration.
- `forge fix --contracts` runs the compiler with that flag over the project
  and applies the edits. Without `--contracts`, `forge fix` behaves as today.

**Scope** (which verified-clean functions get an attribute):

- Default: functions whose final TIR contains at least one `EReuse`,
  `EAllocHole (Some _)`, or `EStackAlloc`. These are the functions where a
  future change would silently reintroduce an allocation, and the count is
  small.
- Opt-in: a `[contracts]` table in `forge.toml` with `no_alloc = ["Dsp.*",
  "Audio.mix"]` (module or function globs). Every verified-clean function
  matching a glob is in scope, including ones with no reuse.
- Never: functions already carrying any `no_alloc` form, synthetic `$`
  functions, and functions in stdlib or dependency sources.

Generation always inserts the hard form. A generated `warn` contract would
never be acted on.

The LSP quick fix uses the same scope predicate, so the editor offers the
action exactly where `forge fix --contracts` would insert it.

## Diagnostics

Messages follow the house style (first person, plain, one hint). Pinned in
`test_compiler`:

```
error: `inc_leaves` is marked @[no_alloc] but allocates.
  In `inc_leaves`: constructor `Node` is allocated here (Perceus could not
  reuse the matched cell because `t` is still used afterwards).

error: `render` is marked @[no_alloc] but allocates.
  `render` calls `format_row`, which allocates (in `format_row`: string
  concatenation).

error: `process` is marked @[no_alloc] but calls through an unknown closure.
  I can't see what `f` does. If you know it doesn't allocate, mark
  `process` @[no_alloc(assume)].

warning: `map_inc` is marked @[no_alloc] but allocates. (TIR optimisation was
  skipped by --no-opt; the normal build may pass.)

error: `map_inc` is marked @[no_alloc] but allocates.
  ...
  This function is TRMC-eligible; compiling with --trmc turns the
  constructor into an in-place write.
```

The "because" clause on the first message is best-effort: it is emitted when
Perceus's FBIP pass recorded a reason for declining reuse at that site and
omitted otherwise. Recording that reason is in scope for this item only if
the hook is trivial; otherwise the message ends after "allocated here".

## Testing

All cases compile a program with `--compile` and assert on exit code and
diagnostic text. Accept cases also run the binary and compare output with
the interpreter, per the compiled-parity convention.

Accept:
- FBIP tree transform (`inc_leaves` over a uniquely-owned tree).
- Accumulator loop where `Cons` is reused (`List.map` shape).
- TRMC producer with `--trmc`.
- `assume` on a function wrapping an extern; a caller of it with the bare form.
- Stack-promoted tuple return.
- Nullary constructors, arithmetic, field reads only.

Reject:
- Plain constructor with the scrutinee still live afterwards.
- Transitive: `f` calls `g`, `g` allocates; diagnostic names `g`.
- String concatenation via builtin.
- `ECallPtr` without `assume`.
- Float that crosses an erased slot (boxed).
- Attribute on an actor or extern (parse error).

Behaviour:
- `warn` form: exit 0, warning printed.
- `--no-opt`: hard form downgraded, message names the flag.
- TRMC hint present when eligible and off; absent when `--trmc` is on.
- `Tagged(_, NoAlloc)` accepts a reused constructor it previously rejected.
- Policy check still rejects a plain allocation.

Language server (`lsp/test`):
- Diagnostic at the name span for a failing contract.
- Code lens text for a holding contract.
- Quick fix offered on a clean function with reuse; not offered on a clean
  function with no reuse and no matching glob; not offered on stdlib.

Forge (`forge/test`):
- `--report-contracts` emits an insert fix for an in-scope function and
  nothing for out-of-scope ones.
- `forge fix --contracts` applies it and a second run is a no-op.

Oracle: `scripts/ir-oracle.sh` must be green across the pipeline-tail
extraction, since that refactor is meant to move no IR.

## Documentation and bookkeeping

- `specs/lang/surface-syntax.md` and its `docs/` copy: attribute reference
  entry with the three forms.
- `specs/lang/capabilities.md`: one paragraph under `cap no_alloc` on how the
  two differ.
- `specs/lang/memory-model.md`: the "Writing allocation-free code" section
  gains the contract as the way to pin a `♻` result.
- `specs/features/compiler-pipeline.md`: the new pass in the pass table.
- `CHANGELOG.md`: one `### Added` bullet.
- `specs/todos/2026-09-03-allocation-contracts.md` filed with this spec;
  moved to `specs/progress/` by the landing PR.
- A second todo for unifying `cap no_alloc` with the contract.

## Roadmap context

This is item 1 of five, taken from a review of OxCaml's documentation
(2026-09-03). The others, in dependency order, each get their own spec:

2. Type kinds: one record per type computed once from `type_defs`,
   replacing the predicates in `rc_types.ml` and `repr.ml`. Strictly
   behaviour-preserving.
3. Portable closures at parallel boundaries: `pmap`, `pfilter`, `preduce`,
   `task_spawn` reject impure closures.
4. Borrow regions for linear values.
5. Unboxed Float layout (depends on 2).

Item 1 establishes the attribute-plus-TIR-check path and the shared pipeline
tail that items 3 and 5 reuse.
