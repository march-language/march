- ✅ **Native arrays carry a header tag, and `copy_value` knows them (2026-09-07)** —
  `native_arr_alloc` (`runtime/march_runtime.c`) never set the header tag, so
  every `NativeU8Arr`/`NativeIntArr`/… carried `tag = 0`: an ordinary ADT
  constructor index, indistinguishable from a two-field cell. Every generic
  walker therefore fell through to its ADT arm, read `n_fields` out of
  `alloc_meta`, and treated the array's **payload** as a vector of pointer
  fields. `march_message.c`'s `copy_value` is the one that would have acted on
  it — on a cross-heap copy or a migration it would have allocated an
  ADT-shaped object of the wrong size and then recursed into whatever the
  bytes happened to look like.

  Native arrays now carry `MARCH_NATIVE_ARR_TAG` (`(int32_t)-6`), the next free
  sentinel after `MARCH_TIMER_TOKEN_TAG`, and `copy_value` has a case for them
  that copies by byte length — `len` at offset 16, `elem_kind` at 24, the
  layout `NATIVE_ARR_HDR = 32` already documents.

  Nothing else reads the tag on this path: `march_decrc` is shallow (it uses
  the tag only for string stats, the GC trace and the resource destructor), and
  native arrays are opaque 0-arity constructors that no pattern ever matches.
  706 tests.

  **Why this was latent.** `NativeIntArr`/`NativeFloatArr`/`NativeF32Arr`/
  `NativeI32Arr`/`NativeU8Arr` are in `non_sendable_types`
  (`lib/typecheck/typecheck_exhaustive.ml`), so an array cannot reach a message
  today and the mangling had nothing to mangle. This is groundwork for GAPS G44
  ("a chunk never crosses an actor boundary"): both defects have to be fixed
  before an array may be copied into a payload at all.

  **What G44 still needs, and why it is not here.** Allowing arrays in messages
  needs a copy, and the copy cannot be generic. `march_send`
  (`runtime/march_runtime.c`) does not copy — a message is passed by reference
  within one shared heap — and `copy_value` cannot be reused on that path,
  because `march_alloc` is a plain `calloc` that prepends no `march_alloc_meta`
  and so ordinary-heap objects carry no field count. `copy_value`'s ADT arm
  works only for `march_process_alloc` objects. The runtime therefore has no
  layout information for an ordinary value, which is the real reason arrays are
  barred rather than copied.

  The fix has to be compiler-emitted: at the `ECon` site for an actor message
  the typechecker already knows exactly which arguments are native arrays (it
  walks them in `check_sendable`), so codegen can emit a clone for those
  arguments and the payload owns a private buffer from birth. That is
  `lib/tir/llvm_emit.ml` plus the interpreter path, a `march_native_arr_clone`
  runtime helper, dropping the five names from `non_sendable_types`, and
  inverting reject tests `t164`/`t165`.
