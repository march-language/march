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

@.str1 = private unnamed_addr constant [31 x i8] c"--- Work-stealing examples ---\00"
@.str2 = private unnamed_addr constant [15 x i8] c"par_fib(30) = \00"
@.str3 = private unnamed_addr constant [34 x i8] c"mixed tiers: fib(20) + fib(25) = \00"

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

define i64 @par_fib(ptr %pool.arg, i64 %n.arg, i64 %threshold.arg) {
entry:
  %pool.addr = alloca ptr
  store ptr %pool.arg, ptr %pool.addr
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
  %ld41 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld41)
  %hp42 = call ptr @march_alloc(i64 48)
  %tgp43 = getelementptr i8, ptr %hp42, i64 8
  store i32 0, ptr %tgp43, align 4
  %fp44 = getelementptr i8, ptr %hp42, i64 16
  store ptr @$lam2016$apply$22, ptr %fp44, align 8
  %ld45 = load i64, ptr %n.addr
  %fp46 = getelementptr i8, ptr %hp42, i64 24
  store i64 %ld45, ptr %fp46, align 8
  %ld47 = load ptr, ptr %pool.addr
  %fp48 = getelementptr i8, ptr %hp42, i64 32
  store ptr %ld47, ptr %fp48, align 8
  %ld49 = load i64, ptr %threshold.addr
  %fp50 = getelementptr i8, ptr %hp42, i64 40
  store i64 %ld49, ptr %fp50, align 8
  %$t2018.addr = alloca ptr
  store ptr %hp42, ptr %$t2018.addr
  %ld51 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld51)
  %ld52 = load ptr, ptr %$t2018.addr
  %fp53 = getelementptr i8, ptr %ld52, i64 16
  %fv54 = load ptr, ptr %fp53, align 8
  %tsres55 = call i64 %fv54(ptr %ld52, i64 0)
  %hp56 = call ptr @march_alloc(i64 24)
  %tgp57 = getelementptr i8, ptr %hp56, i64 8
  store i32 0, ptr %tgp57, align 4
  %fp58 = getelementptr i8, ptr %hp56, i64 16
  store i64 %tsres55, ptr %fp58, align 8
  %t1.addr = alloca ptr
  store ptr %hp56, ptr %t1.addr
  %ld59 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld59)
  %hp60 = call ptr @march_alloc(i64 48)
  %tgp61 = getelementptr i8, ptr %hp60, i64 8
  store i32 0, ptr %tgp61, align 4
  %fp62 = getelementptr i8, ptr %hp60, i64 16
  store ptr @$lam2019$apply$23, ptr %fp62, align 8
  %ld63 = load i64, ptr %n.addr
  %fp64 = getelementptr i8, ptr %hp60, i64 24
  store i64 %ld63, ptr %fp64, align 8
  %ld65 = load ptr, ptr %pool.addr
  %fp66 = getelementptr i8, ptr %hp60, i64 32
  store ptr %ld65, ptr %fp66, align 8
  %ld67 = load i64, ptr %threshold.addr
  %fp68 = getelementptr i8, ptr %hp60, i64 40
  store i64 %ld67, ptr %fp68, align 8
  %$t2021.addr = alloca ptr
  store ptr %hp60, ptr %$t2021.addr
  %ld69 = load ptr, ptr %$t2021.addr
  %fp70 = getelementptr i8, ptr %ld69, i64 16
  %fv71 = load ptr, ptr %fp70, align 8
  %tsres72 = call i64 %fv71(ptr %ld69, i64 0)
  %hp73 = call ptr @march_alloc(i64 24)
  %tgp74 = getelementptr i8, ptr %hp73, i64 8
  store i32 0, ptr %tgp74, align 4
  %fp75 = getelementptr i8, ptr %hp73, i64 16
  store i64 %tsres72, ptr %fp75, align 8
  %t2.addr = alloca ptr
  store ptr %hp73, ptr %t2.addr
  %ld76 = load ptr, ptr %t1.addr
  %fp77 = getelementptr i8, ptr %ld76, i64 16
  %fv78 = load i64, ptr %fp77, align 8
  %r1.addr = alloca i64
  store i64 %fv78, ptr %r1.addr
  %ld79 = load ptr, ptr %t2.addr
  %fp80 = getelementptr i8, ptr %ld79, i64 16
  %fv81 = load i64, ptr %fp80, align 8
  %r2.addr = alloca i64
  store i64 %fv81, ptr %r2.addr
  %ld82 = load i64, ptr %r1.addr
  %ld83 = load i64, ptr %r2.addr
  %ar84 = add i64 %ld82, %ld83
  %cv85 = inttoptr i64 %ar84 to ptr
  store ptr %cv85, ptr %res_slot36
  br label %case_merge7
