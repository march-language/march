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
@.str17 = private unnamed_addr constant [27 x i8] c"Streaming 10KB response...\00"
@.str18 = private unnamed_addr constant [28 x i8] c"http://httpbin.org/stream/5\00"
@.str19 = private unnamed_addr constant [9 x i8] c"Status: \00"
@.str20 = private unnamed_addr constant [5 x i8] c"done\00"
@.str21 = private unnamed_addr constant [6 x i8] c"error\00"
@.str22 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str23 = private unnamed_addr constant [4 x i8] c"url\00"
@.str24 = private unnamed_addr constant [1 x i8] c"\00"
@.str25 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str26 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str27 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str28 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str29 = private unnamed_addr constant [1 x i8] c"\00"
@.str30 = private unnamed_addr constant [1 x i8] c"\00"
@.str31 = private unnamed_addr constant [9 x i8] c"[chunk: \00"
@.str32 = private unnamed_addr constant [8 x i8] c" bytes]\00"

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
  %sl375 = call ptr @march_string_lit(ptr @.str17, i64 26)
  call void @march_print(ptr %sl375)
  %hp376 = call ptr @march_alloc(i64 24)
  %tgp377 = getelementptr i8, ptr %hp376, i64 8
  store i32 0, ptr %tgp377, align 4
  %fp378 = getelementptr i8, ptr %hp376, i64 16
  store ptr @on_chunk$apply$22, ptr %fp378, align 8
  %on_chunk.addr = alloca ptr
  store ptr %hp376, ptr %on_chunk.addr
  %ld379 = load ptr, ptr %client_1.addr
  %sl380 = call ptr @march_string_lit(ptr @.str18, i64 27)
  %ld381 = load ptr, ptr %on_chunk.addr
  %cr382 = call ptr @HttpClient.stream_get(ptr %ld379, ptr %sl380, ptr %ld381)
  %$t2012.addr = alloca ptr
  store ptr %cr382, ptr %$t2012.addr
  %ld383 = load ptr, ptr %$t2012.addr
  %res_slot384 = alloca ptr
  %tgp385 = getelementptr i8, ptr %ld383, i64 8
  %tag386 = load i32, ptr %tgp385, align 4
  switch i32 %tag386, label %case_default75 [
      i32 0, label %case_br76
      i32 1, label %case_br77
  ]
case_br76:
  %fp387 = getelementptr i8, ptr %ld383, i64 16
  %fv388 = load ptr, ptr %fp387, align 8
  %$f2015.addr = alloca ptr
  store ptr %fv388, ptr %$f2015.addr
  %freed389 = call i64 @march_decrc_freed(ptr %ld383)
  %freed_b390 = icmp ne i64 %freed389, 0
  br i1 %freed_b390, label %br_unique78, label %br_shared79
br_shared79:
  call void @march_incrc(ptr %fv388)
  br label %br_body80
br_unique78:
  br label %br_body80
br_body80:
  %ld391 = load ptr, ptr %$f2015.addr
  %res_slot392 = alloca ptr
  %tgp393 = getelementptr i8, ptr %ld391, i64 8
  %tag394 = load i32, ptr %tgp393, align 4
  switch i32 %tag394, label %case_default82 [
      i32 0, label %case_br83
  ]
case_br83:
  %fp395 = getelementptr i8, ptr %ld391, i64 16
  %fv396 = load ptr, ptr %fp395, align 8
  %$f2016.addr = alloca ptr
  store ptr %fv396, ptr %$f2016.addr
  %fp397 = getelementptr i8, ptr %ld391, i64 24
  %fv398 = load ptr, ptr %fp397, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv398, ptr %$f2017.addr
  %fp399 = getelementptr i8, ptr %ld391, i64 32
  %fv400 = load ptr, ptr %fp399, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv400, ptr %$f2018.addr
  %freed401 = call i64 @march_decrc_freed(ptr %ld391)
  %freed_b402 = icmp ne i64 %freed401, 0
  br i1 %freed_b402, label %br_unique84, label %br_shared85
br_shared85:
  call void @march_incrc(ptr %fv400)
  call void @march_incrc(ptr %fv398)
  call void @march_incrc(ptr %fv396)
  br label %br_body86
br_unique84:
  br label %br_body86
br_body86:
  %ld403 = load ptr, ptr %$f2016.addr
  %status.addr = alloca ptr
  store ptr %ld403, ptr %status.addr
  %ld404 = load ptr, ptr %status.addr
  %cr405 = call ptr @march_int_to_string(ptr %ld404)
  %$t2013.addr = alloca ptr
  store ptr %cr405, ptr %$t2013.addr
  %sl406 = call ptr @march_string_lit(ptr @.str19, i64 8)
  %ld407 = load ptr, ptr %$t2013.addr
  %cr408 = call ptr @march_string_concat(ptr %sl406, ptr %ld407)
  %$t2014.addr = alloca ptr
  store ptr %cr408, ptr %$t2014.addr
  %ld409 = load ptr, ptr %$t2014.addr
  call void @march_print(ptr %ld409)
  %sl410 = call ptr @march_string_lit(ptr @.str20, i64 4)
  call void @march_print(ptr %sl410)
  %cv411 = inttoptr i64 0 to ptr
  store ptr %cv411, ptr %res_slot392
  br label %case_merge81
case_default82:
  unreachable
case_merge81:
  %case_r412 = load ptr, ptr %res_slot392
  store ptr %case_r412, ptr %res_slot384
  br label %case_merge74
case_br77:
  %fp413 = getelementptr i8, ptr %ld383, i64 16
  %fv414 = load ptr, ptr %fp413, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv414, ptr %$f2019.addr
  %freed415 = call i64 @march_decrc_freed(ptr %ld383)
  %freed_b416 = icmp ne i64 %freed415, 0
  br i1 %freed_b416, label %br_unique87, label %br_shared88
br_shared88:
  call void @march_incrc(ptr %fv414)
  br label %br_body89
br_unique87:
  br label %br_body89
br_body89:
  %sl417 = call ptr @march_string_lit(ptr @.str21, i64 5)
  call void @march_print(ptr %sl417)
  %cv418 = inttoptr i64 0 to ptr
  store ptr %cv418, ptr %res_slot384
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r419 = load ptr, ptr %res_slot384
  ret ptr %case_r419
}

define ptr @HttpClient.stream_get(ptr %client.arg, ptr %url.arg, ptr %on_chunk.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %ld420 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld420)
  %ld421 = load ptr, ptr %url.addr
  %url_i26.addr = alloca ptr
  store ptr %ld421, ptr %url_i26.addr
  %ld422 = load ptr, ptr %url_i26.addr
  %cr423 = call ptr @Http.parse_url(ptr %ld422)
  %$t1073.addr = alloca ptr
  store ptr %cr423, ptr %$t1073.addr
  %ld424 = load ptr, ptr %$t1073.addr
  %res_slot425 = alloca ptr
  %tgp426 = getelementptr i8, ptr %ld424, i64 8
  %tag427 = load i32, ptr %tgp426, align 4
  switch i32 %tag427, label %case_default91 [
      i32 1, label %case_br92
      i32 0, label %case_br93
  ]
case_br92:
  %fp428 = getelementptr i8, ptr %ld424, i64 16
  %fv429 = load ptr, ptr %fp428, align 8
  %$f1096.addr = alloca ptr
  store ptr %fv429, ptr %$f1096.addr
  %sl430 = call ptr @march_string_lit(ptr @.str22, i64 13)
  %ld431 = load ptr, ptr %url.addr
  %cr432 = call ptr @march_string_concat(ptr %sl430, ptr %ld431)
  %$t1074.addr = alloca ptr
  store ptr %cr432, ptr %$t1074.addr
  %hp433 = call ptr @march_alloc(i64 32)
  %tgp434 = getelementptr i8, ptr %hp433, i64 8
  store i32 1, ptr %tgp434, align 4
  %sl435 = call ptr @march_string_lit(ptr @.str23, i64 3)
  %fp436 = getelementptr i8, ptr %hp433, i64 16
  store ptr %sl435, ptr %fp436, align 8
  %ld437 = load ptr, ptr %$t1074.addr
  %fp438 = getelementptr i8, ptr %hp433, i64 24
  store ptr %ld437, ptr %fp438, align 8
  %$t1075.addr = alloca ptr
  store ptr %hp433, ptr %$t1075.addr
  %ld439 = load ptr, ptr %$t1073.addr
  %ld440 = load ptr, ptr %$t1075.addr
  %rc441 = load i64, ptr %ld439, align 8
  %uniq442 = icmp eq i64 %rc441, 1
  %fbip_slot443 = alloca ptr
  br i1 %uniq442, label %fbip_reuse94, label %fbip_fresh95
fbip_reuse94:
  %tgp444 = getelementptr i8, ptr %ld439, i64 8
  store i32 1, ptr %tgp444, align 4
  %fp445 = getelementptr i8, ptr %ld439, i64 16
  store ptr %ld440, ptr %fp445, align 8
  store ptr %ld439, ptr %fbip_slot443
  br label %fbip_merge96
fbip_fresh95:
  call void @march_decrc(ptr %ld439)
  %hp446 = call ptr @march_alloc(i64 24)
  %tgp447 = getelementptr i8, ptr %hp446, i64 8
  store i32 1, ptr %tgp447, align 4
  %fp448 = getelementptr i8, ptr %hp446, i64 16
  store ptr %ld440, ptr %fp448, align 8
  store ptr %hp446, ptr %fbip_slot443
  br label %fbip_merge96
fbip_merge96:
  %fbip_r449 = load ptr, ptr %fbip_slot443
  store ptr %fbip_r449, ptr %res_slot425
  br label %case_merge90
case_br93:
  %fp450 = getelementptr i8, ptr %ld424, i64 16
  %fv451 = load ptr, ptr %fp450, align 8
  %$f1097.addr = alloca ptr
  store ptr %fv451, ptr %$f1097.addr
  %freed452 = call i64 @march_decrc_freed(ptr %ld424)
  %freed_b453 = icmp ne i64 %freed452, 0
  br i1 %freed_b453, label %br_unique97, label %br_shared98
br_shared98:
  call void @march_incrc(ptr %fv451)
  br label %br_body99
br_unique97:
  br label %br_body99
br_body99:
  %ld454 = load ptr, ptr %$f1097.addr
  %req.addr = alloca ptr
  store ptr %ld454, ptr %req.addr
  %ld455 = load ptr, ptr %req.addr
  %sl456 = call ptr @march_string_lit(ptr @.str24, i64 0)
  %cr457 = call ptr @Http.set_body$Request_T_$String(ptr %ld455, ptr %sl456)
  %req_1.addr = alloca ptr
  store ptr %cr457, ptr %req_1.addr
  %ld458 = load ptr, ptr %client.addr
  %res_slot459 = alloca ptr
  %tgp460 = getelementptr i8, ptr %ld458, i64 8
  %tag461 = load i32, ptr %tgp460, align 4
  switch i32 %tag461, label %case_default101 [
      i32 0, label %case_br102
  ]
case_br102:
  %fp462 = getelementptr i8, ptr %ld458, i64 16
  %fv463 = load ptr, ptr %fp462, align 8
  %$f1090.addr = alloca ptr
  store ptr %fv463, ptr %$f1090.addr
  %fp464 = getelementptr i8, ptr %ld458, i64 24
  %fv465 = load ptr, ptr %fp464, align 8
  %$f1091.addr = alloca ptr
  store ptr %fv465, ptr %$f1091.addr
  %fp466 = getelementptr i8, ptr %ld458, i64 32
  %fv467 = load ptr, ptr %fp466, align 8
  %$f1092.addr = alloca ptr
  store ptr %fv467, ptr %$f1092.addr
  %fp468 = getelementptr i8, ptr %ld458, i64 40
  %fv469 = load i64, ptr %fp468, align 8
  %$f1093.addr = alloca i64
  store i64 %fv469, ptr %$f1093.addr
  %fp470 = getelementptr i8, ptr %ld458, i64 48
  %fv471 = load i64, ptr %fp470, align 8
  %$f1094.addr = alloca i64
  store i64 %fv471, ptr %$f1094.addr
  %fp472 = getelementptr i8, ptr %ld458, i64 56
  %fv473 = load i64, ptr %fp472, align 8
  %$f1095.addr = alloca i64
  store i64 %fv473, ptr %$f1095.addr
  %freed474 = call i64 @march_decrc_freed(ptr %ld458)
  %freed_b475 = icmp ne i64 %freed474, 0
  br i1 %freed_b475, label %br_unique103, label %br_shared104
br_shared104:
  call void @march_incrc(ptr %fv467)
  call void @march_incrc(ptr %fv465)
  call void @march_incrc(ptr %fv463)
  br label %br_body105
br_unique103:
  br label %br_body105
br_body105:
  %ld476 = load ptr, ptr %$f1090.addr
  %req_steps.addr = alloca ptr
  store ptr %ld476, ptr %req_steps.addr
  %ld477 = load ptr, ptr %req_steps.addr
  %ld478 = load ptr, ptr %req_1.addr
  %cr479 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld477, ptr %ld478)
  %$t1076.addr = alloca ptr
  store ptr %cr479, ptr %$t1076.addr
  %ld480 = load ptr, ptr %$t1076.addr
  %res_slot481 = alloca ptr
  %tgp482 = getelementptr i8, ptr %ld480, i64 8
  %tag483 = load i32, ptr %tgp482, align 4
  switch i32 %tag483, label %case_default107 [
      i32 1, label %case_br108
      i32 0, label %case_br109
  ]
case_br108:
  %fp484 = getelementptr i8, ptr %ld480, i64 16
  %fv485 = load ptr, ptr %fp484, align 8
  %$f1088.addr = alloca ptr
  store ptr %fv485, ptr %$f1088.addr
  %ld486 = load ptr, ptr %$f1088.addr
  %e.addr = alloca ptr
  store ptr %ld486, ptr %e.addr
  %ld487 = load ptr, ptr %$t1076.addr
  %ld488 = load ptr, ptr %e.addr
  %rc489 = load i64, ptr %ld487, align 8
  %uniq490 = icmp eq i64 %rc489, 1
  %fbip_slot491 = alloca ptr
  br i1 %uniq490, label %fbip_reuse110, label %fbip_fresh111
fbip_reuse110:
  %tgp492 = getelementptr i8, ptr %ld487, i64 8
  store i32 1, ptr %tgp492, align 4
  %fp493 = getelementptr i8, ptr %ld487, i64 16
  store ptr %ld488, ptr %fp493, align 8
  store ptr %ld487, ptr %fbip_slot491
  br label %fbip_merge112
fbip_fresh111:
  call void @march_decrc(ptr %ld487)
  %hp494 = call ptr @march_alloc(i64 24)
  %tgp495 = getelementptr i8, ptr %hp494, i64 8
  store i32 1, ptr %tgp495, align 4
  %fp496 = getelementptr i8, ptr %hp494, i64 16
  store ptr %ld488, ptr %fp496, align 8
  store ptr %hp494, ptr %fbip_slot491
  br label %fbip_merge112
fbip_merge112:
  %fbip_r497 = load ptr, ptr %fbip_slot491
  store ptr %fbip_r497, ptr %res_slot481
  br label %case_merge106
case_br109:
  %fp498 = getelementptr i8, ptr %ld480, i64 16
  %fv499 = load ptr, ptr %fp498, align 8
  %$f1089.addr = alloca ptr
  store ptr %fv499, ptr %$f1089.addr
  %freed500 = call i64 @march_decrc_freed(ptr %ld480)
  %freed_b501 = icmp ne i64 %freed500, 0
  br i1 %freed_b501, label %br_unique113, label %br_shared114
br_shared114:
  call void @march_incrc(ptr %fv499)
  br label %br_body115
br_unique113:
  br label %br_body115
