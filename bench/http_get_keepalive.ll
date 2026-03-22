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
@.str18 = private unnamed_addr constant [13 x i8] c"keep-alive: \00"
@.str19 = private unnamed_addr constant [6 x i8] c" GETs\00"
@.str20 = private unnamed_addr constant [18 x i8] c"error parsing url\00"
@.str21 = private unnamed_addr constant [1 x i8] c"\00"
@.str22 = private unnamed_addr constant [5 x i8] c"done\00"
@.str23 = private unnamed_addr constant [6 x i8] c"error\00"
@.str24 = private unnamed_addr constant [6 x i8] c"error\00"
@.str25 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str26 = private unnamed_addr constant [4 x i8] c"url\00"
@.str27 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str28 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str29 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str30 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str31 = private unnamed_addr constant [9 x i8] c"location\00"
@.str32 = private unnamed_addr constant [1 x i8] c"\00"
@.str33 = private unnamed_addr constant [1 x i8] c"\00"
@.str34 = private unnamed_addr constant [11 x i8] c"Connection\00"
@.str35 = private unnamed_addr constant [6 x i8] c"close\00"

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

define ptr @march_main() {
entry:
  %n.addr = alloca i64
  store i64 20, ptr %n.addr
  %sl364 = call ptr @march_string_lit(ptr @.str16, i64 22)
  %url.addr = alloca ptr
  store ptr %sl364, ptr %url.addr
  %hp365 = call ptr @march_alloc(i64 16)
  %tgp366 = getelementptr i8, ptr %hp365, i64 8
  store i32 0, ptr %tgp366, align 4
  %$t880_i24.addr = alloca ptr
  store ptr %hp365, ptr %$t880_i24.addr
  %hp367 = call ptr @march_alloc(i64 16)
  %tgp368 = getelementptr i8, ptr %hp367, i64 8
  store i32 0, ptr %tgp368, align 4
  %$t881_i25.addr = alloca ptr
  store ptr %hp367, ptr %$t881_i25.addr
  %hp369 = call ptr @march_alloc(i64 16)
  %tgp370 = getelementptr i8, ptr %hp369, i64 8
  store i32 0, ptr %tgp370, align 4
  %$t882_i26.addr = alloca ptr
  store ptr %hp369, ptr %$t882_i26.addr
  %hp371 = call ptr @march_alloc(i64 64)
  %tgp372 = getelementptr i8, ptr %hp371, i64 8
  store i32 0, ptr %tgp372, align 4
  %ld373 = load ptr, ptr %$t880_i24.addr
  %fp374 = getelementptr i8, ptr %hp371, i64 16
  store ptr %ld373, ptr %fp374, align 8
  %ld375 = load ptr, ptr %$t881_i25.addr
  %fp376 = getelementptr i8, ptr %hp371, i64 24
  store ptr %ld375, ptr %fp376, align 8
  %ld377 = load ptr, ptr %$t882_i26.addr
  %fp378 = getelementptr i8, ptr %hp371, i64 32
  store ptr %ld377, ptr %fp378, align 8
  %fp379 = getelementptr i8, ptr %hp371, i64 40
  store i64 0, ptr %fp379, align 8
  %fp380 = getelementptr i8, ptr %hp371, i64 48
  store i64 0, ptr %fp380, align 8
  %fp381 = getelementptr i8, ptr %hp371, i64 56
  store i64 0, ptr %fp381, align 8
  %client.addr = alloca ptr
  store ptr %hp371, ptr %client.addr
  %ld382 = load ptr, ptr %client.addr
  %sl383 = call ptr @march_string_lit(ptr @.str17, i64 8)
  %cwrap384 = call ptr @march_alloc(i64 24)
  %cwt385 = getelementptr i8, ptr %cwrap384, i64 8
  store i32 0, ptr %cwt385, align 4
  %cwf386 = getelementptr i8, ptr %cwrap384, i64 16
  store ptr @HttpClient.step_default_headers$clo_wrap, ptr %cwf386, align 8
  %cr387 = call ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__5868_Result_Request_V__5867_V__5866(ptr %ld382, ptr %sl383, ptr %cwrap384)
  %client_1.addr = alloca ptr
  store ptr %cr387, ptr %client_1.addr
  %ld388 = load i64, ptr %n.addr
  %cr389 = call ptr @march_int_to_string(i64 %ld388)
  %$t2014.addr = alloca ptr
  store ptr %cr389, ptr %$t2014.addr
  %sl390 = call ptr @march_string_lit(ptr @.str18, i64 12)
  %ld391 = load ptr, ptr %$t2014.addr
  %cr392 = call ptr @march_string_concat(ptr %sl390, ptr %ld391)
  %$t2015.addr = alloca ptr
  store ptr %cr392, ptr %$t2015.addr
  %ld393 = load ptr, ptr %$t2015.addr
  %sl394 = call ptr @march_string_lit(ptr @.str19, i64 5)
  %cr395 = call ptr @march_string_concat(ptr %ld393, ptr %sl394)
  %$t2016.addr = alloca ptr
  store ptr %cr395, ptr %$t2016.addr
  %ld396 = load ptr, ptr %$t2016.addr
  call void @march_print(ptr %ld396)
  %ld397 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld397)
  %ld398 = load ptr, ptr %url.addr
  %url_i23.addr = alloca ptr
  store ptr %ld398, ptr %url_i23.addr
  %ld399 = load ptr, ptr %url_i23.addr
  %cr400 = call ptr @Http.parse_url(ptr %ld399)
  %$t2017.addr = alloca ptr
  store ptr %cr400, ptr %$t2017.addr
  %ld401 = load ptr, ptr %$t2017.addr
  %res_slot402 = alloca ptr
  %tgp403 = getelementptr i8, ptr %ld401, i64 8
  %tag404 = load i32, ptr %tgp403, align 4
  switch i32 %tag404, label %case_default78 [
      i32 1, label %case_br79
      i32 0, label %case_br80
  ]
case_br79:
  %fp405 = getelementptr i8, ptr %ld401, i64 16
  %fv406 = load ptr, ptr %fp405, align 8
  %$f2021.addr = alloca ptr
  store ptr %fv406, ptr %$f2021.addr
  %freed407 = call i64 @march_decrc_freed(ptr %ld401)
  %freed_b408 = icmp ne i64 %freed407, 0
  br i1 %freed_b408, label %br_unique81, label %br_shared82
br_shared82:
  call void @march_incrc(ptr %fv406)
  br label %br_body83
br_unique81:
  br label %br_body83
br_body83:
  %sl409 = call ptr @march_string_lit(ptr @.str20, i64 17)
  call void @march_print(ptr %sl409)
  %cv410 = inttoptr i64 0 to ptr
  store ptr %cv410, ptr %res_slot402
  br label %case_merge77
case_br80:
  %fp411 = getelementptr i8, ptr %ld401, i64 16
  %fv412 = load ptr, ptr %fp411, align 8
  %$f2022.addr = alloca ptr
  store ptr %fv412, ptr %$f2022.addr
  %freed413 = call i64 @march_decrc_freed(ptr %ld401)
  %freed_b414 = icmp ne i64 %freed413, 0
  br i1 %freed_b414, label %br_unique84, label %br_shared85
br_shared85:
  call void @march_incrc(ptr %fv412)
  br label %br_body86
br_unique84:
  br label %br_body86
br_body86:
  %ld415 = load ptr, ptr %$f2022.addr
  %req.addr = alloca ptr
  store ptr %ld415, ptr %req.addr
  %ld416 = load ptr, ptr %req.addr
  %sl417 = call ptr @march_string_lit(ptr @.str21, i64 0)
  %cr418 = call ptr @Http.set_body$Request_T_$String(ptr %ld416, ptr %sl417)
  %req_1.addr = alloca ptr
  store ptr %cr418, ptr %req_1.addr
  %hp419 = call ptr @march_alloc(i64 40)
  %tgp420 = getelementptr i8, ptr %hp419, i64 8
  store i32 0, ptr %tgp420, align 4
  %fp421 = getelementptr i8, ptr %hp419, i64 16
  store ptr @callback$apply$21, ptr %fp421, align 8
  %ld422 = load i64, ptr %n.addr
  %fp423 = getelementptr i8, ptr %hp419, i64 24
  store i64 %ld422, ptr %fp423, align 8
  %ld424 = load ptr, ptr %req_1.addr
  %fp425 = getelementptr i8, ptr %hp419, i64 32
  store ptr %ld424, ptr %fp425, align 8
  %callback.addr = alloca ptr
  store ptr %hp419, ptr %callback.addr
  %ld426 = load ptr, ptr %client_1.addr
  %ld427 = load ptr, ptr %url.addr
  %ld428 = load ptr, ptr %callback.addr
  %cr429 = call ptr @HttpClient.with_connection$Client$String$Fn_Fn_Request_String_Result_Response_V__3283_HttpError_Result_Int_HttpError(ptr %ld426, ptr %ld427, ptr %ld428)
  %$t2018.addr = alloca ptr
  store ptr %cr429, ptr %$t2018.addr
  %ld430 = load ptr, ptr %$t2018.addr
  %res_slot431 = alloca ptr
  %tgp432 = getelementptr i8, ptr %ld430, i64 8
  %tag433 = load i32, ptr %tgp432, align 4
  switch i32 %tag433, label %case_default88 [
      i32 0, label %case_br89
  ]
case_br89:
  %fp434 = getelementptr i8, ptr %ld430, i64 16
  %fv435 = load ptr, ptr %fp434, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv435, ptr %$f2019.addr
  %freed436 = call i64 @march_decrc_freed(ptr %ld430)
  %freed_b437 = icmp ne i64 %freed436, 0
  br i1 %freed_b437, label %br_unique90, label %br_shared91
br_shared91:
  call void @march_incrc(ptr %fv435)
  br label %br_body92
br_unique90:
  br label %br_body92
br_body92:
  %ld438 = load ptr, ptr %$f2019.addr
  %res_slot439 = alloca ptr
  %tgp440 = getelementptr i8, ptr %ld438, i64 8
  %tag441 = load i32, ptr %tgp440, align 4
  switch i32 %tag441, label %case_default94 [
      i32 0, label %case_br95
  ]
case_br95:
  %fp442 = getelementptr i8, ptr %ld438, i64 16
  %fv443 = load ptr, ptr %fp442, align 8
  %$f2020.addr = alloca ptr
  store ptr %fv443, ptr %$f2020.addr
  %freed444 = call i64 @march_decrc_freed(ptr %ld438)
  %freed_b445 = icmp ne i64 %freed444, 0
  br i1 %freed_b445, label %br_unique96, label %br_shared97
br_shared97:
  call void @march_incrc(ptr %fv443)
  br label %br_body98
br_unique96:
  br label %br_body98
br_body98:
  %sl446 = call ptr @march_string_lit(ptr @.str22, i64 4)
  call void @march_print(ptr %sl446)
  %cv447 = inttoptr i64 0 to ptr
  store ptr %cv447, ptr %res_slot439
  br label %case_merge93
case_default94:
  %ld448 = load ptr, ptr %$f2019.addr
  call void @march_decrc(ptr %ld448)
  %sl449 = call ptr @march_string_lit(ptr @.str23, i64 5)
  call void @march_print(ptr %sl449)
  %cv450 = inttoptr i64 0 to ptr
  store ptr %cv450, ptr %res_slot439
  br label %case_merge93
case_merge93:
  %case_r451 = load ptr, ptr %res_slot439
  store ptr %case_r451, ptr %res_slot431
  br label %case_merge87
case_default88:
  %ld452 = load ptr, ptr %$t2018.addr
  call void @march_decrc(ptr %ld452)
  %sl453 = call ptr @march_string_lit(ptr @.str24, i64 5)
  call void @march_print(ptr %sl453)
  %cv454 = inttoptr i64 0 to ptr
  store ptr %cv454, ptr %res_slot431
  br label %case_merge87
case_merge87:
  %case_r455 = load ptr, ptr %res_slot431
  store ptr %case_r455, ptr %res_slot402
  br label %case_merge77
case_default78:
  unreachable
case_merge77:
  %case_r456 = load ptr, ptr %res_slot402
  ret ptr %case_r456
}

define ptr @HttpClient.with_connection$Client$String$Fn_Fn_Request_String_Result_Response_V__3283_HttpError_Result_Int_HttpError(ptr %client.arg, ptr %url.arg, ptr %callback.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld457 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld457)
  %ld458 = load ptr, ptr %url.addr
  %cr459 = call ptr @Http.parse_url(ptr %ld458)
  %$t1058.addr = alloca ptr
  store ptr %cr459, ptr %$t1058.addr
  %ld460 = load ptr, ptr %$t1058.addr
  %res_slot461 = alloca ptr
  %tgp462 = getelementptr i8, ptr %ld460, i64 8
  %tag463 = load i32, ptr %tgp462, align 4
  switch i32 %tag463, label %case_default100 [
      i32 1, label %case_br101
      i32 0, label %case_br102
  ]
case_br101:
  %fp464 = getelementptr i8, ptr %ld460, i64 16
  %fv465 = load ptr, ptr %fp464, align 8
  %$f1071.addr = alloca ptr
  store ptr %fv465, ptr %$f1071.addr
  %sl466 = call ptr @march_string_lit(ptr @.str25, i64 13)
  %ld467 = load ptr, ptr %url.addr
  %cr468 = call ptr @march_string_concat(ptr %sl466, ptr %ld467)
  %$t1059.addr = alloca ptr
  store ptr %cr468, ptr %$t1059.addr
  %hp469 = call ptr @march_alloc(i64 32)
  %tgp470 = getelementptr i8, ptr %hp469, i64 8
  store i32 1, ptr %tgp470, align 4
  %sl471 = call ptr @march_string_lit(ptr @.str26, i64 3)
  %fp472 = getelementptr i8, ptr %hp469, i64 16
  store ptr %sl471, ptr %fp472, align 8
  %ld473 = load ptr, ptr %$t1059.addr
  %fp474 = getelementptr i8, ptr %hp469, i64 24
  store ptr %ld473, ptr %fp474, align 8
  %$t1060.addr = alloca ptr
  store ptr %hp469, ptr %$t1060.addr
  %ld475 = load ptr, ptr %$t1058.addr
  %ld476 = load ptr, ptr %$t1060.addr
  %rc477 = load i64, ptr %ld475, align 8
  %uniq478 = icmp eq i64 %rc477, 1
  %fbip_slot479 = alloca ptr
  br i1 %uniq478, label %fbip_reuse103, label %fbip_fresh104
fbip_reuse103:
  %tgp480 = getelementptr i8, ptr %ld475, i64 8
  store i32 1, ptr %tgp480, align 4
  %fp481 = getelementptr i8, ptr %ld475, i64 16
  store ptr %ld476, ptr %fp481, align 8
  store ptr %ld475, ptr %fbip_slot479
  br label %fbip_merge105
fbip_fresh104:
  call void @march_decrc(ptr %ld475)
  %hp482 = call ptr @march_alloc(i64 24)
  %tgp483 = getelementptr i8, ptr %hp482, i64 8
  store i32 1, ptr %tgp483, align 4
  %fp484 = getelementptr i8, ptr %hp482, i64 16
  store ptr %ld476, ptr %fp484, align 8
  store ptr %hp482, ptr %fbip_slot479
  br label %fbip_merge105
fbip_merge105:
  %fbip_r485 = load ptr, ptr %fbip_slot479
  store ptr %fbip_r485, ptr %res_slot461
  br label %case_merge99
case_br102:
  %fp486 = getelementptr i8, ptr %ld460, i64 16
  %fv487 = load ptr, ptr %fp486, align 8
  %$f1072.addr = alloca ptr
  store ptr %fv487, ptr %$f1072.addr
  %freed488 = call i64 @march_decrc_freed(ptr %ld460)
  %freed_b489 = icmp ne i64 %freed488, 0
  br i1 %freed_b489, label %br_unique106, label %br_shared107
br_shared107:
  call void @march_incrc(ptr %fv487)
  br label %br_body108
br_unique106:
  br label %br_body108
br_body108:
  %ld490 = load ptr, ptr %$f1072.addr
  %base_req.addr = alloca ptr
  store ptr %ld490, ptr %base_req.addr
  %ld491 = load ptr, ptr %base_req.addr
  %cr492 = call ptr @HttpTransport.connect$Request_T_(ptr %ld491)
  %$t1061.addr = alloca ptr
  store ptr %cr492, ptr %$t1061.addr
  %ld493 = load ptr, ptr %$t1061.addr
  %res_slot494 = alloca ptr
  %tgp495 = getelementptr i8, ptr %ld493, i64 8
  %tag496 = load i32, ptr %tgp495, align 4
  switch i32 %tag496, label %case_default110 [
      i32 1, label %case_br111
      i32 0, label %case_br112
  ]
case_br111:
  %fp497 = getelementptr i8, ptr %ld493, i64 16
  %fv498 = load ptr, ptr %fp497, align 8
  %$f1069.addr = alloca ptr
  store ptr %fv498, ptr %$f1069.addr
  %ld499 = load ptr, ptr %$f1069.addr
  %e.addr = alloca ptr
  store ptr %ld499, ptr %e.addr
  %hp500 = call ptr @march_alloc(i64 24)
  %tgp501 = getelementptr i8, ptr %hp500, i64 8
  store i32 0, ptr %tgp501, align 4
  %ld502 = load ptr, ptr %e.addr
  %fp503 = getelementptr i8, ptr %hp500, i64 16
  store ptr %ld502, ptr %fp503, align 8
  %$t1062.addr = alloca ptr
  store ptr %hp500, ptr %$t1062.addr
  %ld504 = load ptr, ptr %$t1061.addr
  %ld505 = load ptr, ptr %$t1062.addr
  %rc506 = load i64, ptr %ld504, align 8
  %uniq507 = icmp eq i64 %rc506, 1
  %fbip_slot508 = alloca ptr
  br i1 %uniq507, label %fbip_reuse113, label %fbip_fresh114
fbip_reuse113:
  %tgp509 = getelementptr i8, ptr %ld504, i64 8
  store i32 1, ptr %tgp509, align 4
  %fp510 = getelementptr i8, ptr %ld504, i64 16
  store ptr %ld505, ptr %fp510, align 8
  store ptr %ld504, ptr %fbip_slot508
  br label %fbip_merge115
fbip_fresh114:
  call void @march_decrc(ptr %ld504)
  %hp511 = call ptr @march_alloc(i64 24)
  %tgp512 = getelementptr i8, ptr %hp511, i64 8
  store i32 1, ptr %tgp512, align 4
  %fp513 = getelementptr i8, ptr %hp511, i64 16
  store ptr %ld505, ptr %fp513, align 8
  store ptr %hp511, ptr %fbip_slot508
  br label %fbip_merge115
fbip_merge115:
  %fbip_r514 = load ptr, ptr %fbip_slot508
  store ptr %fbip_r514, ptr %res_slot494
  br label %case_merge109
case_br112:
  %fp515 = getelementptr i8, ptr %ld493, i64 16
  %fv516 = load ptr, ptr %fp515, align 8
  %$f1070.addr = alloca ptr
  store ptr %fv516, ptr %$f1070.addr
  %freed517 = call i64 @march_decrc_freed(ptr %ld493)
  %freed_b518 = icmp ne i64 %freed517, 0
  br i1 %freed_b518, label %br_unique116, label %br_shared117
br_shared117:
  call void @march_incrc(ptr %fv516)
  br label %br_body118
br_unique116:
  br label %br_body118
br_body118:
  %ld519 = load ptr, ptr %$f1070.addr
  %fd.addr = alloca ptr
  store ptr %ld519, ptr %fd.addr
  %ld520 = load ptr, ptr %client.addr
  %res_slot521 = alloca ptr
  %tgp522 = getelementptr i8, ptr %ld520, i64 8
  %tag523 = load i32, ptr %tgp522, align 4
  switch i32 %tag523, label %case_default120 [
      i32 0, label %case_br121
  ]
case_br121:
  %fp524 = getelementptr i8, ptr %ld520, i64 16
  %fv525 = load ptr, ptr %fp524, align 8
  %$f1063.addr = alloca ptr
  store ptr %fv525, ptr %$f1063.addr
  %fp526 = getelementptr i8, ptr %ld520, i64 24
  %fv527 = load ptr, ptr %fp526, align 8
  %$f1064.addr = alloca ptr
  store ptr %fv527, ptr %$f1064.addr
  %fp528 = getelementptr i8, ptr %ld520, i64 32
  %fv529 = load ptr, ptr %fp528, align 8
  %$f1065.addr = alloca ptr
  store ptr %fv529, ptr %$f1065.addr
  %fp530 = getelementptr i8, ptr %ld520, i64 40
  %fv531 = load i64, ptr %fp530, align 8
  %$f1066.addr = alloca i64
  store i64 %fv531, ptr %$f1066.addr
  %fp532 = getelementptr i8, ptr %ld520, i64 48
  %fv533 = load i64, ptr %fp532, align 8
  %$f1067.addr = alloca i64
  store i64 %fv533, ptr %$f1067.addr
  %fp534 = getelementptr i8, ptr %ld520, i64 56
  %fv535 = load i64, ptr %fp534, align 8
  %$f1068.addr = alloca i64
  store i64 %fv535, ptr %$f1068.addr
  %freed536 = call i64 @march_decrc_freed(ptr %ld520)
  %freed_b537 = icmp ne i64 %freed536, 0
  br i1 %freed_b537, label %br_unique122, label %br_shared123
br_shared123:
  call void @march_incrc(ptr %fv529)
  call void @march_incrc(ptr %fv527)
  call void @march_incrc(ptr %fv525)
  br label %br_body124
br_unique122:
  br label %br_body124
br_body124:
  %ld538 = load i64, ptr %$f1067.addr
  %max_retries.addr = alloca i64
  store i64 %ld538, ptr %max_retries.addr
  %ld539 = load i64, ptr %$f1066.addr
  %max_redir.addr = alloca i64
  store i64 %ld539, ptr %max_redir.addr
  %ld540 = load ptr, ptr %$f1065.addr
  %err_steps.addr = alloca ptr
  store ptr %ld540, ptr %err_steps.addr
  %ld541 = load ptr, ptr %$f1064.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld541, ptr %resp_steps.addr
  %ld542 = load ptr, ptr %$f1063.addr
  %req_steps.addr = alloca ptr
  store ptr %ld542, ptr %req_steps.addr
  %ld543 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld543)
  %hp544 = call ptr @march_alloc(i64 72)
  %tgp545 = getelementptr i8, ptr %hp544, i64 8
  store i32 0, ptr %tgp545, align 4
  %fp546 = getelementptr i8, ptr %hp544, i64 16
  store ptr @do_request$apply$24, ptr %fp546, align 8
  %ld547 = load ptr, ptr %err_steps.addr
  %fp548 = getelementptr i8, ptr %hp544, i64 24
  store ptr %ld547, ptr %fp548, align 8
  %ld549 = load ptr, ptr %fd.addr
  %fp550 = getelementptr i8, ptr %hp544, i64 32
  store ptr %ld549, ptr %fp550, align 8
  %ld551 = load i64, ptr %max_redir.addr
  %fp552 = getelementptr i8, ptr %hp544, i64 40
  store i64 %ld551, ptr %fp552, align 8
  %ld553 = load i64, ptr %max_retries.addr
  %fp554 = getelementptr i8, ptr %hp544, i64 48
  store i64 %ld553, ptr %fp554, align 8
  %ld555 = load ptr, ptr %req_steps.addr
  %fp556 = getelementptr i8, ptr %hp544, i64 56
  store ptr %ld555, ptr %fp556, align 8
  %ld557 = load ptr, ptr %resp_steps.addr
  %fp558 = getelementptr i8, ptr %hp544, i64 64
  store ptr %ld557, ptr %fp558, align 8
  %do_request.addr = alloca ptr
  store ptr %hp544, ptr %do_request.addr
  %ld559 = load ptr, ptr %callback.addr
  %fp560 = getelementptr i8, ptr %ld559, i64 16
  %fv561 = load ptr, ptr %fp560, align 8
  %ld562 = load ptr, ptr %do_request.addr
  %cr563 = call ptr (ptr, ptr) %fv561(ptr %ld559, ptr %ld562)
  %result.addr = alloca ptr
  store ptr %cr563, ptr %result.addr
  %ld564 = load ptr, ptr %tcp_close.addr
  %fp565 = getelementptr i8, ptr %ld564, i64 16
  %fv566 = load ptr, ptr %fp565, align 8
  %ld567 = load ptr, ptr %fd.addr
  %cr568 = call ptr (ptr, ptr) %fv566(ptr %ld564, ptr %ld567)
  %hp569 = call ptr @march_alloc(i64 24)
  %tgp570 = getelementptr i8, ptr %hp569, i64 8
  store i32 0, ptr %tgp570, align 4
  %ld571 = load ptr, ptr %result.addr
  %fp572 = getelementptr i8, ptr %hp569, i64 16
  store ptr %ld571, ptr %fp572, align 8
  store ptr %hp569, ptr %res_slot521
  br label %case_merge119
case_default120:
  unreachable
case_merge119:
  %case_r573 = load ptr, ptr %res_slot521
  store ptr %case_r573, ptr %res_slot494
  br label %case_merge109
case_default110:
  unreachable
case_merge109:
  %case_r574 = load ptr, ptr %res_slot494
  store ptr %case_r574, ptr %res_slot461
  br label %case_merge99
case_default100:
  unreachable
case_merge99:
  %case_r575 = load ptr, ptr %res_slot461
  ret ptr %case_r575
}

define ptr @run_keepalive$Int$Fn_Request_String_Result_V__5883_V__5882$Request_String(i64 %n.arg, ptr %do_request.arg, ptr %req.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %do_request.addr = alloca ptr
  store ptr %do_request.arg, ptr %do_request.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld576 = load i64, ptr %n.addr
  %cmp577 = icmp eq i64 %ld576, 0
  %ar578 = zext i1 %cmp577 to i64
  %$t2009.addr = alloca i64
  store i64 %ar578, ptr %$t2009.addr
  %ld579 = load i64, ptr %$t2009.addr
  %res_slot580 = alloca ptr
  %bi581 = trunc i64 %ld579 to i1
  br i1 %bi581, label %case_br127, label %case_default126
case_br127:
  %hp582 = call ptr @march_alloc(i64 24)
  %tgp583 = getelementptr i8, ptr %hp582, i64 8
  store i32 0, ptr %tgp583, align 4
  %cv584 = inttoptr i64 0 to ptr
  %fp585 = getelementptr i8, ptr %hp582, i64 16
  store ptr %cv584, ptr %fp585, align 8
  store ptr %hp582, ptr %res_slot580
  br label %case_merge125
case_default126:
  %ld586 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld586)
  %ld587 = load ptr, ptr %do_request.addr
  %fp588 = getelementptr i8, ptr %ld587, i64 16
  %fv589 = load ptr, ptr %fp588, align 8
  %ld590 = load ptr, ptr %req.addr
  %cr591 = call ptr (ptr, ptr) %fv589(ptr %ld587, ptr %ld590)
  %$t2010.addr = alloca ptr
  store ptr %cr591, ptr %$t2010.addr
  %ld592 = load ptr, ptr %$t2010.addr
  %res_slot593 = alloca ptr
  %tgp594 = getelementptr i8, ptr %ld592, i64 8
  %tag595 = load i32, ptr %tgp594, align 4
  switch i32 %tag595, label %case_default129 [
      i32 0, label %case_br130
      i32 1, label %case_br131
  ]
case_br130:
  %fp596 = getelementptr i8, ptr %ld592, i64 16
  %fv597 = load ptr, ptr %fp596, align 8
  %$f2012.addr = alloca ptr
  store ptr %fv597, ptr %$f2012.addr
  %freed598 = call i64 @march_decrc_freed(ptr %ld592)
  %freed_b599 = icmp ne i64 %freed598, 0
  br i1 %freed_b599, label %br_unique132, label %br_shared133
br_shared133:
  call void @march_incrc(ptr %fv597)
  br label %br_body134
br_unique132:
  br label %br_body134
br_body134:
  %ld600 = load i64, ptr %n.addr
  %ar601 = sub i64 %ld600, 1
  %$t2011.addr = alloca i64
  store i64 %ar601, ptr %$t2011.addr
  %ld602 = load i64, ptr %$t2011.addr
  %ld603 = load ptr, ptr %do_request.addr
  %ld604 = load ptr, ptr %req.addr
  %cr605 = call ptr @run_keepalive$Int$Fn_Request_String_Result_V__5883_V__5882$Request_String(i64 %ld602, ptr %ld603, ptr %ld604)
  store ptr %cr605, ptr %res_slot593
  br label %case_merge128
case_br131:
  %fp606 = getelementptr i8, ptr %ld592, i64 16
  %fv607 = load ptr, ptr %fp606, align 8
  %$f2013.addr = alloca ptr
  store ptr %fv607, ptr %$f2013.addr
  %ld608 = load ptr, ptr %$f2013.addr
  %e.addr = alloca ptr
  store ptr %ld608, ptr %e.addr
  %ld609 = load ptr, ptr %$t2010.addr
  %ld610 = load ptr, ptr %e.addr
  %rc611 = load i64, ptr %ld609, align 8
  %uniq612 = icmp eq i64 %rc611, 1
  %fbip_slot613 = alloca ptr
  br i1 %uniq612, label %fbip_reuse135, label %fbip_fresh136
fbip_reuse135:
  %tgp614 = getelementptr i8, ptr %ld609, i64 8
  store i32 1, ptr %tgp614, align 4
  %fp615 = getelementptr i8, ptr %ld609, i64 16
  store ptr %ld610, ptr %fp615, align 8
  store ptr %ld609, ptr %fbip_slot613
  br label %fbip_merge137
fbip_fresh136:
  call void @march_decrc(ptr %ld609)
  %hp616 = call ptr @march_alloc(i64 24)
  %tgp617 = getelementptr i8, ptr %hp616, i64 8
  store i32 1, ptr %tgp617, align 4
  %fp618 = getelementptr i8, ptr %hp616, i64 16
  store ptr %ld610, ptr %fp618, align 8
  store ptr %hp616, ptr %fbip_slot613
  br label %fbip_merge137
fbip_merge137:
  %fbip_r619 = load ptr, ptr %fbip_slot613
  store ptr %fbip_r619, ptr %res_slot593
  br label %case_merge128
case_default129:
  unreachable
case_merge128:
  %case_r620 = load ptr, ptr %res_slot593
  store ptr %case_r620, ptr %res_slot580
  br label %case_merge125
case_merge125:
  %case_r621 = load ptr, ptr %res_slot580
  ret ptr %case_r621
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld622 = load ptr, ptr %req.addr
  %res_slot623 = alloca ptr
  %tgp624 = getelementptr i8, ptr %ld622, i64 8
  %tag625 = load i32, ptr %tgp624, align 4
  switch i32 %tag625, label %case_default139 [
      i32 0, label %case_br140
  ]
case_br140:
  %fp626 = getelementptr i8, ptr %ld622, i64 16
  %fv627 = load ptr, ptr %fp626, align 8
  %$f648.addr = alloca ptr
  store ptr %fv627, ptr %$f648.addr
  %fp628 = getelementptr i8, ptr %ld622, i64 24
  %fv629 = load ptr, ptr %fp628, align 8
  %$f649.addr = alloca ptr
  store ptr %fv629, ptr %$f649.addr
  %fp630 = getelementptr i8, ptr %ld622, i64 32
  %fv631 = load ptr, ptr %fp630, align 8
  %$f650.addr = alloca ptr
  store ptr %fv631, ptr %$f650.addr
  %fp632 = getelementptr i8, ptr %ld622, i64 40
  %fv633 = load ptr, ptr %fp632, align 8
  %$f651.addr = alloca ptr
  store ptr %fv633, ptr %$f651.addr
  %fp634 = getelementptr i8, ptr %ld622, i64 48
  %fv635 = load ptr, ptr %fp634, align 8
  %$f652.addr = alloca ptr
  store ptr %fv635, ptr %$f652.addr
  %fp636 = getelementptr i8, ptr %ld622, i64 56
  %fv637 = load ptr, ptr %fp636, align 8
  %$f653.addr = alloca ptr
  store ptr %fv637, ptr %$f653.addr
  %fp638 = getelementptr i8, ptr %ld622, i64 64
  %fv639 = load ptr, ptr %fp638, align 8
  %$f654.addr = alloca ptr
  store ptr %fv639, ptr %$f654.addr
  %fp640 = getelementptr i8, ptr %ld622, i64 72
  %fv641 = load ptr, ptr %fp640, align 8
  %$f655.addr = alloca ptr
  store ptr %fv641, ptr %$f655.addr
  %ld642 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld642, ptr %hd.addr
  %ld643 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld643, ptr %q.addr
  %ld644 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld644, ptr %pa.addr
  %ld645 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld645, ptr %p.addr
  %ld646 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld646, ptr %h.addr
  %ld647 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld647, ptr %sc.addr
  %ld648 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld648, ptr %m.addr
  %ld649 = load ptr, ptr %req.addr
  %ld650 = load ptr, ptr %m.addr
  %ld651 = load ptr, ptr %sc.addr
  %ld652 = load ptr, ptr %h.addr
  %ld653 = load ptr, ptr %p.addr
  %ld654 = load ptr, ptr %pa.addr
  %ld655 = load ptr, ptr %q.addr
  %ld656 = load ptr, ptr %hd.addr
  %ld657 = load ptr, ptr %new_body.addr
  %rc658 = load i64, ptr %ld649, align 8
  %uniq659 = icmp eq i64 %rc658, 1
  %fbip_slot660 = alloca ptr
  br i1 %uniq659, label %fbip_reuse141, label %fbip_fresh142
fbip_reuse141:
  %tgp661 = getelementptr i8, ptr %ld649, i64 8
  store i32 0, ptr %tgp661, align 4
  %fp662 = getelementptr i8, ptr %ld649, i64 16
  store ptr %ld650, ptr %fp662, align 8
  %fp663 = getelementptr i8, ptr %ld649, i64 24
  store ptr %ld651, ptr %fp663, align 8
  %fp664 = getelementptr i8, ptr %ld649, i64 32
  store ptr %ld652, ptr %fp664, align 8
  %fp665 = getelementptr i8, ptr %ld649, i64 40
  store ptr %ld653, ptr %fp665, align 8
  %fp666 = getelementptr i8, ptr %ld649, i64 48
  store ptr %ld654, ptr %fp666, align 8
  %fp667 = getelementptr i8, ptr %ld649, i64 56
  store ptr %ld655, ptr %fp667, align 8
  %fp668 = getelementptr i8, ptr %ld649, i64 64
  store ptr %ld656, ptr %fp668, align 8
  %fp669 = getelementptr i8, ptr %ld649, i64 72
  store ptr %ld657, ptr %fp669, align 8
  store ptr %ld649, ptr %fbip_slot660
  br label %fbip_merge143
fbip_fresh142:
  call void @march_decrc(ptr %ld649)
  %hp670 = call ptr @march_alloc(i64 80)
  %tgp671 = getelementptr i8, ptr %hp670, i64 8
  store i32 0, ptr %tgp671, align 4
  %fp672 = getelementptr i8, ptr %hp670, i64 16
  store ptr %ld650, ptr %fp672, align 8
  %fp673 = getelementptr i8, ptr %hp670, i64 24
  store ptr %ld651, ptr %fp673, align 8
  %fp674 = getelementptr i8, ptr %hp670, i64 32
  store ptr %ld652, ptr %fp674, align 8
  %fp675 = getelementptr i8, ptr %hp670, i64 40
  store ptr %ld653, ptr %fp675, align 8
  %fp676 = getelementptr i8, ptr %hp670, i64 48
  store ptr %ld654, ptr %fp676, align 8
  %fp677 = getelementptr i8, ptr %hp670, i64 56
  store ptr %ld655, ptr %fp677, align 8
  %fp678 = getelementptr i8, ptr %hp670, i64 64
  store ptr %ld656, ptr %fp678, align 8
  %fp679 = getelementptr i8, ptr %hp670, i64 72
  store ptr %ld657, ptr %fp679, align 8
  store ptr %hp670, ptr %fbip_slot660
  br label %fbip_merge143
fbip_merge143:
  %fbip_r680 = load ptr, ptr %fbip_slot660
  store ptr %fbip_r680, ptr %res_slot623
  br label %case_merge138
case_default139:
  unreachable