case_merge7:
  %case_r86 = load ptr, ptr %res_slot36
  store ptr %case_r86, ptr %res_slot27
  br label %case_merge4
case_merge4:
  %case_r87 = load ptr, ptr %res_slot27
  %cv88 = ptrtoint ptr %case_r87 to i64
  ret i64 %cv88
}

define i64 @mixed_tiers(ptr %pool.arg) {
entry:
  %pool.addr = alloca ptr
  store ptr %pool.arg, ptr %pool.addr
  %hp89 = call ptr @march_alloc(i64 24)
  %tgp90 = getelementptr i8, ptr %hp89, i64 8
  store i32 0, ptr %tgp90, align 4
  %fp91 = getelementptr i8, ptr %hp89, i64 16
  store ptr @$lam2024$apply$25, ptr %fp91, align 8
  %$t2025.addr = alloca ptr
  store ptr %hp89, ptr %$t2025.addr
  %ld92 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld92)
  %ld93 = load ptr, ptr %$t2025.addr
  %fp94 = getelementptr i8, ptr %ld93, i64 16
  %fv95 = load ptr, ptr %fp94, align 8
  %tsres96 = call i64 %fv95(ptr %ld93, i64 0)
  %hp97 = call ptr @march_alloc(i64 24)
  %tgp98 = getelementptr i8, ptr %hp97, i64 8
  store i32 0, ptr %tgp98, align 4
  %fp99 = getelementptr i8, ptr %hp97, i64 16
  store i64 %tsres96, ptr %fp99, align 8
  %t1.addr = alloca ptr
  store ptr %hp97, ptr %t1.addr
  %hp100 = call ptr @march_alloc(i64 24)
  %tgp101 = getelementptr i8, ptr %hp100, i64 8
  store i32 0, ptr %tgp101, align 4
  %fp102 = getelementptr i8, ptr %hp100, i64 16
  store ptr @$lam2026$apply$26, ptr %fp102, align 8
  %$t2027.addr = alloca ptr
  store ptr %hp100, ptr %$t2027.addr
  %ld103 = load ptr, ptr %$t2027.addr
  %fp104 = getelementptr i8, ptr %ld103, i64 16
  %fv105 = load ptr, ptr %fp104, align 8
  %tsres106 = call i64 %fv105(ptr %ld103, i64 0)
  %hp107 = call ptr @march_alloc(i64 24)
  %tgp108 = getelementptr i8, ptr %hp107, i64 8
  store i32 0, ptr %tgp108, align 4
  %fp109 = getelementptr i8, ptr %hp107, i64 16
  store i64 %tsres106, ptr %fp109, align 8
  %t2.addr = alloca ptr
  store ptr %hp107, ptr %t2.addr
  %ld110 = load ptr, ptr %t1.addr
  %fp111 = getelementptr i8, ptr %ld110, i64 16
  %fv112 = load i64, ptr %fp111, align 8
  %r1.addr = alloca i64
  store i64 %fv112, ptr %r1.addr
  %ld113 = load ptr, ptr %t2.addr
  %fp114 = getelementptr i8, ptr %ld113, i64 16
  %fv115 = load i64, ptr %fp114, align 8
  %r2.addr = alloca i64
  store i64 %fv115, ptr %r2.addr
  %ld116 = load i64, ptr %r1.addr
  %ld117 = load i64, ptr %r2.addr
  %ar118 = add i64 %ld116, %ld117
  ret i64 %ar118
}