br_body115:
  %ld502 = load ptr, ptr %$f1089.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld502, ptr %transformed_req.addr
  %ld503 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld503)
  %ld504 = load ptr, ptr %transformed_req.addr
  %cr505 = call ptr @HttpTransport.connect$Request_String(ptr %ld504)
  %$t1077.addr = alloca ptr
  store ptr %cr505, ptr %$t1077.addr
  %ld506 = load ptr, ptr %$t1077.addr
  %res_slot507 = alloca ptr
  %tgp508 = getelementptr i8, ptr %ld506, i64 8
  %tag509 = load i32, ptr %tgp508, align 4
  switch i32 %tag509, label %case_default117 [
      i32 1, label %case_br118
      i32 0, label %case_br119
  ]
case_br118:
  %fp510 = getelementptr i8, ptr %ld506, i64 16
  %fv511 = load ptr, ptr %fp510, align 8
  %$f1086.addr = alloca ptr
  store ptr %fv511, ptr %$f1086.addr
  %ld512 = load ptr, ptr %$f1086.addr
  %e_1.addr = alloca ptr
  store ptr %ld512, ptr %e_1.addr
  %hp513 = call ptr @march_alloc(i64 24)
  %tgp514 = getelementptr i8, ptr %hp513, i64 8
  store i32 0, ptr %tgp514, align 4
  %ld515 = load ptr, ptr %e_1.addr
  %fp516 = getelementptr i8, ptr %hp513, i64 16
  store ptr %ld515, ptr %fp516, align 8
  %$t1078.addr = alloca ptr
  store ptr %hp513, ptr %$t1078.addr
  %ld517 = load ptr, ptr %$t1077.addr
  %ld518 = load ptr, ptr %$t1078.addr
  %rc519 = load i64, ptr %ld517, align 8
  %uniq520 = icmp eq i64 %rc519, 1
  %fbip_slot521 = alloca ptr
  br i1 %uniq520, label %fbip_reuse120, label %fbip_fresh121
fbip_reuse120:
  %tgp522 = getelementptr i8, ptr %ld517, i64 8
  store i32 1, ptr %tgp522, align 4
  %fp523 = getelementptr i8, ptr %ld517, i64 16
  store ptr %ld518, ptr %fp523, align 8
  store ptr %ld517, ptr %fbip_slot521
  br label %fbip_merge122
fbip_fresh121:
  call void @march_decrc(ptr %ld517)
  %hp524 = call ptr @march_alloc(i64 24)
  %tgp525 = getelementptr i8, ptr %hp524, i64 8
  store i32 1, ptr %tgp525, align 4
  %fp526 = getelementptr i8, ptr %hp524, i64 16
  store ptr %ld518, ptr %fp526, align 8
  store ptr %hp524, ptr %fbip_slot521
  br label %fbip_merge122
fbip_merge122:
  %fbip_r527 = load ptr, ptr %fbip_slot521
  store ptr %fbip_r527, ptr %res_slot507
  br label %case_merge116
case_br119:
  %fp528 = getelementptr i8, ptr %ld506, i64 16
  %fv529 = load ptr, ptr %fp528, align 8
  %$f1087.addr = alloca ptr
  store ptr %fv529, ptr %$f1087.addr
  %freed530 = call i64 @march_decrc_freed(ptr %ld506)
  %freed_b531 = icmp ne i64 %freed530, 0
  br i1 %freed_b531, label %br_unique123, label %br_shared124
br_shared124:
  call void @march_incrc(ptr %fv529)
  br label %br_body125
br_unique123:
  br label %br_body125
br_body125:
  %ld532 = load ptr, ptr %$f1087.addr
  %fd.addr = alloca ptr
  store ptr %ld532, ptr %fd.addr
  %ld533 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld533)
  %ld534 = load ptr, ptr %fd.addr
  %ld535 = load ptr, ptr %transformed_req.addr
  %ld536 = load ptr, ptr %on_chunk.addr
  %cr537 = call ptr @HttpTransport.stream_request_on$V__2823$Request_String$Fn_String_T_(ptr %ld534, ptr %ld535, ptr %ld536)
  %result.addr = alloca ptr
  store ptr %cr537, ptr %result.addr
  %ld538 = load ptr, ptr %fd.addr
  %cr539 = call ptr @march_tcp_close(ptr %ld538)
  %ld540 = load ptr, ptr %result.addr
  %res_slot541 = alloca ptr
  %tgp542 = getelementptr i8, ptr %ld540, i64 8
  %tag543 = load i32, ptr %tgp542, align 4
  switch i32 %tag543, label %case_default127 [
      i32 1, label %case_br128
      i32 0, label %case_br129
  ]
case_br128:
  %fp544 = getelementptr i8, ptr %ld540, i64 16
  %fv545 = load ptr, ptr %fp544, align 8
  %$f1081.addr = alloca ptr
  store ptr %fv545, ptr %$f1081.addr
  %ld546 = load ptr, ptr %$f1081.addr
  %e_2.addr = alloca ptr
  store ptr %ld546, ptr %e_2.addr
  %hp547 = call ptr @march_alloc(i64 24)
  %tgp548 = getelementptr i8, ptr %hp547, i64 8
  store i32 0, ptr %tgp548, align 4
  %ld549 = load ptr, ptr %e_2.addr
  %fp550 = getelementptr i8, ptr %hp547, i64 16
  store ptr %ld549, ptr %fp550, align 8
  %$t1079.addr = alloca ptr
  store ptr %hp547, ptr %$t1079.addr
  %ld551 = load ptr, ptr %result.addr
  %ld552 = load ptr, ptr %$t1079.addr
  %rc553 = load i64, ptr %ld551, align 8
  %uniq554 = icmp eq i64 %rc553, 1
  %fbip_slot555 = alloca ptr
  br i1 %uniq554, label %fbip_reuse130, label %fbip_fresh131
fbip_reuse130:
  %tgp556 = getelementptr i8, ptr %ld551, i64 8
  store i32 1, ptr %tgp556, align 4
  %fp557 = getelementptr i8, ptr %ld551, i64 16
  store ptr %ld552, ptr %fp557, align 8
  store ptr %ld551, ptr %fbip_slot555
  br label %fbip_merge132
fbip_fresh131:
  call void @march_decrc(ptr %ld551)
  %hp558 = call ptr @march_alloc(i64 24)
  %tgp559 = getelementptr i8, ptr %hp558, i64 8
  store i32 1, ptr %tgp559, align 4
  %fp560 = getelementptr i8, ptr %hp558, i64 16
  store ptr %ld552, ptr %fp560, align 8
  store ptr %hp558, ptr %fbip_slot555
  br label %fbip_merge132
fbip_merge132:
  %fbip_r561 = load ptr, ptr %fbip_slot555
  store ptr %fbip_r561, ptr %res_slot541
  br label %case_merge126
case_br129:
  %fp562 = getelementptr i8, ptr %ld540, i64 16
  %fv563 = load ptr, ptr %fp562, align 8
  %$f1082.addr = alloca ptr
  store ptr %fv563, ptr %$f1082.addr
  %freed564 = call i64 @march_decrc_freed(ptr %ld540)
  %freed_b565 = icmp ne i64 %freed564, 0
  br i1 %freed_b565, label %br_unique133, label %br_shared134
br_shared134:
  call void @march_incrc(ptr %fv563)
  br label %br_body135
br_unique133:
  br label %br_body135
br_body135:
  %ld566 = load ptr, ptr %$f1082.addr
  %res_slot567 = alloca ptr
  %tgp568 = getelementptr i8, ptr %ld566, i64 8
  %tag569 = load i32, ptr %tgp568, align 4
  switch i32 %tag569, label %case_default137 [
      i32 0, label %case_br138
  ]
case_br138:
  %fp570 = getelementptr i8, ptr %ld566, i64 16
  %fv571 = load ptr, ptr %fp570, align 8
  %$f1083.addr = alloca ptr
  store ptr %fv571, ptr %$f1083.addr
  %fp572 = getelementptr i8, ptr %ld566, i64 24
  %fv573 = load ptr, ptr %fp572, align 8
  %$f1084.addr = alloca ptr
  store ptr %fv573, ptr %$f1084.addr
  %fp574 = getelementptr i8, ptr %ld566, i64 32
  %fv575 = load ptr, ptr %fp574, align 8
  %$f1085.addr = alloca ptr
  store ptr %fv575, ptr %$f1085.addr
  %freed576 = call i64 @march_decrc_freed(ptr %ld566)
  %freed_b577 = icmp ne i64 %freed576, 0
  br i1 %freed_b577, label %br_unique139, label %br_shared140
br_shared140:
  call void @march_incrc(ptr %fv575)
  call void @march_incrc(ptr %fv573)
  call void @march_incrc(ptr %fv571)
  br label %br_body141
br_unique139:
  br label %br_body141
br_body141:
  %ld578 = load ptr, ptr %$f1085.addr
  %last.addr = alloca ptr
  store ptr %ld578, ptr %last.addr
  %ld579 = load ptr, ptr %$f1084.addr
  %headers.addr = alloca ptr
  store ptr %ld579, ptr %headers.addr
  %ld580 = load ptr, ptr %$f1083.addr
  %status.addr = alloca ptr
  store ptr %ld580, ptr %status.addr
  %hp581 = call ptr @march_alloc(i64 40)
  %tgp582 = getelementptr i8, ptr %hp581, i64 8
  store i32 0, ptr %tgp582, align 4
  %ld583 = load ptr, ptr %status.addr
  %fp584 = getelementptr i8, ptr %hp581, i64 16
  store ptr %ld583, ptr %fp584, align 8
  %ld585 = load ptr, ptr %headers.addr
  %fp586 = getelementptr i8, ptr %hp581, i64 24
  store ptr %ld585, ptr %fp586, align 8
  %ld587 = load ptr, ptr %last.addr
  %fp588 = getelementptr i8, ptr %hp581, i64 32
  store ptr %ld587, ptr %fp588, align 8
  %$t1080.addr = alloca ptr
  store ptr %hp581, ptr %$t1080.addr
  %hp589 = call ptr @march_alloc(i64 24)
  %tgp590 = getelementptr i8, ptr %hp589, i64 8
  store i32 0, ptr %tgp590, align 4
  %ld591 = load ptr, ptr %$t1080.addr
  %fp592 = getelementptr i8, ptr %hp589, i64 16
  store ptr %ld591, ptr %fp592, align 8
  store ptr %hp589, ptr %res_slot567
  br label %case_merge136
case_default137:
  unreachable
case_merge136:
  %case_r593 = load ptr, ptr %res_slot567
  store ptr %case_r593, ptr %res_slot541
  br label %case_merge126
case_default127:
  unreachable
case_merge126:
  %case_r594 = load ptr, ptr %res_slot541
  store ptr %case_r594, ptr %res_slot507
  br label %case_merge116
case_default117:
  unreachable
case_merge116:
  %case_r595 = load ptr, ptr %res_slot507
  store ptr %case_r595, ptr %res_slot481
  br label %case_merge106
case_default107:
  unreachable
case_merge106:
  %case_r596 = load ptr, ptr %res_slot481
  store ptr %case_r596, ptr %res_slot459
  br label %case_merge100
case_default101:
  unreachable
case_merge100:
  %case_r597 = load ptr, ptr %res_slot459
  store ptr %case_r597, ptr %res_slot425
  br label %case_merge90
case_default91:
  unreachable
case_merge90:
  %case_r598 = load ptr, ptr %res_slot425
  ret ptr %case_r598
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld599 = load ptr, ptr %req.addr
  %sl600 = call ptr @march_string_lit(ptr @.str25, i64 10)
  %sl601 = call ptr @march_string_lit(ptr @.str26, i64 9)
  %cr602 = call ptr @Http.set_header$Request_V__3635$String$String(ptr %ld599, ptr %sl600, ptr %sl601)
  %req_1.addr = alloca ptr
  store ptr %cr602, ptr %req_1.addr
  %ld603 = load ptr, ptr %req_1.addr
  %sl604 = call ptr @march_string_lit(ptr @.str27, i64 6)
  %sl605 = call ptr @march_string_lit(ptr @.str28, i64 3)
  %cr606 = call ptr @Http.set_header$Request_V__3637$String$String(ptr %ld603, ptr %sl604, ptr %sl605)
  %req_2.addr = alloca ptr
  store ptr %cr606, ptr %req_2.addr
  %hp607 = call ptr @march_alloc(i64 24)
  %tgp608 = getelementptr i8, ptr %hp607, i64 8
  store i32 0, ptr %tgp608, align 4
  %ld609 = load ptr, ptr %req_2.addr
  %fp610 = getelementptr i8, ptr %hp607, i64 16
  store ptr %ld609, ptr %fp610, align 8
  ret ptr %hp607
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__6076_Result_Request_V__6075_V__6074(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld611 = load ptr, ptr %client.addr
  %res_slot612 = alloca ptr
  %tgp613 = getelementptr i8, ptr %ld611, i64 8
  %tag614 = load i32, ptr %tgp613, align 4
  switch i32 %tag614, label %case_default143 [
      i32 0, label %case_br144
  ]
case_br144:
  %fp615 = getelementptr i8, ptr %ld611, i64 16
  %fv616 = load ptr, ptr %fp615, align 8
  %$f889.addr = alloca ptr
  store ptr %fv616, ptr %$f889.addr
  %fp617 = getelementptr i8, ptr %ld611, i64 24
  %fv618 = load ptr, ptr %fp617, align 8
  %$f890.addr = alloca ptr
  store ptr %fv618, ptr %$f890.addr
  %fp619 = getelementptr i8, ptr %ld611, i64 32
  %fv620 = load ptr, ptr %fp619, align 8
  %$f891.addr = alloca ptr
  store ptr %fv620, ptr %$f891.addr
  %fp621 = getelementptr i8, ptr %ld611, i64 40
  %fv622 = load i64, ptr %fp621, align 8
  %$f892.addr = alloca i64
  store i64 %fv622, ptr %$f892.addr
  %fp623 = getelementptr i8, ptr %ld611, i64 48
  %fv624 = load i64, ptr %fp623, align 8
  %$f893.addr = alloca i64
  store i64 %fv624, ptr %$f893.addr
  %fp625 = getelementptr i8, ptr %ld611, i64 56
  %fv626 = load i64, ptr %fp625, align 8
  %$f894.addr = alloca i64
  store i64 %fv626, ptr %$f894.addr
  %ld627 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld627, ptr %backoff.addr
  %ld628 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld628, ptr %retries.addr
  %ld629 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld629, ptr %redir.addr
  %ld630 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld630, ptr %err_steps.addr
  %ld631 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld631, ptr %resp_steps.addr
  %ld632 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld632, ptr %req_steps.addr
  %hp633 = call ptr @march_alloc(i64 32)
  %tgp634 = getelementptr i8, ptr %hp633, i64 8
  store i32 0, ptr %tgp634, align 4
  %ld635 = load ptr, ptr %name.addr
  %fp636 = getelementptr i8, ptr %hp633, i64 16
  store ptr %ld635, ptr %fp636, align 8
  %ld637 = load ptr, ptr %step.addr
  %fp638 = getelementptr i8, ptr %hp633, i64 24
  store ptr %ld637, ptr %fp638, align 8
  %$t887.addr = alloca ptr
  store ptr %hp633, ptr %$t887.addr
  %ld639 = load ptr, ptr %req_steps.addr
  %ld640 = load ptr, ptr %$t887.addr
  %cr641 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld639, ptr %ld640)
  %$t888.addr = alloca ptr
  store ptr %cr641, ptr %$t888.addr
  %ld642 = load ptr, ptr %client.addr
  %ld643 = load ptr, ptr %$t888.addr
  %ld644 = load ptr, ptr %resp_steps.addr
  %ld645 = load ptr, ptr %err_steps.addr
  %ld646 = load i64, ptr %redir.addr
  %ld647 = load i64, ptr %retries.addr
  %ld648 = load i64, ptr %backoff.addr
  %rc649 = load i64, ptr %ld642, align 8
  %uniq650 = icmp eq i64 %rc649, 1
  %fbip_slot651 = alloca ptr
  br i1 %uniq650, label %fbip_reuse145, label %fbip_fresh146
