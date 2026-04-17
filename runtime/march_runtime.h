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

void  march_free(void *p);

/* I/O builtins. */
void  march_print(void *s);
void  march_println(void *s);
void  march_print_stderr(void *s);
void *march_io_read_line(void);
int64_t march_int_pow(int64_t base, int64_t exp);

/* Panic/todo primitive variants (return ptr so they satisfy polymorphic `a`). */
void *march_panic_ext(void *s);
void *march_todo_ext(void *s);

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

/* String builtins. */
typedef struct { int64_t rc; int64_t len; char data[]; } march_string;
void *march_string_lit(const char *utf8, int64_t len);
void *march_int_to_string(int64_t n);
void *march_float_to_string(double f);
void *march_bool_to_string(int64_t b);
void *march_string_concat(void *a, void *b);
int64_t march_string_eq(void *a, void *b);
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

/* Actor builtins.
 * Actor object layout (on top of the standard 16-byte header):
 *   offset 16: ptr     dispatch fn  (field 0, stored as closure struct)
 *   offset 24: int64_t alive flag   (field 1; 1=alive, 0=dead)
 *   offset 32+: state fields        (fields 2+, alphabetical order)
 * As int64_t array: [0]=rc [1]=tag+pad [2]=dispatch [3]=alive [4+]=state */
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
/* Spawn a March thunk closure (fn () -> T) as an async green thread.
 * Returns a boxed Task handle. */
void   *march_task_spawn_thunk(void *clo_ptr);

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

/* Capability revocation (Phase 3). */
/* Explicitly revoke a capability identified by (pid_index, epoch).
 * After this call, march_send_checked and march_is_cap_valid reject the cap.
 * Idempotent — safe to call more than once for the same cap. */
void    march_revoke_cap(int64_t pid_index, int64_t epoch);
/* Check whether (pid_index, epoch) is still a valid capability:
 * returns 1 if valid (actor alive, epoch matches, not revoked), 0 otherwise. */
int64_t march_is_cap_valid(int64_t pid_index, int64_t epoch);
/* Capability-checked send: validates liveness, epoch, and revocation before
 * enqueuing msg.  No-op if the capability is invalid. */
void    march_send_checked(void *cap, void *msg);

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
void   *march_mpst_new(void *proto_name, int64_t n_roles);
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
