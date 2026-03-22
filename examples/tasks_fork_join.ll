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

@.str1 = private unnamed_addr constant [27 x i8] c"--- Fork-join examples ---\00"
@.str2 = private unnamed_addr constant [21 x i8] c"par_sum(1..10000) = \00"
@.str3 = private unnamed_addr constant [33 x i8] c"max collatz steps in 1..10000 = \00"

define i64 @sum_range(i64 %lo.arg, i64 %hi.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %ld1 = load i64, ptr %lo.addr
  %ld2 = load i64, ptr %hi.addr
  %cmp3 = icmp sgt i64 %ld1, %ld2
  %ar4 = zext i1 %cmp3 to i64
  %$t2009.addr = alloca i64
  store i64 %ar4, ptr %$t2009.addr
  %ld5 = load i64, ptr %$t2009.addr
  %res_slot6 = alloca ptr
  %bi7 = trunc i64 %ld5 to i1
  br i1 %bi7, label %case_br3, label %case_default2
case_br3:
  %cv8 = inttoptr i64 0 to ptr
  store ptr %cv8, ptr %res_slot6
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %lo.addr
  %ar10 = add i64 %ld9, 1
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %$t2010.addr
  %ld12 = load i64, ptr %hi.addr
  %cr13 = call i64 @sum_range(i64 %ld11, i64 %ld12)
  %$t2011.addr = alloca i64
  store i64 %cr13, ptr %$t2011.addr
  %ld14 = load i64, ptr %lo.addr
  %ld15 = load i64, ptr %$t2011.addr
  %ar16 = add i64 %ld14, %ld15
  %cv17 = inttoptr i64 %ar16 to ptr
  store ptr %cv17, ptr %res_slot6
  br label %case_merge1
case_merge1:
  %case_r18 = load ptr, ptr %res_slot6
  %cv19 = ptrtoint ptr %case_r18 to i64
  ret i64 %cv19
}

