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


define i64 @fib(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp slt i64 %ld1, 2
  %ar3 = zext i1 %cmp2 to i64
  %$t2009.addr = alloca i64
  store i64 %ar3, ptr %$t2009.addr
  %ld4 = load i64, ptr %$t2009.addr
  %res_slot5 = alloca ptr
  %bi6 = trunc i64 %ld4 to i1
  br i1 %bi6, label %case_br3, label %case_default2
case_br3:
  %ld7 = load i64, ptr %n.addr
  %cv8 = inttoptr i64 %ld7 to ptr
  store ptr %cv8, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %n.addr
  %ar10 = sub i64 %ld9, 1
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %$t2010.addr
  %cr12 = call i64 @fib(i64 %ld11)
  %$t2011.addr = alloca i64
  store i64 %cr12, ptr %$t2011.addr
  %ld13 = load i64, ptr %n.addr
  %ar14 = sub i64 %ld13, 2
  %$t2012.addr = alloca i64
  store i64 %ar14, ptr %$t2012.addr
  %ld15 = load i64, ptr %$t2012.addr
  %cr16 = call i64 @fib(i64 %ld15)
  %$t2013.addr = alloca i64
  store i64 %cr16, ptr %$t2013.addr
  %ld17 = load i64, ptr %$t2011.addr
  %ld18 = load i64, ptr %$t2013.addr
  %ar19 = add i64 %ld17, %ld18
  %cv20 = inttoptr i64 %ar19 to ptr
  store ptr %cv20, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r21 = load ptr, ptr %res_slot5
  %cv22 = ptrtoint ptr %case_r21 to i64
  ret i64 %cv22
}

define i64 @par_fib(i64 %n.arg, i64 %threshold.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld23 = load i64, ptr %n.addr
  %cmp24 = icmp slt i64 %ld23, 2
  %ar25 = zext i1 %cmp24 to i64
  %$t2014.addr = alloca i64
  store i64 %ar25, ptr %$t2014.addr
  %ld26 = load i64, ptr %$t2014.addr
  %res_slot27 = alloca ptr
  %bi28 = trunc i64 %ld26 to i1
  br i1 %bi28, label %case_br6, label %case_default5
case_br6:
  %ld29 = load i64, ptr %n.addr
  %cv30 = inttoptr i64 %ld29 to ptr
  store ptr %cv30, ptr %res_slot27
  br label %case_merge4
case_default5:
  %ld31 = load i64, ptr %n.addr
  %ld32 = load i64, ptr %threshold.addr
  %cmp33 = icmp sle i64 %ld31, %ld32
  %ar34 = zext i1 %cmp33 to i64
  %$t2015.addr = alloca i64
  store i64 %ar34, ptr %$t2015.addr
  %ld35 = load i64, ptr %$t2015.addr
  %res_slot36 = alloca ptr
  %bi37 = trunc i64 %ld35 to i1
  br i1 %bi37, label %case_br9, label %case_default8
case_br9:
  %ld38 = load i64, ptr %n.addr
  %cr39 = call i64 @fib(i64 %ld38)
  %cv40 = inttoptr i64 %cr39 to ptr
  store ptr %cv40, ptr %res_slot36
  br label %case_merge7
case_default8:
  %hp41 = call ptr @march_alloc(i64 40)
  %tgp42 = getelementptr i8, ptr %hp41, i64 8
  store i32 0, ptr %tgp42, align 4
  %fp43 = getelementptr i8, ptr %hp41, i64 16
  store ptr @$lam2016$apply$21, ptr %fp43, align 8
  %ld44 = load i64, ptr %n.addr
  %fp45 = getelementptr i8, ptr %hp41, i64 24
  store i64 %ld44, ptr %fp45, align 8
  %ld46 = load i64, ptr %threshold.addr
  %fp47 = getelementptr i8, ptr %hp41, i64 32
  store i64 %ld46, ptr %fp47, align 8
  %$t2018.addr = alloca ptr
  store ptr %hp41, ptr %$t2018.addr
  %ld48 = load ptr, ptr %$t2018.addr
  %fp49 = getelementptr i8, ptr %ld48, i64 16
  %fv50 = load ptr, ptr %fp49, align 8
  %tsres51 = call i64 %fv50(ptr %ld48, i64 0)
  %hp52 = call ptr @march_alloc(i64 24)
  %tgp53 = getelementptr i8, ptr %hp52, i64 8
  store i32 0, ptr %tgp53, align 4
  %fp54 = getelementptr i8, ptr %hp52, i64 16
  store i64 %tsres51, ptr %fp54, align 8
  %t1.addr = alloca ptr
  store ptr %hp52, ptr %t1.addr
  %hp55 = call ptr @march_alloc(i64 40)
  %tgp56 = getelementptr i8, ptr %hp55, i64 8
  store i32 0, ptr %tgp56, align 4
  %fp57 = getelementptr i8, ptr %hp55, i64 16
  store ptr @$lam2019$apply$22, ptr %fp57, align 8
  %ld58 = load i64, ptr %n.addr
  %fp59 = getelementptr i8, ptr %hp55, i64 24
  store i64 %ld58, ptr %fp59, align 8
  %ld60 = load i64, ptr %threshold.addr
  %fp61 = getelementptr i8, ptr %hp55, i64 32
  store i64 %ld60, ptr %fp61, align 8
  %$t2021.addr = alloca ptr
  store ptr %hp55, ptr %$t2021.addr
  %ld62 = load ptr, ptr %$t2021.addr
  %fp63 = getelementptr i8, ptr %ld62, i64 16
  %fv64 = load ptr, ptr %fp63, align 8
  %tsres65 = call i64 %fv64(ptr %ld62, i64 0)
  %hp66 = call ptr @march_alloc(i64 24)
  %tgp67 = getelementptr i8, ptr %hp66, i64 8
  store i32 0, ptr %tgp67, align 4
  %fp68 = getelementptr i8, ptr %hp66, i64 16
  store i64 %tsres65, ptr %fp68, align 8
  %t2.addr = alloca ptr
  store ptr %hp66, ptr %t2.addr
  %ld69 = load ptr, ptr %t1.addr
  %fp70 = getelementptr i8, ptr %ld69, i64 16
  %fv71 = load i64, ptr %fp70, align 8
  %r1.addr = alloca i64
  store i64 %fv71, ptr %r1.addr
  %ld72 = load ptr, ptr %t2.addr
  %fp73 = getelementptr i8, ptr %ld72, i64 16
  %fv74 = load i64, ptr %fp73, align 8
  %r2.addr = alloca i64
  store i64 %fv74, ptr %r2.addr
  %ld75 = load i64, ptr %r1.addr
  %ld76 = load i64, ptr %r2.addr
  %ar77 = add i64 %ld75, %ld76
  %cv78 = inttoptr i64 %ar77 to ptr
  store ptr %cv78, ptr %res_slot36
  br label %case_merge7
case_merge7:
  %case_r79 = load ptr, ptr %res_slot36
  store ptr %case_r79, ptr %res_slot27
  br label %case_merge4
case_merge4:
  %case_r80 = load ptr, ptr %res_slot27
  %cv81 = ptrtoint ptr %case_r80 to i64
  ret i64 %cv81
}

