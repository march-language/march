#pragma once
#include <stdint.h>

/* Object header layout (16 bytes):
 *   offset  0: int64_t  rc   (reference count)
 *   offset  8: int32_t  tag  (constructor tag)
 *   offset 12: int32_t  pad  (alignment)
 * Fields start at offset 16, each 8 bytes.
 * TInt fields stored as int64_t, TFloat as double, all others as pointer. */
typedef struct { int64_t rc; int32_t tag; int32_t pad; } march_hdr;

/* Heap allocation: allocates sz bytes zeroed, returns a pointer. */
void *march_alloc(int64_t sz);

/* Reference counting. */
void  march_incrc(void *p);
void  march_decrc(void *p);
/* Decrement RC and return 1 if the object was freed (RC hit 0), 0 if still alive.
   Used when pattern-matching to conditionally IncRC extracted child pointers. */
int64_t march_decrc_freed(void *p);

void  march_free(void *p);

/* I/O builtins. */
void  march_print(void *s);
void  march_println(void *s);

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

/* Value pretty-printing. */
void *march_value_to_string(void *v);
