# `[P2]` Nested-module types need their own identity in the typechecker (so two same-short-name types can both `derive Json`)

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

## 2026-10-11: re-verified on main (`7700714fd`), still open, still blocked on the design call

The repro above (with B's `roundtrip` written out over `NC`/`ND`) gives:

- **interpreted:** `A err` / `B 3`. `to_json` is right on both sides (#880);
  `A.roundtrip`'s `from_json` decodes with B's codec and fails.
- **compiled:** rejected at compile time, `ambiguous interface-method call to
  JsonFrom$Note.from_json: 2 implementations are in scope
  (JsonFrom$B.Note.from_json, JsonFrom$A.Note.from_json)`.

Nothing since 2026-10-07 has changed the cause: `surface_ty` still
canonicalizes both nested types to `TCon "Note"`, so the result-type dispatch
cannot tell them apart. Not fixed in the group-b typecheck batch: per the note
above, the only sound fix is nominal identity for nested-module types, which
needs its own design pass (the lexical-module heuristic stays rejected as
unsound). The acceptance criterion is unchanged.

## 2026-10-11: owner decision: a compile error now, the full fix later

**Decision (owner, 2026-10-11).** Reject the program at compile time until
nested-module types have their own identity; the silent wrong decode is worse
than a loud error.

**Landed.** Two DIFFERENT types with the same short name that both `derive
Json` are now a compile error, `json_derive_name_collision`, on every path
(`--check`, interpreted, compiled). The message names both types by their
declaring-module path (`B.Note` / `A.Note`) and points at both `derive` sites
(the primary span at the second, a label at the first).
`Typecheck.check_json_derive_collisions` walks the module's `JsonFrom` impls
(`collect_json_derive_sites`, resolving each bare type name to the innermost
enclosing level that declares it, as the derive expansion does) at the start
of `check_module_core`; the sites ride on `env.json_derive_sites` so a check
seeded from the cached stdlib env still sees the stdlib's derives (the stdlib
derives Json for no type today). To point at the derive, a derived Json
`DImpl` now carries the derive site as its decl span, as every other derive
already did (`lib/desugar/desugar_derive.ml`); this re-salts the derived Json
code's synthetic spans, which is why `test/errors/overlapping_impl_1` moved.

Pinned by `specs/lang/types/reject/t318_derive_json_same_short_name.march`
and the golden twin `test/errors/json_derive_name_collision_1`. Only ONE of
the two deriving Json was already fine on both backends (`A 3` / `B 3`) and
stays accepted: `test/stdlib/test_json_collision.march` now pins that shape
(it used to pin the interpreter's `to_json` routing with both deriving, a
program that is now rejected). The `@[endpoints]` case in the description
(a user type named like a generated `P_Message`) reports the new error ahead
of the existing `overlapping_impl` ones.

**What stays open (the real fix).** Nominal identity for nested-module types
in the typechecker: `surface_ty` (`lib/typecheck/typecheck_unify.ml`,
`canon_name`) must stop canonicalizing `A.Note` and `B.Note` to one bare
`TCon "Note"`, so they stop unifying and `Json_dispatch.record` can name the
qualified type. Every `canon_type_name` / `ci_type` / bare-name lookup site is
involved; it needs its own design pass. When it lands, drop
`check_json_derive_collisions` (and its code) and turn t318 into an accept
program that round-trips `A 3` / `B 3` on both backends.

**Acceptance (narrowed).** With nominal identity in place, the original
repro (both `Note`s deriving Json) compiles and prints `A 3` / `B 3` on both
backends, and a user protocol with a stdlib protocol's name compiles.
