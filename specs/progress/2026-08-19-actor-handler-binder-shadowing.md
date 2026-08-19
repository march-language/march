# An actor handler binder did not shadow a same-named top-level function (compiled only)

`lower_actor.ml`'s `lower_handler` lowered a handler body with
`Lower_match.lower_expr env h.ah_body` without first registering the handler's
own params in `Lower_state._fn_param_types`.

That table is the shield `resolve_use_alias` (`lib/tir/lower_state.ml`) consults
FIRST, before rewriting a bare name into a qualified global. `lower_fn_def`
(`lib/tir/lower_decls.ml`) already establishes it for a normal function's
parameters, and lower.ml's `EBlock`/`ELet` case does the same for let-bound
names — its comment names this exact failure mode ("turning a local into a
global function reference"). Actor handlers were the one binder form with no
such scope.

Consequence: a handler param whose name matched ANY top-level function linked
into the program — no `import` of the declaring module required, since the
program-global `_use_aliases` fallback fires for unqualified names — was
silently discarded, and the bare reference resolved to the FUNCTION. Lowering
then emitted the function's raw code address where the bound value belonged.
Params that happened not to collide worked only by name coincidence with the
TIR param var of the same name.

Found in the wild 2026-08-19 in a compiled Bastion/Envoy HTTP server. The actor

    on Deliver(session_id, kind, text, approved) do
      Envoy.SessionRegistry.deliver_here(session_id, kind, text, approved)

collided with stdlib `HttpServer.text`, and the emitted IR read:

    call ptr @Envoy.SessionRegistry.deliver_here(ptr %ld, ptr %ld,
                                                 ptr @HttpServer.text, i64 %cv)

The decode DID extract field 2 into `%$Deliver_text.addr`; the body simply never
loaded it (locals were created for `session_id_i18572`, `kind_i18573`,
`approved_i18575` — id 18574 skipped).

Symptom: the callee dropped that param, `march_decrc_local` wrote the refcount
at ptr+0 into read-only `__TEXT`, and the process died with SIGBUS via
`march_scheduler.c`'s `fatal:` `_exit(128+signo)` — exit 138. `IS_HEAP_PTR`
cannot filter this: a code address is aligned, >= 4096 and positive, so it
passes all three guards. It presented misleadingly as "an actor spawned inside
this handler never runs and the process dies as its green thread starts" — the
fault is in the SENDING actor's handler, before the spawned actor is scheduled.
A String-typed use instead gives `march: out of memory` (garbage length).

The tree-walking interpreter binds handler params directly (`eval.ml`) and was
always correct, so this was a compiled-only miscompile.

Scope, established empirically against the same toolchain: ONLY actor-handler
binders. Plain `fn` params, `let` bindings, `match` binders and lambda params
named `text` all resolved correctly.

Fix: register `params` in `_fn_param_types` around the body lowering, with
additive save/restore of shadowed entries (not `lower_fn_def`'s clear-all, so no
entry the enclosing scope relies on is removed).

Regression test: `test_actor_handler_binder_shadows_toplevel_fn` in
`test/test_codegen.ml` (`actor_dispatch_codegen` suite). An actor whose handler
binds `text` while an imported `Helper.text` exists must not emit
`, ptr @Helper.text` as a call argument. Verified non-vacuous: the test fails on
the parent commit and passes with the fix. The TIR golden snapshots are
unchanged, confirming the fix is inert for non-colliding names.
