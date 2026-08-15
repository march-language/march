# Config needs a tagged value boundary

`Vault(v)` now carries a phantom element type, so a bound Vault handle rejects
storing an `Int` and reading it as a `Pid`. `Config` deliberately opts out of
that rule: its process-global table is heterogeneous, and `Config.get` remains
polymorphic at every call site.

That leaves the old erased-value confusion reachable through the public Config
API. The following witness typechecks, then fails at runtime when `is_alive`
receives the stored `Int` as though it were a `Pid`:

```march
mod M do
  needs IO.Console
  needs IO.Mut

  fn main(_cap_console : Cap(IO.Console), _cap_mut : Cap(IO.Mut)) do
    Config.put(:config_erased_witness, :value, 42)
    match Config.get(:config_erased_witness, :value) do
      Some(p) -> println(bool_to_string(is_alive(p)))
      None    -> println("missing")
    end
  end
end
```

Observed on 2026-08-15:

- `--check` succeeds.
- Interpretation reaches `is_alive` and reports `is_alive: expected Pid`.

This is not fixed by adding another phantom parameter to Vault. Config needs a
tagged/dynamic value representation and checked extraction or an explicitly
typed Config API. Any future fix must preserve heterogeneous storage while
making an `Int`-as-`Pid` read fail before an actor builtin receives the value.

## Acceptance criteria

- The witness no longer reaches `is_alive` with an unchecked value.
- Heterogeneous Config storage continues to support existing Int/String/Bool
  use cases.
- The failure is explicit and recoverable rather than a runtime representation
  error or process crash.
- Both interpreter and compiled execution agree on the behavior.
