# `[P3]` A relational scalar return (`{Int | _ > x}`) does not discharge a caller's closed demand

Filed 2026-10-21 from the inference-lite design (§0, row G1).

```march
fn inc(x : Int) : {Int | _ > x} do x + 1 end
fn go(n : {Int | _ >= 0}) : Int do need_pos(inc(n)) end
```

`need_pos(inc(n))` stays `solver-undecided` (also with `_ == x + 1`): the relational return is not
substituted at the call and combined with `n`'s fact. Related: `specs/todos/2026-10-18-refine-relational-scalar-demand.md`.

## Resolution (2026-10-24)

Fixed: `need_pos(inc(n))` proves. The relational return was already substituted at the
actuals (`inc$ret > n`). The caller's own fact about `n` never reached the query. Also fixed
here: a capture of the named return binder, which was unsound. Details:
`specs/progress/2026-10-24-refine-demand-chains.md`.
