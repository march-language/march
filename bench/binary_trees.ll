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

@.str1 = private unnamed_addr constant [17 x i8] c" trees of depth \00"
@.str2 = private unnamed_addr constant [9 x i8] c" check: \00"
@.str3 = private unnamed_addr constant [23 x i8] c"stretch tree of depth \00"
@.str4 = private unnamed_addr constant [9 x i8] c" check: \00"
@.str5 = private unnamed_addr constant [26 x i8] c"long lived tree of depth \00"
@.str6 = private unnamed_addr constant [9 x i8] c" check: \00"

define ptr @make(i64 %d.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %ld1 = load i64, ptr %d.addr
  %cmp2 = icmp eq i64 %ld1, 0
  %ar3 = zext i1 %cmp2 to i64
  %$t2009.addr = alloca i64
  store i64 %ar3, ptr %$t2009.addr
  %ld4 = load i64, ptr %$t2009.addr
  %res_slot5 = alloca ptr
  %bi6 = trunc i64 %ld4 to i1
  br i1 %bi6, label %case_br3, label %case_default2
case_br3:
  %hp7 = call ptr @march_alloc(i64 16)
  %tgp8 = getelementptr i8, ptr %hp7, i64 8
  store i32 0, ptr %tgp8, align 4
  store ptr %hp7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %d.addr
  %ar10 = sub i64 %ld9, 1
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %$t2010.addr
  %cr12 = call ptr @make(i64 %ld11)
  %$t2011.addr = alloca ptr
  store ptr %cr12, ptr %$t2011.addr
  %ld13 = load i64, ptr %d.addr
  %ar14 = sub i64 %ld13, 1
  %$t2012.addr = alloca i64
  store i64 %ar14, ptr %$t2012.addr
  %ld15 = load i64, ptr %$t2012.addr
  %cr16 = call ptr @make(i64 %ld15)
  %$t2013.addr = alloca ptr
  store ptr %cr16, ptr %$t2013.addr
  %hp17 = call ptr @march_alloc(i64 32)
  %tgp18 = getelementptr i8, ptr %hp17, i64 8
  store i32 1, ptr %tgp18, align 4
  %ld19 = load ptr, ptr %$t2011.addr
  %fp20 = getelementptr i8, ptr %hp17, i64 16
  store ptr %ld19, ptr %fp20, align 8
  %ld21 = load ptr, ptr %$t2013.addr
  %fp22 = getelementptr i8, ptr %hp17, i64 24
  store ptr %ld21, ptr %fp22, align 8
  store ptr %hp17, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r23 = load ptr, ptr %res_slot5
  ret ptr %case_r23
}

define i64 @check(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld24 = load ptr, ptr %t.addr
  %res_slot25 = alloca ptr
  %tgp26 = getelementptr i8, ptr %ld24, i64 8
  %tag27 = load i32, ptr %tgp26, align 4
  switch i32 %tag27, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %ld28 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld28)
  %cv29 = inttoptr i64 1 to ptr
  store ptr %cv29, ptr %res_slot25
  br label %case_merge4
