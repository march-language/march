# Logger v2 — design

**Status:** In progress.
**Date:** 2026-04-14
**Predecessor:** `stdlib/logger.march` (v1) — `println`-with-severity
plus a flat `(String, String)` context list.  Useful for quick scripts;
not viable for services.

## Goals (in priority order)

1. **Structured fields with rich values.**  A log entry's metadata is
   not just `Map(String, String)`.  It carries `Int`, `Float`, `Bool`,
   `Atom`, `String`, and `Null`.  This lets formatters emit a real
   `request_ms=42` instead of `request_ms="42"`, and lets aggregators
   (Datadog, Honeycomb, Loki) index them as the right type.
2. **Tracing context propagates without ceremony.**  A function deep
   in the call tree calls `Logger.info("hi")` and the resulting log
   entry already carries `trace_id`, `span_id`, `parent_span_id`, and
   any custom fields the caller layered on.  No manual threading.
3. **Pluggable appenders + formatters.**  The default appender writes
   to stderr in human-readable text; production swaps in a
   JSON-to-stdout appender for log shipping, optionally a file
   appender for redundancy, and the user can register their own
   callback (e.g., for OTLP export).
4. **Per-module level filtering.**  Set the global level to `Info` but
   debug a single noisy module without recompiling.
5. **Backward compatible with v1.**  Existing `Logger.info(msg)`,
   `Logger.with_context(k, v)`, `Logger.set_level(level)` keep
   working.  v2 is additive.

## Non-goals

- A full OpenTelemetry SDK.  We aim for *compatibility* with OTLP
  field naming when emitting JSON, but tracing/metrics export is a
  separate library.
- Per-actor isolated context.  Today's runtime context is global per
  OS process.  Per-actor context is a runtime-level change and lives
  in a separate epic.
- Sampling, rate limiting, log aggregation.

## Surface (March-side)

```march
mod Logger do

  -- ── Levels ─────────────────────────────────────────────────────────
  type Level = Trace | Debug | Info | Warn | Error | Fatal

  -- ── Field values ───────────────────────────────────────────────────
  -- Rich field values so formatters preserve types.
  type LogValue =
    | LStr(String)
    | LInt(Int)
    | LFloat(Float)
    | LBool(Bool)
    | LAtom(Atom)
    | LNull

  type LogField = LogField(String, LogValue)

  type LogEntry = LogEntry(
    Level,            -- severity
    String,           -- message
    Int,              -- unix_ms timestamp
    String,           -- module / source
    List(LogField)    -- merged context + per-call fields, in order
  )

  -- ── Convenience constructors for LogValue ───────────────────────────
  fn s(v : String) : LogValue do LStr(v) end
  fn i(v : Int)    : LogValue do LInt(v) end
  fn f(v : Float)  : LogValue do LFloat(v) end
  fn b(v : Bool)   : LogValue do LBool(v) end
  fn a(v : Atom)   : LogValue do LAtom(v) end

  -- ── Level control ───────────────────────────────────────────────────
  fn set_level(level : Level) : Unit            -- global default
  fn get_level() : Level
  fn set_module_level(module : String, l : Level) : Unit
  fn clear_module_level(module : String) : Unit
  fn level_for(module : String) : Level         -- effective level

  -- ── Context (scoped) ────────────────────────────────────────────────
  fn with_field(key : String, value : LogValue) : Unit
  fn with_fields(fields : List(LogField)) : Unit
  fn current_fields() : List(LogField)
  fn clear_context() : Unit

  -- Auto-cleaning scope: pushes fields, runs the thunk, pops on
  -- normal return AND on panic (via try_finally primitive).
  fn with_scope(fields : List(LogField), thunk : () -> a) : a

  -- ── Tracing helpers ────────────────────────────────────────────────
  -- These are convenience wrappers that store special-case keys
  -- ("trace_id", "span_id", "parent_span_id") in the field stack.
  -- Formatters that emit OTLP recognise these and place them in the
  -- correct OTLP slot.
  fn with_trace_context(trace_id : String, span_id : String,
                        parent_span_id : Option(String)) : Unit
  fn current_trace_id() : Option(String)
  fn current_span_id() : Option(String)
  fn with_span(name : String, thunk : () -> a) : a   -- generates a span_id, tracks duration

  -- ── Appenders ──────────────────────────────────────────────────────
  type Appender = Appender(String, LogEntry -> Unit)
  -- The String is a name for `remove_appender`.

  fn add_appender(a : Appender) : Unit
  fn remove_appender(name : String) : Unit
  fn clear_appenders() : Unit
  fn list_appenders() : List(String)

  -- Built-in appenders
  fn appender_stderr(format : LogEntry -> String) : Appender
  fn appender_stdout(format : LogEntry -> String) : Appender
  fn appender_file(path : String, format : LogEntry -> String) : Appender
  fn appender_callback(name : String, on_entry : LogEntry -> Unit) : Appender

  -- ── Formatters ─────────────────────────────────────────────────────
  fn format_text(entry : LogEntry) : String       -- "[INFO] msg {k=v, ...}"
  fn format_logfmt(entry : LogEntry) : String     -- "level=info ts=… msg=\"…\" k=v"
  fn format_json(entry : LogEntry) : String       -- single-line JSON, OTLP-compatible

  -- ── Logging ────────────────────────────────────────────────────────
  fn trace(msg : String) : Unit
  fn debug(msg : String) : Unit
  fn info(msg : String)  : Unit
  fn warn(msg : String)  : Unit
  fn error(msg : String) : Unit
  fn fatal(msg : String) : Unit

  fn log(level : Level, msg : String) : Unit
  fn log_with(level : Level, msg : String, fields : List(LogField)) : Unit
  fn log_in(module : String, level : Level, msg : String,
            fields : List(LogField)) : Unit       -- explicit module name

  -- ── v1 compatibility shims ─────────────────────────────────────────
  fn with_context(key : String, value : String) : Unit
    -- Equivalent to `with_field(key, LStr(value))`.

end
```

