`[P2]` **The tail-call analysis merges an entry module's names with the prelude's, fabricating an SCC.**

```march
mod Zed do
  fn go(ys : List(Int)) : Int do if length(ys) == 0 do 1 else 2 end end
  fn main() : Int do go([1]) end
end
```

→ ``Function `go`: recursive call to `length` is not in tail position``

There is no recursion here. `enforce_tail_calls_in_decls`
(`lib/typecheck/typecheck.ml`) builds `fn_names` and the call graph over one
flat decl list, and an entry module's members are unwrapped to top level next to
the prepended prelude's — so a nested helper's name colliding with an
entry-module function fabricates a strongly-connected component. Specifically
`stdlib/prelude.march`'s `fn length` contains an inner `fn go`, so any entry
module that defines `go` and calls `length` hits it.

Any entry-module function whose name collides with a prelude helper can trigger
this; `go` is simply the one that surfaced.

Surfaced 2026-07-30 while making `collect_direct_names` exhaustive (an
entry-module extern's self-qualified call now strips to the bare name and lands
here), but **entirely independent of that change** — reproduced with the
parent's `desugar.ml` swapped in, and the fault is in `typecheck.ml`, which that
commit does not touch.
