`[P2]` Channel.parse does not round-trip Channel.serialize and rejects ordinary Phoenix frames (2026-11-11)

`Channel.parse` extracts fields by substring search. A string field ends at the first `"`, so a field containing a quote (which `serialize` escapes as `\"`) is cut at the backslash and `parse(serialize(m))` is not `m`. A `null` field (Phoenix clients send `"join_ref":null` on heartbeats) or a space after a colon gives `None`. The doc string lists the null and spacing limits, but the escaped-quote case contradicts its claim that it accepts what `serialize` produces.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let cm = Channel.make_msg("0", "1", "room:\"x\"", "new_msg", "{}")
  let wire = Channel.serialize(cm)
  println(wire)
  println(to_string(Channel.parse(wire)))
end
end
```
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  -- Phoenix clients send join_ref:null for pushes outside a join and for heartbeats.
  let s = "{\"join_ref\":null,\"ref\":\"1\",\"topic\":\"phoenix\",\"event\":\"heartbeat\",\"payload\":{}}"
  println(to_string(Channel.parse(s)))
end
end
```
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  -- Valid JSON with a space after each colon (what JSON.stringify(x, null, 1) or many encoders emit).
  let s = "{\"join_ref\": \"0\", \"ref\": \"1\", \"topic\": \"room:lobby\", \"event\": \"new_msg\", \"payload\": {}}"
  println(to_string(Channel.parse(s)))
end
end
```

Expected: topic `room:"x"` survives the round trip; the null and spaced frames parse.

Actual (interpreted / compiled): topic comes back as `room:\`; the other two give `None` (interpreted).

Source: `parse`, `extract_json_string` in `stdlib/channel.march`. Using the JSON module would fix all three.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
