# A heap field destructured out of a generic ctor is never dropped — 1 object per destructure

Filed 2026-08-22, found while fixing the erased-slot Float leaks
(`specs/progress/2026-08-22-erased-slot-ownership-leaks.md`). **Pre-existing,
not a regression from that work** — measured identically on `origin/main`
(8897bb1a) and on the fixed tree, to the allocation.

## Reduction

```march
mod W do
  needs IO.Console
  type One(a) = One(a) | Nothing

  pfn one_leg(n : Int, acc : Int) : Int do
    if n <= 0 do acc
    else
      let c = One(int_to_string(n))
      let v = match c do
        One(s) -> string_length(s)
        Nothing -> 0
      end
      one_leg(n - 1, acc + v)
    end
  end

  fn main(_c : Cap(IO.Console)) do
    one_leg(5, 0)
    let a = live_allocs()
    one_leg(10000, 0)
    println(int_to_string(live_allocs() - a))
  end
end
```

Darwin arm64, `--compile --opt 2`:

| | `live_allocs` delta |
|---|---:|
| `One(String)`, 10,000 destructures | **10,000** |
| same, on `origin/main` 8897bb1a | 10,000 |
| interpreted | 0 |

One leaked `String` per destructure — the only heap object the loop allocates.
It is the extracted FIELD that leaks, not the cell.

Two-field form, `type Cell(a,b) = Cell(a,b) | Empty` with
`Cell(int_to_string(n), 0.5)`, 10,000 iterations: **20,000** on `origin/main`
(the String plus the Float box), **10,000** after the erased-slot fix (the
String alone). So this is the residue that fix deliberately left.

Making the use of `s` OWNING rather than borrowing (`string_length(s ++ "!")`)
does not change the count — so it is not simply "a borrowed-position last use
gets no post-dec".

## What the TIR says

```
fn mixed_leg(...) =
  ...
  let c : Cell(String, Float) = alloc Cell.Cell($t30209, 0.5) in
  case c of
    Cell($f30212, $f30213) -> dec_rc c;
      let f : Float = $f30213 in
      let s : String = $f30212 in
      ... string_length(s) ...
```

`dec_rc c` frees the cell (the free is shallow — `march_decrc` does not walk
fields), so the field's reference transfers to `$f30212`/`s`. Nothing ever
`dec_rc`s `s`. Note the sibling arm DOES call a generated deep drop —
`__drop$Cell_String_Float(c)` in the non-exhaustive-panic arm — so the
machinery for releasing a cell's children exists; the destructure path just
doesn't use it and doesn't hand the job to the binder either.

`llvm_case` already resolves the shared-vs-unique question for exactly these
fields (`march_decrc_freed` + IncRC-on-shared), which is the accounting that
makes the transfer sound. The missing half is in Perceus: nothing gives the
binder a drop at its last use.

Leads, in order:
1. `_borrowed_field_vars` (perceus.ml) — a variable bound from a field of a
   still-live source inherits "borrowed" and gets NO RC ops. Check whether
   `$f30212` lands in that set even though the branch consumed the cell
   (`dec_rc c` in the same arm), which would suppress exactly this drop.
2. The niche form leaks too (`One(String)` is niche-encoded: `Nothing` = null,
   `One(s)` IS `s`), and there `strip_decrc_niche` removes the scrutinee's dec
   because "scrut IS the payload" — so the binder inherits the reference by a
   different route and needs a drop for the same reason.

## Probably the same defect as

The "second, separate observation" in the original
`2026-08-21-boxed-option-float-cells-never-freed.md` filing: `to_string` of a
`List(String)` leaks 5 allocations per iteration (3 elements) compiled while
the interpreter stays flat. `Cons` is a boxed generic ctor and `to_string`
destructures it. Worth re-measuring against this reduction before treating them
as two items.

## Verification bar

The `One(String)` reduction RED (1/destructure) → GREEN (small constant); the
`Cell(String, Float)` form likewise; `native_erased_float_slot_leak_probe`'s
`mixed_leg` can then be switched from its string LITERAL back to
`int_to_string(n)` and stay green, which is the cross-check that the two fixes
compose. Full ASAN corpus — a missing drop and an over-eager drop look
identical in a unit test and opposite in a corpus sweep.
