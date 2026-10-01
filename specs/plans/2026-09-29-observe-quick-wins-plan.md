# Observe quick wins: four prototypes that test the plan before building it

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In about five working days, answer four questions that decide the shape of
[`2026-09-28-observe-recon-shell-plan.md`](2026-09-28-observe-recon-shell-plan.md)
(the "big plan") before any of its items R0–R6 is built.

| # | Question | Prototype | Decides |
|---|---|---|---|
| QW1 | Is the data an Observer would show actually useful to an operator? | A pure-March report over what the runtime already exposes | Which panels and fields R1/R3 build first |
| QW2 | Do per-actor counters and idle timing survive the 1% benchmark gate? | The R2 counters as a runtime patch, measured A/B | Whether R2 ships as designed |
| QW3 | Is a remote shell's compile→deploy→run round trip fast enough, and does it print usefully? | A "shell" built only on today's hot deploy | Whether R5's fragment emission and on-demand `derive Show` are mandatory |
| QW4 | Can a foreign pthread walk the actor table safely and quickly? | A minimal observe socket thread | Whether R0/R1's architecture stands |

**Architecture:** All prototype code lives on a **throwaway branch**
`proto/observe-quick-wins` in a new directory `prototypes/observe/`, plus two
runtime patches (QW2, QW4). Nothing on that branch merges. The only artifact that
merges is one results file, `specs/progress/2026-09-29-observe-quick-wins-results.md`,
committed on the spec branch `claude/observer-recon-deploy-spec-ab90e2` together with
edits to the big plan that the results force.

**Tech Stack:** March (compiled backend), the C runtime (`runtime/`), the existing
hot-reload plane (`test/hcr_deploy.exe`), bash, python3 (timing and A/B only), `nc -U`,
Docker image `march-amdr-repro` (Linux ASAN).

## Global Constraints

- Work only inside the worktree `/Users/80197052/code/march/.claude/worktrees/clever-rhodes-ed1346`.
- Every task starts from this environment block (paste it into each shell):
  ```bash
  export WT=/Users/80197052/code/march/.claude/worktrees/clever-rhodes-ed1346
  export MARCH=$WT/_build/default/bin/main.exe
  export MARCH_STDLIB=$WT/stdlib
  export MARCH_RUNTIME_DIR=$WT/runtime
  export OBS=/tmp/obs-clever-rhodes
  mkdir -p "$OBS"
  ```
  `MARCH_RUNTIME_DIR` points at the **source** runtime, so a runtime edit is in the
  next compile with no restaging (a targeted `dune build bin/main.exe` never
  refreshes `_build/default/runtime`). `OBS` is short because a Unix socket path is
  cut at 104 bytes on macOS.
- Build the tools once per task that needs them: `dune build --root . bin/main.exe test/hcr_deploy.exe`. Always `--root .` in a worktree.
- **Never pipe `$MARCH --compile`.** Redirect to a file: `> log 2>&1`.
- **Signals do not work from the agent sandbox** (`kill` exits 0 and delivers
  nothing). Every prototype is triggered by a **file** and **exits on its own
  deadline**. Never rely on killing a process; if one must die, give the user the
  command.
- Benchmarks are same-box, interleaved A/B, compiled with `--opt 2`, load average
  < 10 (`python3 -c 'import os;print(os.getloadavg())'`). Never compare absolute ms
  across sessions.
- No `git stash`. Stage files by name only. No `Co-Authored-By` trailers.
- Log to the decision graph as you go (`deciduous add action …` before a task,
  `deciduous add outcome …` after, `deciduous link` both). Parent goal node: 2381.
- March syntax traps: `if c do … else … end` (else mandatory, one `end` per `if`);
  list patterns are `Nil` / `Cons(h, t)`; `fn (a, b) -> …` is a **two-argument**
  lambda, so destructure a tuple with `fn pair -> match pair do (a, b) -> … end`;
  lambda bodies are `fn -> …` (zero-arg) with no `do … end`.
