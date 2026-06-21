/* lib/eval/eval_ffi_stubs.c — dynamic C-call trampoline for the tree-walking
 * interpreter's FFI (Phase 4, primitives only).
 *
 * The interpreter cannot statically know an extern's C signature, and there is
 * no libffi available, so we use fixed-arity trampolines that cast the resolved
 * function pointer.  Integer/pointer args are passed in GP registers (x0-x7 on
 * arm64); FLOAT ARGUMENTS ARE NOT SUPPORTED (they require FP registers).  Two
 * return shapes are covered: int64 (dyncall_i) and double (dyncall_d).
 *
 * Symbols are prefixed `march_eval_` to avoid clashing with the JIT's identical
 * dlopen/dlsym helpers (both libs are linked into the compiler binary). */
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <stdint.h>
#include <dlfcn.h>

CAMLprim value march_eval_dlopen(value path) {
    CAMLparam1(path);
    void *h = dlopen(String_val(path), RTLD_NOW | RTLD_GLOBAL);
    CAMLreturn(caml_copy_nativeint((intnat)h));
}

CAMLprim value march_eval_dlsym(value handle, value name) {
    CAMLparam2(handle, name);
    void *h = (void *)Nativeint_val(handle);
    /* handle 0 = look up in the global symbol scope (already-loaded libs) */
    void *f = dlsym(h ? h : RTLD_DEFAULT, String_val(name));
    CAMLreturn(caml_copy_nativeint((intnat)f));
}

static int64_t dyncall_i(void *fn, const int64_t *a, int n) {
    switch (n) {
        case 0: return ((int64_t (*)(void)) fn)();
        case 1: return ((int64_t (*)(int64_t)) fn)(a[0]);
        case 2: return ((int64_t (*)(int64_t,int64_t)) fn)(a[0],a[1]);
        case 3: return ((int64_t (*)(int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2]);
        case 4: return ((int64_t (*)(int64_t,int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2],a[3]);
        case 5: return ((int64_t (*)(int64_t,int64_t,int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2],a[3],a[4]);
        default: return ((int64_t (*)(int64_t,int64_t,int64_t,int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2],a[3],a[4],a[5]);
    }
}
static double dyncall_d(void *fn, const int64_t *a, int n) {
    switch (n) {
        case 0: return ((double (*)(void)) fn)();
        case 1: return ((double (*)(int64_t)) fn)(a[0]);
        case 2: return ((double (*)(int64_t,int64_t)) fn)(a[0],a[1]);
        case 3: return ((double (*)(int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2]);
        case 4: return ((double (*)(int64_t,int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2],a[3]);
        case 5: return ((double (*)(int64_t,int64_t,int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2],a[3],a[4]);
        default: return ((double (*)(int64_t,int64_t,int64_t,int64_t,int64_t,int64_t)) fn)(a[0],a[1],a[2],a[3],a[4],a[5]);
    }
}

/* args : int64 array (boxed), n : int. Returns the int64 / double result. */
CAMLprim value march_eval_dyncall_i(value fn, value args, value n_) {
    CAMLparam3(fn, args, n_);
    int n = Int_val(n_);
    int64_t a[6];
    for (int i = 0; i < n && i < 6; i++) a[i] = Int64_val(Field(args, i));
    int64_t r = dyncall_i((void *)Nativeint_val(fn), a, n);
    CAMLreturn(caml_copy_int64(r));
}
CAMLprim value march_eval_dyncall_d(value fn, value args, value n_) {
    CAMLparam3(fn, args, n_);
    int n = Int_val(n_);
    int64_t a[6];
    for (int i = 0; i < n && i < 6; i++) a[i] = Int64_val(Field(args, i));
    double r = dyncall_d((void *)Nativeint_val(fn), a, n);
    CAMLreturn(caml_copy_double(r));
}
