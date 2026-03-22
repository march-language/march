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
@.str16 = private unnamed_addr constant [23 x i8] c"http://httpbin.org/get\00"
@.str17 = private unnamed_addr constant [9 x i8] c"defaults\00"
@.str18 = private unnamed_addr constant [25 x i8] c"connection-per-request: \00"
@.str19 = private unnamed_addr constant [6 x i8] c" GETs\00"
@.str20 = private unnamed_addr constant [5 x i8] c"done\00"
@.str21 = private unnamed_addr constant [6 x i8] c"error\00"
@.str22 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str23 = private unnamed_addr constant [4 x i8] c"url\00"
@.str24 = private unnamed_addr constant [1 x i8] c"\00"
@.str25 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str26 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str27 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str28 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str29 = private unnamed_addr constant [9 x i8] c"location\00"
@.str30 = private unnamed_addr constant [1 x i8] c"\00"
@.str31 = private unnamed_addr constant [1 x i8] c"\00"
@.str32 = private unnamed_addr constant [11 x i8] c"Connection\00"
@.str33 = private unnamed_addr constant [6 x i8] c"close\00"

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

define i64 @Http.status_code(ptr %s.arg) {
entry:
  %s.addr = alloca ptr
  store ptr %s.arg, ptr %s.addr
  %ld30 = load ptr, ptr %s.addr
  %res_slot31 = alloca ptr
  %tgp32 = getelementptr i8, ptr %ld30, i64 8
  %tag33 = load i32, ptr %tgp32, align 4
  switch i32 %tag33, label %case_default17 [
      i32 0, label %case_br18
  ]
case_br18:
  %fp34 = getelementptr i8, ptr %ld30, i64 16
  %fv35 = load i64, ptr %fp34, align 8
  %$f532.addr = alloca i64
  store i64 %fv35, ptr %$f532.addr
  %ld36 = load ptr, ptr %s.addr
  call void @march_decrc(ptr %ld36)
  %ld37 = load i64, ptr %$f532.addr
  %n.addr = alloca i64
  store i64 %ld37, ptr %n.addr
  %ld38 = load i64, ptr %n.addr
  %cv39 = inttoptr i64 %ld38 to ptr
  store ptr %cv39, ptr %res_slot31
  br label %case_merge16
case_default17:
  unreachable
case_merge16:
  %case_r40 = load ptr, ptr %res_slot31
  %cv41 = ptrtoint ptr %case_r40 to i64
  ret i64 %cv41
}

define ptr @Http.parse_url(ptr %url.arg) {
entry:
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld42 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld42)
  %ld43 = load ptr, ptr %url.addr
  %sl44 = call ptr @march_string_lit(ptr @.str10, i64 8)
  %cr45 = call i64 @march_string_starts_with(ptr %ld43, ptr %sl44)
  %has_https.addr = alloca i64
  store i64 %cr45, ptr %has_https.addr
  %ld46 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld46)
  %ld47 = load ptr, ptr %url.addr
  %sl48 = call ptr @march_string_lit(ptr @.str11, i64 7)
  %cr49 = call i64 @march_string_starts_with(ptr %ld47, ptr %sl48)
  %has_http.addr = alloca i64
  store i64 %cr49, ptr %has_http.addr
  %ld50 = load i64, ptr %has_https.addr
  %ar51 = xor i64 %ld50, 1
  %$t692.addr = alloca i64
  store i64 %ar51, ptr %$t692.addr
  %ld52 = load i64, ptr %has_http.addr
  %ar53 = xor i64 %ld52, 1
  %$t693.addr = alloca i64
  store i64 %ar53, ptr %$t693.addr
  %ld54 = load i64, ptr %$t692.addr
  %ld55 = load i64, ptr %$t693.addr
  %ar56 = and i64 %ld54, %ld55
  %$t694.addr = alloca i64
  store i64 %ar56, ptr %$t694.addr
  %ld57 = load i64, ptr %$t694.addr
  %res_slot58 = alloca ptr
  %bi59 = trunc i64 %ld57 to i1
  br i1 %bi59, label %case_br21, label %case_default20
case_br21:
  %hp60 = call ptr @march_alloc(i64 24)
  %tgp61 = getelementptr i8, ptr %hp60, i64 8
  store i32 0, ptr %tgp61, align 4
  %ld62 = load ptr, ptr %url.addr
  %fp63 = getelementptr i8, ptr %hp60, i64 16
  store ptr %ld62, ptr %fp63, align 8
  %$t695.addr = alloca ptr
  store ptr %hp60, ptr %$t695.addr
  %hp64 = call ptr @march_alloc(i64 24)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 1, ptr %tgp65, align 4
  %ld66 = load ptr, ptr %$t695.addr
  %fp67 = getelementptr i8, ptr %hp64, i64 16
  store ptr %ld66, ptr %fp67, align 8
  store ptr %hp64, ptr %res_slot58
  br label %case_merge19
case_default20:
  %ld68 = load i64, ptr %has_https.addr
  %res_slot69 = alloca ptr
  %bi70 = trunc i64 %ld68 to i1
  br i1 %bi70, label %case_br24, label %case_default23
case_br24:
  %hp71 = call ptr @march_alloc(i64 16)
  %tgp72 = getelementptr i8, ptr %hp71, i64 8
  store i32 1, ptr %tgp72, align 4
  store ptr %hp71, ptr %res_slot69
  br label %case_merge22
case_default23:
  %hp73 = call ptr @march_alloc(i64 16)
  %tgp74 = getelementptr i8, ptr %hp73, i64 8
  store i32 0, ptr %tgp74, align 4
  store ptr %hp73, ptr %res_slot69
  br label %case_merge22
case_merge22:
  %case_r75 = load ptr, ptr %res_slot69
  %url_scheme.addr = alloca ptr
  store ptr %case_r75, ptr %url_scheme.addr
  %ld76 = load i64, ptr %has_https.addr
  %res_slot77 = alloca ptr
  %bi78 = trunc i64 %ld76 to i1
  br i1 %bi78, label %case_br27, label %case_default26
case_br27:
  %cv79 = inttoptr i64 8 to ptr
  store ptr %cv79, ptr %res_slot77
  br label %case_merge25
case_default26:
  %cv80 = inttoptr i64 7 to ptr
  store ptr %cv80, ptr %res_slot77
  br label %case_merge25
case_merge25:
  %case_r81 = load ptr, ptr %res_slot77
  %cv82 = ptrtoint ptr %case_r81 to i64
  %prefix_len.addr = alloca i64
  store i64 %cv82, ptr %prefix_len.addr
  %ld83 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld83)
  %ld84 = load ptr, ptr %url.addr
  %cr85 = call i64 @march_string_byte_length(ptr %ld84)
  %$t696.addr = alloca i64
  store i64 %cr85, ptr %$t696.addr
  %ld86 = load i64, ptr %$t696.addr
  %ld87 = load i64, ptr %prefix_len.addr
  %ar88 = sub i64 %ld86, %ld87
  %$t697.addr = alloca i64
  store i64 %ar88, ptr %$t697.addr
  %ld89 = load ptr, ptr %url.addr
  %ld90 = load i64, ptr %prefix_len.addr
  %ld91 = load i64, ptr %$t697.addr
  %cr92 = call ptr @march_string_slice(ptr %ld89, i64 %ld90, i64 %ld91)
  %rest.addr = alloca ptr
  store ptr %cr92, ptr %rest.addr
  %ld93 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld93)
  %ld94 = load ptr, ptr %rest.addr
  %sl95 = call ptr @march_string_lit(ptr @.str12, i64 1)
  %cr96 = call ptr @march_string_index_of(ptr %ld94, ptr %sl95)
  %path_idx.addr = alloca ptr
  store ptr %cr96, ptr %path_idx.addr
  %ld97 = load ptr, ptr %path_idx.addr
  %res_slot98 = alloca ptr
  %tgp99 = getelementptr i8, ptr %ld97, i64 8
  %tag100 = load i32, ptr %tgp99, align 4
  switch i32 %tag100, label %case_default29 [
      i32 1, label %case_br30
      i32 0, label %case_br31
  ]
case_br30:
  %fp101 = getelementptr i8, ptr %ld97, i64 16
  %fv102 = load ptr, ptr %fp101, align 8
  %$f698.addr = alloca ptr
  store ptr %fv102, ptr %$f698.addr
  %ld103 = load ptr, ptr %$f698.addr
  %i.addr = alloca ptr
  store ptr %ld103, ptr %i.addr
  %ld104 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld104)
  %ld105 = load ptr, ptr %rest.addr
  %ld106 = load ptr, ptr %i.addr
  %cr107 = call ptr @march_string_slice(ptr %ld105, i64 0, ptr %ld106)
  store ptr %cr107, ptr %res_slot98
  br label %case_merge28
case_br31:
  %ld108 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld108)
  %ld109 = load ptr, ptr %rest.addr
  store ptr %ld109, ptr %res_slot98
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r110 = load ptr, ptr %res_slot98
  %host_part.addr = alloca ptr
  store ptr %case_r110, ptr %host_part.addr
  %ld111 = load ptr, ptr %path_idx.addr
  %res_slot112 = alloca ptr
  %tgp113 = getelementptr i8, ptr %ld111, i64 8
  %tag114 = load i32, ptr %tgp113, align 4
  switch i32 %tag114, label %case_default33 [
      i32 1, label %case_br34
      i32 0, label %case_br35
  ]
case_br34:
  %fp115 = getelementptr i8, ptr %ld111, i64 16
  %fv116 = load ptr, ptr %fp115, align 8
  %$f701.addr = alloca ptr
  store ptr %fv116, ptr %$f701.addr
  %ld117 = load ptr, ptr %path_idx.addr
  call void @march_decrc(ptr %ld117)
  %ld118 = load ptr, ptr %$f701.addr
  %i_1.addr = alloca ptr
  store ptr %ld118, ptr %i_1.addr
  %ld119 = load ptr, ptr %rest.addr
  call void @march_incrc(ptr %ld119)
  %ld120 = load ptr, ptr %rest.addr
  %cr121 = call i64 @march_string_byte_length(ptr %ld120)
  %$t699.addr = alloca i64
  store i64 %cr121, ptr %$t699.addr
  %ld122 = load i64, ptr %$t699.addr
  %ld123 = load ptr, ptr %i_1.addr
  %cv124 = ptrtoint ptr %ld123 to i64
  %ar125 = sub i64 %ld122, %cv124
  %$t700.addr = alloca i64
  store i64 %ar125, ptr %$t700.addr
  %ld126 = load ptr, ptr %rest.addr
  %ld127 = load ptr, ptr %i_1.addr
  %ld128 = load i64, ptr %$t700.addr
  %cr129 = call ptr @march_string_slice(ptr %ld126, ptr %ld127, i64 %ld128)
  store ptr %cr129, ptr %res_slot112
  br label %case_merge32
case_br35:
  %ld130 = load ptr, ptr %path_idx.addr
  call void @march_decrc(ptr %ld130)
  %sl131 = call ptr @march_string_lit(ptr @.str13, i64 1)
  store ptr %sl131, ptr %res_slot112
  br label %case_merge32
case_default33:
  unreachable
case_merge32:
  %case_r132 = load ptr, ptr %res_slot112
  %path_and_query.addr = alloca ptr
  store ptr %case_r132, ptr %path_and_query.addr
  %ld133 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld133)
  %ld134 = load ptr, ptr %path_and_query.addr
  %sl135 = call ptr @march_string_lit(ptr @.str14, i64 1)
  %cr136 = call ptr @march_string_index_of(ptr %ld134, ptr %sl135)
  %query_idx.addr = alloca ptr
  store ptr %cr136, ptr %query_idx.addr
  %ld137 = load ptr, ptr %query_idx.addr
  %res_slot138 = alloca ptr
  %tgp139 = getelementptr i8, ptr %ld137, i64 8
  %tag140 = load i32, ptr %tgp139, align 4
  switch i32 %tag140, label %case_default37 [
      i32 1, label %case_br38
      i32 0, label %case_br39
  ]
case_br38:
  %fp141 = getelementptr i8, ptr %ld137, i64 16
  %fv142 = load ptr, ptr %fp141, align 8
  %$f702.addr = alloca ptr
  store ptr %fv142, ptr %$f702.addr
  %ld143 = load ptr, ptr %$f702.addr
  %i_2.addr = alloca ptr
  store ptr %ld143, ptr %i_2.addr
  %ld144 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld144)
  %ld145 = load ptr, ptr %path_and_query.addr
  %ld146 = load ptr, ptr %i_2.addr
  %cr147 = call ptr @march_string_slice(ptr %ld145, i64 0, ptr %ld146)
  store ptr %cr147, ptr %res_slot138
  br label %case_merge36
case_br39:
  %ld148 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld148)
  %ld149 = load ptr, ptr %path_and_query.addr
  store ptr %ld149, ptr %res_slot138
  br label %case_merge36
case_default37:
  unreachable
case_merge36:
  %case_r150 = load ptr, ptr %res_slot138
  %url_path.addr = alloca ptr
  store ptr %case_r150, ptr %url_path.addr
  %ld151 = load ptr, ptr %query_idx.addr
  %res_slot152 = alloca ptr
  %tgp153 = getelementptr i8, ptr %ld151, i64 8
  %tag154 = load i32, ptr %tgp153, align 4
  switch i32 %tag154, label %case_default41 [
      i32 1, label %case_br42
      i32 0, label %case_br43
  ]
case_br42:
  %fp155 = getelementptr i8, ptr %ld151, i64 16
  %fv156 = load ptr, ptr %fp155, align 8
  %$f708.addr = alloca ptr
  store ptr %fv156, ptr %$f708.addr
  %ld157 = load ptr, ptr %$f708.addr
  %i_3.addr = alloca ptr
  store ptr %ld157, ptr %i_3.addr
  %ld158 = load ptr, ptr %i_3.addr
  %cv159 = ptrtoint ptr %ld158 to i64
  %ar160 = add i64 %cv159, 1
  %$t703.addr = alloca i64
  store i64 %ar160, ptr %$t703.addr
  %ld161 = load ptr, ptr %path_and_query.addr
  call void @march_incrc(ptr %ld161)
  %ld162 = load ptr, ptr %path_and_query.addr
  %cr163 = call i64 @march_string_byte_length(ptr %ld162)
  %$t704.addr = alloca i64
  store i64 %cr163, ptr %$t704.addr
  %ld164 = load i64, ptr %$t704.addr
  %ld165 = load ptr, ptr %i_3.addr
  %cv166 = ptrtoint ptr %ld165 to i64
  %ar167 = sub i64 %ld164, %cv166
  %$t705.addr = alloca i64
  store i64 %ar167, ptr %$t705.addr
  %ld168 = load i64, ptr %$t705.addr
  %ar169 = sub i64 %ld168, 1
  %$t706.addr = alloca i64
  store i64 %ar169, ptr %$t706.addr
  %ld170 = load ptr, ptr %path_and_query.addr
  %ld171 = load i64, ptr %$t703.addr
  %ld172 = load i64, ptr %$t706.addr
  %cr173 = call ptr @march_string_slice(ptr %ld170, i64 %ld171, i64 %ld172)
  %$t707.addr = alloca ptr
  store ptr %cr173, ptr %$t707.addr
  %ld174 = load ptr, ptr %query_idx.addr
  %ld175 = load ptr, ptr %$t707.addr
  %rc176 = load i64, ptr %ld174, align 8
  %uniq177 = icmp eq i64 %rc176, 1
  %fbip_slot178 = alloca ptr
  br i1 %uniq177, label %fbip_reuse44, label %fbip_fresh45
fbip_reuse44:
  %tgp179 = getelementptr i8, ptr %ld174, i64 8
  store i32 1, ptr %tgp179, align 4
  %fp180 = getelementptr i8, ptr %ld174, i64 16
  store ptr %ld175, ptr %fp180, align 8
  store ptr %ld174, ptr %fbip_slot178
  br label %fbip_merge46
fbip_fresh45:
  call void @march_decrc(ptr %ld174)
  %hp181 = call ptr @march_alloc(i64 24)
  %tgp182 = getelementptr i8, ptr %hp181, i64 8
  store i32 1, ptr %tgp182, align 4
  %fp183 = getelementptr i8, ptr %hp181, i64 16
  store ptr %ld175, ptr %fp183, align 8
  store ptr %hp181, ptr %fbip_slot178
  br label %fbip_merge46
fbip_merge46:
  %fbip_r184 = load ptr, ptr %fbip_slot178
  store ptr %fbip_r184, ptr %res_slot152
  br label %case_merge40
case_br43:
  %ld185 = load ptr, ptr %query_idx.addr
  %rc186 = load i64, ptr %ld185, align 8
  %uniq187 = icmp eq i64 %rc186, 1
  %fbip_slot188 = alloca ptr
  br i1 %uniq187, label %fbip_reuse47, label %fbip_fresh48
fbip_reuse47:
  %tgp189 = getelementptr i8, ptr %ld185, i64 8
  store i32 0, ptr %tgp189, align 4
  store ptr %ld185, ptr %fbip_slot188
  br label %fbip_merge49
fbip_fresh48:
  call void @march_decrc(ptr %ld185)
  %hp190 = call ptr @march_alloc(i64 16)
  %tgp191 = getelementptr i8, ptr %hp190, i64 8
  store i32 0, ptr %tgp191, align 4
  store ptr %hp190, ptr %fbip_slot188
  br label %fbip_merge49
fbip_merge49:
  %fbip_r192 = load ptr, ptr %fbip_slot188
  store ptr %fbip_r192, ptr %res_slot152
  br label %case_merge40
case_default41:
  unreachable
case_merge40:
  %case_r193 = load ptr, ptr %res_slot152
  %url_query.addr = alloca ptr
  store ptr %case_r193, ptr %url_query.addr
  %ld194 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld194)
  %ld195 = load ptr, ptr %host_part.addr
  %sl196 = call ptr @march_string_lit(ptr @.str15, i64 1)
  %cr197 = call ptr @march_string_index_of(ptr %ld195, ptr %sl196)
  %port_idx.addr = alloca ptr
  store ptr %cr197, ptr %port_idx.addr
  %ld198 = load ptr, ptr %port_idx.addr
  %res_slot199 = alloca ptr
  %tgp200 = getelementptr i8, ptr %ld198, i64 8
  %tag201 = load i32, ptr %tgp200, align 4
  switch i32 %tag201, label %case_default51 [
      i32 1, label %case_br52
      i32 0, label %case_br53
  ]
case_br52:
  %fp202 = getelementptr i8, ptr %ld198, i64 16
  %fv203 = load ptr, ptr %fp202, align 8
  %$f709.addr = alloca ptr
  store ptr %fv203, ptr %$f709.addr
  %ld204 = load ptr, ptr %$f709.addr
  %i_4.addr = alloca ptr
  store ptr %ld204, ptr %i_4.addr
  %ld205 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld205)
  %ld206 = load ptr, ptr %host_part.addr
  %ld207 = load ptr, ptr %i_4.addr
  %cr208 = call ptr @march_string_slice(ptr %ld206, i64 0, ptr %ld207)
  store ptr %cr208, ptr %res_slot199
  br label %case_merge50
case_br53:
  %ld209 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld209)
  %ld210 = load ptr, ptr %host_part.addr
  store ptr %ld210, ptr %res_slot199
  br label %case_merge50
case_default51:
  unreachable
case_merge50:
  %case_r211 = load ptr, ptr %res_slot199
  %url_host.addr = alloca ptr
  store ptr %case_r211, ptr %url_host.addr
  %ld212 = load ptr, ptr %port_idx.addr
  %res_slot213 = alloca ptr
  %tgp214 = getelementptr i8, ptr %ld212, i64 8
  %tag215 = load i32, ptr %tgp214, align 4
  switch i32 %tag215, label %case_default55 [
      i32 1, label %case_br56
      i32 0, label %case_br57
  ]
case_br56:
  %fp216 = getelementptr i8, ptr %ld212, i64 16
  %fv217 = load ptr, ptr %fp216, align 8
  %$f717.addr = alloca ptr
  store ptr %fv217, ptr %$f717.addr
  %ld218 = load ptr, ptr %port_idx.addr
  call void @march_decrc(ptr %ld218)
  %ld219 = load ptr, ptr %$f717.addr
  %i_5.addr = alloca ptr
  store ptr %ld219, ptr %i_5.addr
  %ld220 = load ptr, ptr %i_5.addr
  %cv221 = ptrtoint ptr %ld220 to i64
  %ar222 = add i64 %cv221, 1
  %$t710.addr = alloca i64
  store i64 %ar222, ptr %$t710.addr
  %ld223 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld223)
  %ld224 = load ptr, ptr %host_part.addr
  %cr225 = call i64 @march_string_byte_length(ptr %ld224)
  %$t711.addr = alloca i64
  store i64 %cr225, ptr %$t711.addr
  %ld226 = load i64, ptr %$t711.addr
  %ld227 = load ptr, ptr %i_5.addr
  %cv228 = ptrtoint ptr %ld227 to i64
  %ar229 = sub i64 %ld226, %cv228
  %$t712.addr = alloca i64
  store i64 %ar229, ptr %$t712.addr
  %ld230 = load i64, ptr %$t712.addr
  %ar231 = sub i64 %ld230, 1
  %$t713.addr = alloca i64
  store i64 %ar231, ptr %$t713.addr
  %ld232 = load ptr, ptr %host_part.addr
  call void @march_incrc(ptr %ld232)
  %ld233 = load ptr, ptr %host_part.addr
  %ld234 = load i64, ptr %$t710.addr
  %ld235 = load i64, ptr %$t713.addr
  %cr236 = call ptr @march_string_slice(ptr %ld233, i64 %ld234, i64 %ld235)
  %port_str.addr = alloca ptr
  store ptr %cr236, ptr %port_str.addr
  %ld237 = load ptr, ptr %port_str.addr
  %cr238 = call ptr @march_string_to_int(ptr %ld237)
  %$t714.addr = alloca ptr
  store ptr %cr238, ptr %$t714.addr
  %ld239 = load ptr, ptr %$t714.addr
  %res_slot240 = alloca ptr
  %tgp241 = getelementptr i8, ptr %ld239, i64 8
  %tag242 = load i32, ptr %tgp241, align 4
  switch i32 %tag242, label %case_default59 [
      i32 1, label %case_br60
      i32 0, label %case_br61
  ]
case_br60:
  %fp243 = getelementptr i8, ptr %ld239, i64 16
  %fv244 = load ptr, ptr %fp243, align 8
  %$f716.addr = alloca ptr
  store ptr %fv244, ptr %$f716.addr
  %ld245 = load ptr, ptr %$f716.addr
  %p.addr = alloca ptr
  store ptr %ld245, ptr %p.addr
  %ld246 = load ptr, ptr %$t714.addr
  %ld247 = load ptr, ptr %p.addr
  %rc248 = load i64, ptr %ld246, align 8
  %uniq249 = icmp eq i64 %rc248, 1
  %fbip_slot250 = alloca ptr
  br i1 %uniq249, label %fbip_reuse62, label %fbip_fresh63
fbip_reuse62:
  %tgp251 = getelementptr i8, ptr %ld246, i64 8
  store i32 1, ptr %tgp251, align 4
  %fp252 = getelementptr i8, ptr %ld246, i64 16
  store ptr %ld247, ptr %fp252, align 8
  store ptr %ld246, ptr %fbip_slot250
  br label %fbip_merge64
fbip_fresh63:
  call void @march_decrc(ptr %ld246)
  %hp253 = call ptr @march_alloc(i64 24)
  %tgp254 = getelementptr i8, ptr %hp253, i64 8
  store i32 1, ptr %tgp254, align 4
  %fp255 = getelementptr i8, ptr %hp253, i64 16
  store ptr %ld247, ptr %fp255, align 8
  store ptr %hp253, ptr %fbip_slot250
  br label %fbip_merge64
fbip_merge64:
  %fbip_r256 = load ptr, ptr %fbip_slot250
  store ptr %fbip_r256, ptr %res_slot240
  br label %case_merge58
case_br61:
  %ld257 = load ptr, ptr %$t714.addr
  call void @march_decrc(ptr %ld257)
  %ar258 = sub i64 0, 1
  %$t715.addr = alloca i64
  store i64 %ar258, ptr %$t715.addr
  %hp259 = call ptr @march_alloc(i64 24)
  %tgp260 = getelementptr i8, ptr %hp259, i64 8
  store i32 1, ptr %tgp260, align 4
  %ld261 = load i64, ptr %$t715.addr
  %cv262 = inttoptr i64 %ld261 to ptr
  %fp263 = getelementptr i8, ptr %hp259, i64 16
  store ptr %cv262, ptr %fp263, align 8
  store ptr %hp259, ptr %res_slot240
  br label %case_merge58
case_default59:
  unreachable
case_merge58:
  %case_r264 = load ptr, ptr %res_slot240
  store ptr %case_r264, ptr %res_slot213
  br label %case_merge54
case_br57:
  %ld265 = load ptr, ptr %port_idx.addr
  %rc266 = load i64, ptr %ld265, align 8
  %uniq267 = icmp eq i64 %rc266, 1
  %fbip_slot268 = alloca ptr
  br i1 %uniq267, label %fbip_reuse65, label %fbip_fresh66
fbip_reuse65:
  %tgp269 = getelementptr i8, ptr %ld265, i64 8
  store i32 0, ptr %tgp269, align 4
  store ptr %ld265, ptr %fbip_slot268
  br label %fbip_merge67
fbip_fresh66:
  call void @march_decrc(ptr %ld265)
  %hp270 = call ptr @march_alloc(i64 16)
  %tgp271 = getelementptr i8, ptr %hp270, i64 8
  store i32 0, ptr %tgp271, align 4
  store ptr %hp270, ptr %fbip_slot268
  br label %fbip_merge67
fbip_merge67:
  %fbip_r272 = load ptr, ptr %fbip_slot268
  store ptr %fbip_r272, ptr %res_slot213
  br label %case_merge54
case_default55:
  unreachable
case_merge54:
  %case_r273 = load ptr, ptr %res_slot213
  %url_port.addr = alloca ptr
  store ptr %case_r273, ptr %url_port.addr
  %ld274 = load ptr, ptr %url_host.addr
  call void @march_incrc(ptr %ld274)
  %ld275 = load ptr, ptr %url_host.addr
  %cr276 = call i64 @march_string_is_empty(ptr %ld275)
  %$t718.addr = alloca i64
  store i64 %cr276, ptr %$t718.addr
  %ld277 = load i64, ptr %$t718.addr
  %res_slot278 = alloca ptr
  %bi279 = trunc i64 %ld277 to i1
  br i1 %bi279, label %case_br70, label %case_default69
case_br70:
  %hp280 = call ptr @march_alloc(i64 16)
  %tgp281 = getelementptr i8, ptr %hp280, i64 8
  store i32 1, ptr %tgp281, align 4
  %$t719.addr = alloca ptr
  store ptr %hp280, ptr %$t719.addr
  %hp282 = call ptr @march_alloc(i64 24)
  %tgp283 = getelementptr i8, ptr %hp282, i64 8
  store i32 1, ptr %tgp283, align 4
  %ld284 = load ptr, ptr %$t719.addr
  %fp285 = getelementptr i8, ptr %hp282, i64 16
  store ptr %ld284, ptr %fp285, align 8
  store ptr %hp282, ptr %res_slot278
  br label %case_merge68
case_default69:
  %ld286 = load ptr, ptr %url_port.addr
  %res_slot287 = alloca ptr
  %tgp288 = getelementptr i8, ptr %ld286, i64 8
  %tag289 = load i32, ptr %tgp288, align 4
  switch i32 %tag289, label %case_default72 [
      i32 1, label %case_br73
  ]
case_br73:
  %fp290 = getelementptr i8, ptr %ld286, i64 16
  %fv291 = load ptr, ptr %fp290, align 8
  %$f725.addr = alloca ptr
  store ptr %fv291, ptr %$f725.addr
  %ld292 = load ptr, ptr %$f725.addr
  %res_slot293 = alloca ptr
  %tgp294 = getelementptr i8, ptr %ld292, i64 8
  %tag295 = load i32, ptr %tgp294, align 4
  switch i32 %tag295, label %case_default75 [
      i32 0, label %case_br76
  ]
case_br76:
  %ld296 = load ptr, ptr %$f725.addr
  call void @march_decrc(ptr %ld296)
  %hp297 = call ptr @march_alloc(i64 24)
  %tgp298 = getelementptr i8, ptr %hp297, i64 8
  store i32 2, ptr %tgp298, align 4
  %ld299 = load ptr, ptr %host_part.addr
  %fp300 = getelementptr i8, ptr %hp297, i64 16
  store ptr %ld299, ptr %fp300, align 8
  %$t720.addr = alloca ptr
  store ptr %hp297, ptr %$t720.addr
  %hp301 = call ptr @march_alloc(i64 24)
  %tgp302 = getelementptr i8, ptr %hp301, i64 8
  store i32 1, ptr %tgp302, align 4
  %ld303 = load ptr, ptr %$t720.addr
  %fp304 = getelementptr i8, ptr %hp301, i64 16
  store ptr %ld303, ptr %fp304, align 8
  store ptr %hp301, ptr %res_slot293
  br label %case_merge74
case_default75:
  %ld305 = load ptr, ptr %$f725.addr
  call void @march_decrc(ptr %ld305)
  %hp306 = call ptr @march_alloc(i64 16)
  %tgp307 = getelementptr i8, ptr %hp306, i64 8
  store i32 0, ptr %tgp307, align 4
  %$t721.addr = alloca ptr
  store ptr %hp306, ptr %$t721.addr
  %hp308 = call ptr @march_alloc(i64 16)
  %tgp309 = getelementptr i8, ptr %hp308, i64 8
  store i32 0, ptr %tgp309, align 4
  %$t722.addr = alloca ptr
  store ptr %hp308, ptr %$t722.addr
  %cv310 = inttoptr i64 0 to ptr
  %$t723.addr = alloca ptr
  store ptr %cv310, ptr %$t723.addr
  %hp311 = call ptr @march_alloc(i64 80)
  %tgp312 = getelementptr i8, ptr %hp311, i64 8
  store i32 0, ptr %tgp312, align 4
  %ld313 = load ptr, ptr %$t721.addr
  %fp314 = getelementptr i8, ptr %hp311, i64 16
  store ptr %ld313, ptr %fp314, align 8
  %ld315 = load ptr, ptr %url_scheme.addr
  %fp316 = getelementptr i8, ptr %hp311, i64 24
  store ptr %ld315, ptr %fp316, align 8
  %ld317 = load ptr, ptr %url_host.addr
  %fp318 = getelementptr i8, ptr %hp311, i64 32
  store ptr %ld317, ptr %fp318, align 8
  %ld319 = load ptr, ptr %url_port.addr
  %fp320 = getelementptr i8, ptr %hp311, i64 40
  store ptr %ld319, ptr %fp320, align 8
  %ld321 = load ptr, ptr %url_path.addr
  %fp322 = getelementptr i8, ptr %hp311, i64 48
  store ptr %ld321, ptr %fp322, align 8
  %ld323 = load ptr, ptr %url_query.addr
  %fp324 = getelementptr i8, ptr %hp311, i64 56
  store ptr %ld323, ptr %fp324, align 8
  %ld325 = load ptr, ptr %$t722.addr
  %fp326 = getelementptr i8, ptr %hp311, i64 64
  store ptr %ld325, ptr %fp326, align 8
  %ld327 = load ptr, ptr %$t723.addr
  %fp328 = getelementptr i8, ptr %hp311, i64 72
  store ptr %ld327, ptr %fp328, align 8
  %$t724.addr = alloca ptr
  store ptr %hp311, ptr %$t724.addr
  %hp329 = call ptr @march_alloc(i64 24)
  %tgp330 = getelementptr i8, ptr %hp329, i64 8
  store i32 0, ptr %tgp330, align 4
  %ld331 = load ptr, ptr %$t724.addr
  %fp332 = getelementptr i8, ptr %hp329, i64 16
  store ptr %ld331, ptr %fp332, align 8
  store ptr %hp329, ptr %res_slot293
  br label %case_merge74
