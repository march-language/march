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

@.str1 = private unnamed_addr constant [4 x i8] c"GET\00"
@.str2 = private unnamed_addr constant [5 x i8] c"POST\00"
@.str3 = private unnamed_addr constant [4 x i8] c"PUT\00"
@.str4 = private unnamed_addr constant [6 x i8] c"PATCH\00"
@.str5 = private unnamed_addr constant [7 x i8] c"DELETE\00"
@.str6 = private unnamed_addr constant [5 x i8] c"HEAD\00"
@.str7 = private unnamed_addr constant [8 x i8] c"OPTIONS\00"
@.str8 = private unnamed_addr constant [6 x i8] c"TRACE\00"
@.str9 = private unnamed_addr constant [8 x i8] c"CONNECT\00"
@.str10 = private unnamed_addr constant [9 x i8] c"https://\00"
@.str11 = private unnamed_addr constant [8 x i8] c"http://\00"
@.str12 = private unnamed_addr constant [2 x i8] c"/\00"
@.str13 = private unnamed_addr constant [2 x i8] c"/\00"
@.str14 = private unnamed_addr constant [2 x i8] c"?\00"
@.str15 = private unnamed_addr constant [2 x i8] c":\00"
@.str16 = private unnamed_addr constant [9 x i8] c"defaults\00"
@.str17 = private unnamed_addr constant [47 x i8] c"Streaming GET response from httpbin.org/get...\00"
@.str18 = private unnamed_addr constant [4 x i8] c"---\00"
@.str19 = private unnamed_addr constant [23 x i8] c"http://httpbin.org/get\00"
@.str20 = private unnamed_addr constant [4 x i8] c"---\00"
@.str21 = private unnamed_addr constant [9 x i8] c"Status: \00"
@.str22 = private unnamed_addr constant [7 x i8] c"Error!\00"
@.str23 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str24 = private unnamed_addr constant [4 x i8] c"url\00"
@.str25 = private unnamed_addr constant [1 x i8] c"\00"
@.str26 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str27 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str28 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str29 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str30 = private unnamed_addr constant [1 x i8] c"\00"
@.str31 = private unnamed_addr constant [1 x i8] c"\00"
@.str32 = private unnamed_addr constant [8 x i8] c"[chunk \00"
@.str33 = private unnamed_addr constant [8 x i8] c" bytes]\00"

define ptr @Http.method_to_string(ptr %m.arg) {
entry:
  %m.addr = alloca ptr
  store ptr %m.arg, ptr %m.addr
  %ld1 = load ptr, ptr %m.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
      i32 2, label %case_br5
      i32 3, label %case_br6
      i32 4, label %case_br7
      i32 5, label %case_br8
      i32 6, label %case_br9
      i32 7, label %case_br10
      i32 8, label %case_br11
      i32 9, label %case_br12
  ]
case_br3:
  %ld5 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld5)
  %sl6 = call ptr @march_string_lit(ptr @.str1, i64 3)
  store ptr %sl6, ptr %res_slot2
  br label %case_merge1
case_br4:
  %ld7 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld7)
  %sl8 = call ptr @march_string_lit(ptr @.str2, i64 4)
  store ptr %sl8, ptr %res_slot2
  br label %case_merge1
case_br5:
  %ld9 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld9)
  %sl10 = call ptr @march_string_lit(ptr @.str3, i64 3)
  store ptr %sl10, ptr %res_slot2
  br label %case_merge1
case_br6:
  %ld11 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld11)
  %sl12 = call ptr @march_string_lit(ptr @.str4, i64 5)
  store ptr %sl12, ptr %res_slot2
  br label %case_merge1
case_br7:
  %ld13 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld13)
  %sl14 = call ptr @march_string_lit(ptr @.str5, i64 6)
  store ptr %sl14, ptr %res_slot2
  br label %case_merge1
case_br8:
  %ld15 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld15)
  %sl16 = call ptr @march_string_lit(ptr @.str6, i64 4)
  store ptr %sl16, ptr %res_slot2
  br label %case_merge1
case_br9:
  %ld17 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld17)
  %sl18 = call ptr @march_string_lit(ptr @.str7, i64 7)
  store ptr %sl18, ptr %res_slot2
  br label %case_merge1
case_br10:
  %ld19 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld19)
  %sl20 = call ptr @march_string_lit(ptr @.str8, i64 5)
  store ptr %sl20, ptr %res_slot2
  br label %case_merge1
case_br11:
  %ld21 = load ptr, ptr %m.addr
  call void @march_decrc(ptr %ld21)
  %sl22 = call ptr @march_string_lit(ptr @.str9, i64 7)
  store ptr %sl22, ptr %res_slot2
  br label %case_merge1
case_br12:
  %fp23 = getelementptr i8, ptr %ld1, i64 16
  %fv24 = load ptr, ptr %fp23, align 8
  %$f531.addr = alloca ptr
  store ptr %fv24, ptr %$f531.addr
  %freed25 = call i64 @march_decrc_freed(ptr %ld1)
  %freed_b26 = icmp ne i64 %freed25, 0
  br i1 %freed_b26, label %br_unique13, label %br_shared14
br_shared14:
  call void @march_incrc(ptr %fv24)
  br label %br_body15
br_unique13:
  br label %br_body15
br_body15:
  %ld27 = load ptr, ptr %$f531.addr
  %s.addr = alloca ptr
  store ptr %ld27, ptr %s.addr
  %ld28 = load ptr, ptr %s.addr
  store ptr %ld28, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r29 = load ptr, ptr %res_slot2
  ret ptr %case_r29
}

define ptr @Http.parse_url(ptr %url.arg) {
entry:
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld30 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld30)
  %ld31 = load ptr, ptr %url.addr
  %sl32 = call ptr @march_string_lit(ptr @.str10, i64 8)
  %cr33 = call i64 @march_string_starts_with(ptr %ld31, ptr %sl32)
  %has_https.addr = alloca i64
  store i64 %cr33, ptr %has_https.addr
  %ld34 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld34)
  %ld35 = load ptr, ptr %url.addr
  %sl36 = call ptr @march_string_lit(ptr @.str11, i64 7)
  %cr37 = call i64 @march_string_starts_with(ptr %ld35, ptr %sl36)
  %has_http.addr = alloca i64
  store i64 %cr37, ptr %has_http.addr
  %ld38 = load i64, ptr %has_https.addr
  %ar39 = xor i64 %ld38, 1
  %$t692.addr = alloca i64
  store i64 %ar39, ptr %$t692.addr
  %ld40 = load i64, ptr %has_http.addr
  %ar41 = xor i64 %ld40, 1
  %$t693.addr = alloca i64
  store i64 %ar41, ptr %$t693.addr
  %ld42 = load i64, ptr %$t692.addr
  %ld43 = load i64, ptr %$t693.addr
  %ar44 = and i64 %ld42, %ld43
  %$t694.addr = alloca i64
  store i64 %ar44, ptr %$t694.addr
  %ld45 = load i64, ptr %$t694.addr
  %res_slot46 = alloca ptr
  %bi47 = trunc i64 %ld45 to i1
  br i1 %bi47, label %case_br18, label %case_default17
case_br18:
  %hp48 = call ptr @march_alloc(i64 24)
  %tgp49 = getelementptr i8, ptr %hp48, i64 8
  store i32 0, ptr %tgp49, align 4
  %ld50 = load ptr, ptr %url.addr
  %fp51 = getelementptr i8, ptr %hp48, i64 16
  store ptr %ld50, ptr %fp51, align 8
  %$t695.addr = alloca ptr
  store ptr %hp48, ptr %$t695.addr
  %hp52 = call ptr @march_alloc(i64 24)
  %tgp53 = getelementptr i8, ptr %hp52, i64 8
  store i32 1, ptr %tgp53, align 4
  %ld54 = load ptr, ptr %$t695.addr
  %fp55 = getelementptr i8, ptr %hp52, i64 16
  store ptr %ld54, ptr %fp55, align 8
  store ptr %hp52, ptr %res_slot46
  br label %case_merge16
case_default17:
  %ld56 = load i64, ptr %has_https.addr
  %res_slot57 = alloca ptr
  %bi58 = trunc i64 %ld56 to i1
  br i1 %bi58, label %case_br21, label %case_default20
case_br21:
  %hp59 = call ptr @march_alloc(i64 16)
  %tgp60 = getelementptr i8, ptr %hp59, i64 8
  store i32 1, ptr %tgp60, align 4
  store ptr %hp59, ptr %res_slot57
  br label %case_merge19
case_default20:
  %hp61 = call ptr @march_alloc(i64 16)
  %tgp62 = getelementptr i8, ptr %hp61, i64 8
  store i32 0, ptr %tgp62, align 4
  store ptr %hp61, ptr %res_slot57
  br label %case_merge19
case_merge19:
  %case_r63 = load ptr, ptr %res_slot57
  %url_scheme.addr = alloca ptr
  store ptr %case_r63, ptr %url_scheme.addr
  %ld64 = load i64, ptr %has_https.addr
  %res_slot65 = alloca ptr
  %bi66 = trunc i64 %ld64 to i1
  br i1 %bi66, label %case_br24, label %case_default23
case_br24:
  %cv67 = inttoptr i64 8 to ptr
  store ptr %cv67, ptr %res_slot65
  br label %case_merge22
case_default23:
  %cv68 = inttoptr i64 7 to ptr
  store ptr %cv68, ptr %res_slot65
  br label %case_merge22
case_merge22:
  %case_r69 = load ptr, ptr %res_slot65
  %cv70 = ptrtoint ptr %case_r69 to i64
  %prefix_len.addr = alloca i64
  store i64 %cv70, ptr %prefix_len.addr
  %ld71 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld71)
  %ld72 = load ptr, ptr %url.addr
  %cr73 = call i64 @march_string_byte_length(ptr %ld72)
  %$t696.addr = alloca i64
  store i64 %cr73, ptr %$t696.addr
  %ld74 = load i64, ptr %$t696.addr
  %ld75 = load i64, ptr %prefix_len.addr
  %ar76 = sub i64 %ld74, %ld75
  %$t697.addr = alloca i64
  store i64 %ar76, ptr %$t697.addr
  %ld77 = load ptr, ptr %url.addr
  %ld78 = load i64, ptr %prefix_len.addr
  %ld79 = load i64, ptr %$t697.addr
  %cr80 = call ptr @march_string_slice(ptr %ld77, i64 %ld78, i64 %ld79)
  %rest.addr = alloca ptr
  store ptr %cr80, ptr %rest.addr
  %ld81 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld81)
  %ld82 = load ptr, ptr %rest.addr
  %sl83 = call ptr @march_string_lit(ptr @.str12, i64 1)
  %cr84 = call ptr @march_string_index_of(ptr %ld82, ptr %sl83)
  %path_idx.addr = alloca ptr
  store ptr %cr84, ptr %path_idx.addr
  %ld85 = load ptr, ptr %path_idx.addr
  %res_slot86 = alloca ptr
  %tgp87 = getelementptr i8, ptr %ld85, i64 8
  %tag88 = load i32, ptr %tgp87, align 4
  switch i32 %tag88, label %case_default26 [
      i32 1, label %case_br27
      i32 0, label %case_br28
  ]
case_br27:
  %fp89 = getelementptr i8, ptr %ld85, i64 16
  %fv90 = load ptr, ptr %fp89, align 8
  %$f698.addr = alloca ptr
  store ptr %fv90, ptr %$f698.addr
  %ld91 = load ptr, ptr %$f698.addr
  %i.addr = alloca ptr
  store ptr %ld91, ptr %i.addr
  %ld92 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld92)
  %ld93 = load ptr, ptr %rest.addr
  %ld94 = load ptr, ptr %i.addr
  %cr95 = call ptr @march_string_slice(ptr %ld93, i64 0, ptr %ld94)
  store ptr %cr95, ptr %res_slot86
  br label %case_merge25
case_br28:
  %ld96 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld96)
  %ld97 = load ptr, ptr %rest.addr
  store ptr %ld97, ptr %res_slot86
  br label %case_merge25
case_default26:
  unreachable
case_merge25:
  %case_r98 = load ptr, ptr %res_slot86
  %host_part.addr = alloca ptr
  store ptr %case_r98, ptr %host_part.addr
  %ld99 = load ptr, ptr %path_idx.addr
  %res_slot100 = alloca ptr
  %tgp101 = getelementptr i8, ptr %ld99, i64 8
  %tag102 = load i32, ptr %tgp101, align 4
  switch i32 %tag102, label %case_default30 [
      i32 1, label %case_br31
      i32 0, label %case_br32
  ]
case_br31:
  %fp103 = getelementptr i8, ptr %ld99, i64 16
  %fv104 = load ptr, ptr %fp103, align 8
  %$f701.addr = alloca ptr
  store ptr %fv104, ptr %$f701.addr
  %ld105 = load ptr, ptr %path_idx.addr
  call void @march_decrc(ptr %ld105)
  %ld106 = load ptr, ptr %$f701.addr
  %i_1.addr = alloca ptr
  store ptr %ld106, ptr %i_1.addr
  %ld107 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld107)
  %ld108 = load ptr, ptr %rest.addr
  %cr109 = call i64 @march_string_byte_length(ptr %ld108)
  %$t699.addr = alloca i64
  store i64 %cr109, ptr %$t699.addr
  %ld110 = load i64, ptr %$t699.addr
  %ld111 = load ptr, ptr %i_1.addr
  %cv112 = ptrtoint ptr %ld111 to i64
  %ar113 = sub i64 %ld110, %cv112
  %$t700.addr = alloca i64
  store i64 %ar113, ptr %$t700.addr
  %ld114 = load ptr, ptr %rest.addr
  %ld115 = load ptr, ptr %i_1.addr
  %ld116 = load i64, ptr %$t700.addr
  %cr117 = call ptr @march_string_slice(ptr %ld114, ptr %ld115, i64 %ld116)
  store ptr %cr117, ptr %res_slot100
  br label %case_merge29
case_br32:
  %ld118 = load ptr, ptr %path_idx.addr
  call void @march_decrc(ptr %ld118)
  %sl119 = call ptr @march_string_lit(ptr @.str13, i64 1)
  store ptr %sl119, ptr %res_slot100
  br label %case_merge29
case_default30:
  unreachable
case_merge29:
  %case_r120 = load ptr, ptr %res_slot100
  %path_and_query.addr = alloca ptr
  store ptr %case_r120, ptr %path_and_query.addr
  %ld121 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld121)
  %ld122 = load ptr, ptr %path_and_query.addr
  %sl123 = call ptr @march_string_lit(ptr @.str14, i64 1)
  %cr124 = call ptr @march_string_index_of(ptr %ld122, ptr %sl123)
  %query_idx.addr = alloca ptr
  store ptr %cr124, ptr %query_idx.addr
  %ld125 = load ptr, ptr %query_idx.addr
  %res_slot126 = alloca ptr
  %tgp127 = getelementptr i8, ptr %ld125, i64 8
  %tag128 = load i32, ptr %tgp127, align 4
  switch i32 %tag128, label %case_default34 [
      i32 1, label %case_br35
      i32 0, label %case_br36
  ]
case_br35:
  %fp129 = getelementptr i8, ptr %ld125, i64 16
  %fv130 = load ptr, ptr %fp129, align 8
  %$f702.addr = alloca ptr
  store ptr %fv130, ptr %$f702.addr
  %ld131 = load ptr, ptr %$f702.addr
  %i_2.addr = alloca ptr
  store ptr %ld131, ptr %i_2.addr
  %ld132 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld132)
  %ld133 = load ptr, ptr %path_and_query.addr
  %ld134 = load ptr, ptr %i_2.addr
  %cr135 = call ptr @march_string_slice(ptr %ld133, i64 0, ptr %ld134)
  store ptr %cr135, ptr %res_slot126
  br label %case_merge33
case_br36:
  %ld136 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld136)
  %ld137 = load ptr, ptr %path_and_query.addr
  store ptr %ld137, ptr %res_slot126
  br label %case_merge33
case_default34:
  unreachable
case_merge33:
  %case_r138 = load ptr, ptr %res_slot126
  %url_path.addr = alloca ptr
  store ptr %case_r138, ptr %url_path.addr
  %ld139 = load ptr, ptr %query_idx.addr
  %res_slot140 = alloca ptr
  %tgp141 = getelementptr i8, ptr %ld139, i64 8
  %tag142 = load i32, ptr %tgp141, align 4
  switch i32 %tag142, label %case_default38 [
      i32 1, label %case_br39
      i32 0, label %case_br40
  ]
case_br39:
  %fp143 = getelementptr i8, ptr %ld139, i64 16
  %fv144 = load ptr, ptr %fp143, align 8
  %$f708.addr = alloca ptr
  store ptr %fv144, ptr %$f708.addr
  %ld145 = load ptr, ptr %$f708.addr
  %i_3.addr = alloca ptr
  store ptr %ld145, ptr %i_3.addr
  %ld146 = load ptr, ptr %i_3.addr
  %cv147 = ptrtoint ptr %ld146 to i64
  %ar148 = add i64 %cv147, 1
  %$t703.addr = alloca i64
  store i64 %ar148, ptr %$t703.addr
  %ld149 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld149)
  %ld150 = load ptr, ptr %path_and_query.addr
  %cr151 = call i64 @march_string_byte_length(ptr %ld150)
  %$t704.addr = alloca i64
  store i64 %cr151, ptr %$t704.addr
  %ld152 = load i64, ptr %$t704.addr
  %ld153 = load ptr, ptr %i_3.addr
  %cv154 = ptrtoint ptr %ld153 to i64
  %ar155 = sub i64 %ld152, %cv154
  %$t705.addr = alloca i64
  store i64 %ar155, ptr %$t705.addr
  %ld156 = load i64, ptr %$t705.addr
  %ar157 = sub i64 %ld156, 1
  %$t706.addr = alloca i64
  store i64 %ar157, ptr %$t706.addr
  %ld158 = load ptr, ptr %path_and_query.addr
  %ld159 = load i64, ptr %$t703.addr
  %ld160 = load i64, ptr %$t706.addr
  %cr161 = call ptr @march_string_slice(ptr %ld158, i64 %ld159, i64 %ld160)
  %$t707.addr = alloca ptr
  store ptr %cr161, ptr %$t707.addr
  %ld162 = load ptr, ptr %query_idx.addr
  %ld163 = load ptr, ptr %$t707.addr
  %rc164 = load i64, ptr %ld162, align 8
  %uniq165 = icmp eq i64 %rc164, 1
  %fbip_slot166 = alloca ptr
  br i1 %uniq165, label %fbip_reuse41, label %fbip_fresh42
fbip_reuse41:
  %tgp167 = getelementptr i8, ptr %ld162, i64 8
  store i32 1, ptr %tgp167, align 4
  %fp168 = getelementptr i8, ptr %ld162, i64 16
  store ptr %ld163, ptr %fp168, align 8
  store ptr %ld162, ptr %fbip_slot166
  br label %fbip_merge43
fbip_fresh42:
  call void @march_decrc(ptr %ld162)
  %hp169 = call ptr @march_alloc(i64 24)
  %tgp170 = getelementptr i8, ptr %hp169, i64 8
  store i32 1, ptr %tgp170, align 4
  %fp171 = getelementptr i8, ptr %hp169, i64 16
  store ptr %ld163, ptr %fp171, align 8
  store ptr %hp169, ptr %fbip_slot166
  br label %fbip_merge43
fbip_merge43:
  %fbip_r172 = load ptr, ptr %fbip_slot166
  store ptr %fbip_r172, ptr %res_slot140
  br label %case_merge37
case_br40:
  %ld173 = load ptr, ptr %query_idx.addr
  %rc174 = load i64, ptr %ld173, align 8
  %uniq175 = icmp eq i64 %rc174, 1
  %fbip_slot176 = alloca ptr
  br i1 %uniq175, label %fbip_reuse44, label %fbip_fresh45
fbip_reuse44:
  %tgp177 = getelementptr i8, ptr %ld173, i64 8
  store i32 0, ptr %tgp177, align 4
  store ptr %ld173, ptr %fbip_slot176
  br label %fbip_merge46
fbip_fresh45:
  call void @march_decrc(ptr %ld173)
  %hp178 = call ptr @march_alloc(i64 16)
  %tgp179 = getelementptr i8, ptr %hp178, i64 8
  store i32 0, ptr %tgp179, align 4
  store ptr %hp178, ptr %fbip_slot176
  br label %fbip_merge46
fbip_merge46:
  %fbip_r180 = load ptr, ptr %fbip_slot176
  store ptr %fbip_r180, ptr %res_slot140
  br label %case_merge37
case_default38:
  unreachable
