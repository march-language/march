# DONE Owned-call drop fusion: a dying variable at two borrowed positions of one call

Done 2026-10-07. Closes the "known remaining gap" of
`specs/progress/2026-10-07-owned-call-drop-fusion.md` (PR #869).

## The gap was reachable

The first version handed a dying argument to an owned clone only when it
occurred once in the call. A variable at two borrowed positions kept its
post-call drop. Inside a clone that variable can be owned where the original
only borrowed it, and the drop then sits after what was a tail call in the
original:

```march
pfn mg(x : List(List(Int)), n : Int) : Int do
  match x do
    Nil -> n
    Cons(h, t) -> mf(t, h, h, n + 1)     -- h at two borrowed positions
  end
end

pfn mf(a : List(List(Int)), b : List(Int), c : List(Int), n : Int) : Int do
  mg(a, n + head0(b) - head0(c))
end
```

In the original `mg`, `h` and `t` are borrowed fields and the call keeps no
drop, so `mg`/`mf` loop (`MARCH_NO_OWNED_CALLS=1`: a 1 000 000-row walk runs).
`main`'s `mg(rows(..), 0)` is redirected to `mg$own0`, where `h` and `t` are
owned; `t` was handed (`mf$own0`), `h` was not, and after `mf$own0` was inlined
the clone contained

```
%cr = call i64 @mg$own0(ptr %t, i64 %n1)
call void @__drop$List_Int(ptr %h)
```

real recursion: the 1 000 000-row walk died with "fault in its stack guard
page (overflow)" (exit 138). A self loop of the same shape (`dd(t, h, h, n+1)`)
stayed a loop only because the self-TCO arm defers the forwarded drop to the
loop's exit (`march_tco_defer_push`, one heap entry per iteration).

## Design

Inside a clone, a dying variable at k > 1 borrowed positions of a redirected
call is handed to ALL k positions, and the caller dups it k - 1 times before
the call (`owned_call_redirect` returns the extra `EIncRC`s; they join the
call's ordinary pre-call dups). The clone owns each of those positions, and
no release is left after the call, so a tail call stays a tail call: both
fixture loops now run through a TCO back edge (`mg$own0`, `dd$own0_1_2`), and
the self loop no longer pushes onto the deferred-drop list.

Why it is sound: it is the accounting every owned call already uses. The
caller owned one reference and the call has k consumers, so k - 1 dups make
one reference per consumer, which is what `find_inc_vars` emits for a
variable at k owned positions. Each clone parameter is an ordinary owned
parameter that the clone releases (an unused one at entry, as before). The
value is shared (rc >= 2) while the clone walks it, so `Llvm_case`'s
`decrc_freed` split takes the shared path and nothing is freed while another
position still refers to it.

Not changed:

- **Original functions.** A repeated variable in an original keeps its
  post-call drop, exactly the base pipeline's shape there, so no original
  can lose a tail call it had. (Handing it there would only buy an extra
  clone for a shared value.)
- **A variable at an owned and a borrowed position** keeps the existing
  dual-position accounting (dup before, drop after) in clones too. This
  cannot cost a clone a tail call the original had: borrow inference makes a
  parameter that reaches an owned position owned, and a scrutinee whose
  matched field reaches one owned too (`Borrow`'s field-escape rule), so the
  same variable is already owned and dying in the original, which has the
  same drop after the same call. The fixture's `og`/`of` shows it: the
  original `og` owns its list and recurses with the feature off as well, so
  that case runs on 5 000 rows, for the accounting only.

## Verification

- `test/native/owned_call_dup_arg.march` (+ `.expected`, the interpreter's
  output; dune rule pair `owned_call_dup_arg`): a self loop and a mutual loop
  over 1 000 000 rows passing the row twice, the owned + borrowed shape, rows
  that are all the same list (rc > 1 through the owned walk), a list still
  read after the walk, and a churn loop that must stay flat by
  `live_allocs`. Compiled output matches the interpreter with the feature on
  and with `MARCH_NO_OWNED_CALLS=1`.
- RED on the base (PR #869's compiler): the fixture's "mutual" line overflows
  the stack (exit 138).
- IR check (`owned_call_dup_arg_llvm_check`): `mg$own0` and `dd$own0_1_2`
  exist and neither calls itself (`1 0 1 0`). On the base: `1 1 0 0` (`mg$own0`
  calls itself, and the self loop has no `dd$own0_1_2`). With the kill switch
  there is no `mg$own0` (RED as well).
- `owned_call_drop_fusion` (+ `_llvm_check`, still `7 0 1`) and
  `native_mutual_tco_forwarded_arg` unchanged and green.
- TIR snapshots: 57 passed, unchanged (the harness never redirects).
- `scripts/run-tests.sh -q compiler codegen`: all passed (1290 + 675), exit 0.
- Refine-audit baseline: two `native_owned_call_dup_arg` lines.

## Measurements

The change cannot move the three benchmarks: `--emit-llvm --opt 2` of
binary_trees, tree_transform and list_ops is byte-identical to PR #869's
compiler (none of them passes a variable twice inside a clone). Timed anyway,
Apple M3 Max, `--compile --opt 2`, three binaries per benchmark (this branch,
PR #869's compiler, this branch with `MARCH_NO_OWNED_CALLS=1`), runs
interleaved with alternating order, 15 runs each, load average 25-35 from
other sessions, outputs identical across the three:

| benchmark | this branch: min / median | #869: min / median | off: min / median |
|---|---:|---:|---:|
| binary_trees | 72.6 / 78.4 ms | 72.0 / 78.0 ms | 77.0 / 92.1 ms |
| tree_transform | 683.6 / 738.4 ms | 651.0 / 742.7 ms | 664.3 / 731.3 ms |
| list_ops | 38.8 / 42.6 ms | 37.7 / 43.1 ms | 35.7 / 44.5 ms |

The spread between the identical-IR columns (up to 5% on a min) is the load.