case_merge74:
  %case_r333 = load ptr, ptr %res_slot293
  store ptr %case_r333, ptr %res_slot287
  br label %case_merge71
case_default72:
  %hp334 = call ptr @march_alloc(i64 16)
  %tgp335 = getelementptr i8, ptr %hp334, i64 8
  store i32 0, ptr %tgp335, align 4
  %$t721_1.addr = alloca ptr
  store ptr %hp334, ptr %$t721_1.addr
  %hp336 = call ptr @march_alloc(i64 16)
  %tgp337 = getelementptr i8, ptr %hp336, i64 8
  store i32 0, ptr %tgp337, align 4
  %$t722_1.addr = alloca ptr
  store ptr %hp336, ptr %$t722_1.addr
  %cv338 = inttoptr i64 0 to ptr
  %$t723_1.addr = alloca ptr
  store ptr %cv338, ptr %$t723_1.addr
  %hp339 = call ptr @march_alloc(i64 80)
  %tgp340 = getelementptr i8, ptr %hp339, i64 8
  store i32 0, ptr %tgp340, align 4
  %ld341 = load ptr, ptr %$t721_1.addr
  %fp342 = getelementptr i8, ptr %hp339, i64 16
  store ptr %ld341, ptr %fp342, align 8
  %ld343 = load ptr, ptr %url_scheme.addr
  %fp344 = getelementptr i8, ptr %hp339, i64 24
  store ptr %ld343, ptr %fp344, align 8
  %ld345 = load ptr, ptr %url_host.addr
  %fp346 = getelementptr i8, ptr %hp339, i64 32
  store ptr %ld345, ptr %fp346, align 8
  %ld347 = load ptr, ptr %url_port.addr
  %fp348 = getelementptr i8, ptr %hp339, i64 40
  store ptr %ld347, ptr %fp348, align 8
  %ld349 = load ptr, ptr %url_path.addr
  %fp350 = getelementptr i8, ptr %hp339, i64 48
  store ptr %ld349, ptr %fp350, align 8
  %ld351 = load ptr, ptr %url_query.addr
  %fp352 = getelementptr i8, ptr %hp339, i64 56
  store ptr %ld351, ptr %fp352, align 8
  %ld353 = load ptr, ptr %$t722_1.addr
  %fp354 = getelementptr i8, ptr %hp339, i64 64
  store ptr %ld353, ptr %fp354, align 8
  %ld355 = load ptr, ptr %$t723_1.addr
  %fp356 = getelementptr i8, ptr %hp339, i64 72
  store ptr %ld355, ptr %fp356, align 8
  %$t724_1.addr = alloca ptr
  store ptr %hp339, ptr %$t724_1.addr
  %hp357 = call ptr @march_alloc(i64 24)
  %tgp358 = getelementptr i8, ptr %hp357, i64 8
  store i32 0, ptr %tgp358, align 4
  %ld359 = load ptr, ptr %$t724_1.addr
  %fp360 = getelementptr i8, ptr %hp357, i64 16
  store ptr %ld359, ptr %fp360, align 8
  store ptr %hp357, ptr %res_slot287
  br label %case_merge71
case_merge71:
  %case_r361 = load ptr, ptr %res_slot287
  store ptr %case_r361, ptr %res_slot278
  br label %case_merge68
case_merge68:
  %case_r362 = load ptr, ptr %res_slot278
  store ptr %case_r362, ptr %res_slot58
  br label %case_merge19
case_merge19:
  %case_r363 = load ptr, ptr %res_slot58
  ret ptr %case_r363
}

define ptr @run_requests(i64 %n.arg, ptr %client.arg, ptr %url.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld364 = load i64, ptr %n.addr
  %cmp365 = icmp eq i64 %ld364, 0
  %ar366 = zext i1 %cmp365 to i64
  %$t2009.addr = alloca i64
  store i64 %ar366, ptr %$t2009.addr
  %ld367 = load i64, ptr %$t2009.addr
  %res_slot368 = alloca ptr
  %bi369 = trunc i64 %ld367 to i1
  br i1 %bi369, label %case_br79, label %case_default78
case_br79:
  %hp370 = call ptr @march_alloc(i64 24)
  %tgp371 = getelementptr i8, ptr %hp370, i64 8
  store i32 0, ptr %tgp371, align 4
  %cv372 = inttoptr i64 0 to ptr
  %fp373 = getelementptr i8, ptr %hp370, i64 16
  store ptr %cv372, ptr %fp373, align 8
  store ptr %hp370, ptr %res_slot368
  br label %case_merge77
case_default78:
  %ld374 = load ptr, ptr %client.addr
  call void @march_incrc(ptr %ld374)
  %ld375 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld375)
  %ld376 = load ptr, ptr %client.addr
  %ld377 = load ptr, ptr %url.addr
  %cr378 = call ptr @HttpClient.get(ptr %ld376, ptr %ld377)
  %$t2010.addr = alloca ptr
  store ptr %cr378, ptr %$t2010.addr
  %ld379 = load ptr, ptr %$t2010.addr
  %res_slot380 = alloca ptr
  %tgp381 = getelementptr i8, ptr %ld379, i64 8
  %tag382 = load i32, ptr %tgp381, align 4
  switch i32 %tag382, label %case_default81 [
      i32 0, label %case_br82
      i32 1, label %case_br83
  ]
case_br82:
  %fp383 = getelementptr i8, ptr %ld379, i64 16
  %fv384 = load ptr, ptr %fp383, align 8
  %$f2012.addr = alloca ptr
  store ptr %fv384, ptr %$f2012.addr
  %freed385 = call i64 @march_decrc_freed(ptr %ld379)
  %freed_b386 = icmp ne i64 %freed385, 0
  br i1 %freed_b386, label %br_unique84, label %br_shared85
br_shared85:
  call void @march_incrc(ptr %fv384)
  br label %br_body86
br_unique84:
  br label %br_body86
br_body86:
  %ld387 = load i64, ptr %n.addr
  %ar388 = sub i64 %ld387, 1
  %$t2011.addr = alloca i64
  store i64 %ar388, ptr %$t2011.addr
  %ld389 = load i64, ptr %$t2011.addr
  %ld390 = load ptr, ptr %client.addr
  %ld391 = load ptr, ptr %url.addr
  %cr392 = call ptr @run_requests(i64 %ld389, ptr %ld390, ptr %ld391)
  store ptr %cr392, ptr %res_slot380
  br label %case_merge80
case_br83:
  %fp393 = getelementptr i8, ptr %ld379, i64 16
  %fv394 = load ptr, ptr %fp393, align 8
  %$f2013.addr = alloca ptr
  store ptr %fv394, ptr %$f2013.addr
  %ld395 = load ptr, ptr %$f2013.addr
  %e.addr = alloca ptr
  store ptr %ld395, ptr %e.addr
  %ld396 = load ptr, ptr %$t2010.addr
  %ld397 = load ptr, ptr %e.addr
  %rc398 = load i64, ptr %ld396, align 8
  %uniq399 = icmp eq i64 %rc398, 1
  %fbip_slot400 = alloca ptr
  br i1 %uniq399, label %fbip_reuse87, label %fbip_fresh88
fbip_reuse87:
  %tgp401 = getelementptr i8, ptr %ld396, i64 8
  store i32 1, ptr %tgp401, align 4
  %fp402 = getelementptr i8, ptr %ld396, i64 16
  store ptr %ld397, ptr %fp402, align 8
  store ptr %ld396, ptr %fbip_slot400
  br label %fbip_merge89
fbip_fresh88:
  call void @march_decrc(ptr %ld396)
  %hp403 = call ptr @march_alloc(i64 24)
  %tgp404 = getelementptr i8, ptr %hp403, i64 8
  store i32 1, ptr %tgp404, align 4
  %fp405 = getelementptr i8, ptr %hp403, i64 16
  store ptr %ld397, ptr %fp405, align 8
  store ptr %hp403, ptr %fbip_slot400
  br label %fbip_merge89
fbip_merge89:
  %fbip_r406 = load ptr, ptr %fbip_slot400
  store ptr %fbip_r406, ptr %res_slot380
  br label %case_merge80
case_default81:
  unreachable
case_merge80:
  %case_r407 = load ptr, ptr %res_slot380
  store ptr %case_r407, ptr %res_slot368
  br label %case_merge77
case_merge77:
  %case_r408 = load ptr, ptr %res_slot368
  ret ptr %case_r408
}

define ptr @march_main() {
entry:
  %n.addr = alloca i64
  store i64 20, ptr %n.addr
  %sl409 = call ptr @march_string_lit(ptr @.str16, i64 22)
  %url.addr = alloca ptr
  store ptr %sl409, ptr %url.addr
  %hp410 = call ptr @march_alloc(i64 16)
  %tgp411 = getelementptr i8, ptr %hp410, i64 8
  store i32 0, ptr %tgp411, align 4
  %$t880_i23.addr = alloca ptr
  store ptr %hp410, ptr %$t880_i23.addr
  %hp412 = call ptr @march_alloc(i64 16)
  %tgp413 = getelementptr i8, ptr %hp412, i64 8
  store i32 0, ptr %tgp413, align 4
  %$t881_i24.addr = alloca ptr
  store ptr %hp412, ptr %$t881_i24.addr
  %hp414 = call ptr @march_alloc(i64 16)
  %tgp415 = getelementptr i8, ptr %hp414, i64 8
  store i32 0, ptr %tgp415, align 4
  %$t882_i25.addr = alloca ptr
  store ptr %hp414, ptr %$t882_i25.addr
  %hp416 = call ptr @march_alloc(i64 64)
  %tgp417 = getelementptr i8, ptr %hp416, i64 8
  store i32 0, ptr %tgp417, align 4
  %ld418 = load ptr, ptr %$t880_i23.addr
  %fp419 = getelementptr i8, ptr %hp416, i64 16
  store ptr %ld418, ptr %fp419, align 8
  %ld420 = load ptr, ptr %$t881_i24.addr
  %fp421 = getelementptr i8, ptr %hp416, i64 24
  store ptr %ld420, ptr %fp421, align 8
  %ld422 = load ptr, ptr %$t882_i25.addr
  %fp423 = getelementptr i8, ptr %hp416, i64 32
  store ptr %ld422, ptr %fp423, align 8
  %fp424 = getelementptr i8, ptr %hp416, i64 40
  store i64 0, ptr %fp424, align 8
  %fp425 = getelementptr i8, ptr %hp416, i64 48
  store i64 0, ptr %fp425, align 8
  %fp426 = getelementptr i8, ptr %hp416, i64 56
  store i64 0, ptr %fp426, align 8
  %client.addr = alloca ptr
  store ptr %hp416, ptr %client.addr
  %ld427 = load ptr, ptr %client.addr
  %sl428 = call ptr @march_string_lit(ptr @.str17, i64 8)
  %cwrap429 = call ptr @march_alloc(i64 24)
  %cwt430 = getelementptr i8, ptr %cwrap429, i64 8
  store i32 0, ptr %cwt430, align 4
  %cwf431 = getelementptr i8, ptr %cwrap429, i64 16
  store ptr @HttpClient.step_default_headers$clo_wrap, ptr %cwf431, align 8
  %cr432 = call ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__5868_Result_Request_V__5867_V__5866(ptr %ld427, ptr %sl428, ptr %cwrap429)
  %client_1.addr = alloca ptr
  store ptr %cr432, ptr %client_1.addr
  %ld433 = load i64, ptr %n.addr
  %cr434 = call ptr @march_int_to_string(i64 %ld433)
  %$t2014.addr = alloca ptr
  store ptr %cr434, ptr %$t2014.addr
  %sl435 = call ptr @march_string_lit(ptr @.str18, i64 24)
  %ld436 = load ptr, ptr %$t2014.addr
  %cr437 = call ptr @march_string_concat(ptr %sl435, ptr %ld436)
  %$t2015.addr = alloca ptr
  store ptr %cr437, ptr %$t2015.addr
  %ld438 = load ptr, ptr %$t2015.addr
  %sl439 = call ptr @march_string_lit(ptr @.str19, i64 5)
  %cr440 = call ptr @march_string_concat(ptr %ld438, ptr %sl439)
  %$t2016.addr = alloca ptr
  store ptr %cr440, ptr %$t2016.addr
  %ld441 = load ptr, ptr %$t2016.addr
  call void @march_print(ptr %ld441)
  %ld442 = load i64, ptr %n.addr
  %ld443 = load ptr, ptr %client_1.addr
  %ld444 = load ptr, ptr %url.addr
  %cr445 = call ptr @run_requests(i64 %ld442, ptr %ld443, ptr %ld444)
  %$t2017.addr = alloca ptr
  store ptr %cr445, ptr %$t2017.addr
  %ld446 = load ptr, ptr %$t2017.addr
  %res_slot447 = alloca ptr
  %tgp448 = getelementptr i8, ptr %ld446, i64 8
  %tag449 = load i32, ptr %tgp448, align 4
  switch i32 %tag449, label %case_default91 [
      i32 0, label %case_br92
      i32 1, label %case_br93
  ]
case_br92:
  %fp450 = getelementptr i8, ptr %ld446, i64 16
  %fv451 = load ptr, ptr %fp450, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv451, ptr %$f2018.addr
  %ld452 = load ptr, ptr %$t2017.addr
  call void @march_decrc(ptr %ld452)
  %sl453 = call ptr @march_string_lit(ptr @.str20, i64 4)
  call void @march_print(ptr %sl453)
  %cv454 = inttoptr i64 0 to ptr
  store ptr %cv454, ptr %res_slot447
  br label %case_merge90
case_br93:
  %fp455 = getelementptr i8, ptr %ld446, i64 16
  %fv456 = load ptr, ptr %fp455, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv456, ptr %$f2019.addr
  %freed457 = call i64 @march_decrc_freed(ptr %ld446)
  %freed_b458 = icmp ne i64 %freed457, 0
  br i1 %freed_b458, label %br_unique94, label %br_shared95
br_shared95:
  call void @march_incrc(ptr %fv456)
  br label %br_body96
br_unique94:
  br label %br_body96
br_body96:
  %sl459 = call ptr @march_string_lit(ptr @.str21, i64 5)
  call void @march_print(ptr %sl459)
  %cv460 = inttoptr i64 0 to ptr
  store ptr %cv460, ptr %res_slot447
  br label %case_merge90
case_default91:
  unreachable
case_merge90:
  %case_r461 = load ptr, ptr %res_slot447
  ret ptr %case_r461
}

define ptr @HttpClient.get(ptr %client.arg, ptr %url.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld462 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld462)
  %ld463 = load ptr, ptr %url.addr
  %url_i26.addr = alloca ptr
  store ptr %ld463, ptr %url_i26.addr
  %ld464 = load ptr, ptr %url_i26.addr
  %cr465 = call ptr @Http.parse_url(ptr %ld464)
  %$t1098.addr = alloca ptr
  store ptr %cr465, ptr %$t1098.addr
  %ld466 = load ptr, ptr %$t1098.addr
  %res_slot467 = alloca ptr
  %tgp468 = getelementptr i8, ptr %ld466, i64 8
  %tag469 = load i32, ptr %tgp468, align 4
  switch i32 %tag469, label %case_default98 [
      i32 1, label %case_br99
      i32 0, label %case_br100
  ]
case_br99:
  %fp470 = getelementptr i8, ptr %ld466, i64 16
  %fv471 = load ptr, ptr %fp470, align 8
  %$f1102.addr = alloca ptr
  store ptr %fv471, ptr %$f1102.addr
  %sl472 = call ptr @march_string_lit(ptr @.str22, i64 13)
  %ld473 = load ptr, ptr %url.addr
  %cr474 = call ptr @march_string_concat(ptr %sl472, ptr %ld473)
  %$t1099.addr = alloca ptr
  store ptr %cr474, ptr %$t1099.addr
  %hp475 = call ptr @march_alloc(i64 32)
  %tgp476 = getelementptr i8, ptr %hp475, i64 8
  store i32 1, ptr %tgp476, align 4
  %sl477 = call ptr @march_string_lit(ptr @.str23, i64 3)
  %fp478 = getelementptr i8, ptr %hp475, i64 16
  store ptr %sl477, ptr %fp478, align 8
  %ld479 = load ptr, ptr %$t1099.addr
  %fp480 = getelementptr i8, ptr %hp475, i64 24
  store ptr %ld479, ptr %fp480, align 8
  %$t1100.addr = alloca ptr
  store ptr %hp475, ptr %$t1100.addr
  %ld481 = load ptr, ptr %$t1098.addr
  %ld482 = load ptr, ptr %$t1100.addr
  %rc483 = load i64, ptr %ld481, align 8
  %uniq484 = icmp eq i64 %rc483, 1
  %fbip_slot485 = alloca ptr
  br i1 %uniq484, label %fbip_reuse101, label %fbip_fresh102
fbip_reuse101:
  %tgp486 = getelementptr i8, ptr %ld481, i64 8
  store i32 1, ptr %tgp486, align 4
  %fp487 = getelementptr i8, ptr %ld481, i64 16
  store ptr %ld482, ptr %fp487, align 8
  store ptr %ld481, ptr %fbip_slot485
  br label %fbip_merge103
fbip_fresh102:
  call void @march_decrc(ptr %ld481)
  %hp488 = call ptr @march_alloc(i64 24)
  %tgp489 = getelementptr i8, ptr %hp488, i64 8
  store i32 1, ptr %tgp489, align 4
  %fp490 = getelementptr i8, ptr %hp488, i64 16
  store ptr %ld482, ptr %fp490, align 8
  store ptr %hp488, ptr %fbip_slot485
  br label %fbip_merge103
fbip_merge103:
  %fbip_r491 = load ptr, ptr %fbip_slot485
  store ptr %fbip_r491, ptr %res_slot467
  br label %case_merge97
case_br100:
  %fp492 = getelementptr i8, ptr %ld466, i64 16
  %fv493 = load ptr, ptr %fp492, align 8
  %$f1103.addr = alloca ptr
  store ptr %fv493, ptr %$f1103.addr
  %freed494 = call i64 @march_decrc_freed(ptr %ld466)
  %freed_b495 = icmp ne i64 %freed494, 0
  br i1 %freed_b495, label %br_unique104, label %br_shared105
br_shared105:
  call void @march_incrc(ptr %fv493)
  br label %br_body106
br_unique104:
  br label %br_body106
br_body106:
  %ld496 = load ptr, ptr %$f1103.addr
  %req.addr = alloca ptr
  store ptr %ld496, ptr %req.addr
  %ld497 = load ptr, ptr %req.addr
  %sl498 = call ptr @march_string_lit(ptr @.str24, i64 0)
  %cr499 = call ptr @Http.set_body$Request_T_$String(ptr %ld497, ptr %sl498)
  %$t1101.addr = alloca ptr
  store ptr %cr499, ptr %$t1101.addr
  %ld500 = load ptr, ptr %client.addr
  %ld501 = load ptr, ptr %$t1101.addr
  %cr502 = call ptr @HttpClient.run(ptr %ld500, ptr %ld501)
  store ptr %cr502, ptr %res_slot467
  br label %case_merge97
case_default98:
  unreachable
case_merge97:
  %case_r503 = load ptr, ptr %res_slot467
  ret ptr %case_r503
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld504 = load ptr, ptr %req.addr
  %sl505 = call ptr @march_string_lit(ptr @.str25, i64 10)
  %sl506 = call ptr @march_string_lit(ptr @.str26, i64 9)
  %cr507 = call ptr @Http.set_header$Request_V__3515$String$String(ptr %ld504, ptr %sl505, ptr %sl506)
  %req_1.addr = alloca ptr
  store ptr %cr507, ptr %req_1.addr
  %ld508 = load ptr, ptr %req_1.addr
  %sl509 = call ptr @march_string_lit(ptr @.str27, i64 6)
  %sl510 = call ptr @march_string_lit(ptr @.str28, i64 3)
  %cr511 = call ptr @Http.set_header$Request_V__3517$String$String(ptr %ld508, ptr %sl509, ptr %sl510)
  %req_2.addr = alloca ptr
  store ptr %cr511, ptr %req_2.addr
  %hp512 = call ptr @march_alloc(i64 24)
  %tgp513 = getelementptr i8, ptr %hp512, i64 8
  store i32 0, ptr %tgp513, align 4
  %ld514 = load ptr, ptr %req_2.addr
  %fp515 = getelementptr i8, ptr %hp512, i64 16
  store ptr %ld514, ptr %fp515, align 8
  ret ptr %hp512
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__5868_Result_Request_V__5867_V__5866(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld516 = load ptr, ptr %client.addr
  %res_slot517 = alloca ptr
  %tgp518 = getelementptr i8, ptr %ld516, i64 8
  %tag519 = load i32, ptr %tgp518, align 4
  switch i32 %tag519, label %case_default108 [
      i32 0, label %case_br109
  ]
case_br109:
  %fp520 = getelementptr i8, ptr %ld516, i64 16
  %fv521 = load ptr, ptr %fp520, align 8
  %$f889.addr = alloca ptr
  store ptr %fv521, ptr %$f889.addr
  %fp522 = getelementptr i8, ptr %ld516, i64 24
  %fv523 = load ptr, ptr %fp522, align 8
  %$f890.addr = alloca ptr
  store ptr %fv523, ptr %$f890.addr
  %fp524 = getelementptr i8, ptr %ld516, i64 32
  %fv525 = load ptr, ptr %fp524, align 8
  %$f891.addr = alloca ptr
  store ptr %fv525, ptr %$f891.addr
  %fp526 = getelementptr i8, ptr %ld516, i64 40
  %fv527 = load i64, ptr %fp526, align 8
  %$f892.addr = alloca i64
  store i64 %fv527, ptr %$f892.addr
  %fp528 = getelementptr i8, ptr %ld516, i64 48
  %fv529 = load i64, ptr %fp528, align 8
  %$f893.addr = alloca i64
  store i64 %fv529, ptr %$f893.addr
  %fp530 = getelementptr i8, ptr %ld516, i64 56
  %fv531 = load i64, ptr %fp530, align 8
  %$f894.addr = alloca i64
  store i64 %fv531, ptr %$f894.addr
  %ld532 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld532, ptr %backoff.addr
  %ld533 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld533, ptr %retries.addr
  %ld534 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld534, ptr %redir.addr
  %ld535 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld535, ptr %err_steps.addr
  %ld536 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld536, ptr %resp_steps.addr
  %ld537 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld537, ptr %req_steps.addr
  %hp538 = call ptr @march_alloc(i64 32)
  %tgp539 = getelementptr i8, ptr %hp538, i64 8
  store i32 0, ptr %tgp539, align 4
  %ld540 = load ptr, ptr %name.addr
  %fp541 = getelementptr i8, ptr %hp538, i64 16
  store ptr %ld540, ptr %fp541, align 8
  %ld542 = load ptr, ptr %step.addr
  %fp543 = getelementptr i8, ptr %hp538, i64 24
  store ptr %ld542, ptr %fp543, align 8
  %$t887.addr = alloca ptr
  store ptr %hp538, ptr %$t887.addr
  %ld544 = load ptr, ptr %req_steps.addr
  %ld545 = load ptr, ptr %$t887.addr
  %cr546 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld544, ptr %ld545)
  %$t888.addr = alloca ptr
  store ptr %cr546, ptr %$t888.addr
  %ld547 = load ptr, ptr %client.addr
  %ld548 = load ptr, ptr %$t888.addr
  %ld549 = load ptr, ptr %resp_steps.addr
  %ld550 = load ptr, ptr %err_steps.addr
  %ld551 = load i64, ptr %redir.addr
  %ld552 = load i64, ptr %retries.addr
  %ld553 = load i64, ptr %backoff.addr
  %rc554 = load i64, ptr %ld547, align 8
  %uniq555 = icmp eq i64 %rc554, 1
  %fbip_slot556 = alloca ptr
  br i1 %uniq555, label %fbip_reuse110, label %fbip_fresh111
fbip_reuse110:
  %tgp557 = getelementptr i8, ptr %ld547, i64 8
  store i32 0, ptr %tgp557, align 4
  %fp558 = getelementptr i8, ptr %ld547, i64 16
  store ptr %ld548, ptr %fp558, align 8
  %fp559 = getelementptr i8, ptr %ld547, i64 24
  store ptr %ld549, ptr %fp559, align 8
  %fp560 = getelementptr i8, ptr %ld547, i64 32
  store ptr %ld550, ptr %fp560, align 8
  %fp561 = getelementptr i8, ptr %ld547, i64 40
  store i64 %ld551, ptr %fp561, align 8
  %fp562 = getelementptr i8, ptr %ld547, i64 48
  store i64 %ld552, ptr %fp562, align 8
  %fp563 = getelementptr i8, ptr %ld547, i64 56
  store i64 %ld553, ptr %fp563, align 8
  store ptr %ld547, ptr %fbip_slot556
  br label %fbip_merge112
fbip_fresh111:
  call void @march_decrc(ptr %ld547)
  %hp564 = call ptr @march_alloc(i64 64)
  %tgp565 = getelementptr i8, ptr %hp564, i64 8
  store i32 0, ptr %tgp565, align 4
  %fp566 = getelementptr i8, ptr %hp564, i64 16
  store ptr %ld548, ptr %fp566, align 8
  %fp567 = getelementptr i8, ptr %hp564, i64 24
  store ptr %ld549, ptr %fp567, align 8
  %fp568 = getelementptr i8, ptr %hp564, i64 32
  store ptr %ld550, ptr %fp568, align 8
  %fp569 = getelementptr i8, ptr %hp564, i64 40
  store i64 %ld551, ptr %fp569, align 8
  %fp570 = getelementptr i8, ptr %hp564, i64 48
  store i64 %ld552, ptr %fp570, align 8
  %fp571 = getelementptr i8, ptr %hp564, i64 56
  store i64 %ld553, ptr %fp571, align 8
  store ptr %hp564, ptr %fbip_slot556
  br label %fbip_merge112
fbip_merge112:
  %fbip_r572 = load ptr, ptr %fbip_slot556
  store ptr %fbip_r572, ptr %res_slot517
  br label %case_merge107
case_default108:
  unreachable
case_merge107:
  %case_r573 = load ptr, ptr %res_slot517
  ret ptr %case_r573
}

define ptr @HttpClient.run(ptr %client.arg, ptr %req.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld574 = load ptr, ptr %client.addr
  %res_slot575 = alloca ptr
  %tgp576 = getelementptr i8, ptr %ld574, i64 8
  %tag577 = load i32, ptr %tgp576, align 4
  switch i32 %tag577, label %case_default114 [
      i32 0, label %case_br115
  ]
case_br115:
  %fp578 = getelementptr i8, ptr %ld574, i64 16
  %fv579 = load ptr, ptr %fp578, align 8
  %$f1052.addr = alloca ptr
  store ptr %fv579, ptr %$f1052.addr
  %fp580 = getelementptr i8, ptr %ld574, i64 24
  %fv581 = load ptr, ptr %fp580, align 8
  %$f1053.addr = alloca ptr
  store ptr %fv581, ptr %$f1053.addr
  %fp582 = getelementptr i8, ptr %ld574, i64 32
  %fv583 = load ptr, ptr %fp582, align 8
  %$f1054.addr = alloca ptr
  store ptr %fv583, ptr %$f1054.addr
  %fp584 = getelementptr i8, ptr %ld574, i64 40
  %fv585 = load i64, ptr %fp584, align 8
  %$f1055.addr = alloca i64
  store i64 %fv585, ptr %$f1055.addr
  %fp586 = getelementptr i8, ptr %ld574, i64 48
  %fv587 = load i64, ptr %fp586, align 8
  %$f1056.addr = alloca i64
  store i64 %fv587, ptr %$f1056.addr
  %fp588 = getelementptr i8, ptr %ld574, i64 56
  %fv589 = load i64, ptr %fp588, align 8
  %$f1057.addr = alloca i64
  store i64 %fv589, ptr %$f1057.addr
  %freed590 = call i64 @march_decrc_freed(ptr %ld574)
  %freed_b591 = icmp ne i64 %freed590, 0
  br i1 %freed_b591, label %br_unique116, label %br_shared117
br_shared117:
  call void @march_incrc(ptr %fv583)
  call void @march_incrc(ptr %fv581)
  call void @march_incrc(ptr %fv579)
  br label %br_body118
br_unique116:
  br label %br_body118
br_body118:
  %ld592 = load i64, ptr %$f1056.addr
  %max_retries.addr = alloca i64
  store i64 %ld592, ptr %max_retries.addr
  %ld593 = load i64, ptr %$f1055.addr
  %max_redir.addr = alloca i64
  store i64 %ld593, ptr %max_redir.addr
  %ld594 = load ptr, ptr %$f1054.addr
  %err_steps.addr = alloca ptr
  store ptr %ld594, ptr %err_steps.addr
  %ld595 = load ptr, ptr %$f1053.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld595, ptr %resp_steps.addr
  %ld596 = load ptr, ptr %$f1052.addr
  %req_steps.addr = alloca ptr
  store ptr %ld596, ptr %req_steps.addr
  %ld597 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld597)
  %ld598 = load ptr, ptr %req_steps.addr
  %ld599 = load ptr, ptr %req.addr
  %cr600 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld598, ptr %ld599)
  %$t1037.addr = alloca ptr
  store ptr %cr600, ptr %$t1037.addr
  %ld601 = load ptr, ptr %$t1037.addr
  %res_slot602 = alloca ptr
  %tgp603 = getelementptr i8, ptr %ld601, i64 8
  %tag604 = load i32, ptr %tgp603, align 4
  switch i32 %tag604, label %case_default120 [
      i32 1, label %case_br121
      i32 0, label %case_br122
  ]
case_br121:
  %fp605 = getelementptr i8, ptr %ld601, i64 16
  %fv606 = load ptr, ptr %fp605, align 8
  %$f1050.addr = alloca ptr
  store ptr %fv606, ptr %$f1050.addr
  %freed607 = call i64 @march_decrc_freed(ptr %ld601)
  %freed_b608 = icmp ne i64 %freed607, 0
  br i1 %freed_b608, label %br_unique123, label %br_shared124
br_shared124:
  call void @march_incrc(ptr %fv606)
  br label %br_body125
br_unique123:
  br label %br_body125
br_body125:
  %ld609 = load ptr, ptr %$f1050.addr
  %e.addr = alloca ptr
  store ptr %ld609, ptr %e.addr
  %ld610 = load ptr, ptr %err_steps.addr
  %ld611 = load ptr, ptr %req.addr
  %ld612 = load ptr, ptr %e.addr
  %cr613 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld610, ptr %ld611, ptr %ld612)
  store ptr %cr613, ptr %res_slot602
  br label %case_merge119