case_merge37:
  %case_r181 = load ptr, ptr %res_slot140
  %url_query.addr = alloca ptr
  store ptr %case_r181, ptr %url_query.addr
  %ld182 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld182)
  %ld183 = load ptr, ptr %host_part.addr
  %sl184 = call ptr @march_string_lit(ptr @.str15, i64 1)
  %cr185 = call ptr @march_string_index_of(ptr %ld183, ptr %sl184)
  %port_idx.addr = alloca ptr
  store ptr %cr185, ptr %port_idx.addr
  %ld186 = load ptr, ptr %port_idx.addr
  %res_slot187 = alloca ptr
  %tgp188 = getelementptr i8, ptr %ld186, i64 8
  %tag189 = load i32, ptr %tgp188, align 4
  switch i32 %tag189, label %case_default48 [
      i32 1, label %case_br49
      i32 0, label %case_br50
  ]
case_br49:
  %fp190 = getelementptr i8, ptr %ld186, i64 16
  %fv191 = load ptr, ptr %fp190, align 8
  %$f709.addr = alloca ptr
  store ptr %fv191, ptr %$f709.addr
  %ld192 = load ptr, ptr %$f709.addr
  %i_4.addr = alloca ptr
  store ptr %ld192, ptr %i_4.addr
  %ld193 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld193)
  %ld194 = load ptr, ptr %host_part.addr
  %ld195 = load ptr, ptr %i_4.addr
  %cr196 = call ptr @march_string_slice(ptr %ld194, i64 0, ptr %ld195)
  store ptr %cr196, ptr %res_slot187
  br label %case_merge47
case_br50:
  %ld197 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld197)
  %ld198 = load ptr, ptr %host_part.addr
  store ptr %ld198, ptr %res_slot187
  br label %case_merge47
case_default48:
  unreachable
case_merge47:
  %case_r199 = load ptr, ptr %res_slot187
  %url_host.addr = alloca ptr
  store ptr %case_r199, ptr %url_host.addr
  %ld200 = load ptr, ptr %port_idx.addr
  %res_slot201 = alloca ptr
  %tgp202 = getelementptr i8, ptr %ld200, i64 8
  %tag203 = load i32, ptr %tgp202, align 4
  switch i32 %tag203, label %case_default52 [
      i32 1, label %case_br53
      i32 0, label %case_br54
  ]
case_br53:
  %fp204 = getelementptr i8, ptr %ld200, i64 16
  %fv205 = load ptr, ptr %fp204, align 8
  %$f717.addr = alloca ptr
  store ptr %fv205, ptr %$f717.addr
  %ld206 = load ptr, ptr %port_idx.addr
  call void @march_decrc(ptr %ld206)
  %ld207 = load ptr, ptr %$f717.addr
  %i_5.addr = alloca ptr
  store ptr %ld207, ptr %i_5.addr
  %ld208 = load ptr, ptr %i_5.addr
  %cv209 = ptrtoint ptr %ld208 to i64
  %ar210 = add i64 %cv209, 1
  %$t710.addr = alloca i64
  store i64 %ar210, ptr %$t710.addr
  %ld211 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld211)
  %ld212 = load ptr, ptr %host_part.addr
  %cr213 = call i64 @march_string_byte_length(ptr %ld212)
  %$t711.addr = alloca i64
  store i64 %cr213, ptr %$t711.addr
  %ld214 = load i64, ptr %$t711.addr
  %ld215 = load ptr, ptr %i_5.addr
  %cv216 = ptrtoint ptr %ld215 to i64
  %ar217 = sub i64 %ld214, %cv216
  %$t712.addr = alloca i64
  store i64 %ar217, ptr %$t712.addr
  %ld218 = load i64, ptr %$t712.addr
  %ar219 = sub i64 %ld218, 1
  %$t713.addr = alloca i64
  store i64 %ar219, ptr %$t713.addr
  %ld220 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld220)
  %ld221 = load ptr, ptr %host_part.addr
  %ld222 = load i64, ptr %$t710.addr
  %ld223 = load i64, ptr %$t713.addr
  %cr224 = call ptr @march_string_slice(ptr %ld221, i64 %ld222, i64 %ld223)
  %port_str.addr = alloca ptr
  store ptr %cr224, ptr %port_str.addr
  %ld225 = load ptr, ptr %port_str.addr
  %cr226 = call ptr @march_string_to_int(ptr %ld225)
  %$t714.addr = alloca ptr
  store ptr %cr226, ptr %$t714.addr
  %ld227 = load ptr, ptr %$t714.addr
  %res_slot228 = alloca ptr
  %tgp229 = getelementptr i8, ptr %ld227, i64 8
  %tag230 = load i32, ptr %tgp229, align 4
  switch i32 %tag230, label %case_default56 [
      i32 1, label %case_br57
      i32 0, label %case_br58
  ]
case_br57:
  %fp231 = getelementptr i8, ptr %ld227, i64 16
  %fv232 = load ptr, ptr %fp231, align 8
  %$f716.addr = alloca ptr
  store ptr %fv232, ptr %$f716.addr
  %ld233 = load ptr, ptr %$f716.addr
  %p.addr = alloca ptr
  store ptr %ld233, ptr %p.addr
  %ld234 = load ptr, ptr %$t714.addr
  %ld235 = load ptr, ptr %p.addr
  %rc236 = load i64, ptr %ld234, align 8
  %uniq237 = icmp eq i64 %rc236, 1
  %fbip_slot238 = alloca ptr
  br i1 %uniq237, label %fbip_reuse59, label %fbip_fresh60
fbip_reuse59:
  %tgp239 = getelementptr i8, ptr %ld234, i64 8
  store i32 1, ptr %tgp239, align 4
  %fp240 = getelementptr i8, ptr %ld234, i64 16
  store ptr %ld235, ptr %fp240, align 8
  store ptr %ld234, ptr %fbip_slot238
  br label %fbip_merge61
fbip_fresh60:
  call void @march_decrc(ptr %ld234)
  %hp241 = call ptr @march_alloc(i64 24)
  %tgp242 = getelementptr i8, ptr %hp241, i64 8
  store i32 1, ptr %tgp242, align 4
  %fp243 = getelementptr i8, ptr %hp241, i64 16
  store ptr %ld235, ptr %fp243, align 8
  store ptr %hp241, ptr %fbip_slot238
  br label %fbip_merge61
fbip_merge61:
  %fbip_r244 = load ptr, ptr %fbip_slot238
  store ptr %fbip_r244, ptr %res_slot228
  br label %case_merge55
case_br58:
  %ld245 = load ptr, ptr %$t714.addr
  call void @march_decrc(ptr %ld245)
  %ar246 = sub i64 0, 1
  %$t715.addr = alloca i64
  store i64 %ar246, ptr %$t715.addr
  %hp247 = call ptr @march_alloc(i64 24)
  %tgp248 = getelementptr i8, ptr %hp247, i64 8
  store i32 1, ptr %tgp248, align 4
  %ld249 = load i64, ptr %$t715.addr
  %cv250 = inttoptr i64 %ld249 to ptr
  %fp251 = getelementptr i8, ptr %hp247, i64 16
  store ptr %cv250, ptr %fp251, align 8
  store ptr %hp247, ptr %res_slot228
  br label %case_merge55
case_default56:
  unreachable
case_merge55:
  %case_r252 = load ptr, ptr %res_slot228
  store ptr %case_r252, ptr %res_slot201
  br label %case_merge51
case_br54:
  %ld253 = load ptr, ptr %port_idx.addr
  %rc254 = load i64, ptr %ld253, align 8
  %uniq255 = icmp eq i64 %rc254, 1
  %fbip_slot256 = alloca ptr
  br i1 %uniq255, label %fbip_reuse62, label %fbip_fresh63
fbip_reuse62:
  %tgp257 = getelementptr i8, ptr %ld253, i64 8
  store i32 0, ptr %tgp257, align 4
  store ptr %ld253, ptr %fbip_slot256
  br label %fbip_merge64
fbip_fresh63:
  call void @march_decrc(ptr %ld253)
  %hp258 = call ptr @march_alloc(i64 16)
  %tgp259 = getelementptr i8, ptr %hp258, i64 8
  store i32 0, ptr %tgp259, align 4
  store ptr %hp258, ptr %fbip_slot256
  br label %fbip_merge64
fbip_merge64:
  %fbip_r260 = load ptr, ptr %fbip_slot256
  store ptr %fbip_r260, ptr %res_slot201
  br label %case_merge51
case_default52:
  unreachable
case_merge51:
  %case_r261 = load ptr, ptr %res_slot201
  %url_port.addr = alloca ptr
  store ptr %case_r261, ptr %url_port.addr
  %ld262 = load ptr, ptr %url_host.addr
  call void @march_incrc(ptr %ld262)
  %ld263 = load ptr, ptr %url_host.addr
  %cr264 = call i64 @march_string_is_empty(ptr %ld263)
  %$t718.addr = alloca i64
  store i64 %cr264, ptr %$t718.addr
  %ld265 = load i64, ptr %$t718.addr
  %res_slot266 = alloca ptr
  %bi267 = trunc i64 %ld265 to i1
  br i1 %bi267, label %case_br67, label %case_default66
case_br67:
  %hp268 = call ptr @march_alloc(i64 16)
  %tgp269 = getelementptr i8, ptr %hp268, i64 8
  store i32 1, ptr %tgp269, align 4
  %$t719.addr = alloca ptr
  store ptr %hp268, ptr %$t719.addr
  %hp270 = call ptr @march_alloc(i64 24)
  %tgp271 = getelementptr i8, ptr %hp270, i64 8
  store i32 1, ptr %tgp271, align 4
  %ld272 = load ptr, ptr %$t719.addr
  %fp273 = getelementptr i8, ptr %hp270, i64 16
  store ptr %ld272, ptr %fp273, align 8
  store ptr %hp270, ptr %res_slot266
  br label %case_merge65
case_default66:
  %ld274 = load ptr, ptr %url_port.addr
  %res_slot275 = alloca ptr
  %tgp276 = getelementptr i8, ptr %ld274, i64 8
  %tag277 = load i32, ptr %tgp276, align 4
  switch i32 %tag277, label %case_default69 [
      i32 1, label %case_br70
  ]
case_br70:
  %fp278 = getelementptr i8, ptr %ld274, i64 16
  %fv279 = load ptr, ptr %fp278, align 8
  %$f725.addr = alloca ptr
  store ptr %fv279, ptr %$f725.addr
  %ld280 = load ptr, ptr %$f725.addr
  %res_slot281 = alloca ptr
  %tgp282 = getelementptr i8, ptr %ld280, i64 8
  %tag283 = load i32, ptr %tgp282, align 4
  switch i32 %tag283, label %case_default72 [
      i32 0, label %case_br73
  ]
case_br73:
  %ld284 = load ptr, ptr %$f725.addr
  call void @march_decrc(ptr %ld284)
  %hp285 = call ptr @march_alloc(i64 24)
  %tgp286 = getelementptr i8, ptr %hp285, i64 8
  store i32 2, ptr %tgp286, align 4
  %ld287 = load ptr, ptr %host_part.addr
  %fp288 = getelementptr i8, ptr %hp285, i64 16
  store ptr %ld287, ptr %fp288, align 8
  %$t720.addr = alloca ptr
  store ptr %hp285, ptr %$t720.addr
  %hp289 = call ptr @march_alloc(i64 24)
  %tgp290 = getelementptr i8, ptr %hp289, i64 8
  store i32 1, ptr %tgp290, align 4
  %ld291 = load ptr, ptr %$t720.addr
  %fp292 = getelementptr i8, ptr %hp289, i64 16
  store ptr %ld291, ptr %fp292, align 8
  store ptr %hp289, ptr %res_slot281
  br label %case_merge71
case_default72:
  %ld293 = load ptr, ptr %$f725.addr
  call void @march_decrc(ptr %ld293)
  %hp294 = call ptr @march_alloc(i64 16)
  %tgp295 = getelementptr i8, ptr %hp294, i64 8
  store i32 0, ptr %tgp295, align 4
  %$t721.addr = alloca ptr
  store ptr %hp294, ptr %$t721.addr
  %hp296 = call ptr @march_alloc(i64 16)
  %tgp297 = getelementptr i8, ptr %hp296, i64 8
  store i32 0, ptr %tgp297, align 4
  %$t722.addr = alloca ptr
  store ptr %hp296, ptr %$t722.addr
  %cv298 = inttoptr i64 0 to ptr
  %$t723.addr = alloca ptr
  store ptr %cv298, ptr %$t723.addr
  %hp299 = call ptr @march_alloc(i64 80)
  %tgp300 = getelementptr i8, ptr %hp299, i64 8
  store i32 0, ptr %tgp300, align 4
  %ld301 = load ptr, ptr %$t721.addr
  %fp302 = getelementptr i8, ptr %hp299, i64 16
  store ptr %ld301, ptr %fp302, align 8
  %ld303 = load ptr, ptr %url_scheme.addr
  %fp304 = getelementptr i8, ptr %hp299, i64 24
  store ptr %ld303, ptr %fp304, align 8
  %ld305 = load ptr, ptr %url_host.addr
  %fp306 = getelementptr i8, ptr %hp299, i64 32
  store ptr %ld305, ptr %fp306, align 8
  %ld307 = load ptr, ptr %url_port.addr
  %fp308 = getelementptr i8, ptr %hp299, i64 40
  store ptr %ld307, ptr %fp308, align 8
  %ld309 = load ptr, ptr %url_path.addr
  %fp310 = getelementptr i8, ptr %hp299, i64 48
  store ptr %ld309, ptr %fp310, align 8
  %ld311 = load ptr, ptr %url_query.addr
  %fp312 = getelementptr i8, ptr %hp299, i64 56
  store ptr %ld311, ptr %fp312, align 8
  %ld313 = load ptr, ptr %$t722.addr
  %fp314 = getelementptr i8, ptr %hp299, i64 64
  store ptr %ld313, ptr %fp314, align 8
  %ld315 = load ptr, ptr %$t723.addr
  %fp316 = getelementptr i8, ptr %hp299, i64 72
  store ptr %ld315, ptr %fp316, align 8
  %$t724.addr = alloca ptr
  store ptr %hp299, ptr %$t724.addr
  %hp317 = call ptr @march_alloc(i64 24)
  %tgp318 = getelementptr i8, ptr %hp317, i64 8
  store i32 0, ptr %tgp318, align 4
  %ld319 = load ptr, ptr %$t724.addr
  %fp320 = getelementptr i8, ptr %hp317, i64 16
  store ptr %ld319, ptr %fp320, align 8
  store ptr %hp317, ptr %res_slot281
  br label %case_merge71
case_merge71:
  %case_r321 = load ptr, ptr %res_slot281
  store ptr %case_r321, ptr %res_slot275
  br label %case_merge68
case_default69:
  %hp322 = call ptr @march_alloc(i64 16)
  %tgp323 = getelementptr i8, ptr %hp322, i64 8
  store i32 0, ptr %tgp323, align 4
  %$t721_1.addr = alloca ptr
  store ptr %hp322, ptr %$t721_1.addr
  %hp324 = call ptr @march_alloc(i64 16)
  %tgp325 = getelementptr i8, ptr %hp324, i64 8
  store i32 0, ptr %tgp325, align 4
  %$t722_1.addr = alloca ptr
  store ptr %hp324, ptr %$t722_1.addr
  %cv326 = inttoptr i64 0 to ptr
  %$t723_1.addr = alloca ptr
  store ptr %cv326, ptr %$t723_1.addr
  %hp327 = call ptr @march_alloc(i64 80)
  %tgp328 = getelementptr i8, ptr %hp327, i64 8
  store i32 0, ptr %tgp328, align 4
  %ld329 = load ptr, ptr %$t721_1.addr
  %fp330 = getelementptr i8, ptr %hp327, i64 16
  store ptr %ld329, ptr %fp330, align 8
  %ld331 = load ptr, ptr %url_scheme.addr
  %fp332 = getelementptr i8, ptr %hp327, i64 24
  store ptr %ld331, ptr %fp332, align 8
  %ld333 = load ptr, ptr %url_host.addr
  %fp334 = getelementptr i8, ptr %hp327, i64 32
  store ptr %ld333, ptr %fp334, align 8
  %ld335 = load ptr, ptr %url_port.addr
  %fp336 = getelementptr i8, ptr %hp327, i64 40
  store ptr %ld335, ptr %fp336, align 8
  %ld337 = load ptr, ptr %url_path.addr
  %fp338 = getelementptr i8, ptr %hp327, i64 48
  store ptr %ld337, ptr %fp338, align 8
  %ld339 = load ptr, ptr %url_query.addr
  %fp340 = getelementptr i8, ptr %hp327, i64 56
  store ptr %ld339, ptr %fp340, align 8
  %ld341 = load ptr, ptr %$t722_1.addr
  %fp342 = getelementptr i8, ptr %hp327, i64 64
  store ptr %ld341, ptr %fp342, align 8
  %ld343 = load ptr, ptr %$t723_1.addr
  %fp344 = getelementptr i8, ptr %hp327, i64 72
  store ptr %ld343, ptr %fp344, align 8
  %$t724_1.addr = alloca ptr
  store ptr %hp327, ptr %$t724_1.addr
  %hp345 = call ptr @march_alloc(i64 24)
  %tgp346 = getelementptr i8, ptr %hp345, i64 8
  store i32 0, ptr %tgp346, align 4
  %ld347 = load ptr, ptr %$t724_1.addr
  %fp348 = getelementptr i8, ptr %hp345, i64 16
  store ptr %ld347, ptr %fp348, align 8
  store ptr %hp345, ptr %res_slot275
  br label %case_merge68
case_merge68:
  %case_r349 = load ptr, ptr %res_slot275
  store ptr %case_r349, ptr %res_slot266
  br label %case_merge65
case_merge65:
  %case_r350 = load ptr, ptr %res_slot266
  store ptr %case_r350, ptr %res_slot46
  br label %case_merge16
case_merge16:
  %case_r351 = load ptr, ptr %res_slot46
  ret ptr %case_r351
}

