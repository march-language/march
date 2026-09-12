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

## Also stamped, same day

`make_nil` / `make_cons` (`List`) and `mk_ok` / `mk_ok_unit` / `mk_err`
(`Result`) in `runtime/march_runtime.c`. Both types' C tags already matched
the declaration order the descriptor is keyed by — Nil=0/Cons=1, Ok=0/Err=1 —
and every call site in that file builds the type its helper's name says (14
`mk_ok`, 3 `mk_err`, 10 `make_cons`, 15 `make_nil`, audited individually),
so the id belongs to the helper rather than the caller.

Measured effect, erased slot, against a worktree built at `origin/main`:

| | `origin/main` | after |
|---|---|---|
| C-built `Result` (a `file_read` error) | `#<tag:1>` | `Err(NotFound("…"))` |

which is byte-identical to the interpreter, nested `FileError` included. Pinned
as the `erased=` line of `test/native/qualified_type_name_render`.

`Option` is deliberately NOT stamped: it is niche-encoded, so `Some(x)` IS `x`
and `None` is null — there is no cell to carry an id, and stamping the payload
would make the renderer print the payload's constructor under the wrapper's
name.

## Cost

One `i32` store per C-built cell, next to a `calloc` that already dominates.
A/B against a compiler built at `origin/main`, same box, interleaved runs,
first discarded:

| | base | after |
|---|---|---|
| 2M C-built cons cells (`string_split` x400k), min | 208 ms | 208 ms |
| `bench/binary_trees.march`, n=20, p25 | 257 ms | 257 ms |

The micro-benchmark is the one that actually exercises the changed path and
its minimum is unchanged. `binary_trees` does not use these builders at all,
and its deltas invert depending on which statistic and which batch is read
(min +3.3% / p25 +0.0% / median +0.6% in one run, min +0.8% / median +2.1% in
another) under a machine load of 5-8 from other sessions — noise, with no
mechanism behind it. Binary size grew 96 bytes on the micro-benchmark.

## Still open

Tuples and anonymous records have no declared type name to hash. The
`march_extras.c` and `march_http.c` builders (their own `make_ok`/`make_err`/
`make_cons`/`make_header`/`make_conn`, ~100 sites) are still unstamped; they
need the same per-helper audit before they can be, since a helper reused for
another shape would print a confidently WRONG constructor rather than a
placeholder.

Stamping also makes an existing renderer divergence reachable in more places:
an erased render quotes nested strings (`["a", "b"]`) where the interpreter's
`Show` path does not (`[a, b]`). That is pre-existing on `origin/main` —
verified by compiling the same program with a compiler built there — and is
filed as `specs/todos/2026-09-12-erased-render-quotes-nested-strings.md`.

The short-name lookup gap itself is NOT closed, only routed around for stamped
cells: a module-declared type whose value is built by compiled code and reaches
a site denoting it bare still resolves through the header id rather than the
name. Closing it properly means carrying the lowered spelling in the TIR type
at the call site (alternative 2 in the original todo), which no longer has a
user-visible symptom driving it.
