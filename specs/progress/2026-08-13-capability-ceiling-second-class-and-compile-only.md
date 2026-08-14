# The capability ceiling's diagnostic was second-class (Task 7, Steps 3-4)

Part of the capability UX remediation plan
(`specs/2026-08-13-capability-ux-plan.md`, Task 7). **Steps 3-4 landed; Step
5 (running the ceiling under `march --check`) did not — see the "Step 5: not
landed" section below.**

## What shipped

The `--cap-strict` ceiling (`lib/caps/cap_ceiling.ml`, `--compile`-only) used
to be reported via a bespoke `-- CAPABILITY CEILING --` block in
`bin/main.ml`: no file, no line, no source excerpt, no machine-applicable
fix. Every other capability diagnostic in the compiler goes through `Err`
and is therefore visible to the LSP and fixable by `forge fix`; the ceiling
was the one exception.

1. **`lib/caps/cap_ceiling.ml`/`.mli`**: `Undeclared` now carries a
   `span : March_ast.Ast.span` — the owning module's first `DNeeds` span, or
   its header span if it declares none. `check` takes a new
   `~module_spans:(string * March_ast.Ast.span) list` parameter to supply
   it, keyed identically to `~module_caps` (bare and fully-qualified nested
   spellings both present, matching the ownership keying `--cap-strict`
   already used). `Unattributed` is unchanged — it names no module, so it
   has no span to carry (see "Unattributed stays bespoke" below).

2. **`bin/main.ml`**: added `cap_ceiling_module_spans`, which walks the
   desugared AST once to build the `~module_spans` table (mirrors
   `Typecheck.check_module_needs`'s `cap_qname_prefix` accumulation, so a
   violation on a doubly-nested module resolves to the same qualified key
   the ceiling's attribution matches against). The reporting block now
   builds a fresh `Err.ctx` (same pattern as the `vectorize_diags` block a
   few dozen lines below it: a throwaway context, not the shared typecheck
   `errors`, since that one has already been drained and printed by this
   point) and emits each `Undeclared` violation via
   `Err.error_with_fix ~span ~code:("cap_ceiling:" ^ cap) ~fix:(FInsert ...)`,
   then renders through the same `render_diagnostic` pipeline every other
   diagnostic uses (file/line resolution, source excerpt, `forge fix`
   compatibility). `Unattributed` violations (no owner, no span) keep the
   old bespoke `eprintf` line — see below for why. The trailing summary line
   and the `--no-cap-strict` mention are unchanged, per the brief.

3. **`forge/lib/cmd_cap.ml`**: `ceiling_violations` (the `forge cap inspect
   --strict` re-check against a built artifact) passes `~module_spans:[]` —
   there is no AST to attribute a span from when re-checking a binary you
   did not build, and its only consumer (`describe`) never reads `span`.

4. **`test/test_cap_ceiling.ml`**:
   - All seven unit tests updated to pass `~module_spans:[]` (span is
     untested at that layer; `describe` ignores it).
   - `rejects`'s marker changed from the literal `"-- CAPABILITY CEILING --"`
     header (which no longer appears for the common `Undeclared` case its
     two callers — `test_stdlib_route_was_completely_silent`,
     `test_builtin_as_value_route` — exercise) to the trailing summary line
     text, `"capability ceiling violation(s)"`, which every ceiling failure
     still prints regardless of violation kind. Caught by actually running
     the Slow suite, not just Quick — see "Verification" below.
   - New Slow test `test_ceiling_violation_carries_a_span_and_a_fix`: pins
     that a ceiling failure (a) does NOT contain the bespoke header, (b)
     contains a numbered source line (`^ *[0-9]+ |`), (c) contains the exact
     fix hint text, (d) still names the offending module and capability.

### Unattributed stays bespoke

`Unattributed` (a capability used by emitted code that attribution could not
pin to any owner) names no module, so it has nothing to key `module_spans`
against and nothing sound to insert a fix line after. Per
`specs/progress/2026-08-08-ceiling-signature-only-fixed.md`, this
constructor has been a dormant backstop since the 2026-08-08 default flip —
its describe-time reason-carrying improvement was explicitly left unbuilt
there because nothing was feeding it any more. Migrating it to `Err` would
require inventing a location (`dummy_span`, or "the whole program"), which
is worse than the honest bespoke line it already has. Left as-is.

## Step 5: not landed

The brief's Step 5 asked to also run the ceiling's rule under `march
--check` (which does not lower to TIR, so the `--compile`-only, TIR-attribution-based
`Cap_ceiling.check` cannot run there as-is), reusing
`Typecheck`'s `own_cap_closures` / `fn_transitive_capability_closures_tbl`
and `cap_subsumes` rather than a new AST walk, per the brief's own
escalation clause: stop and report rather than ship something that might
over-report, since an over-reporting ceiling under `--check` would break
every March project that compiles today.

**Finding: the reuse the brief proposed is unsound, and it is unsound for a
reason this codebase has already hit and fixed once, on the `--compile`
side.**

`own_cap_closures` is fed by `record_fn_caps`, which is called with a
function's SIGNATURE capabilities (`Cap(X)` parameter types) in addition to
its body-scanned ones — line ~9223 (`record_fn_caps qname sig_caps`) in
`lib/typecheck/typecheck.ml`. That is correct for the table's existing
consumer, Check 2 ("declared `needs` but never used" — a signature `Cap(X)`
parameter legitimately counts as use). It is wrong for a ceiling check,
whose whole point (per `cap_ceiling.mli`) is to ask what code ACTUALLY
DOES, not what a signature merely accepts — which is exactly why the
`--compile`-side ceiling deliberately stopped unioning in
`own_caps_of_this_module` (see `specs/progress/2026-08-08-ceiling-signature-only-fixed.md`,
closed via the 2026-08-08 default flip): that union produced a false
positive on `fn main(cap : Cap(IO))`, the documented entry-point shape.

Prototyping the brief's approach directly (a per-module transitive-closure
comparison spliced into `check_module_core` right after the top-level
`check_module_needs` call, using `fn_transitive_capability_closures_tbl` —
built from `own_cap_closures` — filtered to each module's own non-stdlib
`DFn`s) reproduced precisely that failure on the very test the brief itself
proposed:

