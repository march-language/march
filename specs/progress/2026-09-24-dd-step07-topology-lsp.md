# Distributed deploys, build step 7: the topology file in the LSP

**DONE 2026-09-24.** The "LSP support for the TOML" item of
[../todos/2026-09-22-dd-step07-topology-file.md](../todos/2026-09-22-dd-step07-topology-file.md);
the static half is [2026-09-22-dd-step07-topology-file-static.md](2026-09-22-dd-step07-topology-file-static.md).
Plan: [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
section 4 (the `forge topology check` paragraph) and II.6.

## One implementation: the LSP links `march_forge`

`forge/lib/topology.ml` was already a module of a library, `march_forge`, that the
compiler binary links (`bin/topology_gen.ml`). The LSP now links it too
(`lsp/lib/dune`) rather than moving code to `lib/`: nothing is copied, and the parse,
the overlay merge, the checks, the project walk and the protocol facts the editor uses
are the functions `forge topology check` calls. Three small additions to
`topology.ml`, none changing forge's behaviour:

- `index.sites`: the span of each indexed fn, actor and protocol NAME, keyed by kind
  and qualified name (`Topology.site`), recorded where the index already names them,
  so go-to-definition lands on the declaration the check resolved the string to.
- `parse_source ~path src`: `parse_module` minus the file read, which it now calls.
- `index_project_with ~parse ~root`: `index_project` with the per-file parse supplied;
  `index_project` is it with `parse_module`. The LSP passes a parse that reads an open
  buffer instead of the file (digest-cached).

No `forge/lib/cmd_*.ml` or `forge/bin` change.

## `lsp/lib/topology_doc.ml`

- **Recognition** by basename: `topology.toml`, `topology.<env>.toml` (non-empty env).
  The server routes these before `analyse_and_cache`, so a topology file is never
  parsed as March, whatever language id the client sends.
- **Diagnostics** are `Topology.of_strings` (the same parse and merge as `load`, from
  buffer text) then `Topology.check` over the buffer-aware index. The message is
  forge's `msg` verbatim, the range the text of the line forge names (first non-blank
  byte to the last before a comment; line 0 maps to the first line), severity
  Error/Warning, source `forge topology`. An overlay shows the `--env <env>` run's
  diagnostics in the overlay. The base shows the plain run's plus, for every overlay
  on disk or open, the `--env` run's in the base file, deduplicated, the env-only
  ones with source `forge topology --env <env>`. This is the only judgement call: a
  `place.count` above the host count and an unknown `place.on` label are reported by
  forge at the ROLE's line in the base, and exist only once an overlay supplies hosts.
  A diagnostic in no topology file (a `.march` that does not parse) goes on the base's
  first line with forge's text.
- **Buffers**: `march_buffers` holds each open `.march` text, set on open/change and
  dropped on close, kept separately from the analysis cache because
  `analyse_resilient` keeps the last GOOD source for a buffer that stops parsing,
  where forge would see the broken file.
- **Republishing**: a topology open/change republishes every open topology document
  in its directory; a `.march` open/change/close republishes every open topology
  document whose directory contains the file (`dependents_of`), via
  `PublishDiagnostics` to the URI the topology document was opened under.
  `didChangeWatchedFiles` republishes them all. Pull diagnostics
  (`textDocument/diagnostic`) answer the same list.
- **Cursor context** (`context_at`): a lexical scan tracking section, the stack of
  inline tables and arrays with the key that holds each, and whether a key or a value
  is expected. It returns the string under the cursor with its key path
  (`[role; "body"]`, `["serves"]`, `["hosts"; "labels"]`), a bare key being typed, or
  a section header. It is a scanner, not `Toml`, because completion runs on
  half-typed text (an unclosed string, a key without `=`) that `Toml` rightly rejects.
- **Definition**: `body`/`start` → `Topology.site `Fn`, `actor` → `` `Actor``; a
  `"Protocol.Role"` string (a `[roles]` key, a `serves`/`initiates` entry) splits at
  the last dot like forge: the protocol part → `` `Protocol`` (found by
  `find_protocol`), the role part → its `role R needs` line, else its first message.
  Target ranges are remapped to UTF-16 against the target file.
- **Completion**, replacing the whole string content so dotted names insert whole:
  functions (`body`, `start`), actors (`actor`), `Protocol.Role` from `proto_roles`
  (`serves`, `initiates`, and quoted at a new `[roles]` key), host labels from every
  topology file (`place.on`, `labels`); outside strings the `known_*_keys` for the
  section or inline table; in a header the section names and the base's and
  overlays' pool names (`[pool.` in an overlay).
- **Hover** on a role string: the grant (`Desugar_endpoints.grants_of`, the function
  the generator uses), the body type `(Cap(Session.Live), Cap(P)..., <P>_<R>.Entry) ->
  <P>_<R>.Yield` as `run_module` declares it (spelled with the `Entry` alias), and the
  step-3 shape of a topology-bound body, `f(env, s, c1..ck, st)`. The type string is
  rendered here, not taken from the typechecker: the generated modules exist only
  after desugaring a file that declares the protocol, which the topology document
  does not have open. It is pinned against the documented shape by the tests.

## Tests

- `lsp/test/test_lsp_topology.ml`, 16 cases in `test_lsp` ("topology file"), over a
  scratch project on disk. The diagnostic cases compute forge's own answer
  (`Topology.load` + `index_project` + `check`, what `forge topology check [--env]`
  runs) over the same files and require every forge diagnostic in the document to be
  on the LSP's list with the same line, severity and text: unknown key (range pinned
  too), unbound served role, unknown label and `count` above hosts under an overlay
  (with the `--env prod` source), the unlabelled-step warning, an overlay's own
  diagnostics and nothing of the base's, a malformed line. The acceptance case edits
  the `.march` BUFFER (rename `serve_one`), sees the unbound-body error appear at the
  role's line, undoes it, breaks the buffer (forge's could-not-parse warning), and
  closes it (back to the disk). Definition on `body`/`actor`/`start` and on both parts
  of role strings; completion in strings (including an unclosed one and the edit
  range), of keys per section, of pool names in an overlay header; hover with and
  without a grant.
- `lsp/test/test_jsonrpc.ml`, "topology.toml: diagnostics follow a .march edit": the
  real server over stdio opens `topology.toml` (languageId `toml`), answers
  definition, completion and hover on it, publishes no March parse error for it, and
  after a `didChange` to `shop.march` publishes the unbound-body error under the
  topology document's URI; pull diagnostics agree.
- Perturbations, both red then restored green: publishing forge's line unshifted
  (off by one) fails 8 of the 16 in-process cases; dropping the republish after a
  `.march` `didChange` fails the wire case (timeout waiting for the publish).

The wire fixture has no `@[endpoints]` attribute: the topology side only parses, and
the server's own March analysis of a buffer with generated endpoint modules took ~28 s
against ~3 s without (measured on the same box, with and without a topology document
open, so not caused by this change).
