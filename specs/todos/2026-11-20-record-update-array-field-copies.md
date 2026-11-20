# `{ r with f: set(r.f, ..) }` still copies the array

Logged 2026-11-20, from specs/progress/2026-11-20-array-field-set-in-place.md.

A native-array field set in place when the record's fields are read out first
(`let lanes = r.lanes` .. `{ walk: walk, lanes: set_int(lanes, i, v), .. }`).
The record-update form

```march
{ occupied with lanes: NativeArray.set_int(occupied.lanes, i, v) }
```

still copies the whole array on every set: `EUpdate` reads the base's other
fields after the new field's value is computed, so the record is alive (and
holds the array) while the set runs. So does any field read after the set.

Likely fix: lower an `EUpdate` whose base is owned and dead after it, and whose
new values consume a native array, as field reads of the kept fields first and
an `ERecord` after (the shape Perceus now releases early), or reuse the base
cell in place (FBIP) after taking the field out of it.

Ur works around it by writing its four hot sites field-first (lane_set,
mark_crossing, Food.enqueue, Scene.face).
