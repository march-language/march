# Setting a record's native array field writes in place (done 2026-11-20)

Reported from Ur: with walkers posed on the GPU, a profile of its
100,000-citizen replay spent about 11% of the main thread in `memmove` and
`native_int_arr_set`: whole-array copies in `Food.enqueue`, `lane_set`,
`mark_crossing` and `Scene.face`, each of which reads an array field out of a
record and sets it.

## Cause

`native_*_arr_set` writes in place only when it holds the array's one
reference. In

```march
pfn lane_set(o : Occupied, i : Int, v : Int) : Occupied do
  let lanes = o.lanes
  ...
  { walk: walk, lanes: NativeArray.set_int(lanes, i, v), ... }
end
```

the record always held a second one:

- Borrow inference (`lib/tir/borrow.ml`) classified `o` borrowed: an `EField`
  source is a read. The caller kept `o` alive across the call.
- Owned (inlined into a caller that owns it), Perceus still released `o` at
  the end of the scope, after the set: a field read from a record that is only
  ever projected is a borrowed alias into it, which keeps it alive, and
  `insert_owned_aggregate_param_drops` drops an owned parameter at each path's
  end.

A micro-benchmark of 20,000 sets on a 200,000-element array: 1.6 s (a copy per
set), against 0.33 s for the same sets on a bare array.

## Fix

- `Borrow.owned_in`: a native-array field read out of the parameter and then
  consumed (`let lanes = o.lanes in .. set_int(lanes, ..)`) makes the
  parameter owned.
- `Perceus_core` (`dup_owned_field`): when the rest of the scope hands a
  native array to a call (`Borrow.consumes_native_array`), every field read
  out of an owned record takes its own reference at the read, even when the
  record is only ever projected, so no borrowed alias points into it.
- `Perceus.insert_owned_aggregate_param_drops`: an owned parameter the rest of
  the path no longer mentions (itself or through an alias) is released there,
  not at the path's end, when that rest consumes a native array.

Each rule is limited to scopes that consume a native array, so other
functions' RC shape is unchanged. With the fix, the micro-benchmark's
let-extract, match-destructure and rebuild forms run at the bare-array speed,
and an `Occupied`-shaped record with String and List fields went from 1.67 s to
0.19 s with identical output (also under `MARCH_SANITIZE=1`).

## Not covered

`{ r with lanes: set_int(r.lanes, i, v) }` still copies: the update reads `r`'s
other fields after the set. So does reading a field after the set. Read the
fields out first.

## Tests

`test/test_codegen.ml` (unboxed_aggregates): "a record's array field set
releases the record first" (the IR of `lane_set` releases the record before
`native_int_arr_set`; unpatched, it never releases it) and "compiled array
field sets equal the interpreter".
