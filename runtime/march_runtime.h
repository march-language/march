#pragma once
#include <stdint.h>
#include <setjmp.h>

/* Object header layout (16 bytes):
 *   offset  0: int64_t  rc   (reference count)
 *   offset  8: int32_t  tag  (constructor tag)
 *   offset 12: int32_t  pad  (alignment)
 * Fields start at offset 16, each 8 bytes.
 * TInt fields stored as int64_t, TFloat as double, all others as pointer. */
typedef struct { int64_t rc; int32_t tag; int32_t pad; } march_hdr;

/* Heap allocation: allocates sz bytes zeroed, returns a pointer. */
void *march_alloc(int64_t sz);

/* Net count of live march objects (alloc + / free-on-rc=0 -). FFI/test leak
   gauge; see specs/2026-06-19-c-ffi-abi-design.md §14.4. */
int64_t march_live_allocs(void);

/* Reference counting (atomic — safe for cross-thread shared values). */
void  march_incrc(void *p);
void  march_decrc(void *p);
/* Decrement RC and return 1 if the object was freed (RC hit 0), 0 if still alive.
   Used when pattern-matching to conditionally IncRC extracted child pointers. */
int64_t march_decrc_freed(void *p);

/* Non-atomic reference counting — only safe for values provably owned by a
   single thread (no actor send in their lifetime).  Faster than atomic ops
   because they avoid memory barriers; the compiler may also optimize them
   into register increments. */
void  march_incrc_local(void *p);
void  march_decrc_local(void *p);

/* Flag the calling OS thread as running compiled March code outside the
 * scheduler (e.g. an HTTP thread-pool worker), forcing atomic "local"
 * refcount ops on that thread.  See march_rc_set_thread_concurrent in
 * march_runtime.c. */
void  march_rc_set_thread_concurrent(int on);

void  march_free(void *p);

/* I/O builtins. */
void  march_print(void *s);
void  march_println(void *s);
void  march_print_stderr(void *s);
void *march_io_read_line(void);
int64_t march_io_read_byte(void);
int64_t march_int_pow(int64_t base, int64_t exp);

/* Panic/todo primitive variants (return ptr so they satisfy polymorphic `a`). */
void *march_panic_ext(void *s);
void *march_todo_ext(void *s);

/* Call-stack frame table (used by compiled binaries for backtraces).
 * march_frame_t is stack-allocated at each March function's entry. */
typedef struct march_frame_t {
    const char         *fn_name;
    const char         *file;
    int                 line;
    struct march_frame_t *prev;
} march_frame_t;

void march_frame_push(march_frame_t *frame);
void march_frame_pop(void);
void march_frame_reset(void);

/* Time builtins. */
double  march_unix_time(void);

/* TypedArray builtins. */
void   *march_typed_array_from_list(void *list);
void   *march_typed_array_to_list(void *arr);
int64_t march_typed_array_length(void *arr);
void   *march_typed_array_get(void *arr, int64_t i);
void   *march_typed_array_set(void *arr, int64_t i, void *val);
void   *march_typed_array_create(int64_t len, void *default_val);
void   *march_typed_array_map(void *arr, void *f);
void   *march_typed_array_filter(void *arr, void *f);
void   *march_typed_array_fold(void *arr, void *acc, void *f);

/* Logger builtins. */
void   *march_logger_set_level(int64_t level);
int64_t march_logger_get_level(void);
void   *march_logger_add_context(void *key, void *value);
void   *march_logger_clear_context(void);
void   *march_logger_get_context(void);
void   *march_logger_write(void *level_str, void *msg, void *ctx, void *extra);

