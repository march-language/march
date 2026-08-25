# Defining a fn whose body contains a lambda: undefined symbol at the REPL, SIGSEGV when compiled (fixed 2026-08-24)

```
march(1)> fn f(xs) do List.map(xs, fn y -> y + 1) end
jit error: dlopen(.../repl_0.so): symbol not found in flat namespace '_f'
march(2)> f([1,2,3])
I cannot find `f`.                       -- the binding was lost
```

Two independent bugs stacked on the same repro. The first is NOT REPL-specific
— the same program miscompiles ahead-of-time:

```march
mod T do
  needs IO
  fn f(xs) do List.map(xs, fn y -> y + 1) end
  fn main(cap : Cap(IO)) do println(f([1, 2, 3])) end
end
```

`march --compile` this and the binary exits 139 (SIGSEGV). Rename `f` to `g`
and it prints `[2, 3, 4]`. The bug is keyed on the NAME.

## Bug 1 — defun dropped a lambda's capture when a top-level fn shadowed it

`stdlib/list.march`'s `map` is the canonical HOF shape: a param `f`, closed
over by an inner `go` accumulator.

```march
fn map(xs : List(a), f : a -> b) : List(b) do
  fn go(lst, acc) do ... Cons(f(h), acc) ... end
  go(xs, Nil)
end
```

`Defun.free_vars_of_expr` excludes any name present in the module's top-level
fn set — genuine top-level refs must not be captured into a closure. But
`collect_lambdas` passed that set unmodified regardless of what the ENCLOSING
scope had bound, so when the module being lowered contained a user top-level
`fn f`, map's *parameter* `f` was mistaken for that global and `go`'s capture
set came back empty. Phase 3 then left `f(h)` as a direct `EApp`, which
`Llvm_toplevel.emit_fn` emitted as `call i64 @f(...)` — a call straight into
the user's unrelated function.

Visible in the post-defun TIR (`MARCH_DUMP_TXT=defun`): `go$apply$N` binds
`go = $clo` and nothing else, while its body still says `f(h)`.

Compiled, that is a call with the wrong signature to the wrong code — SIGSEGV.
At the REPL, `f` is not defined in the helpers fragment at all, so macOS dyld
rejects the whole fragment at `dlopen` with `symbol not found in flat
namespace '_f'`.

**Fix** (`lib/tir/defun.ml`): `collect_lambdas` now threads a `bound` set of
enclosing-scope binders (host fn params, lets, case-arm vars, outer lambda
names/params) and subtracts it from `top_level` before the free-var walk —
local binders shadow same-named top-level fns, so they stay capturable. This is
the capture-side sibling of the existing phase-3 case-B shadowing fix (the `go`
name-collision bug already recorded in `progress_through_july_2026.md`); that
one made *calls* to a shadowed name dispatch indirectly, this one makes the
name *capturable* in the first place.

## Bug 2 — helper lambdas were compiled in a fragment loaded BEFORE the fn

`Repl_jit.run_decl`'s `is_fn_decl` path emitted the defun'd helper lambdas via
`emit_fns_fragment` into their own fragment, compiled and dlopen'd it, and only
then emitted the primary fn. A lambda inside the fn body may legitimately
reference the fn being defined:

```
march(1)> fn g(n) do if n <= 0 do 0 else List.length(List.map([n], fn y -> g(y - 1))) end end
jit error: dlopen(.../repl_1.so): symbol not found in flat namespace '_g'
```

macOS binds a dylib's undefined symbols eagerly at `dlopen`, so the helpers
fragment failed even though `g`'s own fragment was about to be loaded one
statement later. `-undefined dynamic_lookup` does not cover it: it defers
resolution to load time, not past it. ORC fails the same way for its own
reason (one shared JITDylib, symbol not yet defined).

**Fix** (`lib/tir/llvm_repl.ml`, `lib/tir/llvm_emit.ml`, `lib/jit/repl_jit.ml`):
`emit_repl_fn_with_closure_slot` takes a new `?helper_fns` list and *defines*
those functions in the same module as the primary fn and the closure-slot init;
`run_decl` no longer emits a separate helpers fragment. Helpers still need to
share a module with each other (an outer lambda allocates an inner lambda's
closure) — that requirement is unchanged, just widened to include the primary.

## Tests

- `test/test_codegen.ml`, `repl_jit_cross_line` group (Quick):
  `fn with lambda shadowing List.map's param compiles + runs` and
  `fn self-recursive through its lambda helper`. Both drive the real
  `run_decl ~is_fn_decl:true` → `run_expr` sequence over a precompiled
  `list.march` prelude, exactly as `lib/repl/repl.ml`'s `DFn` arm does.
  Verified RED on the reverted sources (both `[FAIL]`), GREEN after.
- `test/test_stdlib_suite.ml`, `adversarial-regressions` group (Slow):
  `lambda capture survives user fn shadowing a HOF param (f)` compiles and runs
  the AOT program above — it is the compiled-mode witness for bug 1, which no
  REPL test can cover.

Both backends verified by hand on the two repros (`MARCH_JIT_BACKEND=orc` and
the default clang path).

Full suite green: 932 compiler / 273 eval / 589 codegen / 869 stdlib (incl. Slow)
/ 61 stdlib_march. `test/repl_smoke_test.sh` is unchanged at 48 pass / 6 fail —
identical on a reverted-source control, so those 6 are pre-existing (three use
the `then` keyword March does not accept). Run it with a private `HOME`: the
shared `~/.cache/march` prelude gets poisoned by concurrent sessions and
manufactures four extra phantom failures. `bench/list_ops.march` (the
closure/HOF benchmark this pass covers) compiles and runs correctly at ~0.06s.

## Follow-up noticed, and fixed independently upstream

While debugging, defining a fn that calls a fn from an EARLIER REPL line also
failed (`invalid redefinition of function 'a1'`): `emit_slot_loader_fns` emits a
zero-arg `define ptr @a1()` slot loader into the new fragment while `extern_fns`
has already `declare`d `@a1` at its real arity. Filed as a todo at the time;
`4946a914` ("a REPL fn calling a prior REPL binding no longer emits invalid IR")
landed on main independently and fixes it by routing such calls through the
loader + closure dispatch, so the todo was dropped rather than merged. Verified
against the merged tree: `fn a1` then `fn b1` calling it then `b1(5)` answers
`12`.
