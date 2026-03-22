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
@.str17 = private unnamed_addr constant [32 x i8] c"=== Pattern 1: Print chunks ===\00"
@.str18 = private unnamed_addr constant [54 x i8] c"Streaming 5 JSON objects from httpbin.org/stream/5...\00"
@.str19 = private unnamed_addr constant [1 x i8] c"\00"
@.str20 = private unnamed_addr constant [28 x i8] c"http://httpbin.org/stream/5\00"
@.str21 = private unnamed_addr constant [9 x i8] c"Status: \00"
@.str22 = private unnamed_addr constant [7 x i8] c"Error!\00"
@.str23 = private unnamed_addr constant [1 x i8] c"\00"
@.str24 = private unnamed_addr constant [33 x i8] c"=== Pattern 2: Byte counting ===\00"
@.str25 = private unnamed_addr constant [46 x i8] c"Counting bytes from httpbin.org/bytes/8192...\00"
@.str26 = private unnamed_addr constant [30 x i8] c"http://httpbin.org/bytes/8192\00"
@.str27 = private unnamed_addr constant [9 x i8] c"Status: \00"
@.str28 = private unnamed_addr constant [7 x i8] c"Error!\00"
@.str29 = private unnamed_addr constant [1 x i8] c"\00"
@.str30 = private unnamed_addr constant [49 x i8] c"=== Pattern 3: Chunked transfer (20 objects) ===\00"
@.str31 = private unnamed_addr constant [29 x i8] c"http://httpbin.org/stream/20\00"
@.str32 = private unnamed_addr constant [9 x i8] c"Status: \00"
@.str33 = private unnamed_addr constant [6 x i8] c"Done!\00"
@.str34 = private unnamed_addr constant [7 x i8] c"Error!\00"
@.str35 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str36 = private unnamed_addr constant [4 x i8] c"url\00"
@.str37 = private unnamed_addr constant [1 x i8] c"\00"
@.str38 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str39 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str40 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str41 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str42 = private unnamed_addr constant [1 x i8] c"\00"
@.str43 = private unnamed_addr constant [1 x i8] c"\00"
@.str44 = private unnamed_addr constant [8 x i8] c"[chunk \00"
@.str45 = private unnamed_addr constant [8 x i8] c" bytes]\00"
@.str46 = private unnamed_addr constant [12 x i8] c"  received \00"
@.str47 = private unnamed_addr constant [7 x i8] c" bytes\00"
@.str48 = private unnamed_addr constant [10 x i8] c"  chunk: \00"
@.str49 = private unnamed_addr constant [7 x i8] c" bytes\00"

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
  %sl375 = call ptr @march_string_lit(ptr @.str17, i64 31)
  call void @march_print(ptr %sl375)
  %sl376 = call ptr @march_string_lit(ptr @.str18, i64 53)
  call void @march_print(ptr %sl376)
  %sl377 = call ptr @march_string_lit(ptr @.str19, i64 0)
  call void @march_print(ptr %sl377)
  %hp378 = call ptr @march_alloc(i64 24)
  %tgp379 = getelementptr i8, ptr %hp378, i64 8
  store i32 0, ptr %tgp379, align 4
  %fp380 = getelementptr i8, ptr %hp378, i64 16
  store ptr @print_chunk$apply$22, ptr %fp380, align 8
  %print_chunk.addr = alloca ptr
  store ptr %hp378, ptr %print_chunk.addr
  %ld381 = load ptr, ptr %client_1.addr
  call void @march_incrc(ptr %ld381)
  %ld382 = load ptr, ptr %client_1.addr
  %sl383 = call ptr @march_string_lit(ptr @.str20, i64 27)
  %ld384 = load ptr, ptr %print_chunk.addr
  %cr385 = call ptr @HttpClient.stream_get(ptr %ld382, ptr %sl383, ptr %ld384)
  %$t2013.addr = alloca ptr
  store ptr %cr385, ptr %$t2013.addr
  %ld386 = load ptr, ptr %$t2013.addr
  %res_slot387 = alloca ptr
  %tgp388 = getelementptr i8, ptr %ld386, i64 8
  %tag389 = load i32, ptr %tgp388, align 4
  switch i32 %tag389, label %case_default75 [
      i32 0, label %case_br76
      i32 1, label %case_br77
  ]
case_br76:
  %fp390 = getelementptr i8, ptr %ld386, i64 16
  %fv391 = load ptr, ptr %fp390, align 8
  %$f2016.addr = alloca ptr
  store ptr %fv391, ptr %$f2016.addr
  %freed392 = call i64 @march_decrc_freed(ptr %ld386)
  %freed_b393 = icmp ne i64 %freed392, 0
  br i1 %freed_b393, label %br_unique78, label %br_shared79
br_shared79:
  call void @march_incrc(ptr %fv391)
  br label %br_body80
br_unique78:
  br label %br_body80
br_body80:
  %ld394 = load ptr, ptr %$f2016.addr
  %res_slot395 = alloca ptr
  %tgp396 = getelementptr i8, ptr %ld394, i64 8
  %tag397 = load i32, ptr %tgp396, align 4
  switch i32 %tag397, label %case_default82 [
      i32 0, label %case_br83
  ]
case_br83:
  %fp398 = getelementptr i8, ptr %ld394, i64 16
  %fv399 = load ptr, ptr %fp398, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv399, ptr %$f2017.addr
  %fp400 = getelementptr i8, ptr %ld394, i64 24
  %fv401 = load ptr, ptr %fp400, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv401, ptr %$f2018.addr
  %fp402 = getelementptr i8, ptr %ld394, i64 32
  %fv403 = load ptr, ptr %fp402, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv403, ptr %$f2019.addr
  %freed404 = call i64 @march_decrc_freed(ptr %ld394)
  %freed_b405 = icmp ne i64 %freed404, 0
  br i1 %freed_b405, label %br_unique84, label %br_shared85
br_shared85:
  call void @march_incrc(ptr %fv403)
  call void @march_incrc(ptr %fv401)
  call void @march_incrc(ptr %fv399)
  br label %br_body86
br_unique84:
  br label %br_body86
br_body86:
  %ld406 = load ptr, ptr %$f2017.addr
  %status.addr = alloca ptr
  store ptr %ld406, ptr %status.addr
  %ld407 = load ptr, ptr %status.addr
  %cr408 = call ptr @march_int_to_string(ptr %ld407)
  %$t2014.addr = alloca ptr
  store ptr %cr408, ptr %$t2014.addr
  %sl409 = call ptr @march_string_lit(ptr @.str21, i64 8)
  %ld410 = load ptr, ptr %$t2014.addr
  %cr411 = call ptr @march_string_concat(ptr %sl409, ptr %ld410)
  %$t2015.addr = alloca ptr
  store ptr %cr411, ptr %$t2015.addr
  %ld412 = load ptr, ptr %$t2015.addr
  call void @march_print(ptr %ld412)
  %cv413 = inttoptr i64 0 to ptr
  store ptr %cv413, ptr %res_slot395
  br label %case_merge81
case_default82:
  unreachable
case_merge81:
  %case_r414 = load ptr, ptr %res_slot395
  store ptr %case_r414, ptr %res_slot387
  br label %case_merge74
case_br77:
  %fp415 = getelementptr i8, ptr %ld386, i64 16
  %fv416 = load ptr, ptr %fp415, align 8
  %$f2020.addr = alloca ptr
  store ptr %fv416, ptr %$f2020.addr
  %freed417 = call i64 @march_decrc_freed(ptr %ld386)
  %freed_b418 = icmp ne i64 %freed417, 0
  br i1 %freed_b418, label %br_unique87, label %br_shared88
br_shared88:
  call void @march_incrc(ptr %fv416)
  br label %br_body89
br_unique87:
  br label %br_body89
br_body89:
  %sl419 = call ptr @march_string_lit(ptr @.str22, i64 6)
  call void @march_print(ptr %sl419)
  %cv420 = inttoptr i64 0 to ptr
  store ptr %cv420, ptr %res_slot387
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r421 = load ptr, ptr %res_slot387
  %sl422 = call ptr @march_string_lit(ptr @.str23, i64 0)
  call void @march_print(ptr %sl422)
  %sl423 = call ptr @march_string_lit(ptr @.str24, i64 32)
  call void @march_print(ptr %sl423)
  %sl424 = call ptr @march_string_lit(ptr @.str25, i64 45)
  call void @march_print(ptr %sl424)
  %hp425 = call ptr @march_alloc(i64 24)
  %tgp426 = getelementptr i8, ptr %hp425, i64 8
  store i32 0, ptr %tgp426, align 4
  %fp427 = getelementptr i8, ptr %hp425, i64 16
  store ptr @count_bytes$apply$23, ptr %fp427, align 8
  %count_bytes.addr = alloca ptr
  store ptr %hp425, ptr %count_bytes.addr
  %ld428 = load ptr, ptr %client_1.addr
  call void @march_incrc(ptr %ld428)
  %ld429 = load ptr, ptr %client_1.addr
  %sl430 = call ptr @march_string_lit(ptr @.str26, i64 29)
  %ld431 = load ptr, ptr %count_bytes.addr
  %cr432 = call ptr @HttpClient.stream_get(ptr %ld429, ptr %sl430, ptr %ld431)
  %$t2025.addr = alloca ptr
  store ptr %cr432, ptr %$t2025.addr
  %ld433 = load ptr, ptr %$t2025.addr
  %res_slot434 = alloca ptr
  %tgp435 = getelementptr i8, ptr %ld433, i64 8
  %tag436 = load i32, ptr %tgp435, align 4
  switch i32 %tag436, label %case_default91 [
      i32 0, label %case_br92
      i32 1, label %case_br93
  ]
case_br92:
  %fp437 = getelementptr i8, ptr %ld433, i64 16
  %fv438 = load ptr, ptr %fp437, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv438, ptr %$f2028.addr
  %freed439 = call i64 @march_decrc_freed(ptr %ld433)
  %freed_b440 = icmp ne i64 %freed439, 0
  br i1 %freed_b440, label %br_unique94, label %br_shared95
br_shared95:
  call void @march_incrc(ptr %fv438)
  br label %br_body96
br_unique94:
  br label %br_body96
br_body96:
  %ld441 = load ptr, ptr %$f2028.addr
  %res_slot442 = alloca ptr
  %tgp443 = getelementptr i8, ptr %ld441, i64 8
  %tag444 = load i32, ptr %tgp443, align 4
  switch i32 %tag444, label %case_default98 [
      i32 0, label %case_br99
  ]
case_br99:
  %fp445 = getelementptr i8, ptr %ld441, i64 16
  %fv446 = load ptr, ptr %fp445, align 8
  %$f2029.addr = alloca ptr
  store ptr %fv446, ptr %$f2029.addr
  %fp447 = getelementptr i8, ptr %ld441, i64 24
  %fv448 = load ptr, ptr %fp447, align 8
  %$f2030.addr = alloca ptr
  store ptr %fv448, ptr %$f2030.addr
  %fp449 = getelementptr i8, ptr %ld441, i64 32
  %fv450 = load ptr, ptr %fp449, align 8
  %$f2031.addr = alloca ptr
  store ptr %fv450, ptr %$f2031.addr
  %freed451 = call i64 @march_decrc_freed(ptr %ld441)
  %freed_b452 = icmp ne i64 %freed451, 0
  br i1 %freed_b452, label %br_unique100, label %br_shared101
br_shared101:
  call void @march_incrc(ptr %fv450)
  call void @march_incrc(ptr %fv448)
  call void @march_incrc(ptr %fv446)
  br label %br_body102
br_unique100:
  br label %br_body102
br_body102:
  %ld453 = load ptr, ptr %$f2029.addr
  %status_1.addr = alloca ptr
  store ptr %ld453, ptr %status_1.addr
  %ld454 = load ptr, ptr %status_1.addr
  %cr455 = call ptr @march_int_to_string(ptr %ld454)
  %$t2026.addr = alloca ptr
  store ptr %cr455, ptr %$t2026.addr
  %sl456 = call ptr @march_string_lit(ptr @.str27, i64 8)
  %ld457 = load ptr, ptr %$t2026.addr
  %cr458 = call ptr @march_string_concat(ptr %sl456, ptr %ld457)
  %$t2027.addr = alloca ptr
  store ptr %cr458, ptr %$t2027.addr
  %ld459 = load ptr, ptr %$t2027.addr
  call void @march_print(ptr %ld459)
  %cv460 = inttoptr i64 0 to ptr
  store ptr %cv460, ptr %res_slot442
  br label %case_merge97
case_default98:
  unreachable
case_merge97:
  %case_r461 = load ptr, ptr %res_slot442
  store ptr %case_r461, ptr %res_slot434
  br label %case_merge90
case_br93:
  %fp462 = getelementptr i8, ptr %ld433, i64 16
  %fv463 = load ptr, ptr %fp462, align 8
  %$f2032.addr = alloca ptr
  store ptr %fv463, ptr %$f2032.addr
  %freed464 = call i64 @march_decrc_freed(ptr %ld433)
  %freed_b465 = icmp ne i64 %freed464, 0
  br i1 %freed_b465, label %br_unique103, label %br_shared104
br_shared104:
  call void @march_incrc(ptr %fv463)
  br label %br_body105
br_unique103:
  br label %br_body105
br_body105:
  %sl466 = call ptr @march_string_lit(ptr @.str28, i64 6)
  call void @march_print(ptr %sl466)
  %cv467 = inttoptr i64 0 to ptr
  store ptr %cv467, ptr %res_slot434
  br label %case_merge90
case_default91:
  unreachable
case_merge90:
  %case_r468 = load ptr, ptr %res_slot434
  %sl469 = call ptr @march_string_lit(ptr @.str29, i64 0)
  call void @march_print(ptr %sl469)
  %sl470 = call ptr @march_string_lit(ptr @.str30, i64 48)
  call void @march_print(ptr %sl470)
  %hp471 = call ptr @march_alloc(i64 24)
  %tgp472 = getelementptr i8, ptr %hp471, i64 8
  store i32 0, ptr %tgp472, align 4
  %fp473 = getelementptr i8, ptr %hp471, i64 16
  store ptr @show_chunk$apply$24, ptr %fp473, align 8
  %show_chunk.addr = alloca ptr
  store ptr %hp471, ptr %show_chunk.addr
  %ld474 = load ptr, ptr %client_1.addr
  %sl475 = call ptr @march_string_lit(ptr @.str31, i64 28)
  %ld476 = load ptr, ptr %show_chunk.addr
  %cr477 = call ptr @HttpClient.stream_get(ptr %ld474, ptr %sl475, ptr %ld476)
  %$t2037.addr = alloca ptr
  store ptr %cr477, ptr %$t2037.addr
  %ld478 = load ptr, ptr %$t2037.addr
  %res_slot479 = alloca ptr
  %tgp480 = getelementptr i8, ptr %ld478, i64 8
  %tag481 = load i32, ptr %tgp480, align 4
  switch i32 %tag481, label %case_default107 [
      i32 0, label %case_br108
      i32 1, label %case_br109
  ]
case_br108:
  %fp482 = getelementptr i8, ptr %ld478, i64 16
  %fv483 = load ptr, ptr %fp482, align 8
  %$f2040.addr = alloca ptr
  store ptr %fv483, ptr %$f2040.addr
  %freed484 = call i64 @march_decrc_freed(ptr %ld478)
  %freed_b485 = icmp ne i64 %freed484, 0
  br i1 %freed_b485, label %br_unique110, label %br_shared111
br_shared111:
  call void @march_incrc(ptr %fv483)
  br label %br_body112
br_unique110:
  br label %br_body112
br_body112:
  %ld486 = load ptr, ptr %$f2040.addr
  %res_slot487 = alloca ptr
  %tgp488 = getelementptr i8, ptr %ld486, i64 8
  %tag489 = load i32, ptr %tgp488, align 4
  switch i32 %tag489, label %case_default114 [
      i32 0, label %case_br115
  ]
case_br115:
  %fp490 = getelementptr i8, ptr %ld486, i64 16
  %fv491 = load ptr, ptr %fp490, align 8
  %$f2041.addr = alloca ptr
  store ptr %fv491, ptr %$f2041.addr
  %fp492 = getelementptr i8, ptr %ld486, i64 24
  %fv493 = load ptr, ptr %fp492, align 8
  %$f2042.addr = alloca ptr
  store ptr %fv493, ptr %$f2042.addr
  %fp494 = getelementptr i8, ptr %ld486, i64 32
  %fv495 = load ptr, ptr %fp494, align 8
  %$f2043.addr = alloca ptr
  store ptr %fv495, ptr %$f2043.addr
  %freed496 = call i64 @march_decrc_freed(ptr %ld486)
  %freed_b497 = icmp ne i64 %freed496, 0
  br i1 %freed_b497, label %br_unique116, label %br_shared117
br_shared117:
  call void @march_incrc(ptr %fv495)
  call void @march_incrc(ptr %fv493)
  call void @march_incrc(ptr %fv491)
  br label %br_body118
br_unique116:
  br label %br_body118
br_body118:
  %ld498 = load ptr, ptr %$f2041.addr
  %status_2.addr = alloca ptr
  store ptr %ld498, ptr %status_2.addr
  %ld499 = load ptr, ptr %status_2.addr
  %cr500 = call ptr @march_int_to_string(ptr %ld499)
  %$t2038.addr = alloca ptr
  store ptr %cr500, ptr %$t2038.addr
  %sl501 = call ptr @march_string_lit(ptr @.str32, i64 8)
  %ld502 = load ptr, ptr %$t2038.addr
  %cr503 = call ptr @march_string_concat(ptr %sl501, ptr %ld502)
  %$t2039.addr = alloca ptr
  store ptr %cr503, ptr %$t2039.addr
  %ld504 = load ptr, ptr %$t2039.addr
  call void @march_print(ptr %ld504)
  %sl505 = call ptr @march_string_lit(ptr @.str33, i64 5)
  call void @march_print(ptr %sl505)
  %cv506 = inttoptr i64 0 to ptr
  store ptr %cv506, ptr %res_slot487
  br label %case_merge113
