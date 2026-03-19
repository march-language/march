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

/* Actor builtins.
 * Actor object layout (on top of the standard 16-byte header):
 *   offset 16: ptr     dispatch fn  (field 0)
 *   offset 24: int64_t alive flag   (field 1; 1=alive, 0=dead)
 *   offset 32+: state fields        (fields 2+, alphabetical order)
 * As int64_t array: [0]=rc [1]=tag+pad [2]=dispatch [3]=alive [4+]=state */
void  march_kill(void *actor);
int64_t march_is_alive(void *actor);
/* Returns Option(Unit): None (tag 0) if dead, Some(()) (tag 1) if dispatch ran. */
void *march_send(void *actor, void *msg);
