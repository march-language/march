# Substantive claim audit of `specs/features/compiler-pipeline.md`

**Completed**: 2026-08-25
**Type**: documentation correctness (docs-only; no compiler behavior changed)

## Why

`specs/features/compiler-pipeline.md` is the entry-point map for anyone working
on the compiler. Before this, it had been audited only for *mechanical* rot —
stale line counts and dead file pointers. Its substantive claims had never been
checked. The one that was spot-checked (§17, "full code generation (linking,
assembly) not yet implemented", derived from reading a 10-line vestigial shim
literally) turned out to be badly false: March emits LLVM IR and links native
binaries every day. A sample of one, and it failed. This audit covered the rest.

## Method

Every `**Status**:` marker, every Known Limitations entry, every Status-column
cell in the Implementation Status Summary, the Dependencies-Between-Passes and
Performance-Characteristics sections, and a spot-check of per-section prose was
checked against the code before being judged — `forge search`,
`forge search --callers`, and direct reads of `bin/main.ml` and `lib/tir/*.ml`.

Corrections are made **in place**, each carrying a
`Correction (2026-08-25 claim audit)` note that states what was claimed and why
it was false. That habit already existed in the file and is why its remaining
errors were findable; it is preserved. Claims that could not be settled in
reasonable time are now explicitly labelled unverified rather than left reading
as fact. No sections were renumbered or restructured, and no file sizes or
line-number pointers were added.

## Result

**~95 claims checked · 19 wrong · ~9 unverifiable.**

The 19 false claims, by damage:

1. **§15 Optimization Coordinator** — the worst. Claimed the fixed-point loop
   runs "Inline → Fold → Simplify → DCE", and illustrated it with a block of
   OCaml presented as `Opt.run`'s body. `Opt.named_passes` actually runs **nine**
   passes (`join-points`, `known-call`, `inline`, `single-use-inline`, `cprop`,
   `fold`, `simplify`, `fusion`, `dce`) and the quoted snippet does not exist in
   `lib/tir/opt.ml`. A fabricated verbatim quotation is worse than a vague
   description: it invites the reader to trust the doc over the source.
2. **§9 Escape Analysis** — "Replace escaped `EAlloc` with `EStackAlloc`" is
   exactly backwards; `escape_fn` promotes `candidates − (escaping ∪ with_incrc)`.
   As written it describes a use-after-return bug. The `with_incrc` exclusion and
   the Boxed-repr-only candidate filter were also missing.
3. **§20 Purity Analysis** — listed "contains no heap allocations (EAlloc,
   EStackAlloc)" as a *condition for purity*. `purity.ml` says the opposite in
   as many words: `| Tir.EAlloc _ -> true (* allocation is pure *)`. The section
   also framed purity as a whitelist when it is a blacklist, omitted the
   `ECallPtr` / `ESetField` / trapping-division cases, and named only the inliner
   as a consumer when DCE is the consumer with the sharpest correctness need.
4. **§11 Inlining** — threshold given as 15 TIR nodes; actual
   `inline_size_threshold = 50`, with the source explicitly noting it was raised
   from 15.
5. **Pass-order note + Dependencies diagram** — the stated `bin/main.ml` ordering
   omitted five real steps: `Vectorize_mark`, `Trmc`, the `Policy_dce` audit, the
   pre-Perceus `Simplify`, and **`Drop`**, which sits *between* Perceus and
   Escape. The conditionality of five passes on `!opt_enabled` was also unstated.
   This section already carried a "Pass-order note" correcting an earlier
   Perceus/Escape inversion, so it had a track record.
6. **§13 Simplification** — three of five listed behaviors belong to other passes
   (two to DCE, one to Fold) or do not exist; the float-freeness guard on
   `x == x`, the one genuinely subtle thing about the pass, went unmentioned.
7. **§14 DCE** — root set given as "`main`, else all functions". Exports, tests
   and setup/migrate functions are roots too, and the all-functions fallback is
   gated on `~fail_open` after `~extra_root`.
8. **§10 Perceus** — expanded FBIP as "Function Body Inlining and Partial
   Application". FBIP is "Functional But In-Place".
9. **§8 Defunctionalization** — gave two contradictory sizes for `builtin_names`
   ("63+" and "56") against an actual 548 distinct names, ~10× off. Matters
   because a missing entry there is a codegen bug, not a missed optimization.
10. **§21 Pretty Printing** — functions listed as `pp_expr`/`pp_ty`/`pp_var`; the
    module uses `string_of_*` throughout and has none of those three names.
11. **§6 TIR Types** — the `expr` listing omitted `EAtomicIncRC`, `EAtomicDecRC`,
    `EAllocHole` and `ESetField`; a `match` written from it would be inexhaustive.
12. **§12 Constant Folding** — claimed `is_int`/`is_float`/`is_string`/`is_bool`
    are folded. None of those names appear in `fold.ml`.
13. **§19 Effects System** — implied `bin/main.ml` calls
    `Effects.check_capabilities`. It does not; the only callers are two tests.
    The *status* (Enforced) is correct, since enforcement reaches
    `check_module_needs` directly — so this was a wiring claim, not a capability
    claim. `effects.ml` is a second instance of the §17 shape: a plausibly-named
    module that is a bypassed shim.
14. **Known Limitations, "Gradual typing"** — "type-level naturals mostly unused"
    is stale. A constraint solver v1 landed 2026-07-31 (`normalize_tnat`,
    `solve_nat_eq`, parser `ty_nat_add`/`ty_nat_mul`, a `type_level_nat` test
    group). Rewritten to say what is still limited.
15. **Known Limitations numbering** — ran 1, 3, 4, 5, 6, 7; item 2 had been
    deleted without renumbering. Renumbered.
16–19. **Status table** — six passes that exist and run
    (`single_use_inline`, `cprop`, `drop`, `vectorize_mark`, `policy_dce`,
    `trmc`) were absent from the table; `codegen.ml` and `effects.ml` read as
    functional gaps rather than bypassed shims; `trmc` (genuinely present-but-off)
    was unmarked; the Optimization Loop row understated the pass count.

Verified **correct** and left alone: the §16 heap object layout (matches
`march_hdr` in `runtime/march_runtime.h`), §19's Enforced status, §17 as already
corrected, §18.1's three execution modes, and Known Limitations on higher-kinded
polymorphism, polymorphic recursion and associated types (each confirmed against
`lib/ast/ast.ml` / `lib/tir/mono.ml` / `lib/typecheck/typecheck.ml`).

Marked **unverified** rather than deleted or left as fact: the six
Performance-Characteristics complexity classes (asymptotic sketches, never
derived or measured — only the ≤5-iteration bound is checkable and it is
correct), the Known Limitation on linearity analysis during lowering, and the
historical parenthetical line numbers throughout the body, which now carry a
blanket warning at the top of the document.

## Code bug found and filed, not fixed

`specs/todos/2026-08-25-effects-ml-docstring-claims-a-call-path-that-does-not-exist.md`
— `lib/effects/effects.ml`'s doc comment asserts "All paths (eval and compile)
pass through this function via [bin/main.ml]", which is false. Low severity, no
runtime effect, but it makes a bypassed module look load-bearing. Left unfixed
because this was a docs-only change.

## Validation

`scripts/check-docs.sh` exits 0.
