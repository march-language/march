; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_panic(ptr %s)
declare void @march_println(ptr %s)
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr  @march_float_to_string(double %f)
declare ptr  @march_bool_to_string(i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
; Ord / Hash builtins
declare i64    @march_compare_int(i64 %x, i64 %y)
declare i64    @march_compare_float(double %x, double %y)
declare i64    @march_compare_string(ptr %x, ptr %y)
declare i64    @march_hash_int(i64 %x)
declare i64    @march_hash_float(double %x)
declare i64    @march_hash_string(ptr %x)
declare i64    @march_hash_bool(i64 %x)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_join(ptr %list, ptr %sep)
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)
declare ptr  @march_spawn(ptr %actor)
declare i64  @march_actor_get_int(ptr %actor, i64 %index)
declare void @march_run_scheduler()
declare i64  @march_tcp_listen(i64 %port)
declare i64  @march_tcp_accept(i64 %fd)
declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)
declare void @march_tcp_send_all(i64 %fd, ptr %data)
declare void @march_tcp_close(i64 %fd)
declare ptr  @march_http_parse_request(ptr %raw)
declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)
declare void @march_http_server_listen(i64 %port, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare void @march_ws_handshake(i64 %fd, ptr %key)
declare ptr  @march_ws_recv(i64 %fd)
declare void @march_ws_send(i64 %fd, ptr %frame)
declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)
; Float builtins
declare double @march_float_abs(double %f)
declare i64    @march_float_ceil(double %f)
declare i64    @march_float_floor(double %f)
declare i64    @march_float_round(double %f)
declare i64    @march_float_truncate(double %f)
declare double @march_int_to_float(i64 %n)
; Math builtins
declare double @march_math_sin(double %f)
declare double @march_math_cos(double %f)
declare double @march_math_tan(double %f)
declare double @march_math_asin(double %f)
declare double @march_math_acos(double %f)
declare double @march_math_atan(double %f)
declare double @march_math_atan2(double %y, double %x)
declare double @march_math_sinh(double %f)
declare double @march_math_cosh(double %f)
declare double @march_math_tanh(double %f)
declare double @march_math_sqrt(double %f)
declare double @march_math_cbrt(double %f)
declare double @march_math_exp(double %f)
declare double @march_math_exp2(double %f)
declare double @march_math_log(double %f)
declare double @march_math_log2(double %f)
declare double @march_math_log10(double %f)
declare double @march_math_pow(double %b, double %e)
; Extended string builtins
declare i64  @march_string_contains(ptr %s, ptr %sub)
declare i64  @march_string_starts_with(ptr %s, ptr %prefix)
declare i64  @march_string_ends_with(ptr %s, ptr %suffix)
declare ptr  @march_string_slice(ptr %s, i64 %start, i64 %len)
declare ptr  @march_string_split(ptr %s, ptr %sep)
declare ptr  @march_string_split_first(ptr %s, ptr %sep)
declare ptr  @march_string_replace(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_replace_all(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_to_lowercase(ptr %s)
declare ptr  @march_string_to_uppercase(ptr %s)
declare ptr  @march_string_trim(ptr %s)
declare ptr  @march_string_trim_start(ptr %s)
declare ptr  @march_string_trim_end(ptr %s)
declare ptr  @march_string_repeat(ptr %s, i64 %n)
declare ptr  @march_string_reverse(ptr %s)
declare ptr  @march_string_pad_left(ptr %s, i64 %width, ptr %fill)
declare ptr  @march_string_pad_right(ptr %s, i64 %width, ptr %fill)
declare i64  @march_string_grapheme_count(ptr %s)
declare ptr  @march_string_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_last_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_to_float(ptr %s)
; List builtins
declare ptr  @march_list_append(ptr %a, ptr %b)
declare ptr  @march_list_concat(ptr %lists)
; File/Dir builtins
declare i64  @march_file_exists(ptr %s)
declare i64  @march_dir_exists(ptr %s)
; Capability builtins
declare ptr  @march_cap_narrow(ptr %cap)
; Monitor/supervision builtins
declare void @march_demonitor(i64 %ref)
declare i64  @march_monitor(ptr %watcher, ptr %target)
declare i64  @march_mailbox_size(ptr %pid)
declare void @march_run_until_idle()
declare void @march_register_resource(ptr %pid, ptr %name, ptr %cleanup)
declare ptr  @march_get_cap(ptr %pid)
declare void @march_send_checked(ptr %cap, ptr %msg)
declare ptr  @march_pid_of_int(i64 %n)
declare ptr  @march_get_actor_field(ptr %pid, ptr %name)
declare ptr  @march_value_to_string(ptr %v)

@.str1 = private unnamed_addr constant [8 x i8] c"Hello, \00"
@.str2 = private unnamed_addr constant [2 x i8] c"!\00"
@.str3 = private unnamed_addr constant [6 x i8] c"world\00"

define ptr @greet(ptr %name.arg) {
entry:
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %sl1 = call ptr @march_string_lit(ptr @.str1, i64 7)
  %ld2 = load ptr, ptr %name.addr
  %cr3 = call ptr @march_string_concat(ptr %sl1, ptr %ld2)
  %$t2009.addr = alloca ptr
  store ptr %cr3, ptr %$t2009.addr
  %ld4 = load ptr, ptr %$t2009.addr
  %sl5 = call ptr @march_string_lit(ptr @.str2, i64 1)
  %cr6 = call ptr @march_string_concat(ptr %ld4, ptr %sl5)
  ret ptr %cr6
}

define i64 @factorial(i64 %__arg0.arg) {
entry:
  %__arg0.addr = alloca i64
  store i64 %__arg0.arg, ptr %__arg0.addr
  %ld7 = load i64, ptr %__arg0.addr
  %res_slot8 = alloca ptr
  switch i64 %ld7, label %case_default2 [
      i64 0, label %case_br3
  ]
case_br3:
  %cv9 = inttoptr i64 1 to ptr
  store ptr %cv9, ptr %res_slot8
  br label %case_merge1
case_default2:
  %ld10 = load i64, ptr %__arg0.addr
  %n.addr = alloca i64
  store i64 %ld10, ptr %n.addr
  %ld11 = load i64, ptr %n.addr
  %ar12 = sub i64 %ld11, 1
  %$t2011.addr = alloca i64
  store i64 %ar12, ptr %$t2011.addr
  %ld13 = load i64, ptr %$t2011.addr
  %cr14 = call i64 @factorial(i64 %ld13)
  %$t2012.addr = alloca i64
  store i64 %cr14, ptr %$t2012.addr
  %ld15 = load i64, ptr %n.addr
  %ld16 = load i64, ptr %$t2012.addr
  %ar17 = mul i64 %ld15, %ld16
  %cv18 = inttoptr i64 %ar17 to ptr
  store ptr %cv18, ptr %res_slot8
  br label %case_merge1
case_merge1:
  %case_r19 = load ptr, ptr %res_slot8
  %cv20 = ptrtoint ptr %case_r19 to i64
  ret i64 %cv20
}

define i64 @fib(i64 %__arg0.arg) {
entry:
  %__arg0.addr = alloca i64
  store i64 %__arg0.arg, ptr %__arg0.addr
  %ld21 = load i64, ptr %__arg0.addr
  %res_slot22 = alloca ptr
  switch i64 %ld21, label %case_default5 [
      i64 0, label %case_br6
      i64 1, label %case_br7
  ]
case_br6:
  %cv23 = inttoptr i64 0 to ptr
  store ptr %cv23, ptr %res_slot22
  br label %case_merge4
case_br7:
  %cv24 = inttoptr i64 1 to ptr
  store ptr %cv24, ptr %res_slot22
  br label %case_merge4
case_default5:
  %ld25 = load i64, ptr %__arg0.addr
  %n.addr = alloca i64
  store i64 %ld25, ptr %n.addr
  %ld26 = load i64, ptr %n.addr
  %ar27 = sub i64 %ld26, 1
  %$t2013.addr = alloca i64
  store i64 %ar27, ptr %$t2013.addr
  %ld28 = load i64, ptr %$t2013.addr
  %cr29 = call i64 @fib(i64 %ld28)
  %$t2014.addr = alloca i64
  store i64 %cr29, ptr %$t2014.addr
  %ld30 = load i64, ptr %n.addr
  %ar31 = sub i64 %ld30, 2
  %$t2015.addr = alloca i64
  store i64 %ar31, ptr %$t2015.addr
  %ld32 = load i64, ptr %$t2015.addr
  %cr33 = call i64 @fib(i64 %ld32)
  %$t2016.addr = alloca i64
  store i64 %cr33, ptr %$t2016.addr
  %ld34 = load i64, ptr %$t2014.addr
  %ld35 = load i64, ptr %$t2016.addr
  %ar36 = add i64 %ld34, %ld35
  %cv37 = inttoptr i64 %ar36 to ptr
  store ptr %cv37, ptr %res_slot22
  br label %case_merge4
case_merge4:
  %case_r38 = load ptr, ptr %res_slot22
  %cv39 = ptrtoint ptr %case_r38 to i64
  ret i64 %cv39
}

define ptr @march_main() {
entry:
  %sl40 = call ptr @march_string_lit(ptr @.str3, i64 5)
  %cr41 = call ptr @greet(ptr %sl40)
  %$t2020.addr = alloca ptr
  store ptr %cr41, ptr %$t2020.addr
  %ld42 = load ptr, ptr %$t2020.addr
  call void @march_println(ptr %ld42)
  %cr43 = call i64 @factorial(i64 5)
  %$t2021.addr = alloca i64
  store i64 %cr43, ptr %$t2021.addr
  %ld44 = load i64, ptr %$t2021.addr
  %cr45 = call ptr @march_int_to_string(i64 %ld44)
  %$t2022.addr = alloca ptr
  store ptr %cr45, ptr %$t2022.addr
  %ld46 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld46)
  %cr47 = call i64 @fib(i64 10)
  %$t2023.addr = alloca i64
  store i64 %cr47, ptr %$t2023.addr
  %ld48 = load i64, ptr %$t2023.addr
  %cr49 = call ptr @march_int_to_string(i64 %ld48)
  %$t2024.addr = alloca ptr
  store ptr %cr49, ptr %$t2024.addr
  %ld50 = load ptr, ptr %$t2024.addr
  call void @march_println(ptr %ld50)
  %cv51 = inttoptr i64 0 to ptr
  ret ptr %cv51
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
