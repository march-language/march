# DONE Unboxed Float calls through closures

Filed 2026-09-30 (`specs/todos/2026-09-30-float-closure-unboxing.md`), done
2026-10-01. Spec: `specs/plans/2026-09-30-float-closure-unboxing.md` (its
"As built" section records where the implementation differs from the design).

## The problem

Every closure call uses one erased ABI in which a Float crosses heap-boxed.
Inside a higher-order function such as `List.fold_left` the callback is a
parameter, so the call is indirect and always boxes: a Float fold over a list
cost about 90 ns per element.

## The change

`lib/tir/hof_spec.ml`, two passes in `lib/tir/contract_pipeline.ml`:

- `specialize`, after Defun and before Known_call. A call that passes a known
  closure allocation to a function whose closure parameter is static (passed
  unchanged to every self-call, never rebound, called indirectly) is redirected
  to a per-lambda clone in which the indirect call is a direct call. The clone
  keeps the closure parameter, so ownership is unchanged. A worklist carries the
  known closure into clone bodies, which is what specializes TRMC's `map$dps`
  loop. Only functions reachable from the program's roots are considered; at
  most 16 clones per function; body budget 200 nodes.
- `redirect_unboxed`, after Opt. A direct call to an apply fn with a Float/Int
  signature goes to a `$ufast$` clone emitted with native parameters.

Off for JS, under hot reload, and with `MARCH_NO_HOF_SPEC=1`, which is also a
CAS-key tag in `bin/main.ml`.

## Verification

- `test/native/hof_spec_closures.march`: 11 cases (fold_left Float/Int,
  capturing and not, map, filter, a user HOF with one lambda at two call sites, a
  non-static HOF, an identity-like lambda, an empty list). Its `.expected` is
  the interpreter's output, and the pass-off build prints the same. A second rule
  pins the IR shape: 2 clones of the user HOF, none of the non-static one.
- Perturbation: dropping the static-argument check specialized the non-static
  HOF and turned one fixture line red (32 instead of 26); restoring it turned it
  green.
- Refcount balance under `MARCH_TRACE_GC`: capturing folds called 500 and 1,000
  times leave the same 2 live objects with the pass on and off; allocations fell
  from 11,011 to 2,011.
- ASAN (Linux container, `MARCH_SANITIZE=1`): 48 programs clean, every
  `test/native` program that passes a lambda to a List HOF (minus network-bound
  ones) plus the fixture and two benchmarks.
- `dune build --root . @test/runtest`: the only failure was the refinement audit
  corpus baseline gaining the new fixture's two lines; regenerated.
- Benchmarks, same compiler with the pass on and off: `list_ops` 1.03×,
  `tree_transform` 0.98×, `binary_trees` 1.03×, all noise at load ~10.
  `bench/float_closure_calls.march`: Float `fold_left` 22.6×, Float `map` 2.9×.
- Compile time (`--emit-llvm`, 4 programs × 3 rounds): +0.1%.

## Not done

- The spec's "within 2× of the hand-written loop" target: Float `fold_left` is
  8.5 ms against 2.6 ms. The rest is a per-iteration closure refcount increment
  (a runtime call) and the yield check; see
  `specs/plans/2026-09-30-inline-rc-fast-path.md`.
- HOFs whose callback reaches a local helper (`each`, `scan_left`, `zip_with`)
  are not specialized.
- Hot reload: the pass is simply off under `--hot-reload`.
