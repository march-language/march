# `[P1]` Compiled: a local named like a builtin/interface method was called as the builtin (so `Map`/`Set` ignored their comparator)

Completed 2026-09-25. Closes `specs/todos/2026-09-24-param-named-eq-lowers-as-builtin.md`
(filed on PR #642's branch `fix/compare-nan-backends`; that PR had not merged
when this landed, so the todo file is not on main to `git mv`).

## Symptom

```march
pfn via_eq(eq, a, b) do eq(a, b) end
via_eq(fn (a : Int, b : Int) -> true, 1, 2)   -- interpreted true, compiled false
```

In compiled code, a call through a LOCAL binding (parameter, `let`, pattern
variable, lambda parameter, nested `fn`) whose name is also an interface method
or builtin was resolved as the global. `eq(a, b)` became `Eq$Int.eq(a, b)`
(i.e. `==`), `compare` became `Ord$T.compare`, `hash` the builtin hash, `show` /
`to_string` the `Show` impl.

`stdlib/map.march`, `stdlib/set.march` and `stdlib/hamt.march` name their
comparator-derived equality closure `eq`, so compiled `Map` / `Set` compared
keys with `==` and never called the caller's comparator. A `Float` NaN key was
never found and re-inserting it added a second entry. A comparator whose
equality is not `==` gave different results from the interpreter.

## Cause: two passes, each missing one kind of local

1. **Lowering** (`lib/tir/lower_expr.ml`, the `EApp` arm's interface-method
   redirect). When the first argument's type was concrete at lowering time
   (a monomorphic `eq : Int -> Int -> Bool` parameter, or a `let eq = fn ...`
   in a monomorphic function), the call was rewritten to the impl
   (`Eq$Int.eq`). The only guard was `_current_module_fns` (a same-module
   top-level fn of that name). Locals were not checked, although lowering
   already tracks them for import-alias shadowing (`_fn_param_types` +
   `_scope_locals`).
2. **Mono** (`lib/tir/mono.ml`, `rewrite_calls`). For a polymorphic
   parameter, lowering left `eq(a, b)` alone, and mono resolved it as an
   interface method once specialisation made the first argument's type
   concrete. `rewrite_calls` has a `shadowed` set for exactly this purpose,
   but it was seeded with `SSet.empty` for each specialised fn and nested
   fn/lambda bodies. It covered `let` binders, pattern variables and
   nested-fn names, but **never function parameters**. The
   `ELet(v, ELetRec ...)` special case (a generalised local fn or lambda bound
   by `let`) also dropped `v` from the continuation's set, so
   `let eq = fn (x, y) -> ...` then `eq(a, b)` was not shadowed either.

`--dump-tir` / `MARCH_DUMP_TXT=all` locates it. In `Map.node_get` the call is
`eq(lk, key)` at `tir-lower` and `Eq$String.eq(lk, key)` from `tir-mono` on.
The monomorphic cases already show `Eq$Int.eq` at `tir-lower`.

## Fix

- `Mono.shadow_params`: each fn body is rewritten with its own parameters in
  `shadowed`. This covers the specialised fn at the worklist entry, nested fns
  in `ELetRec`, and fns in the `ELet(v, ELetRec)` special case. That special
  case now also adds `v` for the continuation.
- `Lower_state.is_local_binding` (`_fn_param_types` or `_scope_locals`)
  guards the lowering-time interface redirect. The same guard now also covers
  the other name-keyed builtin rewrites in the same arm family: `tap`
  (previously checked `_fn_param_types` only), `march_version`, `own`, and the
  interpreter-only-builtin rejection.

Both changes are general. They key on the binder, not on any particular
name, so every builtin or interface-method name is covered (`eq`, `compare`,
`hash`, `show`, `to_string`, and any user interface method).

## The "Related" curried-closure SIGSEGV: fixed here, different root cause

Compiled, passing a top-level function that RETURNS a closure
(`fn curried_lt(a : Int) : Int -> Bool do fn b -> a < b end`) as a value to a
generic fn that calls it curried (`let f = cmp(a)` then `f(b)`) exited 139
with `pc=0x0`.

This is a different bug. It is in `lib/tir/llvm_emit.ml`, in the
`$clo_wrap` trampoline built for a top-level fn used as a first-class value.
The trampoline took its signature from the **use-site** type. The
typechecker's arrows are curried, and `convert_ty` uncurries the use-site
`Int -> Int -> Bool` into a 2-param `TFn([Int; Int], Bool)`. So the trampoline
called the 1-param `@curried_lt` with two args and treated the returned
closure pointer as an i64. Now, when the use-site arity disagrees with the
definition (`top_fn_param_tys` / `top_fn_ret_ty`), the trampoline follows the
definition.