case_br122:
  %fp614 = getelementptr i8, ptr %ld601, i64 16
  %fv615 = load ptr, ptr %fp614, align 8
  %$f1051.addr = alloca ptr
  store ptr %fv615, ptr %$f1051.addr
  %freed616 = call i64 @march_decrc_freed(ptr %ld601)
  %freed_b617 = icmp ne i64 %freed616, 0
  br i1 %freed_b617, label %br_unique126, label %br_shared127
br_shared127:
  call void @march_incrc(ptr %fv615)
  br label %br_body128
br_unique126:
  br label %br_body128
br_body128:
  %ld618 = load ptr, ptr %$f1051.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld618, ptr %transformed_req.addr
  %ld619 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld619)
  %ld620 = load ptr, ptr %transformed_req.addr
  %ld621 = load i64, ptr %max_retries.addr
  %cr622 = call ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %ld620, i64 %ld621)
  %$t1038.addr = alloca ptr
  store ptr %cr622, ptr %$t1038.addr
  %ld623 = load ptr, ptr %$t1038.addr
  %res_slot624 = alloca ptr
  %tgp625 = getelementptr i8, ptr %ld623, i64 8
  %tag626 = load i32, ptr %tgp625, align 4
  switch i32 %tag626, label %case_default130 [
      i32 1, label %case_br131
      i32 0, label %case_br132
  ]
case_br131:
  %fp627 = getelementptr i8, ptr %ld623, i64 16
  %fv628 = load ptr, ptr %fp627, align 8
  %$f1048.addr = alloca ptr
  store ptr %fv628, ptr %$f1048.addr
  %freed629 = call i64 @march_decrc_freed(ptr %ld623)
  %freed_b630 = icmp ne i64 %freed629, 0
  br i1 %freed_b630, label %br_unique133, label %br_shared134
br_shared134:
  call void @march_incrc(ptr %fv628)
  br label %br_body135
br_unique133:
  br label %br_body135
br_body135:
  %ld631 = load ptr, ptr %$f1048.addr
  %transport_err.addr = alloca ptr
  store ptr %ld631, ptr %transport_err.addr
  %hp632 = call ptr @march_alloc(i64 24)
  %tgp633 = getelementptr i8, ptr %hp632, i64 8
  store i32 0, ptr %tgp633, align 4
  %ld634 = load ptr, ptr %transport_err.addr
  %fp635 = getelementptr i8, ptr %hp632, i64 16
  store ptr %ld634, ptr %fp635, align 8
  %$t1039.addr = alloca ptr
  store ptr %hp632, ptr %$t1039.addr
  %ld636 = load ptr, ptr %err_steps.addr
  %ld637 = load ptr, ptr %transformed_req.addr
  %ld638 = load ptr, ptr %$t1039.addr
  %cr639 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld636, ptr %ld637, ptr %ld638)
  store ptr %cr639, ptr %res_slot624
  br label %case_merge129
case_br132:
  %fp640 = getelementptr i8, ptr %ld623, i64 16
  %fv641 = load ptr, ptr %fp640, align 8
  %$f1049.addr = alloca ptr
  store ptr %fv641, ptr %$f1049.addr
  %freed642 = call i64 @march_decrc_freed(ptr %ld623)
  %freed_b643 = icmp ne i64 %freed642, 0
  br i1 %freed_b643, label %br_unique136, label %br_shared137
br_shared137:
  call void @march_incrc(ptr %fv641)
  br label %br_body138
br_unique136:
  br label %br_body138
br_body138:
  %ld644 = load ptr, ptr %$f1049.addr
  %resp.addr = alloca ptr
  store ptr %ld644, ptr %resp.addr
  %ld645 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld645)
  %ld646 = load ptr, ptr %transformed_req.addr
  %ld647 = load ptr, ptr %resp.addr
  %ld648 = load i64, ptr %max_redir.addr
  %cr649 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3336$Int$Int(ptr %ld646, ptr %ld647, i64 %ld648, i64 0)
  %$t1040.addr = alloca ptr
  store ptr %cr649, ptr %$t1040.addr
  %ld650 = load ptr, ptr %$t1040.addr
  %res_slot651 = alloca ptr
  %tgp652 = getelementptr i8, ptr %ld650, i64 8
  %tag653 = load i32, ptr %tgp652, align 4
  switch i32 %tag653, label %case_default140 [
      i32 1, label %case_br141
      i32 0, label %case_br142
  ]
case_br141:
  %fp654 = getelementptr i8, ptr %ld650, i64 16
  %fv655 = load ptr, ptr %fp654, align 8
  %$f1046.addr = alloca ptr
  store ptr %fv655, ptr %$f1046.addr
  %freed656 = call i64 @march_decrc_freed(ptr %ld650)
  %freed_b657 = icmp ne i64 %freed656, 0
  br i1 %freed_b657, label %br_unique143, label %br_shared144
br_shared144:
  call void @march_incrc(ptr %fv655)
  br label %br_body145
br_unique143:
  br label %br_body145
br_body145:
  %ld658 = load ptr, ptr %$f1046.addr
  %e_1.addr = alloca ptr
  store ptr %ld658, ptr %e_1.addr
  %ld659 = load ptr, ptr %err_steps.addr
  %ld660 = load ptr, ptr %transformed_req.addr
  %ld661 = load ptr, ptr %e_1.addr
  %cr662 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld659, ptr %ld660, ptr %ld661)
  store ptr %cr662, ptr %res_slot651
  br label %case_merge139
case_br142:
  %fp663 = getelementptr i8, ptr %ld650, i64 16
  %fv664 = load ptr, ptr %fp663, align 8
  %$f1047.addr = alloca ptr
  store ptr %fv664, ptr %$f1047.addr
  %freed665 = call i64 @march_decrc_freed(ptr %ld650)
  %freed_b666 = icmp ne i64 %freed665, 0
  br i1 %freed_b666, label %br_unique146, label %br_shared147
br_shared147:
  call void @march_incrc(ptr %fv664)
  br label %br_body148
br_unique146:
  br label %br_body148
br_body148:
  %ld667 = load ptr, ptr %$f1047.addr
  %final_resp.addr = alloca ptr
  store ptr %ld667, ptr %final_resp.addr
  %ld668 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld668)
  %ld669 = load ptr, ptr %resp_steps.addr
  %ld670 = load ptr, ptr %transformed_req.addr
  %ld671 = load ptr, ptr %final_resp.addr
  %cr672 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3336(ptr %ld669, ptr %ld670, ptr %ld671)
  %$t1041.addr = alloca ptr
  store ptr %cr672, ptr %$t1041.addr
  %ld673 = load ptr, ptr %$t1041.addr
  %res_slot674 = alloca ptr
  %tgp675 = getelementptr i8, ptr %ld673, i64 8
  %tag676 = load i32, ptr %tgp675, align 4
  switch i32 %tag676, label %case_default150 [
      i32 1, label %case_br151
      i32 0, label %case_br152
  ]
case_br151:
  %fp677 = getelementptr i8, ptr %ld673, i64 16
  %fv678 = load ptr, ptr %fp677, align 8
  %$f1042.addr = alloca ptr
  store ptr %fv678, ptr %$f1042.addr
  %freed679 = call i64 @march_decrc_freed(ptr %ld673)
  %freed_b680 = icmp ne i64 %freed679, 0
  br i1 %freed_b680, label %br_unique153, label %br_shared154
br_shared154:
  call void @march_incrc(ptr %fv678)
  br label %br_body155
br_unique153:
  br label %br_body155
br_body155:
  %ld681 = load ptr, ptr %$f1042.addr
  %e_2.addr = alloca ptr
  store ptr %ld681, ptr %e_2.addr
  %ld682 = load ptr, ptr %err_steps.addr
  %ld683 = load ptr, ptr %transformed_req.addr
  %ld684 = load ptr, ptr %e_2.addr
  %cr685 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld682, ptr %ld683, ptr %ld684)
  store ptr %cr685, ptr %res_slot674
  br label %case_merge149
case_br152:
  %fp686 = getelementptr i8, ptr %ld673, i64 16
  %fv687 = load ptr, ptr %fp686, align 8
  %$f1043.addr = alloca ptr
  store ptr %fv687, ptr %$f1043.addr
  %freed688 = call i64 @march_decrc_freed(ptr %ld673)
  %freed_b689 = icmp ne i64 %freed688, 0
  br i1 %freed_b689, label %br_unique156, label %br_shared157
br_shared157:
  call void @march_incrc(ptr %fv687)
  br label %br_body158
br_unique156:
  br label %br_body158
br_body158:
  %ld690 = load ptr, ptr %$f1043.addr
  %res_slot691 = alloca ptr
  %tgp692 = getelementptr i8, ptr %ld690, i64 8
  %tag693 = load i32, ptr %tgp692, align 4
  switch i32 %tag693, label %case_default160 [
      i32 0, label %case_br161
  ]
case_br161:
  %fp694 = getelementptr i8, ptr %ld690, i64 16
  %fv695 = load ptr, ptr %fp694, align 8
  %$f1044.addr = alloca ptr
  store ptr %fv695, ptr %$f1044.addr
  %fp696 = getelementptr i8, ptr %ld690, i64 24
  %fv697 = load ptr, ptr %fp696, align 8
  %$f1045.addr = alloca ptr
  store ptr %fv697, ptr %$f1045.addr
  %freed698 = call i64 @march_decrc_freed(ptr %ld690)
  %freed_b699 = icmp ne i64 %freed698, 0
  br i1 %freed_b699, label %br_unique162, label %br_shared163
br_shared163:
  call void @march_incrc(ptr %fv697)
  call void @march_incrc(ptr %fv695)
  br label %br_body164
br_unique162:
  br label %br_body164
br_body164:
  %ld700 = load ptr, ptr %$f1045.addr
  %response.addr = alloca ptr
  store ptr %ld700, ptr %response.addr
  %hp701 = call ptr @march_alloc(i64 24)
  %tgp702 = getelementptr i8, ptr %hp701, i64 8
  store i32 0, ptr %tgp702, align 4
  %ld703 = load ptr, ptr %response.addr
  %fp704 = getelementptr i8, ptr %hp701, i64 16
  store ptr %ld703, ptr %fp704, align 8
  store ptr %hp701, ptr %res_slot691
  br label %case_merge159
case_default160:
  unreachable
case_merge159:
  %case_r705 = load ptr, ptr %res_slot691
  store ptr %case_r705, ptr %res_slot674
  br label %case_merge149
case_default150:
  unreachable
case_merge149:
  %case_r706 = load ptr, ptr %res_slot674
  store ptr %case_r706, ptr %res_slot651
  br label %case_merge139
case_default140:
  unreachable
case_merge139:
  %case_r707 = load ptr, ptr %res_slot651
  store ptr %case_r707, ptr %res_slot624
  br label %case_merge129
case_default130:
  unreachable
case_merge129:
  %case_r708 = load ptr, ptr %res_slot624
  store ptr %case_r708, ptr %res_slot602
  br label %case_merge119
case_default120:
  unreachable
case_merge119:
  %case_r709 = load ptr, ptr %res_slot602
  store ptr %case_r709, ptr %res_slot575
  br label %case_merge113
case_default114:
  unreachable
case_merge113:
  %case_r710 = load ptr, ptr %res_slot575
  ret ptr %case_r710
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld711 = load ptr, ptr %req.addr
  %res_slot712 = alloca ptr
  %tgp713 = getelementptr i8, ptr %ld711, i64 8
  %tag714 = load i32, ptr %tgp713, align 4
  switch i32 %tag714, label %case_default166 [
      i32 0, label %case_br167
  ]
case_br167:
  %fp715 = getelementptr i8, ptr %ld711, i64 16
  %fv716 = load ptr, ptr %fp715, align 8
  %$f648.addr = alloca ptr
  store ptr %fv716, ptr %$f648.addr
  %fp717 = getelementptr i8, ptr %ld711, i64 24
  %fv718 = load ptr, ptr %fp717, align 8
  %$f649.addr = alloca ptr
  store ptr %fv718, ptr %$f649.addr
  %fp719 = getelementptr i8, ptr %ld711, i64 32
  %fv720 = load ptr, ptr %fp719, align 8
  %$f650.addr = alloca ptr
  store ptr %fv720, ptr %$f650.addr
  %fp721 = getelementptr i8, ptr %ld711, i64 40
  %fv722 = load ptr, ptr %fp721, align 8
  %$f651.addr = alloca ptr
  store ptr %fv722, ptr %$f651.addr
  %fp723 = getelementptr i8, ptr %ld711, i64 48
  %fv724 = load ptr, ptr %fp723, align 8
  %$f652.addr = alloca ptr
  store ptr %fv724, ptr %$f652.addr
  %fp725 = getelementptr i8, ptr %ld711, i64 56
  %fv726 = load ptr, ptr %fp725, align 8
  %$f653.addr = alloca ptr
  store ptr %fv726, ptr %$f653.addr
  %fp727 = getelementptr i8, ptr %ld711, i64 64
  %fv728 = load ptr, ptr %fp727, align 8
  %$f654.addr = alloca ptr
  store ptr %fv728, ptr %$f654.addr
  %fp729 = getelementptr i8, ptr %ld711, i64 72
  %fv730 = load ptr, ptr %fp729, align 8
  %$f655.addr = alloca ptr
  store ptr %fv730, ptr %$f655.addr
  %ld731 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld731, ptr %hd.addr
  %ld732 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld732, ptr %q.addr
  %ld733 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld733, ptr %pa.addr
  %ld734 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld734, ptr %p.addr
  %ld735 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld735, ptr %h.addr
  %ld736 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld736, ptr %sc.addr
  %ld737 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld737, ptr %m.addr
  %ld738 = load ptr, ptr %req.addr
  %ld739 = load ptr, ptr %m.addr
  %ld740 = load ptr, ptr %sc.addr
  %ld741 = load ptr, ptr %h.addr
  %ld742 = load ptr, ptr %p.addr
  %ld743 = load ptr, ptr %pa.addr
  %ld744 = load ptr, ptr %q.addr
  %ld745 = load ptr, ptr %hd.addr
  %ld746 = load ptr, ptr %new_body.addr
  %rc747 = load i64, ptr %ld738, align 8
  %uniq748 = icmp eq i64 %rc747, 1
  %fbip_slot749 = alloca ptr
  br i1 %uniq748, label %fbip_reuse168, label %fbip_fresh169
fbip_reuse168:
  %tgp750 = getelementptr i8, ptr %ld738, i64 8
  store i32 0, ptr %tgp750, align 4
  %fp751 = getelementptr i8, ptr %ld738, i64 16
  store ptr %ld739, ptr %fp751, align 8
  %fp752 = getelementptr i8, ptr %ld738, i64 24
  store ptr %ld740, ptr %fp752, align 8
  %fp753 = getelementptr i8, ptr %ld738, i64 32
  store ptr %ld741, ptr %fp753, align 8
  %fp754 = getelementptr i8, ptr %ld738, i64 40
  store ptr %ld742, ptr %fp754, align 8
  %fp755 = getelementptr i8, ptr %ld738, i64 48
  store ptr %ld743, ptr %fp755, align 8
  %fp756 = getelementptr i8, ptr %ld738, i64 56
  store ptr %ld744, ptr %fp756, align 8
  %fp757 = getelementptr i8, ptr %ld738, i64 64
  store ptr %ld745, ptr %fp757, align 8
  %fp758 = getelementptr i8, ptr %ld738, i64 72
  store ptr %ld746, ptr %fp758, align 8
  store ptr %ld738, ptr %fbip_slot749
  br label %fbip_merge170
fbip_fresh169:
  call void @march_decrc(ptr %ld738)
  %hp759 = call ptr @march_alloc(i64 80)
  %tgp760 = getelementptr i8, ptr %hp759, i64 8
  store i32 0, ptr %tgp760, align 4
  %fp761 = getelementptr i8, ptr %hp759, i64 16
  store ptr %ld739, ptr %fp761, align 8
  %fp762 = getelementptr i8, ptr %hp759, i64 24
  store ptr %ld740, ptr %fp762, align 8
  %fp763 = getelementptr i8, ptr %hp759, i64 32
  store ptr %ld741, ptr %fp763, align 8
  %fp764 = getelementptr i8, ptr %hp759, i64 40
  store ptr %ld742, ptr %fp764, align 8
  %fp765 = getelementptr i8, ptr %hp759, i64 48
  store ptr %ld743, ptr %fp765, align 8
  %fp766 = getelementptr i8, ptr %hp759, i64 56
  store ptr %ld744, ptr %fp766, align 8
  %fp767 = getelementptr i8, ptr %hp759, i64 64
  store ptr %ld745, ptr %fp767, align 8
  %fp768 = getelementptr i8, ptr %hp759, i64 72
  store ptr %ld746, ptr %fp768, align 8
  store ptr %hp759, ptr %fbip_slot749
  br label %fbip_merge170
fbip_merge170:
  %fbip_r769 = load ptr, ptr %fbip_slot749
  store ptr %fbip_r769, ptr %res_slot712
  br label %case_merge165
case_default166:
  unreachable
case_merge165:
  %case_r770 = load ptr, ptr %res_slot712
  ret ptr %case_r770
}

define ptr @Http.set_header$Request_V__3517$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld771 = load ptr, ptr %req.addr
  %res_slot772 = alloca ptr
  %tgp773 = getelementptr i8, ptr %ld771, i64 8
  %tag774 = load i32, ptr %tgp773, align 4
  switch i32 %tag774, label %case_default172 [
      i32 0, label %case_br173
  ]
case_br173:
  %fp775 = getelementptr i8, ptr %ld771, i64 16
  %fv776 = load ptr, ptr %fp775, align 8
  %$f658.addr = alloca ptr
  store ptr %fv776, ptr %$f658.addr
  %fp777 = getelementptr i8, ptr %ld771, i64 24
  %fv778 = load ptr, ptr %fp777, align 8
  %$f659.addr = alloca ptr
  store ptr %fv778, ptr %$f659.addr
  %fp779 = getelementptr i8, ptr %ld771, i64 32
  %fv780 = load ptr, ptr %fp779, align 8
  %$f660.addr = alloca ptr
  store ptr %fv780, ptr %$f660.addr
  %fp781 = getelementptr i8, ptr %ld771, i64 40
  %fv782 = load ptr, ptr %fp781, align 8
  %$f661.addr = alloca ptr
  store ptr %fv782, ptr %$f661.addr
  %fp783 = getelementptr i8, ptr %ld771, i64 48
  %fv784 = load ptr, ptr %fp783, align 8
  %$f662.addr = alloca ptr
  store ptr %fv784, ptr %$f662.addr
  %fp785 = getelementptr i8, ptr %ld771, i64 56
  %fv786 = load ptr, ptr %fp785, align 8
  %$f663.addr = alloca ptr
  store ptr %fv786, ptr %$f663.addr
  %fp787 = getelementptr i8, ptr %ld771, i64 64
  %fv788 = load ptr, ptr %fp787, align 8
  %$f664.addr = alloca ptr
  store ptr %fv788, ptr %$f664.addr
  %fp789 = getelementptr i8, ptr %ld771, i64 72
  %fv790 = load ptr, ptr %fp789, align 8
  %$f665.addr = alloca ptr
  store ptr %fv790, ptr %$f665.addr
  %ld791 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld791, ptr %bd.addr
  %ld792 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld792, ptr %hd.addr
  %ld793 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld793, ptr %q.addr
  %ld794 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld794, ptr %pa.addr
  %ld795 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld795, ptr %p.addr
  %ld796 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld796, ptr %h.addr
  %ld797 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld797, ptr %sc.addr
  %ld798 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld798, ptr %m.addr
  %hp799 = call ptr @march_alloc(i64 32)
  %tgp800 = getelementptr i8, ptr %hp799, i64 8
  store i32 0, ptr %tgp800, align 4
  %ld801 = load ptr, ptr %name.addr
  %fp802 = getelementptr i8, ptr %hp799, i64 16
  store ptr %ld801, ptr %fp802, align 8
  %ld803 = load ptr, ptr %value.addr
  %fp804 = getelementptr i8, ptr %hp799, i64 24
  store ptr %ld803, ptr %fp804, align 8
  %$t656.addr = alloca ptr
  store ptr %hp799, ptr %$t656.addr
  %hp805 = call ptr @march_alloc(i64 32)
  %tgp806 = getelementptr i8, ptr %hp805, i64 8
  store i32 1, ptr %tgp806, align 4
  %ld807 = load ptr, ptr %$t656.addr
  %fp808 = getelementptr i8, ptr %hp805, i64 16
  store ptr %ld807, ptr %fp808, align 8
  %ld809 = load ptr, ptr %hd.addr
  %fp810 = getelementptr i8, ptr %hp805, i64 24
  store ptr %ld809, ptr %fp810, align 8
  %$t657.addr = alloca ptr
  store ptr %hp805, ptr %$t657.addr
  %ld811 = load ptr, ptr %req.addr
  %ld812 = load ptr, ptr %m.addr
  %ld813 = load ptr, ptr %sc.addr
  %ld814 = load ptr, ptr %h.addr
  %ld815 = load ptr, ptr %p.addr
  %ld816 = load ptr, ptr %pa.addr
  %ld817 = load ptr, ptr %q.addr
  %ld818 = load ptr, ptr %$t657.addr
  %ld819 = load ptr, ptr %bd.addr
  %rc820 = load i64, ptr %ld811, align 8
  %uniq821 = icmp eq i64 %rc820, 1
  %fbip_slot822 = alloca ptr
  br i1 %uniq821, label %fbip_reuse174, label %fbip_fresh175
fbip_reuse174:
  %tgp823 = getelementptr i8, ptr %ld811, i64 8
  store i32 0, ptr %tgp823, align 4
  %fp824 = getelementptr i8, ptr %ld811, i64 16
  store ptr %ld812, ptr %fp824, align 8
  %fp825 = getelementptr i8, ptr %ld811, i64 24
  store ptr %ld813, ptr %fp825, align 8
  %fp826 = getelementptr i8, ptr %ld811, i64 32
  store ptr %ld814, ptr %fp826, align 8
  %fp827 = getelementptr i8, ptr %ld811, i64 40
  store ptr %ld815, ptr %fp827, align 8
  %fp828 = getelementptr i8, ptr %ld811, i64 48
  store ptr %ld816, ptr %fp828, align 8
  %fp829 = getelementptr i8, ptr %ld811, i64 56
  store ptr %ld817, ptr %fp829, align 8
  %fp830 = getelementptr i8, ptr %ld811, i64 64
  store ptr %ld818, ptr %fp830, align 8
  %fp831 = getelementptr i8, ptr %ld811, i64 72
  store ptr %ld819, ptr %fp831, align 8
  store ptr %ld811, ptr %fbip_slot822
  br label %fbip_merge176
fbip_fresh175:
  call void @march_decrc(ptr %ld811)
  %hp832 = call ptr @march_alloc(i64 80)
  %tgp833 = getelementptr i8, ptr %hp832, i64 8
  store i32 0, ptr %tgp833, align 4
  %fp834 = getelementptr i8, ptr %hp832, i64 16
  store ptr %ld812, ptr %fp834, align 8
  %fp835 = getelementptr i8, ptr %hp832, i64 24
  store ptr %ld813, ptr %fp835, align 8
  %fp836 = getelementptr i8, ptr %hp832, i64 32
  store ptr %ld814, ptr %fp836, align 8
  %fp837 = getelementptr i8, ptr %hp832, i64 40
  store ptr %ld815, ptr %fp837, align 8
  %fp838 = getelementptr i8, ptr %hp832, i64 48
  store ptr %ld816, ptr %fp838, align 8
  %fp839 = getelementptr i8, ptr %hp832, i64 56
  store ptr %ld817, ptr %fp839, align 8
  %fp840 = getelementptr i8, ptr %hp832, i64 64
  store ptr %ld818, ptr %fp840, align 8
  %fp841 = getelementptr i8, ptr %hp832, i64 72
  store ptr %ld819, ptr %fp841, align 8
  store ptr %hp832, ptr %fbip_slot822
  br label %fbip_merge176
fbip_merge176:
  %fbip_r842 = load ptr, ptr %fbip_slot822
  store ptr %fbip_r842, ptr %res_slot772
  br label %case_merge171
case_default172:
  unreachable
case_merge171:
  %case_r843 = load ptr, ptr %res_slot772
  ret ptr %case_r843
}

define ptr @Http.set_header$Request_V__3515$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld844 = load ptr, ptr %req.addr
  %res_slot845 = alloca ptr
  %tgp846 = getelementptr i8, ptr %ld844, i64 8
  %tag847 = load i32, ptr %tgp846, align 4
  switch i32 %tag847, label %case_default178 [
      i32 0, label %case_br179
  ]
case_br179:
  %fp848 = getelementptr i8, ptr %ld844, i64 16
  %fv849 = load ptr, ptr %fp848, align 8
  %$f658.addr = alloca ptr
  store ptr %fv849, ptr %$f658.addr
  %fp850 = getelementptr i8, ptr %ld844, i64 24
  %fv851 = load ptr, ptr %fp850, align 8
  %$f659.addr = alloca ptr
  store ptr %fv851, ptr %$f659.addr
  %fp852 = getelementptr i8, ptr %ld844, i64 32
  %fv853 = load ptr, ptr %fp852, align 8
  %$f660.addr = alloca ptr
  store ptr %fv853, ptr %$f660.addr
  %fp854 = getelementptr i8, ptr %ld844, i64 40
  %fv855 = load ptr, ptr %fp854, align 8
  %$f661.addr = alloca ptr
  store ptr %fv855, ptr %$f661.addr
  %fp856 = getelementptr i8, ptr %ld844, i64 48
  %fv857 = load ptr, ptr %fp856, align 8
  %$f662.addr = alloca ptr
  store ptr %fv857, ptr %$f662.addr
  %fp858 = getelementptr i8, ptr %ld844, i64 56
  %fv859 = load ptr, ptr %fp858, align 8
  %$f663.addr = alloca ptr
  store ptr %fv859, ptr %$f663.addr
  %fp860 = getelementptr i8, ptr %ld844, i64 64
  %fv861 = load ptr, ptr %fp860, align 8
  %$f664.addr = alloca ptr
  store ptr %fv861, ptr %$f664.addr
  %fp862 = getelementptr i8, ptr %ld844, i64 72
  %fv863 = load ptr, ptr %fp862, align 8
  %$f665.addr = alloca ptr
  store ptr %fv863, ptr %$f665.addr
  %ld864 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld864, ptr %bd.addr
  %ld865 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld865, ptr %hd.addr
  %ld866 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld866, ptr %q.addr
  %ld867 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld867, ptr %pa.addr
  %ld868 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld868, ptr %p.addr
  %ld869 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld869, ptr %h.addr
  %ld870 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld870, ptr %sc.addr
  %ld871 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld871, ptr %m.addr
  %hp872 = call ptr @march_alloc(i64 32)
  %tgp873 = getelementptr i8, ptr %hp872, i64 8
  store i32 0, ptr %tgp873, align 4
  %ld874 = load ptr, ptr %name.addr
  %fp875 = getelementptr i8, ptr %hp872, i64 16
  store ptr %ld874, ptr %fp875, align 8
  %ld876 = load ptr, ptr %value.addr
  %fp877 = getelementptr i8, ptr %hp872, i64 24
  store ptr %ld876, ptr %fp877, align 8
  %$t656.addr = alloca ptr
  store ptr %hp872, ptr %$t656.addr
  %hp878 = call ptr @march_alloc(i64 32)
  %tgp879 = getelementptr i8, ptr %hp878, i64 8
  store i32 1, ptr %tgp879, align 4
  %ld880 = load ptr, ptr %$t656.addr
  %fp881 = getelementptr i8, ptr %hp878, i64 16
  store ptr %ld880, ptr %fp881, align 8
  %ld882 = load ptr, ptr %hd.addr
  %fp883 = getelementptr i8, ptr %hp878, i64 24
  store ptr %ld882, ptr %fp883, align 8
  %$t657.addr = alloca ptr
  store ptr %hp878, ptr %$t657.addr
  %ld884 = load ptr, ptr %req.addr
  %ld885 = load ptr, ptr %m.addr
  %ld886 = load ptr, ptr %sc.addr
  %ld887 = load ptr, ptr %h.addr
  %ld888 = load ptr, ptr %p.addr
  %ld889 = load ptr, ptr %pa.addr
  %ld890 = load ptr, ptr %q.addr
  %ld891 = load ptr, ptr %$t657.addr
  %ld892 = load ptr, ptr %bd.addr
  %rc893 = load i64, ptr %ld884, align 8
  %uniq894 = icmp eq i64 %rc893, 1
  %fbip_slot895 = alloca ptr
  br i1 %uniq894, label %fbip_reuse180, label %fbip_fresh181
fbip_reuse180:
  %tgp896 = getelementptr i8, ptr %ld884, i64 8
  store i32 0, ptr %tgp896, align 4
  %fp897 = getelementptr i8, ptr %ld884, i64 16
  store ptr %ld885, ptr %fp897, align 8
  %fp898 = getelementptr i8, ptr %ld884, i64 24
  store ptr %ld886, ptr %fp898, align 8
  %fp899 = getelementptr i8, ptr %ld884, i64 32
  store ptr %ld887, ptr %fp899, align 8
  %fp900 = getelementptr i8, ptr %ld884, i64 40
  store ptr %ld888, ptr %fp900, align 8
  %fp901 = getelementptr i8, ptr %ld884, i64 48
  store ptr %ld889, ptr %fp901, align 8
  %fp902 = getelementptr i8, ptr %ld884, i64 56
  store ptr %ld890, ptr %fp902, align 8
  %fp903 = getelementptr i8, ptr %ld884, i64 64
  store ptr %ld891, ptr %fp903, align 8
  %fp904 = getelementptr i8, ptr %ld884, i64 72
  store ptr %ld892, ptr %fp904, align 8
  store ptr %ld884, ptr %fbip_slot895
  br label %fbip_merge182
fbip_fresh181:
  call void @march_decrc(ptr %ld884)
  %hp905 = call ptr @march_alloc(i64 80)
  %tgp906 = getelementptr i8, ptr %hp905, i64 8
  store i32 0, ptr %tgp906, align 4
  %fp907 = getelementptr i8, ptr %hp905, i64 16
  store ptr %ld885, ptr %fp907, align 8
  %fp908 = getelementptr i8, ptr %hp905, i64 24
  store ptr %ld886, ptr %fp908, align 8
  %fp909 = getelementptr i8, ptr %hp905, i64 32
  store ptr %ld887, ptr %fp909, align 8
  %fp910 = getelementptr i8, ptr %hp905, i64 40
  store ptr %ld888, ptr %fp910, align 8
  %fp911 = getelementptr i8, ptr %hp905, i64 48
  store ptr %ld889, ptr %fp911, align 8
  %fp912 = getelementptr i8, ptr %hp905, i64 56
  store ptr %ld890, ptr %fp912, align 8
  %fp913 = getelementptr i8, ptr %hp905, i64 64
  store ptr %ld891, ptr %fp913, align 8
  %fp914 = getelementptr i8, ptr %hp905, i64 72
  store ptr %ld892, ptr %fp914, align 8
  store ptr %hp905, ptr %fbip_slot895
  br label %fbip_merge182
