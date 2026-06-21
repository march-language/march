# Merkle tree benchmark — matches bench/merkle.march (1024 leaves, 50 rounds)
# Uses :crypto.hash(:sha256, ...) from Erlang/OTP (hardware-accelerated on most hosts).
# Expected output: 6400
defmodule MerkleBench do
  def sha256_hex(s),
    do: :crypto.hash(:sha256, s) |> Base.encode16(case: :lower)

  # Nodes are {hash, left, right} tuples; leaves have left=nil.
  def make_leaf(val),    do: {sha256_hex(val), nil, nil}
  def make_branch(l, r) do
    {hl, _, _} = l; {hr, _, _} = r
    {sha256_hex(hl <> hr), l, r}
  end

  def hash_of({h, _, _}), do: h

  def build_range(vals, lo, hi) when hi - lo == 1,
    do: make_leaf(elem(vals, lo))
  def build_range(vals, lo, hi) do
    mid = div(lo + hi, 2)
    make_branch(build_range(vals, lo, mid), build_range(vals, mid, hi))
  end

  def diff_count({ha, _, _}, {hb, _, _}) when ha == hb, do: 0
  def diff_count({_, nil, _}, _),                        do: 1
  def diff_count(_, {_, nil, _}),                        do: 1
  def diff_count({_, la, ra}, {_, lb, rb}),
    do: diff_count(la, lb) + diff_count(ra, rb)

  def run_once do
    vals_a = 0..1023 |> Enum.map(&Integer.to_string/1) |> List.to_tuple()
    vals_b =
      0..1023
      |> Enum.map(fn i ->
        if rem(i, 8) == 0, do: "modified_#{i}", else: Integer.to_string(i)
      end)
      |> List.to_tuple()
    ta = build_range(vals_a, 0, 1024)
    tb = build_range(vals_b, 0, 1024)
    diff_count(ta, tb)
  end

  def run do
    total = Enum.reduce(1..50, 0, fn _, acc -> acc + run_once() end)
    IO.puts(total)
  end
end

MerkleBench.run()
