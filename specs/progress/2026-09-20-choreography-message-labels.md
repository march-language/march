# Choreography: a protocol step can name its message

Closes the `[P2]` item filed 2026-09-20 by the choreography UX pass (the top
finding): every generated name carried a synthesised message name
(`Stream_Cons.S_recv_Msg_Prod_Cons_1`, `Got_Msg_Prod_Cons_1`), and plain
messages had no way to supply one although branch heads did (through the
`choose` label). Implementation plan: `specs/2026-09-20-message-labels-implementation.md`.

## What landed

A message step may carry a lowercase label, `item: Prod -> Cons : Int`. The
constructor is its capitalisation, exactly as a branch label's is, and every
generated name uses it: `Stream_Msg.Item(Int)`, `Stream_Prod.send_Item`,
`Stream_Prod.S_send_Item`, `Stream_Cons.recv_Item`/`recv_Item_or`,
`Stream_Cons.S_recv_Item`, `Stream_Cons.await_Item`, `Got_Item`,
`leave_recv_Item`. Unlabelled steps keep `Msg_<From>_<To>_<k>` byte for byte
(pinned by a test), so no existing program changes.

- **Parser** (`lib/parser/parser.mly`, `protocol_step`): one new alternative,
  `lower_name COLON upper_name ARROW upper_name COLON ty`. The bare `lower_name`
  alternative (`stop`) is told apart by the COLON. Menhir conflicts: 11 before,
  11 after.
- **AST** (`lib/ast/ast.ml`): `ProtoMsg of name * name * ty * name option`.
  Every match site updated, the label ignored everywhere but the generator:
  `lib/tir/lower.ml`, `lib/eval/eval.ml`, `lib/typecheck/typecheck.ml`,
  `lib/typecheck/typecheck_session.ml` (three sites), `lib/format/format.ml`
  (prints the label back), `lib/dump/ast_json.ml` (a `label` field, present only
  on a labelled step, so unlabelled JSON is unchanged), and
  `lsp/lib/code_actions_ast.ml` (the protocol scaffold's comment names the label).
- **Generator** (`lib/desugar/desugar_endpoints.ml`, `annotate`): the ctor of a
  labelled step is `capitalize label`. Rules:
  1. A name shared by two steps: allowed when the payloads agree (one
     constructor in `<P>_Msg`), the existing "used for two messages with
     different payload types" error when they differ. What the plan called "as
     two branch heads with one label do today" turned out to be narrower than
     it sounded: transitions are named after the message (`send_Item`), so a
     role that takes BOTH steps got two functions of one name, the second
     silently shadowing the first (branch labels across two `choose`s had the
     same hole). `role_module` now reports it: "two steps A takes are named
     alike, so the role module would define `send_Ping` twice ... Rename one of
     them." The event API's own "received in two states with different
     continuations" check already covered the receiving side. So the precise
     rule is: share a name when the payloads agree and no single role takes
     both steps.
  2. A label on a `choose` branch's head message is an error: the branch label
     already names it.
  3. A label whose capitalised form starts with `Msg_` is an error: it could
     collide with a synthesised name.
  The fingerprint already keyed on the ctor, so renaming a step changes it
  (tested).

## Tests

- `test/test_endpoints.ml`: `unlabelled_names_pinned` (the unlabelled
  `stream`'s Prod and Cons function lists, literal), `labelled_shape` (the
  labelled twin's lists equal the pinned ones with `Msg_Prod_Cons_1` replaced by
  `Item`), `label_changes_fingerprint`, `labelled_roles_ok`,
  `label_on_branch_head`, `label_msg_prefix`, `shared_label_ok`,
  `shared_label_two_payloads`, `shared_label_one_role`.
- Grammar corpus: `parse/p38_protocol_labelled_message_step`,
  `reject/r17_protocol_label_after_arrow` (`Prod -> item: Cons : Int`).
- Typing corpus: `accept/t270_endpoints_labelled_steps` (t190 labelled, roles
  written against the new names), `reject/t271_endpoints_label_on_branch_head`,
  `reject/t272_endpoints_label_msg_prefix`. The rejects need mirroring in
  march-lean after merge.
- Two-node: `test/two_node/stream_labelled`, the `stream` scenario with `item:`,
  nodes precompiled in `scenario.sh`; goldens unchanged (nothing printed names a
  generated function).
- TIR snapshots: unchanged.

## Docs

`docs/choreography.md` and `specs/lang/choreography.md` (twins): the naming
rule as a table under "What the compiler generates"; the guide's `Fan` and
`Stream` examples use labelled steps, so every later signature reads
`S_recv_Number` rather than `S_recv_Msg_A_C_1`. `specs/lang/surface-syntax.md`
gets the step form. CHANGELOG under Added.

## Found on the way, not fixed here

A `choose` branch cannot hold a second message step on its own line: the token
filter's arm-boundary scan reads the step's `->` as a new arm and the parser
gets stuck at the receiver (`go -> A -> B : Int` followed by `A -> B : Int` on
the next line). Pre-existing and independent of labels (a labelled second step
fails the same way); a `loop do` or `choose by` on that line parses, since `do`
and the colon-less scan stop the lookahead. Filed as its own item.

## Out of scope

Dropping the `_1` suffix for unlabelled single messages (renames everything);
labels on `loop` or `choose` themselves.
