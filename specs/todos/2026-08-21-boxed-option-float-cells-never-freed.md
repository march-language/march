`[P2]` Boxed `Option(Float)` cells are never freed on the compiled backend

Found while fixing the erased/uniform-boundary family
(`specs/progress/2026-08-20-nested-option-vault-boxed-niche-mismatch.md` and
`specs/progress/2026-08-20-record-put-get-float-niche-segfault.md`), on the
branch `fix/vault-record-erased-repr`.

**This is PRE-EXISTING, not a regression from that work.** Measured identically
on `origin/main` (`3fda8f46`) by file-copy-swapping the five changed sources
back and rebuilding — same number, to the allocation. It is filed now because
those fixes make the leaky path *reachable* for `Vault(Float)` and record Float
reads, which previously crashed before they could leak.

## Repro (minimal, no Vault, no Record, no builtin)

```march
mod Main do
  needs IO

  pfn mk(n) do
    if n % 2 == 0 do Some(0.5) else None end
  end

  pfn loop(n, acc) do
    if n <= 0 do
      acc
    else
      let a = match mk(n) do
        Some(x) -> x
        None -> 1.0
      end
      loop(n - 1, acc + a)
    end
  end

  fn main(cap: Cap(IO)) do
    println(loop(50, 0.0))            -- warm
    let a0 = live_allocs()
    loop(20000, 0.0)
    println(int_to_string(live_allocs() - a0))
  end
end
```

```
interpreted : 0
compiled    : 30000
```

## What the number says

20000 iterations produce 10000 `Some(0.5)` and 10000 `None`. `Option(Float)` is
niche-UNSAFE (`0.0` bitcasts to the `None` niche), so it uses the BOXED
representation: `Some` is a heap cell plus a `march_alloc_float` box for the
field, `None` is a bare heap cell. That is 10000×2 + 10000×1 = 30000
allocations — i.e. **every single one leaks; nothing on this path is freed.**

Payload-kind sweep, same harness, 20000 iterations each:

| element type     | repr  | live_allocs delta |
|------------------|-------|------------------:|
| `Option(Float)`  | Boxed |         **30000** |
| `Option(Int)`    | Niche |                 3 |
| `Option(String)` | Niche |                 1 |
| `Option(Unit)`   | Boxed |                 1 |

So it is not "boxed Options leak" in general — the `Unit` payload is boxed too
and does not leak (though that row may be vacuous: a `Unit` payload is a strong
DCE candidate and the loop may fold away entirely — worth confirming with
`--emit-llvm` before drawing a conclusion from it). The Float payload is the
one that leaks, and it leaks the OUTER cell as well as the inner box.

## Where to look

`lib/tir/llvm_case.ml`'s boxed-branch field extraction only records a field for
conditional `IncRC` when `concrete_field_ty = "ptr" && field_ty = "ptr"`. For a
`Float` field the concrete type is `"double"`, so the field is skipped — and the
branch body reaches the binder through `Llvm_ctx.coerce ("ptr","double")`, i.e.
`march_unbox_float`, which reads the box without taking ownership of it. Nothing
then owns the box, and the outer cell's own drop appears not to run either
(otherwise the `None` half, which has no inner box at all, would not leak).

Check in this order:

1. whether Perceus/`drop` classifies a `TCon("Option",[TFloat])` binding as
   needing RC at all (`Rc_types.needs_rc`) — the `None` half leaking points at
   the OUTER cell's drop being missing, which is upstream of the field question;
2. whether the free path walks and releases a boxed cell's fields, or whether
   the branch is expected to release them explicitly;
3. `march_alloc_float`'s box: who is meant to own it once
   `march_unbox_float` has read the double out.

## Severity

P2. It is a steady leak, not a crash or a wrong answer, and it needs a loop over
a boxed `Option(Float)` to matter — but that is not an exotic shape (any
`Vault(Float)` read loop, any schema/ORM walking Float columns, any
`record_get` of a Float field in a hot path), and the two fixes above have just
made those shapes work instead of crash.

## Second, separate observation — do NOT assume it is the same bug

`to_string` of a `List(String)` also grows the live-allocation count compiled
while the interpreter stays flat: 20000 iterations of
`to_string(["alpha", "beta", "gamma_long_enough_to_be_heap_allocated"])` leak
100000 allocations (5 per iteration, 3 elements). Also identical on
`origin/main`, so also pre-existing. Not characterized further — it involves no
Float and no boxed Option, so it is probably a different defect and deserves its
own reduction before anyone tries to fix the two together.
