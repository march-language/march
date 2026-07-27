// SIMD cross-language benchmark: sum a Float array. Matches bench/simd_sum.march
// Data generation is NOT timed -- see bench/simd_sum.march for why.
use std::time::Instant;

fn main() {
    let n: usize = 5_000_000;
    let arr: Vec<f64> = (0..n).map(|i| (i % 100) as f64 / 100.0).collect();
    let t0 = Instant::now();
    let total: f64 = arr.iter().sum();
    let elapsed = t0.elapsed();
    println!("RESULT {}", total);
    println!("TIME_MS {}", elapsed.as_secs_f64() * 1000.0);
}
