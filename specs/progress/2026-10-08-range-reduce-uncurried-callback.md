# `Range.reduce` passes an uncurried callback to `List.fold_left`

`Range.reduce` declared the same curried function type as `List.fold_left`,
but wrapped its callback as two nested single-argument lambdas.  The fold
applies its callback with both arguments at once, so the wrapper returned a
function instead of an accumulator: the interpreter raised an arity error and
native output was invalid.

The wrapper now uses a two-parameter lambda.  The regression fixture applies
an order-sensitive reducer to `Range.new(1, 6)` with a nonzero seed and expects
`712345` on the interpreter, optimized native, and no-opt native backends.

The type check that distinguishes a tuple-parameter function from a
multi-parameter lambda is separate from this runtime bug and remains out of
scope.

Verified with:

```sh
dune build --root . test/native_range_reduce.out test/native_range_reduce_no_opt.out test/interp_range_reduce.out
diff -u test/native/range_reduce.expected _build/default/test/native_range_reduce.out
diff -u test/native/range_reduce.expected _build/default/test/native_range_reduce_no_opt.out
diff -u test/native/range_reduce.expected _build/default/test/interp_range_reduce.out
```
