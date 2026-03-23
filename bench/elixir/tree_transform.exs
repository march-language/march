# Tree transform benchmark — matches bench/tree_transform.march (depth=20, 100 passes)
# inc_leaves maps over a tree incrementing every leaf value.
# Unlike March (Perceus FBIP, reuses nodes in-place), Elixir allocates fresh nodes each pass.
defmodule TreeTransform do
  def make(0), do: {:leaf, 0}
  def make(d), do: {:node, make(d - 1), make(d - 1)}

  def inc_leaves({:leaf, n}), do: {:leaf, n + 1}
  def inc_leaves({:node, l, r}), do: {:node, inc_leaves(l), inc_leaves(r)}

  def sum_leaves({:leaf, n}), do: n
  def sum_leaves({:node, l, r}), do: sum_leaves(l) + sum_leaves(r)

  def repeat(t, 0), do: t
  def repeat(t, n), do: repeat(inc_leaves(t), n - 1)

  def main do
    depth = 20
    passes = 100
    t = make(depth)
    t2 = repeat(t, passes)
    IO.puts(sum_leaves(t2))
  end
end

TreeTransform.main()
