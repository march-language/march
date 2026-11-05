# Type-directed suggestions (diagnostics-depth X8, tier 2 and total twins)

Lands tier 2 of §X8 in `specs/plans/2026-11-02-diagnostics-depth-plan.md` and the first item
of tier 3 (total twins). Tier 1 is `specs/progress/2026-11-03-diag-did-you-mean-tier1.md`.
The rest of tier 3 (solver-checked guards, ranking by provability and by capability) stays
open in `specs/todos/2026-11-02-diag-did-you-mean-ranking.md`.

## Trial unification that leaves no trace

`lib/typecheck/typecheck_suggest.ml`. Every fit test is a real unification, run against a
private substitution instead of the live union-find:

- live types are only read: `walk` follows `Link`s without the path compression `repr` does;
- binding a variable records it in the trial's hashtable, never in the live `tvar ref`;
- no fresh variable is minted (`fresh_id` is never called); a lambda argument's placeholder
  variables get negative ids, which the live counter never produces;
- `try_unify` undoes a failed attempt's bindings from a trail (union-find with undo), so the
  argument positions of one call are scored in one trial, each against the bindings the
  earlier positions made;
- candidates are printed by a local printer (`pp_local`) that names variables in order of
  appearance, because `pp_ty` names them through a global table and printing with it would
  shift the names in later diagnostics.

Every search runs only after a diagnostic has been reported, so an accepted program's
inference is unchanged by construction; the types oracle confirms it (TIER1 CORE-AST
IDENTICAL against the merge base).

## What changed

- **Search by call shape.** `I cannot find `f`.` and `Module `Q` does not export `f`.` with
  no spelling candidate get "These `Q` functions take these arguments:" and up to three
  signatures, for in-scope functions of the call's arity whose parameters unify with the
  arguments' types (with three or more arguments, all but one, marked "argument #k
  differs") and whose result unifies with what the position needs. A candidate must fit on
  at least one position where both sides have a known head (a bare type variable takes
  anything and is no evidence); more such positions rank higher. When the best tier is
  larger than three, the names the typo is a prefix-spelling of win (`fodl` → `fold_left`,
  `fold_right`, not `preduce`, `scan_left`); otherwise nothing is shown. Hooked in the
  `EApp` arm of `infer_expr`: the arguments of an unknown callee are inferred exactly as the
  `TError` callee path did, and their types fed to the search; `with_suggest_need` now also
  records an `EApp`'s expected type.
- **Argument permutations.** When a call reports a type mismatch in its arguments and the
  callee takes the same (two or three) arguments in exactly one other order, judged from the
  arguments' syntax-evident types (literals, variables, lambda arity), the first mismatch says
  "The two arguments are the other way round: `List.map(xs, fn x -> x * 2)` fits." with the
  swap as its fix.
- **Conversions.** A mismatch between two plain types (no type parameters) with no
  hand-written hint looks for in-scope `S -> T` functions. The name is the evidence: an
  unqualified candidate must name both types as `_`-separated words (`bool_to_string`,
  `celsius_to_fahrenheit`), a member of `S`'s or `T`'s module the other type
  (`String.from_int`); by type alone `String -> Int` is also `String.byte_size`, and
  `Int -> Pid(a)` exists and forges a pid. The result must be exactly `T`: a parse returning
  `Option(Int)` does not fit where an `Int` is needed (offering one on every String/Int
  mismatch, mostly string literals and branch mismatches, was tried and was noise). The
  hand-written hints in `common_mismatch_hint` stay as overrides.
- **Total twins (tier 3, item 1).** A call that fails its callee's precondition
  (`refinement_violated`, `undeclared_requirement`) gets a note naming `f_opt` when it
  resolves, takes as many parameters, refines none, and returns `Option(R)` / `Result(R, _)`
  for `f`'s own return type `R`, with the `match` it needs. A definition-table lookup, no
  solver call (`Refine_check.total_twin`).

Corpus: `unknown_qualified_name_6` (`List.fodl`), `unbound_variable_1` (a bare unknown
callee; the annotated `Float` picks `average` over the generic `head`), `type_mismatch_43`
(`List.map` arguments swapped, with fix), `_44` (the program's own `celsius_to_fahrenheit`),
`_45` (`bool_to_string`),
`refinement_violated_16` / `_17` (`head_opt`, `nth_opt`), `undeclared_requirement_1`.
Goldens moved: `refinement_violated_6`, `_12`, `_14` gain the twin note; nothing else.

Known overlap left for X4 (hint exclusivity): on a swapped call the first mismatch still
carries `common_mismatch_hint`'s "This value is a function. Did you forget to apply it…"
next to the permutation note.