- **Pre-registered thresholds** (in each task's "Verdict" step) are written down
  before measuring. Do not move them after seeing the numbers; if a threshold looks
  wrong afterwards, say so in the results file next to the unmoved verdict.

---

## File structure

| Path (throwaway branch) | Responsibility |
|---|---|
| `prototypes/observe/README.md` | One paragraph: "throwaway, see the plan"; how to run each prototype |
| `prototypes/observe/recon_lite/recon_lite.march` | `mod ReconLite`: `report(intro) : String` from existing APIs |
| `prototypes/observe/recon_lite/slow_consumer.march` | Demo app with a planted slow consumer; polls a trigger file; prints the report |
| `prototypes/observe/ab.py` | Interleaved A/B runner with loadavg gating and the gate verdict |
| `runtime/march_scheduler.h`, `runtime/march_scheduler.c`, `runtime/march_runtime.c` | QW2 counters + idle timing (+ a dump for non-vacuity) and QW4 spike thread |
| `prototypes/observe/shell/app.march` | Node with `mod Hook`'s `run(io)` whose `-- EXPR` line is rewritten per input |
| `prototypes/observe/shell/rpc.sh` | One "shell input": rewrite, `--compile-so`, deploy, trigger, wait, time |
| `prototypes/observe/spike/many_actors.march` | 20 000 idle actors plus spawn/kill churn, for QW4 |
| `prototypes/observe/spike/poll.sh` | Polls `ACTORS` N times and records `took_us` |

| Path (spec branch, merges) | Responsibility |
|---|---|
| `specs/progress/2026-09-29-observe-quick-wins-results.md` | Numbers, verdicts, and what changes in the big plan |
| `specs/plans/2026-09-28-observe-recon-shell-plan.md` | Edited only where a verdict forces it (Task 5) |

---

### Task 0: Throwaway branch and tools

**Files:**
- Create: `prototypes/observe/README.md`

**Interfaces:**
- Produces: branch `proto/observe-quick-wins`; built `$MARCH` and `$WT/_build/default/test/hcr_deploy.exe`.

- [ ] **Step 1: Create the branch from the spec branch's tip**

```bash
cd $WT && git switch -c proto/observe-quick-wins
```
Expected: `Switched to a new branch 'proto/observe-quick-wins'`. The spec files are
untracked on the spec branch; commit them there first if they are still untracked
(`git switch claude/observer-recon-deploy-spec-ab90e2 && git add specs/2026-09-24-observe-recon-shell-design.md specs/plans/2026-09-28-observe-recon-shell-plan.md specs/plans/2026-09-29-observe-quick-wins-plan.md specs/todos/2026-09-24-observe-recon-shell.md && git commit -m "specs: observe/recon/shell design, plan, quick-wins plan"`), then branch.

- [ ] **Step 2: Build the tools and prove they are fresh**

```bash
cd $WT && dune build --root . bin/main.exe test/hcr_deploy.exe > $OBS/build.log 2>&1; echo "exit $?"
ls -la $MARCH $WT/_build/default/test/hcr_deploy.exe
$MARCH --help > $OBS/help.txt 2>&1; grep -c -- "--compile-so" $OBS/help.txt
```
Expected: `exit 0`; both files have today's mtime; the grep prints a number ≥ 1.

- [ ] **Step 3: Write the README**

```markdown
# prototypes/observe — THROWAWAY

Four prototypes from specs/plans/2026-09-29-observe-quick-wins-plan.md.
Nothing here merges; results go to
specs/progress/2026-09-29-observe-quick-wins-results.md on the spec branch.
Every program here exits on its own deadline and is driven by trigger files,
because signals cannot be sent from the agent sandbox.
```

- [ ] **Step 4: Commit**

```bash
git add prototypes/observe/README.md && git commit -m "proto(observe): throwaway branch for the quick wins"
```

---

### Task 1: QW1, a pure-March "recon-lite" report

**Files:**
- Create: `prototypes/observe/recon_lite/recon_lite.march`
- Create: `prototypes/observe/recon_lite/slow_consumer.march`

**Interfaces:**
- Consumes: `Actor.introspect(io : Cap(IO)) : Cap(Actor.Introspect)`,
  `Actor.list(c)`, `Actor.top_by_mailbox(c, n) : List((Pid, Int))`,
  `Actor.registered(c) : List(String)`, `Actor.whereis(c, name) : Option(Pid)`,
  `Actor.register(pid, name)`, `pid_to_int`, `mailbox_size`,
  `Scheduler.live_procs/total_spawned/runq_depth/dropped_messages : () -> Int`,
  `System.mem_peak_bytes() : Int`, `System.monotonic_time() : Int` (ms),
  `File.exists(path) : Bool`, `File.delete(path) : Result((), FileError)`,
  `sleep_ms : Int -> ()`, `String.join(List(String), String) : String`.
- Produces: `ReconLite.report(intro : Cap(Actor.Introspect)) : String`.

- [ ] **Step 1: Write the report module**

`prototypes/observe/recon_lite/recon_lite.march`:
```march
-- ReconLite: throwaway quick win 1. A node report built ONLY from what the
-- runtime already exposes, to learn whether this data is worth an Observer.
-- See specs/plans/2026-09-29-observe-quick-wins-plan.md.
mod ReconLite do
  needs IO
  needs IO.Process
  needs IO.Clock

  -- The first registered name whose pid is `p`, or "-". There is no reverse
  -- lookup (pid -> names) in the stdlib; this linear scan is itself a finding.
  pfn name_of(intro : Cap(Actor.Introspect), names : List(String), p) : String do
    match names do
      Nil -> "-"
      Cons(n, rest) ->
        match Actor.whereis(intro, n) do
          Some(q) ->
            if pid_to_int(q) == pid_to_int(p) do n else name_of(intro, rest, p) end
          None -> name_of(intro, rest, p)
        end
    end
  end

  pfn row(intro : Cap(Actor.Introspect), names : List(String), pair) : String do
    match pair do
      (p, depth) ->
        String.join(["  pid=", int_to_string(pid_to_int(p)),
                     " mbox=", int_to_string(depth),
                     " name=", name_of(intro, names, p)], "")
    end
  end

  fn report(intro : Cap(Actor.Introspect)) : String do
    let names = Actor.registered(intro)
    let top = Actor.top_by_mailbox(intro, 5)
    let rows = List.map(top, fn pair -> row(intro, names, pair))
    let line1 = String.join(["== recon-lite @", int_to_string(System.monotonic_time()), "ms =="], "")
    let line2 = String.join(["live_procs=", int_to_string(Scheduler.live_procs()),
                             " total_spawned=", int_to_string(Scheduler.total_spawned()),
                             " runq=", int_to_string(Scheduler.runq_depth()),
                             " dropped=", int_to_string(Scheduler.dropped_messages()),
                             " peak_rss=", int_to_string(System.mem_peak_bytes())], "")
    let line3 = String.join(["actors=", int_to_string(List.length(Actor.list(intro))),
                             " registered=", String.join(names, ",")], "")
    String.join(List.concat([[line1, line2, line3, "top mailboxes:"], rows]), "\n")
  end
end
```
`List.concat : List(List(a)) -> List(a)` is `stdlib/list.march:462`.

- [ ] **Step 2: Write the demo app with a planted slow consumer**

`prototypes/observe/recon_lite/slow_consumer.march`:
```march
-- Quick win 1 demo: one slow consumer, one fast one, one producer. Touch
-- $OBS/qw1.trigger to get a ReconLite report on stdout. Exits after 30 s.
mod SlowConsumer do
  needs IO
  needs IO.Console
  needs IO.Spawn
  needs IO.Clock
  needs IO.Process
  needs IO.FileRead
  needs IO.FileWrite

  actor Slow do
    state { n : Int }
    init  { n: 0 }
    on SlowJob(k : Int) do
      sleep_ms(2)
      { n: state.n + k }
    end
  end

  actor Fast do
    state { n : Int }
    init  { n: 0 }
    on FastJob(k : Int) do
      { n: state.n + k }
    end
  end

  fn produce(slow, fast, k : Int) : () do
    if k == 0 do ()
    else
      send(slow, SlowJob(1))
      send(fast, FastJob(1))
      produce(slow, fast, k - 1)
    end
  end

  fn watch(intro : Cap(Actor.Introspect), trigger : String, deadline : Int) : () do
    if System.monotonic_time() > deadline do ()
    else
      if File.exists(trigger) do
        let _ = File.delete(trigger)
        println(ReconLite.report(intro))
        watch(intro, trigger, deadline)
      else
        sleep_ms(100)
        watch(intro, trigger, deadline)
      end
    end
  end

  fn main(io : Cap(IO)) do
    let intro = Actor.introspect(io)
    let slow = spawn(Slow)
    let fast = spawn(Fast)
    let _ = Actor.register(slow, "slow_consumer")
    let _ = Actor.register(fast, "fast_consumer")
    let _ = Task.async(fn -> produce(slow, fast, 20000))
    println("qw1: ready")
    watch(intro, "/tmp/obs-clever-rhodes/qw1.trigger", System.monotonic_time() + 30000)
    println("qw1: done")
  end
end
```

- [ ] **Step 3: Compile; fix only what the compiler names**

```bash
cd $WT/prototypes/observe/recon_lite && \
  MARCH_LIB_PATH=$WT/prototypes/observe/recon_lite \
  $MARCH --compile --opt 2 -o $OBS/qw1 slow_consumer.march > $OBS/qw1_build.log 2>&1; echo "exit $?"; cat $OBS/qw1_build.log
```
Expected: `exit 0`. If the compiler rejects a `needs` line or a capability, apply
exactly the change its message names (for example add the `needs` it asks for) and
recompile. Record every such fix in the results file: friction is data.

- [ ] **Step 4: Run it and take three reports while the producer runs**

Run the program in the background (it exits after 30 s):
```bash
$OBS/qw1 > $OBS/qw1.log 2>&1 &
```
Then, in a separate call:
```bash
until grep -q "qw1: ready" $OBS/qw1.log; do sleep 0.1; done
for i in 1 2 3; do touch $OBS/qw1.trigger; sleep 1.5; done
cat $OBS/qw1.log
```
Expected: three `== recon-lite @…ms ==` blocks. In each, the first `top mailboxes`
row should have `name=slow_consumer` and a large `mbox`; `fast_consumer` near 0.

- [ ] **Step 5: Verdict (thresholds fixed now)**

- **PASS** if at least 2 of the 3 reports name `slow_consumer` on the first row.
- Regardless of pass/fail, write the operator's view into the results file: for
  each of these, *could you answer it from the report?* (yes/no + why):
  1. Which actor is the bottleneck?
  2. Is its mailbox growing or shrinking? (needs two reports)
  3. What *type* of actor is it? (the report has no type; expected "no")
  4. Is the node CPU-bound? (expected "no": there is no utilisation)
  5. Has anything crashed? (expected "no": there is no crash data)
  Each "no" names a big-plan field (type → R1 row `type`, growth → R2 windowed
  `TOP`, CPU → R2 idle time, crashes → R2 crash ring). A "yes" to 3–5 would mean
  the big plan over-builds.

- [ ] **Step 6: Commit**

```bash
cd $WT && git add prototypes/observe/recon_lite/recon_lite.march prototypes/observe/recon_lite/slow_consumer.march && \
  git commit -m "proto(observe): QW1 recon-lite report over existing APIs"
```

---

### Task 2: QW2, counter and idle-time cost

**Files:**
- Create: `prototypes/observe/ab.py`
- Modify: `runtime/march_scheduler.h` (end of `march_proc`, before the `#ifdef MARCH_DEBUG` at ~`:469`; `march_scheduler` stat fields at ~`:504-507`)
- Modify: `runtime/march_scheduler.c` (`march_sched_init` ~`:1453`; idle path ~`:1964-1973`; dispatch ~`:2026-2029`; DEAD reap ~`:2075`; `march_sched_recv_actor_ex` ~`:3106-3113`)
- Modify: `runtime/march_runtime.c` (`march_send` ~`:7076-7077`)

**Interfaces:**
- Produces: `march_proc.obs_slices`, `.obs_msgs_in`, `.obs_msgs_out` (`_Atomic uint64_t`);
  `march_scheduler.obs_idle_ns` (`_Atomic uint64_t`); macro `MARCH_OBS_BUMP(field)`;
  `void march_obs_spike_dump(void)` (atexit, prints only with `MARCH_OBS_SPIKE_DUMP=1`).
  Task 4 reads `obs_slices`.

- [ ] **Step 1: Snapshot the base runtime before touching it**

```bash
rm -rf $OBS/runtime_base && cp -R $WT/runtime $OBS/runtime_base && git -C $WT status --short runtime/
```
Expected: the copy exists and `git status` shows no runtime changes (the base is clean).

- [ ] **Step 2: Write the A/B runner**

`prototypes/observe/ab.py`:
```python
#!/usr/bin/env python3
"""Interleaved same-box A/B (quick win 2). Usage:
   ab.py BASE_BIN PATCHED_BIN [--runs 40] [--scheds 1,8] [--max-load 10]
Gate (pre-registered): at 1 scheduler FAIL if |delta| > 1%; at >1 scheduler FAIL if
|delta| > the base arm's own (p75-p25)/2 as a % of its median."""
import argparse, os, statistics, subprocess, sys, time

def run(binary, scheds):
    env = dict(os.environ, MARCH_NUM_SCHEDULERS=str(scheds))
    t = time.perf_counter()
    subprocess.run([binary], env=env, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return time.perf_counter() - t

def quantile(xs, p):
    s = sorted(xs)
    return s[min(len(s) - 1, int(p * (len(s) - 1) + 0.5))]

def wait_quiet(limit, seen):
    while True:
        load = os.getloadavg()[0]
        seen.append(load)
        if load < limit:
            return
        time.sleep(5)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base"); ap.add_argument("patched")
    ap.add_argument("--runs", type=int, default=40)
    ap.add_argument("--scheds", default="1,8")
    ap.add_argument("--max-load", type=float, default=10.0)
    a = ap.parse_args()
    failed = False
    for scheds in [int(x) for x in a.scheds.split(",")]:
        loads, base, pat = [], [], []
        run(a.base, scheds); run(a.patched, scheds)          # warm-up, discarded
        for i in range(a.runs):
            wait_quiet(a.max_load, loads)
            order = [(a.base, base), (a.patched, pat)]
            if i % 2: order.reverse()                         # first-position bias
            for binary, out in order:
                out.append(run(binary, scheds))
        mb, mp = statistics.median(base), statistics.median(pat)
        delta = (mp - mb) / mb * 100
        half = (quantile(base, .75) - quantile(base, .25)) / 2 / mb * 100
        limit = 1.0 if scheds == 1 else half
        verdict = "FAIL" if abs(delta) > limit else "PASS"
        failed |= verdict == "FAIL"
        print(f"scheds={scheds} n={a.runs} base_med={mb*1000:.1f}ms patched_med={mp*1000:.1f}ms "
              f"delta={delta:+.2f}% base_halfIQR={half:.2f}% limit={limit:.2f}% "
              f"max_load={max(loads):.1f} {verdict}")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
```

- [ ] **Step 3: A/A control first (proves the box can resolve 1%)**

```bash
cd $WT && MARCH_RUNTIME_DIR=$OBS/runtime_base $MARCH --compile --opt 2 bench/actors/fanin_flood.march -o $OBS/ff_base > $OBS/ff_base.log 2>&1; echo "exit $?"
cp $OBS/ff_base $OBS/ff_base2
python3 prototypes/observe/ab.py $OBS/ff_base $OBS/ff_base2 --runs 40
```
Expected: two `PASS` lines. **If an A/A line FAILs, the box is too noisy to decide
QW2: stop, record the A/A numbers and the load average in the results file, and
retry later.** A green A/B is meaningless on a box that fails A/A.

- [ ] **Step 4: Add the fields and the bump macro**

In `runtime/march_scheduler.h`, inside `typedef struct march_proc`, immediately
before the last `#ifdef MARCH_DEBUG` in the struct (~`:469`):
```c
    /* observe quick win 2 (THROWAWAY spike): cumulative counters. One writer
     * each, relaxed atomics: a plain load and store on x86-64 and arm64. */
    _Atomic uint64_t            obs_slices;   /* owning scheduler, at dispatch   */
    _Atomic uint64_t            obs_msgs_in;  /* this proc, at dequeue           */
    _Atomic uint64_t            obs_msgs_out; /* this proc, after a good send    */
```
In `typedef struct march_scheduler` (the struct with `stat_idle_polls`, ~`:506`),
after `int64_t stat_idle_polls;`:
```c
    _Atomic uint64_t obs_idle_ns;     /* QW2 spike: ns asleep on the idle path */
```
After the `march_proc` typedef closes (`} march_proc;`), add:
```c
/* QW2 spike: single-writer increment without an RMW. */
#define MARCH_OBS_BUMP(field) \
    atomic_store_explicit(&(field), \
        atomic_load_explicit(&(field), memory_order_relaxed) + 1, \
        memory_order_relaxed)
void march_obs_spike_dump(void);
```

- [ ] **Step 5: Bump at the four sites**

`runtime/march_scheduler.c`, dispatch (right after `sched->stat_dispatches++;`, ~`:2029`):
```c
        MARCH_OBS_BUMP(p->obs_slices);
```
Idle path: replace the three lines `march_reclaim_offline(); nanosleep(&idle_sleep, NULL); march_reclaim_online();` (~`:1970-1972`) with:
```c
            struct timespec obs_t0, obs_t1;
            clock_gettime(CLOCK_MONOTONIC, &obs_t0);
            march_reclaim_offline();
            nanosleep(&idle_sleep, NULL);
            march_reclaim_online();
            clock_gettime(CLOCK_MONOTONIC, &obs_t1);
            atomic_store_explicit(&sched->obs_idle_ns,
                atomic_load_explicit(&sched->obs_idle_ns, memory_order_relaxed)
                + (uint64_t)((obs_t1.tv_sec - obs_t0.tv_sec) * 1000000000LL
                             + (obs_t1.tv_nsec - obs_t0.tv_nsec)),
                memory_order_relaxed);
```
Dequeue, in `march_sched_recv_actor_ex`, right after the `march_mbox_node *node = mbox_unlink(...);` statement (~`:3113`):
```c
            MARCH_OBS_BUMP(p->obs_msgs_in);   /* counts markers too: spike */
```
`runtime/march_runtime.c`, `march_send`, right after `march_reclaim_exit();` that
follows `int send_rc = gt ? march_sched_send(gt, msg) : MARCH_SEND_DEAD;` (~`:7077`):
```c
    if (send_rc != MARCH_SEND_DEAD) {
        /* Re-read the TLS here, after any BLOCK-policy park inside
         * march_sched_send: the green thread may now run on another OS thread.
         * march_sched_current lives in march_scheduler.c, so it cannot be
         * inlined or hoisted across that switch. */
        march_proc *obs_self = march_sched_current();
        if (obs_self) MARCH_OBS_BUMP(obs_self->obs_msgs_out);
    }
```

- [ ] **Step 6: Non-vacuity dump (off unless `MARCH_OBS_SPIKE_DUMP=1`)**

`runtime/march_scheduler.c`, near the top-level statics:
```c
static int              g_obs_dump;               /* QW2 spike */
static _Atomic uint64_t g_obs_reaped_msgs_out;    /* QW2 spike */

void march_obs_spike_dump(void) {
    if (!g_obs_dump) return;
    uint64_t idle = 0;
    for (int i = 0; i <= MARCH_MAX_SCHEDULERS; i++)
        idle += atomic_load_explicit(&g_scheds[i].obs_idle_ns, memory_order_relaxed);
    fprintf(stderr, "obs-spike: idle_ns=%llu reaped_msgs_out=%llu\n",
            (unsigned long long)idle,
            (unsigned long long)atomic_load_explicit(&g_obs_reaped_msgs_out,
                                                     memory_order_relaxed));
}
```
In `march_sched_init` (~`:1453`), first lines of the body:
```c
    {
        static int obs_once;
        const char *d = getenv("MARCH_OBS_SPIKE_DUMP");
        g_obs_dump = (d && d[0] == '1');
        if (g_obs_dump && !obs_once) { obs_once = 1; atexit(march_obs_spike_dump); }
    }
```
In the DEAD reap branch (`} else if (st == PROC_DEAD) {`, ~`:2075`), first statement:
```c
            if (g_obs_dump)
                atomic_fetch_add_explicit(&g_obs_reaped_msgs_out,
                    atomic_load_explicit(&p->obs_msgs_out, memory_order_relaxed),
                    memory_order_relaxed);
```
(`g_scheds` is declared above `march_sched_init`; if the compiler says it is not,
move `march_obs_spike_dump` below the `g_scheds` definition at ~`:127`.)

- [ ] **Step 7: Build the patched arm and prove the patch is in it**

```bash
cd $WT && $MARCH --compile --opt 2 bench/actors/fanin_flood.march -o $OBS/ff_patched > $OBS/ff_patched.log 2>&1; echo "exit $?"; cat $OBS/ff_patched.log
MARCH_OBS_SPIKE_DUMP=1 $OBS/ff_patched > $OBS/ff_dump.txt 2>&1; cat $OBS/ff_dump.txt
MARCH_OBS_SPIKE_DUMP=1 $OBS/ff_base    > $OBS/ff_dump_base.txt 2>&1; grep -c obs-spike $OBS/ff_dump_base.txt
```
Expected: patched prints `delivered 400000` (or the program's count) and
`obs-spike: idle_ns=<nonzero> reaped_msgs_out=<≥ 400000>`; the base prints no
`obs-spike` line (`0`). If `reaped_msgs_out` is below the delivered count, the
`msgs_out` site is wrong: fix before measuring.

- [ ] **Step 8: Measure**

```bash
python3 prototypes/observe/ab.py $OBS/ff_base $OBS/ff_patched --runs 40 | tee $OBS/qw2_ab.txt
```
Then the two sanity benches, n=10 each, same script:
```bash
for b in call_storm spawn_churn; do
  MARCH_RUNTIME_DIR=$OBS/runtime_base $MARCH --compile --opt 2 bench/actors/$b.march -o $OBS/${b}_base > $OBS/${b}_b.log 2>&1
  $MARCH --compile --opt 2 bench/actors/$b.march -o $OBS/${b}_patched > $OBS/${b}_p.log 2>&1
  python3 prototypes/observe/ab.py $OBS/${b}_base $OBS/${b}_patched --runs 10 | tee -a $OBS/qw2_ab.txt
done
```

- [ ] **Step 9: Verdict (thresholds fixed now)**

- **PASS** if both fanin_flood lines are `PASS`.
- If fanin_flood FAILs, bisect by reverting one site at a time (idle timing,
  dispatch bump, dequeue bump, send bump) and re-measure; record which site costs.
  The big plan's R2 then drops or gates that counter.
- call_storm and spawn_churn are sanity checks at n=10: record, don't gate.

- [ ] **Step 10: Commit**

```bash
cd $WT && git add prototypes/observe/ab.py runtime/march_scheduler.h runtime/march_scheduler.c runtime/march_runtime.c && \
  git commit -m "proto(observe): QW2 per-proc counters + idle-time spike and A/B runner"
```

---

### Task 3: QW3, a shell on today's hot deploy

**Files:**
- Create: `prototypes/observe/shell/app.march`
- Create: `prototypes/observe/shell/rpc.sh`

**Interfaces:**
- Consumes: `test/hcr_deploy.exe keygen <dir>` (writes `pk` base64, `sk` hex) and
  `hcr_deploy.exe deploy <socket> <keydir> <so> [<old .schemas.json> <old .hcr_manifest>]`
  (`test/hcr_deploy.ml:1-15`); `--hot-reload <NestedModule>` makes that nested module's
  functions reloadable (the entry module's own top-level fns are **not** on the boundary);
  a call dispatches whenever its **callee** is reloadable.
- Produces: `rpc.sh '<expr>'` prints the node's rendered result and one timing line
  `qw3: compile_s=… deploy_s=… run_s=… total_s=… so_bytes=…`.

- [ ] **Step 1: Write the node**

`prototypes/observe/shell/app.march`:
```march
-- Quick win 3 (THROWAWAY): a "remote shell" made only of today's hot deploy.
-- rpc.sh rewrites the line ending in "-- EXPR" inside Hook.run, builds a
-- --compile-so patch, deploys it, then touches the trigger file; main's poll
-- loop calls Hook.run and prints "SHELL-OUT <seq> <result>". Hook is a
-- NESTED module so it sits on the hot-reload boundary (--hot-reload Hook).
-- The version-1 expression below touches Actor, Scheduler and System so the
-- capability-widening gate accepts later inputs that use any of them.
mod ShellApp do
  needs IO
  needs IO.Console
  needs IO.Spawn
  needs IO.Clock
  needs IO.Process
  needs IO.FileRead
  needs IO.FileWrite

  actor Counter do
    state { n : Int }
    init  { n: 0 }
    on Bump(k : Int) do
      { n: state.n + k }
    end
  end

  mod Hook do
    needs IO
    needs IO.Process
    needs IO.Clock

    fn run(io : Cap(IO)) : String do
      let intro = Actor.introspect(io)
      to_string((List.length(Actor.list(intro)), Scheduler.live_procs(), System.mem_peak_bytes()))  -- EXPR
    end
  end

  fn poll(io : Cap(IO), trigger : String, seq : Int, deadline : Int) : () do
    if System.monotonic_time() > deadline do ()
    else
      if File.exists(trigger) do
        let _ = File.delete(trigger)
        println(String.join(["SHELL-OUT ", int_to_string(seq), " ", Hook.run(io)], ""))
        poll(io, trigger, seq + 1, deadline)
      else
        sleep_ms(20)
        poll(io, trigger, seq, deadline)
      end
    end
  end

  fn main(io : Cap(IO)) do
    let c = spawn(Counter)
    let _ = Actor.register(c, "counter")
    send(c, Bump(1))
    println("shell-app: ready")
    poll(io, "/tmp/obs-clever-rhodes/qw3.trigger", 1, System.monotonic_time() + 900000)
    println("shell-app: deadline")
  end
end
```

- [ ] **Step 2: Build the base with a signing key; start it**

```bash
rm -rf $OBS/qw3_keys $OBS/qw3_base $OBS/qw3_patch_* $OBS/qw3.seq $OBS/qw3.trigger && mkdir -p $OBS/qw3_keys $OBS/qw3_base
$WT/_build/default/test/hcr_deploy.exe keygen $OBS/qw3_keys
cp $WT/prototypes/observe/shell/app.march $OBS/qw3_base/app.march
cd $OBS/qw3_base && $MARCH --compile --hot-reload Hook --signing-pubkey "$(cat $OBS/qw3_keys/pk)" -o $OBS/qw3_base/app app.march > $OBS/qw3_base/build.log 2>&1; echo "exit $?"; cat $OBS/qw3_base/build.log; ls $OBS/qw3_base
```
Expected: `exit 0` and, beside `app`, sidecars ending `.schemas.json` and
`.hcr_manifest`. Start it in the background (it exits itself after 15 min):
```bash
MARCH_HOT_RELOAD_SOCKET=$OBS/qw3.sock $OBS/qw3_base/app > $OBS/qw3_app.log 2>&1 &
```
Then: `until grep -q "shell-app: ready" $OBS/qw3_app.log; do sleep 0.1; done; ls -la $OBS/qw3.sock`.

- [ ] **Step 3: Write `rpc.sh`**

`prototypes/observe/shell/rpc.sh`:
```bash
#!/usr/bin/env bash
# Quick win 3 (THROWAWAY): one "shell input". Usage: rpc.sh '<march expr>'
# Inside the expression, `intro : Cap(Actor.Introspect)` and `io : Cap(IO)` are in scope.
set -euo pipefail
: "${WT:?}" "${MARCH:?}" "${OBS:?}"
now() { python3 -c 'import time; print(time.time())'; }
n=$(( $(cat "$OBS/qw3.seq" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$OBS/qw3.seq"
d="$OBS/qw3_patch_$n"; mkdir -p "$d"
EXPR="$1" python3 - "$WT/prototypes/observe/shell/app.march" "$d/app.march" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
out = []
for line in open(src):
    if line.rstrip().endswith("-- EXPR"):
        indent = line[: len(line) - len(line.lstrip())]
        line = f"{indent}to_string({os.environ['EXPR']})  -- EXPR\n"
    out.append(line)
open(dst, "w").writelines(out)
PY
if [ "$n" -eq 1 ]; then prev="$OBS/qw3_base"; else prev="$OBS/qw3_patch_$((n - 1))"; fi
old_s=$(ls "$prev"/*.schemas.json 2>/dev/null | head -1 || true)
old_m=$(ls "$prev"/*.hcr_manifest 2>/dev/null | head -1 || true)
t0=$(now)
( cd "$d" && "$MARCH" --compile --compile-so --hot-reload Hook -o "$d/v.so" app.march ) > "$d/compile.log" 2>&1 \
  || { echo "qw3: COMPILE FAILED"; cat "$d/compile.log"; exit 2; }
t1=$(now)
"$WT/_build/default/test/hcr_deploy.exe" deploy "$OBS/qw3.sock" "$OBS/qw3_keys" "$d/v.so" $old_s $old_m \
  > "$d/deploy.log" 2>&1 || { echo "qw3: DEPLOY REFUSED"; cat "$d/deploy.log"; exit 3; }
t2=$(now)
before=$(grep -c '^SHELL-OUT' "$OBS/qw3_app.log" || true)
touch "$OBS/qw3.trigger"
for _ in $(seq 1 500); do
  [ "$(grep -c '^SHELL-OUT' "$OBS/qw3_app.log" || true)" -gt "$before" ] && break
  sleep 0.02
done
t3=$(now)
grep '^SHELL-OUT' "$OBS/qw3_app.log" | tail -1
python3 - "$t0" "$t1" "$t2" "$t3" "$(wc -c < "$d/v.so")" <<'PY'
import sys
t0, t1, t2, t3 = map(float, sys.argv[1:5])
print(f"qw3: compile_s={t1-t0:.2f} deploy_s={t2-t1:.2f} run_s={t3-t2:.2f} "
      f"total_s={t3-t0:.2f} so_bytes={sys.argv[5]}")
PY
```
`chmod +x prototypes/observe/shell/rpc.sh`.

- [ ] **Step 4: Run the input set, in order, recording every output**

```bash
cd $WT && R=prototypes/observe/shell/rpc.sh
$R 'Scheduler.live_procs()'
$R 'Actor.top_by_mailbox(intro, 3)'
$R 'Actor.whereis(intro, "counter")'
$R 'List.map(Actor.list(intro), fn p -> mailbox_size(p))'
$R '(1, "two", Some(3.5), [4, 5])'
$R 'Scheduler.live_procs()'
$R 'println("side effect")'
```
Expected: inputs 1–6 each print a `SHELL-OUT` line and a `qw3:` timing line; input
6 repeats input 1 to show a warm compile. Input 7 needs `IO.Console`, which version
1's `Hook.run` does not use, so **expect `qw3: DEPLOY REFUSED`** with the widening
gate's message. If input 7 is *accepted*, that is a finding: record it.

- [ ] **Step 5: Verdict (thresholds fixed now)**

Using the median `total_s` of inputs 1–6:
- **≤ 2 s:** a shell is viable on whole-program patches; the big plan's R5.5
  (`--fragment` emission) becomes an optimisation, filed separately.
- **2–5 s:** keep R5.5 in R5; record which phase dominates (compile or deploy).
- **> 5 s:** R5.5 is mandatory and R6 does not start without it.

Rendering: for each of inputs 2–5, mark the output **useful** (constructor names,
values legible) or **opaque** (`#<tag:N>`, raw pointers). Any opaque output keeps
the big plan's R5.7 (on-demand `derive Show`) mandatory.

Also record `so_bytes`. This is the big plan's R5.1 measurement.

- [ ] **Step 6: Commit**

```bash
cd $WT && git add prototypes/observe/shell/app.march prototypes/observe/shell/rpc.sh && \
  git commit -m "proto(observe): QW3 shell round trip on today's hot deploy"
```

---

### Task 4: QW4, an observe thread that walks the actor table

**Files:**
- Modify: `runtime/march_runtime.c` (append a section at end of file; one call at the top of `march_run_scheduler`, ~`:7003`)
- Create: `prototypes/observe/spike/many_actors.march`
- Create: `prototypes/observe/spike/poll.sh`

**Interfaces:**
- Consumes: `g_actor_tbl`, `MARCH_SCHED_BUCKETS`, `pe_pid`, `meta_gt`,
  `march_reclaim_enter/exit` (all visible inside `march_runtime.c`), and
  `obs_slices` from Task 2.
- Produces: env `MARCH_OBSERVE_SOCKET=<path>` starts a thread answering
  `PING` → `PONG` and `ACTORS` → one line per actor `"<pid> <mbox> <status> <slices>"`
  followed by `took_us <N> count <M>`.

- [ ] **Step 1: Write the stress program**

`prototypes/observe/spike/many_actors.march`:
```march
-- Quick win 4 (THROWAWAY): 20 000 idle actors plus a spawn/kill churn task,
-- so the observe thread walks a large, changing actor table. Exits by itself.
mod ManyActors do
  needs IO
  needs IO.Console
  needs IO.Spawn
  needs IO.Clock

  actor W do
    state { n : Int }
    init  { n: 0 }
    on Poke(k : Int) do
      { n: state.n + k }
    end
  end

  fn spawn_n(k : Int, acc) do
    if k == 0 do acc else spawn_n(k - 1, Cons(spawn(W), acc)) end
  end

  fn churn(k : Int) : () do
    if k == 0 do ()
    else
      let p = spawn(W)
      send(p, Poke(1))
      let _ = kill(p)
      churn(k - 1)
    end
  end

  fn main(_io : Cap(IO)) do
    let keep = spawn_n(20000, Nil)
    run_until_idle()
    println("qw4: ready " ++ int_to_string(List.length(keep)))
    let t = Task.async(fn -> churn(300000))
    let _ = Task.await(t)
    println("qw4: churn done")
    sleep_ms(2000)
    println("qw4: exit " ++ int_to_string(List.length(keep)))
  end
end
```

- [ ] **Step 2: Write the poller**

`prototypes/observe/spike/poll.sh`:
```bash
#!/usr/bin/env bash
# Quick win 4: poll ACTORS N times; append each reply's took_us/count line.
set -euo pipefail
: "${OBS:?}"
n=${1:-200}; out=${2:-$OBS/qw4_took.txt}; : > "$out"
for _ in $(seq 1 "$n"); do
  printf 'ACTORS\n' | nc -U -w 2 "$OBS/qw4.sock" | tail -1 >> "$out" || echo "ERR" >> "$out"
done
python3 - "$out" <<'PY'
import statistics, sys
rows = [l.split() for l in open(sys.argv[1]) if l.startswith("took_us")]
us = sorted(int(r[1]) for r in rows); cnt = [int(r[3]) for r in rows]
errs = sum(1 for l in open(sys.argv[1]) if not l.startswith("took_us"))
p = lambda q: us[min(len(us) - 1, int(q * (len(us) - 1)))]
print(f"qw4: replies={len(us)} errors={errs} took_us p50={p(.5)} p99={p(.99)} max={us[-1]} "
      f"count min={min(cnt)} max={max(cnt)}")
PY
```
`chmod +x prototypes/observe/spike/poll.sh`.

- [ ] **Step 3: Run the program before the spike exists (expect no socket)**

```bash
cd $WT/prototypes/observe/spike && $MARCH --compile --opt 2 -o $OBS/qw4 many_actors.march > $OBS/qw4_build.log 2>&1; echo "exit $?"
MARCH_OBSERVE_SOCKET=$OBS/qw4.sock $OBS/qw4 > $OBS/qw4.log 2>&1 &
```
Then: `until grep -q "qw4: ready" $OBS/qw4.log; do sleep 0.2; done; ls $OBS/qw4.sock 2>&1`.
Expected: `No such file or directory`: nothing listens yet (the RED check).
Wait for `qw4: exit` in the log before continuing.

- [ ] **Step 4: Add the spike to the runtime**

Append to the end of `runtime/march_runtime.c`:
```c
/* ── observe quick win 4 (THROWAWAY spike) ─────────────────────────────────
 * MARCH_OBSERVE_SOCKET=<path>: a detached pthread answers PING and ACTORS on a
 * Unix socket. The walk is march_actor_pid_indices' walk plus a copy-out of a
 * few proc fields, inside ONE reclamation critical section, on a thread that is
 * not a scheduler (slots are per OS thread, registered lazily). Nothing parks
 * or sleeps inside the section. */
#include <sys/socket.h>
#include <sys/un.h>
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

static char *obs_spike_actors(size_t *len_out) {
    size_t cap = 1u << 16, len = 0;
    char *buf = (char *)malloc(cap);
    if (!buf) return NULL;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    long long count = 0;
    march_reclaim_enter();
    for (unsigned int b = 0; b < MARCH_SCHED_BUCKETS; b++) {
        for (march_actor_meta *m = atomic_load_explicit(&g_actor_tbl[b], memory_order_acquire);
             m; m = atomic_load_explicit(&m->tbl_next, memory_order_acquire)) {
            int64_t pidx = pe_pid(m->pe);
            if (!m->actor || pidx < 0) continue;
            march_proc *gt = meta_gt(m);
            long long mbox = gt ? (long long)atomic_load_explicit(&gt->mbox_count, memory_order_relaxed) : -1;
            int st = gt ? (int)atomic_load_explicit(&gt->status, memory_order_relaxed) : -1;
            unsigned long long sl = gt ? (unsigned long long)atomic_load_explicit(&gt->obs_slices, memory_order_relaxed) : 0;
            if (cap - len < 128) {
                char *g = (char *)realloc(buf, cap * 2);
                if (!g) goto walked;
                buf = g; cap *= 2;
            }
            len += (size_t)snprintf(buf + len, cap - len, "%lld %lld %d %llu\n",
                                    (long long)pidx, mbox, st, sl);
            count++;
        }
    }
walked:
    march_reclaim_exit();
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long us = (long long)(t1.tv_sec - t0.tv_sec) * 1000000LL
                 + (long long)(t1.tv_nsec - t0.tv_nsec) / 1000LL;
    if (cap - len < 64) {
        char *g = (char *)realloc(buf, cap + 64);
        if (!g) { free(buf); return NULL; }
        buf = g; cap += 64;
    }
    len += (size_t)snprintf(buf + len, cap - len, "took_us %lld count %lld\n", us, count);
    *len_out = len;
    return buf;
}

static void obs_spike_send_all(int c, const char *p, size_t n) {
    while (n > 0) {
        ssize_t w = send(c, p, n, MSG_NOSIGNAL);
        if (w <= 0) return;
        p += w; n -= (size_t)w;
    }
}

static void *obs_spike_thread(void *arg) {
    int ls = (int)(intptr_t)arg;
    for (;;) {
        int c = accept(ls, NULL, NULL);
        if (c < 0) continue;
#ifdef SO_NOSIGPIPE
        { int one = 1; setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one); }
#endif
        char line[64];
        ssize_t n = read(c, line, sizeof line - 1);
        if (n > 0) {
            line[n] = '\0';
            if (strncmp(line, "ACTORS", 6) == 0) {
                size_t len = 0;
                char *buf = obs_spike_actors(&len);
                if (buf) { obs_spike_send_all(c, buf, len); free(buf); }
            } else if (strncmp(line, "PING", 4) == 0) {
                obs_spike_send_all(c, "PONG\n", 5);
            }
        }
        close(c);
    }
    return NULL;
}

/* Called on the main OS thread at the top of march_run_scheduler, before any
 * green thread runs: never pthread_create from a green thread (ASAN SIGSEGV). */
void march_obs_spike_maybe_start(void) {
    static int started;
    if (started) return;
    const char *path = getenv("MARCH_OBSERVE_SOCKET");
    struct sockaddr_un a;
    if (!path || !*path || strlen(path) >= sizeof a.sun_path) return;
    started = 1;
    int ls = socket(AF_UNIX, SOCK_STREAM, 0);
    if (ls < 0) return;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    strncpy(a.sun_path, path, sizeof a.sun_path - 1);
    unlink(path);
    if (bind(ls, (struct sockaddr *)&a, sizeof a) < 0 || listen(ls, 8) < 0) { close(ls); return; }
    pthread_t t;
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&at, 1u << 20);
    pthread_create(&t, &at, obs_spike_thread, (void *)(intptr_t)ls);
    pthread_attr_destroy(&at);
}
```
At the top of `march_run_scheduler`'s body (~`:7003`), before the first `if`:
```c
    { extern void march_obs_spike_maybe_start(void); march_obs_spike_maybe_start(); }
```

- [ ] **Step 5: Rebuild and prove it answers (the GREEN check)**

```bash
cd $WT/prototypes/observe/spike && rm -f $OBS/qw4.sock && $MARCH --compile --opt 2 -o $OBS/qw4 many_actors.march > $OBS/qw4_build.log 2>&1; echo "exit $?"; cat $OBS/qw4_build.log
MARCH_OBSERVE_SOCKET=$OBS/qw4.sock $OBS/qw4 > $OBS/qw4.log 2>&1 &
```
Then:
```bash
until grep -q "qw4: ready" $OBS/qw4.log; do sleep 0.2; done
printf 'PING\n' | nc -U -w 2 $OBS/qw4.sock
printf 'ACTORS\n' | nc -U -w 2 $OBS/qw4.sock | tail -3
```
Expected: `PONG`; then two actor lines and `took_us <N> count <≥ 20000>`.

- [ ] **Step 6: Measure under churn**

Restart the program (it has probably exited) and poll while the churn task runs:
```bash
MARCH_OBSERVE_SOCKET=$OBS/qw4.sock $OBS/qw4 > $OBS/qw4.log 2>&1 &
```
```bash
until grep -q "qw4: ready" $OBS/qw4.log; do sleep 0.2; done
$WT/prototypes/observe/spike/poll.sh 200 $OBS/qw4_took.txt
grep -E "qw4: (churn done|exit)" $OBS/qw4.log
```
Expected: the `qw4:` summary line; `errors=0`; the program still prints `qw4: churn
done` and `qw4: exit 20000` (the walk neither crashed nor wedged it). If `churn
done` printed before polling finished, rerun with `churn(1000000)` so all 200
polls overlap churn; record which count you used.

- [ ] **Step 7: Linux ASAN run in Docker**

```bash
docker rm -f march-obs-asan 2>/dev/null
docker run -d --name march-obs-asan --user opam -v "$WT":/mnt:ro march-amdr-repro bash -c \
  'mkdir -p /tmp/work && cd /mnt && tar --exclude=_build --exclude=.git --exclude=.march -cf - . | (cd /tmp/work && tar xf -) && cd /tmp/work && opam exec -- dune build --root . bin/main.exe > /tmp/build.log 2>&1; echo built > /tmp/built; sleep 3600'
until docker exec march-obs-asan test -f /tmp/built; do sleep 10; done
docker exec march-obs-asan bash -c 'cd /tmp/work && export MARCH_RUNTIME_DIR=/tmp/work/runtime MARCH_STDLIB=/tmp/work/stdlib MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1 && ./_build/default/bin/main.exe --compile -o /tmp/qw4 prototypes/observe/spike/many_actors.march > /tmp/c.log 2>&1; echo compile=$?; (MARCH_OBSERVE_SOCKET=/tmp/q.sock /tmp/qw4 > /tmp/run.log 2>&1 &); until grep -q "qw4: ready" /tmp/run.log; do sleep 0.5; done; for i in $(seq 1 100); do printf "ACTORS\n" | nc -U -w 2 /tmp/q.sock | tail -1; done > /tmp/poll.txt; sleep 30; tail -5 /tmp/run.log; grep -c took_us /tmp/poll.txt; grep -c "ERROR: AddressSanitizer" /tmp/run.log || true'
docker rm -f march-obs-asan
```
Expected: `compile=0`, the run log ends with `qw4: exit 20000`, 100 `took_us` lines,
and ASAN error count `0`. If `nc` lacks `-U` in the image, install it with
`docker exec --user root march-obs-asan apt-get install -y netcat-openbsd` and rerun
the exec. If the image is missing or the build fails, record "ASAN not run" and why:
the verdict below is then provisional.

- [ ] **Step 8: Verdict (thresholds fixed now)**

- **PASS** if, at 20 000 actors under churn: `errors=0`, the program exits normally,
  `took_us p99 < 10 000` (10 ms), and Linux ASAN reports nothing.
- If p99 ≥ 10 ms, record p50/p99 and the count; the big plan's R1 then adds a hard
  `n` cap and pagination before any other verb.
- Any crash, wedge or ASAN report: stop; that falsifies the big plan's C16
  ("a foreign thread can read procs this way"), and R0/R1 must move the walk to a
  green thread the socket thread asks and waits on.

- [ ] **Step 9: Commit**

```bash
cd $WT && git add runtime/march_runtime.c prototypes/observe/spike/many_actors.march prototypes/observe/spike/poll.sh && \
  git commit -m "proto(observe): QW4 foreign-thread actor walk over a Unix socket"
```

---

### Task 5: Results file and big-plan edits (this is the only work that merges)

**Files:**
- Create: `specs/progress/2026-09-29-observe-quick-wins-results.md` (on the spec branch)
- Modify: `specs/plans/2026-09-28-observe-recon-shell-plan.md` (only what a verdict forces)
- Modify: `specs/todos/2026-09-24-observe-recon-shell.md` (one line linking the results)

- [ ] **Step 1: Switch to the spec branch**

```bash
cd $WT && git switch claude/observer-recon-deploy-spec-ab90e2 && git status --short
```
Expected: clean (the throwaway branch keeps the prototype commits).

- [ ] **Step 2: Write the results file with this exact skeleton, filled in**

```markdown
# Observe quick wins: results

**Date:** <day measured>
**Plan:** [plans/2026-09-29-observe-quick-wins-plan.md](../plans/2026-09-29-observe-quick-wins-plan.md)
**Prototype code:** branch `proto/observe-quick-wins` (not merged), commit <sha>.
**Box:** <machine>, load average during runs <min–max>.

## QW1 recon-lite: <PASS|FAIL>
- Reports naming slow_consumer first: <k>/3.
- Operator questions (yes/no, why): <five lines>.
- Compiler friction while writing it: <list or "none">.
- Big-plan consequence: <one sentence>.

## QW2 counter cost: <PASS|FAIL|UNDECIDED (A/A failed)>
| bench | scheds | n | base med | patched med | delta | limit | verdict |
|---|---|---|---|---|---|---|---|
- A/A control: <two lines>.
- Non-vacuity dump: idle_ns=<…> reaped_msgs_out=<…>.
- Big-plan consequence: <one sentence>.

## QW3 shell round trip: <≤2 s | 2–5 s | >5 s>
| # | input | output (verbatim) | useful/opaque | compile_s | deploy_s | run_s | total_s | so_bytes |
|---|---|---|---|---|---|---|---|---|
- Input 7 (widening): <refused with "…" | accepted>.
- Big-plan consequence (R5.1, R5.5, R5.7): <sentences>.

## QW4 foreign-thread walk: <PASS|FAIL|PROVISIONAL>
- 20 000 actors, churn <count>: replies <n>, errors <n>, took_us p50 <…> p99 <…> max <…>.
- Linux ASAN: <clean | findings | not run: why>.
- Big-plan consequence (C16, R0, R1): <sentence>.

## Changes made to the big plan
- <bullet per edit, with the section id>
```

- [ ] **Step 3: Edit the big plan where a verdict forces it**

Apply exactly these rules, nothing else:
- QW2 FAIL at a site → R2 item: mark that counter "gated behind the armed flag" or
  "dropped", citing the results file.
- QW3 `total_s ≤ 2 s` → R5 item 5 (`--fragment`): move to R11 as an optimisation.
  `> 5 s` → add to R5's Acceptance "fragment round trip ≤ 2 s".
- QW3 any opaque rendering → R5 item 7 stays mandatory (no edit); all useful →
  R5 item 7 becomes "verify, not build".
- QW4 FAIL → R0 item 1 and R1 item 1: the walk runs on a green thread the socket
  thread asks and waits on; C16 row gets "falsified by QW4".
- QW1 answers "yes" to question 3, 4 or 5 → note the over-build in R1/R2 as a
  candidate cut. No edit otherwise.

- [ ] **Step 4: Link the results from the todo**

Append to `specs/todos/2026-09-24-observe-recon-shell.md`:
```markdown
Quick-win results (2026-09-29): [`progress/2026-09-29-observe-quick-wins-results.md`](../progress/2026-09-29-observe-quick-wins-results.md).
```

- [ ] **Step 5: Lint and commit**

```bash
cd $WT && scripts/check-docs.sh > $OBS/docs.log 2>&1; echo "exit $?"; tail -2 $OBS/docs.log
git add specs/progress/2026-09-29-observe-quick-wins-results.md specs/plans/2026-09-28-observe-recon-shell-plan.md specs/todos/2026-09-24-observe-recon-shell.md && \
  git commit -m "specs: observe quick-win results and the plan edits they force"
deciduous add outcome "Observe quick wins measured; plan updated" -c 85 --commit HEAD
```
Expected: `exit 0` and `doc-lint passed`. No CHANGELOG entry: nothing user-visible ships.
