// Higher-order function pipeline — matches bench/list_ops.march
// range(1..=1M).map(*2).filter(%3==0).sum()
// Uses Rust iterators (zero-cost abstractions, fused into a single loop by the optimizer).
fn main() {
    let total: i64 = (1i64..=1_000_000)
        .map(|x| x * 2)
        .filter(|x| x % 3 == 0)
        .sum();
    println!("{}", total);
}