define ptr @march_main() {
entry:
  %hp352 = call ptr @march_alloc(i64 16)
  %tgp353 = getelementptr i8, ptr %hp352, i64 8
  store i32 0, ptr %tgp353, align 4
  %$t880_i23.addr = alloca ptr
  store ptr %hp352, ptr %$t880_i23.addr
  %hp354 = call ptr @march_alloc(i64 16)
  %tgp355 = getelementptr i8, ptr %hp354, i64 8
  store i32 0, ptr %tgp355, align 4
  %$t881_i24.addr = alloca ptr
  store ptr %hp354, ptr %$t881_i24.addr
  %hp356 = call ptr @march_alloc(i64 16)
  %tgp357 = getelementptr i8, ptr %hp356, i64 8
  store i32 0, ptr %tgp357, align 4
  %$t882_i25.addr = alloca ptr
  store ptr %hp356, ptr %$t882_i25.addr
  %hp358 = call ptr @march_alloc(i64 64)
  %tgp359 = getelementptr i8, ptr %hp358, i64 8
  store i32 0, ptr %tgp359, align 4
  %ld360 = load ptr, ptr %$t880_i23.addr
  %fp361 = getelementptr i8, ptr %hp358, i64 16
  store ptr %ld360, ptr %fp361, align 8
  %ld362 = load ptr, ptr %$t881_i24.addr
  %fp363 = getelementptr i8, ptr %hp358, i64 24
  store ptr %ld362, ptr %fp363, align 8
  %ld364 = load ptr, ptr %$t882_i25.addr
  %fp365 = getelementptr i8, ptr %hp358, i64 32
  store ptr %ld364, ptr %fp365, align 8
  %fp366 = getelementptr i8, ptr %hp358, i64 40
  store i64 0, ptr %fp366, align 8
  %fp367 = getelementptr i8, ptr %hp358, i64 48
  store i64 0, ptr %fp367, align 8
  %fp368 = getelementptr i8, ptr %hp358, i64 56
  store i64 0, ptr %fp368, align 8
  %client.addr = alloca ptr
  store ptr %hp358, ptr %client.addr
  %ld369 = load ptr, ptr %client.addr
  %sl370 = call ptr @march_string_lit(ptr @.str16, i64 8)
  %cwrap371 = call ptr @march_alloc(i64 24)
  %cwt372 = getelementptr i8, ptr %cwrap371, i64 8
  store i32 0, ptr %cwt372, align 4
  %cwf373 = getelementptr i8, ptr %cwrap371, i64 16
  store ptr @HttpClient.step_default_headers$clo_wrap, ptr %cwf373, align 8
  %cr374 = call ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__6076_Result_Request_V__6075_V__6074(ptr %ld369, ptr %sl370, ptr %cwrap371)
  %client_1.addr = alloca ptr
  store ptr %cr374, ptr %client_1.addr
  %sl375 = call ptr @march_string_lit(ptr @.str17, i64 46)
  call void @march_print(ptr %sl375)
  %sl376 = call ptr @march_string_lit(ptr @.str18, i64 3)
  call void @march_print(ptr %sl376)
  %hp377 = call ptr @march_alloc(i64 24)
  %tgp378 = getelementptr i8, ptr %hp377, i64 8
  store i32 0, ptr %tgp378, align 4
  %fp379 = getelementptr i8, ptr %hp377, i64 16
  store ptr @on_chunk$apply$22, ptr %fp379, align 8
  %on_chunk.addr = alloca ptr
  store ptr %hp377, ptr %on_chunk.addr
  %ld380 = load ptr, ptr %client_1.addr
  %sl381 = call ptr @march_string_lit(ptr @.str19, i64 22)
  %ld382 = load ptr, ptr %on_chunk.addr
  %cr383 = call ptr @HttpClient.stream_get(ptr %ld380, ptr %sl381, ptr %ld382)
  %$t2013.addr = alloca ptr
  store ptr %cr383, ptr %$t2013.addr
  %ld384 = load ptr, ptr %$t2013.addr
  %res_slot385 = alloca ptr
  %tgp386 = getelementptr i8, ptr %ld384, i64 8
  %tag387 = load i32, ptr %tgp386, align 4
  switch i32 %tag387, label %case_default75 [
      i32 0, label %case_br76
      i32 1, label %case_br77
  ]
case_br76:
  %fp388 = getelementptr i8, ptr %ld384, i64 16
  %fv389 = load ptr, ptr %fp388, align 8
  %$f2016.addr = alloca ptr
  store ptr %fv389, ptr %$f2016.addr
  %freed390 = call i64 @march_decrc_freed(ptr %ld384)
  %freed_b391 = icmp ne i64 %freed390, 0
  br i1 %freed_b391, label %br_unique78, label %br_shared79
br_shared79:
  call void @march_incrc(ptr %fv389)
  br label %br_body80
br_unique78:
  br label %br_body80
br_body80:
  %ld392 = load ptr, ptr %$f2016.addr
  %res_slot393 = alloca ptr
  %tgp394 = getelementptr i8, ptr %ld392, i64 8
  %tag395 = load i32, ptr %tgp394, align 4
  switch i32 %tag395, label %case_default82 [
      i32 0, label %case_br83
  ]
case_br83:
  %fp396 = getelementptr i8, ptr %ld392, i64 16
  %fv397 = load ptr, ptr %fp396, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv397, ptr %$f2017.addr
  %fp398 = getelementptr i8, ptr %ld392, i64 24
  %fv399 = load ptr, ptr %fp398, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv399, ptr %$f2018.addr
  %fp400 = getelementptr i8, ptr %ld392, i64 32
  %fv401 = load ptr, ptr %fp400, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv401, ptr %$f2019.addr
  %freed402 = call i64 @march_decrc_freed(ptr %ld392)
  %freed_b403 = icmp ne i64 %freed402, 0
  br i1 %freed_b403, label %br_unique84, label %br_shared85
br_shared85:
  call void @march_incrc(ptr %fv401)
  call void @march_incrc(ptr %fv399)
  call void @march_incrc(ptr %fv397)
  br label %br_body86
br_unique84:
  br label %br_body86
br_body86:
  %ld404 = load ptr, ptr %$f2018.addr
  %headers.addr = alloca ptr
  store ptr %ld404, ptr %headers.addr
  %ld405 = load ptr, ptr %headers.addr
  call void @march_decrc(ptr %ld405)
  %ld406 = load ptr, ptr %$f2017.addr
  %status.addr = alloca ptr
  store ptr %ld406, ptr %status.addr
  %sl407 = call ptr @march_string_lit(ptr @.str20, i64 3)
  call void @march_print(ptr %sl407)
  %ld408 = load ptr, ptr %status.addr
  %cr409 = call ptr @march_int_to_string(ptr %ld408)
  %$t2014.addr = alloca ptr
  store ptr %cr409, ptr %$t2014.addr
  %sl410 = call ptr @march_string_lit(ptr @.str21, i64 8)
  %ld411 = load ptr, ptr %$t2014.addr
  %cr412 = call ptr @march_string_concat(ptr %sl410, ptr %ld411)
  %$t2015.addr = alloca ptr
  store ptr %cr412, ptr %$t2015.addr
  %ld413 = load ptr, ptr %$t2015.addr
  call void @march_print(ptr %ld413)
  %cv414 = inttoptr i64 0 to ptr
  store ptr %cv414, ptr %res_slot393
  br label %case_merge81
case_default82:
  unreachable
case_merge81:
  %case_r415 = load ptr, ptr %res_slot393
  store ptr %case_r415, ptr %res_slot385
  br label %case_merge74
case_br77:
  %fp416 = getelementptr i8, ptr %ld384, i64 16
  %fv417 = load ptr, ptr %fp416, align 8
  %$f2020.addr = alloca ptr
  store ptr %fv417, ptr %$f2020.addr
  %freed418 = call i64 @march_decrc_freed(ptr %ld384)
  %freed_b419 = icmp ne i64 %freed418, 0
  br i1 %freed_b419, label %br_unique87, label %br_shared88
br_shared88:
  call void @march_incrc(ptr %fv417)
  br label %br_body89
br_unique87:
  br label %br_body89
br_body89:
  %ld420 = load ptr, ptr %$f2020.addr
  %e.addr = alloca ptr
  store ptr %ld420, ptr %e.addr
  %ld421 = load ptr, ptr %e.addr
  call void @march_decrc(ptr %ld421)
  %sl422 = call ptr @march_string_lit(ptr @.str22, i64 6)
  call void @march_print(ptr %sl422)
  %cv423 = inttoptr i64 0 to ptr
  store ptr %cv423, ptr %res_slot385
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r424 = load ptr, ptr %res_slot385
  ret ptr %case_r424
}

define ptr @HttpClient.stream_get(ptr %client.arg, ptr %url.arg, ptr %on_chunk.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %ld425 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld425)
  %ld426 = load ptr, ptr %url.addr
  %url_i26.addr = alloca ptr
  store ptr %ld426, ptr %url_i26.addr
  %ld427 = load ptr, ptr %url_i26.addr
  %cr428 = call ptr @Http.parse_url(ptr %ld427)
  %$t1073.addr = alloca ptr
  store ptr %cr428, ptr %$t1073.addr
  %ld429 = load ptr, ptr %$t1073.addr
  %res_slot430 = alloca ptr
  %tgp431 = getelementptr i8, ptr %ld429, i64 8
  %tag432 = load i32, ptr %tgp431, align 4
  switch i32 %tag432, label %case_default91 [
      i32 1, label %case_br92
      i32 0, label %case_br93
  ]
case_br92:
  %fp433 = getelementptr i8, ptr %ld429, i64 16
  %fv434 = load ptr, ptr %fp433, align 8
  %$f1096.addr = alloca ptr
  store ptr %fv434, ptr %$f1096.addr
  %sl435 = call ptr @march_string_lit(ptr @.str23, i64 13)
  %ld436 = load ptr, ptr %url.addr
  %cr437 = call ptr @march_string_concat(ptr %sl435, ptr %ld436)
  %$t1074.addr = alloca ptr
  store ptr %cr437, ptr %$t1074.addr
  %hp438 = call ptr @march_alloc(i64 32)
  %tgp439 = getelementptr i8, ptr %hp438, i64 8
  store i32 1, ptr %tgp439, align 4
  %sl440 = call ptr @march_string_lit(ptr @.str24, i64 3)
  %fp441 = getelementptr i8, ptr %hp438, i64 16
  store ptr %sl440, ptr %fp441, align 8
  %ld442 = load ptr, ptr %$t1074.addr
  %fp443 = getelementptr i8, ptr %hp438, i64 24
  store ptr %ld442, ptr %fp443, align 8
  %$t1075.addr = alloca ptr
  store ptr %hp438, ptr %$t1075.addr
  %ld444 = load ptr, ptr %$t1073.addr
  %ld445 = load ptr, ptr %$t1075.addr
  %rc446 = load i64, ptr %ld444, align 8
  %uniq447 = icmp eq i64 %rc446, 1
  %fbip_slot448 = alloca ptr
  br i1 %uniq447, label %fbip_reuse94, label %fbip_fresh95
fbip_reuse94:
  %tgp449 = getelementptr i8, ptr %ld444, i64 8
  store i32 1, ptr %tgp449, align 4
  %fp450 = getelementptr i8, ptr %ld444, i64 16
  store ptr %ld445, ptr %fp450, align 8
  store ptr %ld444, ptr %fbip_slot448
  br label %fbip_merge96
fbip_fresh95:
  call void @march_decrc(ptr %ld444)
  %hp451 = call ptr @march_alloc(i64 24)
  %tgp452 = getelementptr i8, ptr %hp451, i64 8
  store i32 1, ptr %tgp452, align 4
  %fp453 = getelementptr i8, ptr %hp451, i64 16
  store ptr %ld445, ptr %fp453, align 8
  store ptr %hp451, ptr %fbip_slot448
  br label %fbip_merge96
fbip_merge96:
  %fbip_r454 = load ptr, ptr %fbip_slot448
  store ptr %fbip_r454, ptr %res_slot430
  br label %case_merge90
case_br93:
  %fp455 = getelementptr i8, ptr %ld429, i64 16
  %fv456 = load ptr, ptr %fp455, align 8
  %$f1097.addr = alloca ptr
  store ptr %fv456, ptr %$f1097.addr
  %freed457 = call i64 @march_decrc_freed(ptr %ld429)
  %freed_b458 = icmp ne i64 %freed457, 0
  br i1 %freed_b458, label %br_unique97, label %br_shared98
br_shared98:
  call void @march_incrc(ptr %fv456)
  br label %br_body99
br_unique97:
  br label %br_body99
br_body99:
  %ld459 = load ptr, ptr %$f1097.addr
  %req.addr = alloca ptr
  store ptr %ld459, ptr %req.addr
  %ld460 = load ptr, ptr %req.addr
  %sl461 = call ptr @march_string_lit(ptr @.str25, i64 0)
  %cr462 = call ptr @Http.set_body$Request_T_$String(ptr %ld460, ptr %sl461)
  %req_1.addr = alloca ptr
  store ptr %cr462, ptr %req_1.addr
  %ld463 = load ptr, ptr %client.addr
  %res_slot464 = alloca ptr
  %tgp465 = getelementptr i8, ptr %ld463, i64 8
  %tag466 = load i32, ptr %tgp465, align 4
  switch i32 %tag466, label %case_default101 [
      i32 0, label %case_br102
  ]
case_br102:
  %fp467 = getelementptr i8, ptr %ld463, i64 16
  %fv468 = load ptr, ptr %fp467, align 8
  %$f1090.addr = alloca ptr
  store ptr %fv468, ptr %$f1090.addr
  %fp469 = getelementptr i8, ptr %ld463, i64 24
  %fv470 = load ptr, ptr %fp469, align 8
  %$f1091.addr = alloca ptr
  store ptr %fv470, ptr %$f1091.addr
  %fp471 = getelementptr i8, ptr %ld463, i64 32
  %fv472 = load ptr, ptr %fp471, align 8
  %$f1092.addr = alloca ptr
  store ptr %fv472, ptr %$f1092.addr
  %fp473 = getelementptr i8, ptr %ld463, i64 40
  %fv474 = load i64, ptr %fp473, align 8
  %$f1093.addr = alloca i64
  store i64 %fv474, ptr %$f1093.addr
  %fp475 = getelementptr i8, ptr %ld463, i64 48
  %fv476 = load i64, ptr %fp475, align 8
  %$f1094.addr = alloca i64
  store i64 %fv476, ptr %$f1094.addr
  %fp477 = getelementptr i8, ptr %ld463, i64 56
  %fv478 = load i64, ptr %fp477, align 8
  %$f1095.addr = alloca i64
  store i64 %fv478, ptr %$f1095.addr
  %freed479 = call i64 @march_decrc_freed(ptr %ld463)
  %freed_b480 = icmp ne i64 %freed479, 0
  br i1 %freed_b480, label %br_unique103, label %br_shared104
br_shared104:
  call void @march_incrc(ptr %fv472)
  call void @march_incrc(ptr %fv470)
  call void @march_incrc(ptr %fv468)
  br label %br_body105
br_unique103:
  br label %br_body105
br_body105:
  %ld481 = load ptr, ptr %$f1090.addr
  %req_steps.addr = alloca ptr
  store ptr %ld481, ptr %req_steps.addr
  %ld482 = load ptr, ptr %req_steps.addr
  %ld483 = load ptr, ptr %req_1.addr
  %cr484 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld482, ptr %ld483)
  %$t1076.addr = alloca ptr
  store ptr %cr484, ptr %$t1076.addr
  %ld485 = load ptr, ptr %$t1076.addr
  %res_slot486 = alloca ptr
  %tgp487 = getelementptr i8, ptr %ld485, i64 8
  %tag488 = load i32, ptr %tgp487, align 4
  switch i32 %tag488, label %case_default107 [
      i32 1, label %case_br108
      i32 0, label %case_br109
  ]
case_br108:
  %fp489 = getelementptr i8, ptr %ld485, i64 16
  %fv490 = load ptr, ptr %fp489, align 8
  %$f1088.addr = alloca ptr
  store ptr %fv490, ptr %$f1088.addr
  %ld491 = load ptr, ptr %$f1088.addr
  %e.addr = alloca ptr
  store ptr %ld491, ptr %e.addr
  %ld492 = load ptr, ptr %$t1076.addr
  %ld493 = load ptr, ptr %e.addr
  %rc494 = load i64, ptr %ld492, align 8
  %uniq495 = icmp eq i64 %rc494, 1
  %fbip_slot496 = alloca ptr
  br i1 %uniq495, label %fbip_reuse110, label %fbip_fresh111
fbip_reuse110:
  %tgp497 = getelementptr i8, ptr %ld492, i64 8
  store i32 1, ptr %tgp497, align 4
  %fp498 = getelementptr i8, ptr %ld492, i64 16
  store ptr %ld493, ptr %fp498, align 8
  store ptr %ld492, ptr %fbip_slot496
  br label %fbip_merge112
fbip_fresh111:
  call void @march_decrc(ptr %ld492)
  %hp499 = call ptr @march_alloc(i64 24)
  %tgp500 = getelementptr i8, ptr %hp499, i64 8
  store i32 1, ptr %tgp500, align 4
  %fp501 = getelementptr i8, ptr %hp499, i64 16
  store ptr %ld493, ptr %fp501, align 8
  store ptr %hp499, ptr %fbip_slot496
  br label %fbip_merge112
fbip_merge112:
  %fbip_r502 = load ptr, ptr %fbip_slot496
  store ptr %fbip_r502, ptr %res_slot486
  br label %case_merge106
case_br109:
  %fp503 = getelementptr i8, ptr %ld485, i64 16
  %fv504 = load ptr, ptr %fp503, align 8
  %$f1089.addr = alloca ptr
  store ptr %fv504, ptr %$f1089.addr
  %freed505 = call i64 @march_decrc_freed(ptr %ld485)
  %freed_b506 = icmp ne i64 %freed505, 0
  br i1 %freed_b506, label %br_unique113, label %br_shared114
br_shared114:
  call void @march_incrc(ptr %fv504)
  br label %br_body115
br_unique113:
  br label %br_body115
br_body115:
  %ld507 = load ptr, ptr %$f1089.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld507, ptr %transformed_req.addr
  %ld508 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld508)
  %ld509 = load ptr, ptr %transformed_req.addr
  %cr510 = call ptr @HttpTransport.connect$Request_String(ptr %ld509)
  %$t1077.addr = alloca ptr
  store ptr %cr510, ptr %$t1077.addr
  %ld511 = load ptr, ptr %$t1077.addr
  %res_slot512 = alloca ptr
  %tgp513 = getelementptr i8, ptr %ld511, i64 8
  %tag514 = load i32, ptr %tgp513, align 4
  switch i32 %tag514, label %case_default117 [
      i32 1, label %case_br118
      i32 0, label %case_br119
  ]
case_br118:
  %fp515 = getelementptr i8, ptr %ld511, i64 16
  %fv516 = load ptr, ptr %fp515, align 8
  %$f1086.addr = alloca ptr
  store ptr %fv516, ptr %$f1086.addr
  %ld517 = load ptr, ptr %$f1086.addr
  %e_1.addr = alloca ptr
  store ptr %ld517, ptr %e_1.addr
  %hp518 = call ptr @march_alloc(i64 24)
  %tgp519 = getelementptr i8, ptr %hp518, i64 8
  store i32 0, ptr %tgp519, align 4
  %ld520 = load ptr, ptr %e_1.addr
  %fp521 = getelementptr i8, ptr %hp518, i64 16
  store ptr %ld520, ptr %fp521, align 8
  %$t1078.addr = alloca ptr
  store ptr %hp518, ptr %$t1078.addr
  %ld522 = load ptr, ptr %$t1077.addr
  %ld523 = load ptr, ptr %$t1078.addr
  %rc524 = load i64, ptr %ld522, align 8
  %uniq525 = icmp eq i64 %rc524, 1
  %fbip_slot526 = alloca ptr
  br i1 %uniq525, label %fbip_reuse120, label %fbip_fresh121
fbip_reuse120:
  %tgp527 = getelementptr i8, ptr %ld522, i64 8
  store i32 1, ptr %tgp527, align 4
  %fp528 = getelementptr i8, ptr %ld522, i64 16
  store ptr %ld523, ptr %fp528, align 8
  store ptr %ld522, ptr %fbip_slot526
  br label %fbip_merge122
fbip_fresh121:
  call void @march_decrc(ptr %ld522)
  %hp529 = call ptr @march_alloc(i64 24)
  %tgp530 = getelementptr i8, ptr %hp529, i64 8
  store i32 1, ptr %tgp530, align 4
  %fp531 = getelementptr i8, ptr %hp529, i64 16
  store ptr %ld523, ptr %fp531, align 8
  store ptr %hp529, ptr %fbip_slot526
  br label %fbip_merge122
fbip_merge122:
  %fbip_r532 = load ptr, ptr %fbip_slot526
  store ptr %fbip_r532, ptr %res_slot512
  br label %case_merge116
case_br119:
  %fp533 = getelementptr i8, ptr %ld511, i64 16
  %fv534 = load ptr, ptr %fp533, align 8
  %$f1087.addr = alloca ptr
  store ptr %fv534, ptr %$f1087.addr
  %freed535 = call i64 @march_decrc_freed(ptr %ld511)
  %freed_b536 = icmp ne i64 %freed535, 0
  br i1 %freed_b536, label %br_unique123, label %br_shared124
br_shared124:
  call void @march_incrc(ptr %fv534)
  br label %br_body125
br_unique123:
  br label %br_body125
br_body125:
  %ld537 = load ptr, ptr %$f1087.addr
  %fd.addr = alloca ptr
  store ptr %ld537, ptr %fd.addr
  %ld538 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld538)
  %ld539 = load ptr, ptr %fd.addr
  %ld540 = load ptr, ptr %transformed_req.addr
  %ld541 = load ptr, ptr %on_chunk.addr
  %cr542 = call ptr @HttpTransport.stream_request_on$V__2823$Request_String$Fn_String_T_(ptr %ld539, ptr %ld540, ptr %ld541)
  %result.addr = alloca ptr
  store ptr %cr542, ptr %result.addr
  %ld543 = load ptr, ptr %fd.addr
  %cr544 = call ptr @march_tcp_close(ptr %ld543)
  %ld545 = load ptr, ptr %result.addr
  %res_slot546 = alloca ptr
  %tgp547 = getelementptr i8, ptr %ld545, i64 8
  %tag548 = load i32, ptr %tgp547, align 4
  switch i32 %tag548, label %case_default127 [
      i32 1, label %case_br128
      i32 0, label %case_br129
  ]
case_br128:
  %fp549 = getelementptr i8, ptr %ld545, i64 16
  %fv550 = load ptr, ptr %fp549, align 8
  %$f1081.addr = alloca ptr
  store ptr %fv550, ptr %$f1081.addr
  %ld551 = load ptr, ptr %$f1081.addr
  %e_2.addr = alloca ptr
  store ptr %ld551, ptr %e_2.addr
  %hp552 = call ptr @march_alloc(i64 24)
  %tgp553 = getelementptr i8, ptr %hp552, i64 8
  store i32 0, ptr %tgp553, align 4
  %ld554 = load ptr, ptr %e_2.addr
  %fp555 = getelementptr i8, ptr %hp552, i64 16
  store ptr %ld554, ptr %fp555, align 8
  %$t1079.addr = alloca ptr
  store ptr %hp552, ptr %$t1079.addr
  %ld556 = load ptr, ptr %result.addr
  %ld557 = load ptr, ptr %$t1079.addr
  %rc558 = load i64, ptr %ld556, align 8
  %uniq559 = icmp eq i64 %rc558, 1
  %fbip_slot560 = alloca ptr
  br i1 %uniq559, label %fbip_reuse130, label %fbip_fresh131
fbip_reuse130:
  %tgp561 = getelementptr i8, ptr %ld556, i64 8
  store i32 1, ptr %tgp561, align 4
  %fp562 = getelementptr i8, ptr %ld556, i64 16
  store ptr %ld557, ptr %fp562, align 8
  store ptr %ld556, ptr %fbip_slot560
  br label %fbip_merge132