fbip_merge182:
  %fbip_r915 = load ptr, ptr %fbip_slot895
  store ptr %fbip_r915, ptr %res_slot845
  br label %case_merge177
case_default178:
  unreachable
case_merge177:
  %case_r916 = load ptr, ptr %res_slot845
  ret ptr %case_r916
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld917 = load ptr, ptr %xs.addr
  %res_slot918 = alloca ptr
  %tgp919 = getelementptr i8, ptr %ld917, i64 8
  %tag920 = load i32, ptr %tgp919, align 4
  switch i32 %tag920, label %case_default184 [
      i32 0, label %case_br185
      i32 1, label %case_br186
  ]
case_br185:
  %ld921 = load ptr, ptr %xs.addr
  %rc922 = load i64, ptr %ld921, align 8
  %uniq923 = icmp eq i64 %rc922, 1
  %fbip_slot924 = alloca ptr
  br i1 %uniq923, label %fbip_reuse187, label %fbip_fresh188
fbip_reuse187:
  %tgp925 = getelementptr i8, ptr %ld921, i64 8
  store i32 0, ptr %tgp925, align 4
  store ptr %ld921, ptr %fbip_slot924
  br label %fbip_merge189
fbip_fresh188:
  call void @march_decrc(ptr %ld921)
  %hp926 = call ptr @march_alloc(i64 16)
  %tgp927 = getelementptr i8, ptr %hp926, i64 8
  store i32 0, ptr %tgp927, align 4
  store ptr %hp926, ptr %fbip_slot924
  br label %fbip_merge189
fbip_merge189:
  %fbip_r928 = load ptr, ptr %fbip_slot924
  %$t883.addr = alloca ptr
  store ptr %fbip_r928, ptr %$t883.addr
  %hp929 = call ptr @march_alloc(i64 32)
  %tgp930 = getelementptr i8, ptr %hp929, i64 8
  store i32 1, ptr %tgp930, align 4
  %ld931 = load ptr, ptr %x.addr
  %fp932 = getelementptr i8, ptr %hp929, i64 16
  store ptr %ld931, ptr %fp932, align 8
  %ld933 = load ptr, ptr %$t883.addr
  %fp934 = getelementptr i8, ptr %hp929, i64 24
  store ptr %ld933, ptr %fp934, align 8
  store ptr %hp929, ptr %res_slot918
  br label %case_merge183
case_br186:
  %fp935 = getelementptr i8, ptr %ld917, i64 16
  %fv936 = load ptr, ptr %fp935, align 8
  %$f885.addr = alloca ptr
  store ptr %fv936, ptr %$f885.addr
  %fp937 = getelementptr i8, ptr %ld917, i64 24
  %fv938 = load ptr, ptr %fp937, align 8
  %$f886.addr = alloca ptr
  store ptr %fv938, ptr %$f886.addr
  %ld939 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld939, ptr %t.addr
  %ld940 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld940, ptr %h.addr
  %ld941 = load ptr, ptr %t.addr
  %ld942 = load ptr, ptr %x.addr
  %cr943 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld941, ptr %ld942)
  %$t884.addr = alloca ptr
  store ptr %cr943, ptr %$t884.addr
  %ld944 = load ptr, ptr %xs.addr
  %ld945 = load ptr, ptr %h.addr
  %ld946 = load ptr, ptr %$t884.addr
  %rc947 = load i64, ptr %ld944, align 8
  %uniq948 = icmp eq i64 %rc947, 1
  %fbip_slot949 = alloca ptr
  br i1 %uniq948, label %fbip_reuse190, label %fbip_fresh191
fbip_reuse190:
  %tgp950 = getelementptr i8, ptr %ld944, i64 8
  store i32 1, ptr %tgp950, align 4
  %fp951 = getelementptr i8, ptr %ld944, i64 16
  store ptr %ld945, ptr %fp951, align 8
  %fp952 = getelementptr i8, ptr %ld944, i64 24
  store ptr %ld946, ptr %fp952, align 8
  store ptr %ld944, ptr %fbip_slot949
  br label %fbip_merge192
fbip_fresh191:
  call void @march_decrc(ptr %ld944)
  %hp953 = call ptr @march_alloc(i64 32)
  %tgp954 = getelementptr i8, ptr %hp953, i64 8
  store i32 1, ptr %tgp954, align 4
  %fp955 = getelementptr i8, ptr %hp953, i64 16
  store ptr %ld945, ptr %fp955, align 8
  %fp956 = getelementptr i8, ptr %hp953, i64 24
  store ptr %ld946, ptr %fp956, align 8
  store ptr %hp953, ptr %fbip_slot949
  br label %fbip_merge192
fbip_merge192:
  %fbip_r957 = load ptr, ptr %fbip_slot949
  store ptr %fbip_r957, ptr %res_slot918
  br label %case_merge183
case_default184:
  unreachable
case_merge183:
  %case_r958 = load ptr, ptr %res_slot918
  ret ptr %case_r958
}

define ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %steps.arg, ptr %req.arg, ptr %err.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %err.addr = alloca ptr
  store ptr %err.arg, ptr %err.addr
  %ld959 = load ptr, ptr %steps.addr
  %res_slot960 = alloca ptr
  %tgp961 = getelementptr i8, ptr %ld959, i64 8
  %tag962 = load i32, ptr %tgp961, align 4
  switch i32 %tag962, label %case_default194 [
      i32 0, label %case_br195
      i32 1, label %case_br196
  ]
case_br195:
  %ld963 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld963)
  %hp964 = call ptr @march_alloc(i64 24)
  %tgp965 = getelementptr i8, ptr %hp964, i64 8
  store i32 1, ptr %tgp965, align 4
  %ld966 = load ptr, ptr %err.addr
  %fp967 = getelementptr i8, ptr %hp964, i64 16
  store ptr %ld966, ptr %fp967, align 8
  store ptr %hp964, ptr %res_slot960
  br label %case_merge193
case_br196:
  %fp968 = getelementptr i8, ptr %ld959, i64 16
  %fv969 = load ptr, ptr %fp968, align 8
  %$f974.addr = alloca ptr
  store ptr %fv969, ptr %$f974.addr
  %fp970 = getelementptr i8, ptr %ld959, i64 24
  %fv971 = load ptr, ptr %fp970, align 8
  %$f975.addr = alloca ptr
  store ptr %fv971, ptr %$f975.addr
  %freed972 = call i64 @march_decrc_freed(ptr %ld959)
  %freed_b973 = icmp ne i64 %freed972, 0
  br i1 %freed_b973, label %br_unique197, label %br_shared198
br_shared198:
  call void @march_incrc(ptr %fv971)
  call void @march_incrc(ptr %fv969)
  br label %br_body199
br_unique197:
  br label %br_body199
br_body199:
  %ld974 = load ptr, ptr %$f974.addr
  %res_slot975 = alloca ptr
  %tgp976 = getelementptr i8, ptr %ld974, i64 8
  %tag977 = load i32, ptr %tgp976, align 4
  switch i32 %tag977, label %case_default201 [
      i32 0, label %case_br202
  ]
case_br202:
  %fp978 = getelementptr i8, ptr %ld974, i64 16
  %fv979 = load ptr, ptr %fp978, align 8
  %$f976.addr = alloca ptr
  store ptr %fv979, ptr %$f976.addr
  %fp980 = getelementptr i8, ptr %ld974, i64 24
  %fv981 = load ptr, ptr %fp980, align 8
  %$f977.addr = alloca ptr
  store ptr %fv981, ptr %$f977.addr
  %freed982 = call i64 @march_decrc_freed(ptr %ld974)
  %freed_b983 = icmp ne i64 %freed982, 0
  br i1 %freed_b983, label %br_unique203, label %br_shared204
br_shared204:
  call void @march_incrc(ptr %fv981)
  call void @march_incrc(ptr %fv979)
  br label %br_body205
br_unique203:
  br label %br_body205
br_body205:
  %ld984 = load ptr, ptr %$f975.addr
  %rest.addr = alloca ptr
  store ptr %ld984, ptr %rest.addr
  %ld985 = load ptr, ptr %$f977.addr
  %step_fn.addr = alloca ptr
  store ptr %ld985, ptr %step_fn.addr
  %ld986 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld986)
  %ld987 = load ptr, ptr %step_fn.addr
  %fp988 = getelementptr i8, ptr %ld987, i64 16
  %fv989 = load ptr, ptr %fp988, align 8
  %ld990 = load ptr, ptr %req.addr
  %ld991 = load ptr, ptr %err.addr
  %cr992 = call ptr (ptr, ptr, ptr) %fv989(ptr %ld987, ptr %ld990, ptr %ld991)
  %$t971.addr = alloca ptr
  store ptr %cr992, ptr %$t971.addr
  %ld993 = load ptr, ptr %$t971.addr
  %res_slot994 = alloca ptr
  %tgp995 = getelementptr i8, ptr %ld993, i64 8
  %tag996 = load i32, ptr %tgp995, align 4
  switch i32 %tag996, label %case_default207 [
      i32 0, label %case_br208
      i32 1, label %case_br209
  ]
case_br208:
  %fp997 = getelementptr i8, ptr %ld993, i64 16
  %fv998 = load ptr, ptr %fp997, align 8
  %$f972.addr = alloca ptr
  store ptr %fv998, ptr %$f972.addr
  %freed999 = call i64 @march_decrc_freed(ptr %ld993)
  %freed_b1000 = icmp ne i64 %freed999, 0
  br i1 %freed_b1000, label %br_unique210, label %br_shared211
br_shared211:
  call void @march_incrc(ptr %fv998)
  br label %br_body212
br_unique210:
  br label %br_body212
br_body212:
  %ld1001 = load ptr, ptr %$f972.addr
  %resp.addr = alloca ptr
  store ptr %ld1001, ptr %resp.addr
  %hp1002 = call ptr @march_alloc(i64 24)
  %tgp1003 = getelementptr i8, ptr %hp1002, i64 8
  store i32 0, ptr %tgp1003, align 4
  %ld1004 = load ptr, ptr %resp.addr
  %fp1005 = getelementptr i8, ptr %hp1002, i64 16
  store ptr %ld1004, ptr %fp1005, align 8
  store ptr %hp1002, ptr %res_slot994
  br label %case_merge206
case_br209:
  %fp1006 = getelementptr i8, ptr %ld993, i64 16
  %fv1007 = load ptr, ptr %fp1006, align 8
  %$f973.addr = alloca ptr
  store ptr %fv1007, ptr %$f973.addr
  %freed1008 = call i64 @march_decrc_freed(ptr %ld993)
  %freed_b1009 = icmp ne i64 %freed1008, 0
  br i1 %freed_b1009, label %br_unique213, label %br_shared214
br_shared214:
  call void @march_incrc(ptr %fv1007)
  br label %br_body215
br_unique213:
  br label %br_body215
br_body215:
  %ld1010 = load ptr, ptr %$f973.addr
  %new_err.addr = alloca ptr
  store ptr %ld1010, ptr %new_err.addr
  %ld1011 = load ptr, ptr %rest.addr
  %ld1012 = load ptr, ptr %req.addr
  %ld1013 = load ptr, ptr %new_err.addr
  %cr1014 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1011, ptr %ld1012, ptr %ld1013)
  store ptr %cr1014, ptr %res_slot994
  br label %case_merge206
case_default207:
  unreachable
case_merge206:
  %case_r1015 = load ptr, ptr %res_slot994
  store ptr %case_r1015, ptr %res_slot975
  br label %case_merge200
case_default201:
  unreachable
case_merge200:
  %case_r1016 = load ptr, ptr %res_slot975
  store ptr %case_r1016, ptr %res_slot960
  br label %case_merge193
case_default194:
  unreachable
case_merge193:
  %case_r1017 = load ptr, ptr %res_slot960
  ret ptr %case_r1017
}

define ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3336(ptr %steps.arg, ptr %req.arg, ptr %resp.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1018 = load ptr, ptr %steps.addr
  %res_slot1019 = alloca ptr
  %tgp1020 = getelementptr i8, ptr %ld1018, i64 8
  %tag1021 = load i32, ptr %tgp1020, align 4
  switch i32 %tag1021, label %case_default217 [
      i32 0, label %case_br218
      i32 1, label %case_br219
  ]
case_br218:
  %ld1022 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1022)
  %hp1023 = call ptr @march_alloc(i64 32)
  %tgp1024 = getelementptr i8, ptr %hp1023, i64 8
  store i32 0, ptr %tgp1024, align 4
  %ld1025 = load ptr, ptr %req.addr
  %fp1026 = getelementptr i8, ptr %hp1023, i64 16
  store ptr %ld1025, ptr %fp1026, align 8
  %ld1027 = load ptr, ptr %resp.addr
  %fp1028 = getelementptr i8, ptr %hp1023, i64 24
  store ptr %ld1027, ptr %fp1028, align 8
  %$t961.addr = alloca ptr
  store ptr %hp1023, ptr %$t961.addr
  %hp1029 = call ptr @march_alloc(i64 24)
  %tgp1030 = getelementptr i8, ptr %hp1029, i64 8
  store i32 0, ptr %tgp1030, align 4
  %ld1031 = load ptr, ptr %$t961.addr
  %fp1032 = getelementptr i8, ptr %hp1029, i64 16
  store ptr %ld1031, ptr %fp1032, align 8
  store ptr %hp1029, ptr %res_slot1019
  br label %case_merge216
case_br219:
  %fp1033 = getelementptr i8, ptr %ld1018, i64 16
  %fv1034 = load ptr, ptr %fp1033, align 8
  %$f967.addr = alloca ptr
  store ptr %fv1034, ptr %$f967.addr
  %fp1035 = getelementptr i8, ptr %ld1018, i64 24
  %fv1036 = load ptr, ptr %fp1035, align 8
  %$f968.addr = alloca ptr
  store ptr %fv1036, ptr %$f968.addr
  %freed1037 = call i64 @march_decrc_freed(ptr %ld1018)
  %freed_b1038 = icmp ne i64 %freed1037, 0
  br i1 %freed_b1038, label %br_unique220, label %br_shared221
br_shared221:
  call void @march_incrc(ptr %fv1036)
  call void @march_incrc(ptr %fv1034)
  br label %br_body222
br_unique220:
  br label %br_body222
br_body222:
  %ld1039 = load ptr, ptr %$f967.addr
  %res_slot1040 = alloca ptr
  %tgp1041 = getelementptr i8, ptr %ld1039, i64 8
  %tag1042 = load i32, ptr %tgp1041, align 4
  switch i32 %tag1042, label %case_default224 [
      i32 0, label %case_br225
  ]
case_br225:
  %fp1043 = getelementptr i8, ptr %ld1039, i64 16
  %fv1044 = load ptr, ptr %fp1043, align 8
  %$f969.addr = alloca ptr
  store ptr %fv1044, ptr %$f969.addr
  %fp1045 = getelementptr i8, ptr %ld1039, i64 24
  %fv1046 = load ptr, ptr %fp1045, align 8
  %$f970.addr = alloca ptr
  store ptr %fv1046, ptr %$f970.addr
  %freed1047 = call i64 @march_decrc_freed(ptr %ld1039)
  %freed_b1048 = icmp ne i64 %freed1047, 0
  br i1 %freed_b1048, label %br_unique226, label %br_shared227
br_shared227:
  call void @march_incrc(ptr %fv1046)
  call void @march_incrc(ptr %fv1044)
  br label %br_body228
br_unique226:
  br label %br_body228
br_body228:
  %ld1049 = load ptr, ptr %$f968.addr
  %rest.addr = alloca ptr
  store ptr %ld1049, ptr %rest.addr
  %ld1050 = load ptr, ptr %$f970.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1050, ptr %step_fn.addr
  %ld1051 = load ptr, ptr %step_fn.addr
  %fp1052 = getelementptr i8, ptr %ld1051, i64 16
  %fv1053 = load ptr, ptr %fp1052, align 8
  %ld1054 = load ptr, ptr %req.addr
  %ld1055 = load ptr, ptr %resp.addr
  %cr1056 = call ptr (ptr, ptr, ptr) %fv1053(ptr %ld1051, ptr %ld1054, ptr %ld1055)
  %$t962.addr = alloca ptr
  store ptr %cr1056, ptr %$t962.addr
  %ld1057 = load ptr, ptr %$t962.addr
  %res_slot1058 = alloca ptr
  %tgp1059 = getelementptr i8, ptr %ld1057, i64 8
  %tag1060 = load i32, ptr %tgp1059, align 4
  switch i32 %tag1060, label %case_default230 [
      i32 1, label %case_br231
      i32 0, label %case_br232
  ]
case_br231:
  %fp1061 = getelementptr i8, ptr %ld1057, i64 16
  %fv1062 = load ptr, ptr %fp1061, align 8
  %$f963.addr = alloca ptr
  store ptr %fv1062, ptr %$f963.addr
  %ld1063 = load ptr, ptr %$f963.addr
  %e.addr = alloca ptr
  store ptr %ld1063, ptr %e.addr
  %ld1064 = load ptr, ptr %$t962.addr
  %ld1065 = load ptr, ptr %e.addr
  %rc1066 = load i64, ptr %ld1064, align 8
  %uniq1067 = icmp eq i64 %rc1066, 1
  %fbip_slot1068 = alloca ptr
  br i1 %uniq1067, label %fbip_reuse233, label %fbip_fresh234
fbip_reuse233:
  %tgp1069 = getelementptr i8, ptr %ld1064, i64 8
  store i32 1, ptr %tgp1069, align 4
  %fp1070 = getelementptr i8, ptr %ld1064, i64 16
  store ptr %ld1065, ptr %fp1070, align 8
  store ptr %ld1064, ptr %fbip_slot1068
  br label %fbip_merge235
fbip_fresh234:
  call void @march_decrc(ptr %ld1064)
  %hp1071 = call ptr @march_alloc(i64 24)
  %tgp1072 = getelementptr i8, ptr %hp1071, i64 8
  store i32 1, ptr %tgp1072, align 4
  %fp1073 = getelementptr i8, ptr %hp1071, i64 16
  store ptr %ld1065, ptr %fp1073, align 8
  store ptr %hp1071, ptr %fbip_slot1068
  br label %fbip_merge235
fbip_merge235:
  %fbip_r1074 = load ptr, ptr %fbip_slot1068
  store ptr %fbip_r1074, ptr %res_slot1058
  br label %case_merge229
case_br232:
  %fp1075 = getelementptr i8, ptr %ld1057, i64 16
  %fv1076 = load ptr, ptr %fp1075, align 8
  %$f964.addr = alloca ptr
  store ptr %fv1076, ptr %$f964.addr
  %freed1077 = call i64 @march_decrc_freed(ptr %ld1057)
  %freed_b1078 = icmp ne i64 %freed1077, 0
  br i1 %freed_b1078, label %br_unique236, label %br_shared237
br_shared237:
  call void @march_incrc(ptr %fv1076)
  br label %br_body238
br_unique236:
  br label %br_body238
br_body238:
  %ld1079 = load ptr, ptr %$f964.addr
  %res_slot1080 = alloca ptr
  %tgp1081 = getelementptr i8, ptr %ld1079, i64 8
  %tag1082 = load i32, ptr %tgp1081, align 4
  switch i32 %tag1082, label %case_default240 [
      i32 0, label %case_br241
  ]
case_br241:
  %fp1083 = getelementptr i8, ptr %ld1079, i64 16
  %fv1084 = load ptr, ptr %fp1083, align 8
  %$f965.addr = alloca ptr
  store ptr %fv1084, ptr %$f965.addr
  %fp1085 = getelementptr i8, ptr %ld1079, i64 24
  %fv1086 = load ptr, ptr %fp1085, align 8
  %$f966.addr = alloca ptr
  store ptr %fv1086, ptr %$f966.addr
  %freed1087 = call i64 @march_decrc_freed(ptr %ld1079)
  %freed_b1088 = icmp ne i64 %freed1087, 0
  br i1 %freed_b1088, label %br_unique242, label %br_shared243
br_shared243:
  call void @march_incrc(ptr %fv1086)
  call void @march_incrc(ptr %fv1084)
  br label %br_body244
br_unique242:
  br label %br_body244
br_body244:
  %ld1089 = load ptr, ptr %$f966.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1089, ptr %new_resp.addr
  %ld1090 = load ptr, ptr %$f965.addr
  %new_req.addr = alloca ptr
  store ptr %ld1090, ptr %new_req.addr
  %ld1091 = load ptr, ptr %rest.addr
  %ld1092 = load ptr, ptr %new_req.addr
  %ld1093 = load ptr, ptr %new_resp.addr
  %cr1094 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3336(ptr %ld1091, ptr %ld1092, ptr %ld1093)
  store ptr %cr1094, ptr %res_slot1080
  br label %case_merge239
case_default240:
  unreachable
case_merge239:
  %case_r1095 = load ptr, ptr %res_slot1080
  store ptr %case_r1095, ptr %res_slot1058
  br label %case_merge229
case_default230:
  unreachable
case_merge229:
  %case_r1096 = load ptr, ptr %res_slot1058
  store ptr %case_r1096, ptr %res_slot1040
  br label %case_merge223
case_default224:
  unreachable
case_merge223:
  %case_r1097 = load ptr, ptr %res_slot1040
  store ptr %case_r1097, ptr %res_slot1019
  br label %case_merge216
case_default217:
  unreachable
case_merge216:
  %case_r1098 = load ptr, ptr %res_slot1019
  ret ptr %case_r1098
}

define ptr @HttpClient.handle_redirects$Request_String$Response_V__3336$Int$Int(ptr %req.arg, ptr %resp.arg, i64 %max.arg, i64 %count.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %max.addr = alloca i64
  store i64 %max.arg, ptr %max.addr
  %count.addr = alloca i64
  store i64 %count.arg, ptr %count.addr
  %ld1099 = load i64, ptr %max.addr
  %cmp1100 = icmp eq i64 %ld1099, 0
  %ar1101 = zext i1 %cmp1100 to i64
  %$t994.addr = alloca i64
  store i64 %ar1101, ptr %$t994.addr
  %ld1102 = load i64, ptr %$t994.addr
  %res_slot1103 = alloca ptr
  %bi1104 = trunc i64 %ld1102 to i1
  br i1 %bi1104, label %case_br247, label %case_default246
case_br247:
  %hp1105 = call ptr @march_alloc(i64 24)
  %tgp1106 = getelementptr i8, ptr %hp1105, i64 8
  store i32 0, ptr %tgp1106, align 4
  %ld1107 = load ptr, ptr %resp.addr
  %fp1108 = getelementptr i8, ptr %hp1105, i64 16
  store ptr %ld1107, ptr %fp1108, align 8
  store ptr %hp1105, ptr %res_slot1103
  br label %case_merge245
case_default246:
  %ld1109 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1109)
  %ld1110 = load ptr, ptr %resp.addr
  %cr1111 = call i64 @Http.response_is_redirect$Response_V__3336(ptr %ld1110)
  %$t995.addr = alloca i64
  store i64 %cr1111, ptr %$t995.addr
  %ld1112 = load i64, ptr %$t995.addr
  %ar1113 = xor i64 %ld1112, 1
  %$t996.addr = alloca i64
  store i64 %ar1113, ptr %$t996.addr
  %ld1114 = load i64, ptr %$t996.addr
  %res_slot1115 = alloca ptr
  %bi1116 = trunc i64 %ld1114 to i1
  br i1 %bi1116, label %case_br250, label %case_default249
case_br250:
  %hp1117 = call ptr @march_alloc(i64 24)
  %tgp1118 = getelementptr i8, ptr %hp1117, i64 8
  store i32 0, ptr %tgp1118, align 4
  %ld1119 = load ptr, ptr %resp.addr
  %fp1120 = getelementptr i8, ptr %hp1117, i64 16
  store ptr %ld1119, ptr %fp1120, align 8
  store ptr %hp1117, ptr %res_slot1115
  br label %case_merge248
case_default249:
  %ld1121 = load i64, ptr %count.addr
  %ld1122 = load i64, ptr %max.addr
  %cmp1123 = icmp sge i64 %ld1121, %ld1122
  %ar1124 = zext i1 %cmp1123 to i64
  %$t997.addr = alloca i64
  store i64 %ar1124, ptr %$t997.addr
  %ld1125 = load i64, ptr %$t997.addr
  %res_slot1126 = alloca ptr
  %bi1127 = trunc i64 %ld1125 to i1
  br i1 %bi1127, label %case_br253, label %case_default252
case_br253:
  %hp1128 = call ptr @march_alloc(i64 24)
  %tgp1129 = getelementptr i8, ptr %hp1128, i64 8
  store i32 2, ptr %tgp1129, align 4
  %ld1130 = load i64, ptr %count.addr
  %fp1131 = getelementptr i8, ptr %hp1128, i64 16
  store i64 %ld1130, ptr %fp1131, align 8
  %$t998.addr = alloca ptr
  store ptr %hp1128, ptr %$t998.addr
  %hp1132 = call ptr @march_alloc(i64 24)
  %tgp1133 = getelementptr i8, ptr %hp1132, i64 8
  store i32 1, ptr %tgp1133, align 4
  %ld1134 = load ptr, ptr %$t998.addr
  %fp1135 = getelementptr i8, ptr %hp1132, i64 16
  store ptr %ld1134, ptr %fp1135, align 8
  store ptr %hp1132, ptr %res_slot1126
  br label %case_merge251
case_default252:
  %ld1136 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1136)
  %ld1137 = load ptr, ptr %resp.addr
  %sl1138 = call ptr @march_string_lit(ptr @.str29, i64 8)
  %cr1139 = call ptr @Http.get_header$Response_V__3336$String(ptr %ld1137, ptr %sl1138)
  %$t999.addr = alloca ptr
  store ptr %cr1139, ptr %$t999.addr
  %ld1140 = load ptr, ptr %$t999.addr
  %res_slot1141 = alloca ptr
  %tgp1142 = getelementptr i8, ptr %ld1140, i64 8
  %tag1143 = load i32, ptr %tgp1142, align 4
  switch i32 %tag1143, label %case_default255 [
      i32 0, label %case_br256
      i32 1, label %case_br257
  ]
case_br256:
  %ld1144 = load ptr, ptr %$t999.addr
  call void @march_decrc(ptr %ld1144)
  %hp1145 = call ptr @march_alloc(i64 24)
  %tgp1146 = getelementptr i8, ptr %hp1145, i64 8
  store i32 0, ptr %tgp1146, align 4
  %ld1147 = load ptr, ptr %resp.addr
  %fp1148 = getelementptr i8, ptr %hp1145, i64 16
  store ptr %ld1147, ptr %fp1148, align 8
  store ptr %hp1145, ptr %res_slot1141
  br label %case_merge254
case_br257:
  %fp1149 = getelementptr i8, ptr %ld1140, i64 16
  %fv1150 = load ptr, ptr %fp1149, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv1150, ptr %$f1018.addr
  %freed1151 = call i64 @march_decrc_freed(ptr %ld1140)
  %freed_b1152 = icmp ne i64 %freed1151, 0
  br i1 %freed_b1152, label %br_unique258, label %br_shared259
br_shared259:
  call void @march_incrc(ptr %fv1150)
  br label %br_body260
br_unique258:
  br label %br_body260
br_body260:
  %ld1153 = load ptr, ptr %$f1018.addr
  %location.addr = alloca ptr
  store ptr %ld1153, ptr %location.addr
  %ld1154 = load ptr, ptr %location.addr
  call void @march_incrc(ptr %ld1154)
  %ld1155 = load ptr, ptr %location.addr
  %cr1156 = call ptr @Http.parse_url(ptr %ld1155)
  %$t1000.addr = alloca ptr
  store ptr %cr1156, ptr %$t1000.addr
  %ld1157 = load ptr, ptr %$t1000.addr
  %res_slot1158 = alloca ptr
  %tgp1159 = getelementptr i8, ptr %ld1157, i64 8
  %tag1160 = load i32, ptr %tgp1159, align 4
  switch i32 %tag1160, label %case_default262 [
      i32 0, label %case_br263
      i32 1, label %case_br264
  ]
case_br263:
  %fp1161 = getelementptr i8, ptr %ld1157, i64 16
  %fv1162 = load ptr, ptr %fp1161, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv1162, ptr %$f1011.addr
  %freed1163 = call i64 @march_decrc_freed(ptr %ld1157)
  %freed_b1164 = icmp ne i64 %freed1163, 0
  br i1 %freed_b1164, label %br_unique265, label %br_shared266
br_shared266:
  call void @march_incrc(ptr %fv1162)
  br label %br_body267
br_unique265:
  br label %br_body267
br_body267:
  %ld1165 = load ptr, ptr %$f1011.addr
  %parsed.addr = alloca ptr
  store ptr %ld1165, ptr %parsed.addr
  %hp1166 = call ptr @march_alloc(i64 16)
  %tgp1167 = getelementptr i8, ptr %hp1166, i64 8
  store i32 0, ptr %tgp1167, align 4
  %$t1001.addr = alloca ptr
  store ptr %hp1166, ptr %$t1001.addr
  %ld1168 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1168)
  %ld1169 = load ptr, ptr %parsed.addr
  %cr1170 = call ptr @Http.scheme$Request_T_(ptr %ld1169)
  %$t1002.addr = alloca ptr
  store ptr %cr1170, ptr %$t1002.addr
  %ld1171 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1171)
  %ld1172 = load ptr, ptr %parsed.addr
  %cr1173 = call ptr @Http.host$Request_T_(ptr %ld1172)
  %$t1003.addr = alloca ptr
  store ptr %cr1173, ptr %$t1003.addr
  %ld1174 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1174)
  %ld1175 = load ptr, ptr %parsed.addr
  %cr1176 = call ptr @Http.port$Request_T_(ptr %ld1175)
  %$t1004.addr = alloca ptr
  store ptr %cr1176, ptr %$t1004.addr
  %ld1177 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1177)
  %ld1178 = load ptr, ptr %parsed.addr
  %cr1179 = call ptr @Http.path$Request_T_(ptr %ld1178)
  %$t1005.addr = alloca ptr
  store ptr %cr1179, ptr %$t1005.addr
  %ld1180 = load ptr, ptr %parsed.addr
  %cr1181 = call ptr @Http.query$Request_T_(ptr %ld1180)
  %$t1006.addr = alloca ptr
  store ptr %cr1181, ptr %$t1006.addr
  %ld1182 = load ptr, ptr %req.addr
  %cr1183 = call ptr @Http.headers$Request_String(ptr %ld1182)
  %$t1007.addr = alloca ptr
  store ptr %cr1183, ptr %$t1007.addr
  %hp1184 = call ptr @march_alloc(i64 80)
  %tgp1185 = getelementptr i8, ptr %hp1184, i64 8
  store i32 0, ptr %tgp1185, align 4
  %ld1186 = load ptr, ptr %$t1001.addr
  %fp1187 = getelementptr i8, ptr %hp1184, i64 16
  store ptr %ld1186, ptr %fp1187, align 8
  %ld1188 = load ptr, ptr %$t1002.addr
  %fp1189 = getelementptr i8, ptr %hp1184, i64 24
  store ptr %ld1188, ptr %fp1189, align 8
  %ld1190 = load ptr, ptr %$t1003.addr
  %fp1191 = getelementptr i8, ptr %hp1184, i64 32
  store ptr %ld1190, ptr %fp1191, align 8
  %ld1192 = load ptr, ptr %$t1004.addr
  %fp1193 = getelementptr i8, ptr %hp1184, i64 40
  store ptr %ld1192, ptr %fp1193, align 8
  %ld1194 = load ptr, ptr %$t1005.addr
  %fp1195 = getelementptr i8, ptr %hp1184, i64 48
  store ptr %ld1194, ptr %fp1195, align 8
  %ld1196 = load ptr, ptr %$t1006.addr
  %fp1197 = getelementptr i8, ptr %hp1184, i64 56
  store ptr %ld1196, ptr %fp1197, align 8
  %ld1198 = load ptr, ptr %$t1007.addr
  %fp1199 = getelementptr i8, ptr %hp1184, i64 64
  store ptr %ld1198, ptr %fp1199, align 8
  %sl1200 = call ptr @march_string_lit(ptr @.str30, i64 0)
  %fp1201 = getelementptr i8, ptr %hp1184, i64 72
  store ptr %sl1200, ptr %fp1201, align 8
  store ptr %hp1184, ptr %res_slot1158
  br label %case_merge261
