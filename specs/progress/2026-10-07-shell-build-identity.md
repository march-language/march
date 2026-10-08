# Shell: refuse inputs that reach code differing from the node's build (R5.4)

Logged 2026-10-07 (observe plan R5.4, design correction C2).

The plan's R5.4 compared the node's per-function `impl_hash`es with the
client's for the boundary functions a fragment calls through dispatch. The
shell as built sends self-contained fragments: each carries its own copy of
everything it runs. So there are no dispatch calls into the node, and the
client could not reproduce `impl_hash`es anyway. Those come from the node
build's fully optimised TIR, a pipeline the shell never runs.

What can still go wrong when the operator's checkout differs from the
node's build:
- the fragment runs a different version of a function than the node does,
  and its answers are not the node's;
- the two number a type's constructors differently, so a value built in the
  fragment and read by the node (an actor message), or the other way round,
  decodes as the wrong constructor.

## What changed

Identity is decided on the source (`lib/jit/shell_ident.ml`):

- **One hash per top-level declaration,** over its text from its own start
  to the next declaration's start (or the end of its module or file). A
  multi-clause fn's later clauses count, whatever span the merged
  declaration carries. Each module also has a header hash over its imports,
  aliases, `needs` and externs, which change how names resolve.
- **Each variant type's constructor tags,** as `Llvm_toplevel.variant_ctor_tags`
  numbers them for the emitted type list.
- **The node's build:** a `--hot-reload` native build embeds the table as
  `__march_shell_ident`, and the shell listener serves it with the `IDENT`
  verb. The declaration table's digest is in the CAS key (`sident:`), since a
  comment edit changes it without changing the TIR.
- **The client:** it computes the same table from its source when a session
  starts and summarises any differences on stderr.
  - For each input, it maps the fragment's final functions to source
    declarations by provenance span (`Provenance.effective_span`, falling
    back to the `$`-stem). Each of those declarations, and its module's
    header, must hash the same as on the node.
  - So must every type the fragment's code mentions, and so must that
    type's constructor tags.
  - Otherwise the input is refused before clang runs, with up to 8
    differences named. Inputs reaching only unchanged code still run.
  - A node without the table (built before this) gets a warning, and its
    inputs are not checked.

## Tests

`test/dune` `native_shell_skew.out`: a node built from
`test/native/shell_node.march`, and a client using
`test/native/shell_node_skew.march`, whose `evens` body and `Shade`
constructor order differ.
- The session summary names both.
- `evens(4)` and `Main.evens(3)` are refused ("evens differs").
- `List.length([Dark, Light])` is refused, naming both tag numberings.
- Inputs not reaching them run.

The existing session test (identical source on both sides) reports no
difference.

## Limits

- **Granularity is the declaration's source text.** A comment edit inside a
  reached function refuses inputs that reach it.
- **The table covers every stdlib declaration.** It is 177 KB (about 4,400
  entries) in the test node's 880 KB `--hot-reload` binary, and about 236 KB
  of base64 sent once per session. Compressing it, or sending per-module
  digests first, would shrink both.
- **Compiler skew is caught only where it changes constructor tags.**
