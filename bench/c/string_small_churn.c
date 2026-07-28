/* C counterpart of bench/string_small_churn.march.
 *
 * The floor: malloc per string, manual sizing, no refcount, no SSO. March's
 * march_string_alloc is a malloc plus a 24-byte header, so this bounds how much
 * of March's cost is allocation itself versus everything the runtime adds on
 * top.
 *
 * Must print checksum=17793810, identical to the March version. A different
 * checksum means the two are not doing the same work and the timing is void. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    long long acc = 0;
    char numbuf[24];
    for (long long i = 0; i < 2000000; i++) {
        int nlen = snprintf(numbuf, sizeof numbuf, "%lld", i % 97);
        size_t name_len = 6 + (size_t)nlen;
        char *name = malloc(name_len + 1);
        memcpy(name, "x-req-", 6);
        memcpy(name + 6, numbuf, (size_t)nlen);
        name[name_len] = '\0';

        int ilen = snprintf(numbuf, sizeof numbuf, "%lld", i);
        size_t value_len = 1 + (size_t)ilen + 9;
        char *value = malloc(value_len + 1);
        value[0] = 'v';
        memcpy(value + 1, numbuf, (size_t)ilen);
        memcpy(value + 1 + ilen, "-abcdefgh", 9);
        value[value_len] = '\0';

        size_t pair_len = name_len + 2 + value_len;
        char *pair = malloc(pair_len + 1);
        memcpy(pair, name, name_len);
        memcpy(pair + name_len, ": ", 2);
        memcpy(pair + name_len + 2, value, value_len);
        pair[pair_len] = '\0';

        int bump = (pair_len >= 6 && memcmp(pair, "x-req-", 6) == 0) ? 1 : 0;
        acc += (long long)name_len + bump;

        free(name); free(value); free(pair);
    }
    printf("checksum=%lld\n", acc);
    return 0;
}
