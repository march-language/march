# Current State (as of 2026-07-30, REPL variable slots now RC-correct)


**A real, independent bug found while chasing the still-open REPL
capture-free-closure leak: REPL variable slots did zero RC bookkeeping.**
`lib/tir/llvm_repl.ml`'s persistent slot mechanism (`@march_repl_get`/
`@march_repl_set`, backed by `runtime/march_extras.c`'s `march_repl_slots`
array) copies raw `int64_t` bits with no incref on read and no decref on
overwrite. Any heap-typed REPL variable — a String, a closure, any boxed
value — read back from a later fragment handed out the slot's OWN
reference with no dup; any overwrite (concretely, the `"v"` magic
last-expression-value slot, genuinely reused across every subsequent REPL
expression) discarded whatever reference the slot held with no release.

Fixed at the two read sites (`emit_prev_slot_bridges`, `emit_slot_loader_fns`
— a prior binding can be read either bridged directly into a later
fragment's entry block, or via a generated zero-arg loader function) and the
one write site (`emit_store_to_slot`), all gated on the *static* `Tir.ty` at
the LLVM-emission call site — deliberately not inside
`march_repl_get`/`march_repl_set` themselves, since slots store
`Int`/`Bool`/`Float` **untagged** (unlike March's usual `(n<<1)|1`
convention), so a blind `IS_HEAP_PTR`-gated fix inside the untyped C
functions would misfire on an ordinary integer whose raw bits happen to look
pointer-shaped. Caught that before it was ever built or run, by diffing
against a `git show`-sourced copy of the pre-edit file rather than mutating
the working tree to test it.

This does NOT close the REPL capture-free-closure leak it was found while
chasing — re-attempting the `is_repl` threading from the previous entry, on
top of this fix, hit the identical SIGSEGV at the identical address. There
is at least one more contributing mechanism, somewhere in how the
precompiled stdlib passes a capture-free closure around internally, not yet
diagnosed. That `is_repl` change was reverted again; this slot fix was kept,
since it is correct and valuable independent of whether the leak is ever
closed.

Verified: all 24 `repl_jit_cross_line`/`repl_jit_regression` tests pass with
this fix alone, including the two shapes that actually exercise repeated
slot access ("var redefinition", "P0: List.length x3 successive
fragments"). Full `dune build @runtest` clean except the pre-existing
environmental ASAN failure.
