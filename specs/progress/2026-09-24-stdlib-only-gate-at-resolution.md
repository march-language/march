# The stdlib-only builtin gate fires at name resolution, and exempts by loader provenance

**DONE 2026-09-24.** Closes the four gate bypasses the distributed-deploys
review filed (PR #614): `2026-09-24-dd-review-stdlib-only-gate-entry-named-like-stdlib.md`,
`-let-shadow.md`, `-skips-impl-interface-test.md` and
`2026-09-24-dd-review-repl-not-stdlib-only-gated.md` (all in this
directory, each with its own "Fixed" trailer). Supersedes the mechanism in
[2026-09-22-stdlib-only-builtins.md](2026-09-22-stdlib-only-builtins.md);
the table (`Typecheck_builtins.stdlib_only`) and the error text are unchanged.

The fifth finding, `2026-09-24-dd-review-session-hold-epoch-public.md`
(`Session.hold_epoch`/`release_epoch` take no capability), stays open here:
`stdlib/session.march` and `stdlib/session_node.march` belong to the D27
session-drains work, which confirmed it will give both wrappers a
`Cap(Session.Live)` parameter (and thread `s` into the generated
`take_idle`/`cancel`) in its own commit and move that todo itself. The gate
below does not touch it: those two files keep calling the raw builtins from
stdlib spans.

## What was wrong (one mechanism, four symptoms)

The gate was a syntactic declaration walk beside Check 1b
(`Typecheck_caps.check_stdlib_only_refs`): visit `DFn`/`DLet`/`DActor`,
collect free variables, skip a module that "locally declares" a gated name,
skip a declaration whose span file is in `stdlib_source_files`. Each of
those choices was a bypass:

- the walk ended in `| _ -> ()`, so `impl` bodies, interface defaults,
  `test`/`describe`/`setup`/`setup_all` were never visited;
- a module-level `let pid_of_int = pid_of_int` counted as a local
  declaration, switching the gate off for the module including the `let`'s
  own right-hand side;
- the REPL's `check_decl`/`infer_expr` path never called the walk, and
  `Repl_jit` discarded the errors of the one path that did;
- the driver put any entry file whose BASENAME was in the stdlib manifest
  into `stdlib_source_files`, so a user's `json.march` was the stdlib's.

## What landed

**Gate at resolution.** `Typecheck.infer_expr`'s `EVar` arm: a name in
`stdlib_only` that still resolves to the builtin, referenced from a span the
stdlib does not own, is an error at that reference. Value references count
as much as calls. No declaration walk exists any more, so there is no kind
to forget: everything the typechecker types (impl and injected default
methods, tests, actor `init` and handlers, nested modules, REPL fragments)
passes through this one arm. `check_stdlib_only_refs` is deleted.

"Still resolves to the builtin" is tracked explicitly: `env.gated_shadowed`
(a `StringSet`) collects gated names that a NON-builtin binding rebound, at
the binding funnels `bind_var`/`bind_linear` (and the one bare method-name
write in `check_decl`'s interface export), cleared once by `base_env` after
it binds the builtins. It is not a physical or structural comparison of the
scheme in scope against `builtin_bindings`: the driver Marshals a cached
stdlib env (physical identity lost, and a fail-open gate is the one thing
this must never be), and a structural compare would mistake a user function
of the same name and type for the builtin. `let pid_of_int = pid_of_int`
types its right-hand side before the binding exists, so the RHS is gated and
the alias never forms.

**Provenance, not basename.** `Typecheck_builtins.stdlib_roots`: the real
paths of the directories the stdlib was loaded from, registered by
`Toolchain.load_stdlib` (driver, `march test`, `march check`, REPL, JIT) and
the LSP's `Analysis.load_stdlib` through `note_stdlib_root`, beside the
existing `note_stdlib_decls`. `file_is_stdlib f` is now "in
`stdlib_source_files`, or its real path is under a root" (memoised per
file). Canonicalisation is injected (`stdlib_realpath`, set to
`Unix.realpath` by both loaders) so `march_typecheck` stays free of `unix`
for the browser REPL. The driver's two "basename in manifest, so add the
entry file" sites are gone. For a stdlib file checked under a spelling that
is not under the resolved root (CI's `march --check stdlib/list.march` from
the repo root, while the compiler resolves its staged `_build/default/stdlib`
copy) there is an explicit `--stdlib-source` flag; CI's two ratchet
invocations pass it, which preserves their previous output exactly (Check 1b
stays a HINT there; the counted `user + stdlib` line is identical either
way, measured). `MARCH_STDLIB=stdlib` works too, by provenance. The
prelude-collision exemption (`is_shipped_stdlib_file`, bin/main.ml) still
matches by basename: it is a diagnostic-noise exemption, not an authority
one, and is left alone on purpose.

`--stdlib-source` is in both CAS keys that cache a `--check` verdict (the
early source-level short-circuit used `~flags:[]`; measured, a clean
`--check --stdlib-source` run satisfied the next plain `--check` of the same
source, which then exited 0 printing nothing).

**REPL and JIT.** Nothing REPL-specific remains: the REPL's per-input
typecheck reports the gate and skips evaluation in both modes. `Repl_jit`'s
four lowering entry points go through `checked_type_map`, which raises
`Repl_jit.Typecheck_failed` with the rendered errors instead of lowering a
fragment the typechecker rejected. `Failure` was deliberately not reused:
some REPL call sites treat it as "the JIT could not compile this, evaluate
it in the interpreter instead".

## Tests

`test/test_stdlib_only.ml` (run_compiler, group `stdlib-only builtins`, 18
cases): the seven original cases, then one per bypass (module-level and
fn-local self-alias, impl method, interface default via an impl, the four
test-block kinds, actor handler), root provenance in-process (a `json.march`
under a registered root passes, the same file elsewhere and the bare
basename fail), the driver end to end on the review's `json.march` repro
(`--check` exits 1 with all three errors, interpreted exits 1 without
printing `forged`, `--stdlib-source` exits 0), the shipped table, an
adversarial sweep (six gated names x fifteen shapes: call, value reference,
both self-aliases, impl, interface default, test, describe, setup,
setup_all, actor handler, actor init, pipe, nested module, REPL fragment,
each asserting the table's exact message) and its negative control (every
name rebound by a user fn in every shape: silent).

`test/test_jit.ml` (group `repl_session`): "stdlib-only builtins rejected"
for the interpreter (Quick), clang JIT and ORC JIT (Slow), piping the
finding's spellings into the real REPL binary and asserting each error text,
no `= Pid(`/`node_id`/`= []`/`val f = <fn>` in the output, and that an
ungated line afterwards still evaluates.

Perturbations, each RED before the fix was restored: gate condition forced
false → 14 of 18 compiler cases fail (the four that stay green are the
shadowing negative controls and "stdlib module allowed"), and the
interpreter REPL session fails on its first assertion; driver basename
exemption re-added → "driver rejects a user json.march" fails on `--check`
exiting 0. (A third run showed 13 failures with the gate restored: a stale
`run_compiler.exe` from the first perturbation, rebuilt and green.)

## Not done / observations

- A `--check` verdict's CAS key still ignores `--no-cap-strict`, which also
  changes verdicts. Pre-existing, filed separately.
- An interface default that no impl ever takes is never typed by the
  typechecker at all (so also not gated); it never runs.
- The LSP: opening a stdlib file from the resolved root draws no gate
  errors (by provenance); a file elsewhere with a stdlib name does.
