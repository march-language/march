# Fixed: builtin passed as a first-class value SIGBUSed when compiled

Compiled-only bug, same family as the other first-class-function-reference
regressions tracked in `specs/progress/`.

## Repro

```march
mod HofApp do
  needs IO.FileRead

  fn apply1(f : (String) -> a, p : String) : a do
    f(p)
  end

  fn main() : () do
    match apply1(file_read, "/etc/hosts") do
      Ok(s)  -> println(string_slice(s, 0, 5))
      Err(_) -> println("err")
    end
  end
end
```

Interpreted: prints the file's first bytes, exit 0. Compiled: exit 138
(SIGBUS).

## Root cause

`lib/tir/llvm_emit.ml`'s `emit_atom` has a dedicated arm for "top-level March
function used as a first-class value" that allocates a real closure —
`{header, fn_ptr}` where `fn_ptr` points at a generated `$clo_wrap`
trampoline presenting the uniform-ptr ABI that `ECallPtr` dispatch expects.

The sibling arm for "**builtin** function used as a first-class value" (e.g.
`file_read` passed bare to `apply1`) skipped all of that and just returned
the raw C-extern global address (`@march_file_read`) as the atom's value.

That's fine as long as the value is only ever fed straight into an `EApp`/
`ECallPtr` site that recognizes it's a known builtin and emits a direct call
(see the `is_builtin_fn` arms in the `ECallPtr` match) — but `apply1`'s
parameter binding lowers to `let f = file_read in call_ptr f(p)`. Once
`file_read` is let-bound to a local, that local has a `var_slot` entry, so
none of the "no var_slot" special cases fire on subsequent use — the generic
closure-dispatch path runs instead: load a "field" off the stored pointer
(treating it as a closure-struct header) and call through it. Since the
stored pointer was actually the raw *code* address of `march_file_read`, not
a heap closure struct, this read garbage off the code page and jumped to it
— SIGBUS.

## Fix

`lib/tir/llvm_emit.ml`: the builtin-as-first-class-value `emit_atom` arm now
builds the same kind of closure as the top-level-fn arm — allocate
`{header, fn_ptr}` (or intern a static one when `static_closure_ok`) with
`fn_ptr` pointing at a `$clo_wrap` trampoline generated via
`Llvm_calls.clo_wrap_define`. The trampoline's parameter/return LLVM types
are read from the builtin's own `declare_sig` via
`Llvm_builtins.builtin_param_llvm_tys` / `builtin_ret_ty` (falling back to
the March-level `TFn` type only if a builtin has no recorded `declare_sig`)
so the trampoline's ptr/i64/double coercions match the real C ABI rather
than the generic March-fn conversion.

## Regression test

`test/test_stdlib_suite.ml`: `test_compiled_builtin_first_class_value`
(`adversarial-regressions` suite) — compiles and runs a program passing
`string_length` through a HOF parameter and calling it via `call_ptr`,
asserting the process exits 0 (the round-tripped value is correct).
