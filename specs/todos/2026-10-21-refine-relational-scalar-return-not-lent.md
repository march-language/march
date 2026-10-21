# `[P3]` A relational scalar return (`{Int | _ > x}`) does not discharge a caller's closed demand

Filed 2026-10-21 from the inference-lite design (§0, row G1).

```march
fn inc(x : Int) : {Int | _ > x} do x + 1 end
fn go(n : {Int | _ >= 0}) : Int do need_pos(inc(n)) end
```

`need_pos(inc(n))` stays `solver-undecided` (also with `_ == x + 1`): the relational return is not
substituted at the call and combined with `n`'s fact. Related: `specs/todos/2026-10-18-refine-relational-scalar-demand.md`.
