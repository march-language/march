# SIMD cross-language benchmark, float32 variant: a * 2.0 + 1.0. Matches bench/simd_f32.march's map leg.
import time
import numpy as np

n = 5_000_000
a = ((np.arange(n) % 100) / 100.0).astype(np.float32)
t0 = time.perf_counter()
mapped = a * np.float32(2.0) + np.float32(1.0)
t1 = time.perf_counter()
total = mapped.sum()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
