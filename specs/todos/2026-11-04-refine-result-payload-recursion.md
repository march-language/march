`[P3]` Refinements: three gaps that kept `Udp.open_sharded`'s count from a proof

Found while putting `stdlib/udp.march` under `cap verified`
(specs/progress/2026-11-04-udp-stdlib-high-throughput.md). The fact wanted:
`open_sharded(..., n, ...) : Result({List(UdpSocket) | len(_) == n}, UdpError)`.
It needs induction, and each route to it ends at one of these. The module
ships with a runtime `List.length(socks) == n` test instead (it cannot fail;
it states the fact to the checker). All repros: `cap verified` + `--check`.

1. **A Result/Option payload's measure fact does not leave a recursive call.**
   A plain return proves; the same function returning the list in `Ok`/`Some`
   is `solver-undecided`, though the recursion is structural on the tail:

   ```march
   pfn each2(ss : List(Int)) : {List(Int) | len(_) == len(ss)} do      -- proved
     match ss do
       Nil -> Nil
       Cons(s, t) ->
         let rest = each2(t)
         Cons(s, rest)
     end
   end
   pfn each(ss : List(Int)) : Result({List(Int) | len(_) == len(ss)}, String) do   -- undecided
     match ss do
       Nil -> Ok(Nil)
       Cons(s, t) ->
         match each(t) do
           Ok(rest) -> Ok(Cons(s, rest))
           Err(e) -> Err(e)
         end
     end
   end
   ```

   (A non-recursive helper has the same problem: `send_batch` returning a
   helper's `Result({Int | _ == total}, _)` did not prove; an inline
   `Ok(List.length(payloads))` does.)

2. **A function over `List(Result(a, e))` is not reflected** ("is not a
   measure or known predicate"), with or without nested patterns, so a lemma
   over it is `lemma_unproved`. The identical shape over `List(Int)`
   (`pos`/`count_pos`, lemma `len(pos(xs)) == count_pos(xs)`) reflects and
   proves:

   ```march
   pfn count_ok(rs : List(Result(Int, String))) : Int do
     match rs do
       Nil -> 0
       Cons(r, t) -> match r do
         Ok(_) -> 1 + count_ok(t)
         Err(_) -> count_ok(t)
       end
     end
   end
   ```

3. **Reflection wants a structural argument; a proved `@[decreases]` metric
   does not count.** `@[decreases(k)] pfn slots(k : {Int | _ >= 0})`
   counting down to `Nil` stays "not reflected ... unproved:no-structural-arg",
   so `len(slots(k)) == k` cannot be stated. Neither `List.range` nor
   `List.repeat` carries a length postcondition for the same reason.

Done when: `open_sharded`'s length test can be deleted with the module still
`cap verified`, and the three repros above prove.
