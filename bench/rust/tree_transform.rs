// Tree transform benchmark — matches bench/tree_transform.march (depth=20, 100 passes)
// Rust ownership means each inc_leaves call rebuilds the tree (consuming the old one).
// This is structurally analogous to Perceus FBIP but uses move semantics, not RC.
enum Tree { Leaf(i64), Node(Box<Tree>, Box<Tree>) }

fn make(d: u32) -> Tree {
    if d == 0 {
        Tree::Leaf(0)
    } else {
        Tree::Node(Box::new(make(d - 1)), Box::new(make(d - 1)))
    }
}

fn inc_leaves(t: Tree) -> Tree {
    match t {
        Tree::Leaf(n)      => Tree::Leaf(n + 1),
        Tree::Node(l, r)   => Tree::Node(Box::new(inc_leaves(*l)), Box::new(inc_leaves(*r))),
    }
}

fn sum_leaves(t: &Tree) -> i64 {
    match t {
        Tree::Leaf(n)    => *n,
        Tree::Node(l, r) => sum_leaves(l) + sum_leaves(r),
    }
}

fn main() {
    let mut t = make(20);
    for _ in 0..100 {
        t = inc_leaves(t);
    }
    println!("{}", sum_leaves(&t));
}