/* String builtins.
 *
 * march_string shares the 16-byte march_hdr prefix (rc/tag/pad) so that a
 * string heap cell is DISCRIMINABLE from an ADT/tuple/record cell by its tag
 * word at offset 8 — every string carries the reserved MARCH_STRING_TAG.
 * This lets march_value_to_string (the type-erased to_string path, hit when
 * the static type is a TVar that actually holds a string) recognize a string
 * and return it verbatim instead of misreading the layout and printing
 * "#<tag:len>".  len moves to offset 16 and data to offset 24; all access is
 * through the struct members, so recompilation keeps every offset correct.
 * Compiled code never bakes in the layout — it builds strings via
 * march_string_lit — so this is a runtime-only change. */
#define MARCH_STRING_TAG ((int32_t)-1) /* 0xFFFFFFFF — reserved sentinel, never a ctor index (ADT tags are >= 0). Matches the long-standing cross-heap copy convention in march_message.c. */
/* FFI resource cell (opaque native handle). Distinct reserved tag so the
 * RC free path can run the destructor. Layout: [rc][tag][pad][native_ptr@16]
 * [dtor@24][type_id@32] (40 bytes). See runtime/march_ffi.c. */
#define MARCH_RESOURCE_TAG ((int32_t)-2)
/* Boxed Float. The stage-2 target of the float-boxing design
 * (specs/plans/2026-07-13-float-boxing-design.md): a Float that flows through
 * a type-ERASED (ptr) slot is heap-boxed so it is discriminable from a tagged
 * int (odd) and a heap object (ADT tag >= 0), instead of the current raw-bits
 * bitcast that IS_HEAP_PTR accidentally accepts (→ RC-on-raw-bits SIGSEGV and
 * generic-compare-on-raw-bits silent wrong answers). Reserved negative tag,
 * joining the string/resource sentinels. Layout: [rc][tag][pad][val@16] (24
 * bytes). Concrete `double` fields and REPL/static Float slots stay unboxed;
 * only erased slots box. Introduced additive (nothing emits it yet) — the
 * codegen flip that populates erased slots with these is stage 2. */
#define MARCH_FLOAT_TAG ((int32_t)-3)
typedef struct { int64_t rc; int32_t tag; int32_t pad; double val; } march_float_box;
/* Allocate a boxed Float (rc=1, tag=MARCH_FLOAT_TAG). */
void   *march_alloc_float(double v);
/* Read the double out of a boxed Float. Undefined if [p] is not a float box. */
double  march_unbox_float(void *p);
typedef struct { int64_t rc; int32_t tag; int32_t pad; int64_t len; char data[]; } march_string;
/* Allocate an uninitialised-data march_string of byte length [len], with the
 * header (rc=1, tag=MARCH_STRING_TAG, pad=0, len) filled in.  Callers fill
 * data[0..len] and the NUL terminator.  Centralises header init so no string
 * site can leave the discriminator tag unset. */
void *march_string_alloc(int64_t len);
void *march_string_lit(const char *utf8, int64_t len);
void *march_int_to_string(int64_t n);
void *march_float_to_string(double f);
void *march_bool_to_string(int64_t b);
void *march_string_concat(void *a, void *b);
int64_t march_string_eq(void *a, void *b);
int64_t march_poly_eq(void *a, void *b);
/* Ordered compare (-1/0/1) for two values in type-ERASED (ptr) slots, when
 * the static type gives no strategy. Dispatches on runtime shape: tagged
 * ints, boxed floats (MARCH_FLOAT_TAG), and strings each compare by value;
 * other heap values fall back to 0 (a full structural order needs static
 * type info unavailable here). The generic-compare half of the float-boxing
 * design — must be wired at the codegen fallback_cmp site in the same stage
 * that boxes floats, else box-only turns wrong-int-compare into
 * wrong-pointer-compare. */
int64_t march_poly_compare(void *a, void *b);
/* Extended string builtins used by the compiled stdlib. */
int64_t march_string_byte_length(void *s);
int64_t march_string_is_empty(void *s);
void   *march_string_to_int(void *s);
void   *march_string_join(void *list, void *sep);
void   *march_codepoint_to_utf8(int64_t cp);  /* Encode codepoint as UTF-8, returns Some(string) or None */

