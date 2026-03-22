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

@.str1 = private unnamed_addr constant [20 x i8] c"--- Task basics ---\00"
@.str2 = private unnamed_addr constant [30 x i8] c"collatz(27) + collatz(871) = \00"
@.str3 = private unnamed_addr constant [26 x i8] c"chained: (10 + 20) * 3 = \00"
@.str4 = private unnamed_addr constant [26 x i8] c"sum of collatz(1..100) = \00"

define i64 @collatz(i64 %n.arg, i64 %steps.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %steps.addr = alloca i64
  store i64 %steps.arg, ptr %steps.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp eq i64 %ld1, 1
  %ar3 = zext i1 %cmp2 to i64
  %$t2009.addr = alloca i64
  store i64 %ar3, ptr %$t2009.addr
  %ld4 = load i64, ptr %$t2009.addr
  %res_slot5 = alloca ptr
  %bi6 = trunc i64 %ld4 to i1
  br i1 %bi6, label %case_br3, label %case_default2
case_br3:
  %ld7 = load i64, ptr %steps.addr
  %cv8 = inttoptr i64 %ld7 to ptr
  store ptr %cv8, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %n.addr
  %ar10 = srem i64 %ld9, 2
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %$t2010.addr
  %cmp12 = icmp eq i64 %ld11, 0
  %ar13 = zext i1 %cmp12 to i64
  %$t2011.addr = alloca i64
  store i64 %ar13, ptr %$t2011.addr
  %ld14 = load i64, ptr %$t2011.addr
  %res_slot15 = alloca ptr
  %bi16 = trunc i64 %ld14 to i1
  br i1 %bi16, label %case_br6, label %case_default5
case_br6:
  %ld17 = load i64, ptr %n.addr
  %ar18 = sdiv i64 %ld17, 2
  %$t2012.addr = alloca i64
  store i64 %ar18, ptr %$t2012.addr
  %ld19 = load i64, ptr %steps.addr
  %ar20 = add i64 %ld19, 1
  %$t2013.addr = alloca i64
  store i64 %ar20, ptr %$t2013.addr
  %ld21 = load i64, ptr %$t2012.addr
  %ld22 = load i64, ptr %$t2013.addr
  %cr23 = call i64 @collatz(i64 %ld21, i64 %ld22)
  %cv24 = inttoptr i64 %cr23 to ptr
  store ptr %cv24, ptr %res_slot15
  br label %case_merge4
case_default5:
  %ld25 = load i64, ptr %n.addr
  %ar26 = mul i64 3, %ld25
  %$t2014.addr = alloca i64
  store i64 %ar26, ptr %$t2014.addr
  %ld27 = load i64, ptr %$t2014.addr
  %ar28 = add i64 %ld27, 1
  %$t2015.addr = alloca i64
  store i64 %ar28, ptr %$t2015.addr
  %ld29 = load i64, ptr %steps.addr
  %ar30 = add i64 %ld29, 1
  %$t2016.addr = alloca i64
  store i64 %ar30, ptr %$t2016.addr
  %ld31 = load i64, ptr %$t2015.addr
  %ld32 = load i64, ptr %$t2016.addr
  %cr33 = call i64 @collatz(i64 %ld31, i64 %ld32)
  %cv34 = inttoptr i64 %cr33 to ptr
  store ptr %cv34, ptr %res_slot15
  br label %case_merge4
case_merge4:
  %case_r35 = load ptr, ptr %res_slot15
  store ptr %case_r35, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r36 = load ptr, ptr %res_slot5
  %cv37 = ptrtoint ptr %case_r36 to i64
  ret i64 %cv37
}

