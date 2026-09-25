# `[P1]` Compiled: a parameter named `eq` is called as the builtin `==`, so `Map` ignores its comparator

Filed 2026-09-24. Found while writing the NaN golden for
`specs/progress/2026-09-25-compare-nan-backends.md`.

## Reproduction

```march
mod EqProbe do
  needs IO.Console

  pfn via_eq(eq, a, b) do
    eq(a, b)
  end

  pfn via_f(f, a, b) do
    f(a, b)
  end

  fn main(_c : Cap(IO.Console)) do
    let always = fn (a : Int, b : Int) -> true
    println("via_eq(always, 1, 2): " ++ bool_to_string(via_eq(always, 1, 2)))
    println("via_f(always, 1, 2): " ++ bool_to_string(via_f(always, 1, 2)))
  end
end
```

| | interpreted | `--compile` |
|---|---|---|
| `via_eq(always, 1, 2)` | true | **false** |
| `via_f(always, 1, 2)` | true | true |

Compiled, the call `eq(a, b)` on the PARAMETER `eq` is lowered as the builtin
`eq` (the `Eq` method), which is `==`. `--dump-tir` of a program using `Map`
shows it inside `Map.node_get`: the source's `eq(lk, key)` has become
`==(lk, key)`, while the unused `eq` closure is only `dec_rc`'d.

## Why it matters

`stdlib/map.march` names its derived-equality closure `eq` in `get`, `insert`,
`remove` and the node helpers (`let eq = fn (a, b) -> cmp_eq(cmp, a, b)`), so a
compiled `Map` compares keys with `==` and never calls the caller's `cmp`:

- A `Map` keyed by `Float` with a NaN key: `Map.get(m, nan, ...)` is `None`
  compiled (`nan == nan` is false) and `Some` interpreted; re-inserting the NaN
  key adds a second entry compiled.
- Any comparator whose equality is not `==` (case-insensitive strings, keys
  compared by one field) behaves differently on the two backends.

Check the other stdlib modules for parameters or locals named like a builtin
(`eq`, `compare`, `hash`, `show`) that are then called.

## Direction

Lowering must resolve a call through a local binding (parameter, `let`, pattern
variable) to that binding before looking the name up as a builtin or interface
method, as the interpreter does. Compare the known
"module-level fn named like a builtin typechecks as the builtin" issue: this
one is the same name-resolution order problem, but at the lowering stage and
for locals.

## Acceptance

The repro above prints `true` twice on both backends, and a native golden with
a `Float`-keyed `Map` holding a NaN key (get, re-insert, size) matches
interpreted and compiled.

## Related

Also seen while writing that test, not investigated: compiled, passing a
top-level function that RETURNS a closure (`fn curried_lt(a : Int) : Int -> Bool
do fn b -> a < b end`) as a value to a generic function that calls it curried
(`let f = cmp(a)` then `f(b)`) exits with SIGSEGV (139); interpreted it works.
A lambda with the same shape works compiled.
