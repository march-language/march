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

## Fixed 2026-11-16

The call site's return type now drives specialisation (`Mono.ret_only_subst`). For a
callee whose return type still holds a type variable that the parameters do not bind,
the variable is matched against the call's concrete return type: the callee variable's
`TFn` result, or for a zero-argument call the callee variable's own type (lowering types
`make_none` at the result, `Option(Float)`, not at a function type). The body is then
specialised per return type and named by it (`mangle_name` over the parameter types plus
the return type), both in the "callee params are monomorphic" arm and, for a callee with
some parameter variables and a further return-only one, in the general arm. The
specialised body's `alloc Option.None(...)` uses the same variable as the declared return
type, so the substitution reaches it and the `None` is Boxed like its consumer.

A return type that is a bare type variable (`panic : a`, `todo`, `unreachable`) is left
alone: with no parameter mentioning it, the callee can only diverge and builds no value
whose layout depends on it, and codegen and the RC passes recognise those functions by
their unmangled name (the `panic` builtin row, the diverging-call lists). A first version
without this exclusion renamed `panic` calls to `panic$String$Float`, which the IR oracle
caught (`List.head`'s panic went through `march_panic_ext` instead of the `panic` builtin).

IR oracle vs `40d029234`: 129 of 518 programs change. 73 are fresh-name renumbering only.
56 gain per-return-type copies of `Vault.new`/`Vault.open`
(`Result(Vault(v), CapError)`), `Toml.err`, `Json.bad_number`, `Task.async`,
`Process.run_stream` and `Actor.call`, plus the helpers and drop glue those now-monomorphic
bodies reach. Total IR size of the changed programs grows 0.82%.

Regression: `test/test_codegen.ml` "return-only type variable specialised per call site"
(`make_none()` at `Option(Float)`, `Option(())`, `Option(Option(Int))` and `Option(Int)`,
a one-parameter `none_after(n) : Option(a)`, and `fail(msg) : Result(a, String)`), at
`--opt 0` to `3`. RED before: SIGSEGV at 0x8, exit 139.

Not covered: the "Related" poly-`let` case above (one binding used at two types).
