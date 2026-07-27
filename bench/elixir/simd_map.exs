# SIMD cross-language benchmark: elementwise (x * 2.0 + 1.0). Matches bench/simd_map.march
xs = for i <- 0..4_999_999, do: rem(i, 100) / 100.0
t0 = System.monotonic_time()
mapped = Enum.map(xs, fn x -> x * 2.0 + 1.0 end)
t1 = System.monotonic_time()
total = Enum.sum(mapped)
IO.puts("RESULT #{total}")
IO.puts("TIME_MS #{System.convert_time_unit(t1 - t0, :native, :microsecond) / 1000.0}")
