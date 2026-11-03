# Stdlib doc coverage: every public fn documented, runnable examples, Try it

Date: 2026-10-18

## What changed

Doc annotations and `--` comments only, across 121 `stdlib/*.march` files (a
strip-docs-and-comments comparison against the base commit shows no code line changed).

- **Undocumented public fns:** 468 of 2528 before, 0 after (counted from the forge
  search index: module-level `fn`, not `pfn`).
- **Public fns with no `march>` example:** 2281 before, 1041 after. The remaining ones do IO,
  networking, actors, randomness or clock reads, or live in a module the browser REPL cannot
  load; they get prose plus plain (non-`march>`) usage snippets.
- **Try it:** 87 modules carry `-- doc: try` (was 32), covering 1481 doc blocks with `march>`
  transcripts (was 242).
- **Wrong docs corrected** along the way, e.g. false stability claims in Sort/Enum/List.sort_by,
  docs attached to the wrong fn (String.to_codepoints, ClusterNode.core_tick, Regex find_*,
  HttpClient.run), broken pre-existing examples (stray `march> ` lines in List, LinearMap
  examples the REPL rejected, Parallel's `7.` expected value, RRB's `v` binding).

## Try-it eligibility rule

A `march>` code block gets a Try it button when its module's header comment has
`-- doc: try` (`specs/2026-10-14-doc-try-it-design.md`). A module is opted in only when every
`march>` example in it runs in the browser REPL: the module is not on
`scripts/gen-browser-stdlib.py`'s UNAVAILABLE list, no example panics, and every Int stays in
32-bit range. Browser-unavailable modules (File, Dir, Process, cluster/node modules, DataFrame,
Msgpack, Random, ...) got no new `march>` lines.

## Verification

- `scripts/check-stdlib-doctests.py --check` on all 121 files: 2245 run, 0 failed; the only
  skips are `let` setup lines and the pre-existing non-opted Dir/HttpServer/panic examples.
- Browser REPL value check of every example: only errors are the allowlisted Dir/HttpServer/
  Option.unwrap(None) lines; value differences are only the printer's `1.0` -> `1`.
- `node scripts/browser-repl-doc-sweep.js`: 2676 examples, 13 fail as expected.
- `scripts/run-tests.sh -q stdlib stdlib_march`, `scripts/check-docs.sh`: pass.

## Bugs found while reading (not fixed)

Stdlib:
- `stdlib/list.march:93-100` `range_step_go`: step 0 with start > stop never terminates;
  `chunks` with size <= 0 at runtime loops forever.
- `stdlib/sort.march:73,83,308` none of the sorts is reliably stable (cmp_swap networks, mixed
  `<`/`<=` assumptions); `stdlib/sort.march:359` `detect_runs` never detects descending runs.
- `stdlib/enum.march:68` `flat_map` is quadratic in output length.
- `stdlib/math.march:157-174` floor/ceil/round/truncate go through Int: NaN gives 0.0 and
  values past Int range are wrong.
- `stdlib/seq.march` `each` threads `f(x)` as the `:ok` accumulator, so natively `f` must
  return an Atom; `stdlib/flow.march` `run` fails to typecheck natively because of it.
- `stdlib/hamt.march:190-200` `get` misses a key whose hash shares the low 35 bits with
  another (collision bucket tagged with the first hash).
- `stdlib/ordered_map.march:184-199` `tree_filter` can leave the tree unbalanced.
- `stdlib/range.march:29-74` a step-0 record loops forever in to_list/each and divides by zero
  in size/contains.
- `stdlib/bigint.march:344,366,393` div/mod_ only accept divisors below 10000 (base), panic
  message says 10^9.
- `stdlib/decimal.march` `div` and `div_round` give different scales; `from_string` turns bad
  input into zero; `round` accepts negative places.
- `stdlib/bytes.march` `from_list` out-of-range bytes wrap natively but error in the browser;
  `decode_base64` stops at the first padded group (`"TQ==TWFu"` -> `Ok("M")`).
- `stdlib/random.march:176` `int` calls `unix_time` without `needs IO.Clock` and seeds from
  whole seconds; `range` with `hi < lo` panics or returns garbage.
- `stdlib/stats.march` `variance_safe([x])` is `Ok(0.0)` but `std_dev_safe([x])` is `Err`.
- `stdlib/json.march` (~470) `escape_of` writes control bytes below 0x20 raw (invalid JSON).
- `stdlib/toml.march` (~990) `to_string` does not escape strings; output is not valid TOML.
- `stdlib/yaml.march` `value_to_yaml` misindents sequences under keys and maps in sequences
  (round trip loses data); `needs_quoting` misses Yes/True/No/NULL/On and newlines.
- `stdlib/xml.march` text runs keep trailing but strip leading whitespace.
- `stdlib/csv.march` `each_row`/`read_all`/`each_row_with_header` leak the handle if the
  callback panics.
- `stdlib/compress.march` `accept_encoding`/`best_encoding` are case-sensitive and only treat
  `q=0`, `q=0.0`, `q=0.00` as rejected; `encode_stream`/`decode_stream` are per-chunk, not
  streaming.
- `stdlib/msgpack.march` `bin` bytes are not range-checked; uint64 above 63 bits wraps.
- `stdlib/http.march` (~470) `parse_url` splits the host only at `/` (`http://h?x=1` keeps the
  query in the host); `:-1` is InvalidPort while `:-5` is accepted.
