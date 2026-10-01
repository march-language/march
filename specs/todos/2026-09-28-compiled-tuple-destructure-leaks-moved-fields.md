# Compiled: destructuring a tuple and moving its fields on leaks them

**Filed:** 2026-09-28, found while wiring compiled Logger appenders
(`specs/progress/2026-09-28-compiled-logger-appenders-are-no-ops.md`).

```march
mod Main do
  needs IO.Console
  type Box = Box(String, String)
  pfn g(b : Box) : Box do b end
  pfn f(t : (String, Int, String)) : Box do
    match t do
      (a, n, c) -> g(Box(a, c))
    end
  end
  pfn lp(i : Int, n : Int) : Unit do
    if i >= n do ()
    else
      let s = "x" ++ int_to_string(i)
      let _ = f((s, i, "y" ++ int_to_string(i)))
      lp(i + 1, n)
    end
  end
  fn main(_c : Cap(IO.Console)) do
    lp(0, 3)
    let b = live_allocs()
    lp(0, 10)
    println("delta: " ++ int_to_string(live_allocs() - b))
  end
end
```

Compiled, this prints `delta: 20`, two objects per call (the two moved
strings). Two variants print `delta: 0`:
- the same shape with a single-constructor type (`Raw(a, n, c) -> g(Box(a, c))`);
- the same function taking three parameters instead of one tuple.

In the emitted IR (`--emit-llvm`), the arm binds each field to a `$f`
temporary: moved in the unique branch, incremented in the shared one. It then
binds the pattern variable with a further `march_incrc_local`, and nothing
ever decrements the `$f` temporary. The constructor-pattern path does not
take that second increment.

The Logger appender bridge sidestepped this by using a constructor
(`Logger.AppenderCall`) instead of a 5-tuple. Its first version leaked one
object per dispatched message.

## Acceptance

The program above prints `delta: 0` compiled, and a leak-probe fixture pins it.