case_default114:
  unreachable
case_merge113:
  %case_r507 = load ptr, ptr %res_slot487
  store ptr %case_r507, ptr %res_slot479
  br label %case_merge106
case_br109:
  %fp508 = getelementptr i8, ptr %ld478, i64 16
  %fv509 = load ptr, ptr %fp508, align 8
  %$f2044.addr = alloca ptr
  store ptr %fv509, ptr %$f2044.addr
  %freed510 = call i64 @march_decrc_freed(ptr %ld478)
  %freed_b511 = icmp ne i64 %freed510, 0
  br i1 %freed_b511, label %br_unique119, label %br_shared120
br_shared120:
  call void @march_incrc(ptr %fv509)
  br label %br_body121
br_unique119:
  br label %br_body121
br_body121:
  %sl512 = call ptr @march_string_lit(ptr @.str34, i64 6)
  call void @march_print(ptr %sl512)
  %cv513 = inttoptr i64 0 to ptr
  store ptr %cv513, ptr %res_slot479
  br label %case_merge106
case_default107:
  unreachable
case_merge106:
  %case_r514 = load ptr, ptr %res_slot479
  ret ptr %case_r514
}

define ptr @HttpClient.stream_get(ptr %client.arg, ptr %url.arg, ptr %on_chunk.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %ld515 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld515)
  %ld516 = load ptr, ptr %url.addr
  %url_i26.addr = alloca ptr
  store ptr %ld516, ptr %url_i26.addr
  %ld517 = load ptr, ptr %url_i26.addr
  %cr518 = call ptr @Http.parse_url(ptr %ld517)
  %$t1073.addr = alloca ptr
  store ptr %cr518, ptr %$t1073.addr
  %ld519 = load ptr, ptr %$t1073.addr
  %res_slot520 = alloca ptr
  %tgp521 = getelementptr i8, ptr %ld519, i64 8
  %tag522 = load i32, ptr %tgp521, align 4
  switch i32 %tag522, label %case_default123 [
      i32 1, label %case_br124
      i32 0, label %case_br125
  ]
case_br124:
  %fp523 = getelementptr i8, ptr %ld519, i64 16
  %fv524 = load ptr, ptr %fp523, align 8
  %$f1096.addr = alloca ptr
  store ptr %fv524, ptr %$f1096.addr
  %sl525 = call ptr @march_string_lit(ptr @.str35, i64 13)
  %ld526 = load ptr, ptr %url.addr
  %cr527 = call ptr @march_string_concat(ptr %sl525, ptr %ld526)
  %$t1074.addr = alloca ptr
  store ptr %cr527, ptr %$t1074.addr
  %hp528 = call ptr @march_alloc(i64 32)
  %tgp529 = getelementptr i8, ptr %hp528, i64 8
  store i32 1, ptr %tgp529, align 4
  %sl530 = call ptr @march_string_lit(ptr @.str36, i64 3)
  %fp531 = getelementptr i8, ptr %hp528, i64 16
  store ptr %sl530, ptr %fp531, align 8
  %ld532 = load ptr, ptr %$t1074.addr
  %fp533 = getelementptr i8, ptr %hp528, i64 24
  store ptr %ld532, ptr %fp533, align 8
  %$t1075.addr = alloca ptr
  store ptr %hp528, ptr %$t1075.addr
  %ld534 = load ptr, ptr %$t1073.addr
  %ld535 = load ptr, ptr %$t1075.addr
  %rc536 = load i64, ptr %ld534, align 8
  %uniq537 = icmp eq i64 %rc536, 1
  %fbip_slot538 = alloca ptr
  br i1 %uniq537, label %fbip_reuse126, label %fbip_fresh127
fbip_reuse126:
  %tgp539 = getelementptr i8, ptr %ld534, i64 8
  store i32 1, ptr %tgp539, align 4
  %fp540 = getelementptr i8, ptr %ld534, i64 16
  store ptr %ld535, ptr %fp540, align 8
  store ptr %ld534, ptr %fbip_slot538
  br label %fbip_merge128
fbip_fresh127:
  call void @march_decrc(ptr %ld534)
  %hp541 = call ptr @march_alloc(i64 24)
  %tgp542 = getelementptr i8, ptr %hp541, i64 8
  store i32 1, ptr %tgp542, align 4
  %fp543 = getelementptr i8, ptr %hp541, i64 16
  store ptr %ld535, ptr %fp543, align 8
  store ptr %hp541, ptr %fbip_slot538
  br label %fbip_merge128
fbip_merge128:
  %fbip_r544 = load ptr, ptr %fbip_slot538
  store ptr %fbip_r544, ptr %res_slot520
  br label %case_merge122
case_br125:
  %fp545 = getelementptr i8, ptr %ld519, i64 16
  %fv546 = load ptr, ptr %fp545, align 8
  %$f1097.addr = alloca ptr
  store ptr %fv546, ptr %$f1097.addr
  %freed547 = call i64 @march_decrc_freed(ptr %ld519)
  %freed_b548 = icmp ne i64 %freed547, 0
  br i1 %freed_b548, label %br_unique129, label %br_shared130
br_shared130:
  call void @march_incrc(ptr %fv546)
  br label %br_body131
br_unique129:
  br label %br_body131
br_body131:
  %ld549 = load ptr, ptr %$f1097.addr
  %req.addr = alloca ptr
  store ptr %ld549, ptr %req.addr
  %ld550 = load ptr, ptr %req.addr
  %sl551 = call ptr @march_string_lit(ptr @.str37, i64 0)
  %cr552 = call ptr @Http.set_body$Request_T_$String(ptr %ld550, ptr %sl551)
  %req_1.addr = alloca ptr
  store ptr %cr552, ptr %req_1.addr
  %ld553 = load ptr, ptr %client.addr
  %res_slot554 = alloca ptr
  %tgp555 = getelementptr i8, ptr %ld553, i64 8
  %tag556 = load i32, ptr %tgp555, align 4
  switch i32 %tag556, label %case_default133 [
      i32 0, label %case_br134
  ]
case_br134:
  %fp557 = getelementptr i8, ptr %ld553, i64 16
  %fv558 = load ptr, ptr %fp557, align 8
  %$f1090.addr = alloca ptr
  store ptr %fv558, ptr %$f1090.addr
  %fp559 = getelementptr i8, ptr %ld553, i64 24
  %fv560 = load ptr, ptr %fp559, align 8
  %$f1091.addr = alloca ptr
  store ptr %fv560, ptr %$f1091.addr
  %fp561 = getelementptr i8, ptr %ld553, i64 32
  %fv562 = load ptr, ptr %fp561, align 8
  %$f1092.addr = alloca ptr
  store ptr %fv562, ptr %$f1092.addr
  %fp563 = getelementptr i8, ptr %ld553, i64 40
  %fv564 = load i64, ptr %fp563, align 8
  %$f1093.addr = alloca i64
  store i64 %fv564, ptr %$f1093.addr
  %fp565 = getelementptr i8, ptr %ld553, i64 48
  %fv566 = load i64, ptr %fp565, align 8
  %$f1094.addr = alloca i64
  store i64 %fv566, ptr %$f1094.addr
  %fp567 = getelementptr i8, ptr %ld553, i64 56
  %fv568 = load i64, ptr %fp567, align 8
  %$f1095.addr = alloca i64
  store i64 %fv568, ptr %$f1095.addr
  %freed569 = call i64 @march_decrc_freed(ptr %ld553)
  %freed_b570 = icmp ne i64 %freed569, 0
  br i1 %freed_b570, label %br_unique135, label %br_shared136
br_shared136:
  call void @march_incrc(ptr %fv562)
  call void @march_incrc(ptr %fv560)
  call void @march_incrc(ptr %fv558)
  br label %br_body137
br_unique135:
  br label %br_body137
br_body137:
  %ld571 = load ptr, ptr %$f1090.addr
  %req_steps.addr = alloca ptr
  store ptr %ld571, ptr %req_steps.addr
  %ld572 = load ptr, ptr %req_steps.addr
  %ld573 = load ptr, ptr %req_1.addr
  %cr574 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld572, ptr %ld573)
  %$t1076.addr = alloca ptr
  store ptr %cr574, ptr %$t1076.addr
  %ld575 = load ptr, ptr %$t1076.addr
  %res_slot576 = alloca ptr
  %tgp577 = getelementptr i8, ptr %ld575, i64 8
  %tag578 = load i32, ptr %tgp577, align 4
  switch i32 %tag578, label %case_default139 [
      i32 1, label %case_br140
      i32 0, label %case_br141
  ]
case_br140:
  %fp579 = getelementptr i8, ptr %ld575, i64 16
  %fv580 = load ptr, ptr %fp579, align 8
  %$f1088.addr = alloca ptr
  store ptr %fv580, ptr %$f1088.addr
  %ld581 = load ptr, ptr %$f1088.addr
  %e.addr = alloca ptr
  store ptr %ld581, ptr %e.addr
  %ld582 = load ptr, ptr %$t1076.addr
  %ld583 = load ptr, ptr %e.addr
  %rc584 = load i64, ptr %ld582, align 8
  %uniq585 = icmp eq i64 %rc584, 1
  %fbip_slot586 = alloca ptr
  br i1 %uniq585, label %fbip_reuse142, label %fbip_fresh143
fbip_reuse142:
  %tgp587 = getelementptr i8, ptr %ld582, i64 8
  store i32 1, ptr %tgp587, align 4
  %fp588 = getelementptr i8, ptr %ld582, i64 16
  store ptr %ld583, ptr %fp588, align 8
  store ptr %ld582, ptr %fbip_slot586
  br label %fbip_merge144
fbip_fresh143:
  call void @march_decrc(ptr %ld582)
  %hp589 = call ptr @march_alloc(i64 24)
  %tgp590 = getelementptr i8, ptr %hp589, i64 8
  store i32 1, ptr %tgp590, align 4
  %fp591 = getelementptr i8, ptr %hp589, i64 16
  store ptr %ld583, ptr %fp591, align 8
  store ptr %hp589, ptr %fbip_slot586
  br label %fbip_merge144
fbip_merge144:
  %fbip_r592 = load ptr, ptr %fbip_slot586
  store ptr %fbip_r592, ptr %res_slot576
  br label %case_merge138
case_br141:
  %fp593 = getelementptr i8, ptr %ld575, i64 16
  %fv594 = load ptr, ptr %fp593, align 8
  %$f1089.addr = alloca ptr
  store ptr %fv594, ptr %$f1089.addr
  %freed595 = call i64 @march_decrc_freed(ptr %ld575)
  %freed_b596 = icmp ne i64 %freed595, 0
  br i1 %freed_b596, label %br_unique145, label %br_shared146
br_shared146:
  call void @march_incrc(ptr %fv594)
  br label %br_body147
br_unique145:
  br label %br_body147
br_body147:
  %ld597 = load ptr, ptr %$f1089.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld597, ptr %transformed_req.addr
  %ld598 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld598)
  %ld599 = load ptr, ptr %transformed_req.addr
  %cr600 = call ptr @HttpTransport.connect$Request_String(ptr %ld599)
  %$t1077.addr = alloca ptr
  store ptr %cr600, ptr %$t1077.addr
  %ld601 = load ptr, ptr %$t1077.addr
  %res_slot602 = alloca ptr
  %tgp603 = getelementptr i8, ptr %ld601, i64 8
  %tag604 = load i32, ptr %tgp603, align 4
  switch i32 %tag604, label %case_default149 [
      i32 1, label %case_br150
      i32 0, label %case_br151
  ]
case_br150:
  %fp605 = getelementptr i8, ptr %ld601, i64 16
  %fv606 = load ptr, ptr %fp605, align 8
  %$f1086.addr = alloca ptr
  store ptr %fv606, ptr %$f1086.addr
  %ld607 = load ptr, ptr %$f1086.addr
  %e_1.addr = alloca ptr
  store ptr %ld607, ptr %e_1.addr
  %hp608 = call ptr @march_alloc(i64 24)
  %tgp609 = getelementptr i8, ptr %hp608, i64 8
  store i32 0, ptr %tgp609, align 4
  %ld610 = load ptr, ptr %e_1.addr
  %fp611 = getelementptr i8, ptr %hp608, i64 16
  store ptr %ld610, ptr %fp611, align 8
  %$t1078.addr = alloca ptr
  store ptr %hp608, ptr %$t1078.addr
  %ld612 = load ptr, ptr %$t1077.addr
  %ld613 = load ptr, ptr %$t1078.addr
  %rc614 = load i64, ptr %ld612, align 8
  %uniq615 = icmp eq i64 %rc614, 1
  %fbip_slot616 = alloca ptr
  br i1 %uniq615, label %fbip_reuse152, label %fbip_fresh153
fbip_reuse152:
  %tgp617 = getelementptr i8, ptr %ld612, i64 8
  store i32 1, ptr %tgp617, align 4
  %fp618 = getelementptr i8, ptr %ld612, i64 16
  store ptr %ld613, ptr %fp618, align 8
  store ptr %ld612, ptr %fbip_slot616
  br label %fbip_merge154
fbip_fresh153:
  call void @march_decrc(ptr %ld612)
  %hp619 = call ptr @march_alloc(i64 24)
  %tgp620 = getelementptr i8, ptr %hp619, i64 8
  store i32 1, ptr %tgp620, align 4
  %fp621 = getelementptr i8, ptr %hp619, i64 16
  store ptr %ld613, ptr %fp621, align 8
  store ptr %hp619, ptr %fbip_slot616
  br label %fbip_merge154
fbip_merge154:
  %fbip_r622 = load ptr, ptr %fbip_slot616
  store ptr %fbip_r622, ptr %res_slot602
  br label %case_merge148
case_br151:
  %fp623 = getelementptr i8, ptr %ld601, i64 16
  %fv624 = load ptr, ptr %fp623, align 8
  %$f1087.addr = alloca ptr
  store ptr %fv624, ptr %$f1087.addr
  %freed625 = call i64 @march_decrc_freed(ptr %ld601)
  %freed_b626 = icmp ne i64 %freed625, 0
  br i1 %freed_b626, label %br_unique155, label %br_shared156
br_shared156:
  call void @march_incrc(ptr %fv624)
  br label %br_body157
br_unique155:
  br label %br_body157
br_body157:
  %ld627 = load ptr, ptr %$f1087.addr
  %fd.addr = alloca ptr
  store ptr %ld627, ptr %fd.addr
  %ld628 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld628)
  %ld629 = load ptr, ptr %fd.addr
  %ld630 = load ptr, ptr %transformed_req.addr
  %ld631 = load ptr, ptr %on_chunk.addr
  %cr632 = call ptr @HttpTransport.stream_request_on$V__2823$Request_String$Fn_String_T_(ptr %ld629, ptr %ld630, ptr %ld631)
  %result.addr = alloca ptr
  store ptr %cr632, ptr %result.addr
  %ld633 = load ptr, ptr %fd.addr
  %cr634 = call ptr @march_tcp_close(ptr %ld633)
  %ld635 = load ptr, ptr %result.addr
  %res_slot636 = alloca ptr
  %tgp637 = getelementptr i8, ptr %ld635, i64 8
  %tag638 = load i32, ptr %tgp637, align 4
  switch i32 %tag638, label %case_default159 [
      i32 1, label %case_br160
      i32 0, label %case_br161
  ]
case_br160:
  %fp639 = getelementptr i8, ptr %ld635, i64 16
  %fv640 = load ptr, ptr %fp639, align 8
  %$f1081.addr = alloca ptr
  store ptr %fv640, ptr %$f1081.addr
  %ld641 = load ptr, ptr %$f1081.addr
  %e_2.addr = alloca ptr
  store ptr %ld641, ptr %e_2.addr
  %hp642 = call ptr @march_alloc(i64 24)
  %tgp643 = getelementptr i8, ptr %hp642, i64 8
  store i32 0, ptr %tgp643, align 4
  %ld644 = load ptr, ptr %e_2.addr
  %fp645 = getelementptr i8, ptr %hp642, i64 16
  store ptr %ld644, ptr %fp645, align 8
  %$t1079.addr = alloca ptr
  store ptr %hp642, ptr %$t1079.addr
  %ld646 = load ptr, ptr %result.addr
  %ld647 = load ptr, ptr %$t1079.addr
  %rc648 = load i64, ptr %ld646, align 8
  %uniq649 = icmp eq i64 %rc648, 1
  %fbip_slot650 = alloca ptr
  br i1 %uniq649, label %fbip_reuse162, label %fbip_fresh163
fbip_reuse162:
  %tgp651 = getelementptr i8, ptr %ld646, i64 8
  store i32 1, ptr %tgp651, align 4
  %fp652 = getelementptr i8, ptr %ld646, i64 16
  store ptr %ld647, ptr %fp652, align 8
  store ptr %ld646, ptr %fbip_slot650
  br label %fbip_merge164
fbip_fresh163:
  call void @march_decrc(ptr %ld646)
  %hp653 = call ptr @march_alloc(i64 24)
  %tgp654 = getelementptr i8, ptr %hp653, i64 8
  store i32 1, ptr %tgp654, align 4
  %fp655 = getelementptr i8, ptr %hp653, i64 16
  store ptr %ld647, ptr %fp655, align 8
  store ptr %hp653, ptr %fbip_slot650
  br label %fbip_merge164
fbip_merge164:
  %fbip_r656 = load ptr, ptr %fbip_slot650
  store ptr %fbip_r656, ptr %res_slot636
  br label %case_merge158
case_br161:
  %fp657 = getelementptr i8, ptr %ld635, i64 16
  %fv658 = load ptr, ptr %fp657, align 8
  %$f1082.addr = alloca ptr
  store ptr %fv658, ptr %$f1082.addr
  %freed659 = call i64 @march_decrc_freed(ptr %ld635)
  %freed_b660 = icmp ne i64 %freed659, 0
  br i1 %freed_b660, label %br_unique165, label %br_shared166
