# `[P2]` Linearity: a `_` wildcard silently discards a linear value

Filed 2026-09-13 from the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 3).

## The hole

Binding an `always_linear` value to `_` drops it with no diagnostic. A named
binder that is never used is rejected, including one spelled `_s`, so the
wildcard is the one spelling that gets around must-use.

```march
mod W do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  fn run(k : S1 -> Int) : Int do k(S1(1)) end
  fn main(c : Cap(IO.Console)) do
    let _ = S1(1)                              -- accepted
    let (a, _) = (S1(2), S1(3))                -- accepted; S1(3) is gone
    println(int_to_string(sink(a) + run(fn _ -> 0)))   -- accepted
  end
end
```

## Measured (main `8eb0d7ee`)

| shape | result |
|---|---|
| `let _ = S1(1)` | **accepted** |
| `let _s = S1(1)`, unused | rejected, "The linear value `_s` was never used." |
| `let (a, _) = (S1(1), S1(2))` | **accepted** |
| `run(fn _ -> 0)` against `S1 -> Int` | **accepted** |
| `match st do _ -> 0 end`, `st : S1` a param | **accepted** (the scrutinee counts as the use) |
| `match st do S1(_) -> 0 end` | accepted (correct: the discarded payload is `Int`) |
| `fn g(_ : S1)` (top-level) | parse error ("I got stuck here"), so not reachable |

## Cause

`PatWild` introduces no binding (`infer_pattern` returns `[]`), so there is
nothing for `ELet`'s `auto_lin` or `bind_pattern_bindings` to promote, and
nothing for a scope close to find. A lambda's `_` parameter is parsed as a
param literally named `"_"` (`parser.mly`, `param: UNDERSCORE`), which
`bind_lam_param` does promote. It just can never be referenced, and no
must-use runs on lambda params at all (see
[[2026-09-10-linear-lambda-parameter-not-must-use]]).

## Decision: `_` on a linear value is an error

March has no destructors, so a discarded linear value is a leak, not a
cleanup. Rust's `let _ = file` runs `drop`; nothing analogous happens here.
The wildcard is also the spelling a user reaches for when a callback's
argument "doesn't matter", which is exactly the case a linear API exists to
forbid.

Affine values stay discardable by `_`. That is what affine means, and
session-channel endpoints (tracked affine) rely on create-and-drop.

## Design

One check, at the point a wildcard meets a type:

- **`let` / pattern wildcards.** In `infer_pattern`'s `PatWild` arm the
  expected type is already recorded into `type_map`. The type is not final
  there, so do the check where the bindings are applied: in the
  `ELet`/`infer_block` let path and `bind_pattern_bindings`, walk the pattern
  alongside its resolved type and report every `PatWild` whose type
  `resolves_always_linear` or is `TLin (Linear, _)`. That covers
  `let _ = …`, tuple and constructor sub-patterns, and match-arm patterns.
- **Lambda `_` params.** In `bind_lam_param`, when `p.param_name.txt = "_"`
  and `effective_lin = Linear`, report immediately instead of binding.
  Unannotated `fn _ ->` in **infer** mode only learns its type later: fold it
  into the deferred path of
  [[2026-09-13-linear-unannotated-parameter-never-promoted]] rather than
  special-casing it here.

**Match-arm wildcards need care.** `match st do S1(_) -> 0 end` on
`always_linear type S1 = S1(Int)` destructures the linear shell and discards
an `Int` payload, which is fine. The check is on the **wildcard's own type**
(`Int`), never on the scrutinee's. A bare `_ -> 0` arm whose scrutinee is
linear discards the whole value, and must be caught. Get both from the
pattern walk, not by special-casing arms.

Message:

```
This `_` discards a linear value of type `S1`.
Linear values must be consumed exactly once. Bind it to a name and pass it
to something that consumes it.
```

## Tests

Reject witnesses (RED on `main` first): `let _ = S1(1)`; `let (a, _) =
(S1(1), S1(2))` with `a` consumed; check-mode `run(fn _ -> 0)`; a
`match st do _ -> 0 end` on a linear `st`. Expected substring: `discards a
linear value`.

Accept witnesses: `match st do S1(_) -> 0 end`; `let _ = sink(s)` (the
wildcard's type is `Int`); `let _ = ch` on a session endpoint (affine);
`fn _ -> 0` against `Int -> Int`.

Blast radius: `scripts/types-oracle.sh` over the corpus, plus a grep of
`stdlib/` and `test/` for `let _ =` on calls returning `Handle` or an
`@[endpoints]` state. Any hit is either a real leak (record it) or a
mistake in the type walk.

---

## What shipped (2026-09-13)

`infer_pattern`'s `PatWild` arm reports each wildcard and its type variable to
a sink installed by `with_wildcards`; after the caller unifies the pattern,
`check_wildcard_discards` reports those whose type is linear (`is_linear_ty`:
`TLin Linear` except channels, or an `always_linear` `TCon`). Wired at the
block `let`, the tail `let`, `let?`, `let*`, and both match paths. A `_`
lambda parameter is checked in `bind_lam_param`.

Two things changed from the design above while building it:

- **Not `type_map`.** The design read wildcard types back from `type_map` by
  span. Desugar-generated wildcards share spans (`desugar_endpoints.ml` gives
  every generated wildcard the protocol's span), so a lookup can return a
  different wildcard's type. The sink carries the wildcard's own variable.
- **Diverging arms are exempt now, not in step 7.** `path_diverges` (tail
  call to a builtin in "Diverging primitives", or an `if`/`match`/`cond` all
  of whose paths diverge) landed here, because `match st do _ -> panic(…) end`
  is the natural spelling of "give up" and must stay legal. Step 7 reuses it.

Witnesses: `reject/t203`–`t206`, `accept/t207`, five unit cases, each proved
able to fail (report disabled: four rejects fail; divergence exemption
removed: the accept case fails). `types-oracle`: no pre-existing fixture
moved. The four `test/session` goldens are byte-identical.
