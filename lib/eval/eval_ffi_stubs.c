/* lib/eval/eval_ffi_stubs.c — dynamic C-call trampoline for the tree-walking
 * interpreter's FFI.
 *
 * The interpreter cannot statically know an extern's C signature, and there is
 * no libffi available, so we use fixed-arity trampolines that cast the resolved
 * function pointer.
 *
 * - dyncall_i / dyncall_d: GP-only (int64) args, int64 or double return.
 *   Used when all parameters are non-Float (Int/Bool/heap types).
 *
 * - dyncall_fi / dyncall_fd: mixed GP + FP args, int64 or double return.
 *   ABI correctness: on x86-64 SysV and AArch64, integer-class and FP-class
 *   args are assigned to their register banks independently of source order.
 *   Passing ni integer args and nf float args via a signature that lists all
 *   ints then all floats is therefore register-equivalent to any interleaving.
 *   Constraint: ni ≤ 8, nf ≤ 8 (stay within the register file).
 *
 * Symbols are prefixed `march_eval_` to avoid clashing with the JIT's
 * identical dlopen/dlsym helpers (both libs are linked into the compiler). */
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
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

/* ── Mixed GP + FP trampolines (Phase A: Float arguments) ─────────────────
 * ia[0..ni-1] are GP-register args (int64), fa[0..nf-1] are FP-register args
 * (double).  Dispatch key = ni*8+nf covers ni,nf ≤ 7 without collision.     */
static int64_t dyncall_fi(void *fn, const int64_t *ia, int ni, const double *fa, int nf) {
    switch (ni * 8 + nf) {
        /* ni=0 */
        case 0*8+1: return ((int64_t(*)(double))fn)(fa[0]);
        case 0*8+2: return ((int64_t(*)(double,double))fn)(fa[0],fa[1]);
        case 0*8+3: return ((int64_t(*)(double,double,double))fn)(fa[0],fa[1],fa[2]);
        case 0*8+4: return ((int64_t(*)(double,double,double,double))fn)(fa[0],fa[1],fa[2],fa[3]);
        /* ni=1 */
        case 1*8+1: return ((int64_t(*)(int64_t,double))fn)(ia[0],fa[0]);
        case 1*8+2: return ((int64_t(*)(int64_t,double,double))fn)(ia[0],fa[0],fa[1]);
        case 1*8+3: return ((int64_t(*)(int64_t,double,double,double))fn)(ia[0],fa[0],fa[1],fa[2]);
        /* ni=2 */
        case 2*8+1: return ((int64_t(*)(int64_t,int64_t,double))fn)(ia[0],ia[1],fa[0]);
        case 2*8+2: return ((int64_t(*)(int64_t,int64_t,double,double))fn)(ia[0],ia[1],fa[0],fa[1]);
        case 2*8+3: return ((int64_t(*)(int64_t,int64_t,double,double,double))fn)(ia[0],ia[1],fa[0],fa[1],fa[2]);
        /* ni=3 */
        case 3*8+1: return ((int64_t(*)(int64_t,int64_t,int64_t,double))fn)(ia[0],ia[1],ia[2],fa[0]);
        case 3*8+2: return ((int64_t(*)(int64_t,int64_t,int64_t,double,double))fn)(ia[0],ia[1],ia[2],fa[0],fa[1]);
        /* ni=4 */
        case 4*8+1: return ((int64_t(*)(int64_t,int64_t,int64_t,int64_t,double))fn)(ia[0],ia[1],ia[2],ia[3],fa[0]);
        /* ni=5 */
        case 5*8+1: return ((int64_t(*)(int64_t,int64_t,int64_t,int64_t,int64_t,double))fn)(ia[0],ia[1],ia[2],ia[3],ia[4],fa[0]);
        default:
            caml_failwith("march_eval dyncall_fi: unsupported (ni,nf) — file a bug");
            return 0;
    }
}
static double dyncall_fd(void *fn, const int64_t *ia, int ni, const double *fa, int nf) {
    switch (ni * 8 + nf) {
        /* ni=0 */
        case 0*8+1: return ((double(*)(double))fn)(fa[0]);
        case 0*8+2: return ((double(*)(double,double))fn)(fa[0],fa[1]);
        case 0*8+3: return ((double(*)(double,double,double))fn)(fa[0],fa[1],fa[2]);
        case 0*8+4: return ((double(*)(double,double,double,double))fn)(fa[0],fa[1],fa[2],fa[3]);
        /* ni=1 */
        case 1*8+1: return ((double(*)(int64_t,double))fn)(ia[0],fa[0]);
        case 1*8+2: return ((double(*)(int64_t,double,double))fn)(ia[0],fa[0],fa[1]);
        /* ni=2 */
        case 2*8+1: return ((double(*)(int64_t,int64_t,double))fn)(ia[0],ia[1],fa[0]);
        case 2*8+2: return ((double(*)(int64_t,int64_t,double,double))fn)(ia[0],ia[1],fa[0],fa[1]);
        /* ni=3 */
        case 3*8+1: return ((double(*)(int64_t,int64_t,int64_t,double))fn)(ia[0],ia[1],ia[2],fa[0]);
        /* ni=4 */
        case 4*8+1: return ((double(*)(int64_t,int64_t,int64_t,int64_t,double))fn)(ia[0],ia[1],ia[2],ia[3],fa[0]);
        default:
            caml_failwith("march_eval dyncall_fd: unsupported (ni,nf) — file a bug");
            return 0.0;
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

/* Mixed-register trampolines: iargs=int64 array, fargs=float array (unboxed). */
CAMLprim value march_eval_dyncall_fi(value fn, value iargs, value ni_, value fargs, value nf_) {
    CAMLparam5(fn, iargs, ni_, fargs, nf_);
    int ni = Int_val(ni_), nf = Int_val(nf_);
    int64_t ia[8]; double fa[8];
    for (int i = 0; i < ni && i < 8; i++) ia[i] = Int64_val(Field(iargs, i));
    for (int i = 0; i < nf && i < 8; i++) fa[i] = Double_field(fargs, i);
    int64_t r = dyncall_fi((void *)Nativeint_val(fn), ia, ni, fa, nf);
    CAMLreturn(caml_copy_int64(r));
}
CAMLprim value march_eval_dyncall_fd(value fn, value iargs, value ni_, value fargs, value nf_) {
    CAMLparam5(fn, iargs, ni_, fargs, nf_);
    int ni = Int_val(ni_), nf = Int_val(nf_);
    int64_t ia[8]; double fa[8];
    for (int i = 0; i < ni && i < 8; i++) ia[i] = Int64_val(Field(iargs, i));
    for (int i = 0; i < nf && i < 8; i++) fa[i] = Double_field(fargs, i);
    double r = dyncall_fd((void *)Nativeint_val(fn), ia, ni, fa, nf);
    CAMLreturn(caml_copy_double(r));
}
