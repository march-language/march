# The compiled capability ceiling misses a stdlib function passed as a value (2026-11-17)

Found by ocap phase 4 Task 8. A nested module that hands a capability-bearing
stdlib function out as a VALUE escapes the compiled (TIR) ceiling:

```march
mod CeilValue do
  needs IO.Console
  needs IO.FileRead
  mod Inner do
    needs IO.Console
    fn apply1(f : (String) -> a, p : String) : a do f(p) end
    fn go() : () do
      match Authority.must(apply1(File.read, "/etc/hosts")) do
        Ok(_)  -> Authority.ignore(println("ok"))
        Err(_) -> Authority.ignore(println("e"))
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) : () do
    Inner.go()
  end
end
```

`march --check` rejects it (`Module Inner uses IO.FileRead but does not declare
needs IO.FileRead`), but `march --compile --cap-strict` builds it. The same
program written `apply1(fn p -> File.read(p), ...)` is rejected by both.
`Cap_attrib.walk` (lib/tir/cap_attrib.ml) charges a builtin passed as an atom
(`atom_cap`) but never adds an `ADefRef` to the callees, so a function value's
own capabilities never reach the module that passes it.

This predates Task 8; Task 8 made it the only spelling of the route
test/test_cap_ceiling.ml "route: builtin passed as a value" used to pin (the raw
`file_read` value is now a `stdlib_internal` error, which that test now asserts).
What to do: add `ADefRef` names to the callees in `Cap_attrib.walk`, and add the
program above as a compiled reject case.
