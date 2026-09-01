# The non-tail-recursion warning promises a TRMC loop that does not happen

The warning emitted by `lib/typecheck/typecheck_tailcall.ml` for structural
non-tail recursion ends with:

> …may use O(depth) stack space; **when the recursive call is the direct
> argument of a constructor, the compiler turns it into a loop.**

That second clause does not hold. A function written in exactly the shape the
sentence describes still warns *and* still overflows the stack.

## Repro (compiled, `--opt 2`)

```march
mod Trmc2 do
  needs IO
  fn map_inc(xs : List(Int)) : List(Int) do
    match xs do
      Nil        -> Nil
      Cons(h, t) -> Cons(h + 1, map_inc(t))   -- direct arg of a constructor
    end
  end
  fn main(cap : Cap(IO)) : Unit do
    let xs = List.range(1, 400000)
    println("length = " ++ int_to_string(length(map_inc(xs))))
  end
end
```

`march --compile --opt 2` → emits the warning above, then the binary dies with
**exit 138 (SIGBUS, stack overflow)**. Same result for a record/`Option`-shaped
tree walk (`Cons(v, spine_values(a))`).

**Control (rules out the harness):** the same 400k list built and measured with
no user recursion —

```march
let xs = List.range(1, 400000)
println("control length = " ++ int_to_string(length(xs)))
```

— exits 0 and prints `399999`. So the overflow is the user recursion, not
`List.range`/`length`.

## Why it matters

The sentence reads as reassurance ("the compiler handles this shape"), so a
reader who writes the named shape and sees only a warning will reasonably ship
it. It then overflows on deep input. A misleading hint is worse than no hint.

## Options

1. **TRMC is meant to fire here and doesn't** — fix the pass so it does, and
   suppress the warning when it applies.
2. **TRMC is narrower than the sentence implies** — reword the warning to state
   the actual condition, and stop promising a loop for shapes that don't get
   one.

Either way the warning text and the compiler's real behaviour need to agree.
Worth checking against `specs/progress/`'s existing TRMC work
(`project_trmc_counter_determinism` in the agent's notes refers to a TRMC pass,
so the machinery exists) to determine which of the two this is.

## Workaround for users today

Carry an explicit worklist so the recursive call is genuinely in tail position;
verified stack-safe at 400k depth:

```march
pfn go(pending : List(BTree), target : Int) : Bool do
  match pending do
    Nil -> false
    Cons(t, rest) ->
      if t.value == target do true else go(push_kids(t, rest), target) end
  end
end
```
