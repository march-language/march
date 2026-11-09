`[P2]` Compiled: an `Actor.call` result passed through a generic helper comes back still wrapped

Found 2026-10-15 while testing the `send_wrong_actor` check. Compiled-only; the
interpreter is correct.

```march
mod Main do
  needs IO.Console
  type Q = Q
  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Show(r) do
      Actor.reply(r, "counter " ++ int_to_string(state.n))
      state
    end
  end
  fn show(r) do
    match r do
      Ok(s) -> s
      Err(e) -> e
    end
  end
  fn main(_c : Cap(IO.Console)) do
    let c = spawn(Counter)
    println(show(Actor.call(c, Q, 1000)))      -- compiled: Ok(counter 0)
    match Actor.call(c, Q, 1000) do             -- compiled: counter 0
      Ok(s) -> println(s)
      Err(e) -> println(e)
    end
  end
end
```

Interpreted, both lines print `counter 0`. Compiled, the first prints
`Ok(counter 0)`: the `Ok` arm of the generic `show` hands back something that
`println` renders as the whole `Result`, while the same match written inline is
right. Suspects: the reply-handler's unannotated `r` leaves the reply type
erased, so `Actor.call`'s `Result(a, String)` reaches `show`'s specialisation
with a different payload representation (boxed vs. the niche/inline form) than
the direct match assumes. Start with `scripts/triage.sh` on the program above and
compare `--dump-tir` of `show`'s specialisation with the inline match.

## 2026-11-09: root cause is a name collision, not `Actor.call`

Re-verified on `9f14c7358`. No actor is needed:

```march
mod Main do
  needs IO.Console
  fn show(r) do
    match r do
      Ok(s) -> s
      Err(e) -> e
    end
  end
  fn mk(x : Int) : Result(String, String) do if x > 0 do Ok("pos") else Err("neg") end end
  fn main(_c : Cap(IO.Console)) do
    println(show(mk(1)))       -- interpreted `pos`, compiled `Ok(pos)`
  end
end
```

The user's `fn show` shares its name with the `Show` interface method. Lowering keeps the call
as `show` (the entry module's own fns shadow interface methods there,
`Lower_state._current_module_fns`), but mono's interface-method-name collision check
(`lib/tir/mono.ml`, the `Some orig_fn when ... iface_impl_name ...` arm) sends a call to the
interface impl whenever the user fn's first parameter type does not mangle the same as the
argument's. For an unannotated `r` that type is `Result('a, 'e)`, which never mangles like
`Result(String, String)`, so the call went to `Show$Result.show`. With `r : Result(String,
String)` written out the types mangle alike and the user's fn runs. Renaming the fn (`pick`)
also fixes it.

**Tried and rejected:** letting a generic parameter type that the argument instantiates claim
the call in mono. It fixes this call and breaks `println(mk(2))` in the same program: the
prelude's `println` calls `show(x)` on the same `Result(String, String)`, and mono cannot tell
that call (which means the interface method) from the user's. Measured: compiled printed `pos`
for `println(mk(2))` instead of `Ok(pos)`.

**What a fix needs:** the decision belongs to lowering, which knows the lexical scope. Give a
user fn whose name is an interface method name its own TIR symbol (or an alias the module's own
call sites are lowered to), so mono never has to guess from types. The same collision affects
every interface method name (`eq`, `compare`, `hash`, `to_json`, ...) and nested modules
(`find_iface_impls` strips the `M.` prefix). Same family as
`2026-10-30-interpreter-compiler-name-resolution-diverge.md`.