define i64 @par_sum(i64 %lo.arg, i64 %hi.arg, i64 %threshold.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld20 = load i64, ptr %hi.addr
  %ld21 = load i64, ptr %lo.addr
  %ar22 = sub i64 %ld20, %ld21
  %$t2012.addr = alloca i64
  store i64 %ar22, ptr %$t2012.addr
  %ld23 = load i64, ptr %$t2012.addr
  %ld24 = load i64, ptr %threshold.addr
  %cmp25 = icmp sle i64 %ld23, %ld24
  %ar26 = zext i1 %cmp25 to i64
  %$t2013.addr = alloca i64
  store i64 %ar26, ptr %$t2013.addr
  %ld27 = load i64, ptr %$t2013.addr
  %res_slot28 = alloca ptr
  %bi29 = trunc i64 %ld27 to i1
  br i1 %bi29, label %case_br6, label %case_default5
case_br6:
  %ld30 = load i64, ptr %lo.addr
  %ld31 = load i64, ptr %hi.addr
  %cr32 = call i64 @sum_range(i64 %ld30, i64 %ld31)
  %cv33 = inttoptr i64 %cr32 to ptr
  store ptr %cv33, ptr %res_slot28
  br label %case_merge4
case_default5:
  %ld34 = load i64, ptr %hi.addr
  %ld35 = load i64, ptr %lo.addr
  %ar36 = sub i64 %ld34, %ld35
  %$t2014.addr = alloca i64
  store i64 %ar36, ptr %$t2014.addr
  %ld37 = load i64, ptr %$t2014.addr
  %ar38 = sdiv i64 %ld37, 2
  %$t2015.addr = alloca i64
  store i64 %ar38, ptr %$t2015.addr
  %ld39 = load i64, ptr %lo.addr
  %ld40 = load i64, ptr %$t2015.addr
  %ar41 = add i64 %ld39, %ld40
  %mid.addr = alloca i64
  store i64 %ar41, ptr %mid.addr
  %hp42 = call ptr @march_alloc(i64 48)
  %tgp43 = getelementptr i8, ptr %hp42, i64 8
  store i32 0, ptr %tgp43, align 4
  %fp44 = getelementptr i8, ptr %hp42, i64 16
  store ptr @$lam2016$apply$22, ptr %fp44, align 8
  %ld45 = load i64, ptr %lo.addr
  %fp46 = getelementptr i8, ptr %hp42, i64 24
  store i64 %ld45, ptr %fp46, align 8
  %ld47 = load i64, ptr %mid.addr
  %fp48 = getelementptr i8, ptr %hp42, i64 32
  store i64 %ld47, ptr %fp48, align 8
  %ld49 = load i64, ptr %threshold.addr
  %fp50 = getelementptr i8, ptr %hp42, i64 40
  store i64 %ld49, ptr %fp50, align 8
  %$t2017.addr = alloca ptr
  store ptr %hp42, ptr %$t2017.addr
  %ld51 = load ptr, ptr %$t2017.addr
  %fp52 = getelementptr i8, ptr %ld51, i64 16
  %fv53 = load ptr, ptr %fp52, align 8
  %tsres54 = call i64 %fv53(ptr %ld51, i64 0)
  %hp55 = call ptr @march_alloc(i64 24)
  %tgp56 = getelementptr i8, ptr %hp55, i64 8
  store i32 0, ptr %tgp56, align 4
  %fp57 = getelementptr i8, ptr %hp55, i64 16
  store i64 %tsres54, ptr %fp57, align 8
  %left.addr = alloca ptr
  store ptr %hp55, ptr %left.addr
  %hp58 = call ptr @march_alloc(i64 48)
  %tgp59 = getelementptr i8, ptr %hp58, i64 8
  store i32 0, ptr %tgp59, align 4
  %fp60 = getelementptr i8, ptr %hp58, i64 16
  store ptr @$lam2018$apply$23, ptr %fp60, align 8
  %ld61 = load i64, ptr %hi.addr
  %fp62 = getelementptr i8, ptr %hp58, i64 24
  store i64 %ld61, ptr %fp62, align 8
  %ld63 = load i64, ptr %mid.addr
  %fp64 = getelementptr i8, ptr %hp58, i64 32
  store i64 %ld63, ptr %fp64, align 8
  %ld65 = load i64, ptr %threshold.addr
  %fp66 = getelementptr i8, ptr %hp58, i64 40
  store i64 %ld65, ptr %fp66, align 8
  %$t2020.addr = alloca ptr
  store ptr %hp58, ptr %$t2020.addr
  %ld67 = load ptr, ptr %$t2020.addr
  %fp68 = getelementptr i8, ptr %ld67, i64 16
  %fv69 = load ptr, ptr %fp68, align 8
  %tsres70 = call i64 %fv69(ptr %ld67, i64 0)
  %hp71 = call ptr @march_alloc(i64 24)
  %tgp72 = getelementptr i8, ptr %hp71, i64 8
  store i32 0, ptr %tgp72, align 4
  %fp73 = getelementptr i8, ptr %hp71, i64 16
  store i64 %tsres70, ptr %fp73, align 8
  %right.addr = alloca ptr
  store ptr %hp71, ptr %right.addr
  %ld74 = load ptr, ptr %left.addr
  %fp75 = getelementptr i8, ptr %ld74, i64 16
  %fv76 = load i64, ptr %fp75, align 8
  %l.addr = alloca i64
  store i64 %fv76, ptr %l.addr
  %ld77 = load ptr, ptr %right.addr
  %fp78 = getelementptr i8, ptr %ld77, i64 16
  %fv79 = load i64, ptr %fp78, align 8
  %r.addr = alloca i64
  store i64 %fv79, ptr %r.addr
  %ld80 = load i64, ptr %l.addr
  %ld81 = load i64, ptr %r.addr
  %ar82 = add i64 %ld80, %ld81
  %cv83 = inttoptr i64 %ar82 to ptr
  store ptr %cv83, ptr %res_slot28
  br label %case_merge4
case_merge4:
  %case_r84 = load ptr, ptr %res_slot28
  %cv85 = ptrtoint ptr %case_r84 to i64
  ret i64 %cv85
}

