# SIMD cross-language benchmark: elementwise (a[i] + b[i]). Matches bench/simd_map2.march
import time

n = 5_000_000
a = [(i % 100) / 100.0 for i in range(n)]
b = [(i % 100) / 100.0 + 1.0 for i in range(n)]
t0 = time.perf_counter()
combined = [x + y for x, y in zip(a, b)]
t1 = time.perf_counter()
total = 0.0
for x in combined:
    total += x
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
