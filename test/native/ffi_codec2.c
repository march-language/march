/* test/native/ffi_codec2.c — filled-in `forge ffi gen-c` artifact for ffi_codec2.march.
 * Exercises the three codec gaps added in the codec-completeness pass:
 *   - Option(Float)  : fully boxed (march_none_boxed / march_some_boxed)
 *   - Option(Unit)   : mixed niche (niche None=0, boxed Some)
 *   - List(Int)      : malloc-owned C array ↔ singly-linked march_list_cons cells
 * The C binding builds and decodes all values; March passes them through without
 * touching the list or boxed-option internals. */
#include "march_ffi.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ── Generated codecs (output of `forge ffi gen-c ffi_codec2.march`) ── */

/* Option_Float: fully boxed — 0.0 bits alias None=0, so both arms are heap cells. */
typedef struct { int32_t is_some; double value; } Option_Float_c;
static Option_Float_c march_decode_Option_Float(march_value v) {
    Option_Float_c o;
    if (march_variant_tag(v) == 0) o.is_some = 0;
    else { o.is_some = 1; o.value = march_get_float(march_variant_field(v, 0)); }
    return o;
}
static march_value march_encode_Option_Float(Option_Float_c o) {
    if (!o.is_some) return march_none_boxed();
    return march_some_boxed(march_make_float(o.value));
}

/* Option_Unit: mixed niche — None=0 (niche), Some(())=boxed heap cell; no value field. */
typedef struct { int32_t is_some; } Option_Unit_c;
static Option_Unit_c march_decode_Option_Unit(march_value v) {
    Option_Unit_c o;
    o.is_some = (v != 0);
    return o;
}
static march_value march_encode_Option_Unit(Option_Unit_c o) {
    if (!o.is_some) return march_none();
    return march_some_boxed(0);  /* Unit Some is boxed */
}

/* List_Int_c: malloc-owned array; caller must free items. */
typedef struct { int64_t *items; int32_t length; } List_Int_c;
static List_Int_c march_decode_List_Int(march_value v) {
    List_Int_c o;
    o.length = march_list_length(v);
    o.items = o.length ? (int64_t *)malloc(o.length * sizeof(int64_t)) : 0;
    for (int32_t i = 0; i < o.length; i++) {
        o.items[i] = march_get_int(march_variant_field(v, 0));
        v = march_variant_field(v, 1);
    }
    return o;
}
static march_value march_encode_List_Int(List_Int_c o) {
    march_value tail = march_list_nil();
    for (int32_t i = o.length - 1; i >= 0; i--)
        tail = march_list_cons(march_make_int(o.items[i]), tail);
    return tail;
}

/* Sample_c mirror struct (fields in name-sorted order: avg, data, flag). */
typedef struct {
    Option_Float_c avg;
    List_Int_c data;
    Option_Unit_c flag;
} Sample_c;
static Sample_c march_decode_Sample(march_value v) {
    Sample_c o;
    o.avg  = march_decode_Option_Float(march_record_field(v, 0));
    o.data = march_decode_List_Int(march_record_field(v, 1));
    o.flag = march_decode_Option_Unit(march_record_field(v, 2));
    return o;
}
static march_value march_encode_Sample(Sample_c o) {
    march_value f[3];
    f[0] = march_encode_Option_Float(o.avg);
    f[1] = march_encode_List_Int(o.data);
    f[2] = march_encode_Option_Unit(o.flag);
    return march_make_record("avg:p;data:p;flag:p;", 3, f);
}

/* ── Shim bodies ── */

/* Build a Sample from C: n>0 → Some(1.5)/Some(())/[10,20,...,n*10]; n=0 → None/None/[]. */
march_value ffi_codec2_make(int64_t n) {
    Sample_c s;
    if (n > 0) {
        s.avg.is_some = 1; s.avg.value = 1.5;
        s.flag.is_some = 1;
        s.data.length = (int32_t)n;
        s.data.items = (int64_t *)malloc((size_t)n * sizeof(int64_t));
        for (int32_t i = 0; i < (int32_t)n; i++) s.data.items[i] = (int64_t)(i + 1) * 10;
    } else {
        s.avg.is_some = 0;
        s.flag.is_some = 0;
        s.data.length = 0; s.data.items = 0;
    }
    march_value result = march_encode_Sample(s);
    free(s.data.items);
    return result;
}

/* Decode a March-passed Sample and format "avg=.../flag=.../data=..." as a String. */
march_value ffi_codec2_describe(march_value v) {
    Sample_c s = march_decode_Sample(v);
    char buf[512];
    int p = 0;
    memcpy(buf + p, "avg=", 4); p += 4;
    if (s.avg.is_some) p += snprintf(buf + p, sizeof buf - p, "%.1f", s.avg.value);
    else { memcpy(buf + p, "none", 4); p += 4; }
    buf[p++] = '/';
    memcpy(buf + p, "flag=", 5); p += 5;
    if (s.flag.is_some) { memcpy(buf + p, "yes", 3); p += 3; }
    else { memcpy(buf + p, "no", 2); p += 2; }
    buf[p++] = '/';
    memcpy(buf + p, "data=", 5); p += 5;
    for (int32_t i = 0; i < s.data.length; i++) {
        if (i > 0) buf[p++] = ',';
        p += snprintf(buf + p, sizeof buf - p, "%lld", (long long)s.data.items[i]);
    }
    free(s.data.items);
    return march_str_new((const uint8_t *)buf, (size_t)p);
}