define i64 @collatz(i64 %n.arg, i64 %steps.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %steps.addr = alloca i64
  store i64 %steps.arg, ptr %steps.addr
  %ld86 = load i64, ptr %n.addr
  %cmp87 = icmp eq i64 %ld86, 1
  %ar88 = zext i1 %cmp87 to i64
  %$t2022.addr = alloca i64
  store i64 %ar88, ptr %$t2022.addr
  %ld89 = load i64, ptr %$t2022.addr
  %res_slot90 = alloca ptr
  %bi91 = trunc i64 %ld89 to i1
  br i1 %bi91, label %case_br9, label %case_default8
case_br9:
  %ld92 = load i64, ptr %steps.addr
  %cv93 = inttoptr i64 %ld92 to ptr
  store ptr %cv93, ptr %res_slot90
  br label %case_merge7
case_default8:
  %ld94 = load i64, ptr %n.addr
  %ar95 = srem i64 %ld94, 2
  %$t2023.addr = alloca i64
  store i64 %ar95, ptr %$t2023.addr
  %ld96 = load i64, ptr %$t2023.addr
  %cmp97 = icmp eq i64 %ld96, 0
  %ar98 = zext i1 %cmp97 to i64
  %$t2024.addr = alloca i64
  store i64 %ar98, ptr %$t2024.addr
  %ld99 = load i64, ptr %$t2024.addr
  %res_slot100 = alloca ptr
  %bi101 = trunc i64 %ld99 to i1
  br i1 %bi101, label %case_br12, label %case_default11
case_br12:
  %ld102 = load i64, ptr %n.addr
  %ar103 = sdiv i64 %ld102, 2
  %$t2025.addr = alloca i64
  store i64 %ar103, ptr %$t2025.addr
  %ld104 = load i64, ptr %steps.addr
  %ar105 = add i64 %ld104, 1
  %$t2026.addr = alloca i64
  store i64 %ar105, ptr %$t2026.addr
  %ld106 = load i64, ptr %$t2025.addr
  %ld107 = load i64, ptr %$t2026.addr
  %cr108 = call i64 @collatz(i64 %ld106, i64 %ld107)
  %cv109 = inttoptr i64 %cr108 to ptr
  store ptr %cv109, ptr %res_slot100
  br label %case_merge10
case_default11:
  %ld110 = load i64, ptr %n.addr
  %ar111 = mul i64 3, %ld110
  %$t2027.addr = alloca i64
  store i64 %ar111, ptr %$t2027.addr
  %ld112 = load i64, ptr %$t2027.addr
  %ar113 = add i64 %ld112, 1
  %$t2028.addr = alloca i64
  store i64 %ar113, ptr %$t2028.addr
  %ld114 = load i64, ptr %steps.addr
  %ar115 = add i64 %ld114, 1
  %$t2029.addr = alloca i64
  store i64 %ar115, ptr %$t2029.addr
  %ld116 = load i64, ptr %$t2028.addr
  %ld117 = load i64, ptr %$t2029.addr
  %cr118 = call i64 @collatz(i64 %ld116, i64 %ld117)
  %cv119 = inttoptr i64 %cr118 to ptr
  store ptr %cv119, ptr %res_slot100
  br label %case_merge10
case_merge10:
  %case_r120 = load ptr, ptr %res_slot100
  store ptr %case_r120, ptr %res_slot90
  br label %case_merge7
case_merge7:
  %case_r121 = load ptr, ptr %res_slot90
  %cv122 = ptrtoint ptr %case_r121 to i64
  ret i64 %cv122
}

