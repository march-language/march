# Protocol parser: a `choose` branch can hold further message steps, labelled or not

Filed 2026-09-20 as `specs/todos/2026-09-20-choose-branch-second-step-parse.md` while adding
message labels ([[2026-09-20-choreography-message-labels]]); closed 2026-09-23.

```march
protocol P do
  choose by A:
    go -> A -> B : Int
          tick: A -> B : Int
          A -> B : Int
    no -> A -> B : Bool
  end
end
```

The todo reported both the plain second step (`A -> B : Int`) and the labelled one
(`tick: A -> B : Int`) failing with "I got stuck here". On origin/main at the time of the fix
only the **labelled** one still failed: the token filter already carried `ms_is_choose`
(from the crash-branch work, #540) and its `UPPER_IDENT` case in the NL handler keeps an
upper-case-led line inside the current branch. A lower-case-led line, though, went through
`lookahead_is_new_arm`, which scanned `tick : A ->`, found an `ARROW` at depth 0, and emitted
an arm separator; `choose_branch` then wanted `lower_name ARROW` and met the `COLON`.

## Fix

Shape (1) from the todo, the protocol-aware scan: `lookahead_is_new_arm` takes
`~is_choose`, and inside a `choose` a depth-0 `COLON` before any `ARROW` ends the scan as
"continuation". An arm of a `choose` is exactly `[|] label ->`, so a `:` before the arrow can
only be a labelled step. The flag is `ms_is_choose`, which is set only by `CHOOSE BY`, so
match arms, cond arms, `with ... else` arms and every other `Match` context scan exactly as
before. `parser.mly` is untouched; menhir still reports 11 shift/reduce conflicts.

## Evidence

- Grammar corpus: `parse/p40_protocol_choose_two_step_branch.march` (plain steps; already
  passing before the fix, pins the #540 behaviour) and
  `parse/p41_protocol_choose_labelled_second_step.march` (labelled steps; "I got stuck here"
  at `tick:` on origin/main). `@grammar-check`: 55 passed, 0 failed.
- Projection/typing, not only parsing (`test/test_endpoints.ml`): a `@[endpoints]` protocol
  whose `go` branch is `A -> B : Int` / `tick: A -> B : Int` / `B -> A : String` generates
  `choose_go`, `send_Tick`, `recv_Msg_B_A_1` for A and `offer_go_no`, `recv_Tick`,
  `send_Msg_B_A_1` for B; both roles driven through the branch typecheck; skipping the
  second step is rejected (`expected S_recv_Msg_B_A_1 but got S_send_Tick`). All three fail
  on origin/main (the protocol does not parse).
- `specs/lang/choreography.md` documents the multi-step branch body.
