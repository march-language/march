# `[P2]` A function from another module taken as a value fails to compile

**Logged:** 2026-10-13, found while extending the call-arity check
(`specs/progress/2026-10-12-two-arg-fn-accepted-as-curried.md`).

```march
mod LL do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let k = List.length
    println(int_to_string(k([1, 2])))
  end
end
```

- `--check`: clean. Interpreted: prints `2`.
- `--compile`: `error: use of undefined value '@List.length'` from clang on the emitted
  `.ll`, exit 1.

A stdlib (or other-module) function used as a first-class value, rather than called
directly, is referenced in the IR by a name no function is emitted under (the direct
call path resolves it; the value path does not, or the function was pruned because no
direct call kept it alive). Start with `march query callers List.length FILE` and the
`tir-defun` / `tir-dce` dumps (`MARCH_DUMP_TXT=tir-defun`) to see whether the
reference survives defunctionalisation and the definition does not survive DCE.
