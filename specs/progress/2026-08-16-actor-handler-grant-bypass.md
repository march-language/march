# Actor message handlers escaped the whole-program capability grant (fixed)

**Severity:** high — a runtime-exploitable hole in the flagship guarantee.

## The bug

`Typecheck.check_main_grant` enforces that a program's entire transitive
capability closure sits under `main`'s capability parameter — "every helper,
every stdlib call, every dependency `main` reaches touches nothing beyond" the
grant. It computes `caps(main) ∪ ⋃ { caps(g) | g ∈ refs(main) }` over the
static reference graph (`env.fn_refs`).

Actor message handlers are lowered to synthesized functions keyed by the bare
`<Actor>_<Msg>` name (e.g. `Exfil_Go`), and their own capability closures
*were* recorded (2026-08-06, the C1 fix). But nothing linked them into the
reachability graph: `main` writes `spawn(Exfil)` / `send(p, Go(...))`, whose
free variables are `spawn`, `send`, `Exfil`, `Go` — never `Exfil_Go`. The
actor name in `ESpawn` is a nullary `ECon` whose tag `free_vars_expr`
discards. So a handler's capabilities never entered `main`'s closure.

Runtime-verified exploit: a module declaring `needs IO.Console` + `needs
IO.FileWrite`, with `fn main(cap : Cap(IO.Console))` that spawns an actor whose
handler calls `file_write`, compiled (`--check` and `--compile` both exit 0),
ran, and wrote the file. The grant was silently narrower than reality.

Asymmetry that made it subtle: the MANIFEST side (Check 1b body-scan and the
`--cap-strict` ceiling) already folded handler bodies in, so `needs
IO.FileWrite` was correctly required. Only the GRANT — the whole-program
ceiling under `main`'s parameter — was blind.

## The fix

Two order-independent reference edges, both keyed by the actor's bare name to
match the handler lowering:

1. `March_ast.Calls.spawned_actor_names` (new) collects every `spawn(Actor)`
   actor name in an expression. `record_fn_refs` emits these as extra
   references of every function, so a `spawn(A)` site references bare `A`.
2. The `DActor` recording arm registers `env.fn_refs[A] = [A_<msg>, ...]`,
   bridging the actor-name node to its handlers.

Together: `main → A → A_<msg> → caps`. Charged on SPAWN (reachability), so a
defined-but-never-spawned actor stays free — the same dead-code-is-free rule
the rest of the grant follows. Verified: exfil now rejected with chain
`main → Exfil → Exfil_Go`; a Console-only handler under a Console grant still
passes; a never-spawned file-writing actor still passes.

## Tests

`test/test_compiler.ml`: `test_actor_handler_escapes_grant_is_caught`,
`test_actor_spawned_not_sent_still_charged`,
`test_actor_defined_never_spawned_is_free`. One existing accept test in
`test/test_cap_ceiling.ml` had a parameterless `main` spawning a printing
actor — previously compiled only because of this bug; updated to carry the
`Cap(IO.Console)` grant it always should have needed.

## Related, filed same pass

Partial-grant diagnostic wording: `check_main_grant`'s "widen the grant (e.g.
`Cap(IO)`)" help steered users to the widest grant. It now suggests the precise
least-privilege parameter (`add a Cap(IO.Spawn) parameter to main`) first,
reusing the no-grant path's `_cap_<leaf>` spelling.

## Follow-up review found and fixed: `init` was a second bypass

An adversarial review of the first fix found the actor `init { ... }` block
was a SEPARATE surviving bypass: `init` runs at spawn time but was not bridged
(only `on` handlers were), so a helper-reached `file_write` from `init`
escaped the grant. Fixed by folding `init`'s builtin caps, free-var refs, and
spawn edges into the actor-name node too. Pinned by
`test_actor_init_io_is_charged_to_grant`.

## Known sound limitation (filed, not fixed here)

Same-named actors in two modules within one compilation unit share the bare
`<Actor>_<Msg>` cap-closure key (pre-existing C1 keying), so their handler
caps merge and spawning either now pulls in both. This is a FALSE POSITIVE
(rejects valid code) but SOUND (over-approximation — never masks a leak).
Filed as `specs/todos/2026-08-16-actor-grant-same-name-false-positive.md`; the
real fix is to key handler closures by TIR's disambiguated handler symbol
rather than the bare name, which touches the TIR naming / HCR manifest
contract and is out of scope for this security fix.

## Pre-existing failures at base 2fc077d0 (NOT this change)

Establishing a pre-fix control showed `accept/t177_vault_typed_handle.march`
(`@types-check`, a vault element-type inference bug) and 8/148 native codegen
fixtures (`actor_registry_*`, `bytes_u8_bridge`, `native_arr_fold*` — missing
`Actor.register` export etc.) already failing on the clean base. Unrelated to
capabilities; flagged for separate triage.
