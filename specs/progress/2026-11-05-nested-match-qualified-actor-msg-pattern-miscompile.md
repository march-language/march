`[P2]` Compiled: a match on a qualified actor message nested in a `Some` arm panics

Found while building the M10 message guard
(`specs/progress/2026-11-05-hcr-live-data-migration-check.md`). Compiled (not interpreted),
this panics with `non-exhaustive pattern match` on its first call:

```march
fn w(m : V1.Msg, none : Counter.Msg) : Counter.Msg do
  match counter_migrate_msg(m) do
    Some(x) ->
      match x do
        Counter.Bump(p0) -> if not_137(p0) do x else none end
        _ -> x
      end
    None -> none
  end
end
```

With the bare pattern `Bump(p0)` it works, and so does the qualified pattern in a function of
its own (`fn g(x : Counter.Msg) : Bool do match x do Counter.Bump(p0) -> ... _ -> true end
end`). The `--dump-tir` of the failing shape shows the outer `case` with a default arm that
panics; the `Some` arm is the one taken. Start with the match compiler's handling of a
qualified constructor in a nested scrutinee (lib/tir/lower_match.ml).

Desugar_migrate_check works around it with a separate guard function; remove the workaround
once this is fixed.

## Fixed 2026-11-11

Not the match compiler, and not specific to actors or to nesting. The cause is Perceus'
scrutinee-escape rewrite (`lib/tir/perceus_scrut.ml`): where an arm returns the scrutinee in tail
position (`Counter.Bump(p0) -> if ... do x else none end`), the rewrite replaces that `x` with a
rebuild of the matched constructor, naming it `<scrutinee type>.<branch tag>`. A pattern written
qualified keeps a qualifier in its tag, so the name came out as `Counter_Msg.Counter.Bump`, which is
no constructor. `Llvm_data.ctor_entry` found nothing and fell back to tag 0, so the arm returned the
type's first constructor with the fields stored under the wrong layout. The panic the todo saw was
the caller's match on that value.

The same happened for every qualified pattern form whose arm returns the scrutinee, silently:

```march
mod Shapes do type Shape = Circle(Int) | Square(Int) | Dot end
fn keep(s : Shapes.Shape, d : Shapes.Shape) : Shapes.Shape do
  match s do
    Shapes.Square(n) -> if n > 3 do s else d end    -- returned Circle(11) for Square(5)
    _ -> s
  end
end
```

The bare pattern worked because its tag has no qualifier, and the function-of-its-own version in
the todo worked because it returned a `Bool`, not the scrutinee.

Fix: `Perceus_scrut.scrut_alloc_key`. A tag of three or more segments whose type segment is the
scrutinee's type is already the exact `Mod.Type.Ctor` key and is kept; any other qualifier (a type,
a module, an actor's name) is dropped and the scrutinee's own type names the constructor, as it
does for a bare tag.

`Desugar_migrate_check` no longer generates a separate `<actor>_migrate_msg__guard` function: the
`<actor>_migrate_msg__hcr` wrapper's `Some(x)` arm is now the match this todo described
(`guard_arms`). `test/hcr_migration_check/check_fns.march` covers it compiled.

Tests: three interpreter-vs-compiled parity tests in `test/test_codegen.ml`
(`cross_module_ctor_resolution` group): module-, type- and stdlib-module-qualified patterns; the
actor-message shape above; and two modules declaring a same-named type with a shared constructor.
All three failed before the fix.