define i64 @max_collatz(i64 %lo.arg, i64 %hi.arg, i64 %threshold.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld123 = load i64, ptr %hi.addr
  %ld124 = load i64, ptr %lo.addr
  %ar125 = sub i64 %ld123, %ld124
  %$t2030.addr = alloca i64
  store i64 %ar125, ptr %$t2030.addr
  %ld126 = load i64, ptr %$t2030.addr
  %ld127 = load i64, ptr %threshold.addr
  %cmp128 = icmp sle i64 %ld126, %ld127
  %ar129 = zext i1 %cmp128 to i64
  %$t2031.addr = alloca i64
  store i64 %ar129, ptr %$t2031.addr
  %ld130 = load i64, ptr %$t2031.addr
  %res_slot131 = alloca ptr
  %bi132 = trunc i64 %ld130 to i1
  br i1 %bi132, label %case_br15, label %case_default14
case_br15:
  %ld133 = load i64, ptr %lo.addr
  %ld134 = load i64, ptr %hi.addr
  %cr135 = call i64 @max_collatz_seq(i64 %ld133, i64 %ld134, i64 0)
  %cv136 = inttoptr i64 %cr135 to ptr
  store ptr %cv136, ptr %res_slot131
  br label %case_merge13
case_default14:
  %ld137 = load i64, ptr %hi.addr
  %ld138 = load i64, ptr %lo.addr
  %ar139 = sub i64 %ld137, %ld138
  %$t2032.addr = alloca i64
  store i64 %ar139, ptr %$t2032.addr
  %ld140 = load i64, ptr %$t2032.addr
  %ar141 = sdiv i64 %ld140, 2
  %$t2033.addr = alloca i64
  store i64 %ar141, ptr %$t2033.addr
  %ld142 = load i64, ptr %lo.addr
  %ld143 = load i64, ptr %$t2033.addr
  %ar144 = add i64 %ld142, %ld143
  %mid.addr = alloca i64
  store i64 %ar144, ptr %mid.addr
  %hp145 = call ptr @march_alloc(i64 48)
  %tgp146 = getelementptr i8, ptr %hp145, i64 8
  store i32 0, ptr %tgp146, align 4
  %fp147 = getelementptr i8, ptr %hp145, i64 16
  store ptr @$lam2034$apply$24, ptr %fp147, align 8
  %ld148 = load i64, ptr %lo.addr
  %fp149 = getelementptr i8, ptr %hp145, i64 24
  store i64 %ld148, ptr %fp149, align 8
  %ld150 = load i64, ptr %mid.addr
  %fp151 = getelementptr i8, ptr %hp145, i64 32
  store i64 %ld150, ptr %fp151, align 8
  %ld152 = load i64, ptr %threshold.addr
  %fp153 = getelementptr i8, ptr %hp145, i64 40
  store i64 %ld152, ptr %fp153, align 8
  %$t2035.addr = alloca ptr
  store ptr %hp145, ptr %$t2035.addr
  %ld154 = load ptr, ptr %$t2035.addr
  %fp155 = getelementptr i8, ptr %ld154, i64 16
  %fv156 = load ptr, ptr %fp155, align 8
  %tsres157 = call i64 %fv156(ptr %ld154, i64 0)
  %hp158 = call ptr @march_alloc(i64 24)
  %tgp159 = getelementptr i8, ptr %hp158, i64 8
  store i32 0, ptr %tgp159, align 4
  %fp160 = getelementptr i8, ptr %hp158, i64 16
  store i64 %tsres157, ptr %fp160, align 8
  %left.addr = alloca ptr
  store ptr %hp158, ptr %left.addr
  %hp161 = call ptr @march_alloc(i64 48)
  %tgp162 = getelementptr i8, ptr %hp161, i64 8
  store i32 0, ptr %tgp162, align 4
  %fp163 = getelementptr i8, ptr %hp161, i64 16
  store ptr @$lam2036$apply$25, ptr %fp163, align 8
  %ld164 = load i64, ptr %hi.addr
  %fp165 = getelementptr i8, ptr %hp161, i64 24
  store i64 %ld164, ptr %fp165, align 8
  %ld166 = load i64, ptr %mid.addr
  %fp167 = getelementptr i8, ptr %hp161, i64 32
  store i64 %ld166, ptr %fp167, align 8
  %ld168 = load i64, ptr %threshold.addr
  %fp169 = getelementptr i8, ptr %hp161, i64 40
  store i64 %ld168, ptr %fp169, align 8
  %$t2038.addr = alloca ptr
  store ptr %hp161, ptr %$t2038.addr
  %ld170 = load ptr, ptr %$t2038.addr
  %fp171 = getelementptr i8, ptr %ld170, i64 16
  %fv172 = load ptr, ptr %fp171, align 8
  %tsres173 = call i64 %fv172(ptr %ld170, i64 0)
  %hp174 = call ptr @march_alloc(i64 24)
  %tgp175 = getelementptr i8, ptr %hp174, i64 8
  store i32 0, ptr %tgp175, align 4
  %fp176 = getelementptr i8, ptr %hp174, i64 16
  store i64 %tsres173, ptr %fp176, align 8
  %right.addr = alloca ptr
  store ptr %hp174, ptr %right.addr
  %ld177 = load ptr, ptr %left.addr
  %fp178 = getelementptr i8, ptr %ld177, i64 16
  %fv179 = load i64, ptr %fp178, align 8
  %l.addr = alloca i64
  store i64 %fv179, ptr %l.addr
  %ld180 = load ptr, ptr %right.addr
  %fp181 = getelementptr i8, ptr %ld180, i64 16
  %fv182 = load i64, ptr %fp181, align 8
  %r.addr = alloca i64
  store i64 %fv182, ptr %r.addr
  %ld183 = load i64, ptr %l.addr
  %a_i23.addr = alloca i64
  store i64 %ld183, ptr %a_i23.addr
  %ld184 = load i64, ptr %r.addr
  %b_i24.addr = alloca i64
  store i64 %ld184, ptr %b_i24.addr
  %ld185 = load i64, ptr %a_i23.addr
  %ld186 = load i64, ptr %b_i24.addr
  %cmp187 = icmp sgt i64 %ld185, %ld186
  %ar188 = zext i1 %cmp187 to i64
  %$t2021_i25.addr = alloca i64
  store i64 %ar188, ptr %$t2021_i25.addr
  %ld189 = load i64, ptr %$t2021_i25.addr
  %res_slot190 = alloca ptr
  %bi191 = trunc i64 %ld189 to i1
  br i1 %bi191, label %case_br18, label %case_default17
case_br18:
  %ld192 = load i64, ptr %a_i23.addr
  %cv193 = inttoptr i64 %ld192 to ptr
  store ptr %cv193, ptr %res_slot190
  br label %case_merge16
case_default17:
  %ld194 = load i64, ptr %b_i24.addr
  %cv195 = inttoptr i64 %ld194 to ptr
  store ptr %cv195, ptr %res_slot190
  br label %case_merge16
case_merge16:
  %case_r196 = load ptr, ptr %res_slot190
  store ptr %case_r196, ptr %res_slot131
  br label %case_merge13
case_merge13:
  %case_r197 = load ptr, ptr %res_slot131
  %cv198 = ptrtoint ptr %case_r197 to i64
  ret i64 %cv198
}