br_shared166:
  call void @march_incrc(ptr %fv658)
  br label %br_body167
br_unique165:
  br label %br_body167
br_body167:
  %ld661 = load ptr, ptr %$f1082.addr
  %res_slot662 = alloca ptr
  %tgp663 = getelementptr i8, ptr %ld661, i64 8
  %tag664 = load i32, ptr %tgp663, align 4
  switch i32 %tag664, label %case_default169 [
      i32 0, label %case_br170
  ]
case_br170:
  %fp665 = getelementptr i8, ptr %ld661, i64 16
  %fv666 = load ptr, ptr %fp665, align 8
  %$f1083.addr = alloca ptr
  store ptr %fv666, ptr %$f1083.addr
  %fp667 = getelementptr i8, ptr %ld661, i64 24
  %fv668 = load ptr, ptr %fp667, align 8
  %$f1084.addr = alloca ptr
  store ptr %fv668, ptr %$f1084.addr
  %fp669 = getelementptr i8, ptr %ld661, i64 32
  %fv670 = load ptr, ptr %fp669, align 8
  %$f1085.addr = alloca ptr
  store ptr %fv670, ptr %$f1085.addr
  %freed671 = call i64 @march_decrc_freed(ptr %ld661)
  %freed_b672 = icmp ne i64 %freed671, 0
  br i1 %freed_b672, label %br_unique171, label %br_shared172
br_shared172:
  call void @march_incrc(ptr %fv670)
  call void @march_incrc(ptr %fv668)
  call void @march_incrc(ptr %fv666)
  br label %br_body173
br_unique171:
  br label %br_body173
br_body173:
  %ld673 = load ptr, ptr %$f1085.addr
  %last.addr = alloca ptr
  store ptr %ld673, ptr %last.addr
  %ld674 = load ptr, ptr %$f1084.addr
  %headers.addr = alloca ptr
  store ptr %ld674, ptr %headers.addr
  %ld675 = load ptr, ptr %$f1083.addr
  %status.addr = alloca ptr
  store ptr %ld675, ptr %status.addr
  %hp676 = call ptr @march_alloc(i64 40)
  %tgp677 = getelementptr i8, ptr %hp676, i64 8
  store i32 0, ptr %tgp677, align 4
  %ld678 = load ptr, ptr %status.addr
  %fp679 = getelementptr i8, ptr %hp676, i64 16
  store ptr %ld678, ptr %fp679, align 8
  %ld680 = load ptr, ptr %headers.addr
  %fp681 = getelementptr i8, ptr %hp676, i64 24
  store ptr %ld680, ptr %fp681, align 8
  %ld682 = load ptr, ptr %last.addr
  %fp683 = getelementptr i8, ptr %hp676, i64 32
  store ptr %ld682, ptr %fp683, align 8
  %$t1080.addr = alloca ptr
  store ptr %hp676, ptr %$t1080.addr
  %hp684 = call ptr @march_alloc(i64 24)
  %tgp685 = getelementptr i8, ptr %hp684, i64 8
  store i32 0, ptr %tgp685, align 4
  %ld686 = load ptr, ptr %$t1080.addr
  %fp687 = getelementptr i8, ptr %hp684, i64 16
  store ptr %ld686, ptr %fp687, align 8
  store ptr %hp684, ptr %res_slot662
  br label %case_merge168
case_default169:
  unreachable
case_merge168:
  %case_r688 = load ptr, ptr %res_slot662
  store ptr %case_r688, ptr %res_slot636
  br label %case_merge158
case_default159:
  unreachable
case_merge158:
  %case_r689 = load ptr, ptr %res_slot636
  store ptr %case_r689, ptr %res_slot602
  br label %case_merge148
case_default149:
  unreachable
case_merge148:
  %case_r690 = load ptr, ptr %res_slot602
  store ptr %case_r690, ptr %res_slot576
  br label %case_merge138
case_default139:
  unreachable
case_merge138:
  %case_r691 = load ptr, ptr %res_slot576
  store ptr %case_r691, ptr %res_slot554
  br label %case_merge132
case_default133:
  unreachable
case_merge132:
  %case_r692 = load ptr, ptr %res_slot554
  store ptr %case_r692, ptr %res_slot520
  br label %case_merge122
case_default123:
  unreachable
case_merge122:
  %case_r693 = load ptr, ptr %res_slot520
  ret ptr %case_r693
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld694 = load ptr, ptr %req.addr
  %sl695 = call ptr @march_string_lit(ptr @.str38, i64 10)
  %sl696 = call ptr @march_string_lit(ptr @.str39, i64 9)
  %cr697 = call ptr @Http.set_header$Request_V__3635$String$String(ptr %ld694, ptr %sl695, ptr %sl696)
  %req_1.addr = alloca ptr
  store ptr %cr697, ptr %req_1.addr
  %ld698 = load ptr, ptr %req_1.addr
  %sl699 = call ptr @march_string_lit(ptr @.str40, i64 6)
  %sl700 = call ptr @march_string_lit(ptr @.str41, i64 3)
  %cr701 = call ptr @Http.set_header$Request_V__3637$String$String(ptr %ld698, ptr %sl699, ptr %sl700)
  %req_2.addr = alloca ptr
  store ptr %cr701, ptr %req_2.addr
  %hp702 = call ptr @march_alloc(i64 24)
  %tgp703 = getelementptr i8, ptr %hp702, i64 8
  store i32 0, ptr %tgp703, align 4
  %ld704 = load ptr, ptr %req_2.addr
  %fp705 = getelementptr i8, ptr %hp702, i64 16
  store ptr %ld704, ptr %fp705, align 8
  ret ptr %hp702
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__6076_Result_Request_V__6075_V__6074(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld706 = load ptr, ptr %client.addr
  %res_slot707 = alloca ptr
  %tgp708 = getelementptr i8, ptr %ld706, i64 8
  %tag709 = load i32, ptr %tgp708, align 4
  switch i32 %tag709, label %case_default175 [
      i32 0, label %case_br176
  ]
case_br176:
  %fp710 = getelementptr i8, ptr %ld706, i64 16
  %fv711 = load ptr, ptr %fp710, align 8
  %$f889.addr = alloca ptr
  store ptr %fv711, ptr %$f889.addr
  %fp712 = getelementptr i8, ptr %ld706, i64 24
  %fv713 = load ptr, ptr %fp712, align 8
  %$f890.addr = alloca ptr
  store ptr %fv713, ptr %$f890.addr
  %fp714 = getelementptr i8, ptr %ld706, i64 32
  %fv715 = load ptr, ptr %fp714, align 8
  %$f891.addr = alloca ptr
  store ptr %fv715, ptr %$f891.addr
  %fp716 = getelementptr i8, ptr %ld706, i64 40
  %fv717 = load i64, ptr %fp716, align 8
  %$f892.addr = alloca i64
  store i64 %fv717, ptr %$f892.addr
  %fp718 = getelementptr i8, ptr %ld706, i64 48
  %fv719 = load i64, ptr %fp718, align 8
  %$f893.addr = alloca i64
  store i64 %fv719, ptr %$f893.addr
  %fp720 = getelementptr i8, ptr %ld706, i64 56
  %fv721 = load i64, ptr %fp720, align 8
  %$f894.addr = alloca i64
  store i64 %fv721, ptr %$f894.addr
  %ld722 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld722, ptr %backoff.addr
  %ld723 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld723, ptr %retries.addr
  %ld724 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld724, ptr %redir.addr
  %ld725 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld725, ptr %err_steps.addr
  %ld726 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld726, ptr %resp_steps.addr
  %ld727 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld727, ptr %req_steps.addr
  %hp728 = call ptr @march_alloc(i64 32)
  %tgp729 = getelementptr i8, ptr %hp728, i64 8
  store i32 0, ptr %tgp729, align 4
  %ld730 = load ptr, ptr %name.addr
  %fp731 = getelementptr i8, ptr %hp728, i64 16
  store ptr %ld730, ptr %fp731, align 8
  %ld732 = load ptr, ptr %step.addr
  %fp733 = getelementptr i8, ptr %hp728, i64 24
  store ptr %ld732, ptr %fp733, align 8
  %$t887.addr = alloca ptr
  store ptr %hp728, ptr %$t887.addr
  %ld734 = load ptr, ptr %req_steps.addr
  %ld735 = load ptr, ptr %$t887.addr
  %cr736 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld734, ptr %ld735)
  %$t888.addr = alloca ptr
  store ptr %cr736, ptr %$t888.addr
  %ld737 = load ptr, ptr %client.addr
  %ld738 = load ptr, ptr %$t888.addr
  %ld739 = load ptr, ptr %resp_steps.addr
  %ld740 = load ptr, ptr %err_steps.addr
  %ld741 = load i64, ptr %redir.addr
  %ld742 = load i64, ptr %retries.addr
  %ld743 = load i64, ptr %backoff.addr
  %rc744 = load i64, ptr %ld737, align 8
  %uniq745 = icmp eq i64 %rc744, 1
  %fbip_slot746 = alloca ptr
  br i1 %uniq745, label %fbip_reuse177, label %fbip_fresh178
fbip_reuse177:
  %tgp747 = getelementptr i8, ptr %ld737, i64 8
  store i32 0, ptr %tgp747, align 4
  %fp748 = getelementptr i8, ptr %ld737, i64 16
  store ptr %ld738, ptr %fp748, align 8
  %fp749 = getelementptr i8, ptr %ld737, i64 24
  store ptr %ld739, ptr %fp749, align 8
  %fp750 = getelementptr i8, ptr %ld737, i64 32
  store ptr %ld740, ptr %fp750, align 8
  %fp751 = getelementptr i8, ptr %ld737, i64 40
  store i64 %ld741, ptr %fp751, align 8
  %fp752 = getelementptr i8, ptr %ld737, i64 48
  store i64 %ld742, ptr %fp752, align 8
  %fp753 = getelementptr i8, ptr %ld737, i64 56
  store i64 %ld743, ptr %fp753, align 8
  store ptr %ld737, ptr %fbip_slot746
  br label %fbip_merge179
fbip_fresh178:
  call void @march_decrc(ptr %ld737)
  %hp754 = call ptr @march_alloc(i64 64)
  %tgp755 = getelementptr i8, ptr %hp754, i64 8
  store i32 0, ptr %tgp755, align 4
  %fp756 = getelementptr i8, ptr %hp754, i64 16
  store ptr %ld738, ptr %fp756, align 8
  %fp757 = getelementptr i8, ptr %hp754, i64 24
  store ptr %ld739, ptr %fp757, align 8
  %fp758 = getelementptr i8, ptr %hp754, i64 32
  store ptr %ld740, ptr %fp758, align 8
  %fp759 = getelementptr i8, ptr %hp754, i64 40
  store i64 %ld741, ptr %fp759, align 8
  %fp760 = getelementptr i8, ptr %hp754, i64 48
  store i64 %ld742, ptr %fp760, align 8
  %fp761 = getelementptr i8, ptr %hp754, i64 56
  store i64 %ld743, ptr %fp761, align 8
  store ptr %hp754, ptr %fbip_slot746
  br label %fbip_merge179
fbip_merge179:
  %fbip_r762 = load ptr, ptr %fbip_slot746
  store ptr %fbip_r762, ptr %res_slot707
  br label %case_merge174
case_default175:
  unreachable
case_merge174:
  %case_r763 = load ptr, ptr %res_slot707
  ret ptr %case_r763
}

define ptr @HttpTransport.stream_request_on$V__2823$Request_String$Fn_String_T_(ptr %fd.arg, ptr %req.arg, ptr %on_chunk.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %on_chunk.addr = alloca ptr
  store ptr %on_chunk.arg, ptr %on_chunk.addr
  %ld764 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld764)
  %ld765 = load ptr, ptr %req.addr
  %cr766 = call ptr @Http.method$Request_String(ptr %ld765)
  %$t801.addr = alloca ptr
  store ptr %cr766, ptr %$t801.addr
  %ld767 = load ptr, ptr %$t801.addr
  %cr768 = call ptr @Http.method_to_string(ptr %ld767)
  %meth.addr = alloca ptr
  store ptr %cr768, ptr %meth.addr
  %ld769 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld769)
  %ld770 = load ptr, ptr %req.addr
  %cr771 = call ptr @Http.host$Request_String(ptr %ld770)
  %req_host.addr = alloca ptr
  store ptr %cr771, ptr %req_host.addr
  %ld772 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld772)
  %ld773 = load ptr, ptr %req.addr
  %cr774 = call ptr @Http.path$Request_String(ptr %ld773)
  %req_path.addr = alloca ptr
  store ptr %cr774, ptr %req_path.addr
  %ld775 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld775)
  %ld776 = load ptr, ptr %req.addr
  %cr777 = call ptr @Http.query$Request_String(ptr %ld776)
  %req_query.addr = alloca ptr
  store ptr %cr777, ptr %req_query.addr
  %ld778 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld778)
  %ld779 = load ptr, ptr %req.addr
  %cr780 = call ptr @Http.headers$Request_String(ptr %ld779)
  %req_headers.addr = alloca ptr
  store ptr %cr780, ptr %req_headers.addr
  %ld781 = load ptr, ptr %req.addr
  %cr782 = call ptr @Http.body$Request_String(ptr %ld781)
  %req_body.addr = alloca ptr
  store ptr %cr782, ptr %req_body.addr
  %ld783 = load ptr, ptr %meth.addr
  %ld784 = load ptr, ptr %req_host.addr
  %ld785 = load ptr, ptr %req_path.addr
  %ld786 = load ptr, ptr %req_query.addr
  %ld787 = load ptr, ptr %req_headers.addr
  %ld788 = load ptr, ptr %req_body.addr
  %cr789 = call ptr @http_serialize_request(ptr %ld783, ptr %ld784, ptr %ld785, ptr %ld786, ptr %ld787, ptr %ld788)
  %raw_request.addr = alloca ptr
  store ptr %cr789, ptr %raw_request.addr
  %ld790 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld790)
  %ld791 = load ptr, ptr %fd.addr
  %ld792 = load ptr, ptr %raw_request.addr
  %cr793 = call ptr @march_tcp_send_all(ptr %ld791, ptr %ld792)
  %$t802.addr = alloca ptr
  store ptr %cr793, ptr %$t802.addr
  %ld794 = load ptr, ptr %$t802.addr
  %res_slot795 = alloca ptr
  %tgp796 = getelementptr i8, ptr %ld794, i64 8
  %tag797 = load i32, ptr %tgp796, align 4
  switch i32 %tag797, label %case_default181 [
      i32 1, label %case_br182
      i32 0, label %case_br183
  ]
case_br182:
  %fp798 = getelementptr i8, ptr %ld794, i64 16
  %fv799 = load ptr, ptr %fp798, align 8
  %$f818.addr = alloca ptr
  store ptr %fv799, ptr %$f818.addr
  %freed800 = call i64 @march_decrc_freed(ptr %ld794)
  %freed_b801 = icmp ne i64 %freed800, 0
  br i1 %freed_b801, label %br_unique184, label %br_shared185
br_shared185:
  call void @march_incrc(ptr %fv799)
  br label %br_body186
br_unique184:
  br label %br_body186
br_body186:
  %ld802 = load ptr, ptr %$f818.addr
  %msg.addr = alloca ptr
  store ptr %ld802, ptr %msg.addr
  %hp803 = call ptr @march_alloc(i64 24)
  %tgp804 = getelementptr i8, ptr %hp803, i64 8
  store i32 2, ptr %tgp804, align 4
  %ld805 = load ptr, ptr %msg.addr
  %fp806 = getelementptr i8, ptr %hp803, i64 16
  store ptr %ld805, ptr %fp806, align 8
  %$t803.addr = alloca ptr
  store ptr %hp803, ptr %$t803.addr
  %hp807 = call ptr @march_alloc(i64 24)
  %tgp808 = getelementptr i8, ptr %hp807, i64 8
  store i32 1, ptr %tgp808, align 4
  %ld809 = load ptr, ptr %$t803.addr
  %fp810 = getelementptr i8, ptr %hp807, i64 16
  store ptr %ld809, ptr %fp810, align 8
  store ptr %hp807, ptr %res_slot795
  br label %case_merge180
case_br183:
  %fp811 = getelementptr i8, ptr %ld794, i64 16
  %fv812 = load ptr, ptr %fp811, align 8
  %$f819.addr = alloca ptr
  store ptr %fv812, ptr %$f819.addr
  %freed813 = call i64 @march_decrc_freed(ptr %ld794)
  %freed_b814 = icmp ne i64 %freed813, 0
  br i1 %freed_b814, label %br_unique187, label %br_shared188
br_shared188:
  call void @march_incrc(ptr %fv812)
  br label %br_body189
br_unique187:
  br label %br_body189
br_body189:
  %ld815 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld815)
  %ld816 = load ptr, ptr %fd.addr
  %cr817 = call ptr @tcp_recv_http_headers(ptr %ld816)
  %$t804.addr = alloca ptr
  store ptr %cr817, ptr %$t804.addr
  %ld818 = load ptr, ptr %$t804.addr
  %res_slot819 = alloca ptr
  %tgp820 = getelementptr i8, ptr %ld818, i64 8
  %tag821 = load i32, ptr %tgp820, align 4
  switch i32 %tag821, label %case_default191 [
      i32 1, label %case_br192
      i32 0, label %case_br193
  ]
case_br192:
  %fp822 = getelementptr i8, ptr %ld818, i64 16
  %fv823 = load ptr, ptr %fp822, align 8
  %$f813.addr = alloca ptr
  store ptr %fv823, ptr %$f813.addr
  %freed824 = call i64 @march_decrc_freed(ptr %ld818)
  %freed_b825 = icmp ne i64 %freed824, 0
  br i1 %freed_b825, label %br_unique194, label %br_shared195
