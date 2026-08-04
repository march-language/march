**CLOSED 2026-08-03 — WON'T FIX, on a count.** The position does not occur. Evidence and
reasoning at the end of this file; the original analysis is kept because the
`with_no_caller` fix it describes is live and must not be undone.

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

---

# Implementation spec (added 2026-08-03)

## The blocker is a type, not an algorithm

`ref_record.caller` is a `string` documented as a fully-qualified `Mod.name`
(`lib/typecheck/typecheck.ml:494`). Interface and impl headers have no such name, which is
why `with_no_caller` blanks the field and the `` `TyCon `` hook then skips recording
entirely. Every route to closing this gap goes through widening that field first.

Widen it to a variant rather than encoding a second kind of thing into the string — a
`"impl Show for B.Widget"` caller would be indistinguishable from a function actually named
that, and every consumer would need to re-parse it:

```ocaml
type ref_owner =
  | Fn of string            (* "Mod.fn" — today's only case *)
  | Interface of string     (* "Mod.Foo" *)
  | Impl of { iface : string; ty : string }
```

`env.current_decl` becomes a `ref_owner option ref` (or keeps `""` meaning "not recording"
and gains the variant alongside — decide by what reads it; check every `current_decl` use
before choosing).

## Then the recording sites

Replace `with_no_caller` at the three sites it currently guards with a `with_owner`
that sets the appropriate variant:

- `Ast.DInterface` in `check_decl` → `Interface "Mod.Foo"`
- its cross-module twins `prebind_interface_decl` / `inject_iface_exports_ref` → same
- `Ast.DImpl` header and `when`-constraint types → `Impl { iface; ty }`

The `` `TyCon `` hook's `caller = ""` skip then becomes "skip only when there is genuinely
no owner", which after this change should be a much smaller set — audit what remains, since
anything still hitting it is a position nobody has thought about.

## Rendering

`forge search --callers` prints the caller. Decide the surface spelling once, in
`forge/lib/cmd_search.ml`, and keep the variant intact everywhere upstream:

```
B.Widget
  A.convert                     lib/a.march:12          (call)
  interface A.Renderable        lib/a.march:4           (type)
  impl Show for B.Widget        lib/b.march:31          (type)
```

## Why this is P3, and the honest case for leaving it

The current behaviour is *silent under-reporting*: a legitimate reference is simply absent
from the results. That is the safe direction — a reverse-lookup that misses a hit sends
someone to grep, whereas one that reports a wrong caller (which is what this position did
before the `with_no_caller` fix) sends them to the wrong file with confidence.

So the question to answer before spending the day is whether interface/impl-header
references matter in practice. A cheap way to find out: count them. Grep the stdlib and a
couple of real projects for qualified types appearing only in interface signatures or impl
headers. If that number is small, close this as won't-fix and say so in the file rather
than leaving it open indefinitely.

## Acceptance

- `forge search --callers B.Widget` reports a hit for a `B.Widget` used only in
  `interface Foo(a) do fn conv: a -> B.Widget end` and one used only in
  `impl Show(B.Widget) do … end`, each with a caller that names the interface or impl
  rather than a function.
- REJECT witness — the one that must not regress:
  `test_typeref_interface_sig_no_stale_caller` (`test/test_search.ml`) currently pins that
  these positions do NOT attribute to whatever function was checked just before them. Any
  fix must keep that property; the failure mode being prevented is a *confidently wrong*
  caller, which is worse than the missing one this todo is about.
- A second REJECT witness: a qualified type inside a plain function body still attributes
  to that function, not to an enclosing interface/impl owner left set by a missing restore.
  `with_owner` must be `Fun.protect`-scoped exactly as `with_no_caller` is.


---

# Closed 2026-08-03: won't fix

The implementation spec added earlier said to count the affected positions before spending
a day on this, and to close the file explicitly if the count was small rather than leave it
open forever. The count:

| Corpus | Interface decls | Impl headers | With a qualified `Mod.Type` |
|---|---|---|---|
| `stdlib/` (112 modules) | 0 real (6 mentions, all in comments) | 20 | **0** |
| whole repo `.march` (incl. 27 in the conformance corpora) | 36 | — | **0** |
| conduit (43 files, external) | — | — | **0** |

Every impl header in the repo names a bare type — `Eq(BigInt)`, `Show(Decimal)` — and no
interface method signature anywhere mentions a qualified type. The gap describes a position
that no March code in existence occupies.

## Why closing is the right call, not just the cheap one

The current behaviour is silent **under**-reporting: a legitimate reference is absent from
the results. That is the safe direction. A reverse-lookup that misses a hit sends someone
to grep; the *confidently wrong* caller this position produced before the `with_no_caller`
fix sent them to the wrong file believing the tool. Under-reporting a position that occurs
zero times costs nothing measurable.

Closing it also avoids a real cost: fixing it requires widening `ref_record.caller` from
`string` to a variant and touching every consumer, to record references that do not exist.

## If this is reopened

Two things must survive, and they are the reason this file is kept rather than deleted:

- `test_typeref_interface_sig_no_stale_caller` (`test/test_search.ml`) pins that these
  positions do NOT attribute to whatever function happened to be checked before them. That
  is the actual bug that was fixed here, and it is a different bug from the one closed.
- Any `with_owner` replacement must be `Fun.protect`-scoped exactly as `with_no_caller` is,
  or a leaked owner reattributes ordinary function-body references.

Reopen if interface/impl-header references start appearing in real code — the count above
is the thing to re-run, and it is a one-line grep.