## State model

The runtime keeps two pieces of mutable state for the logger:

1. `logger_level : Int` — the global default level.  (Already exists.)
2. `logger_fields : List(LogField)` — the structured context stack.
   Replaces the old `logger_context : List((String, String))`.  v1
   `with_context` writes a `LStr` field to this stack; v2 reads/writes
   it directly.  The list is treated as a stack: most recent push is
   at the head; `with_scope` records the depth at entry and pops back
   to it on exit.

Module-specific level overrides live in a small `Hashtbl` keyed by
module name.  `level_for(module)` consults the override map first,
then falls back to `logger_level`.

Appenders live in a list; the first registered appender is called
first.  The default state has one appender — `appender_stderr` with
`format_text` — so existing behaviour is preserved.

## Backward compatibility

The v1 surface stays:

- `Logger.set_level(Level)` — unchanged.
- `Logger.with_context(key, value)` — now equivalent to
  `Logger.with_field(key, LStr(value))`.
- `Logger.clear_context()` — clears the field stack (same observable
  behaviour as before).
- `Logger.info("msg")`, `Logger.debug` etc. — unchanged.
- `Logger.log_with(level, msg, [(k, v), …])` — `[(String, String)]`
  pairs are auto-promoted to `LogField` with `LStr` values.

The default appender list is `[appender_stderr(format_text)]`, which
matches v1's "write to stderr in `[LEVEL] msg {k=v}` format" exactly.

## Tracing model

Three special field names — `trace_id`, `span_id`, `parent_span_id` —
are recognised by `format_json` and placed in OTLP's `traceId`,
`spanId`, and `parentSpanId` slots when emitting JSON.  All other
fields go into the `attributes` object.

`with_span(name, thunk)` is sugar:

```
fn with_span(name, thunk) do
  let span_id = generate_span_id()  -- 16 hex chars
  let parent  = current_span_id()
  let trace   = match current_trace_id() do
    Some(t) -> t
    None    -> generate_trace_id()  -- new root span
    end
  with_scope([
    LogField("trace_id",        LStr(trace)),
    LogField("span_id",         LStr(span_id)),
    LogField("parent_span_id",  match parent do
      Some(p) -> LStr(p)
      None    -> LNull
      end),
    LogField("span_name",       LStr(name)),
    LogField("span_start_ms",   LInt(now_ms())),
  ], thunk)
end
```

`with_scope` ensures the trace fields are popped when the thunk
returns or panics — so even if a span's body panics, the OUTER scope's
trace context is restored.

## Implementation phases

**Phase A — Structured fields and types (this commit):**
1. Add `LogValue`, `LogField`, `LogEntry` types.
2. Add `s/i/f/b/a` value constructors for ergonomic construction.
3. Add `with_field`, `current_fields`, `with_scope`.
4. Replace runtime `logger_context : (String * String) list ref` with
   `logger_fields : (string * log_value) list ref` (OCaml side).  v1
   `with_context(k, v)` becomes a thin shim.
5. Keep all existing exports working.

**Phase B — Appenders + formatters:**
1. Add `Appender` type + registry.
2. Add `format_text` (default), `format_logfmt`, `format_json`.
3. Add `appender_stderr`, `appender_stdout`, `appender_file`,
   `appender_callback`.
4. Default state: one stderr/text appender.
5. Move logger_write's stderr writing through the appender list.

**Phase C — Module-level overrides:**
1. Add `set_module_level`, `level_for`, `clear_module_level`.
2. Add `log_in(module, level, msg, fields)` — caller-provided module
   name; the regular `info`/`warn`/etc. still log under `""` (default).

**Phase D — Tracing helpers:**
1. Add `with_trace_context`, `current_trace_id`, `current_span_id`.
2. Add `with_span(name, thunk)` using the runtime's `try_finally`.
3. `format_json` recognises the trace-related field names.

This commit lands Phase A + Phase B (the minimum that lets users emit
real JSON for log shipping).  Phases C and D follow.
