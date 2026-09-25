# `[P3]` Interpreter: a nested module calling a parent fn declared AFTER it dies with "stub called before initialisation"

Filed 2026-09-25 while fixing the compiled side of the same shape
(`specs/progress/2026-09-25-nested-module-parent-call.md`).

```march
mod Main do
  needs IO.Console
  mod Outer do
    mod Inner do
      fn g(x : Int) : Int do later(x) end
    end
    fn later(x : Int) : Int do x * 10 end
  end
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(Outer.Inner.g(4)))
  end
end
```

`march --check` accepts it, and `march --compile` output prints `40`. The
interpreter exits 1:

```
stub later called before initialisation
  [0] later()                  main.march:5
  [1] Outer.Inner.g()          main.march:10
```

The same happens when `Outer` is a `MARCH_LIB_PATH` module. If `later` is
declared before `mod Inner`, it works. The interpreter seems to bind the
nested module's closures eagerly, capturing the parent's placeholder stub for
`later`. The later definition then does not patch that stub.

Workaround: declare the parent fn before the nested module.

Guard to add once it is fixed: interpret the program in
`test_nested_module_parent_call_lib_path_compiled` (`test/test_codegen.ml`),
which today checks the compiled output only because of this bug.
