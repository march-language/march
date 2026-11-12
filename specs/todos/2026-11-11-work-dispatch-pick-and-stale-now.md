`[P3]` `WorkDispatch`: the pick is deterministic, a negative index gives `None`, and fallbacks reuse a stale `now_ms` (2026-11-11)

All three are stated in the doc strings; they are API traps.
1. `pick_dispatch_target` is described as power-of-two-choices but always compares the first and last fresh entries, so a better node in the middle of the list is never chosen and every caller with the same list picks the same node.
2. `pick_two` reduces an index with `idx - (idx / n) * n`, which stays negative for a negative index, and then returns `None` instead of a member.
3. `dispatch` and `dispatch_affine` fall back after a remote call has failed with `DeadlineExceeded` but pass the original `now_ms` on: the second attempt's freshness filter and deadline (`now_ms + timeout_ms`) are computed from a time that is already at least `timeout_ms` in the past. (Item 3 is by source reading only.)

Repro (`work_dispatch_pick.march`):

```march
mod A do
needs IO.Console
fn nl(id, load) do
  { node_id: id, cpu_count: 4, cpu_load_milli: load, mem_total_mb: 100, mem_avail_mb: 50, sampled_at: 1000 }
end
fn name(o) do match o do Some(x) -> x.node_id | None -> "None" end end
fn main(_c : Cap(IO.Console)) do
  -- b is the least loaded (most spare) node but sits in the middle of the list.
  let ms = [nl("a", 3900), nl("b", 0), nl("c", 3800)]
  println("pick x5: " ++ name(WorkDispatch.pick_dispatch_target(ms, ClusterLoad.spare_cpu_milli, 1000))
     ++ name(WorkDispatch.pick_dispatch_target(ms, ClusterLoad.spare_cpu_milli, 1000))
     ++ name(WorkDispatch.pick_dispatch_target(ms, ClusterLoad.spare_cpu_milli, 1000))
     ++ name(WorkDispatch.pick_dispatch_target(ms, ClusterLoad.spare_cpu_milli, 1000))
     ++ name(WorkDispatch.pick_dispatch_target(ms, ClusterLoad.spare_cpu_milli, 1000)))
  println("pick_two(1,2): " ++ name(WorkDispatch.pick_two(ms, 1, 2, ClusterLoad.spare_cpu_milli, 1000)))
  println("pick_two(-1,1): " ++ name(WorkDispatch.pick_two(ms, 0 - 1, 1, ClusterLoad.spare_cpu_milli, 1000)))
  println("pick_two(-3,1): " ++ name(WorkDispatch.pick_two(ms, 0 - 3, 1, ClusterLoad.spare_cpu_milli, 1000)))
  println("pick_two(4,-2): " ++ name(WorkDispatch.pick_two(ms, 4, 0 - 2, ClusterLoad.spare_cpu_milli, 1000)))
end
end
```

Expected: a random pair; a negative index wraps; a fallback takes a fresh clock.

Actual (interpreted / compiled): `ccccc`, `pick_two(-1,1): None`, `pick_two(4,-2): None` / the same.

Source: `pick_dispatch_target`, `pick_two`, `dispatch`, `dispatch_affine`, stdlib/work_dispatch.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