case_br264:
  %fp1202 = getelementptr i8, ptr %ld1157, i64 16
  %fv1203 = load ptr, ptr %fp1202, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv1203, ptr %$f1012.addr
  %freed1204 = call i64 @march_decrc_freed(ptr %ld1157)
  %freed_b1205 = icmp ne i64 %freed1204, 0
  br i1 %freed_b1205, label %br_unique268, label %br_shared269
br_shared269:
  call void @march_incrc(ptr %fv1203)
  br label %br_body270
br_unique268:
  br label %br_body270
br_body270:
  %ld1206 = load ptr, ptr %req.addr
  %ld1207 = load ptr, ptr %location.addr
  %cr1208 = call ptr @Http.set_path$Request_String$String(ptr %ld1206, ptr %ld1207)
  %$t1008.addr = alloca ptr
  store ptr %cr1208, ptr %$t1008.addr
  %hp1209 = call ptr @march_alloc(i64 16)
  %tgp1210 = getelementptr i8, ptr %hp1209, i64 8
  store i32 0, ptr %tgp1210, align 4
  %$t1009.addr = alloca ptr
  store ptr %hp1209, ptr %$t1009.addr
  %ld1211 = load ptr, ptr %$t1008.addr
  %ld1212 = load ptr, ptr %$t1009.addr
  %cr1213 = call ptr @Http.set_method$Request_String$Method(ptr %ld1211, ptr %ld1212)
  %$t1010.addr = alloca ptr
  store ptr %cr1213, ptr %$t1010.addr
  %ld1214 = load ptr, ptr %$t1010.addr
  %sl1215 = call ptr @march_string_lit(ptr @.str31, i64 0)
  %cr1216 = call ptr @Http.set_body$Request_String$String(ptr %ld1214, ptr %sl1215)
  store ptr %cr1216, ptr %res_slot1158
  br label %case_merge261
case_default262:
  unreachable
case_merge261:
  %case_r1217 = load ptr, ptr %res_slot1158
  %redirect_req.addr = alloca ptr
  store ptr %case_r1217, ptr %redirect_req.addr
  %ld1218 = load ptr, ptr %redirect_req.addr
  call void @march_incrc(ptr %ld1218)
  %ld1219 = load ptr, ptr %redirect_req.addr
  %cr1220 = call ptr @HttpTransport.request$Request_String(ptr %ld1219)
  %$t1013.addr = alloca ptr
  store ptr %cr1220, ptr %$t1013.addr
  %ld1221 = load ptr, ptr %$t1013.addr
  %res_slot1222 = alloca ptr
  %tgp1223 = getelementptr i8, ptr %ld1221, i64 8
  %tag1224 = load i32, ptr %tgp1223, align 4
  switch i32 %tag1224, label %case_default272 [
      i32 1, label %case_br273
      i32 0, label %case_br274
  ]
case_br273:
  %fp1225 = getelementptr i8, ptr %ld1221, i64 16
  %fv1226 = load ptr, ptr %fp1225, align 8
  %$f1016.addr = alloca ptr
  store ptr %fv1226, ptr %$f1016.addr
  %ld1227 = load ptr, ptr %$f1016.addr
  %e.addr = alloca ptr
  store ptr %ld1227, ptr %e.addr
  %hp1228 = call ptr @march_alloc(i64 24)
  %tgp1229 = getelementptr i8, ptr %hp1228, i64 8
  store i32 0, ptr %tgp1229, align 4
  %ld1230 = load ptr, ptr %e.addr
  %fp1231 = getelementptr i8, ptr %hp1228, i64 16
  store ptr %ld1230, ptr %fp1231, align 8
  %$t1014.addr = alloca ptr
  store ptr %hp1228, ptr %$t1014.addr
  %ld1232 = load ptr, ptr %$t1013.addr
  %ld1233 = load ptr, ptr %$t1014.addr
  %rc1234 = load i64, ptr %ld1232, align 8
  %uniq1235 = icmp eq i64 %rc1234, 1
  %fbip_slot1236 = alloca ptr
  br i1 %uniq1235, label %fbip_reuse275, label %fbip_fresh276
fbip_reuse275:
  %tgp1237 = getelementptr i8, ptr %ld1232, i64 8
  store i32 1, ptr %tgp1237, align 4
  %fp1238 = getelementptr i8, ptr %ld1232, i64 16
  store ptr %ld1233, ptr %fp1238, align 8
  store ptr %ld1232, ptr %fbip_slot1236
  br label %fbip_merge277
fbip_fresh276:
  call void @march_decrc(ptr %ld1232)
  %hp1239 = call ptr @march_alloc(i64 24)
  %tgp1240 = getelementptr i8, ptr %hp1239, i64 8
  store i32 1, ptr %tgp1240, align 4
  %fp1241 = getelementptr i8, ptr %hp1239, i64 16
  store ptr %ld1233, ptr %fp1241, align 8
  store ptr %hp1239, ptr %fbip_slot1236
  br label %fbip_merge277
fbip_merge277:
  %fbip_r1242 = load ptr, ptr %fbip_slot1236
  store ptr %fbip_r1242, ptr %res_slot1222
  br label %case_merge271
case_br274:
  %fp1243 = getelementptr i8, ptr %ld1221, i64 16
  %fv1244 = load ptr, ptr %fp1243, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv1244, ptr %$f1017.addr
  %freed1245 = call i64 @march_decrc_freed(ptr %ld1221)
  %freed_b1246 = icmp ne i64 %freed1245, 0
  br i1 %freed_b1246, label %br_unique278, label %br_shared279
br_shared279:
  call void @march_incrc(ptr %fv1244)
  br label %br_body280
br_unique278:
  br label %br_body280
br_body280:
  %ld1247 = load ptr, ptr %$f1017.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1247, ptr %new_resp.addr
  %ld1248 = load i64, ptr %count.addr
  %ar1249 = add i64 %ld1248, 1
  %$t1015.addr = alloca i64
  store i64 %ar1249, ptr %$t1015.addr
  %ld1250 = load ptr, ptr %redirect_req.addr
  %ld1251 = load ptr, ptr %new_resp.addr
  %ld1252 = load i64, ptr %max.addr
  %ld1253 = load i64, ptr %$t1015.addr
  %cr1254 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3336$Int$Int(ptr %ld1250, ptr %ld1251, i64 %ld1252, i64 %ld1253)
  store ptr %cr1254, ptr %res_slot1222
  br label %case_merge271
case_default272:
  unreachable
case_merge271:
  %case_r1255 = load ptr, ptr %res_slot1222
  store ptr %case_r1255, ptr %res_slot1141
  br label %case_merge254
case_default255:
  unreachable
case_merge254:
  %case_r1256 = load ptr, ptr %res_slot1141
  store ptr %case_r1256, ptr %res_slot1126
  br label %case_merge251
case_merge251:
  %case_r1257 = load ptr, ptr %res_slot1126
  store ptr %case_r1257, ptr %res_slot1115
  br label %case_merge248
case_merge248:
  %case_r1258 = load ptr, ptr %res_slot1115
  store ptr %case_r1258, ptr %res_slot1103
  br label %case_merge245
case_merge245:
  %case_r1259 = load ptr, ptr %res_slot1103
  ret ptr %case_r1259
}

define ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %req.arg, i64 %retries_left.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld1260 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1260)
  %ld1261 = load ptr, ptr %req.addr
  %cr1262 = call ptr @HttpTransport.request$Request_String(ptr %ld1261)
  %$t978.addr = alloca ptr
  store ptr %cr1262, ptr %$t978.addr
  %ld1263 = load ptr, ptr %$t978.addr
  %res_slot1264 = alloca ptr
  %tgp1265 = getelementptr i8, ptr %ld1263, i64 8
  %tag1266 = load i32, ptr %tgp1265, align 4
  switch i32 %tag1266, label %case_default282 [
      i32 0, label %case_br283
      i32 1, label %case_br284
  ]
case_br283:
  %fp1267 = getelementptr i8, ptr %ld1263, i64 16
  %fv1268 = load ptr, ptr %fp1267, align 8
  %$f981.addr = alloca ptr
  store ptr %fv1268, ptr %$f981.addr
  %ld1269 = load ptr, ptr %$f981.addr
  %resp.addr = alloca ptr
  store ptr %ld1269, ptr %resp.addr
  %ld1270 = load ptr, ptr %$t978.addr
  %ld1271 = load ptr, ptr %resp.addr
  %rc1272 = load i64, ptr %ld1270, align 8
  %uniq1273 = icmp eq i64 %rc1272, 1
  %fbip_slot1274 = alloca ptr
  br i1 %uniq1273, label %fbip_reuse285, label %fbip_fresh286
fbip_reuse285:
  %tgp1275 = getelementptr i8, ptr %ld1270, i64 8
  store i32 0, ptr %tgp1275, align 4
  %fp1276 = getelementptr i8, ptr %ld1270, i64 16
  store ptr %ld1271, ptr %fp1276, align 8
  store ptr %ld1270, ptr %fbip_slot1274
  br label %fbip_merge287
fbip_fresh286:
  call void @march_decrc(ptr %ld1270)
  %hp1277 = call ptr @march_alloc(i64 24)
  %tgp1278 = getelementptr i8, ptr %hp1277, i64 8
  store i32 0, ptr %tgp1278, align 4
  %fp1279 = getelementptr i8, ptr %hp1277, i64 16
  store ptr %ld1271, ptr %fp1279, align 8
  store ptr %hp1277, ptr %fbip_slot1274
  br label %fbip_merge287
fbip_merge287:
  %fbip_r1280 = load ptr, ptr %fbip_slot1274
  store ptr %fbip_r1280, ptr %res_slot1264
  br label %case_merge281
case_br284:
  %fp1281 = getelementptr i8, ptr %ld1263, i64 16
  %fv1282 = load ptr, ptr %fp1281, align 8
  %$f982.addr = alloca ptr
  store ptr %fv1282, ptr %$f982.addr
  %freed1283 = call i64 @march_decrc_freed(ptr %ld1263)
  %freed_b1284 = icmp ne i64 %freed1283, 0
  br i1 %freed_b1284, label %br_unique288, label %br_shared289
br_shared289:
  call void @march_incrc(ptr %fv1282)
  br label %br_body290
br_unique288:
  br label %br_body290
br_body290:
  %ld1285 = load ptr, ptr %$f982.addr
  %e.addr = alloca ptr
  store ptr %ld1285, ptr %e.addr
  %ld1286 = load i64, ptr %retries_left.addr
  %cmp1287 = icmp sgt i64 %ld1286, 0
  %ar1288 = zext i1 %cmp1287 to i64
  %$t979.addr = alloca i64
  store i64 %ar1288, ptr %$t979.addr
  %ld1289 = load i64, ptr %$t979.addr
  %res_slot1290 = alloca ptr
  %bi1291 = trunc i64 %ld1289 to i1
  br i1 %bi1291, label %case_br293, label %case_default292
case_br293:
  %ld1292 = load i64, ptr %retries_left.addr
  %ar1293 = sub i64 %ld1292, 1
  %$t980.addr = alloca i64
  store i64 %ar1293, ptr %$t980.addr
  %ld1294 = load ptr, ptr %req.addr
  %ld1295 = load i64, ptr %$t980.addr
  %cr1296 = call ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %ld1294, i64 %ld1295)
  store ptr %cr1296, ptr %res_slot1290
  br label %case_merge291
case_default292:
  %hp1297 = call ptr @march_alloc(i64 24)
  %tgp1298 = getelementptr i8, ptr %hp1297, i64 8
  store i32 1, ptr %tgp1298, align 4
  %ld1299 = load ptr, ptr %e.addr
  %fp1300 = getelementptr i8, ptr %hp1297, i64 16
  store ptr %ld1299, ptr %fp1300, align 8
  store ptr %hp1297, ptr %res_slot1290
  br label %case_merge291
case_merge291:
  %case_r1301 = load ptr, ptr %res_slot1290
  store ptr %case_r1301, ptr %res_slot1264
  br label %case_merge281
case_default282:
  unreachable
case_merge281:
  %case_r1302 = load ptr, ptr %res_slot1264
  ret ptr %case_r1302
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1303 = load ptr, ptr %steps.addr
  %res_slot1304 = alloca ptr
  %tgp1305 = getelementptr i8, ptr %ld1303, i64 8
  %tag1306 = load i32, ptr %tgp1305, align 4
  switch i32 %tag1306, label %case_default295 [
      i32 0, label %case_br296
      i32 1, label %case_br297
  ]
case_br296:
  %ld1307 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1307)
  %hp1308 = call ptr @march_alloc(i64 24)
  %tgp1309 = getelementptr i8, ptr %hp1308, i64 8
  store i32 0, ptr %tgp1309, align 4
  %ld1310 = load ptr, ptr %req.addr
  %fp1311 = getelementptr i8, ptr %hp1308, i64 16
  store ptr %ld1310, ptr %fp1311, align 8
  store ptr %hp1308, ptr %res_slot1304
  br label %case_merge294
case_br297:
  %fp1312 = getelementptr i8, ptr %ld1303, i64 16
  %fv1313 = load ptr, ptr %fp1312, align 8
  %$f957.addr = alloca ptr
  store ptr %fv1313, ptr %$f957.addr
  %fp1314 = getelementptr i8, ptr %ld1303, i64 24
  %fv1315 = load ptr, ptr %fp1314, align 8
  %$f958.addr = alloca ptr
  store ptr %fv1315, ptr %$f958.addr
  %freed1316 = call i64 @march_decrc_freed(ptr %ld1303)
  %freed_b1317 = icmp ne i64 %freed1316, 0
  br i1 %freed_b1317, label %br_unique298, label %br_shared299
br_shared299:
  call void @march_incrc(ptr %fv1315)
  call void @march_incrc(ptr %fv1313)
  br label %br_body300
br_unique298:
  br label %br_body300
br_body300:
  %ld1318 = load ptr, ptr %$f957.addr
  %res_slot1319 = alloca ptr
  %tgp1320 = getelementptr i8, ptr %ld1318, i64 8
  %tag1321 = load i32, ptr %tgp1320, align 4
  switch i32 %tag1321, label %case_default302 [
      i32 0, label %case_br303
  ]
case_br303:
  %fp1322 = getelementptr i8, ptr %ld1318, i64 16
  %fv1323 = load ptr, ptr %fp1322, align 8
  %$f959.addr = alloca ptr
  store ptr %fv1323, ptr %$f959.addr
  %fp1324 = getelementptr i8, ptr %ld1318, i64 24
  %fv1325 = load ptr, ptr %fp1324, align 8
  %$f960.addr = alloca ptr
  store ptr %fv1325, ptr %$f960.addr
  %freed1326 = call i64 @march_decrc_freed(ptr %ld1318)
  %freed_b1327 = icmp ne i64 %freed1326, 0
  br i1 %freed_b1327, label %br_unique304, label %br_shared305
br_shared305:
  call void @march_incrc(ptr %fv1325)
  call void @march_incrc(ptr %fv1323)
  br label %br_body306
br_unique304:
  br label %br_body306
br_body306:
  %ld1328 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld1328, ptr %rest.addr
  %ld1329 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1329, ptr %step_fn.addr
  %ld1330 = load ptr, ptr %step_fn.addr
  %fp1331 = getelementptr i8, ptr %ld1330, i64 16
  %fv1332 = load ptr, ptr %fp1331, align 8
  %ld1333 = load ptr, ptr %req.addr
  %cr1334 = call ptr (ptr, ptr) %fv1332(ptr %ld1330, ptr %ld1333)
  %$t954.addr = alloca ptr
  store ptr %cr1334, ptr %$t954.addr
  %ld1335 = load ptr, ptr %$t954.addr
  %res_slot1336 = alloca ptr
  %tgp1337 = getelementptr i8, ptr %ld1335, i64 8
  %tag1338 = load i32, ptr %tgp1337, align 4
  switch i32 %tag1338, label %case_default308 [
      i32 1, label %case_br309
      i32 0, label %case_br310
  ]
case_br309:
  %fp1339 = getelementptr i8, ptr %ld1335, i64 16
  %fv1340 = load ptr, ptr %fp1339, align 8
  %$f955.addr = alloca ptr
  store ptr %fv1340, ptr %$f955.addr
  %ld1341 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld1341, ptr %e.addr
  %ld1342 = load ptr, ptr %$t954.addr
  %ld1343 = load ptr, ptr %e.addr
  %rc1344 = load i64, ptr %ld1342, align 8
  %uniq1345 = icmp eq i64 %rc1344, 1
  %fbip_slot1346 = alloca ptr
  br i1 %uniq1345, label %fbip_reuse311, label %fbip_fresh312
fbip_reuse311:
  %tgp1347 = getelementptr i8, ptr %ld1342, i64 8
  store i32 1, ptr %tgp1347, align 4
  %fp1348 = getelementptr i8, ptr %ld1342, i64 16
  store ptr %ld1343, ptr %fp1348, align 8
  store ptr %ld1342, ptr %fbip_slot1346
  br label %fbip_merge313
fbip_fresh312:
  call void @march_decrc(ptr %ld1342)
  %hp1349 = call ptr @march_alloc(i64 24)
  %tgp1350 = getelementptr i8, ptr %hp1349, i64 8
  store i32 1, ptr %tgp1350, align 4
  %fp1351 = getelementptr i8, ptr %hp1349, i64 16
  store ptr %ld1343, ptr %fp1351, align 8
  store ptr %hp1349, ptr %fbip_slot1346
  br label %fbip_merge313
fbip_merge313:
  %fbip_r1352 = load ptr, ptr %fbip_slot1346
  store ptr %fbip_r1352, ptr %res_slot1336
  br label %case_merge307
case_br310:
  %fp1353 = getelementptr i8, ptr %ld1335, i64 16
  %fv1354 = load ptr, ptr %fp1353, align 8
  %$f956.addr = alloca ptr
  store ptr %fv1354, ptr %$f956.addr
  %freed1355 = call i64 @march_decrc_freed(ptr %ld1335)
  %freed_b1356 = icmp ne i64 %freed1355, 0
  br i1 %freed_b1356, label %br_unique314, label %br_shared315
br_shared315:
  call void @march_incrc(ptr %fv1354)
  br label %br_body316
br_unique314:
  br label %br_body316
br_body316:
  %ld1357 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld1357, ptr %new_req.addr
  %ld1358 = load ptr, ptr %rest.addr
  %ld1359 = load ptr, ptr %new_req.addr
  %cr1360 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld1358, ptr %ld1359)
  store ptr %cr1360, ptr %res_slot1336
  br label %case_merge307
case_default308:
  unreachable
case_merge307:
  %case_r1361 = load ptr, ptr %res_slot1336
  store ptr %case_r1361, ptr %res_slot1319
  br label %case_merge301
case_default302:
  unreachable
case_merge301:
  %case_r1362 = load ptr, ptr %res_slot1319
  store ptr %case_r1362, ptr %res_slot1304
  br label %case_merge294
case_default295:
  unreachable
case_merge294:
  %case_r1363 = load ptr, ptr %res_slot1304
  ret ptr %case_r1363
}

define ptr @HttpTransport.request$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1364 = load ptr, ptr %req.addr
  %sl1365 = call ptr @march_string_lit(ptr @.str32, i64 10)
  %sl1366 = call ptr @march_string_lit(ptr @.str33, i64 5)
  %cr1367 = call ptr @Http.set_header$Request_String$String$String(ptr %ld1364, ptr %sl1365, ptr %sl1366)
  %req_1.addr = alloca ptr
  store ptr %cr1367, ptr %req_1.addr
  %ld1368 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1368)
  %ld1369 = load ptr, ptr %req_1.addr
  %cr1370 = call ptr @Http.host$Request_V__2815(ptr %ld1369)
  %req_host.addr = alloca ptr
  store ptr %cr1370, ptr %req_host.addr
  %ld1371 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1371)
  %ld1372 = load ptr, ptr %req_1.addr
  %cr1373 = call ptr @Http.port$Request_V__2818(ptr %ld1372)
  %$t837.addr = alloca ptr
  store ptr %cr1373, ptr %$t837.addr
  %ld1374 = load ptr, ptr %$t837.addr
  %res_slot1375 = alloca ptr
  %tgp1376 = getelementptr i8, ptr %ld1374, i64 8
  %tag1377 = load i32, ptr %tgp1376, align 4
  switch i32 %tag1377, label %case_default318 [
      i32 1, label %case_br319
      i32 0, label %case_br320
  ]
case_br319:
  %fp1378 = getelementptr i8, ptr %ld1374, i64 16
  %fv1379 = load ptr, ptr %fp1378, align 8
  %$f838.addr = alloca ptr
  store ptr %fv1379, ptr %$f838.addr
  %ld1380 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld1380)
  %ld1381 = load ptr, ptr %$f838.addr
  %p.addr = alloca ptr
  store ptr %ld1381, ptr %p.addr
  %ld1382 = load ptr, ptr %p.addr
  store ptr %ld1382, ptr %res_slot1375
  br label %case_merge317
case_br320:
  %ld1383 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld1383)
  %cv1384 = inttoptr i64 80 to ptr
  store ptr %cv1384, ptr %res_slot1375
  br label %case_merge317
case_default318:
  unreachable
case_merge317:
  %case_r1385 = load ptr, ptr %res_slot1375
  %cv1386 = ptrtoint ptr %case_r1385 to i64
  %req_port.addr = alloca i64
  store i64 %cv1386, ptr %req_port.addr
  %ld1387 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1387)
  %ld1388 = load ptr, ptr %req_1.addr
  %cr1389 = call ptr @Http.method$Request_V__2825(ptr %ld1388)
  %$t839.addr = alloca ptr
  store ptr %cr1389, ptr %$t839.addr
  %ld1390 = load ptr, ptr %$t839.addr
  %cr1391 = call ptr @Http.method_to_string(ptr %ld1390)
  %$t840.addr = alloca ptr
  store ptr %cr1391, ptr %$t840.addr
  %ld1392 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1392)
  %ld1393 = load ptr, ptr %req_1.addr
  %cr1394 = call ptr @Http.path$Request_V__2827(ptr %ld1393)
  %$t841.addr = alloca ptr
  store ptr %cr1394, ptr %$t841.addr
  %ld1395 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1395)
  %ld1396 = load ptr, ptr %req_1.addr
  %cr1397 = call ptr @Http.query$Request_V__2829(ptr %ld1396)
  %$t842.addr = alloca ptr
  store ptr %cr1397, ptr %$t842.addr
  %ld1398 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1398)
  %ld1399 = load ptr, ptr %req_1.addr
  %cr1400 = call ptr @Http.headers$Request_V__2831(ptr %ld1399)
  %$t843.addr = alloca ptr
  store ptr %cr1400, ptr %$t843.addr
  %ld1401 = load ptr, ptr %req_1.addr
  %cr1402 = call ptr @Http.body$Request_V__2833(ptr %ld1401)
  %$t844.addr = alloca ptr
  store ptr %cr1402, ptr %$t844.addr
  %ld1403 = load ptr, ptr %req_host.addr
  call void @march_incrc(ptr %ld1403)
  %ld1404 = load ptr, ptr %http_serialize_request.addr
  %fp1405 = getelementptr i8, ptr %ld1404, i64 16
  %fv1406 = load ptr, ptr %fp1405, align 8
  %ld1407 = load ptr, ptr %$t840.addr
  %ld1408 = load ptr, ptr %req_host.addr
  %ld1409 = load ptr, ptr %$t841.addr
  %ld1410 = load ptr, ptr %$t842.addr
  %ld1411 = load ptr, ptr %$t843.addr
  %ld1412 = load ptr, ptr %$t844.addr
  %cr1413 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv1406(ptr %ld1404, ptr %ld1407, ptr %ld1408, ptr %ld1409, ptr %ld1410, ptr %ld1411, ptr %ld1412)
  %raw_request.addr = alloca ptr
  store ptr %cr1413, ptr %raw_request.addr
  %ld1414 = load ptr, ptr %tcp_connect.addr
  %fp1415 = getelementptr i8, ptr %ld1414, i64 16
  %fv1416 = load ptr, ptr %fp1415, align 8
  %ld1417 = load ptr, ptr %req_host.addr
  %ld1418 = load i64, ptr %req_port.addr
  %cv1419 = inttoptr i64 %ld1418 to ptr
  %cr1420 = call ptr (ptr, ptr, ptr) %fv1416(ptr %ld1414, ptr %ld1417, ptr %cv1419)
  %$t845.addr = alloca ptr
  store ptr %cr1420, ptr %$t845.addr
  %ld1421 = load ptr, ptr %$t845.addr
  %res_slot1422 = alloca ptr
  %tgp1423 = getelementptr i8, ptr %ld1421, i64 8
  %tag1424 = load i32, ptr %tgp1423, align 4
  switch i32 %tag1424, label %case_default322 [
      i32 0, label %case_br323
      i32 0, label %case_br324
  ]
case_br323:
  %fp1425 = getelementptr i8, ptr %ld1421, i64 16
  %fv1426 = load ptr, ptr %fp1425, align 8
  %$f864.addr = alloca ptr
  store ptr %fv1426, ptr %$f864.addr
  %freed1427 = call i64 @march_decrc_freed(ptr %ld1421)
  %freed_b1428 = icmp ne i64 %freed1427, 0
  br i1 %freed_b1428, label %br_unique325, label %br_shared326
br_shared326:
  call void @march_incrc(ptr %fv1426)
  br label %br_body327
br_unique325:
  br label %br_body327
br_body327:
  %ld1429 = load ptr, ptr %$f864.addr
  %msg.addr = alloca ptr
  store ptr %ld1429, ptr %msg.addr
  %hp1430 = call ptr @march_alloc(i64 24)
  %tgp1431 = getelementptr i8, ptr %hp1430, i64 8
  store i32 0, ptr %tgp1431, align 4
  %ld1432 = load ptr, ptr %msg.addr
  %fp1433 = getelementptr i8, ptr %hp1430, i64 16
  store ptr %ld1432, ptr %fp1433, align 8
  %$t846.addr = alloca ptr
  store ptr %hp1430, ptr %$t846.addr
  %hp1434 = call ptr @march_alloc(i64 24)
  %tgp1435 = getelementptr i8, ptr %hp1434, i64 8
  store i32 1, ptr %tgp1435, align 4
  %ld1436 = load ptr, ptr %$t846.addr
  %fp1437 = getelementptr i8, ptr %hp1434, i64 16
  store ptr %ld1436, ptr %fp1437, align 8
  store ptr %hp1434, ptr %res_slot1422
  br label %case_merge321
case_br324:
  %fp1438 = getelementptr i8, ptr %ld1421, i64 16
  %fv1439 = load ptr, ptr %fp1438, align 8
  %$f865.addr = alloca ptr
  store ptr %fv1439, ptr %$f865.addr
  %freed1440 = call i64 @march_decrc_freed(ptr %ld1421)
  %freed_b1441 = icmp ne i64 %freed1440, 0
  br i1 %freed_b1441, label %br_unique328, label %br_shared329
br_shared329:
  call void @march_incrc(ptr %fv1439)
  br label %br_body330
br_unique328:
  br label %br_body330
br_body330:
  %ld1442 = load ptr, ptr %$f865.addr
  %fd.addr = alloca ptr
  store ptr %ld1442, ptr %fd.addr
  %ld1443 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1443)
  %ld1444 = load ptr, ptr %tcp_send_all.addr
  %fp1445 = getelementptr i8, ptr %ld1444, i64 16
  %fv1446 = load ptr, ptr %fp1445, align 8
  %ld1447 = load ptr, ptr %fd.addr
  %ld1448 = load ptr, ptr %raw_request.addr
  %cr1449 = call ptr (ptr, ptr, ptr) %fv1446(ptr %ld1444, ptr %ld1447, ptr %ld1448)
  %$t847.addr = alloca ptr
  store ptr %cr1449, ptr %$t847.addr
  %ld1450 = load ptr, ptr %$t847.addr
  %res_slot1451 = alloca ptr
  %tgp1452 = getelementptr i8, ptr %ld1450, i64 8
  %tag1453 = load i32, ptr %tgp1452, align 4
  switch i32 %tag1453, label %case_default332 [
      i32 0, label %case_br333
      i32 0, label %case_br334
  ]
case_br333:
  %fp1454 = getelementptr i8, ptr %ld1450, i64 16
  %fv1455 = load ptr, ptr %fp1454, align 8
  %$f862.addr = alloca ptr
  store ptr %fv1455, ptr %$f862.addr
  %freed1456 = call i64 @march_decrc_freed(ptr %ld1450)
  %freed_b1457 = icmp ne i64 %freed1456, 0
  br i1 %freed_b1457, label %br_unique335, label %br_shared336
br_shared336:
  call void @march_incrc(ptr %fv1455)
  br label %br_body337
br_unique335:
  br label %br_body337
br_body337:
  %ld1458 = load ptr, ptr %$f862.addr
  %msg_1.addr = alloca ptr
  store ptr %ld1458, ptr %msg_1.addr
  %ld1459 = load ptr, ptr %tcp_close.addr
  %fp1460 = getelementptr i8, ptr %ld1459, i64 16
  %fv1461 = load ptr, ptr %fp1460, align 8
  %ld1462 = load ptr, ptr %fd.addr
  %cr1463 = call ptr (ptr, ptr) %fv1461(ptr %ld1459, ptr %ld1462)
  %hp1464 = call ptr @march_alloc(i64 24)
  %tgp1465 = getelementptr i8, ptr %hp1464, i64 8
  store i32 2, ptr %tgp1465, align 4
  %ld1466 = load ptr, ptr %msg_1.addr
  %fp1467 = getelementptr i8, ptr %hp1464, i64 16
  store ptr %ld1466, ptr %fp1467, align 8
  %$t848.addr = alloca ptr
  store ptr %hp1464, ptr %$t848.addr
  %hp1468 = call ptr @march_alloc(i64 24)
  %tgp1469 = getelementptr i8, ptr %hp1468, i64 8
  store i32 1, ptr %tgp1469, align 4
  %ld1470 = load ptr, ptr %$t848.addr
  %fp1471 = getelementptr i8, ptr %hp1468, i64 16
  store ptr %ld1470, ptr %fp1471, align 8
  store ptr %hp1468, ptr %res_slot1451
  br label %case_merge331
