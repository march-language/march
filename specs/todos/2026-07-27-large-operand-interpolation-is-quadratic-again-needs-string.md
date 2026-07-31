# Large-operand interpolation is quadratic again — needs `string_concat_n` (OPEN, 2026-07-27)


`fceea07b` removed the `string_join` cons-list path, so every interpolation now
desugars to a `++` chain folded into three-way `string_concat3` calls. That is
the right call for the common case — measured here with SHORT (8-byte)
operands, the concat3 chain beats `string_join` at *every* size tested, with no
crossover up to 20 operands:

| operands | chain | join |
|---|---|---|
| 2  | 30ms  | 59ms  |
| 5  | 77ms  | 108ms |
| 8  | 121ms | 157ms |
| 20 | 302ms | 350ms |

But `string_concat3` still re-copies the accumulated prefix at every step, so
with LARGE operands the single remaining shape is quadratic, and the join path
that used to cover that band is gone:

| operands | chain (4KB operands) | join (4KB operands) |
|---|---|---|
| 4  | 16ms   | 13ms |
| 8  | 87ms   | 23ms |
| 16 | 356ms  | 49ms |
| 32 | 1236ms | 97ms |

Restoring a count-based threshold would not fix this: the parser knows operand
COUNT but not operand SIZE, and these two tables disagree about the right
choice at the same count. The fix that removes the tradeoff entirely is a
length-summing **`string_concat_n`** — sum all parts once, allocate once, copy
once — which would dominate both shapes at every size with no cons cells.
Blocked on the constraint that forced the fixed-arity `string_concat3` fold in
the first place: March builtin signatures are `Mono (TArrow ...)` and cannot be
variadic, so this needs either a variadic builtin mechanism or a
spread-into-array calling shape.