- `stdlib/crypto.march` `verify_password` panics on iteration count 0 and compares digests
  case-sensitively.
- `stdlib/regex.march` `fold_case` lowercases `\D \W \S`; `replace_all`/`split` drop a byte
  after an empty match; a mid-pattern `$` ends the pattern; `multiline` is inert.
- `stdlib/datetime.march:242` `day_of_week` negative before 1970-01-01 minus 4 days;
  `:254-262` `format` has no `%%`; `:278-333` `parse` ignores trailing input; `:378`
  `fixed_zone_hours` skips the +/-14h check.
- `stdlib/shell_render.march` `string`/`raw` cut at codepoints but count graphemes.
- `stdlib/logger.march:311` atoms print as `::ok`; `:205` `with_scope` thunk arity differs in
  the browser; `:342` logfmt does not escape `\`, newlines or `=`; `:394` NaN/inf gives invalid
  JSON.
- `stdlib/gen.march:518` `list_of_size` deeper shrink candidates lose length `n`.
- `stdlib/http_client.march:483` `step_basic_auth` does not base64-encode; `:194-213`
  keepalive reconnects consume two retries and leak the new fd; `:99` `backoff_ms` unused;
  `:263` redirects turn 307/308 into GET; `:16` TransportError mirror lacks
  SchemeNotSupported.
- `stdlib/tls.march:322` `https_get` does one 1 MiB read and never frees the context.
- `stdlib/websocket.march:61` `select` can never return ActorMsg; continuation frames close
  the socket (runtime/march_http.c ~2895).
- `stdlib/http_server.march` `spawn_n` does not pass `release_conn`.
- `stdlib/node_queue.march:279-294` `withdraw` answers the oldest waiter, not the timed-out
  one; `:216-226` DropOld ignores a dead connection; `:149-152,431-440` byte counter not
  reduced on drop.
- `stdlib/node_send.march:213-216` `cast_from` pending entries never removed on success.
- `stdlib/cluster_conn.march:172-173,182-183` `accept_split_auth` leaks fds on error paths.
- `stdlib/cluster_auth.march:42` `verify` compares HMACs with `==` (not constant time).
- `stdlib/dist_link.march:153` `find_by_target_pid` ignores the node; header names
  nonexistent `monitor`/`demonitor`.
- `stdlib/work_dispatch.march:22,59,146-151` pick is not random, negative index gives None,
  retry reuses a stale `now_ms`.
- `stdlib/swim_driver.march:501-503` Gossip sent as legacy frame loses creation;
  `stdlib/swim.march:120` suspects an already-Dead member.
- `stdlib/membership.march:94` `supersedes` tie makes merge non-commutative;
  `stdlib/global_registry.march:61` equal clocks resolve by arrival order.
- `stdlib/consistent_hash.march:85` wraps to the last ring entry, not the first; `:27`
  re-adding a name duplicates its vnodes.
- `stdlib/crdt.march:243` ORSet.remove has no tombstone; `:290` ORSet.equal compares counts;
  `:140` PNCounter.equal compares totals; `:276` merge duplicates tags; `:188` LWWRegister
  merge not commutative; `:38` GCounter.add accepts negatives.
- `stdlib/channel.march:324` `parse` rejects spaces/null and escaped quotes;
  `stdlib/pubsub.march:79,205` duplicate subscriptions deliver twice;
  `stdlib/channel_server.march:233` `select_shard([])` divides by zero;
  `stdlib/channel_socket.march:174-179,255,275` join never spawns a channel, `connect_fn`
  never called, pushes go to pid 0; `stdlib/presence.march:280` `untrack` always broadcasts
  leave.
- `stdlib/plot.march:297` `fmt_float` drops the sign in (-1, 0) and truncates; `:139` bar
  labels never drawn.
- `stdlib/dataframe.march:3504` `html_esc` replaces only the first match (XSS); `:601`
  `from_rows` matches later rows by position; `:1801` `split_csv_line` ignores quotes;
  `:461` nulls stored as zero values; `:2532` outer join loses right-only keys; `:1772`
  sort unstable; `:3436` Lag/Lead with negative n panics; `:291` `compare_values`
  inconsistent for mixed types.
- `runtime/march_dom.mjs:107-112` `Js.Dom.unlisten` never removes a listener.

Native REPL / interpreter (affect doctests):
- Map.int_cmp/str_cmp passed as values crash the native REPL (SIGSEGV) on lookup hits.
- Zero-arg closures bound with `let` return 0 in the native REPL (`let f = fn -> 1; f()`).
- `lib/repl/repl.ml:1045` the REPL rebinds `v` to the last result.
- `lib/repl/multiline.ml:13-14` counts `do`/`end` inside string literals (input hangs).
- Values read from Vault-backed state compare unequal after printing correctly
  (`Vault.get(...) == Some(10)` is false).
- Nested local `go` helpers return tagged Ints in the REPL (Presence.entry_count,
  LazyNicheProbe.first_or).
- `()` prints as `= 1`; `0.0 / 0.0` reports division by zero.
- `lib/eval/eval_builtins.ml:1526-1557` char builtins error on multi-byte input in the
  interpreter but read the first byte natively.
