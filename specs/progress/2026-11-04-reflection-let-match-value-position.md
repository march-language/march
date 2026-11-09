`[P2]` Reflection: a `let` whose right-hand side is a `match` or `if` unfolds

From todo `2026-10-31-reflection-encoder-gaps` ("a `match` in a non-tail value position").
`Refine_reflect.tr_case`'s block `let` arm translates the rest of the block once per case of
the right-hand side, each under that case's conditions, exactly as a tail `match` is; at most
`max_let_cases` (16) cases, else the body declines as before.

Tests: `reflect-lemma` `let_match` (`depth2(Ez) == 10`, `depth2(Cz(x, Ez)) == x + 1`) and
`let_match_red` (a false theorem is reported violated).