fbip_fresh131:
  call void @march_decrc(ptr %ld556)
  %hp563 = call ptr @march_alloc(i64 24)
  %tgp564 = getelementptr i8, ptr %hp563, i64 8
  store i32 1, ptr %tgp564, align 4
  %fp565 = getelementptr i8, ptr %hp563, i64 16
  store ptr %ld557, ptr %fp565, align 8
  store ptr %hp563, ptr %fbip_slot560
  br label %fbip_merge132
fbip_merge132:
  %fbip_r566 = load ptr, ptr %fbip_slot560
  store ptr %fbip_r566, ptr %res_slot546
  br label %case_merge126
case_br129:
  %fp567 = getelementptr i8, ptr %ld545, i64 16
  %fv568 = load ptr, ptr %fp567, align 8
  %$f1082.addr = alloca ptr
  store ptr %fv568, ptr %$f1082.addr
  %freed569 = call i64 @march_decrc_freed(ptr %ld545)
  %freed_b570 = icmp ne i64 %freed569, 0
  br i1 %freed_b570, label %br_unique133, label %br_shared134
br_shared134:
  call void @march_incrc(ptr %fv568)
  br label %br_body135
br_unique133:
  br label %br_body135
br_body135:
  %ld571 = load ptr, ptr %$f1082.addr
  %res_slot572 = alloca ptr
  %tgp573 = getelementptr i8, ptr %ld571, i64 8
  %tag574 = load i32, ptr %tgp573, align 4
  switch i32 %tag574, label %case_default137 [
      i32 0, label %case_br138
  ]
case_br138:
  %fp575 = getelementptr i8, ptr %ld571, i64 16
  %fv576 = load ptr, ptr %fp575, align 8
  %$f1083.addr = alloca ptr
  store ptr %fv576, ptr %$f1083.addr
  %fp577 = getelementptr i8, ptr %ld571, i64 24
  %fv578 = load ptr, ptr %fp577, align 8
  %$f1084.addr = alloca ptr
  store ptr %fv578, ptr %$f1084.addr
  %fp579 = getelementptr i8, ptr %ld571, i64 32
  %fv580 = load ptr, ptr %fp579, align 8
  %$f1085.addr = alloca ptr
  store ptr %fv580, ptr %$f1085.addr
  %freed581 = call i64 @march_decrc_freed(ptr %ld571)
  %freed_b582 = icmp ne i64 %freed581, 0
  br i1 %freed_b582, label %br_unique139, label %br_shared140
br_shared140:
  call void @march_incrc(ptr %fv580)
  call void @march_incrc(ptr %fv578)
  call void @march_incrc(ptr %fv576)
  br label %br_body141
br_unique139:
  br label %br_body141
br_body141:
  %ld583 = load ptr, ptr %$f1085.addr
  %last.addr = alloca ptr
  store ptr %ld583, ptr %last.addr
  %ld584 = load ptr, ptr %$f1084.addr
  %headers.addr = alloca ptr
  store ptr %ld584, ptr %headers.addr
  %ld585 = load ptr, ptr %$f1083.addr
  %status.addr = alloca ptr
  store ptr %ld585, ptr %status.addr
  %hp586 = call ptr @march_alloc(i64 40)
  %tgp587 = getelementptr i8, ptr %hp586, i64 8
  store i32 0, ptr %tgp587, align 4
  %ld588 = load ptr, ptr %status.addr
  %fp589 = getelementptr i8, ptr %hp586, i64 16
  store ptr %ld588, ptr %fp589, align 8
  %ld590 = load ptr, ptr %headers.addr
  %fp591 = getelementptr i8, ptr %hp586, i64 24
  store ptr %ld590, ptr %fp591, align 8
  %ld592 = load ptr, ptr %last.addr
  %fp593 = getelementptr i8, ptr %hp586, i64 32
  store ptr %ld592, ptr %fp593, align 8
  %$t1080.addr = alloca ptr
  store ptr %hp586, ptr %$t1080.addr
  %hp594 = call ptr @march_alloc(i64 24)
  %tgp595 = getelementptr i8, ptr %hp594, i64 8
  store i32 0, ptr %tgp595, align 4
  %ld596 = load ptr, ptr %$t1080.addr
  %fp597 = getelementptr i8, ptr %hp594, i64 16
  store ptr %ld596, ptr %fp597, align 8
  store ptr %hp594, ptr %res_slot572
  br label %case_merge136
case_default137:
  unreachable
case_merge136:
  %case_r598 = load ptr, ptr %res_slot572
  store ptr %case_r598, ptr %res_slot546
  br label %case_merge126
case_default127:
  unreachable
case_merge126:
  %case_r599 = load ptr, ptr %res_slot546
  store ptr %case_r599, ptr %res_slot512
  br label %case_merge116
case_default117:
  unreachable
case_merge116:
  %case_r600 = load ptr, ptr %res_slot512
  store ptr %case_r600, ptr %res_slot486
  br label %case_merge106
case_default107:
  unreachable
case_merge106:
  %case_r601 = load ptr, ptr %res_slot486
  store ptr %case_r601, ptr %res_slot464
  br label %case_merge100
case_default101:
  unreachable
case_merge100:
  %case_r602 = load ptr, ptr %res_slot464
  store ptr %case_r602, ptr %res_slot430
  br label %case_merge90
case_default91:
  unreachable
case_merge90:
  %case_r603 = load ptr, ptr %res_slot430
  ret ptr %case_r603
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld604 = load ptr, ptr %req.addr
  %sl605 = call ptr @march_string_lit(ptr @.str26, i64 10)
  %sl606 = call ptr @march_string_lit(ptr @.str27, i64 9)
  %cr607 = call ptr @Http.set_header$Request_V__3635$String$String(ptr %ld604, ptr %sl605, ptr %sl606)
  %req_1.addr = alloca ptr
  store ptr %cr607, ptr %req_1.addr
  %ld608 = load ptr, ptr %req_1.addr
  %sl609 = call ptr @march_string_lit(ptr @.str28, i64 6)
  %sl610 = call ptr @march_string_lit(ptr @.str29, i64 3)
  %cr611 = call ptr @Http.set_header$Request_V__3637$String$String(ptr %ld608, ptr %sl609, ptr %sl610)
  %req_2.addr = alloca ptr
  store ptr %cr611, ptr %req_2.addr
  %hp612 = call ptr @march_alloc(i64 24)
  %tgp613 = getelementptr i8, ptr %hp612, i64 8
  store i32 0, ptr %tgp613, align 4
  %ld614 = load ptr, ptr %req_2.addr
  %fp615 = getelementptr i8, ptr %hp612, i64 16
  store ptr %ld614, ptr %fp615, align 8
  ret ptr %hp612
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__6076_Result_Request_V__6075_V__6074(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld616 = load ptr, ptr %client.addr
  %res_slot617 = alloca ptr
  %tgp618 = getelementptr i8, ptr %ld616, i64 8
  %tag619 = load i32, ptr %tgp618, align 4
  switch i32 %tag619, label %case_default143 [
      i32 0, label %case_br144
  ]
case_br144:
  %fp620 = getelementptr i8, ptr %ld616, i64 16
  %fv621 = load ptr, ptr %fp620, align 8
  %$f889.addr = alloca ptr
  store ptr %fv621, ptr %$f889.addr
  %fp622 = getelementptr i8, ptr %ld616, i64 24
  %fv623 = load ptr, ptr %fp622, align 8
  %$f890.addr = alloca ptr
  store ptr %fv623, ptr %$f890.addr
  %fp624 = getelementptr i8, ptr %ld616, i64 32
  %fv625 = load ptr, ptr %fp624, align 8
  %$f891.addr = alloca ptr
  store ptr %fv625, ptr %$f891.addr
  %fp626 = getelementptr i8, ptr %ld616, i64 40
  %fv627 = load i64, ptr %fp626, align 8
  %$f892.addr = alloca i64
  store i64 %fv627, ptr %$f892.addr
  %fp628 = getelementptr i8, ptr %ld616, i64 48
  %fv629 = load i64, ptr %fp628, align 8
  %$f893.addr = alloca i64
  store i64 %fv629, ptr %$f893.addr
  %fp630 = getelementptr i8, ptr %ld616, i64 56
  %fv631 = load i64, ptr %fp630, align 8
  %$f894.addr = alloca i64
  store i64 %fv631, ptr %$f894.addr
  %ld632 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld632, ptr %backoff.addr
  %ld633 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld633, ptr %retries.addr
  %ld634 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld634, ptr %redir.addr
  %ld635 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld635, ptr %err_steps.addr
  %ld636 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld636, ptr %resp_steps.addr
  %ld637 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld637, ptr %req_steps.addr
  %hp638 = call ptr @march_alloc(i64 32)
  %tgp639 = getelementptr i8, ptr %hp638, i64 8
  store i32 0, ptr %tgp639, align 4
  %ld640 = load ptr, ptr %name.addr
  %fp641 = getelementptr i8, ptr %hp638, i64 16
  store ptr %ld640, ptr %fp641, align 8
  %ld642 = load ptr, ptr %step.addr
  %fp643 = getelementptr i8, ptr %hp638, i64 24
  store ptr %ld642, ptr %fp643, align 8
  %$t887.addr = alloca ptr
  store ptr %hp638, ptr %$t887.addr
  %ld644 = load ptr, ptr %req_steps.addr
  %ld645 = load ptr, ptr %$t887.addr
  %cr646 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld644, ptr %ld645)
  %$t888.addr = alloca ptr
  store ptr %cr646, ptr %$t888.addr
  %ld647 = load ptr, ptr %client.addr
  %ld648 = load ptr, ptr %$t888.addr
  %ld649 = load ptr, ptr %resp_steps.addr
  %ld650 = load ptr, ptr %err_steps.addr
  %ld651 = load i64, ptr %redir.addr
  %ld652 = load i64, ptr %retries.addr
  %ld653 = load i64, ptr %backoff.addr
  %rc654 = load i64, ptr %ld647, align 8
  %uniq655 = icmp eq i64 %rc654, 1
  %fbip_slot656 = alloca ptr
  br i1 %uniq655, label %fbip_reuse145, label %fbip_fresh146
fbip_reuse145:
  %tgp657 = getelementptr i8, ptr %ld647, i64 8
  store i32 0, ptr %tgp657, align 4
  %fp658 = getelementptr i8, ptr %ld647, i64 16
  store ptr %ld648, ptr %fp658, align 8
  %fp659 = getelementptr i8, ptr %ld647, i64 24
  store ptr %ld649, ptr %fp659, align 8
  %fp660 = getelementptr i8, ptr %ld647, i64 32
  store ptr %ld650, ptr %fp660, align 8
  %fp661 = getelementptr i8, ptr %ld647, i64 40
  store i64 %ld651, ptr %fp661, align 8
  %fp662 = getelementptr i8, ptr %ld647, i64 48
  store i64 %ld652, ptr %fp662, align 8
  %fp663 = getelementptr i8, ptr %ld647, i64 56
  store i64 %ld653, ptr %fp663, align 8
  store ptr %ld647, ptr %fbip_slot656
  br label %fbip_merge147
fbip_fresh146:
  call void @march_decrc(ptr %ld647)
  %hp664 = call ptr @march_alloc(i64 64)
  %tgp665 = getelementptr i8, ptr %hp664, i64 8
  store i32 0, ptr %tgp665, align 4
  %fp666 = getelementptr i8, ptr %hp664, i64 16
  store ptr %ld648, ptr %fp666, align 8
  %fp667 = getelementptr i8, ptr %hp664, i64 24
  store ptr %ld649, ptr %fp667, align 8
  %fp668 = getelementptr i8, ptr %hp664, i64 32
  store ptr %ld650, ptr %fp668, align 8
  %fp669 = getelementptr i8, ptr %hp664, i64 40
  store i64 %ld651, ptr %fp669, align 8
  %fp670 = getelementptr i8, ptr %hp664, i64 48
  store i64 %ld652, ptr %fp670, align 8
  %fp671 = getelementptr i8, ptr %hp664, i64 56
  store i64 %ld653, ptr %fp671, align 8
  store ptr %hp664, ptr %fbip_slot656
  br label %fbip_merge147
fbip_merge147:
  %fbip_r672 = load ptr, ptr %fbip_slot656
  store ptr %fbip_r672, ptr %res_slot617
  br label %case_merge142
case_default143:
  unreachable
case_merge142:
  %case_r673 = load ptr, ptr %res_slot617
  ret ptr %case_r673
}

define ptr @HttpTransport.stream_request_on$V__2823$Request_String$Fn_String_T_(ptr %fd.arg, ptr %req.arg, ptr %on_chunk.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %ld674 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld674)
  %ld675 = load ptr, ptr %req.addr
  %cr676 = call ptr @Http.method$Request_String(ptr %ld675)
  %$t801.addr = alloca ptr
  store ptr %cr676, ptr %$t801.addr
  %ld677 = load ptr, ptr %$t801.addr
  %cr678 = call ptr @Http.method_to_string(ptr %ld677)
  %meth.addr = alloca ptr
  store ptr %cr678, ptr %meth.addr
  %ld679 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld679)
  %ld680 = load ptr, ptr %req.addr
  %cr681 = call ptr @Http.host$Request_String(ptr %ld680)
  %req_host.addr = alloca ptr
  store ptr %cr681, ptr %req_host.addr
  %ld682 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld682)
  %ld683 = load ptr, ptr %req.addr
  %cr684 = call ptr @Http.path$Request_String(ptr %ld683)
  %req_path.addr = alloca ptr
  store ptr %cr684, ptr %req_path.addr
  %ld685 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld685)
  %ld686 = load ptr, ptr %req.addr
  %cr687 = call ptr @Http.query$Request_String(ptr %ld686)
  %req_query.addr = alloca ptr
  store ptr %cr687, ptr %req_query.addr
  %ld688 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld688)
  %ld689 = load ptr, ptr %req.addr
  %cr690 = call ptr @Http.headers$Request_String(ptr %ld689)
  %req_headers.addr = alloca ptr
  store ptr %cr690, ptr %req_headers.addr
  %ld691 = load ptr, ptr %req.addr
  %cr692 = call ptr @Http.body$Request_String(ptr %ld691)
  %req_body.addr = alloca ptr
  store ptr %cr692, ptr %req_body.addr
  %ld693 = load ptr, ptr %meth.addr
  %ld694 = load ptr, ptr %req_host.addr
  %ld695 = load ptr, ptr %req_path.addr
  %ld696 = load ptr, ptr %req_query.addr
  %ld697 = load ptr, ptr %req_headers.addr
  %ld698 = load ptr, ptr %req_body.addr
  %cr699 = call ptr @http_serialize_request(ptr %ld693, ptr %ld694, ptr %ld695, ptr %ld696, ptr %ld697, ptr %ld698)
  %raw_request.addr = alloca ptr
  store ptr %cr699, ptr %raw_request.addr
  %ld700 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld700)
  %ld701 = load ptr, ptr %fd.addr
  %ld702 = load ptr, ptr %raw_request.addr
  %cr703 = call ptr @march_tcp_send_all(ptr %ld701, ptr %ld702)
  %$t802.addr = alloca ptr
  store ptr %cr703, ptr %$t802.addr
  %ld704 = load ptr, ptr %$t802.addr
  %res_slot705 = alloca ptr
  %tgp706 = getelementptr i8, ptr %ld704, i64 8
  %tag707 = load i32, ptr %tgp706, align 4
  switch i32 %tag707, label %case_default149 [
      i32 1, label %case_br150
      i32 0, label %case_br151
  ]
case_br150:
  %fp708 = getelementptr i8, ptr %ld704, i64 16
  %fv709 = load ptr, ptr %fp708, align 8
  %$f818.addr = alloca ptr
  store ptr %fv709, ptr %$f818.addr
  %freed710 = call i64 @march_decrc_freed(ptr %ld704)
  %freed_b711 = icmp ne i64 %freed710, 0
  br i1 %freed_b711, label %br_unique152, label %br_shared153
br_shared153:
  call void @march_incrc(ptr %fv709)
  br label %br_body154
br_unique152:
  br label %br_body154
br_body154:
  %ld712 = load ptr, ptr %$f818.addr
  %msg.addr = alloca ptr
  store ptr %ld712, ptr %msg.addr
  %hp713 = call ptr @march_alloc(i64 24)
  %tgp714 = getelementptr i8, ptr %hp713, i64 8
  store i32 2, ptr %tgp714, align 4
  %ld715 = load ptr, ptr %msg.addr
  %fp716 = getelementptr i8, ptr %hp713, i64 16
  store ptr %ld715, ptr %fp716, align 8
  %$t803.addr = alloca ptr
  store ptr %hp713, ptr %$t803.addr
  %hp717 = call ptr @march_alloc(i64 24)
  %tgp718 = getelementptr i8, ptr %hp717, i64 8
  store i32 1, ptr %tgp718, align 4
  %ld719 = load ptr, ptr %$t803.addr
  %fp720 = getelementptr i8, ptr %hp717, i64 16
  store ptr %ld719, ptr %fp720, align 8
  store ptr %hp717, ptr %res_slot705
  br label %case_merge148
case_br151:
  %fp721 = getelementptr i8, ptr %ld704, i64 16
  %fv722 = load ptr, ptr %fp721, align 8
  %$f819.addr = alloca ptr
  store ptr %fv722, ptr %$f819.addr
  %freed723 = call i64 @march_decrc_freed(ptr %ld704)
  %freed_b724 = icmp ne i64 %freed723, 0
  br i1 %freed_b724, label %br_unique155, label %br_shared156
br_shared156:
  call void @march_incrc(ptr %fv722)
  br label %br_body157
br_unique155:
  br label %br_body157
br_body157:
  %ld725 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld725)
  %ld726 = load ptr, ptr %fd.addr
  %cr727 = call ptr @tcp_recv_http_headers(ptr %ld726)
  %$t804.addr = alloca ptr
  store ptr %cr727, ptr %$t804.addr
  %ld728 = load ptr, ptr %$t804.addr
  %res_slot729 = alloca ptr
  %tgp730 = getelementptr i8, ptr %ld728, i64 8
  %tag731 = load i32, ptr %tgp730, align 4
  switch i32 %tag731, label %case_default159 [
      i32 1, label %case_br160
      i32 0, label %case_br161
  ]
case_br160:
  %fp732 = getelementptr i8, ptr %ld728, i64 16
  %fv733 = load ptr, ptr %fp732, align 8
  %$f813.addr = alloca ptr
  store ptr %fv733, ptr %$f813.addr
  %freed734 = call i64 @march_decrc_freed(ptr %ld728)
  %freed_b735 = icmp ne i64 %freed734, 0
  br i1 %freed_b735, label %br_unique162, label %br_shared163
br_shared163:
  call void @march_incrc(ptr %fv733)
  br label %br_body164
br_unique162:
  br label %br_body164
br_body164:
  %ld736 = load ptr, ptr %$f813.addr
  %msg_1.addr = alloca ptr
  store ptr %ld736, ptr %msg_1.addr
  %hp737 = call ptr @march_alloc(i64 24)
  %tgp738 = getelementptr i8, ptr %hp737, i64 8
  store i32 3, ptr %tgp738, align 4
  %ld739 = load ptr, ptr %msg_1.addr
  %fp740 = getelementptr i8, ptr %hp737, i64 16
  store ptr %ld739, ptr %fp740, align 8
  %$t805.addr = alloca ptr
  store ptr %hp737, ptr %$t805.addr
  %hp741 = call ptr @march_alloc(i64 24)
  %tgp742 = getelementptr i8, ptr %hp741, i64 8
  store i32 1, ptr %tgp742, align 4
  %ld743 = load ptr, ptr %$t805.addr
  %fp744 = getelementptr i8, ptr %hp741, i64 16
  store ptr %ld743, ptr %fp744, align 8
  store ptr %hp741, ptr %res_slot729
  br label %case_merge158
case_br161:
  %fp745 = getelementptr i8, ptr %ld728, i64 16
  %fv746 = load ptr, ptr %fp745, align 8
  %$f814.addr = alloca ptr
  store ptr %fv746, ptr %$f814.addr
  %freed747 = call i64 @march_decrc_freed(ptr %ld728)
  %freed_b748 = icmp ne i64 %freed747, 0
  br i1 %freed_b748, label %br_unique165, label %br_shared166
br_shared166:
  call void @march_incrc(ptr %fv746)
  br label %br_body167
br_unique165:
  br label %br_body167
br_body167:
  %ld749 = load ptr, ptr %$f814.addr
  %res_slot750 = alloca ptr
  %tgp751 = getelementptr i8, ptr %ld749, i64 8
  %tag752 = load i32, ptr %tgp751, align 4
  switch i32 %tag752, label %case_default169 [
      i32 0, label %case_br170
  ]
