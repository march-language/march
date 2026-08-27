# `inject_iface_exports_ref` is installed but never read — cross-module interface exports are silently dropped

**Filed:** 2026-08-27, at `f3c37fb6`. Found while planning
`specs/plans/2026-08-27-remaining-decomposition-targets.md` Target B (the
module-initialisation-order hazard that gated Phase 6 tasks 6.7/6.8).
**Not fixed** — this is a report.

## The finding

`lib/typecheck/typecheck_env.ml:1073` declares a forward hook:

```ocaml
let inject_iface_exports_ref
  : (string -> March_modules.Module_registry.module_exports -> env -> env) ref =
  ref (fun _mod_name _exports env -> env)
```

`lib/typecheck/typecheck.ml:745` installs a real implementation into it (a
33-line closure, `:743–775`, that folds `ExInterface` entries into `env.vars`
as `Mod.method` bindings).

**Nothing dereferences it.** The whole tree contains exactly four occurrences of
the string, and none of them is a read:

```
$ grep -rn 'inject_iface_exports' lib/ lsp/ bin/ forge/ test/
lib/typecheck/typecheck.ml:745:let () = inject_iface_exports_ref := (fun mod_name exports env ->
lib/typecheck/typecheck_env.ml:1073:let inject_iface_exports_ref
lib/typecheck/typecheck_env.ml:1079:    ... handled separately via inject_iface_exports_ref. *)
lib/typecheck/typecheck_env.ml:1166:    | ExInterface _ -> env  (* handled by inject_iface_exports_ref ... *)
```

`typecheck_env.ml:1166` is the load path that the hook is supposed to complete:
`load_module_into_env` matches `ExInterface _ -> env`, i.e. it drops the export
on the floor and defers to a hook that no one calls. `typecheck.ml:743`'s own
comment names the intended caller — "so `resolve_qualified_var` can inject
interface method bindings cross-module" — and `resolve_qualified_var` does not
call it.

## Why it looks like an unfinished feature, not a regression

```
$ git log --oneline -S'inject_iface_exports_ref' -- lib/typecheck/ | tail -1
d95631a6 wip: in-progress changes (interface exports, try_suffix qualified lookup, stdlib/runtime)
```

Both the declaration and the installation arrived together in that WIP commit
(2026-04-10). A read site was never added, so this has been inert since birth;
the Phase 6 decomposition (`7c8cb588`) only moved the declaration into
`typecheck_env.ml`.

## Observable consequence (unconfirmed)

A cross-module `ExInterface` export should make `Mod.method` resolvable in the
importing module. Since the injection never runs, it presumably is not. **This
has not been reproduced** — no fixture was written. Before fixing, write a
two-module reject/accept fixture that exercises a qualified interface-method
reference across a module boundary and confirm the failure mode.

## What to do

One of:

1. **Finish it** — call the hook from `load_module_into_env` (or from
   `resolve_qualified_var`), guarded so the ordering constraint the forward ref
   exists for still holds, plus a conformance fixture.
2. **Delete it** — remove the declaration, the installation and the two
   comments, and change `typecheck_env.ml:1166`'s `ExInterface _ -> env` comment
   to say plainly that cross-module interface exports are not injected.

Do not leave it as is: the comments assert a behaviour the code does not have.

## Side note for refactoring

Until this is resolved, `lib/typecheck/` has exactly **two** top-level side
effects in the entire library —

```
$ grep -n '^let () =' lib/typecheck/*.ml
lib/typecheck/typecheck.ml:745:let () = inject_iface_exports_ref := ...
lib/typecheck/typecheck.ml:841:let () = expand_record_ref := ...
```

— and this one is a no-op. That is what makes Target B's task B3 (extract §1/§2
to `typecheck_unify.ml`) safe: see the plan for the argument.
