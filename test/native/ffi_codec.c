/* test/native/ffi_codec.c — the realistic post-`forge ffi gen-c` artifact for
 * ffi_codec.march: the GENERATED record/variant codecs verbatim, with the shim
 * TODOs filled in.  Exercises decode (March-built value -> C struct) and encode
 * (C struct -> March value) both ways.  Compiled via `--ffi-c`. */
#include "march_ffi.h"
#include <stdint.h>

/* ── Generated codecs (record/variant <-> repr-C mirror) ── */
typedef struct {
    int32_t tag;
    union {
        struct { int64_t f0; } Circle;
        struct { int64_t f0; int64_t f1; } Rect;
    } u;
} Shape_c;
static Shape_c march_decode_Shape(march_value v) {
    Shape_c o;
    o.tag = march_variant_tag(v);
    switch (o.tag) {
      case 0:
        o.u.Circle.f0 = march_variant_field(v, 0);
        break;
      case 1:
        o.u.Rect.f0 = march_variant_field(v, 0);
        o.u.Rect.f1 = march_variant_field(v, 1);
        break;
      default: break;
    }
    return o;
}
static march_value march_encode_Shape(Shape_c o) {
    switch (o.tag) {
      case 0: {
        march_value f[1];
        f[0] = o.u.Circle.f0;
        return march_make_variant(0, 1, f);
      }
      case 1: {
        march_value f[2];
        f[0] = o.u.Rect.f0;
        f[1] = o.u.Rect.f1;
        return march_make_variant(1, 2, f);
      }
    }
    return march_make_variant(o.tag, 0, (const march_value *)0);
}

typedef struct {
    int64_t x;
    int64_t y;
} Point_c;
static Point_c march_decode_Point(march_value v) {
    Point_c o;
    o.x = march_record_field(v, 0);
    o.y = march_record_field(v, 1);
    return o;
}
static march_value march_encode_Point(Point_c o) {
    march_value f[2];
    f[0] = o.x;
    f[1] = o.y;
    return march_make_record("x:i;y:i;", 2, f);
}

/* ── Shim bodies (TODOs filled in) ── */

/* area(s : Shape) : Int — decode a March-built Shape, compute. */
int64_t ffi_codec_area(march_value s_v) {
    Shape_c s = march_decode_Shape(s_v);
    switch (s.tag) {
      case 0:  return 3 * s.u.Circle.f0 * s.u.Circle.f0;
      default: return s.u.Rect.f0 * s.u.Rect.f1;
    }
}

/* translate(p : Point, dx, dy) : Point — decode a Point, encode a fresh one. */
march_value ffi_codec_translate(march_value p_v, int64_t dx, int64_t dy) {
    Point_c p = march_decode_Point(p_v);
    Point_c q = { p.x + dx, p.y + dy };
    return march_encode_Point(q);
}

/* widen(s : Shape) : Shape — Circle(r) -> Rect(r,r); Rect passes through. */
march_value ffi_codec_widen(march_value s_v) {
    Shape_c s = march_decode_Shape(s_v);
    if (s.tag == 0) {
        Shape_c r; r.tag = 1;
        r.u.Rect.f0 = s.u.Circle.f0;
        r.u.Rect.f1 = s.u.Circle.f0;
        return march_encode_Shape(r);
    }
    return march_encode_Shape(s);
}