case_merge138:
  %case_r681 = load ptr, ptr %res_slot623
  ret ptr %case_r681
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld682 = load ptr, ptr %req.addr
  %sl683 = call ptr @march_string_lit(ptr @.str27, i64 10)
  %sl684 = call ptr @march_string_lit(ptr @.str28, i64 9)
  %cr685 = call ptr @Http.set_header$Request_V__3515$String$String(ptr %ld682, ptr %sl683, ptr %sl684)
  %req_1.addr = alloca ptr
  store ptr %cr685, ptr %req_1.addr
  %ld686 = load ptr, ptr %req_1.addr
  %sl687 = call ptr @march_string_lit(ptr @.str29, i64 6)
  %sl688 = call ptr @march_string_lit(ptr @.str30, i64 3)
  %cr689 = call ptr @Http.set_header$Request_V__3517$String$String(ptr %ld686, ptr %sl687, ptr %sl688)
  %req_2.addr = alloca ptr
  store ptr %cr689, ptr %req_2.addr
  %hp690 = call ptr @march_alloc(i64 24)
  %tgp691 = getelementptr i8, ptr %hp690, i64 8
  store i32 0, ptr %tgp691, align 4
  %ld692 = load ptr, ptr %req_2.addr
  %fp693 = getelementptr i8, ptr %hp690, i64 16
  store ptr %ld692, ptr %fp693, align 8
  ret ptr %hp690
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__5868_Result_Request_V__5867_V__5866(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld694 = load ptr, ptr %client.addr
  %res_slot695 = alloca ptr
  %tgp696 = getelementptr i8, ptr %ld694, i64 8
  %tag697 = load i32, ptr %tgp696, align 4
  switch i32 %tag697, label %case_default145 [
      i32 0, label %case_br146
  ]
case_br146:
  %fp698 = getelementptr i8, ptr %ld694, i64 16
  %fv699 = load ptr, ptr %fp698, align 8
  %$f889.addr = alloca ptr
  store ptr %fv699, ptr %$f889.addr
  %fp700 = getelementptr i8, ptr %ld694, i64 24
  %fv701 = load ptr, ptr %fp700, align 8
  %$f890.addr = alloca ptr
  store ptr %fv701, ptr %$f890.addr
  %fp702 = getelementptr i8, ptr %ld694, i64 32
  %fv703 = load ptr, ptr %fp702, align 8
  %$f891.addr = alloca ptr
  store ptr %fv703, ptr %$f891.addr
  %fp704 = getelementptr i8, ptr %ld694, i64 40
  %fv705 = load i64, ptr %fp704, align 8
  %$f892.addr = alloca i64
  store i64 %fv705, ptr %$f892.addr
  %fp706 = getelementptr i8, ptr %ld694, i64 48
  %fv707 = load i64, ptr %fp706, align 8
  %$f893.addr = alloca i64
  store i64 %fv707, ptr %$f893.addr
  %fp708 = getelementptr i8, ptr %ld694, i64 56
  %fv709 = load i64, ptr %fp708, align 8
  %$f894.addr = alloca i64
  store i64 %fv709, ptr %$f894.addr
  %ld710 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld710, ptr %backoff.addr
  %ld711 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld711, ptr %retries.addr
  %ld712 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld712, ptr %redir.addr
  %ld713 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld713, ptr %err_steps.addr
  %ld714 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld714, ptr %resp_steps.addr
  %ld715 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld715, ptr %req_steps.addr
  %hp716 = call ptr @march_alloc(i64 32)
  %tgp717 = getelementptr i8, ptr %hp716, i64 8
  store i32 0, ptr %tgp717, align 4
  %ld718 = load ptr, ptr %name.addr
  %fp719 = getelementptr i8, ptr %hp716, i64 16
  store ptr %ld718, ptr %fp719, align 8
  %ld720 = load ptr, ptr %step.addr
  %fp721 = getelementptr i8, ptr %hp716, i64 24
  store ptr %ld720, ptr %fp721, align 8
  %$t887.addr = alloca ptr
  store ptr %hp716, ptr %$t887.addr
  %ld722 = load ptr, ptr %req_steps.addr
  %ld723 = load ptr, ptr %$t887.addr
  %cr724 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld722, ptr %ld723)
  %$t888.addr = alloca ptr
  store ptr %cr724, ptr %$t888.addr
  %ld725 = load ptr, ptr %client.addr
  %ld726 = load ptr, ptr %$t888.addr
  %ld727 = load ptr, ptr %resp_steps.addr
  %ld728 = load ptr, ptr %err_steps.addr
  %ld729 = load i64, ptr %redir.addr
  %ld730 = load i64, ptr %retries.addr
  %ld731 = load i64, ptr %backoff.addr
  %rc732 = load i64, ptr %ld725, align 8
  %uniq733 = icmp eq i64 %rc732, 1
  %fbip_slot734 = alloca ptr
  br i1 %uniq733, label %fbip_reuse147, label %fbip_fresh148
fbip_reuse147:
  %tgp735 = getelementptr i8, ptr %ld725, i64 8
  store i32 0, ptr %tgp735, align 4
  %fp736 = getelementptr i8, ptr %ld725, i64 16
  store ptr %ld726, ptr %fp736, align 8
  %fp737 = getelementptr i8, ptr %ld725, i64 24
  store ptr %ld727, ptr %fp737, align 8
  %fp738 = getelementptr i8, ptr %ld725, i64 32
  store ptr %ld728, ptr %fp738, align 8
  %fp739 = getelementptr i8, ptr %ld725, i64 40
  store i64 %ld729, ptr %fp739, align 8
  %fp740 = getelementptr i8, ptr %ld725, i64 48
  store i64 %ld730, ptr %fp740, align 8
  %fp741 = getelementptr i8, ptr %ld725, i64 56
  store i64 %ld731, ptr %fp741, align 8
  store ptr %ld725, ptr %fbip_slot734
  br label %fbip_merge149
fbip_fresh148:
  call void @march_decrc(ptr %ld725)
  %hp742 = call ptr @march_alloc(i64 64)
  %tgp743 = getelementptr i8, ptr %hp742, i64 8
  store i32 0, ptr %tgp743, align 4
  %fp744 = getelementptr i8, ptr %hp742, i64 16
  store ptr %ld726, ptr %fp744, align 8
  %fp745 = getelementptr i8, ptr %hp742, i64 24
  store ptr %ld727, ptr %fp745, align 8
  %fp746 = getelementptr i8, ptr %hp742, i64 32
  store ptr %ld728, ptr %fp746, align 8
  %fp747 = getelementptr i8, ptr %hp742, i64 40
  store i64 %ld729, ptr %fp747, align 8
  %fp748 = getelementptr i8, ptr %hp742, i64 48
  store i64 %ld730, ptr %fp748, align 8
  %fp749 = getelementptr i8, ptr %hp742, i64 56
  store i64 %ld731, ptr %fp749, align 8
  store ptr %hp742, ptr %fbip_slot734
  br label %fbip_merge149
fbip_merge149:
  %fbip_r750 = load ptr, ptr %fbip_slot734
  store ptr %fbip_r750, ptr %res_slot695
  br label %case_merge144
case_default145:
  unreachable
case_merge144:
  %case_r751 = load ptr, ptr %res_slot695
  ret ptr %case_r751
}

define ptr @HttpClient.run_on_fd$V__3281$List_RequestStepEntry$List_ResponseStepEntry$List_ErrorStepEntry$Int$Int$Request_String(ptr %fd.arg, ptr %req_steps.arg, ptr %resp_steps.arg, ptr %err_steps.arg, i64 %max_redir.arg, i64 %max_retries.arg, ptr %req.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req_steps.addr = alloca ptr
  store ptr %req_steps.arg, ptr %req_steps.addr
  %resp_steps.addr = alloca ptr
  store ptr %resp_steps.arg, ptr %resp_steps.addr
  %err_steps.addr = alloca ptr
  store ptr %err_steps.arg, ptr %err_steps.addr
  %max_redir.addr = alloca i64
  store i64 %max_redir.arg, ptr %max_redir.addr
  %max_retries.addr = alloca i64
  store i64 %max_retries.arg, ptr %max_retries.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld752 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld752)
  %ld753 = load ptr, ptr %req_steps.addr
  %ld754 = load ptr, ptr %req.addr
  %cr755 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld753, ptr %ld754)
  %$t1019.addr = alloca ptr
  store ptr %cr755, ptr %$t1019.addr
  %ld756 = load ptr, ptr %$t1019.addr
  %res_slot757 = alloca ptr
  %tgp758 = getelementptr i8, ptr %ld756, i64 8
  %tag759 = load i32, ptr %tgp758, align 4
  switch i32 %tag759, label %case_default151 [
      i32 1, label %case_br152
      i32 0, label %case_br153
  ]
case_br152:
  %fp760 = getelementptr i8, ptr %ld756, i64 16
  %fv761 = load ptr, ptr %fp760, align 8
  %$f1035.addr = alloca ptr
  store ptr %fv761, ptr %$f1035.addr
  %freed762 = call i64 @march_decrc_freed(ptr %ld756)
  %freed_b763 = icmp ne i64 %freed762, 0
  br i1 %freed_b763, label %br_unique154, label %br_shared155
br_shared155:
  call void @march_incrc(ptr %fv761)
  br label %br_body156
br_unique154:
  br label %br_body156
br_body156:
  %ld764 = load ptr, ptr %$f1035.addr
  %e.addr = alloca ptr
  store ptr %ld764, ptr %e.addr
  %ld765 = load ptr, ptr %err_steps.addr
  %ld766 = load ptr, ptr %req.addr
  %ld767 = load ptr, ptr %e.addr
  %cr768 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld765, ptr %ld766, ptr %ld767)
  store ptr %cr768, ptr %res_slot757
  br label %case_merge150
case_br153:
  %fp769 = getelementptr i8, ptr %ld756, i64 16
  %fv770 = load ptr, ptr %fp769, align 8
  %$f1036.addr = alloca ptr
  store ptr %fv770, ptr %$f1036.addr
  %freed771 = call i64 @march_decrc_freed(ptr %ld756)
  %freed_b772 = icmp ne i64 %freed771, 0
  br i1 %freed_b772, label %br_unique157, label %br_shared158
br_shared158:
  call void @march_incrc(ptr %fv770)
  br label %br_body159
br_unique157:
  br label %br_body159
br_body159:
  %ld773 = load ptr, ptr %$f1036.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld773, ptr %transformed_req.addr
  %ld774 = load i64, ptr %max_retries.addr
  %ar775 = add i64 %ld774, 1
  %$t1020.addr = alloca i64
  store i64 %ar775, ptr %$t1020.addr
  %ld776 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld776)
  %ld777 = load ptr, ptr %fd.addr
  %ld778 = load ptr, ptr %transformed_req.addr
  %ld779 = load i64, ptr %$t1020.addr
  %cr780 = call ptr @HttpClient.transport_keepalive$V__3281$Request_String$Int(ptr %ld777, ptr %ld778, i64 %ld779)
  %$t1021.addr = alloca ptr
  store ptr %cr780, ptr %$t1021.addr
  %ld781 = load ptr, ptr %$t1021.addr
  %res_slot782 = alloca ptr
  %tgp783 = getelementptr i8, ptr %ld781, i64 8
  %tag784 = load i32, ptr %tgp783, align 4
  switch i32 %tag784, label %case_default161 [
      i32 1, label %case_br162
      i32 0, label %case_br163
  ]
case_br162:
  %fp785 = getelementptr i8, ptr %ld781, i64 16
  %fv786 = load ptr, ptr %fp785, align 8
  %$f1031.addr = alloca ptr
  store ptr %fv786, ptr %$f1031.addr
  %freed787 = call i64 @march_decrc_freed(ptr %ld781)
  %freed_b788 = icmp ne i64 %freed787, 0
  br i1 %freed_b788, label %br_unique164, label %br_shared165
br_shared165:
  call void @march_incrc(ptr %fv786)
  br label %br_body166
br_unique164:
  br label %br_body166
br_body166:
  %ld789 = load ptr, ptr %$f1031.addr
  %transport_err.addr = alloca ptr
  store ptr %ld789, ptr %transport_err.addr
  %hp790 = call ptr @march_alloc(i64 24)
  %tgp791 = getelementptr i8, ptr %hp790, i64 8
  store i32 0, ptr %tgp791, align 4
  %ld792 = load ptr, ptr %transport_err.addr
  %fp793 = getelementptr i8, ptr %hp790, i64 16
  store ptr %ld792, ptr %fp793, align 8
  %$t1022.addr = alloca ptr
  store ptr %hp790, ptr %$t1022.addr
  %ld794 = load ptr, ptr %err_steps.addr
  %ld795 = load ptr, ptr %transformed_req.addr
  %ld796 = load ptr, ptr %$t1022.addr
  %cr797 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld794, ptr %ld795, ptr %ld796)
  store ptr %cr797, ptr %res_slot782
  br label %case_merge160
case_br163:
  %fp798 = getelementptr i8, ptr %ld781, i64 16
  %fv799 = load ptr, ptr %fp798, align 8
  %$f1032.addr = alloca ptr
  store ptr %fv799, ptr %$f1032.addr
  %freed800 = call i64 @march_decrc_freed(ptr %ld781)
  %freed_b801 = icmp ne i64 %freed800, 0
  br i1 %freed_b801, label %br_unique167, label %br_shared168
br_shared168:
  call void @march_incrc(ptr %fv799)
  br label %br_body169
br_unique167:
  br label %br_body169
br_body169:
  %ld802 = load ptr, ptr %$f1032.addr
  %res_slot803 = alloca ptr
  %tgp804 = getelementptr i8, ptr %ld802, i64 8
  %tag805 = load i32, ptr %tgp804, align 4
  switch i32 %tag805, label %case_default171 [
      i32 0, label %case_br172
  ]
case_br172:
  %fp806 = getelementptr i8, ptr %ld802, i64 16
  %fv807 = load ptr, ptr %fp806, align 8
  %$f1033.addr = alloca ptr
  store ptr %fv807, ptr %$f1033.addr
  %fp808 = getelementptr i8, ptr %ld802, i64 24
  %fv809 = load ptr, ptr %fp808, align 8
  %$f1034.addr = alloca ptr
  store ptr %fv809, ptr %$f1034.addr
  %freed810 = call i64 @march_decrc_freed(ptr %ld802)
  %freed_b811 = icmp ne i64 %freed810, 0
  br i1 %freed_b811, label %br_unique173, label %br_shared174
br_shared174:
  call void @march_incrc(ptr %fv809)
  call void @march_incrc(ptr %fv807)
  br label %br_body175
br_unique173:
  br label %br_body175
br_body175:
  %ld812 = load ptr, ptr %$f1034.addr
  %resp.addr = alloca ptr
  store ptr %ld812, ptr %resp.addr
  %ld813 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld813)
  %ld814 = load ptr, ptr %transformed_req.addr
  %ld815 = load ptr, ptr %resp.addr
  %ld816 = load i64, ptr %max_redir.addr
  %cr817 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3283$Int$Int(ptr %ld814, ptr %ld815, i64 %ld816, i64 0)
  %$t1023.addr = alloca ptr
  store ptr %cr817, ptr %$t1023.addr
  %ld818 = load ptr, ptr %$t1023.addr
  %res_slot819 = alloca ptr
  %tgp820 = getelementptr i8, ptr %ld818, i64 8
  %tag821 = load i32, ptr %tgp820, align 4
  switch i32 %tag821, label %case_default177 [
      i32 1, label %case_br178
      i32 0, label %case_br179
  ]
case_br178:
  %fp822 = getelementptr i8, ptr %ld818, i64 16
  %fv823 = load ptr, ptr %fp822, align 8
  %$f1029.addr = alloca ptr
  store ptr %fv823, ptr %$f1029.addr
  %freed824 = call i64 @march_decrc_freed(ptr %ld818)
  %freed_b825 = icmp ne i64 %freed824, 0
  br i1 %freed_b825, label %br_unique180, label %br_shared181
br_shared181:
  call void @march_incrc(ptr %fv823)
  br label %br_body182
br_unique180:
  br label %br_body182
br_body182:
  %ld826 = load ptr, ptr %$f1029.addr
  %e_1.addr = alloca ptr
  store ptr %ld826, ptr %e_1.addr
  %ld827 = load ptr, ptr %err_steps.addr
  %ld828 = load ptr, ptr %transformed_req.addr
  %ld829 = load ptr, ptr %e_1.addr
  %cr830 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld827, ptr %ld828, ptr %ld829)
  store ptr %cr830, ptr %res_slot819
  br label %case_merge176
case_br179:
  %fp831 = getelementptr i8, ptr %ld818, i64 16
  %fv832 = load ptr, ptr %fp831, align 8
  %$f1030.addr = alloca ptr
  store ptr %fv832, ptr %$f1030.addr
  %freed833 = call i64 @march_decrc_freed(ptr %ld818)
  %freed_b834 = icmp ne i64 %freed833, 0
  br i1 %freed_b834, label %br_unique183, label %br_shared184
br_shared184:
  call void @march_incrc(ptr %fv832)
  br label %br_body185
br_unique183:
  br label %br_body185
br_body185:
  %ld835 = load ptr, ptr %$f1030.addr
  %final_resp.addr = alloca ptr
  store ptr %ld835, ptr %final_resp.addr
  %ld836 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld836)
  %ld837 = load ptr, ptr %resp_steps.addr
  %ld838 = load ptr, ptr %transformed_req.addr
  %ld839 = load ptr, ptr %final_resp.addr
  %cr840 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3283(ptr %ld837, ptr %ld838, ptr %ld839)
  %$t1024.addr = alloca ptr
  store ptr %cr840, ptr %$t1024.addr
  %ld841 = load ptr, ptr %$t1024.addr
  %res_slot842 = alloca ptr
  %tgp843 = getelementptr i8, ptr %ld841, i64 8
  %tag844 = load i32, ptr %tgp843, align 4
  switch i32 %tag844, label %case_default187 [
      i32 1, label %case_br188
      i32 0, label %case_br189
  ]
case_br188:
  %fp845 = getelementptr i8, ptr %ld841, i64 16
  %fv846 = load ptr, ptr %fp845, align 8
  %$f1025.addr = alloca ptr
  store ptr %fv846, ptr %$f1025.addr
  %freed847 = call i64 @march_decrc_freed(ptr %ld841)
  %freed_b848 = icmp ne i64 %freed847, 0
  br i1 %freed_b848, label %br_unique190, label %br_shared191
br_shared191:
  call void @march_incrc(ptr %fv846)
  br label %br_body192
br_unique190:
  br label %br_body192
br_body192:
  %ld849 = load ptr, ptr %$f1025.addr
  %e_2.addr = alloca ptr
  store ptr %ld849, ptr %e_2.addr
  %ld850 = load ptr, ptr %err_steps.addr
  %ld851 = load ptr, ptr %transformed_req.addr
  %ld852 = load ptr, ptr %e_2.addr
  %cr853 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld850, ptr %ld851, ptr %ld852)
  store ptr %cr853, ptr %res_slot842
  br label %case_merge186
case_br189:
  %fp854 = getelementptr i8, ptr %ld841, i64 16
  %fv855 = load ptr, ptr %fp854, align 8
  %$f1026.addr = alloca ptr
  store ptr %fv855, ptr %$f1026.addr
  %freed856 = call i64 @march_decrc_freed(ptr %ld841)
  %freed_b857 = icmp ne i64 %freed856, 0
  br i1 %freed_b857, label %br_unique193, label %br_shared194
br_shared194:
  call void @march_incrc(ptr %fv855)
  br label %br_body195
br_unique193:
  br label %br_body195
br_body195:
  %ld858 = load ptr, ptr %$f1026.addr
  %res_slot859 = alloca ptr
  %tgp860 = getelementptr i8, ptr %ld858, i64 8
  %tag861 = load i32, ptr %tgp860, align 4
  switch i32 %tag861, label %case_default197 [
      i32 0, label %case_br198
  ]
case_br198:
  %fp862 = getelementptr i8, ptr %ld858, i64 16
  %fv863 = load ptr, ptr %fp862, align 8
  %$f1027.addr = alloca ptr
  store ptr %fv863, ptr %$f1027.addr
  %fp864 = getelementptr i8, ptr %ld858, i64 24
  %fv865 = load ptr, ptr %fp864, align 8
  %$f1028.addr = alloca ptr
  store ptr %fv865, ptr %$f1028.addr
  %freed866 = call i64 @march_decrc_freed(ptr %ld858)
  %freed_b867 = icmp ne i64 %freed866, 0
  br i1 %freed_b867, label %br_unique199, label %br_shared200
br_shared200:
  call void @march_incrc(ptr %fv865)
  call void @march_incrc(ptr %fv863)
  br label %br_body201
br_unique199:
  br label %br_body201
br_body201:
  %ld868 = load ptr, ptr %$f1028.addr
  %response.addr = alloca ptr
  store ptr %ld868, ptr %response.addr
  %hp869 = call ptr @march_alloc(i64 24)
  %tgp870 = getelementptr i8, ptr %hp869, i64 8
  store i32 0, ptr %tgp870, align 4
  %ld871 = load ptr, ptr %response.addr
  %fp872 = getelementptr i8, ptr %hp869, i64 16
  store ptr %ld871, ptr %fp872, align 8
  store ptr %hp869, ptr %res_slot859
  br label %case_merge196
case_default197:
  unreachable
case_merge196:
  %case_r873 = load ptr, ptr %res_slot859
  store ptr %case_r873, ptr %res_slot842
  br label %case_merge186
case_default187:
  unreachable
case_merge186:
  %case_r874 = load ptr, ptr %res_slot842
  store ptr %case_r874, ptr %res_slot819
  br label %case_merge176
case_default177:
  unreachable
case_merge176:
  %case_r875 = load ptr, ptr %res_slot819
  store ptr %case_r875, ptr %res_slot803
  br label %case_merge170
case_default171:
  unreachable
case_merge170:
  %case_r876 = load ptr, ptr %res_slot803
  store ptr %case_r876, ptr %res_slot782
  br label %case_merge160
case_default161:
  unreachable
case_merge160:
  %case_r877 = load ptr, ptr %res_slot782
  store ptr %case_r877, ptr %res_slot757
  br label %case_merge150
case_default151:
  unreachable
case_merge150:
  %case_r878 = load ptr, ptr %res_slot757
  ret ptr %case_r878
}

define ptr @HttpTransport.connect$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld879 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld879)
  %ld880 = load ptr, ptr %req.addr
  %cr881 = call ptr @Http.host$Request_T_(ptr %ld880)
  %req_host.addr = alloca ptr
  store ptr %cr881, ptr %req_host.addr
  %ld882 = load ptr, ptr %req.addr
  %cr883 = call ptr @Http.port$Request_T_(ptr %ld882)
  %$t777.addr = alloca ptr
  store ptr %cr883, ptr %$t777.addr
  %ld884 = load ptr, ptr %$t777.addr
  %res_slot885 = alloca ptr
  %tgp886 = getelementptr i8, ptr %ld884, i64 8
  %tag887 = load i32, ptr %tgp886, align 4
  switch i32 %tag887, label %case_default203 [
      i32 1, label %case_br204
      i32 0, label %case_br205
  ]
case_br204:
  %fp888 = getelementptr i8, ptr %ld884, i64 16
  %fv889 = load ptr, ptr %fp888, align 8
  %$f778.addr = alloca ptr
  store ptr %fv889, ptr %$f778.addr
  %ld890 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld890)
  %ld891 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld891, ptr %p.addr
  %ld892 = load ptr, ptr %p.addr
  store ptr %ld892, ptr %res_slot885
  br label %case_merge202
case_br205:
  %ld893 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld893)
  %cv894 = inttoptr i64 80 to ptr
  store ptr %cv894, ptr %res_slot885
  br label %case_merge202
case_default203:
  unreachable
case_merge202:
  %case_r895 = load ptr, ptr %res_slot885
  %cv896 = ptrtoint ptr %case_r895 to i64
  %req_port.addr = alloca i64
  store i64 %cv896, ptr %req_port.addr
  %ld897 = load ptr, ptr %tcp_connect.addr
  %fp898 = getelementptr i8, ptr %ld897, i64 16
  %fv899 = load ptr, ptr %fp898, align 8
  %ld900 = load ptr, ptr %req_host.addr
  %ld901 = load i64, ptr %req_port.addr
  %cv902 = inttoptr i64 %ld901 to ptr
  %cr903 = call ptr (ptr, ptr, ptr) %fv899(ptr %ld897, ptr %ld900, ptr %cv902)
  %$t779.addr = alloca ptr
  store ptr %cr903, ptr %$t779.addr
  %ld904 = load ptr, ptr %$t779.addr
  %res_slot905 = alloca ptr
  %tgp906 = getelementptr i8, ptr %ld904, i64 8
  %tag907 = load i32, ptr %tgp906, align 4
  switch i32 %tag907, label %case_default207 [
      i32 0, label %case_br208
      i32 0, label %case_br209
  ]
case_br208:
  %fp908 = getelementptr i8, ptr %ld904, i64 16
  %fv909 = load ptr, ptr %fp908, align 8
  %$f781.addr = alloca ptr
  store ptr %fv909, ptr %$f781.addr
  %freed910 = call i64 @march_decrc_freed(ptr %ld904)
  %freed_b911 = icmp ne i64 %freed910, 0
  br i1 %freed_b911, label %br_unique210, label %br_shared211
br_shared211:
  call void @march_incrc(ptr %fv909)
  br label %br_body212
br_unique210:
  br label %br_body212
br_body212:
  %ld912 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld912, ptr %msg.addr
  %hp913 = call ptr @march_alloc(i64 24)
  %tgp914 = getelementptr i8, ptr %hp913, i64 8
  store i32 0, ptr %tgp914, align 4
  %ld915 = load ptr, ptr %msg.addr
  %fp916 = getelementptr i8, ptr %hp913, i64 16
  store ptr %ld915, ptr %fp916, align 8
  %$t780.addr = alloca ptr
  store ptr %hp913, ptr %$t780.addr
  %hp917 = call ptr @march_alloc(i64 24)
  %tgp918 = getelementptr i8, ptr %hp917, i64 8
  store i32 1, ptr %tgp918, align 4
  %ld919 = load ptr, ptr %$t780.addr
  %fp920 = getelementptr i8, ptr %hp917, i64 16
  store ptr %ld919, ptr %fp920, align 8
  store ptr %hp917, ptr %res_slot905
  br label %case_merge206
case_br209:
  %fp921 = getelementptr i8, ptr %ld904, i64 16
  %fv922 = load ptr, ptr %fp921, align 8
  %$f782.addr = alloca ptr
  store ptr %fv922, ptr %$f782.addr
  %freed923 = call i64 @march_decrc_freed(ptr %ld904)
  %freed_b924 = icmp ne i64 %freed923, 0
  br i1 %freed_b924, label %br_unique213, label %br_shared214
br_shared214:
  call void @march_incrc(ptr %fv922)
  br label %br_body215
br_unique213:
  br label %br_body215
br_body215:
  %ld925 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld925, ptr %fd.addr
  %hp926 = call ptr @march_alloc(i64 24)
  %tgp927 = getelementptr i8, ptr %hp926, i64 8
  store i32 0, ptr %tgp927, align 4
  %ld928 = load ptr, ptr %fd.addr
  %fp929 = getelementptr i8, ptr %hp926, i64 16
  store ptr %ld928, ptr %fp929, align 8
  store ptr %hp926, ptr %res_slot905
  br label %case_merge206
case_default207:
  unreachable
case_merge206:
  %case_r930 = load ptr, ptr %res_slot905
  ret ptr %case_r930
}

define ptr @Http.set_header$Request_V__3517$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld931 = load ptr, ptr %req.addr
  %res_slot932 = alloca ptr
  %tgp933 = getelementptr i8, ptr %ld931, i64 8
  %tag934 = load i32, ptr %tgp933, align 4
  switch i32 %tag934, label %case_default217 [
      i32 0, label %case_br218
  ]
case_br218:
  %fp935 = getelementptr i8, ptr %ld931, i64 16
  %fv936 = load ptr, ptr %fp935, align 8
  %$f658.addr = alloca ptr
  store ptr %fv936, ptr %$f658.addr
  %fp937 = getelementptr i8, ptr %ld931, i64 24
  %fv938 = load ptr, ptr %fp937, align 8
  %$f659.addr = alloca ptr
  store ptr %fv938, ptr %$f659.addr
  %fp939 = getelementptr i8, ptr %ld931, i64 32
  %fv940 = load ptr, ptr %fp939, align 8
  %$f660.addr = alloca ptr
  store ptr %fv940, ptr %$f660.addr
  %fp941 = getelementptr i8, ptr %ld931, i64 40
  %fv942 = load ptr, ptr %fp941, align 8
  %$f661.addr = alloca ptr
  store ptr %fv942, ptr %$f661.addr
  %fp943 = getelementptr i8, ptr %ld931, i64 48
  %fv944 = load ptr, ptr %fp943, align 8
  %$f662.addr = alloca ptr
  store ptr %fv944, ptr %$f662.addr
  %fp945 = getelementptr i8, ptr %ld931, i64 56
  %fv946 = load ptr, ptr %fp945, align 8
  %$f663.addr = alloca ptr
  store ptr %fv946, ptr %$f663.addr
  %fp947 = getelementptr i8, ptr %ld931, i64 64
  %fv948 = load ptr, ptr %fp947, align 8
  %$f664.addr = alloca ptr
  store ptr %fv948, ptr %$f664.addr
  %fp949 = getelementptr i8, ptr %ld931, i64 72
  %fv950 = load ptr, ptr %fp949, align 8
  %$f665.addr = alloca ptr
  store ptr %fv950, ptr %$f665.addr
  %ld951 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld951, ptr %bd.addr
  %ld952 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld952, ptr %hd.addr
  %ld953 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld953, ptr %q.addr
  %ld954 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld954, ptr %pa.addr
  %ld955 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld955, ptr %p.addr
  %ld956 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld956, ptr %h.addr
  %ld957 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld957, ptr %sc.addr
  %ld958 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld958, ptr %m.addr
  %hp959 = call ptr @march_alloc(i64 32)
  %tgp960 = getelementptr i8, ptr %hp959, i64 8
  store i32 0, ptr %tgp960, align 4
  %ld961 = load ptr, ptr %name.addr
  %fp962 = getelementptr i8, ptr %hp959, i64 16
  store ptr %ld961, ptr %fp962, align 8
  %ld963 = load ptr, ptr %value.addr
  %fp964 = getelementptr i8, ptr %hp959, i64 24
  store ptr %ld963, ptr %fp964, align 8
  %$t656.addr = alloca ptr
  store ptr %hp959, ptr %$t656.addr
  %hp965 = call ptr @march_alloc(i64 32)
  %tgp966 = getelementptr i8, ptr %hp965, i64 8
  store i32 1, ptr %tgp966, align 4
  %ld967 = load ptr, ptr %$t656.addr
  %fp968 = getelementptr i8, ptr %hp965, i64 16
  store ptr %ld967, ptr %fp968, align 8
  %ld969 = load ptr, ptr %hd.addr
  %fp970 = getelementptr i8, ptr %hp965, i64 24
  store ptr %ld969, ptr %fp970, align 8
  %$t657.addr = alloca ptr
  store ptr %hp965, ptr %$t657.addr
  %ld971 = load ptr, ptr %req.addr
  %ld972 = load ptr, ptr %m.addr
  %ld973 = load ptr, ptr %sc.addr
  %ld974 = load ptr, ptr %h.addr
  %ld975 = load ptr, ptr %p.addr
  %ld976 = load ptr, ptr %pa.addr
  %ld977 = load ptr, ptr %q.addr
  %ld978 = load ptr, ptr %$t657.addr
  %ld979 = load ptr, ptr %bd.addr
  %rc980 = load i64, ptr %ld971, align 8
  %uniq981 = icmp eq i64 %rc980, 1
  %fbip_slot982 = alloca ptr
  br i1 %uniq981, label %fbip_reuse219, label %fbip_fresh220
fbip_reuse219:
  %tgp983 = getelementptr i8, ptr %ld971, i64 8
  store i32 0, ptr %tgp983, align 4
  %fp984 = getelementptr i8, ptr %ld971, i64 16
  store ptr %ld972, ptr %fp984, align 8
  %fp985 = getelementptr i8, ptr %ld971, i64 24
  store ptr %ld973, ptr %fp985, align 8
  %fp986 = getelementptr i8, ptr %ld971, i64 32
  store ptr %ld974, ptr %fp986, align 8
  %fp987 = getelementptr i8, ptr %ld971, i64 40
  store ptr %ld975, ptr %fp987, align 8
  %fp988 = getelementptr i8, ptr %ld971, i64 48
  store ptr %ld976, ptr %fp988, align 8
  %fp989 = getelementptr i8, ptr %ld971, i64 56
  store ptr %ld977, ptr %fp989, align 8
  %fp990 = getelementptr i8, ptr %ld971, i64 64
  store ptr %ld978, ptr %fp990, align 8
  %fp991 = getelementptr i8, ptr %ld971, i64 72
  store ptr %ld979, ptr %fp991, align 8
  store ptr %ld971, ptr %fbip_slot982
  br label %fbip_merge221
fbip_fresh220:
  call void @march_decrc(ptr %ld971)
  %hp992 = call ptr @march_alloc(i64 80)
  %tgp993 = getelementptr i8, ptr %hp992, i64 8
  store i32 0, ptr %tgp993, align 4
  %fp994 = getelementptr i8, ptr %hp992, i64 16
  store ptr %ld972, ptr %fp994, align 8
  %fp995 = getelementptr i8, ptr %hp992, i64 24
  store ptr %ld973, ptr %fp995, align 8
  %fp996 = getelementptr i8, ptr %hp992, i64 32
  store ptr %ld974, ptr %fp996, align 8
  %fp997 = getelementptr i8, ptr %hp992, i64 40
  store ptr %ld975, ptr %fp997, align 8
  %fp998 = getelementptr i8, ptr %hp992, i64 48
  store ptr %ld976, ptr %fp998, align 8
  %fp999 = getelementptr i8, ptr %hp992, i64 56
  store ptr %ld977, ptr %fp999, align 8
  %fp1000 = getelementptr i8, ptr %hp992, i64 64
  store ptr %ld978, ptr %fp1000, align 8
  %fp1001 = getelementptr i8, ptr %hp992, i64 72
  store ptr %ld979, ptr %fp1001, align 8
  store ptr %hp992, ptr %fbip_slot982
  br label %fbip_merge221
fbip_merge221:
  %fbip_r1002 = load ptr, ptr %fbip_slot982
  store ptr %fbip_r1002, ptr %res_slot932
  br label %case_merge216
case_default217:
  unreachable
case_merge216:
  %case_r1003 = load ptr, ptr %res_slot932
  ret ptr %case_r1003
}

define ptr @Http.set_header$Request_V__3515$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1004 = load ptr, ptr %req.addr
  %res_slot1005 = alloca ptr
  %tgp1006 = getelementptr i8, ptr %ld1004, i64 8
  %tag1007 = load i32, ptr %tgp1006, align 4
  switch i32 %tag1007, label %case_default223 [
      i32 0, label %case_br224
  ]
case_br224:
  %fp1008 = getelementptr i8, ptr %ld1004, i64 16
  %fv1009 = load ptr, ptr %fp1008, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1009, ptr %$f658.addr
  %fp1010 = getelementptr i8, ptr %ld1004, i64 24
  %fv1011 = load ptr, ptr %fp1010, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1011, ptr %$f659.addr
  %fp1012 = getelementptr i8, ptr %ld1004, i64 32
  %fv1013 = load ptr, ptr %fp1012, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1013, ptr %$f660.addr
  %fp1014 = getelementptr i8, ptr %ld1004, i64 40
  %fv1015 = load ptr, ptr %fp1014, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1015, ptr %$f661.addr
  %fp1016 = getelementptr i8, ptr %ld1004, i64 48
  %fv1017 = load ptr, ptr %fp1016, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1017, ptr %$f662.addr
  %fp1018 = getelementptr i8, ptr %ld1004, i64 56
  %fv1019 = load ptr, ptr %fp1018, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1019, ptr %$f663.addr
  %fp1020 = getelementptr i8, ptr %ld1004, i64 64
  %fv1021 = load ptr, ptr %fp1020, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1021, ptr %$f664.addr
  %fp1022 = getelementptr i8, ptr %ld1004, i64 72
  %fv1023 = load ptr, ptr %fp1022, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1023, ptr %$f665.addr
  %ld1024 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1024, ptr %bd.addr
  %ld1025 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1025, ptr %hd.addr
  %ld1026 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1026, ptr %q.addr
  %ld1027 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1027, ptr %pa.addr
  %ld1028 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1028, ptr %p.addr
  %ld1029 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1029, ptr %h.addr
  %ld1030 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1030, ptr %sc.addr
  %ld1031 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1031, ptr %m.addr
  %hp1032 = call ptr @march_alloc(i64 32)
  %tgp1033 = getelementptr i8, ptr %hp1032, i64 8
  store i32 0, ptr %tgp1033, align 4
  %ld1034 = load ptr, ptr %name.addr
  %fp1035 = getelementptr i8, ptr %hp1032, i64 16
  store ptr %ld1034, ptr %fp1035, align 8
  %ld1036 = load ptr, ptr %value.addr
  %fp1037 = getelementptr i8, ptr %hp1032, i64 24
  store ptr %ld1036, ptr %fp1037, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1032, ptr %$t656.addr
  %hp1038 = call ptr @march_alloc(i64 32)
  %tgp1039 = getelementptr i8, ptr %hp1038, i64 8
  store i32 1, ptr %tgp1039, align 4
  %ld1040 = load ptr, ptr %$t656.addr
  %fp1041 = getelementptr i8, ptr %hp1038, i64 16
  store ptr %ld1040, ptr %fp1041, align 8
  %ld1042 = load ptr, ptr %hd.addr
  %fp1043 = getelementptr i8, ptr %hp1038, i64 24
  store ptr %ld1042, ptr %fp1043, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1038, ptr %$t657.addr
  %ld1044 = load ptr, ptr %req.addr
  %ld1045 = load ptr, ptr %m.addr
  %ld1046 = load ptr, ptr %sc.addr
  %ld1047 = load ptr, ptr %h.addr
  %ld1048 = load ptr, ptr %p.addr
  %ld1049 = load ptr, ptr %pa.addr
  %ld1050 = load ptr, ptr %q.addr
  %ld1051 = load ptr, ptr %$t657.addr
  %ld1052 = load ptr, ptr %bd.addr
  %rc1053 = load i64, ptr %ld1044, align 8
  %uniq1054 = icmp eq i64 %rc1053, 1
  %fbip_slot1055 = alloca ptr
  br i1 %uniq1054, label %fbip_reuse225, label %fbip_fresh226
fbip_reuse225:
  %tgp1056 = getelementptr i8, ptr %ld1044, i64 8
  store i32 0, ptr %tgp1056, align 4
  %fp1057 = getelementptr i8, ptr %ld1044, i64 16
  store ptr %ld1045, ptr %fp1057, align 8
  %fp1058 = getelementptr i8, ptr %ld1044, i64 24
  store ptr %ld1046, ptr %fp1058, align 8
  %fp1059 = getelementptr i8, ptr %ld1044, i64 32
  store ptr %ld1047, ptr %fp1059, align 8
  %fp1060 = getelementptr i8, ptr %ld1044, i64 40
  store ptr %ld1048, ptr %fp1060, align 8
  %fp1061 = getelementptr i8, ptr %ld1044, i64 48
  store ptr %ld1049, ptr %fp1061, align 8
  %fp1062 = getelementptr i8, ptr %ld1044, i64 56
  store ptr %ld1050, ptr %fp1062, align 8
  %fp1063 = getelementptr i8, ptr %ld1044, i64 64
  store ptr %ld1051, ptr %fp1063, align 8
  %fp1064 = getelementptr i8, ptr %ld1044, i64 72
  store ptr %ld1052, ptr %fp1064, align 8
  store ptr %ld1044, ptr %fbip_slot1055
  br label %fbip_merge227
fbip_fresh226:
  call void @march_decrc(ptr %ld1044)
  %hp1065 = call ptr @march_alloc(i64 80)
  %tgp1066 = getelementptr i8, ptr %hp1065, i64 8
  store i32 0, ptr %tgp1066, align 4
  %fp1067 = getelementptr i8, ptr %hp1065, i64 16
  store ptr %ld1045, ptr %fp1067, align 8
  %fp1068 = getelementptr i8, ptr %hp1065, i64 24
  store ptr %ld1046, ptr %fp1068, align 8
  %fp1069 = getelementptr i8, ptr %hp1065, i64 32
  store ptr %ld1047, ptr %fp1069, align 8
  %fp1070 = getelementptr i8, ptr %hp1065, i64 40
  store ptr %ld1048, ptr %fp1070, align 8
  %fp1071 = getelementptr i8, ptr %hp1065, i64 48
  store ptr %ld1049, ptr %fp1071, align 8
  %fp1072 = getelementptr i8, ptr %hp1065, i64 56
  store ptr %ld1050, ptr %fp1072, align 8
  %fp1073 = getelementptr i8, ptr %hp1065, i64 64
  store ptr %ld1051, ptr %fp1073, align 8
  %fp1074 = getelementptr i8, ptr %hp1065, i64 72
  store ptr %ld1052, ptr %fp1074, align 8
  store ptr %hp1065, ptr %fbip_slot1055
  br label %fbip_merge227
