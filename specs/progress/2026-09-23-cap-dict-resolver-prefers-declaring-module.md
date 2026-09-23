# Capability dictionary resolver prefers the declaring module's record

**Landed:** 2026-09-23

## Problem

`Typecheck_env.resolve_cap_dict_type` resolved the record type named by
`proof cap X with T` by trying the BARE key `T` in `env.records` first and the
declaring module's qualification (`<Mod>.T`) only second. March has one global
type namespace, and a module's public records are exported under both the bare
and the qualified key, so when two modules each declare a dictionary type with
the same bare name, the bare key holds whichever module was exported LAST. The
other module's capability then resolved to the wrong record, and
`check_cap_impl_sites` (and any `cap_dict`/`cap_ops_empty` read) failed with
"expected `Ops` but got `Ops`".

Hit in PR #601 (D35, `Cap(ClusterNode.Live)`): adding `type Ops` to
`stdlib/cluster_node.march` broke `Session.attach` (`stdlib/session.march:66`).
Stdlib-spanned diagnostics are hidden, so only the whole-stdlib ratchet
(`entry_mod_qual_erasure` case 5) caught it; the PR renamed the type to
`ClusterOps` as a workaround.

## Fix

`resolve_cap_dict_type` now tries `<declaring module>.T` first (module from
`List.assoc_opt cap_path env.proof_caps`) and falls back to the bare `T` only
when the qualified key is absent. The fallback is still needed while the
declaring module itself is being checked: its records are registered under the
bare name inside the module and gain the qualified key only on export.

It returns the BARE spelling whenever the bare key holds the same declaration as
the qualified one, and the qualified spelling only on a real collision. A first
cut that always returned the qualified name broke
`error_improvements`/"arity mismatch: a note names the declared type parameter"
(`test_parameterised_type_arity_note`): a cap-dict `TCon("P.SessionOps", [])`
no longer printed like the record literal's `SessionOps(m)`, so
`report_mismatch`'s same-printed-name arity note never fired. "Same
declaration" is a structural compare of the field lists with each field's
`TyLinear` wrapper stripped. Physical equality is not enough, because the
prebind pass registers the qualified key and `check_decl` later re-registers
the bare key with a fresh, linearity-wrapped list. `Ast.ty` names carry spans,
so two separate declarations never compare equal.

Every consumer goes through this one function: the deferred
`check_cap_dict_decls` and `check_cap_impl_sites` sweeps, and the inline
`cap_dict` / `cap_ops_empty` inference arms via `Cap_dict_resolve.dict_ty_of_cap`,
so they cannot disagree.

## Tests

`test/test_cap_dict.ml`: two sibling modules `Alpha` and `Beta` each declare
`proof cap Live with Ops` over different `Ops` records; both `cap_impl` and
`cap_dict`, and a third module reads each dictionary through its qualified cap
(accept). A second case hands `Alpha`'s cap `Beta`'s field (reject), so the fix
cannot have loosened the check to a bare-name match. Both were RED before the
fix (the first with the exact "expected `Ops` but got `Ops`" diagnostic; the
second was wrongly ACCEPTED because `Alpha.Live` resolved to `Beta.Ops`).

## Follow-up

PR #601 (still open at landing) can rename `ClusterOps` back to `Ops` once it
is rebased onto this.
