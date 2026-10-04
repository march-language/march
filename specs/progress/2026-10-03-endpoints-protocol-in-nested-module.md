# `[P2]` DONE An `@[endpoints]` protocol inside a nested, library or stdlib module now works

Filed 2026-09-28 (dd step 12a) as `specs/todos/2026-09-28-endpoints-protocol-in-nested-module.md`;
closed 2026-10-03. It blocked moving the control plane's `Ctl` and `CtlFetch` protocols
into `stdlib/control.march`, so they live in `test/session/control_peers.march` and are
spliced into each topology app's entry module.

## The bug

```march
mod Deep do
  mod Outer do
    @[endpoints]
    protocol Pq do
      hi: A -> B : Int
    end
    fn run(c : Cap(IO)) : () do
      ...
      let _ = Pq_B.script(s, Pq_B.register(s, 0), [...])
    end
  end
end
```

`Unknown module `Pq_B`` (and, from inside the generated code, `Unknown module `Pq_Msg``).
The same protocol at `Deep`'s top level worked. A protocol in a stdlib module checked when
the stdlib was typechecked on its own (where the module is a top level), and failed for
every program whose entry module is named like a stdlib module (`mod Test`), which takes
the combined from-scratch check where the stdlib module is nested.

## Causes and fixes

Three independent holes, each red on its own.

1. **A nested protocol generated nothing.** `Desugar.desugar_module` ran
   `Desugar_endpoints.expand` over the file's top-level declarations only. It now
   recurses (`expand_endpoints`): a protocol in a nested module expands inside that module,
   inserted after its leading directives exactly as at the top level. A library or stdlib
   file's protocol was already expanded (each file is desugared with its module as the top
   level); those failed on cause 2.

2. **A qualified TYPE written relative to an enclosing module did not resolve.** Pass 1
   (`prebind_mod_members`) seeds a submodule's public types under their path from the
   ENTRY module's top level (`Outer.Pq_A.Entry`), and a nested module's export step adds
   only the bare name. So `Pq_A.Entry` worked one level below the entry module, where the
   path is `Pq_A`, and nowhere deeper: not in `Deep.Outer`, not in a MARCH_LIB_PATH module,
   not in a stdlib module in the combined check. Functions and constructors were fine (the
   export step binds `Pq_A.f` and `Pq_A.Ctor` into the enclosing scope); types were not,
   and every generated module names its siblings' types (`Pq_Msg.Pq_Message`,
   `Pq_A.S_send_Hi`, `Pq_A.Entry`). The same failure without protocols:

   ```march
   mod Outer do
     mod A do type T = T1(Int) end
     mod B do fn g(t : A.T) : Int do 0 end end   -- Unknown module `A`
   end
   ```

   `Typecheck_unify.lexical_qualified_type`: a qualified type name that does not resolve
   as written is tried under each enclosing module's path, innermost first
   (`env.cap_qual_prefix`), the way a lexical reference resolves. "Resolves as written"
   counts types and aliases only: `env.records` can hold a qualified key naming no type (a
   nested module re-exports every bare record key whose name matches one of its public
   names, so a role module's `Entry` alias re-exported the stdlib's unrelated `Entry`
   record as `Pq_A.Entry`), which made the name look resolved.

3. **A stdlib protocol made a user's bare `from_json` ambiguous, compiled.** #677's
   write-up saw it for `derive Json` in an eagerly loaded module; a protocol always brings
   one (its `P_Msg` codec), plus its payload types'. A return-position method
   (`from_json`) whose result type the call site does not pin resolves to the program's
   only impl (`Mono.return_position_single_impl`); the stdlib's impls made that two or
   more. Lowering now records which impl symbols the stdlib declares
   (`Mono.stdlib_impl_syms`, by the impl's span or its enclosing module's name span: a
   derived `Json` impl carries a dummy span, a stdlib module's name carries its file), and
   the fallback does not count them when the program has exactly one impl of its own. The
   compiled ambiguity diagnostic (`Llvm_calls.fail_if_unresolved_iface_method`) applies the
   same rule, so `to_json(3)` with no codec of the user's own is still "no `JsonTo`
   implementation for type `Int`", not an ambiguity listing the protocol's codecs (a
   literal argument is now classified by its literal type for that message).

## Tests

`test/test_codegen.ml`, group `endpoints_protocol_placement`, nine cases. One protocol
body (a record payload deriving Json, real roles typed by `Pq_A.Entry`, a scripted peer
used from inside, a runner reference that typechecks and links but never runs) is declared
at each place, and driven from ANOTHER module by qualified name (real roles, a scripted
and a chaos peer of each role, `Pq_Msg.role_names()`, `Pq_Msg.fingerprint()`):

- nested: `Deep.Outer` (the todo's repro), driven from `Deep.Caller`;
- library: a MARCH_LIB_PATH module, driven from the app;
- stdlib: a copy of the stdlib whose `control.march` declares it, entry module `mod Test`;
- `from_json`: the stdlib copy plus a user `derive Json` decoded by an unpinned `from_json`;
- `to_json(3)` beside the stdlib protocol: still the no-codec diagnostic.

Each of the first four runs interpreted and compiled. Red/green: against the base
compiler all nine fail; with fixes 1 and 2 but not 3, only the two compiled Json cases
fail.

## The `Ctl` move, tried (not landed)

Moving `Ctl`, `CtlFetch`, the `Wire*` records and the role bodies from
`test/session/control_peers.march` into a COPY of the stdlib's `control.march`, and
qualifying the fixture's references (`Control.Ctl_Agent`, `Control.agent_role`, ...):
the fixture prints its golden, interpreted and compiled; `test/native`'s `mod Test`
fixtures and `from_json_dispatch` pass; `derive_json_dispatch_codegen` and
`interpreter_only_dsl` pass. One rename was needed: `result_of` already exists in
`Control`. Steps are in
[../todos/2026-09-28-dd-step12a-control-wiring.md](../todos/2026-09-28-dd-step12a-control-wiring.md).

## Not fixed here

- Two types with the same short name that both derive Json, in different modules, break
  both backends (pre-existing): so two protocols with one name in two modules, or a user
  protocol named like a stdlib one, do too.
  [../todos/2026-10-03-derive-json-same-short-name-two-modules.md](../todos/2026-10-03-derive-json-same-short-name-two-modules.md).
  `specs/lang/choreography.md` documents the restriction.
