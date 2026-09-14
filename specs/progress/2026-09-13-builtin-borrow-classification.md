# Read-only builtins no longer leak their heap arguments

**Landed 2026-09-13.** Closes
`specs/todos/2026-08-22-boxed-ctor-heap-field-binder-not-dropped.md`, whose
title was wrong: that file's original text is kept below the rule, unchanged.
This is step 1 of the order proposed in
`specs/2026-09-11-codegen-leaks-design.md` (§4, which predicted the
misattribution).

## The defect

Perceus asks `Borrow.is_borrowed` whether a builtin consumes each argument,
keyed by the builtin's **TIR name**. A name that is not in
`extern_borrow_table` defaults to **owned**. The caller then hands its
reference over and emits no release, and when the C implementation only reads
the value, nobody frees it.

Re-measured on `main` at `8432eb44`, `--compile --opt 2`, `live_allocs` deltas:

| call on a fresh value | leaked per call | why |
|---|---|---|
| `s == ""`, `s != "5"`, `s < "5"`, `s >= "5"` (String) | 1 | operators had no entry at all |
| `xs == [1, 2]` (List(Int)) | 6 | both lists; same cause |
| `Tagged(...) == Tagged(...)` (boxed ADT, `derive Eq`) | per cell | same cause |
| `a == b` on erased operands (`march_poly_eq`) | 1 | same cause |
| `string_length(int_to_string(n))` | 1 | listed only as `march_string_byte_length` |
| `One(s) -> string_length(s)` | 1 | **the todo's reduction; the destructure is innocent** |
| `file_exists(fresh path)` | 1 | unlisted; still owned (see below) |

The todo's reduction leaks exactly as much with no constructor involved
(`string_length(int_to_string(n))`, and `s == ""`). Matching the field away
with `One(_)` is flat, and so is allocating a string and dropping it. The
post-Perceus TIR shows `==(s, "")` / `string_length(s)` with no `dec_rc`
after.

A static cross-check of `Llvm_builtins.builtins` against the table found **173
`in_is_builtin` rows with a `ptr` parameter and no entry**. The design doc's
own cross-check had found 2, because it compared C names and the operators
have none.

## What landed

- **`lib/tir/borrow.ml`**: `==`, `!=`, `<`, `<=`, `>`, `>=` borrow both
  operands. Every emit path in `llvm_emit_arith.ml` only reads them:
  - `march_string_eq` / `march_compare_string`;
  - the inline unboxed-aggregate compare;
  - the generated `Llvm_eq` structural equality, which calls only other
    generated eq fns and those helpers;
  - `march_poly_eq` / `march_poly_compare`.

  `string_length` and `to_string` are now listed under their TIR names.
  `march_value_to_string` takes its own +1 when it returns a String argument
  unchanged, so borrowed is right for it too.
- **`Borrow.extern_owned_builtins`** (new): the other 173 heap-param builtins,
  named explicitly. Each either consumes its argument or has not been audited,
  and keeps today's behaviour. **`test/test_builtin_borrow_classification.ml`**
  fails if any `in_is_builtin` row with a `ptr` parameter is in none of the
  three lists, or in two. The default can no longer be silent.
- **`runtime/march_runtime.c`**: `march_typed_array_get` and
  `march_typed_array_to_list` now take a reference on the element they hand
  out. Both returned the bare slot. That only stayed balanced because every
  consumer was treated as consuming a reference it never released. With a
  borrowing `==`, the unowned element was freed under the array.

## Why the unaudited builtins were not flipped in the same change

Marking a consumer borrowed is sound only if **every value that reaches it is
owned**. A producer that returns an unowned reference turns the fix into an
early free. That is exactly what the typed-array legs caught.

The known remaining producer is `pid_of_int`. It returns a pid without a
reference, and `send(pid_of_int(i), m)` and `mailbox_size(p)` stay balanced
only because they "consume" it. So the actor family stays owned until
`specs/todos/2026-09-13-send-leaks-a-reference-to-a-live-pid.md` settles pid
ownership.

The rest of the owned list (file/dir/process paths, hashing, compression,
native arrays, vault keys, …) is the audit's remaining work. Each move needs
its C body read *and* its producers checked.

## Tests

`test/native/builtin_borrow_leak_probe.march` (+ `.expected`, `test/dune`)
has ten legs, each 10,000 calls, and prints `flat: true/false` plus the
computed value.

Two traps in writing it, both caught before landing:
- **Dead-code elimination.** The first draft discarded each loop's result with
  `let _ = leg(n, 0)`. A pure call is dead-code eliminated, so 9 of 11 legs
  reported flat on the *unfixed* compiler. Every loop's result is now printed.
- **An unfreeable typed-array element.** The typed-array leg first used
  `"beta" ++ ""`, which folds to an immortal literal and so could never be
  freed. It also sampled after a warmup call, by which time an early free had
  already happened. It now uses a heap string, samples before the first call,
  requires a non-negative delta, and allocates same-sized strings before the
  read-back.

Red controls:

| build | result |
|---|---|
| `main` | 9 leak legs `false` |
| borrow entries reverted, runtime kept | the same 9 `false` |
| runtime `incrc` reverted, borrow kept | `RC underflow … aborting`, 3 of 3 runs (exit 134/133) |
| classification guard with `file_exists` deleted from the owned list | test fails |
| this change | all legs `true`, computed values byte-identical to `main` |

TIR snapshots: `nested_cons_ctor_heap` and `trmc_modulo_cons` (perceus stage)
lose the `inc_rc` dups before comparisons on erased operands. No other change.

## Found in passing, filed

- `to_string` of a `List` is rewritten to `Show$List.show`, which leaks 4–5
  objects per call for `List(Int)` and `List(String)` alike. It is not this
  bug, since the builtin is never called:
  `specs/todos/2026-09-13-show-list-leaks-per-call.md`.
- `compare_string` typechecks but compiled code fails to link (`_compare_string`
  undefined): `specs/todos/2026-09-13-compare-string-does-not-link.md`.

---

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

> **Design spec (2026-09-11):** `specs/2026-09-11-codegen-leaks-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
