`[P3]` `DistLink.find_by_target_pid` ignores the node; the module header names functions that do not exist (2026-11-11)

1. `find_by_target_pid(tbl, pid)` returns the first monitor whose local pid number matches, on any node. Local pid numbers are per node, so with monitors on two nodes that both host a pid 7 it can return the wrong one. The doc string says the node is not compared. No stdlib code calls it today (only test/stdlib/test_dist_link.march), so it is an API trap, not a live wrong answer.
2. The header comment describes `monitor(target_pid, timeout_ms)` and `demonitor(ref)`; the module exports neither (it has `insert_monitor`, `remove_monitor`, the frame codecs and `resend_pending`).

Repro (`dist_link_find_by_target_pid.march`):

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let w = GlobalPid.make("me", 1, 0)
  let t = DistLink.insert_monitor(DistLink.empty_table(), DistLink.make_monitor(DistLink.MonitorRef(1), "nodeA", 7, w))
  let t = DistLink.insert_monitor(t, DistLink.make_monitor(DistLink.MonitorRef(2), "nodeB", 7, w))
  -- a MONITOR_FIRE for pid 7 arriving from nodeB can only be looked up by pid
  match DistLink.find_by_target_pid(t, 7) do
    Some(m) -> println("found monitor on " ++ m.target_node ++ " (both nodeA and nodeB host a pid 7)")
    None -> println("None")
  end
end
end
```

Expected: a lookup that takes the node id, or both matches.

Actual (interpreted / compiled): `found monitor on nodeA` / the same.

Source: `find_by_target_pid` and the header comment, stdlib/dist_link.march.

Related: specs/todos/2026-10-14-stdlib-doc-coverage-backlog.md lists `DistLink.monitor` as a nonexistent name referenced from dist_supervisor.march; it does not mention this header.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
