# `[P4]` `MARCH_STRING_STATS`: string frees are never counted, so `peak_live_bytes` is cumulative

Filed 2026-10-31 while measuring `String.fold_split` (`specs/progress/2026-10-31-string-abi-internal.md`).

`march_string_stats frees` reads 0 for every program measured (`bench/string_split_large`,
`bench/string_split_fold`), while `live_objs` at exit is 3-5. So freeing a string never reaches
the stats hook that increments `str_free_count` and subtracts from `str_live_bytes`
(`runtime/march_runtime.c` ~360-370): strings are freed through the generic object free path.
As a result `peak_live_bytes` is really total string bytes allocated, and it reported 39.8 MB for
`fold_split`, which holds one field at a time (maximum RSS 4 MB, against 25 MB for `split`).

Fix: call the string-stats free hook from wherever a `march_string` is actually freed (or count
string frees by type tag in the generic free), then check `frees` and `peak_live_bytes` against
the two benchmarks above.