case_br334:
  %fp1472 = getelementptr i8, ptr %ld1450, i64 16
  %fv1473 = load ptr, ptr %fp1472, align 8
  %$f863.addr = alloca ptr
  store ptr %fv1473, ptr %$f863.addr
  %freed1474 = call i64 @march_decrc_freed(ptr %ld1450)
  %freed_b1475 = icmp ne i64 %freed1474, 0
  br i1 %freed_b1475, label %br_unique338, label %br_shared339
br_shared339:
  call void @march_incrc(ptr %fv1473)
  br label %br_body340
br_unique338:
  br label %br_body340
br_body340:
  %ld1476 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1476)
  %ld1477 = load ptr, ptr %tcp_recv_all.addr
  %fp1478 = getelementptr i8, ptr %ld1477, i64 16
  %fv1479 = load ptr, ptr %fp1478, align 8
  %ld1480 = load ptr, ptr %fd.addr
  %cv1481 = inttoptr i64 1048576 to ptr
  %cv1482 = inttoptr i64 30000 to ptr
  %cr1483 = call ptr (ptr, ptr, ptr, ptr) %fv1479(ptr %ld1477, ptr %ld1480, ptr %cv1481, ptr %cv1482)
  %$t849.addr = alloca ptr
  store ptr %cr1483, ptr %$t849.addr
  %ld1484 = load ptr, ptr %$t849.addr
  %res_slot1485 = alloca ptr
  %tgp1486 = getelementptr i8, ptr %ld1484, i64 8
  %tag1487 = load i32, ptr %tgp1486, align 4
  switch i32 %tag1487, label %case_default342 [
      i32 0, label %case_br343
      i32 0, label %case_br344
  ]
case_br343:
  %fp1488 = getelementptr i8, ptr %ld1484, i64 16
  %fv1489 = load ptr, ptr %fp1488, align 8
  %$f860.addr = alloca ptr
  store ptr %fv1489, ptr %$f860.addr
  %freed1490 = call i64 @march_decrc_freed(ptr %ld1484)
  %freed_b1491 = icmp ne i64 %freed1490, 0
  br i1 %freed_b1491, label %br_unique345, label %br_shared346
br_shared346:
  call void @march_incrc(ptr %fv1489)
  br label %br_body347
br_unique345:
  br label %br_body347
br_body347:
  %ld1492 = load ptr, ptr %$f860.addr
  %msg_2.addr = alloca ptr
  store ptr %ld1492, ptr %msg_2.addr
  %ld1493 = load ptr, ptr %tcp_close.addr
  %fp1494 = getelementptr i8, ptr %ld1493, i64 16
  %fv1495 = load ptr, ptr %fp1494, align 8
  %ld1496 = load ptr, ptr %fd.addr
  %cr1497 = call ptr (ptr, ptr) %fv1495(ptr %ld1493, ptr %ld1496)
  %hp1498 = call ptr @march_alloc(i64 24)
  %tgp1499 = getelementptr i8, ptr %hp1498, i64 8
  store i32 3, ptr %tgp1499, align 4
  %ld1500 = load ptr, ptr %msg_2.addr
  %fp1501 = getelementptr i8, ptr %hp1498, i64 16
  store ptr %ld1500, ptr %fp1501, align 8
  %$t850.addr = alloca ptr
  store ptr %hp1498, ptr %$t850.addr
  %hp1502 = call ptr @march_alloc(i64 24)
  %tgp1503 = getelementptr i8, ptr %hp1502, i64 8
  store i32 1, ptr %tgp1503, align 4
  %ld1504 = load ptr, ptr %$t850.addr
  %fp1505 = getelementptr i8, ptr %hp1502, i64 16
  store ptr %ld1504, ptr %fp1505, align 8
  store ptr %hp1502, ptr %res_slot1485
  br label %case_merge341
case_br344:
  %fp1506 = getelementptr i8, ptr %ld1484, i64 16
  %fv1507 = load ptr, ptr %fp1506, align 8
  %$f861.addr = alloca ptr
  store ptr %fv1507, ptr %$f861.addr
  %freed1508 = call i64 @march_decrc_freed(ptr %ld1484)
  %freed_b1509 = icmp ne i64 %freed1508, 0
  br i1 %freed_b1509, label %br_unique348, label %br_shared349
br_shared349:
  call void @march_incrc(ptr %fv1507)
  br label %br_body350
br_unique348:
  br label %br_body350
br_body350:
  %ld1510 = load ptr, ptr %$f861.addr
  %raw_response.addr = alloca ptr
  store ptr %ld1510, ptr %raw_response.addr
  %ld1511 = load ptr, ptr %tcp_close.addr
  %fp1512 = getelementptr i8, ptr %ld1511, i64 16
  %fv1513 = load ptr, ptr %fp1512, align 8
  %ld1514 = load ptr, ptr %fd.addr
  %cr1515 = call ptr (ptr, ptr) %fv1513(ptr %ld1511, ptr %ld1514)
  %ld1516 = load ptr, ptr %http_parse_response.addr
  %fp1517 = getelementptr i8, ptr %ld1516, i64 16
  %fv1518 = load ptr, ptr %fp1517, align 8
  %ld1519 = load ptr, ptr %raw_response.addr
  %cr1520 = call ptr (ptr, ptr) %fv1518(ptr %ld1516, ptr %ld1519)
  %$t851.addr = alloca ptr
  store ptr %cr1520, ptr %$t851.addr
  %ld1521 = load ptr, ptr %$t851.addr
  %res_slot1522 = alloca ptr
  %tgp1523 = getelementptr i8, ptr %ld1521, i64 8
  %tag1524 = load i32, ptr %tgp1523, align 4
  switch i32 %tag1524, label %case_default352 [
      i32 0, label %case_br353
      i32 0, label %case_br354
  ]
case_br353:
  %fp1525 = getelementptr i8, ptr %ld1521, i64 16
  %fv1526 = load ptr, ptr %fp1525, align 8
  %$f855.addr = alloca ptr
  store ptr %fv1526, ptr %$f855.addr
  %freed1527 = call i64 @march_decrc_freed(ptr %ld1521)
  %freed_b1528 = icmp ne i64 %freed1527, 0
  br i1 %freed_b1528, label %br_unique355, label %br_shared356
br_shared356:
  call void @march_incrc(ptr %fv1526)
  br label %br_body357
br_unique355:
  br label %br_body357
br_body357:
  %ld1529 = load ptr, ptr %$f855.addr
  %msg_3.addr = alloca ptr
  store ptr %ld1529, ptr %msg_3.addr
  %hp1530 = call ptr @march_alloc(i64 24)
  %tgp1531 = getelementptr i8, ptr %hp1530, i64 8
  store i32 0, ptr %tgp1531, align 4
  %ld1532 = load ptr, ptr %msg_3.addr
  %fp1533 = getelementptr i8, ptr %hp1530, i64 16
  store ptr %ld1532, ptr %fp1533, align 8
  %$t852.addr = alloca ptr
  store ptr %hp1530, ptr %$t852.addr
  %hp1534 = call ptr @march_alloc(i64 24)
  %tgp1535 = getelementptr i8, ptr %hp1534, i64 8
  store i32 1, ptr %tgp1535, align 4
  %ld1536 = load ptr, ptr %$t852.addr
  %fp1537 = getelementptr i8, ptr %hp1534, i64 16
  store ptr %ld1536, ptr %fp1537, align 8
  store ptr %hp1534, ptr %res_slot1522
  br label %case_merge351
case_br354:
  %fp1538 = getelementptr i8, ptr %ld1521, i64 16
  %fv1539 = load ptr, ptr %fp1538, align 8
  %$f856.addr = alloca ptr
  store ptr %fv1539, ptr %$f856.addr
  %freed1540 = call i64 @march_decrc_freed(ptr %ld1521)
  %freed_b1541 = icmp ne i64 %freed1540, 0
  br i1 %freed_b1541, label %br_unique358, label %br_shared359
br_shared359:
  call void @march_incrc(ptr %fv1539)
  br label %br_body360
br_unique358:
  br label %br_body360
br_body360:
  %ld1542 = load ptr, ptr %$f856.addr
  %res_slot1543 = alloca ptr
  %tgp1544 = getelementptr i8, ptr %ld1542, i64 8
  %tag1545 = load i32, ptr %tgp1544, align 4
  switch i32 %tag1545, label %case_default362 [
      i32 0, label %case_br363
  ]
case_br363:
  %fp1546 = getelementptr i8, ptr %ld1542, i64 16
  %fv1547 = load ptr, ptr %fp1546, align 8
  %$f857.addr = alloca ptr
  store ptr %fv1547, ptr %$f857.addr
  %fp1548 = getelementptr i8, ptr %ld1542, i64 24
  %fv1549 = load ptr, ptr %fp1548, align 8
  %$f858.addr = alloca ptr
  store ptr %fv1549, ptr %$f858.addr
  %fp1550 = getelementptr i8, ptr %ld1542, i64 32
  %fv1551 = load ptr, ptr %fp1550, align 8
  %$f859.addr = alloca ptr
  store ptr %fv1551, ptr %$f859.addr
  %freed1552 = call i64 @march_decrc_freed(ptr %ld1542)
  %freed_b1553 = icmp ne i64 %freed1552, 0
  br i1 %freed_b1553, label %br_unique364, label %br_shared365
br_shared365:
  call void @march_incrc(ptr %fv1551)
  call void @march_incrc(ptr %fv1549)
  call void @march_incrc(ptr %fv1547)
  br label %br_body366
br_unique364:
  br label %br_body366
br_body366:
  %ld1554 = load ptr, ptr %$f859.addr
  %resp_body.addr = alloca ptr
  store ptr %ld1554, ptr %resp_body.addr
  %ld1555 = load ptr, ptr %$f858.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld1555, ptr %resp_headers.addr
  %ld1556 = load ptr, ptr %$f857.addr
  %status_code.addr = alloca ptr
  store ptr %ld1556, ptr %status_code.addr
  %hp1557 = call ptr @march_alloc(i64 24)
  %tgp1558 = getelementptr i8, ptr %hp1557, i64 8
  store i32 0, ptr %tgp1558, align 4
  %ld1559 = load ptr, ptr %status_code.addr
  %fp1560 = getelementptr i8, ptr %hp1557, i64 16
  store ptr %ld1559, ptr %fp1560, align 8
  %$t853.addr = alloca ptr
  store ptr %hp1557, ptr %$t853.addr
  %hp1561 = call ptr @march_alloc(i64 40)
  %tgp1562 = getelementptr i8, ptr %hp1561, i64 8
  store i32 0, ptr %tgp1562, align 4
  %ld1563 = load ptr, ptr %$t853.addr
  %fp1564 = getelementptr i8, ptr %hp1561, i64 16
  store ptr %ld1563, ptr %fp1564, align 8
  %ld1565 = load ptr, ptr %resp_headers.addr
  %fp1566 = getelementptr i8, ptr %hp1561, i64 24
  store ptr %ld1565, ptr %fp1566, align 8
  %ld1567 = load ptr, ptr %resp_body.addr
  %fp1568 = getelementptr i8, ptr %hp1561, i64 32
  store ptr %ld1567, ptr %fp1568, align 8
  %$t854.addr = alloca ptr
  store ptr %hp1561, ptr %$t854.addr
  %hp1569 = call ptr @march_alloc(i64 24)
  %tgp1570 = getelementptr i8, ptr %hp1569, i64 8
  store i32 0, ptr %tgp1570, align 4
  %ld1571 = load ptr, ptr %$t854.addr
  %fp1572 = getelementptr i8, ptr %hp1569, i64 16
  store ptr %ld1571, ptr %fp1572, align 8
  store ptr %hp1569, ptr %res_slot1543
  br label %case_merge361
case_default362:
  unreachable
case_merge361:
  %case_r1573 = load ptr, ptr %res_slot1543
  store ptr %case_r1573, ptr %res_slot1522
  br label %case_merge351
case_default352:
  unreachable
case_merge351:
  %case_r1574 = load ptr, ptr %res_slot1522
  store ptr %case_r1574, ptr %res_slot1485
  br label %case_merge341
case_default342:
  unreachable
case_merge341:
  %case_r1575 = load ptr, ptr %res_slot1485
  store ptr %case_r1575, ptr %res_slot1451
  br label %case_merge331
case_default332:
  unreachable
case_merge331:
  %case_r1576 = load ptr, ptr %res_slot1451
  store ptr %case_r1576, ptr %res_slot1422
  br label %case_merge321
case_default322:
  unreachable
case_merge321:
  %case_r1577 = load ptr, ptr %res_slot1422
  ret ptr %case_r1577
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1578 = load ptr, ptr %req.addr
  %res_slot1579 = alloca ptr
  %tgp1580 = getelementptr i8, ptr %ld1578, i64 8
  %tag1581 = load i32, ptr %tgp1580, align 4
  switch i32 %tag1581, label %case_default368 [
      i32 0, label %case_br369
  ]
case_br369:
  %fp1582 = getelementptr i8, ptr %ld1578, i64 16
  %fv1583 = load ptr, ptr %fp1582, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1583, ptr %$f591.addr
  %fp1584 = getelementptr i8, ptr %ld1578, i64 24
  %fv1585 = load ptr, ptr %fp1584, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1585, ptr %$f592.addr
  %fp1586 = getelementptr i8, ptr %ld1578, i64 32
  %fv1587 = load ptr, ptr %fp1586, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1587, ptr %$f593.addr
  %fp1588 = getelementptr i8, ptr %ld1578, i64 40
  %fv1589 = load ptr, ptr %fp1588, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1589, ptr %$f594.addr
  %fp1590 = getelementptr i8, ptr %ld1578, i64 48
  %fv1591 = load ptr, ptr %fp1590, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1591, ptr %$f595.addr
  %fp1592 = getelementptr i8, ptr %ld1578, i64 56
  %fv1593 = load ptr, ptr %fp1592, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1593, ptr %$f596.addr
  %fp1594 = getelementptr i8, ptr %ld1578, i64 64
  %fv1595 = load ptr, ptr %fp1594, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1595, ptr %$f597.addr
  %fp1596 = getelementptr i8, ptr %ld1578, i64 72
  %fv1597 = load ptr, ptr %fp1596, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1597, ptr %$f598.addr
  %freed1598 = call i64 @march_decrc_freed(ptr %ld1578)
  %freed_b1599 = icmp ne i64 %freed1598, 0
  br i1 %freed_b1599, label %br_unique370, label %br_shared371
br_shared371:
  call void @march_incrc(ptr %fv1597)
  call void @march_incrc(ptr %fv1595)
  call void @march_incrc(ptr %fv1593)
  call void @march_incrc(ptr %fv1591)
  call void @march_incrc(ptr %fv1589)
  call void @march_incrc(ptr %fv1587)
  call void @march_incrc(ptr %fv1585)
  call void @march_incrc(ptr %fv1583)
  br label %br_body372
br_unique370:
  br label %br_body372
br_body372:
  %ld1600 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1600, ptr %h.addr
  %ld1601 = load ptr, ptr %h.addr
  store ptr %ld1601, ptr %res_slot1579
  br label %case_merge367
case_default368:
  unreachable
case_merge367:
  %case_r1602 = load ptr, ptr %res_slot1579
  ret ptr %case_r1602
}

define ptr @Http.query$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1603 = load ptr, ptr %req.addr
  %res_slot1604 = alloca ptr
  %tgp1605 = getelementptr i8, ptr %ld1603, i64 8
  %tag1606 = load i32, ptr %tgp1605, align 4
  switch i32 %tag1606, label %case_default374 [
      i32 0, label %case_br375
  ]
case_br375:
  %fp1607 = getelementptr i8, ptr %ld1603, i64 16
  %fv1608 = load ptr, ptr %fp1607, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1608, ptr %$f583.addr
  %fp1609 = getelementptr i8, ptr %ld1603, i64 24
  %fv1610 = load ptr, ptr %fp1609, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1610, ptr %$f584.addr
  %fp1611 = getelementptr i8, ptr %ld1603, i64 32
  %fv1612 = load ptr, ptr %fp1611, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1612, ptr %$f585.addr
  %fp1613 = getelementptr i8, ptr %ld1603, i64 40
  %fv1614 = load ptr, ptr %fp1613, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1614, ptr %$f586.addr
  %fp1615 = getelementptr i8, ptr %ld1603, i64 48
  %fv1616 = load ptr, ptr %fp1615, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1616, ptr %$f587.addr
  %fp1617 = getelementptr i8, ptr %ld1603, i64 56
  %fv1618 = load ptr, ptr %fp1617, align 8
  %$f588.addr = alloca ptr
  store ptr %fv1618, ptr %$f588.addr
  %fp1619 = getelementptr i8, ptr %ld1603, i64 64
  %fv1620 = load ptr, ptr %fp1619, align 8
  %$f589.addr = alloca ptr
  store ptr %fv1620, ptr %$f589.addr
  %fp1621 = getelementptr i8, ptr %ld1603, i64 72
  %fv1622 = load ptr, ptr %fp1621, align 8
  %$f590.addr = alloca ptr
  store ptr %fv1622, ptr %$f590.addr
  %freed1623 = call i64 @march_decrc_freed(ptr %ld1603)
  %freed_b1624 = icmp ne i64 %freed1623, 0
  br i1 %freed_b1624, label %br_unique376, label %br_shared377
br_shared377:
  call void @march_incrc(ptr %fv1622)
  call void @march_incrc(ptr %fv1620)
  call void @march_incrc(ptr %fv1618)
  call void @march_incrc(ptr %fv1616)
  call void @march_incrc(ptr %fv1614)
  call void @march_incrc(ptr %fv1612)
  call void @march_incrc(ptr %fv1610)
  call void @march_incrc(ptr %fv1608)
  br label %br_body378
br_unique376:
  br label %br_body378
br_body378:
  %ld1625 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld1625, ptr %q.addr
  %ld1626 = load ptr, ptr %q.addr
  store ptr %ld1626, ptr %res_slot1604
  br label %case_merge373
case_default374:
  unreachable
case_merge373:
  %case_r1627 = load ptr, ptr %res_slot1604
  ret ptr %case_r1627
}

define ptr @Http.path$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1628 = load ptr, ptr %req.addr
  %res_slot1629 = alloca ptr
  %tgp1630 = getelementptr i8, ptr %ld1628, i64 8
  %tag1631 = load i32, ptr %tgp1630, align 4
  switch i32 %tag1631, label %case_default380 [
      i32 0, label %case_br381
  ]
case_br381:
  %fp1632 = getelementptr i8, ptr %ld1628, i64 16
  %fv1633 = load ptr, ptr %fp1632, align 8
  %$f575.addr = alloca ptr
  store ptr %fv1633, ptr %$f575.addr
  %fp1634 = getelementptr i8, ptr %ld1628, i64 24
  %fv1635 = load ptr, ptr %fp1634, align 8
  %$f576.addr = alloca ptr
  store ptr %fv1635, ptr %$f576.addr
  %fp1636 = getelementptr i8, ptr %ld1628, i64 32
  %fv1637 = load ptr, ptr %fp1636, align 8
  %$f577.addr = alloca ptr
  store ptr %fv1637, ptr %$f577.addr
  %fp1638 = getelementptr i8, ptr %ld1628, i64 40
  %fv1639 = load ptr, ptr %fp1638, align 8
  %$f578.addr = alloca ptr
  store ptr %fv1639, ptr %$f578.addr
  %fp1640 = getelementptr i8, ptr %ld1628, i64 48
  %fv1641 = load ptr, ptr %fp1640, align 8
  %$f579.addr = alloca ptr
  store ptr %fv1641, ptr %$f579.addr
  %fp1642 = getelementptr i8, ptr %ld1628, i64 56
  %fv1643 = load ptr, ptr %fp1642, align 8
  %$f580.addr = alloca ptr
  store ptr %fv1643, ptr %$f580.addr
  %fp1644 = getelementptr i8, ptr %ld1628, i64 64
  %fv1645 = load ptr, ptr %fp1644, align 8
  %$f581.addr = alloca ptr
  store ptr %fv1645, ptr %$f581.addr
  %fp1646 = getelementptr i8, ptr %ld1628, i64 72
  %fv1647 = load ptr, ptr %fp1646, align 8
  %$f582.addr = alloca ptr
  store ptr %fv1647, ptr %$f582.addr
  %freed1648 = call i64 @march_decrc_freed(ptr %ld1628)
  %freed_b1649 = icmp ne i64 %freed1648, 0
  br i1 %freed_b1649, label %br_unique382, label %br_shared383
br_shared383:
  call void @march_incrc(ptr %fv1647)
  call void @march_incrc(ptr %fv1645)
  call void @march_incrc(ptr %fv1643)
  call void @march_incrc(ptr %fv1641)
  call void @march_incrc(ptr %fv1639)
  call void @march_incrc(ptr %fv1637)
  call void @march_incrc(ptr %fv1635)
  call void @march_incrc(ptr %fv1633)
  br label %br_body384
br_unique382:
  br label %br_body384
br_body384:
  %ld1650 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld1650, ptr %p.addr
  %ld1651 = load ptr, ptr %p.addr
  store ptr %ld1651, ptr %res_slot1629
  br label %case_merge379
case_default380:
  unreachable
case_merge379:
  %case_r1652 = load ptr, ptr %res_slot1629
  ret ptr %case_r1652
}

define ptr @Http.port$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1653 = load ptr, ptr %req.addr
  %res_slot1654 = alloca ptr
  %tgp1655 = getelementptr i8, ptr %ld1653, i64 8
  %tag1656 = load i32, ptr %tgp1655, align 4
  switch i32 %tag1656, label %case_default386 [
      i32 0, label %case_br387
  ]
case_br387:
  %fp1657 = getelementptr i8, ptr %ld1653, i64 16
  %fv1658 = load ptr, ptr %fp1657, align 8
  %$f567.addr = alloca ptr
  store ptr %fv1658, ptr %$f567.addr
  %fp1659 = getelementptr i8, ptr %ld1653, i64 24
  %fv1660 = load ptr, ptr %fp1659, align 8
  %$f568.addr = alloca ptr
  store ptr %fv1660, ptr %$f568.addr
  %fp1661 = getelementptr i8, ptr %ld1653, i64 32
  %fv1662 = load ptr, ptr %fp1661, align 8
  %$f569.addr = alloca ptr
  store ptr %fv1662, ptr %$f569.addr
  %fp1663 = getelementptr i8, ptr %ld1653, i64 40
  %fv1664 = load ptr, ptr %fp1663, align 8
  %$f570.addr = alloca ptr
  store ptr %fv1664, ptr %$f570.addr
  %fp1665 = getelementptr i8, ptr %ld1653, i64 48
  %fv1666 = load ptr, ptr %fp1665, align 8
  %$f571.addr = alloca ptr
  store ptr %fv1666, ptr %$f571.addr
  %fp1667 = getelementptr i8, ptr %ld1653, i64 56
  %fv1668 = load ptr, ptr %fp1667, align 8
  %$f572.addr = alloca ptr
  store ptr %fv1668, ptr %$f572.addr
  %fp1669 = getelementptr i8, ptr %ld1653, i64 64
  %fv1670 = load ptr, ptr %fp1669, align 8
  %$f573.addr = alloca ptr
  store ptr %fv1670, ptr %$f573.addr
  %fp1671 = getelementptr i8, ptr %ld1653, i64 72
  %fv1672 = load ptr, ptr %fp1671, align 8
  %$f574.addr = alloca ptr
  store ptr %fv1672, ptr %$f574.addr
  %freed1673 = call i64 @march_decrc_freed(ptr %ld1653)
  %freed_b1674 = icmp ne i64 %freed1673, 0
  br i1 %freed_b1674, label %br_unique388, label %br_shared389
br_shared389:
  call void @march_incrc(ptr %fv1672)
  call void @march_incrc(ptr %fv1670)
  call void @march_incrc(ptr %fv1668)
  call void @march_incrc(ptr %fv1666)
  call void @march_incrc(ptr %fv1664)
  call void @march_incrc(ptr %fv1662)
  call void @march_incrc(ptr %fv1660)
  call void @march_incrc(ptr %fv1658)
  br label %br_body390
br_unique388:
  br label %br_body390
br_body390:
  %ld1675 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld1675, ptr %p.addr
  %ld1676 = load ptr, ptr %p.addr
  store ptr %ld1676, ptr %res_slot1654
  br label %case_merge385
case_default386:
  unreachable
case_merge385:
  %case_r1677 = load ptr, ptr %res_slot1654
  ret ptr %case_r1677
}

define ptr @Http.host$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1678 = load ptr, ptr %req.addr
  %res_slot1679 = alloca ptr
  %tgp1680 = getelementptr i8, ptr %ld1678, i64 8
  %tag1681 = load i32, ptr %tgp1680, align 4
  switch i32 %tag1681, label %case_default392 [
      i32 0, label %case_br393
  ]
case_br393:
  %fp1682 = getelementptr i8, ptr %ld1678, i64 16
  %fv1683 = load ptr, ptr %fp1682, align 8
  %$f559.addr = alloca ptr
  store ptr %fv1683, ptr %$f559.addr
  %fp1684 = getelementptr i8, ptr %ld1678, i64 24
  %fv1685 = load ptr, ptr %fp1684, align 8
  %$f560.addr = alloca ptr
  store ptr %fv1685, ptr %$f560.addr
  %fp1686 = getelementptr i8, ptr %ld1678, i64 32
  %fv1687 = load ptr, ptr %fp1686, align 8
  %$f561.addr = alloca ptr
  store ptr %fv1687, ptr %$f561.addr
  %fp1688 = getelementptr i8, ptr %ld1678, i64 40
  %fv1689 = load ptr, ptr %fp1688, align 8
  %$f562.addr = alloca ptr
  store ptr %fv1689, ptr %$f562.addr
  %fp1690 = getelementptr i8, ptr %ld1678, i64 48
  %fv1691 = load ptr, ptr %fp1690, align 8
  %$f563.addr = alloca ptr
  store ptr %fv1691, ptr %$f563.addr
  %fp1692 = getelementptr i8, ptr %ld1678, i64 56
  %fv1693 = load ptr, ptr %fp1692, align 8
  %$f564.addr = alloca ptr
  store ptr %fv1693, ptr %$f564.addr
  %fp1694 = getelementptr i8, ptr %ld1678, i64 64
  %fv1695 = load ptr, ptr %fp1694, align 8
  %$f565.addr = alloca ptr
  store ptr %fv1695, ptr %$f565.addr
  %fp1696 = getelementptr i8, ptr %ld1678, i64 72
  %fv1697 = load ptr, ptr %fp1696, align 8
  %$f566.addr = alloca ptr
  store ptr %fv1697, ptr %$f566.addr
  %freed1698 = call i64 @march_decrc_freed(ptr %ld1678)
  %freed_b1699 = icmp ne i64 %freed1698, 0
  br i1 %freed_b1699, label %br_unique394, label %br_shared395
br_shared395:
  call void @march_incrc(ptr %fv1697)
  call void @march_incrc(ptr %fv1695)
  call void @march_incrc(ptr %fv1693)
  call void @march_incrc(ptr %fv1691)
  call void @march_incrc(ptr %fv1689)
  call void @march_incrc(ptr %fv1687)
  call void @march_incrc(ptr %fv1685)
  call void @march_incrc(ptr %fv1683)
  br label %br_body396
br_unique394:
  br label %br_body396
br_body396:
  %ld1700 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld1700, ptr %h.addr
  %ld1701 = load ptr, ptr %h.addr
  store ptr %ld1701, ptr %res_slot1679
  br label %case_merge391
case_default392:
  unreachable
case_merge391:
  %case_r1702 = load ptr, ptr %res_slot1679
  ret ptr %case_r1702
}

define ptr @Http.scheme$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1703 = load ptr, ptr %req.addr
  %res_slot1704 = alloca ptr
  %tgp1705 = getelementptr i8, ptr %ld1703, i64 8
  %tag1706 = load i32, ptr %tgp1705, align 4
  switch i32 %tag1706, label %case_default398 [
      i32 0, label %case_br399
  ]
case_br399:
  %fp1707 = getelementptr i8, ptr %ld1703, i64 16
  %fv1708 = load ptr, ptr %fp1707, align 8
  %$f551.addr = alloca ptr
  store ptr %fv1708, ptr %$f551.addr
  %fp1709 = getelementptr i8, ptr %ld1703, i64 24
  %fv1710 = load ptr, ptr %fp1709, align 8
  %$f552.addr = alloca ptr
  store ptr %fv1710, ptr %$f552.addr
  %fp1711 = getelementptr i8, ptr %ld1703, i64 32
  %fv1712 = load ptr, ptr %fp1711, align 8
  %$f553.addr = alloca ptr
  store ptr %fv1712, ptr %$f553.addr
  %fp1713 = getelementptr i8, ptr %ld1703, i64 40
  %fv1714 = load ptr, ptr %fp1713, align 8
  %$f554.addr = alloca ptr
  store ptr %fv1714, ptr %$f554.addr
  %fp1715 = getelementptr i8, ptr %ld1703, i64 48
  %fv1716 = load ptr, ptr %fp1715, align 8
  %$f555.addr = alloca ptr
  store ptr %fv1716, ptr %$f555.addr
  %fp1717 = getelementptr i8, ptr %ld1703, i64 56
  %fv1718 = load ptr, ptr %fp1717, align 8
  %$f556.addr = alloca ptr
  store ptr %fv1718, ptr %$f556.addr
  %fp1719 = getelementptr i8, ptr %ld1703, i64 64
  %fv1720 = load ptr, ptr %fp1719, align 8
  %$f557.addr = alloca ptr
  store ptr %fv1720, ptr %$f557.addr
  %fp1721 = getelementptr i8, ptr %ld1703, i64 72
  %fv1722 = load ptr, ptr %fp1721, align 8
  %$f558.addr = alloca ptr
  store ptr %fv1722, ptr %$f558.addr
  %freed1723 = call i64 @march_decrc_freed(ptr %ld1703)
  %freed_b1724 = icmp ne i64 %freed1723, 0
  br i1 %freed_b1724, label %br_unique400, label %br_shared401
br_shared401:
  call void @march_incrc(ptr %fv1722)
  call void @march_incrc(ptr %fv1720)
  call void @march_incrc(ptr %fv1718)
  call void @march_incrc(ptr %fv1716)
  call void @march_incrc(ptr %fv1714)
  call void @march_incrc(ptr %fv1712)
  call void @march_incrc(ptr %fv1710)
  call void @march_incrc(ptr %fv1708)
  br label %br_body402
br_unique400:
  br label %br_body402
br_body402:
  %ld1725 = load ptr, ptr %$f552.addr
  %s.addr = alloca ptr
  store ptr %ld1725, ptr %s.addr
  %ld1726 = load ptr, ptr %s.addr
  store ptr %ld1726, ptr %res_slot1704
  br label %case_merge397
case_default398:
  unreachable
case_merge397:
  %case_r1727 = load ptr, ptr %res_slot1704
  ret ptr %case_r1727
}

define ptr @Http.set_body$Request_String$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld1728 = load ptr, ptr %req.addr
  %res_slot1729 = alloca ptr
  %tgp1730 = getelementptr i8, ptr %ld1728, i64 8
  %tag1731 = load i32, ptr %tgp1730, align 4
  switch i32 %tag1731, label %case_default404 [
      i32 0, label %case_br405
  ]
