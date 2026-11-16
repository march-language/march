`[P2]` A generic fn whose type variable is only in its return type returns a niche `None` that a niche-unsafe caller decodes Boxed (compiled SIGSEGV at 0x8).

Found while fixing #1173 (`specs/progress/2026-11-07-poly-let-none-niche-unsafe.md`).
It predates that fix and has a different root cause.

## Repro

```march
mod Main do
  needs IO.Console

  fn make_none() : Option(a) do
    None
  end

  fn pick(o : Option(Float)) : String do
    match o do
    | None -> "none"
    | Some(f) -> float_to_string(f)
    end
  end

  fn main(_c : Cap(IO.Console)) : () do
    let x : Option(Float) = make_none()
    println(pick(x))
  end
end
```

The interpreter prints `none`. Compiled at `--opt 0` to `3` it dies with
`fatal SIGSEGV ... addr=0x8`, with or without the annotation on `x`.

## Cause

`Mono.rewrite_calls` builds a specialisation from the callee's PARAMETER types only
(`build_subst`). With no type variable in the parameters, `make_none` goes through the
"callee params are monomorphic" arm and is emitted once, generic. Its
`alloc Option.None('a)()` is niche-encoded (raw null) under the `Option(TVar)`
convention, while the caller holds an `Option(Float)`, which is Boxed, and loads the tag
from `ptr + 8`. `check_repr_disagreement` only runs on the other arm, so nothing reports
the mismatch.

## Done when

The call site's return type also drives specialisation, or mono refuses the call the
way `check_repr_disagreement` refuses a non-specialisable call. The repro above, at
`Option(Float)`, `Option(())` and `Option(Option(Int))`, matches the interpreter at every
`--opt`.

## Related

A poly `let` binding used at two different concrete types
(`let x = None; f(x : Option(Float)); g(x : Option(Int))`) is not specialised by the
#1173 fix, because one value cannot serve both types. It needs one copy per type. No
crashing case has been seen yet.
