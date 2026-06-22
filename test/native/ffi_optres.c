/* test/native/ffi_optres.c — the filled-in `forge ffi gen-c` artifact for
 * ffi_optres.march: the GENERATED fully-typed Option/Result field codecs
 * verbatim, plus shim bodies. Exercises decode + encode of record fields whose
 * types are Option(Int) / Option(String) / Result(Int, String). */
#include "march_ffi.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>

/* ── Generated codecs (record/variant <-> repr-C mirror) ── */
typedef struct { int32_t is_some; int64_t value; } Option_Int_c;
static Option_Int_c march_decode_Option_Int(march_value v) {
    Option_Int_c o;
    if (v == 0) o.is_some = 0;
    else { o.is_some = 1; o.value = march_get_int(v); }
    return o;
}
static march_value march_encode_Option_Int(Option_Int_c o) {
    if (!o.is_some) return march_none();
    return march_some(march_make_int(o.value));
}

typedef struct { int32_t is_some; march_slice value; } Option_String_c;
static Option_String_c march_decode_Option_String(march_value v) {
    Option_String_c o;
    if (v == 0) o.is_some = 0;
    else { o.is_some = 1; o.value = march_str_borrow(v); }
    return o;
}
static march_value march_encode_Option_String(Option_String_c o) {
    if (!o.is_some) return march_none();
    return march_some(march_str_new(o.value.ptr, o.value.len));
}

typedef struct { int32_t is_ok; int64_t ok; march_slice err; } Result_Int_String_c;
static Result_Int_String_c march_decode_Result_Int_String(march_value v) {
    Result_Int_String_c o;
    if (march_variant_tag(v) == 0) { o.is_ok = 1; o.ok = march_get_int(march_variant_field(v, 0)); }
    else { o.is_ok = 0; o.err = march_str_borrow(march_variant_field(v, 0)); }
    return o;
}
static march_value march_encode_Result_Int_String(Result_Int_String_c o) {
    if (o.is_ok) return march_ok(march_make_int(o.ok));
    return march_err(march_str_new(o.err.ptr, o.err.len));
}

typedef struct {
    Option_Int_c maybe;
    Option_String_c name;
    Result_Int_String_c res;
    int64_t tag;
} Box_c;
static Box_c march_decode_Box(march_value v) {
    Box_c o;
    o.maybe = march_decode_Option_Int(march_record_field(v, 0));
    o.name = march_decode_Option_String(march_record_field(v, 1));
    o.res = march_decode_Result_Int_String(march_record_field(v, 2));
    o.tag = march_record_field(v, 3);
    return o;
}
static march_value march_encode_Box(Box_c o) {
    march_value f[4];
    f[0] = march_encode_Option_Int(o.maybe);
    f[1] = march_encode_Option_String(o.name);
    f[2] = march_encode_Result_Int_String(o.res);
    f[3] = o.tag;
    return march_make_record("maybe:p;name:p;res:p;tag:i;", 4, f);
}

/* ── Shim bodies ── */

/* Build a Box with typed Option/Result fields: Some(42) / Some("hi") / Ok(100). */
march_value ffi_optres_make(int64_t tag) {
    static const char hi[] = "hi";
    Box_c b;
    b.tag = tag;
    b.maybe.is_some = 1; b.maybe.value = 42;
    b.name.is_some = 1; b.name.value.ptr = (const uint8_t *)hi; b.name.value.len = 2;
    b.res.is_ok = 1; b.res.ok = 100;
    return march_encode_Box(b);
}

/* Decode a Box and summarize "maybe/name/res" from its typed fields. */
march_value ffi_optres_classify(march_value v) {
    Box_c b = march_decode_Box(v);
    char buf[128];
    int p = 0;
    if (b.maybe.is_some) p += snprintf(buf + p, sizeof buf - p, "%lld", (long long)b.maybe.value);
    else { memcpy(buf + p, "none", 4); p += 4; }
    buf[p++] = '/';
    if (b.name.is_some) { memcpy(buf + p, b.name.value.ptr, b.name.value.len); p += (int)b.name.value.len; }
    else { memcpy(buf + p, "noname", 6); p += 6; }
    buf[p++] = '/';
    if (b.res.is_ok) p += snprintf(buf + p, sizeof buf - p, "ok:%lld", (long long)b.res.ok);
    else { memcpy(buf + p, "err:", 4); p += 4;
           memcpy(buf + p, b.res.err.ptr, b.res.err.len); p += (int)b.res.err.len; }
    return march_str_new((const uint8_t *)buf, (size_t)p);
}
