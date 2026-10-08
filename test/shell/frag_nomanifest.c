/* A fragment without a cap manifest (an older or hand-built client): the
 * node refuses it after loading, before it runs. */
#include <stdint.h>
void *march_string_lit(const char *utf8, int64_t len);
void *__shell_frag_nomanifest(void) {
    return march_string_lit("ran", 3);
}