define void @march_main() {
entry:
  %pool.addr = alloca ptr
  store ptr null, ptr %pool.addr
  %sl119 = call ptr @march_string_lit(ptr @.str1, i64 30)
  call void @march_println(ptr %sl119)
  %ld120 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld120)
  %ld121 = load ptr, ptr %pool.addr
  %cr122 = call i64 @par_fib(ptr %ld121, i64 30, i64 15)
  %r.addr = alloca i64
  store i64 %cr122, ptr %r.addr
  %ld123 = load i64, ptr %r.addr
  %cr124 = call ptr @march_int_to_string(i64 %ld123)
  %$t2028.addr = alloca ptr
  store ptr %cr124, ptr %$t2028.addr
  %sl125 = call ptr @march_string_lit(ptr @.str2, i64 14)
  %ld126 = load ptr, ptr %$t2028.addr
  %cr127 = call ptr @march_string_concat(ptr %sl125, ptr %ld126)
  %$t2029.addr = alloca ptr
  store ptr %cr127, ptr %$t2029.addr
  %ld128 = load ptr, ptr %$t2029.addr
  call void @march_println(ptr %ld128)
  %ld129 = load ptr, ptr %pool.addr
  %cr130 = call i64 @mixed_tiers(ptr %ld129)
  %m.addr = alloca i64
  store i64 %cr130, ptr %m.addr
  %ld131 = load i64, ptr %m.addr
  %cr132 = call ptr @march_int_to_string(i64 %ld131)
  %$t2030.addr = alloca ptr
  store ptr %cr132, ptr %$t2030.addr
  %sl133 = call ptr @march_string_lit(ptr @.str3, i64 33)
  %ld134 = load ptr, ptr %$t2030.addr
  %cr135 = call ptr @march_string_concat(ptr %sl133, ptr %ld134)
  %$t2031.addr = alloca ptr
  store ptr %cr135, ptr %$t2031.addr
  %ld136 = load ptr, ptr %$t2031.addr
  call void @march_println(ptr %ld136)
  ret void
}

define i64 @$lam2016$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld137 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld137)
  %ld138 = load ptr, ptr %$clo.addr
  %fp139 = getelementptr i8, ptr %ld138, i64 24
  %fv140 = load ptr, ptr %fp139, align 8
  %cv141 = ptrtoint ptr %fv140 to i64
  %n.addr = alloca i64
  store i64 %cv141, ptr %n.addr
  %ld142 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld142)
  %ld143 = load ptr, ptr %$clo.addr
  %fp144 = getelementptr i8, ptr %ld143, i64 32
  %fv145 = load ptr, ptr %fp144, align 8
  %pool.addr = alloca ptr
  store ptr %fv145, ptr %pool.addr
  %ld146 = load ptr, ptr %$clo.addr
  %fp147 = getelementptr i8, ptr %ld146, i64 40
  %fv148 = load i64, ptr %fp147, align 8
  %threshold.addr = alloca i64
  store i64 %fv148, ptr %threshold.addr
  %ld149 = load i64, ptr %n.addr
  %ar150 = sub i64 %ld149, 1
  %$t2017.addr = alloca i64
  store i64 %ar150, ptr %$t2017.addr
  %ld151 = load ptr, ptr %pool.addr
  %ld152 = load i64, ptr %$t2017.addr
  %ld153 = load i64, ptr %threshold.addr
  %cr154 = call i64 @par_fib(ptr %ld151, i64 %ld152, i64 %ld153)
  ret i64 %cr154
}

define i64 @$lam2019$apply$23(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld155 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld155)
  %ld156 = load ptr, ptr %$clo.addr
  %fp157 = getelementptr i8, ptr %ld156, i64 24
  %fv158 = load ptr, ptr %fp157, align 8
  %cv159 = ptrtoint ptr %fv158 to i64
  %n.addr = alloca i64
  store i64 %cv159, ptr %n.addr
  %ld160 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld160)
  %ld161 = load ptr, ptr %$clo.addr
  %fp162 = getelementptr i8, ptr %ld161, i64 32
  %fv163 = load ptr, ptr %fp162, align 8
  %pool.addr = alloca ptr
  store ptr %fv163, ptr %pool.addr
  %ld164 = load ptr, ptr %$clo.addr
  %fp165 = getelementptr i8, ptr %ld164, i64 40
  %fv166 = load i64, ptr %fp165, align 8
  %threshold.addr = alloca i64
  store i64 %fv166, ptr %threshold.addr
  %ld167 = load i64, ptr %n.addr
  %ar168 = sub i64 %ld167, 2
  %$t2020.addr = alloca i64
  store i64 %ar168, ptr %$t2020.addr
  %ld169 = load ptr, ptr %pool.addr
  %ld170 = load i64, ptr %$t2020.addr
  %ld171 = load i64, ptr %threshold.addr
  %cr172 = call i64 @par_fib(ptr %ld169, i64 %ld170, i64 %ld171)
  ret i64 %cr172
}

