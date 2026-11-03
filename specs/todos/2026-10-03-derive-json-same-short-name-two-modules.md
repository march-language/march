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

## 2026-10-13: design proposal (nominal identity for colliding nested types)

Design only: this section lands no behaviour change. Measured on
`origin/main` `3d2925fce`.

### Evidence today

- **The repro** (both `Note`s deriving Json, B's `roundtrip` written out) is
  rejected on every path with `json_derive_name_collision` (#946,
  `de4ffce25`). With that check bypassed locally it still gives `A err` /
  `B 3` interpreted and the `ambiguous interface-method call to
  JsonFrom$Note.from_json` error compiled, as recorded on 2026-10-11.
- **The cause is wider than Json: it is a type-confusion hole.** No derive
  is needed. This program passes `--check`, then panics on both backends
  (`no branch matched the value NA(3)` interpreted, `non-exhaustive pattern
  match` compiled), because `A.Note` and `B.Note` are one `TCon "Note"`:

  ```march
  mod Mix do
    needs IO.Console
    mod A do
      type Note = NA(Int) | NB(String)
      fn make() : Note do NA(3) end
    end
    mod B do
      type Note = NC(Bool) | ND(Int, Int)
      fn describe(n : Note) : String do
        match n do
          NC(b) -> if b do "NC true" else "NC false" end
          ND(x, y) -> "ND " ++ int_to_string(x + y)
        end
      end
    end
    fn main(c : Cap(IO.Console)) do
      print_line(B.describe(A.make()))
    end
  end
  ```

  The fix must make this a type error ("expected `B.Note` but got
  `A.Note`"). That is the soundness half. The Json half follows from it.

### What the three related PRs do (none touches type identity)

- **#946** (`de4ffce25`): the interim error. `collect_json_derive_sites` +
  `check_json_derive_collisions` (`lib/typecheck/typecheck.ml` ~9082-9151),
  run at the start of `check_module_core`. Each derive's bare type name is
  resolved to the innermost enclosing declaring path, as the derive
  expansion does.
- **#941** (`47349c520`, "module-declared scalar aggregates get the unboxed
  layout"): TIR-only. `Kind.canonical_name` (`lib/tir/kind.ml:194`) used to
  resolve every type to its short name. It now maps a short name to its
  qualified `k_unboxed` declaration through `k_unboxed_short`
  (`unboxed_short_index`), leaving out short names that two unboxed keys
  share (the collision set forces those Boxed). It qualifies the LAYOUT
  lookup, not the identity: the static `Tir.ty` stays the bare `TCon`.
- **#947** (`8c8ed667d`, `nonregular_type`): `check_nonregular_types`
  (`lib/typecheck/typecheck.ml:8961`) keys types by short name per module
  scope (`check_scope` builds a fresh table per `DMod`). It is already
  correct for two same-short-name types in different modules and this
  proposal does not affect it.

### Where types are keyed by short name today

Typecheck (the root of both bugs):

1. `surface_ty`'s `canon_name` (`lib/typecheck/typecheck_unify.ml:824`) via
   `canon_type_name` (`lib/typecheck/typecheck_env.ml:1111`): a qualified
   `A.Note` collapses to bare `Note` whenever `Note` is a type of the same
   arity in scope. Every annotation yields `TCon "Note"`.
2. Constructor result types: `instantiate_ctor`
   (`typecheck_unify.ml:1000`) builds `TCon (ci.ci_type, ...)`, and every
   registration site sets `ci_type = name.txt` (bare): `check_decl`'s DType
   arm (`typecheck.ml` ~6026), `prebind_mod_members` (~9247, ~9275; the
   in-tree comment there records the reverted qualified-`ci_type`
   experiment), the entry's pass 1 (~9371), and the three copies in
   `check_module_with_env` (~9644, ~9672, ~9753). `ci_module` is the SHORT
   module name at `check_decl` and the full path at prebind, so it cannot
   serve as the declaring scope.
3. Constructor ARGUMENT types are resolved at the USE site
   (`instantiate_ctor` runs `surface_ty env` on `ci_arg_tys` in the caller's
   scope). A qualified identity therefore needs the declaring scope carried
   on the ctor, not only on the result type.
4. Pass-1 signature prebinding: `prebind_fn_scheme` (`typecheck.ml:7421`)
   builds `TCon (name.txt, ...)` with no env. `register_impl_shape`'s
   `lenient_ty` (`typecheck.ml:4913`, `TCon (n.txt, args')` at ~4946) does
   the same for impl heads.
5. Exhaustiveness: `ctors_for_type` (`typecheck_exhaustive.ml:153`) filters
   by `ci_type` string equality plus `ci_module` shadow heuristics.
   `inst_ty` (`typecheck_exhaustive.ml:202`) rebuilds nested ctor-arg types
   with bare `TCon`.
6. `from_json` dispatch: `json_dispatch_head` / `json_dispatch_target`
   (`lib/typecheck/typecheck_caps.ml:1753`, `:1798`) record the `TCon`'s
   name (so `"Note"`), or for a record the SHORT name of the field-set match
   (`record_type_name`, `:1763`).
7. `env.types` holds both the bare and the qualified key (`check_decl` adds
   `name.txt`; prebind adds `prefix.name` and, first-wins, the bare name).

Interpreter: `impl_tbl` is keyed `(iface, bare type)`
(`lib/eval/eval.ml:3746`). A colliding type's Json codec also claims the
qualified slot `(iface, current_doc_prefix () ^ type)` (`:3655`, `:3751`),
and `from_json` reads `impl_tbl (iface, Json_dispatch.find sp)`
(`eval.ml` ~1915). So the interpreter should accept a qualified dispatch
name as it is. Stage 1 must confirm the slot's spelling (module-stack path)
equals the typecheck identity.

Derive / TIR: the derive expansion emits `impl JsonFrom(Note)` in the
declaring module. TIR already names nested types `prefix ^ name`
(`Collision_set`, `lib/tir/collision_set.ml`) and mangles a colliding
type's impls module-qualified (`lib/tir/lower.ml:556`, giving
`JsonFrom$A.Note.from_json`). The compiled `from_json` rewrite
(`lib/tir/lower_expr.ml` ~670-680) spells `iface ^ "$" ^ tname`, so a
qualified `tname` lands on the symbol that already exists. Everything else in
TIR keeps the "TCon stays bare" invariant (`lib/tir/lower_state.ml`
~242-330, `shared_ctor_collision_tbl`, `own_module_ctor_key`; #941's
`k_unboxed_short`). `convert_ty` (`lib/tir/lower_types.ml:76`) passes
typechecker `TCon` names through verbatim, and `resolve_iface_method`
(`lower_state.ml` ~1032) reads a bare name out of the `type_map`.

### Proposed minimal change (one stage, collision-conditional)

The plan archived as `specs/plans/archive/2026-07-17-fqn-type-ctor-identity.md`
tried this as "cut (b)" and reverted it: registry-loaded stdlib signatures
stayed bare while the program's types went qualified. This proposal avoids
that split in two ways. Identity is scoped to the CHECKED PROGRAM's own
declarations, and every backend keeps its bare static type:

1. **Collision table.** At the start of `check_module_core`, walk the AST
   (accumulating the `cap_qual_prefix`-style path, entry level `""`). Collect
   every `DType`/`DAlwaysLinearType` with a `TDVariant` whose short name is
   declared at two or more paths. Skip declarations whose span is a stdlib
   file (`stdlib_source_files`) or a dummy span. Each entry maps
   `(path, short)` to `(identity, arity)`, where the identity is
   `path ^ "." ^ short` (bare at the entry level). A short name declared
   once is absent from the table, so a program without such a collision
   typechecks byte-identically. Records and aliases are left out, because
   records unify structurally as `TRecord`.
2. **Resolution.** `nominal_resolve_in ~scope name` resolves lexically,
   innermost scope first. Bare `Note` means the nearest enclosing path that
   declares it. `A.Note` means `A` as seen from the nearest enclosing scope
   that has it; the entry's own name is also accepted as a prefix. A bare
   name that no enclosing scope declares stays bare and unifies with
   neither type, so an ambiguous reference becomes a mismatch instead of a
   silent pick. Wire it ahead of `canon_name` in `surface_ty`, make
   `canon_type_name` leave an identity alone, and use it in
   `prebind_fn_scheme` (pass the prebind prefix) and `register_impl_shape`
   (pass the declaring path).
3. **Constructors.** Register `ci_type = identity` at the seven DType sites
   above; only a colliding type's ctors change. Add `ci_scope : string` to
   `ctor_info`: the declaring `cap_qual_prefix`, or `""` at builtins and the
   export bridge. That is 23 literal construction sites, all mechanical. Add
   an `env.nominal_scope : string option` that `instantiate_ctor` sets to
   `Some ci.ci_scope` and that only the resolver reads. A ctor's argument
   types then mean what its declaration meant, from any use site. This is
   needed for a NON-colliding `W(Note)` declared next to a colliding
   `Note`, and for actor message ctors. `inst_ty` in exhaustiveness gets the
   same scope. Audit the remaining `ci_type` comparisons against a bare decl
   name. The DMod export filter (`typecheck.ml` ~6464-6501: `opaque_types`,
   `pub_set`, the `_Msg` suffix test) must compare the short name.
   `matches_adt` (~5299) and `ctors_name_a_variant` already accept a
   `.name` suffix. Once `ci_type` is qualified, `ctors_for_type` on
   `TCon "A.Note"` matches exactly A's ctors, so the `ci_module` heuristics
   no longer matter for this case.
4. **Backends stay bare.** Add a global `identity -> short` map
   (`nominal_bare_name`) and apply it in `convert_ty` and in
   `resolve_iface_method`'s `type_map` read. TIR, mono, mangling, the CAS
   and the HCR impl hashes (`lib/cas/hash.ml` hashes TIR) then see exactly
   today's program. The ONLY qualified name that crosses into the backends
   is the `from_json` target in `Json_dispatch`, which both backends
   already resolve (see above).
5. **Retire the interim error for variants.** Keep
   `check_json_derive_collisions` only for a pair where either side is
   missing from the collision table. That covers records, whose
   `record_type_name` still collapses to the short name (fixed in stage 2).
   Flip t318 to an accept program that prints `A 3` / `B 3`. Its golden
   twin `test/errors/json_derive_name_collision_1` then becomes a record
   case or is removed.

A partial prototype was written and built cleanly on 2026-10-13: the
collision table, the resolver, the `ci_scope` field and the env plumbing,
before any of it was wired into `surface_ty`. It was then discarded,
because this pass is design-only. None of it is in the tree.

### Risks

- **Error messages / goldens.** A colliding nested type now renders as
  `A.Note`, which is clearer and is the point of the change. Only programs
  with such a collision change; `test/errors` and the types-oracle corpus
  show which. A program that used to be accepted while MIXING the two types
  (the `Mix` program above) becomes a type error. That is intended, but it
  is a user-visible break, so it needs a CHANGELOG `### Changed` entry.
- **Cut (b)'s failure mode** (registry-loaded or cached-env signatures stay
  bare): avoided by excluding stdlib declarations. The same exclusion is why
  this stage does NOT fix "a user protocol named like a stdlib protocol". A
  `MARCH_LIB_PATH` library loaded through the module registry, rather than
  as AST `DMod`s, would hit the same split if one of its types collides with
  one of the entry's. Before landing, check how `MARCH_LIB_PATH` modules
  reach `check_module_core`.
