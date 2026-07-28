# SIMD cross-language benchmark: sum a Float array. Matches bench/simd_sum.march
# BEAM has no flat numeric array type or auto-vectorization; this is a plain
# List + Enum, the idiomatic BEAM way, included as the honest "no SIMD" floor.
# Data generation is NOT timed -- see bench/simd_sum.march for why.
xs = for i <- 0..4_999_999, do: rem(i, 100) / 100.0
t0 = System.monotonic_time()
total = Enum.sum(xs)
t1 = System.monotonic_time()
IO.puts("RESULT #{total}")
IO.puts("TIME_MS #{System.convert_time_unit(t1 - t0, :native, :microsecond) / 1000.0}")