define i64 @max_collatz_seq(i64 %lo.arg, i64 %hi.arg, i64 %best.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %best.addr = alloca i64
  store i64 %best.arg, ptr %best.addr
  %ld199 = load i64, ptr %lo.addr
  %ld200 = load i64, ptr %hi.addr
  %cmp201 = icmp sgt i64 %ld199, %ld200
  %ar202 = zext i1 %cmp201 to i64
  %$t2039.addr = alloca i64
  store i64 %ar202, ptr %$t2039.addr
  %ld203 = load i64, ptr %$t2039.addr
  %res_slot204 = alloca ptr
  %bi205 = trunc i64 %ld203 to i1
  br i1 %bi205, label %case_br21, label %case_default20
case_br21:
  %ld206 = load i64, ptr %best.addr
  %cv207 = inttoptr i64 %ld206 to ptr
  store ptr %cv207, ptr %res_slot204
  br label %case_merge19
case_default20:
  %ld208 = load i64, ptr %lo.addr
  %cr209 = call i64 @collatz(i64 %ld208, i64 0)
  %steps.addr = alloca i64
  store i64 %cr209, ptr %steps.addr
  %ld210 = load i64, ptr %lo.addr
  %ar211 = add i64 %ld210, 1
  %$t2040.addr = alloca i64
  store i64 %ar211, ptr %$t2040.addr
  %ld212 = load i64, ptr %steps.addr
  %a_i26.addr = alloca i64
  store i64 %ld212, ptr %a_i26.addr
  %ld213 = load i64, ptr %best.addr
  %b_i27.addr = alloca i64
  store i64 %ld213, ptr %b_i27.addr
  %ld214 = load i64, ptr %a_i26.addr
  %ld215 = load i64, ptr %b_i27.addr
  %cmp216 = icmp sgt i64 %ld214, %ld215
  %ar217 = zext i1 %cmp216 to i64
  %$t2021_i28.addr = alloca i64
  store i64 %ar217, ptr %$t2021_i28.addr
  %ld218 = load i64, ptr %$t2021_i28.addr
  %res_slot219 = alloca ptr
  %bi220 = trunc i64 %ld218 to i1
  br i1 %bi220, label %case_br24, label %case_default23
case_br24:
  %ld221 = load i64, ptr %a_i26.addr
  %cv222 = inttoptr i64 %ld221 to ptr
  store ptr %cv222, ptr %res_slot219
  br label %case_merge22
case_default23:
  %ld223 = load i64, ptr %b_i27.addr
  %cv224 = inttoptr i64 %ld223 to ptr
  store ptr %cv224, ptr %res_slot219
  br label %case_merge22
case_merge22:
  %case_r225 = load ptr, ptr %res_slot219
  %cv226 = ptrtoint ptr %case_r225 to i64
  %$t2041.addr = alloca i64
  store i64 %cv226, ptr %$t2041.addr
  %ld227 = load i64, ptr %$t2040.addr
  %ld228 = load i64, ptr %hi.addr
  %ld229 = load i64, ptr %$t2041.addr
  %cr230 = call i64 @max_collatz_seq(i64 %ld227, i64 %ld228, i64 %ld229)
  %cv231 = inttoptr i64 %cr230 to ptr
  store ptr %cv231, ptr %res_slot204
  br label %case_merge19
case_merge19:
  %case_r232 = load ptr, ptr %res_slot204
  %cv233 = ptrtoint ptr %case_r232 to i64
  ret i64 %cv233
}