br_shared195:
  call void @march_incrc(ptr %fv823)
  br label %br_body196
br_unique194:
  br label %br_body196
br_body196:
  %ld826 = load ptr, ptr %$f813.addr
  %msg_1.addr = alloca ptr
  store ptr %ld826, ptr %msg_1.addr
  %hp827 = call ptr @march_alloc(i64 24)
  %tgp828 = getelementptr i8, ptr %hp827, i64 8
  store i32 3, ptr %tgp828, align 4
  %ld829 = load ptr, ptr %msg_1.addr
  %fp830 = getelementptr i8, ptr %hp827, i64 16
  store ptr %ld829, ptr %fp830, align 8
  %$t805.addr = alloca ptr
  store ptr %hp827, ptr %$t805.addr
  %hp831 = call ptr @march_alloc(i64 24)
  %tgp832 = getelementptr i8, ptr %hp831, i64 8
  store i32 1, ptr %tgp832, align 4
  %ld833 = load ptr, ptr %$t805.addr
  %fp834 = getelementptr i8, ptr %hp831, i64 16
  store ptr %ld833, ptr %fp834, align 8
  store ptr %hp831, ptr %res_slot819
  br label %case_merge190
case_br193:
  %fp835 = getelementptr i8, ptr %ld818, i64 16
  %fv836 = load ptr, ptr %fp835, align 8
  %$f814.addr = alloca ptr
  store ptr %fv836, ptr %$f814.addr
  %freed837 = call i64 @march_decrc_freed(ptr %ld818)
  %freed_b838 = icmp ne i64 %freed837, 0
  br i1 %freed_b838, label %br_unique197, label %br_shared198
br_shared198:
  call void @march_incrc(ptr %fv836)
  br label %br_body199
br_unique197:
  br label %br_body199
br_body199:
  %ld839 = load ptr, ptr %$f814.addr
  %res_slot840 = alloca ptr
  %tgp841 = getelementptr i8, ptr %ld839, i64 8
  %tag842 = load i32, ptr %tgp841, align 4
  switch i32 %tag842, label %case_default201 [
      i32 0, label %case_br202
  ]
case_br202:
  %fp843 = getelementptr i8, ptr %ld839, i64 16
  %fv844 = load ptr, ptr %fp843, align 8
  %$f815.addr = alloca ptr
  store ptr %fv844, ptr %$f815.addr
  %fp845 = getelementptr i8, ptr %ld839, i64 24
  %fv846 = load ptr, ptr %fp845, align 8
  %$f816.addr = alloca ptr
  store ptr %fv846, ptr %$f816.addr
  %fp847 = getelementptr i8, ptr %ld839, i64 32
  %fv848 = load ptr, ptr %fp847, align 8
  %$f817.addr = alloca ptr
  store ptr %fv848, ptr %$f817.addr
  %freed849 = call i64 @march_decrc_freed(ptr %ld839)
  %freed_b850 = icmp ne i64 %freed849, 0
  br i1 %freed_b850, label %br_unique203, label %br_shared204
br_shared204:
  call void @march_incrc(ptr %fv848)
  call void @march_incrc(ptr %fv846)
  call void @march_incrc(ptr %fv844)
  br label %br_body205
br_unique203:
  br label %br_body205
br_body205:
  %ld851 = load ptr, ptr %$f817.addr
  %is_chunked.addr = alloca ptr
  store ptr %ld851, ptr %is_chunked.addr
  %ld852 = load ptr, ptr %$f816.addr
  %content_length.addr = alloca ptr
  store ptr %ld852, ptr %content_length.addr
  %ld853 = load ptr, ptr %$f815.addr
  %headers_str.addr = alloca ptr
  store ptr %ld853, ptr %headers_str.addr
  %ld854 = load ptr, ptr %headers_str.addr
  %cr855 = call ptr @http_parse_response(ptr %ld854)
  %$t806.addr = alloca ptr
  store ptr %cr855, ptr %$t806.addr
  %ld856 = load ptr, ptr %$t806.addr
  %res_slot857 = alloca ptr
  %tgp858 = getelementptr i8, ptr %ld856, i64 8
  %tag859 = load i32, ptr %tgp858, align 4
  switch i32 %tag859, label %case_default207 [
      i32 1, label %case_br208
      i32 0, label %case_br209
  ]
case_br208:
  %fp860 = getelementptr i8, ptr %ld856, i64 16
  %fv861 = load ptr, ptr %fp860, align 8
  %$f808.addr = alloca ptr
  store ptr %fv861, ptr %$f808.addr
  %freed862 = call i64 @march_decrc_freed(ptr %ld856)
  %freed_b863 = icmp ne i64 %freed862, 0
  br i1 %freed_b863, label %br_unique210, label %br_shared211
br_shared211:
  call void @march_incrc(ptr %fv861)
  br label %br_body212
br_unique210:
  br label %br_body212
br_body212:
  %ld864 = load ptr, ptr %$f808.addr
  %msg_2.addr = alloca ptr
  store ptr %ld864, ptr %msg_2.addr
  %hp865 = call ptr @march_alloc(i64 24)
  %tgp866 = getelementptr i8, ptr %hp865, i64 8
  store i32 0, ptr %tgp866, align 4
  %ld867 = load ptr, ptr %msg_2.addr
  %fp868 = getelementptr i8, ptr %hp865, i64 16
  store ptr %ld867, ptr %fp868, align 8
  %$t807.addr = alloca ptr
  store ptr %hp865, ptr %$t807.addr
  %hp869 = call ptr @march_alloc(i64 24)
  %tgp870 = getelementptr i8, ptr %hp869, i64 8
  store i32 1, ptr %tgp870, align 4
  %ld871 = load ptr, ptr %$t807.addr
  %fp872 = getelementptr i8, ptr %hp869, i64 16
  store ptr %ld871, ptr %fp872, align 8
  store ptr %hp869, ptr %res_slot857
  br label %case_merge206
case_br209:
  %fp873 = getelementptr i8, ptr %ld856, i64 16
  %fv874 = load ptr, ptr %fp873, align 8
  %$f809.addr = alloca ptr
  store ptr %fv874, ptr %$f809.addr
  %freed875 = call i64 @march_decrc_freed(ptr %ld856)
  %freed_b876 = icmp ne i64 %freed875, 0
  br i1 %freed_b876, label %br_unique213, label %br_shared214
br_shared214:
  call void @march_incrc(ptr %fv874)
  br label %br_body215
br_unique213:
  br label %br_body215
br_body215:
  %ld877 = load ptr, ptr %$f809.addr
  %res_slot878 = alloca ptr
  %tgp879 = getelementptr i8, ptr %ld877, i64 8
  %tag880 = load i32, ptr %tgp879, align 4
  switch i32 %tag880, label %case_default217 [
      i32 0, label %case_br218
  ]
case_br218:
  %fp881 = getelementptr i8, ptr %ld877, i64 16
  %fv882 = load ptr, ptr %fp881, align 8
  %$f810.addr = alloca ptr
  store ptr %fv882, ptr %$f810.addr
  %fp883 = getelementptr i8, ptr %ld877, i64 24
  %fv884 = load ptr, ptr %fp883, align 8
  %$f811.addr = alloca ptr
  store ptr %fv884, ptr %$f811.addr
  %fp885 = getelementptr i8, ptr %ld877, i64 32
  %fv886 = load ptr, ptr %fp885, align 8
  %$f812.addr = alloca ptr
  store ptr %fv886, ptr %$f812.addr
  %freed887 = call i64 @march_decrc_freed(ptr %ld877)
  %freed_b888 = icmp ne i64 %freed887, 0
  br i1 %freed_b888, label %br_unique219, label %br_shared220
br_shared220:
  call void @march_incrc(ptr %fv886)
  call void @march_incrc(ptr %fv884)
  call void @march_incrc(ptr %fv882)
  br label %br_body221
br_unique219:
  br label %br_body221
br_body221:
  %ld889 = load ptr, ptr %$f811.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld889, ptr %resp_headers.addr
  %ld890 = load ptr, ptr %$f810.addr
  %status_code.addr = alloca ptr
  store ptr %ld890, ptr %status_code.addr
  %ld891 = load ptr, ptr %is_chunked.addr
  %res_slot892 = alloca ptr
  %bi893 = trunc i64 %ld891 to i1
  br i1 %bi893, label %case_br224, label %case_default223
case_br224:
  %ld894 = load ptr, ptr %fd.addr
  %ld895 = load ptr, ptr %on_chunk.addr
  %ld896 = load ptr, ptr %status_code.addr
  %ld897 = load ptr, ptr %resp_headers.addr
  %cr898 = call ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %ld894, ptr %ld895, ptr %ld896, ptr %ld897)
  store ptr %cr898, ptr %res_slot892
  br label %case_merge222
case_default223:
  %ld899 = load ptr, ptr %fd.addr
  %ld900 = load ptr, ptr %content_length.addr
  %ld901 = load ptr, ptr %on_chunk.addr
  %ld902 = load ptr, ptr %status_code.addr
  %ld903 = load ptr, ptr %resp_headers.addr
  %cr904 = call ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %ld899, ptr %ld900, ptr %ld901, ptr %ld902, ptr %ld903)
  store ptr %cr904, ptr %res_slot892
  br label %case_merge222
case_merge222:
  %case_r905 = load ptr, ptr %res_slot892
  store ptr %case_r905, ptr %res_slot878
  br label %case_merge216
case_default217:
  unreachable
case_merge216:
  %case_r906 = load ptr, ptr %res_slot878
  store ptr %case_r906, ptr %res_slot857
  br label %case_merge206
case_default207:
  unreachable
case_merge206:
  %case_r907 = load ptr, ptr %res_slot857
  store ptr %case_r907, ptr %res_slot840
  br label %case_merge200
case_default201:
  unreachable
case_merge200:
  %case_r908 = load ptr, ptr %res_slot840
  store ptr %case_r908, ptr %res_slot819
  br label %case_merge190
case_default191:
  unreachable
case_merge190:
  %case_r909 = load ptr, ptr %res_slot819
  store ptr %case_r909, ptr %res_slot795
  br label %case_merge180
case_default181:
  unreachable
case_merge180:
  %case_r910 = load ptr, ptr %res_slot795
  ret ptr %case_r910
}

define ptr @HttpTransport.connect$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld911 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld911)
  %ld912 = load ptr, ptr %req.addr
  %cr913 = call ptr @Http.host$Request_String(ptr %ld912)
  %req_host.addr = alloca ptr
  store ptr %cr913, ptr %req_host.addr
  %ld914 = load ptr, ptr %req.addr
  %cr915 = call ptr @Http.port$Request_String(ptr %ld914)
  %$t777.addr = alloca ptr
  store ptr %cr915, ptr %$t777.addr
  %ld916 = load ptr, ptr %$t777.addr
  %res_slot917 = alloca ptr
  %tgp918 = getelementptr i8, ptr %ld916, i64 8
  %tag919 = load i32, ptr %tgp918, align 4
  switch i32 %tag919, label %case_default226 [
      i32 1, label %case_br227
      i32 0, label %case_br228
  ]
case_br227:
  %fp920 = getelementptr i8, ptr %ld916, i64 16
  %fv921 = load ptr, ptr %fp920, align 8
  %$f778.addr = alloca ptr
  store ptr %fv921, ptr %$f778.addr
  %ld922 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld922)
  %ld923 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld923, ptr %p.addr
  %ld924 = load ptr, ptr %p.addr
  store ptr %ld924, ptr %res_slot917
  br label %case_merge225
case_br228:
  %ld925 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld925)
  %cv926 = inttoptr i64 80 to ptr
  store ptr %cv926, ptr %res_slot917
  br label %case_merge225
case_default226:
  unreachable
case_merge225:
  %case_r927 = load ptr, ptr %res_slot917
  %cv928 = ptrtoint ptr %case_r927 to i64
  %req_port.addr = alloca i64
  store i64 %cv928, ptr %req_port.addr
  %ld929 = load ptr, ptr %req_host.addr
  %ld930 = load i64, ptr %req_port.addr
  %cr931 = call ptr @tcp_connect(ptr %ld929, i64 %ld930)
  %$t779.addr = alloca ptr
  store ptr %cr931, ptr %$t779.addr
  %ld932 = load ptr, ptr %$t779.addr
  %res_slot933 = alloca ptr
  %tgp934 = getelementptr i8, ptr %ld932, i64 8
  %tag935 = load i32, ptr %tgp934, align 4
  switch i32 %tag935, label %case_default230 [
      i32 1, label %case_br231
      i32 0, label %case_br232
  ]
case_br231:
  %fp936 = getelementptr i8, ptr %ld932, i64 16
  %fv937 = load ptr, ptr %fp936, align 8
  %$f781.addr = alloca ptr
  store ptr %fv937, ptr %$f781.addr
  %freed938 = call i64 @march_decrc_freed(ptr %ld932)
  %freed_b939 = icmp ne i64 %freed938, 0
  br i1 %freed_b939, label %br_unique233, label %br_shared234
br_shared234:
  call void @march_incrc(ptr %fv937)
  br label %br_body235
br_unique233:
  br label %br_body235
br_body235:
  %ld940 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld940, ptr %msg.addr
  %hp941 = call ptr @march_alloc(i64 24)
  %tgp942 = getelementptr i8, ptr %hp941, i64 8
  store i32 0, ptr %tgp942, align 4
  %ld943 = load ptr, ptr %msg.addr
  %fp944 = getelementptr i8, ptr %hp941, i64 16
  store ptr %ld943, ptr %fp944, align 8
  %$t780.addr = alloca ptr
  store ptr %hp941, ptr %$t780.addr
  %hp945 = call ptr @march_alloc(i64 24)
  %tgp946 = getelementptr i8, ptr %hp945, i64 8
  store i32 1, ptr %tgp946, align 4
  %ld947 = load ptr, ptr %$t780.addr
  %fp948 = getelementptr i8, ptr %hp945, i64 16
  store ptr %ld947, ptr %fp948, align 8
  store ptr %hp945, ptr %res_slot933
  br label %case_merge229
case_br232:
  %fp949 = getelementptr i8, ptr %ld932, i64 16
  %fv950 = load ptr, ptr %fp949, align 8
  %$f782.addr = alloca ptr
  store ptr %fv950, ptr %$f782.addr
  %freed951 = call i64 @march_decrc_freed(ptr %ld932)
  %freed_b952 = icmp ne i64 %freed951, 0
  br i1 %freed_b952, label %br_unique236, label %br_shared237
br_shared237:
  call void @march_incrc(ptr %fv950)
  br label %br_body238
br_unique236:
  br label %br_body238
br_body238:
  %ld953 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld953, ptr %fd.addr
  %hp954 = call ptr @march_alloc(i64 24)
  %tgp955 = getelementptr i8, ptr %hp954, i64 8
  store i32 0, ptr %tgp955, align 4
  %ld956 = load ptr, ptr %fd.addr
  %fp957 = getelementptr i8, ptr %hp954, i64 16
  store ptr %ld956, ptr %fp957, align 8
  store ptr %hp954, ptr %res_slot933
  br label %case_merge229
case_default230:
  unreachable
case_merge229:
  %case_r958 = load ptr, ptr %res_slot933
  ret ptr %case_r958
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld959 = load ptr, ptr %steps.addr
  %res_slot960 = alloca ptr
  %tgp961 = getelementptr i8, ptr %ld959, i64 8
  %tag962 = load i32, ptr %tgp961, align 4
  switch i32 %tag962, label %case_default240 [
      i32 0, label %case_br241
      i32 1, label %case_br242
  ]
case_br241:
  %ld963 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld963)
  %hp964 = call ptr @march_alloc(i64 24)
  %tgp965 = getelementptr i8, ptr %hp964, i64 8
  store i32 0, ptr %tgp965, align 4
  %ld966 = load ptr, ptr %req.addr
  %fp967 = getelementptr i8, ptr %hp964, i64 16
  store ptr %ld966, ptr %fp967, align 8
  store ptr %hp964, ptr %res_slot960
  br label %case_merge239
case_br242:
  %fp968 = getelementptr i8, ptr %ld959, i64 16
  %fv969 = load ptr, ptr %fp968, align 8
  %$f957.addr = alloca ptr
  store ptr %fv969, ptr %$f957.addr
  %fp970 = getelementptr i8, ptr %ld959, i64 24
  %fv971 = load ptr, ptr %fp970, align 8
  %$f958.addr = alloca ptr
  store ptr %fv971, ptr %$f958.addr
  %freed972 = call i64 @march_decrc_freed(ptr %ld959)
  %freed_b973 = icmp ne i64 %freed972, 0
  br i1 %freed_b973, label %br_unique243, label %br_shared244
br_shared244:
  call void @march_incrc(ptr %fv971)
  call void @march_incrc(ptr %fv969)
  br label %br_body245
br_unique243:
  br label %br_body245
br_body245:
  %ld974 = load ptr, ptr %$f957.addr
  %res_slot975 = alloca ptr
  %tgp976 = getelementptr i8, ptr %ld974, i64 8
  %tag977 = load i32, ptr %tgp976, align 4
  switch i32 %tag977, label %case_default247 [
      i32 0, label %case_br248
  ]
case_br248:
  %fp978 = getelementptr i8, ptr %ld974, i64 16
  %fv979 = load ptr, ptr %fp978, align 8
  %$f959.addr = alloca ptr
  store ptr %fv979, ptr %$f959.addr
  %fp980 = getelementptr i8, ptr %ld974, i64 24
  %fv981 = load ptr, ptr %fp980, align 8
  %$f960.addr = alloca ptr
  store ptr %fv981, ptr %$f960.addr
  %freed982 = call i64 @march_decrc_freed(ptr %ld974)
  %freed_b983 = icmp ne i64 %freed982, 0
  br i1 %freed_b983, label %br_unique249, label %br_shared250