```
mod StdlibRouted do
  needs IO.Console
  fn slurp(p : String) : String do
    match File.read(p) do ... end
  end
  fn main(cap : Cap(IO)) : () do
    println(slurp("/etc/passwd"))
  end
end
```

```
PROTOTYPE CEILING: module `StdlibRouted` uses `IO` but does not declare `needs IO`
PROTOTYPE CEILING: module `StdlibRouted` uses `IO.FileRead` but does not declare `needs IO.FileRead`
```

The second line is the intended catch. The first is the reintroduced bug —
`main`'s own `Cap(IO)` parameter, not anything `main`'s body does.

In every case checked, this specific pollution happened to coincide with an
error the PRE-EXISTING typecheck already raises independently (Check 1:
a function's own signature `Cap` not covered by its own module's `needs`;
or `check_main_grant`: `main`'s grant not covering the reachable set) — so
it never flipped an accepting program to a rejecting one in testing. But
`own_cap_closures`'s reference edges (`env.fn_refs`, built from
`free_vars_expr`) are deliberately over-inclusive by a documented design
decision one layer down: they record a reference to a capability-typed
function whether or not it is ever actually CALLED (see the "cardinal sin"
comment on `record_fn_refs` in `typecheck.ml`, ~line 9007 — precisely so a
function merely passed around as a *value* isn't falsely treated as pure).
Combined with signature pollution, this means a module that references
(but never calls) another module's `Cap(X)`-parameterized helper —
`let f = Utils.demo` and nothing more, no independent `Cap(X)` obligation of
its own — would inherit `X` into its transitive closure and could be
rejected by a `needs` ceiling for a capability its own code never
exercises. I did not find or construct a concrete case that both (a) passes
`--check` today and (b) is rejected by the prototype without the mitigating
coincidence above, but I also did not exhaustively search the space, and
the reference-graph mechanism described above provides no assurance that
one doesn't exist — which is exactly the situation the escalation clause
told me to stop on rather than guess through.

**A correct implementation would need a body-only-derived closure table**
(seeded from body/extern-scanned capabilities alone, still walking the
existing `fn_refs` edges to a fixpoint) **kept separately from
`own_cap_closures`**, since `record_fn_caps` currently merges signature and
body capabilities into one entry and Check 2 depends on that merge staying
as-is. That is materially more than "reuse `own_cap_closures`, do not
re-derive the closure" — it is a second table, populated at the same
record-time call sites the existing one is, which is real design and
review surface I was told not to take on without checking back first.

Steps 3-4 (this commit) stand on their own and are unaffected by Step 5's
absence — the ceiling's diagnostic quality improved regardless of which
pipeline stage runs it. `specs/lang/capabilities.md` / `docs/capabilities.md`
were deliberately left unchanged: their claims that `--check` exits 0 on a
stdlib-mediated call and that only `--compile` catches it remain true.

## Verification

- `dune build --root . bin/main.exe forge/bin/main.exe test/run_compiler.exe` — exit 0.
- `./_build/default/test/run_compiler.exe -e` (full suite, not `-q`, per the
  Slow-test warning in `CLAUDE.md`) — see the commit message / task report
  for the pass count; the two pre-existing `rejects`-based Slow tests
  (`test_stdlib_route_was_completely_silent`, `test_builtin_as_value_route`)
  were caught failing against the new output shape and fixed in the same
  commit (see `test/test_cap_ceiling.ml`'s `rejects` above).
- `dune build --root . @types-check` — exit 0 (no corpus file asserted the
  old `-- CAPABILITY CEILING --` header text).
- `scripts/check-docs.sh` — exit 0 (no doc passages changed).
- Corpus sweep for Step 5 false positives was **not applicable** — Step 5
  did not land, so there is no new `--check`-path behavior to sweep for
  regressions in.
