# The capability ceiling does not charge an `impl` method in a nested module

Found 2026-11-10 while probing for ocap phase 3 (`specs/plans/2026-11-10-ocap-p3-checks-plan.md`).
Every mode accepts this, `--compile` included, although §4 of
`specs/2026-11-10-object-capability-design.md` charges an interface method to the impl's module:

```march
mod Main do
  needs IO.Console, IO.FileRead
  interface Src(a) do
    fn get : a -> String
  end
  mod Dep do
    needs IO.Console
    type Box = Box(String)
    impl Src(Box) do
      fn get(b) do
        match b do
          Box(p) -> match File.read(p) do
            Ok(s) -> s
            Err(_) -> ""
          end
        end
      end
    end
    fn make() : Box do Box("/etc/hostname") end
  end
  fn main(c : Cap(IO.Console), f : Cap(IO.FileRead)) do
    println(get(Dep.make()))
  end
end
```

Expected: `cap_ceiling`, module `Dep` uses `IO.FileRead`. Likely cause: the impl's TIR name
(`Src$Box.get`) resolves to a synthetic owner in `Cap_attrib.owner_of`, which no `needs` can
declare and which the ceiling skips. Fixing it newly rejects programs in every mode.