define void @march_main() {
entry:
  %sl234 = call ptr @march_string_lit(ptr @.str1, i64 26)
  call void @march_println(ptr %sl234)
  %cr235 = call i64 @par_sum(i64 1, i64 10000, i64 500)
  %total.addr = alloca i64
  store i64 %cr235, ptr %total.addr
  %ld236 = load i64, ptr %total.addr
  %cr237 = call ptr @march_int_to_string(i64 %ld236)
  %$t2042.addr = alloca ptr
  store ptr %cr237, ptr %$t2042.addr
  %sl238 = call ptr @march_string_lit(ptr @.str2, i64 20)
  %ld239 = load ptr, ptr %$t2042.addr
  %cr240 = call ptr @march_string_concat(ptr %sl238, ptr %ld239)
  %$t2043.addr = alloca ptr
  store ptr %cr240, ptr %$t2043.addr
  %ld241 = load ptr, ptr %$t2043.addr
  call void @march_println(ptr %ld241)
  %cr242 = call i64 @max_collatz(i64 1, i64 10000, i64 500)
  %max_steps.addr = alloca i64
  store i64 %cr242, ptr %max_steps.addr
  %ld243 = load i64, ptr %max_steps.addr
  %cr244 = call ptr @march_int_to_string(i64 %ld243)
  %$t2044.addr = alloca ptr
  store ptr %cr244, ptr %$t2044.addr
  %sl245 = call ptr @march_string_lit(ptr @.str3, i64 32)
  %ld246 = load ptr, ptr %$t2044.addr
  %cr247 = call ptr @march_string_concat(ptr %sl245, ptr %ld246)
  %$t2045.addr = alloca ptr
  store ptr %cr247, ptr %$t2045.addr
  %ld248 = load ptr, ptr %$t2045.addr
  call void @march_println(ptr %ld248)
  ret void
}

define i64 @$lam2016$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld249 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld249)
  %ld250 = load ptr, ptr %$clo.addr
  %fp251 = getelementptr i8, ptr %ld250, i64 24
  %fv252 = load ptr, ptr %fp251, align 8
  %cv253 = ptrtoint ptr %fv252 to i64
  %lo.addr = alloca i64
  store i64 %cv253, ptr %lo.addr
  %ld254 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld254)
  %ld255 = load ptr, ptr %$clo.addr
  %fp256 = getelementptr i8, ptr %ld255, i64 32
  %fv257 = load ptr, ptr %fp256, align 8
  %cv258 = ptrtoint ptr %fv257 to i64
  %mid.addr = alloca i64
  store i64 %cv258, ptr %mid.addr
  %ld259 = load ptr, ptr %$clo.addr
  %fp260 = getelementptr i8, ptr %ld259, i64 40
  %fv261 = load i64, ptr %fp260, align 8
  %threshold.addr = alloca i64
  store i64 %fv261, ptr %threshold.addr
  %ld262 = load i64, ptr %lo.addr
  %ld263 = load i64, ptr %mid.addr
  %ld264 = load i64, ptr %threshold.addr
  %cr265 = call i64 @par_sum(i64 %ld262, i64 %ld263, i64 %ld264)
  ret i64 %cr265
}