case_br405:
  %fp1732 = getelementptr i8, ptr %ld1728, i64 16
  %fv1733 = load ptr, ptr %fp1732, align 8
  %$f648.addr = alloca ptr
  store ptr %fv1733, ptr %$f648.addr
  %fp1734 = getelementptr i8, ptr %ld1728, i64 24
  %fv1735 = load ptr, ptr %fp1734, align 8
  %$f649.addr = alloca ptr
  store ptr %fv1735, ptr %$f649.addr
  %fp1736 = getelementptr i8, ptr %ld1728, i64 32
  %fv1737 = load ptr, ptr %fp1736, align 8
  %$f650.addr = alloca ptr
  store ptr %fv1737, ptr %$f650.addr
  %fp1738 = getelementptr i8, ptr %ld1728, i64 40
  %fv1739 = load ptr, ptr %fp1738, align 8
  %$f651.addr = alloca ptr
  store ptr %fv1739, ptr %$f651.addr
  %fp1740 = getelementptr i8, ptr %ld1728, i64 48
  %fv1741 = load ptr, ptr %fp1740, align 8
  %$f652.addr = alloca ptr
  store ptr %fv1741, ptr %$f652.addr
  %fp1742 = getelementptr i8, ptr %ld1728, i64 56
  %fv1743 = load ptr, ptr %fp1742, align 8
  %$f653.addr = alloca ptr
  store ptr %fv1743, ptr %$f653.addr
  %fp1744 = getelementptr i8, ptr %ld1728, i64 64
  %fv1745 = load ptr, ptr %fp1744, align 8
  %$f654.addr = alloca ptr
  store ptr %fv1745, ptr %$f654.addr
  %fp1746 = getelementptr i8, ptr %ld1728, i64 72
  %fv1747 = load ptr, ptr %fp1746, align 8
  %$f655.addr = alloca ptr
  store ptr %fv1747, ptr %$f655.addr
  %ld1748 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld1748, ptr %hd.addr
  %ld1749 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld1749, ptr %q.addr
  %ld1750 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld1750, ptr %pa.addr
  %ld1751 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld1751, ptr %p.addr
  %ld1752 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld1752, ptr %h.addr
  %ld1753 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld1753, ptr %sc.addr
  %ld1754 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld1754, ptr %m.addr
  %ld1755 = load ptr, ptr %req.addr
  %ld1756 = load ptr, ptr %m.addr
  %ld1757 = load ptr, ptr %sc.addr
  %ld1758 = load ptr, ptr %h.addr
  %ld1759 = load ptr, ptr %p.addr
  %ld1760 = load ptr, ptr %pa.addr
  %ld1761 = load ptr, ptr %q.addr
  %ld1762 = load ptr, ptr %hd.addr
  %ld1763 = load ptr, ptr %new_body.addr
  %rc1764 = load i64, ptr %ld1755, align 8
  %uniq1765 = icmp eq i64 %rc1764, 1
  %fbip_slot1766 = alloca ptr
  br i1 %uniq1765, label %fbip_reuse406, label %fbip_fresh407
fbip_reuse406:
  %tgp1767 = getelementptr i8, ptr %ld1755, i64 8
  store i32 0, ptr %tgp1767, align 4
  %fp1768 = getelementptr i8, ptr %ld1755, i64 16
  store ptr %ld1756, ptr %fp1768, align 8
  %fp1769 = getelementptr i8, ptr %ld1755, i64 24
  store ptr %ld1757, ptr %fp1769, align 8
  %fp1770 = getelementptr i8, ptr %ld1755, i64 32
  store ptr %ld1758, ptr %fp1770, align 8
  %fp1771 = getelementptr i8, ptr %ld1755, i64 40
  store ptr %ld1759, ptr %fp1771, align 8
  %fp1772 = getelementptr i8, ptr %ld1755, i64 48
  store ptr %ld1760, ptr %fp1772, align 8
  %fp1773 = getelementptr i8, ptr %ld1755, i64 56
  store ptr %ld1761, ptr %fp1773, align 8
  %fp1774 = getelementptr i8, ptr %ld1755, i64 64
  store ptr %ld1762, ptr %fp1774, align 8
  %fp1775 = getelementptr i8, ptr %ld1755, i64 72
  store ptr %ld1763, ptr %fp1775, align 8
  store ptr %ld1755, ptr %fbip_slot1766
  br label %fbip_merge408
fbip_fresh407:
  call void @march_decrc(ptr %ld1755)
  %hp1776 = call ptr @march_alloc(i64 80)
  %tgp1777 = getelementptr i8, ptr %hp1776, i64 8
  store i32 0, ptr %tgp1777, align 4
  %fp1778 = getelementptr i8, ptr %hp1776, i64 16
  store ptr %ld1756, ptr %fp1778, align 8
  %fp1779 = getelementptr i8, ptr %hp1776, i64 24
  store ptr %ld1757, ptr %fp1779, align 8
  %fp1780 = getelementptr i8, ptr %hp1776, i64 32
  store ptr %ld1758, ptr %fp1780, align 8
  %fp1781 = getelementptr i8, ptr %hp1776, i64 40
  store ptr %ld1759, ptr %fp1781, align 8
  %fp1782 = getelementptr i8, ptr %hp1776, i64 48
  store ptr %ld1760, ptr %fp1782, align 8
  %fp1783 = getelementptr i8, ptr %hp1776, i64 56
  store ptr %ld1761, ptr %fp1783, align 8
  %fp1784 = getelementptr i8, ptr %hp1776, i64 64
  store ptr %ld1762, ptr %fp1784, align 8
  %fp1785 = getelementptr i8, ptr %hp1776, i64 72
  store ptr %ld1763, ptr %fp1785, align 8
  store ptr %hp1776, ptr %fbip_slot1766
  br label %fbip_merge408
fbip_merge408:
  %fbip_r1786 = load ptr, ptr %fbip_slot1766
  store ptr %fbip_r1786, ptr %res_slot1729
  br label %case_merge403
case_default404:
  unreachable
case_merge403:
  %case_r1787 = load ptr, ptr %res_slot1729
  ret ptr %case_r1787
}

define ptr @Http.set_method$Request_String$Method(ptr %req.arg, ptr %m.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %m.addr = alloca ptr
  store ptr %m.arg, ptr %m.addr
  %ld1788 = load ptr, ptr %req.addr
  %res_slot1789 = alloca ptr
  %tgp1790 = getelementptr i8, ptr %ld1788, i64 8
  %tag1791 = load i32, ptr %tgp1790, align 4
  switch i32 %tag1791, label %case_default410 [
      i32 0, label %case_br411
  ]
case_br411:
  %fp1792 = getelementptr i8, ptr %ld1788, i64 16
  %fv1793 = load ptr, ptr %fp1792, align 8
  %$f607.addr = alloca ptr
  store ptr %fv1793, ptr %$f607.addr
  %fp1794 = getelementptr i8, ptr %ld1788, i64 24
  %fv1795 = load ptr, ptr %fp1794, align 8
  %$f608.addr = alloca ptr
  store ptr %fv1795, ptr %$f608.addr
  %fp1796 = getelementptr i8, ptr %ld1788, i64 32
  %fv1797 = load ptr, ptr %fp1796, align 8
  %$f609.addr = alloca ptr
  store ptr %fv1797, ptr %$f609.addr
  %fp1798 = getelementptr i8, ptr %ld1788, i64 40
  %fv1799 = load ptr, ptr %fp1798, align 8
  %$f610.addr = alloca ptr
  store ptr %fv1799, ptr %$f610.addr
  %fp1800 = getelementptr i8, ptr %ld1788, i64 48
  %fv1801 = load ptr, ptr %fp1800, align 8
  %$f611.addr = alloca ptr
  store ptr %fv1801, ptr %$f611.addr
  %fp1802 = getelementptr i8, ptr %ld1788, i64 56
  %fv1803 = load ptr, ptr %fp1802, align 8
  %$f612.addr = alloca ptr
  store ptr %fv1803, ptr %$f612.addr
  %fp1804 = getelementptr i8, ptr %ld1788, i64 64
  %fv1805 = load ptr, ptr %fp1804, align 8
  %$f613.addr = alloca ptr
  store ptr %fv1805, ptr %$f613.addr
  %fp1806 = getelementptr i8, ptr %ld1788, i64 72
  %fv1807 = load ptr, ptr %fp1806, align 8
  %$f614.addr = alloca ptr
  store ptr %fv1807, ptr %$f614.addr
  %ld1808 = load ptr, ptr %$f614.addr
  %bd.addr = alloca ptr
  store ptr %ld1808, ptr %bd.addr
  %ld1809 = load ptr, ptr %$f613.addr
  %hd.addr = alloca ptr
  store ptr %ld1809, ptr %hd.addr
  %ld1810 = load ptr, ptr %$f612.addr
  %q.addr = alloca ptr
  store ptr %ld1810, ptr %q.addr
  %ld1811 = load ptr, ptr %$f611.addr
  %pa.addr = alloca ptr
  store ptr %ld1811, ptr %pa.addr
  %ld1812 = load ptr, ptr %$f610.addr
  %p.addr = alloca ptr
  store ptr %ld1812, ptr %p.addr
  %ld1813 = load ptr, ptr %$f609.addr
  %h.addr = alloca ptr
  store ptr %ld1813, ptr %h.addr
  %ld1814 = load ptr, ptr %$f608.addr
  %sc.addr = alloca ptr
  store ptr %ld1814, ptr %sc.addr
  %ld1815 = load ptr, ptr %req.addr
  %ld1816 = load ptr, ptr %m.addr
  %ld1817 = load ptr, ptr %sc.addr
  %ld1818 = load ptr, ptr %h.addr
  %ld1819 = load ptr, ptr %p.addr
  %ld1820 = load ptr, ptr %pa.addr
  %ld1821 = load ptr, ptr %q.addr
  %ld1822 = load ptr, ptr %hd.addr
  %ld1823 = load ptr, ptr %bd.addr
  %rc1824 = load i64, ptr %ld1815, align 8
  %uniq1825 = icmp eq i64 %rc1824, 1
  %fbip_slot1826 = alloca ptr
  br i1 %uniq1825, label %fbip_reuse412, label %fbip_fresh413
fbip_reuse412:
  %tgp1827 = getelementptr i8, ptr %ld1815, i64 8
  store i32 0, ptr %tgp1827, align 4
  %fp1828 = getelementptr i8, ptr %ld1815, i64 16
  store ptr %ld1816, ptr %fp1828, align 8
  %fp1829 = getelementptr i8, ptr %ld1815, i64 24
  store ptr %ld1817, ptr %fp1829, align 8
  %fp1830 = getelementptr i8, ptr %ld1815, i64 32
  store ptr %ld1818, ptr %fp1830, align 8
  %fp1831 = getelementptr i8, ptr %ld1815, i64 40
  store ptr %ld1819, ptr %fp1831, align 8
  %fp1832 = getelementptr i8, ptr %ld1815, i64 48
  store ptr %ld1820, ptr %fp1832, align 8
  %fp1833 = getelementptr i8, ptr %ld1815, i64 56
  store ptr %ld1821, ptr %fp1833, align 8
  %fp1834 = getelementptr i8, ptr %ld1815, i64 64
  store ptr %ld1822, ptr %fp1834, align 8
  %fp1835 = getelementptr i8, ptr %ld1815, i64 72
  store ptr %ld1823, ptr %fp1835, align 8
  store ptr %ld1815, ptr %fbip_slot1826
  br label %fbip_merge414
fbip_fresh413:
  call void @march_decrc(ptr %ld1815)
  %hp1836 = call ptr @march_alloc(i64 80)
  %tgp1837 = getelementptr i8, ptr %hp1836, i64 8
  store i32 0, ptr %tgp1837, align 4
  %fp1838 = getelementptr i8, ptr %hp1836, i64 16
  store ptr %ld1816, ptr %fp1838, align 8
  %fp1839 = getelementptr i8, ptr %hp1836, i64 24
  store ptr %ld1817, ptr %fp1839, align 8
  %fp1840 = getelementptr i8, ptr %hp1836, i64 32
  store ptr %ld1818, ptr %fp1840, align 8
  %fp1841 = getelementptr i8, ptr %hp1836, i64 40
  store ptr %ld1819, ptr %fp1841, align 8
  %fp1842 = getelementptr i8, ptr %hp1836, i64 48
  store ptr %ld1820, ptr %fp1842, align 8
  %fp1843 = getelementptr i8, ptr %hp1836, i64 56
  store ptr %ld1821, ptr %fp1843, align 8
  %fp1844 = getelementptr i8, ptr %hp1836, i64 64
  store ptr %ld1822, ptr %fp1844, align 8
  %fp1845 = getelementptr i8, ptr %hp1836, i64 72
  store ptr %ld1823, ptr %fp1845, align 8
  store ptr %hp1836, ptr %fbip_slot1826
  br label %fbip_merge414
fbip_merge414:
  %fbip_r1846 = load ptr, ptr %fbip_slot1826
  store ptr %fbip_r1846, ptr %res_slot1789
  br label %case_merge409
case_default410:
  unreachable
case_merge409:
  %case_r1847 = load ptr, ptr %res_slot1789
  ret ptr %case_r1847
}

define ptr @Http.set_path$Request_String$String(ptr %req.arg, ptr %new_path.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_path.addr = alloca ptr
  store ptr %new_path.arg, ptr %new_path.addr
  %ld1848 = load ptr, ptr %req.addr
  %res_slot1849 = alloca ptr
  %tgp1850 = getelementptr i8, ptr %ld1848, i64 8
  %tag1851 = load i32, ptr %tgp1850, align 4
  switch i32 %tag1851, label %case_default416 [
      i32 0, label %case_br417
  ]
case_br417:
  %fp1852 = getelementptr i8, ptr %ld1848, i64 16
  %fv1853 = load ptr, ptr %fp1852, align 8
  %$f640.addr = alloca ptr
  store ptr %fv1853, ptr %$f640.addr
  %fp1854 = getelementptr i8, ptr %ld1848, i64 24
  %fv1855 = load ptr, ptr %fp1854, align 8
  %$f641.addr = alloca ptr
  store ptr %fv1855, ptr %$f641.addr
  %fp1856 = getelementptr i8, ptr %ld1848, i64 32
  %fv1857 = load ptr, ptr %fp1856, align 8
  %$f642.addr = alloca ptr
  store ptr %fv1857, ptr %$f642.addr
  %fp1858 = getelementptr i8, ptr %ld1848, i64 40
  %fv1859 = load ptr, ptr %fp1858, align 8
  %$f643.addr = alloca ptr
  store ptr %fv1859, ptr %$f643.addr
  %fp1860 = getelementptr i8, ptr %ld1848, i64 48
  %fv1861 = load ptr, ptr %fp1860, align 8
  %$f644.addr = alloca ptr
  store ptr %fv1861, ptr %$f644.addr
  %fp1862 = getelementptr i8, ptr %ld1848, i64 56
  %fv1863 = load ptr, ptr %fp1862, align 8
  %$f645.addr = alloca ptr
  store ptr %fv1863, ptr %$f645.addr
  %fp1864 = getelementptr i8, ptr %ld1848, i64 64
  %fv1865 = load ptr, ptr %fp1864, align 8
  %$f646.addr = alloca ptr
  store ptr %fv1865, ptr %$f646.addr
  %fp1866 = getelementptr i8, ptr %ld1848, i64 72
  %fv1867 = load ptr, ptr %fp1866, align 8
  %$f647.addr = alloca ptr
  store ptr %fv1867, ptr %$f647.addr
  %ld1868 = load ptr, ptr %$f647.addr
  %bd.addr = alloca ptr
  store ptr %ld1868, ptr %bd.addr
  %ld1869 = load ptr, ptr %$f646.addr
  %hd.addr = alloca ptr
  store ptr %ld1869, ptr %hd.addr
  %ld1870 = load ptr, ptr %$f645.addr
  %q.addr = alloca ptr
  store ptr %ld1870, ptr %q.addr
  %ld1871 = load ptr, ptr %$f643.addr
  %p.addr = alloca ptr
  store ptr %ld1871, ptr %p.addr
  %ld1872 = load ptr, ptr %$f642.addr
  %h.addr = alloca ptr
  store ptr %ld1872, ptr %h.addr
  %ld1873 = load ptr, ptr %$f641.addr
  %sc.addr = alloca ptr
  store ptr %ld1873, ptr %sc.addr
  %ld1874 = load ptr, ptr %$f640.addr
  %m.addr = alloca ptr
  store ptr %ld1874, ptr %m.addr
  %ld1875 = load ptr, ptr %req.addr
  %ld1876 = load ptr, ptr %m.addr
  %ld1877 = load ptr, ptr %sc.addr
  %ld1878 = load ptr, ptr %h.addr
  %ld1879 = load ptr, ptr %p.addr
  %ld1880 = load ptr, ptr %new_path.addr
  %ld1881 = load ptr, ptr %q.addr
  %ld1882 = load ptr, ptr %hd.addr
  %ld1883 = load ptr, ptr %bd.addr
  %rc1884 = load i64, ptr %ld1875, align 8
  %uniq1885 = icmp eq i64 %rc1884, 1
  %fbip_slot1886 = alloca ptr
  br i1 %uniq1885, label %fbip_reuse418, label %fbip_fresh419
fbip_reuse418:
  %tgp1887 = getelementptr i8, ptr %ld1875, i64 8
  store i32 0, ptr %tgp1887, align 4
  %fp1888 = getelementptr i8, ptr %ld1875, i64 16
  store ptr %ld1876, ptr %fp1888, align 8
  %fp1889 = getelementptr i8, ptr %ld1875, i64 24
  store ptr %ld1877, ptr %fp1889, align 8
  %fp1890 = getelementptr i8, ptr %ld1875, i64 32
  store ptr %ld1878, ptr %fp1890, align 8
  %fp1891 = getelementptr i8, ptr %ld1875, i64 40
  store ptr %ld1879, ptr %fp1891, align 8
  %fp1892 = getelementptr i8, ptr %ld1875, i64 48
  store ptr %ld1880, ptr %fp1892, align 8
  %fp1893 = getelementptr i8, ptr %ld1875, i64 56
  store ptr %ld1881, ptr %fp1893, align 8
  %fp1894 = getelementptr i8, ptr %ld1875, i64 64
  store ptr %ld1882, ptr %fp1894, align 8
  %fp1895 = getelementptr i8, ptr %ld1875, i64 72
  store ptr %ld1883, ptr %fp1895, align 8
  store ptr %ld1875, ptr %fbip_slot1886
  br label %fbip_merge420
fbip_fresh419:
  call void @march_decrc(ptr %ld1875)
  %hp1896 = call ptr @march_alloc(i64 80)
  %tgp1897 = getelementptr i8, ptr %hp1896, i64 8
  store i32 0, ptr %tgp1897, align 4
  %fp1898 = getelementptr i8, ptr %hp1896, i64 16
  store ptr %ld1876, ptr %fp1898, align 8
  %fp1899 = getelementptr i8, ptr %hp1896, i64 24
  store ptr %ld1877, ptr %fp1899, align 8
  %fp1900 = getelementptr i8, ptr %hp1896, i64 32
  store ptr %ld1878, ptr %fp1900, align 8
  %fp1901 = getelementptr i8, ptr %hp1896, i64 40
  store ptr %ld1879, ptr %fp1901, align 8
  %fp1902 = getelementptr i8, ptr %hp1896, i64 48
  store ptr %ld1880, ptr %fp1902, align 8
  %fp1903 = getelementptr i8, ptr %hp1896, i64 56
  store ptr %ld1881, ptr %fp1903, align 8
  %fp1904 = getelementptr i8, ptr %hp1896, i64 64
  store ptr %ld1882, ptr %fp1904, align 8
  %fp1905 = getelementptr i8, ptr %hp1896, i64 72
  store ptr %ld1883, ptr %fp1905, align 8
  store ptr %hp1896, ptr %fbip_slot1886
  br label %fbip_merge420
fbip_merge420:
  %fbip_r1906 = load ptr, ptr %fbip_slot1886
  store ptr %fbip_r1906, ptr %res_slot1849
  br label %case_merge415
case_default416:
  unreachable
case_merge415:
  %case_r1907 = load ptr, ptr %res_slot1849
  ret ptr %case_r1907
}

define ptr @Http.get_header$Response_V__3336$String(ptr %resp.arg, ptr %name.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld1908 = load ptr, ptr %name.addr
  %cr1909 = call ptr @march_string_to_lowercase(ptr %ld1908)
  %lower_name.addr = alloca ptr
  store ptr %cr1909, ptr %lower_name.addr
  %hp1910 = call ptr @march_alloc(i64 32)
  %tgp1911 = getelementptr i8, ptr %hp1910, i64 8
  store i32 0, ptr %tgp1911, align 4
  %fp1912 = getelementptr i8, ptr %hp1910, i64 16
  store ptr @find$apply$24, ptr %fp1912, align 8
  %ld1913 = load ptr, ptr %lower_name.addr
  %fp1914 = getelementptr i8, ptr %hp1910, i64 24
  store ptr %ld1913, ptr %fp1914, align 8
  %find.addr = alloca ptr
  store ptr %hp1910, ptr %find.addr
  %ld1915 = load ptr, ptr %resp.addr
  %cr1916 = call ptr @Http.response_headers$Response_V__2424(ptr %ld1915)
  %$t684.addr = alloca ptr
  store ptr %cr1916, ptr %$t684.addr
  %ld1917 = load ptr, ptr %find.addr
  %fp1918 = getelementptr i8, ptr %ld1917, i64 16
  %fv1919 = load ptr, ptr %fp1918, align 8
  %ld1920 = load ptr, ptr %$t684.addr
  %cr1921 = call ptr (ptr, ptr) %fv1919(ptr %ld1917, ptr %ld1920)
  ret ptr %cr1921
}

define i64 @Http.response_is_redirect$Response_V__3336(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1922 = load ptr, ptr %resp.addr
  %cr1923 = call ptr @Http.response_status$Response_V__2408(ptr %ld1922)
  %$t677.addr = alloca ptr
  store ptr %cr1923, ptr %$t677.addr
  %ld1924 = load ptr, ptr %$t677.addr
  %s_i27.addr = alloca ptr
  store ptr %ld1924, ptr %s_i27.addr
  %ld1925 = load ptr, ptr %s_i27.addr
  %cr1926 = call i64 @Http.status_code(ptr %ld1925)
  %c_i28.addr = alloca i64
  store i64 %cr1926, ptr %c_i28.addr
  %ld1927 = load i64, ptr %c_i28.addr
  %cmp1928 = icmp sge i64 %ld1927, 300
  %ar1929 = zext i1 %cmp1928 to i64
  %$t537_i29.addr = alloca i64
  store i64 %ar1929, ptr %$t537_i29.addr
  %ld1930 = load i64, ptr %c_i28.addr
  %cmp1931 = icmp slt i64 %ld1930, 400
  %ar1932 = zext i1 %cmp1931 to i64
  %$t538_i30.addr = alloca i64
  store i64 %ar1932, ptr %$t538_i30.addr
  %ld1933 = load i64, ptr %$t537_i29.addr
  %ld1934 = load i64, ptr %$t538_i30.addr
  %ar1935 = and i64 %ld1933, %ld1934
  ret i64 %ar1935
}

define ptr @Http.body$Request_V__2833(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1936 = load ptr, ptr %req.addr
  %res_slot1937 = alloca ptr
  %tgp1938 = getelementptr i8, ptr %ld1936, i64 8
  %tag1939 = load i32, ptr %tgp1938, align 4
  switch i32 %tag1939, label %case_default422 [
      i32 0, label %case_br423
  ]
case_br423:
  %fp1940 = getelementptr i8, ptr %ld1936, i64 16
  %fv1941 = load ptr, ptr %fp1940, align 8
  %$f599.addr = alloca ptr
  store ptr %fv1941, ptr %$f599.addr
  %fp1942 = getelementptr i8, ptr %ld1936, i64 24
  %fv1943 = load ptr, ptr %fp1942, align 8
  %$f600.addr = alloca ptr
  store ptr %fv1943, ptr %$f600.addr
  %fp1944 = getelementptr i8, ptr %ld1936, i64 32
  %fv1945 = load ptr, ptr %fp1944, align 8
  %$f601.addr = alloca ptr
  store ptr %fv1945, ptr %$f601.addr
  %fp1946 = getelementptr i8, ptr %ld1936, i64 40
  %fv1947 = load ptr, ptr %fp1946, align 8
  %$f602.addr = alloca ptr
  store ptr %fv1947, ptr %$f602.addr
  %fp1948 = getelementptr i8, ptr %ld1936, i64 48
  %fv1949 = load ptr, ptr %fp1948, align 8
  %$f603.addr = alloca ptr
  store ptr %fv1949, ptr %$f603.addr
  %fp1950 = getelementptr i8, ptr %ld1936, i64 56
  %fv1951 = load ptr, ptr %fp1950, align 8
  %$f604.addr = alloca ptr
  store ptr %fv1951, ptr %$f604.addr
  %fp1952 = getelementptr i8, ptr %ld1936, i64 64
  %fv1953 = load ptr, ptr %fp1952, align 8
  %$f605.addr = alloca ptr
  store ptr %fv1953, ptr %$f605.addr
  %fp1954 = getelementptr i8, ptr %ld1936, i64 72
  %fv1955 = load ptr, ptr %fp1954, align 8
  %$f606.addr = alloca ptr
  store ptr %fv1955, ptr %$f606.addr
  %freed1956 = call i64 @march_decrc_freed(ptr %ld1936)
  %freed_b1957 = icmp ne i64 %freed1956, 0
  br i1 %freed_b1957, label %br_unique424, label %br_shared425
br_shared425:
  call void @march_incrc(ptr %fv1955)
  call void @march_incrc(ptr %fv1953)
  call void @march_incrc(ptr %fv1951)
  call void @march_incrc(ptr %fv1949)
  call void @march_incrc(ptr %fv1947)
  call void @march_incrc(ptr %fv1945)
  call void @march_incrc(ptr %fv1943)
  call void @march_incrc(ptr %fv1941)
  br label %br_body426
br_unique424:
  br label %br_body426
br_body426:
  %ld1958 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld1958, ptr %b.addr
  %ld1959 = load ptr, ptr %b.addr
  store ptr %ld1959, ptr %res_slot1937
  br label %case_merge421
case_default422:
  unreachable
case_merge421:
  %case_r1960 = load ptr, ptr %res_slot1937
  ret ptr %case_r1960
}

define ptr @Http.headers$Request_V__2831(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1961 = load ptr, ptr %req.addr
  %res_slot1962 = alloca ptr
  %tgp1963 = getelementptr i8, ptr %ld1961, i64 8
  %tag1964 = load i32, ptr %tgp1963, align 4
  switch i32 %tag1964, label %case_default428 [
      i32 0, label %case_br429
  ]
case_br429:
  %fp1965 = getelementptr i8, ptr %ld1961, i64 16
  %fv1966 = load ptr, ptr %fp1965, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1966, ptr %$f591.addr
  %fp1967 = getelementptr i8, ptr %ld1961, i64 24
  %fv1968 = load ptr, ptr %fp1967, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1968, ptr %$f592.addr
  %fp1969 = getelementptr i8, ptr %ld1961, i64 32
  %fv1970 = load ptr, ptr %fp1969, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1970, ptr %$f593.addr
  %fp1971 = getelementptr i8, ptr %ld1961, i64 40
  %fv1972 = load ptr, ptr %fp1971, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1972, ptr %$f594.addr
  %fp1973 = getelementptr i8, ptr %ld1961, i64 48
  %fv1974 = load ptr, ptr %fp1973, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1974, ptr %$f595.addr
  %fp1975 = getelementptr i8, ptr %ld1961, i64 56
  %fv1976 = load ptr, ptr %fp1975, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1976, ptr %$f596.addr
  %fp1977 = getelementptr i8, ptr %ld1961, i64 64
  %fv1978 = load ptr, ptr %fp1977, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1978, ptr %$f597.addr
  %fp1979 = getelementptr i8, ptr %ld1961, i64 72
  %fv1980 = load ptr, ptr %fp1979, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1980, ptr %$f598.addr
  %freed1981 = call i64 @march_decrc_freed(ptr %ld1961)
  %freed_b1982 = icmp ne i64 %freed1981, 0
  br i1 %freed_b1982, label %br_unique430, label %br_shared431
br_shared431:
  call void @march_incrc(ptr %fv1980)
  call void @march_incrc(ptr %fv1978)
  call void @march_incrc(ptr %fv1976)
  call void @march_incrc(ptr %fv1974)
  call void @march_incrc(ptr %fv1972)
  call void @march_incrc(ptr %fv1970)
  call void @march_incrc(ptr %fv1968)
  call void @march_incrc(ptr %fv1966)
  br label %br_body432
br_unique430:
  br label %br_body432
br_body432:
  %ld1983 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1983, ptr %h.addr
  %ld1984 = load ptr, ptr %h.addr
  store ptr %ld1984, ptr %res_slot1962
  br label %case_merge427
case_default428:
  unreachable
case_merge427:
  %case_r1985 = load ptr, ptr %res_slot1962
  ret ptr %case_r1985
}

define ptr @Http.query$Request_V__2829(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1986 = load ptr, ptr %req.addr
  %res_slot1987 = alloca ptr
  %tgp1988 = getelementptr i8, ptr %ld1986, i64 8
  %tag1989 = load i32, ptr %tgp1988, align 4
  switch i32 %tag1989, label %case_default434 [
      i32 0, label %case_br435
  ]
case_br435:
  %fp1990 = getelementptr i8, ptr %ld1986, i64 16
  %fv1991 = load ptr, ptr %fp1990, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1991, ptr %$f583.addr
  %fp1992 = getelementptr i8, ptr %ld1986, i64 24
  %fv1993 = load ptr, ptr %fp1992, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1993, ptr %$f584.addr
  %fp1994 = getelementptr i8, ptr %ld1986, i64 32
  %fv1995 = load ptr, ptr %fp1994, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1995, ptr %$f585.addr
  %fp1996 = getelementptr i8, ptr %ld1986, i64 40
  %fv1997 = load ptr, ptr %fp1996, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1997, ptr %$f586.addr
  %fp1998 = getelementptr i8, ptr %ld1986, i64 48
  %fv1999 = load ptr, ptr %fp1998, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1999, ptr %$f587.addr
  %fp2000 = getelementptr i8, ptr %ld1986, i64 56
  %fv2001 = load ptr, ptr %fp2000, align 8
  %$f588.addr = alloca ptr
  store ptr %fv2001, ptr %$f588.addr
  %fp2002 = getelementptr i8, ptr %ld1986, i64 64
  %fv2003 = load ptr, ptr %fp2002, align 8
  %$f589.addr = alloca ptr
  store ptr %fv2003, ptr %$f589.addr
  %fp2004 = getelementptr i8, ptr %ld1986, i64 72
  %fv2005 = load ptr, ptr %fp2004, align 8
  %$f590.addr = alloca ptr
  store ptr %fv2005, ptr %$f590.addr
  %freed2006 = call i64 @march_decrc_freed(ptr %ld1986)
  %freed_b2007 = icmp ne i64 %freed2006, 0
  br i1 %freed_b2007, label %br_unique436, label %br_shared437
br_shared437:
  call void @march_incrc(ptr %fv2005)
  call void @march_incrc(ptr %fv2003)
  call void @march_incrc(ptr %fv2001)
  call void @march_incrc(ptr %fv1999)
  call void @march_incrc(ptr %fv1997)
  call void @march_incrc(ptr %fv1995)
  call void @march_incrc(ptr %fv1993)
  call void @march_incrc(ptr %fv1991)
  br label %br_body438
br_unique436:
  br label %br_body438
br_body438:
  %ld2008 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld2008, ptr %q.addr
  %ld2009 = load ptr, ptr %q.addr
  store ptr %ld2009, ptr %res_slot1987
  br label %case_merge433
case_default434:
  unreachable
case_merge433:
  %case_r2010 = load ptr, ptr %res_slot1987
  ret ptr %case_r2010
}

