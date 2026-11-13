# A path-scoped `needs IO.FileRead(...)` is not enforced at the stdlib wrappers (2026-11-12)

Found in review of ocap phase 2b, Task 10. The path scope is checked only where a program
calls a file builtin DIRECTLY with a literal path (`path_arg_builtins` /
`literal_path_uses`, lib/typecheck/typecheck_caps.ml). The stdlib entry points user code
calls (`File.open`, `File.read`, `File.write`, `File.open_dir`, `Csv.read_all`, ...) pass the
path to the builtin as a variable, and `Authority.check` applies no scope at run time yet, so
neither a compile-time nor a run-time scope check reaches them:

```march
mod Scoped do
  needs IO.Console
  needs IO.FileRead("/srv/data")
  fn main(_c : Cap(IO.Console), _r : Cap(IO.FileRead)) : () do
    match Authority.must(File.read("/etc/hosts")) do
      Ok(s) -> Authority.ignore(println("read " ++ int_to_string(String.byte_size(s)) ++ " bytes"))
      Err(_) -> Authority.ignore(println("err"))
    end
  end
end
```

`march --check` exits 0, and running it prints `read 263 bytes`. Task 10 made the raw open
builtins (`file_open`, `csv_open`, `dir_open`, ...) stdlib-only, so the literal check no longer
fires on any user program for them; the path conveniences (`file_read`, ...) are still callable
directly until ocap phase 1's gate (`2026-11-10-ocap-p1-gate-raw-capability-builtins.md`) lands,
after which the literal check is dead for user code entirely.

What to do: check a literal path argument at the wrapper entry points (map each `File.*` /
`Csv.*` / `File.open_dir*` entry to its path argument, as `path_arg_builtins` does for the
builtins), and/or check the path against the module's scope in `Authority.check` at run time
(phase 4). Add the repro above as a reject fixture.
