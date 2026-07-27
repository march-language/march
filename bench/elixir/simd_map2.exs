# SIMD cross-language benchmark: elementwise (a[i] + b[i]). Matches bench/simd_map2.march
a = for i <- 0..4_999_999, do: rem(i, 100) / 100.0
b = for i <- 0..4_999_999, do: rem(i, 100) / 100.0 + 1.0
t0 = System.monotonic_time()
combined = Enum.zip_with(a, b, fn x, y -> x + y end)
t1 = System.monotonic_time()
total = Enum.sum(combined)
IO.puts("RESULT #{total}")
IO.puts("TIME_MS #{System.convert_time_unit(t1 - t0, :native, :microsecond) / 1000.0}")
