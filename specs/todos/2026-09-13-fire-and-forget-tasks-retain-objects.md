# Fire-and-forget tasks retain ~0.7–0.9 objects per spawn (compiled)

Found 2026-09-13 while fixing the Float task result box
(`specs/progress/2026-09-13-float-task-result-box-released.md`).

```march
pfn ff(n : Int) : Int do
  if n <= 0 do 0 else
    let _t = task_spawn(fn _ -> 7)
    ff(n - 1)
  end
end
-- ff(5000), then 2,000 (or 200,000) task_yield()s, then sample live_allocs
```

`--compile --opt 2`, Darwin arm64: `live_allocs` grew by **3,540 / 4,452 /
3,595** over three runs, for an `Int` result and identically for a Float
one. Awaited tasks are flat (`test/native/task_lifetime_leak_probe.march`),
so the problem is specific to a handle dropped without an await.

Not yet known: whether this is a leak, or tasks not yet run when the sample is
taken. The count varies per run, and a hundredfold more yields did not reduce
it, which argues against "not yet run" but does not rule it out, because
`task_yield` may not drain other schedulers' queues.

Start by counting completed trampolines. Then check the ownership of:
- the closure `wa->clo`: the trampoline comment says a capture-free thunk's
  closure is a static global natively;
- the `malloc`'d `march_thunk_arg`;
- the Task's two references: the caller's, dropped at `_t`'s scope end, and
  the trampoline's hold.

Make the probe wait deterministically, for example with a counter actor the
thunks message, before trusting any delta.