case_br170:
  %fp753 = getelementptr i8, ptr %ld749, i64 16
  %fv754 = load ptr, ptr %fp753, align 8
  %$f815.addr = alloca ptr
  store ptr %fv754, ptr %$f815.addr
  %fp755 = getelementptr i8, ptr %ld749, i64 24
  %fv756 = load ptr, ptr %fp755, align 8
  %$f816.addr = alloca ptr
  store ptr %fv756, ptr %$f816.addr
  %fp757 = getelementptr i8, ptr %ld749, i64 32
  %fv758 = load ptr, ptr %fp757, align 8
  %$f817.addr = alloca ptr
  store ptr %fv758, ptr %$f817.addr
  %freed759 = call i64 @march_decrc_freed(ptr %ld749)
  %freed_b760 = icmp ne i64 %freed759, 0
  br i1 %freed_b760, label %br_unique171, label %br_shared172
br_shared172:
  call void @march_incrc(ptr %fv758)
  call void @march_incrc(ptr %fv756)
  call void @march_incrc(ptr %fv754)
  br label %br_body173
br_unique171:
  br label %br_body173
br_body173:
  %ld761 = load ptr, ptr %$f817.addr
  %is_chunked.addr = alloca ptr
  store ptr %ld761, ptr %is_chunked.addr
  %ld762 = load ptr, ptr %$f816.addr
  %content_length.addr = alloca ptr
  store ptr %ld762, ptr %content_length.addr
  %ld763 = load ptr, ptr %$f815.addr
  %headers_str.addr = alloca ptr
  store ptr %ld763, ptr %headers_str.addr
  %ld764 = load ptr, ptr %headers_str.addr
  %cr765 = call ptr @http_parse_response(ptr %ld764)
  %$t806.addr = alloca ptr
  store ptr %cr765, ptr %$t806.addr
  %ld766 = load ptr, ptr %$t806.addr
  %res_slot767 = alloca ptr
  %tgp768 = getelementptr i8, ptr %ld766, i64 8
  %tag769 = load i32, ptr %tgp768, align 4
  switch i32 %tag769, label %case_default175 [
      i32 1, label %case_br176
      i32 0, label %case_br177
  ]
case_br176:
  %fp770 = getelementptr i8, ptr %ld766, i64 16
  %fv771 = load ptr, ptr %fp770, align 8
  %$f808.addr = alloca ptr
  store ptr %fv771, ptr %$f808.addr
  %freed772 = call i64 @march_decrc_freed(ptr %ld766)
  %freed_b773 = icmp ne i64 %freed772, 0
  br i1 %freed_b773, label %br_unique178, label %br_shared179
br_shared179:
  call void @march_incrc(ptr %fv771)
  br label %br_body180
br_unique178:
  br label %br_body180
br_body180:
  %ld774 = load ptr, ptr %$f808.addr
  %msg_2.addr = alloca ptr
  store ptr %ld774, ptr %msg_2.addr
  %hp775 = call ptr @march_alloc(i64 24)
  %tgp776 = getelementptr i8, ptr %hp775, i64 8
  store i32 0, ptr %tgp776, align 4
  %ld777 = load ptr, ptr %msg_2.addr
  %fp778 = getelementptr i8, ptr %hp775, i64 16
  store ptr %ld777, ptr %fp778, align 8
  %$t807.addr = alloca ptr
  store ptr %hp775, ptr %$t807.addr
  %hp779 = call ptr @march_alloc(i64 24)
  %tgp780 = getelementptr i8, ptr %hp779, i64 8
  store i32 1, ptr %tgp780, align 4
  %ld781 = load ptr, ptr %$t807.addr
  %fp782 = getelementptr i8, ptr %hp779, i64 16
  store ptr %ld781, ptr %fp782, align 8
  store ptr %hp779, ptr %res_slot767
  br label %case_merge174
case_br177:
  %fp783 = getelementptr i8, ptr %ld766, i64 16
  %fv784 = load ptr, ptr %fp783, align 8
  %$f809.addr = alloca ptr
  store ptr %fv784, ptr %$f809.addr
  %freed785 = call i64 @march_decrc_freed(ptr %ld766)
  %freed_b786 = icmp ne i64 %freed785, 0
  br i1 %freed_b786, label %br_unique181, label %br_shared182
br_shared182:
  call void @march_incrc(ptr %fv784)
  br label %br_body183
br_unique181:
  br label %br_body183
br_body183:
  %ld787 = load ptr, ptr %$f809.addr
  %res_slot788 = alloca ptr
  %tgp789 = getelementptr i8, ptr %ld787, i64 8
  %tag790 = load i32, ptr %tgp789, align 4
  switch i32 %tag790, label %case_default185 [
      i32 0, label %case_br186
  ]
case_br186:
  %fp791 = getelementptr i8, ptr %ld787, i64 16
  %fv792 = load ptr, ptr %fp791, align 8
  %$f810.addr = alloca ptr
  store ptr %fv792, ptr %$f810.addr
  %fp793 = getelementptr i8, ptr %ld787, i64 24
  %fv794 = load ptr, ptr %fp793, align 8
  %$f811.addr = alloca ptr
  store ptr %fv794, ptr %$f811.addr
  %fp795 = getelementptr i8, ptr %ld787, i64 32
  %fv796 = load ptr, ptr %fp795, align 8
  %$f812.addr = alloca ptr
  store ptr %fv796, ptr %$f812.addr
  %freed797 = call i64 @march_decrc_freed(ptr %ld787)
  %freed_b798 = icmp ne i64 %freed797, 0
  br i1 %freed_b798, label %br_unique187, label %br_shared188
br_shared188:
  call void @march_incrc(ptr %fv796)
  call void @march_incrc(ptr %fv794)
  call void @march_incrc(ptr %fv792)
  br label %br_body189
br_unique187:
  br label %br_body189
br_body189:
  %ld799 = load ptr, ptr %$f811.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld799, ptr %resp_headers.addr
  %ld800 = load ptr, ptr %$f810.addr
  %status_code.addr = alloca ptr
  store ptr %ld800, ptr %status_code.addr
  %ld801 = load ptr, ptr %is_chunked.addr
  %res_slot802 = alloca ptr
  %bi803 = trunc i64 %ld801 to i1
  br i1 %bi803, label %case_br192, label %case_default191
case_br192:
  %ld804 = load ptr, ptr %fd.addr
  %ld805 = load ptr, ptr %on_chunk.addr
  %ld806 = load ptr, ptr %status_code.addr
  %ld807 = load ptr, ptr %resp_headers.addr
  %cr808 = call ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %ld804, ptr %ld805, ptr %ld806, ptr %ld807)
  store ptr %cr808, ptr %res_slot802
  br label %case_merge190
case_default191:
  %ld809 = load ptr, ptr %fd.addr
  %ld810 = load ptr, ptr %content_length.addr
  %ld811 = load ptr, ptr %on_chunk.addr
  %ld812 = load ptr, ptr %status_code.addr
  %ld813 = load ptr, ptr %resp_headers.addr
  %cr814 = call ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %ld809, ptr %ld810, ptr %ld811, ptr %ld812, ptr %ld813)
  store ptr %cr814, ptr %res_slot802
  br label %case_merge190
case_merge190:
  %case_r815 = load ptr, ptr %res_slot802
  store ptr %case_r815, ptr %res_slot788
  br label %case_merge184
case_default185:
  unreachable
case_merge184:
  %case_r816 = load ptr, ptr %res_slot788
  store ptr %case_r816, ptr %res_slot767
  br label %case_merge174
case_default175:
  unreachable
case_merge174:
  %case_r817 = load ptr, ptr %res_slot767
  store ptr %case_r817, ptr %res_slot750
  br label %case_merge168
case_default169:
  unreachable
case_merge168:
  %case_r818 = load ptr, ptr %res_slot750
  store ptr %case_r818, ptr %res_slot729
  br label %case_merge158
case_default159:
  unreachable
case_merge158:
  %case_r819 = load ptr, ptr %res_slot729
  store ptr %case_r819, ptr %res_slot705
  br label %case_merge148
case_default149:
  unreachable
case_merge148:
  %case_r820 = load ptr, ptr %res_slot705
  ret ptr %case_r820
}

define ptr @HttpTransport.connect$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld821 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld821)
  %ld822 = load ptr, ptr %req.addr
  %cr823 = call ptr @Http.host$Request_String(ptr %ld822)
  %req_host.addr = alloca ptr
  store ptr %cr823, ptr %req_host.addr
  %ld824 = load ptr, ptr %req.addr
  %cr825 = call ptr @Http.port$Request_String(ptr %ld824)
  %$t777.addr = alloca ptr
  store ptr %cr825, ptr %$t777.addr
  %ld826 = load ptr, ptr %$t777.addr
  %res_slot827 = alloca ptr
  %tgp828 = getelementptr i8, ptr %ld826, i64 8
  %tag829 = load i32, ptr %tgp828, align 4
  switch i32 %tag829, label %case_default194 [
      i32 1, label %case_br195
      i32 0, label %case_br196
  ]
case_br195:
  %fp830 = getelementptr i8, ptr %ld826, i64 16
  %fv831 = load ptr, ptr %fp830, align 8
  %$f778.addr = alloca ptr
  store ptr %fv831, ptr %$f778.addr
  %ld832 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld832)
  %ld833 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld833, ptr %p.addr
  %ld834 = load ptr, ptr %p.addr
  store ptr %ld834, ptr %res_slot827
  br label %case_merge193
case_br196:
  %ld835 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld835)
  %cv836 = inttoptr i64 80 to ptr
  store ptr %cv836, ptr %res_slot827
  br label %case_merge193
case_default194:
  unreachable
case_merge193:
  %case_r837 = load ptr, ptr %res_slot827
  %cv838 = ptrtoint ptr %case_r837 to i64
  %req_port.addr = alloca i64
  store i64 %cv838, ptr %req_port.addr
  %ld839 = load ptr, ptr %req_host.addr
  %ld840 = load i64, ptr %req_port.addr
  %cr841 = call ptr @tcp_connect(ptr %ld839, i64 %ld840)
  %$t779.addr = alloca ptr
  store ptr %cr841, ptr %$t779.addr
  %ld842 = load ptr, ptr %$t779.addr
  %res_slot843 = alloca ptr
  %tgp844 = getelementptr i8, ptr %ld842, i64 8
  %tag845 = load i32, ptr %tgp844, align 4
  switch i32 %tag845, label %case_default198 [
      i32 1, label %case_br199
      i32 0, label %case_br200
  ]
case_br199:
  %fp846 = getelementptr i8, ptr %ld842, i64 16
  %fv847 = load ptr, ptr %fp846, align 8
  %$f781.addr = alloca ptr
  store ptr %fv847, ptr %$f781.addr
  %freed848 = call i64 @march_decrc_freed(ptr %ld842)
  %freed_b849 = icmp ne i64 %freed848, 0
  br i1 %freed_b849, label %br_unique201, label %br_shared202
br_shared202:
  call void @march_incrc(ptr %fv847)
  br label %br_body203
br_unique201:
  br label %br_body203
br_body203:
  %ld850 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld850, ptr %msg.addr
  %hp851 = call ptr @march_alloc(i64 24)
  %tgp852 = getelementptr i8, ptr %hp851, i64 8
  store i32 0, ptr %tgp852, align 4
  %ld853 = load ptr, ptr %msg.addr
  %fp854 = getelementptr i8, ptr %hp851, i64 16
  store ptr %ld853, ptr %fp854, align 8
  %$t780.addr = alloca ptr
  store ptr %hp851, ptr %$t780.addr
  %hp855 = call ptr @march_alloc(i64 24)
  %tgp856 = getelementptr i8, ptr %hp855, i64 8
  store i32 1, ptr %tgp856, align 4
  %ld857 = load ptr, ptr %$t780.addr
  %fp858 = getelementptr i8, ptr %hp855, i64 16
  store ptr %ld857, ptr %fp858, align 8
  store ptr %hp855, ptr %res_slot843
  br label %case_merge197
case_br200:
  %fp859 = getelementptr i8, ptr %ld842, i64 16
  %fv860 = load ptr, ptr %fp859, align 8
  %$f782.addr = alloca ptr
  store ptr %fv860, ptr %$f782.addr
  %freed861 = call i64 @march_decrc_freed(ptr %ld842)
  %freed_b862 = icmp ne i64 %freed861, 0
  br i1 %freed_b862, label %br_unique204, label %br_shared205
br_shared205:
  call void @march_incrc(ptr %fv860)
  br label %br_body206
br_unique204:
  br label %br_body206
br_body206:
  %ld863 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld863, ptr %fd.addr
  %hp864 = call ptr @march_alloc(i64 24)
  %tgp865 = getelementptr i8, ptr %hp864, i64 8
  store i32 0, ptr %tgp865, align 4
  %ld866 = load ptr, ptr %fd.addr
  %fp867 = getelementptr i8, ptr %hp864, i64 16
  store ptr %ld866, ptr %fp867, align 8
  store ptr %hp864, ptr %res_slot843
  br label %case_merge197
case_default198:
  unreachable
case_merge197:
  %case_r868 = load ptr, ptr %res_slot843
  ret ptr %case_r868
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld869 = load ptr, ptr %steps.addr
  %res_slot870 = alloca ptr
  %tgp871 = getelementptr i8, ptr %ld869, i64 8
  %tag872 = load i32, ptr %tgp871, align 4
  switch i32 %tag872, label %case_default208 [
      i32 0, label %case_br209
      i32 1, label %case_br210
  ]
case_br209:
  %ld873 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld873)
  %hp874 = call ptr @march_alloc(i64 24)
  %tgp875 = getelementptr i8, ptr %hp874, i64 8
  store i32 0, ptr %tgp875, align 4
  %ld876 = load ptr, ptr %req.addr
  %fp877 = getelementptr i8, ptr %hp874, i64 16
  store ptr %ld876, ptr %fp877, align 8
  store ptr %hp874, ptr %res_slot870
  br label %case_merge207
case_br210:
  %fp878 = getelementptr i8, ptr %ld869, i64 16
  %fv879 = load ptr, ptr %fp878, align 8
  %$f957.addr = alloca ptr
  store ptr %fv879, ptr %$f957.addr
  %fp880 = getelementptr i8, ptr %ld869, i64 24
  %fv881 = load ptr, ptr %fp880, align 8
  %$f958.addr = alloca ptr
  store ptr %fv881, ptr %$f958.addr
  %freed882 = call i64 @march_decrc_freed(ptr %ld869)
  %freed_b883 = icmp ne i64 %freed882, 0
  br i1 %freed_b883, label %br_unique211, label %br_shared212
br_shared212:
  call void @march_incrc(ptr %fv881)
  call void @march_incrc(ptr %fv879)
  br label %br_body213
br_unique211:
  br label %br_body213
br_body213:
  %ld884 = load ptr, ptr %$f957.addr
  %res_slot885 = alloca ptr
  %tgp886 = getelementptr i8, ptr %ld884, i64 8
  %tag887 = load i32, ptr %tgp886, align 4
  switch i32 %tag887, label %case_default215 [
      i32 0, label %case_br216
  ]
case_br216:
  %fp888 = getelementptr i8, ptr %ld884, i64 16
  %fv889 = load ptr, ptr %fp888, align 8
  %$f959.addr = alloca ptr
  store ptr %fv889, ptr %$f959.addr
  %fp890 = getelementptr i8, ptr %ld884, i64 24
  %fv891 = load ptr, ptr %fp890, align 8
  %$f960.addr = alloca ptr
  store ptr %fv891, ptr %$f960.addr
  %freed892 = call i64 @march_decrc_freed(ptr %ld884)
  %freed_b893 = icmp ne i64 %freed892, 0
  br i1 %freed_b893, label %br_unique217, label %br_shared218
br_shared218:
  call void @march_incrc(ptr %fv891)
  call void @march_incrc(ptr %fv889)
  br label %br_body219
br_unique217:
  br label %br_body219
br_body219:
  %ld894 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld894, ptr %rest.addr
  %ld895 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld895, ptr %step_fn.addr
  %ld896 = load ptr, ptr %step_fn.addr
  %fp897 = getelementptr i8, ptr %ld896, i64 16
  %fv898 = load ptr, ptr %fp897, align 8
  %ld899 = load ptr, ptr %req.addr
  %cr900 = call ptr (ptr, ptr) %fv898(ptr %ld896, ptr %ld899)
  %$t954.addr = alloca ptr
  store ptr %cr900, ptr %$t954.addr
  %ld901 = load ptr, ptr %$t954.addr
  %res_slot902 = alloca ptr
  %tgp903 = getelementptr i8, ptr %ld901, i64 8
  %tag904 = load i32, ptr %tgp903, align 4
  switch i32 %tag904, label %case_default221 [
      i32 1, label %case_br222
      i32 0, label %case_br223
  ]
case_br222:
  %fp905 = getelementptr i8, ptr %ld901, i64 16
  %fv906 = load ptr, ptr %fp905, align 8
  %$f955.addr = alloca ptr
  store ptr %fv906, ptr %$f955.addr
  %ld907 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld907, ptr %e.addr
  %ld908 = load ptr, ptr %$t954.addr
  %ld909 = load ptr, ptr %e.addr
  %rc910 = load i64, ptr %ld908, align 8
  %uniq911 = icmp eq i64 %rc910, 1
  %fbip_slot912 = alloca ptr
  br i1 %uniq911, label %fbip_reuse224, label %fbip_fresh225
fbip_reuse224:
  %tgp913 = getelementptr i8, ptr %ld908, i64 8
  store i32 1, ptr %tgp913, align 4
  %fp914 = getelementptr i8, ptr %ld908, i64 16
  store ptr %ld909, ptr %fp914, align 8
  store ptr %ld908, ptr %fbip_slot912
  br label %fbip_merge226
fbip_fresh225:
  call void @march_decrc(ptr %ld908)
  %hp915 = call ptr @march_alloc(i64 24)
  %tgp916 = getelementptr i8, ptr %hp915, i64 8
  store i32 1, ptr %tgp916, align 4
  %fp917 = getelementptr i8, ptr %hp915, i64 16
  store ptr %ld909, ptr %fp917, align 8
  store ptr %hp915, ptr %fbip_slot912
  br label %fbip_merge226
fbip_merge226:
  %fbip_r918 = load ptr, ptr %fbip_slot912
  store ptr %fbip_r918, ptr %res_slot902
  br label %case_merge220
case_br223:
  %fp919 = getelementptr i8, ptr %ld901, i64 16
  %fv920 = load ptr, ptr %fp919, align 8
  %$f956.addr = alloca ptr
  store ptr %fv920, ptr %$f956.addr
  %freed921 = call i64 @march_decrc_freed(ptr %ld901)
  %freed_b922 = icmp ne i64 %freed921, 0
  br i1 %freed_b922, label %br_unique227, label %br_shared228
br_shared228:
  call void @march_incrc(ptr %fv920)
  br label %br_body229
br_unique227:
  br label %br_body229
br_body229:
  %ld923 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld923, ptr %new_req.addr
  %ld924 = load ptr, ptr %rest.addr
  %ld925 = load ptr, ptr %new_req.addr
  %cr926 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld924, ptr %ld925)
  store ptr %cr926, ptr %res_slot902
  br label %case_merge220
case_default221:
  unreachable
case_merge220:
  %case_r927 = load ptr, ptr %res_slot902
  store ptr %case_r927, ptr %res_slot885
  br label %case_merge214
case_default215:
  unreachable
case_merge214:
  %case_r928 = load ptr, ptr %res_slot885
  store ptr %case_r928, ptr %res_slot870
  br label %case_merge207
case_default208:
  unreachable
case_merge207:
  %case_r929 = load ptr, ptr %res_slot870
  ret ptr %case_r929
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld930 = load ptr, ptr %req.addr
  %res_slot931 = alloca ptr
  %tgp932 = getelementptr i8, ptr %ld930, i64 8
  %tag933 = load i32, ptr %tgp932, align 4
  switch i32 %tag933, label %case_default231 [
      i32 0, label %case_br232
  ]
