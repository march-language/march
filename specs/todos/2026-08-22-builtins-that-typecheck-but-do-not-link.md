# Two builtins still typecheck but do not link

Filed 2026-08-22, out of the audit in
`specs/progress/2026-08-21-unix-time-ms-has-no-codegen-backing.md`. That item
fixed three of six; these are the remaining ones, left out because each needs
its own decision rather than the same mechanical seven-site addition.

Originally filed as three. The third, `from_json_events`, was a **false
positive** and has been struck — see "Struck: `from_json_events`" below before
re-adding it.

## The two

| builtin | typecheck.ml | interpreted | compiled |
|---|---|---|---|
| `worker` | `2811`, `∀a. a -> ChildSpec` | implemented (domain-checks its arg) | `Undefined symbols: _worker` |
| `dynamic_supervisor` | `2815`, `Atom -> Atom -> ChildSpec` | implemented | `Undefined symbols: _dynamic_supervisor` |

`worker` / `dynamic_supervisor` build `ChildSpec` values for the supervision
DSL. Giving them codegen backing means deciding what a `ChildSpec` is at the
C-runtime boundary, which is a design question, not a table entry.

## Struck: `from_json_events` was a false positive (2026-09-08)

The original table listed `from_json_events` (`2474`, `∀a b. a -> b`) as
`unbound variable` interpreted, and concluded it "has no implementation on
EITHER backend ... Either implement it or delete the entry."

**Do not delete it.** That conclusion is an artifact of how it was probed. The
audit's step 3 probes each name with "a one-line `.march` program" — i.e. a
*bare* call with nothing else in the module. `from_json_events` is not an
ordinary builtin: like `to_json` and `from_json`, it is a placeholder that
`derive Json for T` **binds per record type** (generated in
`lib/desugar/desugar_derive.ml`, Task 7 / Phase B). Bare, with no `derive Json`
in scope, it is unbound — and so are bare `to_json` and bare `from_json`, which
nobody would call dead. The three are literally adjacent entries in the same
table with the same `poly2 (fun a b -> TArrow (a, b))` type and the same
comment explaining why (`lib/typecheck/typecheck_builtins.ml`), and none of the
three has an `llvm_builtins.ml` entry. The audit's step-2 criterion therefore
flags all three equally; it just happened to probe only this one.

It works. Probed with a `derive Json` in scope, interpreted:

```march
mod FjeEpic do
  needs IO
  type P = { a: Int, b: String }
  derive Json for P
  -- events_of = JsonStream.feed(JsonStream.start(), s) then JsonStream.finish
  let probe = match events_of("{\"a\": 7, \"b\": \"hi\"}") do
    Err(_e) -> "PARSEERR"
    Ok(evs) -> match from_json_events(evs) do
      Ok((r, _rest)) -> "OK:" ++ Json.to_string(to_json(r))
      Err(_e) -> "DECODEERR"
      end
    end
  fn main(cap : Cap(IO)) do print(probe) end
end
```

prints `OK:{"a":7,"b":"hi"}`.

Deleting the entry was tried and reverted. It breaks two things:

1. **`derive Json` for record types stops compiling.** With the table entry
   removed and the compiler rebuilt, the program above fails with
   ``I cannot find `from_json_events` ``. This is the exact failure
   `specs/progress/2026-07-31-typed-json-decoding-task-7-from-json-events.md`
   warns about: the entry exists so that `is_json_derive`'s
   "don't re-bind the polymorphic scheme" skip does not leave the name unbound
   after the first derive is processed.
2. **It reopens a capability-forging hole.** The `demote_to_monomorphic` arm at
   `lib/typecheck/typecheck.ml:1453` that "references it by name" is not dead
   weight — it is capability unforgeability check R3, and
   `specs/lang/types/reject/t147_cap_from_json_events.march` exists precisely to
   fail if that name is dropped from the check. That fixture currently rejects
   with ``Cap(IO)` cannot be deserialized — a capability may only be received,
   never constructed.`` Its own header says it best: it is "coverage of a
   distinct binding", not a variation on t143.

There is also live test coverage: `test/stdlib/test_json_typed.march` calls
`from_json_events` as one half of a differential oracle against the tree
decoder over a 7-document corpus.

The residual grain of truth is narrow and cosmetic: a bare `from_json_events`
call with no `derive Json` in scope reports `unbound variable` rather than
something that explains the name needs a `derive Json for T`. That is a
diagnostic-wording nit shared identically by `to_json` and `from_json`, and it
is not what this file is tracking.

**Lesson for the audit itself:** step 2's three resolution routes miss a
fourth — *names bound by desugaring/derive expansion*. Any CI check built from
the "Reproducing the audit" recipe below must exclude derive-bound placeholders
or it will report the same false positive again.

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

## A now-removable workaround, while you are here

`stdlib/string.march`'s `String.from_codepoint` / `String.to_codepoints` are a
hand-written pure-March UTF-8 codec, and their comments say why: the builtins
they would otherwise call did not link when compiled. They do now. The two
implementations agree on every case including truncated multi-byte input (the C
decoder deliberately reproduces the interpreter's lead-byte fallback), and
`test/test_codegen.ml` has parity tests for both spellings, so delegating is a
small, well-covered change — just not this one. Whoever picks up the audit above
is in the right neighbourhood for it.

## Related

- `specs/progress/2026-08-21-unix-time-ms-has-no-codegen-backing.md` — the
  three that were fixed (`unix_time_ms`, `string_to_codepoints`,
  `string_from_codepoint`) and the seven sites each one needed.

> **Design spec (2026-09-11):** `specs/2026-09-11-correctness-fixes-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
