`[P2]` `Json.to_string` writes NaN and infinite floats as `nan` and `inf`, which is not JSON (2026-11-23)

`Json.to_string`'s `Number` arm (stdlib/json.march, about line 539) falls through to
`float_to_string`, so a non-finite float is written as a bare word. JSON has no such token, and
`Json.parse` cannot read the output back.

Repro (interpreted and compiled print the same):

```march
mod Jn do
  needs IO.Console
  fn main() do
    println(Json.to_string(Json.Number(Math.sqrt(0.0 -. 1.0))))
    println(Json.to_string(Json.Array([Json.Number(Math.exp(1000.0))])))
  end
end
```

Actual: `nan` and `[inf]`. Expected: valid JSON on both lines.

`Logger.format_json` has the same bug and its own todo
(2026-11-11-logger-json-nan-inf.md). Decide the policy once for both (`null` is what most
encoders write; refusing with an `Err` would change `to_string`'s type) and fix them in one
change, with the escaping fix in 2026-11-11-json-control-bytes-raw.md. A round-trip property
over a generator that produces non-finite floats would have found it.

Found 2026-11-23 while reading the serializers for
specs/plans/2026-11-23-pre-1.0-bug-first-plan.md (unit U11); confirmed by running the repro on
a build of `4744a0830`.