case_br7:
  %fp30 = getelementptr i8, ptr %ld24, i64 16
  %fv31 = load ptr, ptr %fp30, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv31, ptr %$f2017.addr
  %fp32 = getelementptr i8, ptr %ld24, i64 24
  %fv33 = load ptr, ptr %fp32, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv33, ptr %$f2018.addr
  %freed34 = call i64 @march_decrc_freed(ptr %ld24)
  %freed_b35 = icmp ne i64 %freed34, 0
  br i1 %freed_b35, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv33)
  call void @march_incrc(ptr %fv31)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld36 = load ptr, ptr %$f2018.addr
  %r.addr = alloca ptr
  store ptr %ld36, ptr %r.addr
  %ld37 = load ptr, ptr %$f2017.addr
  %l.addr = alloca ptr
  store ptr %ld37, ptr %l.addr
  %ld38 = load ptr, ptr %l.addr
  %cr39 = call i64 @check(ptr %ld38)
  %$t2014.addr = alloca i64
  store i64 %cr39, ptr %$t2014.addr
  %ld40 = load ptr, ptr %r.addr
  %cr41 = call i64 @check(ptr %ld40)
  %$t2015.addr = alloca i64
  store i64 %cr41, ptr %$t2015.addr
  %ld42 = load i64, ptr %$t2014.addr
  %ld43 = load i64, ptr %$t2015.addr
  %ar44 = add i64 %ld42, %ld43
  %$t2016.addr = alloca i64
  store i64 %ar44, ptr %$t2016.addr
  %ld45 = load i64, ptr %$t2016.addr
  %ar46 = add i64 %ld45, 1
  %cv47 = inttoptr i64 %ar46 to ptr
  store ptr %cv47, ptr %res_slot25
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r48 = load ptr, ptr %res_slot25
  %cv49 = ptrtoint ptr %case_r48 to i64
  ret i64 %cv49
}

define i64 @pow2(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld50 = load i64, ptr %n.addr
  %cmp51 = icmp eq i64 %ld50, 0
  %ar52 = zext i1 %cmp51 to i64
  %$t2019.addr = alloca i64
  store i64 %ar52, ptr %$t2019.addr
  %ld53 = load i64, ptr %$t2019.addr
  %res_slot54 = alloca ptr
  %bi55 = trunc i64 %ld53 to i1
  br i1 %bi55, label %case_br13, label %case_default12
case_br13:
  %cv56 = inttoptr i64 1 to ptr
  store ptr %cv56, ptr %res_slot54
  br label %case_merge11
case_default12:
  %ld57 = load i64, ptr %n.addr
  %ar58 = sub i64 %ld57, 1
  %$t2020.addr = alloca i64
  store i64 %ar58, ptr %$t2020.addr
  %ld59 = load i64, ptr %$t2020.addr
  %cr60 = call i64 @pow2(i64 %ld59)
  %$t2021.addr = alloca i64
  store i64 %cr60, ptr %$t2021.addr
  %ld61 = load i64, ptr %$t2021.addr
  %ld62 = load i64, ptr %$t2021.addr
  %ar63 = add i64 %ld61, %ld62
  %sr_s1.addr = alloca i64
  store i64 %ar63, ptr %sr_s1.addr
  %ld64 = load i64, ptr %sr_s1.addr
  %cv65 = inttoptr i64 %ld64 to ptr
  store ptr %cv65, ptr %res_slot54
  br label %case_merge11
case_merge11:
  %case_r66 = load ptr, ptr %res_slot54
  %cv67 = ptrtoint ptr %case_r66 to i64
  ret i64 %cv67
}

define i64 @sum_trees(i64 %iters.arg, i64 %depth.arg, i64 %acc.arg) {
entry:
  %iters.addr = alloca i64
  store i64 %iters.arg, ptr %iters.addr
  %depth.addr = alloca i64
  store i64 %depth.arg, ptr %depth.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld68 = load i64, ptr %iters.addr
  %cmp69 = icmp eq i64 %ld68, 0
  %ar70 = zext i1 %cmp69 to i64
  %$t2022.addr = alloca i64
  store i64 %ar70, ptr %$t2022.addr
  %ld71 = load i64, ptr %$t2022.addr
  %res_slot72 = alloca ptr
  %bi73 = trunc i64 %ld71 to i1
  br i1 %bi73, label %case_br16, label %case_default15
case_br16:
  %ld74 = load i64, ptr %acc.addr
  %cv75 = inttoptr i64 %ld74 to ptr
  store ptr %cv75, ptr %res_slot72
  br label %case_merge14
case_default15:
  %ld76 = load i64, ptr %iters.addr
  %ar77 = sub i64 %ld76, 1
  %$t2023.addr = alloca i64
  store i64 %ar77, ptr %$t2023.addr
  %ld78 = load i64, ptr %depth.addr
  %cr79 = call ptr @make(i64 %ld78)
  %$t2024.addr = alloca ptr
  store ptr %cr79, ptr %$t2024.addr
  %ld80 = load ptr, ptr %$t2024.addr
  %cr81 = call i64 @check(ptr %ld80)
  %$t2025.addr = alloca i64
  store i64 %cr81, ptr %$t2025.addr
  %ld82 = load i64, ptr %acc.addr
  %ld83 = load i64, ptr %$t2025.addr
  %ar84 = add i64 %ld82, %ld83
  %$t2026.addr = alloca i64
  store i64 %ar84, ptr %$t2026.addr
  %ld85 = load i64, ptr %$t2023.addr
  %ld86 = load i64, ptr %depth.addr
  %ld87 = load i64, ptr %$t2026.addr
  %cr88 = call i64 @sum_trees(i64 %ld85, i64 %ld86, i64 %ld87)
  %cv89 = inttoptr i64 %cr88 to ptr
  store ptr %cv89, ptr %res_slot72
  br label %case_merge14
case_merge14:
  %case_r90 = load ptr, ptr %res_slot72
  %cv91 = ptrtoint ptr %case_r90 to i64
  ret i64 %cv91
}

