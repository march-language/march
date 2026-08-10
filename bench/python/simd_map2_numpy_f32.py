# SIMD cross-language benchmark, float32 variant: elementwise a[i] + b[i]. Matches bench/simd_f32.march's map2 leg.
import time
import numpy as np

n = 5_000_000
a = ((np.arange(n) % 100) / 100.0).astype(np.float32)
b = ((np.arange(n) % 100) / 100.0 + 1.0).astype(np.float32)
t0 = time.perf_counter()
combined = a + b
t1 = time.perf_counter()
total = combined.sum()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
