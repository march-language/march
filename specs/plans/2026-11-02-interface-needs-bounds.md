# Interface `needs` bounds (per-function bounds, phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An interface method signature may carry a `needs` bound; every impl of that
method, and the interface's own default body, is checked against it.

**Architecture:** Phase 1 (PR #1052) records a bound per function in
`env.fn_bound_points` and checks it against the solved capability row at the end of
`check_module_core`. Phase 2 adds the bound to `Ast.method_decl`, and in
`check_module_needs` gives each impl method (and each interface default body) a bound
point taken from its interface. The end-of-module check is phase 1's, with the
message naming the interface. Nothing about types, constraints or call charging changes.

**Tech Stack:** OCaml 5.5.1, menhir, dune, alcotest; tree-sitter (grammar.js).

**Spec:** `specs/plans/2026-11-01-per-function-needs-bounds.md` (phase 2) and
`specs/plans/2026-09-28-road-to-1.0.md` decision 2 (2026-09-29). The design decisions
below were agreed in conversation on 2026-11-02 and are the spec for this phase.

**Branch:** starts from `main` after #1052 merges (it needs `fn_needs`,
`fn_bound_points`, `cap_bound`). Do not stack on `claude/fn-needs-bounds`.

## Design decisions (the spec for this phase)

1. **No capability threading.** The interface bound is a check on impls, made once per
   impl method where the impl is declared. It is NOT part of the method's type, NOT
   carried by `when Iface(a)` constraints, and adds nothing to generic functions or to
   callers. A call through an interface is still charged the union of the impls in the
   build (the existing dispatch node), not the bound.
2. **Syntax.** `fn get : (a, String) -> Option(String) needs IO.FileRead` in an
   interface body, after the type and before an optional `do <default> end`.
   `needs ()` is the empty bound. Plain capability paths only, as in phase 1.
3. **Impl methods.** An impl method with no bound of its own is checked against the
   interface's bound. An impl method with its own bound must declare one within the
   interface's (narrowing is allowed, widening is an error), and is then checked
   against its own, as in phase 1.
4. **Default bodies.** A default method body in the interface is checked against that
   method's bound.
5. **Module ceiling exemption.** An interface bound's paths must be real capabilities,
   but need NOT lie within the declaring module's `needs`: it limits other modules'
   impls. The impl's module still needs the capability itself (existing module-ceiling
   check, unchanged).
6. **Optional per method.** A method with no bound constrains nothing (today's
   behaviour).
7. **Built-in interfaces.** `Show`, `Eq`, `Ord`, `Hash` get `needs ()` only if the
   measurement in Task 4 is clean or the user accepts the breakage. That is a decision
   for the user, not the implementer.

## Global Constraints

- Menhir conflict count stays at 7 (CLAUDE.md; phase 1 kept it).
- A parser change ships with the tree-sitter grammar extended and `scripts/check-tree-sitter.sh` green.
- Language reference edits go in `specs/lang/`, then `scripts/gen-lang-docs.py`; never hand-edit `docs/`.
- `specs/todos/2026-11-01-fn-needs-bounds-interfaces.md` is `git mv`'d to `specs/progress/` in the commit that finishes the phase; CHANGELOG `[Unreleased]` gets an `### Added` bullet.
- Build and test from the worktree with `--root .` or `scripts/run-tests.sh`.
- No `ast_json` change: phase 1 left `fn_needs` out of `--emit-core-ast`; leave `md_needs` out too, so the types oracle stays quiet.

## Review Focus

1. **Interface declared in another module than the impl** (`impl Store.Backend(T)` or a
   `use`d interface): the impl must still be checked. A lookup that only searches the
   impl's own `decls` passes every same-module test and checks nothing across modules.
   Test in Task 2.
2. **A generic caller of a bounded method** (`fn sync(s : a) when Store(a)`): must get
   no new diagnostic and no new annotation. This is the no-threading guarantee. Test in Task 2.
3. **An impl method that narrows the bound and then reaches beyond its own (narrower)
   bound but within the interface's:** must be rejected against its own bound. Test in Task 3.
4. **A derive-generated impl** (`derive Show for T`) under a bounded interface: must
   pass, and must not report the error at a synthetic `<none>` span. Test in Task 4.
5. **An interface whose bound names a capability its own module does not declare:**
   must be accepted (decision 5), while a misspelt capability is still rejected. Test in Task 2.

---

### Task 1: Syntax: `md_needs` in the AST, parser, formatter and tree-sitter

