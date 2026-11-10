`[P3]` JS target: Float `/.` by zero gives Infinity/NaN instead of stopping

`x /. 0.0` (or `-0.0`) is specified to stop with "division by zero"
(`specs/lang/core-march.md`, δ-Div-0F). The interpreter does, and native code calls
`march_checked_fdiv` (`runtime/march_runtime.c`). `--target js` emits a plain JS `/`
(`lib/tir/js_emit.ml`, the `"/."` arm of the binary-operator table), so the program
goes on with `Infinity`, `-Infinity` or `NaN`:

```
println(float_to_string(1.0 /. 0.0))
```

prints `inf` and exits 0 under node; the interpreter and a native build stop, exit 1.
Since the #1169 fold fix this holds with opt.fold on or off (before it, the folded
form was the `inf.0` SyntaxError). Int `/` and `%` by zero were fixed the same way on
JS in #1194 (an inline zero test that throws); `/.` needs the same treatment, and
`test_compiled_float_div_zero_literal` in `test/test_codegen.ml` then gains a JS half.
