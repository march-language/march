# A path scope on a nested module is not checked

Found 2026-11-10 (ocap phase 3 probes). `cap_scope_violation` fires for a literal path outside
a path scope on the ENTRY module, but not when the scoped `needs` is on a nested module (here the
parent declares the capability unscoped; under `march check`, which nests every file's module in a
synthetic one, the same happens with no parent declaration at all):

```march
mod Main do
  needs IO.Console, IO.FileRead
  mod R do
    needs IO.FileRead("/srv/data/")
    fn r() : String do
      match file_read("/etc/hostname") do
        Ok(s) -> s
        Err(_) -> ""
      end
    end
  end
  fn main(c : Cap(IO.Console), f : Cap(IO.FileRead)) do println(R.r()) end
end
```

Every mode accepts it, `--compile` included. The path-scope walk is in
`lib/typecheck/typecheck_caps.ml` (`literal_path_uses` and the `mod_need_scopes` filter);
check which module's scopes `env.mod_need_scopes` holds when the nested module's bodies are
walked. `test/test_cap_mode_parity.ml` skips `path_scope` under `march_check` for this.