**Files:**
- Modify: `lib/ast/ast.ml` (`method_decl`, ~line 448)
- Modify: `lib/parser/parser.mly` (`method_sig`, ~line 1473)
- Modify: `lib/typecheck/typecheck_builtins.ml` (`mk_builtin_iface`, ~line 484)
- Modify: `test/test_refinecheck.ml` (two `method_decl` literals, ~lines 12982, 13256)
- Modify: `lib/format/format.ml` (interface method lines, ~line 1036)
- Modify: `tree-sitter-march/grammar.js` (`method_sig`), regenerate `src/parser.c`, `src/grammar.json`, `src/node-types.json`; add a case to `tree-sitter-march/test/corpus/declarations.txt`
- Test: `test/test_cap_fn_bounds.ml`

**Interfaces:**
- Produces: `Ast.method_decl.md_needs : (name list list * span) option`, the same shape as `Ast.fn_def.fn_needs`.

- [ ] **Step 1: Write the failing tests** in `test/test_cap_fn_bounds.ml`:
  - `test_iface_bound_parses`: parse `interface Store(a) do\n  fn get : a -> Int needs IO.FileRead\n  fn put : a -> Unit needs ()\n  fn name : a -> String\nend` (in a module) and assert the three methods' `md_needs` are `Some ([["IO";"FileRead"]], _)`, `Some ([], _)` and `None`.
  - `test_iface_bound_with_default_parses`: `fn label : a -> String needs () do fn (_) -> "x" end` parses with `md_needs = Some ([], _)` and `md_default <> None`.
  - `test_iface_formatter_keeps_the_bound`: `March_format.Format` round-trip of the first source contains `fn get : a -> Int needs IO.FileRead` and `fn put : a -> Unit needs ()`, and formatting twice is idempotent.
  Register them in `tests`.
- [ ] **Step 2: Run** `scripts/run-tests.sh compiler` — expect a build error (unknown field `md_needs`).
- [ ] **Step 3: Implement.** Add the field. In `method_sig`, take `needs = option(fn_needs_clause)` after `t = ty` and before the default; set `md_needs = needs`. Set `md_needs = None` at every other literal (builtins, the two refinecheck tests). In the formatter, print the bound after the type with the same rendering as `emit_fn` (~line 1254): factor that rendering into a shared `fmt_needs : (name list list * span) option -> string` and use it in both places.
- [ ] **Step 4: Check the conflict count.** `dune build --root . lib/parser 2>&1 | grep -i conflict` reports the same 7 as before the change.
- [ ] **Step 5: Tree-sitter.** In `grammar.js`, `method_sig` gets `optional($.fn_needs)` after `field('type', $._type)`. Regenerate the parser as phase 1 did (private `HOME`, so no cached grammar). Add corpus case "Interface method with a needs bound" covering both a bounded signature and a bounded one with a default. Run `scripts/check-tree-sitter.sh`: green.
- [ ] **Step 6: Run** `scripts/run-tests.sh compiler`: all pass.
- [ ] **Step 7: Commit** `feat(parser): needs bound on interface method signatures`.

### Task 2: Check impls and default bodies against the interface bound

**Files:**
- Modify: `lib/typecheck/typecheck_env.ml`, `typecheck_env.mli`, `typecheck.mli` (`fn_bound_points` value type)
- Modify: `lib/typecheck/typecheck_caps.ml` (`record_fn_bound`, the `DInterface` and `DImpl` arms ~lines 757–800)
- Modify: `lib/typecheck/typecheck.ml` (`check_fn_bounds`, ~line 7932)
- Test: `test/test_cap_fn_bounds.ml`

**Interfaces:**
- Consumes: `md_needs` (Task 1).
- Produces, in `typecheck_env.ml` (re-exported like the existing field):
  ```ocaml
  type bound_origin =
    | Fn_decl                                  (* phase 1: written on the function *)
    | Iface_method of { iface : string; impl_ty : string option }
        (* None = the interface's default body *)
  type fn_bound = { fb_caps : string list; fb_span : Ast.span; fb_origin : bound_origin }
  fn_bound_points : (string, fn_bound) Hashtbl.t
  ```
  `fb_span` is always the span of the `needs` clause that set the bound (the interface's
  for an inherited bound). Task 3 relies on `Iface_method` to word its message.

