/* eval_beneath_stubs.c — the interpreter's binding to
 * runtime/march_file_beneath.c (File.Dir; ocap phase 2).
 *
 * The runtime file's core (no March values) is compiled right here, so the
 * interpreter and a compiled binary refuse and resolve a path beneath a
 * directory with the same C.  lib/eval/dune puts ../../runtime on the include
 * path and names the file in extra_deps; scripts/check-runtime-sources.sh
 * checks that this include stays. */
#define MARCH_BENEATH_CORE_ONLY 1
#include "march_file_beneath.c"

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

/* march_eval_beneath_open : int -> string -> int -> int
 * (dirfd, rel, flag code 0 read / 1 truncate / 2 append) -> fd, or -errno. */
CAMLprim value march_eval_beneath_open(value v_dirfd, value v_rel, value v_code) {
    CAMLparam3(v_dirfd, v_rel, v_code);
    int r = march_beneath_open_mode(Int_val(v_dirfd), String_val(v_rel),
                                    caml_string_length(v_rel), Long_val(v_code));
    CAMLreturn(Val_int(r));
}

/* march_eval_dir_open : string -> int
 * open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC), as march_dir_open: the fd,
 * or -errno. */
CAMLprim value march_eval_dir_open(value v_path) {
    CAMLparam1(v_path);
    if (memchr(String_val(v_path), '\0', caml_string_length(v_path)) != NULL)
        CAMLreturn(Val_int(-ENOENT));
    int fd = open(String_val(v_path), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    CAMLreturn(Val_int(fd < 0 ? -errno : fd));
}

/* march_eval_beneath_list : int -> string -> int * string array
 * (0, sorted names) or (errno, [||]).  "" lists the directory itself. */
CAMLprim value march_eval_beneath_list(value v_dirfd, value v_rel) {
    CAMLparam2(v_dirfd, v_rel);
    CAMLlocal3(arr, s, res);
    char **names = NULL;
    int n = 0;
    int r = march_beneath_list(Int_val(v_dirfd), String_val(v_rel),
                               caml_string_length(v_rel), &names, &n);
    if (r < 0) {
        arr = caml_alloc(0, 0);
        res = caml_alloc_tuple(2);
        Store_field(res, 0, Val_int(-r));
        Store_field(res, 1, arr);
        CAMLreturn(res);
    }
    arr = caml_alloc(n, 0);
    for (int i = 0; i < n; i++) {
        s = caml_copy_string(names[i]);
        Store_field(arr, i, s);
    }
    march_beneath_free_names(names, n);
    res = caml_alloc_tuple(2);
    Store_field(res, 0, Val_int(0));
    Store_field(res, 1, arr);
    CAMLreturn(res);
}

/* march_eval_beneath_errinfo : int -> int * string
 * Classify a positive errno the way march_file_beneath.c's beneath_err does:
 * 0 escapes (EXDEV, ELOOP), 1 ENOENT, 2 EACCES/EPERM, 3 EISDIR, 4 ENOTDIR,
 * 5 anything else; with strerror's text. */
CAMLprim value march_eval_beneath_errinfo(value v_err) {
    CAMLparam1(v_err);
    CAMLlocal2(res, msg);
    int e = Int_val(v_err);
    int kind = march_beneath_is_escape(e) ? 0
             : e == ENOENT ? 1
             : (e == EACCES || e == EPERM) ? 2
             : e == EISDIR ? 3
             : e == ENOTDIR ? 4 : 5;
    msg = caml_copy_string(strerror(e));
    res = caml_alloc_tuple(2);
    Store_field(res, 0, Val_int(kind));
    Store_field(res, 1, msg);
    CAMLreturn(res);
}
