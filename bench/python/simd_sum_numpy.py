# SIMD cross-language benchmark: sum a Float array. Matches bench/simd_sum.march
# NumPy: hand-tuned, BLAS/vectorized-backed reference implementation.
# Data generation is NOT timed -- see bench/simd_sum.march for why.
import time
import numpy as np

n = 5_000_000
arr = (np.arange(n) % 100) / 100.0
t0 = time.perf_counter()
total = arr.sum()
t1 = time.perf_counter()
print(f"RESULT {total}")
print(f"TIME_MS {(t1 - t0) * 1000.0}")
