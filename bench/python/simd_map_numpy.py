# SIMD cross-language benchmark: elementwise (x * 2.0 + 1.0). Matches bench/simd_map.march
import time
import numpy as np

n = 5_000_000
arr = (np.arange(n) % 100) / 100.0
t0 = time.perf_counter()
mapped = arr * 2.0 + 1.0
t1 = time.perf_counter()
total = mapped.sum()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
