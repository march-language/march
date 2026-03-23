# Higher-order function pipeline — matches bench/list_ops.march
# range(1..1M) |> map(*2) |> filter(%3=0) |> sum
# Tests Enum pipeline performance (BEAM JIT vs March native).
total =
  1..1_000_000
  |> Enum.map(&(&1 * 2))
  |> Enum.filter(&(rem(&1, 3) == 0))
  |> Enum.sum()

IO.puts(total)
