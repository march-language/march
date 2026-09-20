# Message labels on protocol steps: implementation spec

Implements [[2026-09-20-choreography-message-labels]] (P2, the top finding of the UX
pass). A protocol step may name its message; every generated name then uses that name
instead of `Msg_<From>_<To>_<k>`.

```march
@[endpoints]
protocol Stream do
  loop do
    item: Prod -> Cons : Int
    choose by Cons:
      more -> Cons -> Prod : Bool
      done -> Cons -> Prod : Bool
              stop
    end
  end
end
```

gives `Stream_Prod.send_Item`, `Stream_Cons.recv_Item`, `Stream_Cons.S_recv_Item`,
`Stream_Cons.await_Item`, `Got_Item`, `Stream_Msg.Item(Int)`, `leave_recv_Item`.
Unlabelled steps keep today's names exactly, so no existing program changes.

## Concurrent work

[[2026-09-20-crash-branches-implementation]] is built at the same time in the same
grammar and generator. It adds NEW constructors (`ProtoMayCrash`, `ProtoCrashOr`) and
never changes `ProtoMsg`'s shape. This work changes `ProtoMsg`'s shape and nothing else
in the AST. Keep to that split, and keep parser changes to the one alternative below.

## Files

**Parser** (`lib/parser/parser.mly`, `protocol_step`, ~948-963): one new alternative,
`lower_name COLON upper ARROW upper COLON ty` -> `ProtoMsg (a, b, ty, Some label)`. The
existing message alternative yields `ProtoMsg (a, b, ty, None)`. `stop` is a bare
`lower_name` in the same rule; a label is a `lower_name COLON`, so there is no ambiguity,
but check the menhir conflict count stays at the baseline (11) with `dune build --root .
@grammar-check --force` (read the log; the alias without `--force` is an empty check).
Labels are lowercase like branch labels; `capitalize` gives the constructor.

**AST** (`lib/ast/ast.ml`): `ProtoMsg of name * name * ty * name option`. The compiler
then lists every match on `ProtoMsg` (typecheck.ml's `DProtocol` checks and
`check_unreachable_after_loop`, `typecheck_session.ml`'s `project_steps`,
`desugar_endpoints.ml`'s `annotate`/`fingerprint_of`/`check_payload_codecs`/others, the
LSP's walkers under `lsp/lib`, `lib/search` if it renders protocols, the AST printer).
Fix each; a label is ignored everywhere except `annotate`. Grep `ProtoMsg` across `lib`,
`lsp`, `bin`, `forge`, `test` before building, so the list is known up front.

**Generator** (`lib/desugar/desugar_endpoints.ml`, `annotate` ~126-163): a labelled
message's constructor is `capitalize label` (as a branch head's is). Rules and errors,
each with a fixture:
1. two labels that capitalise to the same constructor in one protocol, or a label equal to
   a branch label, is the existing "the label `X` is used for two messages with different
   payload types" if the payloads differ; if the payloads are the same, it is ALLOWED and
   the two steps share a constructor (as two branch heads with one label do today) --
   document this;
2. a label on a `choose` branch's head message (`more -> item: Cons -> Prod : Bool`) is an
   error: "the branch label `more` already names this message";
3. a label whose capitalised form starts with `Msg_` is an error (it would collide with a
   synthesised name); say so.

The fingerprint (`fingerprint_of`) must include the label (`ty_key` line: use the ctor
name, which it already does through `AMsg`'s ctor), so renaming a step changes the
fingerprint.

**LSP** (`lsp/lib`): if hover/completion renders protocol steps, show the label. Do not
add features.

**Docs**: `docs/choreography.md` + `specs/lang/choreography.md` (twins): the naming rule
as a table in "What the compiler generates" (labelled step -> `Label`; unlabelled ->
`Msg_A_B_k`; branch head -> its label), and switch the guide's `Fan` and `Stream`
examples to labelled steps so every later signature in the guide reads `S_recv_Number`
rather than `S_recv_Msg_A_C_1` -- update every code block that names a generated
function, and re-check that the guide's twin stays identical. `specs/lang/surface-syntax.md`
gets the step form. CHANGELOG under Added.

## Tests

- `test/test_endpoints.ml`: the module-shape test with a labelled protocol (function
  names), `bad_desugar` for errors 2 and 3, an `ok` for a shared label with equal
  payloads, and one asserting the unlabelled names are byte-identical to before (take the
  existing `stream` fixture's generated names as the oracle).
- `specs/lang/grammar/parse/` a labelled protocol; `specs/lang/grammar/reject/` a label
  in the wrong place (`Prod -> item: Cons : Int`). Update that corpus's INDEX counts.
- `specs/lang/types/accept/` a labelled `@[endpoints]` protocol with a role written
  against the new names; reject fixtures for errors 2 and 3. INDEX counts (three sites);
  mirror rejects in march-lean after merge.
- One two-node scenario converted to labels, e.g. copy `test/two_node/stream` to
  `test/two_node/stream_labelled` with `item:`; goldens unchanged except nothing (output
  does not mention names). Precompile nodes in scenario.sh.
- `test/run_snapshots.exe`: unchanged.

## Out of scope

Dropping the `_1` suffix for unlabelled single messages (renames everything); labels on
`loop` or `choose` themselves.
