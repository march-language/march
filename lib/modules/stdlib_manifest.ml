(** The stdlib load manifest — which files the compiler eagerly loads.

    Lives in a library rather than in bin/main.ml so a TEST can assert the
    manifest is exhaustive over stdlib/.  That is not bookkeeping: a module
    absent from [stdlib_file_list] is reachable only through
    [Module_registry.ensure_loaded], which extracts export SHAPES without
    running the body through inference in its caller's context.  A generic
    `Option`/`Result` such a module exports then reaches monomorphization with
    an unresolved tvar, falls back to a boxed representation, and is read by a
    concrete caller expecting the niche encoding — a wrong VALUE, no
    diagnostic, compiled only, different garbage per run.

    That class has been point-fixed three times by adding the newly-noticed
    files to the list (deque, cluster_load, then six more on 2026-08-01).  The
    list being exhaustive is the invariant those fixes were each restoring by
    hand; [Stdlib_manifest_test] in test/test_compiler.ml now holds it.

    See specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md *)

(** The ordered list of stdlib file names. *)
let stdlib_file_list = [
  "prelude.march";
  "option.march";
  "result.march";
  "list.march";
  "hamt.march";
  "map.march";
  "math.march";
  "string.march";
  "iolist.march";
  (* deque.march must load EAGERLY (full body typecheck), not lazily.  A
     lazily-loaded module's call sites leave the caller's let-binders as
     unresolved '_ tvars in the type_map, so monomorphization cannot
     specialize a generic function like Deque.pop_front : Deque(a) ->
     (Option(a), Deque(a)) — the generic body then allocates a BOXED
     Some cell while the concrete caller decodes the tuple field as a
     NICHE Option(Int), reading the box's heap ADDRESS as the payload.
     Symptom: bench/deque_ops.march printed a raw pointer for a popped
     Int interpreted correctly, and its drain loop never terminated
     ("deque_ops hangs compiled").  The lazy-vs-eager split changing
     REPRESENTATION decisions is a compiler bug class of its own, filed
     in specs/todos.md; eager-loading Deque removes this instance. *)
  "deque.march";
  "html.march";
  "sigil.march";
  "http.march";
  "http_transport.march";
  "http_client.march";
  "seq.march";
  "path.march";
  "file.march";
  "dir.march";
  "sort.march";
  "csv.march";
  "websocket.march";
  "http_server.march";
  "iterable.march";
  "set.march";
  "hash_map.march";
  "array.march";
  "bigint.march";
  "decimal.march";
  "duration.march";
  "bytes.march";
  "msgpack.march";
  "compress.march";
  "parser.march";
  "toml.march";
  "xml.march";
  "yaml.march";
  "socket.march";
  "dns.march";
  "process.march";
  "io.march";
  "system.march";
  "cluster.march";
  "cluster_load.march";
  (* consistent_hash.march and work_dispatch.march must load EAGERLY, same
     class of bug as the deque.march note above: a lazily-loaded module's
     generic Option/Result-returning functions (e.g. ConsistentHash.get,
     WorkDispatch functions) reach mono with unresolved call-site tvars and
     default to a Boxed representation, while a concrete caller (e.g.
     Option(Int)) expects the niche encoding — the caller then reads the
     box's heap address as the payload. Confirmed live 2026-08-01 via
     ConsistentHash.get returning a garbage pointer instead of the stored
     Int, compiled only. *)
  "consistent_hash.march";
  "work_dispatch.march";
  "logger.march";
  "actor.march";
  "scheduler.march";
  "flow.march";
  "json.march";
  "json_stream.march";
  "regex.march";
  "datetime.march";
  "queue.march";
  "aho_corasick.march";
  "ring_buf.march";
  "enum.march";
  "random.march";
  "gen.march";
  "check.march";
  "stats.march";
  "plot.march";
  "dataframe.march";
  "tls.march";
  "uuid.march";
  "vault.march";
  "channel.march";
  "pubsub.march";
  "channel_server.march";
  "channel_socket.march";
  "presence.march";
  "env.march";
  "config.march";
  "cli.march";
  "test.march";
  "tuple.march";
  "char.march";
  "ordered_map.march";
  "sorted_set.march";
  "range.march";
  "crypto.march";
  "base64.march";
  "native_array.march";
  "simd.march";
  "task.march";
  "signal.march";
  "rrb_vec.march";
  "parallel.march";
  "uri.march";
  "forge_nb.march";
  "handle.march";
  (* CRDT primitives — loaded before distributed OTP modules that depend on them *)
  "vector_clock.march";
  "crdt.march";
  "merkle.march";
  (* Distributed OTP — added after all other stdlib deps are loaded *)
  "net_frame.march";
  "cluster_auth.march";
  "node_identity.march";
  "handshake.march";
  "global_pid.march";
  "remote_call.march";
  "node_rpc.march";
  "peer_registry.march";
  "net_kernel.march";
  "membership.march";
  "swim.march";
  "swim_driver.march";
  "global_registry.march";
  "cluster_conn.march";
  "node_call.march";
  (* dist_link.march / dist_supervisor.march: same lazy-load representation
     bug as above (see the deque.march / consistent_hash.march notes) — both
     export Option/Result-returning generics over concrete node/monitor
     types. dist_supervisor depends on dist_link, so it must come after. *)
  "dist_link.march";
  "dist_supervisor.march";
  (* Session transport capability (proof cap + dictionary). References
     Bytes, so it must sit after bytes.march; it has no dependents. *)
  "session.march"
]

let js_only_stdlib_file_list = ["dom.march"; "canvas.march"; "audio.march"]

(** Files under stdlib/ deliberately NOT eagerly loaded, and why.

    Adding to this list is the escape hatch the exhaustiveness test points at.
    Do it only with the consequence above understood: a lazily-loaded module
    that exports a generic `Option`/`Result` over a niche-eligible type will
    miscompile silently at a concrete call site. *)
let lazily_loaded_allowlist =
  [ (* The regression fixture for that very bug — it MUST stay lazy or it stops
       demonstrating the lazy path.  See its own doc comment before touching. *)
    "lazy_niche_probe.march" ]

(** Every file the compiler knows about, by any route. *)
let all_known =
  stdlib_file_list @ js_only_stdlib_file_list @ lazily_loaded_allowlist