define i64 @$lam2018$apply$23(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld266 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld266)
  %ld267 = load ptr, ptr %$clo.addr
  %fp268 = getelementptr i8, ptr %ld267, i64 24
  %fv269 = load ptr, ptr %fp268, align 8
  %cv270 = ptrtoint ptr %fv269 to i64
  %hi.addr = alloca i64
  store i64 %cv270, ptr %hi.addr
  %ld271 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld271)
  %ld272 = load ptr, ptr %$clo.addr
  %fp273 = getelementptr i8, ptr %ld272, i64 32
  %fv274 = load ptr, ptr %fp273, align 8
  %cv275 = ptrtoint ptr %fv274 to i64
  %mid.addr = alloca i64
  store i64 %cv275, ptr %mid.addr
  %ld276 = load ptr, ptr %$clo.addr
  %fp277 = getelementptr i8, ptr %ld276, i64 40
  %fv278 = load i64, ptr %fp277, align 8
  %threshold.addr = alloca i64
  store i64 %fv278, ptr %threshold.addr
  %ld279 = load i64, ptr %mid.addr
  %ar280 = add i64 %ld279, 1
  %$t2019.addr = alloca i64
  store i64 %ar280, ptr %$t2019.addr
  %ld281 = load i64, ptr %$t2019.addr
  %ld282 = load i64, ptr %hi.addr
  %ld283 = load i64, ptr %threshold.addr
  %cr284 = call i64 @par_sum(i64 %ld281, i64 %ld282, i64 %ld283)
  ret i64 %cr284
}

define i64 @$lam2034$apply$24(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld285 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld285)
  %ld286 = load ptr, ptr %$clo.addr
  %fp287 = getelementptr i8, ptr %ld286, i64 24
  %fv288 = load ptr, ptr %fp287, align 8
  %cv289 = ptrtoint ptr %fv288 to i64
  %lo.addr = alloca i64
  store i64 %cv289, ptr %lo.addr
  %ld290 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld290)
  %ld291 = load ptr, ptr %$clo.addr
  %fp292 = getelementptr i8, ptr %ld291, i64 32
  %fv293 = load ptr, ptr %fp292, align 8
  %cv294 = ptrtoint ptr %fv293 to i64
  %mid.addr = alloca i64
  store i64 %cv294, ptr %mid.addr
  %ld295 = load ptr, ptr %$clo.addr
  %fp296 = getelementptr i8, ptr %ld295, i64 40
  %fv297 = load i64, ptr %fp296, align 8
  %threshold.addr = alloca i64
  store i64 %fv297, ptr %threshold.addr
  %ld298 = load i64, ptr %lo.addr
  %ld299 = load i64, ptr %mid.addr
  %ld300 = load i64, ptr %threshold.addr
  %cr301 = call i64 @max_collatz(i64 %ld298, i64 %ld299, i64 %ld300)
  ret i64 %cr301
}

define i64 @$lam2036$apply$25(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld302 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld302)
  %ld303 = load ptr, ptr %$clo.addr
  %fp304 = getelementptr i8, ptr %ld303, i64 24
  %fv305 = load ptr, ptr %fp304, align 8
  %cv306 = ptrtoint ptr %fv305 to i64
  %hi.addr = alloca i64
  store i64 %cv306, ptr %hi.addr
  %ld307 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld307)
  %ld308 = load ptr, ptr %$clo.addr
  %fp309 = getelementptr i8, ptr %ld308, i64 32
  %fv310 = load ptr, ptr %fp309, align 8
  %cv311 = ptrtoint ptr %fv310 to i64
  %mid.addr = alloca i64
  store i64 %cv311, ptr %mid.addr
  %ld312 = load ptr, ptr %$clo.addr
  %fp313 = getelementptr i8, ptr %ld312, i64 40
  %fv314 = load i64, ptr %fp313, align 8
  %threshold.addr = alloca i64
  store i64 %fv314, ptr %threshold.addr
  %ld315 = load i64, ptr %mid.addr
  %ar316 = add i64 %ld315, 1
  %$t2037.addr = alloca i64
  store i64 %ar316, ptr %$t2037.addr
  %ld317 = load i64, ptr %$t2037.addr
  %ld318 = load i64, ptr %hi.addr
  %ld319 = load i64, ptr %threshold.addr
  %cr320 = call i64 @max_collatz(i64 %ld317, i64 %ld318, i64 %ld319)
  ret i64 %cr320
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
