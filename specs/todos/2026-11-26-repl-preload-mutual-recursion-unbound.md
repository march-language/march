`[P3]` `march repl FILE`: mutually recursive functions in the file are unbound (2026-11-26)

Loading a file whose functions call each other leaves both unbound:

```march
mod MR do
  needs IO.Console
  fn ev(n : Int) : Bool do if n == 0 do true else od(n - 1) end end
  fn od(n : Int) : Bool do if n == 0 do false else ev(n - 1) end end
end
```

`march repl mr.march` prints "I cannot find `od`" and "I cannot find `ev`" while loading,
then `ev(10)` at the prompt is "I cannot find `ev`". A batch run of the same module is
fine. The preload apparently checks the declarations one at a time, so the first one's
call of the second has nothing to resolve to.

A related failure seen at the same time, not investigated: with `od` no longer calling
`ev` (`fn od(n) do if n == 0 do false else n > 100 end end`, defined first), loading
succeeds but `ev(10)` at the prompt fails with
`March_tir.Llvm_calls.Unknown_callee("`ev` (called from
`$clodrop$$Clo_$jp7__repl1_method_words$0_Authority_method_words`) ...")`. Both happen on
main without the A1.3 change (checked 2026-11-26 by reverting it).

Found because `test/cap_conformance/frame_mutual_tail.march` (A1.3) cannot run in the
conformance runner's REPL mode; it is in `repl_unsupported` with a pointer here. Remove
that entry when this is fixed.
