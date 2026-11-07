# Proof hints: `assert … by`, `calc`, `reveal`, `with fuel` (2026-11-06)

Closes quick wins 1, 2 and 4 of `specs/todos/2026-11-06-verification-ladder-roadmap.md`
(todos `2026-11-06-proof-assert-by`, `-proof-calc-blocks`, `-proof-reveal-and-local-fuel`).
Language reference: `specs/lang/lemmas.md`, "Proof hints".

## What changed

- **AST.** One node, `EProof of proof * span`, with `PAssertBy`, `PReveal`, `PWithFuel` and
  `PCalc` (`lib/ast/ast.ml`), and `proof_children` / `map_proof` so every traversal handles it in
  one line. Every exhaustive matcher got an arm (about 40 sites).
- **Syntax** (`lib/parser/parser.mly`, `proof_stmt`): `assert e by hint` (`by` was already a
  keyword, from `choose … by`), `reveal f`, `with fuel(f, N) do … end` (`fuel` checked by name
  after the `with` keyword), and `calc do e0 op e1 [by h] … end`, where operands are parsed at
  the additive level so a leading `==` on the next line starts a step instead of continuing the
  term. A hint is any call-level expression, which includes a `do … end` block. `calc` and
  `reveal` are new keywords (no identifier of either name in the repo). The grammar has the same 7
  shift/reduce conflicts as before; `assert assert p by h` gives the `by` to the inner assert
  (`%prec prec_assert`).
- **Semantics** (`lib/refinecheck/refine_check.ml`):
  - `proof_assert_by` proves `P` under the path plus `hint_path` (each hint lemma call's theorem
    and each assert, in order), through `lemma_assert` (now with a `?callee` label). A proved `P`
    is pushed for the statements after it; the hints' facts are not. Static in every context: a
    function's `assert … by` is never a runtime check, so an unproved one is not assumed.
  - `proof_calc` proves step i (`prev op_i rhs_i`) with only that step's hint, reports it as
    `calc step i`, and pushes every proved step.
  - `reveal f` pushes `f` onto `Reflect_state.revealed` for the rest of the block. An `@[opaque]`
    function blocked by R9 alone, with every callee reflected and alone in its SCC, is marked
    revealable by `Refine_reflect.analyze`; when the program contains a `reveal`, `install` gives
    it a symbol and template and files its call sites in `Reflect_state.hidden_call_sym`, which
    `resolve_site` reads only while the function is revealed. Its row and every caller's verdict
    are unchanged, so a program with no `reveal` sees no difference.
  - `with fuel(f, N)` sets `Reflect_state.fuel_override` (clamped 1-8) while its body is walked;
    `Refine_reflect`'s unfolding reads `fuel_for` instead of the template's fuel.
- **Erasure** (`lib/desugar/lemma_erase.ml`): every proof statement becomes `()`, except a
  `with fuel` body, which stays as a block. The interpreter and lowering have total arms too.
- **Typechecking**: `assert … by` checks `P : Bool` and types the hints; `calc` types each step
  as the comparison it is; `with fuel` has its body's type.
- **Tools**: the formatter prints each form on one line; `--emit-core-ast` dumps `EProof` with
  its sub-kind; tree-sitter (`assert … by`, `reveal_expression`, `with_fuel_expression`,
  `calc_expression`; parser regenerated with 0.26.7).

## Verification

| Check | Result |
|---|---|
| `proof-hints` group (12): assert-by proves and assumes P (one call / a block), hint facts do not leak, an unproved assert-by is not assumed, erased (program runs), `reveal` proves `need4(dbl(2))` with `@[opaque] dbl` and is scoped to its block, `with fuel(cnt, 5)` proves `cnt(3) == 3` (default fuel skips), its body still runs, calc proves each step and the chain, a wrong middle step is reported as `calc step 2` with nothing assumed, mixed `==`/`<=` | RED (parse errors) → GREEN, 12/12 |
| The two `lemmas.md` examples | both prove (`assert`, `calc step 1/2`, `need_eq`) |
| `scripts/check-tree-sitter.sh` | ok (1739/1743 clean, 4 known failures as before; keywords listed) |
| Menhir | 7 shift/reduce conflicts, as on main; no reduce/reduce |
| `scripts/affected.sh --run --full` | see the PR |
