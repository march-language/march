# `march --jit` printed `:<atom>` for the program's own atoms (2026-10-14)

Found while fixing the REPL atom-payload segfault
(`2026-10-14-repl-atom-payload-segfault.md`), which left this alone.

```march
println(to_string(:zz))   -- :<atom> under --jit (ORC and clang); :zz elsewhere
```

## Cause

Atoms compile to nameless FNV-1a hashes; each LLVM module gets a generated
internal `@march_atom_to_string` reverse table (`Llvm_toplevel.emit_atom_show_table`).
Under `--jit` a program is two modules: the precompiled stdlib prelude `.so` and the
program fragment. The fragment's `to_string(:zz)` calls the prelude's `Show$Atom.show`,
so the lookup runs against the *prelude's* table, which never saw `:zz`. The fragment
itself emitted no table at all (`MARCH_KEEP_LL=1 MARCH_JIT_BACKEND=clang`: the fragment
`.ll` has `call ptr @Show$Atom.show` and no `@march_atom_name_or_null`), because the
table was gated on an in-module `@march_atom_to_string` call site.

## Fix

- `emit_atom_show_table ~jit:true` (every emitter in `lib/tir/llvm_repl.ml`): a JIT
  module emits its table whenever it has atoms of its own, so it registers them with
  the runtime's namer registry, and its `@march_atom_to_string` asks that registry
  (new `march_atom_name_registered`, `runtime/march_runtime.c`) for a hash its own
  table lacks before answering `:<atom>`. The registry calls each module's pure
  `@march_atom_name_or_null`, so the fallback cannot recurse. AOT output is unchanged.
- ORC runs no `@llvm.global_ctors`, so the registration constructor only ever fired
  under the clang/dlopen backend. `Repl_jit.run_file`'s entry
  (`march_jit_program_N`) now calls `@march_atom_namer_register()` explicitly.
  Removing that call reproduces `:<atom>` under ORC only, while clang stays correct.
- `march_set_atom_namer` is idempotent, so the clang backend's ctor + explicit call
  register the table once.

Test: `jit_file` cases "march --jit names the program's atoms" (ORC and clang) in
`test/test_jit.ml`: a bare atom, atoms returned from a function, and the
runtime-seeded `:ok`, with no `:<atom>` anywhere in the output.

Not covered: REPL expression/declaration fragments under ORC still register their
tables only through the constructor (i.e. not at all under ORC), so a `Logger` LAtom
field or a cross-fragment `show` of an atom defined in an earlier ORC fragment can
still fall back to `:<atom>`/`null`.