- **Process-global tables** (like `Json_dispatch`): reset per
  `check_module_core`. The REPL (`check_module_with_env`) and the LSP's
  long-running process re-check. The identity->short map must be additive,
  because TIR reads it after the check, and `is_nominal_identity` must read
  the current check's set only.
- **Stdlib tcenv cache**: adding `ci_scope` changes the Marshal layout. The
  cache key includes the compiler build id, so the cache invalidates itself.
- **CAS keys / HCR hashes**: unchanged for every program by construction
  (step 4). Prove it with `scripts/ir-oracle.sh` (expect 0 changed) and
  `scripts/determinism-oracle.sh`.
- **LSP**: hover and completion show `ci_type` (`lsp/lib/analysis.ml`
  ~2732, ~3303), which becomes `A.Note` for a colliding type. Acceptable;
  check with the LSP suite.
- **Refinecheck** strips names to the short name (`refine_check.ml` ~323),
  so it is unaffected. Confirm with `scripts/refine-oracle.sh`.

### Staged plan

1. **Stage 1 (typecheck identity, backends bare).** Steps 1-5 above. Tests:
   - the repro as a `test/native` fixture printing `A 3` / `B 3` on both
     backends, plus a `test/stdlib` case;
   - the `Mix` program as a `specs/lang/types/reject` witness
     (`expected B.Note but got A.Note`);
   - accept witnesses for a non-colliding ctor that wraps a colliding type
     and is used cross-module, an actor message carrying one, `derive Eq`
     and `Show` on both types, exhaustiveness over each, and an entry-level
     `Note` beside a nested `Note`.

   Gate: types-oracle (only colliding programs change), ir-oracle with 0
   changed, full suite.
2. **Stage 2 (records).** When the field set picks a single declaration,
   give `json_dispatch_head`'s record path that declaration's
   declaring-path identity. Then drop `check_json_derive_collisions`
   entirely.
3. **Stage 3 (stdlib / registry types).** Thread the same identity through
   the cached stdlib env and `load_module_into_env`. A user type named like
   a stdlib type then gets its own identity, and so does a user
   `@[endpoints]` protocol named like a stdlib one. This stage needs the
   archived plan's "the Stage 1 shim must be total" care.