/* Actor link builtins. */
/* link: establish a bidirectional crash-propagation link between two actors.
   If either dies, the other receives a Down notification (and may crash too). */
void    march_link(void *actor_a, void *actor_b);
/* unlink: cancel a previously established link (best-effort, no-op if absent). */
void    march_unlink(void *actor_a, void *actor_b);
/* register_supervisor: record an actor as a supervisor with a given restart
   strategy (0=one_for_one, 1=one_for_all, 2=rest_for_one), max_restarts, and
   time window in seconds.  Children are registered separately via march_link. */
void    march_register_supervisor(void *supervisor, int64_t strategy,
                                   int64_t max_restarts, int64_t window_secs);

/* ── Phase 5: Actor state migration ─────────────────────────────────── */

/* Tag value for system migrate messages.  Chosen to be far outside the range
 * of normal March ADT constructor tags (which start at 0 and are bounded by
 * the number of constructors per type, typically < 1000). */
#define MARCH_MIGRATE_TAG ((int64_t)0x4D494752L)   /* "MIGR" */

/* System message injected into an actor's mailbox to trigger state migration.
 * Layout: standard 16-byte march object header (rc at 0, tag at 8) so that
 * actor_green_thread can detect it by checking ((int64_t*)msg)[1].
 * Allocated with malloc() by march_actor_broadcast_migrate; freed with free()
 * (NOT march_decrc) by actor_green_thread after handling. */
typedef struct {
    int64_t  _rc;              /* always 1 (not reference-counted) */
    int64_t  _tag;             /* MARCH_MIGRATE_TAG */
    void    *(*migrate_fn)(void *);  /* migrate_fn(old_state_ptr) → new_state_ptr, or NULL */
} march_migrate_msg_t;

/* Set the dispatch-table NAME_ID for a hot-reload actor.  Must be called
 * immediately after march_spawn().  name_id is the slot ID registered for
 * the actor's _dispatch function.  No-op if actor has no meta entry. */
void march_actor_set_dispatch_id(void *actor, uint32_t name_id);

/* Register the global tag of the actor's FIRST message constructor (its
 * "call tag base").  Emitted by codegen right after the actor record's
 * alloc; march_actor_call adds the sentinel's ctor index to this base to
 * address the handler positionally under F19's globally-unique msg tags. */
void march_actor_set_call_base(void *actor, int64_t base);

/* Walk all live actors whose dispatch_name_id equals [dispatch_name_id] and
 * inject a MARCH_MIGRATE_TAG message so each actor migrates its state on
 * the next turn.  migrate_fn may be NULL (skip state transform). */
void march_actor_broadcast_migrate(uint32_t dispatch_name_id,
                                   void *(*migrate_fn)(void *));

/* Actor builtins.
 * Actor object layout (on top of the standard 16-byte header):
 *   offset 16: ptr     dispatch fn  (field 0, stored as closure struct)
 *   offset 24: int64_t alive flag   (field 1; 1=alive, 0=dead)
 *   offset 32+: state fields        (fields 2+, alphabetical order)
 *   -- in --hot-reload builds only:
 *   offset 32: ptr     state record (field 2, $f_state ptr, replaces inline fields)
 * As int64_t array: [0]=rc [1]=tag+pad [2]=dispatch [3]=alive [4+]=state
 *   (hot-reload: [4]=ptr-to-state-record instead of inline state fields) */
void    march_kill(void *actor);
int64_t march_is_alive(void *actor);
/* Register an actor with the scheduler; returns actor unchanged. */
void   *march_spawn(void *actor);
/* Read word at int64_t index from actor struct (0=rc,1=tag,2=dispatch,...). */
int64_t march_actor_get_int(void *actor, int64_t index);
/* Send a message (takes ownership of msg's RC).
 * Returns Option(Unit): None (tag 0) if dead, Some(()) (tag 1) if enqueued. */
