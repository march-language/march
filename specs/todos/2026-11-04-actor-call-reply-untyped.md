`[P2]` `Actor.call` replies are untyped, so the deploy gate cannot check reply covariance

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
