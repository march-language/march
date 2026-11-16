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

Every claim below was re-run on 2026-11-11; see "Triage of the bugs found while reading
(2026-11-11)" at the end of this file for the verdict and the todo that now tracks it.

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

## Triage of the bugs found while reading (2026-11-11)

Step 1 of package E6 in `specs/plans/2026-11-11-pre-1.0-execution-plan.md`. Every claim in the
list above was split into single claims (128) and re-run on `origin/main` at a7110f95f with a
minimal program: interpreted, and compiled wherever the backend could matter. Claims about
sockets, TLS or a live cluster that could not run standalone were classified from the current
source and say "source reading" in the table. Nothing was fixed.

| Verdict | Claims |
|---|---|
| fixed | 9 |
| live | 116 |
| not reproduced | 2 |
| by design, not a bug | 1 |

The 116 live claims by class: 46 wrong answer or invalid output, 14 hang, crash or leak, 42
inconsistent or surprising API, 14 cosmetic. 113 are tracked by 85 new todos
(`specs/todos/2026-11-11-*.md`; claims that share a root cause or are cosmetic items of one
module share a file); the other 3 were already covered by
`specs/todos/2026-10-14-native-repl-quirks-found-by-doctests.md`. No other existing todo covered
any of them.

Most live claims are now stated in the function's doc string, because the 2026-10-18 sweep
documented the behaviour instead of fixing it. A documented caveat did not change the class: the
class says what the function does, and follows the plan's own examples (an unstable sort, an
unescaped `Toml.to_string` and a `Hamt.get` miss count as wrong answers). Priorities: `[P2]` for
a wrong answer, a leak, or a hang or crash in a commonly used module; `[P3]` for the rest. A
shared todo carries the highest priority of its claims.

