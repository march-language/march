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

/* dlsym(handle, symbol) -> function pointer (nativeint) */
CAMLprim value march_dlsym(value v_handle, value v_sym) {
    CAMLparam2(v_handle, v_sym);
    void *handle = (void *)Nativeint_val(v_handle);
    const char *sym = String_val(v_sym);
    void *ptr = dlsym(handle, sym);
    if (!ptr) caml_failwith(dlerror());
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
