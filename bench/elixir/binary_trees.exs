# Binary Trees benchmark — matches bench/binary_trees.march (depth=15)
# Allocates and walks complete binary trees to stress the allocator/GC.
defmodule BinaryTrees do
  def make(0), do: :leaf
  def make(d), do: {:node, make(d - 1), make(d - 1)}

  def check(:leaf), do: 1
  def check({:node, l, r}), do: check(l) + check(r) + 1

  def pow2(0), do: 1
  def pow2(n), do: 2 * pow2(n - 1)

  def sum_trees(0, _depth, acc), do: acc
  def sum_trees(iters, depth, acc) do
    sum_trees(iters - 1, depth, acc + check(make(depth)))
  end

  def run_depths(d, max_depth, _min_depth) when d > max_depth, do: :ok
  def run_depths(d, max_depth, min_depth) do
    iters = pow2(max_depth - d + min_depth)
    s = sum_trees(iters, d, 0)
    IO.puts("#{iters} trees of depth #{d} check: #{s}")
    run_depths(d + 2, max_depth, min_depth)
  end

  def main do
    n = 15
    min_depth = 4
    max_depth = if n > min_depth + 2, do: n, else: min_depth + 2
    stretch = max_depth + 1

    IO.puts("stretch tree of depth #{stretch} check: #{check(make(stretch))}")

    long_lived = make(max_depth)
    run_depths(min_depth, max_depth, min_depth)

    IO.puts("long lived tree of depth #{max_depth} check: #{check(long_lived)}")
  end
end

BinaryTrees.main()
