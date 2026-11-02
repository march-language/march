# The string layout is internal at 1.0 (road-to-1.0 decision 8, revised)

Decided 2026-10-31. The 2026-10-30 decision was "tune the existing inline small-string encoding,
then freeze it". Its premise was wrong: `specs/plans/2026-07-27-string-sso.md` stopped after
Task 1, so the encoding, its accessors and `march_sso_selftest` exist, but no string is ever
created inline (`march_string_lit` and every constructor allocate). Finishing it means routing
~413 runtime C reads of `->len`/`->data`, the codegen's string accesses and the JIT through
accessors before anything can be "tuned", and 7 bytes is the hard maximum of a tagged pointer.

**Measured** (macOS arm64, compiled `--opt 2`, `MARCH_STRING_STATS=1`, median of 5 user times;
a C microbenchmark over the runtime's own objects puts one small allocate+copy+free at 13.1 ns):

| benchmark | strings ≤ 7 bytes | share of string allocs | ceiling of the saving |
|---|---|---|---|
| iolist_template (templating) | 53,164 | 53% | 2.3% |
| json_stream (JSON parse) | 360,218 | 86% | 7.9% |
| json_stream_strings | 6,011 | 43% | 1.6% |
| string_build | 500,002 | 100% | 21.8% |
| string_pipeline | 200,002 | 100% | 26.2% (10 ms run, coarse) |
| string_small_churn | 4,206,194 | 42% | 18.4% |
| string_split_large | 9,000,061 | 100% | 56.1% |
| string_slice_walk | 9,000,000 | 100% | 84.2% |
| string_case, string_scan | 0 | 0% | 0% |

The ceiling ignores the branch the flip adds to every string read, which the workloads with no
short strings would only pay. Realistic workloads are bounded at 2-8%; the large numbers come
from synthetic benches that chop a buffer into 3-byte fields, the pattern the SSO plan warns
inline strings flatter without fixing.

**Decision:** the in-memory layout of values, strings included, is not part of the 1.0 promise
(`specs/lang/compatibility.md`, "What is not promised"). C code already reaches String only
through `runtime/march_ffi.h` (`march_value`, `march_slice`, `march_str_new`), and
`scripts/check-runtime-sources.sh` Check 5 now fails if that header ever names the string struct
or its fields (red with a `march_string` line appended, green without). The inline encoding can
land in any 1.x as a pure speedup. The slicing/splitting allocation cost is to be attacked
directly; it needs its own design (a borrowed view has the same every-reader cost as the inline
flip).

## The slicing cost, attacked directly (decided 2026-10-31: allocation-free APIs)

A borrowed-view string would have the same every-reader cost as the inline flip, so the
allocation the synthetic benches show is addressed with APIs that don't need it:

- `String.index_of_from` (search from a byte offset) already existed; the comment in
  `bench/string_slice_walk.march` that said it was missing is corrected.
- New `String.fold_split(s, sep, acc, f)`: `split`'s fields, one at a time, with no list.
- New `String.fold_split_ranges(s, sep, acc, f)`: the fields' byte ranges, with no allocation.
  Both give exactly `split`'s fields (property tests in `test/stdlib/test_string.march`).

Measured (`bench/string_split_fold.march` against `bench/string_split_large.march`, same buffer
and 60 iterations; compiled `--opt 2`, median user time of 7, maximum RSS): `split` 0.20 s and
25 MB; `fold_split` 0.20 s and 4 MB; `fold_split_ranges` 0.06 s and 4 MB.

**Found and fixed on the way:** the interpreter's `String.split` returned the wrong fields for a
repeating multi-byte separator: `String.split(",,,,", ",,")` gave `["", ",,"]` (compiled code
gave `["", "", ""]`). Its loop also matched inside the previous match, computed a negative
length, and the exception ended the loop early. It now matches only at or after the previous
match's end (`lib/eval/eval_builtins.ml`); pinned in `test/stdlib/test_string.march`.

**Filed:** `MARCH_STRING_STATS` never counts string frees
(`specs/todos/2026-10-31-string-stats-frees-never-counted.md`), so its `peak_live_bytes` is
cumulative; the memory figures above are maximum RSS instead.