fbip_reuse145:
  %tgp652 = getelementptr i8, ptr %ld642, i64 8
  store i32 0, ptr %tgp652, align 4
  %fp653 = getelementptr i8, ptr %ld642, i64 16
  store ptr %ld643, ptr %fp653, align 8
  %fp654 = getelementptr i8, ptr %ld642, i64 24
  store ptr %ld644, ptr %fp654, align 8
  %fp655 = getelementptr i8, ptr %ld642, i64 32
  store ptr %ld645, ptr %fp655, align 8
  %fp656 = getelementptr i8, ptr %ld642, i64 40
  store i64 %ld646, ptr %fp656, align 8
  %fp657 = getelementptr i8, ptr %ld642, i64 48
  store i64 %ld647, ptr %fp657, align 8
  %fp658 = getelementptr i8, ptr %ld642, i64 56
  store i64 %ld648, ptr %fp658, align 8
  store ptr %ld642, ptr %fbip_slot651
  br label %fbip_merge147
fbip_fresh146:
  call void @march_decrc(ptr %ld642)
  %hp659 = call ptr @march_alloc(i64 64)
  %tgp660 = getelementptr i8, ptr %hp659, i64 8
  store i32 0, ptr %tgp660, align 4
  %fp661 = getelementptr i8, ptr %hp659, i64 16
  store ptr %ld643, ptr %fp661, align 8
  %fp662 = getelementptr i8, ptr %hp659, i64 24
  store ptr %ld644, ptr %fp662, align 8
  %fp663 = getelementptr i8, ptr %hp659, i64 32
  store ptr %ld645, ptr %fp663, align 8
  %fp664 = getelementptr i8, ptr %hp659, i64 40
  store i64 %ld646, ptr %fp664, align 8
  %fp665 = getelementptr i8, ptr %hp659, i64 48
  store i64 %ld647, ptr %fp665, align 8
  %fp666 = getelementptr i8, ptr %hp659, i64 56
  store i64 %ld648, ptr %fp666, align 8
  store ptr %hp659, ptr %fbip_slot651
  br label %fbip_merge147
fbip_merge147:
  %fbip_r667 = load ptr, ptr %fbip_slot651
  store ptr %fbip_r667, ptr %res_slot612
  br label %case_merge142
case_default143:
  unreachable
case_merge142:
  %case_r668 = load ptr, ptr %res_slot612
  ret ptr %case_r668
}

define ptr @HttpTransport.stream_request_on$V__2823$Request_String$Fn_String_T_(ptr %fd.arg, ptr %req.arg, ptr %on_chunk.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %ld669 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld669)
  %ld670 = load ptr, ptr %req.addr
  %cr671 = call ptr @Http.method$Request_String(ptr %ld670)
  %$t801.addr = alloca ptr
  store ptr %cr671, ptr %$t801.addr
  %ld672 = load ptr, ptr %$t801.addr
  %cr673 = call ptr @Http.method_to_string(ptr %ld672)
  %meth.addr = alloca ptr
  store ptr %cr673, ptr %meth.addr
  %ld674 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld674)
  %ld675 = load ptr, ptr %req.addr
  %cr676 = call ptr @Http.host$Request_String(ptr %ld675)
  %req_host.addr = alloca ptr
  store ptr %cr676, ptr %req_host.addr
  %ld677 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld677)
  %ld678 = load ptr, ptr %req.addr
  %cr679 = call ptr @Http.path$Request_String(ptr %ld678)
  %req_path.addr = alloca ptr
  store ptr %cr679, ptr %req_path.addr
  %ld680 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld680)
  %ld681 = load ptr, ptr %req.addr
  %cr682 = call ptr @Http.query$Request_String(ptr %ld681)
  %req_query.addr = alloca ptr
  store ptr %cr682, ptr %req_query.addr
  %ld683 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld683)
  %ld684 = load ptr, ptr %req.addr
  %cr685 = call ptr @Http.headers$Request_String(ptr %ld684)
  %req_headers.addr = alloca ptr
  store ptr %cr685, ptr %req_headers.addr
  %ld686 = load ptr, ptr %req.addr
  %cr687 = call ptr @Http.body$Request_String(ptr %ld686)
  %req_body.addr = alloca ptr
  store ptr %cr687, ptr %req_body.addr
  %ld688 = load ptr, ptr %meth.addr
  %ld689 = load ptr, ptr %req_host.addr
  %ld690 = load ptr, ptr %req_path.addr
  %ld691 = load ptr, ptr %req_query.addr
  %ld692 = load ptr, ptr %req_headers.addr
  %ld693 = load ptr, ptr %req_body.addr
  %cr694 = call ptr @http_serialize_request(ptr %ld688, ptr %ld689, ptr %ld690, ptr %ld691, ptr %ld692, ptr %ld693)
  %raw_request.addr = alloca ptr
  store ptr %cr694, ptr %raw_request.addr
  %ld695 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld695)
  %ld696 = load ptr, ptr %fd.addr
  %ld697 = load ptr, ptr %raw_request.addr
  %cr698 = call ptr @march_tcp_send_all(ptr %ld696, ptr %ld697)
  %$t802.addr = alloca ptr
  store ptr %cr698, ptr %$t802.addr
  %ld699 = load ptr, ptr %$t802.addr
  %res_slot700 = alloca ptr
  %tgp701 = getelementptr i8, ptr %ld699, i64 8
  %tag702 = load i32, ptr %tgp701, align 4
  switch i32 %tag702, label %case_default149 [
      i32 1, label %case_br150
      i32 0, label %case_br151
  ]
case_br150:
  %fp703 = getelementptr i8, ptr %ld699, i64 16
  %fv704 = load ptr, ptr %fp703, align 8
  %$f818.addr = alloca ptr
  store ptr %fv704, ptr %$f818.addr
  %freed705 = call i64 @march_decrc_freed(ptr %ld699)
  %freed_b706 = icmp ne i64 %freed705, 0
  br i1 %freed_b706, label %br_unique152, label %br_shared153
br_shared153:
  call void @march_incrc(ptr %fv704)
  br label %br_body154
br_unique152:
  br label %br_body154
br_body154:
  %ld707 = load ptr, ptr %$f818.addr
  %msg.addr = alloca ptr
  store ptr %ld707, ptr %msg.addr
  %hp708 = call ptr @march_alloc(i64 24)
  %tgp709 = getelementptr i8, ptr %hp708, i64 8
  store i32 2, ptr %tgp709, align 4
  %ld710 = load ptr, ptr %msg.addr
  %fp711 = getelementptr i8, ptr %hp708, i64 16
  store ptr %ld710, ptr %fp711, align 8
  %$t803.addr = alloca ptr
  store ptr %hp708, ptr %$t803.addr
  %hp712 = call ptr @march_alloc(i64 24)
  %tgp713 = getelementptr i8, ptr %hp712, i64 8
  store i32 1, ptr %tgp713, align 4
  %ld714 = load ptr, ptr %$t803.addr
  %fp715 = getelementptr i8, ptr %hp712, i64 16
  store ptr %ld714, ptr %fp715, align 8
  store ptr %hp712, ptr %res_slot700
  br label %case_merge148
case_br151:
  %fp716 = getelementptr i8, ptr %ld699, i64 16
  %fv717 = load ptr, ptr %fp716, align 8
  %$f819.addr = alloca ptr
  store ptr %fv717, ptr %$f819.addr
  %freed718 = call i64 @march_decrc_freed(ptr %ld699)
  %freed_b719 = icmp ne i64 %freed718, 0
  br i1 %freed_b719, label %br_unique155, label %br_shared156
br_shared156:
  call void @march_incrc(ptr %fv717)
  br label %br_body157
br_unique155:
  br label %br_body157
br_body157:
  %ld720 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld720)
  %ld721 = load ptr, ptr %fd.addr
  %cr722 = call ptr @tcp_recv_http_headers(ptr %ld721)
  %$t804.addr = alloca ptr
  store ptr %cr722, ptr %$t804.addr
  %ld723 = load ptr, ptr %$t804.addr
  %res_slot724 = alloca ptr
  %tgp725 = getelementptr i8, ptr %ld723, i64 8
  %tag726 = load i32, ptr %tgp725, align 4
  switch i32 %tag726, label %case_default159 [
      i32 1, label %case_br160
      i32 0, label %case_br161
  ]
case_br160:
  %fp727 = getelementptr i8, ptr %ld723, i64 16
  %fv728 = load ptr, ptr %fp727, align 8
  %$f813.addr = alloca ptr
  store ptr %fv728, ptr %$f813.addr
  %freed729 = call i64 @march_decrc_freed(ptr %ld723)
  %freed_b730 = icmp ne i64 %freed729, 0
  br i1 %freed_b730, label %br_unique162, label %br_shared163
br_shared163:
  call void @march_incrc(ptr %fv728)
  br label %br_body164
br_unique162:
  br label %br_body164
br_body164:
  %ld731 = load ptr, ptr %$f813.addr
  %msg_1.addr = alloca ptr
  store ptr %ld731, ptr %msg_1.addr
  %hp732 = call ptr @march_alloc(i64 24)
  %tgp733 = getelementptr i8, ptr %hp732, i64 8
  store i32 3, ptr %tgp733, align 4
  %ld734 = load ptr, ptr %msg_1.addr
  %fp735 = getelementptr i8, ptr %hp732, i64 16
  store ptr %ld734, ptr %fp735, align 8
  %$t805.addr = alloca ptr
  store ptr %hp732, ptr %$t805.addr
  %hp736 = call ptr @march_alloc(i64 24)
  %tgp737 = getelementptr i8, ptr %hp736, i64 8
  store i32 1, ptr %tgp737, align 4
  %ld738 = load ptr, ptr %$t805.addr
  %fp739 = getelementptr i8, ptr %hp736, i64 16
  store ptr %ld738, ptr %fp739, align 8
  store ptr %hp736, ptr %res_slot724
  br label %case_merge158
case_br161:
  %fp740 = getelementptr i8, ptr %ld723, i64 16
  %fv741 = load ptr, ptr %fp740, align 8
  %$f814.addr = alloca ptr
  store ptr %fv741, ptr %$f814.addr
  %freed742 = call i64 @march_decrc_freed(ptr %ld723)
  %freed_b743 = icmp ne i64 %freed742, 0
  br i1 %freed_b743, label %br_unique165, label %br_shared166
br_shared166:
  call void @march_incrc(ptr %fv741)
  br label %br_body167
br_unique165:
  br label %br_body167
br_body167:
  %ld744 = load ptr, ptr %$f814.addr
  %res_slot745 = alloca ptr
  %tgp746 = getelementptr i8, ptr %ld744, i64 8
  %tag747 = load i32, ptr %tgp746, align 4
  switch i32 %tag747, label %case_default169 [
      i32 0, label %case_br170
  ]
case_br170:
  %fp748 = getelementptr i8, ptr %ld744, i64 16
  %fv749 = load ptr, ptr %fp748, align 8
  %$f815.addr = alloca ptr
  store ptr %fv749, ptr %$f815.addr
  %fp750 = getelementptr i8, ptr %ld744, i64 24
  %fv751 = load ptr, ptr %fp750, align 8
  %$f816.addr = alloca ptr
  store ptr %fv751, ptr %$f816.addr
  %fp752 = getelementptr i8, ptr %ld744, i64 32
  %fv753 = load ptr, ptr %fp752, align 8
  %$f817.addr = alloca ptr
  store ptr %fv753, ptr %$f817.addr
  %freed754 = call i64 @march_decrc_freed(ptr %ld744)
  %freed_b755 = icmp ne i64 %freed754, 0
  br i1 %freed_b755, label %br_unique171, label %br_shared172
br_shared172:
  call void @march_incrc(ptr %fv753)
  call void @march_incrc(ptr %fv751)
  call void @march_incrc(ptr %fv749)
  br label %br_body173
br_unique171:
  br label %br_body173
br_body173:
  %ld756 = load ptr, ptr %$f817.addr
  %is_chunked.addr = alloca ptr
  store ptr %ld756, ptr %is_chunked.addr
  %ld757 = load ptr, ptr %$f816.addr
  %content_length.addr = alloca ptr
  store ptr %ld757, ptr %content_length.addr
  %ld758 = load ptr, ptr %$f815.addr
  %headers_str.addr = alloca ptr
  store ptr %ld758, ptr %headers_str.addr
  %ld759 = load ptr, ptr %headers_str.addr
  %cr760 = call ptr @http_parse_response(ptr %ld759)
  %$t806.addr = alloca ptr
  store ptr %cr760, ptr %$t806.addr
  %ld761 = load ptr, ptr %$t806.addr
  %res_slot762 = alloca ptr
  %tgp763 = getelementptr i8, ptr %ld761, i64 8
  %tag764 = load i32, ptr %tgp763, align 4
  switch i32 %tag764, label %case_default175 [
      i32 1, label %case_br176
      i32 0, label %case_br177
  ]
case_br176:
  %fp765 = getelementptr i8, ptr %ld761, i64 16
  %fv766 = load ptr, ptr %fp765, align 8
  %$f808.addr = alloca ptr
  store ptr %fv766, ptr %$f808.addr
  %freed767 = call i64 @march_decrc_freed(ptr %ld761)
  %freed_b768 = icmp ne i64 %freed767, 0
  br i1 %freed_b768, label %br_unique178, label %br_shared179
br_shared179:
  call void @march_incrc(ptr %fv766)
  br label %br_body180
br_unique178:
  br label %br_body180
br_body180:
  %ld769 = load ptr, ptr %$f808.addr
  %msg_2.addr = alloca ptr
  store ptr %ld769, ptr %msg_2.addr
  %hp770 = call ptr @march_alloc(i64 24)
  %tgp771 = getelementptr i8, ptr %hp770, i64 8
  store i32 0, ptr %tgp771, align 4
  %ld772 = load ptr, ptr %msg_2.addr
  %fp773 = getelementptr i8, ptr %hp770, i64 16
  store ptr %ld772, ptr %fp773, align 8
  %$t807.addr = alloca ptr
  store ptr %hp770, ptr %$t807.addr
  %hp774 = call ptr @march_alloc(i64 24)
  %tgp775 = getelementptr i8, ptr %hp774, i64 8
  store i32 1, ptr %tgp775, align 4
  %ld776 = load ptr, ptr %$t807.addr
  %fp777 = getelementptr i8, ptr %hp774, i64 16
  store ptr %ld776, ptr %fp777, align 8
  store ptr %hp774, ptr %res_slot762
  br label %case_merge174
case_br177:
  %fp778 = getelementptr i8, ptr %ld761, i64 16
  %fv779 = load ptr, ptr %fp778, align 8
  %$f809.addr = alloca ptr
  store ptr %fv779, ptr %$f809.addr
  %freed780 = call i64 @march_decrc_freed(ptr %ld761)
  %freed_b781 = icmp ne i64 %freed780, 0
  br i1 %freed_b781, label %br_unique181, label %br_shared182
br_shared182:
  call void @march_incrc(ptr %fv779)
  br label %br_body183
br_unique181:
  br label %br_body183
br_body183:
  %ld782 = load ptr, ptr %$f809.addr
  %res_slot783 = alloca ptr
  %tgp784 = getelementptr i8, ptr %ld782, i64 8
  %tag785 = load i32, ptr %tgp784, align 4
  switch i32 %tag785, label %case_default185 [
      i32 0, label %case_br186
  ]
