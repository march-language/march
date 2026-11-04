`[P3]` `Actor.call` and `Actor.reply` are untyped: `actor_call` is `(Pid(a), b, Int) -> Result(c, String)`
and `actor_reply` is `(a, b) -> ()`, so nothing relates the reply's type to the caller's use of it.
Found by the §F2 target 5 survey (specs/plans/2026-11-02-diagnostics-depth-plan.md):

- `match Actor.call(pid, GetReq, 5000) do Ok(n) -> println("count = " ++ n) …` is accepted when the
  handler replies with an `Int`.
- `Actor.reply(state.count, reply_to)` (arguments swapped) is accepted.
- `Actor.call(pid, Inc(1), 5000)`, a message with a payload rather than a zero-arg sentinel, is
  accepted; the call routes by tag, so it reaches whatever handler has that tag.

Each needs an inference change (a reply type per call handler, carried by the sentinel or the
handler), so it is not a diagnostics item. Once the types exist, the mismatch should say "the
`GetCount` handler of actor `Counter` replies with an `Int`" and label the `Actor.reply`.
