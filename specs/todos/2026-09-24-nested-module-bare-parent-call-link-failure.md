# `[P2]` A nested module's bare call to a parent function fails to LINK when the module is not the entry

Filed 2026-09-24 while fixing `stdlib/compress.march`'s hidden type errors
(`specs/progress/2026-09-24-stdlib-compress-error-type.md`).

A function in a nested module that calls a function of its enclosing module by
its bare name typechecks and runs interpreted, but a compiled program fails at
link time with the bare name undefined, whenever the enclosing module is loaded
as a library rather than being the compile's entry module:

```march
-- lib/outer.march   (reached through MARCH_LIB_PATH, or any stdlib module)
mod Outer do
  pfn helper(x : Int) : Int do x + 1 end
  mod Inner do
    fn f(x : Int) : Int do helper(x) end
  end
end

-- main.march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(Outer.Inner.f(41)))
  end
end
```

`MARCH_LIB_PATH=lib march main.march` prints `42`. `march --compile` fails:
`"_helper", referenced from: l_march_main_entry_thunk ... ld: symbol(s) not
found`. The same `Outer`/`Inner` shape written INSIDE the entry module links
and prints `42`, so it is the library-module lowering path that leaves the
call unqualified (`lib/tir/lower_state.ml`'s module-scope resolution:
`mod_prefix` / `current_module_aliases` / `_current_module_fns` are the
places to look).

Two things make it worse than a link error:

- the obvious workaround, calling it QUALIFIED (`Outer.helper(x)`), is
  rejected by the typechecker when `helper` is a `pfn` ("Function `helper` is
  private to module `Outer`"), even though the caller is lexically inside
  `Outer`. So a stdlib module must make the helper public to use it from a
  sub-module. `Compress.lift_encode_error` / `lift_decode_error` are public
  for exactly this reason.
- the stdlib diagnostic filter hides the privacy error, and the interpreter
  runs the bare call fine, so only a compiled program that reaches the call
  notices.

Fix: resolve a bare name in a nested module against the enclosing modules'
functions in the library-lowering path the way the entry path does, and let a
qualified call to an enclosing module's `pfn` from inside that module
typecheck. Then make the Compress lifts private again.
