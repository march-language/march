// Binary Trees benchmark — matches bench/binary_trees.march (depth=15)
enum Tree { Leaf, Node(Box<Tree>, Box<Tree>) }

fn make(d: u32) -> Tree {
    if d == 0 { Tree::Leaf } else { Tree::Node(Box::new(make(d - 1)), Box::new(make(d - 1))) }
}

fn check(t: &Tree) -> i64 {
    match t {
        Tree::Leaf => 1,
        Tree::Node(l, r) => check(l) + check(r) + 1,
    }
}

fn main() {
    let (n, min_depth): (u32, u32) = (15, 4);
    let max_depth = n.max(min_depth + 2);
    let stretch = max_depth + 1;
    println!("stretch tree of depth {} check: {}", stretch, check(&make(stretch)));

    let long_lived = make(max_depth);
    let mut d = min_depth;
    while d <= max_depth {
        let iters = 1i64 << (max_depth - d + min_depth);
        let sum: i64 = (0..iters).map(|_| check(&make(d))).sum();
        println!("{} trees of depth {} check: {}", iters, d, sum);
        d += 2;
    }
    println!("long lived tree of depth {} check: {}", max_depth, check(&long_lived));
}
