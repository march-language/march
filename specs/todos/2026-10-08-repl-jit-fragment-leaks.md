`[P3]` **The local REPL's fragments leak like the shell's did.**

Filed 2026-10-08. The remote shell's fragments were fixed in
[2026-10-08-shell-slot-and-drop-leaks](../progress/2026-10-08-shell-slot-and-drop-leaks.md).
The fixes went only into the shell's path (`Repl_jit.shell_compile`, and
options of `Llvm_repl.emit_repl_expr` that only the shell passes). The local
REPL's path, `Repl_jit.lower_module` and the plain `emit_repl_*` calls, has
the same three causes. They were not measured there:

1. **No `Drop.run`** after Perceus (`lower_module`). A `dec_rc` of an
   aggregate the code does not take apart frees only its top cell.
2. **The slot bridge increments every heap binding on every input**
   (`Llvm_repl.emit_prev_slot_bridges` without `~borrow`, and the loaders
   of `emit_slot_loader_fns`). Perceus treats REPL variables as borrowed in
   `main` and never releases them, so each REPL line adds one count to every
   heap binding.
3. **No closure-release registration** (`~register_drops`) and **no
   `Known_call`** before Perceus. A closure released through its function
   type keeps its captures, and `List.filter`'s `go` leaks its predicate.

Leaks in the REPL matter less than on a long-running node, since the process
ends with the session. But the same fixes apply. Check `test_jit`, the
precompiled-stdlib path (`~fragment:false`) and the ORC backend before
turning them on there, as all three share the emitter.