void   *march_send(void *actor, void *msg);
/* Process all actors in the run queue (called automatically by march_send). */
void    march_run_scheduler(void);
/* Spawn a no-arg C function as a green thread (for the main entrypoint). */
void    march_spawn_main(void (*fn)(void));
/* Signal.watch (stdlib/signal.march): register/remove a deferred OS-signal
 * watcher (closure passed OWNED), send a signal to self, and drain pending
 * watchers from a scheduler / event-loop body (never from signal context). */
void    march_signal_watch(int64_t code, void *clo);
void    march_signal_unwatch(int64_t code);
void    march_signal_raise_self(int64_t code);
void    march_signal_drain(void);
/* Spawn a March thunk closure (fn () -> T) as an async green thread.
 * Returns a boxed Task handle (32 bytes: header + proc ptr + result ptr). */
void   *march_task_spawn_thunk(void *clo_ptr);
/* Wait for a task to complete; returns Ok(result) or Err(msg). */
void   *march_task_await(void *task_obj);
/* Spawn a thunk closure with a cancel token; yields cancel checks. */
void   *march_task_spawn_with_cancel_thunk(void *clo_ptr, void *tok_ptr);
/* Mark a task's green thread as DEAD (cooperative cancel). */
void    march_task_cancel_by_id(void *task_obj);

/* Float builtins. */
double  march_float_abs(double f);
int64_t march_float_ceil(double f);
int64_t march_float_floor(double f);
int64_t march_float_round(double f);
int64_t march_float_truncate(double f);
double  march_int_to_float(int64_t n);

/* Math builtins. */
double march_math_sin(double f);
double march_math_cos(double f);
double march_math_tan(double f);
double march_math_asin(double f);
double march_math_acos(double f);
double march_math_atan(double f);
double march_math_atan2(double y, double x);
double march_math_sinh(double f);
double march_math_cosh(double f);
double march_math_tanh(double f);
double march_math_sqrt(double f);
double march_math_cbrt(double f);
double march_math_exp(double f);
double march_math_exp2(double f);
double march_math_log(double f);
double march_math_log2(double f);
double march_math_log10(double f);
double march_math_pow(double b, double e);

/* Extended string builtins. */
int64_t march_string_contains(void *s, void *sub);
int64_t march_string_starts_with(void *s, void *prefix);
int64_t march_string_ends_with(void *s, void *suffix);
void   *march_string_slice(void *s, int64_t start, int64_t len);
void   *march_string_split(void *s, void *sep);
void   *march_string_split_first(void *s, void *sep);
void   *march_string_replace(void *s, void *old, void *new_);
void   *march_string_replace_all(void *s, void *old, void *new_);
void   *march_string_to_lowercase(void *s);
void   *march_string_to_uppercase(void *s);
void   *march_string_trim(void *s);
void   *march_string_trim_start(void *s);
void   *march_string_trim_end(void *s);
void   *march_string_repeat(void *s, int64_t n);
void   *march_string_reverse(void *s);
void   *march_string_pad_left(void *s, int64_t width, void *fill);
void   *march_string_pad_right(void *s, int64_t width, void *fill);
int64_t march_string_grapheme_count(void *s);
void   *march_string_index_of(void *s, void *sub);
void   *march_string_last_index_of(void *s, void *sub);
void   *march_string_to_float(void *s);

/* List builtins. */
void *march_list_append(void *a, void *b);
void *march_list_concat(void *lists);

/* File/Dir builtins. */
int64_t march_file_exists(void *s);
int64_t march_dir_exists(void *s);
void   *march_file_open(void *path);
void   *march_file_close(void *handle);
void   *march_file_read(void *path);
void   *march_file_read_line(void *handle);
void   *march_file_read_chunk(void *handle, int64_t size);
void   *march_file_write(void *path, void *data);
void   *march_file_append(void *path, void *data);
void   *march_file_delete(void *path);
void   *march_file_copy(void *src, void *dst);
void   *march_file_rename(void *src, void *dst);
void   *march_file_stat(void *path);

