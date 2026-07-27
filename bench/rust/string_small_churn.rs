// Rust counterpart of bench/string_small_churn.march.
//
// The control that matters: Rust's String has NO small-string optimization, so
// it allocates per string exactly as March does. If March trails Rust here, the
// gap is allocator and refcount overhead rather than representation -- which a
// size-class freelist addresses. If March matches Rust, a further win needs
// true inline storage, a much larger change. C++ (with SSO) bounds that.
//
// Must print checksum=17793810, identical to the March version.
fn main() {
    let mut acc: i64 = 0;
    for i in 0..2_000_000i64 {
        let name  = String::from("x-req-") + &(i % 97).to_string();
        let value = String::from("v") + &i.to_string() + "-abcdefgh";
        // concat() over a slice is one allocation, matching what March's
        // three-way concat folding does for `name ++ ": " ++ value`.
        let pair  = [name.as_str(), ": ", value.as_str()].concat();
        let bump  = if pair.starts_with("x-req-") { 1 } else { 0 };
        acc += name.len() as i64 + bump;
    }
    println!("checksum={}", acc);
}
