# A `Vault(Option(_))` element type mis-decodes on the compiled backend (boxed/niche mismatch)

Found while getting depot's test sandbox green during 0.3.0 downstream
validation. Interpreted is correct; compiled panics "non-exhaustive pattern
match".

## Repro (minimal, no dependencies)

```march
mod Main do
  needs IO
  needs IO.Mut

  fn snapshot_one(tbl, k) do
    match Vault.get(tbl, k) do
      Some(v) -> (k, v)
      None -> (k, None)     -- unifies the table's element type with Option(b)
    end
  end

  fn snapshot_table(table_name) do
    match Vault.whereis(table_name) do
      None -> Nil
      Some(tbl) ->
        let ks = Vault.keys(tbl)
        List.map(ks, fn k -> snapshot_one(tbl, k))
    end
  end

  pfn walk(snaps) do
    match snaps do
      Nil -> ()
      Cons((name, snap), rest) ->
        println("tbl: " ++ name)
        walk(rest)
    end
  end

  fn main(cap: Cap(IO)) do
    let data = Vault.new("data")
    Vault.set(data, "row1", "hello")
    let snaps = List.map(["data"], fn n -> (n, snapshot_table(n)))
    walk(snaps)
    println("done")
  end
end
```

Interpreted: prints `tbl: data` / `done`. Compiled (`--opt 2`, also `--opt 0`):
`panic: non-exhaustive pattern match`.

## Mechanism

`snapshot_one`'s `None -> (k, None)` arm unifies the whereis-minted handle's
phantom element type with `Option(b)`, so `Vault.get` on that handle returns
`Option(Option(b))`. Nested Option is niche-UNSAFE, so the compiled call site
decodes it with the BOXED strategy (tag load at `[v+8]`) — but the runtime's
`march_vault_get` returns the NICHE encoding unconditionally (raw payload or
0). The tag load lands inside the payload's own heap layout (here a
`march_string`), reads garbage, matches no arm, and falls through to the
compiled match's default panic arm.

Same family as the erased-niche residuals documented in
`runtime/march_extras.c`'s Option-helper comments and
`lib/tir/llvm_eq.ml`'s degenerate-value guard; this is the Vault-shaped
instance. A uniform Option encoding is the complete fix; short of that, the
vault builtins could detect a nested-Option element type at the call site
(the typechecker knows it) and box on return.

## Downstream impact

depot's `Depot.Test` sandbox hit this exact shape (its `snapshot_one` was
written precisely this way) — every checkout/checkin/rollback test failed
compiled-only. Worked around in depot by restructuring to `List.filter_map`
with `Some((k, v))` so the element type never unifies with Option
(depot commit on `main`, 2026-08-20). Any user code that stores handler-style
"maybe present" values in a Vault can trip this.
