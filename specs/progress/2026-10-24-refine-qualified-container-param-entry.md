`[P4]` Refinement: a parameter typed with a module-qualified container gets no element entry

Filed 2026-10-21 by the stdlib refinement sweep
(`specs/progress/2026-10-21-stdlib-refinement-sweep.md`).

A parameter whose type is a container declared in ANOTHER module, spelled
qualified, carries no container entry for its element refinement, so it is
not a known source for the parametric rule:

```march
mod PQual do
  cap verified
  mod Dk do
    type Dk(a) = Dk(List(a), List(a))
    fn to_list(d : Dk(a)) : List(a) do
      match d do
      Dk(f, _) -> f
      end
    end
  end
  type Lk(a) = Lk(List(a), List(a))
  fn lk_list(d : Lk(a)) : List(a) do
    match d do
    Lk(f, _) -> f
    end
  end
  fn sum_pos(_xs : List({Int | _ > 0})) : Int do 0 end
  fn a(q : Dk.Dk({Int | _ > 0})) : Int do sum_pos(Dk.to_list(q)) end   -- skip
  fn b(q : Lk({Int | _ > 0})) : Int do sum_pos(lk_list(q)) end         -- proved
end
```

`a` is `parametric-source-unproved` ("the elements of argument 1 of
`Dk.to_list` is not known to satisfy it"); `b` is proved. Measured on
`fa70709af` with the sweep's stdlib. The same holds for the stdlib containers:
`sum_pos(Deque.to_list(d))` with `d : Deque.Deque({Int | _ > 0})`, and
`sum_pos(Queue.to_list(q))` with `q : Queue.Queue({Int | _ > 0})`, are skips,
while a queue or deque built inside the function from a refined list proves
(`sum_pos(Queue.to_list(Queue.from_list(pos)))`). A lost proof, never a false
one.

Likely cause (not confirmed): `Refine_scope.cont_of_fnparams` builds the
entry through `elem_refinement`, which admits a `TyCon` only when
`is_container_type c` holds, looking `c` up via `adt_sort_name`; the
annotation's spelling is the qualified `Dk.Dk`, and the registry may know
only the bare `Dk`. Even if the lookup succeeded, the entry's container name
would then have to match the one a callee's declared `Dk(a)` produces.

Pinned as a skip in `test/test_refinecheck.ml` group `stdlib-refine-sweep`
("a Queue.Queue-typed parameter"); that row flips when this is fixed.

## Closed 2026-10-24

Fixed with the `Deque.to_list` element fact; see
`specs/progress/2026-10-24-refine-deque-to-list-element-fact.md`. The cause was the one
guessed above: `adt_sort_name` mapped the qualified `Dk.Dk` / `Queue.Queue` / `Deque.Deque`
to an unregistered key, so `is_container_type` was false. `Refine_encode.canonical_type_name`
now resolves a qualified spelling to its unique declaration, and the container's name is
stored in that spelling, so it matches the callee's declared `Dk(a)`. The pinned
`stdlib-refine-sweep` row ("a Queue.Queue-typed parameter") is now a proof. An ambiguous
bare name is still unknown (a skip, a ruling).