define void @run_depths(i64 %d.arg, i64 %max_depth.arg, i64 %min_depth.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %max_depth.addr = alloca i64
  store i64 %max_depth.arg, ptr %max_depth.addr
  %min_depth.addr = alloca i64
  store i64 %min_depth.arg, ptr %min_depth.addr
  %ld92 = load i64, ptr %d.addr
  %ld93 = load i64, ptr %max_depth.addr
  %cmp94 = icmp sgt i64 %ld92, %ld93
  %ar95 = zext i1 %cmp94 to i64
  %$t2027.addr = alloca i64
  store i64 %ar95, ptr %$t2027.addr
  %ld96 = load i64, ptr %$t2027.addr
  %res_slot97 = alloca ptr
  %bi98 = trunc i64 %ld96 to i1
  br i1 %bi98, label %case_br19, label %case_default18
case_br19:
  %cv99 = inttoptr i64 0 to ptr
  store ptr %cv99, ptr %res_slot97
  br label %case_merge17
case_default18:
  %ld100 = load i64, ptr %max_depth.addr
  %ld101 = load i64, ptr %d.addr
  %ar102 = sub i64 %ld100, %ld101
  %$t2028.addr = alloca i64
  store i64 %ar102, ptr %$t2028.addr
  %ld103 = load i64, ptr %$t2028.addr
  %ld104 = load i64, ptr %min_depth.addr
  %ar105 = add i64 %ld103, %ld104
  %$t2029.addr = alloca i64
  store i64 %ar105, ptr %$t2029.addr
  %ld106 = load i64, ptr %$t2029.addr
  %cr107 = call i64 @pow2(i64 %ld106)
  %iters.addr = alloca i64
  store i64 %cr107, ptr %iters.addr
  %ld108 = load i64, ptr %iters.addr
  %ld109 = load i64, ptr %d.addr
  %cr110 = call i64 @sum_trees(i64 %ld108, i64 %ld109, i64 0)
  %s.addr = alloca i64
  store i64 %cr110, ptr %s.addr
  %ld111 = load i64, ptr %iters.addr
  %cr112 = call ptr @march_int_to_string(i64 %ld111)
  %$t2030.addr = alloca ptr
  store ptr %cr112, ptr %$t2030.addr
  %ld113 = load ptr, ptr %$t2030.addr
  %sl114 = call ptr @march_string_lit(ptr @.str1, i64 16)
  %cr115 = call ptr @march_string_concat(ptr %ld113, ptr %sl114)
  %$t2031.addr = alloca ptr
  store ptr %cr115, ptr %$t2031.addr
  %ld116 = load i64, ptr %d.addr
  %cr117 = call ptr @march_int_to_string(i64 %ld116)
  %$t2032.addr = alloca ptr
  store ptr %cr117, ptr %$t2032.addr
  %ld118 = load ptr, ptr %$t2031.addr
  %ld119 = load ptr, ptr %$t2032.addr
  %cr120 = call ptr @march_string_concat(ptr %ld118, ptr %ld119)
  %$t2033.addr = alloca ptr
  store ptr %cr120, ptr %$t2033.addr
  %ld121 = load ptr, ptr %$t2033.addr
  %sl122 = call ptr @march_string_lit(ptr @.str2, i64 8)
  %cr123 = call ptr @march_string_concat(ptr %ld121, ptr %sl122)
  %$t2034.addr = alloca ptr
  store ptr %cr123, ptr %$t2034.addr
  %ld124 = load i64, ptr %s.addr
  %cr125 = call ptr @march_int_to_string(i64 %ld124)
  %$t2035.addr = alloca ptr
  store ptr %cr125, ptr %$t2035.addr
  %ld126 = load ptr, ptr %$t2034.addr
  %ld127 = load ptr, ptr %$t2035.addr
  %cr128 = call ptr @march_string_concat(ptr %ld126, ptr %ld127)
  %$t2036.addr = alloca ptr
  store ptr %cr128, ptr %$t2036.addr
  %ld129 = load ptr, ptr %$t2036.addr
  call void @march_println(ptr %ld129)
  %ld130 = load i64, ptr %d.addr
  %ar131 = add i64 %ld130, 2
  %$t2037.addr = alloca i64
  store i64 %ar131, ptr %$t2037.addr
  %ld132 = load i64, ptr %$t2037.addr
  %ld133 = load i64, ptr %max_depth.addr
  %ld134 = load i64, ptr %min_depth.addr
  %cr135 = call ptr @run_depths(i64 %ld132, i64 %ld133, i64 %ld134)
  store ptr %cr135, ptr %res_slot97
  br label %case_merge17
case_merge17:
  %case_r136 = load ptr, ptr %res_slot97
  ret void
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 15, ptr %n.addr
  %min_depth.addr = alloca i64
  store i64 4, ptr %min_depth.addr
  %ld137 = load i64, ptr %min_depth.addr
  %ar138 = add i64 %ld137, 2
  %$t2038.addr = alloca i64
  store i64 %ar138, ptr %$t2038.addr
  %ld139 = load i64, ptr %n.addr
  %ld140 = load i64, ptr %$t2038.addr
  %cmp141 = icmp sgt i64 %ld139, %ld140
  %ar142 = zext i1 %cmp141 to i64
  %$t2039.addr = alloca i64
  store i64 %ar142, ptr %$t2039.addr
  %ld143 = load i64, ptr %$t2039.addr
  %res_slot144 = alloca ptr
  %bi145 = trunc i64 %ld143 to i1
  br i1 %bi145, label %case_br22, label %case_default21
case_br22:
  %ld146 = load i64, ptr %n.addr
  %cv147 = inttoptr i64 %ld146 to ptr
  store ptr %cv147, ptr %res_slot144
  br label %case_merge20
case_default21:
  %ld148 = load i64, ptr %min_depth.addr
  %ar149 = add i64 %ld148, 2
  %cv150 = inttoptr i64 %ar149 to ptr
  store ptr %cv150, ptr %res_slot144
  br label %case_merge20
case_merge20:
  %case_r151 = load ptr, ptr %res_slot144
  %cv152 = ptrtoint ptr %case_r151 to i64
  %max_depth.addr = alloca i64
  store i64 %cv152, ptr %max_depth.addr
  %ld153 = load i64, ptr %max_depth.addr
  %ar154 = add i64 %ld153, 1
  %stretch.addr = alloca i64
  store i64 %ar154, ptr %stretch.addr
  %ld155 = load i64, ptr %stretch.addr
  %cr156 = call ptr @march_int_to_string(i64 %ld155)
  %$t2040.addr = alloca ptr
  store ptr %cr156, ptr %$t2040.addr
  %sl157 = call ptr @march_string_lit(ptr @.str3, i64 22)
  %ld158 = load ptr, ptr %$t2040.addr
  %cr159 = call ptr @march_string_concat(ptr %sl157, ptr %ld158)
  %$t2041.addr = alloca ptr
  store ptr %cr159, ptr %$t2041.addr
  %ld160 = load ptr, ptr %$t2041.addr
  %sl161 = call ptr @march_string_lit(ptr @.str4, i64 8)
  %cr162 = call ptr @march_string_concat(ptr %ld160, ptr %sl161)
  %$t2042.addr = alloca ptr
  store ptr %cr162, ptr %$t2042.addr
  %ld163 = load i64, ptr %stretch.addr
  %cr164 = call ptr @make(i64 %ld163)
  %$t2043.addr = alloca ptr
  store ptr %cr164, ptr %$t2043.addr
  %ld165 = load ptr, ptr %$t2043.addr
  %cr166 = call i64 @check(ptr %ld165)
  %$t2044.addr = alloca i64
  store i64 %cr166, ptr %$t2044.addr
  %ld167 = load i64, ptr %$t2044.addr
  %cr168 = call ptr @march_int_to_string(i64 %ld167)
  %$t2045.addr = alloca ptr
  store ptr %cr168, ptr %$t2045.addr
  %ld169 = load ptr, ptr %$t2042.addr
  %ld170 = load ptr, ptr %$t2045.addr
  %cr171 = call ptr @march_string_concat(ptr %ld169, ptr %ld170)
  %$t2046.addr = alloca ptr
  store ptr %cr171, ptr %$t2046.addr
  %ld172 = load ptr, ptr %$t2046.addr
  call void @march_println(ptr %ld172)
  %ld173 = load i64, ptr %max_depth.addr
  %cr174 = call ptr @make(i64 %ld173)
  %long_lived.addr = alloca ptr
  store ptr %cr174, ptr %long_lived.addr
  %ld175 = load i64, ptr %min_depth.addr
  %ld176 = load i64, ptr %max_depth.addr
  %ld177 = load i64, ptr %min_depth.addr
  %cr178 = call ptr @run_depths(i64 %ld175, i64 %ld176, i64 %ld177)
  %ld179 = load i64, ptr %max_depth.addr
  %cr180 = call ptr @march_int_to_string(i64 %ld179)
  %$t2047.addr = alloca ptr
  store ptr %cr180, ptr %$t2047.addr
  %sl181 = call ptr @march_string_lit(ptr @.str5, i64 25)
  %ld182 = load ptr, ptr %$t2047.addr
  %cr183 = call ptr @march_string_concat(ptr %sl181, ptr %ld182)
  %$t2048.addr = alloca ptr
  store ptr %cr183, ptr %$t2048.addr
  %ld184 = load ptr, ptr %$t2048.addr
  %sl185 = call ptr @march_string_lit(ptr @.str6, i64 8)
  %cr186 = call ptr @march_string_concat(ptr %ld184, ptr %sl185)
  %$t2049.addr = alloca ptr
  store ptr %cr186, ptr %$t2049.addr
  %ld187 = load ptr, ptr %long_lived.addr
  %cr188 = call i64 @check(ptr %ld187)
  %$t2050.addr = alloca i64
  store i64 %cr188, ptr %$t2050.addr
  %ld189 = load i64, ptr %$t2050.addr
  %cr190 = call ptr @march_int_to_string(i64 %ld189)
  %$t2051.addr = alloca ptr
  store ptr %cr190, ptr %$t2051.addr
  %ld191 = load ptr, ptr %$t2049.addr
  %ld192 = load ptr, ptr %$t2051.addr
  %cr193 = call ptr @march_string_concat(ptr %ld191, ptr %ld192)
  %$t2052.addr = alloca ptr
  store ptr %cr193, ptr %$t2052.addr
  %ld194 = load ptr, ptr %$t2052.addr
  call void @march_println(ptr %ld194)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