br_shared250:
  call void @march_incrc(ptr %fv981)
  call void @march_incrc(ptr %fv979)
  br label %br_body251
br_unique249:
  br label %br_body251
br_body251:
  %ld984 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld984, ptr %rest.addr
  %ld985 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld985, ptr %step_fn.addr
  %ld986 = load ptr, ptr %step_fn.addr
  %fp987 = getelementptr i8, ptr %ld986, i64 16
  %fv988 = load ptr, ptr %fp987, align 8
  %ld989 = load ptr, ptr %req.addr
  %cr990 = call ptr (ptr, ptr) %fv988(ptr %ld986, ptr %ld989)
  %$t954.addr = alloca ptr
  store ptr %cr990, ptr %$t954.addr
  %ld991 = load ptr, ptr %$t954.addr
  %res_slot992 = alloca ptr
  %tgp993 = getelementptr i8, ptr %ld991, i64 8
  %tag994 = load i32, ptr %tgp993, align 4
  switch i32 %tag994, label %case_default253 [
      i32 1, label %case_br254
      i32 0, label %case_br255
  ]
case_br254:
  %fp995 = getelementptr i8, ptr %ld991, i64 16
  %fv996 = load ptr, ptr %fp995, align 8
  %$f955.addr = alloca ptr
  store ptr %fv996, ptr %$f955.addr
  %ld997 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld997, ptr %e.addr
  %ld998 = load ptr, ptr %$t954.addr
  %ld999 = load ptr, ptr %e.addr
  %rc1000 = load i64, ptr %ld998, align 8
  %uniq1001 = icmp eq i64 %rc1000, 1
  %fbip_slot1002 = alloca ptr
  br i1 %uniq1001, label %fbip_reuse256, label %fbip_fresh257
fbip_reuse256:
  %tgp1003 = getelementptr i8, ptr %ld998, i64 8
  store i32 1, ptr %tgp1003, align 4
  %fp1004 = getelementptr i8, ptr %ld998, i64 16
  store ptr %ld999, ptr %fp1004, align 8
  store ptr %ld998, ptr %fbip_slot1002
  br label %fbip_merge258
fbip_fresh257:
  call void @march_decrc(ptr %ld998)
  %hp1005 = call ptr @march_alloc(i64 24)
  %tgp1006 = getelementptr i8, ptr %hp1005, i64 8
  store i32 1, ptr %tgp1006, align 4
  %fp1007 = getelementptr i8, ptr %hp1005, i64 16
  store ptr %ld999, ptr %fp1007, align 8
  store ptr %hp1005, ptr %fbip_slot1002
  br label %fbip_merge258
fbip_merge258:
  %fbip_r1008 = load ptr, ptr %fbip_slot1002
  store ptr %fbip_r1008, ptr %res_slot992
  br label %case_merge252
case_br255:
  %fp1009 = getelementptr i8, ptr %ld991, i64 16
  %fv1010 = load ptr, ptr %fp1009, align 8
  %$f956.addr = alloca ptr
  store ptr %fv1010, ptr %$f956.addr
  %freed1011 = call i64 @march_decrc_freed(ptr %ld991)
  %freed_b1012 = icmp ne i64 %freed1011, 0
  br i1 %freed_b1012, label %br_unique259, label %br_shared260
br_shared260:
  call void @march_incrc(ptr %fv1010)
  br label %br_body261
br_unique259:
  br label %br_body261
br_body261:
  %ld1013 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld1013, ptr %new_req.addr
  %ld1014 = load ptr, ptr %rest.addr
  %ld1015 = load ptr, ptr %new_req.addr
  %cr1016 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld1014, ptr %ld1015)
  store ptr %cr1016, ptr %res_slot992
  br label %case_merge252
case_default253:
  unreachable
case_merge252:
  %case_r1017 = load ptr, ptr %res_slot992
  store ptr %case_r1017, ptr %res_slot975
  br label %case_merge246
case_default247:
  unreachable
case_merge246:
  %case_r1018 = load ptr, ptr %res_slot975
  store ptr %case_r1018, ptr %res_slot960
  br label %case_merge239
case_default240:
  unreachable
case_merge239:
  %case_r1019 = load ptr, ptr %res_slot960
  ret ptr %case_r1019
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld1020 = load ptr, ptr %req.addr
  %res_slot1021 = alloca ptr
  %tgp1022 = getelementptr i8, ptr %ld1020, i64 8
  %tag1023 = load i32, ptr %tgp1022, align 4
  switch i32 %tag1023, label %case_default263 [
      i32 0, label %case_br264
  ]
case_br264:
  %fp1024 = getelementptr i8, ptr %ld1020, i64 16
  %fv1025 = load ptr, ptr %fp1024, align 8
  %$f648.addr = alloca ptr
  store ptr %fv1025, ptr %$f648.addr
  %fp1026 = getelementptr i8, ptr %ld1020, i64 24
  %fv1027 = load ptr, ptr %fp1026, align 8
  %$f649.addr = alloca ptr
  store ptr %fv1027, ptr %$f649.addr
  %fp1028 = getelementptr i8, ptr %ld1020, i64 32
  %fv1029 = load ptr, ptr %fp1028, align 8
  %$f650.addr = alloca ptr
  store ptr %fv1029, ptr %$f650.addr
  %fp1030 = getelementptr i8, ptr %ld1020, i64 40
  %fv1031 = load ptr, ptr %fp1030, align 8
  %$f651.addr = alloca ptr
  store ptr %fv1031, ptr %$f651.addr
  %fp1032 = getelementptr i8, ptr %ld1020, i64 48
  %fv1033 = load ptr, ptr %fp1032, align 8
  %$f652.addr = alloca ptr
  store ptr %fv1033, ptr %$f652.addr
  %fp1034 = getelementptr i8, ptr %ld1020, i64 56
  %fv1035 = load ptr, ptr %fp1034, align 8
  %$f653.addr = alloca ptr
  store ptr %fv1035, ptr %$f653.addr
  %fp1036 = getelementptr i8, ptr %ld1020, i64 64
  %fv1037 = load ptr, ptr %fp1036, align 8
  %$f654.addr = alloca ptr
  store ptr %fv1037, ptr %$f654.addr
  %fp1038 = getelementptr i8, ptr %ld1020, i64 72
  %fv1039 = load ptr, ptr %fp1038, align 8
  %$f655.addr = alloca ptr
  store ptr %fv1039, ptr %$f655.addr
  %ld1040 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld1040, ptr %hd.addr
  %ld1041 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld1041, ptr %q.addr
  %ld1042 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld1042, ptr %pa.addr
  %ld1043 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld1043, ptr %p.addr
  %ld1044 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld1044, ptr %h.addr
  %ld1045 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld1045, ptr %sc.addr
  %ld1046 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld1046, ptr %m.addr
  %ld1047 = load ptr, ptr %req.addr
  %ld1048 = load ptr, ptr %m.addr
  %ld1049 = load ptr, ptr %sc.addr
  %ld1050 = load ptr, ptr %h.addr
  %ld1051 = load ptr, ptr %p.addr
  %ld1052 = load ptr, ptr %pa.addr
  %ld1053 = load ptr, ptr %q.addr
  %ld1054 = load ptr, ptr %hd.addr
  %ld1055 = load ptr, ptr %new_body.addr
  %rc1056 = load i64, ptr %ld1047, align 8
  %uniq1057 = icmp eq i64 %rc1056, 1
  %fbip_slot1058 = alloca ptr
  br i1 %uniq1057, label %fbip_reuse265, label %fbip_fresh266
fbip_reuse265:
  %tgp1059 = getelementptr i8, ptr %ld1047, i64 8
  store i32 0, ptr %tgp1059, align 4
  %fp1060 = getelementptr i8, ptr %ld1047, i64 16
  store ptr %ld1048, ptr %fp1060, align 8
  %fp1061 = getelementptr i8, ptr %ld1047, i64 24
  store ptr %ld1049, ptr %fp1061, align 8
  %fp1062 = getelementptr i8, ptr %ld1047, i64 32
  store ptr %ld1050, ptr %fp1062, align 8
  %fp1063 = getelementptr i8, ptr %ld1047, i64 40
  store ptr %ld1051, ptr %fp1063, align 8
  %fp1064 = getelementptr i8, ptr %ld1047, i64 48
  store ptr %ld1052, ptr %fp1064, align 8
  %fp1065 = getelementptr i8, ptr %ld1047, i64 56
  store ptr %ld1053, ptr %fp1065, align 8
  %fp1066 = getelementptr i8, ptr %ld1047, i64 64
  store ptr %ld1054, ptr %fp1066, align 8
  %fp1067 = getelementptr i8, ptr %ld1047, i64 72
  store ptr %ld1055, ptr %fp1067, align 8
  store ptr %ld1047, ptr %fbip_slot1058
  br label %fbip_merge267
fbip_fresh266:
  call void @march_decrc(ptr %ld1047)
  %hp1068 = call ptr @march_alloc(i64 80)
  %tgp1069 = getelementptr i8, ptr %hp1068, i64 8
  store i32 0, ptr %tgp1069, align 4
  %fp1070 = getelementptr i8, ptr %hp1068, i64 16
  store ptr %ld1048, ptr %fp1070, align 8
  %fp1071 = getelementptr i8, ptr %hp1068, i64 24
  store ptr %ld1049, ptr %fp1071, align 8
  %fp1072 = getelementptr i8, ptr %hp1068, i64 32
  store ptr %ld1050, ptr %fp1072, align 8
  %fp1073 = getelementptr i8, ptr %hp1068, i64 40
  store ptr %ld1051, ptr %fp1073, align 8
  %fp1074 = getelementptr i8, ptr %hp1068, i64 48
  store ptr %ld1052, ptr %fp1074, align 8
  %fp1075 = getelementptr i8, ptr %hp1068, i64 56
  store ptr %ld1053, ptr %fp1075, align 8
  %fp1076 = getelementptr i8, ptr %hp1068, i64 64
  store ptr %ld1054, ptr %fp1076, align 8
  %fp1077 = getelementptr i8, ptr %hp1068, i64 72
  store ptr %ld1055, ptr %fp1077, align 8
  store ptr %hp1068, ptr %fbip_slot1058
  br label %fbip_merge267
fbip_merge267:
  %fbip_r1078 = load ptr, ptr %fbip_slot1058
  store ptr %fbip_r1078, ptr %res_slot1021
  br label %case_merge262
case_default263:
  unreachable
case_merge262:
  %case_r1079 = load ptr, ptr %res_slot1021
  ret ptr %case_r1079
}

define ptr @Http.set_header$Request_V__3637$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1080 = load ptr, ptr %req.addr
  %res_slot1081 = alloca ptr
  %tgp1082 = getelementptr i8, ptr %ld1080, i64 8
  %tag1083 = load i32, ptr %tgp1082, align 4
  switch i32 %tag1083, label %case_default269 [
      i32 0, label %case_br270
  ]
case_br270:
  %fp1084 = getelementptr i8, ptr %ld1080, i64 16
  %fv1085 = load ptr, ptr %fp1084, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1085, ptr %$f658.addr
  %fp1086 = getelementptr i8, ptr %ld1080, i64 24
  %fv1087 = load ptr, ptr %fp1086, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1087, ptr %$f659.addr
  %fp1088 = getelementptr i8, ptr %ld1080, i64 32
  %fv1089 = load ptr, ptr %fp1088, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1089, ptr %$f660.addr
  %fp1090 = getelementptr i8, ptr %ld1080, i64 40
  %fv1091 = load ptr, ptr %fp1090, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1091, ptr %$f661.addr
  %fp1092 = getelementptr i8, ptr %ld1080, i64 48
  %fv1093 = load ptr, ptr %fp1092, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1093, ptr %$f662.addr
  %fp1094 = getelementptr i8, ptr %ld1080, i64 56
  %fv1095 = load ptr, ptr %fp1094, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1095, ptr %$f663.addr
  %fp1096 = getelementptr i8, ptr %ld1080, i64 64
  %fv1097 = load ptr, ptr %fp1096, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1097, ptr %$f664.addr
  %fp1098 = getelementptr i8, ptr %ld1080, i64 72
  %fv1099 = load ptr, ptr %fp1098, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1099, ptr %$f665.addr
  %ld1100 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1100, ptr %bd.addr
  %ld1101 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1101, ptr %hd.addr
  %ld1102 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1102, ptr %q.addr
  %ld1103 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1103, ptr %pa.addr
  %ld1104 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1104, ptr %p.addr
  %ld1105 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1105, ptr %h.addr
  %ld1106 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1106, ptr %sc.addr
  %ld1107 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1107, ptr %m.addr
  %hp1108 = call ptr @march_alloc(i64 32)
  %tgp1109 = getelementptr i8, ptr %hp1108, i64 8
  store i32 0, ptr %tgp1109, align 4
  %ld1110 = load ptr, ptr %name.addr
  %fp1111 = getelementptr i8, ptr %hp1108, i64 16
  store ptr %ld1110, ptr %fp1111, align 8
  %ld1112 = load ptr, ptr %value.addr
  %fp1113 = getelementptr i8, ptr %hp1108, i64 24
  store ptr %ld1112, ptr %fp1113, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1108, ptr %$t656.addr
  %hp1114 = call ptr @march_alloc(i64 32)
  %tgp1115 = getelementptr i8, ptr %hp1114, i64 8
  store i32 1, ptr %tgp1115, align 4
  %ld1116 = load ptr, ptr %$t656.addr
  %fp1117 = getelementptr i8, ptr %hp1114, i64 16
  store ptr %ld1116, ptr %fp1117, align 8
  %ld1118 = load ptr, ptr %hd.addr
  %fp1119 = getelementptr i8, ptr %hp1114, i64 24
  store ptr %ld1118, ptr %fp1119, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1114, ptr %$t657.addr
  %ld1120 = load ptr, ptr %req.addr
  %ld1121 = load ptr, ptr %m.addr
  %ld1122 = load ptr, ptr %sc.addr
  %ld1123 = load ptr, ptr %h.addr
  %ld1124 = load ptr, ptr %p.addr
  %ld1125 = load ptr, ptr %pa.addr
  %ld1126 = load ptr, ptr %q.addr
  %ld1127 = load ptr, ptr %$t657.addr
  %ld1128 = load ptr, ptr %bd.addr
  %rc1129 = load i64, ptr %ld1120, align 8
  %uniq1130 = icmp eq i64 %rc1129, 1
  %fbip_slot1131 = alloca ptr
  br i1 %uniq1130, label %fbip_reuse271, label %fbip_fresh272
fbip_reuse271:
  %tgp1132 = getelementptr i8, ptr %ld1120, i64 8
  store i32 0, ptr %tgp1132, align 4
  %fp1133 = getelementptr i8, ptr %ld1120, i64 16
  store ptr %ld1121, ptr %fp1133, align 8
  %fp1134 = getelementptr i8, ptr %ld1120, i64 24
  store ptr %ld1122, ptr %fp1134, align 8
  %fp1135 = getelementptr i8, ptr %ld1120, i64 32
  store ptr %ld1123, ptr %fp1135, align 8
  %fp1136 = getelementptr i8, ptr %ld1120, i64 40
  store ptr %ld1124, ptr %fp1136, align 8
  %fp1137 = getelementptr i8, ptr %ld1120, i64 48
  store ptr %ld1125, ptr %fp1137, align 8
  %fp1138 = getelementptr i8, ptr %ld1120, i64 56
  store ptr %ld1126, ptr %fp1138, align 8
  %fp1139 = getelementptr i8, ptr %ld1120, i64 64
  store ptr %ld1127, ptr %fp1139, align 8
  %fp1140 = getelementptr i8, ptr %ld1120, i64 72
  store ptr %ld1128, ptr %fp1140, align 8
  store ptr %ld1120, ptr %fbip_slot1131
  br label %fbip_merge273
fbip_fresh272:
  call void @march_decrc(ptr %ld1120)
  %hp1141 = call ptr @march_alloc(i64 80)
  %tgp1142 = getelementptr i8, ptr %hp1141, i64 8
  store i32 0, ptr %tgp1142, align 4
  %fp1143 = getelementptr i8, ptr %hp1141, i64 16
  store ptr %ld1121, ptr %fp1143, align 8
  %fp1144 = getelementptr i8, ptr %hp1141, i64 24
  store ptr %ld1122, ptr %fp1144, align 8
  %fp1145 = getelementptr i8, ptr %hp1141, i64 32
  store ptr %ld1123, ptr %fp1145, align 8
  %fp1146 = getelementptr i8, ptr %hp1141, i64 40
  store ptr %ld1124, ptr %fp1146, align 8
  %fp1147 = getelementptr i8, ptr %hp1141, i64 48
  store ptr %ld1125, ptr %fp1147, align 8
  %fp1148 = getelementptr i8, ptr %hp1141, i64 56
  store ptr %ld1126, ptr %fp1148, align 8
  %fp1149 = getelementptr i8, ptr %hp1141, i64 64
  store ptr %ld1127, ptr %fp1149, align 8
  %fp1150 = getelementptr i8, ptr %hp1141, i64 72
  store ptr %ld1128, ptr %fp1150, align 8
  store ptr %hp1141, ptr %fbip_slot1131
  br label %fbip_merge273
fbip_merge273:
  %fbip_r1151 = load ptr, ptr %fbip_slot1131
  store ptr %fbip_r1151, ptr %res_slot1081
  br label %case_merge268
case_default269:
  unreachable
case_merge268:
  %case_r1152 = load ptr, ptr %res_slot1081
  ret ptr %case_r1152
}

define ptr @Http.set_header$Request_V__3635$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1153 = load ptr, ptr %req.addr
  %res_slot1154 = alloca ptr
  %tgp1155 = getelementptr i8, ptr %ld1153, i64 8
  %tag1156 = load i32, ptr %tgp1155, align 4
  switch i32 %tag1156, label %case_default275 [
      i32 0, label %case_br276
  ]
