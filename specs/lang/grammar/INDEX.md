# Grammar corpus index (p01–p14 parse, r01–r08 reject; Task 1 seeded p01–p02/r01–r02, Task 2 added p03–p08/r03–r04, Task 3 added p09–p11/r05–r06, Task 4 added p12–p14/r07–r08)

Navigable map of the resolved-grammar conformance corpus: each program in
this directory (`specs/lang/grammar/parse/*.march`,
`specs/lang/grammar/reject/*.march`) to the grammar section/rule it anchors
in `specs/lang/grammar.md`. See that document for the full per-rule prose.

## The `--check` parse/reject harness model

Like `specs/lang/types/` (the static-semantics corpus), this corpus has only
**one** parser to check against — it runs identically regardless of whether
the pipeline continues to `eval` or `--compile`. The anchor is the compiler's
own `--check` mode (`march --check file.march`: exit 0 = parsed [+ typed],
exit 1 + a diagnostic = rejected):

- **`parse/*.march`** — must parse: `march --check file.march` must exit
  **0**. Kept **well-typed** so exit 0 unambiguously isolates "this parsed"
  (not "this parsed but then failed to typecheck") — the tricky part these
  programs are meant to exercise is the *syntax*, so the types are kept
  trivial.
- **`reject/*.march`** — must fail to **parse**: `march --check file.march`
  must exit **1**, AND its output must contain the exact substring named in
  the program's own first-line annotation, `-- EXPECT-ERROR: <substring>`.
  The pinned substring must be a **parse** diagnostic (e.g. `` I don't
  recognize `then` here ``, `I got stuck here`), never a type error — this
  corpus isolates the parser, not the typechecker. Some substrings are
  menhir's generic fallback message rather than a bespoke one; that is
  expected and intentional (see `grammar.md` §1's honesty note on this).

Run the whole corpus:

```
MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/grammar/check_grammar.sh
```

Exit 0 iff every program behaves as declared (currently 22/22 — 14 parse, 8
reject).

**Naming note:** this corpus uses `parse/` + `reject/` (not `accept/` +
`reject/` like `types/`) — an intentional, acknowledged divergence: "must
parse" reads truer for a grammar corpus than "must accept". The harness
shape is otherwise identical to `types/check_types.sh`.

## Program index

| Program | Grammar section / rule anchored | What it witnesses |
|---|---|---|
| [`parse/p01_block_newline_separation.march`](parse/p01_block_newline_separation.march) | §3.3 (newline-glom, `Block` context, baseline swallow-by-default) | A plain `fn ... do ... end` body with three `let`-bound block expressions separated only by source newlines; every `NL` between them is deleted by `token_filter` before menhir sees the stream (no context is `Match`, so the "swallow by default" rule applies throughout). Prints the correct sum, evidencing the block parsed as three sequential statements, not one runaway expression. |
| [`parse/p02_match_multi_expr_arms.march`](parse/p02_match_multi_expr_arms.march) | §3.3 (newline-glom inside `Match`, the arm-boundary lookahead), §3.4 (`is_pattern_start` used as the lookahead's pre-filter) | A `match` with two arms, each a **multi-expression body** (`let`/`let`/final-expr). Exercises every branch of the arm-boundary state machine: `NL` after `ARROW` suppressed, `NL` after each internal `let` suppressed (bails on `LET` at depth 0), and the `NL` before the second arm's `Square(side) ->` correctly emitted as the arm separator (lookahead reaches `ARROW` at depth 0 after crossing the `LPAREN...RPAREN` of `Square(side)`). Run (non-`--check`) it prints `36` then `16` — the *only* correct output if the arm boundary resolved exactly where §3.3 says it does, so this is a value-witness, not just a parse-witness. |
| [`reject/r01_then_keyword_rejected.march`](reject/r01_then_keyword_rejected.march) | §1 honesty note / (future §4) — `THEN` is a lexer token with no production that can ever complete a parse | `if true then ... else ... end` — `then` only appears in `parser.mly`'s dedicated error-recovery production (`IF; _c = expr; THEN; ...; error`), which unconditionally raises a diagnostic; there is no path from `THEN` to a value. Captured live: `` I don't recognize `then` here — March uses do/end blocks instead. `` |
| [`reject/r02_record_pattern_in_arm_unreachable.march`](reject/r02_record_pattern_in_arm_unreachable.march) | §3.4 (cross-check corollary: `LBRACE` is correctly absent from `is_pattern_start`, since no pattern production starts with it) / (future §6) — `PatRecord` has no surface production | `match 1 do { x } -> x end` — a record-shaped pattern in an arm position. `simple_pattern`/`pattern` have no production beginning with `LBRACE`, so `token_filter`'s `is_pattern_start` (§3.4) correctly does not list it either, and menhir rejects the construct outright with its generic fallback. Captured live: `I got stuck here`. This double-checks as a §3.4 witness now and will be promoted to the primary reachability witness for `PatRecord` in Task 4's §6. |
| [`parse/p03_additive_left_assoc.march`](parse/p03_additive_left_assoc.march) | §4.5 `expr_add` — left-associativity of `-` | `10 - 3 - 2` prints `5` (`(10 - 3) - 2`), not `9` (`10 - (3 - 2)`, what right-associativity would give) — a value-witness of `expr_add`'s left-recursive production. |
| [`parse/p04_mul_binds_tighter_than_add.march`](parse/p04_mul_binds_tighter_than_add.march) | §4.5 `expr_mul` binds tighter than `expr_add` (stratification, no `%prec` needed) | `1 + 2 * 3` prints `7`, not `9` — proves `*` binds before `+` purely from the stratum nesting (`expr_add`'s operands are `expr_mul`, not `expr_add`). |
| [`parse/p05_pipe_left_to_right_chain.march`](parse/p05_pipe_left_to_right_chain.march) | §4.2 `expr_pipe` — left-associativity of `\|>` | `3 \|> double \|> inc` prints `7` (`inc(double(3))`), not `8` (`double(inc(3))`) — witnesses `expr_pipe`'s left recursion (`expr_pipe PIPE_ARROW expr_or`). |
| [`parse/p06_field_access_vs_application.march`](parse/p06_field_access_vs_application.march) | §4.7 `expr_app` / §4.8 `expr_field` — field access resolves before becoming a call argument | `get(b.get)` prints `105` — `b.get` (`expr_field`) is fully reduced to a value before being passed as `expr_app`'s sole argument. |
| [`parse/p07_list_comprehension_with_guard.march`](parse/p07_list_comprehension_with_guard.march) | §4.9 list comprehensions (`expr_atom`-level, `desugar_list_comp`) | `[x * 2 for x in [1,2,3,4,5], x > 2]` prints `[6, 8, 10]` — filter-then-map desugaring order, binding a `pattern` after `for`. |
| [`parse/p08_comparison_binds_tighter_than_bool.march`](parse/p08_comparison_binds_tighter_than_bool.march) | §4.3/§4.4 — `expr_cmp` binds tighter than `expr_and`/`expr_or` | `1 < 2 && 3 > 2` prints `true`, only well-typed if `&&`'s operands are the two `Bool` comparison results, not `Int`s captured by a tighter-binding `&&`. |
| [`reject/r03_chained_comparison_nonassoc.march`](reject/r03_chained_comparison_nonassoc.march) | §4.4 `expr_cmp` — non-associativity (`%nonassoc EQEQ NEQ LT GT LEQ GEQ`, `parser.mly:217`) | `1 < 2 < 3` — both operands of a comparison are `expr_add`, one level down, not `expr_cmp` again, so chained comparisons have no derivation. Captured live: `I got stuck here`. |
| [`reject/r04_malformed_comprehension_missing_in.march`](reject/r04_malformed_comprehension_missing_in.march) | §4.9 list comprehensions — malformed form (missing `in <expr>`) | `[x * 2 for x]` — `for pattern` with no following `in expr`. Captured live: `I got stuck here` (menhir's generic fallback; no bespoke comprehension diagnostic exists). |
| [`parse/p09_block_let_sequencing.march`](parse/p09_block_let_sequencing.march) | §5.1 `block_body`/`block_expr` — sequencing with no separator token | Three chained `let`s (`a = 2`, `b = a * 3`, `c = b + 4`) then the bare final expression `c`, all separated only by source newlines already deleted by `token_filter` (§3.3) before menhir sees them. Prints `10` — proves the three `let`s bound in sequence, not nested/misparsed. |
| [`parse/p10_match_multi_expr_arms_three_way.march`](parse/p10_match_multi_expr_arms_three_way.march) | §5.3 `match` arm grammar — arm-boundary lookahead across mixed single-/multi-expression arms | A three-constructor `match` (`Circle`/`Square`/`Triangle`) where the first two arms are multi-expression bodies and the third is single-expression, deliberately mixing shapes to exercise the arm-boundary transition into, between, and out of multi-expression arms in one program. Prints `36`, `16`, `30` — extends §3.3's two-arm `p02` witness to three arms with a shape change. |
| [`parse/p11_if_else_if_chain.march`](parse/p11_if_else_if_chain.march) | §5.2 `if`/`else` — "`else if`" is `else` + a nested `if…end`, not a dedicated production | A 4-way `if … else if … else if … else … end end end` classification chain — note the three stacked trailing `end`s, one per nested `if`, since there is no `ELSIF` token/production eliding them. Prints `negative`/`zero`/`small`/`large` for `-5`/`0`/`3`/`100`. |
| [`reject/r05_letq_last_in_block.march`](reject/r05_letq_last_in_block.march) | §5.4 `let?` position constraint | `fn f() do let? x = Ok(1) end` — `let?` as the last `block_expr`. Parses fine (`fold_letq` produces `ELetQ(p, e, EBlock([], sp), sp)`); rejected at **typecheck**, not parse (`Typecheck.infer_expr`'s `ELetQ` case matches the empty-`EBlock` continuation). `march --check` still exits 1. Captured live: `` `let?` cannot be the last expression in a block. ``. |
| [`reject/r06_if_missing_else.march`](reject/r06_if_missing_else.march) | §5.2 `if` requires `else` — no bare `if` | `if x > 0 do 1 end` with no `else` branch — a genuine **parse**-stage rejection (`parser.mly:1058–1062`'s dedicated `error` alternative fires before typechecking). Captured live: `` March `if` expressions always need an `else` branch: ``. |
| [`parse/p12_nested_constructor_tuple_pattern.march`](parse/p12_nested_constructor_tuple_pattern.march) | §6.2 `pattern` — constructor patterns nesting a tuple pattern (`PatCon` wrapping `PatTuple`) | `match Pair(2, (3, 4)) do Pair(scale, (a, b)) -> ... end` destructures both the constructor's own args and its nested tuple arg in one pattern. Prints `14` (`2 * (3 + 4)`) — only obtainable if the nested destructure bound `scale=2, a=3, b=4` correctly. |
| [`parse/p13_rich_type_annotation.march`](parse/p13_rich_type_annotation.march) | §7.1 `ty` ladder — arrow right-associativity, tuple types, record types, generic `ty_app` | `mk: Int -> (Int, Int) -> { x: Int, y: Int }` parses as `Int -> ((Int, Int) -> {x,y})` per §7.1's right-recursive `ty` production; `type Pair(a, b) = MkPair(a, b)` exercises `type_params` + `ty_app` with type-variable arguments. Prints `10`, `20`, `one` — the curried arrow, tuple/record types, and generic instantiation all resolved as documented. |
| [`parse/p14_list_and_atom_payload_patterns.march`](parse/p14_list_and_atom_payload_patterns.march) | §6.2 `pattern` — atom patterns (`PatAtom`) and §6.1 list-literal pattern sugar (`PatCon(Cons/Nil, …)`) | `:ok(n)`/`:error(_msg)` atom-payload patterns and `[a, b]`/`[a, b, c]`/`[]` list-literal patterns in the same program. Prints `70`, `-1`, `3`, `6`, `0` — each value only obtainable if the corresponding atom/list-arity arm matched. |
| [`reject/r07_record_pattern_in_let_unreachable.march`](reject/r07_record_pattern_in_let_unreachable.march) | §6.3 reachability — `PatRecord` unreachable, witnessed at a second call site (`let`, not `match`) | `let { x } = r` — `simple_pattern` (what `let` accepts, §6.2) has no `LBRACE`-led alternative, same as full `pattern`. Captured live: `I got stuck here`. |
| [`reject/r08_as_pattern_unreachable.march`](reject/r08_as_pattern_unreachable.march) | §6.3 reachability — `PatAs` unreachable | `match 1 do x as y -> y end` — `x` fully reduces to `pattern` via the ordinary route, so `branch`'s dedicated error-recovery alternative fires wanting `ARROW`, not menhir's generic fallback. Captured live: `` I was expecting `->` in the match arm here ``. |

Task 2 (§4 Expressions, the precedence ladder) added p03–p08/r03–r04 above.
Task 3 (§5 Blocks & statements) added p09–p11/r05–r06: block-sequencing,
the `if`/`else if` stacking rule, the three-way `match` arm-boundary
witness, and the `let?`-last-in-block constraint (a typecheck-stage
rejection, called out explicitly since every other `reject/` program here
pins a parse-stage diagnostic). Task 4 (§6 Patterns, §7 Types) added
p12–p14/r07–r08: a nested constructor+tuple pattern, a rich curried/tuple/
record/generic type annotation, atom- and list-literal patterns, and the
two new `PatRecord`/`PatAs` reachability witnesses (`r02` from Task 1 is
the third, promoted to primary status in §6.3). Task 5 will extend this
table with the declaration-form corpus; see
`specs/plans/2026-07-06-resolved-grammar-plan.md` for the task breakdown.
