`[P2]` Logger.format_logfmt does not escape backslashes or newlines and leaves values containing `=` unquoted (2026-11-11)

`format_logfmt` escapes only `"`. A message or value ending in a backslash produces `\"`, which a logfmt reader takes as an escaped quote, so the string never closes. A newline in the message or in a field value is written raw and splits the record into two lines, which lets logged user input forge a log line. A value containing `=` is not quoted.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let e = Logger.LogEntry(Logger.Info, "back\\slash end\\", 0, "", [Logger.LogField("a", Logger.s("x\ny")), Logger.LogField("b", Logger.s("k=v")), Logger.LogField("c", Logger.s("tail\\")), Logger.LogField("d", Logger.s("q\"\\"))])
  println(Logger.format_logfmt(e))
  let e2 = Logger.LogEntry(Logger.Info, "line1\nline2", 0, "", [])
  println(Logger.format_logfmt(e2))
end
end
```

Expected: one line, with `\\`, `\n` written as escapes and `b="k=v"`

Actual (interpreted / compiled): `level=info ts=0 msg="back\slash end\" a=x` + newline + `y b=k=v c=tail\ d="q\"\"` / same

Source: `format_logfmt` and `fields_to_logfmt` (`quote_if_needed`) in stdlib/logger.march.
