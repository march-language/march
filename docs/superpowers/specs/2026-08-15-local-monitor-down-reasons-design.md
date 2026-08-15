# Local monitor Down reasons — design

## Scope

Make local monitors deliver the same information on the interpreter and
compiled backends: the monitor reference, the dead actor's Pid, and a reason
that distinguishes normal termination, explicit killing, and a crash. This
change does not add links, trap-exit, restart types, or selective receive.

The public signal is:

```march
Down(monitor_ref, target_pid, reason)
```

with the reason vocabulary aligned to `DistLink.DownReason`:

```march
Normal | Killed | Crash(String)
```

`NodeDown` remains distributed-only.

## Runtime model

`march_actor_meta` will retain the terminal reason for an actor. All compiled
death paths will call one reason-aware death function:

- an explicit `kill(pid)` records `Killed`;
- the supervised crash trap records `Crash(message)`;
- a normal actor-loop termination records `Normal`.

The reason is stored before monitor delivery and before the actor is retired.
Monitoring an already-dead target reads that stored reason; an invalid or
never-spawned target receives `Normal` as the same “no process” fallback used
by the interpreter today. The interpreter will use the same three constructors
and target-Pid field, preserving its existing crash string.

The compiled runtime will construct a reserved system message for `Down`.
Its tag and boxed layout will be declared once in the compiler/runtime ABI,
outside user actor-message tags, so a message cannot be mistaken for a user
constructor. The value owns references to the target Pid and crash string in
the ordinary Perceus manner. A watcher can consume it through `receive()` and
pattern matching just like the interpreter value.

## Mailbox and ordering semantics

Down is control-plane traffic. It bypasses bounded-mailbox drop policies and
is enqueued exactly once for every live monitor at death. This prevents a
full/drop-new mailbox from losing the lifecycle event needed to recover from
overload. `mailbox_size(pid)` reports queued Down messages through the normal
mailbox depth; the obsolete side-band `down_count` is removed.

Monitor registration and death delivery use the existing monitor-list lock.
The target's monitor list is detached before delivery, so `demonitor` racing
with death has the existing best-effort semantics: a monitor either is
detached before the death sweep or receives exactly one Down from that sweep.

## Language and standard library surface

The actor standard library will expose the local reason type and document the
Down shape alongside `monitor`/`demonitor`. The compiler's builtin type table
will know the reserved constructors, while existing user actor message
constructors remain unchanged. The distributed `DownReason` remains the
canonical vocabulary; no second reason type is introduced.

The existing interpreter tests will be strengthened from “mailbox is
non-empty” and a two-field string reason to assertions over all three fields.
Compiled tests will cover explicit kill, crash, already-dead monitoring, and a
bounded/drop-new watcher mailbox to prove the control-plane bypass.

## Failure handling

If allocation of a Down message fails, the runtime terminates through its
existing OOM path rather than silently restoring the old count-only behavior.
If a watcher dies before delivery, its notification is discarded without
touching the watcher mailbox. Crash strings are copied into the Down value;
normal and killed reasons carry no string payload.

## Documentation and completion criteria

Update both actor-language documentation copies if the same section exists in
`docs/` and `specs/lang/`, add an Unreleased changelog entry, move the todo to
`specs/progress/`, and run the actor tests on both backends plus
`scripts/check-docs.sh`. The implementation is complete only when the
interpreter and compiled tests assert the same ref/Pid/reason shape.