define i64 @two_tasks() {
entry:
  %hp38 = call ptr @march_alloc(i64 24)
  %tgp39 = getelementptr i8, ptr %hp38, i64 8
  store i32 0, ptr %tgp39, align 4
  %fp40 = getelementptr i8, ptr %hp38, i64 16
  store ptr @$lam2017$apply$22, ptr %fp40, align 8
  %$t2018.addr = alloca ptr
  store ptr %hp38, ptr %$t2018.addr
  %ld41 = load ptr, ptr %$t2018.addr
  %fp42 = getelementptr i8, ptr %ld41, i64 16
  %fv43 = load ptr, ptr %fp42, align 8
  %tsres44 = call i64 %fv43(ptr %ld41, i64 0)
  %hp45 = call ptr @march_alloc(i64 24)
  %tgp46 = getelementptr i8, ptr %hp45, i64 8
  store i32 0, ptr %tgp46, align 4
  %fp47 = getelementptr i8, ptr %hp45, i64 16
  store i64 %tsres44, ptr %fp47, align 8
  %t1.addr = alloca ptr
  store ptr %hp45, ptr %t1.addr
  %hp48 = call ptr @march_alloc(i64 24)
  %tgp49 = getelementptr i8, ptr %hp48, i64 8
  store i32 0, ptr %tgp49, align 4
  %fp50 = getelementptr i8, ptr %hp48, i64 16
  store ptr @$lam2019$apply$23, ptr %fp50, align 8
  %$t2020.addr = alloca ptr
  store ptr %hp48, ptr %$t2020.addr
  %ld51 = load ptr, ptr %$t2020.addr
  %fp52 = getelementptr i8, ptr %ld51, i64 16
  %fv53 = load ptr, ptr %fp52, align 8
  %tsres54 = call i64 %fv53(ptr %ld51, i64 0)
  %hp55 = call ptr @march_alloc(i64 24)
  %tgp56 = getelementptr i8, ptr %hp55, i64 8
  store i32 0, ptr %tgp56, align 4
  %fp57 = getelementptr i8, ptr %hp55, i64 16
  store i64 %tsres54, ptr %fp57, align 8
  %t2.addr = alloca ptr
  store ptr %hp55, ptr %t2.addr
  %ld58 = load ptr, ptr %t1.addr
  %fp59 = getelementptr i8, ptr %ld58, i64 16
  %fv60 = load i64, ptr %fp59, align 8
  %r1.addr = alloca i64
  store i64 %fv60, ptr %r1.addr
  %ld61 = load ptr, ptr %t2.addr
  %fp62 = getelementptr i8, ptr %ld61, i64 16
  %fv63 = load i64, ptr %fp62, align 8
  %r2.addr = alloca i64
  store i64 %fv63, ptr %r2.addr
  %ld64 = load i64, ptr %r1.addr
  %ld65 = load i64, ptr %r2.addr
  %ar66 = add i64 %ld64, %ld65
  ret i64 %ar66
}

define i64 @fan_out_inner(i64 %n.arg, i64 %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld67 = load i64, ptr %n.addr
  %cmp68 = icmp eq i64 %ld67, 0
  %ar69 = zext i1 %cmp68 to i64
  %$t2025.addr = alloca i64
  store i64 %ar69, ptr %$t2025.addr
  %ld70 = load i64, ptr %$t2025.addr
  %res_slot71 = alloca ptr
  %bi72 = trunc i64 %ld70 to i1
  br i1 %bi72, label %case_br9, label %case_default8
case_br9:
  %ld73 = load i64, ptr %acc.addr
  %cv74 = inttoptr i64 %ld73 to ptr
  store ptr %cv74, ptr %res_slot71
  br label %case_merge7
case_default8:
  %hp75 = call ptr @march_alloc(i64 32)
  %tgp76 = getelementptr i8, ptr %hp75, i64 8
  store i32 0, ptr %tgp76, align 4
  %fp77 = getelementptr i8, ptr %hp75, i64 16
  store ptr @$lam2026$apply$26, ptr %fp77, align 8
  %ld78 = load i64, ptr %n.addr
  %fp79 = getelementptr i8, ptr %hp75, i64 24
  store i64 %ld78, ptr %fp79, align 8
  %$t2027.addr = alloca ptr
  store ptr %hp75, ptr %$t2027.addr
  %ld80 = load ptr, ptr %$t2027.addr
  %fp81 = getelementptr i8, ptr %ld80, i64 16
  %fv82 = load ptr, ptr %fp81, align 8
  %tsres83 = call i64 %fv82(ptr %ld80, i64 0)
  %hp84 = call ptr @march_alloc(i64 24)
  %tgp85 = getelementptr i8, ptr %hp84, i64 8
  store i32 0, ptr %tgp85, align 4
  %fp86 = getelementptr i8, ptr %hp84, i64 16
  store i64 %tsres83, ptr %fp86, align 8
  %t.addr = alloca ptr
  store ptr %hp84, ptr %t.addr
  %ld87 = load ptr, ptr %t.addr
  %fp88 = getelementptr i8, ptr %ld87, i64 16
  %fv89 = load i64, ptr %fp88, align 8
  %r.addr = alloca i64
  store i64 %fv89, ptr %r.addr
  %ld90 = load i64, ptr %n.addr
  %ar91 = sub i64 %ld90, 1
  %$t2028.addr = alloca i64
  store i64 %ar91, ptr %$t2028.addr
  %ld92 = load i64, ptr %acc.addr
  %ld93 = load i64, ptr %r.addr
  %ar94 = add i64 %ld92, %ld93
  %$t2029.addr = alloca i64
  store i64 %ar94, ptr %$t2029.addr
  %ld95 = load i64, ptr %$t2028.addr
  %ld96 = load i64, ptr %$t2029.addr
  %cr97 = call i64 @fan_out_inner(i64 %ld95, i64 %ld96)
  %cv98 = inttoptr i64 %cr97 to ptr
  store ptr %cv98, ptr %res_slot71
  br label %case_merge7
case_merge7:
  %case_r99 = load ptr, ptr %res_slot71
  %cv100 = ptrtoint ptr %case_r99 to i64
  ret i64 %cv100
}

