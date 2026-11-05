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

## Hot-deploy consequence: no reply-covariance law

Design `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` §3.3, item 1: across a
hot deploy, a call handler's new reply refinement must imply the old one, because a caller
still running old-epoch code relies on the old reply contract. Phase A0 left this undone,
and it can't be done by the deploy gate alone.

## Now

- `actor_reply : a -> b -> Unit` and `actor_call : … -> Result(c, String)`
  (`lib/typecheck/typecheck_builtins.ml`) are fully polymorphic and unconnected: the
  handler's `reply_to` has no reply type, and the caller's `Ok(v)` is typed by its use.
- A handler can reply with values of different types on different paths, and nothing ties
  them to the caller's expectation. So there is no reply type, let alone a reply refinement,
  to write into `.schemas.json`.

## Needed first

A typed reply channel, for example `on GetCount(reply_to : Reply({Int | _ >= 0}))`, with
`Actor.reply : Reply(a) -> a -> Unit` and `Actor.call` typed by the handler it targets. That
is a language change (syntax, typechecker, both backends' call paths), with its own design.

## Then

The schema writer records each call handler's reply refinement (`"reply_refine"`), and
`--check-migration` adds a law `<Actor>.<Handler>.reply`, new ⇒ old (covariant), with the
same verdicts and the `--accept-unproved` override.
