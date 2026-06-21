# Deque operations benchmark — matches bench/deque_ops.march (100 rounds)
# Uses Erlang's :queue module (two-list functional deque built into OTP).
# :queue.in_r/2 = push_front, :queue.in/2 = push_back, :queue.out/1 = pop_front.
# Expected output: 20001000000
defmodule DequeOps do
  def push_phase(q, 0), do: q
  def push_phase(q, n) do
    q |> :queue.in_r(n) |> :queue.in(n + 10000) |> push_phase(n - 1)
  end

  def drain(q, acc) do
    case :queue.out(q) do
      {:empty, _}         -> acc
      {{:value, v}, rest} -> drain(rest, acc + v)
    end
  end

  def run do
    total =
      Enum.reduce(1..100, 0, fn _, acc ->
        q = push_phase(:queue.new(), 10000)
        acc + drain(q, 0)
      end)
    IO.puts(total)
  end
end

DequeOps.run()