fbip_merge227:
  %fbip_r1075 = load ptr, ptr %fbip_slot1055
  store ptr %fbip_r1075, ptr %res_slot1005
  br label %case_merge222
case_default223:
  unreachable
case_merge222:
  %case_r1076 = load ptr, ptr %res_slot1005
  ret ptr %case_r1076
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld1077 = load ptr, ptr %xs.addr
  %res_slot1078 = alloca ptr
  %tgp1079 = getelementptr i8, ptr %ld1077, i64 8
  %tag1080 = load i32, ptr %tgp1079, align 4
  switch i32 %tag1080, label %case_default229 [
      i32 0, label %case_br230
      i32 1, label %case_br231
  ]
case_br230:
  %ld1081 = load ptr, ptr %xs.addr
  %rc1082 = load i64, ptr %ld1081, align 8
  %uniq1083 = icmp eq i64 %rc1082, 1
  %fbip_slot1084 = alloca ptr
  br i1 %uniq1083, label %fbip_reuse232, label %fbip_fresh233
fbip_reuse232:
  %tgp1085 = getelementptr i8, ptr %ld1081, i64 8
  store i32 0, ptr %tgp1085, align 4
  store ptr %ld1081, ptr %fbip_slot1084
  br label %fbip_merge234
fbip_fresh233:
  call void @march_decrc(ptr %ld1081)
  %hp1086 = call ptr @march_alloc(i64 16)
  %tgp1087 = getelementptr i8, ptr %hp1086, i64 8
  store i32 0, ptr %tgp1087, align 4
  store ptr %hp1086, ptr %fbip_slot1084
  br label %fbip_merge234
fbip_merge234:
  %fbip_r1088 = load ptr, ptr %fbip_slot1084
  %$t883.addr = alloca ptr
  store ptr %fbip_r1088, ptr %$t883.addr
  %hp1089 = call ptr @march_alloc(i64 32)
  %tgp1090 = getelementptr i8, ptr %hp1089, i64 8
  store i32 1, ptr %tgp1090, align 4
  %ld1091 = load ptr, ptr %x.addr
  %fp1092 = getelementptr i8, ptr %hp1089, i64 16
  store ptr %ld1091, ptr %fp1092, align 8
  %ld1093 = load ptr, ptr %$t883.addr
  %fp1094 = getelementptr i8, ptr %hp1089, i64 24
  store ptr %ld1093, ptr %fp1094, align 8
  store ptr %hp1089, ptr %res_slot1078
  br label %case_merge228
case_br231:
  %fp1095 = getelementptr i8, ptr %ld1077, i64 16
  %fv1096 = load ptr, ptr %fp1095, align 8
  %$f885.addr = alloca ptr
  store ptr %fv1096, ptr %$f885.addr
  %fp1097 = getelementptr i8, ptr %ld1077, i64 24
  %fv1098 = load ptr, ptr %fp1097, align 8
  %$f886.addr = alloca ptr
  store ptr %fv1098, ptr %$f886.addr
  %ld1099 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld1099, ptr %t.addr
  %ld1100 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld1100, ptr %h.addr
  %ld1101 = load ptr, ptr %t.addr
  %ld1102 = load ptr, ptr %x.addr
  %cr1103 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld1101, ptr %ld1102)
  %$t884.addr = alloca ptr
  store ptr %cr1103, ptr %$t884.addr
  %ld1104 = load ptr, ptr %xs.addr
  %ld1105 = load ptr, ptr %h.addr
  %ld1106 = load ptr, ptr %$t884.addr
  %rc1107 = load i64, ptr %ld1104, align 8
  %uniq1108 = icmp eq i64 %rc1107, 1
  %fbip_slot1109 = alloca ptr
  br i1 %uniq1108, label %fbip_reuse235, label %fbip_fresh236
fbip_reuse235:
  %tgp1110 = getelementptr i8, ptr %ld1104, i64 8
  store i32 1, ptr %tgp1110, align 4
  %fp1111 = getelementptr i8, ptr %ld1104, i64 16
  store ptr %ld1105, ptr %fp1111, align 8
  %fp1112 = getelementptr i8, ptr %ld1104, i64 24
  store ptr %ld1106, ptr %fp1112, align 8
  store ptr %ld1104, ptr %fbip_slot1109
  br label %fbip_merge237
fbip_fresh236:
  call void @march_decrc(ptr %ld1104)
  %hp1113 = call ptr @march_alloc(i64 32)
  %tgp1114 = getelementptr i8, ptr %hp1113, i64 8
  store i32 1, ptr %tgp1114, align 4
  %fp1115 = getelementptr i8, ptr %hp1113, i64 16
  store ptr %ld1105, ptr %fp1115, align 8
  %fp1116 = getelementptr i8, ptr %hp1113, i64 24
  store ptr %ld1106, ptr %fp1116, align 8
  store ptr %hp1113, ptr %fbip_slot1109
  br label %fbip_merge237
fbip_merge237:
  %fbip_r1117 = load ptr, ptr %fbip_slot1109
  store ptr %fbip_r1117, ptr %res_slot1078
  br label %case_merge228
case_default229:
  unreachable
case_merge228:
  %case_r1118 = load ptr, ptr %res_slot1078
  ret ptr %case_r1118
}

define ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %steps.arg, ptr %req.arg, ptr %err.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %err.addr = alloca ptr
  store ptr %err.arg, ptr %err.addr
  %ld1119 = load ptr, ptr %steps.addr
  %res_slot1120 = alloca ptr
  %tgp1121 = getelementptr i8, ptr %ld1119, i64 8
  %tag1122 = load i32, ptr %tgp1121, align 4
  switch i32 %tag1122, label %case_default239 [
      i32 0, label %case_br240
      i32 1, label %case_br241
  ]
case_br240:
  %ld1123 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1123)
  %hp1124 = call ptr @march_alloc(i64 24)
  %tgp1125 = getelementptr i8, ptr %hp1124, i64 8
  store i32 1, ptr %tgp1125, align 4
  %ld1126 = load ptr, ptr %err.addr
  %fp1127 = getelementptr i8, ptr %hp1124, i64 16
  store ptr %ld1126, ptr %fp1127, align 8
  store ptr %hp1124, ptr %res_slot1120
  br label %case_merge238
case_br241:
  %fp1128 = getelementptr i8, ptr %ld1119, i64 16
  %fv1129 = load ptr, ptr %fp1128, align 8
  %$f974.addr = alloca ptr
  store ptr %fv1129, ptr %$f974.addr
  %fp1130 = getelementptr i8, ptr %ld1119, i64 24
  %fv1131 = load ptr, ptr %fp1130, align 8
  %$f975.addr = alloca ptr
  store ptr %fv1131, ptr %$f975.addr
  %freed1132 = call i64 @march_decrc_freed(ptr %ld1119)
  %freed_b1133 = icmp ne i64 %freed1132, 0
  br i1 %freed_b1133, label %br_unique242, label %br_shared243
br_shared243:
  call void @march_incrc(ptr %fv1131)
  call void @march_incrc(ptr %fv1129)
  br label %br_body244
br_unique242:
  br label %br_body244
br_body244:
  %ld1134 = load ptr, ptr %$f974.addr
  %res_slot1135 = alloca ptr
  %tgp1136 = getelementptr i8, ptr %ld1134, i64 8
  %tag1137 = load i32, ptr %tgp1136, align 4
  switch i32 %tag1137, label %case_default246 [
      i32 0, label %case_br247
  ]
case_br247:
  %fp1138 = getelementptr i8, ptr %ld1134, i64 16
  %fv1139 = load ptr, ptr %fp1138, align 8
  %$f976.addr = alloca ptr
  store ptr %fv1139, ptr %$f976.addr
  %fp1140 = getelementptr i8, ptr %ld1134, i64 24
  %fv1141 = load ptr, ptr %fp1140, align 8
  %$f977.addr = alloca ptr
  store ptr %fv1141, ptr %$f977.addr
  %freed1142 = call i64 @march_decrc_freed(ptr %ld1134)
  %freed_b1143 = icmp ne i64 %freed1142, 0
  br i1 %freed_b1143, label %br_unique248, label %br_shared249
br_shared249:
  call void @march_incrc(ptr %fv1141)
  call void @march_incrc(ptr %fv1139)
  br label %br_body250
br_unique248:
  br label %br_body250
br_body250:
  %ld1144 = load ptr, ptr %$f975.addr
  %rest.addr = alloca ptr
  store ptr %ld1144, ptr %rest.addr
  %ld1145 = load ptr, ptr %$f977.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1145, ptr %step_fn.addr
  %ld1146 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1146)
  %ld1147 = load ptr, ptr %step_fn.addr
  %fp1148 = getelementptr i8, ptr %ld1147, i64 16
  %fv1149 = load ptr, ptr %fp1148, align 8
  %ld1150 = load ptr, ptr %req.addr
  %ld1151 = load ptr, ptr %err.addr
  %cr1152 = call ptr (ptr, ptr, ptr) %fv1149(ptr %ld1147, ptr %ld1150, ptr %ld1151)
  %$t971.addr = alloca ptr
  store ptr %cr1152, ptr %$t971.addr
  %ld1153 = load ptr, ptr %$t971.addr
  %res_slot1154 = alloca ptr
  %tgp1155 = getelementptr i8, ptr %ld1153, i64 8
  %tag1156 = load i32, ptr %tgp1155, align 4
  switch i32 %tag1156, label %case_default252 [
      i32 0, label %case_br253
      i32 1, label %case_br254
  ]
case_br253:
  %fp1157 = getelementptr i8, ptr %ld1153, i64 16
  %fv1158 = load ptr, ptr %fp1157, align 8
  %$f972.addr = alloca ptr
  store ptr %fv1158, ptr %$f972.addr
  %freed1159 = call i64 @march_decrc_freed(ptr %ld1153)
  %freed_b1160 = icmp ne i64 %freed1159, 0
  br i1 %freed_b1160, label %br_unique255, label %br_shared256
br_shared256:
  call void @march_incrc(ptr %fv1158)
  br label %br_body257
br_unique255:
  br label %br_body257
br_body257:
  %ld1161 = load ptr, ptr %$f972.addr
  %resp.addr = alloca ptr
  store ptr %ld1161, ptr %resp.addr
  %hp1162 = call ptr @march_alloc(i64 24)
  %tgp1163 = getelementptr i8, ptr %hp1162, i64 8
  store i32 0, ptr %tgp1163, align 4
  %ld1164 = load ptr, ptr %resp.addr
  %fp1165 = getelementptr i8, ptr %hp1162, i64 16
  store ptr %ld1164, ptr %fp1165, align 8
  store ptr %hp1162, ptr %res_slot1154
  br label %case_merge251
case_br254:
  %fp1166 = getelementptr i8, ptr %ld1153, i64 16
  %fv1167 = load ptr, ptr %fp1166, align 8
  %$f973.addr = alloca ptr
  store ptr %fv1167, ptr %$f973.addr
  %freed1168 = call i64 @march_decrc_freed(ptr %ld1153)
  %freed_b1169 = icmp ne i64 %freed1168, 0
  br i1 %freed_b1169, label %br_unique258, label %br_shared259
br_shared259:
  call void @march_incrc(ptr %fv1167)
  br label %br_body260
br_unique258:
  br label %br_body260
br_body260:
  %ld1170 = load ptr, ptr %$f973.addr
  %new_err.addr = alloca ptr
  store ptr %ld1170, ptr %new_err.addr
  %ld1171 = load ptr, ptr %rest.addr
  %ld1172 = load ptr, ptr %req.addr
  %ld1173 = load ptr, ptr %new_err.addr
  %cr1174 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1171, ptr %ld1172, ptr %ld1173)
  store ptr %cr1174, ptr %res_slot1154
  br label %case_merge251
case_default252:
  unreachable
case_merge251:
  %case_r1175 = load ptr, ptr %res_slot1154
  store ptr %case_r1175, ptr %res_slot1135
  br label %case_merge245
case_default246:
  unreachable
case_merge245:
  %case_r1176 = load ptr, ptr %res_slot1135
  store ptr %case_r1176, ptr %res_slot1120
  br label %case_merge238
case_default239:
  unreachable
case_merge238:
  %case_r1177 = load ptr, ptr %res_slot1120
  ret ptr %case_r1177
}

define ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3283(ptr %steps.arg, ptr %req.arg, ptr %resp.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1178 = load ptr, ptr %steps.addr
  %res_slot1179 = alloca ptr
  %tgp1180 = getelementptr i8, ptr %ld1178, i64 8
  %tag1181 = load i32, ptr %tgp1180, align 4
  switch i32 %tag1181, label %case_default262 [
      i32 0, label %case_br263
      i32 1, label %case_br264
  ]
case_br263:
  %ld1182 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1182)
  %hp1183 = call ptr @march_alloc(i64 32)
  %tgp1184 = getelementptr i8, ptr %hp1183, i64 8
  store i32 0, ptr %tgp1184, align 4
  %ld1185 = load ptr, ptr %req.addr
  %fp1186 = getelementptr i8, ptr %hp1183, i64 16
  store ptr %ld1185, ptr %fp1186, align 8
  %ld1187 = load ptr, ptr %resp.addr
  %fp1188 = getelementptr i8, ptr %hp1183, i64 24
  store ptr %ld1187, ptr %fp1188, align 8
  %$t961.addr = alloca ptr
  store ptr %hp1183, ptr %$t961.addr
  %hp1189 = call ptr @march_alloc(i64 24)
  %tgp1190 = getelementptr i8, ptr %hp1189, i64 8
  store i32 0, ptr %tgp1190, align 4
  %ld1191 = load ptr, ptr %$t961.addr
  %fp1192 = getelementptr i8, ptr %hp1189, i64 16
  store ptr %ld1191, ptr %fp1192, align 8
  store ptr %hp1189, ptr %res_slot1179
  br label %case_merge261
case_br264:
  %fp1193 = getelementptr i8, ptr %ld1178, i64 16
  %fv1194 = load ptr, ptr %fp1193, align 8
  %$f967.addr = alloca ptr
  store ptr %fv1194, ptr %$f967.addr
  %fp1195 = getelementptr i8, ptr %ld1178, i64 24
  %fv1196 = load ptr, ptr %fp1195, align 8
  %$f968.addr = alloca ptr
  store ptr %fv1196, ptr %$f968.addr
  %freed1197 = call i64 @march_decrc_freed(ptr %ld1178)
  %freed_b1198 = icmp ne i64 %freed1197, 0
  br i1 %freed_b1198, label %br_unique265, label %br_shared266
br_shared266:
  call void @march_incrc(ptr %fv1196)
  call void @march_incrc(ptr %fv1194)
  br label %br_body267
br_unique265:
  br label %br_body267
br_body267:
  %ld1199 = load ptr, ptr %$f967.addr
  %res_slot1200 = alloca ptr
  %tgp1201 = getelementptr i8, ptr %ld1199, i64 8
  %tag1202 = load i32, ptr %tgp1201, align 4
  switch i32 %tag1202, label %case_default269 [
      i32 0, label %case_br270
  ]
case_br270:
  %fp1203 = getelementptr i8, ptr %ld1199, i64 16
  %fv1204 = load ptr, ptr %fp1203, align 8
  %$f969.addr = alloca ptr
  store ptr %fv1204, ptr %$f969.addr
  %fp1205 = getelementptr i8, ptr %ld1199, i64 24
  %fv1206 = load ptr, ptr %fp1205, align 8
  %$f970.addr = alloca ptr
  store ptr %fv1206, ptr %$f970.addr
  %freed1207 = call i64 @march_decrc_freed(ptr %ld1199)
  %freed_b1208 = icmp ne i64 %freed1207, 0
  br i1 %freed_b1208, label %br_unique271, label %br_shared272
br_shared272:
  call void @march_incrc(ptr %fv1206)
  call void @march_incrc(ptr %fv1204)
  br label %br_body273
br_unique271:
  br label %br_body273
br_body273:
  %ld1209 = load ptr, ptr %$f968.addr
  %rest.addr = alloca ptr
  store ptr %ld1209, ptr %rest.addr
  %ld1210 = load ptr, ptr %$f970.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1210, ptr %step_fn.addr
  %ld1211 = load ptr, ptr %step_fn.addr
  %fp1212 = getelementptr i8, ptr %ld1211, i64 16
  %fv1213 = load ptr, ptr %fp1212, align 8
  %ld1214 = load ptr, ptr %req.addr
  %ld1215 = load ptr, ptr %resp.addr
  %cr1216 = call ptr (ptr, ptr, ptr) %fv1213(ptr %ld1211, ptr %ld1214, ptr %ld1215)
  %$t962.addr = alloca ptr
  store ptr %cr1216, ptr %$t962.addr
  %ld1217 = load ptr, ptr %$t962.addr
  %res_slot1218 = alloca ptr
  %tgp1219 = getelementptr i8, ptr %ld1217, i64 8
  %tag1220 = load i32, ptr %tgp1219, align 4
  switch i32 %tag1220, label %case_default275 [
      i32 1, label %case_br276
      i32 0, label %case_br277
  ]
case_br276:
  %fp1221 = getelementptr i8, ptr %ld1217, i64 16
  %fv1222 = load ptr, ptr %fp1221, align 8
  %$f963.addr = alloca ptr
  store ptr %fv1222, ptr %$f963.addr
  %ld1223 = load ptr, ptr %$f963.addr
  %e.addr = alloca ptr
  store ptr %ld1223, ptr %e.addr
  %ld1224 = load ptr, ptr %$t962.addr
  %ld1225 = load ptr, ptr %e.addr
  %rc1226 = load i64, ptr %ld1224, align 8
  %uniq1227 = icmp eq i64 %rc1226, 1
  %fbip_slot1228 = alloca ptr
  br i1 %uniq1227, label %fbip_reuse278, label %fbip_fresh279
fbip_reuse278:
  %tgp1229 = getelementptr i8, ptr %ld1224, i64 8
  store i32 1, ptr %tgp1229, align 4
  %fp1230 = getelementptr i8, ptr %ld1224, i64 16
  store ptr %ld1225, ptr %fp1230, align 8
  store ptr %ld1224, ptr %fbip_slot1228
  br label %fbip_merge280
fbip_fresh279:
  call void @march_decrc(ptr %ld1224)
  %hp1231 = call ptr @march_alloc(i64 24)
  %tgp1232 = getelementptr i8, ptr %hp1231, i64 8
  store i32 1, ptr %tgp1232, align 4
  %fp1233 = getelementptr i8, ptr %hp1231, i64 16
  store ptr %ld1225, ptr %fp1233, align 8
  store ptr %hp1231, ptr %fbip_slot1228
  br label %fbip_merge280
fbip_merge280:
  %fbip_r1234 = load ptr, ptr %fbip_slot1228
  store ptr %fbip_r1234, ptr %res_slot1218
  br label %case_merge274
case_br277:
  %fp1235 = getelementptr i8, ptr %ld1217, i64 16
  %fv1236 = load ptr, ptr %fp1235, align 8
  %$f964.addr = alloca ptr
  store ptr %fv1236, ptr %$f964.addr
  %freed1237 = call i64 @march_decrc_freed(ptr %ld1217)
  %freed_b1238 = icmp ne i64 %freed1237, 0
  br i1 %freed_b1238, label %br_unique281, label %br_shared282
br_shared282:
  call void @march_incrc(ptr %fv1236)
  br label %br_body283
br_unique281:
  br label %br_body283
br_body283:
  %ld1239 = load ptr, ptr %$f964.addr
  %res_slot1240 = alloca ptr
  %tgp1241 = getelementptr i8, ptr %ld1239, i64 8
  %tag1242 = load i32, ptr %tgp1241, align 4
  switch i32 %tag1242, label %case_default285 [
      i32 0, label %case_br286
  ]
case_br286:
  %fp1243 = getelementptr i8, ptr %ld1239, i64 16
  %fv1244 = load ptr, ptr %fp1243, align 8
  %$f965.addr = alloca ptr
  store ptr %fv1244, ptr %$f965.addr
  %fp1245 = getelementptr i8, ptr %ld1239, i64 24
  %fv1246 = load ptr, ptr %fp1245, align 8
  %$f966.addr = alloca ptr
  store ptr %fv1246, ptr %$f966.addr
  %freed1247 = call i64 @march_decrc_freed(ptr %ld1239)
  %freed_b1248 = icmp ne i64 %freed1247, 0
  br i1 %freed_b1248, label %br_unique287, label %br_shared288
br_shared288:
  call void @march_incrc(ptr %fv1246)
  call void @march_incrc(ptr %fv1244)
  br label %br_body289
br_unique287:
  br label %br_body289
br_body289:
  %ld1249 = load ptr, ptr %$f966.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1249, ptr %new_resp.addr
  %ld1250 = load ptr, ptr %$f965.addr
  %new_req.addr = alloca ptr
  store ptr %ld1250, ptr %new_req.addr
  %ld1251 = load ptr, ptr %rest.addr
  %ld1252 = load ptr, ptr %new_req.addr
  %ld1253 = load ptr, ptr %new_resp.addr
  %cr1254 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3283(ptr %ld1251, ptr %ld1252, ptr %ld1253)
  store ptr %cr1254, ptr %res_slot1240
  br label %case_merge284
case_default285:
  unreachable
case_merge284:
  %case_r1255 = load ptr, ptr %res_slot1240
  store ptr %case_r1255, ptr %res_slot1218
  br label %case_merge274
case_default275:
  unreachable
case_merge274:
  %case_r1256 = load ptr, ptr %res_slot1218
  store ptr %case_r1256, ptr %res_slot1200
  br label %case_merge268
case_default269:
  unreachable
case_merge268:
  %case_r1257 = load ptr, ptr %res_slot1200
  store ptr %case_r1257, ptr %res_slot1179
  br label %case_merge261
case_default262:
  unreachable
case_merge261:
  %case_r1258 = load ptr, ptr %res_slot1179
  ret ptr %case_r1258
}

define ptr @HttpClient.handle_redirects$Request_String$Response_V__3283$Int$Int(ptr %req.arg, ptr %resp.arg, i64 %max.arg, i64 %count.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %max.addr = alloca i64
  store i64 %max.arg, ptr %max.addr
  %count.addr = alloca i64
  store i64 %count.arg, ptr %count.addr
  %ld1259 = load i64, ptr %max.addr
  %cmp1260 = icmp eq i64 %ld1259, 0
  %ar1261 = zext i1 %cmp1260 to i64
  %$t994.addr = alloca i64
  store i64 %ar1261, ptr %$t994.addr
  %ld1262 = load i64, ptr %$t994.addr
  %res_slot1263 = alloca ptr
  %bi1264 = trunc i64 %ld1262 to i1
  br i1 %bi1264, label %case_br292, label %case_default291
case_br292:
  %hp1265 = call ptr @march_alloc(i64 24)
  %tgp1266 = getelementptr i8, ptr %hp1265, i64 8
  store i32 0, ptr %tgp1266, align 4
  %ld1267 = load ptr, ptr %resp.addr
  %fp1268 = getelementptr i8, ptr %hp1265, i64 16
  store ptr %ld1267, ptr %fp1268, align 8
  store ptr %hp1265, ptr %res_slot1263
  br label %case_merge290
case_default291:
  %ld1269 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1269)
  %ld1270 = load ptr, ptr %resp.addr
  %cr1271 = call i64 @Http.response_is_redirect$Response_V__3283(ptr %ld1270)
  %$t995.addr = alloca i64
  store i64 %cr1271, ptr %$t995.addr
  %ld1272 = load i64, ptr %$t995.addr
  %ar1273 = xor i64 %ld1272, 1
  %$t996.addr = alloca i64
  store i64 %ar1273, ptr %$t996.addr
  %ld1274 = load i64, ptr %$t996.addr
  %res_slot1275 = alloca ptr
  %bi1276 = trunc i64 %ld1274 to i1
  br i1 %bi1276, label %case_br295, label %case_default294
case_br295:
  %hp1277 = call ptr @march_alloc(i64 24)
  %tgp1278 = getelementptr i8, ptr %hp1277, i64 8
  store i32 0, ptr %tgp1278, align 4
  %ld1279 = load ptr, ptr %resp.addr
  %fp1280 = getelementptr i8, ptr %hp1277, i64 16
  store ptr %ld1279, ptr %fp1280, align 8
  store ptr %hp1277, ptr %res_slot1275
  br label %case_merge293
case_default294:
  %ld1281 = load i64, ptr %count.addr
  %ld1282 = load i64, ptr %max.addr
  %cmp1283 = icmp sge i64 %ld1281, %ld1282
  %ar1284 = zext i1 %cmp1283 to i64
  %$t997.addr = alloca i64
  store i64 %ar1284, ptr %$t997.addr
  %ld1285 = load i64, ptr %$t997.addr
  %res_slot1286 = alloca ptr
  %bi1287 = trunc i64 %ld1285 to i1
  br i1 %bi1287, label %case_br298, label %case_default297
case_br298:
  %hp1288 = call ptr @march_alloc(i64 24)
  %tgp1289 = getelementptr i8, ptr %hp1288, i64 8
  store i32 2, ptr %tgp1289, align 4
  %ld1290 = load i64, ptr %count.addr
  %fp1291 = getelementptr i8, ptr %hp1288, i64 16
  store i64 %ld1290, ptr %fp1291, align 8
  %$t998.addr = alloca ptr
  store ptr %hp1288, ptr %$t998.addr
  %hp1292 = call ptr @march_alloc(i64 24)
  %tgp1293 = getelementptr i8, ptr %hp1292, i64 8
  store i32 1, ptr %tgp1293, align 4
  %ld1294 = load ptr, ptr %$t998.addr
  %fp1295 = getelementptr i8, ptr %hp1292, i64 16
  store ptr %ld1294, ptr %fp1295, align 8
  store ptr %hp1292, ptr %res_slot1286
  br label %case_merge296
case_default297:
  %ld1296 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1296)
  %ld1297 = load ptr, ptr %resp.addr
  %sl1298 = call ptr @march_string_lit(ptr @.str31, i64 8)
  %cr1299 = call ptr @Http.get_header$Response_V__3283$String(ptr %ld1297, ptr %sl1298)
  %$t999.addr = alloca ptr
  store ptr %cr1299, ptr %$t999.addr
  %ld1300 = load ptr, ptr %$t999.addr
  %res_slot1301 = alloca ptr
  %tgp1302 = getelementptr i8, ptr %ld1300, i64 8
  %tag1303 = load i32, ptr %tgp1302, align 4
  switch i32 %tag1303, label %case_default300 [
      i32 0, label %case_br301
      i32 1, label %case_br302
  ]
case_br301:
  %ld1304 = load ptr, ptr %$t999.addr
  call void @march_decrc(ptr %ld1304)
  %hp1305 = call ptr @march_alloc(i64 24)
  %tgp1306 = getelementptr i8, ptr %hp1305, i64 8
  store i32 0, ptr %tgp1306, align 4
  %ld1307 = load ptr, ptr %resp.addr
  %fp1308 = getelementptr i8, ptr %hp1305, i64 16
  store ptr %ld1307, ptr %fp1308, align 8
  store ptr %hp1305, ptr %res_slot1301
  br label %case_merge299
case_br302:
  %fp1309 = getelementptr i8, ptr %ld1300, i64 16
  %fv1310 = load ptr, ptr %fp1309, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv1310, ptr %$f1018.addr
  %freed1311 = call i64 @march_decrc_freed(ptr %ld1300)
  %freed_b1312 = icmp ne i64 %freed1311, 0
  br i1 %freed_b1312, label %br_unique303, label %br_shared304
br_shared304:
  call void @march_incrc(ptr %fv1310)
  br label %br_body305
br_unique303:
  br label %br_body305
br_body305:
  %ld1313 = load ptr, ptr %$f1018.addr
  %location.addr = alloca ptr
  store ptr %ld1313, ptr %location.addr
  %ld1314 = load ptr, ptr %location.addr
  call void @march_incrc(ptr %ld1314)
  %ld1315 = load ptr, ptr %location.addr
  %cr1316 = call ptr @Http.parse_url(ptr %ld1315)
  %$t1000.addr = alloca ptr
  store ptr %cr1316, ptr %$t1000.addr
  %ld1317 = load ptr, ptr %$t1000.addr
  %res_slot1318 = alloca ptr
  %tgp1319 = getelementptr i8, ptr %ld1317, i64 8
  %tag1320 = load i32, ptr %tgp1319, align 4
  switch i32 %tag1320, label %case_default307 [
      i32 0, label %case_br308
      i32 1, label %case_br309
  ]
case_br308:
  %fp1321 = getelementptr i8, ptr %ld1317, i64 16
  %fv1322 = load ptr, ptr %fp1321, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv1322, ptr %$f1011.addr
  %freed1323 = call i64 @march_decrc_freed(ptr %ld1317)
  %freed_b1324 = icmp ne i64 %freed1323, 0
  br i1 %freed_b1324, label %br_unique310, label %br_shared311
br_shared311:
  call void @march_incrc(ptr %fv1322)
  br label %br_body312
br_unique310:
  br label %br_body312
br_body312:
  %ld1325 = load ptr, ptr %$f1011.addr
  %parsed.addr = alloca ptr
  store ptr %ld1325, ptr %parsed.addr
  %hp1326 = call ptr @march_alloc(i64 16)
  %tgp1327 = getelementptr i8, ptr %hp1326, i64 8
  store i32 0, ptr %tgp1327, align 4
  %$t1001.addr = alloca ptr
  store ptr %hp1326, ptr %$t1001.addr
  %ld1328 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1328)
  %ld1329 = load ptr, ptr %parsed.addr
  %cr1330 = call ptr @Http.scheme$Request_T_(ptr %ld1329)
  %$t1002.addr = alloca ptr
  store ptr %cr1330, ptr %$t1002.addr
  %ld1331 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1331)
  %ld1332 = load ptr, ptr %parsed.addr
  %cr1333 = call ptr @Http.host$Request_T_(ptr %ld1332)
  %$t1003.addr = alloca ptr
  store ptr %cr1333, ptr %$t1003.addr
  %ld1334 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1334)
  %ld1335 = load ptr, ptr %parsed.addr
  %cr1336 = call ptr @Http.port$Request_T_(ptr %ld1335)
  %$t1004.addr = alloca ptr
  store ptr %cr1336, ptr %$t1004.addr
  %ld1337 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1337)
  %ld1338 = load ptr, ptr %parsed.addr
  %cr1339 = call ptr @Http.path$Request_T_(ptr %ld1338)
  %$t1005.addr = alloca ptr
  store ptr %cr1339, ptr %$t1005.addr
  %ld1340 = load ptr, ptr %parsed.addr
  %cr1341 = call ptr @Http.query$Request_T_(ptr %ld1340)
  %$t1006.addr = alloca ptr
  store ptr %cr1341, ptr %$t1006.addr
  %ld1342 = load ptr, ptr %req.addr
  %cr1343 = call ptr @Http.headers$Request_String(ptr %ld1342)
  %$t1007.addr = alloca ptr
  store ptr %cr1343, ptr %$t1007.addr
  %hp1344 = call ptr @march_alloc(i64 80)
  %tgp1345 = getelementptr i8, ptr %hp1344, i64 8
  store i32 0, ptr %tgp1345, align 4
  %ld1346 = load ptr, ptr %$t1001.addr
  %fp1347 = getelementptr i8, ptr %hp1344, i64 16
  store ptr %ld1346, ptr %fp1347, align 8
  %ld1348 = load ptr, ptr %$t1002.addr
  %fp1349 = getelementptr i8, ptr %hp1344, i64 24
  store ptr %ld1348, ptr %fp1349, align 8
  %ld1350 = load ptr, ptr %$t1003.addr
  %fp1351 = getelementptr i8, ptr %hp1344, i64 32
  store ptr %ld1350, ptr %fp1351, align 8
  %ld1352 = load ptr, ptr %$t1004.addr
  %fp1353 = getelementptr i8, ptr %hp1344, i64 40
  store ptr %ld1352, ptr %fp1353, align 8
  %ld1354 = load ptr, ptr %$t1005.addr
  %fp1355 = getelementptr i8, ptr %hp1344, i64 48
  store ptr %ld1354, ptr %fp1355, align 8
  %ld1356 = load ptr, ptr %$t1006.addr
  %fp1357 = getelementptr i8, ptr %hp1344, i64 56
  store ptr %ld1356, ptr %fp1357, align 8
  %ld1358 = load ptr, ptr %$t1007.addr
  %fp1359 = getelementptr i8, ptr %hp1344, i64 64
  store ptr %ld1358, ptr %fp1359, align 8
  %sl1360 = call ptr @march_string_lit(ptr @.str32, i64 0)
  %fp1361 = getelementptr i8, ptr %hp1344, i64 72
  store ptr %sl1360, ptr %fp1361, align 8
  store ptr %hp1344, ptr %res_slot1318
  br label %case_merge306
case_br309:
  %fp1362 = getelementptr i8, ptr %ld1317, i64 16
  %fv1363 = load ptr, ptr %fp1362, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv1363, ptr %$f1012.addr
  %freed1364 = call i64 @march_decrc_freed(ptr %ld1317)
  %freed_b1365 = icmp ne i64 %freed1364, 0
  br i1 %freed_b1365, label %br_unique313, label %br_shared314
br_shared314:
  call void @march_incrc(ptr %fv1363)
  br label %br_body315
br_unique313:
  br label %br_body315
br_body315:
  %ld1366 = load ptr, ptr %req.addr
  %ld1367 = load ptr, ptr %location.addr
  %cr1368 = call ptr @Http.set_path$Request_String$String(ptr %ld1366, ptr %ld1367)
  %$t1008.addr = alloca ptr
  store ptr %cr1368, ptr %$t1008.addr
  %hp1369 = call ptr @march_alloc(i64 16)
  %tgp1370 = getelementptr i8, ptr %hp1369, i64 8
  store i32 0, ptr %tgp1370, align 4
  %$t1009.addr = alloca ptr
  store ptr %hp1369, ptr %$t1009.addr
  %ld1371 = load ptr, ptr %$t1008.addr
  %ld1372 = load ptr, ptr %$t1009.addr
  %cr1373 = call ptr @Http.set_method$Request_String$Method(ptr %ld1371, ptr %ld1372)
  %$t1010.addr = alloca ptr
  store ptr %cr1373, ptr %$t1010.addr
  %ld1374 = load ptr, ptr %$t1010.addr
  %sl1375 = call ptr @march_string_lit(ptr @.str33, i64 0)
  %cr1376 = call ptr @Http.set_body$Request_String$String(ptr %ld1374, ptr %sl1375)
  store ptr %cr1376, ptr %res_slot1318
  br label %case_merge306
case_default307:
  unreachable
case_merge306:
  %case_r1377 = load ptr, ptr %res_slot1318
  %redirect_req.addr = alloca ptr
  store ptr %case_r1377, ptr %redirect_req.addr
  %ld1378 = load ptr, ptr %redirect_req.addr
  call void @march_incrc(ptr %ld1378)
  %ld1379 = load ptr, ptr %redirect_req.addr
  %cr1380 = call ptr @HttpTransport.request$Request_String(ptr %ld1379)
  %$t1013.addr = alloca ptr
  store ptr %cr1380, ptr %$t1013.addr
  %ld1381 = load ptr, ptr %$t1013.addr
  %res_slot1382 = alloca ptr
  %tgp1383 = getelementptr i8, ptr %ld1381, i64 8
  %tag1384 = load i32, ptr %tgp1383, align 4
  switch i32 %tag1384, label %case_default317 [
      i32 1, label %case_br318
      i32 0, label %case_br319
  ]
case_br318:
  %fp1385 = getelementptr i8, ptr %ld1381, i64 16
  %fv1386 = load ptr, ptr %fp1385, align 8
  %$f1016.addr = alloca ptr
  store ptr %fv1386, ptr %$f1016.addr
  %ld1387 = load ptr, ptr %$f1016.addr
  %e.addr = alloca ptr
  store ptr %ld1387, ptr %e.addr
  %hp1388 = call ptr @march_alloc(i64 24)
  %tgp1389 = getelementptr i8, ptr %hp1388, i64 8
  store i32 0, ptr %tgp1389, align 4
  %ld1390 = load ptr, ptr %e.addr
  %fp1391 = getelementptr i8, ptr %hp1388, i64 16
  store ptr %ld1390, ptr %fp1391, align 8
  %$t1014.addr = alloca ptr
  store ptr %hp1388, ptr %$t1014.addr
  %ld1392 = load ptr, ptr %$t1013.addr
  %ld1393 = load ptr, ptr %$t1014.addr
  %rc1394 = load i64, ptr %ld1392, align 8
  %uniq1395 = icmp eq i64 %rc1394, 1
  %fbip_slot1396 = alloca ptr
  br i1 %uniq1395, label %fbip_reuse320, label %fbip_fresh321
fbip_reuse320:
  %tgp1397 = getelementptr i8, ptr %ld1392, i64 8
  store i32 1, ptr %tgp1397, align 4
  %fp1398 = getelementptr i8, ptr %ld1392, i64 16
  store ptr %ld1393, ptr %fp1398, align 8
  store ptr %ld1392, ptr %fbip_slot1396
  br label %fbip_merge322
fbip_fresh321:
  call void @march_decrc(ptr %ld1392)
  %hp1399 = call ptr @march_alloc(i64 24)
  %tgp1400 = getelementptr i8, ptr %hp1399, i64 8
  store i32 1, ptr %tgp1400, align 4
  %fp1401 = getelementptr i8, ptr %hp1399, i64 16
  store ptr %ld1393, ptr %fp1401, align 8
  store ptr %hp1399, ptr %fbip_slot1396
  br label %fbip_merge322
fbip_merge322:
  %fbip_r1402 = load ptr, ptr %fbip_slot1396
  store ptr %fbip_r1402, ptr %res_slot1382
  br label %case_merge316
case_br319:
  %fp1403 = getelementptr i8, ptr %ld1381, i64 16
  %fv1404 = load ptr, ptr %fp1403, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv1404, ptr %$f1017.addr
  %freed1405 = call i64 @march_decrc_freed(ptr %ld1381)
  %freed_b1406 = icmp ne i64 %freed1405, 0
  br i1 %freed_b1406, label %br_unique323, label %br_shared324
