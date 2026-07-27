# SIMD cross-language benchmark: sum a Float array. Matches bench/simd_sum.march
# Naive Python list + for-loop -- the interpreted, non-vectorized floor.
# Data generation is NOT timed -- see bench/simd_sum.march for why.
import time

n = 5_000_000
xs = [(i % 100) / 100.0 for i in range(n)]
t0 = time.perf_counter()
total = 0.0
for x in xs:
    total += x
t1 = time.perf_counter()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
