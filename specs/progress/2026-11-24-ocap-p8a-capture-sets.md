# Object capabilities, phase 8a: capture sets (inference, display, soundness oracle)

Plan: `specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md`. Design:
`specs/2026-11-11-ocap-capture-checking-design.md` (§16 row 8a). Phases 8b (`scoped` parameters
and escape) and 8c (the public-signature rule, the stdlib migration, `forge fix`) are open in
`specs/todos/2026-11-12-ocap-capture-checking.md`.

## What it does

For every function value, and every value that holds one, the compiler infers a capture set:
an upper bound, in the `needs` scope language, on what the value can do when called. Hover,
`march-lsp query type|hover` and the new `march --dump-captures FILE` show it. It adds no
diagnostic and changes no generated code.

## How it is built

- **A second pass, beside the types.** `lib/typecheck/capture.ml` walks the checked program
  and reads each expression's solved type from `env.type_map`. `Typecheck_types.ty`,
  unification, `Cap_rows` and `check_fn_bounds` are untouched, so the layer erases by
  construction: nothing it computes reaches lowering.
- **Annotated types** (`lib/typecheck/capture_ty.ml`): the shape of a solved type with a set
  variable on every arrow and on every value of a declared type that can hold a function
  value. A type that reaches no arrow is `Plain` and carries nothing, which is most data and
  the pass's fast path. One HM type variable is one annotation, with a set variable for
  everything a value of that type holds.
- **Constraints** are inclusions between set variables, plus constants. The least solution is
  a worklist propagation. `lib/caps/capture_set.ml` is the scope-set algebra: union, covering,
  a narrowing that is a sound upper bound of intersection, and `admits` for a run-time target.
- **Two effect variables per function value.** `own` collects the operations its body
  performs and the own reach of the named functions it calls directly; the static authority
  at its creation site (the enclosing function's `needs` clause, every literal `restrict`
  around it, its package's grant) narrows that. `valv` collects the sets of the function
  values it calls, captures and creates; those arrive whole, because a function value runs
  under its own authority. Keeping them apart is what makes narrowing sound.
- **Named functions get schemes**, computed on demand from `env.fn_row_bodies`, one recursive
  group at a time, memoised. A scheme is the function's annotated parameter and result types,
  its own reach as a constant (narrowed by its clause), and the bounds and flows among its
  interface variables. A call instantiates it; inside a recursive group the group's own
  variables are used directly. A parameter's type is taken from its first use (a `Hole`),
  because the callee span in `type_map` is unreliable (a zero-argument call, an operator).
- **Declared types** carry one set per value (design §4.2): a constructor's fields are read
  from its declaration with every bare arrow, and every declared type that holds one, sharing
  the value's set; a type parameter is the value's own annotated argument.
- **Grounding.** Each instantiation links its variables back to the scheme's, so a second
  solution over those links replaces every variable by everything it is ever instantiated
  with. That is what the oracle compares against.
- **`not tracked`** (`Capture_set.unknown`) is above every set. Every construct the pass does
  not model gets it, with a cause the report prints.

Where the pass reads its inputs when the checker recorded none: the editor's entry point
(`check_module_with_env`) writes no `fn_row_bodies` for the user's file, so the pass also reads
plain functions, top-level lets and actor handlers from the declarations it is given.

## The soundness oracle

`MARCH_CAPTURE_ORACLE=1` on an interpreted run (`bin/capture_oracle.ml`; hooks in
`Eval_prim.capture_oracle`, `None` otherwise): while a function value is running, every
capability operation the run-time layers admit, done by it or by anything it calls or spawns,
must be inside the value's grounded set. A miss is an unsound rule.

Two things the first runs taught:

- **Only admitted operations count.** A function value narrowed by a `restrict` can still try
  an operation outside it and be refused. The static set bounds what it can do, not what it
  can try (design §10.1). The hook is given the scope texts of the layers in force and the
  oracle judges them with `Capture_set.admits`.
- **A direct `Authority.check(kind, target)` is an operation.** The conformance fixtures probe
  authority that way. A literal kind is that kind; a computed kind is `not tracked`.

And one bug it found in the pass: a closure made inside a module-level `restrict` was being
narrowed, but module-level code captures nothing at run time, so the closure runs under its
caller's authority (`restrict_module_level_closure_captures_nothing`). Fixed, with a unit test.

The oracle is shown to go red. With one rule removed (`MARCH_CAPTURE_ORACLE_UNSOUND`) it must
report a miss, and does:

| Rule removed | Fixture that catches it |
|---|---|
| a called value's set is not added to the caller's effect (`drop_callee_effect`) | `capture_laundered` |
| arguments do not flow to parameters (`drop_arg_flow`) | `capture_laundered` |
| arriving values are narrowed by a `restrict` (`narrow_values`) | `capture_restrict_mixed` |

Dropping the capture rule itself cannot be seen by an extent oracle: a captured value's
operations always arrive through a call. That rule is pinned by unit tests.

## Tests

Suite `captures` (`test/run_captures.exe`; `scripts/run-tests.sh captures`; CI: the `forge`
shard):

- `capture_set`: the set algebra, with a property test that narrowing is an upper bound.
- `captures`: 26 inference cases through `march --dump-captures`.
- `capture_golden`: `test/captures/*.march` against `.expected`
  (`UPDATE_CAPTURES=1`, `CAPTURES_ONLY=`).
- `capture_oracle`: the five fixtures in `test/captures/oracle/`, the whole
  `test/cap_conformance/` corpus (dependency-grant fixtures included), and the three red-proof
  cases.
- `capture_sweep`: the pass over every stdlib function, and over every bench and example
  program.

Hover and query: `lsp/test/test_lsp_analysis.ml` (four cases, one of them that diagnostics do
not force the pass) and `lsp/test/test_query_cli.ml`.

## Numbers

See the PR body for the run that shipped (oracle counts, the cost table, the sweep).

## Decisions taken while building (the plan's rulings)

- Tests live in their own fast runner, not `run_compiler`.
- The pass is two files, not four.
- An undeclared builtin type holds no function value unless listed (`Task`), so handles are
  plain; a builtin may call only what it can see is a function.
- Capturing a value adds what it holds, not its parameters' sets.
- Kind-dropping narrowing cannot occur in an accepted program (`cap_bound` and `cap_restrict`
  reject it first), so narrowing only ever refines a scope.
- A set-carrying type inside a comma-separated list is parenthesised:
  `Result((Task(()) needs IO.Console), CapError)`.
- Labelled constructor fields in the design's examples (`Client(fetch : ...)`) are not March
  syntax; the tests and docs use `Client(String -> ...)` and records.
- March has no partial application; the design's case is an eta-lambda.

What is coarse or untracked: `specs/todos/2026-11-24-ocap-capture-inference-precision-gaps.md`.