case_br186:
  %fp786 = getelementptr i8, ptr %ld782, i64 16
  %fv787 = load ptr, ptr %fp786, align 8
  %$f810.addr = alloca ptr
  store ptr %fv787, ptr %$f810.addr
  %fp788 = getelementptr i8, ptr %ld782, i64 24
  %fv789 = load ptr, ptr %fp788, align 8
  %$f811.addr = alloca ptr
  store ptr %fv789, ptr %$f811.addr
  %fp790 = getelementptr i8, ptr %ld782, i64 32
  %fv791 = load ptr, ptr %fp790, align 8
  %$f812.addr = alloca ptr
  store ptr %fv791, ptr %$f812.addr
  %freed792 = call i64 @march_decrc_freed(ptr %ld782)
  %freed_b793 = icmp ne i64 %freed792, 0
  br i1 %freed_b793, label %br_unique187, label %br_shared188
br_shared188:
  call void @march_incrc(ptr %fv791)
  call void @march_incrc(ptr %fv789)
  call void @march_incrc(ptr %fv787)
  br label %br_body189
br_unique187:
  br label %br_body189
br_body189:
  %ld794 = load ptr, ptr %$f811.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld794, ptr %resp_headers.addr
  %ld795 = load ptr, ptr %$f810.addr
  %status_code.addr = alloca ptr
  store ptr %ld795, ptr %status_code.addr
  %ld796 = load ptr, ptr %is_chunked.addr
  %res_slot797 = alloca ptr
  %bi798 = trunc i64 %ld796 to i1
  br i1 %bi798, label %case_br192, label %case_default191
case_br192:
  %ld799 = load ptr, ptr %fd.addr
  %ld800 = load ptr, ptr %on_chunk.addr
  %ld801 = load ptr, ptr %status_code.addr
  %ld802 = load ptr, ptr %resp_headers.addr
  %cr803 = call ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %ld799, ptr %ld800, ptr %ld801, ptr %ld802)
  store ptr %cr803, ptr %res_slot797
  br label %case_merge190
case_default191:
  %ld804 = load ptr, ptr %fd.addr
  %ld805 = load ptr, ptr %content_length.addr
  %ld806 = load ptr, ptr %on_chunk.addr
  %ld807 = load ptr, ptr %status_code.addr
  %ld808 = load ptr, ptr %resp_headers.addr
  %cr809 = call ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %ld804, ptr %ld805, ptr %ld806, ptr %ld807, ptr %ld808)
  store ptr %cr809, ptr %res_slot797
  br label %case_merge190
case_merge190:
  %case_r810 = load ptr, ptr %res_slot797
  store ptr %case_r810, ptr %res_slot783
  br label %case_merge184
case_default185:
  unreachable
case_merge184:
  %case_r811 = load ptr, ptr %res_slot783
  store ptr %case_r811, ptr %res_slot762
  br label %case_merge174
case_default175:
  unreachable
case_merge174:
  %case_r812 = load ptr, ptr %res_slot762
  store ptr %case_r812, ptr %res_slot745
  br label %case_merge168
case_default169:
  unreachable
case_merge168:
  %case_r813 = load ptr, ptr %res_slot745
  store ptr %case_r813, ptr %res_slot724
  br label %case_merge158
case_default159:
  unreachable
case_merge158:
  %case_r814 = load ptr, ptr %res_slot724
  store ptr %case_r814, ptr %res_slot700
  br label %case_merge148
case_default149:
  unreachable
case_merge148:
  %case_r815 = load ptr, ptr %res_slot700
  ret ptr %case_r815
}

define ptr @HttpTransport.connect$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld816 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld816)
  %ld817 = load ptr, ptr %req.addr
  %cr818 = call ptr @Http.host$Request_String(ptr %ld817)
  %req_host.addr = alloca ptr
  store ptr %cr818, ptr %req_host.addr
  %ld819 = load ptr, ptr %req.addr
  %cr820 = call ptr @Http.port$Request_String(ptr %ld819)
  %$t777.addr = alloca ptr
  store ptr %cr820, ptr %$t777.addr
  %ld821 = load ptr, ptr %$t777.addr
  %res_slot822 = alloca ptr
  %tgp823 = getelementptr i8, ptr %ld821, i64 8
  %tag824 = load i32, ptr %tgp823, align 4
  switch i32 %tag824, label %case_default194 [
      i32 1, label %case_br195
      i32 0, label %case_br196
  ]
case_br195:
  %fp825 = getelementptr i8, ptr %ld821, i64 16
  %fv826 = load ptr, ptr %fp825, align 8
  %$f778.addr = alloca ptr
  store ptr %fv826, ptr %$f778.addr
  %ld827 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld827)
  %ld828 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld828, ptr %p.addr
  %ld829 = load ptr, ptr %p.addr
  store ptr %ld829, ptr %res_slot822
  br label %case_merge193
case_br196:
  %ld830 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld830)
  %cv831 = inttoptr i64 80 to ptr
  store ptr %cv831, ptr %res_slot822
  br label %case_merge193
case_default194:
  unreachable
case_merge193:
  %case_r832 = load ptr, ptr %res_slot822
  %cv833 = ptrtoint ptr %case_r832 to i64
  %req_port.addr = alloca i64
  store i64 %cv833, ptr %req_port.addr
  %ld834 = load ptr, ptr %req_host.addr
  %ld835 = load i64, ptr %req_port.addr
  %cr836 = call ptr @tcp_connect(ptr %ld834, i64 %ld835)
  %$t779.addr = alloca ptr
  store ptr %cr836, ptr %$t779.addr
  %ld837 = load ptr, ptr %$t779.addr
  %res_slot838 = alloca ptr
  %tgp839 = getelementptr i8, ptr %ld837, i64 8
  %tag840 = load i32, ptr %tgp839, align 4
  switch i32 %tag840, label %case_default198 [
      i32 1, label %case_br199
      i32 0, label %case_br200
  ]
case_br199:
  %fp841 = getelementptr i8, ptr %ld837, i64 16
  %fv842 = load ptr, ptr %fp841, align 8
  %$f781.addr = alloca ptr
  store ptr %fv842, ptr %$f781.addr
  %freed843 = call i64 @march_decrc_freed(ptr %ld837)
  %freed_b844 = icmp ne i64 %freed843, 0
  br i1 %freed_b844, label %br_unique201, label %br_shared202
br_shared202:
  call void @march_incrc(ptr %fv842)
  br label %br_body203
br_unique201:
  br label %br_body203
br_body203:
  %ld845 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld845, ptr %msg.addr
  %hp846 = call ptr @march_alloc(i64 24)
  %tgp847 = getelementptr i8, ptr %hp846, i64 8
  store i32 0, ptr %tgp847, align 4
  %ld848 = load ptr, ptr %msg.addr
  %fp849 = getelementptr i8, ptr %hp846, i64 16
  store ptr %ld848, ptr %fp849, align 8
  %$t780.addr = alloca ptr
  store ptr %hp846, ptr %$t780.addr
  %hp850 = call ptr @march_alloc(i64 24)
  %tgp851 = getelementptr i8, ptr %hp850, i64 8
  store i32 1, ptr %tgp851, align 4
  %ld852 = load ptr, ptr %$t780.addr
  %fp853 = getelementptr i8, ptr %hp850, i64 16
  store ptr %ld852, ptr %fp853, align 8
  store ptr %hp850, ptr %res_slot838
  br label %case_merge197
case_br200:
  %fp854 = getelementptr i8, ptr %ld837, i64 16
  %fv855 = load ptr, ptr %fp854, align 8
  %$f782.addr = alloca ptr
  store ptr %fv855, ptr %$f782.addr
  %freed856 = call i64 @march_decrc_freed(ptr %ld837)
  %freed_b857 = icmp ne i64 %freed856, 0
  br i1 %freed_b857, label %br_unique204, label %br_shared205
br_shared205:
  call void @march_incrc(ptr %fv855)
  br label %br_body206
br_unique204:
  br label %br_body206
br_body206:
  %ld858 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld858, ptr %fd.addr
  %hp859 = call ptr @march_alloc(i64 24)
  %tgp860 = getelementptr i8, ptr %hp859, i64 8
  store i32 0, ptr %tgp860, align 4
  %ld861 = load ptr, ptr %fd.addr
  %fp862 = getelementptr i8, ptr %hp859, i64 16
  store ptr %ld861, ptr %fp862, align 8
  store ptr %hp859, ptr %res_slot838
  br label %case_merge197
case_default198:
  unreachable
case_merge197:
  %case_r863 = load ptr, ptr %res_slot838
  ret ptr %case_r863
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld864 = load ptr, ptr %steps.addr
  %res_slot865 = alloca ptr
  %tgp866 = getelementptr i8, ptr %ld864, i64 8
  %tag867 = load i32, ptr %tgp866, align 4
  switch i32 %tag867, label %case_default208 [
      i32 0, label %case_br209
      i32 1, label %case_br210
  ]
case_br209:
  %ld868 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld868)
  %hp869 = call ptr @march_alloc(i64 24)
  %tgp870 = getelementptr i8, ptr %hp869, i64 8
  store i32 0, ptr %tgp870, align 4
  %ld871 = load ptr, ptr %req.addr
  %fp872 = getelementptr i8, ptr %hp869, i64 16
  store ptr %ld871, ptr %fp872, align 8
  store ptr %hp869, ptr %res_slot865
  br label %case_merge207
case_br210:
  %fp873 = getelementptr i8, ptr %ld864, i64 16
  %fv874 = load ptr, ptr %fp873, align 8
  %$f957.addr = alloca ptr
  store ptr %fv874, ptr %$f957.addr
  %fp875 = getelementptr i8, ptr %ld864, i64 24
  %fv876 = load ptr, ptr %fp875, align 8
  %$f958.addr = alloca ptr
  store ptr %fv876, ptr %$f958.addr
  %freed877 = call i64 @march_decrc_freed(ptr %ld864)
  %freed_b878 = icmp ne i64 %freed877, 0
  br i1 %freed_b878, label %br_unique211, label %br_shared212
br_shared212:
  call void @march_incrc(ptr %fv876)
  call void @march_incrc(ptr %fv874)
  br label %br_body213
br_unique211:
  br label %br_body213
br_body213:
  %ld879 = load ptr, ptr %$f957.addr
  %res_slot880 = alloca ptr
  %tgp881 = getelementptr i8, ptr %ld879, i64 8
  %tag882 = load i32, ptr %tgp881, align 4
  switch i32 %tag882, label %case_default215 [
      i32 0, label %case_br216
  ]
case_br216:
  %fp883 = getelementptr i8, ptr %ld879, i64 16
  %fv884 = load ptr, ptr %fp883, align 8
  %$f959.addr = alloca ptr
  store ptr %fv884, ptr %$f959.addr
  %fp885 = getelementptr i8, ptr %ld879, i64 24
  %fv886 = load ptr, ptr %fp885, align 8
  %$f960.addr = alloca ptr
  store ptr %fv886, ptr %$f960.addr
  %freed887 = call i64 @march_decrc_freed(ptr %ld879)
  %freed_b888 = icmp ne i64 %freed887, 0
  br i1 %freed_b888, label %br_unique217, label %br_shared218
br_shared218:
  call void @march_incrc(ptr %fv886)
  call void @march_incrc(ptr %fv884)
  br label %br_body219
br_unique217:
  br label %br_body219
br_body219:
  %ld889 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld889, ptr %rest.addr
  %ld890 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld890, ptr %step_fn.addr
  %ld891 = load ptr, ptr %step_fn.addr
  %fp892 = getelementptr i8, ptr %ld891, i64 16
  %fv893 = load ptr, ptr %fp892, align 8
  %ld894 = load ptr, ptr %req.addr
  %cr895 = call ptr (ptr, ptr) %fv893(ptr %ld891, ptr %ld894)
  %$t954.addr = alloca ptr
  store ptr %cr895, ptr %$t954.addr
  %ld896 = load ptr, ptr %$t954.addr
  %res_slot897 = alloca ptr
  %tgp898 = getelementptr i8, ptr %ld896, i64 8
  %tag899 = load i32, ptr %tgp898, align 4
  switch i32 %tag899, label %case_default221 [
      i32 1, label %case_br222
      i32 0, label %case_br223
  ]
case_br222:
  %fp900 = getelementptr i8, ptr %ld896, i64 16
  %fv901 = load ptr, ptr %fp900, align 8
  %$f955.addr = alloca ptr
  store ptr %fv901, ptr %$f955.addr
  %ld902 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld902, ptr %e.addr
  %ld903 = load ptr, ptr %$t954.addr
  %ld904 = load ptr, ptr %e.addr
  %rc905 = load i64, ptr %ld903, align 8
  %uniq906 = icmp eq i64 %rc905, 1
  %fbip_slot907 = alloca ptr
  br i1 %uniq906, label %fbip_reuse224, label %fbip_fresh225
fbip_reuse224:
  %tgp908 = getelementptr i8, ptr %ld903, i64 8
  store i32 1, ptr %tgp908, align 4
  %fp909 = getelementptr i8, ptr %ld903, i64 16
  store ptr %ld904, ptr %fp909, align 8
  store ptr %ld903, ptr %fbip_slot907
  br label %fbip_merge226
fbip_fresh225:
  call void @march_decrc(ptr %ld903)
  %hp910 = call ptr @march_alloc(i64 24)
  %tgp911 = getelementptr i8, ptr %hp910, i64 8
  store i32 1, ptr %tgp911, align 4
  %fp912 = getelementptr i8, ptr %hp910, i64 16
  store ptr %ld904, ptr %fp912, align 8
  store ptr %hp910, ptr %fbip_slot907
  br label %fbip_merge226
fbip_merge226:
  %fbip_r913 = load ptr, ptr %fbip_slot907
  store ptr %fbip_r913, ptr %res_slot897
  br label %case_merge220
case_br223:
  %fp914 = getelementptr i8, ptr %ld896, i64 16
  %fv915 = load ptr, ptr %fp914, align 8
  %$f956.addr = alloca ptr
  store ptr %fv915, ptr %$f956.addr
  %freed916 = call i64 @march_decrc_freed(ptr %ld896)
  %freed_b917 = icmp ne i64 %freed916, 0
  br i1 %freed_b917, label %br_unique227, label %br_shared228
br_shared228:
  call void @march_incrc(ptr %fv915)
  br label %br_body229
br_unique227:
  br label %br_body229
br_body229:
  %ld918 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld918, ptr %new_req.addr
  %ld919 = load ptr, ptr %rest.addr
  %ld920 = load ptr, ptr %new_req.addr
  %cr921 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld919, ptr %ld920)
  store ptr %cr921, ptr %res_slot897
  br label %case_merge220
case_default221:
  unreachable
case_merge220:
  %case_r922 = load ptr, ptr %res_slot897
  store ptr %case_r922, ptr %res_slot880
  br label %case_merge214
case_default215:
  unreachable
case_merge214:
  %case_r923 = load ptr, ptr %res_slot880
  store ptr %case_r923, ptr %res_slot865
  br label %case_merge207
case_default208:
  unreachable
case_merge207:
  %case_r924 = load ptr, ptr %res_slot865
  ret ptr %case_r924
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld925 = load ptr, ptr %req.addr
  %res_slot926 = alloca ptr
  %tgp927 = getelementptr i8, ptr %ld925, i64 8
  %tag928 = load i32, ptr %tgp927, align 4
  switch i32 %tag928, label %case_default231 [
      i32 0, label %case_br232
  ]
