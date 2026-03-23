# Naive recursive Fibonacci — matches bench/fib.march (fib(40))
defmodule Fib do
  def fib(n) when n < 2, do: n
  def fib(n), do: fib(n - 1) + fib(n - 2)
end

IO.puts(Fib.fib(40))
