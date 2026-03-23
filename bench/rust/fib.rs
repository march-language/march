// Naive recursive Fibonacci — matches bench/fib.march (fib(40))
fn fib(n: u64) -> u64 {
    if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

fn main() {
    println!("{}", fib(40));
}
