`[P2]` Four hand-written JSON string escapers beside `Json`'s, and each misses bytes (2026-11-23)

From reading the source; not run.

`Json` has the full escaper (`escape_of` / `escape_str`, stdlib/json.march lines 450 and 486), but
it is private, so other modules wrote their own:

| Where | Escapes | Misses |
|---|---|---|
| `Channel.json_escape` (stdlib/channel.march:449) | `\` and `"` | newline, CR, tab, every control byte |
| `Presence.json_escape_pr` (stdlib/presence.march:356) | `\` and `"` | the same |
| `Logger.json_escape` (stdlib/logger.march:706) | `\`, `"`, `\n`, `\r`, `\t` | other control bytes (tracked in 2026-11-11-logger-json-nan-inf.md) |
| `json_escape` in forge/tasks/notebook_server.march:50 | not read in detail | not verified |

A topic, event or presence key containing a newline therefore produces a frame that is not valid
JSON. `Json.escape_of` itself writes control bytes below 0x20 raw
(2026-11-11-json-control-bytes-raw.md), so the fix order matters.

Fix: fix `Json.escape_of` first, export one escaping function from `Json`, and replace the four
copies with calls to it. Check that `Logger` can depend on `Json` in the stdlib load order (not
verified). A round-trip property per producer (`Json.parse` of the output is `Ok`) with a string
generator that includes control bytes keeps it fixed.

Found 2026-11-23 while reading the serializers for
specs/plans/2026-11-23-pre-1.0-bug-first-plan.md (unit U11).