case_br232:
  %fp934 = getelementptr i8, ptr %ld930, i64 16
  %fv935 = load ptr, ptr %fp934, align 8
  %$f648.addr = alloca ptr
  store ptr %fv935, ptr %$f648.addr
  %fp936 = getelementptr i8, ptr %ld930, i64 24
  %fv937 = load ptr, ptr %fp936, align 8
  %$f649.addr = alloca ptr
  store ptr %fv937, ptr %$f649.addr
  %fp938 = getelementptr i8, ptr %ld930, i64 32
  %fv939 = load ptr, ptr %fp938, align 8
  %$f650.addr = alloca ptr
  store ptr %fv939, ptr %$f650.addr
  %fp940 = getelementptr i8, ptr %ld930, i64 40
  %fv941 = load ptr, ptr %fp940, align 8
  %$f651.addr = alloca ptr
  store ptr %fv941, ptr %$f651.addr
  %fp942 = getelementptr i8, ptr %ld930, i64 48
  %fv943 = load ptr, ptr %fp942, align 8
  %$f652.addr = alloca ptr
  store ptr %fv943, ptr %$f652.addr
  %fp944 = getelementptr i8, ptr %ld930, i64 56
  %fv945 = load ptr, ptr %fp944, align 8
  %$f653.addr = alloca ptr
  store ptr %fv945, ptr %$f653.addr
  %fp946 = getelementptr i8, ptr %ld930, i64 64
  %fv947 = load ptr, ptr %fp946, align 8
  %$f654.addr = alloca ptr
  store ptr %fv947, ptr %$f654.addr
  %fp948 = getelementptr i8, ptr %ld930, i64 72
  %fv949 = load ptr, ptr %fp948, align 8
  %$f655.addr = alloca ptr
  store ptr %fv949, ptr %$f655.addr
  %ld950 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld950, ptr %hd.addr
  %ld951 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld951, ptr %q.addr
  %ld952 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld952, ptr %pa.addr
  %ld953 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld953, ptr %p.addr
  %ld954 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld954, ptr %h.addr
  %ld955 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld955, ptr %sc.addr
  %ld956 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld956, ptr %m.addr
  %ld957 = load ptr, ptr %req.addr
  %ld958 = load ptr, ptr %m.addr
  %ld959 = load ptr, ptr %sc.addr
  %ld960 = load ptr, ptr %h.addr
  %ld961 = load ptr, ptr %p.addr
  %ld962 = load ptr, ptr %pa.addr
  %ld963 = load ptr, ptr %q.addr
  %ld964 = load ptr, ptr %hd.addr
  %ld965 = load ptr, ptr %new_body.addr
  %rc966 = load i64, ptr %ld957, align 8
  %uniq967 = icmp eq i64 %rc966, 1
  %fbip_slot968 = alloca ptr
  br i1 %uniq967, label %fbip_reuse233, label %fbip_fresh234
fbip_reuse233:
  %tgp969 = getelementptr i8, ptr %ld957, i64 8
  store i32 0, ptr %tgp969, align 4
  %fp970 = getelementptr i8, ptr %ld957, i64 16
  store ptr %ld958, ptr %fp970, align 8
  %fp971 = getelementptr i8, ptr %ld957, i64 24
  store ptr %ld959, ptr %fp971, align 8
  %fp972 = getelementptr i8, ptr %ld957, i64 32
  store ptr %ld960, ptr %fp972, align 8
  %fp973 = getelementptr i8, ptr %ld957, i64 40
  store ptr %ld961, ptr %fp973, align 8
  %fp974 = getelementptr i8, ptr %ld957, i64 48
  store ptr %ld962, ptr %fp974, align 8
  %fp975 = getelementptr i8, ptr %ld957, i64 56
  store ptr %ld963, ptr %fp975, align 8
  %fp976 = getelementptr i8, ptr %ld957, i64 64
  store ptr %ld964, ptr %fp976, align 8
  %fp977 = getelementptr i8, ptr %ld957, i64 72
  store ptr %ld965, ptr %fp977, align 8
  store ptr %ld957, ptr %fbip_slot968
  br label %fbip_merge235
fbip_fresh234:
  call void @march_decrc(ptr %ld957)
  %hp978 = call ptr @march_alloc(i64 80)
  %tgp979 = getelementptr i8, ptr %hp978, i64 8
  store i32 0, ptr %tgp979, align 4
  %fp980 = getelementptr i8, ptr %hp978, i64 16
  store ptr %ld958, ptr %fp980, align 8
  %fp981 = getelementptr i8, ptr %hp978, i64 24
  store ptr %ld959, ptr %fp981, align 8
  %fp982 = getelementptr i8, ptr %hp978, i64 32
  store ptr %ld960, ptr %fp982, align 8
  %fp983 = getelementptr i8, ptr %hp978, i64 40
  store ptr %ld961, ptr %fp983, align 8
  %fp984 = getelementptr i8, ptr %hp978, i64 48
  store ptr %ld962, ptr %fp984, align 8
  %fp985 = getelementptr i8, ptr %hp978, i64 56
  store ptr %ld963, ptr %fp985, align 8
  %fp986 = getelementptr i8, ptr %hp978, i64 64
  store ptr %ld964, ptr %fp986, align 8
  %fp987 = getelementptr i8, ptr %hp978, i64 72
  store ptr %ld965, ptr %fp987, align 8
  store ptr %hp978, ptr %fbip_slot968
  br label %fbip_merge235
fbip_merge235:
  %fbip_r988 = load ptr, ptr %fbip_slot968
  store ptr %fbip_r988, ptr %res_slot931
  br label %case_merge230
case_default231:
  unreachable
case_merge230:
  %case_r989 = load ptr, ptr %res_slot931
  ret ptr %case_r989
}

define ptr @Http.set_header$Request_V__3637$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld990 = load ptr, ptr %req.addr
  %res_slot991 = alloca ptr
  %tgp992 = getelementptr i8, ptr %ld990, i64 8
  %tag993 = load i32, ptr %tgp992, align 4
  switch i32 %tag993, label %case_default237 [
      i32 0, label %case_br238
  ]
case_br238:
  %fp994 = getelementptr i8, ptr %ld990, i64 16
  %fv995 = load ptr, ptr %fp994, align 8
  %$f658.addr = alloca ptr
  store ptr %fv995, ptr %$f658.addr
  %fp996 = getelementptr i8, ptr %ld990, i64 24
  %fv997 = load ptr, ptr %fp996, align 8
  %$f659.addr = alloca ptr
  store ptr %fv997, ptr %$f659.addr
  %fp998 = getelementptr i8, ptr %ld990, i64 32
  %fv999 = load ptr, ptr %fp998, align 8
  %$f660.addr = alloca ptr
  store ptr %fv999, ptr %$f660.addr
  %fp1000 = getelementptr i8, ptr %ld990, i64 40
  %fv1001 = load ptr, ptr %fp1000, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1001, ptr %$f661.addr
  %fp1002 = getelementptr i8, ptr %ld990, i64 48
  %fv1003 = load ptr, ptr %fp1002, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1003, ptr %$f662.addr
  %fp1004 = getelementptr i8, ptr %ld990, i64 56
  %fv1005 = load ptr, ptr %fp1004, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1005, ptr %$f663.addr
  %fp1006 = getelementptr i8, ptr %ld990, i64 64
  %fv1007 = load ptr, ptr %fp1006, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1007, ptr %$f664.addr
  %fp1008 = getelementptr i8, ptr %ld990, i64 72
  %fv1009 = load ptr, ptr %fp1008, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1009, ptr %$f665.addr
  %ld1010 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1010, ptr %bd.addr
  %ld1011 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1011, ptr %hd.addr
  %ld1012 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1012, ptr %q.addr
  %ld1013 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1013, ptr %pa.addr
  %ld1014 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1014, ptr %p.addr
  %ld1015 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1015, ptr %h.addr
  %ld1016 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1016, ptr %sc.addr
  %ld1017 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1017, ptr %m.addr
  %hp1018 = call ptr @march_alloc(i64 32)
  %tgp1019 = getelementptr i8, ptr %hp1018, i64 8
  store i32 0, ptr %tgp1019, align 4
  %ld1020 = load ptr, ptr %name.addr
  %fp1021 = getelementptr i8, ptr %hp1018, i64 16
  store ptr %ld1020, ptr %fp1021, align 8
  %ld1022 = load ptr, ptr %value.addr
  %fp1023 = getelementptr i8, ptr %hp1018, i64 24
  store ptr %ld1022, ptr %fp1023, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1018, ptr %$t656.addr
  %hp1024 = call ptr @march_alloc(i64 32)
  %tgp1025 = getelementptr i8, ptr %hp1024, i64 8
  store i32 1, ptr %tgp1025, align 4
  %ld1026 = load ptr, ptr %$t656.addr
  %fp1027 = getelementptr i8, ptr %hp1024, i64 16
  store ptr %ld1026, ptr %fp1027, align 8
  %ld1028 = load ptr, ptr %hd.addr
  %fp1029 = getelementptr i8, ptr %hp1024, i64 24
  store ptr %ld1028, ptr %fp1029, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1024, ptr %$t657.addr
  %ld1030 = load ptr, ptr %req.addr
  %ld1031 = load ptr, ptr %m.addr
  %ld1032 = load ptr, ptr %sc.addr
  %ld1033 = load ptr, ptr %h.addr
  %ld1034 = load ptr, ptr %p.addr
  %ld1035 = load ptr, ptr %pa.addr
  %ld1036 = load ptr, ptr %q.addr
  %ld1037 = load ptr, ptr %$t657.addr
  %ld1038 = load ptr, ptr %bd.addr
  %rc1039 = load i64, ptr %ld1030, align 8
  %uniq1040 = icmp eq i64 %rc1039, 1
  %fbip_slot1041 = alloca ptr
  br i1 %uniq1040, label %fbip_reuse239, label %fbip_fresh240
fbip_reuse239:
  %tgp1042 = getelementptr i8, ptr %ld1030, i64 8
  store i32 0, ptr %tgp1042, align 4
  %fp1043 = getelementptr i8, ptr %ld1030, i64 16
  store ptr %ld1031, ptr %fp1043, align 8
  %fp1044 = getelementptr i8, ptr %ld1030, i64 24
  store ptr %ld1032, ptr %fp1044, align 8
  %fp1045 = getelementptr i8, ptr %ld1030, i64 32
  store ptr %ld1033, ptr %fp1045, align 8
  %fp1046 = getelementptr i8, ptr %ld1030, i64 40
  store ptr %ld1034, ptr %fp1046, align 8
  %fp1047 = getelementptr i8, ptr %ld1030, i64 48
  store ptr %ld1035, ptr %fp1047, align 8
  %fp1048 = getelementptr i8, ptr %ld1030, i64 56
  store ptr %ld1036, ptr %fp1048, align 8
  %fp1049 = getelementptr i8, ptr %ld1030, i64 64
  store ptr %ld1037, ptr %fp1049, align 8
  %fp1050 = getelementptr i8, ptr %ld1030, i64 72
  store ptr %ld1038, ptr %fp1050, align 8
  store ptr %ld1030, ptr %fbip_slot1041
  br label %fbip_merge241
fbip_fresh240:
  call void @march_decrc(ptr %ld1030)
  %hp1051 = call ptr @march_alloc(i64 80)
  %tgp1052 = getelementptr i8, ptr %hp1051, i64 8
  store i32 0, ptr %tgp1052, align 4
  %fp1053 = getelementptr i8, ptr %hp1051, i64 16
  store ptr %ld1031, ptr %fp1053, align 8
  %fp1054 = getelementptr i8, ptr %hp1051, i64 24
  store ptr %ld1032, ptr %fp1054, align 8
  %fp1055 = getelementptr i8, ptr %hp1051, i64 32
  store ptr %ld1033, ptr %fp1055, align 8
  %fp1056 = getelementptr i8, ptr %hp1051, i64 40
  store ptr %ld1034, ptr %fp1056, align 8
  %fp1057 = getelementptr i8, ptr %hp1051, i64 48
  store ptr %ld1035, ptr %fp1057, align 8
  %fp1058 = getelementptr i8, ptr %hp1051, i64 56
  store ptr %ld1036, ptr %fp1058, align 8
  %fp1059 = getelementptr i8, ptr %hp1051, i64 64
  store ptr %ld1037, ptr %fp1059, align 8
  %fp1060 = getelementptr i8, ptr %hp1051, i64 72
  store ptr %ld1038, ptr %fp1060, align 8
  store ptr %hp1051, ptr %fbip_slot1041
  br label %fbip_merge241
fbip_merge241:
  %fbip_r1061 = load ptr, ptr %fbip_slot1041
  store ptr %fbip_r1061, ptr %res_slot991
  br label %case_merge236
case_default237:
  unreachable
case_merge236:
  %case_r1062 = load ptr, ptr %res_slot991
  ret ptr %case_r1062
}

define ptr @Http.set_header$Request_V__3635$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1063 = load ptr, ptr %req.addr
  %res_slot1064 = alloca ptr
  %tgp1065 = getelementptr i8, ptr %ld1063, i64 8
  %tag1066 = load i32, ptr %tgp1065, align 4
  switch i32 %tag1066, label %case_default243 [
      i32 0, label %case_br244
  ]
case_br244:
  %fp1067 = getelementptr i8, ptr %ld1063, i64 16
  %fv1068 = load ptr, ptr %fp1067, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1068, ptr %$f658.addr
  %fp1069 = getelementptr i8, ptr %ld1063, i64 24
  %fv1070 = load ptr, ptr %fp1069, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1070, ptr %$f659.addr
  %fp1071 = getelementptr i8, ptr %ld1063, i64 32
  %fv1072 = load ptr, ptr %fp1071, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1072, ptr %$f660.addr
  %fp1073 = getelementptr i8, ptr %ld1063, i64 40
  %fv1074 = load ptr, ptr %fp1073, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1074, ptr %$f661.addr
  %fp1075 = getelementptr i8, ptr %ld1063, i64 48
  %fv1076 = load ptr, ptr %fp1075, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1076, ptr %$f662.addr
  %fp1077 = getelementptr i8, ptr %ld1063, i64 56
  %fv1078 = load ptr, ptr %fp1077, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1078, ptr %$f663.addr
  %fp1079 = getelementptr i8, ptr %ld1063, i64 64
  %fv1080 = load ptr, ptr %fp1079, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1080, ptr %$f664.addr
  %fp1081 = getelementptr i8, ptr %ld1063, i64 72
  %fv1082 = load ptr, ptr %fp1081, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1082, ptr %$f665.addr
  %ld1083 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1083, ptr %bd.addr
  %ld1084 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1084, ptr %hd.addr
  %ld1085 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1085, ptr %q.addr
  %ld1086 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1086, ptr %pa.addr
  %ld1087 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1087, ptr %p.addr
  %ld1088 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1088, ptr %h.addr
  %ld1089 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1089, ptr %sc.addr
  %ld1090 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1090, ptr %m.addr
  %hp1091 = call ptr @march_alloc(i64 32)
  %tgp1092 = getelementptr i8, ptr %hp1091, i64 8
  store i32 0, ptr %tgp1092, align 4
  %ld1093 = load ptr, ptr %name.addr
  %fp1094 = getelementptr i8, ptr %hp1091, i64 16
  store ptr %ld1093, ptr %fp1094, align 8
  %ld1095 = load ptr, ptr %value.addr
  %fp1096 = getelementptr i8, ptr %hp1091, i64 24
  store ptr %ld1095, ptr %fp1096, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1091, ptr %$t656.addr
  %hp1097 = call ptr @march_alloc(i64 32)
  %tgp1098 = getelementptr i8, ptr %hp1097, i64 8
  store i32 1, ptr %tgp1098, align 4
  %ld1099 = load ptr, ptr %$t656.addr
  %fp1100 = getelementptr i8, ptr %hp1097, i64 16
  store ptr %ld1099, ptr %fp1100, align 8
  %ld1101 = load ptr, ptr %hd.addr
  %fp1102 = getelementptr i8, ptr %hp1097, i64 24
  store ptr %ld1101, ptr %fp1102, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1097, ptr %$t657.addr
  %ld1103 = load ptr, ptr %req.addr
  %ld1104 = load ptr, ptr %m.addr
  %ld1105 = load ptr, ptr %sc.addr
  %ld1106 = load ptr, ptr %h.addr
  %ld1107 = load ptr, ptr %p.addr
  %ld1108 = load ptr, ptr %pa.addr
  %ld1109 = load ptr, ptr %q.addr
  %ld1110 = load ptr, ptr %$t657.addr
  %ld1111 = load ptr, ptr %bd.addr
  %rc1112 = load i64, ptr %ld1103, align 8
  %uniq1113 = icmp eq i64 %rc1112, 1
  %fbip_slot1114 = alloca ptr
  br i1 %uniq1113, label %fbip_reuse245, label %fbip_fresh246
fbip_reuse245:
  %tgp1115 = getelementptr i8, ptr %ld1103, i64 8
  store i32 0, ptr %tgp1115, align 4
  %fp1116 = getelementptr i8, ptr %ld1103, i64 16
  store ptr %ld1104, ptr %fp1116, align 8
  %fp1117 = getelementptr i8, ptr %ld1103, i64 24
  store ptr %ld1105, ptr %fp1117, align 8
  %fp1118 = getelementptr i8, ptr %ld1103, i64 32
  store ptr %ld1106, ptr %fp1118, align 8
  %fp1119 = getelementptr i8, ptr %ld1103, i64 40
  store ptr %ld1107, ptr %fp1119, align 8
  %fp1120 = getelementptr i8, ptr %ld1103, i64 48
  store ptr %ld1108, ptr %fp1120, align 8
  %fp1121 = getelementptr i8, ptr %ld1103, i64 56
  store ptr %ld1109, ptr %fp1121, align 8
  %fp1122 = getelementptr i8, ptr %ld1103, i64 64
  store ptr %ld1110, ptr %fp1122, align 8
  %fp1123 = getelementptr i8, ptr %ld1103, i64 72
  store ptr %ld1111, ptr %fp1123, align 8
  store ptr %ld1103, ptr %fbip_slot1114
  br label %fbip_merge247
fbip_fresh246:
  call void @march_decrc(ptr %ld1103)
  %hp1124 = call ptr @march_alloc(i64 80)
  %tgp1125 = getelementptr i8, ptr %hp1124, i64 8
  store i32 0, ptr %tgp1125, align 4
  %fp1126 = getelementptr i8, ptr %hp1124, i64 16
  store ptr %ld1104, ptr %fp1126, align 8
  %fp1127 = getelementptr i8, ptr %hp1124, i64 24
  store ptr %ld1105, ptr %fp1127, align 8
  %fp1128 = getelementptr i8, ptr %hp1124, i64 32
  store ptr %ld1106, ptr %fp1128, align 8
  %fp1129 = getelementptr i8, ptr %hp1124, i64 40
  store ptr %ld1107, ptr %fp1129, align 8
  %fp1130 = getelementptr i8, ptr %hp1124, i64 48
  store ptr %ld1108, ptr %fp1130, align 8
  %fp1131 = getelementptr i8, ptr %hp1124, i64 56
  store ptr %ld1109, ptr %fp1131, align 8
  %fp1132 = getelementptr i8, ptr %hp1124, i64 64
  store ptr %ld1110, ptr %fp1132, align 8
  %fp1133 = getelementptr i8, ptr %hp1124, i64 72
  store ptr %ld1111, ptr %fp1133, align 8
  store ptr %hp1124, ptr %fbip_slot1114
  br label %fbip_merge247
fbip_merge247:
  %fbip_r1134 = load ptr, ptr %fbip_slot1114
  store ptr %fbip_r1134, ptr %res_slot1064
  br label %case_merge242
case_default243:
  unreachable
case_merge242:
  %case_r1135 = load ptr, ptr %res_slot1064
  ret ptr %case_r1135
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld1136 = load ptr, ptr %xs.addr
  %res_slot1137 = alloca ptr
  %tgp1138 = getelementptr i8, ptr %ld1136, i64 8
  %tag1139 = load i32, ptr %tgp1138, align 4
  switch i32 %tag1139, label %case_default249 [
      i32 0, label %case_br250
      i32 1, label %case_br251
  ]
case_br250:
  %ld1140 = load ptr, ptr %xs.addr
  %rc1141 = load i64, ptr %ld1140, align 8
  %uniq1142 = icmp eq i64 %rc1141, 1
  %fbip_slot1143 = alloca ptr
  br i1 %uniq1142, label %fbip_reuse252, label %fbip_fresh253
fbip_reuse252:
  %tgp1144 = getelementptr i8, ptr %ld1140, i64 8
  store i32 0, ptr %tgp1144, align 4
  store ptr %ld1140, ptr %fbip_slot1143
  br label %fbip_merge254
fbip_fresh253:
  call void @march_decrc(ptr %ld1140)
  %hp1145 = call ptr @march_alloc(i64 16)
  %tgp1146 = getelementptr i8, ptr %hp1145, i64 8
  store i32 0, ptr %tgp1146, align 4
  store ptr %hp1145, ptr %fbip_slot1143
  br label %fbip_merge254
fbip_merge254:
  %fbip_r1147 = load ptr, ptr %fbip_slot1143
  %$t883.addr = alloca ptr
  store ptr %fbip_r1147, ptr %$t883.addr
  %hp1148 = call ptr @march_alloc(i64 32)
  %tgp1149 = getelementptr i8, ptr %hp1148, i64 8
  store i32 1, ptr %tgp1149, align 4
  %ld1150 = load ptr, ptr %x.addr
  %fp1151 = getelementptr i8, ptr %hp1148, i64 16
  store ptr %ld1150, ptr %fp1151, align 8
  %ld1152 = load ptr, ptr %$t883.addr
  %fp1153 = getelementptr i8, ptr %hp1148, i64 24
  store ptr %ld1152, ptr %fp1153, align 8
  store ptr %hp1148, ptr %res_slot1137
  br label %case_merge248
