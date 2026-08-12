# SIMD cross-language benchmark, float32 variant: sum(a). Matches bench/simd_f32.march's sum leg.
# Same shapes as simd_sum_numpy.py but with explicit dtype=np.float32 (the default
# arange/divide pipeline produces float64, which is what the original table measured).
import time
import numpy as np

n = 5_000_000
a = ((np.arange(n) % 100) / 100.0).astype(np.float32)
t0 = time.perf_counter()
total = a.sum()
t1 = time.perf_counter()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
