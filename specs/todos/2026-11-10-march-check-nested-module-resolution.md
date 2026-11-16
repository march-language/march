# `march check` reports `Unknown module` for a call inside a twice-nested module

Found 2026-11-10 by `test/test_cap_mode_parity.ml` (fixture `ceiling_value`). `march check`
(`run_check_cmd`, the command `forge check`/`forge build` run) wraps every file's module in a
synthetic `LibCheck` module. On this program it reports
`error: Unknown module 'Inner'. [unknown_qualified_name]` at `Inner.go()` in `main`, while
`--check` and `--compile` accept it:

```march
mod Main do
  needs IO.Console, IO.FileRead
  mod Inner do
    needs IO.Console, IO.FileRead
    fn apply1(f : (String) -> a, p : String) : a do f(p) end
    fn go() : () do
      match apply1(file_read, "/x") do
        Ok(_)  -> println("ok")
        Err(_) -> println("e")
      end
    end
  end
  fn main(_c : Cap(IO.Console), _f : Cap(IO.FileRead)) : () do
    Inner.go()
  end
end
```

The parity test skips `ceiling_value` under `march_check` until this is fixed.