case_br251:
  %fp1154 = getelementptr i8, ptr %ld1136, i64 16
  %fv1155 = load ptr, ptr %fp1154, align 8
  %$f885.addr = alloca ptr
  store ptr %fv1155, ptr %$f885.addr
  %fp1156 = getelementptr i8, ptr %ld1136, i64 24
  %fv1157 = load ptr, ptr %fp1156, align 8
  %$f886.addr = alloca ptr
  store ptr %fv1157, ptr %$f886.addr
  %ld1158 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld1158, ptr %t.addr
  %ld1159 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld1159, ptr %h.addr
  %ld1160 = load ptr, ptr %t.addr
  %ld1161 = load ptr, ptr %x.addr
  %cr1162 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld1160, ptr %ld1161)
  %$t884.addr = alloca ptr
  store ptr %cr1162, ptr %$t884.addr
  %ld1163 = load ptr, ptr %xs.addr
  %ld1164 = load ptr, ptr %h.addr
  %ld1165 = load ptr, ptr %$t884.addr
  %rc1166 = load i64, ptr %ld1163, align 8
  %uniq1167 = icmp eq i64 %rc1166, 1
  %fbip_slot1168 = alloca ptr
  br i1 %uniq1167, label %fbip_reuse255, label %fbip_fresh256
fbip_reuse255:
  %tgp1169 = getelementptr i8, ptr %ld1163, i64 8
  store i32 1, ptr %tgp1169, align 4
  %fp1170 = getelementptr i8, ptr %ld1163, i64 16
  store ptr %ld1164, ptr %fp1170, align 8
  %fp1171 = getelementptr i8, ptr %ld1163, i64 24
  store ptr %ld1165, ptr %fp1171, align 8
  store ptr %ld1163, ptr %fbip_slot1168
  br label %fbip_merge257
fbip_fresh256:
  call void @march_decrc(ptr %ld1163)
  %hp1172 = call ptr @march_alloc(i64 32)
  %tgp1173 = getelementptr i8, ptr %hp1172, i64 8
  store i32 1, ptr %tgp1173, align 4
  %fp1174 = getelementptr i8, ptr %hp1172, i64 16
  store ptr %ld1164, ptr %fp1174, align 8
  %fp1175 = getelementptr i8, ptr %hp1172, i64 24
  store ptr %ld1165, ptr %fp1175, align 8
  store ptr %hp1172, ptr %fbip_slot1168
  br label %fbip_merge257
fbip_merge257:
  %fbip_r1176 = load ptr, ptr %fbip_slot1168
  store ptr %fbip_r1176, ptr %res_slot1137
  br label %case_merge248
case_default249:
  unreachable
case_merge248:
  %case_r1177 = load ptr, ptr %res_slot1137
  ret ptr %case_r1177
}

define ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %fd.arg, ptr %on_chunk.arg, ptr %status_code.arg, ptr %resp_headers.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %status_code.addr = alloca ptr
  store ptr %status_code.arg, ptr %status_code.addr
  %resp_headers.addr = alloca ptr
  store ptr %resp_headers.arg, ptr %resp_headers.addr
  %ld1178 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1178)
  %ld1179 = load ptr, ptr %fd.addr
  %cr1180 = call ptr @tcp_recv_chunked_frame(ptr %ld1179)
  %$t820.addr = alloca ptr
  store ptr %cr1180, ptr %$t820.addr
  %ld1181 = load ptr, ptr %$t820.addr
  %res_slot1182 = alloca ptr
  %tgp1183 = getelementptr i8, ptr %ld1181, i64 8
  %tag1184 = load i32, ptr %tgp1183, align 4
  switch i32 %tag1184, label %case_default259 [
      i32 1, label %case_br260
      i32 0, label %case_br261
  ]
case_br260:
  %fp1185 = getelementptr i8, ptr %ld1181, i64 16
  %fv1186 = load ptr, ptr %fp1185, align 8
  %$f824.addr = alloca ptr
  store ptr %fv1186, ptr %$f824.addr
  %freed1187 = call i64 @march_decrc_freed(ptr %ld1181)
  %freed_b1188 = icmp ne i64 %freed1187, 0
  br i1 %freed_b1188, label %br_unique262, label %br_shared263
br_shared263:
  call void @march_incrc(ptr %fv1186)
  br label %br_body264
br_unique262:
  br label %br_body264
br_body264:
  %ld1189 = load ptr, ptr %$f824.addr
  %msg.addr = alloca ptr
  store ptr %ld1189, ptr %msg.addr
  %hp1190 = call ptr @march_alloc(i64 24)
  %tgp1191 = getelementptr i8, ptr %hp1190, i64 8
  store i32 3, ptr %tgp1191, align 4
  %ld1192 = load ptr, ptr %msg.addr
  %fp1193 = getelementptr i8, ptr %hp1190, i64 16
  store ptr %ld1192, ptr %fp1193, align 8
  %$t821.addr = alloca ptr
  store ptr %hp1190, ptr %$t821.addr
  %hp1194 = call ptr @march_alloc(i64 24)
  %tgp1195 = getelementptr i8, ptr %hp1194, i64 8
  store i32 1, ptr %tgp1195, align 4
  %ld1196 = load ptr, ptr %$t821.addr
  %fp1197 = getelementptr i8, ptr %hp1194, i64 16
  store ptr %ld1196, ptr %fp1197, align 8
  store ptr %hp1194, ptr %res_slot1182
  br label %case_merge258
case_br261:
  %fp1198 = getelementptr i8, ptr %ld1181, i64 16
  %fv1199 = load ptr, ptr %fp1198, align 8
  %$f825.addr = alloca ptr
  store ptr %fv1199, ptr %$f825.addr
  %freed1200 = call i64 @march_decrc_freed(ptr %ld1181)
  %freed_b1201 = icmp ne i64 %freed1200, 0
  br i1 %freed_b1201, label %br_unique265, label %br_shared266
br_shared266:
  call void @march_incrc(ptr %fv1199)
  br label %br_body267
br_unique265:
  br label %br_body267
br_body267:
  %ld1202 = load ptr, ptr %$f825.addr
  %res_slot1203 = alloca ptr
  %sl1204 = call ptr @march_string_lit(ptr @.str30, i64 0)
  %seq1205 = call i64 @march_string_eq(ptr %ld1202, ptr %sl1204)
  %cmp1206 = icmp ne i64 %seq1205, 0
  br i1 %cmp1206, label %case_br270, label %str_next271
str_next271:
  br label %case_default269
case_br270:
  %ld1207 = load ptr, ptr %$f825.addr
  call void @march_decrc(ptr %ld1207)
  %cv1208 = inttoptr i64 0 to ptr
  %$t822.addr = alloca ptr
  store ptr %cv1208, ptr %$t822.addr
  %hp1209 = call ptr @march_alloc(i64 40)
  %tgp1210 = getelementptr i8, ptr %hp1209, i64 8
  store i32 0, ptr %tgp1210, align 4
  %ld1211 = load ptr, ptr %status_code.addr
  %fp1212 = getelementptr i8, ptr %hp1209, i64 16
  store ptr %ld1211, ptr %fp1212, align 8
  %ld1213 = load ptr, ptr %resp_headers.addr
  %fp1214 = getelementptr i8, ptr %hp1209, i64 24
  store ptr %ld1213, ptr %fp1214, align 8
  %ld1215 = load ptr, ptr %$t822.addr
  %fp1216 = getelementptr i8, ptr %hp1209, i64 32
  store ptr %ld1215, ptr %fp1216, align 8
  %$t823.addr = alloca ptr
  store ptr %hp1209, ptr %$t823.addr
  %hp1217 = call ptr @march_alloc(i64 24)
  %tgp1218 = getelementptr i8, ptr %hp1217, i64 8
  store i32 0, ptr %tgp1218, align 4
  %ld1219 = load ptr, ptr %$t823.addr
  %fp1220 = getelementptr i8, ptr %hp1217, i64 16
  store ptr %ld1219, ptr %fp1220, align 8
  store ptr %hp1217, ptr %res_slot1203
  br label %case_merge268
case_default269:
  %ld1221 = load ptr, ptr %$f825.addr
  %chunk.addr = alloca ptr
  store ptr %ld1221, ptr %chunk.addr
  %ld1222 = load ptr, ptr %on_chunk.addr
  %fp1223 = getelementptr i8, ptr %ld1222, i64 16
  %fv1224 = load ptr, ptr %fp1223, align 8
  %ld1225 = load ptr, ptr %chunk.addr
  %cr1226 = call ptr (ptr, ptr) %fv1224(ptr %ld1222, ptr %ld1225)
  %ld1227 = load ptr, ptr %fd.addr
  %ld1228 = load ptr, ptr %on_chunk.addr
  %ld1229 = load ptr, ptr %status_code.addr
  %ld1230 = load ptr, ptr %resp_headers.addr
  %cr1231 = call ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %ld1227, ptr %ld1228, ptr %ld1229, ptr %ld1230)
  store ptr %cr1231, ptr %res_slot1203
  br label %case_merge268
case_merge268:
  %case_r1232 = load ptr, ptr %res_slot1203
  store ptr %case_r1232, ptr %res_slot1182
  br label %case_merge258
case_default259:
  unreachable
case_merge258:
  %case_r1233 = load ptr, ptr %res_slot1182
  ret ptr %case_r1233
}

define ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %fd.arg, i64 %remaining.arg, ptr %on_chunk.arg, ptr %status_code.arg, ptr %resp_headers.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %remaining.addr = alloca i64
  store i64 %remaining.arg, ptr %remaining.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %status_code.addr = alloca ptr
  store ptr %status_code.arg, ptr %status_code.addr
  %resp_headers.addr = alloca ptr
  store ptr %resp_headers.arg, ptr %resp_headers.addr
  %ld1234 = load i64, ptr %remaining.addr
  %cmp1235 = icmp eq i64 %ld1234, 0
  %ar1236 = zext i1 %cmp1235 to i64
  %$t826.addr = alloca i64
  store i64 %ar1236, ptr %$t826.addr
  %ld1237 = load i64, ptr %$t826.addr
  %res_slot1238 = alloca ptr
  %bi1239 = trunc i64 %ld1237 to i1
  br i1 %bi1239, label %case_br274, label %case_default273
case_br274:
  %cv1240 = inttoptr i64 0 to ptr
  %$t827.addr = alloca ptr
  store ptr %cv1240, ptr %$t827.addr
  %hp1241 = call ptr @march_alloc(i64 40)
  %tgp1242 = getelementptr i8, ptr %hp1241, i64 8
  store i32 0, ptr %tgp1242, align 4
  %ld1243 = load ptr, ptr %status_code.addr
  %fp1244 = getelementptr i8, ptr %hp1241, i64 16
  store ptr %ld1243, ptr %fp1244, align 8
  %ld1245 = load ptr, ptr %resp_headers.addr
  %fp1246 = getelementptr i8, ptr %hp1241, i64 24
  store ptr %ld1245, ptr %fp1246, align 8
  %ld1247 = load ptr, ptr %$t827.addr
  %fp1248 = getelementptr i8, ptr %hp1241, i64 32
  store ptr %ld1247, ptr %fp1248, align 8
  %$t828.addr = alloca ptr
  store ptr %hp1241, ptr %$t828.addr
  %hp1249 = call ptr @march_alloc(i64 24)
  %tgp1250 = getelementptr i8, ptr %hp1249, i64 8
  store i32 0, ptr %tgp1250, align 4
  %ld1251 = load ptr, ptr %$t828.addr
  %fp1252 = getelementptr i8, ptr %hp1249, i64 16
  store ptr %ld1251, ptr %fp1252, align 8
  store ptr %hp1249, ptr %res_slot1238
  br label %case_merge272
case_default273:
  %ld1253 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1253)
  %ld1254 = load ptr, ptr %fd.addr
  %ld1255 = load i64, ptr %remaining.addr
  %cr1256 = call ptr @tcp_recv_chunk(ptr %ld1254, i64 %ld1255)
  %$t829.addr = alloca ptr
  store ptr %cr1256, ptr %$t829.addr
  %ld1257 = load ptr, ptr %$t829.addr
  %res_slot1258 = alloca ptr
  %tgp1259 = getelementptr i8, ptr %ld1257, i64 8
  %tag1260 = load i32, ptr %tgp1259, align 4
  switch i32 %tag1260, label %case_default276 [
      i32 1, label %case_br277
      i32 0, label %case_br278
  ]
case_br277:
  %fp1261 = getelementptr i8, ptr %ld1257, i64 16
  %fv1262 = load ptr, ptr %fp1261, align 8
  %$f835.addr = alloca ptr
  store ptr %fv1262, ptr %$f835.addr
  %freed1263 = call i64 @march_decrc_freed(ptr %ld1257)
  %freed_b1264 = icmp ne i64 %freed1263, 0
  br i1 %freed_b1264, label %br_unique279, label %br_shared280
br_shared280:
  call void @march_incrc(ptr %fv1262)
  br label %br_body281
br_unique279:
  br label %br_body281
br_body281:
  %ld1265 = load ptr, ptr %$f835.addr
  %msg.addr = alloca ptr
  store ptr %ld1265, ptr %msg.addr
  %hp1266 = call ptr @march_alloc(i64 24)
  %tgp1267 = getelementptr i8, ptr %hp1266, i64 8
  store i32 3, ptr %tgp1267, align 4
  %ld1268 = load ptr, ptr %msg.addr
  %fp1269 = getelementptr i8, ptr %hp1266, i64 16
  store ptr %ld1268, ptr %fp1269, align 8
  %$t830.addr = alloca ptr
  store ptr %hp1266, ptr %$t830.addr
  %hp1270 = call ptr @march_alloc(i64 24)
  %tgp1271 = getelementptr i8, ptr %hp1270, i64 8
  store i32 1, ptr %tgp1271, align 4
  %ld1272 = load ptr, ptr %$t830.addr
  %fp1273 = getelementptr i8, ptr %hp1270, i64 16
  store ptr %ld1272, ptr %fp1273, align 8
  store ptr %hp1270, ptr %res_slot1258
  br label %case_merge275
case_br278:
  %fp1274 = getelementptr i8, ptr %ld1257, i64 16
  %fv1275 = load ptr, ptr %fp1274, align 8
  %$f836.addr = alloca ptr
  store ptr %fv1275, ptr %$f836.addr
  %freed1276 = call i64 @march_decrc_freed(ptr %ld1257)
  %freed_b1277 = icmp ne i64 %freed1276, 0
  br i1 %freed_b1277, label %br_unique282, label %br_shared283
br_shared283:
  call void @march_incrc(ptr %fv1275)
  br label %br_body284
br_unique282:
  br label %br_body284
br_body284:
  %ld1278 = load ptr, ptr %$f836.addr
  %res_slot1279 = alloca ptr
  %sl1280 = call ptr @march_string_lit(ptr @.str31, i64 0)
  %seq1281 = call i64 @march_string_eq(ptr %ld1278, ptr %sl1280)
  %cmp1282 = icmp ne i64 %seq1281, 0
  br i1 %cmp1282, label %case_br287, label %str_next288
str_next288:
  br label %case_default286
case_br287:
  %ld1283 = load ptr, ptr %$f836.addr
  call void @march_decrc(ptr %ld1283)
  %cv1284 = inttoptr i64 0 to ptr
  %$t831.addr = alloca ptr
  store ptr %cv1284, ptr %$t831.addr
  %hp1285 = call ptr @march_alloc(i64 40)
  %tgp1286 = getelementptr i8, ptr %hp1285, i64 8
  store i32 0, ptr %tgp1286, align 4
  %ld1287 = load ptr, ptr %status_code.addr
  %fp1288 = getelementptr i8, ptr %hp1285, i64 16
  store ptr %ld1287, ptr %fp1288, align 8
  %ld1289 = load ptr, ptr %resp_headers.addr
  %fp1290 = getelementptr i8, ptr %hp1285, i64 24
  store ptr %ld1289, ptr %fp1290, align 8
  %ld1291 = load ptr, ptr %$t831.addr
  %fp1292 = getelementptr i8, ptr %hp1285, i64 32
  store ptr %ld1291, ptr %fp1292, align 8
  %$t832.addr = alloca ptr
  store ptr %hp1285, ptr %$t832.addr
  %hp1293 = call ptr @march_alloc(i64 24)
  %tgp1294 = getelementptr i8, ptr %hp1293, i64 8
  store i32 0, ptr %tgp1294, align 4
  %ld1295 = load ptr, ptr %$t832.addr
  %fp1296 = getelementptr i8, ptr %hp1293, i64 16
  store ptr %ld1295, ptr %fp1296, align 8
  store ptr %hp1293, ptr %res_slot1279
  br label %case_merge285
case_default286:
  %ld1297 = load ptr, ptr %$f836.addr
  %chunk.addr = alloca ptr
  store ptr %ld1297, ptr %chunk.addr
  %ld1298 = load ptr, ptr %chunk.addr
  call void @march_incrc(ptr %ld1298)
  %ld1299 = load ptr, ptr %on_chunk.addr
  %fp1300 = getelementptr i8, ptr %ld1299, i64 16
  %fv1301 = load ptr, ptr %fp1300, align 8
  %ld1302 = load ptr, ptr %chunk.addr
  %cr1303 = call ptr (ptr, ptr) %fv1301(ptr %ld1299, ptr %ld1302)
  %ld1304 = load ptr, ptr %chunk.addr
  %cr1305 = call i64 @string_length(ptr %ld1304)
  %$t833.addr = alloca i64
  store i64 %cr1305, ptr %$t833.addr
  %ld1306 = load i64, ptr %remaining.addr
  %ld1307 = load i64, ptr %$t833.addr
  %ar1308 = sub i64 %ld1306, %ld1307
  %$t834.addr = alloca i64
  store i64 %ar1308, ptr %$t834.addr
  %ld1309 = load ptr, ptr %fd.addr
  %ld1310 = load i64, ptr %$t834.addr
  %ld1311 = load ptr, ptr %on_chunk.addr
  %ld1312 = load ptr, ptr %status_code.addr
  %ld1313 = load ptr, ptr %resp_headers.addr
  %cr1314 = call ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %ld1309, i64 %ld1310, ptr %ld1311, ptr %ld1312, ptr %ld1313)
  store ptr %cr1314, ptr %res_slot1279
  br label %case_merge285
case_merge285:
  %case_r1315 = load ptr, ptr %res_slot1279
  store ptr %case_r1315, ptr %res_slot1258
  br label %case_merge275
case_default276:
  unreachable
case_merge275:
  %case_r1316 = load ptr, ptr %res_slot1258
  store ptr %case_r1316, ptr %res_slot1238
  br label %case_merge272
case_merge272:
  %case_r1317 = load ptr, ptr %res_slot1238
  ret ptr %case_r1317
}

define ptr @Http.body$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1318 = load ptr, ptr %req.addr
  %res_slot1319 = alloca ptr
  %tgp1320 = getelementptr i8, ptr %ld1318, i64 8
  %tag1321 = load i32, ptr %tgp1320, align 4
  switch i32 %tag1321, label %case_default290 [
      i32 0, label %case_br291
  ]
case_br291:
  %fp1322 = getelementptr i8, ptr %ld1318, i64 16
  %fv1323 = load ptr, ptr %fp1322, align 8
  %$f599.addr = alloca ptr
  store ptr %fv1323, ptr %$f599.addr
  %fp1324 = getelementptr i8, ptr %ld1318, i64 24
  %fv1325 = load ptr, ptr %fp1324, align 8
  %$f600.addr = alloca ptr
  store ptr %fv1325, ptr %$f600.addr
  %fp1326 = getelementptr i8, ptr %ld1318, i64 32
  %fv1327 = load ptr, ptr %fp1326, align 8
  %$f601.addr = alloca ptr
  store ptr %fv1327, ptr %$f601.addr
  %fp1328 = getelementptr i8, ptr %ld1318, i64 40
  %fv1329 = load ptr, ptr %fp1328, align 8
  %$f602.addr = alloca ptr
  store ptr %fv1329, ptr %$f602.addr
  %fp1330 = getelementptr i8, ptr %ld1318, i64 48
  %fv1331 = load ptr, ptr %fp1330, align 8
  %$f603.addr = alloca ptr
  store ptr %fv1331, ptr %$f603.addr
  %fp1332 = getelementptr i8, ptr %ld1318, i64 56
  %fv1333 = load ptr, ptr %fp1332, align 8
  %$f604.addr = alloca ptr
  store ptr %fv1333, ptr %$f604.addr
  %fp1334 = getelementptr i8, ptr %ld1318, i64 64
  %fv1335 = load ptr, ptr %fp1334, align 8
  %$f605.addr = alloca ptr
  store ptr %fv1335, ptr %$f605.addr
  %fp1336 = getelementptr i8, ptr %ld1318, i64 72
  %fv1337 = load ptr, ptr %fp1336, align 8
  %$f606.addr = alloca ptr
  store ptr %fv1337, ptr %$f606.addr
  %freed1338 = call i64 @march_decrc_freed(ptr %ld1318)
  %freed_b1339 = icmp ne i64 %freed1338, 0
  br i1 %freed_b1339, label %br_unique292, label %br_shared293
