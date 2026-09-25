# A non-inlined user fn named like a builtin is emitted under the builtin's C symbol

Filed 2026-09-25, found while closing
`specs/progress/2026-09-25-runtime-symbol-naming-and-uncompiled-caps.md`.

The entry module's top-level functions are unprefixed in TIR (lowering strips
the entry module's name). Codegen turns every function name into a symbol with
`Llvm_builtins.mangle_extern`, at definitions (`llvm_toplevel.ml`,
`llvm_tco.ml`, `llvm_repl.ml`) and at references (`llvm_emit.ml`,
`llvm_emit_call.ml`). `mangle_extern` looks the bare name up in the builtin
table FIRST. So a user

```march
fn file_read(x : Int) : Int do ... end    -- any of the ~330 names with a c_name row
```

that survives to emission, because it is too big to inline or is used as a
value, is emitted as `define i64 @march_file_read(i64 %x.arg)`. That collides
with the preamble's `declare ptr @march_file_read(ptr)`, and clang fails with
`invalid redefinition of function 'march_file_read'`. The interpreter runs the
program fine. A small function is inlined and never emitted, so the
bug hides until it grows.

Repro (compiles interpreted, fails `--compile`):

```march
mod Shfr do
  needs IO.Console
  fn count_up(i : Int, n : Int, acc : Int) : Int do
    if i >= n do acc else count_up(i + 1, n, acc + i * 3 + 1) end
  end
  fn file_read(x : Int) : Int do
    count_up(0, x, 0) + count_up(1, x, 7) * 2 + count_up(2, x, 9) * 5
  end
  fn apply_it(f : Int -> Int, x : Int) : Int do f(x) end
  fn main(_cap : Cap(IO.Console)) : () do
    println(int_to_string(apply_it(file_read, 4)))
  end
end
```

**Why this is not a one-line fix.** The TIR name alone cannot tell the user's
`file_read` from the builtin. The prelude is unwrapped into the entry module
with bare names too, and stdlib modules call builtins by bare name (e.g.
`File.read` calls `file_read`). If "defined in `tm_fns` ⇒ user symbol" were
applied at every reference, the stdlib's builtin call would silently go to the
user's function, which turns a compile error into a miscompile. The
disambiguation has to happen at lowering, where scope is known
(`Lower_state._current_module_fns`), for example by giving an entry-module
function that shadows a builtin a distinct TIR name at its definition and at
the references that resolve to it. That new name also has to survive mono
(`$` suffixes), HCR manifests and `Handler_owner`.

Capability attribution already treats a call to a defined name as a call to
that function (`Cap_attrib.walk ~is_defined`, 2026-09-25), so this is purely a
codegen naming bug. It no longer produces a false capability error.
