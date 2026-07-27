# SIMD cross-language benchmark: elementwise (x * 2.0 + 1.0). Matches bench/simd_map.march
import time

n = 5_000_000
xs = [(i % 100) / 100.0 for i in range(n)]
t0 = time.perf_counter()
mapped = [x * 2.0 + 1.0 for x in xs]
t1 = time.perf_counter()
total = 0.0
for x in mapped:
    total += x
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