define void @march_main() {
entry:
  %sl101 = call ptr @march_string_lit(ptr @.str1, i64 19)
  call void @march_println(ptr %sl101)
  %cr102 = call i64 @two_tasks()
  %r.addr = alloca i64
  store i64 %cr102, ptr %r.addr
  %ld103 = load i64, ptr %r.addr
  %cr104 = call ptr @march_int_to_string(i64 %ld103)
  %$t2030.addr = alloca ptr
  store ptr %cr104, ptr %$t2030.addr
  %sl105 = call ptr @march_string_lit(ptr @.str2, i64 29)
  %ld106 = load ptr, ptr %$t2030.addr
  %cr107 = call ptr @march_string_concat(ptr %sl105, ptr %ld106)
  %$t2031.addr = alloca ptr
  store ptr %cr107, ptr %$t2031.addr
  %ld108 = load ptr, ptr %$t2031.addr
  call void @march_println(ptr %ld108)
  %hp109 = call ptr @march_alloc(i64 24)
  %tgp110 = getelementptr i8, ptr %hp109, i64 8
  store i32 0, ptr %tgp110, align 4
  %fp111 = getelementptr i8, ptr %hp109, i64 16
  store ptr @$lam2021$apply$24, ptr %fp111, align 8
  %$t2022_i24.addr = alloca ptr
  store ptr %hp109, ptr %$t2022_i24.addr
  %ld112 = load ptr, ptr %$t2022_i24.addr
  %fp113 = getelementptr i8, ptr %ld112, i64 16
  %fv114 = load ptr, ptr %fp113, align 8
  %tsres115 = call i64 %fv114(ptr %ld112, i64 0)
  %hp116 = call ptr @march_alloc(i64 24)
  %tgp117 = getelementptr i8, ptr %hp116, i64 8
  store i32 0, ptr %tgp117, align 4
  %fp118 = getelementptr i8, ptr %hp116, i64 16
  store i64 %tsres115, ptr %fp118, align 8
  %t1_i25.addr = alloca ptr
  store ptr %hp116, ptr %t1_i25.addr
  %ld119 = load ptr, ptr %t1_i25.addr
  %fp120 = getelementptr i8, ptr %ld119, i64 16
  %fv121 = load i64, ptr %fp120, align 8
  %v1_i26.addr = alloca i64
  store i64 %fv121, ptr %v1_i26.addr
  %hp122 = call ptr @march_alloc(i64 32)
  %tgp123 = getelementptr i8, ptr %hp122, i64 8
  store i32 0, ptr %tgp123, align 4
  %fp124 = getelementptr i8, ptr %hp122, i64 16
  store ptr @$lam2023$apply$25, ptr %fp124, align 8
  %ld125 = load i64, ptr %v1_i26.addr
  %fp126 = getelementptr i8, ptr %hp122, i64 24
  store i64 %ld125, ptr %fp126, align 8
  %$t2024_i27.addr = alloca ptr
  store ptr %hp122, ptr %$t2024_i27.addr
  %ld127 = load ptr, ptr %$t2024_i27.addr
  %fp128 = getelementptr i8, ptr %ld127, i64 16
  %fv129 = load ptr, ptr %fp128, align 8
  %tsres130 = call i64 %fv129(ptr %ld127, i64 0)
  %hp131 = call ptr @march_alloc(i64 24)
  %tgp132 = getelementptr i8, ptr %hp131, i64 8
  store i32 0, ptr %tgp132, align 4
  %fp133 = getelementptr i8, ptr %hp131, i64 16
  store i64 %tsres130, ptr %fp133, align 8
  %t2_i28.addr = alloca ptr
  store ptr %hp131, ptr %t2_i28.addr
  %ld134 = load ptr, ptr %t2_i28.addr
  %fp135 = getelementptr i8, ptr %ld134, i64 16
  %fv136 = load i64, ptr %fp135, align 8
  %c.addr = alloca i64
  store i64 %fv136, ptr %c.addr
  %ld137 = load i64, ptr %c.addr
  %cr138 = call ptr @march_int_to_string(i64 %ld137)
  %$t2032.addr = alloca ptr
  store ptr %cr138, ptr %$t2032.addr
  %sl139 = call ptr @march_string_lit(ptr @.str3, i64 25)
  %ld140 = load ptr, ptr %$t2032.addr
  %cr141 = call ptr @march_string_concat(ptr %sl139, ptr %ld140)
  %$t2033.addr = alloca ptr
  store ptr %cr141, ptr %$t2033.addr
  %ld142 = load ptr, ptr %$t2033.addr
  call void @march_println(ptr %ld142)
  %n_i23.addr = alloca i64
  store i64 100, ptr %n_i23.addr
  %ld143 = load i64, ptr %n_i23.addr
  %cr144 = call i64 @fan_out_inner(i64 %ld143, i64 0)
  %f.addr = alloca i64
  store i64 %cr144, ptr %f.addr
  %ld145 = load i64, ptr %f.addr
  %cr146 = call ptr @march_int_to_string(i64 %ld145)
  %$t2034.addr = alloca ptr
  store ptr %cr146, ptr %$t2034.addr
  %sl147 = call ptr @march_string_lit(ptr @.str4, i64 25)
  %ld148 = load ptr, ptr %$t2034.addr
  %cr149 = call ptr @march_string_concat(ptr %sl147, ptr %ld148)
  %$t2035.addr = alloca ptr
  store ptr %cr149, ptr %$t2035.addr
  %ld150 = load ptr, ptr %$t2035.addr
  call void @march_println(ptr %ld150)
  ret void
}

define i64 @$lam2017$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %cr151 = call i64 @collatz(i64 27, i64 0)
  ret i64 %cr151
}

define i64 @$lam2019$apply$23(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %cr152 = call i64 @collatz(i64 871, i64 0)
  ret i64 %cr152
}

define i64 @$lam2021$apply$24(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  ret i64 30
}

define i64 @$lam2023$apply$25(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld153 = load ptr, ptr %$clo.addr
  %fp154 = getelementptr i8, ptr %ld153, i64 24
  %fv155 = load i64, ptr %fp154, align 8
  %v1.addr = alloca i64
  store i64 %fv155, ptr %v1.addr
  %ld156 = load i64, ptr %v1.addr
  %ar157 = mul i64 %ld156, 3
  ret i64 %ar157
}

define i64 @$lam2026$apply$26(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld158 = load ptr, ptr %$clo.addr
  %fp159 = getelementptr i8, ptr %ld158, i64 24
  %fv160 = load i64, ptr %fp159, align 8
  %n.addr = alloca i64
  store i64 %fv160, ptr %n.addr
  %ld161 = load i64, ptr %n.addr
  %cr162 = call i64 @collatz(i64 %ld161, i64 0)
  ret i64 %cr162
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