case_br276:
  %fp1157 = getelementptr i8, ptr %ld1153, i64 16
  %fv1158 = load ptr, ptr %fp1157, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1158, ptr %$f658.addr
  %fp1159 = getelementptr i8, ptr %ld1153, i64 24
  %fv1160 = load ptr, ptr %fp1159, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1160, ptr %$f659.addr
  %fp1161 = getelementptr i8, ptr %ld1153, i64 32
  %fv1162 = load ptr, ptr %fp1161, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1162, ptr %$f660.addr
  %fp1163 = getelementptr i8, ptr %ld1153, i64 40
  %fv1164 = load ptr, ptr %fp1163, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1164, ptr %$f661.addr
  %fp1165 = getelementptr i8, ptr %ld1153, i64 48
  %fv1166 = load ptr, ptr %fp1165, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1166, ptr %$f662.addr
  %fp1167 = getelementptr i8, ptr %ld1153, i64 56
  %fv1168 = load ptr, ptr %fp1167, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1168, ptr %$f663.addr
  %fp1169 = getelementptr i8, ptr %ld1153, i64 64
  %fv1170 = load ptr, ptr %fp1169, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1170, ptr %$f664.addr
  %fp1171 = getelementptr i8, ptr %ld1153, i64 72
  %fv1172 = load ptr, ptr %fp1171, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1172, ptr %$f665.addr
  %ld1173 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1173, ptr %bd.addr
  %ld1174 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1174, ptr %hd.addr
  %ld1175 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1175, ptr %q.addr
  %ld1176 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1176, ptr %pa.addr
  %ld1177 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1177, ptr %p.addr
  %ld1178 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1178, ptr %h.addr
  %ld1179 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1179, ptr %sc.addr
  %ld1180 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1180, ptr %m.addr
  %hp1181 = call ptr @march_alloc(i64 32)
  %tgp1182 = getelementptr i8, ptr %hp1181, i64 8
  store i32 0, ptr %tgp1182, align 4
  %ld1183 = load ptr, ptr %name.addr
  %fp1184 = getelementptr i8, ptr %hp1181, i64 16
  store ptr %ld1183, ptr %fp1184, align 8
  %ld1185 = load ptr, ptr %value.addr
  %fp1186 = getelementptr i8, ptr %hp1181, i64 24
  store ptr %ld1185, ptr %fp1186, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1181, ptr %$t656.addr
  %hp1187 = call ptr @march_alloc(i64 32)
  %tgp1188 = getelementptr i8, ptr %hp1187, i64 8
  store i32 1, ptr %tgp1188, align 4
  %ld1189 = load ptr, ptr %$t656.addr
  %fp1190 = getelementptr i8, ptr %hp1187, i64 16
  store ptr %ld1189, ptr %fp1190, align 8
  %ld1191 = load ptr, ptr %hd.addr
  %fp1192 = getelementptr i8, ptr %hp1187, i64 24
  store ptr %ld1191, ptr %fp1192, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1187, ptr %$t657.addr
  %ld1193 = load ptr, ptr %req.addr
  %ld1194 = load ptr, ptr %m.addr
  %ld1195 = load ptr, ptr %sc.addr
  %ld1196 = load ptr, ptr %h.addr
  %ld1197 = load ptr, ptr %p.addr
  %ld1198 = load ptr, ptr %pa.addr
  %ld1199 = load ptr, ptr %q.addr
  %ld1200 = load ptr, ptr %$t657.addr
  %ld1201 = load ptr, ptr %bd.addr
  %rc1202 = load i64, ptr %ld1193, align 8
  %uniq1203 = icmp eq i64 %rc1202, 1
  %fbip_slot1204 = alloca ptr
  br i1 %uniq1203, label %fbip_reuse277, label %fbip_fresh278
fbip_reuse277:
  %tgp1205 = getelementptr i8, ptr %ld1193, i64 8
  store i32 0, ptr %tgp1205, align 4
  %fp1206 = getelementptr i8, ptr %ld1193, i64 16
  store ptr %ld1194, ptr %fp1206, align 8
  %fp1207 = getelementptr i8, ptr %ld1193, i64 24
  store ptr %ld1195, ptr %fp1207, align 8
  %fp1208 = getelementptr i8, ptr %ld1193, i64 32
  store ptr %ld1196, ptr %fp1208, align 8
  %fp1209 = getelementptr i8, ptr %ld1193, i64 40
  store ptr %ld1197, ptr %fp1209, align 8
  %fp1210 = getelementptr i8, ptr %ld1193, i64 48
  store ptr %ld1198, ptr %fp1210, align 8
  %fp1211 = getelementptr i8, ptr %ld1193, i64 56
  store ptr %ld1199, ptr %fp1211, align 8
  %fp1212 = getelementptr i8, ptr %ld1193, i64 64
  store ptr %ld1200, ptr %fp1212, align 8
  %fp1213 = getelementptr i8, ptr %ld1193, i64 72
  store ptr %ld1201, ptr %fp1213, align 8
  store ptr %ld1193, ptr %fbip_slot1204
  br label %fbip_merge279
fbip_fresh278:
  call void @march_decrc(ptr %ld1193)
  %hp1214 = call ptr @march_alloc(i64 80)
  %tgp1215 = getelementptr i8, ptr %hp1214, i64 8
  store i32 0, ptr %tgp1215, align 4
  %fp1216 = getelementptr i8, ptr %hp1214, i64 16
  store ptr %ld1194, ptr %fp1216, align 8
  %fp1217 = getelementptr i8, ptr %hp1214, i64 24
  store ptr %ld1195, ptr %fp1217, align 8
  %fp1218 = getelementptr i8, ptr %hp1214, i64 32
  store ptr %ld1196, ptr %fp1218, align 8
  %fp1219 = getelementptr i8, ptr %hp1214, i64 40
  store ptr %ld1197, ptr %fp1219, align 8
  %fp1220 = getelementptr i8, ptr %hp1214, i64 48
  store ptr %ld1198, ptr %fp1220, align 8
  %fp1221 = getelementptr i8, ptr %hp1214, i64 56
  store ptr %ld1199, ptr %fp1221, align 8
  %fp1222 = getelementptr i8, ptr %hp1214, i64 64
  store ptr %ld1200, ptr %fp1222, align 8
  %fp1223 = getelementptr i8, ptr %hp1214, i64 72
  store ptr %ld1201, ptr %fp1223, align 8
  store ptr %hp1214, ptr %fbip_slot1204
  br label %fbip_merge279
fbip_merge279:
  %fbip_r1224 = load ptr, ptr %fbip_slot1204
  store ptr %fbip_r1224, ptr %res_slot1154
  br label %case_merge274
case_default275:
  unreachable
case_merge274:
  %case_r1225 = load ptr, ptr %res_slot1154
  ret ptr %case_r1225
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld1226 = load ptr, ptr %xs.addr
  %res_slot1227 = alloca ptr
  %tgp1228 = getelementptr i8, ptr %ld1226, i64 8
  %tag1229 = load i32, ptr %tgp1228, align 4
  switch i32 %tag1229, label %case_default281 [
      i32 0, label %case_br282
      i32 1, label %case_br283
  ]
case_br282:
  %ld1230 = load ptr, ptr %xs.addr
  %rc1231 = load i64, ptr %ld1230, align 8
  %uniq1232 = icmp eq i64 %rc1231, 1
  %fbip_slot1233 = alloca ptr
  br i1 %uniq1232, label %fbip_reuse284, label %fbip_fresh285
fbip_reuse284:
  %tgp1234 = getelementptr i8, ptr %ld1230, i64 8
  store i32 0, ptr %tgp1234, align 4
  store ptr %ld1230, ptr %fbip_slot1233
  br label %fbip_merge286
fbip_fresh285:
  call void @march_decrc(ptr %ld1230)
  %hp1235 = call ptr @march_alloc(i64 16)
  %tgp1236 = getelementptr i8, ptr %hp1235, i64 8
  store i32 0, ptr %tgp1236, align 4
  store ptr %hp1235, ptr %fbip_slot1233
  br label %fbip_merge286
fbip_merge286:
  %fbip_r1237 = load ptr, ptr %fbip_slot1233
  %$t883.addr = alloca ptr
  store ptr %fbip_r1237, ptr %$t883.addr
  %hp1238 = call ptr @march_alloc(i64 32)
  %tgp1239 = getelementptr i8, ptr %hp1238, i64 8
  store i32 1, ptr %tgp1239, align 4
  %ld1240 = load ptr, ptr %x.addr
  %fp1241 = getelementptr i8, ptr %hp1238, i64 16
  store ptr %ld1240, ptr %fp1241, align 8
  %ld1242 = load ptr, ptr %$t883.addr
  %fp1243 = getelementptr i8, ptr %hp1238, i64 24
  store ptr %ld1242, ptr %fp1243, align 8
  store ptr %hp1238, ptr %res_slot1227
  br label %case_merge280
case_br283:
  %fp1244 = getelementptr i8, ptr %ld1226, i64 16
  %fv1245 = load ptr, ptr %fp1244, align 8
  %$f885.addr = alloca ptr
  store ptr %fv1245, ptr %$f885.addr
  %fp1246 = getelementptr i8, ptr %ld1226, i64 24
  %fv1247 = load ptr, ptr %fp1246, align 8
  %$f886.addr = alloca ptr
  store ptr %fv1247, ptr %$f886.addr
  %ld1248 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld1248, ptr %t.addr
  %ld1249 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld1249, ptr %h.addr
  %ld1250 = load ptr, ptr %t.addr
  %ld1251 = load ptr, ptr %x.addr
  %cr1252 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld1250, ptr %ld1251)
  %$t884.addr = alloca ptr
  store ptr %cr1252, ptr %$t884.addr
  %ld1253 = load ptr, ptr %xs.addr
  %ld1254 = load ptr, ptr %h.addr
  %ld1255 = load ptr, ptr %$t884.addr
  %rc1256 = load i64, ptr %ld1253, align 8
  %uniq1257 = icmp eq i64 %rc1256, 1
  %fbip_slot1258 = alloca ptr
  br i1 %uniq1257, label %fbip_reuse287, label %fbip_fresh288
fbip_reuse287:
  %tgp1259 = getelementptr i8, ptr %ld1253, i64 8
  store i32 1, ptr %tgp1259, align 4
  %fp1260 = getelementptr i8, ptr %ld1253, i64 16
  store ptr %ld1254, ptr %fp1260, align 8
  %fp1261 = getelementptr i8, ptr %ld1253, i64 24
  store ptr %ld1255, ptr %fp1261, align 8
  store ptr %ld1253, ptr %fbip_slot1258
  br label %fbip_merge289
fbip_fresh288:
  call void @march_decrc(ptr %ld1253)
  %hp1262 = call ptr @march_alloc(i64 32)
  %tgp1263 = getelementptr i8, ptr %hp1262, i64 8
  store i32 1, ptr %tgp1263, align 4
  %fp1264 = getelementptr i8, ptr %hp1262, i64 16
  store ptr %ld1254, ptr %fp1264, align 8
  %fp1265 = getelementptr i8, ptr %hp1262, i64 24
  store ptr %ld1255, ptr %fp1265, align 8
  store ptr %hp1262, ptr %fbip_slot1258
  br label %fbip_merge289
fbip_merge289:
  %fbip_r1266 = load ptr, ptr %fbip_slot1258
  store ptr %fbip_r1266, ptr %res_slot1227
  br label %case_merge280
case_default281:
  unreachable
case_merge280:
  %case_r1267 = load ptr, ptr %res_slot1227
  ret ptr %case_r1267
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
  %ld1268 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1268)
  %ld1269 = load ptr, ptr %fd.addr
  %cr1270 = call ptr @tcp_recv_chunked_frame(ptr %ld1269)
  %$t820.addr = alloca ptr
  store ptr %cr1270, ptr %$t820.addr
  %ld1271 = load ptr, ptr %$t820.addr
  %res_slot1272 = alloca ptr
  %tgp1273 = getelementptr i8, ptr %ld1271, i64 8
  %tag1274 = load i32, ptr %tgp1273, align 4
  switch i32 %tag1274, label %case_default291 [
      i32 1, label %case_br292
      i32 0, label %case_br293
  ]
case_br292:
  %fp1275 = getelementptr i8, ptr %ld1271, i64 16
  %fv1276 = load ptr, ptr %fp1275, align 8
  %$f824.addr = alloca ptr
  store ptr %fv1276, ptr %$f824.addr
  %freed1277 = call i64 @march_decrc_freed(ptr %ld1271)
  %freed_b1278 = icmp ne i64 %freed1277, 0
  br i1 %freed_b1278, label %br_unique294, label %br_shared295
br_shared295:
  call void @march_incrc(ptr %fv1276)
  br label %br_body296
br_unique294:
  br label %br_body296
br_body296:
  %ld1279 = load ptr, ptr %$f824.addr
  %msg.addr = alloca ptr
  store ptr %ld1279, ptr %msg.addr
  %hp1280 = call ptr @march_alloc(i64 24)
  %tgp1281 = getelementptr i8, ptr %hp1280, i64 8
  store i32 3, ptr %tgp1281, align 4
  %ld1282 = load ptr, ptr %msg.addr
  %fp1283 = getelementptr i8, ptr %hp1280, i64 16
  store ptr %ld1282, ptr %fp1283, align 8
  %$t821.addr = alloca ptr
  store ptr %hp1280, ptr %$t821.addr
  %hp1284 = call ptr @march_alloc(i64 24)
  %tgp1285 = getelementptr i8, ptr %hp1284, i64 8
  store i32 1, ptr %tgp1285, align 4
  %ld1286 = load ptr, ptr %$t821.addr
  %fp1287 = getelementptr i8, ptr %hp1284, i64 16
  store ptr %ld1286, ptr %fp1287, align 8
  store ptr %hp1284, ptr %res_slot1272
  br label %case_merge290
case_br293:
  %fp1288 = getelementptr i8, ptr %ld1271, i64 16
  %fv1289 = load ptr, ptr %fp1288, align 8
  %$f825.addr = alloca ptr
  store ptr %fv1289, ptr %$f825.addr
  %freed1290 = call i64 @march_decrc_freed(ptr %ld1271)
  %freed_b1291 = icmp ne i64 %freed1290, 0
  br i1 %freed_b1291, label %br_unique297, label %br_shared298
br_shared298:
  call void @march_incrc(ptr %fv1289)
  br label %br_body299
br_unique297:
  br label %br_body299
br_body299:
  %ld1292 = load ptr, ptr %$f825.addr
  %res_slot1293 = alloca ptr
  %sl1294 = call ptr @march_string_lit(ptr @.str42, i64 0)
  %seq1295 = call i64 @march_string_eq(ptr %ld1292, ptr %sl1294)
  %cmp1296 = icmp ne i64 %seq1295, 0
  br i1 %cmp1296, label %case_br302, label %str_next303
str_next303:
  br label %case_default301
case_br302:
  %ld1297 = load ptr, ptr %$f825.addr
  call void @march_decrc(ptr %ld1297)
  %cv1298 = inttoptr i64 0 to ptr
  %$t822.addr = alloca ptr
  store ptr %cv1298, ptr %$t822.addr
  %hp1299 = call ptr @march_alloc(i64 40)
  %tgp1300 = getelementptr i8, ptr %hp1299, i64 8
  store i32 0, ptr %tgp1300, align 4
  %ld1301 = load ptr, ptr %status_code.addr
  %fp1302 = getelementptr i8, ptr %hp1299, i64 16
  store ptr %ld1301, ptr %fp1302, align 8
  %ld1303 = load ptr, ptr %resp_headers.addr
  %fp1304 = getelementptr i8, ptr %hp1299, i64 24
  store ptr %ld1303, ptr %fp1304, align 8
  %ld1305 = load ptr, ptr %$t822.addr
  %fp1306 = getelementptr i8, ptr %hp1299, i64 32
  store ptr %ld1305, ptr %fp1306, align 8
  %$t823.addr = alloca ptr
  store ptr %hp1299, ptr %$t823.addr
  %hp1307 = call ptr @march_alloc(i64 24)
  %tgp1308 = getelementptr i8, ptr %hp1307, i64 8
  store i32 0, ptr %tgp1308, align 4
  %ld1309 = load ptr, ptr %$t823.addr
  %fp1310 = getelementptr i8, ptr %hp1307, i64 16
  store ptr %ld1309, ptr %fp1310, align 8
  store ptr %hp1307, ptr %res_slot1293
  br label %case_merge300
case_default301:
  %ld1311 = load ptr, ptr %$f825.addr
  %chunk.addr = alloca ptr
  store ptr %ld1311, ptr %chunk.addr
  %ld1312 = load ptr, ptr %on_chunk.addr
  %fp1313 = getelementptr i8, ptr %ld1312, i64 16
  %fv1314 = load ptr, ptr %fp1313, align 8
  %ld1315 = load ptr, ptr %chunk.addr
  %cr1316 = call ptr (ptr, ptr) %fv1314(ptr %ld1312, ptr %ld1315)
  %ld1317 = load ptr, ptr %fd.addr
  %ld1318 = load ptr, ptr %on_chunk.addr
  %ld1319 = load ptr, ptr %status_code.addr
  %ld1320 = load ptr, ptr %resp_headers.addr
  %cr1321 = call ptr @HttpTransport.stream_chunked_body$V__2823$Fn_String_T_$V__2865$V__2866(ptr %ld1317, ptr %ld1318, ptr %ld1319, ptr %ld1320)
  store ptr %cr1321, ptr %res_slot1293
  br label %case_merge300
case_merge300:
  %case_r1322 = load ptr, ptr %res_slot1293
  store ptr %case_r1322, ptr %res_slot1272
  br label %case_merge290
case_default291:
  unreachable