br_shared293:
  call void @march_incrc(ptr %fv1337)
  call void @march_incrc(ptr %fv1335)
  call void @march_incrc(ptr %fv1333)
  call void @march_incrc(ptr %fv1331)
  call void @march_incrc(ptr %fv1329)
  call void @march_incrc(ptr %fv1327)
  call void @march_incrc(ptr %fv1325)
  call void @march_incrc(ptr %fv1323)
  br label %br_body294
br_unique292:
  br label %br_body294
br_body294:
  %ld1340 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld1340, ptr %b.addr
  %ld1341 = load ptr, ptr %b.addr
  store ptr %ld1341, ptr %res_slot1319
  br label %case_merge289
case_default290:
  unreachable
case_merge289:
  %case_r1342 = load ptr, ptr %res_slot1319
  ret ptr %case_r1342
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1343 = load ptr, ptr %req.addr
  %res_slot1344 = alloca ptr
  %tgp1345 = getelementptr i8, ptr %ld1343, i64 8
  %tag1346 = load i32, ptr %tgp1345, align 4
  switch i32 %tag1346, label %case_default296 [
      i32 0, label %case_br297
  ]
case_br297:
  %fp1347 = getelementptr i8, ptr %ld1343, i64 16
  %fv1348 = load ptr, ptr %fp1347, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1348, ptr %$f591.addr
  %fp1349 = getelementptr i8, ptr %ld1343, i64 24
  %fv1350 = load ptr, ptr %fp1349, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1350, ptr %$f592.addr
  %fp1351 = getelementptr i8, ptr %ld1343, i64 32
  %fv1352 = load ptr, ptr %fp1351, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1352, ptr %$f593.addr
  %fp1353 = getelementptr i8, ptr %ld1343, i64 40
  %fv1354 = load ptr, ptr %fp1353, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1354, ptr %$f594.addr
  %fp1355 = getelementptr i8, ptr %ld1343, i64 48
  %fv1356 = load ptr, ptr %fp1355, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1356, ptr %$f595.addr
  %fp1357 = getelementptr i8, ptr %ld1343, i64 56
  %fv1358 = load ptr, ptr %fp1357, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1358, ptr %$f596.addr
  %fp1359 = getelementptr i8, ptr %ld1343, i64 64
  %fv1360 = load ptr, ptr %fp1359, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1360, ptr %$f597.addr
  %fp1361 = getelementptr i8, ptr %ld1343, i64 72
  %fv1362 = load ptr, ptr %fp1361, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1362, ptr %$f598.addr
  %freed1363 = call i64 @march_decrc_freed(ptr %ld1343)
  %freed_b1364 = icmp ne i64 %freed1363, 0
  br i1 %freed_b1364, label %br_unique298, label %br_shared299
br_shared299:
  call void @march_incrc(ptr %fv1362)
  call void @march_incrc(ptr %fv1360)
  call void @march_incrc(ptr %fv1358)
  call void @march_incrc(ptr %fv1356)
  call void @march_incrc(ptr %fv1354)
  call void @march_incrc(ptr %fv1352)
  call void @march_incrc(ptr %fv1350)
  call void @march_incrc(ptr %fv1348)
  br label %br_body300
br_unique298:
  br label %br_body300
br_body300:
  %ld1365 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1365, ptr %h.addr
  %ld1366 = load ptr, ptr %h.addr
  store ptr %ld1366, ptr %res_slot1344
  br label %case_merge295
case_default296:
  unreachable
case_merge295:
  %case_r1367 = load ptr, ptr %res_slot1344
  ret ptr %case_r1367
}

define ptr @Http.query$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1368 = load ptr, ptr %req.addr
  %res_slot1369 = alloca ptr
  %tgp1370 = getelementptr i8, ptr %ld1368, i64 8
  %tag1371 = load i32, ptr %tgp1370, align 4
  switch i32 %tag1371, label %case_default302 [
      i32 0, label %case_br303
  ]
case_br303:
  %fp1372 = getelementptr i8, ptr %ld1368, i64 16
  %fv1373 = load ptr, ptr %fp1372, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1373, ptr %$f583.addr
  %fp1374 = getelementptr i8, ptr %ld1368, i64 24
  %fv1375 = load ptr, ptr %fp1374, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1375, ptr %$f584.addr
  %fp1376 = getelementptr i8, ptr %ld1368, i64 32
  %fv1377 = load ptr, ptr %fp1376, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1377, ptr %$f585.addr
  %fp1378 = getelementptr i8, ptr %ld1368, i64 40
  %fv1379 = load ptr, ptr %fp1378, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1379, ptr %$f586.addr
  %fp1380 = getelementptr i8, ptr %ld1368, i64 48
  %fv1381 = load ptr, ptr %fp1380, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1381, ptr %$f587.addr
  %fp1382 = getelementptr i8, ptr %ld1368, i64 56
  %fv1383 = load ptr, ptr %fp1382, align 8
  %$f588.addr = alloca ptr
  store ptr %fv1383, ptr %$f588.addr
  %fp1384 = getelementptr i8, ptr %ld1368, i64 64
  %fv1385 = load ptr, ptr %fp1384, align 8
  %$f589.addr = alloca ptr
  store ptr %fv1385, ptr %$f589.addr
  %fp1386 = getelementptr i8, ptr %ld1368, i64 72
  %fv1387 = load ptr, ptr %fp1386, align 8
  %$f590.addr = alloca ptr
  store ptr %fv1387, ptr %$f590.addr
  %freed1388 = call i64 @march_decrc_freed(ptr %ld1368)
  %freed_b1389 = icmp ne i64 %freed1388, 0
  br i1 %freed_b1389, label %br_unique304, label %br_shared305
br_shared305:
  call void @march_incrc(ptr %fv1387)
  call void @march_incrc(ptr %fv1385)
  call void @march_incrc(ptr %fv1383)
  call void @march_incrc(ptr %fv1381)
  call void @march_incrc(ptr %fv1379)
  call void @march_incrc(ptr %fv1377)
  call void @march_incrc(ptr %fv1375)
  call void @march_incrc(ptr %fv1373)
  br label %br_body306
br_unique304:
  br label %br_body306
br_body306:
  %ld1390 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld1390, ptr %q.addr
  %ld1391 = load ptr, ptr %q.addr
  store ptr %ld1391, ptr %res_slot1369
  br label %case_merge301
case_default302:
  unreachable
case_merge301:
  %case_r1392 = load ptr, ptr %res_slot1369
  ret ptr %case_r1392
}

define ptr @Http.path$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1393 = load ptr, ptr %req.addr
  %res_slot1394 = alloca ptr
  %tgp1395 = getelementptr i8, ptr %ld1393, i64 8
  %tag1396 = load i32, ptr %tgp1395, align 4
  switch i32 %tag1396, label %case_default308 [
      i32 0, label %case_br309
  ]
case_br309:
  %fp1397 = getelementptr i8, ptr %ld1393, i64 16
  %fv1398 = load ptr, ptr %fp1397, align 8
  %$f575.addr = alloca ptr
  store ptr %fv1398, ptr %$f575.addr
  %fp1399 = getelementptr i8, ptr %ld1393, i64 24
  %fv1400 = load ptr, ptr %fp1399, align 8
  %$f576.addr = alloca ptr
  store ptr %fv1400, ptr %$f576.addr
  %fp1401 = getelementptr i8, ptr %ld1393, i64 32
  %fv1402 = load ptr, ptr %fp1401, align 8
  %$f577.addr = alloca ptr
  store ptr %fv1402, ptr %$f577.addr
  %fp1403 = getelementptr i8, ptr %ld1393, i64 40
  %fv1404 = load ptr, ptr %fp1403, align 8
  %$f578.addr = alloca ptr
  store ptr %fv1404, ptr %$f578.addr
  %fp1405 = getelementptr i8, ptr %ld1393, i64 48
  %fv1406 = load ptr, ptr %fp1405, align 8
  %$f579.addr = alloca ptr
  store ptr %fv1406, ptr %$f579.addr
  %fp1407 = getelementptr i8, ptr %ld1393, i64 56
  %fv1408 = load ptr, ptr %fp1407, align 8
  %$f580.addr = alloca ptr
  store ptr %fv1408, ptr %$f580.addr
  %fp1409 = getelementptr i8, ptr %ld1393, i64 64
  %fv1410 = load ptr, ptr %fp1409, align 8
  %$f581.addr = alloca ptr
  store ptr %fv1410, ptr %$f581.addr
  %fp1411 = getelementptr i8, ptr %ld1393, i64 72
  %fv1412 = load ptr, ptr %fp1411, align 8
  %$f582.addr = alloca ptr
  store ptr %fv1412, ptr %$f582.addr
  %freed1413 = call i64 @march_decrc_freed(ptr %ld1393)
  %freed_b1414 = icmp ne i64 %freed1413, 0
  br i1 %freed_b1414, label %br_unique310, label %br_shared311
br_shared311:
  call void @march_incrc(ptr %fv1412)
  call void @march_incrc(ptr %fv1410)
  call void @march_incrc(ptr %fv1408)
  call void @march_incrc(ptr %fv1406)
  call void @march_incrc(ptr %fv1404)
  call void @march_incrc(ptr %fv1402)
  call void @march_incrc(ptr %fv1400)
  call void @march_incrc(ptr %fv1398)
  br label %br_body312
br_unique310:
  br label %br_body312
br_body312:
  %ld1415 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld1415, ptr %p.addr
  %ld1416 = load ptr, ptr %p.addr
  store ptr %ld1416, ptr %res_slot1394
  br label %case_merge307
case_default308:
  unreachable
case_merge307:
  %case_r1417 = load ptr, ptr %res_slot1394
  ret ptr %case_r1417
}

define ptr @Http.host$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1418 = load ptr, ptr %req.addr
  %res_slot1419 = alloca ptr
  %tgp1420 = getelementptr i8, ptr %ld1418, i64 8
  %tag1421 = load i32, ptr %tgp1420, align 4
  switch i32 %tag1421, label %case_default314 [
      i32 0, label %case_br315
  ]
case_br315:
  %fp1422 = getelementptr i8, ptr %ld1418, i64 16
  %fv1423 = load ptr, ptr %fp1422, align 8
  %$f559.addr = alloca ptr
  store ptr %fv1423, ptr %$f559.addr
  %fp1424 = getelementptr i8, ptr %ld1418, i64 24
  %fv1425 = load ptr, ptr %fp1424, align 8
  %$f560.addr = alloca ptr
  store ptr %fv1425, ptr %$f560.addr
  %fp1426 = getelementptr i8, ptr %ld1418, i64 32
  %fv1427 = load ptr, ptr %fp1426, align 8
  %$f561.addr = alloca ptr
  store ptr %fv1427, ptr %$f561.addr
  %fp1428 = getelementptr i8, ptr %ld1418, i64 40
  %fv1429 = load ptr, ptr %fp1428, align 8
  %$f562.addr = alloca ptr
  store ptr %fv1429, ptr %$f562.addr
  %fp1430 = getelementptr i8, ptr %ld1418, i64 48
  %fv1431 = load ptr, ptr %fp1430, align 8
  %$f563.addr = alloca ptr
  store ptr %fv1431, ptr %$f563.addr
  %fp1432 = getelementptr i8, ptr %ld1418, i64 56
  %fv1433 = load ptr, ptr %fp1432, align 8
  %$f564.addr = alloca ptr
  store ptr %fv1433, ptr %$f564.addr
  %fp1434 = getelementptr i8, ptr %ld1418, i64 64
  %fv1435 = load ptr, ptr %fp1434, align 8
  %$f565.addr = alloca ptr
  store ptr %fv1435, ptr %$f565.addr
  %fp1436 = getelementptr i8, ptr %ld1418, i64 72
  %fv1437 = load ptr, ptr %fp1436, align 8
  %$f566.addr = alloca ptr
  store ptr %fv1437, ptr %$f566.addr
  %freed1438 = call i64 @march_decrc_freed(ptr %ld1418)
  %freed_b1439 = icmp ne i64 %freed1438, 0
  br i1 %freed_b1439, label %br_unique316, label %br_shared317
br_shared317:
  call void @march_incrc(ptr %fv1437)
  call void @march_incrc(ptr %fv1435)
  call void @march_incrc(ptr %fv1433)
  call void @march_incrc(ptr %fv1431)
  call void @march_incrc(ptr %fv1429)
  call void @march_incrc(ptr %fv1427)
  call void @march_incrc(ptr %fv1425)
  call void @march_incrc(ptr %fv1423)
  br label %br_body318
br_unique316:
  br label %br_body318
br_body318:
  %ld1440 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld1440, ptr %h.addr
  %ld1441 = load ptr, ptr %h.addr
  store ptr %ld1441, ptr %res_slot1419
  br label %case_merge313
case_default314:
  unreachable
case_merge313:
  %case_r1442 = load ptr, ptr %res_slot1419
  ret ptr %case_r1442
}

define ptr @Http.method$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1443 = load ptr, ptr %req.addr
  %res_slot1444 = alloca ptr
  %tgp1445 = getelementptr i8, ptr %ld1443, i64 8
  %tag1446 = load i32, ptr %tgp1445, align 4
  switch i32 %tag1446, label %case_default320 [
      i32 0, label %case_br321
  ]
case_br321:
  %fp1447 = getelementptr i8, ptr %ld1443, i64 16
  %fv1448 = load ptr, ptr %fp1447, align 8
  %$f543.addr = alloca ptr
  store ptr %fv1448, ptr %$f543.addr
  %fp1449 = getelementptr i8, ptr %ld1443, i64 24
  %fv1450 = load ptr, ptr %fp1449, align 8
  %$f544.addr = alloca ptr
  store ptr %fv1450, ptr %$f544.addr
  %fp1451 = getelementptr i8, ptr %ld1443, i64 32
  %fv1452 = load ptr, ptr %fp1451, align 8
  %$f545.addr = alloca ptr
  store ptr %fv1452, ptr %$f545.addr
  %fp1453 = getelementptr i8, ptr %ld1443, i64 40
  %fv1454 = load ptr, ptr %fp1453, align 8
  %$f546.addr = alloca ptr
  store ptr %fv1454, ptr %$f546.addr
  %fp1455 = getelementptr i8, ptr %ld1443, i64 48
  %fv1456 = load ptr, ptr %fp1455, align 8
  %$f547.addr = alloca ptr
  store ptr %fv1456, ptr %$f547.addr
  %fp1457 = getelementptr i8, ptr %ld1443, i64 56
  %fv1458 = load ptr, ptr %fp1457, align 8
  %$f548.addr = alloca ptr
  store ptr %fv1458, ptr %$f548.addr
  %fp1459 = getelementptr i8, ptr %ld1443, i64 64
  %fv1460 = load ptr, ptr %fp1459, align 8
  %$f549.addr = alloca ptr
  store ptr %fv1460, ptr %$f549.addr
  %fp1461 = getelementptr i8, ptr %ld1443, i64 72
  %fv1462 = load ptr, ptr %fp1461, align 8
  %$f550.addr = alloca ptr
  store ptr %fv1462, ptr %$f550.addr
  %freed1463 = call i64 @march_decrc_freed(ptr %ld1443)
  %freed_b1464 = icmp ne i64 %freed1463, 0
  br i1 %freed_b1464, label %br_unique322, label %br_shared323
br_shared323:
  call void @march_incrc(ptr %fv1462)
  call void @march_incrc(ptr %fv1460)
  call void @march_incrc(ptr %fv1458)
  call void @march_incrc(ptr %fv1456)
  call void @march_incrc(ptr %fv1454)
  call void @march_incrc(ptr %fv1452)
  call void @march_incrc(ptr %fv1450)
  call void @march_incrc(ptr %fv1448)
  br label %br_body324
br_unique322:
  br label %br_body324
br_body324:
  %ld1465 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld1465, ptr %m.addr
  %ld1466 = load ptr, ptr %m.addr
  store ptr %ld1466, ptr %res_slot1444
  br label %case_merge319
case_default320:
  unreachable
case_merge319:
  %case_r1467 = load ptr, ptr %res_slot1444
  ret ptr %case_r1467
}

define ptr @Http.port$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1468 = load ptr, ptr %req.addr
  %res_slot1469 = alloca ptr
  %tgp1470 = getelementptr i8, ptr %ld1468, i64 8
  %tag1471 = load i32, ptr %tgp1470, align 4
  switch i32 %tag1471, label %case_default326 [
      i32 0, label %case_br327
  ]
case_br327:
  %fp1472 = getelementptr i8, ptr %ld1468, i64 16
  %fv1473 = load ptr, ptr %fp1472, align 8
  %$f567.addr = alloca ptr
  store ptr %fv1473, ptr %$f567.addr
  %fp1474 = getelementptr i8, ptr %ld1468, i64 24
  %fv1475 = load ptr, ptr %fp1474, align 8
  %$f568.addr = alloca ptr
  store ptr %fv1475, ptr %$f568.addr
  %fp1476 = getelementptr i8, ptr %ld1468, i64 32
  %fv1477 = load ptr, ptr %fp1476, align 8
  %$f569.addr = alloca ptr
  store ptr %fv1477, ptr %$f569.addr
  %fp1478 = getelementptr i8, ptr %ld1468, i64 40
  %fv1479 = load ptr, ptr %fp1478, align 8
  %$f570.addr = alloca ptr
  store ptr %fv1479, ptr %$f570.addr
  %fp1480 = getelementptr i8, ptr %ld1468, i64 48
  %fv1481 = load ptr, ptr %fp1480, align 8
  %$f571.addr = alloca ptr
  store ptr %fv1481, ptr %$f571.addr
  %fp1482 = getelementptr i8, ptr %ld1468, i64 56
  %fv1483 = load ptr, ptr %fp1482, align 8
  %$f572.addr = alloca ptr
  store ptr %fv1483, ptr %$f572.addr
  %fp1484 = getelementptr i8, ptr %ld1468, i64 64
  %fv1485 = load ptr, ptr %fp1484, align 8
  %$f573.addr = alloca ptr
  store ptr %fv1485, ptr %$f573.addr
  %fp1486 = getelementptr i8, ptr %ld1468, i64 72
  %fv1487 = load ptr, ptr %fp1486, align 8
  %$f574.addr = alloca ptr
  store ptr %fv1487, ptr %$f574.addr
  %freed1488 = call i64 @march_decrc_freed(ptr %ld1468)
  %freed_b1489 = icmp ne i64 %freed1488, 0
  br i1 %freed_b1489, label %br_unique328, label %br_shared329
br_shared329:
  call void @march_incrc(ptr %fv1487)
  call void @march_incrc(ptr %fv1485)
  call void @march_incrc(ptr %fv1483)
  call void @march_incrc(ptr %fv1481)
  call void @march_incrc(ptr %fv1479)
  call void @march_incrc(ptr %fv1477)
  call void @march_incrc(ptr %fv1475)
  call void @march_incrc(ptr %fv1473)
  br label %br_body330
br_unique328:
  br label %br_body330
br_body330:
  %ld1490 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld1490, ptr %p.addr
  %ld1491 = load ptr, ptr %p.addr
  store ptr %ld1491, ptr %res_slot1469
  br label %case_merge325
case_default326:
  unreachable
case_merge325:
  %case_r1492 = load ptr, ptr %res_slot1469
  ret ptr %case_r1492
}

define ptr @on_chunk$apply$22(ptr %$clo.arg, ptr %chunk.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %chunk.addr = alloca ptr
  store ptr %chunk.arg, ptr %chunk.addr
  %ld1493 = load ptr, ptr %chunk.addr
  call void @march_incrc(ptr %ld1493)
  %ld1494 = load ptr, ptr %chunk.addr
  %cr1495 = call i64 @string_length(ptr %ld1494)
  %$t2009.addr = alloca i64
  store i64 %cr1495, ptr %$t2009.addr
  %ld1496 = load i64, ptr %$t2009.addr
  %cr1497 = call ptr @march_int_to_string(i64 %ld1496)
  %$t2010.addr = alloca ptr
  store ptr %cr1497, ptr %$t2010.addr
  %sl1498 = call ptr @march_string_lit(ptr @.str32, i64 7)
  %ld1499 = load ptr, ptr %$t2010.addr
  %cr1500 = call ptr @march_string_concat(ptr %sl1498, ptr %ld1499)
  %$t2011.addr = alloca ptr
  store ptr %cr1500, ptr %$t2011.addr
  %ld1501 = load ptr, ptr %$t2011.addr
  %sl1502 = call ptr @march_string_lit(ptr @.str33, i64 7)
  %cr1503 = call ptr @march_string_concat(ptr %ld1501, ptr %sl1502)
  %$t2012.addr = alloca ptr
  store ptr %cr1503, ptr %$t2012.addr
  %ld1504 = load ptr, ptr %$t2012.addr
  call void @march_print(ptr %ld1504)
  %ld1505 = load ptr, ptr %chunk.addr
  call void @march_print(ptr %ld1505)
  %cv1506 = inttoptr i64 0 to ptr
  ret ptr %cv1506
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @HttpClient.step_default_headers$clo_wrap(ptr %_clo, ptr %a0) {
entry:
  %r = call ptr @HttpClient.step_default_headers(ptr %a0)
  ret ptr %r
}