define i64 @$lam2022$apply$24(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld173 = load ptr, ptr %$clo.addr
  %fp174 = getelementptr i8, ptr %ld173, i64 24
  %fv175 = load i64, ptr %fp174, align 8
  %n.addr = alloca i64
  store i64 %fv175, ptr %n.addr
  %ld176 = load i64, ptr %n.addr
  %cr177 = call i64 @fib(i64 %ld176)
  ret i64 %cr177
}

define i64 @$lam2024$apply$25(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %n_i24.addr = alloca i64
  store i64 20, ptr %n_i24.addr
  %hp178 = call ptr @march_alloc(i64 32)
  %tgp179 = getelementptr i8, ptr %hp178, i64 8
  store i32 0, ptr %tgp179, align 4
  %fp180 = getelementptr i8, ptr %hp178, i64 16
  store ptr @$lam2022$apply$24, ptr %fp180, align 8
  %ld181 = load i64, ptr %n_i24.addr
  %fp182 = getelementptr i8, ptr %hp178, i64 24
  store i64 %ld181, ptr %fp182, align 8
  %$t2023_i25.addr = alloca ptr
  store ptr %hp178, ptr %$t2023_i25.addr
  %ld183 = load ptr, ptr %$t2023_i25.addr
  %fp184 = getelementptr i8, ptr %ld183, i64 16
  %fv185 = load ptr, ptr %fp184, align 8
  %tsres186 = call i64 %fv185(ptr %ld183, i64 0)
  %hp187 = call ptr @march_alloc(i64 24)
  %tgp188 = getelementptr i8, ptr %hp187, i64 8
  store i32 0, ptr %tgp188, align 4
  %fp189 = getelementptr i8, ptr %hp187, i64 16
  store i64 %tsres186, ptr %fp189, align 8
  %t_i26.addr = alloca ptr
  store ptr %hp187, ptr %t_i26.addr
  %ld190 = load ptr, ptr %t_i26.addr
  %fp191 = getelementptr i8, ptr %ld190, i64 16
  %fv192 = load i64, ptr %fp191, align 8
  ret i64 %fv192
}

define i64 @$lam2026$apply$26(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %n_i27.addr = alloca i64
  store i64 25, ptr %n_i27.addr
  %hp193 = call ptr @march_alloc(i64 32)
  %tgp194 = getelementptr i8, ptr %hp193, i64 8
  store i32 0, ptr %tgp194, align 4
  %fp195 = getelementptr i8, ptr %hp193, i64 16
  store ptr @$lam2022$apply$24, ptr %fp195, align 8
  %ld196 = load i64, ptr %n_i27.addr
  %fp197 = getelementptr i8, ptr %hp193, i64 24
  store i64 %ld196, ptr %fp197, align 8
  %$t2023_i28.addr = alloca ptr
  store ptr %hp193, ptr %$t2023_i28.addr
  %ld198 = load ptr, ptr %$t2023_i28.addr
  %fp199 = getelementptr i8, ptr %ld198, i64 16
  %fv200 = load ptr, ptr %fp199, align 8
  %tsres201 = call i64 %fv200(ptr %ld198, i64 0)
  %hp202 = call ptr @march_alloc(i64 24)
  %tgp203 = getelementptr i8, ptr %hp202, i64 8
  store i32 0, ptr %tgp203, align 4
  %fp204 = getelementptr i8, ptr %hp202, i64 16
  store i64 %tsres201, ptr %fp204, align 8
  %t_i29.addr = alloca ptr
  store ptr %hp202, ptr %t_i29.addr
  %ld205 = load ptr, ptr %t_i29.addr
  %fp206 = getelementptr i8, ptr %ld205, i64 16
  %fv207 = load i64, ptr %fp206, align 8
  ret i64 %fv207
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
