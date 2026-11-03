#!/usr/bin/env python3
"""Generate the diagnose fixtures: each is {"before": <SNAPSHOT envelope>,
"after": <SNAPSHOT envelope>}, shaped exactly like the observe socket's
replies, starting from one healthy node and changing what each finding needs.
expected.txt lists the finding ids (and severities) every implementation must
produce: forge/lib/diagnose.ml and stdlib/diagnose.march are both tested
against it. Rerun after editing: python3 gen.py"""
import copy, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
T0 = 1_790_000_000_000          # before.at_ms
WINDOW = 1000                   # after.at_ms - before.at_ms

def actor(pid, mbox=0, held=0, limit=0, policy="unbounded", names=(), typ="W",
          parent=None, children=0, crashes=0, child_crashes=0):
    return {"pid": pid, "type": typ, "names": list(names), "status": "waiting",
            "mbox": mbox, "user_mbox": mbox, "held": held, "mbox_limit": limit,
            "mbox_policy": policy, "code_epoch": 1, "cap_epoch": 0, "sched": 0,
            "pinned": False, "draining": False, "parent": parent,
            "children": children, "spawned_by": None, "slices": 10,
            "msgs_in": 10, "msgs_out": 10, "crashes": crashes,
            "child_crashes": child_crashes, "idle_ms": 5}

def healthy():
    actors = [actor(1, names=["web"]), actor(2), actor(3, typ="Sup", children=2),
              actor(4, parent=3), actor(5, parent=3)]
    return {
        "actors": {"total": len(actors), "shown": len(actors), "sort": "mbox", "actors": actors},
        "mem": {"rss_bytes": 50_000_000, "peak_rss_bytes": 60_000_000,
                "live_objects": 100_000, "stacks_recycled": 0,
                "queued_messages": 0, "actors": len(actors)},
        "sched": {"schedulers": 2, "window_ms": None,
                  "threads": [{"id": 0, "idle_ms": 10_000}, {"id": 1, "idle_ms": 10_000}],
                  "runq": 0, "msgs_dropped": 0},
        "epochs": {"current": 3, "pins": [{"epoch": 3, "pins": 5, "current": True, "draining": False}],
                   "slots": [], "counters": {}},
        "crashes": {"total": 0, "crashes": []},
        "names": {"names": [{"name": "web", "pid": 1}]},
        "tree": {"total": len(actors), "roots": [], "unsupervised": [], "truncated": False},
    }

def env(data, at):
    return {"proto": "march.observe/1", "node": "fixture", "at_ms": at, "took_us": 10,
            "truncated": False, "data": data}

def busy_threads(d, idle_delta):
    """Advance each thread's idle_ms by idle_delta[i] over the window."""
    for t, dd in zip(d["sched"]["threads"], idle_delta):
        t["idle_ms"] += dd

def requeue(d):
    d["mem"]["queued_messages"] = sum(a["mbox"] + a["held"] for a in d["actors"]["actors"])

cases = {}

# healthy: nothing changes except schedulers idling ~90% of the window.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
cases["healthy"] = (b, a, [])

# mailbox.growth (warning): one actor's mailbox grows 0 -> 40 of a 140 total.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
a["actors"]["actors"][1]["mbox"] = 40; a["actors"]["actors"][0]["mbox"] = 100
b["actors"]["actors"][0]["mbox"] = 100; requeue(b); requeue(a)
cases["mailbox_growth_warning"] = (b, a, ["mailbox.growth/warning"])

# mailbox.growth (critical): one actor holds over half of 5000 queued (some held by an Actor.call).
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
b["actors"]["actors"][1]["mbox"] = 1000
a["actors"]["actors"][1]["mbox"] = 3500; a["actors"]["actors"][1]["held"] = 500
a["actors"]["actors"][0]["mbox"] = 1000; requeue(b); requeue(a)
cases["mailbox_growth_critical"] = (b, a, ["mailbox.growth/critical"])

# mailbox.over_limit: an actor at its drop_new limit while the node drops.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
for d in (b, a):
    d["actors"]["actors"][2]["mbox"] = 64; d["actors"]["actors"][2]["mbox_limit"] = 64
    d["actors"]["actors"][2]["mbox_policy"] = "drop_new"; requeue(d)
