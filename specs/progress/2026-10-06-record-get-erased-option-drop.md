# `record_get` of a Float field: the returned box is released twice (ASAN UAF, compiled)

**FIXED 2026-10-06.** Filed as `specs/todos/2026-10-05-record-get-float-box-double-release.md`.

## Cause

`record_get(r, "y")` with nothing pinning the payload type is `Option('a)`, and the
runtime answers such an erased ('g') read in the NICHE encoding: `Some(x)` is `x` itself,
`None` is null (`rec_some_k` / `rec_none_k` in march_extras.c). Mono defaults the dangling
variable to String for `println`/`to_string`, so `Show$Option.show$Option_String` decodes
the niche correctly; but the caller's drop still saw `Option('a)`, which classifies Boxed,
so the synthesized `__drop$Option_V_N` ran `march_decrc_freed` on `x` as if it were the
`Some` cell and then `dec_rc` on its "payload", the same freed cell.

Fixing that exposed a second bug on the same path: Perceus' `result_is_borrowed_field`
still treated `to_string(x)` / `Show$String.show(x)` on a borrowed String as an alias of
`x` (it was the identity once). Both lower to `march_value_to_string`, which returns its
own reference (`march_incrc` on a String, a fresh string otherwise), so the result was
never released: one string leaked per `Show$Option.show` of an erased payload.

## Fix

- `lib/tir/drop.ml`: an `Option('a)` (payload a type variable) is released with a plain
  `dec_rc` (`drop_op`, `drop_fn_for`): right for the niche (releases `x`, ignores null),
  and for a boxed cell a leak of the payload at worst, never a double release.
- `lib/tir/perceus_core.ml`: the `to_string` / `Show$String.show` alias arm is gone.

## Test

`test/native/erased_option_read.march`: the live-object count over 200 erased reads shown
through `to_string` is unchanged (RED before: 200). The use-after-free itself shows only
under ASAN (`record_erased_field_repr` in the container sweep: clean after).

## The original report


**Logged 2026-10-05.** Found by an ASAN sweep of `test/native/*.march` (Linux arm64
container, `MARCH_SANITIZE=1`) while validating the colliding-type drop fix; the emitted
IR is identical (modulo fresh-name numbering) with and without that fix, so this
predates it.

`test/native/record_erased_field_repr.march` prints `Some(7)`, `Some(8)`, `Some(0.5)`,
then ASAN reports a heap-use-after-free in `march_main`:

- allocated: `march_record_get` -> `march_alloc_float` (the Float box for the erased
  `"y"` read of `record_put(record_from_list([]), "y", 0.5)`)
- freed: `march_main` -> `march_decrc_freed`
- read again: `march_main` -> `march_decrc_local`, a second release of the same cell

Without ASAN the program passes its golden (the freed cell is not reused before the
second decrement), so `native_record_erased_field_repr` stays green. The likely owner is
the ownership hand-off at the erased boundary fixed in
[../progress/2026-08-20-record-put-get-float-niche-segfault.md](../progress/2026-08-20-record-put-get-float-niche-segfault.md):
the Some cell and its Float payload are each released once by the caller, but one
path also releases the payload through the Option's drop.

Next: snapshot the post-Perceus TIR of the `rf` leg (`--dump-tir`) and count the
releases reaching the Float box.