br_shared324:
  call void @march_incrc(ptr %fv1404)
  br label %br_body325
br_unique323:
  br label %br_body325
br_body325:
  %ld1407 = load ptr, ptr %$f1017.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1407, ptr %new_resp.addr
  %ld1408 = load i64, ptr %count.addr
  %ar1409 = add i64 %ld1408, 1
  %$t1015.addr = alloca i64
  store i64 %ar1409, ptr %$t1015.addr
  %ld1410 = load ptr, ptr %redirect_req.addr
  %ld1411 = load ptr, ptr %new_resp.addr
  %ld1412 = load i64, ptr %max.addr
  %ld1413 = load i64, ptr %$t1015.addr
  %cr1414 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3283$Int$Int(ptr %ld1410, ptr %ld1411, i64 %ld1412, i64 %ld1413)
  store ptr %cr1414, ptr %res_slot1382
  br label %case_merge316
case_default317:
  unreachable
case_merge316:
  %case_r1415 = load ptr, ptr %res_slot1382
  store ptr %case_r1415, ptr %res_slot1301
  br label %case_merge299
case_default300:
  unreachable
case_merge299:
  %case_r1416 = load ptr, ptr %res_slot1301
  store ptr %case_r1416, ptr %res_slot1286
  br label %case_merge296
case_merge296:
  %case_r1417 = load ptr, ptr %res_slot1286
  store ptr %case_r1417, ptr %res_slot1275
  br label %case_merge293
case_merge293:
  %case_r1418 = load ptr, ptr %res_slot1275
  store ptr %case_r1418, ptr %res_slot1263
  br label %case_merge290
case_merge290:
  %case_r1419 = load ptr, ptr %res_slot1263
  ret ptr %case_r1419
}

define ptr @HttpClient.transport_keepalive$V__3281$Request_String$Int(ptr %fd.arg, ptr %req.arg, i64 %retries_left.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld1420 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1420)
  %ld1421 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1421)
  %ld1422 = load ptr, ptr %fd.addr
  %ld1423 = load ptr, ptr %req.addr
  %cr1424 = call ptr @HttpTransport.request_on$V__3281$Request_String(ptr %ld1422, ptr %ld1423)
  %$t987.addr = alloca ptr
  store ptr %cr1424, ptr %$t987.addr
  %ld1425 = load ptr, ptr %$t987.addr
  %res_slot1426 = alloca ptr
  %tgp1427 = getelementptr i8, ptr %ld1425, i64 8
  %tag1428 = load i32, ptr %tgp1427, align 4
  switch i32 %tag1428, label %case_default327 [
      i32 0, label %case_br328
      i32 1, label %case_br329
  ]
case_br328:
  %fp1429 = getelementptr i8, ptr %ld1425, i64 16
  %fv1430 = load ptr, ptr %fp1429, align 8
  %$f992.addr = alloca ptr
  store ptr %fv1430, ptr %$f992.addr
  %ld1431 = load ptr, ptr %$f992.addr
  %resp.addr = alloca ptr
  store ptr %ld1431, ptr %resp.addr
  %hp1432 = call ptr @march_alloc(i64 32)
  %tgp1433 = getelementptr i8, ptr %hp1432, i64 8
  store i32 0, ptr %tgp1433, align 4
  %ld1434 = load ptr, ptr %fd.addr
  %fp1435 = getelementptr i8, ptr %hp1432, i64 16
  store ptr %ld1434, ptr %fp1435, align 8
  %ld1436 = load ptr, ptr %resp.addr
  %fp1437 = getelementptr i8, ptr %hp1432, i64 24
  store ptr %ld1436, ptr %fp1437, align 8
  %$t988.addr = alloca ptr
  store ptr %hp1432, ptr %$t988.addr
  %ld1438 = load ptr, ptr %$t987.addr
  %ld1439 = load ptr, ptr %$t988.addr
  %rc1440 = load i64, ptr %ld1438, align 8
  %uniq1441 = icmp eq i64 %rc1440, 1
  %fbip_slot1442 = alloca ptr
  br i1 %uniq1441, label %fbip_reuse330, label %fbip_fresh331
fbip_reuse330:
  %tgp1443 = getelementptr i8, ptr %ld1438, i64 8
  store i32 0, ptr %tgp1443, align 4
  %fp1444 = getelementptr i8, ptr %ld1438, i64 16
  store ptr %ld1439, ptr %fp1444, align 8
  store ptr %ld1438, ptr %fbip_slot1442
  br label %fbip_merge332
fbip_fresh331:
  call void @march_decrc(ptr %ld1438)
  %hp1445 = call ptr @march_alloc(i64 24)
  %tgp1446 = getelementptr i8, ptr %hp1445, i64 8
  store i32 0, ptr %tgp1446, align 4
  %fp1447 = getelementptr i8, ptr %hp1445, i64 16
  store ptr %ld1439, ptr %fp1447, align 8
  store ptr %hp1445, ptr %fbip_slot1442
  br label %fbip_merge332
fbip_merge332:
  %fbip_r1448 = load ptr, ptr %fbip_slot1442
  store ptr %fbip_r1448, ptr %res_slot1426
  br label %case_merge326
case_br329:
  %fp1449 = getelementptr i8, ptr %ld1425, i64 16
  %fv1450 = load ptr, ptr %fp1449, align 8
  %$f993.addr = alloca ptr
  store ptr %fv1450, ptr %$f993.addr
  %freed1451 = call i64 @march_decrc_freed(ptr %ld1425)
  %freed_b1452 = icmp ne i64 %freed1451, 0
  br i1 %freed_b1452, label %br_unique333, label %br_shared334
br_shared334:
  call void @march_incrc(ptr %fv1450)
  br label %br_body335
br_unique333:
  br label %br_body335
br_body335:
  %ld1453 = load ptr, ptr %tcp_close.addr
  %fp1454 = getelementptr i8, ptr %ld1453, i64 16
  %fv1455 = load ptr, ptr %fp1454, align 8
  %ld1456 = load ptr, ptr %fd.addr
  %cr1457 = call ptr (ptr, ptr) %fv1455(ptr %ld1453, ptr %ld1456)
  %ld1458 = load i64, ptr %retries_left.addr
  %cmp1459 = icmp sgt i64 %ld1458, 0
  %ar1460 = zext i1 %cmp1459 to i64
  %$t989.addr = alloca i64
  store i64 %ar1460, ptr %$t989.addr
  %ld1461 = load i64, ptr %$t989.addr
  %res_slot1462 = alloca ptr
  %bi1463 = trunc i64 %ld1461 to i1
  br i1 %bi1463, label %case_br338, label %case_default337
case_br338:
  %ld1464 = load i64, ptr %retries_left.addr
  %ar1465 = sub i64 %ld1464, 1
  %$t990.addr = alloca i64
  store i64 %ar1465, ptr %$t990.addr
  %ld1466 = load ptr, ptr %req.addr
  %ld1467 = load i64, ptr %$t990.addr
  %cr1468 = call ptr @HttpClient.reconnect_and_retry(ptr %ld1466, i64 %ld1467)
  store ptr %cr1468, ptr %res_slot1462
  br label %case_merge336
case_default337:
  %hp1469 = call ptr @march_alloc(i64 16)
  %tgp1470 = getelementptr i8, ptr %hp1469, i64 8
  store i32 0, ptr %tgp1470, align 4
  %$t991.addr = alloca ptr
  store ptr %hp1469, ptr %$t991.addr
  %hp1471 = call ptr @march_alloc(i64 24)
  %tgp1472 = getelementptr i8, ptr %hp1471, i64 8
  store i32 1, ptr %tgp1472, align 4
  %ld1473 = load ptr, ptr %$t991.addr
  %fp1474 = getelementptr i8, ptr %hp1471, i64 16
  store ptr %ld1473, ptr %fp1474, align 8
  store ptr %hp1471, ptr %res_slot1462
  br label %case_merge336
case_merge336:
  %case_r1475 = load ptr, ptr %res_slot1462
  store ptr %case_r1475, ptr %res_slot1426
  br label %case_merge326
case_default327:
  unreachable
case_merge326:
  %case_r1476 = load ptr, ptr %res_slot1426
  ret ptr %case_r1476
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1477 = load ptr, ptr %steps.addr
  %res_slot1478 = alloca ptr
  %tgp1479 = getelementptr i8, ptr %ld1477, i64 8
  %tag1480 = load i32, ptr %tgp1479, align 4
  switch i32 %tag1480, label %case_default340 [
      i32 0, label %case_br341
      i32 1, label %case_br342
  ]
case_br341:
  %ld1481 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1481)
  %hp1482 = call ptr @march_alloc(i64 24)
  %tgp1483 = getelementptr i8, ptr %hp1482, i64 8
  store i32 0, ptr %tgp1483, align 4
  %ld1484 = load ptr, ptr %req.addr
  %fp1485 = getelementptr i8, ptr %hp1482, i64 16
  store ptr %ld1484, ptr %fp1485, align 8
  store ptr %hp1482, ptr %res_slot1478
  br label %case_merge339
case_br342:
  %fp1486 = getelementptr i8, ptr %ld1477, i64 16
  %fv1487 = load ptr, ptr %fp1486, align 8
  %$f957.addr = alloca ptr
  store ptr %fv1487, ptr %$f957.addr
  %fp1488 = getelementptr i8, ptr %ld1477, i64 24
  %fv1489 = load ptr, ptr %fp1488, align 8
  %$f958.addr = alloca ptr
  store ptr %fv1489, ptr %$f958.addr
  %freed1490 = call i64 @march_decrc_freed(ptr %ld1477)
  %freed_b1491 = icmp ne i64 %freed1490, 0
  br i1 %freed_b1491, label %br_unique343, label %br_shared344
br_shared344:
  call void @march_incrc(ptr %fv1489)
  call void @march_incrc(ptr %fv1487)
  br label %br_body345
br_unique343:
  br label %br_body345
br_body345:
  %ld1492 = load ptr, ptr %$f957.addr
  %res_slot1493 = alloca ptr
  %tgp1494 = getelementptr i8, ptr %ld1492, i64 8
  %tag1495 = load i32, ptr %tgp1494, align 4
  switch i32 %tag1495, label %case_default347 [
      i32 0, label %case_br348
  ]
case_br348:
  %fp1496 = getelementptr i8, ptr %ld1492, i64 16
  %fv1497 = load ptr, ptr %fp1496, align 8
  %$f959.addr = alloca ptr
  store ptr %fv1497, ptr %$f959.addr
  %fp1498 = getelementptr i8, ptr %ld1492, i64 24
  %fv1499 = load ptr, ptr %fp1498, align 8
  %$f960.addr = alloca ptr
  store ptr %fv1499, ptr %$f960.addr
  %freed1500 = call i64 @march_decrc_freed(ptr %ld1492)
  %freed_b1501 = icmp ne i64 %freed1500, 0
  br i1 %freed_b1501, label %br_unique349, label %br_shared350
br_shared350:
  call void @march_incrc(ptr %fv1499)
  call void @march_incrc(ptr %fv1497)
  br label %br_body351
br_unique349:
  br label %br_body351
br_body351:
  %ld1502 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld1502, ptr %rest.addr
  %ld1503 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1503, ptr %step_fn.addr
  %ld1504 = load ptr, ptr %step_fn.addr
  %fp1505 = getelementptr i8, ptr %ld1504, i64 16
  %fv1506 = load ptr, ptr %fp1505, align 8
  %ld1507 = load ptr, ptr %req.addr
  %cr1508 = call ptr (ptr, ptr) %fv1506(ptr %ld1504, ptr %ld1507)
  %$t954.addr = alloca ptr
  store ptr %cr1508, ptr %$t954.addr
  %ld1509 = load ptr, ptr %$t954.addr
  %res_slot1510 = alloca ptr
  %tgp1511 = getelementptr i8, ptr %ld1509, i64 8
  %tag1512 = load i32, ptr %tgp1511, align 4
  switch i32 %tag1512, label %case_default353 [
      i32 1, label %case_br354
      i32 0, label %case_br355
  ]
case_br354:
  %fp1513 = getelementptr i8, ptr %ld1509, i64 16
  %fv1514 = load ptr, ptr %fp1513, align 8
  %$f955.addr = alloca ptr
  store ptr %fv1514, ptr %$f955.addr
  %ld1515 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld1515, ptr %e.addr
  %ld1516 = load ptr, ptr %$t954.addr
  %ld1517 = load ptr, ptr %e.addr
  %rc1518 = load i64, ptr %ld1516, align 8
  %uniq1519 = icmp eq i64 %rc1518, 1
  %fbip_slot1520 = alloca ptr
  br i1 %uniq1519, label %fbip_reuse356, label %fbip_fresh357
fbip_reuse356:
  %tgp1521 = getelementptr i8, ptr %ld1516, i64 8
  store i32 1, ptr %tgp1521, align 4
  %fp1522 = getelementptr i8, ptr %ld1516, i64 16
  store ptr %ld1517, ptr %fp1522, align 8
  store ptr %ld1516, ptr %fbip_slot1520
  br label %fbip_merge358
fbip_fresh357:
  call void @march_decrc(ptr %ld1516)
  %hp1523 = call ptr @march_alloc(i64 24)
  %tgp1524 = getelementptr i8, ptr %hp1523, i64 8
  store i32 1, ptr %tgp1524, align 4
  %fp1525 = getelementptr i8, ptr %hp1523, i64 16
  store ptr %ld1517, ptr %fp1525, align 8
  store ptr %hp1523, ptr %fbip_slot1520
  br label %fbip_merge358
fbip_merge358:
  %fbip_r1526 = load ptr, ptr %fbip_slot1520
  store ptr %fbip_r1526, ptr %res_slot1510
  br label %case_merge352
case_br355:
  %fp1527 = getelementptr i8, ptr %ld1509, i64 16
  %fv1528 = load ptr, ptr %fp1527, align 8
  %$f956.addr = alloca ptr
  store ptr %fv1528, ptr %$f956.addr
  %freed1529 = call i64 @march_decrc_freed(ptr %ld1509)
  %freed_b1530 = icmp ne i64 %freed1529, 0
  br i1 %freed_b1530, label %br_unique359, label %br_shared360
br_shared360:
  call void @march_incrc(ptr %fv1528)
  br label %br_body361
br_unique359:
  br label %br_body361
br_body361:
  %ld1531 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld1531, ptr %new_req.addr
  %ld1532 = load ptr, ptr %rest.addr
  %ld1533 = load ptr, ptr %new_req.addr
  %cr1534 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld1532, ptr %ld1533)
  store ptr %cr1534, ptr %res_slot1510
  br label %case_merge352
case_default353:
  unreachable
case_merge352:
  %case_r1535 = load ptr, ptr %res_slot1510
  store ptr %case_r1535, ptr %res_slot1493
  br label %case_merge346
case_default347:
  unreachable
case_merge346:
  %case_r1536 = load ptr, ptr %res_slot1493
  store ptr %case_r1536, ptr %res_slot1478
  br label %case_merge339
case_default340:
  unreachable
case_merge339:
  %case_r1537 = load ptr, ptr %res_slot1478
  ret ptr %case_r1537
}

define ptr @Http.port$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1538 = load ptr, ptr %req.addr
  %res_slot1539 = alloca ptr
  %tgp1540 = getelementptr i8, ptr %ld1538, i64 8
  %tag1541 = load i32, ptr %tgp1540, align 4
  switch i32 %tag1541, label %case_default363 [
      i32 0, label %case_br364
  ]
case_br364:
  %fp1542 = getelementptr i8, ptr %ld1538, i64 16
  %fv1543 = load ptr, ptr %fp1542, align 8
  %$f567.addr = alloca ptr
  store ptr %fv1543, ptr %$f567.addr
  %fp1544 = getelementptr i8, ptr %ld1538, i64 24
  %fv1545 = load ptr, ptr %fp1544, align 8
  %$f568.addr = alloca ptr
  store ptr %fv1545, ptr %$f568.addr
  %fp1546 = getelementptr i8, ptr %ld1538, i64 32
  %fv1547 = load ptr, ptr %fp1546, align 8
  %$f569.addr = alloca ptr
  store ptr %fv1547, ptr %$f569.addr
  %fp1548 = getelementptr i8, ptr %ld1538, i64 40
  %fv1549 = load ptr, ptr %fp1548, align 8
  %$f570.addr = alloca ptr
  store ptr %fv1549, ptr %$f570.addr
  %fp1550 = getelementptr i8, ptr %ld1538, i64 48
  %fv1551 = load ptr, ptr %fp1550, align 8
  %$f571.addr = alloca ptr
  store ptr %fv1551, ptr %$f571.addr
  %fp1552 = getelementptr i8, ptr %ld1538, i64 56
  %fv1553 = load ptr, ptr %fp1552, align 8
  %$f572.addr = alloca ptr
  store ptr %fv1553, ptr %$f572.addr
  %fp1554 = getelementptr i8, ptr %ld1538, i64 64
  %fv1555 = load ptr, ptr %fp1554, align 8
  %$f573.addr = alloca ptr
  store ptr %fv1555, ptr %$f573.addr
  %fp1556 = getelementptr i8, ptr %ld1538, i64 72
  %fv1557 = load ptr, ptr %fp1556, align 8
  %$f574.addr = alloca ptr
  store ptr %fv1557, ptr %$f574.addr
  %freed1558 = call i64 @march_decrc_freed(ptr %ld1538)
  %freed_b1559 = icmp ne i64 %freed1558, 0
  br i1 %freed_b1559, label %br_unique365, label %br_shared366
br_shared366:
  call void @march_incrc(ptr %fv1557)
  call void @march_incrc(ptr %fv1555)
  call void @march_incrc(ptr %fv1553)
  call void @march_incrc(ptr %fv1551)
  call void @march_incrc(ptr %fv1549)
  call void @march_incrc(ptr %fv1547)
  call void @march_incrc(ptr %fv1545)
  call void @march_incrc(ptr %fv1543)
  br label %br_body367
br_unique365:
  br label %br_body367
br_body367:
  %ld1560 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld1560, ptr %p.addr
  %ld1561 = load ptr, ptr %p.addr
  store ptr %ld1561, ptr %res_slot1539
  br label %case_merge362
case_default363:
  unreachable
case_merge362:
  %case_r1562 = load ptr, ptr %res_slot1539
  ret ptr %case_r1562
}

define ptr @Http.host$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1563 = load ptr, ptr %req.addr
  %res_slot1564 = alloca ptr
  %tgp1565 = getelementptr i8, ptr %ld1563, i64 8
  %tag1566 = load i32, ptr %tgp1565, align 4
  switch i32 %tag1566, label %case_default369 [
      i32 0, label %case_br370
  ]
case_br370:
  %fp1567 = getelementptr i8, ptr %ld1563, i64 16
  %fv1568 = load ptr, ptr %fp1567, align 8
  %$f559.addr = alloca ptr
  store ptr %fv1568, ptr %$f559.addr
  %fp1569 = getelementptr i8, ptr %ld1563, i64 24
  %fv1570 = load ptr, ptr %fp1569, align 8
  %$f560.addr = alloca ptr
  store ptr %fv1570, ptr %$f560.addr
  %fp1571 = getelementptr i8, ptr %ld1563, i64 32
  %fv1572 = load ptr, ptr %fp1571, align 8
  %$f561.addr = alloca ptr
  store ptr %fv1572, ptr %$f561.addr
  %fp1573 = getelementptr i8, ptr %ld1563, i64 40
  %fv1574 = load ptr, ptr %fp1573, align 8
  %$f562.addr = alloca ptr
  store ptr %fv1574, ptr %$f562.addr
  %fp1575 = getelementptr i8, ptr %ld1563, i64 48
  %fv1576 = load ptr, ptr %fp1575, align 8
  %$f563.addr = alloca ptr
  store ptr %fv1576, ptr %$f563.addr
  %fp1577 = getelementptr i8, ptr %ld1563, i64 56
  %fv1578 = load ptr, ptr %fp1577, align 8
  %$f564.addr = alloca ptr
  store ptr %fv1578, ptr %$f564.addr
  %fp1579 = getelementptr i8, ptr %ld1563, i64 64
  %fv1580 = load ptr, ptr %fp1579, align 8
  %$f565.addr = alloca ptr
  store ptr %fv1580, ptr %$f565.addr
  %fp1581 = getelementptr i8, ptr %ld1563, i64 72
  %fv1582 = load ptr, ptr %fp1581, align 8
  %$f566.addr = alloca ptr
  store ptr %fv1582, ptr %$f566.addr
  %freed1583 = call i64 @march_decrc_freed(ptr %ld1563)
  %freed_b1584 = icmp ne i64 %freed1583, 0
  br i1 %freed_b1584, label %br_unique371, label %br_shared372
br_shared372:
  call void @march_incrc(ptr %fv1582)
  call void @march_incrc(ptr %fv1580)
  call void @march_incrc(ptr %fv1578)
  call void @march_incrc(ptr %fv1576)
  call void @march_incrc(ptr %fv1574)
  call void @march_incrc(ptr %fv1572)
  call void @march_incrc(ptr %fv1570)
  call void @march_incrc(ptr %fv1568)
  br label %br_body373
br_unique371:
  br label %br_body373
br_body373:
  %ld1585 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld1585, ptr %h.addr
  %ld1586 = load ptr, ptr %h.addr
  store ptr %ld1586, ptr %res_slot1564
  br label %case_merge368
case_default369:
  unreachable
case_merge368:
  %case_r1587 = load ptr, ptr %res_slot1564
  ret ptr %case_r1587
}

define ptr @HttpTransport.request$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1588 = load ptr, ptr %req.addr
  %sl1589 = call ptr @march_string_lit(ptr @.str34, i64 10)
  %sl1590 = call ptr @march_string_lit(ptr @.str35, i64 5)
  %cr1591 = call ptr @Http.set_header$Request_String$String$String(ptr %ld1588, ptr %sl1589, ptr %sl1590)
  %req_1.addr = alloca ptr
  store ptr %cr1591, ptr %req_1.addr
  %ld1592 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1592)
  %ld1593 = load ptr, ptr %req_1.addr
  %cr1594 = call ptr @Http.host$Request_V__2815(ptr %ld1593)
  %req_host.addr = alloca ptr
  store ptr %cr1594, ptr %req_host.addr
  %ld1595 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1595)
  %ld1596 = load ptr, ptr %req_1.addr
  %cr1597 = call ptr @Http.port$Request_V__2818(ptr %ld1596)
  %$t837.addr = alloca ptr
  store ptr %cr1597, ptr %$t837.addr
  %ld1598 = load ptr, ptr %$t837.addr
  %res_slot1599 = alloca ptr
  %tgp1600 = getelementptr i8, ptr %ld1598, i64 8
  %tag1601 = load i32, ptr %tgp1600, align 4
  switch i32 %tag1601, label %case_default375 [
      i32 1, label %case_br376
      i32 0, label %case_br377
  ]
case_br376:
  %fp1602 = getelementptr i8, ptr %ld1598, i64 16
  %fv1603 = load ptr, ptr %fp1602, align 8
  %$f838.addr = alloca ptr
  store ptr %fv1603, ptr %$f838.addr
  %ld1604 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld1604)
  %ld1605 = load ptr, ptr %$f838.addr
  %p.addr = alloca ptr
  store ptr %ld1605, ptr %p.addr
  %ld1606 = load ptr, ptr %p.addr
  store ptr %ld1606, ptr %res_slot1599
  br label %case_merge374
case_br377:
  %ld1607 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld1607)
  %cv1608 = inttoptr i64 80 to ptr
  store ptr %cv1608, ptr %res_slot1599
  br label %case_merge374
case_default375:
  unreachable
case_merge374:
  %case_r1609 = load ptr, ptr %res_slot1599
  %cv1610 = ptrtoint ptr %case_r1609 to i64
  %req_port.addr = alloca i64
  store i64 %cv1610, ptr %req_port.addr
  %ld1611 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1611)
  %ld1612 = load ptr, ptr %req_1.addr
  %cr1613 = call ptr @Http.method$Request_V__2825(ptr %ld1612)
  %$t839.addr = alloca ptr
  store ptr %cr1613, ptr %$t839.addr
  %ld1614 = load ptr, ptr %$t839.addr
  %cr1615 = call ptr @Http.method_to_string(ptr %ld1614)
  %$t840.addr = alloca ptr
  store ptr %cr1615, ptr %$t840.addr
  %ld1616 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1616)
  %ld1617 = load ptr, ptr %req_1.addr
  %cr1618 = call ptr @Http.path$Request_V__2827(ptr %ld1617)
  %$t841.addr = alloca ptr
  store ptr %cr1618, ptr %$t841.addr
  %ld1619 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1619)
  %ld1620 = load ptr, ptr %req_1.addr
  %cr1621 = call ptr @Http.query$Request_V__2829(ptr %ld1620)
  %$t842.addr = alloca ptr
  store ptr %cr1621, ptr %$t842.addr
  %ld1622 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld1622)
  %ld1623 = load ptr, ptr %req_1.addr
  %cr1624 = call ptr @Http.headers$Request_V__2831(ptr %ld1623)
  %$t843.addr = alloca ptr
  store ptr %cr1624, ptr %$t843.addr
  %ld1625 = load ptr, ptr %req_1.addr
  %cr1626 = call ptr @Http.body$Request_V__2833(ptr %ld1625)
  %$t844.addr = alloca ptr
  store ptr %cr1626, ptr %$t844.addr
  %ld1627 = load ptr, ptr %req_host.addr
  call void @march_incrc(ptr %ld1627)
  %ld1628 = load ptr, ptr %http_serialize_request.addr
  %fp1629 = getelementptr i8, ptr %ld1628, i64 16
  %fv1630 = load ptr, ptr %fp1629, align 8
  %ld1631 = load ptr, ptr %$t840.addr
  %ld1632 = load ptr, ptr %req_host.addr
  %ld1633 = load ptr, ptr %$t841.addr
  %ld1634 = load ptr, ptr %$t842.addr
  %ld1635 = load ptr, ptr %$t843.addr
  %ld1636 = load ptr, ptr %$t844.addr
  %cr1637 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv1630(ptr %ld1628, ptr %ld1631, ptr %ld1632, ptr %ld1633, ptr %ld1634, ptr %ld1635, ptr %ld1636)
  %raw_request.addr = alloca ptr
  store ptr %cr1637, ptr %raw_request.addr
  %ld1638 = load ptr, ptr %tcp_connect.addr
  %fp1639 = getelementptr i8, ptr %ld1638, i64 16
  %fv1640 = load ptr, ptr %fp1639, align 8
  %ld1641 = load ptr, ptr %req_host.addr
  %ld1642 = load i64, ptr %req_port.addr
  %cv1643 = inttoptr i64 %ld1642 to ptr
  %cr1644 = call ptr (ptr, ptr, ptr) %fv1640(ptr %ld1638, ptr %ld1641, ptr %cv1643)
  %$t845.addr = alloca ptr
  store ptr %cr1644, ptr %$t845.addr
  %ld1645 = load ptr, ptr %$t845.addr
  %res_slot1646 = alloca ptr
  %tgp1647 = getelementptr i8, ptr %ld1645, i64 8
  %tag1648 = load i32, ptr %tgp1647, align 4
  switch i32 %tag1648, label %case_default379 [
      i32 0, label %case_br380
      i32 0, label %case_br381
  ]
case_br380:
  %fp1649 = getelementptr i8, ptr %ld1645, i64 16
  %fv1650 = load ptr, ptr %fp1649, align 8
  %$f864.addr = alloca ptr
  store ptr %fv1650, ptr %$f864.addr
  %freed1651 = call i64 @march_decrc_freed(ptr %ld1645)
  %freed_b1652 = icmp ne i64 %freed1651, 0
  br i1 %freed_b1652, label %br_unique382, label %br_shared383
br_shared383:
  call void @march_incrc(ptr %fv1650)
  br label %br_body384
br_unique382:
  br label %br_body384
br_body384:
  %ld1653 = load ptr, ptr %$f864.addr
  %msg.addr = alloca ptr
  store ptr %ld1653, ptr %msg.addr
  %hp1654 = call ptr @march_alloc(i64 24)
  %tgp1655 = getelementptr i8, ptr %hp1654, i64 8
  store i32 0, ptr %tgp1655, align 4
  %ld1656 = load ptr, ptr %msg.addr
  %fp1657 = getelementptr i8, ptr %hp1654, i64 16
  store ptr %ld1656, ptr %fp1657, align 8
  %$t846.addr = alloca ptr
  store ptr %hp1654, ptr %$t846.addr
  %hp1658 = call ptr @march_alloc(i64 24)
  %tgp1659 = getelementptr i8, ptr %hp1658, i64 8
  store i32 1, ptr %tgp1659, align 4
  %ld1660 = load ptr, ptr %$t846.addr
  %fp1661 = getelementptr i8, ptr %hp1658, i64 16
  store ptr %ld1660, ptr %fp1661, align 8
  store ptr %hp1658, ptr %res_slot1646
  br label %case_merge378
case_br381:
  %fp1662 = getelementptr i8, ptr %ld1645, i64 16
  %fv1663 = load ptr, ptr %fp1662, align 8
  %$f865.addr = alloca ptr
  store ptr %fv1663, ptr %$f865.addr
  %freed1664 = call i64 @march_decrc_freed(ptr %ld1645)
  %freed_b1665 = icmp ne i64 %freed1664, 0
  br i1 %freed_b1665, label %br_unique385, label %br_shared386
br_shared386:
  call void @march_incrc(ptr %fv1663)
  br label %br_body387
br_unique385:
  br label %br_body387
br_body387:
  %ld1666 = load ptr, ptr %$f865.addr
  %fd.addr = alloca ptr
  store ptr %ld1666, ptr %fd.addr
  %ld1667 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1667)
  %ld1668 = load ptr, ptr %tcp_send_all.addr
  %fp1669 = getelementptr i8, ptr %ld1668, i64 16
  %fv1670 = load ptr, ptr %fp1669, align 8
  %ld1671 = load ptr, ptr %fd.addr
  %ld1672 = load ptr, ptr %raw_request.addr
  %cr1673 = call ptr (ptr, ptr, ptr) %fv1670(ptr %ld1668, ptr %ld1671, ptr %ld1672)
  %$t847.addr = alloca ptr
  store ptr %cr1673, ptr %$t847.addr
  %ld1674 = load ptr, ptr %$t847.addr
  %res_slot1675 = alloca ptr
  %tgp1676 = getelementptr i8, ptr %ld1674, i64 8
  %tag1677 = load i32, ptr %tgp1676, align 4
  switch i32 %tag1677, label %case_default389 [
      i32 0, label %case_br390
      i32 0, label %case_br391
  ]
case_br390:
  %fp1678 = getelementptr i8, ptr %ld1674, i64 16
  %fv1679 = load ptr, ptr %fp1678, align 8
  %$f862.addr = alloca ptr
  store ptr %fv1679, ptr %$f862.addr
  %freed1680 = call i64 @march_decrc_freed(ptr %ld1674)
  %freed_b1681 = icmp ne i64 %freed1680, 0
  br i1 %freed_b1681, label %br_unique392, label %br_shared393
br_shared393:
  call void @march_incrc(ptr %fv1679)
  br label %br_body394
br_unique392:
  br label %br_body394
br_body394:
  %ld1682 = load ptr, ptr %$f862.addr
  %msg_1.addr = alloca ptr
  store ptr %ld1682, ptr %msg_1.addr
  %ld1683 = load ptr, ptr %tcp_close.addr
  %fp1684 = getelementptr i8, ptr %ld1683, i64 16
  %fv1685 = load ptr, ptr %fp1684, align 8
  %ld1686 = load ptr, ptr %fd.addr
  %cr1687 = call ptr (ptr, ptr) %fv1685(ptr %ld1683, ptr %ld1686)
  %hp1688 = call ptr @march_alloc(i64 24)
  %tgp1689 = getelementptr i8, ptr %hp1688, i64 8
  store i32 2, ptr %tgp1689, align 4
  %ld1690 = load ptr, ptr %msg_1.addr
  %fp1691 = getelementptr i8, ptr %hp1688, i64 16
  store ptr %ld1690, ptr %fp1691, align 8
  %$t848.addr = alloca ptr
  store ptr %hp1688, ptr %$t848.addr
  %hp1692 = call ptr @march_alloc(i64 24)
  %tgp1693 = getelementptr i8, ptr %hp1692, i64 8
  store i32 1, ptr %tgp1693, align 4
  %ld1694 = load ptr, ptr %$t848.addr
  %fp1695 = getelementptr i8, ptr %hp1692, i64 16
  store ptr %ld1694, ptr %fp1695, align 8
  store ptr %hp1692, ptr %res_slot1675
  br label %case_merge388
case_br391:
  %fp1696 = getelementptr i8, ptr %ld1674, i64 16
  %fv1697 = load ptr, ptr %fp1696, align 8
  %$f863.addr = alloca ptr
  store ptr %fv1697, ptr %$f863.addr
  %freed1698 = call i64 @march_decrc_freed(ptr %ld1674)
  %freed_b1699 = icmp ne i64 %freed1698, 0
  br i1 %freed_b1699, label %br_unique395, label %br_shared396
br_shared396:
  call void @march_incrc(ptr %fv1697)
  br label %br_body397
br_unique395:
  br label %br_body397
br_body397:
  %ld1700 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld1700)
  %ld1701 = load ptr, ptr %tcp_recv_all.addr
  %fp1702 = getelementptr i8, ptr %ld1701, i64 16
  %fv1703 = load ptr, ptr %fp1702, align 8
  %ld1704 = load ptr, ptr %fd.addr
  %cv1705 = inttoptr i64 1048576 to ptr
  %cv1706 = inttoptr i64 30000 to ptr
  %cr1707 = call ptr (ptr, ptr, ptr, ptr) %fv1703(ptr %ld1701, ptr %ld1704, ptr %cv1705, ptr %cv1706)
  %$t849.addr = alloca ptr
  store ptr %cr1707, ptr %$t849.addr
  %ld1708 = load ptr, ptr %$t849.addr
  %res_slot1709 = alloca ptr
  %tgp1710 = getelementptr i8, ptr %ld1708, i64 8
  %tag1711 = load i32, ptr %tgp1710, align 4
  switch i32 %tag1711, label %case_default399 [
      i32 0, label %case_br400
      i32 0, label %case_br401
  ]
case_br400:
  %fp1712 = getelementptr i8, ptr %ld1708, i64 16
  %fv1713 = load ptr, ptr %fp1712, align 8
  %$f860.addr = alloca ptr
  store ptr %fv1713, ptr %$f860.addr
  %freed1714 = call i64 @march_decrc_freed(ptr %ld1708)
  %freed_b1715 = icmp ne i64 %freed1714, 0
  br i1 %freed_b1715, label %br_unique402, label %br_shared403
br_shared403:
  call void @march_incrc(ptr %fv1713)
  br label %br_body404
br_unique402:
  br label %br_body404
br_body404:
  %ld1716 = load ptr, ptr %$f860.addr
  %msg_2.addr = alloca ptr
  store ptr %ld1716, ptr %msg_2.addr
  %ld1717 = load ptr, ptr %tcp_close.addr
  %fp1718 = getelementptr i8, ptr %ld1717, i64 16
  %fv1719 = load ptr, ptr %fp1718, align 8
  %ld1720 = load ptr, ptr %fd.addr
  %cr1721 = call ptr (ptr, ptr) %fv1719(ptr %ld1717, ptr %ld1720)
  %hp1722 = call ptr @march_alloc(i64 24)
  %tgp1723 = getelementptr i8, ptr %hp1722, i64 8
  store i32 3, ptr %tgp1723, align 4
  %ld1724 = load ptr, ptr %msg_2.addr
  %fp1725 = getelementptr i8, ptr %hp1722, i64 16
  store ptr %ld1724, ptr %fp1725, align 8
  %$t850.addr = alloca ptr
  store ptr %hp1722, ptr %$t850.addr
  %hp1726 = call ptr @march_alloc(i64 24)
  %tgp1727 = getelementptr i8, ptr %hp1726, i64 8
  store i32 1, ptr %tgp1727, align 4
  %ld1728 = load ptr, ptr %$t850.addr
  %fp1729 = getelementptr i8, ptr %hp1726, i64 16
  store ptr %ld1728, ptr %fp1729, align 8
  store ptr %hp1726, ptr %res_slot1709
  br label %case_merge398
case_br401:
  %fp1730 = getelementptr i8, ptr %ld1708, i64 16
  %fv1731 = load ptr, ptr %fp1730, align 8
  %$f861.addr = alloca ptr
  store ptr %fv1731, ptr %$f861.addr
  %freed1732 = call i64 @march_decrc_freed(ptr %ld1708)
  %freed_b1733 = icmp ne i64 %freed1732, 0
  br i1 %freed_b1733, label %br_unique405, label %br_shared406
br_shared406:
  call void @march_incrc(ptr %fv1731)
  br label %br_body407
br_unique405:
  br label %br_body407
br_body407:
  %ld1734 = load ptr, ptr %$f861.addr
  %raw_response.addr = alloca ptr
  store ptr %ld1734, ptr %raw_response.addr
  %ld1735 = load ptr, ptr %tcp_close.addr
  %fp1736 = getelementptr i8, ptr %ld1735, i64 16
  %fv1737 = load ptr, ptr %fp1736, align 8
  %ld1738 = load ptr, ptr %fd.addr
  %cr1739 = call ptr (ptr, ptr) %fv1737(ptr %ld1735, ptr %ld1738)
  %ld1740 = load ptr, ptr %http_parse_response.addr
  %fp1741 = getelementptr i8, ptr %ld1740, i64 16
  %fv1742 = load ptr, ptr %fp1741, align 8
  %ld1743 = load ptr, ptr %raw_response.addr
  %cr1744 = call ptr (ptr, ptr) %fv1742(ptr %ld1740, ptr %ld1743)
  %$t851.addr = alloca ptr
  store ptr %cr1744, ptr %$t851.addr
  %ld1745 = load ptr, ptr %$t851.addr
  %res_slot1746 = alloca ptr
  %tgp1747 = getelementptr i8, ptr %ld1745, i64 8
  %tag1748 = load i32, ptr %tgp1747, align 4
  switch i32 %tag1748, label %case_default409 [
      i32 0, label %case_br410
      i32 0, label %case_br411
  ]
case_br410:
  %fp1749 = getelementptr i8, ptr %ld1745, i64 16
  %fv1750 = load ptr, ptr %fp1749, align 8
  %$f855.addr = alloca ptr
  store ptr %fv1750, ptr %$f855.addr
  %freed1751 = call i64 @march_decrc_freed(ptr %ld1745)
  %freed_b1752 = icmp ne i64 %freed1751, 0
  br i1 %freed_b1752, label %br_unique412, label %br_shared413
