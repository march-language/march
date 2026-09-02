# Function-head binders now count as structurally smaller (and a soundness hole closed)

**Filed:** 2026-09-01  **Resolved:** 2026-09-02

The identical structurally-recursive tree walk compiled as a single `fn` with
an explicit `match` (warning only) and was a hard ERROR written with multi-head
function heads. Two defects, one found while fixing the other.

## 1. Tuple scrutinee defeated the parameter test

Desugar merges multi-head clauses into one `EMatch`. For a function of ONE
parameter the scrutinee is `EVar $a0`; for TWO OR MORE it is a synthesised
tuple, `match ($a0, $a1) do (Branch(l,v,r), t) -> …`
(`desugar.ml`'s general path). `scrutinee_is_param_or_smaller` only recognised
a bare `EVar`, so a tuple scrutinee was never "a parameter", no arm binder was
marked structurally smaller, and ordinary structural recursion became an error.

That is why the bug looked arity-dependent: `fn g(Branch(l,v,r))` was accepted
while `fn g(Branch(l,v,r), t : Int)` was not.

`arm_smaller_vars` now pairs a tuple scrutinee against a tuple pattern
**position by position**, which is required for correctness rather than
convenience: in `(Branch(l,v,r), t)` against `($a0, $a1)`, `l`/`v`/`r` are
components of `$a0` and ARE smaller, while `t` binds the whole of `$a1` and is
NOT. Treating the synthesised tuple as a single destructuring would have
wrongly made `t` smaller and accepted `h(t, t)` as decreasing.

## 2. Whole-value arm binders were treated as smaller

Found while fixing the above. The arm logic marked *every* arm binder smaller
when the scrutinee was a parameter, including one that names the whole value —
so this was ACCEPTED before this change, and does not terminate:

```march
fn loopy(x : Int) : Int do
  match x do
    y -> 1 + loopy(y)      -- y IS x
  end
end
```

Only sub-component binders are smaller now. A bare `PatVar`, and the name bound
by `as`, are not.

## The correction the conformance corpora caught

The first cut dropped whole-value binders from BOTH sets, which broke
`fib(n - 1) + fib(n - 2)`: `n` is not smaller, but it IS another name for the
matched value, so arithmetic reduction on it still decreases. The unit suite
stayed green; `@grammar-check` caught it as
`p15_multi_head_fn_merge.march` ("should parse but was rejected"), and the
`@oracle` sweep caught it again as two fresh `INTERP_FAIL`s
(`examples/hello.march`, `examples/pattern_matching.march`).

So the model needs two sets, not one:

- **whole-value** binders (`PatVar`, the `as` name) → the PARAMETER set, so
  `n - 1` still counts as a reduction, while bare `n` does not;
- **sub-component** binders (anything under a constructor / tuple / record) →
  the SMALLER set.

`params` is now threaded through `chk` so it can grow per arm, alongside the
`smaller` set that was already threaded.

## Verification

| case | before | after |
|---|---|---|
| multi-head tree walk | 2 errors | 0 errors, 2 warnings |
| same code as explicit `match` | 0 errors, 2 warnings | unchanged |
| `fib(n-1) + fib(n-2)` | accepted | accepted |
| destructuring param + plain param | 2 errors | accepted |
| `loopy` (recurse on whole-value binder) | **accepted** | **rejected** |
| `f(x)`, `f(Cons2(h,t))` non-terminating | rejected | rejected |

- `scripts/run-tests.sh` green.
- `@types-check --force`: 303/303 (`--force` matters — without it the alias
  exits 0 with a zero-byte log and proves nothing).
- `@grammar-check --force`: 48/48.
- `@oracle --force`: 2 un-triaged divergences, **identical to a pristine
  `origin/main` control** (`bench/array_numeric.march`, `bench/simd_f32.march`
  — both SIMD/numeric, unrelated). Running the control is what separated the
  2 pre-existing failures from the 2 this change had introduced.

Five regression tests in `test/test_compiler.ml`, the central one asserting the
A/B directly: the multi-head and explicit-`match` spellings must reach the SAME
verdict, so they cannot silently diverge again.
