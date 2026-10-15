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