br_shared413:
  call void @march_incrc(ptr %fv1750)
  br label %br_body414
br_unique412:
  br label %br_body414
br_body414:
  %ld1753 = load ptr, ptr %$f855.addr
  %msg_3.addr = alloca ptr
  store ptr %ld1753, ptr %msg_3.addr
  %hp1754 = call ptr @march_alloc(i64 24)
  %tgp1755 = getelementptr i8, ptr %hp1754, i64 8
  store i32 0, ptr %tgp1755, align 4
  %ld1756 = load ptr, ptr %msg_3.addr
  %fp1757 = getelementptr i8, ptr %hp1754, i64 16
  store ptr %ld1756, ptr %fp1757, align 8
  %$t852.addr = alloca ptr
  store ptr %hp1754, ptr %$t852.addr
  %hp1758 = call ptr @march_alloc(i64 24)
  %tgp1759 = getelementptr i8, ptr %hp1758, i64 8
  store i32 1, ptr %tgp1759, align 4
  %ld1760 = load ptr, ptr %$t852.addr
  %fp1761 = getelementptr i8, ptr %hp1758, i64 16
  store ptr %ld1760, ptr %fp1761, align 8
  store ptr %hp1758, ptr %res_slot1746
  br label %case_merge408
case_br411:
  %fp1762 = getelementptr i8, ptr %ld1745, i64 16
  %fv1763 = load ptr, ptr %fp1762, align 8
  %$f856.addr = alloca ptr
  store ptr %fv1763, ptr %$f856.addr
  %freed1764 = call i64 @march_decrc_freed(ptr %ld1745)
  %freed_b1765 = icmp ne i64 %freed1764, 0
  br i1 %freed_b1765, label %br_unique415, label %br_shared416
br_shared416:
  call void @march_incrc(ptr %fv1763)
  br label %br_body417
br_unique415:
  br label %br_body417
br_body417:
  %ld1766 = load ptr, ptr %$f856.addr
  %res_slot1767 = alloca ptr
  %tgp1768 = getelementptr i8, ptr %ld1766, i64 8
  %tag1769 = load i32, ptr %tgp1768, align 4
  switch i32 %tag1769, label %case_default419 [
      i32 0, label %case_br420
  ]
case_br420:
  %fp1770 = getelementptr i8, ptr %ld1766, i64 16
  %fv1771 = load ptr, ptr %fp1770, align 8
  %$f857.addr = alloca ptr
  store ptr %fv1771, ptr %$f857.addr
  %fp1772 = getelementptr i8, ptr %ld1766, i64 24
  %fv1773 = load ptr, ptr %fp1772, align 8
  %$f858.addr = alloca ptr
  store ptr %fv1773, ptr %$f858.addr
  %fp1774 = getelementptr i8, ptr %ld1766, i64 32
  %fv1775 = load ptr, ptr %fp1774, align 8
  %$f859.addr = alloca ptr
  store ptr %fv1775, ptr %$f859.addr
  %freed1776 = call i64 @march_decrc_freed(ptr %ld1766)
  %freed_b1777 = icmp ne i64 %freed1776, 0
  br i1 %freed_b1777, label %br_unique421, label %br_shared422
br_shared422:
  call void @march_incrc(ptr %fv1775)
  call void @march_incrc(ptr %fv1773)
  call void @march_incrc(ptr %fv1771)
  br label %br_body423
br_unique421:
  br label %br_body423
br_body423:
  %ld1778 = load ptr, ptr %$f859.addr
  %resp_body.addr = alloca ptr
  store ptr %ld1778, ptr %resp_body.addr
  %ld1779 = load ptr, ptr %$f858.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld1779, ptr %resp_headers.addr
  %ld1780 = load ptr, ptr %$f857.addr
  %status_code.addr = alloca ptr
  store ptr %ld1780, ptr %status_code.addr
  %hp1781 = call ptr @march_alloc(i64 24)
  %tgp1782 = getelementptr i8, ptr %hp1781, i64 8
  store i32 0, ptr %tgp1782, align 4
  %ld1783 = load ptr, ptr %status_code.addr
  %fp1784 = getelementptr i8, ptr %hp1781, i64 16
  store ptr %ld1783, ptr %fp1784, align 8
  %$t853.addr = alloca ptr
  store ptr %hp1781, ptr %$t853.addr
  %hp1785 = call ptr @march_alloc(i64 40)
  %tgp1786 = getelementptr i8, ptr %hp1785, i64 8
  store i32 0, ptr %tgp1786, align 4
  %ld1787 = load ptr, ptr %$t853.addr
  %fp1788 = getelementptr i8, ptr %hp1785, i64 16
  store ptr %ld1787, ptr %fp1788, align 8
  %ld1789 = load ptr, ptr %resp_headers.addr
  %fp1790 = getelementptr i8, ptr %hp1785, i64 24
  store ptr %ld1789, ptr %fp1790, align 8
  %ld1791 = load ptr, ptr %resp_body.addr
  %fp1792 = getelementptr i8, ptr %hp1785, i64 32
  store ptr %ld1791, ptr %fp1792, align 8
  %$t854.addr = alloca ptr
  store ptr %hp1785, ptr %$t854.addr
  %hp1793 = call ptr @march_alloc(i64 24)
  %tgp1794 = getelementptr i8, ptr %hp1793, i64 8
  store i32 0, ptr %tgp1794, align 4
  %ld1795 = load ptr, ptr %$t854.addr
  %fp1796 = getelementptr i8, ptr %hp1793, i64 16
  store ptr %ld1795, ptr %fp1796, align 8
  store ptr %hp1793, ptr %res_slot1767
  br label %case_merge418
case_default419:
  unreachable
case_merge418:
  %case_r1797 = load ptr, ptr %res_slot1767
  store ptr %case_r1797, ptr %res_slot1746
  br label %case_merge408
case_default409:
  unreachable
case_merge408:
  %case_r1798 = load ptr, ptr %res_slot1746
  store ptr %case_r1798, ptr %res_slot1709
  br label %case_merge398
case_default399:
  unreachable
case_merge398:
  %case_r1799 = load ptr, ptr %res_slot1709
  store ptr %case_r1799, ptr %res_slot1675
  br label %case_merge388
case_default389:
  unreachable
case_merge388:
  %case_r1800 = load ptr, ptr %res_slot1675
  store ptr %case_r1800, ptr %res_slot1646
  br label %case_merge378
case_default379:
  unreachable
case_merge378:
  %case_r1801 = load ptr, ptr %res_slot1646
  ret ptr %case_r1801
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1802 = load ptr, ptr %req.addr
  %res_slot1803 = alloca ptr
  %tgp1804 = getelementptr i8, ptr %ld1802, i64 8
  %tag1805 = load i32, ptr %tgp1804, align 4
  switch i32 %tag1805, label %case_default425 [
      i32 0, label %case_br426
  ]
case_br426:
  %fp1806 = getelementptr i8, ptr %ld1802, i64 16
  %fv1807 = load ptr, ptr %fp1806, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1807, ptr %$f591.addr
  %fp1808 = getelementptr i8, ptr %ld1802, i64 24
  %fv1809 = load ptr, ptr %fp1808, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1809, ptr %$f592.addr
  %fp1810 = getelementptr i8, ptr %ld1802, i64 32
  %fv1811 = load ptr, ptr %fp1810, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1811, ptr %$f593.addr
  %fp1812 = getelementptr i8, ptr %ld1802, i64 40
  %fv1813 = load ptr, ptr %fp1812, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1813, ptr %$f594.addr
  %fp1814 = getelementptr i8, ptr %ld1802, i64 48
  %fv1815 = load ptr, ptr %fp1814, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1815, ptr %$f595.addr
  %fp1816 = getelementptr i8, ptr %ld1802, i64 56
  %fv1817 = load ptr, ptr %fp1816, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1817, ptr %$f596.addr
  %fp1818 = getelementptr i8, ptr %ld1802, i64 64
  %fv1819 = load ptr, ptr %fp1818, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1819, ptr %$f597.addr
  %fp1820 = getelementptr i8, ptr %ld1802, i64 72
  %fv1821 = load ptr, ptr %fp1820, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1821, ptr %$f598.addr
  %freed1822 = call i64 @march_decrc_freed(ptr %ld1802)
  %freed_b1823 = icmp ne i64 %freed1822, 0
  br i1 %freed_b1823, label %br_unique427, label %br_shared428
br_shared428:
  call void @march_incrc(ptr %fv1821)
  call void @march_incrc(ptr %fv1819)
  call void @march_incrc(ptr %fv1817)
  call void @march_incrc(ptr %fv1815)
  call void @march_incrc(ptr %fv1813)
  call void @march_incrc(ptr %fv1811)
  call void @march_incrc(ptr %fv1809)
  call void @march_incrc(ptr %fv1807)
  br label %br_body429
br_unique427:
  br label %br_body429
br_body429:
  %ld1824 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1824, ptr %h.addr
  %ld1825 = load ptr, ptr %h.addr
  store ptr %ld1825, ptr %res_slot1803
  br label %case_merge424
case_default425:
  unreachable
case_merge424:
  %case_r1826 = load ptr, ptr %res_slot1803
  ret ptr %case_r1826
}

define ptr @Http.query$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1827 = load ptr, ptr %req.addr
  %res_slot1828 = alloca ptr
  %tgp1829 = getelementptr i8, ptr %ld1827, i64 8
  %tag1830 = load i32, ptr %tgp1829, align 4
  switch i32 %tag1830, label %case_default431 [
      i32 0, label %case_br432
  ]
case_br432:
  %fp1831 = getelementptr i8, ptr %ld1827, i64 16
  %fv1832 = load ptr, ptr %fp1831, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1832, ptr %$f583.addr
  %fp1833 = getelementptr i8, ptr %ld1827, i64 24
  %fv1834 = load ptr, ptr %fp1833, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1834, ptr %$f584.addr
  %fp1835 = getelementptr i8, ptr %ld1827, i64 32
  %fv1836 = load ptr, ptr %fp1835, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1836, ptr %$f585.addr
  %fp1837 = getelementptr i8, ptr %ld1827, i64 40
  %fv1838 = load ptr, ptr %fp1837, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1838, ptr %$f586.addr
  %fp1839 = getelementptr i8, ptr %ld1827, i64 48
  %fv1840 = load ptr, ptr %fp1839, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1840, ptr %$f587.addr
  %fp1841 = getelementptr i8, ptr %ld1827, i64 56
  %fv1842 = load ptr, ptr %fp1841, align 8
  %$f588.addr = alloca ptr
  store ptr %fv1842, ptr %$f588.addr
  %fp1843 = getelementptr i8, ptr %ld1827, i64 64
  %fv1844 = load ptr, ptr %fp1843, align 8
  %$f589.addr = alloca ptr
  store ptr %fv1844, ptr %$f589.addr
  %fp1845 = getelementptr i8, ptr %ld1827, i64 72
  %fv1846 = load ptr, ptr %fp1845, align 8
  %$f590.addr = alloca ptr
  store ptr %fv1846, ptr %$f590.addr
  %freed1847 = call i64 @march_decrc_freed(ptr %ld1827)
  %freed_b1848 = icmp ne i64 %freed1847, 0
  br i1 %freed_b1848, label %br_unique433, label %br_shared434
br_shared434:
  call void @march_incrc(ptr %fv1846)
  call void @march_incrc(ptr %fv1844)
  call void @march_incrc(ptr %fv1842)
  call void @march_incrc(ptr %fv1840)
  call void @march_incrc(ptr %fv1838)
  call void @march_incrc(ptr %fv1836)
  call void @march_incrc(ptr %fv1834)
  call void @march_incrc(ptr %fv1832)
  br label %br_body435
br_unique433:
  br label %br_body435
br_body435:
  %ld1849 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld1849, ptr %q.addr
  %ld1850 = load ptr, ptr %q.addr
  store ptr %ld1850, ptr %res_slot1828
  br label %case_merge430
case_default431:
  unreachable
case_merge430:
  %case_r1851 = load ptr, ptr %res_slot1828
  ret ptr %case_r1851
}

define ptr @Http.path$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1852 = load ptr, ptr %req.addr
  %res_slot1853 = alloca ptr
  %tgp1854 = getelementptr i8, ptr %ld1852, i64 8
  %tag1855 = load i32, ptr %tgp1854, align 4
  switch i32 %tag1855, label %case_default437 [
      i32 0, label %case_br438
  ]
case_br438:
  %fp1856 = getelementptr i8, ptr %ld1852, i64 16
  %fv1857 = load ptr, ptr %fp1856, align 8
  %$f575.addr = alloca ptr
  store ptr %fv1857, ptr %$f575.addr
  %fp1858 = getelementptr i8, ptr %ld1852, i64 24
  %fv1859 = load ptr, ptr %fp1858, align 8
  %$f576.addr = alloca ptr
  store ptr %fv1859, ptr %$f576.addr
  %fp1860 = getelementptr i8, ptr %ld1852, i64 32
  %fv1861 = load ptr, ptr %fp1860, align 8
  %$f577.addr = alloca ptr
  store ptr %fv1861, ptr %$f577.addr
  %fp1862 = getelementptr i8, ptr %ld1852, i64 40
  %fv1863 = load ptr, ptr %fp1862, align 8
  %$f578.addr = alloca ptr
  store ptr %fv1863, ptr %$f578.addr
  %fp1864 = getelementptr i8, ptr %ld1852, i64 48
  %fv1865 = load ptr, ptr %fp1864, align 8
  %$f579.addr = alloca ptr
  store ptr %fv1865, ptr %$f579.addr
  %fp1866 = getelementptr i8, ptr %ld1852, i64 56
  %fv1867 = load ptr, ptr %fp1866, align 8
  %$f580.addr = alloca ptr
  store ptr %fv1867, ptr %$f580.addr
  %fp1868 = getelementptr i8, ptr %ld1852, i64 64
  %fv1869 = load ptr, ptr %fp1868, align 8
  %$f581.addr = alloca ptr
  store ptr %fv1869, ptr %$f581.addr
  %fp1870 = getelementptr i8, ptr %ld1852, i64 72
  %fv1871 = load ptr, ptr %fp1870, align 8
  %$f582.addr = alloca ptr
  store ptr %fv1871, ptr %$f582.addr
  %freed1872 = call i64 @march_decrc_freed(ptr %ld1852)
  %freed_b1873 = icmp ne i64 %freed1872, 0
  br i1 %freed_b1873, label %br_unique439, label %br_shared440
br_shared440:
  call void @march_incrc(ptr %fv1871)
  call void @march_incrc(ptr %fv1869)
  call void @march_incrc(ptr %fv1867)
  call void @march_incrc(ptr %fv1865)
  call void @march_incrc(ptr %fv1863)
  call void @march_incrc(ptr %fv1861)
  call void @march_incrc(ptr %fv1859)
  call void @march_incrc(ptr %fv1857)
  br label %br_body441
br_unique439:
  br label %br_body441
br_body441:
  %ld1874 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld1874, ptr %p.addr
  %ld1875 = load ptr, ptr %p.addr
  store ptr %ld1875, ptr %res_slot1853
  br label %case_merge436
case_default437:
  unreachable
case_merge436:
  %case_r1876 = load ptr, ptr %res_slot1853
  ret ptr %case_r1876
}

define ptr @Http.scheme$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1877 = load ptr, ptr %req.addr
  %res_slot1878 = alloca ptr
  %tgp1879 = getelementptr i8, ptr %ld1877, i64 8
  %tag1880 = load i32, ptr %tgp1879, align 4
  switch i32 %tag1880, label %case_default443 [
      i32 0, label %case_br444
  ]
case_br444:
  %fp1881 = getelementptr i8, ptr %ld1877, i64 16
  %fv1882 = load ptr, ptr %fp1881, align 8
  %$f551.addr = alloca ptr
  store ptr %fv1882, ptr %$f551.addr
  %fp1883 = getelementptr i8, ptr %ld1877, i64 24
  %fv1884 = load ptr, ptr %fp1883, align 8
  %$f552.addr = alloca ptr
  store ptr %fv1884, ptr %$f552.addr
  %fp1885 = getelementptr i8, ptr %ld1877, i64 32
  %fv1886 = load ptr, ptr %fp1885, align 8
  %$f553.addr = alloca ptr
  store ptr %fv1886, ptr %$f553.addr
  %fp1887 = getelementptr i8, ptr %ld1877, i64 40
  %fv1888 = load ptr, ptr %fp1887, align 8
  %$f554.addr = alloca ptr
  store ptr %fv1888, ptr %$f554.addr
  %fp1889 = getelementptr i8, ptr %ld1877, i64 48
  %fv1890 = load ptr, ptr %fp1889, align 8
  %$f555.addr = alloca ptr
  store ptr %fv1890, ptr %$f555.addr
  %fp1891 = getelementptr i8, ptr %ld1877, i64 56
  %fv1892 = load ptr, ptr %fp1891, align 8
  %$f556.addr = alloca ptr
  store ptr %fv1892, ptr %$f556.addr
  %fp1893 = getelementptr i8, ptr %ld1877, i64 64
  %fv1894 = load ptr, ptr %fp1893, align 8
  %$f557.addr = alloca ptr
  store ptr %fv1894, ptr %$f557.addr
  %fp1895 = getelementptr i8, ptr %ld1877, i64 72
  %fv1896 = load ptr, ptr %fp1895, align 8
  %$f558.addr = alloca ptr
  store ptr %fv1896, ptr %$f558.addr
  %freed1897 = call i64 @march_decrc_freed(ptr %ld1877)
  %freed_b1898 = icmp ne i64 %freed1897, 0
  br i1 %freed_b1898, label %br_unique445, label %br_shared446
br_shared446:
  call void @march_incrc(ptr %fv1896)
  call void @march_incrc(ptr %fv1894)
  call void @march_incrc(ptr %fv1892)
  call void @march_incrc(ptr %fv1890)
  call void @march_incrc(ptr %fv1888)
  call void @march_incrc(ptr %fv1886)
  call void @march_incrc(ptr %fv1884)
  call void @march_incrc(ptr %fv1882)
  br label %br_body447
br_unique445:
  br label %br_body447
br_body447:
  %ld1899 = load ptr, ptr %$f552.addr
  %s.addr = alloca ptr
  store ptr %ld1899, ptr %s.addr
  %ld1900 = load ptr, ptr %s.addr
  store ptr %ld1900, ptr %res_slot1878
  br label %case_merge442
case_default443:
  unreachable
case_merge442:
  %case_r1901 = load ptr, ptr %res_slot1878
  ret ptr %case_r1901
}

define ptr @Http.set_body$Request_String$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld1902 = load ptr, ptr %req.addr
  %res_slot1903 = alloca ptr
  %tgp1904 = getelementptr i8, ptr %ld1902, i64 8
  %tag1905 = load i32, ptr %tgp1904, align 4
  switch i32 %tag1905, label %case_default449 [
      i32 0, label %case_br450
  ]
case_br450:
  %fp1906 = getelementptr i8, ptr %ld1902, i64 16
  %fv1907 = load ptr, ptr %fp1906, align 8
  %$f648.addr = alloca ptr
  store ptr %fv1907, ptr %$f648.addr
  %fp1908 = getelementptr i8, ptr %ld1902, i64 24
  %fv1909 = load ptr, ptr %fp1908, align 8
  %$f649.addr = alloca ptr
  store ptr %fv1909, ptr %$f649.addr
  %fp1910 = getelementptr i8, ptr %ld1902, i64 32
  %fv1911 = load ptr, ptr %fp1910, align 8
  %$f650.addr = alloca ptr
  store ptr %fv1911, ptr %$f650.addr
  %fp1912 = getelementptr i8, ptr %ld1902, i64 40
  %fv1913 = load ptr, ptr %fp1912, align 8
  %$f651.addr = alloca ptr
  store ptr %fv1913, ptr %$f651.addr
  %fp1914 = getelementptr i8, ptr %ld1902, i64 48
  %fv1915 = load ptr, ptr %fp1914, align 8
  %$f652.addr = alloca ptr
  store ptr %fv1915, ptr %$f652.addr
  %fp1916 = getelementptr i8, ptr %ld1902, i64 56
  %fv1917 = load ptr, ptr %fp1916, align 8
  %$f653.addr = alloca ptr
  store ptr %fv1917, ptr %$f653.addr
  %fp1918 = getelementptr i8, ptr %ld1902, i64 64
  %fv1919 = load ptr, ptr %fp1918, align 8
  %$f654.addr = alloca ptr
  store ptr %fv1919, ptr %$f654.addr
  %fp1920 = getelementptr i8, ptr %ld1902, i64 72
  %fv1921 = load ptr, ptr %fp1920, align 8
  %$f655.addr = alloca ptr
  store ptr %fv1921, ptr %$f655.addr
  %ld1922 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld1922, ptr %hd.addr
  %ld1923 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld1923, ptr %q.addr
  %ld1924 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld1924, ptr %pa.addr
  %ld1925 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld1925, ptr %p.addr
  %ld1926 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld1926, ptr %h.addr
  %ld1927 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld1927, ptr %sc.addr
  %ld1928 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld1928, ptr %m.addr
  %ld1929 = load ptr, ptr %req.addr
  %ld1930 = load ptr, ptr %m.addr
  %ld1931 = load ptr, ptr %sc.addr
  %ld1932 = load ptr, ptr %h.addr
  %ld1933 = load ptr, ptr %p.addr
  %ld1934 = load ptr, ptr %pa.addr
  %ld1935 = load ptr, ptr %q.addr
  %ld1936 = load ptr, ptr %hd.addr
  %ld1937 = load ptr, ptr %new_body.addr
  %rc1938 = load i64, ptr %ld1929, align 8
  %uniq1939 = icmp eq i64 %rc1938, 1
  %fbip_slot1940 = alloca ptr
  br i1 %uniq1939, label %fbip_reuse451, label %fbip_fresh452
fbip_reuse451:
  %tgp1941 = getelementptr i8, ptr %ld1929, i64 8
  store i32 0, ptr %tgp1941, align 4
  %fp1942 = getelementptr i8, ptr %ld1929, i64 16
  store ptr %ld1930, ptr %fp1942, align 8
  %fp1943 = getelementptr i8, ptr %ld1929, i64 24
  store ptr %ld1931, ptr %fp1943, align 8
  %fp1944 = getelementptr i8, ptr %ld1929, i64 32
  store ptr %ld1932, ptr %fp1944, align 8
  %fp1945 = getelementptr i8, ptr %ld1929, i64 40
  store ptr %ld1933, ptr %fp1945, align 8
  %fp1946 = getelementptr i8, ptr %ld1929, i64 48
  store ptr %ld1934, ptr %fp1946, align 8
  %fp1947 = getelementptr i8, ptr %ld1929, i64 56
  store ptr %ld1935, ptr %fp1947, align 8
  %fp1948 = getelementptr i8, ptr %ld1929, i64 64
  store ptr %ld1936, ptr %fp1948, align 8
  %fp1949 = getelementptr i8, ptr %ld1929, i64 72
  store ptr %ld1937, ptr %fp1949, align 8
  store ptr %ld1929, ptr %fbip_slot1940
  br label %fbip_merge453
fbip_fresh452:
  call void @march_decrc(ptr %ld1929)
  %hp1950 = call ptr @march_alloc(i64 80)
  %tgp1951 = getelementptr i8, ptr %hp1950, i64 8
  store i32 0, ptr %tgp1951, align 4
  %fp1952 = getelementptr i8, ptr %hp1950, i64 16
  store ptr %ld1930, ptr %fp1952, align 8
  %fp1953 = getelementptr i8, ptr %hp1950, i64 24
  store ptr %ld1931, ptr %fp1953, align 8
  %fp1954 = getelementptr i8, ptr %hp1950, i64 32
  store ptr %ld1932, ptr %fp1954, align 8
  %fp1955 = getelementptr i8, ptr %hp1950, i64 40
  store ptr %ld1933, ptr %fp1955, align 8
  %fp1956 = getelementptr i8, ptr %hp1950, i64 48
  store ptr %ld1934, ptr %fp1956, align 8
  %fp1957 = getelementptr i8, ptr %hp1950, i64 56
  store ptr %ld1935, ptr %fp1957, align 8
  %fp1958 = getelementptr i8, ptr %hp1950, i64 64
  store ptr %ld1936, ptr %fp1958, align 8
  %fp1959 = getelementptr i8, ptr %hp1950, i64 72
  store ptr %ld1937, ptr %fp1959, align 8
  store ptr %hp1950, ptr %fbip_slot1940
  br label %fbip_merge453
fbip_merge453:
  %fbip_r1960 = load ptr, ptr %fbip_slot1940
  store ptr %fbip_r1960, ptr %res_slot1903
  br label %case_merge448
case_default449:
  unreachable
case_merge448:
  %case_r1961 = load ptr, ptr %res_slot1903
  ret ptr %case_r1961
}

define ptr @Http.set_method$Request_String$Method(ptr %req.arg, ptr %m.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %m.addr = alloca ptr
  store ptr %m.arg, ptr %m.addr
  %ld1962 = load ptr, ptr %req.addr
  %res_slot1963 = alloca ptr
  %tgp1964 = getelementptr i8, ptr %ld1962, i64 8
  %tag1965 = load i32, ptr %tgp1964, align 4
  switch i32 %tag1965, label %case_default455 [
      i32 0, label %case_br456
  ]
case_br456:
  %fp1966 = getelementptr i8, ptr %ld1962, i64 16
  %fv1967 = load ptr, ptr %fp1966, align 8
  %$f607.addr = alloca ptr
  store ptr %fv1967, ptr %$f607.addr
  %fp1968 = getelementptr i8, ptr %ld1962, i64 24
  %fv1969 = load ptr, ptr %fp1968, align 8
  %$f608.addr = alloca ptr
  store ptr %fv1969, ptr %$f608.addr
  %fp1970 = getelementptr i8, ptr %ld1962, i64 32
  %fv1971 = load ptr, ptr %fp1970, align 8
  %$f609.addr = alloca ptr
  store ptr %fv1971, ptr %$f609.addr
  %fp1972 = getelementptr i8, ptr %ld1962, i64 40
  %fv1973 = load ptr, ptr %fp1972, align 8
  %$f610.addr = alloca ptr
  store ptr %fv1973, ptr %$f610.addr
  %fp1974 = getelementptr i8, ptr %ld1962, i64 48
  %fv1975 = load ptr, ptr %fp1974, align 8
  %$f611.addr = alloca ptr
  store ptr %fv1975, ptr %$f611.addr
  %fp1976 = getelementptr i8, ptr %ld1962, i64 56
  %fv1977 = load ptr, ptr %fp1976, align 8
  %$f612.addr = alloca ptr
  store ptr %fv1977, ptr %$f612.addr
  %fp1978 = getelementptr i8, ptr %ld1962, i64 64
  %fv1979 = load ptr, ptr %fp1978, align 8
  %$f613.addr = alloca ptr
  store ptr %fv1979, ptr %$f613.addr
  %fp1980 = getelementptr i8, ptr %ld1962, i64 72
  %fv1981 = load ptr, ptr %fp1980, align 8
  %$f614.addr = alloca ptr
  store ptr %fv1981, ptr %$f614.addr
  %ld1982 = load ptr, ptr %$f614.addr
  %bd.addr = alloca ptr
  store ptr %ld1982, ptr %bd.addr
  %ld1983 = load ptr, ptr %$f613.addr
  %hd.addr = alloca ptr
  store ptr %ld1983, ptr %hd.addr
  %ld1984 = load ptr, ptr %$f612.addr
  %q.addr = alloca ptr
  store ptr %ld1984, ptr %q.addr
  %ld1985 = load ptr, ptr %$f611.addr
  %pa.addr = alloca ptr
  store ptr %ld1985, ptr %pa.addr
  %ld1986 = load ptr, ptr %$f610.addr
  %p.addr = alloca ptr
  store ptr %ld1986, ptr %p.addr
  %ld1987 = load ptr, ptr %$f609.addr
  %h.addr = alloca ptr
  store ptr %ld1987, ptr %h.addr
  %ld1988 = load ptr, ptr %$f608.addr
  %sc.addr = alloca ptr
  store ptr %ld1988, ptr %sc.addr
  %ld1989 = load ptr, ptr %req.addr
  %ld1990 = load ptr, ptr %m.addr
  %ld1991 = load ptr, ptr %sc.addr
  %ld1992 = load ptr, ptr %h.addr
  %ld1993 = load ptr, ptr %p.addr
  %ld1994 = load ptr, ptr %pa.addr
  %ld1995 = load ptr, ptr %q.addr
  %ld1996 = load ptr, ptr %hd.addr
  %ld1997 = load ptr, ptr %bd.addr
  %rc1998 = load i64, ptr %ld1989, align 8
  %uniq1999 = icmp eq i64 %rc1998, 1
  %fbip_slot2000 = alloca ptr
  br i1 %uniq1999, label %fbip_reuse457, label %fbip_fresh458
fbip_reuse457:
  %tgp2001 = getelementptr i8, ptr %ld1989, i64 8
  store i32 0, ptr %tgp2001, align 4
  %fp2002 = getelementptr i8, ptr %ld1989, i64 16
  store ptr %ld1990, ptr %fp2002, align 8
  %fp2003 = getelementptr i8, ptr %ld1989, i64 24
  store ptr %ld1991, ptr %fp2003, align 8
  %fp2004 = getelementptr i8, ptr %ld1989, i64 32
  store ptr %ld1992, ptr %fp2004, align 8
  %fp2005 = getelementptr i8, ptr %ld1989, i64 40
  store ptr %ld1993, ptr %fp2005, align 8
  %fp2006 = getelementptr i8, ptr %ld1989, i64 48
  store ptr %ld1994, ptr %fp2006, align 8
  %fp2007 = getelementptr i8, ptr %ld1989, i64 56
  store ptr %ld1995, ptr %fp2007, align 8
  %fp2008 = getelementptr i8, ptr %ld1989, i64 64
  store ptr %ld1996, ptr %fp2008, align 8
  %fp2009 = getelementptr i8, ptr %ld1989, i64 72
  store ptr %ld1997, ptr %fp2009, align 8
  store ptr %ld1989, ptr %fbip_slot2000
  br label %fbip_merge459
fbip_fresh458:
  call void @march_decrc(ptr %ld1989)
  %hp2010 = call ptr @march_alloc(i64 80)
  %tgp2011 = getelementptr i8, ptr %hp2010, i64 8
  store i32 0, ptr %tgp2011, align 4
  %fp2012 = getelementptr i8, ptr %hp2010, i64 16
  store ptr %ld1990, ptr %fp2012, align 8
  %fp2013 = getelementptr i8, ptr %hp2010, i64 24
  store ptr %ld1991, ptr %fp2013, align 8
  %fp2014 = getelementptr i8, ptr %hp2010, i64 32
  store ptr %ld1992, ptr %fp2014, align 8
  %fp2015 = getelementptr i8, ptr %hp2010, i64 40
  store ptr %ld1993, ptr %fp2015, align 8
  %fp2016 = getelementptr i8, ptr %hp2010, i64 48
  store ptr %ld1994, ptr %fp2016, align 8
  %fp2017 = getelementptr i8, ptr %hp2010, i64 56
  store ptr %ld1995, ptr %fp2017, align 8
  %fp2018 = getelementptr i8, ptr %hp2010, i64 64
  store ptr %ld1996, ptr %fp2018, align 8
  %fp2019 = getelementptr i8, ptr %hp2010, i64 72
  store ptr %ld1997, ptr %fp2019, align 8
  store ptr %hp2010, ptr %fbip_slot2000
  br label %fbip_merge459
fbip_merge459:
  %fbip_r2020 = load ptr, ptr %fbip_slot2000
  store ptr %fbip_r2020, ptr %res_slot1963
  br label %case_merge454
case_default455:
  unreachable
case_merge454:
  %case_r2021 = load ptr, ptr %res_slot1963
  ret ptr %case_r2021
}

define ptr @Http.set_path$Request_String$String(ptr %req.arg, ptr %new_path.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_path.addr = alloca ptr
  store ptr %new_path.arg, ptr %new_path.addr
  %ld2022 = load ptr, ptr %req.addr
  %res_slot2023 = alloca ptr
  %tgp2024 = getelementptr i8, ptr %ld2022, i64 8
  %tag2025 = load i32, ptr %tgp2024, align 4
  switch i32 %tag2025, label %case_default461 [
      i32 0, label %case_br462
  ]
case_br462:
  %fp2026 = getelementptr i8, ptr %ld2022, i64 16
  %fv2027 = load ptr, ptr %fp2026, align 8
  %$f640.addr = alloca ptr
  store ptr %fv2027, ptr %$f640.addr
  %fp2028 = getelementptr i8, ptr %ld2022, i64 24
  %fv2029 = load ptr, ptr %fp2028, align 8
  %$f641.addr = alloca ptr
  store ptr %fv2029, ptr %$f641.addr
  %fp2030 = getelementptr i8, ptr %ld2022, i64 32
  %fv2031 = load ptr, ptr %fp2030, align 8
  %$f642.addr = alloca ptr
  store ptr %fv2031, ptr %$f642.addr
  %fp2032 = getelementptr i8, ptr %ld2022, i64 40
  %fv2033 = load ptr, ptr %fp2032, align 8
  %$f643.addr = alloca ptr
  store ptr %fv2033, ptr %$f643.addr
  %fp2034 = getelementptr i8, ptr %ld2022, i64 48
  %fv2035 = load ptr, ptr %fp2034, align 8
  %$f644.addr = alloca ptr
  store ptr %fv2035, ptr %$f644.addr
  %fp2036 = getelementptr i8, ptr %ld2022, i64 56
  %fv2037 = load ptr, ptr %fp2036, align 8
  %$f645.addr = alloca ptr
  store ptr %fv2037, ptr %$f645.addr
  %fp2038 = getelementptr i8, ptr %ld2022, i64 64
  %fv2039 = load ptr, ptr %fp2038, align 8
  %$f646.addr = alloca ptr
  store ptr %fv2039, ptr %$f646.addr
  %fp2040 = getelementptr i8, ptr %ld2022, i64 72
  %fv2041 = load ptr, ptr %fp2040, align 8
  %$f647.addr = alloca ptr
  store ptr %fv2041, ptr %$f647.addr
  %ld2042 = load ptr, ptr %$f647.addr
  %bd.addr = alloca ptr
  store ptr %ld2042, ptr %bd.addr
  %ld2043 = load ptr, ptr %$f646.addr
  %hd.addr = alloca ptr
  store ptr %ld2043, ptr %hd.addr
  %ld2044 = load ptr, ptr %$f645.addr
  %q.addr = alloca ptr
  store ptr %ld2044, ptr %q.addr
  %ld2045 = load ptr, ptr %$f643.addr
  %p.addr = alloca ptr
  store ptr %ld2045, ptr %p.addr
  %ld2046 = load ptr, ptr %$f642.addr
  %h.addr = alloca ptr
  store ptr %ld2046, ptr %h.addr
  %ld2047 = load ptr, ptr %$f641.addr
  %sc.addr = alloca ptr
  store ptr %ld2047, ptr %sc.addr
  %ld2048 = load ptr, ptr %$f640.addr
  %m.addr = alloca ptr
  store ptr %ld2048, ptr %m.addr
  %ld2049 = load ptr, ptr %req.addr
  %ld2050 = load ptr, ptr %m.addr
  %ld2051 = load ptr, ptr %sc.addr
  %ld2052 = load ptr, ptr %h.addr
  %ld2053 = load ptr, ptr %p.addr
  %ld2054 = load ptr, ptr %new_path.addr
  %ld2055 = load ptr, ptr %q.addr
  %ld2056 = load ptr, ptr %hd.addr
  %ld2057 = load ptr, ptr %bd.addr
  %rc2058 = load i64, ptr %ld2049, align 8
  %uniq2059 = icmp eq i64 %rc2058, 1
  %fbip_slot2060 = alloca ptr
  br i1 %uniq2059, label %fbip_reuse463, label %fbip_fresh464
fbip_reuse463:
  %tgp2061 = getelementptr i8, ptr %ld2049, i64 8
  store i32 0, ptr %tgp2061, align 4
  %fp2062 = getelementptr i8, ptr %ld2049, i64 16
  store ptr %ld2050, ptr %fp2062, align 8
  %fp2063 = getelementptr i8, ptr %ld2049, i64 24
  store ptr %ld2051, ptr %fp2063, align 8
  %fp2064 = getelementptr i8, ptr %ld2049, i64 32
  store ptr %ld2052, ptr %fp2064, align 8
  %fp2065 = getelementptr i8, ptr %ld2049, i64 40
  store ptr %ld2053, ptr %fp2065, align 8
  %fp2066 = getelementptr i8, ptr %ld2049, i64 48
  store ptr %ld2054, ptr %fp2066, align 8
  %fp2067 = getelementptr i8, ptr %ld2049, i64 56
  store ptr %ld2055, ptr %fp2067, align 8
  %fp2068 = getelementptr i8, ptr %ld2049, i64 64
  store ptr %ld2056, ptr %fp2068, align 8
  %fp2069 = getelementptr i8, ptr %ld2049, i64 72
  store ptr %ld2057, ptr %fp2069, align 8
  store ptr %ld2049, ptr %fbip_slot2060
  br label %fbip_merge465
fbip_fresh464:
  call void @march_decrc(ptr %ld2049)
  %hp2070 = call ptr @march_alloc(i64 80)
  %tgp2071 = getelementptr i8, ptr %hp2070, i64 8
  store i32 0, ptr %tgp2071, align 4
  %fp2072 = getelementptr i8, ptr %hp2070, i64 16
  store ptr %ld2050, ptr %fp2072, align 8
  %fp2073 = getelementptr i8, ptr %hp2070, i64 24
  store ptr %ld2051, ptr %fp2073, align 8
  %fp2074 = getelementptr i8, ptr %hp2070, i64 32
  store ptr %ld2052, ptr %fp2074, align 8
  %fp2075 = getelementptr i8, ptr %hp2070, i64 40
  store ptr %ld2053, ptr %fp2075, align 8
  %fp2076 = getelementptr i8, ptr %hp2070, i64 48
  store ptr %ld2054, ptr %fp2076, align 8
  %fp2077 = getelementptr i8, ptr %hp2070, i64 56
  store ptr %ld2055, ptr %fp2077, align 8
  %fp2078 = getelementptr i8, ptr %hp2070, i64 64
  store ptr %ld2056, ptr %fp2078, align 8
  %fp2079 = getelementptr i8, ptr %hp2070, i64 72
  store ptr %ld2057, ptr %fp2079, align 8
  store ptr %hp2070, ptr %fbip_slot2060
  br label %fbip_merge465
fbip_merge465:
  %fbip_r2080 = load ptr, ptr %fbip_slot2060
  store ptr %fbip_r2080, ptr %res_slot2023
  br label %case_merge460
case_default461:
  unreachable
case_merge460:
  %case_r2081 = load ptr, ptr %res_slot2023
  ret ptr %case_r2081
}