case_br232:
  %fp929 = getelementptr i8, ptr %ld925, i64 16
  %fv930 = load ptr, ptr %fp929, align 8
  %$f648.addr = alloca ptr
  store ptr %fv930, ptr %$f648.addr
  %fp931 = getelementptr i8, ptr %ld925, i64 24
  %fv932 = load ptr, ptr %fp931, align 8
  %$f649.addr = alloca ptr
  store ptr %fv932, ptr %$f649.addr
  %fp933 = getelementptr i8, ptr %ld925, i64 32
  %fv934 = load ptr, ptr %fp933, align 8
  %$f650.addr = alloca ptr
  store ptr %fv934, ptr %$f650.addr
  %fp935 = getelementptr i8, ptr %ld925, i64 40
  %fv936 = load ptr, ptr %fp935, align 8
  %$f651.addr = alloca ptr
  store ptr %fv936, ptr %$f651.addr
  %fp937 = getelementptr i8, ptr %ld925, i64 48
  %fv938 = load ptr, ptr %fp937, align 8
  %$f652.addr = alloca ptr
  store ptr %fv938, ptr %$f652.addr
  %fp939 = getelementptr i8, ptr %ld925, i64 56
  %fv940 = load ptr, ptr %fp939, align 8
  %$f653.addr = alloca ptr
  store ptr %fv940, ptr %$f653.addr
  %fp941 = getelementptr i8, ptr %ld925, i64 64
  %fv942 = load ptr, ptr %fp941, align 8
  %$f654.addr = alloca ptr
  store ptr %fv942, ptr %$f654.addr
  %fp943 = getelementptr i8, ptr %ld925, i64 72
  %fv944 = load ptr, ptr %fp943, align 8
  %$f655.addr = alloca ptr
  store ptr %fv944, ptr %$f655.addr
  %ld945 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld945, ptr %hd.addr
  %ld946 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld946, ptr %q.addr
  %ld947 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld947, ptr %pa.addr
  %ld948 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld948, ptr %p.addr
  %ld949 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld949, ptr %h.addr
  %ld950 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld950, ptr %sc.addr
  %ld951 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld951, ptr %m.addr
  %ld952 = load ptr, ptr %req.addr
  %ld953 = load ptr, ptr %m.addr
  %ld954 = load ptr, ptr %sc.addr
  %ld955 = load ptr, ptr %h.addr
  %ld956 = load ptr, ptr %p.addr
  %ld957 = load ptr, ptr %pa.addr
  %ld958 = load ptr, ptr %q.addr
  %ld959 = load ptr, ptr %hd.addr
  %ld960 = load ptr, ptr %new_body.addr
  %rc961 = load i64, ptr %ld952, align 8
  %uniq962 = icmp eq i64 %rc961, 1
  %fbip_slot963 = alloca ptr
  br i1 %uniq962, label %fbip_reuse233, label %fbip_fresh234
fbip_reuse233:
  %tgp964 = getelementptr i8, ptr %ld952, i64 8
  store i32 0, ptr %tgp964, align 4
  %fp965 = getelementptr i8, ptr %ld952, i64 16
  store ptr %ld953, ptr %fp965, align 8
  %fp966 = getelementptr i8, ptr %ld952, i64 24
  store ptr %ld954, ptr %fp966, align 8
  %fp967 = getelementptr i8, ptr %ld952, i64 32
  store ptr %ld955, ptr %fp967, align 8
  %fp968 = getelementptr i8, ptr %ld952, i64 40
  store ptr %ld956, ptr %fp968, align 8
  %fp969 = getelementptr i8, ptr %ld952, i64 48
  store ptr %ld957, ptr %fp969, align 8
  %fp970 = getelementptr i8, ptr %ld952, i64 56
  store ptr %ld958, ptr %fp970, align 8
  %fp971 = getelementptr i8, ptr %ld952, i64 64
  store ptr %ld959, ptr %fp971, align 8
  %fp972 = getelementptr i8, ptr %ld952, i64 72
  store ptr %ld960, ptr %fp972, align 8
  store ptr %ld952, ptr %fbip_slot963
  br label %fbip_merge235
fbip_fresh234:
  call void @march_decrc(ptr %ld952)
  %hp973 = call ptr @march_alloc(i64 80)
  %tgp974 = getelementptr i8, ptr %hp973, i64 8
  store i32 0, ptr %tgp974, align 4
  %fp975 = getelementptr i8, ptr %hp973, i64 16
  store ptr %ld953, ptr %fp975, align 8
  %fp976 = getelementptr i8, ptr %hp973, i64 24
  store ptr %ld954, ptr %fp976, align 8
  %fp977 = getelementptr i8, ptr %hp973, i64 32
  store ptr %ld955, ptr %fp977, align 8
  %fp978 = getelementptr i8, ptr %hp973, i64 40
  store ptr %ld956, ptr %fp978, align 8
  %fp979 = getelementptr i8, ptr %hp973, i64 48
  store ptr %ld957, ptr %fp979, align 8
  %fp980 = getelementptr i8, ptr %hp973, i64 56
  store ptr %ld958, ptr %fp980, align 8
  %fp981 = getelementptr i8, ptr %hp973, i64 64
  store ptr %ld959, ptr %fp981, align 8
  %fp982 = getelementptr i8, ptr %hp973, i64 72
  store ptr %ld960, ptr %fp982, align 8
  store ptr %hp973, ptr %fbip_slot963
  br label %fbip_merge235
fbip_merge235:
  %fbip_r983 = load ptr, ptr %fbip_slot963
  store ptr %fbip_r983, ptr %res_slot926
  br label %case_merge230
case_default231:
  unreachable
case_merge230:
  %case_r984 = load ptr, ptr %res_slot926
  ret ptr %case_r984
}

define ptr @Http.set_header$Request_V__3637$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld985 = load ptr, ptr %req.addr
  %res_slot986 = alloca ptr
  %tgp987 = getelementptr i8, ptr %ld985, i64 8
  %tag988 = load i32, ptr %tgp987, align 4
  switch i32 %tag988, label %case_default237 [
      i32 0, label %case_br238
  ]
case_br238:
  %fp989 = getelementptr i8, ptr %ld985, i64 16
  %fv990 = load ptr, ptr %fp989, align 8
  %$f658.addr = alloca ptr
  store ptr %fv990, ptr %$f658.addr
  %fp991 = getelementptr i8, ptr %ld985, i64 24
  %fv992 = load ptr, ptr %fp991, align 8
  %$f659.addr = alloca ptr
  store ptr %fv992, ptr %$f659.addr
  %fp993 = getelementptr i8, ptr %ld985, i64 32
  %fv994 = load ptr, ptr %fp993, align 8
  %$f660.addr = alloca ptr
  store ptr %fv994, ptr %$f660.addr
  %fp995 = getelementptr i8, ptr %ld985, i64 40
  %fv996 = load ptr, ptr %fp995, align 8
  %$f661.addr = alloca ptr
  store ptr %fv996, ptr %$f661.addr
  %fp997 = getelementptr i8, ptr %ld985, i64 48
  %fv998 = load ptr, ptr %fp997, align 8
  %$f662.addr = alloca ptr
  store ptr %fv998, ptr %$f662.addr
  %fp999 = getelementptr i8, ptr %ld985, i64 56
  %fv1000 = load ptr, ptr %fp999, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1000, ptr %$f663.addr
  %fp1001 = getelementptr i8, ptr %ld985, i64 64
  %fv1002 = load ptr, ptr %fp1001, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1002, ptr %$f664.addr
  %fp1003 = getelementptr i8, ptr %ld985, i64 72
  %fv1004 = load ptr, ptr %fp1003, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1004, ptr %$f665.addr
  %ld1005 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1005, ptr %bd.addr
  %ld1006 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1006, ptr %hd.addr
  %ld1007 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1007, ptr %q.addr
  %ld1008 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1008, ptr %pa.addr
  %ld1009 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1009, ptr %p.addr
  %ld1010 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1010, ptr %h.addr
  %ld1011 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1011, ptr %sc.addr
  %ld1012 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1012, ptr %m.addr
  %hp1013 = call ptr @march_alloc(i64 32)
  %tgp1014 = getelementptr i8, ptr %hp1013, i64 8
  store i32 0, ptr %tgp1014, align 4
  %ld1015 = load ptr, ptr %name.addr
  %fp1016 = getelementptr i8, ptr %hp1013, i64 16
  store ptr %ld1015, ptr %fp1016, align 8
  %ld1017 = load ptr, ptr %value.addr
  %fp1018 = getelementptr i8, ptr %hp1013, i64 24
  store ptr %ld1017, ptr %fp1018, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1013, ptr %$t656.addr
  %hp1019 = call ptr @march_alloc(i64 32)
  %tgp1020 = getelementptr i8, ptr %hp1019, i64 8
  store i32 1, ptr %tgp1020, align 4
  %ld1021 = load ptr, ptr %$t656.addr
  %fp1022 = getelementptr i8, ptr %hp1019, i64 16
  store ptr %ld1021, ptr %fp1022, align 8
  %ld1023 = load ptr, ptr %hd.addr
  %fp1024 = getelementptr i8, ptr %hp1019, i64 24
  store ptr %ld1023, ptr %fp1024, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1019, ptr %$t657.addr
  %ld1025 = load ptr, ptr %req.addr
  %ld1026 = load ptr, ptr %m.addr
  %ld1027 = load ptr, ptr %sc.addr
  %ld1028 = load ptr, ptr %h.addr
  %ld1029 = load ptr, ptr %p.addr
  %ld1030 = load ptr, ptr %pa.addr
  %ld1031 = load ptr, ptr %q.addr
  %ld1032 = load ptr, ptr %$t657.addr
  %ld1033 = load ptr, ptr %bd.addr
  %rc1034 = load i64, ptr %ld1025, align 8
  %uniq1035 = icmp eq i64 %rc1034, 1
  %fbip_slot1036 = alloca ptr
  br i1 %uniq1035, label %fbip_reuse239, label %fbip_fresh240
fbip_reuse239:
  %tgp1037 = getelementptr i8, ptr %ld1025, i64 8
  store i32 0, ptr %tgp1037, align 4
  %fp1038 = getelementptr i8, ptr %ld1025, i64 16
  store ptr %ld1026, ptr %fp1038, align 8
  %fp1039 = getelementptr i8, ptr %ld1025, i64 24
  store ptr %ld1027, ptr %fp1039, align 8
  %fp1040 = getelementptr i8, ptr %ld1025, i64 32
  store ptr %ld1028, ptr %fp1040, align 8
  %fp1041 = getelementptr i8, ptr %ld1025, i64 40
  store ptr %ld1029, ptr %fp1041, align 8
  %fp1042 = getelementptr i8, ptr %ld1025, i64 48
  store ptr %ld1030, ptr %fp1042, align 8
  %fp1043 = getelementptr i8, ptr %ld1025, i64 56
  store ptr %ld1031, ptr %fp1043, align 8
  %fp1044 = getelementptr i8, ptr %ld1025, i64 64
  store ptr %ld1032, ptr %fp1044, align 8
  %fp1045 = getelementptr i8, ptr %ld1025, i64 72
  store ptr %ld1033, ptr %fp1045, align 8
  store ptr %ld1025, ptr %fbip_slot1036
  br label %fbip_merge241
fbip_fresh240:
  call void @march_decrc(ptr %ld1025)
  %hp1046 = call ptr @march_alloc(i64 80)
  %tgp1047 = getelementptr i8, ptr %hp1046, i64 8
  store i32 0, ptr %tgp1047, align 4
  %fp1048 = getelementptr i8, ptr %hp1046, i64 16
  store ptr %ld1026, ptr %fp1048, align 8
  %fp1049 = getelementptr i8, ptr %hp1046, i64 24
  store ptr %ld1027, ptr %fp1049, align 8
  %fp1050 = getelementptr i8, ptr %hp1046, i64 32
  store ptr %ld1028, ptr %fp1050, align 8
  %fp1051 = getelementptr i8, ptr %hp1046, i64 40
  store ptr %ld1029, ptr %fp1051, align 8
  %fp1052 = getelementptr i8, ptr %hp1046, i64 48
  store ptr %ld1030, ptr %fp1052, align 8
  %fp1053 = getelementptr i8, ptr %hp1046, i64 56
  store ptr %ld1031, ptr %fp1053, align 8
  %fp1054 = getelementptr i8, ptr %hp1046, i64 64
  store ptr %ld1032, ptr %fp1054, align 8
  %fp1055 = getelementptr i8, ptr %hp1046, i64 72
  store ptr %ld1033, ptr %fp1055, align 8
  store ptr %hp1046, ptr %fbip_slot1036
  br label %fbip_merge241
fbip_merge241:
  %fbip_r1056 = load ptr, ptr %fbip_slot1036
  store ptr %fbip_r1056, ptr %res_slot986
  br label %case_merge236
case_default237:
  unreachable
case_merge236:
  %case_r1057 = load ptr, ptr %res_slot986
  ret ptr %case_r1057
}

define ptr @Http.set_header$Request_V__3635$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1058 = load ptr, ptr %req.addr
  %res_slot1059 = alloca ptr
  %tgp1060 = getelementptr i8, ptr %ld1058, i64 8
  %tag1061 = load i32, ptr %tgp1060, align 4
  switch i32 %tag1061, label %case_default243 [
      i32 0, label %case_br244
  ]
case_br244:
  %fp1062 = getelementptr i8, ptr %ld1058, i64 16
  %fv1063 = load ptr, ptr %fp1062, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1063, ptr %$f658.addr
  %fp1064 = getelementptr i8, ptr %ld1058, i64 24
  %fv1065 = load ptr, ptr %fp1064, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1065, ptr %$f659.addr
  %fp1066 = getelementptr i8, ptr %ld1058, i64 32
  %fv1067 = load ptr, ptr %fp1066, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1067, ptr %$f660.addr
  %fp1068 = getelementptr i8, ptr %ld1058, i64 40
  %fv1069 = load ptr, ptr %fp1068, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1069, ptr %$f661.addr
  %fp1070 = getelementptr i8, ptr %ld1058, i64 48
  %fv1071 = load ptr, ptr %fp1070, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1071, ptr %$f662.addr
  %fp1072 = getelementptr i8, ptr %ld1058, i64 56
  %fv1073 = load ptr, ptr %fp1072, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1073, ptr %$f663.addr
  %fp1074 = getelementptr i8, ptr %ld1058, i64 64
  %fv1075 = load ptr, ptr %fp1074, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1075, ptr %$f664.addr
  %fp1076 = getelementptr i8, ptr %ld1058, i64 72
  %fv1077 = load ptr, ptr %fp1076, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1077, ptr %$f665.addr
  %ld1078 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1078, ptr %bd.addr
  %ld1079 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1079, ptr %hd.addr
  %ld1080 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1080, ptr %q.addr
  %ld1081 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1081, ptr %pa.addr
  %ld1082 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1082, ptr %p.addr
  %ld1083 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1083, ptr %h.addr
  %ld1084 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1084, ptr %sc.addr
  %ld1085 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1085, ptr %m.addr
  %hp1086 = call ptr @march_alloc(i64 32)
  %tgp1087 = getelementptr i8, ptr %hp1086, i64 8
  store i32 0, ptr %tgp1087, align 4
  %ld1088 = load ptr, ptr %name.addr
  %fp1089 = getelementptr i8, ptr %hp1086, i64 16
  store ptr %ld1088, ptr %fp1089, align 8
  %ld1090 = load ptr, ptr %value.addr
  %fp1091 = getelementptr i8, ptr %hp1086, i64 24
  store ptr %ld1090, ptr %fp1091, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1086, ptr %$t656.addr
  %hp1092 = call ptr @march_alloc(i64 32)
  %tgp1093 = getelementptr i8, ptr %hp1092, i64 8
  store i32 1, ptr %tgp1093, align 4
  %ld1094 = load ptr, ptr %$t656.addr
  %fp1095 = getelementptr i8, ptr %hp1092, i64 16
  store ptr %ld1094, ptr %fp1095, align 8
  %ld1096 = load ptr, ptr %hd.addr
  %fp1097 = getelementptr i8, ptr %hp1092, i64 24
  store ptr %ld1096, ptr %fp1097, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1092, ptr %$t657.addr
  %ld1098 = load ptr, ptr %req.addr
  %ld1099 = load ptr, ptr %m.addr
  %ld1100 = load ptr, ptr %sc.addr
  %ld1101 = load ptr, ptr %h.addr
  %ld1102 = load ptr, ptr %p.addr
  %ld1103 = load ptr, ptr %pa.addr
  %ld1104 = load ptr, ptr %q.addr
  %ld1105 = load ptr, ptr %$t657.addr
  %ld1106 = load ptr, ptr %bd.addr
  %rc1107 = load i64, ptr %ld1098, align 8
  %uniq1108 = icmp eq i64 %rc1107, 1
  %fbip_slot1109 = alloca ptr
  br i1 %uniq1108, label %fbip_reuse245, label %fbip_fresh246
