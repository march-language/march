# Name scopes: calls the compile-time check does not see (2026-11-13)

Logged by the ocap p2b Task 12 review, fix round 1. A name scope (`needs IO.Mut("sessions")`,
`needs IO.Registry("logger", prefix("worker."))`) is judged in
`lib/typecheck/typecheck_caps.ml` (`check_name_scopes`) at calls of the functions in
`name_arg_fns`, in the module that declares the scope. These routes still reach a name outside
it with no error. All of them close at run time once phase 4's checked `Authority.check`
judges the name itself; until then each one is a fail-open hole.

Closed in fix round 1, and pinned by `test/test_compiler.ml` `name_scope_*`: impl, interface
default, app, test, describe and setup bodies; `Vault.ns_set/ns_get/ns_drop` and
`Config.new_store`; an alias of `Actor` / `Vault` (local, or from an enclosing module); a nested
module widening its parent's scope. The `import Actor` route was already closed, because
`import Actor` demands `needs IO` (`import_cap_missing`).

## 1. A user-written wrapper in another module

```march
mod Main do
  needs IO
  mod Reg do
    needs IO.Registry            -- unscoped: passes any name through
    fn put(pid, name : String) : Bool do Actor.register(pid, name) end
  end
  mod Worker do
    needs IO.Registry("logger")
    fn go(pid) : Bool do Reg.put(pid, "other") end   -- accepted
  end
end
```

`Reg.put` is not in `name_arg_fns`, so the literal in `Worker` is never judged. The capability
itself is charged (`Worker` must declare `IO.Registry`), but the name is not. A sound static
fix needs a name parameter annotation (like `@[net_dest(p)]` for host scopes) or name-flow
analysis through the callee. Phase 4's run-time check closes it without either.

## 2. A wrapper that builds the name

The same applies to a stdlib or user function that computes the name before the open. No stdlib
function does this today: `grep` found only `Config.new_store`, which passes the name straight
through and is now in the table. Any new stdlib function that turns a caller's string into a
table or registry name must be added to `name_arg_fns`.

## 3. Calls the walker cannot name

A name-taking function passed in through a function-typed parameter (`fn f(reg) do reg(pid,
"other") end` called as `f(Actor.register)`) is refused only where `Actor.register` is named as
a value inside a scoped module. If the value is created in an unscoped module and handed to a
scoped one, the scoped module's call is not judged. Phase 4 closes this.

## Also open (Task 12 re-review)

- **Grandchild widening.** Nested modules are checked against the union of all
  ancestors' scopes, so `Outer prefix("w.")` > `Mid prefix("w.x.")` > `In prefix("w.")`
  is accepted: `In` widens back past `Mid`. A nested module's scope should be
  judged against its nearest enclosing declaration of the same capability.
- **Over-eager machine fix.** The `prefix(w)` → `prefix("w")` fix is also offered
  for other identifier-valued options such as `no_redirects(w)`, where quoting does
  not make the scope valid. Offer it only for `prefix(...)`.