define void @march_main() {
entry:
  %cr82 = call i64 @par_fib(i64 40, i64 20)
  %result.addr = alloca i64
  store i64 %cr82, ptr %result.addr
  %ld83 = load i64, ptr %result.addr
  %cr84 = call ptr @march_int_to_string(i64 %ld83)
  %$t2022.addr = alloca ptr
  store ptr %cr84, ptr %$t2022.addr
  %ld85 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld85)
  ret void
}

define i64 @$lam2016$apply$21(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld86 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld86)
  %ld87 = load ptr, ptr %$clo.addr
  %fp88 = getelementptr i8, ptr %ld87, i64 24
  %fv89 = load ptr, ptr %fp88, align 8
  %cv90 = ptrtoint ptr %fv89 to i64
  %n.addr = alloca i64
  store i64 %cv90, ptr %n.addr
  %ld91 = load ptr, ptr %$clo.addr
  %fp92 = getelementptr i8, ptr %ld91, i64 32
  %fv93 = load i64, ptr %fp92, align 8
  %threshold.addr = alloca i64
  store i64 %fv93, ptr %threshold.addr
  %ld94 = load i64, ptr %n.addr
  %ar95 = sub i64 %ld94, 1
  %$t2017.addr = alloca i64
  store i64 %ar95, ptr %$t2017.addr
  %ld96 = load i64, ptr %$t2017.addr
  %ld97 = load i64, ptr %threshold.addr
  %cr98 = call i64 @par_fib(i64 %ld96, i64 %ld97)
  ret i64 %cr98
}

define i64 @$lam2019$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld99 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld99)
  %ld100 = load ptr, ptr %$clo.addr
  %fp101 = getelementptr i8, ptr %ld100, i64 24
  %fv102 = load ptr, ptr %fp101, align 8
  %cv103 = ptrtoint ptr %fv102 to i64
  %n.addr = alloca i64
  store i64 %cv103, ptr %n.addr
  %ld104 = load ptr, ptr %$clo.addr
  %fp105 = getelementptr i8, ptr %ld104, i64 32
  %fv106 = load i64, ptr %fp105, align 8
  %threshold.addr = alloca i64
  store i64 %fv106, ptr %threshold.addr
  %ld107 = load i64, ptr %n.addr
  %ar108 = sub i64 %ld107, 2
  %$t2020.addr = alloca i64
  store i64 %ar108, ptr %$t2020.addr
  %ld109 = load i64, ptr %$t2020.addr
  %ld110 = load i64, ptr %threshold.addr
  %cr111 = call i64 @par_fib(i64 %ld109, i64 %ld110)
  ret i64 %cr111
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