fbip_reuse245:
  %tgp1110 = getelementptr i8, ptr %ld1098, i64 8
  store i32 0, ptr %tgp1110, align 4
  %fp1111 = getelementptr i8, ptr %ld1098, i64 16
  store ptr %ld1099, ptr %fp1111, align 8
  %fp1112 = getelementptr i8, ptr %ld1098, i64 24
  store ptr %ld1100, ptr %fp1112, align 8
  %fp1113 = getelementptr i8, ptr %ld1098, i64 32
  store ptr %ld1101, ptr %fp1113, align 8
  %fp1114 = getelementptr i8, ptr %ld1098, i64 40
  store ptr %ld1102, ptr %fp1114, align 8
  %fp1115 = getelementptr i8, ptr %ld1098, i64 48
  store ptr %ld1103, ptr %fp1115, align 8
  %fp1116 = getelementptr i8, ptr %ld1098, i64 56
  store ptr %ld1104, ptr %fp1116, align 8
  %fp1117 = getelementptr i8, ptr %ld1098, i64 64
  store ptr %ld1105, ptr %fp1117, align 8
  %fp1118 = getelementptr i8, ptr %ld1098, i64 72
  store ptr %ld1106, ptr %fp1118, align 8
  store ptr %ld1098, ptr %fbip_slot1109
  br label %fbip_merge247
fbip_fresh246:
  call void @march_decrc(ptr %ld1098)
  %hp1119 = call ptr @march_alloc(i64 80)
  %tgp1120 = getelementptr i8, ptr %hp1119, i64 8
  store i32 0, ptr %tgp1120, align 4
  %fp1121 = getelementptr i8, ptr %hp1119, i64 16
  store ptr %ld1099, ptr %fp1121, align 8
  %fp1122 = getelementptr i8, ptr %hp1119, i64 24
  store ptr %ld1100, ptr %fp1122, align 8
  %fp1123 = getelementptr i8, ptr %hp1119, i64 32
  store ptr %ld1101, ptr %fp1123, align 8
  %fp1124 = getelementptr i8, ptr %hp1119, i64 40
  store ptr %ld1102, ptr %fp1124, align 8
  %fp1125 = getelementptr i8, ptr %hp1119, i64 48
  store ptr %ld1103, ptr %fp1125, align 8
  %fp1126 = getelementptr i8, ptr %hp1119, i64 56
  store ptr %ld1104, ptr %fp1126, align 8
  %fp1127 = getelementptr i8, ptr %hp1119, i64 64
  store ptr %ld1105, ptr %fp1127, align 8
  %fp1128 = getelementptr i8, ptr %hp1119, i64 72
  store ptr %ld1106, ptr %fp1128, align 8
  store ptr %hp1119, ptr %fbip_slot1109
  br label %fbip_merge247
fbip_merge247:
  %fbip_r1129 = load ptr, ptr %fbip_slot1109
  store ptr %fbip_r1129, ptr %res_slot1059
  br label %case_merge242
case_default243:
  unreachable
case_merge242:
  %case_r1130 = load ptr, ptr %res_slot1059
  ret ptr %case_r1130
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld1131 = load ptr, ptr %xs.addr
  %res_slot1132 = alloca ptr
  %tgp1133 = getelementptr i8, ptr %ld1131, i64 8
  %tag1134 = load i32, ptr %tgp1133, align 4
  switch i32 %tag1134, label %case_default249 [
      i32 0, label %case_br250
      i32 1, label %case_br251
  ]
case_br250:
  %ld1135 = load ptr, ptr %xs.addr
  %rc1136 = load i64, ptr %ld1135, align 8
  %uniq1137 = icmp eq i64 %rc1136, 1
  %fbip_slot1138 = alloca ptr
  br i1 %uniq1137, label %fbip_reuse252, label %fbip_fresh253
fbip_reuse252:
  %tgp1139 = getelementptr i8, ptr %ld1135, i64 8
  store i32 0, ptr %tgp1139, align 4
  store ptr %ld1135, ptr %fbip_slot1138
  br label %fbip_merge254
fbip_fresh253:
  call void @march_decrc(ptr %ld1135)
  %hp1140 = call ptr @march_alloc(i64 16)
  %tgp1141 = getelementptr i8, ptr %hp1140, i64 8
  store i32 0, ptr %tgp1141, align 4
  store ptr %hp1140, ptr %fbip_slot1138
  br label %fbip_merge254
fbip_merge254:
  %fbip_r1142 = load ptr, ptr %fbip_slot1138
  %$t883.addr = alloca ptr
  store ptr %fbip_r1142, ptr %$t883.addr
  %hp1143 = call ptr @march_alloc(i64 32)
  %tgp1144 = getelementptr i8, ptr %hp1143, i64 8
  store i32 1, ptr %tgp1144, align 4
  %ld1145 = load ptr, ptr %x.addr
  %fp1146 = getelementptr i8, ptr %hp1143, i64 16
  store ptr %ld1145, ptr %fp1146, align 8
  %ld1147 = load ptr, ptr %$t883.addr
  %fp1148 = getelementptr i8, ptr %hp1143, i64 24
  store ptr %ld1147, ptr %fp1148, align 8
  store ptr %hp1143, ptr %res_slot1132
  br label %case_merge248
case_br251:
  %fp1149 = getelementptr i8, ptr %ld1131, i64 16
  %fv1150 = load ptr, ptr %fp1149, align 8
  %$f885.addr = alloca ptr
  store ptr %fv1150, ptr %$f885.addr
  %fp1151 = getelementptr i8, ptr %ld1131, i64 24
  %fv1152 = load ptr, ptr %fp1151, align 8
  %$f886.addr = alloca ptr
  store ptr %fv1152, ptr %$f886.addr
  %ld1153 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld1153, ptr %t.addr
  %ld1154 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld1154, ptr %h.addr
  %ld1155 = load ptr, ptr %t.addr
  %ld1156 = load ptr, ptr %x.addr
  %cr1157 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld1155, ptr %ld1156)
  %$t884.addr = alloca ptr
  store ptr %cr1157, ptr %$t884.addr
  %ld1158 = load ptr, ptr %xs.addr
  %ld1159 = load ptr, ptr %h.addr
  %ld1160 = load ptr, ptr %$t884.addr
  %rc1161 = load i64, ptr %ld1158, align 8
  %uniq1162 = icmp eq i64 %rc1161, 1
  %fbip_slot1163 = alloca ptr
  br i1 %uniq1162, label %fbip_reuse255, label %fbip_fresh256
fbip_reuse255:
  %tgp1164 = getelementptr i8, ptr %ld1158, i64 8
  store i32 1, ptr %tgp1164, align 4
  %fp1165 = getelementptr i8, ptr %ld1158, i64 16
  store ptr %ld1159, ptr %fp1165, align 8
  %fp1166 = getelementptr i8, ptr %ld1158, i64 24
  store ptr %ld1160, ptr %fp1166, align 8
  store ptr %ld1158, ptr %fbip_slot1163
  br label %fbip_merge257
fbip_fresh256:
  call void @march_decrc(ptr %ld1158)
  %hp1167 = call ptr @march_alloc(i64 32)
  %tgp1168 = getelementptr i8, ptr %hp1167, i64 8
  store i32 1, ptr %tgp1168, align 4
  %fp1169 = getelementptr i8, ptr %hp1167, i64 16
  store ptr %ld1159, ptr %fp1169, align 8
  %fp1170 = getelementptr i8, ptr %hp1167, i64 24
  store ptr %ld1160, ptr %fp1170, align 8
  store ptr %hp1167, ptr %fbip_slot1163
  br label %fbip_merge257
fbip_merge257:
  %fbip_r1171 = load ptr, ptr %fbip_slot1163
  store ptr %fbip_r1171, ptr %res_slot1132
  br label %case_merge248
case_default249:
  unreachable
case_merge248:
  %case_r1172 = load ptr, ptr %res_slot1132
  ret ptr %case_r1172
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
  %ld1173 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1173)
  %ld1174 = load ptr, ptr %fd.addr
  %cr1175 = call ptr @tcp_recv_chunked_frame(ptr %ld1174)
  %$t820.addr = alloca ptr
  store ptr %cr1175, ptr %$t820.addr
  %ld1176 = load ptr, ptr %$t820.addr
  %res_slot1177 = alloca ptr
  %tgp1178 = getelementptr i8, ptr %ld1176, i64 8
  %tag1179 = load i32, ptr %tgp1178, align 4
  switch i32 %tag1179, label %case_default259 [
      i32 1, label %case_br260
      i32 0, label %case_br261
  ]
case_br260:
  %fp1180 = getelementptr i8, ptr %ld1176, i64 16
  %fv1181 = load ptr, ptr %fp1180, align 8
  %$f824.addr = alloca ptr
  store ptr %fv1181, ptr %$f824.addr
  %freed1182 = call i64 @march_decrc_freed(ptr %ld1176)
  %freed_b1183 = icmp ne i64 %freed1182, 0
  br i1 %freed_b1183, label %br_unique262, label %br_shared263
br_shared263:
  call void @march_incrc(ptr %fv1181)
  br label %br_body264
br_unique262:
  br label %br_body264
br_body264:
  %ld1184 = load ptr, ptr %$f824.addr
  %msg.addr = alloca ptr
  store ptr %ld1184, ptr %msg.addr
  %hp1185 = call ptr @march_alloc(i64 24)
  %tgp1186 = getelementptr i8, ptr %hp1185, i64 8
  store i32 3, ptr %tgp1186, align 4
  %ld1187 = load ptr, ptr %msg.addr
  %fp1188 = getelementptr i8, ptr %hp1185, i64 16
  store ptr %ld1187, ptr %fp1188, align 8
  %$t821.addr = alloca ptr
  store ptr %hp1185, ptr %$t821.addr
  %hp1189 = call ptr @march_alloc(i64 24)
  %tgp1190 = getelementptr i8, ptr %hp1189, i64 8
  store i32 1, ptr %tgp1190, align 4
  %ld1191 = load ptr, ptr %$t821.addr
  %fp1192 = getelementptr i8, ptr %hp1189, i64 16
  store ptr %ld1191, ptr %fp1192, align 8
  store ptr %hp1189, ptr %res_slot1177
  br label %case_merge258
case_br261:
  %fp1193 = getelementptr i8, ptr %ld1176, i64 16
  %fv1194 = load ptr, ptr %fp1193, align 8
  %$f825.addr = alloca ptr
  store ptr %fv1194, ptr %$f825.addr
  %freed1195 = call i64 @march_decrc_freed(ptr %ld1176)
  %freed_b1196 = icmp ne i64 %freed1195, 0
  br i1 %freed_b1196, label %br_unique265, label %br_shared266
br_shared266:
  call void @march_incrc(ptr %fv1194)
  br label %br_body267
br_unique265:
  br label %br_body267
br_body267:
  %ld1197 = load ptr, ptr %$f825.addr
  %res_slot1198 = alloca ptr
  %sl1199 = call ptr @march_string_lit(ptr @.str29, i64 0)
  %seq1200 = call i64 @march_string_eq(ptr %ld1197, ptr %sl1199)
  %cmp1201 = icmp ne i64 %seq1200, 0
  br i1 %cmp1201, label %case_br270, label %str_next271
str_next271:
  br label %case_default269
case_br270:
  %ld1202 = load ptr, ptr %$f825.addr
  call void @march_decrc(ptr %ld1202)
  %cv1203 = inttoptr i64 0 to ptr
  %$t822.addr = alloca ptr
  store ptr %cv1203, ptr %$t822.addr
  %hp1204 = call ptr @march_alloc(i64 40)
  %tgp1205 = getelementptr i8, ptr %hp1204, i64 8
  store i32 0, ptr %tgp1205, align 4
  %ld1206 = load ptr, ptr %status_code.addr
  %fp1207 = getelementptr i8, ptr %hp1204, i64 16
  store ptr %ld1206, ptr %fp1207, align 8
  %ld1208 = load ptr, ptr %resp_headers.addr
  %fp1209 = getelementptr i8, ptr %hp1204, i64 24
  store ptr %ld1208, ptr %fp1209, align 8
  %ld1210 = load ptr, ptr %$t822.addr
  %fp1211 = getelementptr i8, ptr %hp1204, i64 32
  store ptr %ld1210, ptr %fp1211, align 8
  %$t823.addr = alloca ptr
  store ptr %hp1204, ptr %$t823.addr
  %hp1212 = call ptr @march_alloc(i64 24)
  %tgp1213 = getelementptr i8, ptr %hp1212, i64 8
  store i32 0, ptr %tgp1213, align 4
  %ld1214 = load ptr, ptr %$t823.addr
  %fp1215 = getelementptr i8, ptr %hp1212, i64 16
  store ptr %ld1214, ptr %fp1215, align 8
  store ptr %hp1212, ptr %res_slot1198
  br label %case_merge268
case_default269:
  %ld1216 = load ptr, ptr %$f825.addr
  %chunk.addr = alloca ptr
  store ptr %ld1216, ptr %chunk.addr
  %ld1217 = load ptr, ptr %on_chunk.addr
  %fp1218 = getelementptr i8, ptr %ld1217, i64 16
  %fv1219 = load ptr, ptr %fp1218, align 8
  %ld1220 = load ptr, ptr %chunk.addr
  %cr1221 = call ptr (ptr, ptr) %fv1219(ptr %ld1217, ptr %ld1220)
  %ld1222 = load ptr, ptr %fd.addr
  %ld1223 = load ptr, ptr %on_chunk.addr
  %ld1224 = load ptr, ptr %status_code.addr
  %ld1225 = load ptr, ptr %resp_headers.addr
  %cr1226 = call ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %ld1222, ptr %ld1223, ptr %ld1224, ptr %ld1225)
  store ptr %cr1226, ptr %res_slot1198
  br label %case_merge268
case_merge268:
  %case_r1227 = load ptr, ptr %res_slot1198
  store ptr %case_r1227, ptr %res_slot1177
  br label %case_merge258
case_default259:
  unreachable
case_merge258:
  %case_r1228 = load ptr, ptr %res_slot1177
  ret ptr %case_r1228
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
  %ld1229 = load i64, ptr %remaining.addr
  %cmp1230 = icmp eq i64 %ld1229, 0
  %ar1231 = zext i1 %cmp1230 to i64
  %$t826.addr = alloca i64
  store i64 %ar1231, ptr %$t826.addr
  %ld1232 = load i64, ptr %$t826.addr
  %res_slot1233 = alloca ptr
  %bi1234 = trunc i64 %ld1232 to i1
  br i1 %bi1234, label %case_br274, label %case_default273