It had to be fixed in this PR: once `Map` really calls its comparator, every
stdlib `Map` caller that passes `Map.str_cmp` / `Map.int_cmp` (top-level fns
of exactly this shape, about 100 call sites in `stdlib/`: ClusterNode, SWIM,
membership, CRDT, the registries, and more) runs the broken trampoline.
`test/native/topology_place` SIGSEGV'd with only the shadowing fix applied.
It passes with both fixes.

## Stdlib audit: locals named like a builtin/interface method that are called

All of these were silently miscompiled before this fix (the comparator was
ignored and `==` used). All are `eq`:

- `stdlib/map.march`: params `eq` of `coll_find`, `coll_insert`,
  `coll_remove`, `node_get`, `node_insert`, `node_remove`, and
  `let eq = fn (a, b) -> cmp_eq(cmp, a, b)` in `get`, `insert`, `remove`.
- `stdlib/set.march`: params `eq` of `coll_has`, `coll_insert_elem`,
  `coll_remove_elem`, `node_contains`, `node_insert`, `node_remove`, and
  `let eq = ...` in `contains`, `insert`, `remove`.
- `stdlib/hamt.march`: params `eq` of `collision_find`, `collision_insert`,
  `collision_remove`, `hamt_get`, `hamt_insert`, `hamt_remove`.

No stdlib local is named `compare`, `hash`, `show`, `to_string`, `print`,
`tap` or `own`. The comparators the stdlib passes to `Map` (`Map.str_cmp`,
`Map.int_cmp`, `Presence.str_cmp`, `PubSub.str_cmp`,
`ChannelSocket.str_cmp_cs`, `DataFrame`'s `str_cmp`) are all `a < b` on
`String`/`Int` and consistent with `==`. So apart from NaN keys, stdlib-internal
Map behaviour is unchanged. The only new work is actually calling the
comparator.

## Evidence

- New native golden `test/native/local_named_like_builtin.{march,expected}`
  (dune rule `native_local_named_like_builtin`, plus 2 lines in
  `test/refine_audit/corpus.baseline`). `.expected` is the interpreter's
  output. It covers every binder kind × `eq`/`compare`/`hash`/`show`/
  `to_string`/`int_to_string`/`print`, polymorphic and monomorphic; a
  Float-keyed Map with a NaN key (get, re-insert, size, contains, remove); a
  Float Set with NaN; a case-insensitive String comparator; a comparator under
  which no key equals itself; the curried top-level comparator; and
  `Map.int_cmp`/`Map.str_cmp` passed as values.
- RED on origin/main (`d166c3399`), compiled vs interpreted: `via_eq` false,
  `via_compare` -1, `via_hash` 1626386729513190885, `via_show` "1",
  and `let_eq`/`nested_fn_eq`/`lam_eq` false. The final golden then dies on
  the curried top-level call (SIGBUS/SIGSEGV, exit 138/139). An earlier cut
  of the golden without that line also showed, on origin/main,
  `get nan` None, `size after re-insert nan` 3, `contains nan` false and
  `never_eq get 7` Some(seven). A separate probe showed a Float `Set` with NaN
  inserted twice at size 2 with `contains` false (interpreted: 1 / true).
- GREEN: the golden matches byte-for-byte. `test/native/topology_place` and
  the related native goldens (`closure_call_arg_ownership_probe`,
  `iface_method_collision`, `perceus_three_deep_field_borrow`,
  `prelude_scope_user_shadow`, `ring_buf_ops`, `aggregate_param_field_alias`,
  `default_args_nested`) still match. `run_snapshots.exe` is unchanged (no
  golden moved: no snapshot corpus program calls a local named like a
  builtin). The codegen groups `iface_impl_mono_codegen`,
  `nested_fn_name_collision_codegen`, `name_resolution`, `known_call`,
  `llvm_emit`, `inline`, `tco_codegen`, `stdlib`, `correctness`, `builtins`,
  `repr`, `llvm_ir_validity_gate` pass, as do the compiler groups
  `builtin_compiled_lowering`, `interface_method_qualifiability`,
  `prelude-collision`, `entry_mod_qual_erasure`, `curried_lambda_over_tuple`,
  `cap_shadow`.
