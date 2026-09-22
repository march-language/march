# forge's TOML parser: line numbers, no silent drops, unknown-key warnings

**DONE 2026-09-22.** G4 of
[specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md).

## Before

`forge/lib/toml.ml` tracked no line numbers and parsed line by line. It:

- dropped any `key = value` line whose value failed to parse (a `Parse_error`
  caught per line);
- ignored a line with no `=` and a `[section` header with no `]`;
- ignored text after a value (`name = "a" "b"` read as `"a"`);
- could not parse an array spanning lines (dropped as "unterminated"), and
  read a trailing comma as an extra `""` element;
- kept the quotes on a quoted key (`"my-dep" = "1.0"` named a dep `"my-dep"`).

No consumer rejected an unknown key, so a misspelled `forge.toml` key was a
silent no-op.

## Now

- `parse_located : string -> (document, int * string) result` parses the
  whole document or returns the first malformed line and why. `parse` raises
  `Parse_error "line N: ..."`. Rejected: a line that is not a header, comment
  or `key = value`; an unterminated `[...]` or `[[...]]` header; text after a
  header or after a value; an unterminated string, array or inline table; an
  empty key.
- Arrays may span lines, with comments and a trailing comma. Quoted keys are
  unquoted. Inline tables and arrays of inline tables
  (`hosts = [{ host = "a", labels = ["db"] }, "b"]`) already parsed and still do.
- `document.located`: every section with its header line and every key with
  its line. Accessors `get_section_at`, `get_all_sections_at`,
  `get_string_at`, `get_table_at`, `get_string_list_at` return the line too;
  the existing accessors are unchanged.
- `check_keys ~section ~known doc` returns `(key, line)` for each unknown key.
- `Project.load_from` reports a malformed `forge.toml` as
  `forge.toml:<line>: <msg>` (it was `forge.toml parse error: <msg>`, and
  usually nothing, since the line was dropped). It **warns** on unknown keys
  in every section it reads a fixed set of keys from (`[package]`/`[project]`,
  `[ffi]`, `[ffi.rust]`, `[hot-reload]`, `[[hot-reload.env]]`, `[contracts]`,
  `[archive.task.*]`, `[patch.*]`, `[deps.*]` and the other dep-table
  sections): `forge.toml:3: warning: unknown key 'replica' in [package]`.
  Sections keyed by names (`[deps]`, `[preprocessors]`, `[js_deps]`, ...)
  are not checked. Each warning prints once per process
  (`Project.warning_sink`, a ref, is where they go).
- `forge`'s entry point turns a `Toml.Parse_error` from any other reader (a
  dependency's or archive's TOML, lint config) into `error: TOML parse error,
  line N: ...` and exit 1, instead of cmdliner's "internal error" backtrace.
  Other exceptions keep the internal-error report and exit 125.

The known-key sets were checked against the 60 `forge.toml` files under
`~/code` (bastion, forgepm, notebook, envoy, ...): none uses a key outside
them, and none uses a multi-line array.

## Deviation from the plan

The plan put `line` inside `Toml.value` and the key/value pairs. The lines
live in a parallel located view instead, because `document.sections` and the
`value` variant are matched directly by about 130 sites across forge and its
tests. A value nested inside an array or inline table has its key's line.

## Tests

forge/test/test_forge.ml, group `toml` (6 new cases): each kind of bad line
reports its number; `Project.load_from_dir` says `forge.toml:3`; unknown keys
in `[package]` and `[[hot-reload.env]]` warn with their lines and a load
still succeeds; a forge.toml using every known key is silent; the
inline-table-array round trip; a multi-line array with comments and a
trailing comma, with the header and key lines.

`dune build --root . @forge/test/runtest`: 17 test executables, all
successful (forge: 164 tests).