case_merge290:
  %case_r1323 = load ptr, ptr %res_slot1272
  ret ptr %case_r1323
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
  %ld1324 = load i64, ptr %remaining.addr
  %cmp1325 = icmp eq i64 %ld1324, 0
  %ar1326 = zext i1 %cmp1325 to i64
  %$t826.addr = alloca i64
  store i64 %ar1326, ptr %$t826.addr
  %ld1327 = load i64, ptr %$t826.addr
  %res_slot1328 = alloca ptr
  %bi1329 = trunc i64 %ld1327 to i1
  br i1 %bi1329, label %case_br306, label %case_default305
case_br306:
  %cv1330 = inttoptr i64 0 to ptr
  %$t827.addr = alloca ptr
  store ptr %cv1330, ptr %$t827.addr
  %hp1331 = call ptr @march_alloc(i64 40)
  %tgp1332 = getelementptr i8, ptr %hp1331, i64 8
  store i32 0, ptr %tgp1332, align 4
  %ld1333 = load ptr, ptr %status_code.addr
  %fp1334 = getelementptr i8, ptr %hp1331, i64 16
  store ptr %ld1333, ptr %fp1334, align 8
  %ld1335 = load ptr, ptr %resp_headers.addr
  %fp1336 = getelementptr i8, ptr %hp1331, i64 24
  store ptr %ld1335, ptr %fp1336, align 8
  %ld1337 = load ptr, ptr %$t827.addr
  %fp1338 = getelementptr i8, ptr %hp1331, i64 32
  store ptr %ld1337, ptr %fp1338, align 8
  %$t828.addr = alloca ptr
  store ptr %hp1331, ptr %$t828.addr
  %hp1339 = call ptr @march_alloc(i64 24)
  %tgp1340 = getelementptr i8, ptr %hp1339, i64 8
  store i32 0, ptr %tgp1340, align 4
  %ld1341 = load ptr, ptr %$t828.addr
  %fp1342 = getelementptr i8, ptr %hp1339, i64 16
  store ptr %ld1341, ptr %fp1342, align 8
  store ptr %hp1339, ptr %res_slot1328
  br label %case_merge304
case_default305:
  %ld1343 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1343)
  %ld1344 = load ptr, ptr %fd.addr
  %ld1345 = load i64, ptr %remaining.addr
  %cr1346 = call ptr @tcp_recv_chunk(ptr %ld1344, i64 %ld1345)
  %$t829.addr = alloca ptr
  store ptr %cr1346, ptr %$t829.addr
  %ld1347 = load ptr, ptr %$t829.addr
  %res_slot1348 = alloca ptr
  %tgp1349 = getelementptr i8, ptr %ld1347, i64 8
  %tag1350 = load i32, ptr %tgp1349, align 4
  switch i32 %tag1350, label %case_default308 [
      i32 1, label %case_br309
      i32 0, label %case_br310
  ]
case_br309:
  %fp1351 = getelementptr i8, ptr %ld1347, i64 16
  %fv1352 = load ptr, ptr %fp1351, align 8
  %$f835.addr = alloca ptr
  store ptr %fv1352, ptr %$f835.addr
  %freed1353 = call i64 @march_decrc_freed(ptr %ld1347)
  %freed_b1354 = icmp ne i64 %freed1353, 0
  br i1 %freed_b1354, label %br_unique311, label %br_shared312
br_shared312:
  call void @march_incrc(ptr %fv1352)
  br label %br_body313
br_unique311:
  br label %br_body313
br_body313:
  %ld1355 = load ptr, ptr %$f835.addr
  %msg.addr = alloca ptr
  store ptr %ld1355, ptr %msg.addr
  %hp1356 = call ptr @march_alloc(i64 24)
  %tgp1357 = getelementptr i8, ptr %hp1356, i64 8
  store i32 3, ptr %tgp1357, align 4
  %ld1358 = load ptr, ptr %msg.addr
  %fp1359 = getelementptr i8, ptr %hp1356, i64 16
  store ptr %ld1358, ptr %fp1359, align 8
  %$t830.addr = alloca ptr
  store ptr %hp1356, ptr %$t830.addr
  %hp1360 = call ptr @march_alloc(i64 24)
  %tgp1361 = getelementptr i8, ptr %hp1360, i64 8
  store i32 1, ptr %tgp1361, align 4
  %ld1362 = load ptr, ptr %$t830.addr
  %fp1363 = getelementptr i8, ptr %hp1360, i64 16
  store ptr %ld1362, ptr %fp1363, align 8
  store ptr %hp1360, ptr %res_slot1348
  br label %case_merge307
case_br310:
  %fp1364 = getelementptr i8, ptr %ld1347, i64 16
  %fv1365 = load ptr, ptr %fp1364, align 8
  %$f836.addr = alloca ptr
  store ptr %fv1365, ptr %$f836.addr
  %freed1366 = call i64 @march_decrc_freed(ptr %ld1347)
  %freed_b1367 = icmp ne i64 %freed1366, 0
  br i1 %freed_b1367, label %br_unique314, label %br_shared315
br_shared315:
  call void @march_incrc(ptr %fv1365)
  br label %br_body316
br_unique314:
  br label %br_body316
br_body316:
  %ld1368 = load ptr, ptr %$f836.addr
  %res_slot1369 = alloca ptr
  %sl1370 = call ptr @march_string_lit(ptr @.str43, i64 0)
  %seq1371 = call i64 @march_string_eq(ptr %ld1368, ptr %sl1370)
  %cmp1372 = icmp ne i64 %seq1371, 0
  br i1 %cmp1372, label %case_br319, label %str_next320
str_next320:
  br label %case_default318
case_br319:
  %ld1373 = load ptr, ptr %$f836.addr
  call void @march_decrc(ptr %ld1373)
  %cv1374 = inttoptr i64 0 to ptr
  %$t831.addr = alloca ptr
  store ptr %cv1374, ptr %$t831.addr
  %hp1375 = call ptr @march_alloc(i64 40)
  %tgp1376 = getelementptr i8, ptr %hp1375, i64 8
  store i32 0, ptr %tgp1376, align 4
  %ld1377 = load ptr, ptr %status_code.addr
  %fp1378 = getelementptr i8, ptr %hp1375, i64 16
  store ptr %ld1377, ptr %fp1378, align 8
  %ld1379 = load ptr, ptr %resp_headers.addr
  %fp1380 = getelementptr i8, ptr %hp1375, i64 24
  store ptr %ld1379, ptr %fp1380, align 8
  %ld1381 = load ptr, ptr %$t831.addr
  %fp1382 = getelementptr i8, ptr %hp1375, i64 32
  store ptr %ld1381, ptr %fp1382, align 8
  %$t832.addr = alloca ptr
  store ptr %hp1375, ptr %$t832.addr
  %hp1383 = call ptr @march_alloc(i64 24)
  %tgp1384 = getelementptr i8, ptr %hp1383, i64 8
  store i32 0, ptr %tgp1384, align 4
  %ld1385 = load ptr, ptr %$t832.addr
  %fp1386 = getelementptr i8, ptr %hp1383, i64 16
  store ptr %ld1385, ptr %fp1386, align 8
  store ptr %hp1383, ptr %res_slot1369
  br label %case_merge317
case_default318:
  %ld1387 = load ptr, ptr %$f836.addr
  %chunk.addr = alloca ptr
  store ptr %ld1387, ptr %chunk.addr
  %ld1388 = load ptr, ptr %chunk.addr
  call void @march_incrc(ptr %ld1388)
  %ld1389 = load ptr, ptr %on_chunk.addr
  %fp1390 = getelementptr i8, ptr %ld1389, i64 16
  %fv1391 = load ptr, ptr %fp1390, align 8
  %ld1392 = load ptr, ptr %chunk.addr
  %cr1393 = call ptr (ptr, ptr) %fv1391(ptr %ld1389, ptr %ld1392)
  %ld1394 = load ptr, ptr %chunk.addr
  %cr1395 = call i64 @string_length(ptr %ld1394)
  %$t833.addr = alloca i64
  store i64 %cr1395, ptr %$t833.addr
  %ld1396 = load i64, ptr %remaining.addr
  %ld1397 = load i64, ptr %$t833.addr
  %ar1398 = sub i64 %ld1396, %ld1397
  %$t834.addr = alloca i64
  store i64 %ar1398, ptr %$t834.addr
  %ld1399 = load ptr, ptr %fd.addr
  %ld1400 = load i64, ptr %$t834.addr
  %ld1401 = load ptr, ptr %on_chunk.addr
  %ld1402 = load ptr, ptr %status_code.addr
  %ld1403 = load ptr, ptr %resp_headers.addr
  %cr1404 = call ptr @HttpTransport.stream_fixed_body$V__2823$Int$Fn_String_T_$V__2865$V__2866(ptr %ld1399, i64 %ld1400, ptr %ld1401, ptr %ld1402, ptr %ld1403)
  store ptr %cr1404, ptr %res_slot1369
  br label %case_merge317
case_merge317:
  %case_r1405 = load ptr, ptr %res_slot1369
  store ptr %case_r1405, ptr %res_slot1348
  br label %case_merge307
case_default308:
  unreachable
case_merge307:
  %case_r1406 = load ptr, ptr %res_slot1348
  store ptr %case_r1406, ptr %res_slot1328
  br label %case_merge304
case_merge304:
  %case_r1407 = load ptr, ptr %res_slot1328
  ret ptr %case_r1407
}

define ptr @Http.body$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1408 = load ptr, ptr %req.addr
  %res_slot1409 = alloca ptr
  %tgp1410 = getelementptr i8, ptr %ld1408, i64 8
  %tag1411 = load i32, ptr %tgp1410, align 4
  switch i32 %tag1411, label %case_default322 [
      i32 0, label %case_br323
  ]
case_br323:
  %fp1412 = getelementptr i8, ptr %ld1408, i64 16
  %fv1413 = load ptr, ptr %fp1412, align 8
  %$f599.addr = alloca ptr
  store ptr %fv1413, ptr %$f599.addr
  %fp1414 = getelementptr i8, ptr %ld1408, i64 24
  %fv1415 = load ptr, ptr %fp1414, align 8
  %$f600.addr = alloca ptr
  store ptr %fv1415, ptr %$f600.addr
  %fp1416 = getelementptr i8, ptr %ld1408, i64 32
  %fv1417 = load ptr, ptr %fp1416, align 8
  %$f601.addr = alloca ptr
  store ptr %fv1417, ptr %$f601.addr
  %fp1418 = getelementptr i8, ptr %ld1408, i64 40
  %fv1419 = load ptr, ptr %fp1418, align 8
  %$f602.addr = alloca ptr
  store ptr %fv1419, ptr %$f602.addr
  %fp1420 = getelementptr i8, ptr %ld1408, i64 48
  %fv1421 = load ptr, ptr %fp1420, align 8
  %$f603.addr = alloca ptr
  store ptr %fv1421, ptr %$f603.addr
  %fp1422 = getelementptr i8, ptr %ld1408, i64 56
  %fv1423 = load ptr, ptr %fp1422, align 8
  %$f604.addr = alloca ptr
  store ptr %fv1423, ptr %$f604.addr
  %fp1424 = getelementptr i8, ptr %ld1408, i64 64
  %fv1425 = load ptr, ptr %fp1424, align 8
  %$f605.addr = alloca ptr
  store ptr %fv1425, ptr %$f605.addr
  %fp1426 = getelementptr i8, ptr %ld1408, i64 72
  %fv1427 = load ptr, ptr %fp1426, align 8
  %$f606.addr = alloca ptr
  store ptr %fv1427, ptr %$f606.addr
  %freed1428 = call i64 @march_decrc_freed(ptr %ld1408)
  %freed_b1429 = icmp ne i64 %freed1428, 0
  br i1 %freed_b1429, label %br_unique324, label %br_shared325
br_shared325:
  call void @march_incrc(ptr %fv1427)
  call void @march_incrc(ptr %fv1425)
  call void @march_incrc(ptr %fv1423)
  call void @march_incrc(ptr %fv1421)
  call void @march_incrc(ptr %fv1419)
  call void @march_incrc(ptr %fv1417)
  call void @march_incrc(ptr %fv1415)
  call void @march_incrc(ptr %fv1413)
  br label %br_body326
br_unique324:
  br label %br_body326
br_body326:
  %ld1430 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld1430, ptr %b.addr
  %ld1431 = load ptr, ptr %b.addr
  store ptr %ld1431, ptr %res_slot1409
  br label %case_merge321
case_default322:
  unreachable
case_merge321:
  %case_r1432 = load ptr, ptr %res_slot1409
  ret ptr %case_r1432
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1433 = load ptr, ptr %req.addr
  %res_slot1434 = alloca ptr
  %tgp1435 = getelementptr i8, ptr %ld1433, i64 8
  %tag1436 = load i32, ptr %tgp1435, align 4
  switch i32 %tag1436, label %case_default328 [
      i32 0, label %case_br329
  ]
case_br329:
  %fp1437 = getelementptr i8, ptr %ld1433, i64 16
  %fv1438 = load ptr, ptr %fp1437, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1438, ptr %$f591.addr
  %fp1439 = getelementptr i8, ptr %ld1433, i64 24
  %fv1440 = load ptr, ptr %fp1439, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1440, ptr %$f592.addr
  %fp1441 = getelementptr i8, ptr %ld1433, i64 32
  %fv1442 = load ptr, ptr %fp1441, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1442, ptr %$f593.addr
  %fp1443 = getelementptr i8, ptr %ld1433, i64 40
  %fv1444 = load ptr, ptr %fp1443, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1444, ptr %$f594.addr
  %fp1445 = getelementptr i8, ptr %ld1433, i64 48
  %fv1446 = load ptr, ptr %fp1445, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1446, ptr %$f595.addr
  %fp1447 = getelementptr i8, ptr %ld1433, i64 56
  %fv1448 = load ptr, ptr %fp1447, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1448, ptr %$f596.addr
  %fp1449 = getelementptr i8, ptr %ld1433, i64 64
  %fv1450 = load ptr, ptr %fp1449, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1450, ptr %$f597.addr
  %fp1451 = getelementptr i8, ptr %ld1433, i64 72
  %fv1452 = load ptr, ptr %fp1451, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1452, ptr %$f598.addr
  %freed1453 = call i64 @march_decrc_freed(ptr %ld1433)
  %freed_b1454 = icmp ne i64 %freed1453, 0
  br i1 %freed_b1454, label %br_unique330, label %br_shared331
br_shared331:
  call void @march_incrc(ptr %fv1452)
  call void @march_incrc(ptr %fv1450)
  call void @march_incrc(ptr %fv1448)
  call void @march_incrc(ptr %fv1446)
  call void @march_incrc(ptr %fv1444)
  call void @march_incrc(ptr %fv1442)
  call void @march_incrc(ptr %fv1440)
  call void @march_incrc(ptr %fv1438)
  br label %br_body332
br_unique330:
  br label %br_body332
br_body332:
  %ld1455 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1455, ptr %h.addr
  %ld1456 = load ptr, ptr %h.addr
  store ptr %ld1456, ptr %res_slot1434
  br label %case_merge327
case_default328:
  unreachable
case_merge327:
  %case_r1457 = load ptr, ptr %res_slot1434
  ret ptr %case_r1457
}

define ptr @Http.query$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1458 = load ptr, ptr %req.addr
  %res_slot1459 = alloca ptr
  %tgp1460 = getelementptr i8, ptr %ld1458, i64 8
  %tag1461 = load i32, ptr %tgp1460, align 4
  switch i32 %tag1461, label %case_default334 [
      i32 0, label %case_br335
  ]
case_br335:
  %fp1462 = getelementptr i8, ptr %ld1458, i64 16
  %fv1463 = load ptr, ptr %fp1462, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1463, ptr %$f583.addr
  %fp1464 = getelementptr i8, ptr %ld1458, i64 24
  %fv1465 = load ptr, ptr %fp1464, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1465, ptr %$f584.addr
  %fp1466 = getelementptr i8, ptr %ld1458, i64 32
  %fv1467 = load ptr, ptr %fp1466, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1467, ptr %$f585.addr
  %fp1468 = getelementptr i8, ptr %ld1458, i64 40
  %fv1469 = load ptr, ptr %fp1468, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1469, ptr %$f586.addr
  %fp1470 = getelementptr i8, ptr %ld1458, i64 48
  %fv1471 = load ptr, ptr %fp1470, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1471, ptr %$f587.addr
  %fp1472 = getelementptr i8, ptr %ld1458, i64 56
  %fv1473 = load ptr, ptr %fp1472, align 8
  %$f588.addr = alloca ptr
  store ptr %fv1473, ptr %$f588.addr
  %fp1474 = getelementptr i8, ptr %ld1458, i64 64
  %fv1475 = load ptr, ptr %fp1474, align 8
  %$f589.addr = alloca ptr
  store ptr %fv1475, ptr %$f589.addr
  %fp1476 = getelementptr i8, ptr %ld1458, i64 72
  %fv1477 = load ptr, ptr %fp1476, align 8
  %$f590.addr = alloca ptr
  store ptr %fv1477, ptr %$f590.addr
  %freed1478 = call i64 @march_decrc_freed(ptr %ld1458)
  %freed_b1479 = icmp ne i64 %freed1478, 0
  br i1 %freed_b1479, label %br_unique336, label %br_shared337
br_shared337:
  call void @march_incrc(ptr %fv1477)
  call void @march_incrc(ptr %fv1475)
  call void @march_incrc(ptr %fv1473)
  call void @march_incrc(ptr %fv1471)
  call void @march_incrc(ptr %fv1469)
  call void @march_incrc(ptr %fv1467)
  call void @march_incrc(ptr %fv1465)
  call void @march_incrc(ptr %fv1463)
  br label %br_body338
br_unique336:
  br label %br_body338
br_body338:
  %ld1480 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld1480, ptr %q.addr
  %ld1481 = load ptr, ptr %q.addr
  store ptr %ld1481, ptr %res_slot1459
  br label %case_merge333