case_br274:
  %cv1235 = inttoptr i64 0 to ptr
  %$t827.addr = alloca ptr
  store ptr %cv1235, ptr %$t827.addr
  %hp1236 = call ptr @march_alloc(i64 40)
  %tgp1237 = getelementptr i8, ptr %hp1236, i64 8
  store i32 0, ptr %tgp1237, align 4
  %ld1238 = load ptr, ptr %status_code.addr
  %fp1239 = getelementptr i8, ptr %hp1236, i64 16
  store ptr %ld1238, ptr %fp1239, align 8
  %ld1240 = load ptr, ptr %resp_headers.addr
  %fp1241 = getelementptr i8, ptr %hp1236, i64 24
  store ptr %ld1240, ptr %fp1241, align 8
  %ld1242 = load ptr, ptr %$t827.addr
  %fp1243 = getelementptr i8, ptr %hp1236, i64 32
  store ptr %ld1242, ptr %fp1243, align 8
  %$t828.addr = alloca ptr
  store ptr %hp1236, ptr %$t828.addr
  %hp1244 = call ptr @march_alloc(i64 24)
  %tgp1245 = getelementptr i8, ptr %hp1244, i64 8
  store i32 0, ptr %tgp1245, align 4
  %ld1246 = load ptr, ptr %$t828.addr
  %fp1247 = getelementptr i8, ptr %hp1244, i64 16
  store ptr %ld1246, ptr %fp1247, align 8
  store ptr %hp1244, ptr %res_slot1233
  br label %case_merge272
case_default273:
  %ld1248 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1248)
  %ld1249 = load ptr, ptr %fd.addr
  %ld1250 = load i64, ptr %remaining.addr
  %cr1251 = call ptr @tcp_recv_chunk(ptr %ld1249, i64 %ld1250)
  %$t829.addr = alloca ptr
  store ptr %cr1251, ptr %$t829.addr
  %ld1252 = load ptr, ptr %$t829.addr
  %res_slot1253 = alloca ptr
  %tgp1254 = getelementptr i8, ptr %ld1252, i64 8
  %tag1255 = load i32, ptr %tgp1254, align 4
  switch i32 %tag1255, label %case_default276 [
      i32 1, label %case_br277
      i32 0, label %case_br278
  ]
case_br277:
  %fp1256 = getelementptr i8, ptr %ld1252, i64 16
  %fv1257 = load ptr, ptr %fp1256, align 8
  %$f835.addr = alloca ptr
  store ptr %fv1257, ptr %$f835.addr
  %freed1258 = call i64 @march_decrc_freed(ptr %ld1252)
  %freed_b1259 = icmp ne i64 %freed1258, 0
  br i1 %freed_b1259, label %br_unique279, label %br_shared280
br_shared280:
  call void @march_incrc(ptr %fv1257)
  br label %br_body281
br_unique279:
  br label %br_body281
br_body281:
  %ld1260 = load ptr, ptr %$f835.addr
  %msg.addr = alloca ptr
  store ptr %ld1260, ptr %msg.addr
  %hp1261 = call ptr @march_alloc(i64 24)
  %tgp1262 = getelementptr i8, ptr %hp1261, i64 8
  store i32 3, ptr %tgp1262, align 4
  %ld1263 = load ptr, ptr %msg.addr
  %fp1264 = getelementptr i8, ptr %hp1261, i64 16
  store ptr %ld1263, ptr %fp1264, align 8
  %$t830.addr = alloca ptr
  store ptr %hp1261, ptr %$t830.addr
  %hp1265 = call ptr @march_alloc(i64 24)
  %tgp1266 = getelementptr i8, ptr %hp1265, i64 8
  store i32 1, ptr %tgp1266, align 4
  %ld1267 = load ptr, ptr %$t830.addr
  %fp1268 = getelementptr i8, ptr %hp1265, i64 16
  store ptr %ld1267, ptr %fp1268, align 8
  store ptr %hp1265, ptr %res_slot1253
  br label %case_merge275
case_br278:
  %fp1269 = getelementptr i8, ptr %ld1252, i64 16
  %fv1270 = load ptr, ptr %fp1269, align 8
  %$f836.addr = alloca ptr
  store ptr %fv1270, ptr %$f836.addr
  %freed1271 = call i64 @march_decrc_freed(ptr %ld1252)
  %freed_b1272 = icmp ne i64 %freed1271, 0
  br i1 %freed_b1272, label %br_unique282, label %br_shared283
br_shared283:
  call void @march_incrc(ptr %fv1270)
  br label %br_body284
br_unique282:
  br label %br_body284
br_body284:
  %ld1273 = load ptr, ptr %$f836.addr
  %res_slot1274 = alloca ptr
  %sl1275 = call ptr @march_string_lit(ptr @.str30, i64 0)
  %seq1276 = call i64 @march_string_eq(ptr %ld1273, ptr %sl1275)
  %cmp1277 = icmp ne i64 %seq1276, 0
  br i1 %cmp1277, label %case_br287, label %str_next288
str_next288:
  br label %case_default286
case_br287:
  %ld1278 = load ptr, ptr %$f836.addr
  call void @march_decrc(ptr %ld1278)
  %cv1279 = inttoptr i64 0 to ptr
  %$t831.addr = alloca ptr
  store ptr %cv1279, ptr %$t831.addr
  %hp1280 = call ptr @march_alloc(i64 40)
  %tgp1281 = getelementptr i8, ptr %hp1280, i64 8
  store i32 0, ptr %tgp1281, align 4
  %ld1282 = load ptr, ptr %status_code.addr
  %fp1283 = getelementptr i8, ptr %hp1280, i64 16
  store ptr %ld1282, ptr %fp1283, align 8
  %ld1284 = load ptr, ptr %resp_headers.addr
  %fp1285 = getelementptr i8, ptr %hp1280, i64 24
  store ptr %ld1284, ptr %fp1285, align 8
  %ld1286 = load ptr, ptr %$t831.addr
  %fp1287 = getelementptr i8, ptr %hp1280, i64 32
  store ptr %ld1286, ptr %fp1287, align 8
  %$t832.addr = alloca ptr
  store ptr %hp1280, ptr %$t832.addr
  %hp1288 = call ptr @march_alloc(i64 24)
  %tgp1289 = getelementptr i8, ptr %hp1288, i64 8
  store i32 0, ptr %tgp1289, align 4
  %ld1290 = load ptr, ptr %$t832.addr
  %fp1291 = getelementptr i8, ptr %hp1288, i64 16
  store ptr %ld1290, ptr %fp1291, align 8
  store ptr %hp1288, ptr %res_slot1274
  br label %case_merge285
case_default286:
  %ld1292 = load ptr, ptr %$f836.addr
  %chunk.addr = alloca ptr
  store ptr %ld1292, ptr %chunk.addr
  %ld1293 = load ptr, ptr %chunk.addr
  call void @march_incrc(ptr %ld1293)
  %ld1294 = load ptr, ptr %on_chunk.addr
  %fp1295 = getelementptr i8, ptr %ld1294, i64 16
  %fv1296 = load ptr, ptr %fp1295, align 8
  %ld1297 = load ptr, ptr %chunk.addr
  %cr1298 = call ptr (ptr, ptr) %fv1296(ptr %ld1294, ptr %ld1297)
  %ld1299 = load ptr, ptr %chunk.addr
  %cr1300 = call i64 @string_length(ptr %ld1299)
  %$t833.addr = alloca i64
  store i64 %cr1300, ptr %$t833.addr
  %ld1301 = load i64, ptr %remaining.addr
  %ld1302 = load i64, ptr %$t833.addr
  %ar1303 = sub i64 %ld1301, %ld1302
  %$t834.addr = alloca i64
  store i64 %ar1303, ptr %$t834.addr
  %ld1304 = load ptr, ptr %fd.addr
  %ld1305 = load i64, ptr %$t834.addr
  %ld1306 = load ptr, ptr %on_chunk.addr
  %ld1307 = load ptr, ptr %status_code.addr
  %ld1308 = load ptr, ptr %resp_headers.addr
  %cr1309 = call ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %ld1304, i64 %ld1305, ptr %ld1306, ptr %ld1307, ptr %ld1308)
  store ptr %cr1309, ptr %res_slot1274
  br label %case_merge285
case_merge285:
  %case_r1310 = load ptr, ptr %res_slot1274
  store ptr %case_r1310, ptr %res_slot1253
  br label %case_merge275
case_default276:
  unreachable
case_merge275:
  %case_r1311 = load ptr, ptr %res_slot1253
  store ptr %case_r1311, ptr %res_slot1233
  br label %case_merge272
case_merge272:
  %case_r1312 = load ptr, ptr %res_slot1233
  ret ptr %case_r1312
}

define ptr @Http.body$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1313 = load ptr, ptr %req.addr
  %res_slot1314 = alloca ptr
  %tgp1315 = getelementptr i8, ptr %ld1313, i64 8
  %tag1316 = load i32, ptr %tgp1315, align 4
  switch i32 %tag1316, label %case_default290 [
      i32 0, label %case_br291
  ]
case_br291:
  %fp1317 = getelementptr i8, ptr %ld1313, i64 16
  %fv1318 = load ptr, ptr %fp1317, align 8
  %$f599.addr = alloca ptr
  store ptr %fv1318, ptr %$f599.addr
  %fp1319 = getelementptr i8, ptr %ld1313, i64 24
  %fv1320 = load ptr, ptr %fp1319, align 8
  %$f600.addr = alloca ptr
  store ptr %fv1320, ptr %$f600.addr
  %fp1321 = getelementptr i8, ptr %ld1313, i64 32
  %fv1322 = load ptr, ptr %fp1321, align 8
  %$f601.addr = alloca ptr
  store ptr %fv1322, ptr %$f601.addr
  %fp1323 = getelementptr i8, ptr %ld1313, i64 40
  %fv1324 = load ptr, ptr %fp1323, align 8
  %$f602.addr = alloca ptr
  store ptr %fv1324, ptr %$f602.addr
  %fp1325 = getelementptr i8, ptr %ld1313, i64 48
  %fv1326 = load ptr, ptr %fp1325, align 8
  %$f603.addr = alloca ptr
  store ptr %fv1326, ptr %$f603.addr
  %fp1327 = getelementptr i8, ptr %ld1313, i64 56
  %fv1328 = load ptr, ptr %fp1327, align 8
  %$f604.addr = alloca ptr
  store ptr %fv1328, ptr %$f604.addr
  %fp1329 = getelementptr i8, ptr %ld1313, i64 64
  %fv1330 = load ptr, ptr %fp1329, align 8
  %$f605.addr = alloca ptr
  store ptr %fv1330, ptr %$f605.addr
  %fp1331 = getelementptr i8, ptr %ld1313, i64 72
  %fv1332 = load ptr, ptr %fp1331, align 8
  %$f606.addr = alloca ptr
  store ptr %fv1332, ptr %$f606.addr
  %freed1333 = call i64 @march_decrc_freed(ptr %ld1313)
  %freed_b1334 = icmp ne i64 %freed1333, 0
  br i1 %freed_b1334, label %br_unique292, label %br_shared293
br_shared293:
  call void @march_incrc(ptr %fv1332)
  call void @march_incrc(ptr %fv1330)
  call void @march_incrc(ptr %fv1328)
  call void @march_incrc(ptr %fv1326)
  call void @march_incrc(ptr %fv1324)
  call void @march_incrc(ptr %fv1322)
  call void @march_incrc(ptr %fv1320)
  call void @march_incrc(ptr %fv1318)
  br label %br_body294
br_unique292:
  br label %br_body294
br_body294:
  %ld1335 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld1335, ptr %b.addr
  %ld1336 = load ptr, ptr %b.addr
  store ptr %ld1336, ptr %res_slot1314
  br label %case_merge289
case_default290:
  unreachable
case_merge289:
  %case_r1337 = load ptr, ptr %res_slot1314
  ret ptr %case_r1337
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1338 = load ptr, ptr %req.addr
  %res_slot1339 = alloca ptr
  %tgp1340 = getelementptr i8, ptr %ld1338, i64 8
  %tag1341 = load i32, ptr %tgp1340, align 4
  switch i32 %tag1341, label %case_default296 [
      i32 0, label %case_br297
  ]
case_br297:
  %fp1342 = getelementptr i8, ptr %ld1338, i64 16
  %fv1343 = load ptr, ptr %fp1342, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1343, ptr %$f591.addr
  %fp1344 = getelementptr i8, ptr %ld1338, i64 24
  %fv1345 = load ptr, ptr %fp1344, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1345, ptr %$f592.addr
  %fp1346 = getelementptr i8, ptr %ld1338, i64 32
  %fv1347 = load ptr, ptr %fp1346, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1347, ptr %$f593.addr
  %fp1348 = getelementptr i8, ptr %ld1338, i64 40
  %fv1349 = load ptr, ptr %fp1348, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1349, ptr %$f594.addr
  %fp1350 = getelementptr i8, ptr %ld1338, i64 48
  %fv1351 = load ptr, ptr %fp1350, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1351, ptr %$f595.addr
  %fp1352 = getelementptr i8, ptr %ld1338, i64 56
  %fv1353 = load ptr, ptr %fp1352, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1353, ptr %$f596.addr
  %fp1354 = getelementptr i8, ptr %ld1338, i64 64
  %fv1355 = load ptr, ptr %fp1354, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1355, ptr %$f597.addr
  %fp1356 = getelementptr i8, ptr %ld1338, i64 72
  %fv1357 = load ptr, ptr %fp1356, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1357, ptr %$f598.addr
  %freed1358 = call i64 @march_decrc_freed(ptr %ld1338)
  %freed_b1359 = icmp ne i64 %freed1358, 0
  br i1 %freed_b1359, label %br_unique298, label %br_shared299
br_shared299:
  call void @march_incrc(ptr %fv1357)
  call void @march_incrc(ptr %fv1355)
  call void @march_incrc(ptr %fv1353)
  call void @march_incrc(ptr %fv1351)
  call void @march_incrc(ptr %fv1349)
  call void @march_incrc(ptr %fv1347)
  call void @march_incrc(ptr %fv1345)
  call void @march_incrc(ptr %fv1343)
  br label %br_body300
br_unique298:
  br label %br_body300
br_body300:
  %ld1360 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1360, ptr %h.addr
  %ld1361 = load ptr, ptr %h.addr
  store ptr %ld1361, ptr %res_slot1339
  br label %case_merge295
case_default296:
  unreachable
case_merge295:
  %case_r1362 = load ptr, ptr %res_slot1339
  ret ptr %case_r1362
}

define ptr @Http.query$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1363 = load ptr, ptr %req.addr
  %res_slot1364 = alloca ptr
  %tgp1365 = getelementptr i8, ptr %ld1363, i64 8
  %tag1366 = load i32, ptr %tgp1365, align 4
  switch i32 %tag1366, label %case_default302 [
      i32 0, label %case_br303
  ]
case_br303:
  %fp1367 = getelementptr i8, ptr %ld1363, i64 16
  %fv1368 = load ptr, ptr %fp1367, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1368, ptr %$f583.addr
  %fp1369 = getelementptr i8, ptr %ld1363, i64 24
  %fv1370 = load ptr, ptr %fp1369, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1370, ptr %$f584.addr
  %fp1371 = getelementptr i8, ptr %ld1363, i64 32
  %fv1372 = load ptr, ptr %fp1371, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1372, ptr %$f585.addr
  %fp1373 = getelementptr i8, ptr %ld1363, i64 40
  %fv1374 = load ptr, ptr %fp1373, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1374, ptr %$f586.addr
  %fp1375 = getelementptr i8, ptr %ld1363, i64 48
  %fv1376 = load ptr, ptr %fp1375, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1376, ptr %$f587.addr
  %fp1377 = getelementptr i8, ptr %ld1363, i64 56
  %fv1378 = load ptr, ptr %fp1377, align 8
  %$f588.addr = alloca ptr
  store ptr %fv1378, ptr %$f588.addr
  %fp1379 = getelementptr i8, ptr %ld1363, i64 64
  %fv1380 = load ptr, ptr %fp1379, align 8
  %$f589.addr = alloca ptr
  store ptr %fv1380, ptr %$f589.addr
  %fp1381 = getelementptr i8, ptr %ld1363, i64 72
  %fv1382 = load ptr, ptr %fp1381, align 8
  %$f590.addr = alloca ptr
  store ptr %fv1382, ptr %$f590.addr
  %freed1383 = call i64 @march_decrc_freed(ptr %ld1363)
  %freed_b1384 = icmp ne i64 %freed1383, 0
  br i1 %freed_b1384, label %br_unique304, label %br_shared305
