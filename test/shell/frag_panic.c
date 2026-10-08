/* A fragment that panics: the node answers PANIC and keeps serving. */
#include <stdint.h>
const char __march_cap_manifest[] = "";
void *march_string_lit(const char *utf8, int64_t len);
void  march_print(void *s);
void  march_panic(void *s);
void *__shell_frag_panic(void) {
    march_print(march_string_lit("before ", 7));
    march_panic(march_string_lit("fragment panicked", 17));
    return 0;
}