| Module | Claim | Verdict | Todo or evidence |
|---|---|---|---|
| List | `range_step` with step 0 and start > stop never terminates | fixed | panics `step must be non-zero` (af422e98e) |
| List | `chunks` with size <= 0 loops forever | fixed | panics `size must be positive` (9a7d468d5) |
| Sort | none of the sorts is reliably stable | live: wrong answer, P2 | `2026-11-11-sort-no-stable-default.md` |
| Sort | `detect_runs` never detects descending runs | live: cosmetic, P3 | `2026-11-11-sort-detect-runs-descending.md` |
| Enum | `flat_map` is quadratic in output length | live: cosmetic, P3 | `2026-11-11-enum-flat-map-quadratic.md` |
| Math | floor/ceil/round/truncate of NaN give 0.0 | fixed | returns `nan` (f00f6d364) |
| Math | floor/ceil/round/truncate wrong past Int range | fixed | 1e19, 1e300, inf returned unchanged (f00f6d364) |
| Seq | `each` needs an Atom-returning callback | live: API, P3 | `2026-11-11-seq-each-atom-flow-run.md` |
| Flow | `run` fails to typecheck | live: API, P3 | `2026-11-11-seq-each-atom-flow-run.md` |
| Hamt | `get` misses a key whose hash shares the low 35 bits with another | live: wrong answer, P2 | `2026-11-11-hamt-low35-hash-collision.md` |
| OrderedMap | `tree_filter` can leave the tree unbalanced | live: cosmetic, P3 | `2026-11-11-ordered-map-filter-unbalanced.md` |
| Range | step-0 record loops forever in `to_list` | fixed | panics `step must be non-zero` (92a98dc79) |
| Range | step-0 record loops forever in `each` | fixed | panics `step must be non-zero` (92a98dc79) |
| Range | step-0 record divides by zero in `size` | live: API, P3 | `2026-11-11-range-step0-size-contains.md` |
| Range | step-0 record divides by zero in `contains` | live: API, P3 | `2026-11-11-range-step0-size-contains.md` |
| BigInt | `div`/`mod_` only accept divisors below 10000 | live: API, P3 | `2026-11-11-bigint-multi-limb-divisor.md` |
| BigInt | panic message says 10^9 | live: cosmetic, P3 | `2026-11-11-bigint-multi-limb-divisor.md` |
| Decimal | `div` and `div_round` give different scales | live: API, P3 | `2026-11-11-decimal-div-scale-and-from-string.md` |
| Decimal | `from_string` turns bad input into zero | live: API, P3 | `2026-11-11-decimal-div-scale-and-from-string.md` |
| Decimal | `round` accepts negative places | live: wrong answer, P2 | `2026-11-11-decimal-round-negative-places.md` |
| Bytes | `from_list` out-of-range bytes differ by backend | live: wrong answer, P2 | `2026-11-11-bytes-from-list-out-of-range.md` |
| Bytes | `decode_base64` stops at the first padded group | live: wrong answer, P2 | `2026-11-11-bytes-decode-base64-trailing-data.md` |
| Random | `int` calls `unix_time` without `needs IO.Clock` | fixed | module declares `needs IO.Clock`; a caller without it is rejected (0979ec8c1) |
| Random | `int` seeds from whole seconds | live: API, P3 | `2026-11-11-random-int-seconds-seed-and-range-order.md` |
| Random | `range` with `hi < lo` panics or returns garbage | live: API, P3 | `2026-11-11-random-int-seconds-seed-and-range-order.md` |
| Stats | `variance_safe([x])` is `Ok(0.0)`, `std_dev_safe([x])` is `Err` | live: API, P3 | `2026-11-11-stats-safe-single-element.md` |
| Json | `escape_of` writes control bytes below 0x20 raw | live: wrong answer, P2 | `2026-11-11-json-control-bytes-raw.md` |
| Toml | `to_string` does not escape strings | live: wrong answer, P2 | `2026-11-11-toml-to-string-unescaped.md` |
| Yaml | sequence under a key is misindented; round trip loses it | live: wrong answer, P2 | `2026-11-11-yaml-seq-under-key-round-trip.md` |
| Yaml | map inside a sequence is misindented | live: wrong answer, P2 | `2026-11-11-yaml-map-in-seq-misindent.md` |
| Yaml | `needs_quoting` misses Yes/True/No/NULL | live: wrong answer, P2 | `2026-11-11-yaml-needs-quoting-case.md` |
| Yaml | `needs_quoting` misses `On` | live: cosmetic, P3 | `2026-11-11-yaml-needs-quoting-case.md` |
| Yaml | `needs_quoting` misses newlines | live: wrong answer, P2 | `2026-11-11-yaml-newline-string-unquoted.md` |
| Xml | text runs keep trailing but strip leading whitespace | live: API, P3 | `2026-11-11-xml-text-whitespace-asymmetric.md` |
| Csv | `each_row` leaks the handle if the callback panics | live: hang, crash or leak, P2 | `2026-11-11-csv-handle-leak-on-callback-panic.md` |
| Csv | `each_row_with_header` leaks the handle likewise | live: hang, crash or leak, P2 | `2026-11-11-csv-handle-leak-on-callback-panic.md` |
| Csv | `read_all` leaks the handle if the callback panics | not reproduced | `read_all` takes no callback; read the source for another panic path, found none |
| Compress | `accept_encoding` is case-sensitive | live: API, P3 | `2026-11-11-compress-accept-encoding-case-and-qvalue.md` |
| Compress | `best_encoding` is case-sensitive | live: API, P3 | `2026-11-11-compress-accept-encoding-case-and-qvalue.md` |
| Compress | only `q=0`, `q=0.0`, `q=0.00` count as rejected | live: wrong answer, P2 | `2026-11-11-compress-accept-encoding-case-and-qvalue.md` |
| Compress | `encode_stream`/`decode_stream` are per-chunk | live: API, P3 | `2026-11-11-compress-stream-is-per-chunk.md` |
| Msgpack | `bin` bytes are not range-checked | live: wrong answer, P2 | `2026-11-11-msgpack-bin-bytes-unchecked.md` |
| Msgpack | uint64 above 63 bits wraps | live: wrong answer, P2 | `2026-11-11-msgpack-uint64-wraps.md` |
| Http | `parse_url` splits the host only at `/` | live: wrong answer, P2 | `2026-11-11-http-parse-url-host-keeps-query.md` |
| Http | `:-1` is InvalidPort while `:-5` is accepted | live: API, P3 | `2026-11-11-http-parse-url-port-sentinel.md` |
| Crypto | `verify_password` panics on iteration count 0 (compiled only) | live: hang, crash or leak, P2 | `2026-11-11-crypto-verify-password-iter-zero-panic.md` |
| Crypto | `verify_password` compares digests case-sensitively | live: API, P3 | `2026-11-11-crypto-verify-password-digest-case.md` |
| Regex | `fold_case` lowercases `\D \W \S` | live: wrong answer, P2 | `2026-11-11-regex-case-insensitive-folds-class-escapes.md` |
| Regex | `replace_all` drops a byte after an empty match | live: wrong answer, P2 | `2026-11-11-regex-empty-match-drops-bytes.md` |
| Regex | `split` drops a byte after an empty match | live: wrong answer, P2 | `2026-11-11-regex-empty-match-drops-bytes.md` |
| Regex | a mid-pattern `$` ends the pattern | live: wrong answer, P2 | `2026-11-11-regex-mid-pattern-dollar-truncates.md` |
| Regex | `multiline` is inert | live: API, P3 | `2026-11-11-regex-multiline-option-inert.md` |
| DateTime | `day_of_week` negative before 1969-12-28 | live: wrong answer, P2 | `2026-11-11-datetime-day-of-week-negative.md` |
| DateTime | `format` has no `%%` | live: API, P3 | `2026-11-11-datetime-format-no-percent-escape.md` |
| DateTime | `parse` ignores trailing input | live: API, P3 | `2026-11-11-datetime-parse-ignores-trailing-input.md` |
| DateTime | `fixed_zone_hours` skips the +/-14h check | live: API, P3 | `2026-11-11-datetime-fixed-zone-hours-unchecked.md` |
| ShellRender | `string`/`raw` cut at codepoints but count graphemes (JS target only; native counts codepoints for both) | live: cosmetic, P3 | `2026-11-11-shell-render-more-chars-count.md` |
| Logger | atoms print as `::ok` | live: cosmetic, P3 | `2026-11-11-logger-atom-double-colon.md` |
| Logger | `with_scope` thunk arity differs by backend (browser half not checked) | live: API, P3 | `2026-11-11-logger-with-scope-thunk-arity.md` |
| Logger | logfmt does not escape `\`, newlines or `=` | live: wrong answer, P2 | `2026-11-11-logger-logfmt-escaping.md` |
| Logger | NaN/inf give invalid JSON | live: wrong answer, P2 | `2026-11-11-logger-json-nan-inf.md` |
| Gen | `list_of_size` deeper shrink candidates lose length `n` | live: wrong answer, P2 | `2026-11-11-gen-list-of-size-shrinks-change-length.md` |
| HttpClient | `step_basic_auth` does not base64-encode | live: wrong answer, P2 | `2026-11-11-http-client-basic-auth-not-base64.md` |
| HttpClient | keepalive reconnect consumes two retries | live: wrong answer, P2 | `2026-11-11-http-client-keepalive-retry-count-and-fd-leak.md` |
| HttpClient | keepalive reconnect leaks the new fd | live: hang, crash or leak, P2 | `2026-11-11-http-client-keepalive-retry-count-and-fd-leak.md` |
| HttpClient | `backoff_ms` unused | live: cosmetic, P3 | `2026-11-11-http-client-backoff-ms-unused.md` |
| HttpClient | redirects turn 307/308 into GET (interpreted; compiled follows no redirect) | live: wrong answer, P2 | `2026-11-11-http-client-redirect-307-308-become-get.md` |
| HttpClient | TransportError mirror lacks SchemeNotSupported | live: hang, crash or leak, P2 | `2026-11-11-http-client-transport-error-mirror-missing-ctor.md` |
| Tls | `https_get` does one 1 MiB read (source reading) | live: wrong answer, P2 | `2026-11-11-tls-https-get-single-read-and-ctx-leak.md` |
| Tls | `https_get` never frees the context (source reading) | live: hang, crash or leak, P2 | `2026-11-11-tls-https-get-single-read-and-ctx-leak.md` |
| WebSocket | `select` can never return ActorMsg (source reading) | live: API, P3 | `2026-11-11-websocket-select-actormsg-and-continuation-frames.md` |
| WebSocket | continuation frames close the socket (source reading) | live: API, P3 | `2026-11-11-websocket-select-actormsg-and-continuation-frames.md` |
| HttpServer | `spawn_n` does not pass `release_conn` (source reading) | live: hang, crash or leak, P3 | `2026-11-11-http-server-spawn-n-no-release-conn.md` |
| NodeQueue | `withdraw` answers the oldest waiter, not the timed-out one | live: wrong answer, P2 | `2026-11-11-node-queue-withdraw-answers-oldest-waiter.md` |
| NodeQueue | DropOld ignores a dead connection | live: cosmetic, P3 | `2026-11-11-node-queue-dead-connection-accounting.md` |
| NodeQueue | byte counter not reduced on drop | live: wrong answer, P2 | `2026-11-11-node-queue-dead-connection-accounting.md` |
| NodeSend | `cast_from` pending entries never removed on success | live: hang, crash or leak, P2 | `2026-11-11-node-send-cast-from-pending-never-removed.md` |
| ClusterConn | `accept_split_auth` leaks fds on error paths | live: hang, crash or leak, P2 | `2026-11-11-cluster-conn-accept-split-auth-fd-leak.md` |
| ClusterAuth | `verify` compares HMACs with `==` | fixed | uses `Crypto.secure_compare` (fa91032dc) |
| DistLink | `find_by_target_pid` ignores the node | live: API, P3 | `2026-11-11-dist-link-find-by-target-pid-and-header.md` |
| DistLink | header names nonexistent `monitor`/`demonitor` (source reading) | live: cosmetic, P3 | `2026-11-11-dist-link-find-by-target-pid-and-header.md` |
| WorkDispatch | pick is not random | live: API, P3 | `2026-11-11-work-dispatch-pick-and-stale-now.md` |
| WorkDispatch | negative index gives None | live: API, P3 | `2026-11-11-work-dispatch-pick-and-stale-now.md` |
| WorkDispatch | retry reuses a stale `now_ms` (source reading) | live: API, P3 | `2026-11-11-work-dispatch-pick-and-stale-now.md` |
| SwimDriver | Gossip sent as legacy frame loses creation | live: API, P3 | `2026-11-11-swim-driver-dispatch-legacy-gossip-loses-creation.md` |
| Swim | `end_period` suspects an already-Dead member | live: cosmetic, P3 | `2026-11-11-swim-end-period-suspects-dead-member.md` |
| Membership | `supersedes` tie makes merge non-commutative | live: API, P3 | `2026-11-11-membership-merge-tie-not-commutative.md` |
| GlobalRegistry | equal clocks resolve by arrival order | live: wrong answer, P2 | `2026-11-11-global-registry-equal-clock-arrival-order.md` |
| ConsistentHash | wraps to the last ring entry, not the first | live: wrong answer, P2 | `2026-11-11-consistent-hash-wraps-to-last-entry.md` |
| ConsistentHash | re-adding a name duplicates its vnodes | live: API, P3 | `2026-11-11-consistent-hash-readd-duplicates-vnodes.md` |
| CRDT | `ORSet.remove` has no tombstone | live: wrong answer, P2 | `2026-11-11-crdt-orset-remove-no-tombstone.md` |
| CRDT | `ORSet.equal` compares counts | live: wrong answer, P2 | `2026-11-11-crdt-equal-not-structural.md` |
| CRDT | `PNCounter.equal` compares totals | live: wrong answer, P2 | `2026-11-11-crdt-equal-not-structural.md` |
| CRDT | `ORSet.merge` duplicates tags | live: cosmetic, P3 | `2026-11-11-crdt-minor-gcounter-negative-orset-tag-growth.md` |
| CRDT | `LWWRegister.merge` not commutative | live: wrong answer, P2 | `2026-11-11-crdt-lwwregister-merge-not-commutative.md` |
| CRDT | `GCounter.add` accepts negatives | live: API, P3 | `2026-11-11-crdt-minor-gcounter-negative-orset-tag-growth.md` |
| Channel | `parse` rejects spaces after a colon | live: API, P3 | `2026-11-11-channel-parse-cannot-read-serialize-output-or-phoenix-frames.md` |
| Channel | `parse` rejects null fields | live: API, P3 | `2026-11-11-channel-parse-cannot-read-serialize-output-or-phoenix-frames.md` |
| Channel | `parse` mishandles escaped quotes | live: wrong answer, P2 | `2026-11-11-channel-parse-cannot-read-serialize-output-or-phoenix-frames.md` |
| PubSub | duplicate subscriptions deliver twice | live: API, P3 | `2026-11-11-pubsub-duplicate-subscription-delivers-twice.md` |
| ChannelServer | `select_shard([])` divides by zero | live: hang, crash or leak, P3 | `2026-11-11-channel-server-select-shard-empty-list-panics.md` |
| ChannelSocket | join never spawns a channel | live: API, P2 | `2026-11-11-channel-socket-join-is-a-stub.md` |
| ChannelSocket | `connect_fn` never called (source reading) | live: API, P2 | `2026-11-11-channel-socket-join-is-a-stub.md` |
| ChannelSocket | pushes go to pid 0 (source reading) | live: wrong answer, P2 | `2026-11-11-channel-socket-join-is-a-stub.md` |
| Presence | `untrack` always broadcasts leave (source reading) | live: API, P3 | `2026-11-11-presence-untrack-always-broadcasts-leave.md` |
| Plot | `fmt_float` drops the sign in (-1, 0) | live: wrong answer, P2 | `2026-11-11-plot-fmt-float-drops-sign-and-truncates.md` |
| Plot | `fmt_float` truncates | live: cosmetic, P3 | `2026-11-11-plot-fmt-float-drops-sign-and-truncates.md` |
| Plot | bar labels never drawn | live: API, P3 | `2026-11-11-plot-bar-labels-never-drawn.md` |
| DataFrame | `html_esc` replaces only the first match (XSS) | fixed | every `<`, `&`, quote escaped (fa91032dc) |
| DataFrame | `from_rows` matches later rows by position | live: API, P3 | `2026-11-11-dataframe-api-rough-edges.md` |
| DataFrame | `split_csv_line` ignores quotes | live: wrong answer, P2 | `2026-11-11-dataframe-csv-reader-ignores-quotes.md` |
| DataFrame | nulls stored as zero values | live: wrong answer, P2 | `2026-11-11-dataframe-nulls-stored-as-zero.md` |
| DataFrame | outer join loses right-only keys | live: wrong answer, P2 | `2026-11-11-dataframe-outer-join-loses-right-only-keys.md` |
| DataFrame | sort unstable | live: API, P3 | `2026-11-11-dataframe-api-rough-edges.md` |
| DataFrame | Lag/Lead with negative n panics | live: hang, crash or leak, P3 | `2026-11-11-dataframe-api-rough-edges.md` |
| DataFrame | `compare_values` inconsistent for mixed types | live: API, P3 | `2026-11-11-dataframe-api-rough-edges.md` |
| Js.Dom (runtime/march_dom.mjs) | `unlisten` never removes a listener | live: wrong answer, P2 | `2026-11-11-js-dom-unlisten-never-removes.md` |
| REPL | `Map.int_cmp` passed as a value crashes on a lookup hit | live: hang, crash or leak, P2 | `2026-11-11-repl-map-named-comparator-crash.md` |
| REPL | `Map.str_cmp` passed as a value crashes likewise | live: hang, crash or leak, P2 | `2026-11-11-repl-map-named-comparator-crash.md` |
| REPL | zero-arg closure bound with `let` returns 0 | live: wrong answer, P2 | `2026-11-11-repl-zero-arg-closure-returns-zero.md` |
| REPL | rebinds `v` to the last result | live: API, P3 | existing: `2026-10-14-native-repl-quirks-found-by-doctests.md` (item 2) |
| REPL | multiline counts `do`/`end` inside string literals | live: hang, crash or leak, P3 | `2026-11-11-repl-multiline-counts-do-end-in-strings.md` |
| REPL | `Vault.get(...) == Some(10)` is false | not reproduced | the REPL now rejects `==` on an Option before it runs (filed below); the related value decay is item 1 of `2026-10-14-native-repl-quirks-found-by-doctests.md` |
| REPL | `Presence.entry_count` returns a tagged Int | live: wrong answer, P2 | `2026-11-11-repl-int-result-printed-tagged.md` |
| REPL | `LazyNicheProbe.first_or` returns a tagged Int | live: wrong answer, P2 | `2026-11-11-repl-int-result-printed-tagged.md` |
| REPL | `()` prints as `= 1` | live: cosmetic, P3 | existing: `2026-10-14-native-repl-quirks-found-by-doctests.md` (item 4) |
| REPL | `0.0 / 0.0` reports division by zero | by design | Float division by zero is specified to stop (`specs/lang/core-march.md`, rule δ-Div-0F); same in the interpreter and compiled |
| Interpreter | char builtins error on multi-byte input but read the first byte natively | live: wrong answer, P2 | `2026-11-11-char-builtins-multibyte-backend-divergence.md` |

### Found in passing (not sweep claims)

Five more bugs showed up while writing the repros. Each was re-run and has its own todo.

| Area | Bug | Class | Todo |
|---|---|---|---|
| HttpTransport, HttpClient (compiled) | `http_parse_response` halves every odd status (401 reads as 200, so `step_raise_on_error` passes it), returns no headers (so no redirect is followed), and reads a dead connection as a 200 | wrong answer, `[P1]` because an authentication failure reads as success | `2026-11-11-http-compiled-response-parse-status-and-headers.md` |
| Compiler (compiled) | `compare` passed as a value, as in every `OrderedMap.from_list(xs, compare)` doc example, fails to link: `use of undefined value '@compare'` | crash (build failure), `[P2]` | `2026-11-11-compiled-builtin-passed-as-value-undefined-symbol.md` |
| Csv (compiled) | a failed open returns an error that is not a `FileError`, so a match on `Csv.FileError(m)` falls through | wrong answer, `[P2]` | `2026-11-11-csv-open-error-shape-compiled.md` |
| REPL | `==` on Option, List and Result values is rejected with "does not implement interface Eq" | crash, `[P2]` | `2026-11-11-repl-eq-on-option-list-result-rejected.md` |
| REPL | a function with a nested local `fn` declared at the prompt fails with `jit error: hd` | crash, `[P3]` | `2026-11-11-repl-nested-fn-decl-jit-error-hd.md` |

The Hamt todo also records a hang found the same way: inserting the second colliding key again
never returns interpreted and overflows the stack compiled.

### Modules with a live wrong-answer bug

For the stability-tier marking (package B2): a module in this list has at least one open
wrong-answer todo and cannot be marked stable until it is fixed.

| Module | Open wrong-answer todos (`specs/todos/2026-11-11-…`) |
|---|---|
| Sort (and `Enum.sort_by`, which shares it) | `sort-no-stable-default` |
| Hamt | `hamt-low35-hash-collision` (`Map` and `DataFrame` mask their hashes and are not affected) |
| Decimal | `decimal-round-negative-places` |
| Bytes | `bytes-from-list-out-of-range`, `bytes-decode-base64-trailing-data` |
| Json | `json-control-bytes-raw` |
| Toml | `toml-to-string-unescaped` |
| Yaml | `yaml-seq-under-key-round-trip`, `yaml-map-in-seq-misindent`, `yaml-needs-quoting-case`, `yaml-newline-string-unquoted` |
| Compress | `compress-accept-encoding-case-and-qvalue` |
| Msgpack | `msgpack-bin-bytes-unchecked`, `msgpack-uint64-wraps` |
| Http | `http-parse-url-host-keeps-query` |
| HttpTransport | `http-compiled-response-parse-status-and-headers` (compiled only) |
| HttpClient | `http-client-basic-auth-not-base64`, `http-client-keepalive-retry-count-and-fd-leak`, `http-client-redirect-307-308-become-get`, and the HttpTransport bug above |
| Tls | `tls-https-get-single-read-and-ctx-leak` |
| Regex | `regex-case-insensitive-folds-class-escapes`, `regex-empty-match-drops-bytes`, `regex-mid-pattern-dollar-truncates` |
| DateTime | `datetime-day-of-week-negative` |
| Logger | `logger-logfmt-escaping`, `logger-json-nan-inf` |
| Gen | `gen-list-of-size-shrinks-change-length` |
| Csv | `csv-open-error-shape-compiled` (compiled only) |
| NodeQueue | `node-queue-withdraw-answers-oldest-waiter`, `node-queue-dead-connection-accounting` |
| GlobalRegistry | `global-registry-equal-clock-arrival-order` |
| ConsistentHash | `consistent-hash-wraps-to-last-entry` |
| CRDT | `crdt-orset-remove-no-tombstone`, `crdt-equal-not-structural`, `crdt-lwwregister-merge-not-commutative` |
| Channel | `channel-parse-cannot-read-serialize-output-or-phoenix-frames` |
| ChannelSocket | `channel-socket-join-is-a-stub` |
| Plot | `plot-fmt-float-drops-sign-and-truncates` |
| DataFrame | `dataframe-csv-reader-ignores-quotes`, `dataframe-nulls-stored-as-zero`, `dataframe-outer-join-loses-right-only-keys` |
| Js.Dom | `js-dom-unlisten-never-removes` |

Not stdlib modules, but wrong answers all the same: the `char_*` builtins
(`char-builtins-multibyte-backend-divergence`) and the native REPL
(`repl-zero-arg-closure-returns-zero`, `repl-int-result-printed-tagged`).

Csv also leaks its handle on a callback panic (`csv-handle-leak-on-callback-panic`). Modules with
no wrong-answer bug but an open hang, crash or leak: Crypto (`verify_password` panics compiled on iteration count 0), NodeSend, ClusterConn,
HttpServer (`spawn_n`), ChannelServer. OrderedMap and Hamt doc examples that pass `compare` or
`hash` do not compile until `compiled-builtin-passed-as-value-undefined-symbol` is fixed.

Modules from the list whose live claims are only API or cosmetic: Enum (`flat_map`), Seq, Flow,
OrderedMap, Range, BigInt, Random, Stats, Xml, ShellRender, WebSocket, DistLink, WorkDispatch,
Swim, SwimDriver, Membership, PubSub, Presence. List, Math and ClusterAuth have no live claim
left.
