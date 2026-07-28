// SIMD cross-language benchmark: elementwise (a[i] + b[i]). Matches bench/simd_map2.march
use std::time::Instant;

fn main() {
    let n: usize = 5_000_000;
    let a: Vec<f64> = (0..n).map(|i| (i % 100) as f64 / 100.0).collect();
    let b: Vec<f64> = (0..n).map(|i| (i % 100) as f64 / 100.0 + 1.0).collect();
    let t0 = Instant::now();
    let combined: Vec<f64> = a.iter().zip(b.iter()).map(|(x, y)| x + y).collect();
    let elapsed = t0.elapsed();
    let total: f64 = combined.iter().sum();
    println!("RESULT {}", total);
    println!("TIME_MS {}", elapsed.as_secs_f64() * 1000.0);
}
