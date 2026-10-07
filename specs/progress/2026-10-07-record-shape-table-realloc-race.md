# Record shape table: lock-free readers raced the intern's realloc

**FIXED 2026-10-07.**

`runtime/march_extras.c` keeps the record shape registry in `rec_shape_table`
(index = shape id - 1). `march_record_shape_intern` appended under
`rec_shape_mu` and grew the array with `realloc`. `rec_shape_of`, which every
dynamic field access goes through (`march_record_field_dyn`, the record
builtins), read `rec_shape_count` and `rec_shape_table` with no lock. A reader on
one scheduler thread could index the array that a concurrent intern on another
thread had just freed.

Seen in merge train E's CI (`sanitize-gate`, run 37629862795, two-node
`cluster_ap_restart`):

```
ERROR: AddressSanitizer: heap-use-after-free ... READ of size 8
  #0 march_record_field_dyn
  #1 __drop$CnState
  #2 ClusterNode__ClusterNodeActor_Unregister
freed by thread T1 here:
  #0 realloc
  #1 march_record_shape_intern
```

Fix: growing allocates a fresh array, copies the entries, and publishes it with a
release store. The old array is retired, not freed, so an in-flight reader still
indexes valid memory; retired memory is bounded by the final table size since
the table doubles. `rec_shape_count` is published with a release store after the
new entry is written. `rec_shape_of` loads count and table with acquire, so an
id it accepts always lands in a table that holds that entry.
