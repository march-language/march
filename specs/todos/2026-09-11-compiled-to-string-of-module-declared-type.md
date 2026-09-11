# Compiled `to_string` of a module-declared type prints `#<tag:N>`

**Filed 2026-09-11**, from the §2 work in
`specs/2026-09-11-correctness-fixes-design.md`. The *matching* half of that
section landed (a cross-module constructor now registers its parent type under
the canonical bare name, so `Err(File.NotFound(p))` is matchable — see
`specs/progress/2026-09-11-fileerror-qualified-ctor-type.md`). This is the half
that did **not**, and an attempt to land it caused a deterministic SIGSEGV, so
the evidence is written down here rather than re-derived.

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

`test/test_stdlib_suite.ml`'s thirteen-case `file_*`/`dir_*` table accepts
either form for exactly this reason, and `test/native/file_error_ctor_match.march`
deliberately prints a classification string rather than the error value.

## Why

`Llvm_ctor_desc.assign_ids` keys `ctor_desc_ids` by the name a type is
**lowered** under — qualified, `File.FileError`, because the `ptype` sits
inside `mod File`. `id_for` looks a call site up by its **static TIR type
name**, which for a builtin's return type is the canonical bare `FileError`
(the builtin tables are right to spell it bare: March has one global type
namespace and a module type's canonical identity is its bare name). The lookup
misses, `id_for` answers `None`, and the call site stays on the type-erased
`march_value_to_string`, which has only a tag.

## What was tried, and what it cost

Aliasing the bare suffix onto the qualified type's id inside `assign_ids`
**deterministically SIGSEGVs**:

| variant | `native_actor_monitor_down_reason` |
|---|---|
| `origin/main` | 0/30 crashed |
| bare-suffix alias in `assign_ids` | **40/40 crashed** (exit 139) |
| same tree, alias removed | 0/40 crashed |

Each measured with `.march/cas/artifacts-v2` cleared first — **a warm CAS
silently returns the previous binary and makes this bisect lie** (it did, twice,
during the original investigation). The alias also grew the binary from 118,712
to 135,736 bytes, so it changes far more than one lookup.

Two narrowings that did **not** help, so the mechanism is neither of these:

- **Restricting the alias to unambiguous suffixes** (no other declared type
  shares the bare name). Still 40/40. Note the corpus really does contain eight
  ambiguous suffixes — `Event`, `HEntry`, `Level`, `Seq`, `T`,
  `TransportError`, `Tree`, `Value` — so any future attempt must handle them,
  but they are not the crash.
- **Moving the fallback out of `assign_ids` into `id_for`**, so the descriptor
  *content* (`build_desc` / `field_token`) is untouched and only the id a call
  site passes changes. Still 40/40. That rules out "field tokens were
  re-resolved" as the mechanism, which was the leading theory.

So a bare name reaching `id_for` is, for some type in that program, **not**
the qualified type it suffix-matches, and handing it that descriptor makes the
runtime renderer read a cell with the wrong layout. `describable`'s own comment
records the same hazard for niche-shaped types ("the renderer reads the
PAYLOAD's header as the wrapper's tag").

## Where to start next

Find the actual mis-resolution before designing a fix: instrument `id_for` to
log `(static name, chosen id, descriptor's type name)` for every call site in
`test/native/actor_monitor_down_reason.march`, run it, and identify which
lookup picks a descriptor for a type the value is not. The fixture uses
qualified cross-module ADTs (`Down.Down`, `DownReason.Crash`) and calls
`to_string` on several of them, so the offender is likely in that family.

Alternatives, if suffix matching cannot be made sound:
1. Emit descriptors under **both** names at lowering time, so the table never
   needs a fallback and `build_desc` describes each name explicitly.
2. Carry the qualified name in the TIR type at the call site, so `id_for` gets
   the lowered spelling and no matching is needed.
3. The pad-word type id in
   `specs/todos/2026-08-05-boxed-adt-type-id.md`, which answers this at
   genuinely erased sites too, at the cost of a store per boxed allocation.

## Acceptance

`to_string` of a `File.FileError` prints `NotFound("…")` compiled as well as
interpreted, `test/test_stdlib_suite.ml`'s table is tightened to byte equality
with the interpreter (drop the `#<tag:%d>` alternative), and
`native_actor_monitor_down_reason` still exits 0 over 40 consecutive runs with
the CAS cleared.
