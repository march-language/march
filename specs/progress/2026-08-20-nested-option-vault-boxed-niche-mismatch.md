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

---

## RESOLVED (2026-08-21) — fixed on the branch `fix/vault-record-erased-repr`

The mechanism section above is correct, and the suggested direction ("the vault
builtins could detect a nested-Option element type at the call site and box on
return") is what shipped — generalised, because the filed nested-Option shape
turned out to be one of THREE element types with the same defect.

### Scope was wider than filed

`Repr.repr_of_ty (Option p)` is `Boxed` for EVERY niche-unsafe payload `p`, not
just a nested Option. Probed on `origin/main` (`3fda8f46`), interpreter correct
in all three cases:

| element type       | compiled behaviour before the fix          |
|--------------------|--------------------------------------------|
| `Vault(Option(_))` | `panic: non-exhaustive pattern match` (1)  |
| `Vault(Float)`     | `panic: non-exhaustive pattern match` (1)  |
| `Vault(Unit)`      | SIGSEGV, exit 139                          |

`Vault(Int)` / `Vault(String)` were and remain correct — `Option(Int)` and
`Option(String)` are niche-SAFE, so both sides already agreed.

### The fix

`lib/tir/llvm_emit.ml`, new `emit_vault_opt_reencode`, applied at the
`vault_get` and `vault_ns_get` arms. `march_vault_get` cannot do better than the
niche encoding — a vault handle's element type is a phantom the C runtime never
sees — so the re-encode belongs at the one point that knows BOTH halves: the
call site, which has the static `Option(p)` and can ask `Repr` how it will be
decoded.

- call site decodes Niche (the overwhelmingly common case, and the only case
  before this existed) → the runtime word is returned untouched, no branch, no
  allocation;
- call site decodes Boxed → emit `null ? boxed-None : boxed-Some(payload)`,
  built with the same `ctor_entry` / `emit_heap_alloc` / `emit_store_field`
  helpers and the same declared field type (`Some(a)` → TVar → `ptr`) that
  `EAlloc`'s own boxed fallthrough and `llvm_case`'s branch extraction use, so
  encode and decode cannot drift.

A `TVar` payload is deliberately treated as Niche rather than Boxed:
`niche_payload_ok` says false for it, but `EAlloc`'s niche path, `llvm_case`'s
abstract-arg niche path and `ensure_adt_eq_fn` all treat `Option(TVar)` as
niche, so boxing there would break the agreement in the other direction.

RC is unchanged: `march_vault_get` already returns `+1`, and the fresh boxed
cell (`march_alloc`, rc=1) takes ownership of it. The `None` case now yields a
real heap cell where it used to yield `null`; Perceus already assumed a heap
cell for a `Boxed` static type (its `decrc` on `null` was simply a no-op).

### Test

`test/native/vault_niche_unsafe_element.march` + `.expected`, wired into
`test/dune`. Covers all three broken element types, the filed repro's own
`Vault.whereis` + `List.map` snapshot shape, AND a `Vault(Int)` block as the
niche-path control with an ODD and an EVEN value (the fixture's header records
why the even case is not redundant).

Non-vacuity, by file-copy swap of the five changed sources back to
`origin/main` (`3fda8f46`) followed by `dune build bin/main.exe` +
`@warm-cache` (verified restaged: `rec_box_erased_float` count 0):

```
----- vault_niche_unsafe_element -----
  run_exit=1
  RESULT: DIFFERS from golden  (non-vacuous)
1,12c1
< nested row1: hello
  ... 12 golden lines ...
---
> panic: non-exhaustive pattern match
```

Same verdict against pre-#315 (`c2f747f7`). With the fix restored: exit 0, zero
diff.

### Not fixed, and inherent

Storing a `None` INTO a `Vault(Option(_))` still writes a raw null, which
`Vault.get` cannot tell from an absent key. That is the niche encoding's own
ambiguity at the vault boundary, not this bug; a uniform Option encoding
remains the only complete answer, as the mechanism section says.

### Same family

This is one of five instances of a single root — the erased/uniform boundary
between the C runtime and compiled code, where the runtime has ONE fixed
representation and the compiled call site decodes by the STATIC type. The other
four: `2026-08-20-vault-non-string-key-native-crash.md` (the key, fixed by
#315) and the three in `2026-08-20-record-put-get-float-niche-segfault.md`.
