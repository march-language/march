`[P1]` The interpreter and the compiled build resolve some names differently, so one program prints
two different answers.

Found by the second soundness review of reflection phase 1a (2026-10-30); it predates reflection
(reproduces with `MARCH_REFLECT=0`, and with no refinement at all). Probes, in the review's scratch
area `review1a2/`:

- `use1/m.march`, `use1/m2.march`, `use2/m.march`: a module-local `fn g` and a `use A.*` that also
  supplies `g`, in either order. Which `g` a call means depends on the backend (and in `use2` the two
  `g`s have different types).
- `slist2.march`: an entry module with a nested `mod List do fn sum_int(xs) = 42 end` and a call
  `List.sum_int([1, 2])`: interpreted `42`, compiled `3` (the stdlib's).
- `al1/m2.march`: `alias A as B` placed before `mod B do fn g(n) = n + 50 end`, then `B.g(1)`:
  interpreted `51`, compiled `2`.

What is needed: one resolution rule (local, enclosing modules innermost first, `use`, `alias`) shared
by the typechecker, the interpreter and lowering, or an `ambiguous_name` error where two of them can
supply a name. Until then the refinement checker treats every such site as unresolved and never
unfolds it (`Refine_term.graph.ambiguous`, `specs/progress/2026-10-30-reflection-phase1a.md`).

## 2026-11-09: two of the three shapes fixed; a user module named like a stdlib module is open

Reproduced on `9f14c7358` with single-file probes:

| Probe | Interpreted | Compiled | Now |
|---|---|---|---|
| `fn sum_int` then `use List.*`, call `sum_int` | 3 (List's) | 102 (local) | 102 on both: the interpreter's bulk `use` (`UseAll`/`UseExcept`) skips a name the current module defines (`Eval.local_def_scopes`), the rule the typechecker already had (`env.local_fns`) |
| `alias A, as: B` plus a declared `mod B`, call `B.g(1)` | 51 (declared `B`) | 2 (alias target) | compile error `alias_shadows_module` (`Typecheck.check_alias_shadows_module`) |
| entry-level `mod List do fn sum_int ...`, call `List.sum_int([1, 2])` | 42 (user's) | 3 (stdlib's) | **still open** |

Pinned by the codegen parity test "a local fn shadows a later `use M.*` on both backends" and
`test/errors/alias_shadows_module_1`.

**Why the last one is bigger.** A module nested in the entry module lowers to the same
qualified TIR names as a stdlib module of the same name (`List.sum_int` both), so the two
definitions are one symbol to the backend, and the stdlib's wins when the stdlib module is
linked in. When it is not (a user `mod Queue` whose `empty` clashes with the stdlib's, in a
program that never uses the stdlib `Queue`), the user's wins and both backends agree, so a
blanket "a user module may not be named like a stdlib module" error would reject working
programs. A real fix gives an entry-level nested module's functions their own TIR names when a
stdlib module of that name exists (or qualifies every user module under the entry module's
name), and rewrites the user's call sites to match, without touching the stdlib's own calls.

## 2026-11-10: the last shape fixed

An entry-file module whose top-level name is also a stdlib module (or a module from another file)
now lowers its fns under their own TIR names (`List.sum_int` -> `List.sum_int$u`), and every
reference in the entry file that resolves to one is mapped to it, so `List.sum_int([1, 2])` is 42 on
both backends while the rest of the stdlib `List` stays reachable. The same tests found the
interpreter wrong inside that module: a bare sibling call (which desugar qualifies to
`List.sum_int`) reached the stdlib's fn; the module's env now binds the qualified name to its own
fn. Details: `specs/progress/2026-11-10-user-stdlib-name-collisions.md`.
