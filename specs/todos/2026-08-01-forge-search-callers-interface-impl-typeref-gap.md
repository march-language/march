`[P3]` **`forge search --callers` never records qualified type references that appear
only in an interface method signature or an impl/when-constraint header.**

Part of the `forge search --callers` reverse-reference-search plan
(`.claude/worktrees/eager-volhard-387ed0/.superpowers/sdd/2026-08-01-forge-search-callers/`).
Task 4 added `` `TypeRef `` recording for explicitly-qualified `Mod.TypeName`
type annotations, hooked into `Ast.TyCon`'s arm of `surface_ty`
(`lib/typecheck/typecheck.ml`). During implementation review, a real
misattribution bug surfaced: `env.current_decl` (the "caller" a reference gets
attributed to) is set only by `check_fn` and never reset, so any `surface_ty`
call site with no enclosing function — an interface method signature
(`Ast.DInterface`, `lib/typecheck/typecheck.ml`'s `check_decl` arm and the
`prebind_interface_decl`/`inject_iface_exports_ref` cross-module twins), or an
impl header/`when`-constraint type (`Ast.DImpl`) — was reading whatever
function happened to be checked immediately before it in module order,
producing a confidently wrong caller for `forge search --callers`.

**Fix round 1 (2026-08-01, same commit as this file):** rather than emit a
wrong caller, these call sites now wrap their `surface_ty` call in
`with_no_caller` (`lib/typecheck/typecheck.ml`, defined just after
`enter_level`/`leave_level`), which blanks `env.current_decl` to `""` for the
duration of the call; the `` `TyCon `` hook itself skips recording entirely
when `caller = ""`. Net effect: a qualified type used *only* inside an
interface method signature or an impl/when-constraint header is no longer
recorded as a `` `TypeRef `` reference at all — not attributed, not present.
Pinned by `test_typeref_interface_sig_no_stale_caller` in
`test/test_search.ml`.

**Still open:** these positions simply aren't tracked. A user running
`forge search --callers B.Widget` will not see a hit for a `B.Widget` used
only in `interface Foo(a) do fn conv: a -> B.Widget end` or
`impl Show(B.Widget) do ... end`, even though that's a legitimate reference a
completionist reverse-lookup should probably surface. Closing this gap
properly needs a real "what declaration is this?" concept for interface/impl
headers (there is no enclosing function to name as `caller` — the natural
`caller` would be something like `"A.Foo"` for the interface itself, or
`"impl Show for B.Widget"`, neither of which fits the current `ref_record`'s
`caller : string` field, which was designed to hold a fully-qualified
`Mod.fn` name). Scoped out of the `forge search --callers` v1 plan (Tasks
1-7) as a follow-up; revisit if/when interface/impl-header references turn
out to matter in practice.