a["sched"]["msgs_dropped"] = 250
cases["mailbox_over_limit"] = (b, a, ["mailbox.over_limit/warning"])

# sched.saturated: both schedulers busy the whole window, work queued.
b = healthy(); a = healthy(); busy_threads(a, [10, 20]); a["sched"]["runq"] = 7
cases["sched_saturated"] = (b, a, ["sched.saturated/warning"])

# sched.idle_imbalance: one at 95%+ but nothing queued, the other idle.
b = healthy(); a = healthy(); busy_threads(a, [100, 950])
cases["sched_imbalance"] = (b, a, ["sched.idle_imbalance/warning"])

# crash.loop (critical): three crashes of one supervisor's children in the last minute.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
ring = [{"seq": i, "kind": "crash", "pid": 10 + i, "type": "W", "code_epoch": 3,
         "supervisor": 3, "restart": i, "at_ms": T0 + WINDOW - 5000 * (4 - i)} for i in (1, 2, 3)]
a["crashes"] = {"total": 3, "crashes": list(reversed(ring))}
a["actors"]["actors"][2]["child_crashes"] = 3
cases["crash_loop_critical"] = (b, a, ["crash.loop/critical"])

# crash.loop (warning): three crashes in the last hour, none in the last minute.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
ring = [{"seq": i, "kind": "crash", "pid": 10 + i, "type": "W", "code_epoch": 3,
         "supervisor": 3, "restart": 1, "at_ms": T0 - 600_000 * i} for i in (1, 2, 3)]
a["crashes"] = {"total": 3, "crashes": ring}
a["actors"]["actors"][2]["child_crashes"] = 3
cases["crash_loop_warning"] = (b, a, ["crash.loop/warning"])

# rc.climb: live objects +20% with the actor count flat.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
a["mem"]["live_objects"] = 120_000
cases["rc_climb"] = (b, a, ["rc.climb/warning"])

# rc.climb does NOT fire when actors grew with the heap.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
a["mem"]["live_objects"] = 150_000
extra = [actor(100 + i) for i in range(5)]
a["actors"]["actors"] += extra; a["actors"]["total"] += 5; a["mem"]["actors"] += 5
cases["rc_climb_with_actors"] = (b, a, [])

# A growing mailbox is also live queued work, not an RC leak.  The raw heap
# gauge crosses rc.climb's threshold, but its entire increase is queued
# messages, so only mailbox.growth must report it.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
b["mem"]["live_objects"] = 1_000
a["mem"]["live_objects"] = 1_120
a["actors"]["actors"][1]["mbox"] = 120; requeue(b); requeue(a)
cases["rc_climb_mailbox_growth"] = (b, a, ["mailbox.growth/critical"])

# Mailbox growth must not hide an independent increase above the RC threshold.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
b["mem"]["live_objects"] = 1_000
a["mem"]["live_objects"] = 1_250
a["actors"]["actors"][1]["mbox"] = 120; requeue(b); requeue(a)
cases["rc_climb_mailbox_and_heap_growth"] = (b, a, ["mailbox.growth/critical", "rc.climb/warning"])

# epoch.stuck + epoch.old_units: a draining epoch, and units two epochs back.
b = healthy(); a = healthy(); busy_threads(a, [900, 900])
for d in (b, a):
    d["epochs"]["pins"] = [{"epoch": 1, "pins": 2, "current": False, "draining": True},
                           {"epoch": 3, "pins": 5, "current": True, "draining": False}]
cases["epoch_stuck"] = (b, a, ["epoch.old_units/warning", "epoch.stuck/warning"])

os.makedirs(HERE, exist_ok=True)
lines = []
for name, (b, a, want) in cases.items():
    with open(os.path.join(HERE, name + ".json"), "w") as f:
        json.dump({"before": env(b, T0), "after": env(a, T0 + WINDOW)}, f, indent=1)
        f.write("\n")
    lines.append(f"{name}: {','.join(sorted(want))}")
with open(os.path.join(HERE, "expected.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
