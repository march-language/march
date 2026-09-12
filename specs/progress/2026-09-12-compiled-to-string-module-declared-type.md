# Compiled `to_string` of a module-declared type prints its constructor

**Filed:** 2026-09-11 (as `specs/todos/2026-09-11-compiled-to-string-of-module-declared-type.md`)
**Landed:** 2026-09-12

## The gap

```march
match dir_list("/nonexistent/zzz") do
  Ok(_)  -> ()
  Err(e) -> println(to_string(e))
end
```

```
interpreted:  NotFound("/nonexistent/zzz")
compiled:     #<tag:0>
```

`Llvm_ctor_desc.assign_ids` keys the constructor-name descriptor by the name a
type is **lowered** under — qualified, `File.FileError`, because the `ptype`
sits inside `mod File`. `id_for` looks a call site up by its **static TIR type
name**, which for a builtin's return type is the canonical bare `FileError`
(the builtin tables are right to spell it bare: March has one global type
namespace and a module type's canonical identity is its bare name). The lookup
missed, `id_for` answered `None`, and the site stayed on the type-erased
renderer, which had only a tag.

## Why the obvious fix is unsound — now with the mechanism, not just the symptom

The todo recorded that aliasing the bare short name onto the qualified type's
id **deterministically SIGSEGVs** `native_actor_monitor_down_reason` (40/40),
that restricting the alias to unambiguous short names did not help, and that
moving the fallback from `assign_ids` into `id_for` did not either. It could
not say WHICH lookup mis-resolved. Reproduced here (40/40 exit 139, against a
0/40 control with the change reverted) and then instrumented, as that todo's
"where to start next" prescribed. One line answers it:

```
[id_for] static Pid  ->  id 151  (descriptor GlobalPid.Pid)
```

`Pid` is a **builtin runtime handle** — an actor reference, not a boxed
constructor cell — and it is also the short name of stdlib's `GlobalPid.Pid`.
The alias handed an actor handle a constructor descriptor, and the renderer
read it as a cell.

This is why the unambiguous-suffix narrowing did not help: `Pid` IS unambiguous
among declared types. The name it collides with is not a declared type at all,
so no check over `type_defs` — `Collision_set` included — can see it. **Any**
compile-time bare-name resolution has this hole; the fix had to come from
somewhere other than the name.

## What landed

The value identifies itself. `mk_file_error` (`runtime/march_runtime.c`) stamps
the cell it builds with `File.FileError`'s header type id
(`march_type_id_of_name`, the pad-word scheme from
`specs/progress/2026-09-11-boxed-adt-type-id.md`), so the type-erased renderer
resolves it through the descriptor table from the cell rather than from a name
it could not resolve. A header id cannot make the `Pid` mistake: it is written
by whoever built the cell, so a value that is not a stamped ADT cell carries no
id and renders exactly as before.

`Llvm_ctor_desc.emit_ensure_if_erased` also had to widen to any named type, not
just an erased one: the dynamic path needs some descriptor registered before it
can resolve anything, and nothing on the runtime side can find one by itself.
It only registers — it decides nothing — so a value whose header says nothing
is unaffected.

## Proof

- `test/native/qualified_type_name_render` (new): `file_read` and `dir_list`
  errors render by constructor. Proven RED on the unfixed compiler (both lines
  `#<tag:0>`) before the fix, GREEN after. `.expected` is the interpreter's own
  output.
- The todo's acceptance: `native_actor_monitor_down_reason` **0/40** nonzero
  exits with `.march/cas/artifacts-v2` cleared first (a warm CAS silently
  returns the previous binary and made this bisect lie twice during the
  original investigation), against the reproduced 40/40 for the alias attempt.
- `test/test_stdlib_suite.ml`'s thirteen-case `file_*`/`dir_*` table tightened
  from "interpreter form OR `#<tag:N>`" to byte equality with the interpreter,
  and the single-case `file_open` guard likewise. Full stdlib suite: 879 tests,
  exit 0.

## Still open

Only `mk_file_error` is stamped. The rest of the C builders (`make_cons`,
`make_ok`, `make_some_i64`, HTTP header pairs; ~100 sites) still build
unstamped cells, so a `List` or `Result` produced by the runtime and rendered
through an erased slot keeps today's output. Stamping them is mechanical —
give each `make_*` helper its type id — but it is a separate change with its
own benchmark and IR-oracle obligations.

The short-name lookup gap itself is NOT closed, only routed around for stamped
cells: a module-declared type whose value is built by compiled code and reaches
a site denoting it bare still resolves through the header id rather than the
name. Closing it properly means carrying the lowered spelling in the TIR type
at the call site (alternative 2 in the original todo), which no longer has a
user-visible symptom driving it.