define ptr @Http.get_header$Response_V__3283$String(ptr %resp.arg, ptr %name.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld2082 = load ptr, ptr %name.addr
  %cr2083 = call ptr @march_string_to_lowercase(ptr %ld2082)
  %lower_name.addr = alloca ptr
  store ptr %cr2083, ptr %lower_name.addr
  %hp2084 = call ptr @march_alloc(i64 32)
  %tgp2085 = getelementptr i8, ptr %hp2084, i64 8
  store i32 0, ptr %tgp2085, align 4
  %fp2086 = getelementptr i8, ptr %hp2084, i64 16
  store ptr @find$apply$26, ptr %fp2086, align 8
  %ld2087 = load ptr, ptr %lower_name.addr
  %fp2088 = getelementptr i8, ptr %hp2084, i64 24
  store ptr %ld2087, ptr %fp2088, align 8
  %find.addr = alloca ptr
  store ptr %hp2084, ptr %find.addr
  %ld2089 = load ptr, ptr %resp.addr
  %cr2090 = call ptr @Http.response_headers$Response_V__2424(ptr %ld2089)
  %$t684.addr = alloca ptr
  store ptr %cr2090, ptr %$t684.addr
  %ld2091 = load ptr, ptr %find.addr
  %fp2092 = getelementptr i8, ptr %ld2091, i64 16
  %fv2093 = load ptr, ptr %fp2092, align 8
  %ld2094 = load ptr, ptr %$t684.addr
  %cr2095 = call ptr (ptr, ptr) %fv2093(ptr %ld2091, ptr %ld2094)
  ret ptr %cr2095
}

define i64 @Http.response_is_redirect$Response_V__3283(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2096 = load ptr, ptr %resp.addr
  %cr2097 = call ptr @Http.response_status$Response_V__2408(ptr %ld2096)
  %$t677.addr = alloca ptr
  store ptr %cr2097, ptr %$t677.addr
  %ld2098 = load ptr, ptr %$t677.addr
  %s_i27.addr = alloca ptr
  store ptr %ld2098, ptr %s_i27.addr
  %ld2099 = load ptr, ptr %s_i27.addr
  %cr2100 = call i64 @Http.status_code(ptr %ld2099)
  %c_i28.addr = alloca i64
  store i64 %cr2100, ptr %c_i28.addr
  %ld2101 = load i64, ptr %c_i28.addr
  %cmp2102 = icmp sge i64 %ld2101, 300
  %ar2103 = zext i1 %cmp2102 to i64
  %$t537_i29.addr = alloca i64
  store i64 %ar2103, ptr %$t537_i29.addr
  %ld2104 = load i64, ptr %c_i28.addr
  %cmp2105 = icmp slt i64 %ld2104, 400
  %ar2106 = zext i1 %cmp2105 to i64
  %$t538_i30.addr = alloca i64
  store i64 %ar2106, ptr %$t538_i30.addr
  %ld2107 = load i64, ptr %$t537_i29.addr
  %ld2108 = load i64, ptr %$t538_i30.addr
  %ar2109 = and i64 %ld2107, %ld2108
  ret i64 %ar2109
}

define ptr @HttpClient.reconnect_and_retry(ptr %req.arg, i64 %retries_left.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld2110 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2110)
  %ld2111 = load ptr, ptr %req.addr
  %cr2112 = call ptr @HttpTransport.connect$Request_String(ptr %ld2111)
  %$t983.addr = alloca ptr
  store ptr %cr2112, ptr %$t983.addr
  %ld2113 = load ptr, ptr %$t983.addr
  %res_slot2114 = alloca ptr
  %tgp2115 = getelementptr i8, ptr %ld2113, i64 8
  %tag2116 = load i32, ptr %tgp2115, align 4
  switch i32 %tag2116, label %case_default467 [
      i32 1, label %case_br468
      i32 0, label %case_br469
  ]
case_br468:
  %fp2117 = getelementptr i8, ptr %ld2113, i64 16
  %fv2118 = load ptr, ptr %fp2117, align 8
  %$f985.addr = alloca ptr
  store ptr %fv2118, ptr %$f985.addr
  %ld2119 = load ptr, ptr %$f985.addr
  %ce.addr = alloca ptr
  store ptr %ld2119, ptr %ce.addr
  %ld2120 = load ptr, ptr %$t983.addr
  %ld2121 = load ptr, ptr %ce.addr
  %rc2122 = load i64, ptr %ld2120, align 8
  %uniq2123 = icmp eq i64 %rc2122, 1
  %fbip_slot2124 = alloca ptr
  br i1 %uniq2123, label %fbip_reuse470, label %fbip_fresh471
fbip_reuse470:
  %tgp2125 = getelementptr i8, ptr %ld2120, i64 8
  store i32 1, ptr %tgp2125, align 4
  %fp2126 = getelementptr i8, ptr %ld2120, i64 16
  store ptr %ld2121, ptr %fp2126, align 8
  store ptr %ld2120, ptr %fbip_slot2124
  br label %fbip_merge472
fbip_fresh471:
  call void @march_decrc(ptr %ld2120)
  %hp2127 = call ptr @march_alloc(i64 24)
  %tgp2128 = getelementptr i8, ptr %hp2127, i64 8
  store i32 1, ptr %tgp2128, align 4
  %fp2129 = getelementptr i8, ptr %hp2127, i64 16
  store ptr %ld2121, ptr %fp2129, align 8
  store ptr %hp2127, ptr %fbip_slot2124
  br label %fbip_merge472
fbip_merge472:
  %fbip_r2130 = load ptr, ptr %fbip_slot2124
  store ptr %fbip_r2130, ptr %res_slot2114
  br label %case_merge466
case_br469:
  %fp2131 = getelementptr i8, ptr %ld2113, i64 16
  %fv2132 = load ptr, ptr %fp2131, align 8
  %$f986.addr = alloca ptr
  store ptr %fv2132, ptr %$f986.addr
  %freed2133 = call i64 @march_decrc_freed(ptr %ld2113)
  %freed_b2134 = icmp ne i64 %freed2133, 0
  br i1 %freed_b2134, label %br_unique473, label %br_shared474
br_shared474:
  call void @march_incrc(ptr %fv2132)
  br label %br_body475
br_unique473:
  br label %br_body475
br_body475:
  %ld2135 = load ptr, ptr %$f986.addr
  %new_fd.addr = alloca ptr
  store ptr %ld2135, ptr %new_fd.addr
  %ld2136 = load i64, ptr %retries_left.addr
  %ar2137 = sub i64 %ld2136, 1
  %$t984.addr = alloca i64
  store i64 %ar2137, ptr %$t984.addr
  %ld2138 = load ptr, ptr %new_fd.addr
  %ld2139 = load ptr, ptr %req.addr
  %ld2140 = load i64, ptr %$t984.addr
  %cr2141 = call ptr @HttpClient.transport_keepalive$V__3172$Request_String$Int(ptr %ld2138, ptr %ld2139, i64 %ld2140)
  store ptr %cr2141, ptr %res_slot2114
  br label %case_merge466
case_default467:
  unreachable
case_merge466:
  %case_r2142 = load ptr, ptr %res_slot2114
  ret ptr %case_r2142
}

define ptr @HttpTransport.request_on$V__3281$Request_String(ptr %fd.arg, ptr %req.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2143 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2143)
  %ld2144 = load ptr, ptr %req.addr
  %cr2145 = call ptr @Http.method$Request_String(ptr %ld2144)
  %$t783.addr = alloca ptr
  store ptr %cr2145, ptr %$t783.addr
  %ld2146 = load ptr, ptr %$t783.addr
  %cr2147 = call ptr @Http.method_to_string(ptr %ld2146)
  %meth.addr = alloca ptr
  store ptr %cr2147, ptr %meth.addr
  %ld2148 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2148)
  %ld2149 = load ptr, ptr %req.addr
  %cr2150 = call ptr @Http.host$Request_String(ptr %ld2149)
  %req_host.addr = alloca ptr
  store ptr %cr2150, ptr %req_host.addr
  %ld2151 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2151)
  %ld2152 = load ptr, ptr %req.addr
  %cr2153 = call ptr @Http.path$Request_String(ptr %ld2152)
  %req_path.addr = alloca ptr
  store ptr %cr2153, ptr %req_path.addr
  %ld2154 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2154)
  %ld2155 = load ptr, ptr %req.addr
  %cr2156 = call ptr @Http.query$Request_String(ptr %ld2155)
  %req_query.addr = alloca ptr
  store ptr %cr2156, ptr %req_query.addr
  %ld2157 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2157)
  %ld2158 = load ptr, ptr %req.addr
  %cr2159 = call ptr @Http.headers$Request_String(ptr %ld2158)
  %req_headers.addr = alloca ptr
  store ptr %cr2159, ptr %req_headers.addr
  %ld2160 = load ptr, ptr %req.addr
  %cr2161 = call ptr @Http.body$Request_String(ptr %ld2160)
  %req_body.addr = alloca ptr
  store ptr %cr2161, ptr %req_body.addr
  %ld2162 = load ptr, ptr %http_serialize_request.addr
  %fp2163 = getelementptr i8, ptr %ld2162, i64 16
  %fv2164 = load ptr, ptr %fp2163, align 8
  %ld2165 = load ptr, ptr %meth.addr
  %ld2166 = load ptr, ptr %req_host.addr
  %ld2167 = load ptr, ptr %req_path.addr
  %ld2168 = load ptr, ptr %req_query.addr
  %ld2169 = load ptr, ptr %req_headers.addr
  %ld2170 = load ptr, ptr %req_body.addr
  %cr2171 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv2164(ptr %ld2162, ptr %ld2165, ptr %ld2166, ptr %ld2167, ptr %ld2168, ptr %ld2169, ptr %ld2170)
  %raw_request.addr = alloca ptr
  store ptr %cr2171, ptr %raw_request.addr
  %ld2172 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2172)
  %ld2173 = load ptr, ptr %tcp_send_all.addr
  %fp2174 = getelementptr i8, ptr %ld2173, i64 16
  %fv2175 = load ptr, ptr %fp2174, align 8
  %ld2176 = load ptr, ptr %fd.addr
  %ld2177 = load ptr, ptr %raw_request.addr
  %cr2178 = call ptr (ptr, ptr, ptr) %fv2175(ptr %ld2173, ptr %ld2176, ptr %ld2177)
  %$t784.addr = alloca ptr
  store ptr %cr2178, ptr %$t784.addr
  %ld2179 = load ptr, ptr %$t784.addr
  %res_slot2180 = alloca ptr
  %tgp2181 = getelementptr i8, ptr %ld2179, i64 8
  %tag2182 = load i32, ptr %tgp2181, align 4
  switch i32 %tag2182, label %case_default477 [
      i32 0, label %case_br478
      i32 0, label %case_br479
  ]
case_br478:
  %fp2183 = getelementptr i8, ptr %ld2179, i64 16
  %fv2184 = load ptr, ptr %fp2183, align 8
  %$f799.addr = alloca ptr
  store ptr %fv2184, ptr %$f799.addr
  %freed2185 = call i64 @march_decrc_freed(ptr %ld2179)
  %freed_b2186 = icmp ne i64 %freed2185, 0
  br i1 %freed_b2186, label %br_unique480, label %br_shared481
br_shared481:
  call void @march_incrc(ptr %fv2184)
  br label %br_body482
br_unique480:
  br label %br_body482
br_body482:
  %ld2187 = load ptr, ptr %$f799.addr
  %msg.addr = alloca ptr
  store ptr %ld2187, ptr %msg.addr
  %hp2188 = call ptr @march_alloc(i64 24)
  %tgp2189 = getelementptr i8, ptr %hp2188, i64 8
  store i32 2, ptr %tgp2189, align 4
  %ld2190 = load ptr, ptr %msg.addr
  %fp2191 = getelementptr i8, ptr %hp2188, i64 16
  store ptr %ld2190, ptr %fp2191, align 8
  %$t785.addr = alloca ptr
  store ptr %hp2188, ptr %$t785.addr
  %hp2192 = call ptr @march_alloc(i64 24)
  %tgp2193 = getelementptr i8, ptr %hp2192, i64 8
  store i32 1, ptr %tgp2193, align 4
  %ld2194 = load ptr, ptr %$t785.addr
  %fp2195 = getelementptr i8, ptr %hp2192, i64 16
  store ptr %ld2194, ptr %fp2195, align 8
  store ptr %hp2192, ptr %res_slot2180
  br label %case_merge476
case_br479:
  %fp2196 = getelementptr i8, ptr %ld2179, i64 16
  %fv2197 = load ptr, ptr %fp2196, align 8
  %$f800.addr = alloca ptr
  store ptr %fv2197, ptr %$f800.addr
  %freed2198 = call i64 @march_decrc_freed(ptr %ld2179)
  %freed_b2199 = icmp ne i64 %freed2198, 0
  br i1 %freed_b2199, label %br_unique483, label %br_shared484
br_shared484:
  call void @march_incrc(ptr %fv2197)
  br label %br_body485
br_unique483:
  br label %br_body485
br_body485:
  %ld2200 = load ptr, ptr %tcp_recv_http.addr
  %fp2201 = getelementptr i8, ptr %ld2200, i64 16
  %fv2202 = load ptr, ptr %fp2201, align 8
  %ld2203 = load ptr, ptr %fd.addr
  %cv2204 = inttoptr i64 1048576 to ptr
  %cr2205 = call ptr (ptr, ptr, ptr) %fv2202(ptr %ld2200, ptr %ld2203, ptr %cv2204)
  %$t786.addr = alloca ptr
  store ptr %cr2205, ptr %$t786.addr
  %ld2206 = load ptr, ptr %$t786.addr
  %res_slot2207 = alloca ptr
  %tgp2208 = getelementptr i8, ptr %ld2206, i64 8
  %tag2209 = load i32, ptr %tgp2208, align 4
  switch i32 %tag2209, label %case_default487 [
      i32 0, label %case_br488
      i32 0, label %case_br489
  ]
case_br488:
  %fp2210 = getelementptr i8, ptr %ld2206, i64 16
  %fv2211 = load ptr, ptr %fp2210, align 8
  %$f797.addr = alloca ptr
  store ptr %fv2211, ptr %$f797.addr
  %freed2212 = call i64 @march_decrc_freed(ptr %ld2206)
  %freed_b2213 = icmp ne i64 %freed2212, 0
  br i1 %freed_b2213, label %br_unique490, label %br_shared491
br_shared491:
  call void @march_incrc(ptr %fv2211)
  br label %br_body492
br_unique490:
  br label %br_body492
br_body492:
  %ld2214 = load ptr, ptr %$f797.addr
  %msg_1.addr = alloca ptr
  store ptr %ld2214, ptr %msg_1.addr
  %hp2215 = call ptr @march_alloc(i64 24)
  %tgp2216 = getelementptr i8, ptr %hp2215, i64 8
  store i32 3, ptr %tgp2216, align 4
  %ld2217 = load ptr, ptr %msg_1.addr
  %fp2218 = getelementptr i8, ptr %hp2215, i64 16
  store ptr %ld2217, ptr %fp2218, align 8
  %$t787.addr = alloca ptr
  store ptr %hp2215, ptr %$t787.addr
  %hp2219 = call ptr @march_alloc(i64 24)
  %tgp2220 = getelementptr i8, ptr %hp2219, i64 8
  store i32 1, ptr %tgp2220, align 4
  %ld2221 = load ptr, ptr %$t787.addr
  %fp2222 = getelementptr i8, ptr %hp2219, i64 16
  store ptr %ld2221, ptr %fp2222, align 8
  store ptr %hp2219, ptr %res_slot2207
  br label %case_merge486
case_br489:
  %fp2223 = getelementptr i8, ptr %ld2206, i64 16
  %fv2224 = load ptr, ptr %fp2223, align 8
  %$f798.addr = alloca ptr
  store ptr %fv2224, ptr %$f798.addr
  %freed2225 = call i64 @march_decrc_freed(ptr %ld2206)
  %freed_b2226 = icmp ne i64 %freed2225, 0
  br i1 %freed_b2226, label %br_unique493, label %br_shared494
br_shared494:
  call void @march_incrc(ptr %fv2224)
  br label %br_body495
br_unique493:
  br label %br_body495
br_body495:
  %ld2227 = load ptr, ptr %$f798.addr
  %raw_response.addr = alloca ptr
  store ptr %ld2227, ptr %raw_response.addr
  %ld2228 = load ptr, ptr %http_parse_response.addr
  %fp2229 = getelementptr i8, ptr %ld2228, i64 16
  %fv2230 = load ptr, ptr %fp2229, align 8
  %ld2231 = load ptr, ptr %raw_response.addr
  %cr2232 = call ptr (ptr, ptr) %fv2230(ptr %ld2228, ptr %ld2231)
  %$t788.addr = alloca ptr
  store ptr %cr2232, ptr %$t788.addr
  %ld2233 = load ptr, ptr %$t788.addr
  %res_slot2234 = alloca ptr
  %tgp2235 = getelementptr i8, ptr %ld2233, i64 8
  %tag2236 = load i32, ptr %tgp2235, align 4
  switch i32 %tag2236, label %case_default497 [
      i32 0, label %case_br498
      i32 0, label %case_br499
  ]
case_br498:
  %fp2237 = getelementptr i8, ptr %ld2233, i64 16
  %fv2238 = load ptr, ptr %fp2237, align 8
  %$f792.addr = alloca ptr
  store ptr %fv2238, ptr %$f792.addr
  %freed2239 = call i64 @march_decrc_freed(ptr %ld2233)
  %freed_b2240 = icmp ne i64 %freed2239, 0
  br i1 %freed_b2240, label %br_unique500, label %br_shared501
br_shared501:
  call void @march_incrc(ptr %fv2238)
  br label %br_body502
br_unique500:
  br label %br_body502
br_body502:
  %ld2241 = load ptr, ptr %$f792.addr
  %msg_2.addr = alloca ptr
  store ptr %ld2241, ptr %msg_2.addr
  %hp2242 = call ptr @march_alloc(i64 24)
  %tgp2243 = getelementptr i8, ptr %hp2242, i64 8
  store i32 0, ptr %tgp2243, align 4
  %ld2244 = load ptr, ptr %msg_2.addr
  %fp2245 = getelementptr i8, ptr %hp2242, i64 16
  store ptr %ld2244, ptr %fp2245, align 8
  %$t789.addr = alloca ptr
  store ptr %hp2242, ptr %$t789.addr
  %hp2246 = call ptr @march_alloc(i64 24)
  %tgp2247 = getelementptr i8, ptr %hp2246, i64 8
  store i32 1, ptr %tgp2247, align 4
  %ld2248 = load ptr, ptr %$t789.addr
  %fp2249 = getelementptr i8, ptr %hp2246, i64 16
  store ptr %ld2248, ptr %fp2249, align 8
  store ptr %hp2246, ptr %res_slot2234
  br label %case_merge496
case_br499:
  %fp2250 = getelementptr i8, ptr %ld2233, i64 16
  %fv2251 = load ptr, ptr %fp2250, align 8
  %$f793.addr = alloca ptr
  store ptr %fv2251, ptr %$f793.addr
  %freed2252 = call i64 @march_decrc_freed(ptr %ld2233)
  %freed_b2253 = icmp ne i64 %freed2252, 0
  br i1 %freed_b2253, label %br_unique503, label %br_shared504
br_shared504:
  call void @march_incrc(ptr %fv2251)
  br label %br_body505
br_unique503:
  br label %br_body505
br_body505:
  %ld2254 = load ptr, ptr %$f793.addr
  %res_slot2255 = alloca ptr
  %tgp2256 = getelementptr i8, ptr %ld2254, i64 8
  %tag2257 = load i32, ptr %tgp2256, align 4
  switch i32 %tag2257, label %case_default507 [
      i32 0, label %case_br508
  ]
case_br508:
  %fp2258 = getelementptr i8, ptr %ld2254, i64 16
  %fv2259 = load ptr, ptr %fp2258, align 8
  %$f794.addr = alloca ptr
  store ptr %fv2259, ptr %$f794.addr
  %fp2260 = getelementptr i8, ptr %ld2254, i64 24
  %fv2261 = load ptr, ptr %fp2260, align 8
  %$f795.addr = alloca ptr
  store ptr %fv2261, ptr %$f795.addr
  %fp2262 = getelementptr i8, ptr %ld2254, i64 32
  %fv2263 = load ptr, ptr %fp2262, align 8
  %$f796.addr = alloca ptr
  store ptr %fv2263, ptr %$f796.addr
  %freed2264 = call i64 @march_decrc_freed(ptr %ld2254)
  %freed_b2265 = icmp ne i64 %freed2264, 0
  br i1 %freed_b2265, label %br_unique509, label %br_shared510
br_shared510:
  call void @march_incrc(ptr %fv2263)
  call void @march_incrc(ptr %fv2261)
  call void @march_incrc(ptr %fv2259)
  br label %br_body511
br_unique509:
  br label %br_body511
br_body511:
  %ld2266 = load ptr, ptr %$f796.addr
  %resp_body.addr = alloca ptr
  store ptr %ld2266, ptr %resp_body.addr
  %ld2267 = load ptr, ptr %$f795.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld2267, ptr %resp_headers.addr
  %ld2268 = load ptr, ptr %$f794.addr
  %status_code.addr = alloca ptr
  store ptr %ld2268, ptr %status_code.addr
  %hp2269 = call ptr @march_alloc(i64 24)
  %tgp2270 = getelementptr i8, ptr %hp2269, i64 8
  store i32 0, ptr %tgp2270, align 4
  %ld2271 = load ptr, ptr %status_code.addr
  %fp2272 = getelementptr i8, ptr %hp2269, i64 16
  store ptr %ld2271, ptr %fp2272, align 8
  %$t790.addr = alloca ptr
  store ptr %hp2269, ptr %$t790.addr
  %hp2273 = call ptr @march_alloc(i64 40)
  %tgp2274 = getelementptr i8, ptr %hp2273, i64 8
  store i32 0, ptr %tgp2274, align 4
  %ld2275 = load ptr, ptr %$t790.addr
  %fp2276 = getelementptr i8, ptr %hp2273, i64 16
  store ptr %ld2275, ptr %fp2276, align 8
  %ld2277 = load ptr, ptr %resp_headers.addr
  %fp2278 = getelementptr i8, ptr %hp2273, i64 24
  store ptr %ld2277, ptr %fp2278, align 8
  %ld2279 = load ptr, ptr %resp_body.addr
  %fp2280 = getelementptr i8, ptr %hp2273, i64 32
  store ptr %ld2279, ptr %fp2280, align 8
  %$t791.addr = alloca ptr
  store ptr %hp2273, ptr %$t791.addr
  %hp2281 = call ptr @march_alloc(i64 24)
  %tgp2282 = getelementptr i8, ptr %hp2281, i64 8
  store i32 0, ptr %tgp2282, align 4
  %ld2283 = load ptr, ptr %$t791.addr
  %fp2284 = getelementptr i8, ptr %hp2281, i64 16
  store ptr %ld2283, ptr %fp2284, align 8
  store ptr %hp2281, ptr %res_slot2255
  br label %case_merge506
case_default507:
  unreachable
case_merge506:
  %case_r2285 = load ptr, ptr %res_slot2255
  store ptr %case_r2285, ptr %res_slot2234
  br label %case_merge496
case_default497:
  unreachable
case_merge496:
  %case_r2286 = load ptr, ptr %res_slot2234
  store ptr %case_r2286, ptr %res_slot2207
  br label %case_merge486
case_default487:
  unreachable
case_merge486:
  %case_r2287 = load ptr, ptr %res_slot2207
  store ptr %case_r2287, ptr %res_slot2180
  br label %case_merge476
case_default477:
  unreachable
case_merge476:
  %case_r2288 = load ptr, ptr %res_slot2180
  ret ptr %case_r2288
}

define ptr @Http.body$Request_V__2833(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2289 = load ptr, ptr %req.addr
  %res_slot2290 = alloca ptr
  %tgp2291 = getelementptr i8, ptr %ld2289, i64 8
  %tag2292 = load i32, ptr %tgp2291, align 4
  switch i32 %tag2292, label %case_default513 [
      i32 0, label %case_br514
  ]
case_br514:
  %fp2293 = getelementptr i8, ptr %ld2289, i64 16
  %fv2294 = load ptr, ptr %fp2293, align 8
  %$f599.addr = alloca ptr
  store ptr %fv2294, ptr %$f599.addr
  %fp2295 = getelementptr i8, ptr %ld2289, i64 24
  %fv2296 = load ptr, ptr %fp2295, align 8
  %$f600.addr = alloca ptr
  store ptr %fv2296, ptr %$f600.addr
  %fp2297 = getelementptr i8, ptr %ld2289, i64 32
  %fv2298 = load ptr, ptr %fp2297, align 8
  %$f601.addr = alloca ptr
  store ptr %fv2298, ptr %$f601.addr
  %fp2299 = getelementptr i8, ptr %ld2289, i64 40
  %fv2300 = load ptr, ptr %fp2299, align 8
  %$f602.addr = alloca ptr
  store ptr %fv2300, ptr %$f602.addr
  %fp2301 = getelementptr i8, ptr %ld2289, i64 48
  %fv2302 = load ptr, ptr %fp2301, align 8
  %$f603.addr = alloca ptr
  store ptr %fv2302, ptr %$f603.addr
  %fp2303 = getelementptr i8, ptr %ld2289, i64 56
  %fv2304 = load ptr, ptr %fp2303, align 8
  %$f604.addr = alloca ptr
  store ptr %fv2304, ptr %$f604.addr
  %fp2305 = getelementptr i8, ptr %ld2289, i64 64
  %fv2306 = load ptr, ptr %fp2305, align 8
  %$f605.addr = alloca ptr
  store ptr %fv2306, ptr %$f605.addr
  %fp2307 = getelementptr i8, ptr %ld2289, i64 72
  %fv2308 = load ptr, ptr %fp2307, align 8
  %$f606.addr = alloca ptr
  store ptr %fv2308, ptr %$f606.addr
  %freed2309 = call i64 @march_decrc_freed(ptr %ld2289)
  %freed_b2310 = icmp ne i64 %freed2309, 0
  br i1 %freed_b2310, label %br_unique515, label %br_shared516
br_shared516:
  call void @march_incrc(ptr %fv2308)
  call void @march_incrc(ptr %fv2306)
  call void @march_incrc(ptr %fv2304)
  call void @march_incrc(ptr %fv2302)
  call void @march_incrc(ptr %fv2300)
  call void @march_incrc(ptr %fv2298)
  call void @march_incrc(ptr %fv2296)
  call void @march_incrc(ptr %fv2294)
  br label %br_body517
br_unique515:
  br label %br_body517
br_body517:
  %ld2311 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld2311, ptr %b.addr
  %ld2312 = load ptr, ptr %b.addr
  store ptr %ld2312, ptr %res_slot2290
  br label %case_merge512
case_default513:
  unreachable
case_merge512:
  %case_r2313 = load ptr, ptr %res_slot2290
  ret ptr %case_r2313
}

define ptr @Http.headers$Request_V__2831(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2314 = load ptr, ptr %req.addr
  %res_slot2315 = alloca ptr
  %tgp2316 = getelementptr i8, ptr %ld2314, i64 8
  %tag2317 = load i32, ptr %tgp2316, align 4
  switch i32 %tag2317, label %case_default519 [
      i32 0, label %case_br520
  ]
case_br520:
  %fp2318 = getelementptr i8, ptr %ld2314, i64 16
  %fv2319 = load ptr, ptr %fp2318, align 8
  %$f591.addr = alloca ptr
  store ptr %fv2319, ptr %$f591.addr
  %fp2320 = getelementptr i8, ptr %ld2314, i64 24
  %fv2321 = load ptr, ptr %fp2320, align 8
  %$f592.addr = alloca ptr
  store ptr %fv2321, ptr %$f592.addr
  %fp2322 = getelementptr i8, ptr %ld2314, i64 32
  %fv2323 = load ptr, ptr %fp2322, align 8
  %$f593.addr = alloca ptr
  store ptr %fv2323, ptr %$f593.addr
  %fp2324 = getelementptr i8, ptr %ld2314, i64 40
  %fv2325 = load ptr, ptr %fp2324, align 8
  %$f594.addr = alloca ptr
  store ptr %fv2325, ptr %$f594.addr
  %fp2326 = getelementptr i8, ptr %ld2314, i64 48
  %fv2327 = load ptr, ptr %fp2326, align 8
  %$f595.addr = alloca ptr
  store ptr %fv2327, ptr %$f595.addr
  %fp2328 = getelementptr i8, ptr %ld2314, i64 56
  %fv2329 = load ptr, ptr %fp2328, align 8
  %$f596.addr = alloca ptr
  store ptr %fv2329, ptr %$f596.addr
  %fp2330 = getelementptr i8, ptr %ld2314, i64 64
  %fv2331 = load ptr, ptr %fp2330, align 8
  %$f597.addr = alloca ptr
  store ptr %fv2331, ptr %$f597.addr
  %fp2332 = getelementptr i8, ptr %ld2314, i64 72
  %fv2333 = load ptr, ptr %fp2332, align 8
  %$f598.addr = alloca ptr
  store ptr %fv2333, ptr %$f598.addr
  %freed2334 = call i64 @march_decrc_freed(ptr %ld2314)
  %freed_b2335 = icmp ne i64 %freed2334, 0
  br i1 %freed_b2335, label %br_unique521, label %br_shared522
br_shared522:
  call void @march_incrc(ptr %fv2333)
  call void @march_incrc(ptr %fv2331)
  call void @march_incrc(ptr %fv2329)
  call void @march_incrc(ptr %fv2327)
  call void @march_incrc(ptr %fv2325)
  call void @march_incrc(ptr %fv2323)
  call void @march_incrc(ptr %fv2321)
  call void @march_incrc(ptr %fv2319)
  br label %br_body523
br_unique521:
  br label %br_body523
br_body523:
  %ld2336 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld2336, ptr %h.addr
  %ld2337 = load ptr, ptr %h.addr
  store ptr %ld2337, ptr %res_slot2315
  br label %case_merge518
case_default519:
  unreachable
case_merge518:
  %case_r2338 = load ptr, ptr %res_slot2315
  ret ptr %case_r2338
}

define ptr @Http.query$Request_V__2829(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2339 = load ptr, ptr %req.addr
  %res_slot2340 = alloca ptr
  %tgp2341 = getelementptr i8, ptr %ld2339, i64 8
  %tag2342 = load i32, ptr %tgp2341, align 4
  switch i32 %tag2342, label %case_default525 [
      i32 0, label %case_br526
  ]
case_br526:
  %fp2343 = getelementptr i8, ptr %ld2339, i64 16
  %fv2344 = load ptr, ptr %fp2343, align 8
  %$f583.addr = alloca ptr
  store ptr %fv2344, ptr %$f583.addr
  %fp2345 = getelementptr i8, ptr %ld2339, i64 24
  %fv2346 = load ptr, ptr %fp2345, align 8
  %$f584.addr = alloca ptr
  store ptr %fv2346, ptr %$f584.addr
  %fp2347 = getelementptr i8, ptr %ld2339, i64 32
  %fv2348 = load ptr, ptr %fp2347, align 8
  %$f585.addr = alloca ptr
  store ptr %fv2348, ptr %$f585.addr
  %fp2349 = getelementptr i8, ptr %ld2339, i64 40
  %fv2350 = load ptr, ptr %fp2349, align 8
  %$f586.addr = alloca ptr
  store ptr %fv2350, ptr %$f586.addr
  %fp2351 = getelementptr i8, ptr %ld2339, i64 48
  %fv2352 = load ptr, ptr %fp2351, align 8
  %$f587.addr = alloca ptr
  store ptr %fv2352, ptr %$f587.addr
  %fp2353 = getelementptr i8, ptr %ld2339, i64 56
  %fv2354 = load ptr, ptr %fp2353, align 8
  %$f588.addr = alloca ptr
  store ptr %fv2354, ptr %$f588.addr
  %fp2355 = getelementptr i8, ptr %ld2339, i64 64
  %fv2356 = load ptr, ptr %fp2355, align 8
  %$f589.addr = alloca ptr
  store ptr %fv2356, ptr %$f589.addr
  %fp2357 = getelementptr i8, ptr %ld2339, i64 72
  %fv2358 = load ptr, ptr %fp2357, align 8
  %$f590.addr = alloca ptr
  store ptr %fv2358, ptr %$f590.addr
  %freed2359 = call i64 @march_decrc_freed(ptr %ld2339)
  %freed_b2360 = icmp ne i64 %freed2359, 0
  br i1 %freed_b2360, label %br_unique527, label %br_shared528
br_shared528:
  call void @march_incrc(ptr %fv2358)
  call void @march_incrc(ptr %fv2356)
  call void @march_incrc(ptr %fv2354)
  call void @march_incrc(ptr %fv2352)
  call void @march_incrc(ptr %fv2350)
  call void @march_incrc(ptr %fv2348)
  call void @march_incrc(ptr %fv2346)
  call void @march_incrc(ptr %fv2344)
  br label %br_body529
br_unique527:
  br label %br_body529
br_body529:
  %ld2361 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld2361, ptr %q.addr
  %ld2362 = load ptr, ptr %q.addr
  store ptr %ld2362, ptr %res_slot2340
  br label %case_merge524
case_default525:
  unreachable
case_merge524:
  %case_r2363 = load ptr, ptr %res_slot2340
  ret ptr %case_r2363
}

define ptr @Http.path$Request_V__2827(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2364 = load ptr, ptr %req.addr
  %res_slot2365 = alloca ptr
  %tgp2366 = getelementptr i8, ptr %ld2364, i64 8
  %tag2367 = load i32, ptr %tgp2366, align 4
  switch i32 %tag2367, label %case_default531 [
      i32 0, label %case_br532
  ]
case_br532:
  %fp2368 = getelementptr i8, ptr %ld2364, i64 16
  %fv2369 = load ptr, ptr %fp2368, align 8
  %$f575.addr = alloca ptr
  store ptr %fv2369, ptr %$f575.addr
  %fp2370 = getelementptr i8, ptr %ld2364, i64 24
  %fv2371 = load ptr, ptr %fp2370, align 8
  %$f576.addr = alloca ptr
  store ptr %fv2371, ptr %$f576.addr
  %fp2372 = getelementptr i8, ptr %ld2364, i64 32
  %fv2373 = load ptr, ptr %fp2372, align 8
  %$f577.addr = alloca ptr
  store ptr %fv2373, ptr %$f577.addr
  %fp2374 = getelementptr i8, ptr %ld2364, i64 40
  %fv2375 = load ptr, ptr %fp2374, align 8
  %$f578.addr = alloca ptr
  store ptr %fv2375, ptr %$f578.addr
  %fp2376 = getelementptr i8, ptr %ld2364, i64 48
  %fv2377 = load ptr, ptr %fp2376, align 8
  %$f579.addr = alloca ptr
  store ptr %fv2377, ptr %$f579.addr
  %fp2378 = getelementptr i8, ptr %ld2364, i64 56
  %fv2379 = load ptr, ptr %fp2378, align 8
  %$f580.addr = alloca ptr
  store ptr %fv2379, ptr %$f580.addr
  %fp2380 = getelementptr i8, ptr %ld2364, i64 64
  %fv2381 = load ptr, ptr %fp2380, align 8
  %$f581.addr = alloca ptr
  store ptr %fv2381, ptr %$f581.addr
  %fp2382 = getelementptr i8, ptr %ld2364, i64 72
  %fv2383 = load ptr, ptr %fp2382, align 8
  %$f582.addr = alloca ptr
  store ptr %fv2383, ptr %$f582.addr
  %freed2384 = call i64 @march_decrc_freed(ptr %ld2364)
  %freed_b2385 = icmp ne i64 %freed2384, 0
  br i1 %freed_b2385, label %br_unique533, label %br_shared534
br_shared534:
  call void @march_incrc(ptr %fv2383)
  call void @march_incrc(ptr %fv2381)
  call void @march_incrc(ptr %fv2379)
  call void @march_incrc(ptr %fv2377)
  call void @march_incrc(ptr %fv2375)
  call void @march_incrc(ptr %fv2373)
  call void @march_incrc(ptr %fv2371)
  call void @march_incrc(ptr %fv2369)
  br label %br_body535
br_unique533:
  br label %br_body535
br_body535:
  %ld2386 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld2386, ptr %p.addr
  %ld2387 = load ptr, ptr %p.addr
  store ptr %ld2387, ptr %res_slot2365
  br label %case_merge530
case_default531:
  unreachable
case_merge530:
  %case_r2388 = load ptr, ptr %res_slot2365
  ret ptr %case_r2388
}

define ptr @Http.method$Request_V__2825(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2389 = load ptr, ptr %req.addr
  %res_slot2390 = alloca ptr
  %tgp2391 = getelementptr i8, ptr %ld2389, i64 8
  %tag2392 = load i32, ptr %tgp2391, align 4
  switch i32 %tag2392, label %case_default537 [
      i32 0, label %case_br538
  ]
case_br538:
  %fp2393 = getelementptr i8, ptr %ld2389, i64 16
  %fv2394 = load ptr, ptr %fp2393, align 8
  %$f543.addr = alloca ptr
  store ptr %fv2394, ptr %$f543.addr
  %fp2395 = getelementptr i8, ptr %ld2389, i64 24
  %fv2396 = load ptr, ptr %fp2395, align 8
  %$f544.addr = alloca ptr
  store ptr %fv2396, ptr %$f544.addr
  %fp2397 = getelementptr i8, ptr %ld2389, i64 32
  %fv2398 = load ptr, ptr %fp2397, align 8
  %$f545.addr = alloca ptr
  store ptr %fv2398, ptr %$f545.addr
  %fp2399 = getelementptr i8, ptr %ld2389, i64 40
  %fv2400 = load ptr, ptr %fp2399, align 8
  %$f546.addr = alloca ptr
  store ptr %fv2400, ptr %$f546.addr
  %fp2401 = getelementptr i8, ptr %ld2389, i64 48
  %fv2402 = load ptr, ptr %fp2401, align 8
  %$f547.addr = alloca ptr
  store ptr %fv2402, ptr %$f547.addr
  %fp2403 = getelementptr i8, ptr %ld2389, i64 56
  %fv2404 = load ptr, ptr %fp2403, align 8
  %$f548.addr = alloca ptr
  store ptr %fv2404, ptr %$f548.addr
  %fp2405 = getelementptr i8, ptr %ld2389, i64 64
  %fv2406 = load ptr, ptr %fp2405, align 8
  %$f549.addr = alloca ptr
  store ptr %fv2406, ptr %$f549.addr
  %fp2407 = getelementptr i8, ptr %ld2389, i64 72
  %fv2408 = load ptr, ptr %fp2407, align 8
  %$f550.addr = alloca ptr
  store ptr %fv2408, ptr %$f550.addr
  %freed2409 = call i64 @march_decrc_freed(ptr %ld2389)
  %freed_b2410 = icmp ne i64 %freed2409, 0
  br i1 %freed_b2410, label %br_unique539, label %br_shared540
br_shared540:
  call void @march_incrc(ptr %fv2408)
  call void @march_incrc(ptr %fv2406)
  call void @march_incrc(ptr %fv2404)
  call void @march_incrc(ptr %fv2402)
  call void @march_incrc(ptr %fv2400)
  call void @march_incrc(ptr %fv2398)
  call void @march_incrc(ptr %fv2396)
  call void @march_incrc(ptr %fv2394)
  br label %br_body541
br_unique539:
  br label %br_body541
br_body541:
  %ld2411 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld2411, ptr %m.addr
  %ld2412 = load ptr, ptr %m.addr
  store ptr %ld2412, ptr %res_slot2390
  br label %case_merge536
case_default537:
  unreachable
case_merge536:
  %case_r2413 = load ptr, ptr %res_slot2390
  ret ptr %case_r2413
}