br_shared305:
  call void @march_incrc(ptr %fv1382)
  call void @march_incrc(ptr %fv1380)
  call void @march_incrc(ptr %fv1378)
  call void @march_incrc(ptr %fv1376)
  call void @march_incrc(ptr %fv1374)
  call void @march_incrc(ptr %fv1372)
  call void @march_incrc(ptr %fv1370)
  call void @march_incrc(ptr %fv1368)
  br label %br_body306
br_unique304:
  br label %br_body306
br_body306:
  %ld1385 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld1385, ptr %q.addr
  %ld1386 = load ptr, ptr %q.addr
  store ptr %ld1386, ptr %res_slot1364
  br label %case_merge301
case_default302:
  unreachable
case_merge301:
  %case_r1387 = load ptr, ptr %res_slot1364
  ret ptr %case_r1387
}

define ptr @Http.path$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1388 = load ptr, ptr %req.addr
  %res_slot1389 = alloca ptr
  %tgp1390 = getelementptr i8, ptr %ld1388, i64 8
  %tag1391 = load i32, ptr %tgp1390, align 4
  switch i32 %tag1391, label %case_default308 [
      i32 0, label %case_br309
  ]
case_br309:
  %fp1392 = getelementptr i8, ptr %ld1388, i64 16
  %fv1393 = load ptr, ptr %fp1392, align 8
  %$f575.addr = alloca ptr
  store ptr %fv1393, ptr %$f575.addr
  %fp1394 = getelementptr i8, ptr %ld1388, i64 24
  %fv1395 = load ptr, ptr %fp1394, align 8
  %$f576.addr = alloca ptr
  store ptr %fv1395, ptr %$f576.addr
  %fp1396 = getelementptr i8, ptr %ld1388, i64 32
  %fv1397 = load ptr, ptr %fp1396, align 8
  %$f577.addr = alloca ptr
  store ptr %fv1397, ptr %$f577.addr
  %fp1398 = getelementptr i8, ptr %ld1388, i64 40
  %fv1399 = load ptr, ptr %fp1398, align 8
  %$f578.addr = alloca ptr
  store ptr %fv1399, ptr %$f578.addr
  %fp1400 = getelementptr i8, ptr %ld1388, i64 48
  %fv1401 = load ptr, ptr %fp1400, align 8
  %$f579.addr = alloca ptr
  store ptr %fv1401, ptr %$f579.addr
  %fp1402 = getelementptr i8, ptr %ld1388, i64 56
  %fv1403 = load ptr, ptr %fp1402, align 8
  %$f580.addr = alloca ptr
  store ptr %fv1403, ptr %$f580.addr
  %fp1404 = getelementptr i8, ptr %ld1388, i64 64
  %fv1405 = load ptr, ptr %fp1404, align 8
  %$f581.addr = alloca ptr
  store ptr %fv1405, ptr %$f581.addr
  %fp1406 = getelementptr i8, ptr %ld1388, i64 72
  %fv1407 = load ptr, ptr %fp1406, align 8
  %$f582.addr = alloca ptr
  store ptr %fv1407, ptr %$f582.addr
  %freed1408 = call i64 @march_decrc_freed(ptr %ld1388)
  %freed_b1409 = icmp ne i64 %freed1408, 0
  br i1 %freed_b1409, label %br_unique310, label %br_shared311
br_shared311:
  call void @march_incrc(ptr %fv1407)
  call void @march_incrc(ptr %fv1405)
  call void @march_incrc(ptr %fv1403)
  call void @march_incrc(ptr %fv1401)
  call void @march_incrc(ptr %fv1399)
  call void @march_incrc(ptr %fv1397)
  call void @march_incrc(ptr %fv1395)
  call void @march_incrc(ptr %fv1393)
  br label %br_body312
br_unique310:
  br label %br_body312
br_body312:
  %ld1410 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld1410, ptr %p.addr
  %ld1411 = load ptr, ptr %p.addr
  store ptr %ld1411, ptr %res_slot1389
  br label %case_merge307
case_default308:
  unreachable
case_merge307:
  %case_r1412 = load ptr, ptr %res_slot1389
  ret ptr %case_r1412
}

define ptr @Http.host$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1413 = load ptr, ptr %req.addr
  %res_slot1414 = alloca ptr
  %tgp1415 = getelementptr i8, ptr %ld1413, i64 8
  %tag1416 = load i32, ptr %tgp1415, align 4
  switch i32 %tag1416, label %case_default314 [
      i32 0, label %case_br315
  ]
case_br315:
  %fp1417 = getelementptr i8, ptr %ld1413, i64 16
  %fv1418 = load ptr, ptr %fp1417, align 8
  %$f559.addr = alloca ptr
  store ptr %fv1418, ptr %$f559.addr
  %fp1419 = getelementptr i8, ptr %ld1413, i64 24
  %fv1420 = load ptr, ptr %fp1419, align 8
  %$f560.addr = alloca ptr
  store ptr %fv1420, ptr %$f560.addr
  %fp1421 = getelementptr i8, ptr %ld1413, i64 32
  %fv1422 = load ptr, ptr %fp1421, align 8
  %$f561.addr = alloca ptr
  store ptr %fv1422, ptr %$f561.addr
  %fp1423 = getelementptr i8, ptr %ld1413, i64 40
  %fv1424 = load ptr, ptr %fp1423, align 8
  %$f562.addr = alloca ptr
  store ptr %fv1424, ptr %$f562.addr
  %fp1425 = getelementptr i8, ptr %ld1413, i64 48
  %fv1426 = load ptr, ptr %fp1425, align 8
  %$f563.addr = alloca ptr
  store ptr %fv1426, ptr %$f563.addr
  %fp1427 = getelementptr i8, ptr %ld1413, i64 56
  %fv1428 = load ptr, ptr %fp1427, align 8
  %$f564.addr = alloca ptr
  store ptr %fv1428, ptr %$f564.addr
  %fp1429 = getelementptr i8, ptr %ld1413, i64 64
  %fv1430 = load ptr, ptr %fp1429, align 8
  %$f565.addr = alloca ptr
  store ptr %fv1430, ptr %$f565.addr
  %fp1431 = getelementptr i8, ptr %ld1413, i64 72
  %fv1432 = load ptr, ptr %fp1431, align 8
  %$f566.addr = alloca ptr
  store ptr %fv1432, ptr %$f566.addr
  %freed1433 = call i64 @march_decrc_freed(ptr %ld1413)
  %freed_b1434 = icmp ne i64 %freed1433, 0
  br i1 %freed_b1434, label %br_unique316, label %br_shared317
br_shared317:
  call void @march_incrc(ptr %fv1432)
  call void @march_incrc(ptr %fv1430)
  call void @march_incrc(ptr %fv1428)
  call void @march_incrc(ptr %fv1426)
  call void @march_incrc(ptr %fv1424)
  call void @march_incrc(ptr %fv1422)
  call void @march_incrc(ptr %fv1420)
  call void @march_incrc(ptr %fv1418)
  br label %br_body318
br_unique316:
  br label %br_body318
br_body318:
  %ld1435 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld1435, ptr %h.addr
  %ld1436 = load ptr, ptr %h.addr
  store ptr %ld1436, ptr %res_slot1414
  br label %case_merge313
case_default314:
  unreachable
case_merge313:
  %case_r1437 = load ptr, ptr %res_slot1414
  ret ptr %case_r1437
}

define ptr @Http.method$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1438 = load ptr, ptr %req.addr
  %res_slot1439 = alloca ptr
  %tgp1440 = getelementptr i8, ptr %ld1438, i64 8
  %tag1441 = load i32, ptr %tgp1440, align 4
  switch i32 %tag1441, label %case_default320 [
      i32 0, label %case_br321
  ]
case_br321:
  %fp1442 = getelementptr i8, ptr %ld1438, i64 16
  %fv1443 = load ptr, ptr %fp1442, align 8
  %$f543.addr = alloca ptr
  store ptr %fv1443, ptr %$f543.addr
  %fp1444 = getelementptr i8, ptr %ld1438, i64 24
  %fv1445 = load ptr, ptr %fp1444, align 8
  %$f544.addr = alloca ptr
  store ptr %fv1445, ptr %$f544.addr
  %fp1446 = getelementptr i8, ptr %ld1438, i64 32
  %fv1447 = load ptr, ptr %fp1446, align 8
  %$f545.addr = alloca ptr
  store ptr %fv1447, ptr %$f545.addr
  %fp1448 = getelementptr i8, ptr %ld1438, i64 40
  %fv1449 = load ptr, ptr %fp1448, align 8
  %$f546.addr = alloca ptr
  store ptr %fv1449, ptr %$f546.addr
  %fp1450 = getelementptr i8, ptr %ld1438, i64 48
  %fv1451 = load ptr, ptr %fp1450, align 8
  %$f547.addr = alloca ptr
  store ptr %fv1451, ptr %$f547.addr
  %fp1452 = getelementptr i8, ptr %ld1438, i64 56
  %fv1453 = load ptr, ptr %fp1452, align 8
  %$f548.addr = alloca ptr
  store ptr %fv1453, ptr %$f548.addr
  %fp1454 = getelementptr i8, ptr %ld1438, i64 64
  %fv1455 = load ptr, ptr %fp1454, align 8
  %$f549.addr = alloca ptr
  store ptr %fv1455, ptr %$f549.addr
  %fp1456 = getelementptr i8, ptr %ld1438, i64 72
  %fv1457 = load ptr, ptr %fp1456, align 8
  %$f550.addr = alloca ptr
  store ptr %fv1457, ptr %$f550.addr
  %freed1458 = call i64 @march_decrc_freed(ptr %ld1438)
  %freed_b1459 = icmp ne i64 %freed1458, 0
  br i1 %freed_b1459, label %br_unique322, label %br_shared323
br_shared323:
  call void @march_incrc(ptr %fv1457)
  call void @march_incrc(ptr %fv1455)
  call void @march_incrc(ptr %fv1453)
  call void @march_incrc(ptr %fv1451)
  call void @march_incrc(ptr %fv1449)
  call void @march_incrc(ptr %fv1447)
  call void @march_incrc(ptr %fv1445)
  call void @march_incrc(ptr %fv1443)
  br label %br_body324
br_unique322:
  br label %br_body324
br_body324:
  %ld1460 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld1460, ptr %m.addr
  %ld1461 = load ptr, ptr %m.addr
  store ptr %ld1461, ptr %res_slot1439
  br label %case_merge319
case_default320:
  unreachable
case_merge319:
  %case_r1462 = load ptr, ptr %res_slot1439
  ret ptr %case_r1462
}

define ptr @Http.port$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1463 = load ptr, ptr %req.addr
  %res_slot1464 = alloca ptr
  %tgp1465 = getelementptr i8, ptr %ld1463, i64 8
  %tag1466 = load i32, ptr %tgp1465, align 4
  switch i32 %tag1466, label %case_default326 [
      i32 0, label %case_br327
  ]
case_br327:
  %fp1467 = getelementptr i8, ptr %ld1463, i64 16
  %fv1468 = load ptr, ptr %fp1467, align 8
  %$f567.addr = alloca ptr
  store ptr %fv1468, ptr %$f567.addr
  %fp1469 = getelementptr i8, ptr %ld1463, i64 24
  %fv1470 = load ptr, ptr %fp1469, align 8
  %$f568.addr = alloca ptr
  store ptr %fv1470, ptr %$f568.addr
  %fp1471 = getelementptr i8, ptr %ld1463, i64 32
  %fv1472 = load ptr, ptr %fp1471, align 8
  %$f569.addr = alloca ptr
  store ptr %fv1472, ptr %$f569.addr
  %fp1473 = getelementptr i8, ptr %ld1463, i64 40
  %fv1474 = load ptr, ptr %fp1473, align 8
  %$f570.addr = alloca ptr
  store ptr %fv1474, ptr %$f570.addr
  %fp1475 = getelementptr i8, ptr %ld1463, i64 48
  %fv1476 = load ptr, ptr %fp1475, align 8
  %$f571.addr = alloca ptr
  store ptr %fv1476, ptr %$f571.addr
  %fp1477 = getelementptr i8, ptr %ld1463, i64 56
  %fv1478 = load ptr, ptr %fp1477, align 8
  %$f572.addr = alloca ptr
  store ptr %fv1478, ptr %$f572.addr
  %fp1479 = getelementptr i8, ptr %ld1463, i64 64
  %fv1480 = load ptr, ptr %fp1479, align 8
  %$f573.addr = alloca ptr
  store ptr %fv1480, ptr %$f573.addr
  %fp1481 = getelementptr i8, ptr %ld1463, i64 72
  %fv1482 = load ptr, ptr %fp1481, align 8
  %$f574.addr = alloca ptr
  store ptr %fv1482, ptr %$f574.addr
  %freed1483 = call i64 @march_decrc_freed(ptr %ld1463)
  %freed_b1484 = icmp ne i64 %freed1483, 0
  br i1 %freed_b1484, label %br_unique328, label %br_shared329
br_shared329:
  call void @march_incrc(ptr %fv1482)
  call void @march_incrc(ptr %fv1480)
  call void @march_incrc(ptr %fv1478)
  call void @march_incrc(ptr %fv1476)
  call void @march_incrc(ptr %fv1474)
  call void @march_incrc(ptr %fv1472)
  call void @march_incrc(ptr %fv1470)
  call void @march_incrc(ptr %fv1468)
  br label %br_body330
br_unique328:
  br label %br_body330
br_body330:
  %ld1485 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld1485, ptr %p.addr
  %ld1486 = load ptr, ptr %p.addr
  store ptr %ld1486, ptr %res_slot1464
  br label %case_merge325
case_default326:
  unreachable
case_merge325:
  %case_r1487 = load ptr, ptr %res_slot1464
  ret ptr %case_r1487
}

define ptr @on_chunk$apply$22(ptr %$clo.arg, ptr %chunk.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %chunk.addr = alloca ptr
  store ptr %chunk.arg, ptr %chunk.addr
  %ld1488 = load ptr, ptr %chunk.addr
  %cr1489 = call i64 @string_length(ptr %ld1488)
  %size.addr = alloca i64
  store i64 %cr1489, ptr %size.addr
  %ld1490 = load i64, ptr %size.addr
  %cr1491 = call ptr @march_int_to_string(i64 %ld1490)
  %$t2009.addr = alloca ptr
  store ptr %cr1491, ptr %$t2009.addr
  %sl1492 = call ptr @march_string_lit(ptr @.str31, i64 8)
  %ld1493 = load ptr, ptr %$t2009.addr
  %cr1494 = call ptr @march_string_concat(ptr %sl1492, ptr %ld1493)
  %$t2010.addr = alloca ptr
  store ptr %cr1494, ptr %$t2010.addr
  %ld1495 = load ptr, ptr %$t2010.addr
  %sl1496 = call ptr @march_string_lit(ptr @.str32, i64 7)
  %cr1497 = call ptr @march_string_concat(ptr %ld1495, ptr %sl1496)
  %$t2011.addr = alloca ptr
  store ptr %cr1497, ptr %$t2011.addr
  %ld1498 = load ptr, ptr %$t2011.addr
  call void @march_print(ptr %ld1498)
  %cv1499 = inttoptr i64 0 to ptr
  ret ptr %cv1499
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

