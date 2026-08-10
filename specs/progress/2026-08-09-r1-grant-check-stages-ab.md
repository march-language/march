# R1 stages A+B: main's capability parameter is the grant

Landed 2026-08-09. Design: `specs/2026-08-08-r1-no-ambient-io-design.md`
(status header there records one correction to its Stage A wording).

## What this is, in one sentence

The first check in the capability system that says **no** rather than
"declare it": `fn main(cap : Cap(IO.Console))` holds the program's whole
transitive capability closure under the console, and a truthful `needs`
manifest does not raise that ceiling.

Everything shipped 2026-08-04..08 (severity flip, ceiling default, R2, R3,
R4a) verifies the MANIFEST end to end — a hostile module with a truthful
manifest passes all of it. This is the piece that turns the system from
auditing into sandboxing, at whole-program granularity.

## The adoption contract

| `main` signature | meaning |
|---|---|
| `fn main()` | ambient — NO gate; every pre-grant program keeps compiling |
| `fn main(cap : Cap(IO))` | full grant (the existing entry-point convention) |
| `fn main(cap : Cap(IO.Console))` | narrow grant, enforced transitively |

Zero migration: the grant-regression sweep over examples/, bench/,
test/native/, test/stdlib/ and test/whole_program/ found zero grant errors,
and the full compiler suite (813) passed unchanged.

## Where it lives

- `Desugar.check_main_signature` accepts `Cap(P)` for any P in
  `Cap_lattice.hierarchy` (was: exactly `Cap(IO)`). Unknown paths
  (`Cap(IO.Nope)`) are rejected HERE, not silently turned into a grant
  nothing sits under.
- `Typecheck.check_main_grant`, called at the end of `check_module_core`
  after `check_module_needs`. Grant extracted from main's clause via the
  shared `Cap_surface_ty.caps_in_ty` walk; closure from
  `fn_transitive_capability_closures_tbl` (key `"main"` — the entry module
  is unwrapped); violations judged by `Cap_lattice.cap_subsumes`.

## Decisions a future reader will want the reasons for

**Typecheck-side closure, not TIR attribution.** Both the interpreter and
compile paths run typecheck; only compile runs attribution. Gating one path
on an analysis the other does not run is exactly how the unused-warning/
ceiling contradiction happened (2026-08-08). Verified: `march f.march` and
`march --compile f.march` reject identically.

**Reachability, not file-union.** caps(main), so dead code costs nothing —
the ceiling's post-#225 semantics. Pinned by the dead-code test; the dead
helper still owes its `needs` line (manifest checks unchanged, orthogonal).

**Non-IO capability roots are skipped.** FFI caps (`Ffi`, `LibC`) are their
own lattice roots — `cap_subsumes "IO" c` is false — and holding them under
an IO grant would reject every FFI program with a message about a lattice
they are not in. Their IO shadow is `IO.Foreign`, which IS bounded:

**`IO.Foreign` under a narrow grant is refused outright**, with its own
message ("linked C code, whose behavior the capability lattice cannot
bound"). Certifying `Cap(IO.Console)` over an extern block would be a lie;
the design doc's interaction list called this before implementation.

**No gate without a parameter.** The design spec's Stage A paragraph, taken
literally (parameterless main = empty grant), breaks every existing IO
program and contradicts its own adoption-contract paragraph. Resolved
adoption-side; "pure main" is claimed by a narrow grant with an empty
closure, not by omission.

## The diagnostic, and the trap inside it

The error names the grant, the capability, and a function that reaches it:

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.Clock`
(reached in `Random.int`). The grant is a ceiling on the WHOLE program —
declaring `needs IO.Clock` does not raise it.
```

The first version picked ANY holder of the capability from
`own_cap_closures` — the whole env, linked stdlib included — and named
`Logger.with_span` for an `IO.Clock` reached through `Random.int`: a
function the program never calls. The hint now restricts holders to a
reachable-from-main set (BFS over `env.fn_refs`, resolving refs bare and
module-prefix-qualified — the closure fixpoint's first two resolver shapes),
falling back to an arbitrary holder only when reachability cannot be
re-proven.

## Witnesses

- `cap_grant` group in test_compiler (9 tests, RED first): both accept
  directions, direct + through-helper violations, full-IO grant, ambient
  compatibility, the Foreign refusal, dead code, and both signature-check
  directions.
- Corpus: `accept/t167_grant_narrow_console_proven` /
  `reject/t166_grant_narrow_violated_by_helper` — the reject file's manifest
  is deliberately perfect, pinning "declaring does not grant".

## Stage C (not built)

Per-function grants — effect rows (R5). The observation that makes it
smaller than feared: `fn_transitive_capability_closures_tbl` already IS the
inferred row; what is missing is row POLYMORPHISM (`map`'s row must be its
argument's, not the union over call sites), the typing, and per-function
discharge. See the design doc.
