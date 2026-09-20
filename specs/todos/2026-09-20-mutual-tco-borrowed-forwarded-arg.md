# `[P1]` Mutual TCO frees a forwarded argument one iteration early (or leaks it)

Filed 2026-09-20, found by the ASAN gate on the access-point PR (#533):
`two-node[cluster_ap_retry]` died with a heap-use-after-free in `march_string_eq`,
inside `__mutco_SessionNode.invite_role_SessionNode.answer_or_next__`, on a string
freed by `march_decrc_local` in that same function.

## Repro (no sanitizer needed)

```march
pfn take_next(xs : List(String), why : String) : String do
  match xs do
    Nil -> why
    Cons(x, rest) -> inspect(x, rest, why)
  end
end

pfn inspect(x : String, rest : List(String), why : String) : String do
  let verdict = if String.starts_with(x, "ok") do "" else "refused: " ++ x end
  if verdict == "" do "accepted " ++ x
  else take_next(rest, if why == "" do verdict else why ++ "; " ++ verdict end) end
end

take_next(Cons("no-x", Cons("no-y", Nil)), "")
```

- interpreted: `refused: no-x; refused: no-y`
- compiled: `refused: no-y; refused: no-y` (the freed text is reused)

Every `--opt` level, with and without TRMC. The fixture is kept as
`test/native/mutual_tco_forwarded_arg.march` (+ `.expected`, generated from the
interpreter), with NO `test/dune` rule: it fails today, so wiring it into `runtest`
would redden CI. Whoever fixes this adds the rule (copy any `native_*` golden pair)
and confirms it goes green; the expected output is the interpreter's.

## Why the obvious fix is not one

The TIR is `let t = inspect(x, rest, why) in dec_rc why; t`: `why` is forwarded to a
BORROWED parameter and dropped after the call, which is correct under real recursion
(the drop happens once the nested call has returned). The flattened loop has no
"after the call": the drop runs immediately before `why`'s new value is stored, so

- **emitting it** frees a value the next iteration reads (this bug), and
- **skipping it** (what the self-TCO arms do, `Llvm_tco.dup_bound_vars` and the guard
  in `Llvm_emit_tcoarm`) means nothing ever drops it -- the leak that
  `test_mutual_tco_borrowed_arg_decref_on_live_path` ("B7") was added to prevent.
  Applying the self-TCO rule to the mutual arms fails that test, as expected.

Faithful semantics would keep every forwarded-and-then-dropped value alive until the
loop exits -- a pending-drop stack, which is what the recursion's own frames are. So
the transform as it stands is unsound for this shape whichever side is chosen.

## Options

1. **Do not flatten a group whose tail call has a dec chain targeting a forwarded,
   non-dup-bound argument.** Safe (no leak, no UAF); costs the loop in that shape, so
   deep recursion there grows the stack again. B7's own fixture is that shape, so its
   assertions (a loop IS emitted) would have to be re-stated.
2. **Keep the value alive to loop exit**: give the combined function a pending-drop
   list and drain it on every `ret`. Faithful, but a new runtime cost on the path
   this transform exists to make cheap.
3. **Restrict the transform to groups whose forwarded args are all owned** (the callee
   consumes them, so no post-call drop is emitted in the first place) and fall back to
   real calls otherwise. A narrower version of 1.

Self-TCO takes the "skip" side today and so has the leak half of the same tension
(`test_tco_self_dup_arg_decref_on_live_path` pins the dup-bound exception, not this).
Whatever is decided should cover both.

## Meanwhile

`stdlib/session_node.march`'s access-point code was written as a mutually recursive
pair (`invite_role` / `answer_or_next`) and is being rewritten as a single recursive
function to avoid the transform ([[2026-09-20-choreography-access-points-a1]]).
