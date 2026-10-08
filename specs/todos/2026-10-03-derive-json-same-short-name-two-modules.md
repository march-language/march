# `[P2]` Two types with the same short name that both `derive Json` break both backends

Filed 2026-10-03, found while fixing
[../progress/2026-10-03-endpoints-protocol-in-nested-module.md](../progress/2026-10-03-endpoints-protocol-in-nested-module.md).
Present on main before that change.

**Repro.**

```march
mod Coll do
  needs IO.Console
  mod A do
    type Note = NA(Int) | NB(String)
    derive Json for Note
    fn roundtrip(n : Note) : String do
      match Json.parse(Json.to_string(to_json(n))) do
        Ok(j) ->
          let r : Result(Note, Json.DecodeError) = from_json(j)
          match r do
            Ok(NA(k)) -> "A " ++ int_to_string(k)
            Ok(NB(s)) -> "A " ++ s
            Err(_) -> "A err"
          end
        Err(_) -> "A parse"
      end
    end
  end
  mod B do
    type Note = NC(Bool) | ND(Int, Int)
    derive Json for Note
    -- the same roundtrip over B's Note
  end
  fn main(c : Cap(IO.Console)) do
    print_line(A.roundtrip(A.NA(3)))
    print_line(B.roundtrip(B.ND(1, 2)))
  end
end
```

Interpreted: `A.roundtrip` runs B's `to_json` and panics (`no branch matched the value
NA(3)`). Compiled: `ambiguous interface-method call to JsonFrom$Note.from_json: 2
implementations are in scope (JsonFrom$B.Note.from_json, JsonFrom$A.Note.from_json)`.
Both backends find a derived codec by the type's SHORT name. The collision machinery
(`Collision_set`) qualifies the impl symbols, but the call inside the derived codec and
the user's call still name the short one.

**Why it matters now.** `@[endpoints]` protocols may now live in any module, so two
protocols with the same name in two modules (each generates `P_Message`), or a payload
type named like another module's, hit this. Moving `Ctl`/`CtlFetch` into
`stdlib/control.march` would reserve `Ctl_Message`, `CtlFetch_Message` and the `Wire*`
payload names in every program: a user protocol named `Ctl` stops compiling. Measured:
the same protocol `Pq` declared in a stdlib module and in the entry module works
interpreted and fails compiled exactly as above. `specs/lang/choreography.md` (Limits)
documents the restriction until this is fixed.

**Acceptance.** The repro prints `A 3` / `B 3` on both backends; a user protocol with a
stdlib protocol's name compiles.

## 2026-10-07: `to_json` fixed in the interpreter; `from_json` needs a design call

**Landed.** The interpreter's `to_json` builtin now looks the codec up by the
value's declaring-module-qualified type (`dispatch_type_name_of_value`, moved to
`Eval_runtime`) before the bare short name, and the `DImpl` arm registers a
colliding type's Json codec under that qualified key too. Compiled `to_json`
already worked (Mono's runtime tag switch). Pinned by
`test/stdlib/test_json_collision.march` (suite `stdlib_march`).

**Still open: `from_json`, both backends.** It dispatches on the RESULT type,
and the typechecker cannot tell `A.Note` from `B.Note`. `surface_ty`
(`lib/typecheck/typecheck_unify.ml`, the `canon_name` comment) canonicalizes
every nested-module type to the bare `TCon "Note"`, so the two types UNIFY with
each other and `Json_dispatch.record` can only ever say `"Note"`. TIR already
mangles the impls as `JsonFrom$A.Note.from_json` / `JsonFrom$B.Note.from_json`
(`collect_iface_impls`, `lib/tir/lower.ml`), so the call side is the only gap.

The cheap fix considered and NOT taken: resolve a colliding target by the call
site's lexical module (`env.cap_qual_prefix` at the `json_cap_sites` record,
choosing the innermost enclosing module that declares the short name). It makes
the repro pass, but it is unsound. Inside `A`, `let r = from_json(j)` followed by
`B.consume(r)` (where `consume` takes `B.Note`) typechecks, because the types
unify, and it would silently decode with A's codec. Today that program is a
compile error (compiled) or a wrong decode (interpreted). The heuristic would
turn the compile error into a silent wrong decode.

The sound fix is nominal identity for nested-module types in the typechecker
(e.g. `TCon "A.Note"`, or a declaring-module tag on `TCon`), so `A.Note` and
`B.Note` stop unifying. That is a typechecker-wide change: every
`canon_type_name` / `ci_type` / bare-name lookup site is involved. It needs its
own design pass before anyone implements it.
