# `to_string` of a List leaks 4–5 objects per call (compiled)

Found 2026-09-13 while fixing read-only builtin leaks
(`specs/progress/2026-09-13-builtin-borrow-classification.md`).

```march
pfn leg(n : Int, acc : Int) : Int do
  if n <= 0 do acc else
    let xs = [n, 7]
    leg(n - 1, acc + string_length(to_string(xs)))
  end
end
```

`--compile --opt 2`, 10,000 calls, `live_allocs` delta:

| element type | delta |
|---|---|
| `List(Int)` `[n, 7]` | 50,003 |
| `List(String)` `[int_to_string(n), "x"]` | 40,004 |

These are measured after the builtin-borrow fix, so `string_length` of the
result is released. Mono rewrites `to_string(xs)` to `Show$List.show$List_…`
(stdlib), so the builtin `to_string` is never called. The leak is inside that
implementation or its helpers, which build the output by concatenation.

Start with `MARCH_DUMP_TXT=perceus` on the reduction, then read
`Show$List.show`'s TIR for intermediate strings without a `dec_rc`. Guard it
with a `live_allocs` delta probe that prints the computed value, not
`let _ = …`, because a discarded pure call is dead-code eliminated (the trap
the builtin probe hit).