- [ ] **Step 1: Write the failing tests**, each an accept/reject pair like phase 1's:
  - `test_impl_inherits_iface_bound`: interface method `fn show : a -> String needs ()`, impl with no own bound whose body calls `println` → `cap_bound`; the same impl without `println` → clean.
  - `test_iface_bound_message_names_the_interface`: the reject above has a message containing ``interface `Show` `` and ``impl Show(T)``.
  - `test_iface_bound_transitive_chain`: the impl reaches `IO.Console` through a `pfn log` helper → message contains `via log`.
  - `test_iface_default_body_checked`: a default body calling `println` under `needs ()` → `cap_bound`; a pure default → clean.
  - `test_iface_unbounded_method_unchecked`: no `needs` on the method, impl prints → clean (decision 6).
  - `test_iface_bound_outside_module_needs` (Review Focus 5): interface in a module with no `needs` declaring `needs IO.Console` → clean; `needs IO.Consol` → `unknown_capability`.
  - `test_iface_bound_cross_module` (Review Focus 1): `mod A do interface Sink(a) do fn emit : a -> Unit needs () end end` and `mod B do needs IO.Console ... impl A.Sink(T) do fn emit(_) do println("x") end end end` → `cap_bound`. Use whichever qualified/`use` spelling `specs/lang/interfaces.md` documents as working under `--check`.
  - `test_iface_bound_no_threading` (Review Focus 2): a bounded `Store` interface, a generic `fn sync(s : a) : Unit when Store(a) do put(s) end` with no `needs`, and a caller of `sync`; assert no diagnostics at all and that `sync`'s solved reach equals the union of the impls' (reach the row through the same API `test_no_effect_on_callers` uses).
  - `test_iface_bound_untraceable_invocation`: an impl body invoking a function value taken from a record field under a narrow interface bound → `cap_bound` with the "cannot trace" message (phase 1's rule applies unchanged).
- [ ] **Step 2: Run** `scripts/run-tests.sh compiler`: the new rejects fail (no diagnostic).
- [ ] **Step 3: Change the table's value type** to `fn_bound` and update phase 1's writer and `check_fn_bounds` to it, with `fb_origin = Fn_decl`. Phase 1's 13 cases pass unchanged.
- [ ] **Step 4: Record interface bounds.** In `check_module_needs`:
  - `DInterface` arm: validate each method's bound paths with `suggest_cap` (no module-ceiling check, decision 5); for a method with a default body and a bound, record a bound point under the existing `Iface$default.m` key with `Iface_method { iface; impl_ty = None }`.
  - `DImpl` arm, for each method with no `fn_needs` of its own: find the interface (`decls` first, then `env.interfaces`, which also holds built-ins and qualified names; confirm the cross-module test exercises the second path) and, if that method has a bound, record it under the mangled key with `Iface_method { iface; impl_ty = Some ty_key }`.
  - A method the interface does not declare, or an interface not found: record nothing (existing errors cover them).
- [ ] **Step 5: Word the message by origin** in `check_fn_bounds`. For `Iface_method { iface; impl_ty = Some ty }`, the leaf is ``"`<m>` in `impl <iface>(<ty>)`"`` and the bound is ``"interface `<iface>`'s `needs <b>`"``; for `impl_ty = None`, ``"the default `<m>` of interface `<iface>`"``. The help line for both is `help: remove the use; widening the interface's bound changes it for every impl and every caller.` `Fn_decl` messages are unchanged byte-for-byte (the golden errors corpus must not move).
- [ ] **Step 6: Run** `scripts/run-tests.sh compiler`, then the golden corpus: `dune build --root . test/run_errors.exe && ./_build/default/test/run_errors.exe -e`. All pass, with no golden diff.
- [ ] **Step 7: Commit** `feat(caps): check impls and default bodies against interface needs bounds`.

### Task 3: An impl's own bound must lie within the interface's

**Files:**
- Modify: `lib/errors/code.ml` (new code `cap_bound_iface`, in the definitions and the registry list next to `cap_bound_needs`)
- Modify: `lib/typecheck/typecheck_caps.ml` (`DImpl` arm)
- Test: `test/test_cap_fn_bounds.ml`

**Interfaces:**
- Consumes: Task 2's interface lookup and `bound_origin`.
- Produces: `Err.Code.cap_bound_iface`.

- [ ] **Step 1: Write the failing tests.**
  - `test_impl_bound_narrower_ok`: interface `needs IO.Console, IO.Clock`, impl `needs IO.Clock` using only the clock → clean.
  - `test_impl_bound_wider_rejected`: interface `needs ()`, impl `needs IO.Console` → `cap_bound_iface`, message contains ``wider than interface `Show`'s `needs ()` ``.
  - `test_impl_narrowed_bound_still_enforced` (Review Focus 3): interface `needs IO.Console, IO.Clock`, impl `needs IO.Clock` whose body prints → `cap_bound` (against its own bound).
  - `test_impl_bound_under_unbounded_method`: interface method has no bound, impl declares one → clean, and the impl is checked as in phase 1.
- [ ] **Step 2: Run**: the wider-bound reject fails.
- [ ] **Step 3: Implement.** In the `DImpl` arm, when the impl method has its own `fn_needs` and the interface method has a bound, report `cap_bound_iface` at the impl's `needs` span for every impl path not covered (`cap_subsumes`) by some interface path. Message: ``"`<m>` in `impl <iface>(<ty>)` declares `needs <own>`, which is wider than interface `<iface>`'s `needs <b>` for `<m>`.\nhelp: narrow the impl's bound to within the interface's."`` The impl's own bound point is still recorded by phase 1's `record_fn_bound` (own ⊆ interface makes it the tighter check). When it is wider, record the interface's bound in its place, so the body is checked against the bound that actually applies.
- [ ] **Step 4: Run** `scripts/run-tests.sh compiler`: all pass.
- [ ] **Step 5: Commit** `feat(caps): an impl's needs bound must lie within its interface's`.

### Task 4: Measure, then (if accepted) bound the built-in interfaces

**Files:**
- Modify: `lib/typecheck/typecheck_builtins.ml` (`mk_builtin_iface` gains an optional bound; `Show`/`Eq`/`Ord`/`Hash` entries)
- Create: `specs/progress/2026-11-02-interface-needs-bounds-measurement.md` (the numbers)
- Test: `test/test_cap_fn_bounds.ml`

- [ ] **Step 1: Measure first, behind a local patch.** Set `needs ()` on all four built-ins (a `Some ([], Ast.dummy_span)` bound), then run `march --check` over the stdlib, every `.march` under `test/` and `examples/` that has an `impl Show|Eq|Ord|Hash`, and the sibling apps (`../conduit`, `../test_conduit_app`) with `MARCH_LIB_PATH`. Count `cap_bound` diagnostics against built-in interfaces, and list each with file and capability.
- [ ] **Step 2: Stop and report to the user**: the count, the list, and whether any rejection is a legitimate use (for example `show` logging). The user decides: bound all four, bound some, or none. Do not continue past this step without that answer.
- [ ] **Step 3 (if accepted): Write the tests.**
  - `test_builtin_show_bound`: user type with a hand-written `impl Show(T)` whose `show` prints → `cap_bound`, message contains ``interface `Show` ``. A pure one → clean.
  - `test_derived_show_under_bound` (Review Focus 4): `derive Show, Eq, Ord, Hash for T` → clean, and if any diagnostic appears, its span is not `<none>`.
- [ ] **Step 4 (if accepted): Implement.** `mk_builtin_iface ?(needs = None)`, with `needs = Some ([], Ast.dummy_span)` for the accepted interfaces. A built-in has no real span, so the message must not point at `dummy_span`: when `fb_span` is `dummy_span`, report at the impl method's name span and say ``interface `Show` (built-in) is bounded by `needs ()` ``. Fix every rejection the measurement found, in the same commit.
- [ ] **Step 5: Run** `scripts/run-tests.sh` (full suite), then `scripts/oracle-base.sh types refine`. Expected: only the measured diagnostics move.
- [ ] **Step 6: Commit** `feat(caps): Show, Eq, Ord and Hash are bounded by needs ()` (or, if declined, commit only the measurement file).

### Task 5: Docs, specs and changelog

**Files:**
- Modify: `specs/lang/interfaces.md` (new section "Capability bounds on methods"), `specs/lang/capabilities.md` ("Per-function bounds" section: interface paragraph plus a "No capability threading" rule paragraph stating decision 1), `specs/lang/surface-syntax.md` (interface method form)
- Regenerate: `docs/*` via `scripts/gen-lang-docs.py`
- Modify: `specs/plans/2026-11-01-per-function-needs-bounds.md` (phase 2 marked done, link this plan), `specs/plans/2026-09-28-road-to-1.0.md` (status line)
- Modify: `specs/todos/2026-11-01-fn-needs-bounds-tooling-semver.md`: add that ANY change to an interface bound is a major bump (widening breaks callers, narrowing breaks implementors)
- Move: `git mv specs/todos/2026-11-01-fn-needs-bounds-interfaces.md specs/progress/2026-11-02-fn-needs-bounds-interfaces.md`, rewritten as the completion note
- Modify: `CHANGELOG.md` `[Unreleased]` → `### Added`

- [ ] **Step 1:** Write the reference sections. The interfaces.md section shows a `Store` example, the impl rules (inherit, narrow, never widen), default bodies, the module-ceiling exemption, and the built-in bounds if Task 4 adopted them.
- [ ] **Step 2:** `scripts/gen-lang-docs.py`, then `scripts/check-docs.sh`: green.
- [ ] **Step 3:** Specs, todo move and CHANGELOG bullet.
- [ ] **Step 4: Final verification:** `scripts/run-tests.sh` (full), `scripts/check-tree-sitter.sh`, `scripts/oracle-base.sh types refine` (expect only intended moves), and the per-function noise measurement re-run from phase 1, to confirm the stdlib count is unchanged.
- [ ] **Step 5: Commit** `docs(caps): interface needs bounds`.
