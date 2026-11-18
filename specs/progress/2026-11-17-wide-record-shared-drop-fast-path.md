# A shared release of a wide record loaded every heap field first (FIXED)

Reported from Ur: in a 100,000-citizen release replay at 3x on an M3 Max, 338 of
871 sampled main-thread stacks were inside the generated drop of `Ur.Sim.City`,
a 105-field record with 75 heap fields. The helper loaded and spilled all 75
fields and only then called `march_decrc_freed`, which told it the record was
still shared, so the loads were thrown away.

## Cause

`Drop.build_aggregate_drop_fn` (`lib/tir/drop.ml`) built

    fn __drop$R(x) = let f1 = x.a in ... let fN = x.z in
                     let freed = march_decrc_freed(x) in
                     case freed of True -> drop f1; ...; drop fN | _ -> ()

`march_decrc_freed` frees the shell at the last decrement, so the field loads
had to sit in front of it, on the shared path as well. LLVM cannot sink them:
the call may free the memory they read.

## Fix

Two runtime entry points split "the count reached zero" from "free the cell":

- `march_decrc_last(p)` decrements atomically and returns 1 iff the caller held
  the last reference, without freeing. It returns 0 for a shared cell, an
  immortal cell and a non-heap word.
- `march_free_last(p)` frees a cell whose count `march_decrc_last` took to
  zero: the same tail a last-reference release runs (destructor and string
  stats for a reserved cell kind, the live gauge, the free). Sanitizer builds
  abort if the count is not zero.

The helper is now

    fn __drop$R(x) = let last = march_decrc_last(x) in
                     case last of
                       True -> let f1 = x.a in ... let fN = x.z in
                               march_free_last(x); drop f1; ...; drop fN
                       _    -> ()

On the last-reference path the helper is the sole owner (count zero, no other
holder to take a reference from), so it reads the fields, frees the shell and
then releases the children; the shell's storage stays owned until the reads
finish. The free still precedes the child drops, so the last one stays in tail
position. A shared release reads the header and nothing else.

`march_decrc_last` has an inline twin (`__march_rc_decrc_last`,
`lib/tir/llvm_rc_inline.ml`); its last-reference block returns 1 and frees
nothing, and an underflow goes to `march_rc_last_atomic`, which aborts. The
decrement is atomic at every site, as `march_decrc_freed` was, so a release
racing on another thread is unchanged. The gc trace is unchanged too:
`march_decrc_last` emits the `free` event `march_decrc_freed` emitted and
`march_free_last` emits none.

Not changed: variant drops (`build_drop_fn`) and closure-environment releases
still use `march_decrc_freed`. A variant's fields are bound by the `ECase` that
dispatches on its tag, so reordering it is a different change.

Tried and dropped: moving the last-owner body into a `noinline` function so the
shared path has no frame. It removed the 320-byte frame and six callee-saved
pairs from the helper's entry but measured within noise (0.355 s against
0.358 s), so it was not worth a second function per record.

## Measured

`bench/wide_record_shared_drop.march`: a 48-field record (36 Strings) held by
`main`, stored in a `Holder` cell and dropped 30,000,000 times, `--opt 2`, M3
Max, user CPU seconds, 15 interleaved runs each (load average about 30):

|        | min   | median | max   |
|--------|-------|--------|-------|
| before | 0.430 | 0.479  | 0.488 |
| after  | 0.301 | 0.358  | 0.397 |

## Tests

- `test/test_codegen.ml` "deep drop: a record is released before its fields are
  loaded": on the emitted helper, `march_decrc_last` precedes every field load,
  `march_free_last` follows the last load and precedes the first child release,
  and `march_decrc_freed` is absent.
- `test/native/record_shared_release.march`: shared releases with the record
  read afterwards, final releases, a shared-then-final pair, and releases
  racing across scheduler threads through 8 tasks; `live_allocs()` growth is 0
  on every leg.
