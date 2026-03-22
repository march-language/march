/* lib/jit/jit_stubs.c */
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <dlfcn.h>

/* dlopen(path, RTLD_NOW | RTLD_GLOBAL) -> handle (nativeint)
   Empty string "" is treated as NULL (returns main program handle). */
CAMLprim value march_dlopen(value v_path) {
    CAMLparam1(v_path);
    const char *path = String_val(v_path);
    /* Treat empty string as NULL (main program handle) */
    if (path[0] == '\0') path = NULL;
    void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) caml_failwith(dlerror());
    CAMLreturn(caml_copy_nativeint((intnat)handle));
}

/* dlsym(handle, symbol) -> function pointer (nativeint)
   Uses dlerror clear-then-check idiom: dlsym returning NULL is not always
   an error (POSIX allows symbols at address 0), but we check dlerror() after
   the call. If dlerror() returns non-NULL, that's a real error. */
CAMLprim value march_dlsym(value v_handle, value v_sym) {
    CAMLparam2(v_handle, v_sym);
    void *handle = (void *)Nativeint_val(v_handle);
    const char *sym = String_val(v_sym);
    dlerror();  /* clear any previous error */
    void *ptr = dlsym(handle, sym);
    char *err = dlerror();  /* check for error */
    if (err != NULL) caml_failwith(err);
    CAMLreturn(caml_copy_nativeint((intnat)ptr));
}

/* dlclose(handle) -> unit */
CAMLprim value march_dlclose(value v_handle) {
    CAMLparam1(v_handle);
    void *handle = (void *)Nativeint_val(v_handle);
    dlclose(handle);
    CAMLreturn(Val_unit);
}

/* Call a void->ptr function (for REPL expressions that return a March value).
   Takes a function pointer (nativeint), calls it, returns result as nativeint. */
CAMLprim value march_call_void_to_ptr(value v_fptr) {
    CAMLparam1(v_fptr);
    void *(*fn)(void) = (void *(*)(void))Nativeint_val(v_fptr);
    void *result = fn();
    CAMLreturn(caml_copy_nativeint((intnat)result));
}

/* Call a void->void function (for REPL declarations with side effects). */
CAMLprim value march_call_void_to_void(value v_fptr) {
    CAMLparam1(v_fptr);
    void (*fn)(void) = (void (*)(void))Nativeint_val(v_fptr);
    fn();
    CAMLreturn(Val_unit);
}

/* Call a void->i64 function (for REPL expressions returning Int/Bool). */
CAMLprim value march_call_void_to_int(value v_fptr) {
    CAMLparam1(v_fptr);
    int64_t (*fn)(void) = (int64_t (*)(void))Nativeint_val(v_fptr);
    int64_t result = fn();
    CAMLreturn(caml_copy_int64(result));
}

/* Call a void->double function (for REPL expressions returning Float). */
CAMLprim value march_call_void_to_float(value v_fptr) {
    CAMLparam1(v_fptr);
    double (*fn)(void) = (double (*)(void))Nativeint_val(v_fptr);
    double result = fn();
    CAMLreturn(caml_copy_double(result));
}

/* Call a ptr→ptr function (e.g., march_value_to_string). */
CAMLprim value march_call_ptr_to_ptr(value v_fptr, value v_arg) {
    CAMLparam2(v_fptr, v_arg);
    void *(*fn)(void *) = (void *(*)(void *))Nativeint_val(v_fptr);
    void *arg = (void *)Nativeint_val(v_arg);
    void *result = fn(arg);
    CAMLreturn(caml_copy_nativeint((intnat)result));
}

/* ── Heap inspection helpers (for REPL pretty-printer) ──────────────── */
#include <string.h>

/* Read int32_t from (ptr + byte_offset), sign-extended to OCaml int.
   Used to read march_hdr.tag (i32 at offset 8 in the header). */
CAMLprim value march_read_i32_at(value v_ptr, value v_off) {
    CAMLparam2(v_ptr, v_off);
    char *ptr = (char *)Nativeint_val(v_ptr);
    int off = Int_val(v_off);
    int32_t val;
    memcpy(&val, ptr + off, 4);
    CAMLreturn(Val_int((int)val));
}

/* Read int64_t from (ptr + byte_offset).
   Used to read i64 fields (TInt, TBool, TUnit, TFloat-as-bits). */
CAMLprim value march_read_i64_at(value v_ptr, value v_off) {
    CAMLparam2(v_ptr, v_off);
    char *ptr = (char *)Nativeint_val(v_ptr);
    int off = Int_val(v_off);
    int64_t val;
    memcpy(&val, ptr + off, 8);
    CAMLreturn(caml_copy_int64(val));
}

/* Read void* from (ptr + byte_offset).
   Used to read pointer fields (TString, TCon, TTuple, etc.). */
CAMLprim value march_read_ptr_at(value v_ptr, value v_off) {
    CAMLparam2(v_ptr, v_off);
    char *ptr = (char *)Nativeint_val(v_ptr);
    int off = Int_val(v_off);
    void *result;
    memcpy(&result, ptr + off, sizeof(void *));
    CAMLreturn(caml_copy_nativeint((intnat)result));
}

/* Read a march_string* as an OCaml string.
   march_string layout: { int64_t rc; int64_t len; char data[]; }
   — rc at offset 0, len at offset 8, data at offset 16. */
CAMLprim value march_read_march_string(value v_ptr) {
    CAMLparam1(v_ptr);
    CAMLlocal1(result);
    char *base = (char *)Nativeint_val(v_ptr);
    int64_t len;
    memcpy(&len, base + 8, 8);
    result = caml_alloc_string((mlsize_t)len);
    memcpy(Bytes_val(result), base + 16, (size_t)len);
    CAMLreturn(result);
}
