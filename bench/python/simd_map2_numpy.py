# SIMD cross-language benchmark: elementwise (a[i] + b[i]). Matches bench/simd_map2.march
import time
import numpy as np

n = 5_000_000
a = (np.arange(n) % 100) / 100.0
b = (np.arange(n) % 100) / 100.0 + 1.0
t0 = time.perf_counter()
combined = a + b
t1 = time.perf_counter()
total = combined.sum()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