case_default334:
  unreachable
case_merge333:
  %case_r1482 = load ptr, ptr %res_slot1459
  ret ptr %case_r1482
}

define ptr @Http.path$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1483 = load ptr, ptr %req.addr
  %res_slot1484 = alloca ptr
  %tgp1485 = getelementptr i8, ptr %ld1483, i64 8
  %tag1486 = load i32, ptr %tgp1485, align 4
  switch i32 %tag1486, label %case_default340 [
      i32 0, label %case_br341
  ]
case_br341:
  %fp1487 = getelementptr i8, ptr %ld1483, i64 16
  %fv1488 = load ptr, ptr %fp1487, align 8
  %$f575.addr = alloca ptr
  store ptr %fv1488, ptr %$f575.addr
  %fp1489 = getelementptr i8, ptr %ld1483, i64 24
  %fv1490 = load ptr, ptr %fp1489, align 8
  %$f576.addr = alloca ptr
  store ptr %fv1490, ptr %$f576.addr
  %fp1491 = getelementptr i8, ptr %ld1483, i64 32
  %fv1492 = load ptr, ptr %fp1491, align 8
  %$f577.addr = alloca ptr
  store ptr %fv1492, ptr %$f577.addr
  %fp1493 = getelementptr i8, ptr %ld1483, i64 40
  %fv1494 = load ptr, ptr %fp1493, align 8
  %$f578.addr = alloca ptr
  store ptr %fv1494, ptr %$f578.addr
  %fp1495 = getelementptr i8, ptr %ld1483, i64 48
  %fv1496 = load ptr, ptr %fp1495, align 8
  %$f579.addr = alloca ptr
  store ptr %fv1496, ptr %$f579.addr
  %fp1497 = getelementptr i8, ptr %ld1483, i64 56
  %fv1498 = load ptr, ptr %fp1497, align 8
  %$f580.addr = alloca ptr
  store ptr %fv1498, ptr %$f580.addr
  %fp1499 = getelementptr i8, ptr %ld1483, i64 64
  %fv1500 = load ptr, ptr %fp1499, align 8
  %$f581.addr = alloca ptr
  store ptr %fv1500, ptr %$f581.addr
  %fp1501 = getelementptr i8, ptr %ld1483, i64 72
  %fv1502 = load ptr, ptr %fp1501, align 8
  %$f582.addr = alloca ptr
  store ptr %fv1502, ptr %$f582.addr
  %freed1503 = call i64 @march_decrc_freed(ptr %ld1483)
  %freed_b1504 = icmp ne i64 %freed1503, 0
  br i1 %freed_b1504, label %br_unique342, label %br_shared343
br_shared343:
  call void @march_incrc(ptr %fv1502)
  call void @march_incrc(ptr %fv1500)
  call void @march_incrc(ptr %fv1498)
  call void @march_incrc(ptr %fv1496)
  call void @march_incrc(ptr %fv1494)
  call void @march_incrc(ptr %fv1492)
  call void @march_incrc(ptr %fv1490)
  call void @march_incrc(ptr %fv1488)
  br label %br_body344
br_unique342:
  br label %br_body344
br_body344:
  %ld1505 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld1505, ptr %p.addr
  %ld1506 = load ptr, ptr %p.addr
  store ptr %ld1506, ptr %res_slot1484
  br label %case_merge339
case_default340:
  unreachable
case_merge339:
  %case_r1507 = load ptr, ptr %res_slot1484
  ret ptr %case_r1507
}

define ptr @Http.host$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1508 = load ptr, ptr %req.addr
  %res_slot1509 = alloca ptr
  %tgp1510 = getelementptr i8, ptr %ld1508, i64 8
  %tag1511 = load i32, ptr %tgp1510, align 4
  switch i32 %tag1511, label %case_default346 [
      i32 0, label %case_br347
  ]
case_br347:
  %fp1512 = getelementptr i8, ptr %ld1508, i64 16
  %fv1513 = load ptr, ptr %fp1512, align 8
  %$f559.addr = alloca ptr
  store ptr %fv1513, ptr %$f559.addr
  %fp1514 = getelementptr i8, ptr %ld1508, i64 24
  %fv1515 = load ptr, ptr %fp1514, align 8
  %$f560.addr = alloca ptr
  store ptr %fv1515, ptr %$f560.addr
  %fp1516 = getelementptr i8, ptr %ld1508, i64 32
  %fv1517 = load ptr, ptr %fp1516, align 8
  %$f561.addr = alloca ptr
  store ptr %fv1517, ptr %$f561.addr
  %fp1518 = getelementptr i8, ptr %ld1508, i64 40
  %fv1519 = load ptr, ptr %fp1518, align 8
  %$f562.addr = alloca ptr
  store ptr %fv1519, ptr %$f562.addr
  %fp1520 = getelementptr i8, ptr %ld1508, i64 48
  %fv1521 = load ptr, ptr %fp1520, align 8
  %$f563.addr = alloca ptr
  store ptr %fv1521, ptr %$f563.addr
  %fp1522 = getelementptr i8, ptr %ld1508, i64 56
  %fv1523 = load ptr, ptr %fp1522, align 8
  %$f564.addr = alloca ptr
  store ptr %fv1523, ptr %$f564.addr
  %fp1524 = getelementptr i8, ptr %ld1508, i64 64
  %fv1525 = load ptr, ptr %fp1524, align 8
  %$f565.addr = alloca ptr
  store ptr %fv1525, ptr %$f565.addr
  %fp1526 = getelementptr i8, ptr %ld1508, i64 72
  %fv1527 = load ptr, ptr %fp1526, align 8
  %$f566.addr = alloca ptr
  store ptr %fv1527, ptr %$f566.addr
  %freed1528 = call i64 @march_decrc_freed(ptr %ld1508)
  %freed_b1529 = icmp ne i64 %freed1528, 0
  br i1 %freed_b1529, label %br_unique348, label %br_shared349
br_shared349:
  call void @march_incrc(ptr %fv1527)
  call void @march_incrc(ptr %fv1525)
  call void @march_incrc(ptr %fv1523)
  call void @march_incrc(ptr %fv1521)
  call void @march_incrc(ptr %fv1519)
  call void @march_incrc(ptr %fv1517)
  call void @march_incrc(ptr %fv1515)
  call void @march_incrc(ptr %fv1513)
  br label %br_body350
br_unique348:
  br label %br_body350
br_body350:
  %ld1530 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld1530, ptr %h.addr
  %ld1531 = load ptr, ptr %h.addr
  store ptr %ld1531, ptr %res_slot1509
  br label %case_merge345
case_default346:
  unreachable
case_merge345:
  %case_r1532 = load ptr, ptr %res_slot1509
  ret ptr %case_r1532
}

define ptr @Http.method$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1533 = load ptr, ptr %req.addr
  %res_slot1534 = alloca ptr
  %tgp1535 = getelementptr i8, ptr %ld1533, i64 8
  %tag1536 = load i32, ptr %tgp1535, align 4
  switch i32 %tag1536, label %case_default352 [
      i32 0, label %case_br353
  ]
case_br353:
  %fp1537 = getelementptr i8, ptr %ld1533, i64 16
  %fv1538 = load ptr, ptr %fp1537, align 8
  %$f543.addr = alloca ptr
  store ptr %fv1538, ptr %$f543.addr
  %fp1539 = getelementptr i8, ptr %ld1533, i64 24
  %fv1540 = load ptr, ptr %fp1539, align 8
  %$f544.addr = alloca ptr
  store ptr %fv1540, ptr %$f544.addr
  %fp1541 = getelementptr i8, ptr %ld1533, i64 32
  %fv1542 = load ptr, ptr %fp1541, align 8
  %$f545.addr = alloca ptr
  store ptr %fv1542, ptr %$f545.addr
  %fp1543 = getelementptr i8, ptr %ld1533, i64 40
  %fv1544 = load ptr, ptr %fp1543, align 8
  %$f546.addr = alloca ptr
  store ptr %fv1544, ptr %$f546.addr
  %fp1545 = getelementptr i8, ptr %ld1533, i64 48
  %fv1546 = load ptr, ptr %fp1545, align 8
  %$f547.addr = alloca ptr
  store ptr %fv1546, ptr %$f547.addr
  %fp1547 = getelementptr i8, ptr %ld1533, i64 56
  %fv1548 = load ptr, ptr %fp1547, align 8
  %$f548.addr = alloca ptr
  store ptr %fv1548, ptr %$f548.addr
  %fp1549 = getelementptr i8, ptr %ld1533, i64 64
  %fv1550 = load ptr, ptr %fp1549, align 8
  %$f549.addr = alloca ptr
  store ptr %fv1550, ptr %$f549.addr
  %fp1551 = getelementptr i8, ptr %ld1533, i64 72
  %fv1552 = load ptr, ptr %fp1551, align 8
  %$f550.addr = alloca ptr
  store ptr %fv1552, ptr %$f550.addr
  %freed1553 = call i64 @march_decrc_freed(ptr %ld1533)
  %freed_b1554 = icmp ne i64 %freed1553, 0
  br i1 %freed_b1554, label %br_unique354, label %br_shared355
br_shared355:
  call void @march_incrc(ptr %fv1552)
  call void @march_incrc(ptr %fv1550)
  call void @march_incrc(ptr %fv1548)
  call void @march_incrc(ptr %fv1546)
  call void @march_incrc(ptr %fv1544)
  call void @march_incrc(ptr %fv1542)
  call void @march_incrc(ptr %fv1540)
  call void @march_incrc(ptr %fv1538)
  br label %br_body356
br_unique354:
  br label %br_body356
br_body356:
  %ld1555 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld1555, ptr %m.addr
  %ld1556 = load ptr, ptr %m.addr
  store ptr %ld1556, ptr %res_slot1534
  br label %case_merge351
case_default352:
  unreachable
case_merge351:
  %case_r1557 = load ptr, ptr %res_slot1534
  ret ptr %case_r1557
}

define ptr @Http.port$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1558 = load ptr, ptr %req.addr
  %res_slot1559 = alloca ptr
  %tgp1560 = getelementptr i8, ptr %ld1558, i64 8
  %tag1561 = load i32, ptr %tgp1560, align 4
  switch i32 %tag1561, label %case_default358 [
      i32 0, label %case_br359
  ]
case_br359:
  %fp1562 = getelementptr i8, ptr %ld1558, i64 16
  %fv1563 = load ptr, ptr %fp1562, align 8
  %$f567.addr = alloca ptr
  store ptr %fv1563, ptr %$f567.addr
  %fp1564 = getelementptr i8, ptr %ld1558, i64 24
  %fv1565 = load ptr, ptr %fp1564, align 8
  %$f568.addr = alloca ptr
  store ptr %fv1565, ptr %$f568.addr
  %fp1566 = getelementptr i8, ptr %ld1558, i64 32
  %fv1567 = load ptr, ptr %fp1566, align 8
  %$f569.addr = alloca ptr
  store ptr %fv1567, ptr %$f569.addr
  %fp1568 = getelementptr i8, ptr %ld1558, i64 40
  %fv1569 = load ptr, ptr %fp1568, align 8
  %$f570.addr = alloca ptr
  store ptr %fv1569, ptr %$f570.addr
  %fp1570 = getelementptr i8, ptr %ld1558, i64 48
  %fv1571 = load ptr, ptr %fp1570, align 8
  %$f571.addr = alloca ptr
  store ptr %fv1571, ptr %$f571.addr
  %fp1572 = getelementptr i8, ptr %ld1558, i64 56
  %fv1573 = load ptr, ptr %fp1572, align 8
  %$f572.addr = alloca ptr
  store ptr %fv1573, ptr %$f572.addr
  %fp1574 = getelementptr i8, ptr %ld1558, i64 64
  %fv1575 = load ptr, ptr %fp1574, align 8
  %$f573.addr = alloca ptr
  store ptr %fv1575, ptr %$f573.addr
  %fp1576 = getelementptr i8, ptr %ld1558, i64 72
  %fv1577 = load ptr, ptr %fp1576, align 8
  %$f574.addr = alloca ptr
  store ptr %fv1577, ptr %$f574.addr
  %freed1578 = call i64 @march_decrc_freed(ptr %ld1558)
  %freed_b1579 = icmp ne i64 %freed1578, 0
  br i1 %freed_b1579, label %br_unique360, label %br_shared361
br_shared361:
  call void @march_incrc(ptr %fv1577)
  call void @march_incrc(ptr %fv1575)
  call void @march_incrc(ptr %fv1573)
  call void @march_incrc(ptr %fv1571)
  call void @march_incrc(ptr %fv1569)
  call void @march_incrc(ptr %fv1567)
  call void @march_incrc(ptr %fv1565)
  call void @march_incrc(ptr %fv1563)
  br label %br_body362
br_unique360:
  br label %br_body362
br_body362:
  %ld1580 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld1580, ptr %p.addr
  %ld1581 = load ptr, ptr %p.addr
  store ptr %ld1581, ptr %res_slot1559
  br label %case_merge357
case_default358:
  unreachable
case_merge357:
  %case_r1582 = load ptr, ptr %res_slot1559
  ret ptr %case_r1582
}

define ptr @print_chunk$apply$22(ptr %$clo.arg, ptr %chunk.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %chunk.addr = alloca ptr
  store ptr %chunk.arg, ptr %chunk.addr
  %ld1583 = load ptr, ptr %chunk.addr
  call void @march_incrc(ptr %ld1583)
  %ld1584 = load ptr, ptr %chunk.addr
  %cr1585 = call i64 @string_length(ptr %ld1584)
  %$t2009.addr = alloca i64
  store i64 %cr1585, ptr %$t2009.addr
  %ld1586 = load i64, ptr %$t2009.addr
  %cr1587 = call ptr @march_int_to_string(i64 %ld1586)
  %$t2010.addr = alloca ptr
  store ptr %cr1587, ptr %$t2010.addr
  %sl1588 = call ptr @march_string_lit(ptr @.str44, i64 7)
  %ld1589 = load ptr, ptr %$t2010.addr
  %cr1590 = call ptr @march_string_concat(ptr %sl1588, ptr %ld1589)
  %$t2011.addr = alloca ptr
  store ptr %cr1590, ptr %$t2011.addr
  %ld1591 = load ptr, ptr %$t2011.addr
  %sl1592 = call ptr @march_string_lit(ptr @.str45, i64 7)
  %cr1593 = call ptr @march_string_concat(ptr %ld1591, ptr %sl1592)
  %$t2012.addr = alloca ptr
  store ptr %cr1593, ptr %$t2012.addr
  %ld1594 = load ptr, ptr %$t2012.addr
  call void @march_print(ptr %ld1594)
  %ld1595 = load ptr, ptr %chunk.addr
  call void @march_print(ptr %ld1595)
  %cv1596 = inttoptr i64 0 to ptr
  ret ptr %cv1596
}

define ptr @count_bytes$apply$23(ptr %$clo.arg, ptr %chunk.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %chunk.addr = alloca ptr
  store ptr %chunk.arg, ptr %chunk.addr
  %ld1597 = load ptr, ptr %chunk.addr
  %cr1598 = call i64 @string_length(ptr %ld1597)
  %$t2021.addr = alloca i64
  store i64 %cr1598, ptr %$t2021.addr
  %ld1599 = load i64, ptr %$t2021.addr
  %cr1600 = call ptr @march_int_to_string(i64 %ld1599)
  %$t2022.addr = alloca ptr
  store ptr %cr1600, ptr %$t2022.addr
  %sl1601 = call ptr @march_string_lit(ptr @.str46, i64 11)
  %ld1602 = load ptr, ptr %$t2022.addr
  %cr1603 = call ptr @march_string_concat(ptr %sl1601, ptr %ld1602)
  %$t2023.addr = alloca ptr
  store ptr %cr1603, ptr %$t2023.addr
  %ld1604 = load ptr, ptr %$t2023.addr
  %sl1605 = call ptr @march_string_lit(ptr @.str47, i64 6)
  %cr1606 = call ptr @march_string_concat(ptr %ld1604, ptr %sl1605)
  %$t2024.addr = alloca ptr
  store ptr %cr1606, ptr %$t2024.addr
  %ld1607 = load ptr, ptr %$t2024.addr
  call void @march_print(ptr %ld1607)
  %cv1608 = inttoptr i64 0 to ptr
  ret ptr %cv1608
}

define ptr @show_chunk$apply$24(ptr %$clo.arg, ptr %chunk.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %chunk.addr = alloca ptr
  store ptr %chunk.arg, ptr %chunk.addr
  %ld1609 = load ptr, ptr %chunk.addr
  %cr1610 = call i64 @string_length(ptr %ld1609)
  %$t2033.addr = alloca i64
  store i64 %cr1610, ptr %$t2033.addr
  %ld1611 = load i64, ptr %$t2033.addr
  %cr1612 = call ptr @march_int_to_string(i64 %ld1611)
  %$t2034.addr = alloca ptr
  store ptr %cr1612, ptr %$t2034.addr
  %sl1613 = call ptr @march_string_lit(ptr @.str48, i64 9)
  %ld1614 = load ptr, ptr %$t2034.addr
  %cr1615 = call ptr @march_string_concat(ptr %sl1613, ptr %ld1614)
  %$t2035.addr = alloca ptr
  store ptr %cr1615, ptr %$t2035.addr
  %ld1616 = load ptr, ptr %$t2035.addr
  %sl1617 = call ptr @march_string_lit(ptr @.str49, i64 6)
  %cr1618 = call ptr @march_string_concat(ptr %ld1616, ptr %sl1617)
  %$t2036.addr = alloca ptr
  store ptr %cr1618, ptr %$t2036.addr
  %ld1619 = load ptr, ptr %$t2036.addr
  call void @march_print(ptr %ld1619)
  %cv1620 = inttoptr i64 0 to ptr
  ret ptr %cv1620
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

