`[P2]` # A stdlib parse error is reported as "Unknown module"

Filed 2026-09-02, from adding `stdlib/session.march`.

## The defect

`bin/toolchain.ml:494` catches `March_parser.Parser.Error` while loading a
stdlib file, prints one line to stderr —

```
[stdlib] parse error in .../stdlib/session.march at line 26 col 2
```

— and **returns `[]`**, so loading continues with that module silently
absent. The program then fails to typecheck with

```
Unknown module `Session`.
```

which points nowhere near the cause. The stderr line is easy to miss (it is
not a diagnostic, has no `-- ERROR --` banner, and is emitted before the
program's own diagnostics), and in this case it took a private-`HOME` run to
notice it at all, because the first suspicion was the shared `~/.cache/march`
tcenv cache.

## What triggered it, which is its own small wart

A `doc` string is only accepted before a `fn`/`pfn`. Before a `type` or a
`proof cap` it is a **parse error**:

```march
mod D1 do
  doc "a record"
  type T = { x : Int }     -- parse error
end
```

That is a plausible thing to write (every stdlib type would benefit from one),
and the parser's own message for it in a user file is the generic "I got stuck
here". In a stdlib file it becomes the "Unknown module" above.

## Acceptance

- A stdlib file that fails to parse is a **hard, banner-formatted error** naming
  the file and position, not a skipped module. There is no situation in which
  silently continuing without a stdlib module is what the user wants, and the
  manifest test (`Stdlib_manifest_test`) already treats an unlisted module as a
  correctness bug for representation reasons; an unparseable listed one is
  worse.
- Separately, either accept `doc` on `type`/`proof cap` declarations, or reject
  it with a message that says so ("`doc` goes before a function; use a `--`
  comment here").

---

## Resolution (2026-09-08)

Both acceptance items are done.

### 1. An unparseable stdlib file is now fatal

`bin/toolchain.ml` no longer prints one unbannered stderr line and returns `[]`.
It renders the real parse error through `Errors.render_parse_error` — the same
banner renderer user files get, naming the file and the position — then exits 1,
with a trailing line noting that a stdlib source file failing to parse is a
compiler-installation problem rather than a fault in the user's program. The
`ParseError (msg, hint, _)` case is handled alongside the bare
`Parser.Error` case, so a parser rule that raises a *specific* message (such as
the new one below) keeps that message instead of falling back to the generic
"I got stuck here".

Verified against a private stdlib copy via `MARCH_STDLIB`, with a clean copy as
the control:

```
$ MARCH_STDLIB=<clean copy>  march hello.march      # control
hi                                                   exit 0

$ MARCH_STDLIB=<copy with a `doc` before a `type`>  march hello.march
-- ERROR -- .../stdlib_broken/uri.march

I got stuck here:

22 |   type URI = URI(String, String, Option(Int), String, String, String)
       ^^^^

This is a stdlib source file, so this is a compiler-installation problem
rather than something wrong with your program.
                                                     exit 1
```

Previously that same perturbation produced `Unknown module \`URI\`` from the
typechecker plus one easy-to-miss stderr line.

### 2. `doc` on `type` / `proof cap`: rejected with a message that says where it goes

**Chose rejection over acceptance, because rejection is by far the smaller
change.** Accepting would require a doc slot to put the string in, and neither
`DType` nor `DProofCap` has one (`lib/ast/ast.ml:160`, `:177`) — `fn_doc` is a
field of the *function definition* record. Adding one means changing both
constructors and every construction and match site, then threading the value
through desugar, typecheck, doc generation and LSP hover, and answering design
questions this todo does not pose (does a type's doc string render in the
generated stdlib HTML? does hover show it?). That is a cross-cutting AST change,
not a diagnostic fix. Rejection is four grammar productions.

`lib/parser/parser.mly` now has explicit `decl` rules for `DOC STRING TYPE`,
`DOC STRING PTYPE`, `DOC STRING OPAQUE` and `DOC STRING PROOFCAP`, all raising:

```
`doc` goes before a function; use a `--` comment here.

hint: `doc "..."` attaches a doc string to a `fn` or `pfn`. Type declarations
      don't carry one — write `-- ...` on the line above instead.
```

The rules match the declaration's **keyword only**, not the whole `type_decl` /
`proof_cap_decl` nonterminal. That matters: the nonterminal spelling costs 11
extra shift/reduce conflicts, while erroring on the keyword needs no lookahead
past it because the action raises rather than reduces.

**Conflict-neutrality was measured, not assumed.** A `dune build` on the
unpatched grammar reported no conflicts at all, which was a *shared-dune-cache
hit* printing nothing — not a clean grammar. Running menhir standalone on both
versions shows the grammar already had 11 shift/reduce conflicts (all in
`LET STAR simple_pattern COLON upper_name` / `LPAREN`, unrelated to `doc`), and
that the patched grammar has the same 11: diffing the conflict bodies is
identical, with only the state *numbers* shifted by 4 for the 4 added
productions.

Verified: `doc` before `type` and before `proof cap` each exit 1 with the
message above; `doc` before a `fn` still parses and exits 0.

`scripts/run-tests.sh -q` passes.

### Not changed

The caret for the new message lands on the *declaration* rather than on the
`doc` line, because `bin/main.ml`'s `ParseError` handler discards the position
carried in the exception and re-derives one from the lexbuf. That is
pre-existing and shared by every `error_raise` site; changing it is a separate
change to parse-error rendering in general.