/* CSV builtins. */
void   *march_csv_open(void *path, void *delim, void *mode);
void   *march_csv_next_row(void *handle);
void   *march_csv_close(void *handle);

/* Resource ownership. */
void    march_own(void *pid, void *value);

/* Capability revocation (Phase 3).  All three take the March-level Cap heap
 * object (words: hdr, hdr, actor ptr, pid_index, epoch — built by
 * march_get_cap), matching the interpreter's Cap(a)-typed builtins. */
/* Explicitly revoke a capability.  After this call, march_send_checked and
 * march_is_cap_valid reject the cap.  Idempotent.  Returns the :ok atom
 * (:error for a null/non-heap cap such as the root_cap sentinel). */
int64_t march_revoke_cap(void *cap);
/* Check whether cap is still valid:
 * returns 1 if valid (actor alive, epoch matches, not revoked), 0 otherwise. */
int64_t march_is_cap_valid(void *cap);
/* Capability-checked send: validates liveness, epoch, and revocation before
 * enqueuing msg.  Returns the :ok atom on delivery, :error otherwise. */
int64_t march_send_checked(void *cap, void *msg);

/* Value pretty-printing. */
void *march_value_to_string(void *v);

/* Process builtins */
void  march_process_argv_init(int argc, char **argv);
void *march_process_argv(void);

/* Vault builtins (march_extras.c). */
void   *march_vault_new(void *name);
void   *march_vault_whereis(void *name);
void   *march_vault_set(void *table, void *key, void *value);
void   *march_vault_set_ttl(void *table, void *key, void *value, int64_t ttl_secs);
void   *march_vault_get(void *table, void *key);
void   *march_vault_drop(void *table, void *key);
void   *march_vault_update(void *table, void *key, void *f);
int64_t march_vault_size(void *table);
void   *march_vault_keys(void *table);
/* String-namespace helpers: accept a String name, auto-create/find vault. */
void   *march_vault_ns_set(void *ns, void *key, void *value);
void   *march_vault_ns_get(void *ns, void *key);
void   *march_vault_ns_drop(void *ns, void *key);

/* Crypto builtins (march_extras.c). */
void   *march_sha256(void *data);
void   *march_sha512(void *data);
void   *march_hmac_sha256(void *key, void *msg);
void   *march_pbkdf2_sha256(void *pass, void *salt, int64_t iters, int64_t dklen);
void   *march_base64_encode(void *input);
void   *march_base64_decode(void *str);
void   *march_random_bytes(int64_t n);
void   *march_uuid_v4(void);

/* System introspection builtins (march_extras.c). */
int64_t march_sys_uptime_ms(void);
int64_t march_sys_cpu_count(void);
int64_t march_sys_heap_bytes(void);
int64_t march_sys_word_size(void);
int64_t march_sys_minor_gcs(void);
int64_t march_sys_major_gcs(void);
int64_t march_sys_actor_count(void);
void   *march_get_version(void);

/* Session-typed channel builtins (binary). */
void   *march_chan_new(void *proto_name);
void   *march_chan_send(void *ep, void *val);
void   *march_chan_recv(void *ep);
int64_t march_chan_close(void *ep);
void   *march_chan_choose(void *ep, void *label);
void   *march_chan_offer(void *ep);

/* Multi-party session type (MPST) builtins. */
void   *march_mpst_new(void *proto_name, int64_t n_roles, void *roles_csv);
void   *march_mpst_send(void *ep, void *target_role_str, void *val);
void   *march_mpst_recv(void *ep, void *source_role_str);
int64_t march_mpst_close(void *ep);

/* Test harness — used by --test compiled binaries. */
extern jmp_buf  march_test_jmp_buf;
extern int      march_test_in_test;
extern char     march_test_fail_buf[4096];
void    march_test_init(int32_t argc, char **argv);
void    march_test_setup_all(void (*fn)(void));
void    march_test_run(void (*fn)(void), const char *name, void (*setup)(void));
int32_t march_test_report(void);
