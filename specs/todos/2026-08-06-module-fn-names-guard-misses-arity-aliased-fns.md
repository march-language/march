# `module_fn_names` guard misses a default-argument function, so a method dispatch node can still union onto it

**Filed:** 2026-08-06, in review of
`specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md`. Same
class as the interface-default false positive fixed in `89c2362b`, but a
*different* instance, and this one **predates that round** — the `DImpl` guard
has had it since it was written in `38ab26fe`.

> **STATUS: STRUCTURAL READ OF THE CODE, NOT MEASURED.** No one has constructed
> the program below and observed the behaviour. Everything here is derived by
> reading `typecheck.ml` and `desugar.ml`. **Reproduce it first, before fixing
> it.** This branch has already had three findings change shape on
> re-measurement, so treat this description as a hypothesis with a suggested
> reproduction, not as an established fact.

## The gap

`lib/typecheck/typecheck.ml:8478-8484` builds the guard set:

```ocaml
let module_fn_names =
  List.filter_map (function
      | Ast.DFn (def, _) -> Some def.Ast.fn_name.Ast.txt
      | _ -> None)
    decls
in
```

It is consulted at `:8556` (the `DInterface` default-body dispatch edge) and
`:8586` (the `DImpl` method dispatch edge). Its job is to suppress the bare
method dispatch node when the module also declares a plain `fn` of that name, so
the plain function's key cannot absorb the method's capabilities.

But `decls` here is **post-desugar**, and `expand_defaults_decl`
(`lib/desugar/desugar.ml:2520`) rewrites `fn f(x \\ d)` into arity-mangled
`f$0` / `f$1` declarations and emits **no base `DFn` named `f`** (its own comment
says so: "No dispatcher DFns: the interpreter … automatically creates
VMultiarity entries for the base name"). So `module_fn_names` contains `f$0` and
`f$1`, never `f`, and the guard does not fire.

Meanwhile the same commit's arity alias (`:8754`, `arity_mangled_base`) records
each `f$N`'s caps and refs **under the bare `f`** — deliberately, so a caller's
reference to `f` resolves. Net effect, if the reading is right: for a module
declaring an interface default (or impl method) `f` *and* a plain `fn f` with a
default argument, the bare `f` node ends up unioning the method's capabilities
with the real function's.

## Suggested reproduction

Not yet run. Expected shape:

```march
mod Clash do
  interface Greeter(a) do
    fn greet : a -> Unit
    fn greet_loud : a -> Unit do fn (x) -> print("loud") end
  end
  fn greet_loud(n, bump \\ 1) do n + bump end   -- pure, and defaulted
end
```

Check whether `fn_own_capability_closures` / `fn_transitive_capability_closures`
attribute `IO.Console` to the bare `Clash.greet_loud`. Confirm first that the
program typechecks (the non-defaulted version does, exit 0 — that is what
`test_interface_default_does_not_capture_a_same_named_fn` is built on).

## Why this is not blocking

Stated deliberately, because these mitigations are what made it a follow-up
rather than a merge blocker:

- **Capped for Check 4.** `import_required_caps` *filters* the imported module's
  declared `needs` by the demand set (`typecheck.ml:8352-8355`) rather than
  returning it, so the result is a subset of `mod_caps` by construction. No
  addition to `own_cap_closures` can make Check 4 stricter than the
  pre-demand-driven module-granular rule.
- **It is NOT the hot-deploy-manifest false positive fixed in `89c2362b`.** The
  manifest is keyed by TIR function names, and a defaulted function is keyed
  `f$N` there, not bare `f`. So the bare `f` union does not land on a manifest
  line for the real function. (This is the surface where the fixed bug was
  actually observable — `bin/main.ml:3534` reads
  `fn_own_capability_closures` unfiltered — so its absence here matters.)
- The corpus is thin on the shape. Counted over `stdlib/*.march`,
  `test/native/*.march` and `bench/*.march` (277 files): **2** `interface`
  declarations in total — `test/native/default_method_args.march` and
  `test/native/iface_collision_ambiguous_call.march` — with exactly **one**
  default method body between them (`neqx`), and no module declaring both a
  method and a same-named plain `fn`. (Every other `interface` hit in the
  corpus is prose in a comment.) The per-function own-caps sweep over the same
  277 files found 0 keys whose capabilities changed. So this is very unlikely
  to be live in-tree today — which is also why a sweep cannot be the thing that
  guards it.

## Shape of the fix

The guard must consider desugar's arity-alias naming, not just bare `DFn` names:
when collecting `module_fn_names`, also add `arity_mangled_base name` for every
`DFn` whose name is arity-mangled — i.e. a module declaring `f$0`/`f$1` should
count as declaring `f` for guard purposes, exactly as the alias at `:8754`
already treats it as declaring `f` for recording purposes. The two sites should
agree on what "this module declares a `fn` called `f`" means; today they do not.

Whatever the fix, pin it the way the Critical was pinned: a REJECT test
asserting the specific function's entry in `fn_own_capability_closures` is
EMPTY, plus a control proving the method's own mangled key still holds the
capability. A corpus sweep will not catch this class — it bounds blast radius,
it does not detect misattribution within a module.

## Related, minor — an assertion that is weaker than it looks

`test_interface_default_does_not_capture_a_same_named_fn`'s first assertion is

```ocaml
Option.value ~default:[] (List.assoc_opt "greet_loud" (… fn_own_capability_closures env))
```

so it **cannot distinguish "key absent" from "key present and empty"**. Benign
today — the `DFn` arm always creates the key for a plain `fn`, and the test's
third assertion (the default body still holds `IO.Console` under
`Greeter$default.greet_loud`) covers the "did anything get recorded at all"
direction. Worth knowing before anyone reads it as a stronger check than it is;
if this todo's fix reshapes those keys, tighten it to match on the key's
presence explicitly.