define ptr @Http.path$Request_V__2827(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2011 = load ptr, ptr %req.addr
  %res_slot2012 = alloca ptr
  %tgp2013 = getelementptr i8, ptr %ld2011, i64 8
  %tag2014 = load i32, ptr %tgp2013, align 4
  switch i32 %tag2014, label %case_default440 [
      i32 0, label %case_br441
  ]
case_br441:
  %fp2015 = getelementptr i8, ptr %ld2011, i64 16
  %fv2016 = load ptr, ptr %fp2015, align 8
  %$f575.addr = alloca ptr
  store ptr %fv2016, ptr %$f575.addr
  %fp2017 = getelementptr i8, ptr %ld2011, i64 24
  %fv2018 = load ptr, ptr %fp2017, align 8
  %$f576.addr = alloca ptr
  store ptr %fv2018, ptr %$f576.addr
  %fp2019 = getelementptr i8, ptr %ld2011, i64 32
  %fv2020 = load ptr, ptr %fp2019, align 8
  %$f577.addr = alloca ptr
  store ptr %fv2020, ptr %$f577.addr
  %fp2021 = getelementptr i8, ptr %ld2011, i64 40
  %fv2022 = load ptr, ptr %fp2021, align 8
  %$f578.addr = alloca ptr
  store ptr %fv2022, ptr %$f578.addr
  %fp2023 = getelementptr i8, ptr %ld2011, i64 48
  %fv2024 = load ptr, ptr %fp2023, align 8
  %$f579.addr = alloca ptr
  store ptr %fv2024, ptr %$f579.addr
  %fp2025 = getelementptr i8, ptr %ld2011, i64 56
  %fv2026 = load ptr, ptr %fp2025, align 8
  %$f580.addr = alloca ptr
  store ptr %fv2026, ptr %$f580.addr
  %fp2027 = getelementptr i8, ptr %ld2011, i64 64
  %fv2028 = load ptr, ptr %fp2027, align 8
  %$f581.addr = alloca ptr
  store ptr %fv2028, ptr %$f581.addr
  %fp2029 = getelementptr i8, ptr %ld2011, i64 72
  %fv2030 = load ptr, ptr %fp2029, align 8
  %$f582.addr = alloca ptr
  store ptr %fv2030, ptr %$f582.addr
  %freed2031 = call i64 @march_decrc_freed(ptr %ld2011)
  %freed_b2032 = icmp ne i64 %freed2031, 0
  br i1 %freed_b2032, label %br_unique442, label %br_shared443
br_shared443:
  call void @march_incrc(ptr %fv2030)
  call void @march_incrc(ptr %fv2028)
  call void @march_incrc(ptr %fv2026)
  call void @march_incrc(ptr %fv2024)
  call void @march_incrc(ptr %fv2022)
  call void @march_incrc(ptr %fv2020)
  call void @march_incrc(ptr %fv2018)
  call void @march_incrc(ptr %fv2016)
  br label %br_body444
br_unique442:
  br label %br_body444
br_body444:
  %ld2033 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld2033, ptr %p.addr
  %ld2034 = load ptr, ptr %p.addr
  store ptr %ld2034, ptr %res_slot2012
  br label %case_merge439
case_default440:
  unreachable
case_merge439:
  %case_r2035 = load ptr, ptr %res_slot2012
  ret ptr %case_r2035
}

define ptr @Http.method$Request_V__2825(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2036 = load ptr, ptr %req.addr
  %res_slot2037 = alloca ptr
  %tgp2038 = getelementptr i8, ptr %ld2036, i64 8
  %tag2039 = load i32, ptr %tgp2038, align 4
  switch i32 %tag2039, label %case_default446 [
      i32 0, label %case_br447
  ]
case_br447:
  %fp2040 = getelementptr i8, ptr %ld2036, i64 16
  %fv2041 = load ptr, ptr %fp2040, align 8
  %$f543.addr = alloca ptr
  store ptr %fv2041, ptr %$f543.addr
  %fp2042 = getelementptr i8, ptr %ld2036, i64 24
  %fv2043 = load ptr, ptr %fp2042, align 8
  %$f544.addr = alloca ptr
  store ptr %fv2043, ptr %$f544.addr
  %fp2044 = getelementptr i8, ptr %ld2036, i64 32
  %fv2045 = load ptr, ptr %fp2044, align 8
  %$f545.addr = alloca ptr
  store ptr %fv2045, ptr %$f545.addr
  %fp2046 = getelementptr i8, ptr %ld2036, i64 40
  %fv2047 = load ptr, ptr %fp2046, align 8
  %$f546.addr = alloca ptr
  store ptr %fv2047, ptr %$f546.addr
  %fp2048 = getelementptr i8, ptr %ld2036, i64 48
  %fv2049 = load ptr, ptr %fp2048, align 8
  %$f547.addr = alloca ptr
  store ptr %fv2049, ptr %$f547.addr
  %fp2050 = getelementptr i8, ptr %ld2036, i64 56
  %fv2051 = load ptr, ptr %fp2050, align 8
  %$f548.addr = alloca ptr
  store ptr %fv2051, ptr %$f548.addr
  %fp2052 = getelementptr i8, ptr %ld2036, i64 64
  %fv2053 = load ptr, ptr %fp2052, align 8
  %$f549.addr = alloca ptr
  store ptr %fv2053, ptr %$f549.addr
  %fp2054 = getelementptr i8, ptr %ld2036, i64 72
  %fv2055 = load ptr, ptr %fp2054, align 8
  %$f550.addr = alloca ptr
  store ptr %fv2055, ptr %$f550.addr
  %freed2056 = call i64 @march_decrc_freed(ptr %ld2036)
  %freed_b2057 = icmp ne i64 %freed2056, 0
  br i1 %freed_b2057, label %br_unique448, label %br_shared449
br_shared449:
  call void @march_incrc(ptr %fv2055)
  call void @march_incrc(ptr %fv2053)
  call void @march_incrc(ptr %fv2051)
  call void @march_incrc(ptr %fv2049)
  call void @march_incrc(ptr %fv2047)
  call void @march_incrc(ptr %fv2045)
  call void @march_incrc(ptr %fv2043)
  call void @march_incrc(ptr %fv2041)
  br label %br_body450
br_unique448:
  br label %br_body450
br_body450:
  %ld2058 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld2058, ptr %m.addr
  %ld2059 = load ptr, ptr %m.addr
  store ptr %ld2059, ptr %res_slot2037
  br label %case_merge445
case_default446:
  unreachable
case_merge445:
  %case_r2060 = load ptr, ptr %res_slot2037
  ret ptr %case_r2060
}

define ptr @Http.port$Request_V__2818(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2061 = load ptr, ptr %req.addr
  %res_slot2062 = alloca ptr
  %tgp2063 = getelementptr i8, ptr %ld2061, i64 8
  %tag2064 = load i32, ptr %tgp2063, align 4
  switch i32 %tag2064, label %case_default452 [
      i32 0, label %case_br453
  ]
case_br453:
  %fp2065 = getelementptr i8, ptr %ld2061, i64 16
  %fv2066 = load ptr, ptr %fp2065, align 8
  %$f567.addr = alloca ptr
  store ptr %fv2066, ptr %$f567.addr
  %fp2067 = getelementptr i8, ptr %ld2061, i64 24
  %fv2068 = load ptr, ptr %fp2067, align 8
  %$f568.addr = alloca ptr
  store ptr %fv2068, ptr %$f568.addr
  %fp2069 = getelementptr i8, ptr %ld2061, i64 32
  %fv2070 = load ptr, ptr %fp2069, align 8
  %$f569.addr = alloca ptr
  store ptr %fv2070, ptr %$f569.addr
  %fp2071 = getelementptr i8, ptr %ld2061, i64 40
  %fv2072 = load ptr, ptr %fp2071, align 8
  %$f570.addr = alloca ptr
  store ptr %fv2072, ptr %$f570.addr
  %fp2073 = getelementptr i8, ptr %ld2061, i64 48
  %fv2074 = load ptr, ptr %fp2073, align 8
  %$f571.addr = alloca ptr
  store ptr %fv2074, ptr %$f571.addr
  %fp2075 = getelementptr i8, ptr %ld2061, i64 56
  %fv2076 = load ptr, ptr %fp2075, align 8
  %$f572.addr = alloca ptr
  store ptr %fv2076, ptr %$f572.addr
  %fp2077 = getelementptr i8, ptr %ld2061, i64 64
  %fv2078 = load ptr, ptr %fp2077, align 8
  %$f573.addr = alloca ptr
  store ptr %fv2078, ptr %$f573.addr
  %fp2079 = getelementptr i8, ptr %ld2061, i64 72
  %fv2080 = load ptr, ptr %fp2079, align 8
  %$f574.addr = alloca ptr
  store ptr %fv2080, ptr %$f574.addr
  %freed2081 = call i64 @march_decrc_freed(ptr %ld2061)
  %freed_b2082 = icmp ne i64 %freed2081, 0
  br i1 %freed_b2082, label %br_unique454, label %br_shared455
br_shared455:
  call void @march_incrc(ptr %fv2080)
  call void @march_incrc(ptr %fv2078)
  call void @march_incrc(ptr %fv2076)
  call void @march_incrc(ptr %fv2074)
  call void @march_incrc(ptr %fv2072)
  call void @march_incrc(ptr %fv2070)
  call void @march_incrc(ptr %fv2068)
  call void @march_incrc(ptr %fv2066)
  br label %br_body456
br_unique454:
  br label %br_body456
br_body456:
  %ld2083 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld2083, ptr %p.addr
  %ld2084 = load ptr, ptr %p.addr
  store ptr %ld2084, ptr %res_slot2062
  br label %case_merge451
case_default452:
  unreachable
case_merge451:
  %case_r2085 = load ptr, ptr %res_slot2062
  ret ptr %case_r2085
}

define ptr @Http.host$Request_V__2815(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2086 = load ptr, ptr %req.addr
  %res_slot2087 = alloca ptr
  %tgp2088 = getelementptr i8, ptr %ld2086, i64 8
  %tag2089 = load i32, ptr %tgp2088, align 4
  switch i32 %tag2089, label %case_default458 [
      i32 0, label %case_br459
  ]
case_br459:
  %fp2090 = getelementptr i8, ptr %ld2086, i64 16
  %fv2091 = load ptr, ptr %fp2090, align 8
  %$f559.addr = alloca ptr
  store ptr %fv2091, ptr %$f559.addr
  %fp2092 = getelementptr i8, ptr %ld2086, i64 24
  %fv2093 = load ptr, ptr %fp2092, align 8
  %$f560.addr = alloca ptr
  store ptr %fv2093, ptr %$f560.addr
  %fp2094 = getelementptr i8, ptr %ld2086, i64 32
  %fv2095 = load ptr, ptr %fp2094, align 8
  %$f561.addr = alloca ptr
  store ptr %fv2095, ptr %$f561.addr
  %fp2096 = getelementptr i8, ptr %ld2086, i64 40
  %fv2097 = load ptr, ptr %fp2096, align 8
  %$f562.addr = alloca ptr
  store ptr %fv2097, ptr %$f562.addr
  %fp2098 = getelementptr i8, ptr %ld2086, i64 48
  %fv2099 = load ptr, ptr %fp2098, align 8
  %$f563.addr = alloca ptr
  store ptr %fv2099, ptr %$f563.addr
  %fp2100 = getelementptr i8, ptr %ld2086, i64 56
  %fv2101 = load ptr, ptr %fp2100, align 8
  %$f564.addr = alloca ptr
  store ptr %fv2101, ptr %$f564.addr
  %fp2102 = getelementptr i8, ptr %ld2086, i64 64
  %fv2103 = load ptr, ptr %fp2102, align 8
  %$f565.addr = alloca ptr
  store ptr %fv2103, ptr %$f565.addr
  %fp2104 = getelementptr i8, ptr %ld2086, i64 72
  %fv2105 = load ptr, ptr %fp2104, align 8
  %$f566.addr = alloca ptr
  store ptr %fv2105, ptr %$f566.addr
  %freed2106 = call i64 @march_decrc_freed(ptr %ld2086)
  %freed_b2107 = icmp ne i64 %freed2106, 0
  br i1 %freed_b2107, label %br_unique460, label %br_shared461
br_shared461:
  call void @march_incrc(ptr %fv2105)
  call void @march_incrc(ptr %fv2103)
  call void @march_incrc(ptr %fv2101)
  call void @march_incrc(ptr %fv2099)
  call void @march_incrc(ptr %fv2097)
  call void @march_incrc(ptr %fv2095)
  call void @march_incrc(ptr %fv2093)
  call void @march_incrc(ptr %fv2091)
  br label %br_body462
br_unique460:
  br label %br_body462
br_body462:
  %ld2108 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld2108, ptr %h.addr
  %ld2109 = load ptr, ptr %h.addr
  store ptr %ld2109, ptr %res_slot2087
  br label %case_merge457
case_default458:
  unreachable
case_merge457:
  %case_r2110 = load ptr, ptr %res_slot2087
  ret ptr %case_r2110
}

define ptr @Http.set_header$Request_String$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld2111 = load ptr, ptr %req.addr
  %res_slot2112 = alloca ptr
  %tgp2113 = getelementptr i8, ptr %ld2111, i64 8
  %tag2114 = load i32, ptr %tgp2113, align 4
  switch i32 %tag2114, label %case_default464 [
      i32 0, label %case_br465
  ]
case_br465:
  %fp2115 = getelementptr i8, ptr %ld2111, i64 16
  %fv2116 = load ptr, ptr %fp2115, align 8
  %$f658.addr = alloca ptr
  store ptr %fv2116, ptr %$f658.addr
  %fp2117 = getelementptr i8, ptr %ld2111, i64 24
  %fv2118 = load ptr, ptr %fp2117, align 8
  %$f659.addr = alloca ptr
  store ptr %fv2118, ptr %$f659.addr
  %fp2119 = getelementptr i8, ptr %ld2111, i64 32
  %fv2120 = load ptr, ptr %fp2119, align 8
  %$f660.addr = alloca ptr
  store ptr %fv2120, ptr %$f660.addr
  %fp2121 = getelementptr i8, ptr %ld2111, i64 40
  %fv2122 = load ptr, ptr %fp2121, align 8
  %$f661.addr = alloca ptr
  store ptr %fv2122, ptr %$f661.addr
  %fp2123 = getelementptr i8, ptr %ld2111, i64 48
  %fv2124 = load ptr, ptr %fp2123, align 8
  %$f662.addr = alloca ptr
  store ptr %fv2124, ptr %$f662.addr
  %fp2125 = getelementptr i8, ptr %ld2111, i64 56
  %fv2126 = load ptr, ptr %fp2125, align 8
  %$f663.addr = alloca ptr
  store ptr %fv2126, ptr %$f663.addr
  %fp2127 = getelementptr i8, ptr %ld2111, i64 64
  %fv2128 = load ptr, ptr %fp2127, align 8
  %$f664.addr = alloca ptr
  store ptr %fv2128, ptr %$f664.addr
  %fp2129 = getelementptr i8, ptr %ld2111, i64 72
  %fv2130 = load ptr, ptr %fp2129, align 8
  %$f665.addr = alloca ptr
  store ptr %fv2130, ptr %$f665.addr
  %ld2131 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld2131, ptr %bd.addr
  %ld2132 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld2132, ptr %hd.addr
  %ld2133 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld2133, ptr %q.addr
  %ld2134 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld2134, ptr %pa.addr
  %ld2135 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld2135, ptr %p.addr
  %ld2136 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld2136, ptr %h.addr
  %ld2137 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld2137, ptr %sc.addr
  %ld2138 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld2138, ptr %m.addr
  %hp2139 = call ptr @march_alloc(i64 32)
  %tgp2140 = getelementptr i8, ptr %hp2139, i64 8
  store i32 0, ptr %tgp2140, align 4
  %ld2141 = load ptr, ptr %name.addr
  %fp2142 = getelementptr i8, ptr %hp2139, i64 16
  store ptr %ld2141, ptr %fp2142, align 8
  %ld2143 = load ptr, ptr %value.addr
  %fp2144 = getelementptr i8, ptr %hp2139, i64 24
  store ptr %ld2143, ptr %fp2144, align 8
  %$t656.addr = alloca ptr
  store ptr %hp2139, ptr %$t656.addr
  %hp2145 = call ptr @march_alloc(i64 32)
  %tgp2146 = getelementptr i8, ptr %hp2145, i64 8
  store i32 1, ptr %tgp2146, align 4
  %ld2147 = load ptr, ptr %$t656.addr
  %fp2148 = getelementptr i8, ptr %hp2145, i64 16
  store ptr %ld2147, ptr %fp2148, align 8
  %ld2149 = load ptr, ptr %hd.addr
  %fp2150 = getelementptr i8, ptr %hp2145, i64 24
  store ptr %ld2149, ptr %fp2150, align 8
  %$t657.addr = alloca ptr
  store ptr %hp2145, ptr %$t657.addr
  %ld2151 = load ptr, ptr %req.addr
  %ld2152 = load ptr, ptr %m.addr
  %ld2153 = load ptr, ptr %sc.addr
  %ld2154 = load ptr, ptr %h.addr
  %ld2155 = load ptr, ptr %p.addr
  %ld2156 = load ptr, ptr %pa.addr
  %ld2157 = load ptr, ptr %q.addr
  %ld2158 = load ptr, ptr %$t657.addr
  %ld2159 = load ptr, ptr %bd.addr
  %rc2160 = load i64, ptr %ld2151, align 8
  %uniq2161 = icmp eq i64 %rc2160, 1
  %fbip_slot2162 = alloca ptr
  br i1 %uniq2161, label %fbip_reuse466, label %fbip_fresh467
fbip_reuse466:
  %tgp2163 = getelementptr i8, ptr %ld2151, i64 8
  store i32 0, ptr %tgp2163, align 4
  %fp2164 = getelementptr i8, ptr %ld2151, i64 16
  store ptr %ld2152, ptr %fp2164, align 8
  %fp2165 = getelementptr i8, ptr %ld2151, i64 24
  store ptr %ld2153, ptr %fp2165, align 8
  %fp2166 = getelementptr i8, ptr %ld2151, i64 32
  store ptr %ld2154, ptr %fp2166, align 8
  %fp2167 = getelementptr i8, ptr %ld2151, i64 40
  store ptr %ld2155, ptr %fp2167, align 8
  %fp2168 = getelementptr i8, ptr %ld2151, i64 48
  store ptr %ld2156, ptr %fp2168, align 8
  %fp2169 = getelementptr i8, ptr %ld2151, i64 56
  store ptr %ld2157, ptr %fp2169, align 8
  %fp2170 = getelementptr i8, ptr %ld2151, i64 64
  store ptr %ld2158, ptr %fp2170, align 8
  %fp2171 = getelementptr i8, ptr %ld2151, i64 72
  store ptr %ld2159, ptr %fp2171, align 8
  store ptr %ld2151, ptr %fbip_slot2162
  br label %fbip_merge468
fbip_fresh467:
  call void @march_decrc(ptr %ld2151)
  %hp2172 = call ptr @march_alloc(i64 80)
  %tgp2173 = getelementptr i8, ptr %hp2172, i64 8
  store i32 0, ptr %tgp2173, align 4
  %fp2174 = getelementptr i8, ptr %hp2172, i64 16
  store ptr %ld2152, ptr %fp2174, align 8
  %fp2175 = getelementptr i8, ptr %hp2172, i64 24
  store ptr %ld2153, ptr %fp2175, align 8
  %fp2176 = getelementptr i8, ptr %hp2172, i64 32
  store ptr %ld2154, ptr %fp2176, align 8
  %fp2177 = getelementptr i8, ptr %hp2172, i64 40
  store ptr %ld2155, ptr %fp2177, align 8
  %fp2178 = getelementptr i8, ptr %hp2172, i64 48
  store ptr %ld2156, ptr %fp2178, align 8
  %fp2179 = getelementptr i8, ptr %hp2172, i64 56
  store ptr %ld2157, ptr %fp2179, align 8
  %fp2180 = getelementptr i8, ptr %hp2172, i64 64
  store ptr %ld2158, ptr %fp2180, align 8
  %fp2181 = getelementptr i8, ptr %hp2172, i64 72
  store ptr %ld2159, ptr %fp2181, align 8
  store ptr %hp2172, ptr %fbip_slot2162
  br label %fbip_merge468
fbip_merge468:
  %fbip_r2182 = load ptr, ptr %fbip_slot2162
  store ptr %fbip_r2182, ptr %res_slot2112
  br label %case_merge463
case_default464:
  unreachable
case_merge463:
  %case_r2183 = load ptr, ptr %res_slot2112
  ret ptr %case_r2183
}

define ptr @Http.response_headers$Response_V__2424(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2184 = load ptr, ptr %resp.addr
  %res_slot2185 = alloca ptr
  %tgp2186 = getelementptr i8, ptr %ld2184, i64 8
  %tag2187 = load i32, ptr %tgp2186, align 4
  switch i32 %tag2187, label %case_default470 [
      i32 0, label %case_br471
  ]
case_br471:
  %fp2188 = getelementptr i8, ptr %ld2184, i64 16
  %fv2189 = load ptr, ptr %fp2188, align 8
  %$f669.addr = alloca ptr
  store ptr %fv2189, ptr %$f669.addr
  %fp2190 = getelementptr i8, ptr %ld2184, i64 24
  %fv2191 = load ptr, ptr %fp2190, align 8
  %$f670.addr = alloca ptr
  store ptr %fv2191, ptr %$f670.addr
  %fp2192 = getelementptr i8, ptr %ld2184, i64 32
  %fv2193 = load ptr, ptr %fp2192, align 8
  %$f671.addr = alloca ptr
  store ptr %fv2193, ptr %$f671.addr
  %freed2194 = call i64 @march_decrc_freed(ptr %ld2184)
  %freed_b2195 = icmp ne i64 %freed2194, 0
  br i1 %freed_b2195, label %br_unique472, label %br_shared473
br_shared473:
  call void @march_incrc(ptr %fv2193)
  call void @march_incrc(ptr %fv2191)
  call void @march_incrc(ptr %fv2189)
  br label %br_body474
br_unique472:
  br label %br_body474
br_body474:
  %ld2196 = load ptr, ptr %$f670.addr
  %h.addr = alloca ptr
  store ptr %ld2196, ptr %h.addr
  %ld2197 = load ptr, ptr %h.addr
  store ptr %ld2197, ptr %res_slot2185
  br label %case_merge469
case_default470:
  unreachable
case_merge469:
  %case_r2198 = load ptr, ptr %res_slot2185
  ret ptr %case_r2198
}

define ptr @Http.response_status$Response_V__2408(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2199 = load ptr, ptr %resp.addr
  %res_slot2200 = alloca ptr
  %tgp2201 = getelementptr i8, ptr %ld2199, i64 8
  %tag2202 = load i32, ptr %tgp2201, align 4
  switch i32 %tag2202, label %case_default476 [
      i32 0, label %case_br477
  ]
case_br477:
  %fp2203 = getelementptr i8, ptr %ld2199, i64 16
  %fv2204 = load ptr, ptr %fp2203, align 8
  %$f666.addr = alloca ptr
  store ptr %fv2204, ptr %$f666.addr
  %fp2205 = getelementptr i8, ptr %ld2199, i64 24
  %fv2206 = load ptr, ptr %fp2205, align 8
  %$f667.addr = alloca ptr
  store ptr %fv2206, ptr %$f667.addr
  %fp2207 = getelementptr i8, ptr %ld2199, i64 32
  %fv2208 = load ptr, ptr %fp2207, align 8
  %$f668.addr = alloca ptr
  store ptr %fv2208, ptr %$f668.addr
  %freed2209 = call i64 @march_decrc_freed(ptr %ld2199)
  %freed_b2210 = icmp ne i64 %freed2209, 0
  br i1 %freed_b2210, label %br_unique478, label %br_shared479
br_shared479:
  call void @march_incrc(ptr %fv2208)
  call void @march_incrc(ptr %fv2206)
  call void @march_incrc(ptr %fv2204)
  br label %br_body480
br_unique478:
  br label %br_body480
br_body480:
  %ld2211 = load ptr, ptr %$f666.addr
  %s.addr = alloca ptr
  store ptr %ld2211, ptr %s.addr
  %ld2212 = load ptr, ptr %s.addr
  store ptr %ld2212, ptr %res_slot2200
  br label %case_merge475
case_default476:
  unreachable
case_merge475:
  %case_r2213 = load ptr, ptr %res_slot2200
  ret ptr %case_r2213
}

define ptr @find$apply$24(ptr %$clo.arg, ptr %hs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %hs.addr = alloca ptr
  store ptr %hs.arg, ptr %hs.addr
  %ld2214 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2214)
  %ld2215 = load ptr, ptr %$clo.addr
  %find.addr = alloca ptr
  store ptr %ld2215, ptr %find.addr
  %ld2216 = load ptr, ptr %$clo.addr
  %fp2217 = getelementptr i8, ptr %ld2216, i64 24
  %fv2218 = load ptr, ptr %fp2217, align 8
  %lower_name.addr = alloca ptr
  store ptr %fv2218, ptr %lower_name.addr
  %ld2219 = load ptr, ptr %hs.addr
  %res_slot2220 = alloca ptr
  %tgp2221 = getelementptr i8, ptr %ld2219, i64 8
  %tag2222 = load i32, ptr %tgp2221, align 4
  switch i32 %tag2222, label %case_default482 [
      i32 0, label %case_br483
      i32 1, label %case_br484
  ]
case_br483:
  %ld2223 = load ptr, ptr %hs.addr
  call void @march_decrc(ptr %ld2223)
  %hp2224 = call ptr @march_alloc(i64 16)
  %tgp2225 = getelementptr i8, ptr %hp2224, i64 8
  store i32 0, ptr %tgp2225, align 4
  store ptr %hp2224, ptr %res_slot2220
  br label %case_merge481
case_br484:
  %fp2226 = getelementptr i8, ptr %ld2219, i64 16
  %fv2227 = load ptr, ptr %fp2226, align 8
  %$f680.addr = alloca ptr
  store ptr %fv2227, ptr %$f680.addr
  %fp2228 = getelementptr i8, ptr %ld2219, i64 24
  %fv2229 = load ptr, ptr %fp2228, align 8
  %$f681.addr = alloca ptr
  store ptr %fv2229, ptr %$f681.addr
  %freed2230 = call i64 @march_decrc_freed(ptr %ld2219)
  %freed_b2231 = icmp ne i64 %freed2230, 0
  br i1 %freed_b2231, label %br_unique485, label %br_shared486
br_shared486:
  call void @march_incrc(ptr %fv2229)
  call void @march_incrc(ptr %fv2227)
  br label %br_body487
br_unique485:
  br label %br_body487
br_body487:
  %ld2232 = load ptr, ptr %$f680.addr
  %res_slot2233 = alloca ptr
  %tgp2234 = getelementptr i8, ptr %ld2232, i64 8
  %tag2235 = load i32, ptr %tgp2234, align 4
  switch i32 %tag2235, label %case_default489 [
      i32 0, label %case_br490
  ]
case_br490:
  %fp2236 = getelementptr i8, ptr %ld2232, i64 16
  %fv2237 = load ptr, ptr %fp2236, align 8
  %$f682.addr = alloca ptr
  store ptr %fv2237, ptr %$f682.addr
  %fp2238 = getelementptr i8, ptr %ld2232, i64 24
  %fv2239 = load ptr, ptr %fp2238, align 8
  %$f683.addr = alloca ptr
  store ptr %fv2239, ptr %$f683.addr
  %freed2240 = call i64 @march_decrc_freed(ptr %ld2232)
  %freed_b2241 = icmp ne i64 %freed2240, 0
  br i1 %freed_b2241, label %br_unique491, label %br_shared492
br_shared492:
  call void @march_incrc(ptr %fv2239)
  call void @march_incrc(ptr %fv2237)
  br label %br_body493
br_unique491:
  br label %br_body493
br_body493:
  %ld2242 = load ptr, ptr %$f681.addr
  %rest.addr = alloca ptr
  store ptr %ld2242, ptr %rest.addr
  %ld2243 = load ptr, ptr %$f683.addr
  %v.addr = alloca ptr
  store ptr %ld2243, ptr %v.addr
  %ld2244 = load ptr, ptr %$f682.addr
  %n.addr = alloca ptr
  store ptr %ld2244, ptr %n.addr
  %ld2245 = load ptr, ptr %n.addr
  %cr2246 = call ptr @march_string_to_lowercase(ptr %ld2245)
  %$t678.addr = alloca ptr
  store ptr %cr2246, ptr %$t678.addr
  %ld2247 = load ptr, ptr %$t678.addr
  %ld2248 = load ptr, ptr %lower_name.addr
  %cr2249 = call i64 @march_string_eq(ptr %ld2247, ptr %ld2248)
  %$t679.addr = alloca i64
  store i64 %cr2249, ptr %$t679.addr
  %ld2250 = load i64, ptr %$t679.addr
  %res_slot2251 = alloca ptr
  %bi2252 = trunc i64 %ld2250 to i1
  br i1 %bi2252, label %case_br496, label %case_default495
case_br496:
  %hp2253 = call ptr @march_alloc(i64 24)
  %tgp2254 = getelementptr i8, ptr %hp2253, i64 8
  store i32 1, ptr %tgp2254, align 4
  %ld2255 = load ptr, ptr %v.addr
  %fp2256 = getelementptr i8, ptr %hp2253, i64 16
  store ptr %ld2255, ptr %fp2256, align 8
  store ptr %hp2253, ptr %res_slot2251
  br label %case_merge494
case_default495:
  %ld2257 = load ptr, ptr %find.addr
  %fp2258 = getelementptr i8, ptr %ld2257, i64 16
  %fv2259 = load ptr, ptr %fp2258, align 8
  %ld2260 = load ptr, ptr %rest.addr
  %cr2261 = call ptr (ptr, ptr) %fv2259(ptr %ld2257, ptr %ld2260)
  store ptr %cr2261, ptr %res_slot2251
  br label %case_merge494
case_merge494:
  %case_r2262 = load ptr, ptr %res_slot2251
  store ptr %case_r2262, ptr %res_slot2233
  br label %case_merge488
case_default489:
  unreachable
case_merge488:
  %case_r2263 = load ptr, ptr %res_slot2233
  store ptr %case_r2263, ptr %res_slot2220
  br label %case_merge481
case_default482:
  unreachable
case_merge481:
  %case_r2264 = load ptr, ptr %res_slot2220
  ret ptr %case_r2264
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

