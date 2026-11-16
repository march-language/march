`[P3]` `Membership.merge` is not commutative for exact ties (2026-11-11)

`supersedes` uses `>=` on a full tie of (creation, incarnation, severity), so the later observation replaces the stored one. Two views that hold the same node at the same creation, incarnation and status but a different name or addr merge to different results depending on the order. The `merge` doc string states the exception ("up to the name/addr of exact ties"); a total order (for example comparing addr, then name) would make the join a real CRDT join.

Repro (`membership_merge_tie.march`):

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let x = Membership.member("n1", "name-x", "10.0.0.1:1", 1, Membership.Alive, 3)
  let y = Membership.member("n1", "name-y", "10.0.0.2:2", 1, Membership.Alive, 3)
  let a = Membership.observe(Membership.empty(), x)
  let b = Membership.observe(Membership.empty(), y)
  println("merge(a,b): " ++ to_string(Membership.get(Membership.merge(a, b), "n1")))
  println("merge(b,a): " ++ to_string(Membership.get(Membership.merge(b, a), "n1")))
end
end
```

Expected: `merge(a, b) == merge(b, a)`.

Actual (interpreted / compiled): `name-y` one way, `name-x` the other / the same.

Source: `supersedes`, `observe`, `merge`, stdlib/membership.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
