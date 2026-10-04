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