define ptr @Http.port$Request_V__2818(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2414 = load ptr, ptr %req.addr
  %res_slot2415 = alloca ptr
  %tgp2416 = getelementptr i8, ptr %ld2414, i64 8
  %tag2417 = load i32, ptr %tgp2416, align 4
  switch i32 %tag2417, label %case_default543 [
      i32 0, label %case_br544
  ]
case_br544:
  %fp2418 = getelementptr i8, ptr %ld2414, i64 16
  %fv2419 = load ptr, ptr %fp2418, align 8
  %$f567.addr = alloca ptr
  store ptr %fv2419, ptr %$f567.addr
  %fp2420 = getelementptr i8, ptr %ld2414, i64 24
  %fv2421 = load ptr, ptr %fp2420, align 8
  %$f568.addr = alloca ptr
  store ptr %fv2421, ptr %$f568.addr
  %fp2422 = getelementptr i8, ptr %ld2414, i64 32
  %fv2423 = load ptr, ptr %fp2422, align 8
  %$f569.addr = alloca ptr
  store ptr %fv2423, ptr %$f569.addr
  %fp2424 = getelementptr i8, ptr %ld2414, i64 40
  %fv2425 = load ptr, ptr %fp2424, align 8
  %$f570.addr = alloca ptr
  store ptr %fv2425, ptr %$f570.addr
  %fp2426 = getelementptr i8, ptr %ld2414, i64 48
  %fv2427 = load ptr, ptr %fp2426, align 8
  %$f571.addr = alloca ptr
  store ptr %fv2427, ptr %$f571.addr
  %fp2428 = getelementptr i8, ptr %ld2414, i64 56
  %fv2429 = load ptr, ptr %fp2428, align 8
  %$f572.addr = alloca ptr
  store ptr %fv2429, ptr %$f572.addr
  %fp2430 = getelementptr i8, ptr %ld2414, i64 64
  %fv2431 = load ptr, ptr %fp2430, align 8
  %$f573.addr = alloca ptr
  store ptr %fv2431, ptr %$f573.addr
  %fp2432 = getelementptr i8, ptr %ld2414, i64 72
  %fv2433 = load ptr, ptr %fp2432, align 8
  %$f574.addr = alloca ptr
  store ptr %fv2433, ptr %$f574.addr
  %freed2434 = call i64 @march_decrc_freed(ptr %ld2414)
  %freed_b2435 = icmp ne i64 %freed2434, 0
  br i1 %freed_b2435, label %br_unique545, label %br_shared546
br_shared546:
  call void @march_incrc(ptr %fv2433)
  call void @march_incrc(ptr %fv2431)
  call void @march_incrc(ptr %fv2429)
  call void @march_incrc(ptr %fv2427)
  call void @march_incrc(ptr %fv2425)
  call void @march_incrc(ptr %fv2423)
  call void @march_incrc(ptr %fv2421)
  call void @march_incrc(ptr %fv2419)
  br label %br_body547
br_unique545:
  br label %br_body547
br_body547:
  %ld2436 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld2436, ptr %p.addr
  %ld2437 = load ptr, ptr %p.addr
  store ptr %ld2437, ptr %res_slot2415
  br label %case_merge542
case_default543:
  unreachable
case_merge542:
  %case_r2438 = load ptr, ptr %res_slot2415
  ret ptr %case_r2438
}

define ptr @Http.host$Request_V__2815(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2439 = load ptr, ptr %req.addr
  %res_slot2440 = alloca ptr
  %tgp2441 = getelementptr i8, ptr %ld2439, i64 8
  %tag2442 = load i32, ptr %tgp2441, align 4
  switch i32 %tag2442, label %case_default549 [
      i32 0, label %case_br550
  ]
case_br550:
  %fp2443 = getelementptr i8, ptr %ld2439, i64 16
  %fv2444 = load ptr, ptr %fp2443, align 8
  %$f559.addr = alloca ptr
  store ptr %fv2444, ptr %$f559.addr
  %fp2445 = getelementptr i8, ptr %ld2439, i64 24
  %fv2446 = load ptr, ptr %fp2445, align 8
  %$f560.addr = alloca ptr
  store ptr %fv2446, ptr %$f560.addr
  %fp2447 = getelementptr i8, ptr %ld2439, i64 32
  %fv2448 = load ptr, ptr %fp2447, align 8
  %$f561.addr = alloca ptr
  store ptr %fv2448, ptr %$f561.addr
  %fp2449 = getelementptr i8, ptr %ld2439, i64 40
  %fv2450 = load ptr, ptr %fp2449, align 8
  %$f562.addr = alloca ptr
  store ptr %fv2450, ptr %$f562.addr
  %fp2451 = getelementptr i8, ptr %ld2439, i64 48
  %fv2452 = load ptr, ptr %fp2451, align 8
  %$f563.addr = alloca ptr
  store ptr %fv2452, ptr %$f563.addr
  %fp2453 = getelementptr i8, ptr %ld2439, i64 56
  %fv2454 = load ptr, ptr %fp2453, align 8
  %$f564.addr = alloca ptr
  store ptr %fv2454, ptr %$f564.addr
  %fp2455 = getelementptr i8, ptr %ld2439, i64 64
  %fv2456 = load ptr, ptr %fp2455, align 8
  %$f565.addr = alloca ptr
  store ptr %fv2456, ptr %$f565.addr
  %fp2457 = getelementptr i8, ptr %ld2439, i64 72
  %fv2458 = load ptr, ptr %fp2457, align 8
  %$f566.addr = alloca ptr
  store ptr %fv2458, ptr %$f566.addr
  %freed2459 = call i64 @march_decrc_freed(ptr %ld2439)
  %freed_b2460 = icmp ne i64 %freed2459, 0
  br i1 %freed_b2460, label %br_unique551, label %br_shared552
br_shared552:
  call void @march_incrc(ptr %fv2458)
  call void @march_incrc(ptr %fv2456)
  call void @march_incrc(ptr %fv2454)
  call void @march_incrc(ptr %fv2452)
  call void @march_incrc(ptr %fv2450)
  call void @march_incrc(ptr %fv2448)
  call void @march_incrc(ptr %fv2446)
  call void @march_incrc(ptr %fv2444)
  br label %br_body553
br_unique551:
  br label %br_body553
br_body553:
  %ld2461 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld2461, ptr %h.addr
  %ld2462 = load ptr, ptr %h.addr
  store ptr %ld2462, ptr %res_slot2440
  br label %case_merge548
case_default549:
  unreachable
case_merge548:
  %case_r2463 = load ptr, ptr %res_slot2440
  ret ptr %case_r2463
}

define ptr @Http.set_header$Request_String$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld2464 = load ptr, ptr %req.addr
  %res_slot2465 = alloca ptr
  %tgp2466 = getelementptr i8, ptr %ld2464, i64 8
  %tag2467 = load i32, ptr %tgp2466, align 4
  switch i32 %tag2467, label %case_default555 [
      i32 0, label %case_br556
  ]
case_br556:
  %fp2468 = getelementptr i8, ptr %ld2464, i64 16
  %fv2469 = load ptr, ptr %fp2468, align 8
  %$f658.addr = alloca ptr
  store ptr %fv2469, ptr %$f658.addr
  %fp2470 = getelementptr i8, ptr %ld2464, i64 24
  %fv2471 = load ptr, ptr %fp2470, align 8
  %$f659.addr = alloca ptr
  store ptr %fv2471, ptr %$f659.addr
  %fp2472 = getelementptr i8, ptr %ld2464, i64 32
  %fv2473 = load ptr, ptr %fp2472, align 8
  %$f660.addr = alloca ptr
  store ptr %fv2473, ptr %$f660.addr
  %fp2474 = getelementptr i8, ptr %ld2464, i64 40
  %fv2475 = load ptr, ptr %fp2474, align 8
  %$f661.addr = alloca ptr
  store ptr %fv2475, ptr %$f661.addr
  %fp2476 = getelementptr i8, ptr %ld2464, i64 48
  %fv2477 = load ptr, ptr %fp2476, align 8
  %$f662.addr = alloca ptr
  store ptr %fv2477, ptr %$f662.addr
  %fp2478 = getelementptr i8, ptr %ld2464, i64 56
  %fv2479 = load ptr, ptr %fp2478, align 8
  %$f663.addr = alloca ptr
  store ptr %fv2479, ptr %$f663.addr
  %fp2480 = getelementptr i8, ptr %ld2464, i64 64
  %fv2481 = load ptr, ptr %fp2480, align 8
  %$f664.addr = alloca ptr
  store ptr %fv2481, ptr %$f664.addr
  %fp2482 = getelementptr i8, ptr %ld2464, i64 72
  %fv2483 = load ptr, ptr %fp2482, align 8
  %$f665.addr = alloca ptr
  store ptr %fv2483, ptr %$f665.addr
  %ld2484 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld2484, ptr %bd.addr
  %ld2485 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld2485, ptr %hd.addr
  %ld2486 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld2486, ptr %q.addr
  %ld2487 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld2487, ptr %pa.addr
  %ld2488 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld2488, ptr %p.addr
  %ld2489 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld2489, ptr %h.addr
  %ld2490 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld2490, ptr %sc.addr
  %ld2491 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld2491, ptr %m.addr
  %hp2492 = call ptr @march_alloc(i64 32)
  %tgp2493 = getelementptr i8, ptr %hp2492, i64 8
  store i32 0, ptr %tgp2493, align 4
  %ld2494 = load ptr, ptr %name.addr
  %fp2495 = getelementptr i8, ptr %hp2492, i64 16
  store ptr %ld2494, ptr %fp2495, align 8
  %ld2496 = load ptr, ptr %value.addr
  %fp2497 = getelementptr i8, ptr %hp2492, i64 24
  store ptr %ld2496, ptr %fp2497, align 8
  %$t656.addr = alloca ptr
  store ptr %hp2492, ptr %$t656.addr
  %hp2498 = call ptr @march_alloc(i64 32)
  %tgp2499 = getelementptr i8, ptr %hp2498, i64 8
  store i32 1, ptr %tgp2499, align 4
  %ld2500 = load ptr, ptr %$t656.addr
  %fp2501 = getelementptr i8, ptr %hp2498, i64 16
  store ptr %ld2500, ptr %fp2501, align 8
  %ld2502 = load ptr, ptr %hd.addr
  %fp2503 = getelementptr i8, ptr %hp2498, i64 24
  store ptr %ld2502, ptr %fp2503, align 8
  %$t657.addr = alloca ptr
  store ptr %hp2498, ptr %$t657.addr
  %ld2504 = load ptr, ptr %req.addr
  %ld2505 = load ptr, ptr %m.addr
  %ld2506 = load ptr, ptr %sc.addr
  %ld2507 = load ptr, ptr %h.addr
  %ld2508 = load ptr, ptr %p.addr
  %ld2509 = load ptr, ptr %pa.addr
  %ld2510 = load ptr, ptr %q.addr
  %ld2511 = load ptr, ptr %$t657.addr
  %ld2512 = load ptr, ptr %bd.addr
  %rc2513 = load i64, ptr %ld2504, align 8
  %uniq2514 = icmp eq i64 %rc2513, 1
  %fbip_slot2515 = alloca ptr
  br i1 %uniq2514, label %fbip_reuse557, label %fbip_fresh558
fbip_reuse557:
  %tgp2516 = getelementptr i8, ptr %ld2504, i64 8
  store i32 0, ptr %tgp2516, align 4
  %fp2517 = getelementptr i8, ptr %ld2504, i64 16
  store ptr %ld2505, ptr %fp2517, align 8
  %fp2518 = getelementptr i8, ptr %ld2504, i64 24
  store ptr %ld2506, ptr %fp2518, align 8
  %fp2519 = getelementptr i8, ptr %ld2504, i64 32
  store ptr %ld2507, ptr %fp2519, align 8
  %fp2520 = getelementptr i8, ptr %ld2504, i64 40
  store ptr %ld2508, ptr %fp2520, align 8
  %fp2521 = getelementptr i8, ptr %ld2504, i64 48
  store ptr %ld2509, ptr %fp2521, align 8
  %fp2522 = getelementptr i8, ptr %ld2504, i64 56
  store ptr %ld2510, ptr %fp2522, align 8
  %fp2523 = getelementptr i8, ptr %ld2504, i64 64
  store ptr %ld2511, ptr %fp2523, align 8
  %fp2524 = getelementptr i8, ptr %ld2504, i64 72
  store ptr %ld2512, ptr %fp2524, align 8
  store ptr %ld2504, ptr %fbip_slot2515
  br label %fbip_merge559
fbip_fresh558:
  call void @march_decrc(ptr %ld2504)
  %hp2525 = call ptr @march_alloc(i64 80)
  %tgp2526 = getelementptr i8, ptr %hp2525, i64 8
  store i32 0, ptr %tgp2526, align 4
  %fp2527 = getelementptr i8, ptr %hp2525, i64 16
  store ptr %ld2505, ptr %fp2527, align 8
  %fp2528 = getelementptr i8, ptr %hp2525, i64 24
  store ptr %ld2506, ptr %fp2528, align 8
  %fp2529 = getelementptr i8, ptr %hp2525, i64 32
  store ptr %ld2507, ptr %fp2529, align 8
  %fp2530 = getelementptr i8, ptr %hp2525, i64 40
  store ptr %ld2508, ptr %fp2530, align 8
  %fp2531 = getelementptr i8, ptr %hp2525, i64 48
  store ptr %ld2509, ptr %fp2531, align 8
  %fp2532 = getelementptr i8, ptr %hp2525, i64 56
  store ptr %ld2510, ptr %fp2532, align 8
  %fp2533 = getelementptr i8, ptr %hp2525, i64 64
  store ptr %ld2511, ptr %fp2533, align 8
  %fp2534 = getelementptr i8, ptr %hp2525, i64 72
  store ptr %ld2512, ptr %fp2534, align 8
  store ptr %hp2525, ptr %fbip_slot2515
  br label %fbip_merge559
fbip_merge559:
  %fbip_r2535 = load ptr, ptr %fbip_slot2515
  store ptr %fbip_r2535, ptr %res_slot2465
  br label %case_merge554
case_default555:
  unreachable
case_merge554:
  %case_r2536 = load ptr, ptr %res_slot2465
  ret ptr %case_r2536
}

define ptr @Http.response_headers$Response_V__2424(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2537 = load ptr, ptr %resp.addr
  %res_slot2538 = alloca ptr
  %tgp2539 = getelementptr i8, ptr %ld2537, i64 8
  %tag2540 = load i32, ptr %tgp2539, align 4
  switch i32 %tag2540, label %case_default561 [
      i32 0, label %case_br562
  ]
case_br562:
  %fp2541 = getelementptr i8, ptr %ld2537, i64 16
  %fv2542 = load ptr, ptr %fp2541, align 8
  %$f669.addr = alloca ptr
  store ptr %fv2542, ptr %$f669.addr
  %fp2543 = getelementptr i8, ptr %ld2537, i64 24
  %fv2544 = load ptr, ptr %fp2543, align 8
  %$f670.addr = alloca ptr
  store ptr %fv2544, ptr %$f670.addr
  %fp2545 = getelementptr i8, ptr %ld2537, i64 32
  %fv2546 = load ptr, ptr %fp2545, align 8
  %$f671.addr = alloca ptr
  store ptr %fv2546, ptr %$f671.addr
  %freed2547 = call i64 @march_decrc_freed(ptr %ld2537)
  %freed_b2548 = icmp ne i64 %freed2547, 0
  br i1 %freed_b2548, label %br_unique563, label %br_shared564
br_shared564:
  call void @march_incrc(ptr %fv2546)
  call void @march_incrc(ptr %fv2544)
  call void @march_incrc(ptr %fv2542)
  br label %br_body565
br_unique563:
  br label %br_body565
br_body565:
  %ld2549 = load ptr, ptr %$f670.addr
  %h.addr = alloca ptr
  store ptr %ld2549, ptr %h.addr
  %ld2550 = load ptr, ptr %h.addr
  store ptr %ld2550, ptr %res_slot2538
  br label %case_merge560
case_default561:
  unreachable
case_merge560:
  %case_r2551 = load ptr, ptr %res_slot2538
  ret ptr %case_r2551
}

define ptr @Http.response_status$Response_V__2408(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2552 = load ptr, ptr %resp.addr
  %res_slot2553 = alloca ptr
  %tgp2554 = getelementptr i8, ptr %ld2552, i64 8
  %tag2555 = load i32, ptr %tgp2554, align 4
  switch i32 %tag2555, label %case_default567 [
      i32 0, label %case_br568
  ]
case_br568:
  %fp2556 = getelementptr i8, ptr %ld2552, i64 16
  %fv2557 = load ptr, ptr %fp2556, align 8
  %$f666.addr = alloca ptr
  store ptr %fv2557, ptr %$f666.addr
  %fp2558 = getelementptr i8, ptr %ld2552, i64 24
  %fv2559 = load ptr, ptr %fp2558, align 8
  %$f667.addr = alloca ptr
  store ptr %fv2559, ptr %$f667.addr
  %fp2560 = getelementptr i8, ptr %ld2552, i64 32
  %fv2561 = load ptr, ptr %fp2560, align 8
  %$f668.addr = alloca ptr
  store ptr %fv2561, ptr %$f668.addr
  %freed2562 = call i64 @march_decrc_freed(ptr %ld2552)
  %freed_b2563 = icmp ne i64 %freed2562, 0
  br i1 %freed_b2563, label %br_unique569, label %br_shared570
br_shared570:
  call void @march_incrc(ptr %fv2561)
  call void @march_incrc(ptr %fv2559)
  call void @march_incrc(ptr %fv2557)
  br label %br_body571
br_unique569:
  br label %br_body571
br_body571:
  %ld2564 = load ptr, ptr %$f666.addr
  %s.addr = alloca ptr
  store ptr %ld2564, ptr %s.addr
  %ld2565 = load ptr, ptr %s.addr
  store ptr %ld2565, ptr %res_slot2553
  br label %case_merge566
case_default567:
  unreachable
case_merge566:
  %case_r2566 = load ptr, ptr %res_slot2553
  ret ptr %case_r2566
}

define ptr @HttpClient.transport_keepalive$V__3172$Request_String$Int(ptr %fd.arg, ptr %req.arg, i64 %retries_left.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld2567 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2567)
  %ld2568 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2568)
  %ld2569 = load ptr, ptr %fd.addr
  %ld2570 = load ptr, ptr %req.addr
  %cr2571 = call ptr @HttpTransport.request_on$V__3172$Request_String(ptr %ld2569, ptr %ld2570)
  %$t987.addr = alloca ptr
  store ptr %cr2571, ptr %$t987.addr
  %ld2572 = load ptr, ptr %$t987.addr
  %res_slot2573 = alloca ptr
  %tgp2574 = getelementptr i8, ptr %ld2572, i64 8
  %tag2575 = load i32, ptr %tgp2574, align 4
  switch i32 %tag2575, label %case_default573 [
      i32 0, label %case_br574
      i32 1, label %case_br575
  ]
case_br574:
  %fp2576 = getelementptr i8, ptr %ld2572, i64 16
  %fv2577 = load ptr, ptr %fp2576, align 8
  %$f992.addr = alloca ptr
  store ptr %fv2577, ptr %$f992.addr
  %ld2578 = load ptr, ptr %$f992.addr
  %resp.addr = alloca ptr
  store ptr %ld2578, ptr %resp.addr
  %hp2579 = call ptr @march_alloc(i64 32)
  %tgp2580 = getelementptr i8, ptr %hp2579, i64 8
  store i32 0, ptr %tgp2580, align 4
  %ld2581 = load ptr, ptr %fd.addr
  %fp2582 = getelementptr i8, ptr %hp2579, i64 16
  store ptr %ld2581, ptr %fp2582, align 8
  %ld2583 = load ptr, ptr %resp.addr
  %fp2584 = getelementptr i8, ptr %hp2579, i64 24
  store ptr %ld2583, ptr %fp2584, align 8
  %$t988.addr = alloca ptr
  store ptr %hp2579, ptr %$t988.addr
  %ld2585 = load ptr, ptr %$t987.addr
  %ld2586 = load ptr, ptr %$t988.addr
  %rc2587 = load i64, ptr %ld2585, align 8
  %uniq2588 = icmp eq i64 %rc2587, 1
  %fbip_slot2589 = alloca ptr
  br i1 %uniq2588, label %fbip_reuse576, label %fbip_fresh577
fbip_reuse576:
  %tgp2590 = getelementptr i8, ptr %ld2585, i64 8
  store i32 0, ptr %tgp2590, align 4
  %fp2591 = getelementptr i8, ptr %ld2585, i64 16
  store ptr %ld2586, ptr %fp2591, align 8
  store ptr %ld2585, ptr %fbip_slot2589
  br label %fbip_merge578
fbip_fresh577:
  call void @march_decrc(ptr %ld2585)
  %hp2592 = call ptr @march_alloc(i64 24)
  %tgp2593 = getelementptr i8, ptr %hp2592, i64 8
  store i32 0, ptr %tgp2593, align 4
  %fp2594 = getelementptr i8, ptr %hp2592, i64 16
  store ptr %ld2586, ptr %fp2594, align 8
  store ptr %hp2592, ptr %fbip_slot2589
  br label %fbip_merge578
fbip_merge578:
  %fbip_r2595 = load ptr, ptr %fbip_slot2589
  store ptr %fbip_r2595, ptr %res_slot2573
  br label %case_merge572
case_br575:
  %fp2596 = getelementptr i8, ptr %ld2572, i64 16
  %fv2597 = load ptr, ptr %fp2596, align 8
  %$f993.addr = alloca ptr
  store ptr %fv2597, ptr %$f993.addr
  %freed2598 = call i64 @march_decrc_freed(ptr %ld2572)
  %freed_b2599 = icmp ne i64 %freed2598, 0
  br i1 %freed_b2599, label %br_unique579, label %br_shared580
br_shared580:
  call void @march_incrc(ptr %fv2597)
  br label %br_body581
br_unique579:
  br label %br_body581
br_body581:
  %ld2600 = load ptr, ptr %tcp_close.addr
  %fp2601 = getelementptr i8, ptr %ld2600, i64 16
  %fv2602 = load ptr, ptr %fp2601, align 8
  %ld2603 = load ptr, ptr %fd.addr
  %cr2604 = call ptr (ptr, ptr) %fv2602(ptr %ld2600, ptr %ld2603)
  %ld2605 = load i64, ptr %retries_left.addr
  %cmp2606 = icmp sgt i64 %ld2605, 0
  %ar2607 = zext i1 %cmp2606 to i64
  %$t989.addr = alloca i64
  store i64 %ar2607, ptr %$t989.addr
  %ld2608 = load i64, ptr %$t989.addr
  %res_slot2609 = alloca ptr
  %bi2610 = trunc i64 %ld2608 to i1
  br i1 %bi2610, label %case_br584, label %case_default583
case_br584:
  %ld2611 = load i64, ptr %retries_left.addr
  %ar2612 = sub i64 %ld2611, 1
  %$t990.addr = alloca i64
  store i64 %ar2612, ptr %$t990.addr
  %ld2613 = load ptr, ptr %req.addr
  %ld2614 = load i64, ptr %$t990.addr
  %cr2615 = call ptr @HttpClient.reconnect_and_retry(ptr %ld2613, i64 %ld2614)
  store ptr %cr2615, ptr %res_slot2609
  br label %case_merge582
case_default583:
  %hp2616 = call ptr @march_alloc(i64 16)
  %tgp2617 = getelementptr i8, ptr %hp2616, i64 8
  store i32 0, ptr %tgp2617, align 4
  %$t991.addr = alloca ptr
  store ptr %hp2616, ptr %$t991.addr
  %hp2618 = call ptr @march_alloc(i64 24)
  %tgp2619 = getelementptr i8, ptr %hp2618, i64 8
  store i32 1, ptr %tgp2619, align 4
  %ld2620 = load ptr, ptr %$t991.addr
  %fp2621 = getelementptr i8, ptr %hp2618, i64 16
  store ptr %ld2620, ptr %fp2621, align 8
  store ptr %hp2618, ptr %res_slot2609
  br label %case_merge582
case_merge582:
  %case_r2622 = load ptr, ptr %res_slot2609
  store ptr %case_r2622, ptr %res_slot2573
  br label %case_merge572
case_default573:
  unreachable
case_merge572:
  %case_r2623 = load ptr, ptr %res_slot2573
  ret ptr %case_r2623
}

define ptr @HttpTransport.connect$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2624 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2624)
  %ld2625 = load ptr, ptr %req.addr
  %cr2626 = call ptr @Http.host$Request_String(ptr %ld2625)
  %req_host.addr = alloca ptr
  store ptr %cr2626, ptr %req_host.addr
  %ld2627 = load ptr, ptr %req.addr
  %cr2628 = call ptr @Http.port$Request_String(ptr %ld2627)
  %$t777.addr = alloca ptr
  store ptr %cr2628, ptr %$t777.addr
  %ld2629 = load ptr, ptr %$t777.addr
  %res_slot2630 = alloca ptr
  %tgp2631 = getelementptr i8, ptr %ld2629, i64 8
  %tag2632 = load i32, ptr %tgp2631, align 4
  switch i32 %tag2632, label %case_default586 [
      i32 1, label %case_br587
      i32 0, label %case_br588
  ]
case_br587:
  %fp2633 = getelementptr i8, ptr %ld2629, i64 16
  %fv2634 = load ptr, ptr %fp2633, align 8
  %$f778.addr = alloca ptr
  store ptr %fv2634, ptr %$f778.addr
  %ld2635 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld2635)
  %ld2636 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld2636, ptr %p.addr
  %ld2637 = load ptr, ptr %p.addr
  store ptr %ld2637, ptr %res_slot2630
  br label %case_merge585
case_br588:
  %ld2638 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld2638)
  %cv2639 = inttoptr i64 80 to ptr
  store ptr %cv2639, ptr %res_slot2630
  br label %case_merge585
case_default586:
  unreachable
case_merge585:
  %case_r2640 = load ptr, ptr %res_slot2630
  %cv2641 = ptrtoint ptr %case_r2640 to i64
  %req_port.addr = alloca i64
  store i64 %cv2641, ptr %req_port.addr
  %ld2642 = load ptr, ptr %tcp_connect.addr
  %fp2643 = getelementptr i8, ptr %ld2642, i64 16
  %fv2644 = load ptr, ptr %fp2643, align 8
  %ld2645 = load ptr, ptr %req_host.addr
  %ld2646 = load i64, ptr %req_port.addr
  %cv2647 = inttoptr i64 %ld2646 to ptr
  %cr2648 = call ptr (ptr, ptr, ptr) %fv2644(ptr %ld2642, ptr %ld2645, ptr %cv2647)
  %$t779.addr = alloca ptr
  store ptr %cr2648, ptr %$t779.addr
  %ld2649 = load ptr, ptr %$t779.addr
  %res_slot2650 = alloca ptr
  %tgp2651 = getelementptr i8, ptr %ld2649, i64 8
  %tag2652 = load i32, ptr %tgp2651, align 4
  switch i32 %tag2652, label %case_default590 [
      i32 0, label %case_br591
      i32 0, label %case_br592
  ]
case_br591:
  %fp2653 = getelementptr i8, ptr %ld2649, i64 16
  %fv2654 = load ptr, ptr %fp2653, align 8
  %$f781.addr = alloca ptr
  store ptr %fv2654, ptr %$f781.addr
  %freed2655 = call i64 @march_decrc_freed(ptr %ld2649)
  %freed_b2656 = icmp ne i64 %freed2655, 0
  br i1 %freed_b2656, label %br_unique593, label %br_shared594
br_shared594:
  call void @march_incrc(ptr %fv2654)
  br label %br_body595
br_unique593:
  br label %br_body595
br_body595:
  %ld2657 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld2657, ptr %msg.addr
  %hp2658 = call ptr @march_alloc(i64 24)
  %tgp2659 = getelementptr i8, ptr %hp2658, i64 8
  store i32 0, ptr %tgp2659, align 4
  %ld2660 = load ptr, ptr %msg.addr
  %fp2661 = getelementptr i8, ptr %hp2658, i64 16
  store ptr %ld2660, ptr %fp2661, align 8
  %$t780.addr = alloca ptr
  store ptr %hp2658, ptr %$t780.addr
  %hp2662 = call ptr @march_alloc(i64 24)
  %tgp2663 = getelementptr i8, ptr %hp2662, i64 8
  store i32 1, ptr %tgp2663, align 4
  %ld2664 = load ptr, ptr %$t780.addr
  %fp2665 = getelementptr i8, ptr %hp2662, i64 16
  store ptr %ld2664, ptr %fp2665, align 8
  store ptr %hp2662, ptr %res_slot2650
  br label %case_merge589
case_br592:
  %fp2666 = getelementptr i8, ptr %ld2649, i64 16
  %fv2667 = load ptr, ptr %fp2666, align 8
  %$f782.addr = alloca ptr
  store ptr %fv2667, ptr %$f782.addr
  %freed2668 = call i64 @march_decrc_freed(ptr %ld2649)
  %freed_b2669 = icmp ne i64 %freed2668, 0
  br i1 %freed_b2669, label %br_unique596, label %br_shared597
br_shared597:
  call void @march_incrc(ptr %fv2667)
  br label %br_body598
br_unique596:
  br label %br_body598
br_body598:
  %ld2670 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld2670, ptr %fd.addr
  %hp2671 = call ptr @march_alloc(i64 24)
  %tgp2672 = getelementptr i8, ptr %hp2671, i64 8
  store i32 0, ptr %tgp2672, align 4
  %ld2673 = load ptr, ptr %fd.addr
  %fp2674 = getelementptr i8, ptr %hp2671, i64 16
  store ptr %ld2673, ptr %fp2674, align 8
  store ptr %hp2671, ptr %res_slot2650
  br label %case_merge589
case_default590:
  unreachable
case_merge589:
  %case_r2675 = load ptr, ptr %res_slot2650
  ret ptr %case_r2675
}

define ptr @Http.body$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2676 = load ptr, ptr %req.addr
  %res_slot2677 = alloca ptr
  %tgp2678 = getelementptr i8, ptr %ld2676, i64 8
  %tag2679 = load i32, ptr %tgp2678, align 4
  switch i32 %tag2679, label %case_default600 [
      i32 0, label %case_br601
  ]
case_br601:
  %fp2680 = getelementptr i8, ptr %ld2676, i64 16
  %fv2681 = load ptr, ptr %fp2680, align 8
  %$f599.addr = alloca ptr
  store ptr %fv2681, ptr %$f599.addr
  %fp2682 = getelementptr i8, ptr %ld2676, i64 24
  %fv2683 = load ptr, ptr %fp2682, align 8
  %$f600.addr = alloca ptr
  store ptr %fv2683, ptr %$f600.addr
  %fp2684 = getelementptr i8, ptr %ld2676, i64 32
  %fv2685 = load ptr, ptr %fp2684, align 8
  %$f601.addr = alloca ptr
  store ptr %fv2685, ptr %$f601.addr
  %fp2686 = getelementptr i8, ptr %ld2676, i64 40
  %fv2687 = load ptr, ptr %fp2686, align 8
  %$f602.addr = alloca ptr
  store ptr %fv2687, ptr %$f602.addr
  %fp2688 = getelementptr i8, ptr %ld2676, i64 48
  %fv2689 = load ptr, ptr %fp2688, align 8
  %$f603.addr = alloca ptr
  store ptr %fv2689, ptr %$f603.addr
  %fp2690 = getelementptr i8, ptr %ld2676, i64 56
  %fv2691 = load ptr, ptr %fp2690, align 8
  %$f604.addr = alloca ptr
  store ptr %fv2691, ptr %$f604.addr
  %fp2692 = getelementptr i8, ptr %ld2676, i64 64
  %fv2693 = load ptr, ptr %fp2692, align 8
  %$f605.addr = alloca ptr
  store ptr %fv2693, ptr %$f605.addr
  %fp2694 = getelementptr i8, ptr %ld2676, i64 72
  %fv2695 = load ptr, ptr %fp2694, align 8
  %$f606.addr = alloca ptr
  store ptr %fv2695, ptr %$f606.addr
  %freed2696 = call i64 @march_decrc_freed(ptr %ld2676)
  %freed_b2697 = icmp ne i64 %freed2696, 0
  br i1 %freed_b2697, label %br_unique602, label %br_shared603
br_shared603:
  call void @march_incrc(ptr %fv2695)
  call void @march_incrc(ptr %fv2693)
  call void @march_incrc(ptr %fv2691)
  call void @march_incrc(ptr %fv2689)
  call void @march_incrc(ptr %fv2687)
  call void @march_incrc(ptr %fv2685)
  call void @march_incrc(ptr %fv2683)
  call void @march_incrc(ptr %fv2681)
  br label %br_body604
br_unique602:
  br label %br_body604
br_body604:
  %ld2698 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld2698, ptr %b.addr
  %ld2699 = load ptr, ptr %b.addr
  store ptr %ld2699, ptr %res_slot2677
  br label %case_merge599
case_default600:
  unreachable
case_merge599:
  %case_r2700 = load ptr, ptr %res_slot2677
  ret ptr %case_r2700
}

define ptr @Http.query$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2701 = load ptr, ptr %req.addr
  %res_slot2702 = alloca ptr
  %tgp2703 = getelementptr i8, ptr %ld2701, i64 8
  %tag2704 = load i32, ptr %tgp2703, align 4
  switch i32 %tag2704, label %case_default606 [
      i32 0, label %case_br607
  ]
case_br607:
  %fp2705 = getelementptr i8, ptr %ld2701, i64 16
  %fv2706 = load ptr, ptr %fp2705, align 8
  %$f583.addr = alloca ptr
  store ptr %fv2706, ptr %$f583.addr
  %fp2707 = getelementptr i8, ptr %ld2701, i64 24
  %fv2708 = load ptr, ptr %fp2707, align 8
  %$f584.addr = alloca ptr
  store ptr %fv2708, ptr %$f584.addr
  %fp2709 = getelementptr i8, ptr %ld2701, i64 32
  %fv2710 = load ptr, ptr %fp2709, align 8
  %$f585.addr = alloca ptr
  store ptr %fv2710, ptr %$f585.addr
  %fp2711 = getelementptr i8, ptr %ld2701, i64 40
  %fv2712 = load ptr, ptr %fp2711, align 8
  %$f586.addr = alloca ptr
  store ptr %fv2712, ptr %$f586.addr
  %fp2713 = getelementptr i8, ptr %ld2701, i64 48
  %fv2714 = load ptr, ptr %fp2713, align 8
  %$f587.addr = alloca ptr
  store ptr %fv2714, ptr %$f587.addr
  %fp2715 = getelementptr i8, ptr %ld2701, i64 56
  %fv2716 = load ptr, ptr %fp2715, align 8
  %$f588.addr = alloca ptr
  store ptr %fv2716, ptr %$f588.addr
  %fp2717 = getelementptr i8, ptr %ld2701, i64 64
  %fv2718 = load ptr, ptr %fp2717, align 8
  %$f589.addr = alloca ptr
  store ptr %fv2718, ptr %$f589.addr
  %fp2719 = getelementptr i8, ptr %ld2701, i64 72
  %fv2720 = load ptr, ptr %fp2719, align 8
  %$f590.addr = alloca ptr
  store ptr %fv2720, ptr %$f590.addr
  %freed2721 = call i64 @march_decrc_freed(ptr %ld2701)
  %freed_b2722 = icmp ne i64 %freed2721, 0
  br i1 %freed_b2722, label %br_unique608, label %br_shared609
br_shared609:
  call void @march_incrc(ptr %fv2720)
  call void @march_incrc(ptr %fv2718)
  call void @march_incrc(ptr %fv2716)
  call void @march_incrc(ptr %fv2714)
  call void @march_incrc(ptr %fv2712)
  call void @march_incrc(ptr %fv2710)
  call void @march_incrc(ptr %fv2708)
  call void @march_incrc(ptr %fv2706)
  br label %br_body610
br_unique608:
  br label %br_body610
br_body610:
  %ld2723 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld2723, ptr %q.addr
  %ld2724 = load ptr, ptr %q.addr
  store ptr %ld2724, ptr %res_slot2702
  br label %case_merge605
case_default606:
  unreachable
case_merge605:
  %case_r2725 = load ptr, ptr %res_slot2702
  ret ptr %case_r2725
}

define ptr @Http.path$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2726 = load ptr, ptr %req.addr
  %res_slot2727 = alloca ptr
  %tgp2728 = getelementptr i8, ptr %ld2726, i64 8
  %tag2729 = load i32, ptr %tgp2728, align 4
  switch i32 %tag2729, label %case_default612 [
      i32 0, label %case_br613
  ]
