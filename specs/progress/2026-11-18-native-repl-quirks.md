`[P2]` - [x] **Native REPL (`march repl`) quirks found by the doc-example checks.**

Items 1, 3, 4, 5 and 6 of `specs/todos/2026-10-14-native-repl-quirks-found-by-doctests.md`.
Item 2 (`v`) is the REPL's documented last-result variable, and the open part of item 1
(what a JIT `let` displays) is still in that todo.

## Fixed 2026-11-18

Re-verified on main (294c3b0aa) first. One thing had changed since the todo was filed:
`Some(1) == Some(1)` no longer ran at all in either REPL.

- **`==` on a stdlib type did not typecheck** (`Option`, `List`, `Result`, …):
  "`Option(Int)` does not implement interface `Eq`". Their `Eq` impls moved into the stdlib
  (`impl Eq(Option(a)) when Eq(a)`, stdlib/option.march) in June. The REPL loads the
  stdlib by folding `check_decl` over its modules one at a time, and a `DMod`'s own impls
  stay in its inner env. `check_decl` exports the module's names, types and ctors, but not
  its impls. `check_module`'s pass 1 registers every module's impls up front;
  `Repl.preregister_stdlib_types` now does the same with `register_impl_shape`, newly
  exported from `Typecheck`. The interpreter REPL shared the bug, but it reported the
  error late, on the next input.
- **Item 1 / 5: `==` answers changed between inputs (ORC backend only).** Each
  fragment that compares a type generates `__march_eq_<ty>` (`Llvm_eq.ensure_adt_eq_fn`)
  with external linkage. Under ORC every fragment shares one JITDylib, so the second
  fragment comparing the same type failed with "Duplicate definition of symbol". The
  REPL treats any `Failure` from the JIT as "fall back to the interpreter", so it re-ran
  the input there without saying so. The interpreter's Vault tables (and actors) are not
  the JIT's, so `Vault.get(c, "h") == Some(1)` was `true` once, then `false`. The record
  case (item 5) was the same mechanism: the list compare had already defined the
  element type's helper. The clang backend's per-fragment `.so` tolerated the duplicate.
  The fix gives these helpers `linkonce_odr` when a session table is installed
  (`Llvm_ctx.session_helper_linkage`), and does the same for collision dispatch fns
  (`Llvm_dispatch.emit_dispatch_fn`), which are also named by type. ORC discards the later
  weak copies. The AOT path has no session table, so its IR is unchanged. The
  original item-5 program (`==` on anonymous records) is now rejected by every backend:
  an anonymous record does not implement `Eq`. So that part needs no REPL fix.
- **Item 3: non-ASCII strings printed escaped**, in BOTH REPLs. The JIT printer used
  OCaml's `%S` and the interpreter's `value_to_string` used `String.escaped`; each spells
  every byte >= 0x80 as a decimal escape. Both now use `Test_report.quote`, the test
  report's quoting, which escapes quotes, backslashes and control bytes and leaves UTF-8
  as it is: `"café"`, `["naïve", "a\tb"]`.
- **Item 4: unit printed as `1`.** A unit result reaches `Repl_jit.run_expr` as
  `TTuple []`, not `TUnit`, so it fell through to the small-word fallback, which printed
  the tagged word. It now has its own arm.
- **Item 6: a panic ended the session.** Inputs ran unguarded, so a panic reached
  `march_panic`'s unhandled path (report, `exit(1)`). New runtime entry points
  `march_repl_guarded_{word,float,void}` (runtime/march_runtime.c) run a fragment
  under the `march_try_call` longjmp channel, saved and restored. `Repl_jit.guarded_call`
  raises `Fragment_panicked "panic: <msg>"`, and the REPL prints
  `runtime error: panic: <msg>`, as the interpreter REPL does, then reads the next
  input. A panicking `let` binds nothing. `march --jit` (whole programs) is unchanged: a
  panic there still exits 1.

Tests (test/test_jit.ml, `repl_session`), each seen failing on main first: unit
prints as `()`; Vault values compare equal every time (ORC and clang); `==` answers in
order across a session; non-ASCII strings print as text (JIT and interpreter); a panic
does not end the session.
