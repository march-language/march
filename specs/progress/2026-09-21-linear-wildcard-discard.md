# A `_` binding no longer counts as a use of a linear value

Filed 2026-09-21 as `specs/todos/2026-09-21-linear-param-body-unchecked.md`,
landed 2026-09-21. Split out of `2026-09-20-role-module-take-closed` when
`take_closed` shipped ([[2026-09-21-endpoints-take-closed]]).

## Correction first: the todo named the wrong hole

The open todo claimed **"a `linear` parameter's body is not checked for exactly
one use"** and framed the decision as *whether to check the body at all* or to
document `linear x : a` as an opt-in the caller takes on trust. That claim was
wrong, and anyone acting on it would have chased a check that already exists.
Probing the compiler at `origin/main` (39bb75877):

| program | `--check` |
| --- | --- |
| `pfn f(linear p : a) : a do p end` | exit 0 (control) |
| `pfn f(linear p : a) : () do () end` | exit 1 — ``The linear value `p` was never used.`` |
| `pfn f(linear p : a) : (a, a) do (p, p) end` | exit 1 — ``The linear value `p` is used more than once here.`` |
| `pfn f(linear p : a) : () do let _ = p  () end` | **exit 0 — the actual hole** |

The body was always checked, in both directions. What let
`pfn drop(linear p : a) : () do let _ = p  () end` through was narrower and
more precise: **a wildcard binding counted as a use of its right-hand side.**

## Why the existing wildcard check was blind to it

`check_wildcard_discards` (`lib/typecheck/typecheck.ml`) has rejected
`let _ = <linear>` since 2026-09-13 (`reject/t203`–`t206`), but it judges a
wildcard by its **type**: `contains_linear env t`. That catches a value that is
linear because of what its type holds — a `TLin` wrapper, an `always_linear
type`. It cannot catch a value that is linear because of how it was **bound**:
a `linear p : a` parameter, or a `linear let x = 5` local, is tracked by name in
`env.lin` while its type stays a plain `a` / `Int`. For those the `_` was not
just unnoticed, it was *counted*: inferring the right-hand side fires
`record_use` on the `EVar`, which sets `le_used`, so the scope-close check saw
a value consumed exactly once.

The consequence was not choreography-specific. One generic function was enough
to launder **any** linear value in the program out of existence, with the
"mark it `linear` where it is defined" hint pointing straight at how to write
it.

## The fix

`lib/typecheck/typecheck.ml`:

- `discarded_linear_binding env e` — the tracked linear binding a `let _ = e`
  would drop when `e`'s value *is* that binding: an `EVar`, a linear field read
  `EField (EVar r, f)` (its `"r#f"` sentinel), or either under an `EAnnot`.
  `None` for anything else, notably a call, whose own result type is what
  `check_wildcard_discards` already judges.
- `report_linear_wildcard_discard` — the diagnostic, in the same voice as the
  two existing linear errors, naming the value, its type, and the way out
  (consume it, match on it, or — for a session endpoint — `take_closed` /
  `take_idle`).
- `check_wildcard_let_discard`, called from both `ELet` sites (the `infer_block`
  arm and the tail-position `infer_expr` arm). Guarded on `contains_linear` so
  it fires only where `check_wildcard_discards` is silent: a type-carrying
  linear value stays that one's report, never two.

The rule is about discarding a linear **value**, not about parameters: it fires
for a `linear` parameter, a `linear let` local, a linear field read and a call
returning a linear value alike (the last two already reported, via the type).

### One deliberate exclusion: session endpoints

A `Chan` is excluded (`is_session_chan`), the same exclusion `ELet`'s
`auto_lin` linearity auto-promotion already makes. Session endpoints have their
own, deliberately **narrower** must-close accounting: only an endpoint that
reached `End` must be passed to `Chan.close` (`reject/t75`); a mid-protocol
drop is out of scope (F6), and the accept corpus creates-and-drops such
endpoints on purpose (`t42`/`t44`). This was found by the blast-radius sweep,
not assumed — see below.

## Blast radius

Measured over every `.march` file in the repo (`--check` sweep: `stdlib/`,
`test/native/`, `specs/lang/types/`, and everything else), plus
`@types-check --force` and the `compiler` / `stdlib` / `codegen` suites.

**One newly-failing site, and it was a session channel:**

- `test/test_compiler.ml:3502` `test_srec_pingpong_loop_typechecks` —
  `let _ = ch2` on a `Chan(Client, PingLoop)` still at Send/Recv.

That is the documented mid-protocol-drop leniency, not a real leak, so the
`TChan` exclusion above is the right resolution rather than a weakening of the
new rule. It is now pinned as `accept/t284`, so the exemption is a corpus fact
instead of an implementation detail.

Everything else: **zero** sites. No stdlib module, no `test/native` program, no
existing corpus fixture relied on the hole — `accept/t207`'s `let _ = sink(s)`
discards an `Int` result and is untouched, and the choreography guide and the
`cluster_ap_hosted*` fixtures had already moved to `take_closed`. **No existing
fixture changed sides.**

## Fixtures

- `reject/t283_linear_opt_in_wildcard_discard.march` — the witness the todo
  asked for: `fn launder(linear val : v) : Int do let _ = val  0 end`, whose
  never-used and used-twice checks both pass.
- `accept/t284_linear_wildcard_session_chan_midprotocol.march` — the exemption.

`specs/lang/types/INDEX.md`: 400/400 → **402/402 (168 accept, 234 reject)**,
all three count sites plus a table row each.

## Also changed

- `specs/lang/linear-types.md` and its drifted twin `docs/linear-types.md`:
  the `` **`_` can't discard one.** `` bullet now says the rule holds however
  the value became linear, and names the session-endpoint exemption.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`.

## Verification

`dune build --root .`; `scripts/run-tests.sh -q compiler|stdlib|codegen`;
`dune build --root . @types-check --force` (402 passed, 0 failed);
`scripts/check-docs.sh`; `scripts/two-node.sh stream` and `cluster_ap_hosted`.
The four probes above now read exit 0 / 1 / 1 / **1**.