case_br613:
  %fp2730 = getelementptr i8, ptr %ld2726, i64 16
  %fv2731 = load ptr, ptr %fp2730, align 8
  %$f575.addr = alloca ptr
  store ptr %fv2731, ptr %$f575.addr
  %fp2732 = getelementptr i8, ptr %ld2726, i64 24
  %fv2733 = load ptr, ptr %fp2732, align 8
  %$f576.addr = alloca ptr
  store ptr %fv2733, ptr %$f576.addr
  %fp2734 = getelementptr i8, ptr %ld2726, i64 32
  %fv2735 = load ptr, ptr %fp2734, align 8
  %$f577.addr = alloca ptr
  store ptr %fv2735, ptr %$f577.addr
  %fp2736 = getelementptr i8, ptr %ld2726, i64 40
  %fv2737 = load ptr, ptr %fp2736, align 8
  %$f578.addr = alloca ptr
  store ptr %fv2737, ptr %$f578.addr
  %fp2738 = getelementptr i8, ptr %ld2726, i64 48
  %fv2739 = load ptr, ptr %fp2738, align 8
  %$f579.addr = alloca ptr
  store ptr %fv2739, ptr %$f579.addr
  %fp2740 = getelementptr i8, ptr %ld2726, i64 56
  %fv2741 = load ptr, ptr %fp2740, align 8
  %$f580.addr = alloca ptr
  store ptr %fv2741, ptr %$f580.addr
  %fp2742 = getelementptr i8, ptr %ld2726, i64 64
  %fv2743 = load ptr, ptr %fp2742, align 8
  %$f581.addr = alloca ptr
  store ptr %fv2743, ptr %$f581.addr
  %fp2744 = getelementptr i8, ptr %ld2726, i64 72
  %fv2745 = load ptr, ptr %fp2744, align 8
  %$f582.addr = alloca ptr
  store ptr %fv2745, ptr %$f582.addr
  %freed2746 = call i64 @march_decrc_freed(ptr %ld2726)
  %freed_b2747 = icmp ne i64 %freed2746, 0
  br i1 %freed_b2747, label %br_unique614, label %br_shared615
br_shared615:
  call void @march_incrc(ptr %fv2745)
  call void @march_incrc(ptr %fv2743)
  call void @march_incrc(ptr %fv2741)
  call void @march_incrc(ptr %fv2739)
  call void @march_incrc(ptr %fv2737)
  call void @march_incrc(ptr %fv2735)
  call void @march_incrc(ptr %fv2733)
  call void @march_incrc(ptr %fv2731)
  br label %br_body616
br_unique614:
  br label %br_body616
br_body616:
  %ld2748 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld2748, ptr %p.addr
  %ld2749 = load ptr, ptr %p.addr
  store ptr %ld2749, ptr %res_slot2727
  br label %case_merge611
case_default612:
  unreachable
case_merge611:
  %case_r2750 = load ptr, ptr %res_slot2727
  ret ptr %case_r2750
}

define ptr @Http.host$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2751 = load ptr, ptr %req.addr
  %res_slot2752 = alloca ptr
  %tgp2753 = getelementptr i8, ptr %ld2751, i64 8
  %tag2754 = load i32, ptr %tgp2753, align 4
  switch i32 %tag2754, label %case_default618 [
      i32 0, label %case_br619
  ]
case_br619:
  %fp2755 = getelementptr i8, ptr %ld2751, i64 16
  %fv2756 = load ptr, ptr %fp2755, align 8
  %$f559.addr = alloca ptr
  store ptr %fv2756, ptr %$f559.addr
  %fp2757 = getelementptr i8, ptr %ld2751, i64 24
  %fv2758 = load ptr, ptr %fp2757, align 8
  %$f560.addr = alloca ptr
  store ptr %fv2758, ptr %$f560.addr
  %fp2759 = getelementptr i8, ptr %ld2751, i64 32
  %fv2760 = load ptr, ptr %fp2759, align 8
  %$f561.addr = alloca ptr
  store ptr %fv2760, ptr %$f561.addr
  %fp2761 = getelementptr i8, ptr %ld2751, i64 40
  %fv2762 = load ptr, ptr %fp2761, align 8
  %$f562.addr = alloca ptr
  store ptr %fv2762, ptr %$f562.addr
  %fp2763 = getelementptr i8, ptr %ld2751, i64 48
  %fv2764 = load ptr, ptr %fp2763, align 8
  %$f563.addr = alloca ptr
  store ptr %fv2764, ptr %$f563.addr
  %fp2765 = getelementptr i8, ptr %ld2751, i64 56
  %fv2766 = load ptr, ptr %fp2765, align 8
  %$f564.addr = alloca ptr
  store ptr %fv2766, ptr %$f564.addr
  %fp2767 = getelementptr i8, ptr %ld2751, i64 64
  %fv2768 = load ptr, ptr %fp2767, align 8
  %$f565.addr = alloca ptr
  store ptr %fv2768, ptr %$f565.addr
  %fp2769 = getelementptr i8, ptr %ld2751, i64 72
  %fv2770 = load ptr, ptr %fp2769, align 8
  %$f566.addr = alloca ptr
  store ptr %fv2770, ptr %$f566.addr
  %freed2771 = call i64 @march_decrc_freed(ptr %ld2751)
  %freed_b2772 = icmp ne i64 %freed2771, 0
  br i1 %freed_b2772, label %br_unique620, label %br_shared621
br_shared621:
  call void @march_incrc(ptr %fv2770)
  call void @march_incrc(ptr %fv2768)
  call void @march_incrc(ptr %fv2766)
  call void @march_incrc(ptr %fv2764)
  call void @march_incrc(ptr %fv2762)
  call void @march_incrc(ptr %fv2760)
  call void @march_incrc(ptr %fv2758)
  call void @march_incrc(ptr %fv2756)
  br label %br_body622
br_unique620:
  br label %br_body622
br_body622:
  %ld2773 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld2773, ptr %h.addr
  %ld2774 = load ptr, ptr %h.addr
  store ptr %ld2774, ptr %res_slot2752
  br label %case_merge617
case_default618:
  unreachable
case_merge617:
  %case_r2775 = load ptr, ptr %res_slot2752
  ret ptr %case_r2775
}

define ptr @Http.method$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2776 = load ptr, ptr %req.addr
  %res_slot2777 = alloca ptr
  %tgp2778 = getelementptr i8, ptr %ld2776, i64 8
  %tag2779 = load i32, ptr %tgp2778, align 4
  switch i32 %tag2779, label %case_default624 [
      i32 0, label %case_br625
  ]
case_br625:
  %fp2780 = getelementptr i8, ptr %ld2776, i64 16
  %fv2781 = load ptr, ptr %fp2780, align 8
  %$f543.addr = alloca ptr
  store ptr %fv2781, ptr %$f543.addr
  %fp2782 = getelementptr i8, ptr %ld2776, i64 24
  %fv2783 = load ptr, ptr %fp2782, align 8
  %$f544.addr = alloca ptr
  store ptr %fv2783, ptr %$f544.addr
  %fp2784 = getelementptr i8, ptr %ld2776, i64 32
  %fv2785 = load ptr, ptr %fp2784, align 8
  %$f545.addr = alloca ptr
  store ptr %fv2785, ptr %$f545.addr
  %fp2786 = getelementptr i8, ptr %ld2776, i64 40
  %fv2787 = load ptr, ptr %fp2786, align 8
  %$f546.addr = alloca ptr
  store ptr %fv2787, ptr %$f546.addr
  %fp2788 = getelementptr i8, ptr %ld2776, i64 48
  %fv2789 = load ptr, ptr %fp2788, align 8
  %$f547.addr = alloca ptr
  store ptr %fv2789, ptr %$f547.addr
  %fp2790 = getelementptr i8, ptr %ld2776, i64 56
  %fv2791 = load ptr, ptr %fp2790, align 8
  %$f548.addr = alloca ptr
  store ptr %fv2791, ptr %$f548.addr
  %fp2792 = getelementptr i8, ptr %ld2776, i64 64
  %fv2793 = load ptr, ptr %fp2792, align 8
  %$f549.addr = alloca ptr
  store ptr %fv2793, ptr %$f549.addr
  %fp2794 = getelementptr i8, ptr %ld2776, i64 72
  %fv2795 = load ptr, ptr %fp2794, align 8
  %$f550.addr = alloca ptr
  store ptr %fv2795, ptr %$f550.addr
  %freed2796 = call i64 @march_decrc_freed(ptr %ld2776)
  %freed_b2797 = icmp ne i64 %freed2796, 0
  br i1 %freed_b2797, label %br_unique626, label %br_shared627
br_shared627:
  call void @march_incrc(ptr %fv2795)
  call void @march_incrc(ptr %fv2793)
  call void @march_incrc(ptr %fv2791)
  call void @march_incrc(ptr %fv2789)
  call void @march_incrc(ptr %fv2787)
  call void @march_incrc(ptr %fv2785)
  call void @march_incrc(ptr %fv2783)
  call void @march_incrc(ptr %fv2781)
  br label %br_body628
br_unique626:
  br label %br_body628
br_body628:
  %ld2798 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld2798, ptr %m.addr
  %ld2799 = load ptr, ptr %m.addr
  store ptr %ld2799, ptr %res_slot2777
  br label %case_merge623
case_default624:
  unreachable
case_merge623:
  %case_r2800 = load ptr, ptr %res_slot2777
  ret ptr %case_r2800
}

define ptr @HttpTransport.request_on$V__3172$Request_String(ptr %fd.arg, ptr %req.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2801 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2801)
  %ld2802 = load ptr, ptr %req.addr
  %cr2803 = call ptr @Http.method$Request_String(ptr %ld2802)
  %$t783.addr = alloca ptr
  store ptr %cr2803, ptr %$t783.addr
  %ld2804 = load ptr, ptr %$t783.addr
  %cr2805 = call ptr @Http.method_to_string(ptr %ld2804)
  %meth.addr = alloca ptr
  store ptr %cr2805, ptr %meth.addr
  %ld2806 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2806)
  %ld2807 = load ptr, ptr %req.addr
  %cr2808 = call ptr @Http.host$Request_String(ptr %ld2807)
  %req_host.addr = alloca ptr
  store ptr %cr2808, ptr %req_host.addr
  %ld2809 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2809)
  %ld2810 = load ptr, ptr %req.addr
  %cr2811 = call ptr @Http.path$Request_String(ptr %ld2810)
  %req_path.addr = alloca ptr
  store ptr %cr2811, ptr %req_path.addr
  %ld2812 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2812)
  %ld2813 = load ptr, ptr %req.addr
  %cr2814 = call ptr @Http.query$Request_String(ptr %ld2813)
  %req_query.addr = alloca ptr
  store ptr %cr2814, ptr %req_query.addr
  %ld2815 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2815)
  %ld2816 = load ptr, ptr %req.addr
  %cr2817 = call ptr @Http.headers$Request_String(ptr %ld2816)
  %req_headers.addr = alloca ptr
  store ptr %cr2817, ptr %req_headers.addr
  %ld2818 = load ptr, ptr %req.addr
  %cr2819 = call ptr @Http.body$Request_String(ptr %ld2818)
  %req_body.addr = alloca ptr
  store ptr %cr2819, ptr %req_body.addr
  %ld2820 = load ptr, ptr %http_serialize_request.addr
  %fp2821 = getelementptr i8, ptr %ld2820, i64 16
  %fv2822 = load ptr, ptr %fp2821, align 8
  %ld2823 = load ptr, ptr %meth.addr
  %ld2824 = load ptr, ptr %req_host.addr
  %ld2825 = load ptr, ptr %req_path.addr
  %ld2826 = load ptr, ptr %req_query.addr
  %ld2827 = load ptr, ptr %req_headers.addr
  %ld2828 = load ptr, ptr %req_body.addr
  %cr2829 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv2822(ptr %ld2820, ptr %ld2823, ptr %ld2824, ptr %ld2825, ptr %ld2826, ptr %ld2827, ptr %ld2828)
  %raw_request.addr = alloca ptr
  store ptr %cr2829, ptr %raw_request.addr
  %ld2830 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2830)
  %ld2831 = load ptr, ptr %tcp_send_all.addr
  %fp2832 = getelementptr i8, ptr %ld2831, i64 16
  %fv2833 = load ptr, ptr %fp2832, align 8
  %ld2834 = load ptr, ptr %fd.addr
  %ld2835 = load ptr, ptr %raw_request.addr
  %cr2836 = call ptr (ptr, ptr, ptr) %fv2833(ptr %ld2831, ptr %ld2834, ptr %ld2835)
  %$t784.addr = alloca ptr
  store ptr %cr2836, ptr %$t784.addr
  %ld2837 = load ptr, ptr %$t784.addr
  %res_slot2838 = alloca ptr
  %tgp2839 = getelementptr i8, ptr %ld2837, i64 8
  %tag2840 = load i32, ptr %tgp2839, align 4
  switch i32 %tag2840, label %case_default630 [
      i32 0, label %case_br631
      i32 0, label %case_br632
  ]
case_br631:
  %fp2841 = getelementptr i8, ptr %ld2837, i64 16
  %fv2842 = load ptr, ptr %fp2841, align 8
  %$f799.addr = alloca ptr
  store ptr %fv2842, ptr %$f799.addr
  %freed2843 = call i64 @march_decrc_freed(ptr %ld2837)
  %freed_b2844 = icmp ne i64 %freed2843, 0
  br i1 %freed_b2844, label %br_unique633, label %br_shared634
br_shared634:
  call void @march_incrc(ptr %fv2842)
  br label %br_body635
br_unique633:
  br label %br_body635
br_body635:
  %ld2845 = load ptr, ptr %$f799.addr
  %msg.addr = alloca ptr
  store ptr %ld2845, ptr %msg.addr
  %hp2846 = call ptr @march_alloc(i64 24)
  %tgp2847 = getelementptr i8, ptr %hp2846, i64 8
  store i32 2, ptr %tgp2847, align 4
  %ld2848 = load ptr, ptr %msg.addr
  %fp2849 = getelementptr i8, ptr %hp2846, i64 16
  store ptr %ld2848, ptr %fp2849, align 8
  %$t785.addr = alloca ptr
  store ptr %hp2846, ptr %$t785.addr
  %hp2850 = call ptr @march_alloc(i64 24)
  %tgp2851 = getelementptr i8, ptr %hp2850, i64 8
  store i32 1, ptr %tgp2851, align 4
  %ld2852 = load ptr, ptr %$t785.addr
  %fp2853 = getelementptr i8, ptr %hp2850, i64 16
  store ptr %ld2852, ptr %fp2853, align 8
  store ptr %hp2850, ptr %res_slot2838
  br label %case_merge629
case_br632:
  %fp2854 = getelementptr i8, ptr %ld2837, i64 16
  %fv2855 = load ptr, ptr %fp2854, align 8
  %$f800.addr = alloca ptr
  store ptr %fv2855, ptr %$f800.addr
  %freed2856 = call i64 @march_decrc_freed(ptr %ld2837)
  %freed_b2857 = icmp ne i64 %freed2856, 0
  br i1 %freed_b2857, label %br_unique636, label %br_shared637
br_shared637:
  call void @march_incrc(ptr %fv2855)
  br label %br_body638
br_unique636:
  br label %br_body638
br_body638:
  %ld2858 = load ptr, ptr %tcp_recv_http.addr
  %fp2859 = getelementptr i8, ptr %ld2858, i64 16
  %fv2860 = load ptr, ptr %fp2859, align 8
  %ld2861 = load ptr, ptr %fd.addr
  %cv2862 = inttoptr i64 1048576 to ptr
  %cr2863 = call ptr (ptr, ptr, ptr) %fv2860(ptr %ld2858, ptr %ld2861, ptr %cv2862)
  %$t786.addr = alloca ptr
  store ptr %cr2863, ptr %$t786.addr
  %ld2864 = load ptr, ptr %$t786.addr
  %res_slot2865 = alloca ptr
  %tgp2866 = getelementptr i8, ptr %ld2864, i64 8
  %tag2867 = load i32, ptr %tgp2866, align 4
  switch i32 %tag2867, label %case_default640 [
      i32 0, label %case_br641
      i32 0, label %case_br642
  ]
case_br641:
  %fp2868 = getelementptr i8, ptr %ld2864, i64 16
  %fv2869 = load ptr, ptr %fp2868, align 8
  %$f797.addr = alloca ptr
  store ptr %fv2869, ptr %$f797.addr
  %freed2870 = call i64 @march_decrc_freed(ptr %ld2864)
  %freed_b2871 = icmp ne i64 %freed2870, 0
  br i1 %freed_b2871, label %br_unique643, label %br_shared644
br_shared644:
  call void @march_incrc(ptr %fv2869)
  br label %br_body645
br_unique643:
  br label %br_body645
br_body645:
  %ld2872 = load ptr, ptr %$f797.addr
  %msg_1.addr = alloca ptr
  store ptr %ld2872, ptr %msg_1.addr
  %hp2873 = call ptr @march_alloc(i64 24)
  %tgp2874 = getelementptr i8, ptr %hp2873, i64 8
  store i32 3, ptr %tgp2874, align 4
  %ld2875 = load ptr, ptr %msg_1.addr
  %fp2876 = getelementptr i8, ptr %hp2873, i64 16
  store ptr %ld2875, ptr %fp2876, align 8
  %$t787.addr = alloca ptr
  store ptr %hp2873, ptr %$t787.addr
  %hp2877 = call ptr @march_alloc(i64 24)
  %tgp2878 = getelementptr i8, ptr %hp2877, i64 8
  store i32 1, ptr %tgp2878, align 4
  %ld2879 = load ptr, ptr %$t787.addr
  %fp2880 = getelementptr i8, ptr %hp2877, i64 16
  store ptr %ld2879, ptr %fp2880, align 8
  store ptr %hp2877, ptr %res_slot2865
  br label %case_merge639
case_br642:
  %fp2881 = getelementptr i8, ptr %ld2864, i64 16
  %fv2882 = load ptr, ptr %fp2881, align 8
  %$f798.addr = alloca ptr
  store ptr %fv2882, ptr %$f798.addr
  %freed2883 = call i64 @march_decrc_freed(ptr %ld2864)
  %freed_b2884 = icmp ne i64 %freed2883, 0
  br i1 %freed_b2884, label %br_unique646, label %br_shared647
br_shared647:
  call void @march_incrc(ptr %fv2882)
  br label %br_body648
br_unique646:
  br label %br_body648
br_body648:
  %ld2885 = load ptr, ptr %$f798.addr
  %raw_response.addr = alloca ptr
  store ptr %ld2885, ptr %raw_response.addr
  %ld2886 = load ptr, ptr %http_parse_response.addr
  %fp2887 = getelementptr i8, ptr %ld2886, i64 16
  %fv2888 = load ptr, ptr %fp2887, align 8
  %ld2889 = load ptr, ptr %raw_response.addr
  %cr2890 = call ptr (ptr, ptr) %fv2888(ptr %ld2886, ptr %ld2889)
  %$t788.addr = alloca ptr
  store ptr %cr2890, ptr %$t788.addr
  %ld2891 = load ptr, ptr %$t788.addr
  %res_slot2892 = alloca ptr
  %tgp2893 = getelementptr i8, ptr %ld2891, i64 8
  %tag2894 = load i32, ptr %tgp2893, align 4
  switch i32 %tag2894, label %case_default650 [
      i32 0, label %case_br651
      i32 0, label %case_br652
  ]
case_br651:
  %fp2895 = getelementptr i8, ptr %ld2891, i64 16
  %fv2896 = load ptr, ptr %fp2895, align 8
  %$f792.addr = alloca ptr
  store ptr %fv2896, ptr %$f792.addr
  %freed2897 = call i64 @march_decrc_freed(ptr %ld2891)
  %freed_b2898 = icmp ne i64 %freed2897, 0
  br i1 %freed_b2898, label %br_unique653, label %br_shared654
br_shared654:
  call void @march_incrc(ptr %fv2896)
  br label %br_body655
br_unique653:
  br label %br_body655
br_body655:
  %ld2899 = load ptr, ptr %$f792.addr
  %msg_2.addr = alloca ptr
  store ptr %ld2899, ptr %msg_2.addr
  %hp2900 = call ptr @march_alloc(i64 24)
  %tgp2901 = getelementptr i8, ptr %hp2900, i64 8
  store i32 0, ptr %tgp2901, align 4
  %ld2902 = load ptr, ptr %msg_2.addr
  %fp2903 = getelementptr i8, ptr %hp2900, i64 16
  store ptr %ld2902, ptr %fp2903, align 8
  %$t789.addr = alloca ptr
  store ptr %hp2900, ptr %$t789.addr
  %hp2904 = call ptr @march_alloc(i64 24)
  %tgp2905 = getelementptr i8, ptr %hp2904, i64 8
  store i32 1, ptr %tgp2905, align 4
  %ld2906 = load ptr, ptr %$t789.addr
  %fp2907 = getelementptr i8, ptr %hp2904, i64 16
  store ptr %ld2906, ptr %fp2907, align 8
  store ptr %hp2904, ptr %res_slot2892
  br label %case_merge649
case_br652:
  %fp2908 = getelementptr i8, ptr %ld2891, i64 16
  %fv2909 = load ptr, ptr %fp2908, align 8
  %$f793.addr = alloca ptr
  store ptr %fv2909, ptr %$f793.addr
  %freed2910 = call i64 @march_decrc_freed(ptr %ld2891)
  %freed_b2911 = icmp ne i64 %freed2910, 0
  br i1 %freed_b2911, label %br_unique656, label %br_shared657
br_shared657:
  call void @march_incrc(ptr %fv2909)
  br label %br_body658
br_unique656:
  br label %br_body658
br_body658:
  %ld2912 = load ptr, ptr %$f793.addr
  %res_slot2913 = alloca ptr
  %tgp2914 = getelementptr i8, ptr %ld2912, i64 8
  %tag2915 = load i32, ptr %tgp2914, align 4
  switch i32 %tag2915, label %case_default660 [
      i32 0, label %case_br661
  ]
case_br661:
  %fp2916 = getelementptr i8, ptr %ld2912, i64 16
  %fv2917 = load ptr, ptr %fp2916, align 8
  %$f794.addr = alloca ptr
  store ptr %fv2917, ptr %$f794.addr
  %fp2918 = getelementptr i8, ptr %ld2912, i64 24
  %fv2919 = load ptr, ptr %fp2918, align 8
  %$f795.addr = alloca ptr
  store ptr %fv2919, ptr %$f795.addr
  %fp2920 = getelementptr i8, ptr %ld2912, i64 32
  %fv2921 = load ptr, ptr %fp2920, align 8
  %$f796.addr = alloca ptr
  store ptr %fv2921, ptr %$f796.addr
  %freed2922 = call i64 @march_decrc_freed(ptr %ld2912)
  %freed_b2923 = icmp ne i64 %freed2922, 0
  br i1 %freed_b2923, label %br_unique662, label %br_shared663
br_shared663:
  call void @march_incrc(ptr %fv2921)
  call void @march_incrc(ptr %fv2919)
  call void @march_incrc(ptr %fv2917)
  br label %br_body664
br_unique662:
  br label %br_body664
br_body664:
  %ld2924 = load ptr, ptr %$f796.addr
  %resp_body.addr = alloca ptr
  store ptr %ld2924, ptr %resp_body.addr
  %ld2925 = load ptr, ptr %$f795.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld2925, ptr %resp_headers.addr
  %ld2926 = load ptr, ptr %$f794.addr
  %status_code.addr = alloca ptr
  store ptr %ld2926, ptr %status_code.addr
  %hp2927 = call ptr @march_alloc(i64 24)
  %tgp2928 = getelementptr i8, ptr %hp2927, i64 8
  store i32 0, ptr %tgp2928, align 4
  %ld2929 = load ptr, ptr %status_code.addr
  %fp2930 = getelementptr i8, ptr %hp2927, i64 16
  store ptr %ld2929, ptr %fp2930, align 8
  %$t790.addr = alloca ptr
  store ptr %hp2927, ptr %$t790.addr
  %hp2931 = call ptr @march_alloc(i64 40)
  %tgp2932 = getelementptr i8, ptr %hp2931, i64 8
  store i32 0, ptr %tgp2932, align 4
  %ld2933 = load ptr, ptr %$t790.addr
  %fp2934 = getelementptr i8, ptr %hp2931, i64 16
  store ptr %ld2933, ptr %fp2934, align 8
  %ld2935 = load ptr, ptr %resp_headers.addr
  %fp2936 = getelementptr i8, ptr %hp2931, i64 24
  store ptr %ld2935, ptr %fp2936, align 8
  %ld2937 = load ptr, ptr %resp_body.addr
  %fp2938 = getelementptr i8, ptr %hp2931, i64 32
  store ptr %ld2937, ptr %fp2938, align 8
  %$t791.addr = alloca ptr
  store ptr %hp2931, ptr %$t791.addr
  %hp2939 = call ptr @march_alloc(i64 24)
  %tgp2940 = getelementptr i8, ptr %hp2939, i64 8
  store i32 0, ptr %tgp2940, align 4
  %ld2941 = load ptr, ptr %$t791.addr
  %fp2942 = getelementptr i8, ptr %hp2939, i64 16
  store ptr %ld2941, ptr %fp2942, align 8
  store ptr %hp2939, ptr %res_slot2913
  br label %case_merge659
case_default660:
  unreachable
case_merge659:
  %case_r2943 = load ptr, ptr %res_slot2913
  store ptr %case_r2943, ptr %res_slot2892
  br label %case_merge649
case_default650:
  unreachable
case_merge649:
  %case_r2944 = load ptr, ptr %res_slot2892
  store ptr %case_r2944, ptr %res_slot2865
  br label %case_merge639
case_default640:
  unreachable
case_merge639:
  %case_r2945 = load ptr, ptr %res_slot2865
  store ptr %case_r2945, ptr %res_slot2838
  br label %case_merge629
case_default630:
  unreachable
case_merge629:
  %case_r2946 = load ptr, ptr %res_slot2838
  ret ptr %case_r2946
}

define ptr @Http.port$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2947 = load ptr, ptr %req.addr
  %res_slot2948 = alloca ptr
  %tgp2949 = getelementptr i8, ptr %ld2947, i64 8
  %tag2950 = load i32, ptr %tgp2949, align 4
  switch i32 %tag2950, label %case_default666 [
      i32 0, label %case_br667
  ]
case_br667:
  %fp2951 = getelementptr i8, ptr %ld2947, i64 16
  %fv2952 = load ptr, ptr %fp2951, align 8
  %$f567.addr = alloca ptr
  store ptr %fv2952, ptr %$f567.addr
  %fp2953 = getelementptr i8, ptr %ld2947, i64 24
  %fv2954 = load ptr, ptr %fp2953, align 8
  %$f568.addr = alloca ptr
  store ptr %fv2954, ptr %$f568.addr
  %fp2955 = getelementptr i8, ptr %ld2947, i64 32
  %fv2956 = load ptr, ptr %fp2955, align 8
  %$f569.addr = alloca ptr
  store ptr %fv2956, ptr %$f569.addr
  %fp2957 = getelementptr i8, ptr %ld2947, i64 40
  %fv2958 = load ptr, ptr %fp2957, align 8
  %$f570.addr = alloca ptr
  store ptr %fv2958, ptr %$f570.addr
  %fp2959 = getelementptr i8, ptr %ld2947, i64 48
  %fv2960 = load ptr, ptr %fp2959, align 8
  %$f571.addr = alloca ptr
  store ptr %fv2960, ptr %$f571.addr
  %fp2961 = getelementptr i8, ptr %ld2947, i64 56
  %fv2962 = load ptr, ptr %fp2961, align 8
  %$f572.addr = alloca ptr
  store ptr %fv2962, ptr %$f572.addr
  %fp2963 = getelementptr i8, ptr %ld2947, i64 64
  %fv2964 = load ptr, ptr %fp2963, align 8
  %$f573.addr = alloca ptr
  store ptr %fv2964, ptr %$f573.addr
  %fp2965 = getelementptr i8, ptr %ld2947, i64 72
  %fv2966 = load ptr, ptr %fp2965, align 8
  %$f574.addr = alloca ptr
  store ptr %fv2966, ptr %$f574.addr
  %freed2967 = call i64 @march_decrc_freed(ptr %ld2947)
  %freed_b2968 = icmp ne i64 %freed2967, 0
  br i1 %freed_b2968, label %br_unique668, label %br_shared669
br_shared669:
  call void @march_incrc(ptr %fv2966)
  call void @march_incrc(ptr %fv2964)
  call void @march_incrc(ptr %fv2962)
  call void @march_incrc(ptr %fv2960)
  call void @march_incrc(ptr %fv2958)
  call void @march_incrc(ptr %fv2956)
  call void @march_incrc(ptr %fv2954)
  call void @march_incrc(ptr %fv2952)
  br label %br_body670
br_unique668:
  br label %br_body670
br_body670:
  %ld2969 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld2969, ptr %p.addr
  %ld2970 = load ptr, ptr %p.addr
  store ptr %ld2970, ptr %res_slot2948
  br label %case_merge665
case_default666:
  unreachable
case_merge665:
  %case_r2971 = load ptr, ptr %res_slot2948
  ret ptr %case_r2971
}

define ptr @callback$apply$21(ptr %$clo.arg, ptr %do_request.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %do_request.addr = alloca ptr
  store ptr %do_request.arg, ptr %do_request.addr
  %ld2972 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2972)
  %ld2973 = load ptr, ptr %$clo.addr
  %fp2974 = getelementptr i8, ptr %ld2973, i64 24
  %fv2975 = load ptr, ptr %fp2974, align 8
  %cv2976 = ptrtoint ptr %fv2975 to i64
  %n.addr = alloca i64
  store i64 %cv2976, ptr %n.addr
  %ld2977 = load ptr, ptr %$clo.addr
  %fp2978 = getelementptr i8, ptr %ld2977, i64 32
  %fv2979 = load ptr, ptr %fp2978, align 8
  %req.addr = alloca ptr
  store ptr %fv2979, ptr %req.addr
  %ld2980 = load i64, ptr %n.addr
  %ld2981 = load ptr, ptr %do_request.addr
  %ld2982 = load ptr, ptr %req.addr
  %cr2983 = call ptr @run_keepalive$Int$Fn_Request_String_Result_V__5883_V__5882$Request_String(i64 %ld2980, ptr %ld2981, ptr %ld2982)
  ret ptr %cr2983
}

define ptr @do_request$apply$24(ptr %$clo.arg, ptr %req.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2984 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2984)
  %ld2985 = load ptr, ptr %$clo.addr
  %fp2986 = getelementptr i8, ptr %ld2985, i64 24
  %fv2987 = load ptr, ptr %fp2986, align 8
  %err_steps.addr = alloca ptr
  store ptr %fv2987, ptr %err_steps.addr
  %ld2988 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2988)
  %ld2989 = load ptr, ptr %$clo.addr
  %fp2990 = getelementptr i8, ptr %ld2989, i64 32
  %fv2991 = load ptr, ptr %fp2990, align 8
  %fd.addr = alloca ptr
  store ptr %fv2991, ptr %fd.addr
  %ld2992 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2992)
  %ld2993 = load ptr, ptr %$clo.addr
  %fp2994 = getelementptr i8, ptr %ld2993, i64 40
  %fv2995 = load ptr, ptr %fp2994, align 8
  %cv2996 = ptrtoint ptr %fv2995 to i64
  %max_redir.addr = alloca i64
  store i64 %cv2996, ptr %max_redir.addr
  %ld2997 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2997)
  %ld2998 = load ptr, ptr %$clo.addr
  %fp2999 = getelementptr i8, ptr %ld2998, i64 48
  %fv3000 = load ptr, ptr %fp2999, align 8
  %cv3001 = ptrtoint ptr %fv3000 to i64
  %max_retries.addr = alloca i64
  store i64 %cv3001, ptr %max_retries.addr
  %ld3002 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3002)
  %ld3003 = load ptr, ptr %$clo.addr
  %fp3004 = getelementptr i8, ptr %ld3003, i64 56
  %fv3005 = load ptr, ptr %fp3004, align 8
  %req_steps.addr = alloca ptr
  store ptr %fv3005, ptr %req_steps.addr
  %ld3006 = load ptr, ptr %$clo.addr
  %fp3007 = getelementptr i8, ptr %ld3006, i64 64
  %fv3008 = load ptr, ptr %fp3007, align 8
  %resp_steps.addr = alloca ptr
  store ptr %fv3008, ptr %resp_steps.addr
  %ld3009 = load ptr, ptr %fd.addr
  %ld3010 = load ptr, ptr %req_steps.addr
  %ld3011 = load ptr, ptr %resp_steps.addr
  %ld3012 = load ptr, ptr %err_steps.addr
  %ld3013 = load i64, ptr %max_redir.addr
  %ld3014 = load i64, ptr %max_retries.addr
  %ld3015 = load ptr, ptr %req.addr
  %cr3016 = call ptr @HttpClient.run_on_fd$V__3281$List_RequestStepEntry$List_ResponseStepEntry$List_ErrorStepEntry$Int$Int$Request_String(ptr %ld3009, ptr %ld3010, ptr %ld3011, ptr %ld3012, i64 %ld3013, i64 %ld3014, ptr %ld3015)
  ret ptr %cr3016
}

define ptr @find$apply$26(ptr %$clo.arg, ptr %hs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %hs.addr = alloca ptr
  store ptr %hs.arg, ptr %hs.addr
  %ld3017 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3017)
  %ld3018 = load ptr, ptr %$clo.addr
  %find.addr = alloca ptr
  store ptr %ld3018, ptr %find.addr
  %ld3019 = load ptr, ptr %$clo.addr
  %fp3020 = getelementptr i8, ptr %ld3019, i64 24
  %fv3021 = load ptr, ptr %fp3020, align 8
  %lower_name.addr = alloca ptr
  store ptr %fv3021, ptr %lower_name.addr
  %ld3022 = load ptr, ptr %hs.addr
  %res_slot3023 = alloca ptr
  %tgp3024 = getelementptr i8, ptr %ld3022, i64 8
  %tag3025 = load i32, ptr %tgp3024, align 4
  switch i32 %tag3025, label %case_default672 [
      i32 0, label %case_br673
      i32 1, label %case_br674
  ]
case_br673:
  %ld3026 = load ptr, ptr %hs.addr
  call void @march_decrc(ptr %ld3026)
  %hp3027 = call ptr @march_alloc(i64 16)
  %tgp3028 = getelementptr i8, ptr %hp3027, i64 8
  store i32 0, ptr %tgp3028, align 4
  store ptr %hp3027, ptr %res_slot3023
  br label %case_merge671
case_br674:
  %fp3029 = getelementptr i8, ptr %ld3022, i64 16
  %fv3030 = load ptr, ptr %fp3029, align 8
  %$f680.addr = alloca ptr
  store ptr %fv3030, ptr %$f680.addr
  %fp3031 = getelementptr i8, ptr %ld3022, i64 24
  %fv3032 = load ptr, ptr %fp3031, align 8
  %$f681.addr = alloca ptr
  store ptr %fv3032, ptr %$f681.addr
  %freed3033 = call i64 @march_decrc_freed(ptr %ld3022)
  %freed_b3034 = icmp ne i64 %freed3033, 0
  br i1 %freed_b3034, label %br_unique675, label %br_shared676
br_shared676:
  call void @march_incrc(ptr %fv3032)
  call void @march_incrc(ptr %fv3030)
  br label %br_body677
br_unique675:
  br label %br_body677
br_body677:
  %ld3035 = load ptr, ptr %$f680.addr
  %res_slot3036 = alloca ptr
  %tgp3037 = getelementptr i8, ptr %ld3035, i64 8
  %tag3038 = load i32, ptr %tgp3037, align 4
  switch i32 %tag3038, label %case_default679 [
      i32 0, label %case_br680
  ]
case_br680:
  %fp3039 = getelementptr i8, ptr %ld3035, i64 16
  %fv3040 = load ptr, ptr %fp3039, align 8
  %$f682.addr = alloca ptr
  store ptr %fv3040, ptr %$f682.addr
  %fp3041 = getelementptr i8, ptr %ld3035, i64 24
  %fv3042 = load ptr, ptr %fp3041, align 8
  %$f683.addr = alloca ptr
  store ptr %fv3042, ptr %$f683.addr
  %freed3043 = call i64 @march_decrc_freed(ptr %ld3035)
  %freed_b3044 = icmp ne i64 %freed3043, 0
  br i1 %freed_b3044, label %br_unique681, label %br_shared682
br_shared682:
  call void @march_incrc(ptr %fv3042)
  call void @march_incrc(ptr %fv3040)
  br label %br_body683
br_unique681:
  br label %br_body683
br_body683:
  %ld3045 = load ptr, ptr %$f681.addr
  %rest.addr = alloca ptr
  store ptr %ld3045, ptr %rest.addr
  %ld3046 = load ptr, ptr %$f683.addr
  %v.addr = alloca ptr
  store ptr %ld3046, ptr %v.addr
  %ld3047 = load ptr, ptr %$f682.addr
  %n.addr = alloca ptr
  store ptr %ld3047, ptr %n.addr
  %ld3048 = load ptr, ptr %n.addr
  %cr3049 = call ptr @march_string_to_lowercase(ptr %ld3048)
  %$t678.addr = alloca ptr
  store ptr %cr3049, ptr %$t678.addr
  %ld3050 = load ptr, ptr %$t678.addr
  %ld3051 = load ptr, ptr %lower_name.addr
  %cr3052 = call i64 @march_string_eq(ptr %ld3050, ptr %ld3051)
  %$t679.addr = alloca i64
  store i64 %cr3052, ptr %$t679.addr
  %ld3053 = load i64, ptr %$t679.addr
  %res_slot3054 = alloca ptr
  %bi3055 = trunc i64 %ld3053 to i1
  br i1 %bi3055, label %case_br686, label %case_default685
case_br686:
  %hp3056 = call ptr @march_alloc(i64 24)
  %tgp3057 = getelementptr i8, ptr %hp3056, i64 8
  store i32 1, ptr %tgp3057, align 4
  %ld3058 = load ptr, ptr %v.addr
  %fp3059 = getelementptr i8, ptr %hp3056, i64 16
  store ptr %ld3058, ptr %fp3059, align 8
  store ptr %hp3056, ptr %res_slot3054
  br label %case_merge684
case_default685:
  %ld3060 = load ptr, ptr %find.addr
  %fp3061 = getelementptr i8, ptr %ld3060, i64 16
  %fv3062 = load ptr, ptr %fp3061, align 8
  %ld3063 = load ptr, ptr %rest.addr
  %cr3064 = call ptr (ptr, ptr) %fv3062(ptr %ld3060, ptr %ld3063)
  store ptr %cr3064, ptr %res_slot3054
  br label %case_merge684
case_merge684:
  %case_r3065 = load ptr, ptr %res_slot3054
  store ptr %case_r3065, ptr %res_slot3036
  br label %case_merge678
case_default679:
  unreachable
case_merge678:
  %case_r3066 = load ptr, ptr %res_slot3036
  store ptr %case_r3066, ptr %res_slot3023
  br label %case_merge671
case_default672:
  unreachable
case_merge671:
  %case_r3067 = load ptr, ptr %res_slot3023
  ret ptr %case_r3067
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

