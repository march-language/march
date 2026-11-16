`[P3]` Laws for `List.zip`, `unzip`, `enumerate`, `concat` and `split_at` (2026-11-15)

`march --check --law-coverage stdlib/list.march` still lists these public pure functions as
uncovered. Each loops in a nested `go` with an accumulator, and a lemma can only name a
top-level function, so the loop has to be lifted to a top-level `pfn` first (as `take` was to
`take_onto` and `length` to `length_onto`), then proved through accumulator lemmas like
`reverse_onto_append`.

Laws worth having: `len(zip(xs, ys)) == min(len(xs), len(ys))`, `len(enumerate(xs)) ==
len(xs)`, `split_at(xs, n) == (take(xs, n), drop(xs, n))`, `len(concat(xss))` as the sum of
the lengths, and `unzip(zip(xs, ys))` when the lengths agree.

The same holds for `Enum.count`, `Enum.sum`, `Enum.product`, `Enum.with_index`,
`Sort.reverse_list` and `Sort.append_list` (found by the 2026-11-16 coverage sweep): each loops
in a nested `go`.

Lifting changes the compiled code's shape, so run `bench/list_ops.march` before and after.
Follow-up to `progress/2026-11-15-stdlib-laws-pass.md`.
