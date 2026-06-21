// Deque operations benchmark — matches bench/deque_ops.march (100 rounds)
// Uses std::collections::VecDeque: mutable, amortised O(1) push/pop both ends.
// Unlike March's functional deque, VecDeque reuses the ring-buffer in place —
// no allocation during steady-state push/pop once capacity is stable.
// Expected output: 20001000000
fn main() {
    use std::collections::VecDeque;
    let mut total: i64 = 0;
    for _ in 0..100 {
        let mut d: VecDeque<i64> = VecDeque::with_capacity(20001);
        for n in (1..=10000i64).rev() {
            d.push_front(n);
            d.push_back(n + 10000);
        }
        while let Some(v) = d.pop_front() {
            total += v;
        }
    }
    println!("{}", total);
}
