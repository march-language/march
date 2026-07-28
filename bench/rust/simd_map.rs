// SIMD cross-language benchmark: elementwise (x * 2.0 + 1.0). Matches bench/simd_map.march
use std::time::Instant;

fn main() {
    let n: usize = 5_000_000;
    let arr: Vec<f64> = (0..n).map(|i| (i % 100) as f64 / 100.0).collect();
    let t0 = Instant::now();
    let mapped: Vec<f64> = arr.iter().map(|x| x * 2.0 + 1.0).collect();
    let elapsed = t0.elapsed();
    let total: f64 = mapped.iter().sum();
    println!("RESULT {}", total);
    println!("TIME_MS {}", elapsed.as_secs_f64() * 1000.0);
}
