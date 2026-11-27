# Fresh names are numbered per function (2026-11-26)

Second of two prerequisites for lowering stdlib function bodies on demand (the first is
`2026-11-26-local-fn-provenance.md`): a function's emitted text must depend on that function,
not on which functions were lowered before it. Three counters that mint function-LOCAL names
were module-wide, so adding a function, or lowering the same functions in another order,
renumbered every function after it.

| counter | names | was | now |
|---|---|---|---|
| `Lower_state` | `$t7` `$f3` `$f_x2` `$p1` `$guard2` `$jp_clo4` `$spawned1` `$mbox_set1` | one per `lower_module` | one per top-level function body |
| `Trmc.trmc_ctr` | `$trmc4` | one per `transform_module` | reset before each top-level function |
| `Auth_rt.captures`' `counter` | `$auth_cap1` `$auth_saved2` `$auth_p3` … | one per call | reset before each top-level function |

Counters that run after the pre-mono prune are untouched (Perceus's `$rc_`, `Join_points`,
Fusion's `$nafuse_`, the inliner's `_i<n>`, the emitter's register and label numbers). They see
only the functions the program reaches, in an order lowering does not decide. They are still
module-wide: a live function added to a program renumbers those.

## Lowering

`Lower_state.enter_fn_body` / `leave_fn_body` (`with_fn_body`), introduced for provenance, now
also own the temp counter: `_fn_counter` restarts at 0 inside the scope and the enclosing value
comes back after it. Scopes nest, because a module lowered lazily in the middle of a body lowers
its own functions there; the outer body's numbering is the same whether or not that happened.

Bracketed, each as one function: `Lower_decls.lower_fn_def` (every parsed fn, impl method and
`lower_more` fn), a module-level let's zero-arg function (both copies), each actor handler
(`on_stop` and the inspect renderer included), an actor's spawn glue, each test body, `setup`,
`setup_all`.

**Code lowered outside any function body** is the initialiser of an entry-module `let`.
`lower_module` folds it into every function that uses the let, so its temporaries end up beside
that function's own. They draw from `_module_counter` and are spelled `$top_t7`; nothing else
mints a `$top_` name, so the two sequences cannot meet. (No program of the IR corpus has such
a temporary. `test_fresh_names.ml` case 3 lowers one and checks every function's minted
binders are distinct.)

`fresh_nested_name` (lambdas, join points, respawn thunks, restrict layers: names that become
symbols) was already keyed by host and ordinal. It no longer ticks the temp counter, which it
did only to keep `$t` numbering unchanged when it was introduced.

`Lower_decls.call_fn_typed_module_lets` runs over every function after lowering and minted its
call temporaries with `fresh_var`: outside any scope, so each function's numbers depended on
how many lets the functions before it used. They are now `$mlet<k>`, counted per function.

Entry paths: `Lower.lower_module` resets both counters and the in-scope flag
(`reset_counter`); `lower_module ~resumable` / `lower_more` clear the flag and continue the
module counter (a call that raised mid-body must not leave the next one inside a scope). The
REPL/JIT, the LSP and the tests all enter through those two.

## Where two functions' locals meet

Every function's `$t1` is now the same name, so each place that puts two functions' bodies in
one scope needs something that keeps them apart.

- **Lambdas, local fns, join points** are lowered inside their host's scope and share its
  counter. Defun lifts them out; nothing is merged.
- **The inliner** (`Inline.alpha_rename`) renames every binder of the inlined body (parameters,
  lets, letrec fns, branch binders) to `<name>_i<n>` from its own counter. Unchanged.
- **Mutual TCO** emits a group of functions as one LLVM function (`__mutco_…`). This is the one
  place same-named locals of two top-level functions really share a scope, and the emitter's
  slot table handles it: `Llvm_ctx.local_names` counts uses of each alloca name and the second
  `$t3` gets the slot `$t3_1`. It always did this for source names (`x` in two members). 14
  combined functions in 13 corpus programs gained such suffixes and their code is otherwise
  identical. 11 of the 13 were compiled and run with both compilers and print the same
  (one benchmark's timings aside); `session_party_released` and `topology_place` need a peer
  node and were not run by hand.
- **Entry-module lets**: the `$top_` spelling, above.
- **Restrict layer fns, actor glue, `uniquify_fn`**: a layer fn's body is built from literals;
  each handler and the spawn glue is its own scope; `uniquify_fn` numbers its `$sh<n>` per
  function already.
- **Hof_spec, Known_call, Fusion**: clone or redirect; none copies one function's binders into
  another. Fusion's NativeArray composition splices two lambdas of one host.
- **Passes with name-keyed tables** (Perceus's `closure_fvs`, `var_ctx`; the emitter's
  `let_alias`, `tco_dup_bound`) are scoped to one function or one mutual-TCO member, or are
  maintained at every rebinding. Source names such as `x` and `acc` already repeat across
  functions, so a module-wide table keyed by variable name could not have worked.

## Release order was derived from name order

`Perceus_core`'s cross-branch pass releases, at the head of a match arm, the variables another
arm still uses. It emitted them with `StringSet.fold`, that is in string order of their names,
so `$f10` came before `$f9`: which of two sibling constructor fields was released first
depended on whether their counters straddled a power of ten. With a module-wide counter that
is rare (two adjacent numbers on either side of 9,999/10,000, say); per function it is every
function whose tenth temporary is a field. Per-function numbers with the old order moved
releases in three stdlib functions (`Handshake.decode_hello`, `SwimDriver.member_of_fields`,
`GlobalPid.of_value`: sibling `$f` fields released in the other order), visible in four corpus
programs, `test/native/session_party_released.march` among them.

The order now comes from `Tir_names.compare_minted_order`: by stem, then by the trailing
counter as a number. For two minted names of one kind that is the order they were minted in,
whatever the numbering; for names without a counter it is string order, as before (a source
name that ends in digits, `x2` against `x10`, now also compares by the number). With it no
corpus program releases anything in a different order from the compiler before this change.

Not done: ordering by binding position, which would not consult names at all. It would also
reorder the releases of source-named variables (currently alphabetical) in most programs, a
change to finaliser order that is larger than a renumbering and wants its own review.

## Tests

`test/test_fresh_names.ml` (suite `fresh-names` in `run_codegen`). Cases 1 to 4 and 6 fail on
the lowering of the commit before; 5 and 6 fail with string order in `compare_minted_order`.

1. A function's TIR straight out of lowering, and after TRMC, is the same text with a (called)
   function declared before it.
2. Its LLVM definition is the same with an uncalled function declared before it (lowered,
   then pruned). The inliner's `_i<n>` is masked: that counter lives as long as the process.
3. `march --emit-llvm`, one process per program: the two `.ll` files are byte-identical.
4. No two minted binders of one function share a name, entry-module lets folded in.
5. `compare_minted_order`: counters compare as numbers; every permutation sorts to one result.
6. The same function with 0 to 11 extra temporaries in front releases its sibling fields in
   the same order by field position; one of the variants has them at `$f9`/`$f10`.

`test/test_auth_rt.ml`, "capture temporaries are numbered per function": the text of a
function that captures is the same with another capturing function declared before it
(`$auth_cap141` against `$auth_cap153` without the reset).

`test/snapshots/`: 56 of 64 expected files regenerated. A script checked each against its
old text function by function: identical once every minted name is replaced by a placeholder,
and old-to-new names form a bijection per function. `test/errors/` did not change.

## What moved in the emitted IR

`scripts/ir-oracle.sh baseline` per compiler (532 programs emit, 30 skip, same set each time),
`scripts/ir-canon-diff.sh` between the previous commit (local-fn provenance) and this one:

| programs | |
|---|---|
| 518 | identical after masking minted counters (3 of them byte-identical) |
| 13 | differ only in the emitter's duplicate-slot suffix, inside 14 `__mutco_…` functions (`%$t3.addr` is now `%$t3_1.addr` for the second member's `$t3`) |
| 1 | `native_module_let_fn`: the module-let call temporary is `$mlet<n>` where it was `$t<n>` |

With those two spellings mapped back, all 532 are identical: no instruction, callee, constant
or release moved. Against the commit before both changes the only further differences are the
provenance rows of `2026-11-26-local-fn-provenance.md` (164 programs).

`scripts/ir-canon-diff.sh`'s mask list did not cover `$trmc`, `$p`, `$guard`, `$f_<field>`,
`$auth_<kind>`, `$jp_clo`, `$spawned`, `$mbox_set` (with the old list the same comparison
reports 133 programs). It now does, with `$top_…` and `$mlet`. It still goes red on a changed
opcode and on a name outside the list.

Also checked on the 532 programs: `MARCH_VERIFY_TIR=1` finds nothing with either compiler, and
clang accepts every emitted module (it rejects a duplicated local name).

## Run

2026-11-26, arm64 macOS, load average 15 to 45 from other sessions throughout.

- Suites, all passing: `compiler` (1,773 tests, run as six shards by group name because the
  one-process run would have outlasted `run-tests.sh`'s 40-minute suite timeout at that load),
  `eval` 309, `codegen` 832 (one tool skip: no cross sysroot for linux/amd64), `stdlib` 924,
  `stdlib_march` 88, `test_jit` 65, `errors` 490, `test_reports` 24, `authority` 76,
  `captures` 63, `cap_conformance` 450, `dep_grants` 53, `run_snapshots` 70, and the LSP
  suites (`lsp`, `utf16`, `jsonrpc`, `incremental`, `query_cli`), which lower through
  `Lower.lower_module`. `refinecheck` was not run: nothing here reaches `lib/refinecheck/`.
- `scripts/determinism-oracle.sh --corpus small`: deterministic across 32 programs and four
  conditions (`examples/topology_app` included); `src_auth_capture` skips, as it does with the
  compiler before.
- `bench/tree_transform.march` and `bench/list_ops.march`, `--compile --opt 2`, both compilers:
  same output (`104857600`, `333333666666`). Also `binary_trees`, `mutual_recursion`,
  `json_stream`.
- `--compile` of a hello world from a cold HOME: 11.2 s user with this change, 11.6 s before;
  `--emit-llvm` warm: 1.07 s against 1.08 s.

## Left as it is

- `Inline.gensym`'s `_i<n>` counter is never reset: a process that compiles two modules (the
  test suite, the LSP) gives the second module the first one's leftovers. One compiler run per
  program is unaffected.
- A lambda lowered outside any function body (in a module-level `let`, an actor handler, a
  test) is named after the host `<Mod>.$top` and an ordinal that counts every such lambda of
  the module (`$lam3_Mod__top`). That is a symbol, and it would move if those bodies were
  lowered in another order.
- An unresolved type variable keeps the typechecker's id in pre-Mono TIR (`'_322`), which
  moves with the source in front of it. Mono resolves it; emitted IR does not carry it.
