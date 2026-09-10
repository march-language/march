# A nested record projection captured by a constructor was moved, not dup'd

**Landed:** 2026-09-09. Found by chasing `test/native/node_discovery.march`'s
"pre-existing" intermittent exit 138 / SIGTRAP (documented as two Msgpack
memory bugs in `specs/todos/2026-09-06-closure-capture-release-widening.md`
#5 — that framing was a debugging artifact, see below).

## Root cause

`lib/tir/perceus_core.ml`, `result_is_borrowed_field`: the lookahead that
decides whether a `let v = e1` binding aliases a field of a record someone else
owns walked a nested let-chain (`ELet (iv, EField src, body)` → recurse) but
had no arm for the chain **ending** in a projection, falling to `| _ -> false`.
`h.identity.name` lowers to exactly `let r = h.identity in r.name`, so `v` was
classified as OWNED: a consuming use (`alloc Value.Str(v)`) took it without a
dup, and that cell's drop later released the record owner's string. The
one-level read `h.nonce` right beside it hit the direct `EField` arm and was
correct. Final TIR of `NetKernel.handshake` (inlined `Handshake.encode_hello`):

```
let $t28373 : String = (let $t28372 = $t28912.identity in $t28372.name) in alloc Value.Str($t28373)  -- no inc
let $t28381 : String = $t28912.nonce in inc_rc $t28381; alloc Value.Str($t28381)                       -- inc
```

Fix: an `EField (AVar src, _)` arm that answers true when `src` is a
borrowed record (in the lookahead's own borrowed set, or `field_src_is_borrowed`),
and the `ELet` arm also consults that local set so a deeper chain composes.

## How it presented, and the trap that hid it

`node_discovery` encodes `my_id.name`/`my_id.node_id` in the handshake hello;
`encode_val` consumes the `Value` and drops the `Str` cells, decrementing
`node_id` to zero while `my_id` still owns it. Each node then re-reads
`my_id.node_id` for its SwimPing/SwimPingAck from freed, reused memory:
`march_string_split`'s `sep->len == 0` loop read a `len` that was malloc
free-list / reused-object data (`0xfac71148`-class values) and faulted at
`ss->data + i`.

Every `lldb` backtrace of a crashing run instead showed 57+ frames of
`Msgpack.list_append` dying on its own prologue push — which is how the old
"cyclic list / stack overflow" theory arose. That fault is a **benign, self-
recovering lazy-stack-growth request**: lldb intercepts `EXC_BAD_ACCESS`
before the runtime's `march_sigsegv_handler` can `mprotect` the next page, so
under a debugger you never get past the first fault of a run, which is almost
never the fatal one. (`MARCH_STACK_MAX` is a compile-time `#define`, never
`getenv`'d, so the "16x larger stack didn't help" experiment tested nothing.)
The real fault was found with in-process instrumentation: `fprintf` at the
handler's `goto fatal` sites printing `si_addr` and the `ucontext` PC minus
`_dyld_get_image_vmaddr_slide(0)`, resolved offline with
`lldb -b -o "image lookup -a <static pc>"` on the binary file. TRMC was ruled
out (byte-identical `list_append` codegen under `--no-trmc`).

**Do not** debug this class by parking a faulting process and attaching /
SIGKILLing it: doing so kernel-panicked the dev Mac. The runtime's own fault
handler comment already warns that a signal death from a green-thread altstack
context wedges the thread uninterruptibly. `MallocStackLogging=1` also masks
the bug (80/80 clean) by deferring block reuse.

## Measured

Same staged runtime, compilers built from the pre-fix and fixed
`perceus_core.ml`, runs interleaved:

| binary | pre-fix | fixed |
|---|---|---|
| `node_discovery`, 60 sequential | 3 crashes | 0 |
| `node_discovery`, 40 interleaved pairs | 8 crashes | 0 |
| `nested_record_field_capture` (heap strings + churn) | exit 138, 3/3 | correct output, 3/3 |

## Pinned by

- `test/native/nested_record_field_capture.march` native golden (`runtest`).
  The fixture builds its strings with `++` on purpose: a literal is immortal
  (`rc = 1<<40`), so the stray `dec_rc` is invisible on it — the first draft
  of the test passed on the broken compiler for exactly that reason.
- `test/snapshots/src/nested_record_field_capture.march`, post-Perceus golden
  with `inc_rc` on all three captures; the other 42 snapshot cases unchanged.
- `test/refine_audit/corpus.baseline` regenerated for the new fixture (the
  sweep lists every native program).

## Left open

`node_discovery` stays on its `node_discovery_quarantined` diff alias: the
separate torn-stdout line-interleaving race (`test/dune` comment on that rule)
is untouched by this fix. Also unchanged: `NetKernel.handshake` stores its
`my_id` parameter into the `Hello` record without a dup while `my_nonce` next
to it gets one — balanced today because the callee owns `my_id` and the
deep-drop of `Hello` consumes that reference, but worth a second look when the
aggregate-ownership rules are next revisited.
