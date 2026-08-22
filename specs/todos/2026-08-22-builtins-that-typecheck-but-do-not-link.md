# Three builtins still typecheck but do not link

Filed 2026-08-22, out of the audit in
`specs/progress/2026-08-21-unix-time-ms-has-no-codegen-backing.md`. That item
fixed three of six; these are the remaining three, left out because each needs
its own decision rather than the same mechanical seven-site addition.

## The three

| builtin | typecheck.ml | interpreted | compiled |
|---|---|---|---|
| `worker` | `2811`, `∀a. a -> ChildSpec` | implemented (domain-checks its arg) | `Undefined symbols: _worker` |
| `dynamic_supervisor` | `2815`, `Atom -> Atom -> ChildSpec` | implemented | `Undefined symbols: _dynamic_supervisor` |
| `from_json_events` | `2474`, `∀a b. a -> b` | **`unbound variable`** | `Undefined symbols: _from_json_events` |

`worker` / `dynamic_supervisor` build `ChildSpec` values for the supervision
DSL. Giving them codegen backing means deciding what a `ChildSpec` is at the
C-runtime boundary, which is a design question, not a table entry.

`from_json_events` is different in kind: it has no implementation on EITHER
backend, only a typecheck-table entry and a `demote_to_monomorphic` arm in
`infer_expr` that references it by name. Either implement it or delete the
entry — right now it is a name the compiler will happily accept and then fail
on, whichever backend you pick.

## Reproducing the audit

Nothing cross-checks `typecheck.ml`'s builtin table against `llvm_builtins.ml`,
so this list will drift again. The sweep that produced it:

1. Extract every `("name", Mono ...)` / `("name", polyN ...)` from
   `lib/typecheck/typecheck.ml` (531 names as of this writing).
2. Drop any that is resolvable by one of the THREE routes the backend has:
   an `llvm_builtins.ml` table entry; a string literal anywhere under
   `lib/tir/` or `lib/jit/` (special-cased in emit); or a bare-named definition
   in `runtime/*.c` — the undocumented third route, which is how `uuid_v7` and
   the whole `logger_*` family link.
3. Probe whatever is left with a one-line `.march` program, interpreted AND
   `--compile`, since the two failure modes differ.

Worth turning into a CI check rather than a periodic sweep: step 2 is
mechanical, and the failure it prevents lands at LINK time with a C symbol name
and no March span.

## Related

- `specs/progress/2026-08-21-unix-time-ms-has-no-codegen-backing.md` — the
  three that were fixed (`unix_time_ms`, `string_to_codepoints`,
  `string_from_codepoint`) and the seven sites each one needed.
