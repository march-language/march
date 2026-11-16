`[P3]` `--jit`: an entry fn named like a builtin is ignored or captures stdlib calls (2026-11-16)

`march --jit` lowers the program with `~shadow_builtins:false` (`lib/jit/repl_jit.ml`, the
shell program and fragment `lower_module` calls), so an entry fn named like a builtin keeps
its bare TIR name. The native and JS pipelines now give it its own name (`not$u`, see
`specs/progress/2026-11-16-entry-fn-builtin-name-cross-module.md`); the JIT does not, and its
output differs from the interpreter on both shadow fixtures:

- `test/native/shadowed_negate_not.march --jit`: the user `string_length`, `negate` and
  `not` are not called (prints `-84`, `false`, `2` where the interpreter prints the user fns'
  markers and results).
- `test/native/shadowed_builtin_cross_module.march --jit`: the user `string_is_empty("y")`
  runs the builtin (prints `false`, expected `user string_is_empty y` then `true`).

The repl_jit comment says renaming would desynchronise the fragments' closure-slot binding by
bare name and `is_c_runtime_fn`; the fix has to rename in both places, or route `--jit`
file runs (not REPL fragments) through the renaming lowering. Found 2026-11-16 on
claude/ocap-p4-runtime-636cb3; pre-existing (independent of that branch's change).
