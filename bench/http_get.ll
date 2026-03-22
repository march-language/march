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
@.str18 = private unnamed_addr constant [42 x i8] c"March HTTP GET (connection-per-request): \00"
@.str19 = private unnamed_addr constant [10 x i8] c" requests\00"
@.str20 = private unnamed_addr constant [5 x i8] c"done\00"
@.str21 = private unnamed_addr constant [6 x i8] c"error\00"
@.str22 = private unnamed_addr constant [1 x i8] c"\00"
@.str23 = private unnamed_addr constant [30 x i8] c"March HTTP GET (keep-alive): \00"
@.str24 = private unnamed_addr constant [10 x i8] c" requests\00"
@.str25 = private unnamed_addr constant [18 x i8] c"error parsing url\00"
@.str26 = private unnamed_addr constant [1 x i8] c"\00"
@.str27 = private unnamed_addr constant [5 x i8] c"done\00"
@.str28 = private unnamed_addr constant [6 x i8] c"error\00"
@.str29 = private unnamed_addr constant [6 x i8] c"error\00"
@.str30 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str31 = private unnamed_addr constant [4 x i8] c"url\00"
@.str32 = private unnamed_addr constant [1 x i8] c"\00"
@.str33 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str34 = private unnamed_addr constant [4 x i8] c"url\00"
@.str35 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str36 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str37 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str38 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str39 = private unnamed_addr constant [9 x i8] c"location\00"
@.str40 = private unnamed_addr constant [1 x i8] c"\00"
@.str41 = private unnamed_addr constant [1 x i8] c"\00"
@.str42 = private unnamed_addr constant [9 x i8] c"location\00"
@.str43 = private unnamed_addr constant [1 x i8] c"\00"
@.str44 = private unnamed_addr constant [1 x i8] c"\00"
@.str45 = private unnamed_addr constant [11 x i8] c"Connection\00"
@.str46 = private unnamed_addr constant [6 x i8] c"close\00"

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
  %$t880_i24.addr = alloca ptr
  store ptr %hp410, ptr %$t880_i24.addr
  %hp412 = call ptr @march_alloc(i64 16)
  %tgp413 = getelementptr i8, ptr %hp412, i64 8
  store i32 0, ptr %tgp413, align 4
  %$t881_i25.addr = alloca ptr
  store ptr %hp412, ptr %$t881_i25.addr
  %hp414 = call ptr @march_alloc(i64 16)
  %tgp415 = getelementptr i8, ptr %hp414, i64 8
  store i32 0, ptr %tgp415, align 4
  %$t882_i26.addr = alloca ptr
  store ptr %hp414, ptr %$t882_i26.addr
  %hp416 = call ptr @march_alloc(i64 64)
  %tgp417 = getelementptr i8, ptr %hp416, i64 8
  store i32 0, ptr %tgp417, align 4
  %ld418 = load ptr, ptr %$t880_i24.addr
  %fp419 = getelementptr i8, ptr %hp416, i64 16
  store ptr %ld418, ptr %fp419, align 8
  %ld420 = load ptr, ptr %$t881_i25.addr
  %fp421 = getelementptr i8, ptr %hp416, i64 24
  store ptr %ld420, ptr %fp421, align 8
  %ld422 = load ptr, ptr %$t882_i26.addr
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
  %cr432 = call ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__5890_Result_Request_V__5889_V__5888(ptr %ld427, ptr %sl428, ptr %cwrap429)
  %client_1.addr = alloca ptr
  store ptr %cr432, ptr %client_1.addr
  %ld433 = load i64, ptr %n.addr
  %cr434 = call ptr @march_int_to_string(i64 %ld433)
  %$t2019.addr = alloca ptr
  store ptr %cr434, ptr %$t2019.addr
  %sl435 = call ptr @march_string_lit(ptr @.str18, i64 41)
  %ld436 = load ptr, ptr %$t2019.addr
  %cr437 = call ptr @march_string_concat(ptr %sl435, ptr %ld436)
  %$t2020.addr = alloca ptr
  store ptr %cr437, ptr %$t2020.addr
  %ld438 = load ptr, ptr %$t2020.addr
  %sl439 = call ptr @march_string_lit(ptr @.str19, i64 9)
  %cr440 = call ptr @march_string_concat(ptr %ld438, ptr %sl439)
  %$t2021.addr = alloca ptr
  store ptr %cr440, ptr %$t2021.addr
  %ld441 = load ptr, ptr %$t2021.addr
  call void @march_print(ptr %ld441)
  %ld442 = load ptr, ptr %client_1.addr
  call void @march_incrc(ptr %ld442)
  %ld443 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld443)
  %ld444 = load i64, ptr %n.addr
  %ld445 = load ptr, ptr %client_1.addr
  %ld446 = load ptr, ptr %url.addr
  %cr447 = call ptr @run_requests(i64 %ld444, ptr %ld445, ptr %ld446)
  %$t2022.addr = alloca ptr
  store ptr %cr447, ptr %$t2022.addr
  %ld448 = load ptr, ptr %$t2022.addr
  %res_slot449 = alloca ptr
  %tgp450 = getelementptr i8, ptr %ld448, i64 8
  %tag451 = load i32, ptr %tgp450, align 4
  switch i32 %tag451, label %case_default91 [
      i32 0, label %case_br92
      i32 1, label %case_br93
  ]
case_br92:
  %fp452 = getelementptr i8, ptr %ld448, i64 16
  %fv453 = load ptr, ptr %fp452, align 8
  %$f2023.addr = alloca ptr
  store ptr %fv453, ptr %$f2023.addr
  %ld454 = load ptr, ptr %$t2022.addr
  call void @march_decrc(ptr %ld454)
  %sl455 = call ptr @march_string_lit(ptr @.str20, i64 4)
  call void @march_print(ptr %sl455)
  %cv456 = inttoptr i64 0 to ptr
  store ptr %cv456, ptr %res_slot449
  br label %case_merge90
case_br93:
  %fp457 = getelementptr i8, ptr %ld448, i64 16
  %fv458 = load ptr, ptr %fp457, align 8
  %$f2024.addr = alloca ptr
  store ptr %fv458, ptr %$f2024.addr
  %freed459 = call i64 @march_decrc_freed(ptr %ld448)
  %freed_b460 = icmp ne i64 %freed459, 0
  br i1 %freed_b460, label %br_unique94, label %br_shared95
br_shared95:
  call void @march_incrc(ptr %fv458)
  br label %br_body96
br_unique94:
  br label %br_body96
br_body96:
  %sl461 = call ptr @march_string_lit(ptr @.str21, i64 5)
  call void @march_print(ptr %sl461)
  %cv462 = inttoptr i64 0 to ptr
  store ptr %cv462, ptr %res_slot449
  br label %case_merge90
case_default91:
  unreachable
case_merge90:
  %case_r463 = load ptr, ptr %res_slot449
  %sl464 = call ptr @march_string_lit(ptr @.str22, i64 0)
  call void @march_print(ptr %sl464)
  %ld465 = load i64, ptr %n.addr
  %cr466 = call ptr @march_int_to_string(i64 %ld465)
  %$t2025.addr = alloca ptr
  store ptr %cr466, ptr %$t2025.addr
  %sl467 = call ptr @march_string_lit(ptr @.str23, i64 29)
  %ld468 = load ptr, ptr %$t2025.addr
  %cr469 = call ptr @march_string_concat(ptr %sl467, ptr %ld468)
  %$t2026.addr = alloca ptr
  store ptr %cr469, ptr %$t2026.addr
  %ld470 = load ptr, ptr %$t2026.addr
  %sl471 = call ptr @march_string_lit(ptr @.str24, i64 9)
  %cr472 = call ptr @march_string_concat(ptr %ld470, ptr %sl471)
  %$t2027.addr = alloca ptr
  store ptr %cr472, ptr %$t2027.addr
  %ld473 = load ptr, ptr %$t2027.addr
  call void @march_print(ptr %ld473)
  %ld474 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld474)
  %ld475 = load ptr, ptr %url.addr
  %url_i23.addr = alloca ptr
  store ptr %ld475, ptr %url_i23.addr
  %ld476 = load ptr, ptr %url_i23.addr
  %cr477 = call ptr @Http.parse_url(ptr %ld476)
  %$t2028.addr = alloca ptr
  store ptr %cr477, ptr %$t2028.addr
  %ld478 = load ptr, ptr %$t2028.addr
  %res_slot479 = alloca ptr
  %tgp480 = getelementptr i8, ptr %ld478, i64 8
  %tag481 = load i32, ptr %tgp480, align 4
  switch i32 %tag481, label %case_default98 [
      i32 1, label %case_br99
      i32 0, label %case_br100
  ]
case_br99:
  %fp482 = getelementptr i8, ptr %ld478, i64 16
  %fv483 = load ptr, ptr %fp482, align 8
  %$f2032.addr = alloca ptr
  store ptr %fv483, ptr %$f2032.addr
  %freed484 = call i64 @march_decrc_freed(ptr %ld478)
  %freed_b485 = icmp ne i64 %freed484, 0
  br i1 %freed_b485, label %br_unique101, label %br_shared102
br_shared102:
  call void @march_incrc(ptr %fv483)
  br label %br_body103
br_unique101:
  br label %br_body103
br_body103:
  %sl486 = call ptr @march_string_lit(ptr @.str25, i64 17)
  call void @march_print(ptr %sl486)
  %cv487 = inttoptr i64 0 to ptr
  store ptr %cv487, ptr %res_slot479
  br label %case_merge97
case_br100:
  %fp488 = getelementptr i8, ptr %ld478, i64 16
  %fv489 = load ptr, ptr %fp488, align 8
  %$f2033.addr = alloca ptr
  store ptr %fv489, ptr %$f2033.addr
  %freed490 = call i64 @march_decrc_freed(ptr %ld478)
  %freed_b491 = icmp ne i64 %freed490, 0
  br i1 %freed_b491, label %br_unique104, label %br_shared105
br_shared105:
  call void @march_incrc(ptr %fv489)
  br label %br_body106
br_unique104:
  br label %br_body106
br_body106:
  %ld492 = load ptr, ptr %$f2033.addr
  %req.addr = alloca ptr
  store ptr %ld492, ptr %req.addr
  %ld493 = load ptr, ptr %req.addr
  %sl494 = call ptr @march_string_lit(ptr @.str26, i64 0)
  %cr495 = call ptr @Http.set_body$Request_T_$String(ptr %ld493, ptr %sl494)
  %req_1.addr = alloca ptr
  store ptr %cr495, ptr %req_1.addr
  %hp496 = call ptr @march_alloc(i64 40)
  %tgp497 = getelementptr i8, ptr %hp496, i64 8
  store i32 0, ptr %tgp497, align 4
  %fp498 = getelementptr i8, ptr %hp496, i64 16
  store ptr @callback$apply$21, ptr %fp498, align 8
  %ld499 = load i64, ptr %n.addr
  %fp500 = getelementptr i8, ptr %hp496, i64 24
  store i64 %ld499, ptr %fp500, align 8
  %ld501 = load ptr, ptr %req_1.addr
  %fp502 = getelementptr i8, ptr %hp496, i64 32
  store ptr %ld501, ptr %fp502, align 8
  %callback.addr = alloca ptr
  store ptr %hp496, ptr %callback.addr
  %ld503 = load ptr, ptr %client_1.addr
  %ld504 = load ptr, ptr %url.addr
  %ld505 = load ptr, ptr %callback.addr
  %cr506 = call ptr @HttpClient.with_connection$Client$String$Fn_Fn_Request_String_Result_Response_V__3284_HttpError_Result_Int_HttpError(ptr %ld503, ptr %ld504, ptr %ld505)
  %$t2029.addr = alloca ptr
  store ptr %cr506, ptr %$t2029.addr
  %ld507 = load ptr, ptr %$t2029.addr
  %res_slot508 = alloca ptr
  %tgp509 = getelementptr i8, ptr %ld507, i64 8
  %tag510 = load i32, ptr %tgp509, align 4
  switch i32 %tag510, label %case_default108 [
      i32 0, label %case_br109
  ]
case_br109:
  %fp511 = getelementptr i8, ptr %ld507, i64 16
  %fv512 = load ptr, ptr %fp511, align 8
  %$f2030.addr = alloca ptr
  store ptr %fv512, ptr %$f2030.addr
  %freed513 = call i64 @march_decrc_freed(ptr %ld507)
  %freed_b514 = icmp ne i64 %freed513, 0
  br i1 %freed_b514, label %br_unique110, label %br_shared111
br_shared111:
  call void @march_incrc(ptr %fv512)
  br label %br_body112
br_unique110:
  br label %br_body112
br_body112:
  %ld515 = load ptr, ptr %$f2030.addr
  %res_slot516 = alloca ptr
  %tgp517 = getelementptr i8, ptr %ld515, i64 8
  %tag518 = load i32, ptr %tgp517, align 4
  switch i32 %tag518, label %case_default114 [
      i32 0, label %case_br115
  ]
case_br115:
  %fp519 = getelementptr i8, ptr %ld515, i64 16
  %fv520 = load ptr, ptr %fp519, align 8
  %$f2031.addr = alloca ptr
  store ptr %fv520, ptr %$f2031.addr
  %freed521 = call i64 @march_decrc_freed(ptr %ld515)
  %freed_b522 = icmp ne i64 %freed521, 0
  br i1 %freed_b522, label %br_unique116, label %br_shared117
br_shared117:
  call void @march_incrc(ptr %fv520)
  br label %br_body118
br_unique116:
  br label %br_body118
br_body118:
  %sl523 = call ptr @march_string_lit(ptr @.str27, i64 4)
  call void @march_print(ptr %sl523)
  %cv524 = inttoptr i64 0 to ptr
  store ptr %cv524, ptr %res_slot516
  br label %case_merge113
case_default114:
  %ld525 = load ptr, ptr %$f2030.addr
  call void @march_decrc(ptr %ld525)
  %sl526 = call ptr @march_string_lit(ptr @.str28, i64 5)
  call void @march_print(ptr %sl526)
  %cv527 = inttoptr i64 0 to ptr
  store ptr %cv527, ptr %res_slot516
  br label %case_merge113
case_merge113:
  %case_r528 = load ptr, ptr %res_slot516
  store ptr %case_r528, ptr %res_slot508
  br label %case_merge107
case_default108:
  %ld529 = load ptr, ptr %$t2029.addr
  call void @march_decrc(ptr %ld529)
  %sl530 = call ptr @march_string_lit(ptr @.str29, i64 5)
  call void @march_print(ptr %sl530)
  %cv531 = inttoptr i64 0 to ptr
  store ptr %cv531, ptr %res_slot508
  br label %case_merge107
case_merge107:
  %case_r532 = load ptr, ptr %res_slot508
  store ptr %case_r532, ptr %res_slot479
  br label %case_merge97
case_default98:
  unreachable
case_merge97:
  %case_r533 = load ptr, ptr %res_slot479
  ret ptr %case_r533
}

define ptr @HttpClient.get(ptr %client.arg, ptr %url.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld534 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld534)
  %ld535 = load ptr, ptr %url.addr
  %url_i27.addr = alloca ptr
  store ptr %ld535, ptr %url_i27.addr
  %ld536 = load ptr, ptr %url_i27.addr
  %cr537 = call ptr @Http.parse_url(ptr %ld536)
  %$t1098.addr = alloca ptr
  store ptr %cr537, ptr %$t1098.addr
  %ld538 = load ptr, ptr %$t1098.addr
  %res_slot539 = alloca ptr
  %tgp540 = getelementptr i8, ptr %ld538, i64 8
  %tag541 = load i32, ptr %tgp540, align 4
  switch i32 %tag541, label %case_default120 [
      i32 1, label %case_br121
      i32 0, label %case_br122
  ]
case_br121:
  %fp542 = getelementptr i8, ptr %ld538, i64 16
  %fv543 = load ptr, ptr %fp542, align 8
  %$f1102.addr = alloca ptr
  store ptr %fv543, ptr %$f1102.addr
  %sl544 = call ptr @march_string_lit(ptr @.str30, i64 13)
  %ld545 = load ptr, ptr %url.addr
  %cr546 = call ptr @march_string_concat(ptr %sl544, ptr %ld545)
  %$t1099.addr = alloca ptr
  store ptr %cr546, ptr %$t1099.addr
  %hp547 = call ptr @march_alloc(i64 32)
  %tgp548 = getelementptr i8, ptr %hp547, i64 8
  store i32 1, ptr %tgp548, align 4
  %sl549 = call ptr @march_string_lit(ptr @.str31, i64 3)
  %fp550 = getelementptr i8, ptr %hp547, i64 16
  store ptr %sl549, ptr %fp550, align 8
  %ld551 = load ptr, ptr %$t1099.addr
  %fp552 = getelementptr i8, ptr %hp547, i64 24
  store ptr %ld551, ptr %fp552, align 8
  %$t1100.addr = alloca ptr
  store ptr %hp547, ptr %$t1100.addr
  %ld553 = load ptr, ptr %$t1098.addr
  %ld554 = load ptr, ptr %$t1100.addr
  %rc555 = load i64, ptr %ld553, align 8
  %uniq556 = icmp eq i64 %rc555, 1
  %fbip_slot557 = alloca ptr
  br i1 %uniq556, label %fbip_reuse123, label %fbip_fresh124
fbip_reuse123:
  %tgp558 = getelementptr i8, ptr %ld553, i64 8
  store i32 1, ptr %tgp558, align 4
  %fp559 = getelementptr i8, ptr %ld553, i64 16
  store ptr %ld554, ptr %fp559, align 8
  store ptr %ld553, ptr %fbip_slot557
  br label %fbip_merge125
fbip_fresh124:
  call void @march_decrc(ptr %ld553)
  %hp560 = call ptr @march_alloc(i64 24)
  %tgp561 = getelementptr i8, ptr %hp560, i64 8
  store i32 1, ptr %tgp561, align 4
  %fp562 = getelementptr i8, ptr %hp560, i64 16
  store ptr %ld554, ptr %fp562, align 8
  store ptr %hp560, ptr %fbip_slot557
  br label %fbip_merge125
fbip_merge125:
  %fbip_r563 = load ptr, ptr %fbip_slot557
  store ptr %fbip_r563, ptr %res_slot539
  br label %case_merge119
case_br122:
  %fp564 = getelementptr i8, ptr %ld538, i64 16
  %fv565 = load ptr, ptr %fp564, align 8
  %$f1103.addr = alloca ptr
  store ptr %fv565, ptr %$f1103.addr
  %freed566 = call i64 @march_decrc_freed(ptr %ld538)
  %freed_b567 = icmp ne i64 %freed566, 0
  br i1 %freed_b567, label %br_unique126, label %br_shared127
br_shared127:
  call void @march_incrc(ptr %fv565)
  br label %br_body128
br_unique126:
  br label %br_body128
br_body128:
  %ld568 = load ptr, ptr %$f1103.addr
  %req.addr = alloca ptr
  store ptr %ld568, ptr %req.addr
  %ld569 = load ptr, ptr %req.addr
  %sl570 = call ptr @march_string_lit(ptr @.str32, i64 0)
  %cr571 = call ptr @Http.set_body$Request_T_$String(ptr %ld569, ptr %sl570)
  %$t1101.addr = alloca ptr
  store ptr %cr571, ptr %$t1101.addr
  %ld572 = load ptr, ptr %client.addr
  %ld573 = load ptr, ptr %$t1101.addr
  %cr574 = call ptr @HttpClient.run(ptr %ld572, ptr %ld573)
  store ptr %cr574, ptr %res_slot539
  br label %case_merge119
case_default120:
  unreachable
case_merge119:
  %case_r575 = load ptr, ptr %res_slot539
  ret ptr %case_r575
}

define ptr @HttpClient.with_connection$Client$String$Fn_Fn_Request_String_Result_Response_V__3284_HttpError_Result_Int_HttpError(ptr %client.arg, ptr %url.arg, ptr %callback.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld576 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld576)
  %ld577 = load ptr, ptr %url.addr
  %cr578 = call ptr @Http.parse_url(ptr %ld577)
  %$t1058.addr = alloca ptr
  store ptr %cr578, ptr %$t1058.addr
  %ld579 = load ptr, ptr %$t1058.addr
  %res_slot580 = alloca ptr
  %tgp581 = getelementptr i8, ptr %ld579, i64 8
  %tag582 = load i32, ptr %tgp581, align 4
  switch i32 %tag582, label %case_default130 [
      i32 1, label %case_br131
      i32 0, label %case_br132
  ]
case_br131:
  %fp583 = getelementptr i8, ptr %ld579, i64 16
  %fv584 = load ptr, ptr %fp583, align 8
  %$f1071.addr = alloca ptr
  store ptr %fv584, ptr %$f1071.addr
  %sl585 = call ptr @march_string_lit(ptr @.str33, i64 13)
  %ld586 = load ptr, ptr %url.addr
  %cr587 = call ptr @march_string_concat(ptr %sl585, ptr %ld586)
  %$t1059.addr = alloca ptr
  store ptr %cr587, ptr %$t1059.addr
  %hp588 = call ptr @march_alloc(i64 32)
  %tgp589 = getelementptr i8, ptr %hp588, i64 8
  store i32 1, ptr %tgp589, align 4
  %sl590 = call ptr @march_string_lit(ptr @.str34, i64 3)
  %fp591 = getelementptr i8, ptr %hp588, i64 16
  store ptr %sl590, ptr %fp591, align 8
  %ld592 = load ptr, ptr %$t1059.addr
  %fp593 = getelementptr i8, ptr %hp588, i64 24
  store ptr %ld592, ptr %fp593, align 8
  %$t1060.addr = alloca ptr
  store ptr %hp588, ptr %$t1060.addr
  %ld594 = load ptr, ptr %$t1058.addr
  %ld595 = load ptr, ptr %$t1060.addr
  %rc596 = load i64, ptr %ld594, align 8
  %uniq597 = icmp eq i64 %rc596, 1
  %fbip_slot598 = alloca ptr
  br i1 %uniq597, label %fbip_reuse133, label %fbip_fresh134
fbip_reuse133:
  %tgp599 = getelementptr i8, ptr %ld594, i64 8
  store i32 1, ptr %tgp599, align 4
  %fp600 = getelementptr i8, ptr %ld594, i64 16
  store ptr %ld595, ptr %fp600, align 8
  store ptr %ld594, ptr %fbip_slot598
  br label %fbip_merge135
fbip_fresh134:
  call void @march_decrc(ptr %ld594)
  %hp601 = call ptr @march_alloc(i64 24)
  %tgp602 = getelementptr i8, ptr %hp601, i64 8
  store i32 1, ptr %tgp602, align 4
  %fp603 = getelementptr i8, ptr %hp601, i64 16
  store ptr %ld595, ptr %fp603, align 8
  store ptr %hp601, ptr %fbip_slot598
  br label %fbip_merge135
fbip_merge135:
  %fbip_r604 = load ptr, ptr %fbip_slot598
  store ptr %fbip_r604, ptr %res_slot580
  br label %case_merge129
case_br132:
  %fp605 = getelementptr i8, ptr %ld579, i64 16
  %fv606 = load ptr, ptr %fp605, align 8
  %$f1072.addr = alloca ptr
  store ptr %fv606, ptr %$f1072.addr
  %freed607 = call i64 @march_decrc_freed(ptr %ld579)
  %freed_b608 = icmp ne i64 %freed607, 0
  br i1 %freed_b608, label %br_unique136, label %br_shared137
br_shared137:
  call void @march_incrc(ptr %fv606)
  br label %br_body138
br_unique136:
  br label %br_body138
br_body138:
  %ld609 = load ptr, ptr %$f1072.addr
  %base_req.addr = alloca ptr
  store ptr %ld609, ptr %base_req.addr
  %ld610 = load ptr, ptr %base_req.addr
  %cr611 = call ptr @HttpTransport.connect$Request_T_(ptr %ld610)
  %$t1061.addr = alloca ptr
  store ptr %cr611, ptr %$t1061.addr
  %ld612 = load ptr, ptr %$t1061.addr
  %res_slot613 = alloca ptr
  %tgp614 = getelementptr i8, ptr %ld612, i64 8
  %tag615 = load i32, ptr %tgp614, align 4
  switch i32 %tag615, label %case_default140 [
      i32 1, label %case_br141
      i32 0, label %case_br142
  ]
case_br141:
  %fp616 = getelementptr i8, ptr %ld612, i64 16
  %fv617 = load ptr, ptr %fp616, align 8
  %$f1069.addr = alloca ptr
  store ptr %fv617, ptr %$f1069.addr
  %ld618 = load ptr, ptr %$f1069.addr
  %e.addr = alloca ptr
  store ptr %ld618, ptr %e.addr
  %hp619 = call ptr @march_alloc(i64 24)
  %tgp620 = getelementptr i8, ptr %hp619, i64 8
  store i32 0, ptr %tgp620, align 4
  %ld621 = load ptr, ptr %e.addr
  %fp622 = getelementptr i8, ptr %hp619, i64 16
  store ptr %ld621, ptr %fp622, align 8
  %$t1062.addr = alloca ptr
  store ptr %hp619, ptr %$t1062.addr
  %ld623 = load ptr, ptr %$t1061.addr
  %ld624 = load ptr, ptr %$t1062.addr
  %rc625 = load i64, ptr %ld623, align 8
  %uniq626 = icmp eq i64 %rc625, 1
  %fbip_slot627 = alloca ptr
  br i1 %uniq626, label %fbip_reuse143, label %fbip_fresh144
fbip_reuse143:
  %tgp628 = getelementptr i8, ptr %ld623, i64 8
  store i32 1, ptr %tgp628, align 4
  %fp629 = getelementptr i8, ptr %ld623, i64 16
  store ptr %ld624, ptr %fp629, align 8
  store ptr %ld623, ptr %fbip_slot627
  br label %fbip_merge145
fbip_fresh144:
  call void @march_decrc(ptr %ld623)
  %hp630 = call ptr @march_alloc(i64 24)
  %tgp631 = getelementptr i8, ptr %hp630, i64 8
  store i32 1, ptr %tgp631, align 4
  %fp632 = getelementptr i8, ptr %hp630, i64 16
  store ptr %ld624, ptr %fp632, align 8
  store ptr %hp630, ptr %fbip_slot627
  br label %fbip_merge145
fbip_merge145:
  %fbip_r633 = load ptr, ptr %fbip_slot627
  store ptr %fbip_r633, ptr %res_slot613
  br label %case_merge139
case_br142:
  %fp634 = getelementptr i8, ptr %ld612, i64 16
  %fv635 = load ptr, ptr %fp634, align 8
  %$f1070.addr = alloca ptr
  store ptr %fv635, ptr %$f1070.addr
  %freed636 = call i64 @march_decrc_freed(ptr %ld612)
  %freed_b637 = icmp ne i64 %freed636, 0
  br i1 %freed_b637, label %br_unique146, label %br_shared147
br_shared147:
  call void @march_incrc(ptr %fv635)
  br label %br_body148
br_unique146:
  br label %br_body148
br_body148:
  %ld638 = load ptr, ptr %$f1070.addr
  %fd.addr = alloca ptr
  store ptr %ld638, ptr %fd.addr
  %ld639 = load ptr, ptr %client.addr
  %res_slot640 = alloca ptr
  %tgp641 = getelementptr i8, ptr %ld639, i64 8
  %tag642 = load i32, ptr %tgp641, align 4
  switch i32 %tag642, label %case_default150 [
      i32 0, label %case_br151
  ]
case_br151:
  %fp643 = getelementptr i8, ptr %ld639, i64 16
  %fv644 = load ptr, ptr %fp643, align 8
  %$f1063.addr = alloca ptr
  store ptr %fv644, ptr %$f1063.addr
  %fp645 = getelementptr i8, ptr %ld639, i64 24
  %fv646 = load ptr, ptr %fp645, align 8
  %$f1064.addr = alloca ptr
  store ptr %fv646, ptr %$f1064.addr
  %fp647 = getelementptr i8, ptr %ld639, i64 32
  %fv648 = load ptr, ptr %fp647, align 8
  %$f1065.addr = alloca ptr
  store ptr %fv648, ptr %$f1065.addr
  %fp649 = getelementptr i8, ptr %ld639, i64 40
  %fv650 = load i64, ptr %fp649, align 8
  %$f1066.addr = alloca i64
  store i64 %fv650, ptr %$f1066.addr
  %fp651 = getelementptr i8, ptr %ld639, i64 48
  %fv652 = load i64, ptr %fp651, align 8
  %$f1067.addr = alloca i64
  store i64 %fv652, ptr %$f1067.addr
  %fp653 = getelementptr i8, ptr %ld639, i64 56
  %fv654 = load i64, ptr %fp653, align 8
  %$f1068.addr = alloca i64
  store i64 %fv654, ptr %$f1068.addr
  %freed655 = call i64 @march_decrc_freed(ptr %ld639)
  %freed_b656 = icmp ne i64 %freed655, 0
  br i1 %freed_b656, label %br_unique152, label %br_shared153
br_shared153:
  call void @march_incrc(ptr %fv648)
  call void @march_incrc(ptr %fv646)
  call void @march_incrc(ptr %fv644)
  br label %br_body154
br_unique152:
  br label %br_body154
br_body154:
  %ld657 = load i64, ptr %$f1067.addr
  %max_retries.addr = alloca i64
  store i64 %ld657, ptr %max_retries.addr
  %ld658 = load i64, ptr %$f1066.addr
  %max_redir.addr = alloca i64
  store i64 %ld658, ptr %max_redir.addr
  %ld659 = load ptr, ptr %$f1065.addr
  %err_steps.addr = alloca ptr
  store ptr %ld659, ptr %err_steps.addr
  %ld660 = load ptr, ptr %$f1064.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld660, ptr %resp_steps.addr
  %ld661 = load ptr, ptr %$f1063.addr
  %req_steps.addr = alloca ptr
  store ptr %ld661, ptr %req_steps.addr
  %ld662 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld662)
  %hp663 = call ptr @march_alloc(i64 72)
  %tgp664 = getelementptr i8, ptr %hp663, i64 8
  store i32 0, ptr %tgp664, align 4
  %fp665 = getelementptr i8, ptr %hp663, i64 16
  store ptr @do_request$apply$24, ptr %fp665, align 8
  %ld666 = load ptr, ptr %err_steps.addr
  %fp667 = getelementptr i8, ptr %hp663, i64 24
  store ptr %ld666, ptr %fp667, align 8
  %ld668 = load ptr, ptr %fd.addr
  %fp669 = getelementptr i8, ptr %hp663, i64 32
  store ptr %ld668, ptr %fp669, align 8
  %ld670 = load i64, ptr %max_redir.addr
  %fp671 = getelementptr i8, ptr %hp663, i64 40
  store i64 %ld670, ptr %fp671, align 8
  %ld672 = load i64, ptr %max_retries.addr
  %fp673 = getelementptr i8, ptr %hp663, i64 48
  store i64 %ld672, ptr %fp673, align 8
  %ld674 = load ptr, ptr %req_steps.addr
  %fp675 = getelementptr i8, ptr %hp663, i64 56
  store ptr %ld674, ptr %fp675, align 8
  %ld676 = load ptr, ptr %resp_steps.addr
  %fp677 = getelementptr i8, ptr %hp663, i64 64
  store ptr %ld676, ptr %fp677, align 8
  %do_request.addr = alloca ptr
  store ptr %hp663, ptr %do_request.addr
  %ld678 = load ptr, ptr %callback.addr
  %fp679 = getelementptr i8, ptr %ld678, i64 16
  %fv680 = load ptr, ptr %fp679, align 8
  %ld681 = load ptr, ptr %do_request.addr
  %cr682 = call ptr (ptr, ptr) %fv680(ptr %ld678, ptr %ld681)
  %result.addr = alloca ptr
  store ptr %cr682, ptr %result.addr
  %ld683 = load ptr, ptr %tcp_close.addr
  %fp684 = getelementptr i8, ptr %ld683, i64 16
  %fv685 = load ptr, ptr %fp684, align 8
  %ld686 = load ptr, ptr %fd.addr
  %cr687 = call ptr (ptr, ptr) %fv685(ptr %ld683, ptr %ld686)
  %hp688 = call ptr @march_alloc(i64 24)
  %tgp689 = getelementptr i8, ptr %hp688, i64 8
  store i32 0, ptr %tgp689, align 4
  %ld690 = load ptr, ptr %result.addr
  %fp691 = getelementptr i8, ptr %hp688, i64 16
  store ptr %ld690, ptr %fp691, align 8
  store ptr %hp688, ptr %res_slot640
  br label %case_merge149
case_default150:
  unreachable
case_merge149:
  %case_r692 = load ptr, ptr %res_slot640
  store ptr %case_r692, ptr %res_slot613
  br label %case_merge139
case_default140:
  unreachable
case_merge139:
  %case_r693 = load ptr, ptr %res_slot613
  store ptr %case_r693, ptr %res_slot580
  br label %case_merge129
case_default130:
  unreachable
case_merge129:
  %case_r694 = load ptr, ptr %res_slot580
  ret ptr %case_r694
}

define ptr @run_keepalive$Int$Fn_Request_String_Result_V__5912_V__5911$Request_String(i64 %n.arg, ptr %do_request.arg, ptr %req.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %do_request.addr = alloca ptr
  store ptr %do_request.arg, ptr %do_request.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld695 = load i64, ptr %n.addr
  %cmp696 = icmp eq i64 %ld695, 0
  %ar697 = zext i1 %cmp696 to i64
  %$t2014.addr = alloca i64
  store i64 %ar697, ptr %$t2014.addr
  %ld698 = load i64, ptr %$t2014.addr
  %res_slot699 = alloca ptr
  %bi700 = trunc i64 %ld698 to i1
  br i1 %bi700, label %case_br157, label %case_default156
case_br157:
  %hp701 = call ptr @march_alloc(i64 24)
  %tgp702 = getelementptr i8, ptr %hp701, i64 8
  store i32 0, ptr %tgp702, align 4
  %cv703 = inttoptr i64 0 to ptr
  %fp704 = getelementptr i8, ptr %hp701, i64 16
  store ptr %cv703, ptr %fp704, align 8
  store ptr %hp701, ptr %res_slot699
  br label %case_merge155
case_default156:
  %ld705 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld705)
  %ld706 = load ptr, ptr %do_request.addr
  %fp707 = getelementptr i8, ptr %ld706, i64 16
  %fv708 = load ptr, ptr %fp707, align 8
  %ld709 = load ptr, ptr %req.addr
  %cr710 = call ptr (ptr, ptr) %fv708(ptr %ld706, ptr %ld709)
  %$t2015.addr = alloca ptr
  store ptr %cr710, ptr %$t2015.addr
  %ld711 = load ptr, ptr %$t2015.addr
  %res_slot712 = alloca ptr
  %tgp713 = getelementptr i8, ptr %ld711, i64 8
  %tag714 = load i32, ptr %tgp713, align 4
  switch i32 %tag714, label %case_default159 [
      i32 0, label %case_br160
      i32 1, label %case_br161
  ]
case_br160:
  %fp715 = getelementptr i8, ptr %ld711, i64 16
  %fv716 = load ptr, ptr %fp715, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv716, ptr %$f2017.addr
  %freed717 = call i64 @march_decrc_freed(ptr %ld711)
  %freed_b718 = icmp ne i64 %freed717, 0
  br i1 %freed_b718, label %br_unique162, label %br_shared163
br_shared163:
  call void @march_incrc(ptr %fv716)
  br label %br_body164
br_unique162:
  br label %br_body164
br_body164:
  %ld719 = load i64, ptr %n.addr
  %ar720 = sub i64 %ld719, 1
  %$t2016.addr = alloca i64
  store i64 %ar720, ptr %$t2016.addr
  %ld721 = load i64, ptr %$t2016.addr
  %ld722 = load ptr, ptr %do_request.addr
  %ld723 = load ptr, ptr %req.addr
  %cr724 = call ptr @run_keepalive$Int$Fn_Request_String_Result_V__5912_V__5911$Request_String(i64 %ld721, ptr %ld722, ptr %ld723)
  store ptr %cr724, ptr %res_slot712
  br label %case_merge158
case_br161:
  %fp725 = getelementptr i8, ptr %ld711, i64 16
  %fv726 = load ptr, ptr %fp725, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv726, ptr %$f2018.addr
  %ld727 = load ptr, ptr %$f2018.addr
  %e.addr = alloca ptr
  store ptr %ld727, ptr %e.addr
  %ld728 = load ptr, ptr %$t2015.addr
  %ld729 = load ptr, ptr %e.addr
  %rc730 = load i64, ptr %ld728, align 8
  %uniq731 = icmp eq i64 %rc730, 1
  %fbip_slot732 = alloca ptr
  br i1 %uniq731, label %fbip_reuse165, label %fbip_fresh166
fbip_reuse165:
  %tgp733 = getelementptr i8, ptr %ld728, i64 8
  store i32 1, ptr %tgp733, align 4
  %fp734 = getelementptr i8, ptr %ld728, i64 16
  store ptr %ld729, ptr %fp734, align 8
  store ptr %ld728, ptr %fbip_slot732
  br label %fbip_merge167
fbip_fresh166:
  call void @march_decrc(ptr %ld728)
  %hp735 = call ptr @march_alloc(i64 24)
  %tgp736 = getelementptr i8, ptr %hp735, i64 8
  store i32 1, ptr %tgp736, align 4
  %fp737 = getelementptr i8, ptr %hp735, i64 16
  store ptr %ld729, ptr %fp737, align 8
  store ptr %hp735, ptr %fbip_slot732
  br label %fbip_merge167
fbip_merge167:
  %fbip_r738 = load ptr, ptr %fbip_slot732
  store ptr %fbip_r738, ptr %res_slot712
  br label %case_merge158
case_default159:
  unreachable
case_merge158:
  %case_r739 = load ptr, ptr %res_slot712
  store ptr %case_r739, ptr %res_slot699
  br label %case_merge155
case_merge155:
  %case_r740 = load ptr, ptr %res_slot699
  ret ptr %case_r740
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld741 = load ptr, ptr %req.addr
  %res_slot742 = alloca ptr
  %tgp743 = getelementptr i8, ptr %ld741, i64 8
  %tag744 = load i32, ptr %tgp743, align 4
  switch i32 %tag744, label %case_default169 [
      i32 0, label %case_br170
  ]
case_br170:
  %fp745 = getelementptr i8, ptr %ld741, i64 16
  %fv746 = load ptr, ptr %fp745, align 8
  %$f648.addr = alloca ptr
  store ptr %fv746, ptr %$f648.addr
  %fp747 = getelementptr i8, ptr %ld741, i64 24
  %fv748 = load ptr, ptr %fp747, align 8
  %$f649.addr = alloca ptr
  store ptr %fv748, ptr %$f649.addr
  %fp749 = getelementptr i8, ptr %ld741, i64 32
  %fv750 = load ptr, ptr %fp749, align 8
  %$f650.addr = alloca ptr
  store ptr %fv750, ptr %$f650.addr
  %fp751 = getelementptr i8, ptr %ld741, i64 40
  %fv752 = load ptr, ptr %fp751, align 8
  %$f651.addr = alloca ptr
  store ptr %fv752, ptr %$f651.addr
  %fp753 = getelementptr i8, ptr %ld741, i64 48
  %fv754 = load ptr, ptr %fp753, align 8
  %$f652.addr = alloca ptr
  store ptr %fv754, ptr %$f652.addr
  %fp755 = getelementptr i8, ptr %ld741, i64 56
  %fv756 = load ptr, ptr %fp755, align 8
  %$f653.addr = alloca ptr
  store ptr %fv756, ptr %$f653.addr
  %fp757 = getelementptr i8, ptr %ld741, i64 64
  %fv758 = load ptr, ptr %fp757, align 8
  %$f654.addr = alloca ptr
  store ptr %fv758, ptr %$f654.addr
  %fp759 = getelementptr i8, ptr %ld741, i64 72
  %fv760 = load ptr, ptr %fp759, align 8
  %$f655.addr = alloca ptr
  store ptr %fv760, ptr %$f655.addr
  %ld761 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld761, ptr %hd.addr
  %ld762 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld762, ptr %q.addr
  %ld763 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld763, ptr %pa.addr
  %ld764 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld764, ptr %p.addr
  %ld765 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld765, ptr %h.addr
  %ld766 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld766, ptr %sc.addr
  %ld767 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld767, ptr %m.addr
  %ld768 = load ptr, ptr %req.addr
  %ld769 = load ptr, ptr %m.addr
  %ld770 = load ptr, ptr %sc.addr
  %ld771 = load ptr, ptr %h.addr
  %ld772 = load ptr, ptr %p.addr
  %ld773 = load ptr, ptr %pa.addr
  %ld774 = load ptr, ptr %q.addr
  %ld775 = load ptr, ptr %hd.addr
  %ld776 = load ptr, ptr %new_body.addr
  %rc777 = load i64, ptr %ld768, align 8
  %uniq778 = icmp eq i64 %rc777, 1
  %fbip_slot779 = alloca ptr
  br i1 %uniq778, label %fbip_reuse171, label %fbip_fresh172
fbip_reuse171:
  %tgp780 = getelementptr i8, ptr %ld768, i64 8
  store i32 0, ptr %tgp780, align 4
  %fp781 = getelementptr i8, ptr %ld768, i64 16
  store ptr %ld769, ptr %fp781, align 8
  %fp782 = getelementptr i8, ptr %ld768, i64 24
  store ptr %ld770, ptr %fp782, align 8
  %fp783 = getelementptr i8, ptr %ld768, i64 32
  store ptr %ld771, ptr %fp783, align 8
  %fp784 = getelementptr i8, ptr %ld768, i64 40
  store ptr %ld772, ptr %fp784, align 8
  %fp785 = getelementptr i8, ptr %ld768, i64 48
  store ptr %ld773, ptr %fp785, align 8
  %fp786 = getelementptr i8, ptr %ld768, i64 56
  store ptr %ld774, ptr %fp786, align 8
  %fp787 = getelementptr i8, ptr %ld768, i64 64
  store ptr %ld775, ptr %fp787, align 8
  %fp788 = getelementptr i8, ptr %ld768, i64 72
  store ptr %ld776, ptr %fp788, align 8
  store ptr %ld768, ptr %fbip_slot779
  br label %fbip_merge173
fbip_fresh172:
  call void @march_decrc(ptr %ld768)
  %hp789 = call ptr @march_alloc(i64 80)
  %tgp790 = getelementptr i8, ptr %hp789, i64 8
  store i32 0, ptr %tgp790, align 4
  %fp791 = getelementptr i8, ptr %hp789, i64 16
  store ptr %ld769, ptr %fp791, align 8
  %fp792 = getelementptr i8, ptr %hp789, i64 24
  store ptr %ld770, ptr %fp792, align 8
  %fp793 = getelementptr i8, ptr %hp789, i64 32
  store ptr %ld771, ptr %fp793, align 8
  %fp794 = getelementptr i8, ptr %hp789, i64 40
  store ptr %ld772, ptr %fp794, align 8
  %fp795 = getelementptr i8, ptr %hp789, i64 48
  store ptr %ld773, ptr %fp795, align 8
  %fp796 = getelementptr i8, ptr %hp789, i64 56
  store ptr %ld774, ptr %fp796, align 8
  %fp797 = getelementptr i8, ptr %hp789, i64 64
  store ptr %ld775, ptr %fp797, align 8
  %fp798 = getelementptr i8, ptr %hp789, i64 72
  store ptr %ld776, ptr %fp798, align 8
  store ptr %hp789, ptr %fbip_slot779
  br label %fbip_merge173
fbip_merge173:
  %fbip_r799 = load ptr, ptr %fbip_slot779
  store ptr %fbip_r799, ptr %res_slot742
  br label %case_merge168
case_default169:
  unreachable
case_merge168:
  %case_r800 = load ptr, ptr %res_slot742
  ret ptr %case_r800
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld801 = load ptr, ptr %req.addr
  %sl802 = call ptr @march_string_lit(ptr @.str35, i64 10)
  %sl803 = call ptr @march_string_lit(ptr @.str36, i64 9)
  %cr804 = call ptr @Http.set_header$Request_V__3516$String$String(ptr %ld801, ptr %sl802, ptr %sl803)
  %req_1.addr = alloca ptr
  store ptr %cr804, ptr %req_1.addr
  %ld805 = load ptr, ptr %req_1.addr
  %sl806 = call ptr @march_string_lit(ptr @.str37, i64 6)
  %sl807 = call ptr @march_string_lit(ptr @.str38, i64 3)
  %cr808 = call ptr @Http.set_header$Request_V__3518$String$String(ptr %ld805, ptr %sl806, ptr %sl807)
  %req_2.addr = alloca ptr
  store ptr %cr808, ptr %req_2.addr
  %hp809 = call ptr @march_alloc(i64 24)
  %tgp810 = getelementptr i8, ptr %hp809, i64 8
  store i32 0, ptr %tgp810, align 4
  %ld811 = load ptr, ptr %req_2.addr
  %fp812 = getelementptr i8, ptr %hp809, i64 16
  store ptr %ld811, ptr %fp812, align 8
  ret ptr %hp809
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__5890_Result_Request_V__5889_V__5888(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld813 = load ptr, ptr %client.addr
  %res_slot814 = alloca ptr
  %tgp815 = getelementptr i8, ptr %ld813, i64 8
  %tag816 = load i32, ptr %tgp815, align 4
  switch i32 %tag816, label %case_default175 [
      i32 0, label %case_br176
  ]
case_br176:
  %fp817 = getelementptr i8, ptr %ld813, i64 16
  %fv818 = load ptr, ptr %fp817, align 8
  %$f889.addr = alloca ptr
  store ptr %fv818, ptr %$f889.addr
  %fp819 = getelementptr i8, ptr %ld813, i64 24
  %fv820 = load ptr, ptr %fp819, align 8
  %$f890.addr = alloca ptr
  store ptr %fv820, ptr %$f890.addr
  %fp821 = getelementptr i8, ptr %ld813, i64 32
  %fv822 = load ptr, ptr %fp821, align 8
  %$f891.addr = alloca ptr
  store ptr %fv822, ptr %$f891.addr
  %fp823 = getelementptr i8, ptr %ld813, i64 40
  %fv824 = load i64, ptr %fp823, align 8
  %$f892.addr = alloca i64
  store i64 %fv824, ptr %$f892.addr
  %fp825 = getelementptr i8, ptr %ld813, i64 48
  %fv826 = load i64, ptr %fp825, align 8
  %$f893.addr = alloca i64
  store i64 %fv826, ptr %$f893.addr
  %fp827 = getelementptr i8, ptr %ld813, i64 56
  %fv828 = load i64, ptr %fp827, align 8
  %$f894.addr = alloca i64
  store i64 %fv828, ptr %$f894.addr
  %ld829 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld829, ptr %backoff.addr
  %ld830 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld830, ptr %retries.addr
  %ld831 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld831, ptr %redir.addr
  %ld832 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld832, ptr %err_steps.addr
  %ld833 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld833, ptr %resp_steps.addr
  %ld834 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld834, ptr %req_steps.addr
  %hp835 = call ptr @march_alloc(i64 32)
  %tgp836 = getelementptr i8, ptr %hp835, i64 8
  store i32 0, ptr %tgp836, align 4
  %ld837 = load ptr, ptr %name.addr
  %fp838 = getelementptr i8, ptr %hp835, i64 16
  store ptr %ld837, ptr %fp838, align 8
  %ld839 = load ptr, ptr %step.addr
  %fp840 = getelementptr i8, ptr %hp835, i64 24
  store ptr %ld839, ptr %fp840, align 8
  %$t887.addr = alloca ptr
  store ptr %hp835, ptr %$t887.addr
  %ld841 = load ptr, ptr %req_steps.addr
  %ld842 = load ptr, ptr %$t887.addr
  %cr843 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld841, ptr %ld842)
  %$t888.addr = alloca ptr
  store ptr %cr843, ptr %$t888.addr
  %ld844 = load ptr, ptr %client.addr
  %ld845 = load ptr, ptr %$t888.addr
  %ld846 = load ptr, ptr %resp_steps.addr
  %ld847 = load ptr, ptr %err_steps.addr
  %ld848 = load i64, ptr %redir.addr
  %ld849 = load i64, ptr %retries.addr
  %ld850 = load i64, ptr %backoff.addr
  %rc851 = load i64, ptr %ld844, align 8
  %uniq852 = icmp eq i64 %rc851, 1
  %fbip_slot853 = alloca ptr
  br i1 %uniq852, label %fbip_reuse177, label %fbip_fresh178
fbip_reuse177:
  %tgp854 = getelementptr i8, ptr %ld844, i64 8
  store i32 0, ptr %tgp854, align 4
  %fp855 = getelementptr i8, ptr %ld844, i64 16
  store ptr %ld845, ptr %fp855, align 8
  %fp856 = getelementptr i8, ptr %ld844, i64 24
  store ptr %ld846, ptr %fp856, align 8
  %fp857 = getelementptr i8, ptr %ld844, i64 32
  store ptr %ld847, ptr %fp857, align 8
  %fp858 = getelementptr i8, ptr %ld844, i64 40
  store i64 %ld848, ptr %fp858, align 8
  %fp859 = getelementptr i8, ptr %ld844, i64 48
  store i64 %ld849, ptr %fp859, align 8
  %fp860 = getelementptr i8, ptr %ld844, i64 56
  store i64 %ld850, ptr %fp860, align 8
  store ptr %ld844, ptr %fbip_slot853
  br label %fbip_merge179
fbip_fresh178:
  call void @march_decrc(ptr %ld844)
  %hp861 = call ptr @march_alloc(i64 64)
  %tgp862 = getelementptr i8, ptr %hp861, i64 8
  store i32 0, ptr %tgp862, align 4
  %fp863 = getelementptr i8, ptr %hp861, i64 16
  store ptr %ld845, ptr %fp863, align 8
  %fp864 = getelementptr i8, ptr %hp861, i64 24
  store ptr %ld846, ptr %fp864, align 8
  %fp865 = getelementptr i8, ptr %hp861, i64 32
  store ptr %ld847, ptr %fp865, align 8
  %fp866 = getelementptr i8, ptr %hp861, i64 40
  store i64 %ld848, ptr %fp866, align 8
  %fp867 = getelementptr i8, ptr %hp861, i64 48
  store i64 %ld849, ptr %fp867, align 8
  %fp868 = getelementptr i8, ptr %hp861, i64 56
  store i64 %ld850, ptr %fp868, align 8
  store ptr %hp861, ptr %fbip_slot853
  br label %fbip_merge179
fbip_merge179:
  %fbip_r869 = load ptr, ptr %fbip_slot853
  store ptr %fbip_r869, ptr %res_slot814
  br label %case_merge174
case_default175:
  unreachable
case_merge174:
  %case_r870 = load ptr, ptr %res_slot814
  ret ptr %case_r870
}

define ptr @HttpClient.run(ptr %client.arg, ptr %req.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld871 = load ptr, ptr %client.addr
  %res_slot872 = alloca ptr
  %tgp873 = getelementptr i8, ptr %ld871, i64 8
  %tag874 = load i32, ptr %tgp873, align 4
  switch i32 %tag874, label %case_default181 [
      i32 0, label %case_br182
  ]
case_br182:
  %fp875 = getelementptr i8, ptr %ld871, i64 16
  %fv876 = load ptr, ptr %fp875, align 8
  %$f1052.addr = alloca ptr
  store ptr %fv876, ptr %$f1052.addr
  %fp877 = getelementptr i8, ptr %ld871, i64 24
  %fv878 = load ptr, ptr %fp877, align 8
  %$f1053.addr = alloca ptr
  store ptr %fv878, ptr %$f1053.addr
  %fp879 = getelementptr i8, ptr %ld871, i64 32
  %fv880 = load ptr, ptr %fp879, align 8
  %$f1054.addr = alloca ptr
  store ptr %fv880, ptr %$f1054.addr
  %fp881 = getelementptr i8, ptr %ld871, i64 40
  %fv882 = load i64, ptr %fp881, align 8
  %$f1055.addr = alloca i64
  store i64 %fv882, ptr %$f1055.addr
  %fp883 = getelementptr i8, ptr %ld871, i64 48
  %fv884 = load i64, ptr %fp883, align 8
  %$f1056.addr = alloca i64
  store i64 %fv884, ptr %$f1056.addr
  %fp885 = getelementptr i8, ptr %ld871, i64 56
  %fv886 = load i64, ptr %fp885, align 8
  %$f1057.addr = alloca i64
  store i64 %fv886, ptr %$f1057.addr
  %freed887 = call i64 @march_decrc_freed(ptr %ld871)
  %freed_b888 = icmp ne i64 %freed887, 0
  br i1 %freed_b888, label %br_unique183, label %br_shared184
br_shared184:
  call void @march_incrc(ptr %fv880)
  call void @march_incrc(ptr %fv878)
  call void @march_incrc(ptr %fv876)
  br label %br_body185
br_unique183:
  br label %br_body185
br_body185:
  %ld889 = load i64, ptr %$f1056.addr
  %max_retries.addr = alloca i64
  store i64 %ld889, ptr %max_retries.addr
  %ld890 = load i64, ptr %$f1055.addr
  %max_redir.addr = alloca i64
  store i64 %ld890, ptr %max_redir.addr
  %ld891 = load ptr, ptr %$f1054.addr
  %err_steps.addr = alloca ptr
  store ptr %ld891, ptr %err_steps.addr
  %ld892 = load ptr, ptr %$f1053.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld892, ptr %resp_steps.addr
  %ld893 = load ptr, ptr %$f1052.addr
  %req_steps.addr = alloca ptr
  store ptr %ld893, ptr %req_steps.addr
  %ld894 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld894)
  %ld895 = load ptr, ptr %req_steps.addr
  %ld896 = load ptr, ptr %req.addr
  %cr897 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld895, ptr %ld896)
  %$t1037.addr = alloca ptr
  store ptr %cr897, ptr %$t1037.addr
  %ld898 = load ptr, ptr %$t1037.addr
  %res_slot899 = alloca ptr
  %tgp900 = getelementptr i8, ptr %ld898, i64 8
  %tag901 = load i32, ptr %tgp900, align 4
  switch i32 %tag901, label %case_default187 [
      i32 1, label %case_br188
      i32 0, label %case_br189
  ]
case_br188:
  %fp902 = getelementptr i8, ptr %ld898, i64 16
  %fv903 = load ptr, ptr %fp902, align 8
  %$f1050.addr = alloca ptr
  store ptr %fv903, ptr %$f1050.addr
  %freed904 = call i64 @march_decrc_freed(ptr %ld898)
  %freed_b905 = icmp ne i64 %freed904, 0
  br i1 %freed_b905, label %br_unique190, label %br_shared191
br_shared191:
  call void @march_incrc(ptr %fv903)
  br label %br_body192
br_unique190:
  br label %br_body192
br_body192:
  %ld906 = load ptr, ptr %$f1050.addr
  %e.addr = alloca ptr
  store ptr %ld906, ptr %e.addr
  %ld907 = load ptr, ptr %err_steps.addr
  %ld908 = load ptr, ptr %req.addr
  %ld909 = load ptr, ptr %e.addr
  %cr910 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld907, ptr %ld908, ptr %ld909)
  store ptr %cr910, ptr %res_slot899
  br label %case_merge186
case_br189:
  %fp911 = getelementptr i8, ptr %ld898, i64 16
  %fv912 = load ptr, ptr %fp911, align 8
  %$f1051.addr = alloca ptr
  store ptr %fv912, ptr %$f1051.addr
  %freed913 = call i64 @march_decrc_freed(ptr %ld898)
  %freed_b914 = icmp ne i64 %freed913, 0
  br i1 %freed_b914, label %br_unique193, label %br_shared194
br_shared194:
  call void @march_incrc(ptr %fv912)
  br label %br_body195
br_unique193:
  br label %br_body195
br_body195:
  %ld915 = load ptr, ptr %$f1051.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld915, ptr %transformed_req.addr
  %ld916 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld916)
  %ld917 = load ptr, ptr %transformed_req.addr
  %ld918 = load i64, ptr %max_retries.addr
  %cr919 = call ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %ld917, i64 %ld918)
  %$t1038.addr = alloca ptr
  store ptr %cr919, ptr %$t1038.addr
  %ld920 = load ptr, ptr %$t1038.addr
  %res_slot921 = alloca ptr
  %tgp922 = getelementptr i8, ptr %ld920, i64 8
  %tag923 = load i32, ptr %tgp922, align 4
  switch i32 %tag923, label %case_default197 [
      i32 1, label %case_br198
      i32 0, label %case_br199
  ]
case_br198:
  %fp924 = getelementptr i8, ptr %ld920, i64 16
  %fv925 = load ptr, ptr %fp924, align 8
  %$f1048.addr = alloca ptr
  store ptr %fv925, ptr %$f1048.addr
  %freed926 = call i64 @march_decrc_freed(ptr %ld920)
  %freed_b927 = icmp ne i64 %freed926, 0
  br i1 %freed_b927, label %br_unique200, label %br_shared201
br_shared201:
  call void @march_incrc(ptr %fv925)
  br label %br_body202
br_unique200:
  br label %br_body202
br_body202:
  %ld928 = load ptr, ptr %$f1048.addr
  %transport_err.addr = alloca ptr
  store ptr %ld928, ptr %transport_err.addr
  %hp929 = call ptr @march_alloc(i64 24)
  %tgp930 = getelementptr i8, ptr %hp929, i64 8
  store i32 0, ptr %tgp930, align 4
  %ld931 = load ptr, ptr %transport_err.addr
  %fp932 = getelementptr i8, ptr %hp929, i64 16
  store ptr %ld931, ptr %fp932, align 8
  %$t1039.addr = alloca ptr
  store ptr %hp929, ptr %$t1039.addr
  %ld933 = load ptr, ptr %err_steps.addr
  %ld934 = load ptr, ptr %transformed_req.addr
  %ld935 = load ptr, ptr %$t1039.addr
  %cr936 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld933, ptr %ld934, ptr %ld935)
  store ptr %cr936, ptr %res_slot921
  br label %case_merge196
case_br199:
  %fp937 = getelementptr i8, ptr %ld920, i64 16
  %fv938 = load ptr, ptr %fp937, align 8
  %$f1049.addr = alloca ptr
  store ptr %fv938, ptr %$f1049.addr
  %freed939 = call i64 @march_decrc_freed(ptr %ld920)
  %freed_b940 = icmp ne i64 %freed939, 0
  br i1 %freed_b940, label %br_unique203, label %br_shared204
br_shared204:
  call void @march_incrc(ptr %fv938)
  br label %br_body205
br_unique203:
  br label %br_body205
br_body205:
  %ld941 = load ptr, ptr %$f1049.addr
  %resp.addr = alloca ptr
  store ptr %ld941, ptr %resp.addr
  %ld942 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld942)
  %ld943 = load ptr, ptr %transformed_req.addr
  %ld944 = load ptr, ptr %resp.addr
  %ld945 = load i64, ptr %max_redir.addr
  %cr946 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3337$Int$Int(ptr %ld943, ptr %ld944, i64 %ld945, i64 0)
  %$t1040.addr = alloca ptr
  store ptr %cr946, ptr %$t1040.addr
  %ld947 = load ptr, ptr %$t1040.addr
  %res_slot948 = alloca ptr
  %tgp949 = getelementptr i8, ptr %ld947, i64 8
  %tag950 = load i32, ptr %tgp949, align 4
  switch i32 %tag950, label %case_default207 [
      i32 1, label %case_br208
      i32 0, label %case_br209
  ]
case_br208:
  %fp951 = getelementptr i8, ptr %ld947, i64 16
  %fv952 = load ptr, ptr %fp951, align 8
  %$f1046.addr = alloca ptr
  store ptr %fv952, ptr %$f1046.addr
  %freed953 = call i64 @march_decrc_freed(ptr %ld947)
  %freed_b954 = icmp ne i64 %freed953, 0
  br i1 %freed_b954, label %br_unique210, label %br_shared211
br_shared211:
  call void @march_incrc(ptr %fv952)
  br label %br_body212
br_unique210:
  br label %br_body212
br_body212:
  %ld955 = load ptr, ptr %$f1046.addr
  %e_1.addr = alloca ptr
  store ptr %ld955, ptr %e_1.addr
  %ld956 = load ptr, ptr %err_steps.addr
  %ld957 = load ptr, ptr %transformed_req.addr
  %ld958 = load ptr, ptr %e_1.addr
  %cr959 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld956, ptr %ld957, ptr %ld958)
  store ptr %cr959, ptr %res_slot948
  br label %case_merge206
case_br209:
  %fp960 = getelementptr i8, ptr %ld947, i64 16
  %fv961 = load ptr, ptr %fp960, align 8
  %$f1047.addr = alloca ptr
  store ptr %fv961, ptr %$f1047.addr
  %freed962 = call i64 @march_decrc_freed(ptr %ld947)
  %freed_b963 = icmp ne i64 %freed962, 0
  br i1 %freed_b963, label %br_unique213, label %br_shared214
br_shared214:
  call void @march_incrc(ptr %fv961)
  br label %br_body215
br_unique213:
  br label %br_body215
br_body215:
  %ld964 = load ptr, ptr %$f1047.addr
  %final_resp.addr = alloca ptr
  store ptr %ld964, ptr %final_resp.addr
  %ld965 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld965)
  %ld966 = load ptr, ptr %resp_steps.addr
  %ld967 = load ptr, ptr %transformed_req.addr
  %ld968 = load ptr, ptr %final_resp.addr
  %cr969 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3337(ptr %ld966, ptr %ld967, ptr %ld968)
  %$t1041.addr = alloca ptr
  store ptr %cr969, ptr %$t1041.addr
  %ld970 = load ptr, ptr %$t1041.addr
  %res_slot971 = alloca ptr
  %tgp972 = getelementptr i8, ptr %ld970, i64 8
  %tag973 = load i32, ptr %tgp972, align 4
  switch i32 %tag973, label %case_default217 [
      i32 1, label %case_br218
      i32 0, label %case_br219
  ]
case_br218:
  %fp974 = getelementptr i8, ptr %ld970, i64 16
  %fv975 = load ptr, ptr %fp974, align 8
  %$f1042.addr = alloca ptr
  store ptr %fv975, ptr %$f1042.addr
  %freed976 = call i64 @march_decrc_freed(ptr %ld970)
  %freed_b977 = icmp ne i64 %freed976, 0
  br i1 %freed_b977, label %br_unique220, label %br_shared221
br_shared221:
  call void @march_incrc(ptr %fv975)
  br label %br_body222
br_unique220:
  br label %br_body222
br_body222:
  %ld978 = load ptr, ptr %$f1042.addr
  %e_2.addr = alloca ptr
  store ptr %ld978, ptr %e_2.addr
  %ld979 = load ptr, ptr %err_steps.addr
  %ld980 = load ptr, ptr %transformed_req.addr
  %ld981 = load ptr, ptr %e_2.addr
  %cr982 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld979, ptr %ld980, ptr %ld981)
  store ptr %cr982, ptr %res_slot971
  br label %case_merge216
case_br219:
  %fp983 = getelementptr i8, ptr %ld970, i64 16
  %fv984 = load ptr, ptr %fp983, align 8
  %$f1043.addr = alloca ptr
  store ptr %fv984, ptr %$f1043.addr
  %freed985 = call i64 @march_decrc_freed(ptr %ld970)
  %freed_b986 = icmp ne i64 %freed985, 0
  br i1 %freed_b986, label %br_unique223, label %br_shared224
br_shared224:
  call void @march_incrc(ptr %fv984)
  br label %br_body225
br_unique223:
  br label %br_body225
br_body225:
  %ld987 = load ptr, ptr %$f1043.addr
  %res_slot988 = alloca ptr
  %tgp989 = getelementptr i8, ptr %ld987, i64 8
  %tag990 = load i32, ptr %tgp989, align 4
  switch i32 %tag990, label %case_default227 [
      i32 0, label %case_br228
  ]
case_br228:
  %fp991 = getelementptr i8, ptr %ld987, i64 16
  %fv992 = load ptr, ptr %fp991, align 8
  %$f1044.addr = alloca ptr
  store ptr %fv992, ptr %$f1044.addr
  %fp993 = getelementptr i8, ptr %ld987, i64 24
  %fv994 = load ptr, ptr %fp993, align 8
  %$f1045.addr = alloca ptr
  store ptr %fv994, ptr %$f1045.addr
  %freed995 = call i64 @march_decrc_freed(ptr %ld987)
  %freed_b996 = icmp ne i64 %freed995, 0
  br i1 %freed_b996, label %br_unique229, label %br_shared230
br_shared230:
  call void @march_incrc(ptr %fv994)
  call void @march_incrc(ptr %fv992)
  br label %br_body231
br_unique229:
  br label %br_body231
br_body231:
  %ld997 = load ptr, ptr %$f1045.addr
  %response.addr = alloca ptr
  store ptr %ld997, ptr %response.addr
  %hp998 = call ptr @march_alloc(i64 24)
  %tgp999 = getelementptr i8, ptr %hp998, i64 8
  store i32 0, ptr %tgp999, align 4
  %ld1000 = load ptr, ptr %response.addr
  %fp1001 = getelementptr i8, ptr %hp998, i64 16
  store ptr %ld1000, ptr %fp1001, align 8
  store ptr %hp998, ptr %res_slot988
  br label %case_merge226
case_default227:
  unreachable
case_merge226:
  %case_r1002 = load ptr, ptr %res_slot988
  store ptr %case_r1002, ptr %res_slot971
  br label %case_merge216
case_default217:
  unreachable
case_merge216:
  %case_r1003 = load ptr, ptr %res_slot971
  store ptr %case_r1003, ptr %res_slot948
  br label %case_merge206
case_default207:
  unreachable
case_merge206:
  %case_r1004 = load ptr, ptr %res_slot948
  store ptr %case_r1004, ptr %res_slot921
  br label %case_merge196
case_default197:
  unreachable
case_merge196:
  %case_r1005 = load ptr, ptr %res_slot921
  store ptr %case_r1005, ptr %res_slot899
  br label %case_merge186
case_default187:
  unreachable
case_merge186:
  %case_r1006 = load ptr, ptr %res_slot899
  store ptr %case_r1006, ptr %res_slot872
  br label %case_merge180
case_default181:
  unreachable
case_merge180:
  %case_r1007 = load ptr, ptr %res_slot872
  ret ptr %case_r1007
}

define ptr @HttpClient.run_on_fd$V__3282$List_RequestStepEntry$List_ResponseStepEntry$List_ErrorStepEntry$Int$Int$Request_String(ptr %fd.arg, ptr %req_steps.arg, ptr %resp_steps.arg, ptr %err_steps.arg, i64 %max_redir.arg, i64 %max_retries.arg, ptr %req.arg) {
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
  %ld1008 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1008)
  %ld1009 = load ptr, ptr %req_steps.addr
  %ld1010 = load ptr, ptr %req.addr
  %cr1011 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld1009, ptr %ld1010)
  %$t1019.addr = alloca ptr
  store ptr %cr1011, ptr %$t1019.addr
  %ld1012 = load ptr, ptr %$t1019.addr
  %res_slot1013 = alloca ptr
  %tgp1014 = getelementptr i8, ptr %ld1012, i64 8
  %tag1015 = load i32, ptr %tgp1014, align 4
  switch i32 %tag1015, label %case_default233 [
      i32 1, label %case_br234
      i32 0, label %case_br235
  ]
case_br234:
  %fp1016 = getelementptr i8, ptr %ld1012, i64 16
  %fv1017 = load ptr, ptr %fp1016, align 8
  %$f1035.addr = alloca ptr
  store ptr %fv1017, ptr %$f1035.addr
  %freed1018 = call i64 @march_decrc_freed(ptr %ld1012)
  %freed_b1019 = icmp ne i64 %freed1018, 0
  br i1 %freed_b1019, label %br_unique236, label %br_shared237
br_shared237:
  call void @march_incrc(ptr %fv1017)
  br label %br_body238
br_unique236:
  br label %br_body238
br_body238:
  %ld1020 = load ptr, ptr %$f1035.addr
  %e.addr = alloca ptr
  store ptr %ld1020, ptr %e.addr
  %ld1021 = load ptr, ptr %err_steps.addr
  %ld1022 = load ptr, ptr %req.addr
  %ld1023 = load ptr, ptr %e.addr
  %cr1024 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1021, ptr %ld1022, ptr %ld1023)
  store ptr %cr1024, ptr %res_slot1013
  br label %case_merge232
case_br235:
  %fp1025 = getelementptr i8, ptr %ld1012, i64 16
  %fv1026 = load ptr, ptr %fp1025, align 8
  %$f1036.addr = alloca ptr
  store ptr %fv1026, ptr %$f1036.addr
  %freed1027 = call i64 @march_decrc_freed(ptr %ld1012)
  %freed_b1028 = icmp ne i64 %freed1027, 0
  br i1 %freed_b1028, label %br_unique239, label %br_shared240
br_shared240:
  call void @march_incrc(ptr %fv1026)
  br label %br_body241
br_unique239:
  br label %br_body241
br_body241:
  %ld1029 = load ptr, ptr %$f1036.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld1029, ptr %transformed_req.addr
  %ld1030 = load i64, ptr %max_retries.addr
  %ar1031 = add i64 %ld1030, 1
  %$t1020.addr = alloca i64
  store i64 %ar1031, ptr %$t1020.addr
  %ld1032 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld1032)
  %ld1033 = load ptr, ptr %fd.addr
  %ld1034 = load ptr, ptr %transformed_req.addr
  %ld1035 = load i64, ptr %$t1020.addr
  %cr1036 = call ptr @HttpClient.transport_keepalive$V__3282$Request_String$Int(ptr %ld1033, ptr %ld1034, i64 %ld1035)
  %$t1021.addr = alloca ptr
  store ptr %cr1036, ptr %$t1021.addr
  %ld1037 = load ptr, ptr %$t1021.addr
  %res_slot1038 = alloca ptr
  %tgp1039 = getelementptr i8, ptr %ld1037, i64 8
  %tag1040 = load i32, ptr %tgp1039, align 4
  switch i32 %tag1040, label %case_default243 [
      i32 1, label %case_br244
      i32 0, label %case_br245
  ]
case_br244:
  %fp1041 = getelementptr i8, ptr %ld1037, i64 16
  %fv1042 = load ptr, ptr %fp1041, align 8
  %$f1031.addr = alloca ptr
  store ptr %fv1042, ptr %$f1031.addr
  %freed1043 = call i64 @march_decrc_freed(ptr %ld1037)
  %freed_b1044 = icmp ne i64 %freed1043, 0
  br i1 %freed_b1044, label %br_unique246, label %br_shared247
br_shared247:
  call void @march_incrc(ptr %fv1042)
  br label %br_body248
br_unique246:
  br label %br_body248
br_body248:
  %ld1045 = load ptr, ptr %$f1031.addr
  %transport_err.addr = alloca ptr
  store ptr %ld1045, ptr %transport_err.addr
  %hp1046 = call ptr @march_alloc(i64 24)
  %tgp1047 = getelementptr i8, ptr %hp1046, i64 8
  store i32 0, ptr %tgp1047, align 4
  %ld1048 = load ptr, ptr %transport_err.addr
  %fp1049 = getelementptr i8, ptr %hp1046, i64 16
  store ptr %ld1048, ptr %fp1049, align 8
  %$t1022.addr = alloca ptr
  store ptr %hp1046, ptr %$t1022.addr
  %ld1050 = load ptr, ptr %err_steps.addr
  %ld1051 = load ptr, ptr %transformed_req.addr
  %ld1052 = load ptr, ptr %$t1022.addr
  %cr1053 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1050, ptr %ld1051, ptr %ld1052)
  store ptr %cr1053, ptr %res_slot1038
  br label %case_merge242
case_br245:
  %fp1054 = getelementptr i8, ptr %ld1037, i64 16
  %fv1055 = load ptr, ptr %fp1054, align 8
  %$f1032.addr = alloca ptr
  store ptr %fv1055, ptr %$f1032.addr
  %freed1056 = call i64 @march_decrc_freed(ptr %ld1037)
  %freed_b1057 = icmp ne i64 %freed1056, 0
  br i1 %freed_b1057, label %br_unique249, label %br_shared250
br_shared250:
  call void @march_incrc(ptr %fv1055)
  br label %br_body251
br_unique249:
  br label %br_body251
br_body251:
  %ld1058 = load ptr, ptr %$f1032.addr
  %res_slot1059 = alloca ptr
  %tgp1060 = getelementptr i8, ptr %ld1058, i64 8
  %tag1061 = load i32, ptr %tgp1060, align 4
  switch i32 %tag1061, label %case_default253 [
      i32 0, label %case_br254
  ]
case_br254:
  %fp1062 = getelementptr i8, ptr %ld1058, i64 16
  %fv1063 = load ptr, ptr %fp1062, align 8
  %$f1033.addr = alloca ptr
  store ptr %fv1063, ptr %$f1033.addr
  %fp1064 = getelementptr i8, ptr %ld1058, i64 24
  %fv1065 = load ptr, ptr %fp1064, align 8
  %$f1034.addr = alloca ptr
  store ptr %fv1065, ptr %$f1034.addr
  %freed1066 = call i64 @march_decrc_freed(ptr %ld1058)
  %freed_b1067 = icmp ne i64 %freed1066, 0
  br i1 %freed_b1067, label %br_unique255, label %br_shared256
br_shared256:
  call void @march_incrc(ptr %fv1065)
  call void @march_incrc(ptr %fv1063)
  br label %br_body257
br_unique255:
  br label %br_body257
br_body257:
  %ld1068 = load ptr, ptr %$f1034.addr
  %resp.addr = alloca ptr
  store ptr %ld1068, ptr %resp.addr
  %ld1069 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld1069)
  %ld1070 = load ptr, ptr %transformed_req.addr
  %ld1071 = load ptr, ptr %resp.addr
  %ld1072 = load i64, ptr %max_redir.addr
  %cr1073 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3284$Int$Int(ptr %ld1070, ptr %ld1071, i64 %ld1072, i64 0)
  %$t1023.addr = alloca ptr
  store ptr %cr1073, ptr %$t1023.addr
  %ld1074 = load ptr, ptr %$t1023.addr
  %res_slot1075 = alloca ptr
  %tgp1076 = getelementptr i8, ptr %ld1074, i64 8
  %tag1077 = load i32, ptr %tgp1076, align 4
  switch i32 %tag1077, label %case_default259 [
      i32 1, label %case_br260
      i32 0, label %case_br261
  ]
case_br260:
  %fp1078 = getelementptr i8, ptr %ld1074, i64 16
  %fv1079 = load ptr, ptr %fp1078, align 8
  %$f1029.addr = alloca ptr
  store ptr %fv1079, ptr %$f1029.addr
  %freed1080 = call i64 @march_decrc_freed(ptr %ld1074)
  %freed_b1081 = icmp ne i64 %freed1080, 0
  br i1 %freed_b1081, label %br_unique262, label %br_shared263
br_shared263:
  call void @march_incrc(ptr %fv1079)
  br label %br_body264
br_unique262:
  br label %br_body264
br_body264:
  %ld1082 = load ptr, ptr %$f1029.addr
  %e_1.addr = alloca ptr
  store ptr %ld1082, ptr %e_1.addr
  %ld1083 = load ptr, ptr %err_steps.addr
  %ld1084 = load ptr, ptr %transformed_req.addr
  %ld1085 = load ptr, ptr %e_1.addr
  %cr1086 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1083, ptr %ld1084, ptr %ld1085)
  store ptr %cr1086, ptr %res_slot1075
  br label %case_merge258
case_br261:
  %fp1087 = getelementptr i8, ptr %ld1074, i64 16
  %fv1088 = load ptr, ptr %fp1087, align 8
  %$f1030.addr = alloca ptr
  store ptr %fv1088, ptr %$f1030.addr
  %freed1089 = call i64 @march_decrc_freed(ptr %ld1074)
  %freed_b1090 = icmp ne i64 %freed1089, 0
  br i1 %freed_b1090, label %br_unique265, label %br_shared266
br_shared266:
  call void @march_incrc(ptr %fv1088)
  br label %br_body267
br_unique265:
  br label %br_body267
br_body267:
  %ld1091 = load ptr, ptr %$f1030.addr
  %final_resp.addr = alloca ptr
  store ptr %ld1091, ptr %final_resp.addr
  %ld1092 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld1092)
  %ld1093 = load ptr, ptr %resp_steps.addr
  %ld1094 = load ptr, ptr %transformed_req.addr
  %ld1095 = load ptr, ptr %final_resp.addr
  %cr1096 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3284(ptr %ld1093, ptr %ld1094, ptr %ld1095)
  %$t1024.addr = alloca ptr
  store ptr %cr1096, ptr %$t1024.addr
  %ld1097 = load ptr, ptr %$t1024.addr
  %res_slot1098 = alloca ptr
  %tgp1099 = getelementptr i8, ptr %ld1097, i64 8
  %tag1100 = load i32, ptr %tgp1099, align 4
  switch i32 %tag1100, label %case_default269 [
      i32 1, label %case_br270
      i32 0, label %case_br271
  ]
case_br270:
  %fp1101 = getelementptr i8, ptr %ld1097, i64 16
  %fv1102 = load ptr, ptr %fp1101, align 8
  %$f1025.addr = alloca ptr
  store ptr %fv1102, ptr %$f1025.addr
  %freed1103 = call i64 @march_decrc_freed(ptr %ld1097)
  %freed_b1104 = icmp ne i64 %freed1103, 0
  br i1 %freed_b1104, label %br_unique272, label %br_shared273
br_shared273:
  call void @march_incrc(ptr %fv1102)
  br label %br_body274
br_unique272:
  br label %br_body274
br_body274:
  %ld1105 = load ptr, ptr %$f1025.addr
  %e_2.addr = alloca ptr
  store ptr %ld1105, ptr %e_2.addr
  %ld1106 = load ptr, ptr %err_steps.addr
  %ld1107 = load ptr, ptr %transformed_req.addr
  %ld1108 = load ptr, ptr %e_2.addr
  %cr1109 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1106, ptr %ld1107, ptr %ld1108)
  store ptr %cr1109, ptr %res_slot1098
  br label %case_merge268
case_br271:
  %fp1110 = getelementptr i8, ptr %ld1097, i64 16
  %fv1111 = load ptr, ptr %fp1110, align 8
  %$f1026.addr = alloca ptr
  store ptr %fv1111, ptr %$f1026.addr
  %freed1112 = call i64 @march_decrc_freed(ptr %ld1097)
  %freed_b1113 = icmp ne i64 %freed1112, 0
  br i1 %freed_b1113, label %br_unique275, label %br_shared276
br_shared276:
  call void @march_incrc(ptr %fv1111)
  br label %br_body277
br_unique275:
  br label %br_body277
br_body277:
  %ld1114 = load ptr, ptr %$f1026.addr
  %res_slot1115 = alloca ptr
  %tgp1116 = getelementptr i8, ptr %ld1114, i64 8
  %tag1117 = load i32, ptr %tgp1116, align 4
  switch i32 %tag1117, label %case_default279 [
      i32 0, label %case_br280
  ]
case_br280:
  %fp1118 = getelementptr i8, ptr %ld1114, i64 16
  %fv1119 = load ptr, ptr %fp1118, align 8
  %$f1027.addr = alloca ptr
  store ptr %fv1119, ptr %$f1027.addr
  %fp1120 = getelementptr i8, ptr %ld1114, i64 24
  %fv1121 = load ptr, ptr %fp1120, align 8
  %$f1028.addr = alloca ptr
  store ptr %fv1121, ptr %$f1028.addr
  %freed1122 = call i64 @march_decrc_freed(ptr %ld1114)
  %freed_b1123 = icmp ne i64 %freed1122, 0
  br i1 %freed_b1123, label %br_unique281, label %br_shared282
br_shared282:
  call void @march_incrc(ptr %fv1121)
  call void @march_incrc(ptr %fv1119)
  br label %br_body283
br_unique281:
  br label %br_body283
br_body283:
  %ld1124 = load ptr, ptr %$f1028.addr
  %response.addr = alloca ptr
  store ptr %ld1124, ptr %response.addr
  %hp1125 = call ptr @march_alloc(i64 24)
  %tgp1126 = getelementptr i8, ptr %hp1125, i64 8
  store i32 0, ptr %tgp1126, align 4
  %ld1127 = load ptr, ptr %response.addr
  %fp1128 = getelementptr i8, ptr %hp1125, i64 16
  store ptr %ld1127, ptr %fp1128, align 8
  store ptr %hp1125, ptr %res_slot1115
  br label %case_merge278
case_default279:
  unreachable
case_merge278:
  %case_r1129 = load ptr, ptr %res_slot1115
  store ptr %case_r1129, ptr %res_slot1098
  br label %case_merge268
case_default269:
  unreachable
case_merge268:
  %case_r1130 = load ptr, ptr %res_slot1098
  store ptr %case_r1130, ptr %res_slot1075
  br label %case_merge258
case_default259:
  unreachable
case_merge258:
  %case_r1131 = load ptr, ptr %res_slot1075
  store ptr %case_r1131, ptr %res_slot1059
  br label %case_merge252
case_default253:
  unreachable
case_merge252:
  %case_r1132 = load ptr, ptr %res_slot1059
  store ptr %case_r1132, ptr %res_slot1038
  br label %case_merge242
case_default243:
  unreachable
case_merge242:
  %case_r1133 = load ptr, ptr %res_slot1038
  store ptr %case_r1133, ptr %res_slot1013
  br label %case_merge232
case_default233:
  unreachable
case_merge232:
  %case_r1134 = load ptr, ptr %res_slot1013
  ret ptr %case_r1134
}

define ptr @HttpTransport.connect$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1135 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1135)
  %ld1136 = load ptr, ptr %req.addr
  %cr1137 = call ptr @Http.host$Request_T_(ptr %ld1136)
  %req_host.addr = alloca ptr
  store ptr %cr1137, ptr %req_host.addr
  %ld1138 = load ptr, ptr %req.addr
  %cr1139 = call ptr @Http.port$Request_T_(ptr %ld1138)
  %$t777.addr = alloca ptr
  store ptr %cr1139, ptr %$t777.addr
  %ld1140 = load ptr, ptr %$t777.addr
  %res_slot1141 = alloca ptr
  %tgp1142 = getelementptr i8, ptr %ld1140, i64 8
  %tag1143 = load i32, ptr %tgp1142, align 4
  switch i32 %tag1143, label %case_default285 [
      i32 1, label %case_br286
      i32 0, label %case_br287
  ]
case_br286:
  %fp1144 = getelementptr i8, ptr %ld1140, i64 16
  %fv1145 = load ptr, ptr %fp1144, align 8
  %$f778.addr = alloca ptr
  store ptr %fv1145, ptr %$f778.addr
  %ld1146 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld1146)
  %ld1147 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld1147, ptr %p.addr
  %ld1148 = load ptr, ptr %p.addr
  store ptr %ld1148, ptr %res_slot1141
  br label %case_merge284
case_br287:
  %ld1149 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld1149)
  %cv1150 = inttoptr i64 80 to ptr
  store ptr %cv1150, ptr %res_slot1141
  br label %case_merge284
case_default285:
  unreachable
case_merge284:
  %case_r1151 = load ptr, ptr %res_slot1141
  %cv1152 = ptrtoint ptr %case_r1151 to i64
  %req_port.addr = alloca i64
  store i64 %cv1152, ptr %req_port.addr
  %ld1153 = load ptr, ptr %tcp_connect.addr
  %fp1154 = getelementptr i8, ptr %ld1153, i64 16
  %fv1155 = load ptr, ptr %fp1154, align 8
  %ld1156 = load ptr, ptr %req_host.addr
  %ld1157 = load i64, ptr %req_port.addr
  %cv1158 = inttoptr i64 %ld1157 to ptr
  %cr1159 = call ptr (ptr, ptr, ptr) %fv1155(ptr %ld1153, ptr %ld1156, ptr %cv1158)
  %$t779.addr = alloca ptr
  store ptr %cr1159, ptr %$t779.addr
  %ld1160 = load ptr, ptr %$t779.addr
  %res_slot1161 = alloca ptr
  %tgp1162 = getelementptr i8, ptr %ld1160, i64 8
  %tag1163 = load i32, ptr %tgp1162, align 4
  switch i32 %tag1163, label %case_default289 [
      i32 0, label %case_br290
      i32 0, label %case_br291
  ]
case_br290:
  %fp1164 = getelementptr i8, ptr %ld1160, i64 16
  %fv1165 = load ptr, ptr %fp1164, align 8
  %$f781.addr = alloca ptr
  store ptr %fv1165, ptr %$f781.addr
  %freed1166 = call i64 @march_decrc_freed(ptr %ld1160)
  %freed_b1167 = icmp ne i64 %freed1166, 0
  br i1 %freed_b1167, label %br_unique292, label %br_shared293
br_shared293:
  call void @march_incrc(ptr %fv1165)
  br label %br_body294
br_unique292:
  br label %br_body294
br_body294:
  %ld1168 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld1168, ptr %msg.addr
  %hp1169 = call ptr @march_alloc(i64 24)
  %tgp1170 = getelementptr i8, ptr %hp1169, i64 8
  store i32 0, ptr %tgp1170, align 4
  %ld1171 = load ptr, ptr %msg.addr
  %fp1172 = getelementptr i8, ptr %hp1169, i64 16
  store ptr %ld1171, ptr %fp1172, align 8
  %$t780.addr = alloca ptr
  store ptr %hp1169, ptr %$t780.addr
  %hp1173 = call ptr @march_alloc(i64 24)
  %tgp1174 = getelementptr i8, ptr %hp1173, i64 8
  store i32 1, ptr %tgp1174, align 4
  %ld1175 = load ptr, ptr %$t780.addr
  %fp1176 = getelementptr i8, ptr %hp1173, i64 16
  store ptr %ld1175, ptr %fp1176, align 8
  store ptr %hp1173, ptr %res_slot1161
  br label %case_merge288
case_br291:
  %fp1177 = getelementptr i8, ptr %ld1160, i64 16
  %fv1178 = load ptr, ptr %fp1177, align 8
  %$f782.addr = alloca ptr
  store ptr %fv1178, ptr %$f782.addr
  %freed1179 = call i64 @march_decrc_freed(ptr %ld1160)
  %freed_b1180 = icmp ne i64 %freed1179, 0
  br i1 %freed_b1180, label %br_unique295, label %br_shared296
br_shared296:
  call void @march_incrc(ptr %fv1178)
  br label %br_body297
br_unique295:
  br label %br_body297
br_body297:
  %ld1181 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld1181, ptr %fd.addr
  %hp1182 = call ptr @march_alloc(i64 24)
  %tgp1183 = getelementptr i8, ptr %hp1182, i64 8
  store i32 0, ptr %tgp1183, align 4
  %ld1184 = load ptr, ptr %fd.addr
  %fp1185 = getelementptr i8, ptr %hp1182, i64 16
  store ptr %ld1184, ptr %fp1185, align 8
  store ptr %hp1182, ptr %res_slot1161
  br label %case_merge288
case_default289:
  unreachable
case_merge288:
  %case_r1186 = load ptr, ptr %res_slot1161
  ret ptr %case_r1186
}

define ptr @Http.set_header$Request_V__3518$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1187 = load ptr, ptr %req.addr
  %res_slot1188 = alloca ptr
  %tgp1189 = getelementptr i8, ptr %ld1187, i64 8
  %tag1190 = load i32, ptr %tgp1189, align 4
  switch i32 %tag1190, label %case_default299 [
      i32 0, label %case_br300
  ]
case_br300:
  %fp1191 = getelementptr i8, ptr %ld1187, i64 16
  %fv1192 = load ptr, ptr %fp1191, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1192, ptr %$f658.addr
  %fp1193 = getelementptr i8, ptr %ld1187, i64 24
  %fv1194 = load ptr, ptr %fp1193, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1194, ptr %$f659.addr
  %fp1195 = getelementptr i8, ptr %ld1187, i64 32
  %fv1196 = load ptr, ptr %fp1195, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1196, ptr %$f660.addr
  %fp1197 = getelementptr i8, ptr %ld1187, i64 40
  %fv1198 = load ptr, ptr %fp1197, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1198, ptr %$f661.addr
  %fp1199 = getelementptr i8, ptr %ld1187, i64 48
  %fv1200 = load ptr, ptr %fp1199, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1200, ptr %$f662.addr
  %fp1201 = getelementptr i8, ptr %ld1187, i64 56
  %fv1202 = load ptr, ptr %fp1201, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1202, ptr %$f663.addr
  %fp1203 = getelementptr i8, ptr %ld1187, i64 64
  %fv1204 = load ptr, ptr %fp1203, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1204, ptr %$f664.addr
  %fp1205 = getelementptr i8, ptr %ld1187, i64 72
  %fv1206 = load ptr, ptr %fp1205, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1206, ptr %$f665.addr
  %ld1207 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1207, ptr %bd.addr
  %ld1208 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1208, ptr %hd.addr
  %ld1209 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1209, ptr %q.addr
  %ld1210 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1210, ptr %pa.addr
  %ld1211 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1211, ptr %p.addr
  %ld1212 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1212, ptr %h.addr
  %ld1213 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1213, ptr %sc.addr
  %ld1214 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1214, ptr %m.addr
  %hp1215 = call ptr @march_alloc(i64 32)
  %tgp1216 = getelementptr i8, ptr %hp1215, i64 8
  store i32 0, ptr %tgp1216, align 4
  %ld1217 = load ptr, ptr %name.addr
  %fp1218 = getelementptr i8, ptr %hp1215, i64 16
  store ptr %ld1217, ptr %fp1218, align 8
  %ld1219 = load ptr, ptr %value.addr
  %fp1220 = getelementptr i8, ptr %hp1215, i64 24
  store ptr %ld1219, ptr %fp1220, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1215, ptr %$t656.addr
  %hp1221 = call ptr @march_alloc(i64 32)
  %tgp1222 = getelementptr i8, ptr %hp1221, i64 8
  store i32 1, ptr %tgp1222, align 4
  %ld1223 = load ptr, ptr %$t656.addr
  %fp1224 = getelementptr i8, ptr %hp1221, i64 16
  store ptr %ld1223, ptr %fp1224, align 8
  %ld1225 = load ptr, ptr %hd.addr
  %fp1226 = getelementptr i8, ptr %hp1221, i64 24
  store ptr %ld1225, ptr %fp1226, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1221, ptr %$t657.addr
  %ld1227 = load ptr, ptr %req.addr
  %ld1228 = load ptr, ptr %m.addr
  %ld1229 = load ptr, ptr %sc.addr
  %ld1230 = load ptr, ptr %h.addr
  %ld1231 = load ptr, ptr %p.addr
  %ld1232 = load ptr, ptr %pa.addr
  %ld1233 = load ptr, ptr %q.addr
  %ld1234 = load ptr, ptr %$t657.addr
  %ld1235 = load ptr, ptr %bd.addr
  %rc1236 = load i64, ptr %ld1227, align 8
  %uniq1237 = icmp eq i64 %rc1236, 1
  %fbip_slot1238 = alloca ptr
  br i1 %uniq1237, label %fbip_reuse301, label %fbip_fresh302
fbip_reuse301:
  %tgp1239 = getelementptr i8, ptr %ld1227, i64 8
  store i32 0, ptr %tgp1239, align 4
  %fp1240 = getelementptr i8, ptr %ld1227, i64 16
  store ptr %ld1228, ptr %fp1240, align 8
  %fp1241 = getelementptr i8, ptr %ld1227, i64 24
  store ptr %ld1229, ptr %fp1241, align 8
  %fp1242 = getelementptr i8, ptr %ld1227, i64 32
  store ptr %ld1230, ptr %fp1242, align 8
  %fp1243 = getelementptr i8, ptr %ld1227, i64 40
  store ptr %ld1231, ptr %fp1243, align 8
  %fp1244 = getelementptr i8, ptr %ld1227, i64 48
  store ptr %ld1232, ptr %fp1244, align 8
  %fp1245 = getelementptr i8, ptr %ld1227, i64 56
  store ptr %ld1233, ptr %fp1245, align 8
  %fp1246 = getelementptr i8, ptr %ld1227, i64 64
  store ptr %ld1234, ptr %fp1246, align 8
  %fp1247 = getelementptr i8, ptr %ld1227, i64 72
  store ptr %ld1235, ptr %fp1247, align 8
  store ptr %ld1227, ptr %fbip_slot1238
  br label %fbip_merge303
fbip_fresh302:
  call void @march_decrc(ptr %ld1227)
  %hp1248 = call ptr @march_alloc(i64 80)
  %tgp1249 = getelementptr i8, ptr %hp1248, i64 8
  store i32 0, ptr %tgp1249, align 4
  %fp1250 = getelementptr i8, ptr %hp1248, i64 16
  store ptr %ld1228, ptr %fp1250, align 8
  %fp1251 = getelementptr i8, ptr %hp1248, i64 24
  store ptr %ld1229, ptr %fp1251, align 8
  %fp1252 = getelementptr i8, ptr %hp1248, i64 32
  store ptr %ld1230, ptr %fp1252, align 8
  %fp1253 = getelementptr i8, ptr %hp1248, i64 40
  store ptr %ld1231, ptr %fp1253, align 8
  %fp1254 = getelementptr i8, ptr %hp1248, i64 48
  store ptr %ld1232, ptr %fp1254, align 8
  %fp1255 = getelementptr i8, ptr %hp1248, i64 56
  store ptr %ld1233, ptr %fp1255, align 8
  %fp1256 = getelementptr i8, ptr %hp1248, i64 64
  store ptr %ld1234, ptr %fp1256, align 8
  %fp1257 = getelementptr i8, ptr %hp1248, i64 72
  store ptr %ld1235, ptr %fp1257, align 8
  store ptr %hp1248, ptr %fbip_slot1238
  br label %fbip_merge303
fbip_merge303:
  %fbip_r1258 = load ptr, ptr %fbip_slot1238
  store ptr %fbip_r1258, ptr %res_slot1188
  br label %case_merge298
case_default299:
  unreachable
case_merge298:
  %case_r1259 = load ptr, ptr %res_slot1188
  ret ptr %case_r1259
}

define ptr @Http.set_header$Request_V__3516$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1260 = load ptr, ptr %req.addr
  %res_slot1261 = alloca ptr
  %tgp1262 = getelementptr i8, ptr %ld1260, i64 8
  %tag1263 = load i32, ptr %tgp1262, align 4
  switch i32 %tag1263, label %case_default305 [
      i32 0, label %case_br306
  ]
case_br306:
  %fp1264 = getelementptr i8, ptr %ld1260, i64 16
  %fv1265 = load ptr, ptr %fp1264, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1265, ptr %$f658.addr
  %fp1266 = getelementptr i8, ptr %ld1260, i64 24
  %fv1267 = load ptr, ptr %fp1266, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1267, ptr %$f659.addr
  %fp1268 = getelementptr i8, ptr %ld1260, i64 32
  %fv1269 = load ptr, ptr %fp1268, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1269, ptr %$f660.addr
  %fp1270 = getelementptr i8, ptr %ld1260, i64 40
  %fv1271 = load ptr, ptr %fp1270, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1271, ptr %$f661.addr
  %fp1272 = getelementptr i8, ptr %ld1260, i64 48
  %fv1273 = load ptr, ptr %fp1272, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1273, ptr %$f662.addr
  %fp1274 = getelementptr i8, ptr %ld1260, i64 56
  %fv1275 = load ptr, ptr %fp1274, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1275, ptr %$f663.addr
  %fp1276 = getelementptr i8, ptr %ld1260, i64 64
  %fv1277 = load ptr, ptr %fp1276, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1277, ptr %$f664.addr
  %fp1278 = getelementptr i8, ptr %ld1260, i64 72
  %fv1279 = load ptr, ptr %fp1278, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1279, ptr %$f665.addr
  %ld1280 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1280, ptr %bd.addr
  %ld1281 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1281, ptr %hd.addr
  %ld1282 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1282, ptr %q.addr
  %ld1283 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1283, ptr %pa.addr
  %ld1284 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1284, ptr %p.addr
  %ld1285 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1285, ptr %h.addr
  %ld1286 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1286, ptr %sc.addr
  %ld1287 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1287, ptr %m.addr
  %hp1288 = call ptr @march_alloc(i64 32)
  %tgp1289 = getelementptr i8, ptr %hp1288, i64 8
  store i32 0, ptr %tgp1289, align 4
  %ld1290 = load ptr, ptr %name.addr
  %fp1291 = getelementptr i8, ptr %hp1288, i64 16
  store ptr %ld1290, ptr %fp1291, align 8
  %ld1292 = load ptr, ptr %value.addr
  %fp1293 = getelementptr i8, ptr %hp1288, i64 24
  store ptr %ld1292, ptr %fp1293, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1288, ptr %$t656.addr
  %hp1294 = call ptr @march_alloc(i64 32)
  %tgp1295 = getelementptr i8, ptr %hp1294, i64 8
  store i32 1, ptr %tgp1295, align 4
  %ld1296 = load ptr, ptr %$t656.addr
  %fp1297 = getelementptr i8, ptr %hp1294, i64 16
  store ptr %ld1296, ptr %fp1297, align 8
  %ld1298 = load ptr, ptr %hd.addr
  %fp1299 = getelementptr i8, ptr %hp1294, i64 24
  store ptr %ld1298, ptr %fp1299, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1294, ptr %$t657.addr
  %ld1300 = load ptr, ptr %req.addr
  %ld1301 = load ptr, ptr %m.addr
  %ld1302 = load ptr, ptr %sc.addr
  %ld1303 = load ptr, ptr %h.addr
  %ld1304 = load ptr, ptr %p.addr
  %ld1305 = load ptr, ptr %pa.addr
  %ld1306 = load ptr, ptr %q.addr
  %ld1307 = load ptr, ptr %$t657.addr
  %ld1308 = load ptr, ptr %bd.addr
  %rc1309 = load i64, ptr %ld1300, align 8
  %uniq1310 = icmp eq i64 %rc1309, 1
  %fbip_slot1311 = alloca ptr
  br i1 %uniq1310, label %fbip_reuse307, label %fbip_fresh308
fbip_reuse307:
  %tgp1312 = getelementptr i8, ptr %ld1300, i64 8
  store i32 0, ptr %tgp1312, align 4
  %fp1313 = getelementptr i8, ptr %ld1300, i64 16
  store ptr %ld1301, ptr %fp1313, align 8
  %fp1314 = getelementptr i8, ptr %ld1300, i64 24
  store ptr %ld1302, ptr %fp1314, align 8
  %fp1315 = getelementptr i8, ptr %ld1300, i64 32
  store ptr %ld1303, ptr %fp1315, align 8
  %fp1316 = getelementptr i8, ptr %ld1300, i64 40
  store ptr %ld1304, ptr %fp1316, align 8
  %fp1317 = getelementptr i8, ptr %ld1300, i64 48
  store ptr %ld1305, ptr %fp1317, align 8
  %fp1318 = getelementptr i8, ptr %ld1300, i64 56
  store ptr %ld1306, ptr %fp1318, align 8
  %fp1319 = getelementptr i8, ptr %ld1300, i64 64
  store ptr %ld1307, ptr %fp1319, align 8
  %fp1320 = getelementptr i8, ptr %ld1300, i64 72
  store ptr %ld1308, ptr %fp1320, align 8
  store ptr %ld1300, ptr %fbip_slot1311
  br label %fbip_merge309
fbip_fresh308:
  call void @march_decrc(ptr %ld1300)
  %hp1321 = call ptr @march_alloc(i64 80)
  %tgp1322 = getelementptr i8, ptr %hp1321, i64 8
  store i32 0, ptr %tgp1322, align 4
  %fp1323 = getelementptr i8, ptr %hp1321, i64 16
  store ptr %ld1301, ptr %fp1323, align 8
  %fp1324 = getelementptr i8, ptr %hp1321, i64 24
  store ptr %ld1302, ptr %fp1324, align 8
  %fp1325 = getelementptr i8, ptr %hp1321, i64 32
  store ptr %ld1303, ptr %fp1325, align 8
  %fp1326 = getelementptr i8, ptr %hp1321, i64 40
  store ptr %ld1304, ptr %fp1326, align 8
  %fp1327 = getelementptr i8, ptr %hp1321, i64 48
  store ptr %ld1305, ptr %fp1327, align 8
  %fp1328 = getelementptr i8, ptr %hp1321, i64 56
  store ptr %ld1306, ptr %fp1328, align 8
  %fp1329 = getelementptr i8, ptr %hp1321, i64 64
  store ptr %ld1307, ptr %fp1329, align 8
  %fp1330 = getelementptr i8, ptr %hp1321, i64 72
  store ptr %ld1308, ptr %fp1330, align 8
  store ptr %hp1321, ptr %fbip_slot1311
  br label %fbip_merge309
fbip_merge309:
  %fbip_r1331 = load ptr, ptr %fbip_slot1311
  store ptr %fbip_r1331, ptr %res_slot1261
  br label %case_merge304
case_default305:
  unreachable
case_merge304:
  %case_r1332 = load ptr, ptr %res_slot1261
  ret ptr %case_r1332
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld1333 = load ptr, ptr %xs.addr
  %res_slot1334 = alloca ptr
  %tgp1335 = getelementptr i8, ptr %ld1333, i64 8
  %tag1336 = load i32, ptr %tgp1335, align 4
  switch i32 %tag1336, label %case_default311 [
      i32 0, label %case_br312
      i32 1, label %case_br313
  ]
case_br312:
  %ld1337 = load ptr, ptr %xs.addr
  %rc1338 = load i64, ptr %ld1337, align 8
  %uniq1339 = icmp eq i64 %rc1338, 1
  %fbip_slot1340 = alloca ptr
  br i1 %uniq1339, label %fbip_reuse314, label %fbip_fresh315
fbip_reuse314:
  %tgp1341 = getelementptr i8, ptr %ld1337, i64 8
  store i32 0, ptr %tgp1341, align 4
  store ptr %ld1337, ptr %fbip_slot1340
  br label %fbip_merge316
fbip_fresh315:
  call void @march_decrc(ptr %ld1337)
  %hp1342 = call ptr @march_alloc(i64 16)
  %tgp1343 = getelementptr i8, ptr %hp1342, i64 8
  store i32 0, ptr %tgp1343, align 4
  store ptr %hp1342, ptr %fbip_slot1340
  br label %fbip_merge316
fbip_merge316:
  %fbip_r1344 = load ptr, ptr %fbip_slot1340
  %$t883.addr = alloca ptr
  store ptr %fbip_r1344, ptr %$t883.addr
  %hp1345 = call ptr @march_alloc(i64 32)
  %tgp1346 = getelementptr i8, ptr %hp1345, i64 8
  store i32 1, ptr %tgp1346, align 4
  %ld1347 = load ptr, ptr %x.addr
  %fp1348 = getelementptr i8, ptr %hp1345, i64 16
  store ptr %ld1347, ptr %fp1348, align 8
  %ld1349 = load ptr, ptr %$t883.addr
  %fp1350 = getelementptr i8, ptr %hp1345, i64 24
  store ptr %ld1349, ptr %fp1350, align 8
  store ptr %hp1345, ptr %res_slot1334
  br label %case_merge310
case_br313:
  %fp1351 = getelementptr i8, ptr %ld1333, i64 16
  %fv1352 = load ptr, ptr %fp1351, align 8
  %$f885.addr = alloca ptr
  store ptr %fv1352, ptr %$f885.addr
  %fp1353 = getelementptr i8, ptr %ld1333, i64 24
  %fv1354 = load ptr, ptr %fp1353, align 8
  %$f886.addr = alloca ptr
  store ptr %fv1354, ptr %$f886.addr
  %ld1355 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld1355, ptr %t.addr
  %ld1356 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld1356, ptr %h.addr
  %ld1357 = load ptr, ptr %t.addr
  %ld1358 = load ptr, ptr %x.addr
  %cr1359 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld1357, ptr %ld1358)
  %$t884.addr = alloca ptr
  store ptr %cr1359, ptr %$t884.addr
  %ld1360 = load ptr, ptr %xs.addr
  %ld1361 = load ptr, ptr %h.addr
  %ld1362 = load ptr, ptr %$t884.addr
  %rc1363 = load i64, ptr %ld1360, align 8
  %uniq1364 = icmp eq i64 %rc1363, 1
  %fbip_slot1365 = alloca ptr
  br i1 %uniq1364, label %fbip_reuse317, label %fbip_fresh318
fbip_reuse317:
  %tgp1366 = getelementptr i8, ptr %ld1360, i64 8
  store i32 1, ptr %tgp1366, align 4
  %fp1367 = getelementptr i8, ptr %ld1360, i64 16
  store ptr %ld1361, ptr %fp1367, align 8
  %fp1368 = getelementptr i8, ptr %ld1360, i64 24
  store ptr %ld1362, ptr %fp1368, align 8
  store ptr %ld1360, ptr %fbip_slot1365
  br label %fbip_merge319
fbip_fresh318:
  call void @march_decrc(ptr %ld1360)
  %hp1369 = call ptr @march_alloc(i64 32)
  %tgp1370 = getelementptr i8, ptr %hp1369, i64 8
  store i32 1, ptr %tgp1370, align 4
  %fp1371 = getelementptr i8, ptr %hp1369, i64 16
  store ptr %ld1361, ptr %fp1371, align 8
  %fp1372 = getelementptr i8, ptr %hp1369, i64 24
  store ptr %ld1362, ptr %fp1372, align 8
  store ptr %hp1369, ptr %fbip_slot1365
  br label %fbip_merge319
fbip_merge319:
  %fbip_r1373 = load ptr, ptr %fbip_slot1365
  store ptr %fbip_r1373, ptr %res_slot1334
  br label %case_merge310
case_default311:
  unreachable
case_merge310:
  %case_r1374 = load ptr, ptr %res_slot1334
  ret ptr %case_r1374
}

define ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %steps.arg, ptr %req.arg, ptr %err.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %err.addr = alloca ptr
  store ptr %err.arg, ptr %err.addr
  %ld1375 = load ptr, ptr %steps.addr
  %res_slot1376 = alloca ptr
  %tgp1377 = getelementptr i8, ptr %ld1375, i64 8
  %tag1378 = load i32, ptr %tgp1377, align 4
  switch i32 %tag1378, label %case_default321 [
      i32 0, label %case_br322
      i32 1, label %case_br323
  ]
case_br322:
  %ld1379 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1379)
  %hp1380 = call ptr @march_alloc(i64 24)
  %tgp1381 = getelementptr i8, ptr %hp1380, i64 8
  store i32 1, ptr %tgp1381, align 4
  %ld1382 = load ptr, ptr %err.addr
  %fp1383 = getelementptr i8, ptr %hp1380, i64 16
  store ptr %ld1382, ptr %fp1383, align 8
  store ptr %hp1380, ptr %res_slot1376
  br label %case_merge320
case_br323:
  %fp1384 = getelementptr i8, ptr %ld1375, i64 16
  %fv1385 = load ptr, ptr %fp1384, align 8
  %$f974.addr = alloca ptr
  store ptr %fv1385, ptr %$f974.addr
  %fp1386 = getelementptr i8, ptr %ld1375, i64 24
  %fv1387 = load ptr, ptr %fp1386, align 8
  %$f975.addr = alloca ptr
  store ptr %fv1387, ptr %$f975.addr
  %freed1388 = call i64 @march_decrc_freed(ptr %ld1375)
  %freed_b1389 = icmp ne i64 %freed1388, 0
  br i1 %freed_b1389, label %br_unique324, label %br_shared325
br_shared325:
  call void @march_incrc(ptr %fv1387)
  call void @march_incrc(ptr %fv1385)
  br label %br_body326
br_unique324:
  br label %br_body326
br_body326:
  %ld1390 = load ptr, ptr %$f974.addr
  %res_slot1391 = alloca ptr
  %tgp1392 = getelementptr i8, ptr %ld1390, i64 8
  %tag1393 = load i32, ptr %tgp1392, align 4
  switch i32 %tag1393, label %case_default328 [
      i32 0, label %case_br329
  ]
case_br329:
  %fp1394 = getelementptr i8, ptr %ld1390, i64 16
  %fv1395 = load ptr, ptr %fp1394, align 8
  %$f976.addr = alloca ptr
  store ptr %fv1395, ptr %$f976.addr
  %fp1396 = getelementptr i8, ptr %ld1390, i64 24
  %fv1397 = load ptr, ptr %fp1396, align 8
  %$f977.addr = alloca ptr
  store ptr %fv1397, ptr %$f977.addr
  %freed1398 = call i64 @march_decrc_freed(ptr %ld1390)
  %freed_b1399 = icmp ne i64 %freed1398, 0
  br i1 %freed_b1399, label %br_unique330, label %br_shared331
br_shared331:
  call void @march_incrc(ptr %fv1397)
  call void @march_incrc(ptr %fv1395)
  br label %br_body332
br_unique330:
  br label %br_body332
br_body332:
  %ld1400 = load ptr, ptr %$f975.addr
  %rest.addr = alloca ptr
  store ptr %ld1400, ptr %rest.addr
  %ld1401 = load ptr, ptr %$f977.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1401, ptr %step_fn.addr
  %ld1402 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1402)
  %ld1403 = load ptr, ptr %step_fn.addr
  %fp1404 = getelementptr i8, ptr %ld1403, i64 16
  %fv1405 = load ptr, ptr %fp1404, align 8
  %ld1406 = load ptr, ptr %req.addr
  %ld1407 = load ptr, ptr %err.addr
  %cr1408 = call ptr (ptr, ptr, ptr) %fv1405(ptr %ld1403, ptr %ld1406, ptr %ld1407)
  %$t971.addr = alloca ptr
  store ptr %cr1408, ptr %$t971.addr
  %ld1409 = load ptr, ptr %$t971.addr
  %res_slot1410 = alloca ptr
  %tgp1411 = getelementptr i8, ptr %ld1409, i64 8
  %tag1412 = load i32, ptr %tgp1411, align 4
  switch i32 %tag1412, label %case_default334 [
      i32 0, label %case_br335
      i32 1, label %case_br336
  ]
case_br335:
  %fp1413 = getelementptr i8, ptr %ld1409, i64 16
  %fv1414 = load ptr, ptr %fp1413, align 8
  %$f972.addr = alloca ptr
  store ptr %fv1414, ptr %$f972.addr
  %freed1415 = call i64 @march_decrc_freed(ptr %ld1409)
  %freed_b1416 = icmp ne i64 %freed1415, 0
  br i1 %freed_b1416, label %br_unique337, label %br_shared338
br_shared338:
  call void @march_incrc(ptr %fv1414)
  br label %br_body339
br_unique337:
  br label %br_body339
br_body339:
  %ld1417 = load ptr, ptr %$f972.addr
  %resp.addr = alloca ptr
  store ptr %ld1417, ptr %resp.addr
  %hp1418 = call ptr @march_alloc(i64 24)
  %tgp1419 = getelementptr i8, ptr %hp1418, i64 8
  store i32 0, ptr %tgp1419, align 4
  %ld1420 = load ptr, ptr %resp.addr
  %fp1421 = getelementptr i8, ptr %hp1418, i64 16
  store ptr %ld1420, ptr %fp1421, align 8
  store ptr %hp1418, ptr %res_slot1410
  br label %case_merge333
case_br336:
  %fp1422 = getelementptr i8, ptr %ld1409, i64 16
  %fv1423 = load ptr, ptr %fp1422, align 8
  %$f973.addr = alloca ptr
  store ptr %fv1423, ptr %$f973.addr
  %freed1424 = call i64 @march_decrc_freed(ptr %ld1409)
  %freed_b1425 = icmp ne i64 %freed1424, 0
  br i1 %freed_b1425, label %br_unique340, label %br_shared341
br_shared341:
  call void @march_incrc(ptr %fv1423)
  br label %br_body342
br_unique340:
  br label %br_body342
br_body342:
  %ld1426 = load ptr, ptr %$f973.addr
  %new_err.addr = alloca ptr
  store ptr %ld1426, ptr %new_err.addr
  %ld1427 = load ptr, ptr %rest.addr
  %ld1428 = load ptr, ptr %req.addr
  %ld1429 = load ptr, ptr %new_err.addr
  %cr1430 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1427, ptr %ld1428, ptr %ld1429)
  store ptr %cr1430, ptr %res_slot1410
  br label %case_merge333
case_default334:
  unreachable
case_merge333:
  %case_r1431 = load ptr, ptr %res_slot1410
  store ptr %case_r1431, ptr %res_slot1391
  br label %case_merge327
case_default328:
  unreachable
case_merge327:
  %case_r1432 = load ptr, ptr %res_slot1391
  store ptr %case_r1432, ptr %res_slot1376
  br label %case_merge320
case_default321:
  unreachable
case_merge320:
  %case_r1433 = load ptr, ptr %res_slot1376
  ret ptr %case_r1433
}

define ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3337(ptr %steps.arg, ptr %req.arg, ptr %resp.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1434 = load ptr, ptr %steps.addr
  %res_slot1435 = alloca ptr
  %tgp1436 = getelementptr i8, ptr %ld1434, i64 8
  %tag1437 = load i32, ptr %tgp1436, align 4
  switch i32 %tag1437, label %case_default344 [
      i32 0, label %case_br345
      i32 1, label %case_br346
  ]
case_br345:
  %ld1438 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1438)
  %hp1439 = call ptr @march_alloc(i64 32)
  %tgp1440 = getelementptr i8, ptr %hp1439, i64 8
  store i32 0, ptr %tgp1440, align 4
  %ld1441 = load ptr, ptr %req.addr
  %fp1442 = getelementptr i8, ptr %hp1439, i64 16
  store ptr %ld1441, ptr %fp1442, align 8
  %ld1443 = load ptr, ptr %resp.addr
  %fp1444 = getelementptr i8, ptr %hp1439, i64 24
  store ptr %ld1443, ptr %fp1444, align 8
  %$t961.addr = alloca ptr
  store ptr %hp1439, ptr %$t961.addr
  %hp1445 = call ptr @march_alloc(i64 24)
  %tgp1446 = getelementptr i8, ptr %hp1445, i64 8
  store i32 0, ptr %tgp1446, align 4
  %ld1447 = load ptr, ptr %$t961.addr
  %fp1448 = getelementptr i8, ptr %hp1445, i64 16
  store ptr %ld1447, ptr %fp1448, align 8
  store ptr %hp1445, ptr %res_slot1435
  br label %case_merge343
case_br346:
  %fp1449 = getelementptr i8, ptr %ld1434, i64 16
  %fv1450 = load ptr, ptr %fp1449, align 8
  %$f967.addr = alloca ptr
  store ptr %fv1450, ptr %$f967.addr
  %fp1451 = getelementptr i8, ptr %ld1434, i64 24
  %fv1452 = load ptr, ptr %fp1451, align 8
  %$f968.addr = alloca ptr
  store ptr %fv1452, ptr %$f968.addr
  %freed1453 = call i64 @march_decrc_freed(ptr %ld1434)
  %freed_b1454 = icmp ne i64 %freed1453, 0
  br i1 %freed_b1454, label %br_unique347, label %br_shared348
br_shared348:
  call void @march_incrc(ptr %fv1452)
  call void @march_incrc(ptr %fv1450)
  br label %br_body349
br_unique347:
  br label %br_body349
br_body349:
  %ld1455 = load ptr, ptr %$f967.addr
  %res_slot1456 = alloca ptr
  %tgp1457 = getelementptr i8, ptr %ld1455, i64 8
  %tag1458 = load i32, ptr %tgp1457, align 4
  switch i32 %tag1458, label %case_default351 [
      i32 0, label %case_br352
  ]
case_br352:
  %fp1459 = getelementptr i8, ptr %ld1455, i64 16
  %fv1460 = load ptr, ptr %fp1459, align 8
  %$f969.addr = alloca ptr
  store ptr %fv1460, ptr %$f969.addr
  %fp1461 = getelementptr i8, ptr %ld1455, i64 24
  %fv1462 = load ptr, ptr %fp1461, align 8
  %$f970.addr = alloca ptr
  store ptr %fv1462, ptr %$f970.addr
  %freed1463 = call i64 @march_decrc_freed(ptr %ld1455)
  %freed_b1464 = icmp ne i64 %freed1463, 0
  br i1 %freed_b1464, label %br_unique353, label %br_shared354
br_shared354:
  call void @march_incrc(ptr %fv1462)
  call void @march_incrc(ptr %fv1460)
  br label %br_body355
br_unique353:
  br label %br_body355
br_body355:
  %ld1465 = load ptr, ptr %$f968.addr
  %rest.addr = alloca ptr
  store ptr %ld1465, ptr %rest.addr
  %ld1466 = load ptr, ptr %$f970.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1466, ptr %step_fn.addr
  %ld1467 = load ptr, ptr %step_fn.addr
  %fp1468 = getelementptr i8, ptr %ld1467, i64 16
  %fv1469 = load ptr, ptr %fp1468, align 8
  %ld1470 = load ptr, ptr %req.addr
  %ld1471 = load ptr, ptr %resp.addr
  %cr1472 = call ptr (ptr, ptr, ptr) %fv1469(ptr %ld1467, ptr %ld1470, ptr %ld1471)
  %$t962.addr = alloca ptr
  store ptr %cr1472, ptr %$t962.addr
  %ld1473 = load ptr, ptr %$t962.addr
  %res_slot1474 = alloca ptr
  %tgp1475 = getelementptr i8, ptr %ld1473, i64 8
  %tag1476 = load i32, ptr %tgp1475, align 4
  switch i32 %tag1476, label %case_default357 [
      i32 1, label %case_br358
      i32 0, label %case_br359
  ]
case_br358:
  %fp1477 = getelementptr i8, ptr %ld1473, i64 16
  %fv1478 = load ptr, ptr %fp1477, align 8
  %$f963.addr = alloca ptr
  store ptr %fv1478, ptr %$f963.addr
  %ld1479 = load ptr, ptr %$f963.addr
  %e.addr = alloca ptr
  store ptr %ld1479, ptr %e.addr
  %ld1480 = load ptr, ptr %$t962.addr
  %ld1481 = load ptr, ptr %e.addr
  %rc1482 = load i64, ptr %ld1480, align 8
  %uniq1483 = icmp eq i64 %rc1482, 1
  %fbip_slot1484 = alloca ptr
  br i1 %uniq1483, label %fbip_reuse360, label %fbip_fresh361
fbip_reuse360:
  %tgp1485 = getelementptr i8, ptr %ld1480, i64 8
  store i32 1, ptr %tgp1485, align 4
  %fp1486 = getelementptr i8, ptr %ld1480, i64 16
  store ptr %ld1481, ptr %fp1486, align 8
  store ptr %ld1480, ptr %fbip_slot1484
  br label %fbip_merge362
fbip_fresh361:
  call void @march_decrc(ptr %ld1480)
  %hp1487 = call ptr @march_alloc(i64 24)
  %tgp1488 = getelementptr i8, ptr %hp1487, i64 8
  store i32 1, ptr %tgp1488, align 4
  %fp1489 = getelementptr i8, ptr %hp1487, i64 16
  store ptr %ld1481, ptr %fp1489, align 8
  store ptr %hp1487, ptr %fbip_slot1484
  br label %fbip_merge362
fbip_merge362:
  %fbip_r1490 = load ptr, ptr %fbip_slot1484
  store ptr %fbip_r1490, ptr %res_slot1474
  br label %case_merge356
case_br359:
  %fp1491 = getelementptr i8, ptr %ld1473, i64 16
  %fv1492 = load ptr, ptr %fp1491, align 8
  %$f964.addr = alloca ptr
  store ptr %fv1492, ptr %$f964.addr
  %freed1493 = call i64 @march_decrc_freed(ptr %ld1473)
  %freed_b1494 = icmp ne i64 %freed1493, 0
  br i1 %freed_b1494, label %br_unique363, label %br_shared364
br_shared364:
  call void @march_incrc(ptr %fv1492)
  br label %br_body365
br_unique363:
  br label %br_body365
br_body365:
  %ld1495 = load ptr, ptr %$f964.addr
  %res_slot1496 = alloca ptr
  %tgp1497 = getelementptr i8, ptr %ld1495, i64 8
  %tag1498 = load i32, ptr %tgp1497, align 4
  switch i32 %tag1498, label %case_default367 [
      i32 0, label %case_br368
  ]
case_br368:
  %fp1499 = getelementptr i8, ptr %ld1495, i64 16
  %fv1500 = load ptr, ptr %fp1499, align 8
  %$f965.addr = alloca ptr
  store ptr %fv1500, ptr %$f965.addr
  %fp1501 = getelementptr i8, ptr %ld1495, i64 24
  %fv1502 = load ptr, ptr %fp1501, align 8
  %$f966.addr = alloca ptr
  store ptr %fv1502, ptr %$f966.addr
  %freed1503 = call i64 @march_decrc_freed(ptr %ld1495)
  %freed_b1504 = icmp ne i64 %freed1503, 0
  br i1 %freed_b1504, label %br_unique369, label %br_shared370
br_shared370:
  call void @march_incrc(ptr %fv1502)
  call void @march_incrc(ptr %fv1500)
  br label %br_body371
br_unique369:
  br label %br_body371
br_body371:
  %ld1505 = load ptr, ptr %$f966.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1505, ptr %new_resp.addr
  %ld1506 = load ptr, ptr %$f965.addr
  %new_req.addr = alloca ptr
  store ptr %ld1506, ptr %new_req.addr
  %ld1507 = load ptr, ptr %rest.addr
  %ld1508 = load ptr, ptr %new_req.addr
  %ld1509 = load ptr, ptr %new_resp.addr
  %cr1510 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3337(ptr %ld1507, ptr %ld1508, ptr %ld1509)
  store ptr %cr1510, ptr %res_slot1496
  br label %case_merge366
case_default367:
  unreachable
case_merge366:
  %case_r1511 = load ptr, ptr %res_slot1496
  store ptr %case_r1511, ptr %res_slot1474
  br label %case_merge356
case_default357:
  unreachable
case_merge356:
  %case_r1512 = load ptr, ptr %res_slot1474
  store ptr %case_r1512, ptr %res_slot1456
  br label %case_merge350
case_default351:
  unreachable
case_merge350:
  %case_r1513 = load ptr, ptr %res_slot1456
  store ptr %case_r1513, ptr %res_slot1435
  br label %case_merge343
case_default344:
  unreachable
case_merge343:
  %case_r1514 = load ptr, ptr %res_slot1435
  ret ptr %case_r1514
}

define ptr @HttpClient.handle_redirects$Request_String$Response_V__3337$Int$Int(ptr %req.arg, ptr %resp.arg, i64 %max.arg, i64 %count.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %max.addr = alloca i64
  store i64 %max.arg, ptr %max.addr
  %count.addr = alloca i64
  store i64 %count.arg, ptr %count.addr
  %ld1515 = load i64, ptr %max.addr
  %cmp1516 = icmp eq i64 %ld1515, 0
  %ar1517 = zext i1 %cmp1516 to i64
  %$t994.addr = alloca i64
  store i64 %ar1517, ptr %$t994.addr
  %ld1518 = load i64, ptr %$t994.addr
  %res_slot1519 = alloca ptr
  %bi1520 = trunc i64 %ld1518 to i1
  br i1 %bi1520, label %case_br374, label %case_default373
case_br374:
  %hp1521 = call ptr @march_alloc(i64 24)
  %tgp1522 = getelementptr i8, ptr %hp1521, i64 8
  store i32 0, ptr %tgp1522, align 4
  %ld1523 = load ptr, ptr %resp.addr
  %fp1524 = getelementptr i8, ptr %hp1521, i64 16
  store ptr %ld1523, ptr %fp1524, align 8
  store ptr %hp1521, ptr %res_slot1519
  br label %case_merge372
case_default373:
  %ld1525 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1525)
  %ld1526 = load ptr, ptr %resp.addr
  %cr1527 = call i64 @Http.response_is_redirect$Response_V__3337(ptr %ld1526)
  %$t995.addr = alloca i64
  store i64 %cr1527, ptr %$t995.addr
  %ld1528 = load i64, ptr %$t995.addr
  %ar1529 = xor i64 %ld1528, 1
  %$t996.addr = alloca i64
  store i64 %ar1529, ptr %$t996.addr
  %ld1530 = load i64, ptr %$t996.addr
  %res_slot1531 = alloca ptr
  %bi1532 = trunc i64 %ld1530 to i1
  br i1 %bi1532, label %case_br377, label %case_default376
case_br377:
  %hp1533 = call ptr @march_alloc(i64 24)
  %tgp1534 = getelementptr i8, ptr %hp1533, i64 8
  store i32 0, ptr %tgp1534, align 4
  %ld1535 = load ptr, ptr %resp.addr
  %fp1536 = getelementptr i8, ptr %hp1533, i64 16
  store ptr %ld1535, ptr %fp1536, align 8
  store ptr %hp1533, ptr %res_slot1531
  br label %case_merge375
case_default376:
  %ld1537 = load i64, ptr %count.addr
  %ld1538 = load i64, ptr %max.addr
  %cmp1539 = icmp sge i64 %ld1537, %ld1538
  %ar1540 = zext i1 %cmp1539 to i64
  %$t997.addr = alloca i64
  store i64 %ar1540, ptr %$t997.addr
  %ld1541 = load i64, ptr %$t997.addr
  %res_slot1542 = alloca ptr
  %bi1543 = trunc i64 %ld1541 to i1
  br i1 %bi1543, label %case_br380, label %case_default379
case_br380:
  %hp1544 = call ptr @march_alloc(i64 24)
  %tgp1545 = getelementptr i8, ptr %hp1544, i64 8
  store i32 2, ptr %tgp1545, align 4
  %ld1546 = load i64, ptr %count.addr
  %fp1547 = getelementptr i8, ptr %hp1544, i64 16
  store i64 %ld1546, ptr %fp1547, align 8
  %$t998.addr = alloca ptr
  store ptr %hp1544, ptr %$t998.addr
  %hp1548 = call ptr @march_alloc(i64 24)
  %tgp1549 = getelementptr i8, ptr %hp1548, i64 8
  store i32 1, ptr %tgp1549, align 4
  %ld1550 = load ptr, ptr %$t998.addr
  %fp1551 = getelementptr i8, ptr %hp1548, i64 16
  store ptr %ld1550, ptr %fp1551, align 8
  store ptr %hp1548, ptr %res_slot1542
  br label %case_merge378
case_default379:
  %ld1552 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1552)
  %ld1553 = load ptr, ptr %resp.addr
  %sl1554 = call ptr @march_string_lit(ptr @.str39, i64 8)
  %cr1555 = call ptr @Http.get_header$Response_V__3337$String(ptr %ld1553, ptr %sl1554)
  %$t999.addr = alloca ptr
  store ptr %cr1555, ptr %$t999.addr
  %ld1556 = load ptr, ptr %$t999.addr
  %res_slot1557 = alloca ptr
  %tgp1558 = getelementptr i8, ptr %ld1556, i64 8
  %tag1559 = load i32, ptr %tgp1558, align 4
  switch i32 %tag1559, label %case_default382 [
      i32 0, label %case_br383
      i32 1, label %case_br384
  ]
case_br383:
  %ld1560 = load ptr, ptr %$t999.addr
  call void @march_decrc(ptr %ld1560)
  %hp1561 = call ptr @march_alloc(i64 24)
  %tgp1562 = getelementptr i8, ptr %hp1561, i64 8
  store i32 0, ptr %tgp1562, align 4
  %ld1563 = load ptr, ptr %resp.addr
  %fp1564 = getelementptr i8, ptr %hp1561, i64 16
  store ptr %ld1563, ptr %fp1564, align 8
  store ptr %hp1561, ptr %res_slot1557
  br label %case_merge381
case_br384:
  %fp1565 = getelementptr i8, ptr %ld1556, i64 16
  %fv1566 = load ptr, ptr %fp1565, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv1566, ptr %$f1018.addr
  %freed1567 = call i64 @march_decrc_freed(ptr %ld1556)
  %freed_b1568 = icmp ne i64 %freed1567, 0
  br i1 %freed_b1568, label %br_unique385, label %br_shared386
br_shared386:
  call void @march_incrc(ptr %fv1566)
  br label %br_body387
br_unique385:
  br label %br_body387
br_body387:
  %ld1569 = load ptr, ptr %$f1018.addr
  %location.addr = alloca ptr
  store ptr %ld1569, ptr %location.addr
  %ld1570 = load ptr, ptr %location.addr
  call void @march_incrc(ptr %ld1570)
  %ld1571 = load ptr, ptr %location.addr
  %cr1572 = call ptr @Http.parse_url(ptr %ld1571)
  %$t1000.addr = alloca ptr
  store ptr %cr1572, ptr %$t1000.addr
  %ld1573 = load ptr, ptr %$t1000.addr
  %res_slot1574 = alloca ptr
  %tgp1575 = getelementptr i8, ptr %ld1573, i64 8
  %tag1576 = load i32, ptr %tgp1575, align 4
  switch i32 %tag1576, label %case_default389 [
      i32 0, label %case_br390
      i32 1, label %case_br391
  ]
case_br390:
  %fp1577 = getelementptr i8, ptr %ld1573, i64 16
  %fv1578 = load ptr, ptr %fp1577, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv1578, ptr %$f1011.addr
  %freed1579 = call i64 @march_decrc_freed(ptr %ld1573)
  %freed_b1580 = icmp ne i64 %freed1579, 0
  br i1 %freed_b1580, label %br_unique392, label %br_shared393
br_shared393:
  call void @march_incrc(ptr %fv1578)
  br label %br_body394
br_unique392:
  br label %br_body394
br_body394:
  %ld1581 = load ptr, ptr %$f1011.addr
  %parsed.addr = alloca ptr
  store ptr %ld1581, ptr %parsed.addr
  %hp1582 = call ptr @march_alloc(i64 16)
  %tgp1583 = getelementptr i8, ptr %hp1582, i64 8
  store i32 0, ptr %tgp1583, align 4
  %$t1001.addr = alloca ptr
  store ptr %hp1582, ptr %$t1001.addr
  %ld1584 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1584)
  %ld1585 = load ptr, ptr %parsed.addr
  %cr1586 = call ptr @Http.scheme$Request_T_(ptr %ld1585)
  %$t1002.addr = alloca ptr
  store ptr %cr1586, ptr %$t1002.addr
  %ld1587 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1587)
  %ld1588 = load ptr, ptr %parsed.addr
  %cr1589 = call ptr @Http.host$Request_T_(ptr %ld1588)
  %$t1003.addr = alloca ptr
  store ptr %cr1589, ptr %$t1003.addr
  %ld1590 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1590)
  %ld1591 = load ptr, ptr %parsed.addr
  %cr1592 = call ptr @Http.port$Request_T_(ptr %ld1591)
  %$t1004.addr = alloca ptr
  store ptr %cr1592, ptr %$t1004.addr
  %ld1593 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1593)
  %ld1594 = load ptr, ptr %parsed.addr
  %cr1595 = call ptr @Http.path$Request_T_(ptr %ld1594)
  %$t1005.addr = alloca ptr
  store ptr %cr1595, ptr %$t1005.addr
  %ld1596 = load ptr, ptr %parsed.addr
  %cr1597 = call ptr @Http.query$Request_T_(ptr %ld1596)
  %$t1006.addr = alloca ptr
  store ptr %cr1597, ptr %$t1006.addr
  %ld1598 = load ptr, ptr %req.addr
  %cr1599 = call ptr @Http.headers$Request_String(ptr %ld1598)
  %$t1007.addr = alloca ptr
  store ptr %cr1599, ptr %$t1007.addr
  %hp1600 = call ptr @march_alloc(i64 80)
  %tgp1601 = getelementptr i8, ptr %hp1600, i64 8
  store i32 0, ptr %tgp1601, align 4
  %ld1602 = load ptr, ptr %$t1001.addr
  %fp1603 = getelementptr i8, ptr %hp1600, i64 16
  store ptr %ld1602, ptr %fp1603, align 8
  %ld1604 = load ptr, ptr %$t1002.addr
  %fp1605 = getelementptr i8, ptr %hp1600, i64 24
  store ptr %ld1604, ptr %fp1605, align 8
  %ld1606 = load ptr, ptr %$t1003.addr
  %fp1607 = getelementptr i8, ptr %hp1600, i64 32
  store ptr %ld1606, ptr %fp1607, align 8
  %ld1608 = load ptr, ptr %$t1004.addr
  %fp1609 = getelementptr i8, ptr %hp1600, i64 40
  store ptr %ld1608, ptr %fp1609, align 8
  %ld1610 = load ptr, ptr %$t1005.addr
  %fp1611 = getelementptr i8, ptr %hp1600, i64 48
  store ptr %ld1610, ptr %fp1611, align 8
  %ld1612 = load ptr, ptr %$t1006.addr
  %fp1613 = getelementptr i8, ptr %hp1600, i64 56
  store ptr %ld1612, ptr %fp1613, align 8
  %ld1614 = load ptr, ptr %$t1007.addr
  %fp1615 = getelementptr i8, ptr %hp1600, i64 64
  store ptr %ld1614, ptr %fp1615, align 8
  %sl1616 = call ptr @march_string_lit(ptr @.str40, i64 0)
  %fp1617 = getelementptr i8, ptr %hp1600, i64 72
  store ptr %sl1616, ptr %fp1617, align 8
  store ptr %hp1600, ptr %res_slot1574
  br label %case_merge388
case_br391:
  %fp1618 = getelementptr i8, ptr %ld1573, i64 16
  %fv1619 = load ptr, ptr %fp1618, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv1619, ptr %$f1012.addr
  %freed1620 = call i64 @march_decrc_freed(ptr %ld1573)
  %freed_b1621 = icmp ne i64 %freed1620, 0
  br i1 %freed_b1621, label %br_unique395, label %br_shared396
br_shared396:
  call void @march_incrc(ptr %fv1619)
  br label %br_body397
br_unique395:
  br label %br_body397
br_body397:
  %ld1622 = load ptr, ptr %req.addr
  %ld1623 = load ptr, ptr %location.addr
  %cr1624 = call ptr @Http.set_path$Request_String$String(ptr %ld1622, ptr %ld1623)
  %$t1008.addr = alloca ptr
  store ptr %cr1624, ptr %$t1008.addr
  %hp1625 = call ptr @march_alloc(i64 16)
  %tgp1626 = getelementptr i8, ptr %hp1625, i64 8
  store i32 0, ptr %tgp1626, align 4
  %$t1009.addr = alloca ptr
  store ptr %hp1625, ptr %$t1009.addr
  %ld1627 = load ptr, ptr %$t1008.addr
  %ld1628 = load ptr, ptr %$t1009.addr
  %cr1629 = call ptr @Http.set_method$Request_String$Method(ptr %ld1627, ptr %ld1628)
  %$t1010.addr = alloca ptr
  store ptr %cr1629, ptr %$t1010.addr
  %ld1630 = load ptr, ptr %$t1010.addr
  %sl1631 = call ptr @march_string_lit(ptr @.str41, i64 0)
  %cr1632 = call ptr @Http.set_body$Request_String$String(ptr %ld1630, ptr %sl1631)
  store ptr %cr1632, ptr %res_slot1574
  br label %case_merge388
case_default389:
  unreachable
case_merge388:
  %case_r1633 = load ptr, ptr %res_slot1574
  %redirect_req.addr = alloca ptr
  store ptr %case_r1633, ptr %redirect_req.addr
  %ld1634 = load ptr, ptr %redirect_req.addr
  call void @march_incrc(ptr %ld1634)
  %ld1635 = load ptr, ptr %redirect_req.addr
  %cr1636 = call ptr @HttpTransport.request$Request_String(ptr %ld1635)
  %$t1013.addr = alloca ptr
  store ptr %cr1636, ptr %$t1013.addr
  %ld1637 = load ptr, ptr %$t1013.addr
  %res_slot1638 = alloca ptr
  %tgp1639 = getelementptr i8, ptr %ld1637, i64 8
  %tag1640 = load i32, ptr %tgp1639, align 4
  switch i32 %tag1640, label %case_default399 [
      i32 1, label %case_br400
      i32 0, label %case_br401
  ]
case_br400:
  %fp1641 = getelementptr i8, ptr %ld1637, i64 16
  %fv1642 = load ptr, ptr %fp1641, align 8
  %$f1016.addr = alloca ptr
  store ptr %fv1642, ptr %$f1016.addr
  %ld1643 = load ptr, ptr %$f1016.addr
  %e.addr = alloca ptr
  store ptr %ld1643, ptr %e.addr
  %hp1644 = call ptr @march_alloc(i64 24)
  %tgp1645 = getelementptr i8, ptr %hp1644, i64 8
  store i32 0, ptr %tgp1645, align 4
  %ld1646 = load ptr, ptr %e.addr
  %fp1647 = getelementptr i8, ptr %hp1644, i64 16
  store ptr %ld1646, ptr %fp1647, align 8
  %$t1014.addr = alloca ptr
  store ptr %hp1644, ptr %$t1014.addr
  %ld1648 = load ptr, ptr %$t1013.addr
  %ld1649 = load ptr, ptr %$t1014.addr
  %rc1650 = load i64, ptr %ld1648, align 8
  %uniq1651 = icmp eq i64 %rc1650, 1
  %fbip_slot1652 = alloca ptr
  br i1 %uniq1651, label %fbip_reuse402, label %fbip_fresh403
fbip_reuse402:
  %tgp1653 = getelementptr i8, ptr %ld1648, i64 8
  store i32 1, ptr %tgp1653, align 4
  %fp1654 = getelementptr i8, ptr %ld1648, i64 16
  store ptr %ld1649, ptr %fp1654, align 8
  store ptr %ld1648, ptr %fbip_slot1652
  br label %fbip_merge404
fbip_fresh403:
  call void @march_decrc(ptr %ld1648)
  %hp1655 = call ptr @march_alloc(i64 24)
  %tgp1656 = getelementptr i8, ptr %hp1655, i64 8
  store i32 1, ptr %tgp1656, align 4
  %fp1657 = getelementptr i8, ptr %hp1655, i64 16
  store ptr %ld1649, ptr %fp1657, align 8
  store ptr %hp1655, ptr %fbip_slot1652
  br label %fbip_merge404
fbip_merge404:
  %fbip_r1658 = load ptr, ptr %fbip_slot1652
  store ptr %fbip_r1658, ptr %res_slot1638
  br label %case_merge398
case_br401:
  %fp1659 = getelementptr i8, ptr %ld1637, i64 16
  %fv1660 = load ptr, ptr %fp1659, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv1660, ptr %$f1017.addr
  %freed1661 = call i64 @march_decrc_freed(ptr %ld1637)
  %freed_b1662 = icmp ne i64 %freed1661, 0
  br i1 %freed_b1662, label %br_unique405, label %br_shared406
br_shared406:
  call void @march_incrc(ptr %fv1660)
  br label %br_body407
br_unique405:
  br label %br_body407
br_body407:
  %ld1663 = load ptr, ptr %$f1017.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1663, ptr %new_resp.addr
  %ld1664 = load i64, ptr %count.addr
  %ar1665 = add i64 %ld1664, 1
  %$t1015.addr = alloca i64
  store i64 %ar1665, ptr %$t1015.addr
  %ld1666 = load ptr, ptr %redirect_req.addr
  %ld1667 = load ptr, ptr %new_resp.addr
  %ld1668 = load i64, ptr %max.addr
  %ld1669 = load i64, ptr %$t1015.addr
  %cr1670 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3337$Int$Int(ptr %ld1666, ptr %ld1667, i64 %ld1668, i64 %ld1669)
  store ptr %cr1670, ptr %res_slot1638
  br label %case_merge398
case_default399:
  unreachable
case_merge398:
  %case_r1671 = load ptr, ptr %res_slot1638
  store ptr %case_r1671, ptr %res_slot1557
  br label %case_merge381
case_default382:
  unreachable
case_merge381:
  %case_r1672 = load ptr, ptr %res_slot1557
  store ptr %case_r1672, ptr %res_slot1542
  br label %case_merge378
case_merge378:
  %case_r1673 = load ptr, ptr %res_slot1542
  store ptr %case_r1673, ptr %res_slot1531
  br label %case_merge375
case_merge375:
  %case_r1674 = load ptr, ptr %res_slot1531
  store ptr %case_r1674, ptr %res_slot1519
  br label %case_merge372
case_merge372:
  %case_r1675 = load ptr, ptr %res_slot1519
  ret ptr %case_r1675
}

define ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %req.arg, i64 %retries_left.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld1676 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1676)
  %ld1677 = load ptr, ptr %req.addr
  %cr1678 = call ptr @HttpTransport.request$Request_String(ptr %ld1677)
  %$t978.addr = alloca ptr
  store ptr %cr1678, ptr %$t978.addr
  %ld1679 = load ptr, ptr %$t978.addr
  %res_slot1680 = alloca ptr
  %tgp1681 = getelementptr i8, ptr %ld1679, i64 8
  %tag1682 = load i32, ptr %tgp1681, align 4
  switch i32 %tag1682, label %case_default409 [
      i32 0, label %case_br410
      i32 1, label %case_br411
  ]
case_br410:
  %fp1683 = getelementptr i8, ptr %ld1679, i64 16
  %fv1684 = load ptr, ptr %fp1683, align 8
  %$f981.addr = alloca ptr
  store ptr %fv1684, ptr %$f981.addr
  %ld1685 = load ptr, ptr %$f981.addr
  %resp.addr = alloca ptr
  store ptr %ld1685, ptr %resp.addr
  %ld1686 = load ptr, ptr %$t978.addr
  %ld1687 = load ptr, ptr %resp.addr
  %rc1688 = load i64, ptr %ld1686, align 8
  %uniq1689 = icmp eq i64 %rc1688, 1
  %fbip_slot1690 = alloca ptr
  br i1 %uniq1689, label %fbip_reuse412, label %fbip_fresh413
fbip_reuse412:
  %tgp1691 = getelementptr i8, ptr %ld1686, i64 8
  store i32 0, ptr %tgp1691, align 4
  %fp1692 = getelementptr i8, ptr %ld1686, i64 16
  store ptr %ld1687, ptr %fp1692, align 8
  store ptr %ld1686, ptr %fbip_slot1690
  br label %fbip_merge414
fbip_fresh413:
  call void @march_decrc(ptr %ld1686)
  %hp1693 = call ptr @march_alloc(i64 24)
  %tgp1694 = getelementptr i8, ptr %hp1693, i64 8
  store i32 0, ptr %tgp1694, align 4
  %fp1695 = getelementptr i8, ptr %hp1693, i64 16
  store ptr %ld1687, ptr %fp1695, align 8
  store ptr %hp1693, ptr %fbip_slot1690
  br label %fbip_merge414
fbip_merge414:
  %fbip_r1696 = load ptr, ptr %fbip_slot1690
  store ptr %fbip_r1696, ptr %res_slot1680
  br label %case_merge408
case_br411:
  %fp1697 = getelementptr i8, ptr %ld1679, i64 16
  %fv1698 = load ptr, ptr %fp1697, align 8
  %$f982.addr = alloca ptr
  store ptr %fv1698, ptr %$f982.addr
  %freed1699 = call i64 @march_decrc_freed(ptr %ld1679)
  %freed_b1700 = icmp ne i64 %freed1699, 0
  br i1 %freed_b1700, label %br_unique415, label %br_shared416
br_shared416:
  call void @march_incrc(ptr %fv1698)
  br label %br_body417
br_unique415:
  br label %br_body417
br_body417:
  %ld1701 = load ptr, ptr %$f982.addr
  %e.addr = alloca ptr
  store ptr %ld1701, ptr %e.addr
  %ld1702 = load i64, ptr %retries_left.addr
  %cmp1703 = icmp sgt i64 %ld1702, 0
  %ar1704 = zext i1 %cmp1703 to i64
  %$t979.addr = alloca i64
  store i64 %ar1704, ptr %$t979.addr
  %ld1705 = load i64, ptr %$t979.addr
  %res_slot1706 = alloca ptr
  %bi1707 = trunc i64 %ld1705 to i1
  br i1 %bi1707, label %case_br420, label %case_default419
case_br420:
  %ld1708 = load i64, ptr %retries_left.addr
  %ar1709 = sub i64 %ld1708, 1
  %$t980.addr = alloca i64
  store i64 %ar1709, ptr %$t980.addr
  %ld1710 = load ptr, ptr %req.addr
  %ld1711 = load i64, ptr %$t980.addr
  %cr1712 = call ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %ld1710, i64 %ld1711)
  store ptr %cr1712, ptr %res_slot1706
  br label %case_merge418
case_default419:
  %hp1713 = call ptr @march_alloc(i64 24)
  %tgp1714 = getelementptr i8, ptr %hp1713, i64 8
  store i32 1, ptr %tgp1714, align 4
  %ld1715 = load ptr, ptr %e.addr
  %fp1716 = getelementptr i8, ptr %hp1713, i64 16
  store ptr %ld1715, ptr %fp1716, align 8
  store ptr %hp1713, ptr %res_slot1706
  br label %case_merge418
case_merge418:
  %case_r1717 = load ptr, ptr %res_slot1706
  store ptr %case_r1717, ptr %res_slot1680
  br label %case_merge408
case_default409:
  unreachable
case_merge408:
  %case_r1718 = load ptr, ptr %res_slot1680
  ret ptr %case_r1718
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1719 = load ptr, ptr %steps.addr
  %res_slot1720 = alloca ptr
  %tgp1721 = getelementptr i8, ptr %ld1719, i64 8
  %tag1722 = load i32, ptr %tgp1721, align 4
  switch i32 %tag1722, label %case_default422 [
      i32 0, label %case_br423
      i32 1, label %case_br424
  ]
case_br423:
  %ld1723 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1723)
  %hp1724 = call ptr @march_alloc(i64 24)
  %tgp1725 = getelementptr i8, ptr %hp1724, i64 8
  store i32 0, ptr %tgp1725, align 4
  %ld1726 = load ptr, ptr %req.addr
  %fp1727 = getelementptr i8, ptr %hp1724, i64 16
  store ptr %ld1726, ptr %fp1727, align 8
  store ptr %hp1724, ptr %res_slot1720
  br label %case_merge421
case_br424:
  %fp1728 = getelementptr i8, ptr %ld1719, i64 16
  %fv1729 = load ptr, ptr %fp1728, align 8
  %$f957.addr = alloca ptr
  store ptr %fv1729, ptr %$f957.addr
  %fp1730 = getelementptr i8, ptr %ld1719, i64 24
  %fv1731 = load ptr, ptr %fp1730, align 8
  %$f958.addr = alloca ptr
  store ptr %fv1731, ptr %$f958.addr
  %freed1732 = call i64 @march_decrc_freed(ptr %ld1719)
  %freed_b1733 = icmp ne i64 %freed1732, 0
  br i1 %freed_b1733, label %br_unique425, label %br_shared426
br_shared426:
  call void @march_incrc(ptr %fv1731)
  call void @march_incrc(ptr %fv1729)
  br label %br_body427
br_unique425:
  br label %br_body427
br_body427:
  %ld1734 = load ptr, ptr %$f957.addr
  %res_slot1735 = alloca ptr
  %tgp1736 = getelementptr i8, ptr %ld1734, i64 8
  %tag1737 = load i32, ptr %tgp1736, align 4
  switch i32 %tag1737, label %case_default429 [
      i32 0, label %case_br430
  ]
case_br430:
  %fp1738 = getelementptr i8, ptr %ld1734, i64 16
  %fv1739 = load ptr, ptr %fp1738, align 8
  %$f959.addr = alloca ptr
  store ptr %fv1739, ptr %$f959.addr
  %fp1740 = getelementptr i8, ptr %ld1734, i64 24
  %fv1741 = load ptr, ptr %fp1740, align 8
  %$f960.addr = alloca ptr
  store ptr %fv1741, ptr %$f960.addr
  %freed1742 = call i64 @march_decrc_freed(ptr %ld1734)
  %freed_b1743 = icmp ne i64 %freed1742, 0
  br i1 %freed_b1743, label %br_unique431, label %br_shared432
br_shared432:
  call void @march_incrc(ptr %fv1741)
  call void @march_incrc(ptr %fv1739)
  br label %br_body433
br_unique431:
  br label %br_body433
br_body433:
  %ld1744 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld1744, ptr %rest.addr
  %ld1745 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1745, ptr %step_fn.addr
  %ld1746 = load ptr, ptr %step_fn.addr
  %fp1747 = getelementptr i8, ptr %ld1746, i64 16
  %fv1748 = load ptr, ptr %fp1747, align 8
  %ld1749 = load ptr, ptr %req.addr
  %cr1750 = call ptr (ptr, ptr) %fv1748(ptr %ld1746, ptr %ld1749)
  %$t954.addr = alloca ptr
  store ptr %cr1750, ptr %$t954.addr
  %ld1751 = load ptr, ptr %$t954.addr
  %res_slot1752 = alloca ptr
  %tgp1753 = getelementptr i8, ptr %ld1751, i64 8
  %tag1754 = load i32, ptr %tgp1753, align 4
  switch i32 %tag1754, label %case_default435 [
      i32 1, label %case_br436
      i32 0, label %case_br437
  ]
case_br436:
  %fp1755 = getelementptr i8, ptr %ld1751, i64 16
  %fv1756 = load ptr, ptr %fp1755, align 8
  %$f955.addr = alloca ptr
  store ptr %fv1756, ptr %$f955.addr
  %ld1757 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld1757, ptr %e.addr
  %ld1758 = load ptr, ptr %$t954.addr
  %ld1759 = load ptr, ptr %e.addr
  %rc1760 = load i64, ptr %ld1758, align 8
  %uniq1761 = icmp eq i64 %rc1760, 1
  %fbip_slot1762 = alloca ptr
  br i1 %uniq1761, label %fbip_reuse438, label %fbip_fresh439
fbip_reuse438:
  %tgp1763 = getelementptr i8, ptr %ld1758, i64 8
  store i32 1, ptr %tgp1763, align 4
  %fp1764 = getelementptr i8, ptr %ld1758, i64 16
  store ptr %ld1759, ptr %fp1764, align 8
  store ptr %ld1758, ptr %fbip_slot1762
  br label %fbip_merge440
fbip_fresh439:
  call void @march_decrc(ptr %ld1758)
  %hp1765 = call ptr @march_alloc(i64 24)
  %tgp1766 = getelementptr i8, ptr %hp1765, i64 8
  store i32 1, ptr %tgp1766, align 4
  %fp1767 = getelementptr i8, ptr %hp1765, i64 16
  store ptr %ld1759, ptr %fp1767, align 8
  store ptr %hp1765, ptr %fbip_slot1762
  br label %fbip_merge440
fbip_merge440:
  %fbip_r1768 = load ptr, ptr %fbip_slot1762
  store ptr %fbip_r1768, ptr %res_slot1752
  br label %case_merge434
case_br437:
  %fp1769 = getelementptr i8, ptr %ld1751, i64 16
  %fv1770 = load ptr, ptr %fp1769, align 8
  %$f956.addr = alloca ptr
  store ptr %fv1770, ptr %$f956.addr
  %freed1771 = call i64 @march_decrc_freed(ptr %ld1751)
  %freed_b1772 = icmp ne i64 %freed1771, 0
  br i1 %freed_b1772, label %br_unique441, label %br_shared442
br_shared442:
  call void @march_incrc(ptr %fv1770)
  br label %br_body443
br_unique441:
  br label %br_body443
br_body443:
  %ld1773 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld1773, ptr %new_req.addr
  %ld1774 = load ptr, ptr %rest.addr
  %ld1775 = load ptr, ptr %new_req.addr
  %cr1776 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld1774, ptr %ld1775)
  store ptr %cr1776, ptr %res_slot1752
  br label %case_merge434
case_default435:
  unreachable
case_merge434:
  %case_r1777 = load ptr, ptr %res_slot1752
  store ptr %case_r1777, ptr %res_slot1735
  br label %case_merge428
case_default429:
  unreachable
case_merge428:
  %case_r1778 = load ptr, ptr %res_slot1735
  store ptr %case_r1778, ptr %res_slot1720
  br label %case_merge421
case_default422:
  unreachable
case_merge421:
  %case_r1779 = load ptr, ptr %res_slot1720
  ret ptr %case_r1779
}

define ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3284(ptr %steps.arg, ptr %req.arg, ptr %resp.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1780 = load ptr, ptr %steps.addr
  %res_slot1781 = alloca ptr
  %tgp1782 = getelementptr i8, ptr %ld1780, i64 8
  %tag1783 = load i32, ptr %tgp1782, align 4
  switch i32 %tag1783, label %case_default445 [
      i32 0, label %case_br446
      i32 1, label %case_br447
  ]
case_br446:
  %ld1784 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1784)
  %hp1785 = call ptr @march_alloc(i64 32)
  %tgp1786 = getelementptr i8, ptr %hp1785, i64 8
  store i32 0, ptr %tgp1786, align 4
  %ld1787 = load ptr, ptr %req.addr
  %fp1788 = getelementptr i8, ptr %hp1785, i64 16
  store ptr %ld1787, ptr %fp1788, align 8
  %ld1789 = load ptr, ptr %resp.addr
  %fp1790 = getelementptr i8, ptr %hp1785, i64 24
  store ptr %ld1789, ptr %fp1790, align 8
  %$t961.addr = alloca ptr
  store ptr %hp1785, ptr %$t961.addr
  %hp1791 = call ptr @march_alloc(i64 24)
  %tgp1792 = getelementptr i8, ptr %hp1791, i64 8
  store i32 0, ptr %tgp1792, align 4
  %ld1793 = load ptr, ptr %$t961.addr
  %fp1794 = getelementptr i8, ptr %hp1791, i64 16
  store ptr %ld1793, ptr %fp1794, align 8
  store ptr %hp1791, ptr %res_slot1781
  br label %case_merge444
case_br447:
  %fp1795 = getelementptr i8, ptr %ld1780, i64 16
  %fv1796 = load ptr, ptr %fp1795, align 8
  %$f967.addr = alloca ptr
  store ptr %fv1796, ptr %$f967.addr
  %fp1797 = getelementptr i8, ptr %ld1780, i64 24
  %fv1798 = load ptr, ptr %fp1797, align 8
  %$f968.addr = alloca ptr
  store ptr %fv1798, ptr %$f968.addr
  %freed1799 = call i64 @march_decrc_freed(ptr %ld1780)
  %freed_b1800 = icmp ne i64 %freed1799, 0
  br i1 %freed_b1800, label %br_unique448, label %br_shared449
br_shared449:
  call void @march_incrc(ptr %fv1798)
  call void @march_incrc(ptr %fv1796)
  br label %br_body450
br_unique448:
  br label %br_body450
br_body450:
  %ld1801 = load ptr, ptr %$f967.addr
  %res_slot1802 = alloca ptr
  %tgp1803 = getelementptr i8, ptr %ld1801, i64 8
  %tag1804 = load i32, ptr %tgp1803, align 4
  switch i32 %tag1804, label %case_default452 [
      i32 0, label %case_br453
  ]
case_br453:
  %fp1805 = getelementptr i8, ptr %ld1801, i64 16
  %fv1806 = load ptr, ptr %fp1805, align 8
  %$f969.addr = alloca ptr
  store ptr %fv1806, ptr %$f969.addr
  %fp1807 = getelementptr i8, ptr %ld1801, i64 24
  %fv1808 = load ptr, ptr %fp1807, align 8
  %$f970.addr = alloca ptr
  store ptr %fv1808, ptr %$f970.addr
  %freed1809 = call i64 @march_decrc_freed(ptr %ld1801)
  %freed_b1810 = icmp ne i64 %freed1809, 0
  br i1 %freed_b1810, label %br_unique454, label %br_shared455
br_shared455:
  call void @march_incrc(ptr %fv1808)
  call void @march_incrc(ptr %fv1806)
  br label %br_body456
br_unique454:
  br label %br_body456
br_body456:
  %ld1811 = load ptr, ptr %$f968.addr
  %rest.addr = alloca ptr
  store ptr %ld1811, ptr %rest.addr
  %ld1812 = load ptr, ptr %$f970.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1812, ptr %step_fn.addr
  %ld1813 = load ptr, ptr %step_fn.addr
  %fp1814 = getelementptr i8, ptr %ld1813, i64 16
  %fv1815 = load ptr, ptr %fp1814, align 8
  %ld1816 = load ptr, ptr %req.addr
  %ld1817 = load ptr, ptr %resp.addr
  %cr1818 = call ptr (ptr, ptr, ptr) %fv1815(ptr %ld1813, ptr %ld1816, ptr %ld1817)
  %$t962.addr = alloca ptr
  store ptr %cr1818, ptr %$t962.addr
  %ld1819 = load ptr, ptr %$t962.addr
  %res_slot1820 = alloca ptr
  %tgp1821 = getelementptr i8, ptr %ld1819, i64 8
  %tag1822 = load i32, ptr %tgp1821, align 4
  switch i32 %tag1822, label %case_default458 [
      i32 1, label %case_br459
      i32 0, label %case_br460
  ]
case_br459:
  %fp1823 = getelementptr i8, ptr %ld1819, i64 16
  %fv1824 = load ptr, ptr %fp1823, align 8
  %$f963.addr = alloca ptr
  store ptr %fv1824, ptr %$f963.addr
  %ld1825 = load ptr, ptr %$f963.addr
  %e.addr = alloca ptr
  store ptr %ld1825, ptr %e.addr
  %ld1826 = load ptr, ptr %$t962.addr
  %ld1827 = load ptr, ptr %e.addr
  %rc1828 = load i64, ptr %ld1826, align 8
  %uniq1829 = icmp eq i64 %rc1828, 1
  %fbip_slot1830 = alloca ptr
  br i1 %uniq1829, label %fbip_reuse461, label %fbip_fresh462
fbip_reuse461:
  %tgp1831 = getelementptr i8, ptr %ld1826, i64 8
  store i32 1, ptr %tgp1831, align 4
  %fp1832 = getelementptr i8, ptr %ld1826, i64 16
  store ptr %ld1827, ptr %fp1832, align 8
  store ptr %ld1826, ptr %fbip_slot1830
  br label %fbip_merge463
fbip_fresh462:
  call void @march_decrc(ptr %ld1826)
  %hp1833 = call ptr @march_alloc(i64 24)
  %tgp1834 = getelementptr i8, ptr %hp1833, i64 8
  store i32 1, ptr %tgp1834, align 4
  %fp1835 = getelementptr i8, ptr %hp1833, i64 16
  store ptr %ld1827, ptr %fp1835, align 8
  store ptr %hp1833, ptr %fbip_slot1830
  br label %fbip_merge463
fbip_merge463:
  %fbip_r1836 = load ptr, ptr %fbip_slot1830
  store ptr %fbip_r1836, ptr %res_slot1820
  br label %case_merge457
case_br460:
  %fp1837 = getelementptr i8, ptr %ld1819, i64 16
  %fv1838 = load ptr, ptr %fp1837, align 8
  %$f964.addr = alloca ptr
  store ptr %fv1838, ptr %$f964.addr
  %freed1839 = call i64 @march_decrc_freed(ptr %ld1819)
  %freed_b1840 = icmp ne i64 %freed1839, 0
  br i1 %freed_b1840, label %br_unique464, label %br_shared465
br_shared465:
  call void @march_incrc(ptr %fv1838)
  br label %br_body466
br_unique464:
  br label %br_body466
br_body466:
  %ld1841 = load ptr, ptr %$f964.addr
  %res_slot1842 = alloca ptr
  %tgp1843 = getelementptr i8, ptr %ld1841, i64 8
  %tag1844 = load i32, ptr %tgp1843, align 4
  switch i32 %tag1844, label %case_default468 [
      i32 0, label %case_br469
  ]
case_br469:
  %fp1845 = getelementptr i8, ptr %ld1841, i64 16
  %fv1846 = load ptr, ptr %fp1845, align 8
  %$f965.addr = alloca ptr
  store ptr %fv1846, ptr %$f965.addr
  %fp1847 = getelementptr i8, ptr %ld1841, i64 24
  %fv1848 = load ptr, ptr %fp1847, align 8
  %$f966.addr = alloca ptr
  store ptr %fv1848, ptr %$f966.addr
  %freed1849 = call i64 @march_decrc_freed(ptr %ld1841)
  %freed_b1850 = icmp ne i64 %freed1849, 0
  br i1 %freed_b1850, label %br_unique470, label %br_shared471
br_shared471:
  call void @march_incrc(ptr %fv1848)
  call void @march_incrc(ptr %fv1846)
  br label %br_body472
br_unique470:
  br label %br_body472
br_body472:
  %ld1851 = load ptr, ptr %$f966.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1851, ptr %new_resp.addr
  %ld1852 = load ptr, ptr %$f965.addr
  %new_req.addr = alloca ptr
  store ptr %ld1852, ptr %new_req.addr
  %ld1853 = load ptr, ptr %rest.addr
  %ld1854 = load ptr, ptr %new_req.addr
  %ld1855 = load ptr, ptr %new_resp.addr
  %cr1856 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3284(ptr %ld1853, ptr %ld1854, ptr %ld1855)
  store ptr %cr1856, ptr %res_slot1842
  br label %case_merge467
case_default468:
  unreachable
case_merge467:
  %case_r1857 = load ptr, ptr %res_slot1842
  store ptr %case_r1857, ptr %res_slot1820
  br label %case_merge457
case_default458:
  unreachable
case_merge457:
  %case_r1858 = load ptr, ptr %res_slot1820
  store ptr %case_r1858, ptr %res_slot1802
  br label %case_merge451
case_default452:
  unreachable
case_merge451:
  %case_r1859 = load ptr, ptr %res_slot1802
  store ptr %case_r1859, ptr %res_slot1781
  br label %case_merge444
case_default445:
  unreachable
case_merge444:
  %case_r1860 = load ptr, ptr %res_slot1781
  ret ptr %case_r1860
}

define ptr @HttpClient.handle_redirects$Request_String$Response_V__3284$Int$Int(ptr %req.arg, ptr %resp.arg, i64 %max.arg, i64 %count.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %max.addr = alloca i64
  store i64 %max.arg, ptr %max.addr
  %count.addr = alloca i64
  store i64 %count.arg, ptr %count.addr
  %ld1861 = load i64, ptr %max.addr
  %cmp1862 = icmp eq i64 %ld1861, 0
  %ar1863 = zext i1 %cmp1862 to i64
  %$t994.addr = alloca i64
  store i64 %ar1863, ptr %$t994.addr
  %ld1864 = load i64, ptr %$t994.addr
  %res_slot1865 = alloca ptr
  %bi1866 = trunc i64 %ld1864 to i1
  br i1 %bi1866, label %case_br475, label %case_default474
case_br475:
  %hp1867 = call ptr @march_alloc(i64 24)
  %tgp1868 = getelementptr i8, ptr %hp1867, i64 8
  store i32 0, ptr %tgp1868, align 4
  %ld1869 = load ptr, ptr %resp.addr
  %fp1870 = getelementptr i8, ptr %hp1867, i64 16
  store ptr %ld1869, ptr %fp1870, align 8
  store ptr %hp1867, ptr %res_slot1865
  br label %case_merge473
case_default474:
  %ld1871 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1871)
  %ld1872 = load ptr, ptr %resp.addr
  %cr1873 = call i64 @Http.response_is_redirect$Response_V__3284(ptr %ld1872)
  %$t995.addr = alloca i64
  store i64 %cr1873, ptr %$t995.addr
  %ld1874 = load i64, ptr %$t995.addr
  %ar1875 = xor i64 %ld1874, 1
  %$t996.addr = alloca i64
  store i64 %ar1875, ptr %$t996.addr
  %ld1876 = load i64, ptr %$t996.addr
  %res_slot1877 = alloca ptr
  %bi1878 = trunc i64 %ld1876 to i1
  br i1 %bi1878, label %case_br478, label %case_default477
case_br478:
  %hp1879 = call ptr @march_alloc(i64 24)
  %tgp1880 = getelementptr i8, ptr %hp1879, i64 8
  store i32 0, ptr %tgp1880, align 4
  %ld1881 = load ptr, ptr %resp.addr
  %fp1882 = getelementptr i8, ptr %hp1879, i64 16
  store ptr %ld1881, ptr %fp1882, align 8
  store ptr %hp1879, ptr %res_slot1877
  br label %case_merge476
case_default477:
  %ld1883 = load i64, ptr %count.addr
  %ld1884 = load i64, ptr %max.addr
  %cmp1885 = icmp sge i64 %ld1883, %ld1884
  %ar1886 = zext i1 %cmp1885 to i64
  %$t997.addr = alloca i64
  store i64 %ar1886, ptr %$t997.addr
  %ld1887 = load i64, ptr %$t997.addr
  %res_slot1888 = alloca ptr
  %bi1889 = trunc i64 %ld1887 to i1
  br i1 %bi1889, label %case_br481, label %case_default480
case_br481:
  %hp1890 = call ptr @march_alloc(i64 24)
  %tgp1891 = getelementptr i8, ptr %hp1890, i64 8
  store i32 2, ptr %tgp1891, align 4
  %ld1892 = load i64, ptr %count.addr
  %fp1893 = getelementptr i8, ptr %hp1890, i64 16
  store i64 %ld1892, ptr %fp1893, align 8
  %$t998.addr = alloca ptr
  store ptr %hp1890, ptr %$t998.addr
  %hp1894 = call ptr @march_alloc(i64 24)
  %tgp1895 = getelementptr i8, ptr %hp1894, i64 8
  store i32 1, ptr %tgp1895, align 4
  %ld1896 = load ptr, ptr %$t998.addr
  %fp1897 = getelementptr i8, ptr %hp1894, i64 16
  store ptr %ld1896, ptr %fp1897, align 8
  store ptr %hp1894, ptr %res_slot1888
  br label %case_merge479
case_default480:
  %ld1898 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1898)
  %ld1899 = load ptr, ptr %resp.addr
  %sl1900 = call ptr @march_string_lit(ptr @.str42, i64 8)
  %cr1901 = call ptr @Http.get_header$Response_V__3284$String(ptr %ld1899, ptr %sl1900)
  %$t999.addr = alloca ptr
  store ptr %cr1901, ptr %$t999.addr
  %ld1902 = load ptr, ptr %$t999.addr
  %res_slot1903 = alloca ptr
  %tgp1904 = getelementptr i8, ptr %ld1902, i64 8
  %tag1905 = load i32, ptr %tgp1904, align 4
  switch i32 %tag1905, label %case_default483 [
      i32 0, label %case_br484
      i32 1, label %case_br485
  ]
case_br484:
  %ld1906 = load ptr, ptr %$t999.addr
  call void @march_decrc(ptr %ld1906)
  %hp1907 = call ptr @march_alloc(i64 24)
  %tgp1908 = getelementptr i8, ptr %hp1907, i64 8
  store i32 0, ptr %tgp1908, align 4
  %ld1909 = load ptr, ptr %resp.addr
  %fp1910 = getelementptr i8, ptr %hp1907, i64 16
  store ptr %ld1909, ptr %fp1910, align 8
  store ptr %hp1907, ptr %res_slot1903
  br label %case_merge482
case_br485:
  %fp1911 = getelementptr i8, ptr %ld1902, i64 16
  %fv1912 = load ptr, ptr %fp1911, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv1912, ptr %$f1018.addr
  %freed1913 = call i64 @march_decrc_freed(ptr %ld1902)
  %freed_b1914 = icmp ne i64 %freed1913, 0
  br i1 %freed_b1914, label %br_unique486, label %br_shared487
br_shared487:
  call void @march_incrc(ptr %fv1912)
  br label %br_body488
br_unique486:
  br label %br_body488
br_body488:
  %ld1915 = load ptr, ptr %$f1018.addr
  %location.addr = alloca ptr
  store ptr %ld1915, ptr %location.addr
  %ld1916 = load ptr, ptr %location.addr
  call void @march_incrc(ptr %ld1916)
  %ld1917 = load ptr, ptr %location.addr
  %cr1918 = call ptr @Http.parse_url(ptr %ld1917)
  %$t1000.addr = alloca ptr
  store ptr %cr1918, ptr %$t1000.addr
  %ld1919 = load ptr, ptr %$t1000.addr
  %res_slot1920 = alloca ptr
  %tgp1921 = getelementptr i8, ptr %ld1919, i64 8
  %tag1922 = load i32, ptr %tgp1921, align 4
  switch i32 %tag1922, label %case_default490 [
      i32 0, label %case_br491
      i32 1, label %case_br492
  ]
case_br491:
  %fp1923 = getelementptr i8, ptr %ld1919, i64 16
  %fv1924 = load ptr, ptr %fp1923, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv1924, ptr %$f1011.addr
  %freed1925 = call i64 @march_decrc_freed(ptr %ld1919)
  %freed_b1926 = icmp ne i64 %freed1925, 0
  br i1 %freed_b1926, label %br_unique493, label %br_shared494
br_shared494:
  call void @march_incrc(ptr %fv1924)
  br label %br_body495
br_unique493:
  br label %br_body495
br_body495:
  %ld1927 = load ptr, ptr %$f1011.addr
  %parsed.addr = alloca ptr
  store ptr %ld1927, ptr %parsed.addr
  %hp1928 = call ptr @march_alloc(i64 16)
  %tgp1929 = getelementptr i8, ptr %hp1928, i64 8
  store i32 0, ptr %tgp1929, align 4
  %$t1001.addr = alloca ptr
  store ptr %hp1928, ptr %$t1001.addr
  %ld1930 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1930)
  %ld1931 = load ptr, ptr %parsed.addr
  %cr1932 = call ptr @Http.scheme$Request_T_(ptr %ld1931)
  %$t1002.addr = alloca ptr
  store ptr %cr1932, ptr %$t1002.addr
  %ld1933 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1933)
  %ld1934 = load ptr, ptr %parsed.addr
  %cr1935 = call ptr @Http.host$Request_T_(ptr %ld1934)
  %$t1003.addr = alloca ptr
  store ptr %cr1935, ptr %$t1003.addr
  %ld1936 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1936)
  %ld1937 = load ptr, ptr %parsed.addr
  %cr1938 = call ptr @Http.port$Request_T_(ptr %ld1937)
  %$t1004.addr = alloca ptr
  store ptr %cr1938, ptr %$t1004.addr
  %ld1939 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1939)
  %ld1940 = load ptr, ptr %parsed.addr
  %cr1941 = call ptr @Http.path$Request_T_(ptr %ld1940)
  %$t1005.addr = alloca ptr
  store ptr %cr1941, ptr %$t1005.addr
  %ld1942 = load ptr, ptr %parsed.addr
  %cr1943 = call ptr @Http.query$Request_T_(ptr %ld1942)
  %$t1006.addr = alloca ptr
  store ptr %cr1943, ptr %$t1006.addr
  %ld1944 = load ptr, ptr %req.addr
  %cr1945 = call ptr @Http.headers$Request_String(ptr %ld1944)
  %$t1007.addr = alloca ptr
  store ptr %cr1945, ptr %$t1007.addr
  %hp1946 = call ptr @march_alloc(i64 80)
  %tgp1947 = getelementptr i8, ptr %hp1946, i64 8
  store i32 0, ptr %tgp1947, align 4
  %ld1948 = load ptr, ptr %$t1001.addr
  %fp1949 = getelementptr i8, ptr %hp1946, i64 16
  store ptr %ld1948, ptr %fp1949, align 8
  %ld1950 = load ptr, ptr %$t1002.addr
  %fp1951 = getelementptr i8, ptr %hp1946, i64 24
  store ptr %ld1950, ptr %fp1951, align 8
  %ld1952 = load ptr, ptr %$t1003.addr
  %fp1953 = getelementptr i8, ptr %hp1946, i64 32
  store ptr %ld1952, ptr %fp1953, align 8
  %ld1954 = load ptr, ptr %$t1004.addr
  %fp1955 = getelementptr i8, ptr %hp1946, i64 40
  store ptr %ld1954, ptr %fp1955, align 8
  %ld1956 = load ptr, ptr %$t1005.addr
  %fp1957 = getelementptr i8, ptr %hp1946, i64 48
  store ptr %ld1956, ptr %fp1957, align 8
  %ld1958 = load ptr, ptr %$t1006.addr
  %fp1959 = getelementptr i8, ptr %hp1946, i64 56
  store ptr %ld1958, ptr %fp1959, align 8
  %ld1960 = load ptr, ptr %$t1007.addr
  %fp1961 = getelementptr i8, ptr %hp1946, i64 64
  store ptr %ld1960, ptr %fp1961, align 8
  %sl1962 = call ptr @march_string_lit(ptr @.str43, i64 0)
  %fp1963 = getelementptr i8, ptr %hp1946, i64 72
  store ptr %sl1962, ptr %fp1963, align 8
  store ptr %hp1946, ptr %res_slot1920
  br label %case_merge489
case_br492:
  %fp1964 = getelementptr i8, ptr %ld1919, i64 16
  %fv1965 = load ptr, ptr %fp1964, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv1965, ptr %$f1012.addr
  %freed1966 = call i64 @march_decrc_freed(ptr %ld1919)
  %freed_b1967 = icmp ne i64 %freed1966, 0
  br i1 %freed_b1967, label %br_unique496, label %br_shared497
br_shared497:
  call void @march_incrc(ptr %fv1965)
  br label %br_body498
br_unique496:
  br label %br_body498
br_body498:
  %ld1968 = load ptr, ptr %req.addr
  %ld1969 = load ptr, ptr %location.addr
  %cr1970 = call ptr @Http.set_path$Request_String$String(ptr %ld1968, ptr %ld1969)
  %$t1008.addr = alloca ptr
  store ptr %cr1970, ptr %$t1008.addr
  %hp1971 = call ptr @march_alloc(i64 16)
  %tgp1972 = getelementptr i8, ptr %hp1971, i64 8
  store i32 0, ptr %tgp1972, align 4
  %$t1009.addr = alloca ptr
  store ptr %hp1971, ptr %$t1009.addr
  %ld1973 = load ptr, ptr %$t1008.addr
  %ld1974 = load ptr, ptr %$t1009.addr
  %cr1975 = call ptr @Http.set_method$Request_String$Method(ptr %ld1973, ptr %ld1974)
  %$t1010.addr = alloca ptr
  store ptr %cr1975, ptr %$t1010.addr
  %ld1976 = load ptr, ptr %$t1010.addr
  %sl1977 = call ptr @march_string_lit(ptr @.str44, i64 0)
  %cr1978 = call ptr @Http.set_body$Request_String$String(ptr %ld1976, ptr %sl1977)
  store ptr %cr1978, ptr %res_slot1920
  br label %case_merge489
case_default490:
  unreachable
case_merge489:
  %case_r1979 = load ptr, ptr %res_slot1920
  %redirect_req.addr = alloca ptr
  store ptr %case_r1979, ptr %redirect_req.addr
  %ld1980 = load ptr, ptr %redirect_req.addr
  call void @march_incrc(ptr %ld1980)
  %ld1981 = load ptr, ptr %redirect_req.addr
  %cr1982 = call ptr @HttpTransport.request$Request_String(ptr %ld1981)
  %$t1013.addr = alloca ptr
  store ptr %cr1982, ptr %$t1013.addr
  %ld1983 = load ptr, ptr %$t1013.addr
  %res_slot1984 = alloca ptr
  %tgp1985 = getelementptr i8, ptr %ld1983, i64 8
  %tag1986 = load i32, ptr %tgp1985, align 4
  switch i32 %tag1986, label %case_default500 [
      i32 1, label %case_br501
      i32 0, label %case_br502
  ]
case_br501:
  %fp1987 = getelementptr i8, ptr %ld1983, i64 16
  %fv1988 = load ptr, ptr %fp1987, align 8
  %$f1016.addr = alloca ptr
  store ptr %fv1988, ptr %$f1016.addr
  %ld1989 = load ptr, ptr %$f1016.addr
  %e.addr = alloca ptr
  store ptr %ld1989, ptr %e.addr
  %hp1990 = call ptr @march_alloc(i64 24)
  %tgp1991 = getelementptr i8, ptr %hp1990, i64 8
  store i32 0, ptr %tgp1991, align 4
  %ld1992 = load ptr, ptr %e.addr
  %fp1993 = getelementptr i8, ptr %hp1990, i64 16
  store ptr %ld1992, ptr %fp1993, align 8
  %$t1014.addr = alloca ptr
  store ptr %hp1990, ptr %$t1014.addr
  %ld1994 = load ptr, ptr %$t1013.addr
  %ld1995 = load ptr, ptr %$t1014.addr
  %rc1996 = load i64, ptr %ld1994, align 8
  %uniq1997 = icmp eq i64 %rc1996, 1
  %fbip_slot1998 = alloca ptr
  br i1 %uniq1997, label %fbip_reuse503, label %fbip_fresh504
fbip_reuse503:
  %tgp1999 = getelementptr i8, ptr %ld1994, i64 8
  store i32 1, ptr %tgp1999, align 4
  %fp2000 = getelementptr i8, ptr %ld1994, i64 16
  store ptr %ld1995, ptr %fp2000, align 8
  store ptr %ld1994, ptr %fbip_slot1998
  br label %fbip_merge505
fbip_fresh504:
  call void @march_decrc(ptr %ld1994)
  %hp2001 = call ptr @march_alloc(i64 24)
  %tgp2002 = getelementptr i8, ptr %hp2001, i64 8
  store i32 1, ptr %tgp2002, align 4
  %fp2003 = getelementptr i8, ptr %hp2001, i64 16
  store ptr %ld1995, ptr %fp2003, align 8
  store ptr %hp2001, ptr %fbip_slot1998
  br label %fbip_merge505
fbip_merge505:
  %fbip_r2004 = load ptr, ptr %fbip_slot1998
  store ptr %fbip_r2004, ptr %res_slot1984
  br label %case_merge499
case_br502:
  %fp2005 = getelementptr i8, ptr %ld1983, i64 16
  %fv2006 = load ptr, ptr %fp2005, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv2006, ptr %$f1017.addr
  %freed2007 = call i64 @march_decrc_freed(ptr %ld1983)
  %freed_b2008 = icmp ne i64 %freed2007, 0
  br i1 %freed_b2008, label %br_unique506, label %br_shared507
br_shared507:
  call void @march_incrc(ptr %fv2006)
  br label %br_body508
br_unique506:
  br label %br_body508
br_body508:
  %ld2009 = load ptr, ptr %$f1017.addr
  %new_resp.addr = alloca ptr
  store ptr %ld2009, ptr %new_resp.addr
  %ld2010 = load i64, ptr %count.addr
  %ar2011 = add i64 %ld2010, 1
  %$t1015.addr = alloca i64
  store i64 %ar2011, ptr %$t1015.addr
  %ld2012 = load ptr, ptr %redirect_req.addr
  %ld2013 = load ptr, ptr %new_resp.addr
  %ld2014 = load i64, ptr %max.addr
  %ld2015 = load i64, ptr %$t1015.addr
  %cr2016 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3284$Int$Int(ptr %ld2012, ptr %ld2013, i64 %ld2014, i64 %ld2015)
  store ptr %cr2016, ptr %res_slot1984
  br label %case_merge499
case_default500:
  unreachable
case_merge499:
  %case_r2017 = load ptr, ptr %res_slot1984
  store ptr %case_r2017, ptr %res_slot1903
  br label %case_merge482
case_default483:
  unreachable
case_merge482:
  %case_r2018 = load ptr, ptr %res_slot1903
  store ptr %case_r2018, ptr %res_slot1888
  br label %case_merge479
case_merge479:
  %case_r2019 = load ptr, ptr %res_slot1888
  store ptr %case_r2019, ptr %res_slot1877
  br label %case_merge476
case_merge476:
  %case_r2020 = load ptr, ptr %res_slot1877
  store ptr %case_r2020, ptr %res_slot1865
  br label %case_merge473
case_merge473:
  %case_r2021 = load ptr, ptr %res_slot1865
  ret ptr %case_r2021
}

define ptr @HttpClient.transport_keepalive$V__3282$Request_String$Int(ptr %fd.arg, ptr %req.arg, i64 %retries_left.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld2022 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2022)
  %ld2023 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2023)
  %ld2024 = load ptr, ptr %fd.addr
  %ld2025 = load ptr, ptr %req.addr
  %cr2026 = call ptr @HttpTransport.request_on$V__3282$Request_String(ptr %ld2024, ptr %ld2025)
  %$t987.addr = alloca ptr
  store ptr %cr2026, ptr %$t987.addr
  %ld2027 = load ptr, ptr %$t987.addr
  %res_slot2028 = alloca ptr
  %tgp2029 = getelementptr i8, ptr %ld2027, i64 8
  %tag2030 = load i32, ptr %tgp2029, align 4
  switch i32 %tag2030, label %case_default510 [
      i32 0, label %case_br511
      i32 1, label %case_br512
  ]
case_br511:
  %fp2031 = getelementptr i8, ptr %ld2027, i64 16
  %fv2032 = load ptr, ptr %fp2031, align 8
  %$f992.addr = alloca ptr
  store ptr %fv2032, ptr %$f992.addr
  %ld2033 = load ptr, ptr %$f992.addr
  %resp.addr = alloca ptr
  store ptr %ld2033, ptr %resp.addr
  %hp2034 = call ptr @march_alloc(i64 32)
  %tgp2035 = getelementptr i8, ptr %hp2034, i64 8
  store i32 0, ptr %tgp2035, align 4
  %ld2036 = load ptr, ptr %fd.addr
  %fp2037 = getelementptr i8, ptr %hp2034, i64 16
  store ptr %ld2036, ptr %fp2037, align 8
  %ld2038 = load ptr, ptr %resp.addr
  %fp2039 = getelementptr i8, ptr %hp2034, i64 24
  store ptr %ld2038, ptr %fp2039, align 8
  %$t988.addr = alloca ptr
  store ptr %hp2034, ptr %$t988.addr
  %ld2040 = load ptr, ptr %$t987.addr
  %ld2041 = load ptr, ptr %$t988.addr
  %rc2042 = load i64, ptr %ld2040, align 8
  %uniq2043 = icmp eq i64 %rc2042, 1
  %fbip_slot2044 = alloca ptr
  br i1 %uniq2043, label %fbip_reuse513, label %fbip_fresh514
fbip_reuse513:
  %tgp2045 = getelementptr i8, ptr %ld2040, i64 8
  store i32 0, ptr %tgp2045, align 4
  %fp2046 = getelementptr i8, ptr %ld2040, i64 16
  store ptr %ld2041, ptr %fp2046, align 8
  store ptr %ld2040, ptr %fbip_slot2044
  br label %fbip_merge515
fbip_fresh514:
  call void @march_decrc(ptr %ld2040)
  %hp2047 = call ptr @march_alloc(i64 24)
  %tgp2048 = getelementptr i8, ptr %hp2047, i64 8
  store i32 0, ptr %tgp2048, align 4
  %fp2049 = getelementptr i8, ptr %hp2047, i64 16
  store ptr %ld2041, ptr %fp2049, align 8
  store ptr %hp2047, ptr %fbip_slot2044
  br label %fbip_merge515
fbip_merge515:
  %fbip_r2050 = load ptr, ptr %fbip_slot2044
  store ptr %fbip_r2050, ptr %res_slot2028
  br label %case_merge509
case_br512:
  %fp2051 = getelementptr i8, ptr %ld2027, i64 16
  %fv2052 = load ptr, ptr %fp2051, align 8
  %$f993.addr = alloca ptr
  store ptr %fv2052, ptr %$f993.addr
  %freed2053 = call i64 @march_decrc_freed(ptr %ld2027)
  %freed_b2054 = icmp ne i64 %freed2053, 0
  br i1 %freed_b2054, label %br_unique516, label %br_shared517
br_shared517:
  call void @march_incrc(ptr %fv2052)
  br label %br_body518
br_unique516:
  br label %br_body518
br_body518:
  %ld2055 = load ptr, ptr %tcp_close.addr
  %fp2056 = getelementptr i8, ptr %ld2055, i64 16
  %fv2057 = load ptr, ptr %fp2056, align 8
  %ld2058 = load ptr, ptr %fd.addr
  %cr2059 = call ptr (ptr, ptr) %fv2057(ptr %ld2055, ptr %ld2058)
  %ld2060 = load i64, ptr %retries_left.addr
  %cmp2061 = icmp sgt i64 %ld2060, 0
  %ar2062 = zext i1 %cmp2061 to i64
  %$t989.addr = alloca i64
  store i64 %ar2062, ptr %$t989.addr
  %ld2063 = load i64, ptr %$t989.addr
  %res_slot2064 = alloca ptr
  %bi2065 = trunc i64 %ld2063 to i1
  br i1 %bi2065, label %case_br521, label %case_default520
case_br521:
  %ld2066 = load i64, ptr %retries_left.addr
  %ar2067 = sub i64 %ld2066, 1
  %$t990.addr = alloca i64
  store i64 %ar2067, ptr %$t990.addr
  %ld2068 = load ptr, ptr %req.addr
  %ld2069 = load i64, ptr %$t990.addr
  %cr2070 = call ptr @HttpClient.reconnect_and_retry(ptr %ld2068, i64 %ld2069)
  store ptr %cr2070, ptr %res_slot2064
  br label %case_merge519
case_default520:
  %hp2071 = call ptr @march_alloc(i64 16)
  %tgp2072 = getelementptr i8, ptr %hp2071, i64 8
  store i32 0, ptr %tgp2072, align 4
  %$t991.addr = alloca ptr
  store ptr %hp2071, ptr %$t991.addr
  %hp2073 = call ptr @march_alloc(i64 24)
  %tgp2074 = getelementptr i8, ptr %hp2073, i64 8
  store i32 1, ptr %tgp2074, align 4
  %ld2075 = load ptr, ptr %$t991.addr
  %fp2076 = getelementptr i8, ptr %hp2073, i64 16
  store ptr %ld2075, ptr %fp2076, align 8
  store ptr %hp2073, ptr %res_slot2064
  br label %case_merge519
case_merge519:
  %case_r2077 = load ptr, ptr %res_slot2064
  store ptr %case_r2077, ptr %res_slot2028
  br label %case_merge509
case_default510:
  unreachable
case_merge509:
  %case_r2078 = load ptr, ptr %res_slot2028
  ret ptr %case_r2078
}

define ptr @Http.port$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2079 = load ptr, ptr %req.addr
  %res_slot2080 = alloca ptr
  %tgp2081 = getelementptr i8, ptr %ld2079, i64 8
  %tag2082 = load i32, ptr %tgp2081, align 4
  switch i32 %tag2082, label %case_default523 [
      i32 0, label %case_br524
  ]
case_br524:
  %fp2083 = getelementptr i8, ptr %ld2079, i64 16
  %fv2084 = load ptr, ptr %fp2083, align 8
  %$f567.addr = alloca ptr
  store ptr %fv2084, ptr %$f567.addr
  %fp2085 = getelementptr i8, ptr %ld2079, i64 24
  %fv2086 = load ptr, ptr %fp2085, align 8
  %$f568.addr = alloca ptr
  store ptr %fv2086, ptr %$f568.addr
  %fp2087 = getelementptr i8, ptr %ld2079, i64 32
  %fv2088 = load ptr, ptr %fp2087, align 8
  %$f569.addr = alloca ptr
  store ptr %fv2088, ptr %$f569.addr
  %fp2089 = getelementptr i8, ptr %ld2079, i64 40
  %fv2090 = load ptr, ptr %fp2089, align 8
  %$f570.addr = alloca ptr
  store ptr %fv2090, ptr %$f570.addr
  %fp2091 = getelementptr i8, ptr %ld2079, i64 48
  %fv2092 = load ptr, ptr %fp2091, align 8
  %$f571.addr = alloca ptr
  store ptr %fv2092, ptr %$f571.addr
  %fp2093 = getelementptr i8, ptr %ld2079, i64 56
  %fv2094 = load ptr, ptr %fp2093, align 8
  %$f572.addr = alloca ptr
  store ptr %fv2094, ptr %$f572.addr
  %fp2095 = getelementptr i8, ptr %ld2079, i64 64
  %fv2096 = load ptr, ptr %fp2095, align 8
  %$f573.addr = alloca ptr
  store ptr %fv2096, ptr %$f573.addr
  %fp2097 = getelementptr i8, ptr %ld2079, i64 72
  %fv2098 = load ptr, ptr %fp2097, align 8
  %$f574.addr = alloca ptr
  store ptr %fv2098, ptr %$f574.addr
  %freed2099 = call i64 @march_decrc_freed(ptr %ld2079)
  %freed_b2100 = icmp ne i64 %freed2099, 0
  br i1 %freed_b2100, label %br_unique525, label %br_shared526
br_shared526:
  call void @march_incrc(ptr %fv2098)
  call void @march_incrc(ptr %fv2096)
  call void @march_incrc(ptr %fv2094)
  call void @march_incrc(ptr %fv2092)
  call void @march_incrc(ptr %fv2090)
  call void @march_incrc(ptr %fv2088)
  call void @march_incrc(ptr %fv2086)
  call void @march_incrc(ptr %fv2084)
  br label %br_body527
br_unique525:
  br label %br_body527
br_body527:
  %ld2101 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld2101, ptr %p.addr
  %ld2102 = load ptr, ptr %p.addr
  store ptr %ld2102, ptr %res_slot2080
  br label %case_merge522
case_default523:
  unreachable
case_merge522:
  %case_r2103 = load ptr, ptr %res_slot2080
  ret ptr %case_r2103
}

define ptr @Http.host$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2104 = load ptr, ptr %req.addr
  %res_slot2105 = alloca ptr
  %tgp2106 = getelementptr i8, ptr %ld2104, i64 8
  %tag2107 = load i32, ptr %tgp2106, align 4
  switch i32 %tag2107, label %case_default529 [
      i32 0, label %case_br530
  ]
case_br530:
  %fp2108 = getelementptr i8, ptr %ld2104, i64 16
  %fv2109 = load ptr, ptr %fp2108, align 8
  %$f559.addr = alloca ptr
  store ptr %fv2109, ptr %$f559.addr
  %fp2110 = getelementptr i8, ptr %ld2104, i64 24
  %fv2111 = load ptr, ptr %fp2110, align 8
  %$f560.addr = alloca ptr
  store ptr %fv2111, ptr %$f560.addr
  %fp2112 = getelementptr i8, ptr %ld2104, i64 32
  %fv2113 = load ptr, ptr %fp2112, align 8
  %$f561.addr = alloca ptr
  store ptr %fv2113, ptr %$f561.addr
  %fp2114 = getelementptr i8, ptr %ld2104, i64 40
  %fv2115 = load ptr, ptr %fp2114, align 8
  %$f562.addr = alloca ptr
  store ptr %fv2115, ptr %$f562.addr
  %fp2116 = getelementptr i8, ptr %ld2104, i64 48
  %fv2117 = load ptr, ptr %fp2116, align 8
  %$f563.addr = alloca ptr
  store ptr %fv2117, ptr %$f563.addr
  %fp2118 = getelementptr i8, ptr %ld2104, i64 56
  %fv2119 = load ptr, ptr %fp2118, align 8
  %$f564.addr = alloca ptr
  store ptr %fv2119, ptr %$f564.addr
  %fp2120 = getelementptr i8, ptr %ld2104, i64 64
  %fv2121 = load ptr, ptr %fp2120, align 8
  %$f565.addr = alloca ptr
  store ptr %fv2121, ptr %$f565.addr
  %fp2122 = getelementptr i8, ptr %ld2104, i64 72
  %fv2123 = load ptr, ptr %fp2122, align 8
  %$f566.addr = alloca ptr
  store ptr %fv2123, ptr %$f566.addr
  %freed2124 = call i64 @march_decrc_freed(ptr %ld2104)
  %freed_b2125 = icmp ne i64 %freed2124, 0
  br i1 %freed_b2125, label %br_unique531, label %br_shared532
br_shared532:
  call void @march_incrc(ptr %fv2123)
  call void @march_incrc(ptr %fv2121)
  call void @march_incrc(ptr %fv2119)
  call void @march_incrc(ptr %fv2117)
  call void @march_incrc(ptr %fv2115)
  call void @march_incrc(ptr %fv2113)
  call void @march_incrc(ptr %fv2111)
  call void @march_incrc(ptr %fv2109)
  br label %br_body533
br_unique531:
  br label %br_body533
br_body533:
  %ld2126 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld2126, ptr %h.addr
  %ld2127 = load ptr, ptr %h.addr
  store ptr %ld2127, ptr %res_slot2105
  br label %case_merge528
case_default529:
  unreachable
case_merge528:
  %case_r2128 = load ptr, ptr %res_slot2105
  ret ptr %case_r2128
}

define ptr @HttpTransport.request$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2129 = load ptr, ptr %req.addr
  %sl2130 = call ptr @march_string_lit(ptr @.str45, i64 10)
  %sl2131 = call ptr @march_string_lit(ptr @.str46, i64 5)
  %cr2132 = call ptr @Http.set_header$Request_String$String$String(ptr %ld2129, ptr %sl2130, ptr %sl2131)
  %req_1.addr = alloca ptr
  store ptr %cr2132, ptr %req_1.addr
  %ld2133 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld2133)
  %ld2134 = load ptr, ptr %req_1.addr
  %cr2135 = call ptr @Http.host$Request_V__2816(ptr %ld2134)
  %req_host.addr = alloca ptr
  store ptr %cr2135, ptr %req_host.addr
  %ld2136 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld2136)
  %ld2137 = load ptr, ptr %req_1.addr
  %cr2138 = call ptr @Http.port$Request_V__2819(ptr %ld2137)
  %$t837.addr = alloca ptr
  store ptr %cr2138, ptr %$t837.addr
  %ld2139 = load ptr, ptr %$t837.addr
  %res_slot2140 = alloca ptr
  %tgp2141 = getelementptr i8, ptr %ld2139, i64 8
  %tag2142 = load i32, ptr %tgp2141, align 4
  switch i32 %tag2142, label %case_default535 [
      i32 1, label %case_br536
      i32 0, label %case_br537
  ]
case_br536:
  %fp2143 = getelementptr i8, ptr %ld2139, i64 16
  %fv2144 = load ptr, ptr %fp2143, align 8
  %$f838.addr = alloca ptr
  store ptr %fv2144, ptr %$f838.addr
  %ld2145 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld2145)
  %ld2146 = load ptr, ptr %$f838.addr
  %p.addr = alloca ptr
  store ptr %ld2146, ptr %p.addr
  %ld2147 = load ptr, ptr %p.addr
  store ptr %ld2147, ptr %res_slot2140
  br label %case_merge534
case_br537:
  %ld2148 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld2148)
  %cv2149 = inttoptr i64 80 to ptr
  store ptr %cv2149, ptr %res_slot2140
  br label %case_merge534
case_default535:
  unreachable
case_merge534:
  %case_r2150 = load ptr, ptr %res_slot2140
  %cv2151 = ptrtoint ptr %case_r2150 to i64
  %req_port.addr = alloca i64
  store i64 %cv2151, ptr %req_port.addr
  %ld2152 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld2152)
  %ld2153 = load ptr, ptr %req_1.addr
  %cr2154 = call ptr @Http.method$Request_V__2826(ptr %ld2153)
  %$t839.addr = alloca ptr
  store ptr %cr2154, ptr %$t839.addr
  %ld2155 = load ptr, ptr %$t839.addr
  %cr2156 = call ptr @Http.method_to_string(ptr %ld2155)
  %$t840.addr = alloca ptr
  store ptr %cr2156, ptr %$t840.addr
  %ld2157 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld2157)
  %ld2158 = load ptr, ptr %req_1.addr
  %cr2159 = call ptr @Http.path$Request_V__2828(ptr %ld2158)
  %$t841.addr = alloca ptr
  store ptr %cr2159, ptr %$t841.addr
  %ld2160 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld2160)
  %ld2161 = load ptr, ptr %req_1.addr
  %cr2162 = call ptr @Http.query$Request_V__2830(ptr %ld2161)
  %$t842.addr = alloca ptr
  store ptr %cr2162, ptr %$t842.addr
  %ld2163 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld2163)
  %ld2164 = load ptr, ptr %req_1.addr
  %cr2165 = call ptr @Http.headers$Request_V__2832(ptr %ld2164)
  %$t843.addr = alloca ptr
  store ptr %cr2165, ptr %$t843.addr
  %ld2166 = load ptr, ptr %req_1.addr
  %cr2167 = call ptr @Http.body$Request_V__2834(ptr %ld2166)
  %$t844.addr = alloca ptr
  store ptr %cr2167, ptr %$t844.addr
  %ld2168 = load ptr, ptr %req_host.addr
  call void @march_incrc(ptr %ld2168)
  %ld2169 = load ptr, ptr %http_serialize_request.addr
  %fp2170 = getelementptr i8, ptr %ld2169, i64 16
  %fv2171 = load ptr, ptr %fp2170, align 8
  %ld2172 = load ptr, ptr %$t840.addr
  %ld2173 = load ptr, ptr %req_host.addr
  %ld2174 = load ptr, ptr %$t841.addr
  %ld2175 = load ptr, ptr %$t842.addr
  %ld2176 = load ptr, ptr %$t843.addr
  %ld2177 = load ptr, ptr %$t844.addr
  %cr2178 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv2171(ptr %ld2169, ptr %ld2172, ptr %ld2173, ptr %ld2174, ptr %ld2175, ptr %ld2176, ptr %ld2177)
  %raw_request.addr = alloca ptr
  store ptr %cr2178, ptr %raw_request.addr
  %ld2179 = load ptr, ptr %tcp_connect.addr
  %fp2180 = getelementptr i8, ptr %ld2179, i64 16
  %fv2181 = load ptr, ptr %fp2180, align 8
  %ld2182 = load ptr, ptr %req_host.addr
  %ld2183 = load i64, ptr %req_port.addr
  %cv2184 = inttoptr i64 %ld2183 to ptr
  %cr2185 = call ptr (ptr, ptr, ptr) %fv2181(ptr %ld2179, ptr %ld2182, ptr %cv2184)
  %$t845.addr = alloca ptr
  store ptr %cr2185, ptr %$t845.addr
  %ld2186 = load ptr, ptr %$t845.addr
  %res_slot2187 = alloca ptr
  %tgp2188 = getelementptr i8, ptr %ld2186, i64 8
  %tag2189 = load i32, ptr %tgp2188, align 4
  switch i32 %tag2189, label %case_default539 [
      i32 0, label %case_br540
      i32 0, label %case_br541
  ]
case_br540:
  %fp2190 = getelementptr i8, ptr %ld2186, i64 16
  %fv2191 = load ptr, ptr %fp2190, align 8
  %$f864.addr = alloca ptr
  store ptr %fv2191, ptr %$f864.addr
  %freed2192 = call i64 @march_decrc_freed(ptr %ld2186)
  %freed_b2193 = icmp ne i64 %freed2192, 0
  br i1 %freed_b2193, label %br_unique542, label %br_shared543
br_shared543:
  call void @march_incrc(ptr %fv2191)
  br label %br_body544
br_unique542:
  br label %br_body544
br_body544:
  %ld2194 = load ptr, ptr %$f864.addr
  %msg.addr = alloca ptr
  store ptr %ld2194, ptr %msg.addr
  %hp2195 = call ptr @march_alloc(i64 24)
  %tgp2196 = getelementptr i8, ptr %hp2195, i64 8
  store i32 0, ptr %tgp2196, align 4
  %ld2197 = load ptr, ptr %msg.addr
  %fp2198 = getelementptr i8, ptr %hp2195, i64 16
  store ptr %ld2197, ptr %fp2198, align 8
  %$t846.addr = alloca ptr
  store ptr %hp2195, ptr %$t846.addr
  %hp2199 = call ptr @march_alloc(i64 24)
  %tgp2200 = getelementptr i8, ptr %hp2199, i64 8
  store i32 1, ptr %tgp2200, align 4
  %ld2201 = load ptr, ptr %$t846.addr
  %fp2202 = getelementptr i8, ptr %hp2199, i64 16
  store ptr %ld2201, ptr %fp2202, align 8
  store ptr %hp2199, ptr %res_slot2187
  br label %case_merge538
case_br541:
  %fp2203 = getelementptr i8, ptr %ld2186, i64 16
  %fv2204 = load ptr, ptr %fp2203, align 8
  %$f865.addr = alloca ptr
  store ptr %fv2204, ptr %$f865.addr
  %freed2205 = call i64 @march_decrc_freed(ptr %ld2186)
  %freed_b2206 = icmp ne i64 %freed2205, 0
  br i1 %freed_b2206, label %br_unique545, label %br_shared546
br_shared546:
  call void @march_incrc(ptr %fv2204)
  br label %br_body547
br_unique545:
  br label %br_body547
br_body547:
  %ld2207 = load ptr, ptr %$f865.addr
  %fd.addr = alloca ptr
  store ptr %ld2207, ptr %fd.addr
  %ld2208 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2208)
  %ld2209 = load ptr, ptr %tcp_send_all.addr
  %fp2210 = getelementptr i8, ptr %ld2209, i64 16
  %fv2211 = load ptr, ptr %fp2210, align 8
  %ld2212 = load ptr, ptr %fd.addr
  %ld2213 = load ptr, ptr %raw_request.addr
  %cr2214 = call ptr (ptr, ptr, ptr) %fv2211(ptr %ld2209, ptr %ld2212, ptr %ld2213)
  %$t847.addr = alloca ptr
  store ptr %cr2214, ptr %$t847.addr
  %ld2215 = load ptr, ptr %$t847.addr
  %res_slot2216 = alloca ptr
  %tgp2217 = getelementptr i8, ptr %ld2215, i64 8
  %tag2218 = load i32, ptr %tgp2217, align 4
  switch i32 %tag2218, label %case_default549 [
      i32 0, label %case_br550
      i32 0, label %case_br551
  ]
case_br550:
  %fp2219 = getelementptr i8, ptr %ld2215, i64 16
  %fv2220 = load ptr, ptr %fp2219, align 8
  %$f862.addr = alloca ptr
  store ptr %fv2220, ptr %$f862.addr
  %freed2221 = call i64 @march_decrc_freed(ptr %ld2215)
  %freed_b2222 = icmp ne i64 %freed2221, 0
  br i1 %freed_b2222, label %br_unique552, label %br_shared553
br_shared553:
  call void @march_incrc(ptr %fv2220)
  br label %br_body554
br_unique552:
  br label %br_body554
br_body554:
  %ld2223 = load ptr, ptr %$f862.addr
  %msg_1.addr = alloca ptr
  store ptr %ld2223, ptr %msg_1.addr
  %ld2224 = load ptr, ptr %tcp_close.addr
  %fp2225 = getelementptr i8, ptr %ld2224, i64 16
  %fv2226 = load ptr, ptr %fp2225, align 8
  %ld2227 = load ptr, ptr %fd.addr
  %cr2228 = call ptr (ptr, ptr) %fv2226(ptr %ld2224, ptr %ld2227)
  %hp2229 = call ptr @march_alloc(i64 24)
  %tgp2230 = getelementptr i8, ptr %hp2229, i64 8
  store i32 2, ptr %tgp2230, align 4
  %ld2231 = load ptr, ptr %msg_1.addr
  %fp2232 = getelementptr i8, ptr %hp2229, i64 16
  store ptr %ld2231, ptr %fp2232, align 8
  %$t848.addr = alloca ptr
  store ptr %hp2229, ptr %$t848.addr
  %hp2233 = call ptr @march_alloc(i64 24)
  %tgp2234 = getelementptr i8, ptr %hp2233, i64 8
  store i32 1, ptr %tgp2234, align 4
  %ld2235 = load ptr, ptr %$t848.addr
  %fp2236 = getelementptr i8, ptr %hp2233, i64 16
  store ptr %ld2235, ptr %fp2236, align 8
  store ptr %hp2233, ptr %res_slot2216
  br label %case_merge548
case_br551:
  %fp2237 = getelementptr i8, ptr %ld2215, i64 16
  %fv2238 = load ptr, ptr %fp2237, align 8
  %$f863.addr = alloca ptr
  store ptr %fv2238, ptr %$f863.addr
  %freed2239 = call i64 @march_decrc_freed(ptr %ld2215)
  %freed_b2240 = icmp ne i64 %freed2239, 0
  br i1 %freed_b2240, label %br_unique555, label %br_shared556
br_shared556:
  call void @march_incrc(ptr %fv2238)
  br label %br_body557
br_unique555:
  br label %br_body557
br_body557:
  %ld2241 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2241)
  %ld2242 = load ptr, ptr %tcp_recv_all.addr
  %fp2243 = getelementptr i8, ptr %ld2242, i64 16
  %fv2244 = load ptr, ptr %fp2243, align 8
  %ld2245 = load ptr, ptr %fd.addr
  %cv2246 = inttoptr i64 1048576 to ptr
  %cv2247 = inttoptr i64 30000 to ptr
  %cr2248 = call ptr (ptr, ptr, ptr, ptr) %fv2244(ptr %ld2242, ptr %ld2245, ptr %cv2246, ptr %cv2247)
  %$t849.addr = alloca ptr
  store ptr %cr2248, ptr %$t849.addr
  %ld2249 = load ptr, ptr %$t849.addr
  %res_slot2250 = alloca ptr
  %tgp2251 = getelementptr i8, ptr %ld2249, i64 8
  %tag2252 = load i32, ptr %tgp2251, align 4
  switch i32 %tag2252, label %case_default559 [
      i32 0, label %case_br560
      i32 0, label %case_br561
  ]
case_br560:
  %fp2253 = getelementptr i8, ptr %ld2249, i64 16
  %fv2254 = load ptr, ptr %fp2253, align 8
  %$f860.addr = alloca ptr
  store ptr %fv2254, ptr %$f860.addr
  %freed2255 = call i64 @march_decrc_freed(ptr %ld2249)
  %freed_b2256 = icmp ne i64 %freed2255, 0
  br i1 %freed_b2256, label %br_unique562, label %br_shared563
br_shared563:
  call void @march_incrc(ptr %fv2254)
  br label %br_body564
br_unique562:
  br label %br_body564
br_body564:
  %ld2257 = load ptr, ptr %$f860.addr
  %msg_2.addr = alloca ptr
  store ptr %ld2257, ptr %msg_2.addr
  %ld2258 = load ptr, ptr %tcp_close.addr
  %fp2259 = getelementptr i8, ptr %ld2258, i64 16
  %fv2260 = load ptr, ptr %fp2259, align 8
  %ld2261 = load ptr, ptr %fd.addr
  %cr2262 = call ptr (ptr, ptr) %fv2260(ptr %ld2258, ptr %ld2261)
  %hp2263 = call ptr @march_alloc(i64 24)
  %tgp2264 = getelementptr i8, ptr %hp2263, i64 8
  store i32 3, ptr %tgp2264, align 4
  %ld2265 = load ptr, ptr %msg_2.addr
  %fp2266 = getelementptr i8, ptr %hp2263, i64 16
  store ptr %ld2265, ptr %fp2266, align 8
  %$t850.addr = alloca ptr
  store ptr %hp2263, ptr %$t850.addr
  %hp2267 = call ptr @march_alloc(i64 24)
  %tgp2268 = getelementptr i8, ptr %hp2267, i64 8
  store i32 1, ptr %tgp2268, align 4
  %ld2269 = load ptr, ptr %$t850.addr
  %fp2270 = getelementptr i8, ptr %hp2267, i64 16
  store ptr %ld2269, ptr %fp2270, align 8
  store ptr %hp2267, ptr %res_slot2250
  br label %case_merge558
case_br561:
  %fp2271 = getelementptr i8, ptr %ld2249, i64 16
  %fv2272 = load ptr, ptr %fp2271, align 8
  %$f861.addr = alloca ptr
  store ptr %fv2272, ptr %$f861.addr
  %freed2273 = call i64 @march_decrc_freed(ptr %ld2249)
  %freed_b2274 = icmp ne i64 %freed2273, 0
  br i1 %freed_b2274, label %br_unique565, label %br_shared566
br_shared566:
  call void @march_incrc(ptr %fv2272)
  br label %br_body567
br_unique565:
  br label %br_body567
br_body567:
  %ld2275 = load ptr, ptr %$f861.addr
  %raw_response.addr = alloca ptr
  store ptr %ld2275, ptr %raw_response.addr
  %ld2276 = load ptr, ptr %tcp_close.addr
  %fp2277 = getelementptr i8, ptr %ld2276, i64 16
  %fv2278 = load ptr, ptr %fp2277, align 8
  %ld2279 = load ptr, ptr %fd.addr
  %cr2280 = call ptr (ptr, ptr) %fv2278(ptr %ld2276, ptr %ld2279)
  %ld2281 = load ptr, ptr %http_parse_response.addr
  %fp2282 = getelementptr i8, ptr %ld2281, i64 16
  %fv2283 = load ptr, ptr %fp2282, align 8
  %ld2284 = load ptr, ptr %raw_response.addr
  %cr2285 = call ptr (ptr, ptr) %fv2283(ptr %ld2281, ptr %ld2284)
  %$t851.addr = alloca ptr
  store ptr %cr2285, ptr %$t851.addr
  %ld2286 = load ptr, ptr %$t851.addr
  %res_slot2287 = alloca ptr
  %tgp2288 = getelementptr i8, ptr %ld2286, i64 8
  %tag2289 = load i32, ptr %tgp2288, align 4
  switch i32 %tag2289, label %case_default569 [
      i32 0, label %case_br570
      i32 0, label %case_br571
  ]
case_br570:
  %fp2290 = getelementptr i8, ptr %ld2286, i64 16
  %fv2291 = load ptr, ptr %fp2290, align 8
  %$f855.addr = alloca ptr
  store ptr %fv2291, ptr %$f855.addr
  %freed2292 = call i64 @march_decrc_freed(ptr %ld2286)
  %freed_b2293 = icmp ne i64 %freed2292, 0
  br i1 %freed_b2293, label %br_unique572, label %br_shared573
br_shared573:
  call void @march_incrc(ptr %fv2291)
  br label %br_body574
br_unique572:
  br label %br_body574
br_body574:
  %ld2294 = load ptr, ptr %$f855.addr
  %msg_3.addr = alloca ptr
  store ptr %ld2294, ptr %msg_3.addr
  %hp2295 = call ptr @march_alloc(i64 24)
  %tgp2296 = getelementptr i8, ptr %hp2295, i64 8
  store i32 0, ptr %tgp2296, align 4
  %ld2297 = load ptr, ptr %msg_3.addr
  %fp2298 = getelementptr i8, ptr %hp2295, i64 16
  store ptr %ld2297, ptr %fp2298, align 8
  %$t852.addr = alloca ptr
  store ptr %hp2295, ptr %$t852.addr
  %hp2299 = call ptr @march_alloc(i64 24)
  %tgp2300 = getelementptr i8, ptr %hp2299, i64 8
  store i32 1, ptr %tgp2300, align 4
  %ld2301 = load ptr, ptr %$t852.addr
  %fp2302 = getelementptr i8, ptr %hp2299, i64 16
  store ptr %ld2301, ptr %fp2302, align 8
  store ptr %hp2299, ptr %res_slot2287
  br label %case_merge568
case_br571:
  %fp2303 = getelementptr i8, ptr %ld2286, i64 16
  %fv2304 = load ptr, ptr %fp2303, align 8
  %$f856.addr = alloca ptr
  store ptr %fv2304, ptr %$f856.addr
  %freed2305 = call i64 @march_decrc_freed(ptr %ld2286)
  %freed_b2306 = icmp ne i64 %freed2305, 0
  br i1 %freed_b2306, label %br_unique575, label %br_shared576
br_shared576:
  call void @march_incrc(ptr %fv2304)
  br label %br_body577
br_unique575:
  br label %br_body577
br_body577:
  %ld2307 = load ptr, ptr %$f856.addr
  %res_slot2308 = alloca ptr
  %tgp2309 = getelementptr i8, ptr %ld2307, i64 8
  %tag2310 = load i32, ptr %tgp2309, align 4
  switch i32 %tag2310, label %case_default579 [
      i32 0, label %case_br580
  ]
case_br580:
  %fp2311 = getelementptr i8, ptr %ld2307, i64 16
  %fv2312 = load ptr, ptr %fp2311, align 8
  %$f857.addr = alloca ptr
  store ptr %fv2312, ptr %$f857.addr
  %fp2313 = getelementptr i8, ptr %ld2307, i64 24
  %fv2314 = load ptr, ptr %fp2313, align 8
  %$f858.addr = alloca ptr
  store ptr %fv2314, ptr %$f858.addr
  %fp2315 = getelementptr i8, ptr %ld2307, i64 32
  %fv2316 = load ptr, ptr %fp2315, align 8
  %$f859.addr = alloca ptr
  store ptr %fv2316, ptr %$f859.addr
  %freed2317 = call i64 @march_decrc_freed(ptr %ld2307)
  %freed_b2318 = icmp ne i64 %freed2317, 0
  br i1 %freed_b2318, label %br_unique581, label %br_shared582
br_shared582:
  call void @march_incrc(ptr %fv2316)
  call void @march_incrc(ptr %fv2314)
  call void @march_incrc(ptr %fv2312)
  br label %br_body583
br_unique581:
  br label %br_body583
br_body583:
  %ld2319 = load ptr, ptr %$f859.addr
  %resp_body.addr = alloca ptr
  store ptr %ld2319, ptr %resp_body.addr
  %ld2320 = load ptr, ptr %$f858.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld2320, ptr %resp_headers.addr
  %ld2321 = load ptr, ptr %$f857.addr
  %status_code.addr = alloca ptr
  store ptr %ld2321, ptr %status_code.addr
  %hp2322 = call ptr @march_alloc(i64 24)
  %tgp2323 = getelementptr i8, ptr %hp2322, i64 8
  store i32 0, ptr %tgp2323, align 4
  %ld2324 = load ptr, ptr %status_code.addr
  %fp2325 = getelementptr i8, ptr %hp2322, i64 16
  store ptr %ld2324, ptr %fp2325, align 8
  %$t853.addr = alloca ptr
  store ptr %hp2322, ptr %$t853.addr
  %hp2326 = call ptr @march_alloc(i64 40)
  %tgp2327 = getelementptr i8, ptr %hp2326, i64 8
  store i32 0, ptr %tgp2327, align 4
  %ld2328 = load ptr, ptr %$t853.addr
  %fp2329 = getelementptr i8, ptr %hp2326, i64 16
  store ptr %ld2328, ptr %fp2329, align 8
  %ld2330 = load ptr, ptr %resp_headers.addr
  %fp2331 = getelementptr i8, ptr %hp2326, i64 24
  store ptr %ld2330, ptr %fp2331, align 8
  %ld2332 = load ptr, ptr %resp_body.addr
  %fp2333 = getelementptr i8, ptr %hp2326, i64 32
  store ptr %ld2332, ptr %fp2333, align 8
  %$t854.addr = alloca ptr
  store ptr %hp2326, ptr %$t854.addr
  %hp2334 = call ptr @march_alloc(i64 24)
  %tgp2335 = getelementptr i8, ptr %hp2334, i64 8
  store i32 0, ptr %tgp2335, align 4
  %ld2336 = load ptr, ptr %$t854.addr
  %fp2337 = getelementptr i8, ptr %hp2334, i64 16
  store ptr %ld2336, ptr %fp2337, align 8
  store ptr %hp2334, ptr %res_slot2308
  br label %case_merge578
case_default579:
  unreachable
case_merge578:
  %case_r2338 = load ptr, ptr %res_slot2308
  store ptr %case_r2338, ptr %res_slot2287
  br label %case_merge568
case_default569:
  unreachable
case_merge568:
  %case_r2339 = load ptr, ptr %res_slot2287
  store ptr %case_r2339, ptr %res_slot2250
  br label %case_merge558
case_default559:
  unreachable
case_merge558:
  %case_r2340 = load ptr, ptr %res_slot2250
  store ptr %case_r2340, ptr %res_slot2216
  br label %case_merge548
case_default549:
  unreachable
case_merge548:
  %case_r2341 = load ptr, ptr %res_slot2216
  store ptr %case_r2341, ptr %res_slot2187
  br label %case_merge538
case_default539:
  unreachable
case_merge538:
  %case_r2342 = load ptr, ptr %res_slot2187
  ret ptr %case_r2342
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2343 = load ptr, ptr %req.addr
  %res_slot2344 = alloca ptr
  %tgp2345 = getelementptr i8, ptr %ld2343, i64 8
  %tag2346 = load i32, ptr %tgp2345, align 4
  switch i32 %tag2346, label %case_default585 [
      i32 0, label %case_br586
  ]
case_br586:
  %fp2347 = getelementptr i8, ptr %ld2343, i64 16
  %fv2348 = load ptr, ptr %fp2347, align 8
  %$f591.addr = alloca ptr
  store ptr %fv2348, ptr %$f591.addr
  %fp2349 = getelementptr i8, ptr %ld2343, i64 24
  %fv2350 = load ptr, ptr %fp2349, align 8
  %$f592.addr = alloca ptr
  store ptr %fv2350, ptr %$f592.addr
  %fp2351 = getelementptr i8, ptr %ld2343, i64 32
  %fv2352 = load ptr, ptr %fp2351, align 8
  %$f593.addr = alloca ptr
  store ptr %fv2352, ptr %$f593.addr
  %fp2353 = getelementptr i8, ptr %ld2343, i64 40
  %fv2354 = load ptr, ptr %fp2353, align 8
  %$f594.addr = alloca ptr
  store ptr %fv2354, ptr %$f594.addr
  %fp2355 = getelementptr i8, ptr %ld2343, i64 48
  %fv2356 = load ptr, ptr %fp2355, align 8
  %$f595.addr = alloca ptr
  store ptr %fv2356, ptr %$f595.addr
  %fp2357 = getelementptr i8, ptr %ld2343, i64 56
  %fv2358 = load ptr, ptr %fp2357, align 8
  %$f596.addr = alloca ptr
  store ptr %fv2358, ptr %$f596.addr
  %fp2359 = getelementptr i8, ptr %ld2343, i64 64
  %fv2360 = load ptr, ptr %fp2359, align 8
  %$f597.addr = alloca ptr
  store ptr %fv2360, ptr %$f597.addr
  %fp2361 = getelementptr i8, ptr %ld2343, i64 72
  %fv2362 = load ptr, ptr %fp2361, align 8
  %$f598.addr = alloca ptr
  store ptr %fv2362, ptr %$f598.addr
  %freed2363 = call i64 @march_decrc_freed(ptr %ld2343)
  %freed_b2364 = icmp ne i64 %freed2363, 0
  br i1 %freed_b2364, label %br_unique587, label %br_shared588
br_shared588:
  call void @march_incrc(ptr %fv2362)
  call void @march_incrc(ptr %fv2360)
  call void @march_incrc(ptr %fv2358)
  call void @march_incrc(ptr %fv2356)
  call void @march_incrc(ptr %fv2354)
  call void @march_incrc(ptr %fv2352)
  call void @march_incrc(ptr %fv2350)
  call void @march_incrc(ptr %fv2348)
  br label %br_body589
br_unique587:
  br label %br_body589
br_body589:
  %ld2365 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld2365, ptr %h.addr
  %ld2366 = load ptr, ptr %h.addr
  store ptr %ld2366, ptr %res_slot2344
  br label %case_merge584
case_default585:
  unreachable
case_merge584:
  %case_r2367 = load ptr, ptr %res_slot2344
  ret ptr %case_r2367
}

define ptr @Http.query$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2368 = load ptr, ptr %req.addr
  %res_slot2369 = alloca ptr
  %tgp2370 = getelementptr i8, ptr %ld2368, i64 8
  %tag2371 = load i32, ptr %tgp2370, align 4
  switch i32 %tag2371, label %case_default591 [
      i32 0, label %case_br592
  ]
case_br592:
  %fp2372 = getelementptr i8, ptr %ld2368, i64 16
  %fv2373 = load ptr, ptr %fp2372, align 8
  %$f583.addr = alloca ptr
  store ptr %fv2373, ptr %$f583.addr
  %fp2374 = getelementptr i8, ptr %ld2368, i64 24
  %fv2375 = load ptr, ptr %fp2374, align 8
  %$f584.addr = alloca ptr
  store ptr %fv2375, ptr %$f584.addr
  %fp2376 = getelementptr i8, ptr %ld2368, i64 32
  %fv2377 = load ptr, ptr %fp2376, align 8
  %$f585.addr = alloca ptr
  store ptr %fv2377, ptr %$f585.addr
  %fp2378 = getelementptr i8, ptr %ld2368, i64 40
  %fv2379 = load ptr, ptr %fp2378, align 8
  %$f586.addr = alloca ptr
  store ptr %fv2379, ptr %$f586.addr
  %fp2380 = getelementptr i8, ptr %ld2368, i64 48
  %fv2381 = load ptr, ptr %fp2380, align 8
  %$f587.addr = alloca ptr
  store ptr %fv2381, ptr %$f587.addr
  %fp2382 = getelementptr i8, ptr %ld2368, i64 56
  %fv2383 = load ptr, ptr %fp2382, align 8
  %$f588.addr = alloca ptr
  store ptr %fv2383, ptr %$f588.addr
  %fp2384 = getelementptr i8, ptr %ld2368, i64 64
  %fv2385 = load ptr, ptr %fp2384, align 8
  %$f589.addr = alloca ptr
  store ptr %fv2385, ptr %$f589.addr
  %fp2386 = getelementptr i8, ptr %ld2368, i64 72
  %fv2387 = load ptr, ptr %fp2386, align 8
  %$f590.addr = alloca ptr
  store ptr %fv2387, ptr %$f590.addr
  %freed2388 = call i64 @march_decrc_freed(ptr %ld2368)
  %freed_b2389 = icmp ne i64 %freed2388, 0
  br i1 %freed_b2389, label %br_unique593, label %br_shared594
br_shared594:
  call void @march_incrc(ptr %fv2387)
  call void @march_incrc(ptr %fv2385)
  call void @march_incrc(ptr %fv2383)
  call void @march_incrc(ptr %fv2381)
  call void @march_incrc(ptr %fv2379)
  call void @march_incrc(ptr %fv2377)
  call void @march_incrc(ptr %fv2375)
  call void @march_incrc(ptr %fv2373)
  br label %br_body595
br_unique593:
  br label %br_body595
br_body595:
  %ld2390 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld2390, ptr %q.addr
  %ld2391 = load ptr, ptr %q.addr
  store ptr %ld2391, ptr %res_slot2369
  br label %case_merge590
case_default591:
  unreachable
case_merge590:
  %case_r2392 = load ptr, ptr %res_slot2369
  ret ptr %case_r2392
}

define ptr @Http.path$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2393 = load ptr, ptr %req.addr
  %res_slot2394 = alloca ptr
  %tgp2395 = getelementptr i8, ptr %ld2393, i64 8
  %tag2396 = load i32, ptr %tgp2395, align 4
  switch i32 %tag2396, label %case_default597 [
      i32 0, label %case_br598
  ]
case_br598:
  %fp2397 = getelementptr i8, ptr %ld2393, i64 16
  %fv2398 = load ptr, ptr %fp2397, align 8
  %$f575.addr = alloca ptr
  store ptr %fv2398, ptr %$f575.addr
  %fp2399 = getelementptr i8, ptr %ld2393, i64 24
  %fv2400 = load ptr, ptr %fp2399, align 8
  %$f576.addr = alloca ptr
  store ptr %fv2400, ptr %$f576.addr
  %fp2401 = getelementptr i8, ptr %ld2393, i64 32
  %fv2402 = load ptr, ptr %fp2401, align 8
  %$f577.addr = alloca ptr
  store ptr %fv2402, ptr %$f577.addr
  %fp2403 = getelementptr i8, ptr %ld2393, i64 40
  %fv2404 = load ptr, ptr %fp2403, align 8
  %$f578.addr = alloca ptr
  store ptr %fv2404, ptr %$f578.addr
  %fp2405 = getelementptr i8, ptr %ld2393, i64 48
  %fv2406 = load ptr, ptr %fp2405, align 8
  %$f579.addr = alloca ptr
  store ptr %fv2406, ptr %$f579.addr
  %fp2407 = getelementptr i8, ptr %ld2393, i64 56
  %fv2408 = load ptr, ptr %fp2407, align 8
  %$f580.addr = alloca ptr
  store ptr %fv2408, ptr %$f580.addr
  %fp2409 = getelementptr i8, ptr %ld2393, i64 64
  %fv2410 = load ptr, ptr %fp2409, align 8
  %$f581.addr = alloca ptr
  store ptr %fv2410, ptr %$f581.addr
  %fp2411 = getelementptr i8, ptr %ld2393, i64 72
  %fv2412 = load ptr, ptr %fp2411, align 8
  %$f582.addr = alloca ptr
  store ptr %fv2412, ptr %$f582.addr
  %freed2413 = call i64 @march_decrc_freed(ptr %ld2393)
  %freed_b2414 = icmp ne i64 %freed2413, 0
  br i1 %freed_b2414, label %br_unique599, label %br_shared600
br_shared600:
  call void @march_incrc(ptr %fv2412)
  call void @march_incrc(ptr %fv2410)
  call void @march_incrc(ptr %fv2408)
  call void @march_incrc(ptr %fv2406)
  call void @march_incrc(ptr %fv2404)
  call void @march_incrc(ptr %fv2402)
  call void @march_incrc(ptr %fv2400)
  call void @march_incrc(ptr %fv2398)
  br label %br_body601
br_unique599:
  br label %br_body601
br_body601:
  %ld2415 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld2415, ptr %p.addr
  %ld2416 = load ptr, ptr %p.addr
  store ptr %ld2416, ptr %res_slot2394
  br label %case_merge596
case_default597:
  unreachable
case_merge596:
  %case_r2417 = load ptr, ptr %res_slot2394
  ret ptr %case_r2417
}

define ptr @Http.scheme$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2418 = load ptr, ptr %req.addr
  %res_slot2419 = alloca ptr
  %tgp2420 = getelementptr i8, ptr %ld2418, i64 8
  %tag2421 = load i32, ptr %tgp2420, align 4
  switch i32 %tag2421, label %case_default603 [
      i32 0, label %case_br604
  ]
case_br604:
  %fp2422 = getelementptr i8, ptr %ld2418, i64 16
  %fv2423 = load ptr, ptr %fp2422, align 8
  %$f551.addr = alloca ptr
  store ptr %fv2423, ptr %$f551.addr
  %fp2424 = getelementptr i8, ptr %ld2418, i64 24
  %fv2425 = load ptr, ptr %fp2424, align 8
  %$f552.addr = alloca ptr
  store ptr %fv2425, ptr %$f552.addr
  %fp2426 = getelementptr i8, ptr %ld2418, i64 32
  %fv2427 = load ptr, ptr %fp2426, align 8
  %$f553.addr = alloca ptr
  store ptr %fv2427, ptr %$f553.addr
  %fp2428 = getelementptr i8, ptr %ld2418, i64 40
  %fv2429 = load ptr, ptr %fp2428, align 8
  %$f554.addr = alloca ptr
  store ptr %fv2429, ptr %$f554.addr
  %fp2430 = getelementptr i8, ptr %ld2418, i64 48
  %fv2431 = load ptr, ptr %fp2430, align 8
  %$f555.addr = alloca ptr
  store ptr %fv2431, ptr %$f555.addr
  %fp2432 = getelementptr i8, ptr %ld2418, i64 56
  %fv2433 = load ptr, ptr %fp2432, align 8
  %$f556.addr = alloca ptr
  store ptr %fv2433, ptr %$f556.addr
  %fp2434 = getelementptr i8, ptr %ld2418, i64 64
  %fv2435 = load ptr, ptr %fp2434, align 8
  %$f557.addr = alloca ptr
  store ptr %fv2435, ptr %$f557.addr
  %fp2436 = getelementptr i8, ptr %ld2418, i64 72
  %fv2437 = load ptr, ptr %fp2436, align 8
  %$f558.addr = alloca ptr
  store ptr %fv2437, ptr %$f558.addr
  %freed2438 = call i64 @march_decrc_freed(ptr %ld2418)
  %freed_b2439 = icmp ne i64 %freed2438, 0
  br i1 %freed_b2439, label %br_unique605, label %br_shared606
br_shared606:
  call void @march_incrc(ptr %fv2437)
  call void @march_incrc(ptr %fv2435)
  call void @march_incrc(ptr %fv2433)
  call void @march_incrc(ptr %fv2431)
  call void @march_incrc(ptr %fv2429)
  call void @march_incrc(ptr %fv2427)
  call void @march_incrc(ptr %fv2425)
  call void @march_incrc(ptr %fv2423)
  br label %br_body607
br_unique605:
  br label %br_body607
br_body607:
  %ld2440 = load ptr, ptr %$f552.addr
  %s.addr = alloca ptr
  store ptr %ld2440, ptr %s.addr
  %ld2441 = load ptr, ptr %s.addr
  store ptr %ld2441, ptr %res_slot2419
  br label %case_merge602
case_default603:
  unreachable
case_merge602:
  %case_r2442 = load ptr, ptr %res_slot2419
  ret ptr %case_r2442
}

define ptr @Http.set_body$Request_String$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld2443 = load ptr, ptr %req.addr
  %res_slot2444 = alloca ptr
  %tgp2445 = getelementptr i8, ptr %ld2443, i64 8
  %tag2446 = load i32, ptr %tgp2445, align 4
  switch i32 %tag2446, label %case_default609 [
      i32 0, label %case_br610
  ]
case_br610:
  %fp2447 = getelementptr i8, ptr %ld2443, i64 16
  %fv2448 = load ptr, ptr %fp2447, align 8
  %$f648.addr = alloca ptr
  store ptr %fv2448, ptr %$f648.addr
  %fp2449 = getelementptr i8, ptr %ld2443, i64 24
  %fv2450 = load ptr, ptr %fp2449, align 8
  %$f649.addr = alloca ptr
  store ptr %fv2450, ptr %$f649.addr
  %fp2451 = getelementptr i8, ptr %ld2443, i64 32
  %fv2452 = load ptr, ptr %fp2451, align 8
  %$f650.addr = alloca ptr
  store ptr %fv2452, ptr %$f650.addr
  %fp2453 = getelementptr i8, ptr %ld2443, i64 40
  %fv2454 = load ptr, ptr %fp2453, align 8
  %$f651.addr = alloca ptr
  store ptr %fv2454, ptr %$f651.addr
  %fp2455 = getelementptr i8, ptr %ld2443, i64 48
  %fv2456 = load ptr, ptr %fp2455, align 8
  %$f652.addr = alloca ptr
  store ptr %fv2456, ptr %$f652.addr
  %fp2457 = getelementptr i8, ptr %ld2443, i64 56
  %fv2458 = load ptr, ptr %fp2457, align 8
  %$f653.addr = alloca ptr
  store ptr %fv2458, ptr %$f653.addr
  %fp2459 = getelementptr i8, ptr %ld2443, i64 64
  %fv2460 = load ptr, ptr %fp2459, align 8
  %$f654.addr = alloca ptr
  store ptr %fv2460, ptr %$f654.addr
  %fp2461 = getelementptr i8, ptr %ld2443, i64 72
  %fv2462 = load ptr, ptr %fp2461, align 8
  %$f655.addr = alloca ptr
  store ptr %fv2462, ptr %$f655.addr
  %ld2463 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld2463, ptr %hd.addr
  %ld2464 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld2464, ptr %q.addr
  %ld2465 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld2465, ptr %pa.addr
  %ld2466 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld2466, ptr %p.addr
  %ld2467 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld2467, ptr %h.addr
  %ld2468 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld2468, ptr %sc.addr
  %ld2469 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld2469, ptr %m.addr
  %ld2470 = load ptr, ptr %req.addr
  %ld2471 = load ptr, ptr %m.addr
  %ld2472 = load ptr, ptr %sc.addr
  %ld2473 = load ptr, ptr %h.addr
  %ld2474 = load ptr, ptr %p.addr
  %ld2475 = load ptr, ptr %pa.addr
  %ld2476 = load ptr, ptr %q.addr
  %ld2477 = load ptr, ptr %hd.addr
  %ld2478 = load ptr, ptr %new_body.addr
  %rc2479 = load i64, ptr %ld2470, align 8
  %uniq2480 = icmp eq i64 %rc2479, 1
  %fbip_slot2481 = alloca ptr
  br i1 %uniq2480, label %fbip_reuse611, label %fbip_fresh612
fbip_reuse611:
  %tgp2482 = getelementptr i8, ptr %ld2470, i64 8
  store i32 0, ptr %tgp2482, align 4
  %fp2483 = getelementptr i8, ptr %ld2470, i64 16
  store ptr %ld2471, ptr %fp2483, align 8
  %fp2484 = getelementptr i8, ptr %ld2470, i64 24
  store ptr %ld2472, ptr %fp2484, align 8
  %fp2485 = getelementptr i8, ptr %ld2470, i64 32
  store ptr %ld2473, ptr %fp2485, align 8
  %fp2486 = getelementptr i8, ptr %ld2470, i64 40
  store ptr %ld2474, ptr %fp2486, align 8
  %fp2487 = getelementptr i8, ptr %ld2470, i64 48
  store ptr %ld2475, ptr %fp2487, align 8
  %fp2488 = getelementptr i8, ptr %ld2470, i64 56
  store ptr %ld2476, ptr %fp2488, align 8
  %fp2489 = getelementptr i8, ptr %ld2470, i64 64
  store ptr %ld2477, ptr %fp2489, align 8
  %fp2490 = getelementptr i8, ptr %ld2470, i64 72
  store ptr %ld2478, ptr %fp2490, align 8
  store ptr %ld2470, ptr %fbip_slot2481
  br label %fbip_merge613
fbip_fresh612:
  call void @march_decrc(ptr %ld2470)
  %hp2491 = call ptr @march_alloc(i64 80)
  %tgp2492 = getelementptr i8, ptr %hp2491, i64 8
  store i32 0, ptr %tgp2492, align 4
  %fp2493 = getelementptr i8, ptr %hp2491, i64 16
  store ptr %ld2471, ptr %fp2493, align 8
  %fp2494 = getelementptr i8, ptr %hp2491, i64 24
  store ptr %ld2472, ptr %fp2494, align 8
  %fp2495 = getelementptr i8, ptr %hp2491, i64 32
  store ptr %ld2473, ptr %fp2495, align 8
  %fp2496 = getelementptr i8, ptr %hp2491, i64 40
  store ptr %ld2474, ptr %fp2496, align 8
  %fp2497 = getelementptr i8, ptr %hp2491, i64 48
  store ptr %ld2475, ptr %fp2497, align 8
  %fp2498 = getelementptr i8, ptr %hp2491, i64 56
  store ptr %ld2476, ptr %fp2498, align 8
  %fp2499 = getelementptr i8, ptr %hp2491, i64 64
  store ptr %ld2477, ptr %fp2499, align 8
  %fp2500 = getelementptr i8, ptr %hp2491, i64 72
  store ptr %ld2478, ptr %fp2500, align 8
  store ptr %hp2491, ptr %fbip_slot2481
  br label %fbip_merge613
fbip_merge613:
  %fbip_r2501 = load ptr, ptr %fbip_slot2481
  store ptr %fbip_r2501, ptr %res_slot2444
  br label %case_merge608
case_default609:
  unreachable
case_merge608:
  %case_r2502 = load ptr, ptr %res_slot2444
  ret ptr %case_r2502
}

define ptr @Http.set_method$Request_String$Method(ptr %req.arg, ptr %m.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %m.addr = alloca ptr
  store ptr %m.arg, ptr %m.addr
  %ld2503 = load ptr, ptr %req.addr
  %res_slot2504 = alloca ptr
  %tgp2505 = getelementptr i8, ptr %ld2503, i64 8
  %tag2506 = load i32, ptr %tgp2505, align 4
  switch i32 %tag2506, label %case_default615 [
      i32 0, label %case_br616
  ]
case_br616:
  %fp2507 = getelementptr i8, ptr %ld2503, i64 16
  %fv2508 = load ptr, ptr %fp2507, align 8
  %$f607.addr = alloca ptr
  store ptr %fv2508, ptr %$f607.addr
  %fp2509 = getelementptr i8, ptr %ld2503, i64 24
  %fv2510 = load ptr, ptr %fp2509, align 8
  %$f608.addr = alloca ptr
  store ptr %fv2510, ptr %$f608.addr
  %fp2511 = getelementptr i8, ptr %ld2503, i64 32
  %fv2512 = load ptr, ptr %fp2511, align 8
  %$f609.addr = alloca ptr
  store ptr %fv2512, ptr %$f609.addr
  %fp2513 = getelementptr i8, ptr %ld2503, i64 40
  %fv2514 = load ptr, ptr %fp2513, align 8
  %$f610.addr = alloca ptr
  store ptr %fv2514, ptr %$f610.addr
  %fp2515 = getelementptr i8, ptr %ld2503, i64 48
  %fv2516 = load ptr, ptr %fp2515, align 8
  %$f611.addr = alloca ptr
  store ptr %fv2516, ptr %$f611.addr
  %fp2517 = getelementptr i8, ptr %ld2503, i64 56
  %fv2518 = load ptr, ptr %fp2517, align 8
  %$f612.addr = alloca ptr
  store ptr %fv2518, ptr %$f612.addr
  %fp2519 = getelementptr i8, ptr %ld2503, i64 64
  %fv2520 = load ptr, ptr %fp2519, align 8
  %$f613.addr = alloca ptr
  store ptr %fv2520, ptr %$f613.addr
  %fp2521 = getelementptr i8, ptr %ld2503, i64 72
  %fv2522 = load ptr, ptr %fp2521, align 8
  %$f614.addr = alloca ptr
  store ptr %fv2522, ptr %$f614.addr
  %ld2523 = load ptr, ptr %$f614.addr
  %bd.addr = alloca ptr
  store ptr %ld2523, ptr %bd.addr
  %ld2524 = load ptr, ptr %$f613.addr
  %hd.addr = alloca ptr
  store ptr %ld2524, ptr %hd.addr
  %ld2525 = load ptr, ptr %$f612.addr
  %q.addr = alloca ptr
  store ptr %ld2525, ptr %q.addr
  %ld2526 = load ptr, ptr %$f611.addr
  %pa.addr = alloca ptr
  store ptr %ld2526, ptr %pa.addr
  %ld2527 = load ptr, ptr %$f610.addr
  %p.addr = alloca ptr
  store ptr %ld2527, ptr %p.addr
  %ld2528 = load ptr, ptr %$f609.addr
  %h.addr = alloca ptr
  store ptr %ld2528, ptr %h.addr
  %ld2529 = load ptr, ptr %$f608.addr
  %sc.addr = alloca ptr
  store ptr %ld2529, ptr %sc.addr
  %ld2530 = load ptr, ptr %req.addr
  %ld2531 = load ptr, ptr %m.addr
  %ld2532 = load ptr, ptr %sc.addr
  %ld2533 = load ptr, ptr %h.addr
  %ld2534 = load ptr, ptr %p.addr
  %ld2535 = load ptr, ptr %pa.addr
  %ld2536 = load ptr, ptr %q.addr
  %ld2537 = load ptr, ptr %hd.addr
  %ld2538 = load ptr, ptr %bd.addr
  %rc2539 = load i64, ptr %ld2530, align 8
  %uniq2540 = icmp eq i64 %rc2539, 1
  %fbip_slot2541 = alloca ptr
  br i1 %uniq2540, label %fbip_reuse617, label %fbip_fresh618
fbip_reuse617:
  %tgp2542 = getelementptr i8, ptr %ld2530, i64 8
  store i32 0, ptr %tgp2542, align 4
  %fp2543 = getelementptr i8, ptr %ld2530, i64 16
  store ptr %ld2531, ptr %fp2543, align 8
  %fp2544 = getelementptr i8, ptr %ld2530, i64 24
  store ptr %ld2532, ptr %fp2544, align 8
  %fp2545 = getelementptr i8, ptr %ld2530, i64 32
  store ptr %ld2533, ptr %fp2545, align 8
  %fp2546 = getelementptr i8, ptr %ld2530, i64 40
  store ptr %ld2534, ptr %fp2546, align 8
  %fp2547 = getelementptr i8, ptr %ld2530, i64 48
  store ptr %ld2535, ptr %fp2547, align 8
  %fp2548 = getelementptr i8, ptr %ld2530, i64 56
  store ptr %ld2536, ptr %fp2548, align 8
  %fp2549 = getelementptr i8, ptr %ld2530, i64 64
  store ptr %ld2537, ptr %fp2549, align 8
  %fp2550 = getelementptr i8, ptr %ld2530, i64 72
  store ptr %ld2538, ptr %fp2550, align 8
  store ptr %ld2530, ptr %fbip_slot2541
  br label %fbip_merge619
fbip_fresh618:
  call void @march_decrc(ptr %ld2530)
  %hp2551 = call ptr @march_alloc(i64 80)
  %tgp2552 = getelementptr i8, ptr %hp2551, i64 8
  store i32 0, ptr %tgp2552, align 4
  %fp2553 = getelementptr i8, ptr %hp2551, i64 16
  store ptr %ld2531, ptr %fp2553, align 8
  %fp2554 = getelementptr i8, ptr %hp2551, i64 24
  store ptr %ld2532, ptr %fp2554, align 8
  %fp2555 = getelementptr i8, ptr %hp2551, i64 32
  store ptr %ld2533, ptr %fp2555, align 8
  %fp2556 = getelementptr i8, ptr %hp2551, i64 40
  store ptr %ld2534, ptr %fp2556, align 8
  %fp2557 = getelementptr i8, ptr %hp2551, i64 48
  store ptr %ld2535, ptr %fp2557, align 8
  %fp2558 = getelementptr i8, ptr %hp2551, i64 56
  store ptr %ld2536, ptr %fp2558, align 8
  %fp2559 = getelementptr i8, ptr %hp2551, i64 64
  store ptr %ld2537, ptr %fp2559, align 8
  %fp2560 = getelementptr i8, ptr %hp2551, i64 72
  store ptr %ld2538, ptr %fp2560, align 8
  store ptr %hp2551, ptr %fbip_slot2541
  br label %fbip_merge619
fbip_merge619:
  %fbip_r2561 = load ptr, ptr %fbip_slot2541
  store ptr %fbip_r2561, ptr %res_slot2504
  br label %case_merge614
case_default615:
  unreachable
case_merge614:
  %case_r2562 = load ptr, ptr %res_slot2504
  ret ptr %case_r2562
}

define ptr @Http.set_path$Request_String$String(ptr %req.arg, ptr %new_path.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_path.addr = alloca ptr
  store ptr %new_path.arg, ptr %new_path.addr
  %ld2563 = load ptr, ptr %req.addr
  %res_slot2564 = alloca ptr
  %tgp2565 = getelementptr i8, ptr %ld2563, i64 8
  %tag2566 = load i32, ptr %tgp2565, align 4
  switch i32 %tag2566, label %case_default621 [
      i32 0, label %case_br622
  ]
case_br622:
  %fp2567 = getelementptr i8, ptr %ld2563, i64 16
  %fv2568 = load ptr, ptr %fp2567, align 8
  %$f640.addr = alloca ptr
  store ptr %fv2568, ptr %$f640.addr
  %fp2569 = getelementptr i8, ptr %ld2563, i64 24
  %fv2570 = load ptr, ptr %fp2569, align 8
  %$f641.addr = alloca ptr
  store ptr %fv2570, ptr %$f641.addr
  %fp2571 = getelementptr i8, ptr %ld2563, i64 32
  %fv2572 = load ptr, ptr %fp2571, align 8
  %$f642.addr = alloca ptr
  store ptr %fv2572, ptr %$f642.addr
  %fp2573 = getelementptr i8, ptr %ld2563, i64 40
  %fv2574 = load ptr, ptr %fp2573, align 8
  %$f643.addr = alloca ptr
  store ptr %fv2574, ptr %$f643.addr
  %fp2575 = getelementptr i8, ptr %ld2563, i64 48
  %fv2576 = load ptr, ptr %fp2575, align 8
  %$f644.addr = alloca ptr
  store ptr %fv2576, ptr %$f644.addr
  %fp2577 = getelementptr i8, ptr %ld2563, i64 56
  %fv2578 = load ptr, ptr %fp2577, align 8
  %$f645.addr = alloca ptr
  store ptr %fv2578, ptr %$f645.addr
  %fp2579 = getelementptr i8, ptr %ld2563, i64 64
  %fv2580 = load ptr, ptr %fp2579, align 8
  %$f646.addr = alloca ptr
  store ptr %fv2580, ptr %$f646.addr
  %fp2581 = getelementptr i8, ptr %ld2563, i64 72
  %fv2582 = load ptr, ptr %fp2581, align 8
  %$f647.addr = alloca ptr
  store ptr %fv2582, ptr %$f647.addr
  %ld2583 = load ptr, ptr %$f647.addr
  %bd.addr = alloca ptr
  store ptr %ld2583, ptr %bd.addr
  %ld2584 = load ptr, ptr %$f646.addr
  %hd.addr = alloca ptr
  store ptr %ld2584, ptr %hd.addr
  %ld2585 = load ptr, ptr %$f645.addr
  %q.addr = alloca ptr
  store ptr %ld2585, ptr %q.addr
  %ld2586 = load ptr, ptr %$f643.addr
  %p.addr = alloca ptr
  store ptr %ld2586, ptr %p.addr
  %ld2587 = load ptr, ptr %$f642.addr
  %h.addr = alloca ptr
  store ptr %ld2587, ptr %h.addr
  %ld2588 = load ptr, ptr %$f641.addr
  %sc.addr = alloca ptr
  store ptr %ld2588, ptr %sc.addr
  %ld2589 = load ptr, ptr %$f640.addr
  %m.addr = alloca ptr
  store ptr %ld2589, ptr %m.addr
  %ld2590 = load ptr, ptr %req.addr
  %ld2591 = load ptr, ptr %m.addr
  %ld2592 = load ptr, ptr %sc.addr
  %ld2593 = load ptr, ptr %h.addr
  %ld2594 = load ptr, ptr %p.addr
  %ld2595 = load ptr, ptr %new_path.addr
  %ld2596 = load ptr, ptr %q.addr
  %ld2597 = load ptr, ptr %hd.addr
  %ld2598 = load ptr, ptr %bd.addr
  %rc2599 = load i64, ptr %ld2590, align 8
  %uniq2600 = icmp eq i64 %rc2599, 1
  %fbip_slot2601 = alloca ptr
  br i1 %uniq2600, label %fbip_reuse623, label %fbip_fresh624
fbip_reuse623:
  %tgp2602 = getelementptr i8, ptr %ld2590, i64 8
  store i32 0, ptr %tgp2602, align 4
  %fp2603 = getelementptr i8, ptr %ld2590, i64 16
  store ptr %ld2591, ptr %fp2603, align 8
  %fp2604 = getelementptr i8, ptr %ld2590, i64 24
  store ptr %ld2592, ptr %fp2604, align 8
  %fp2605 = getelementptr i8, ptr %ld2590, i64 32
  store ptr %ld2593, ptr %fp2605, align 8
  %fp2606 = getelementptr i8, ptr %ld2590, i64 40
  store ptr %ld2594, ptr %fp2606, align 8
  %fp2607 = getelementptr i8, ptr %ld2590, i64 48
  store ptr %ld2595, ptr %fp2607, align 8
  %fp2608 = getelementptr i8, ptr %ld2590, i64 56
  store ptr %ld2596, ptr %fp2608, align 8
  %fp2609 = getelementptr i8, ptr %ld2590, i64 64
  store ptr %ld2597, ptr %fp2609, align 8
  %fp2610 = getelementptr i8, ptr %ld2590, i64 72
  store ptr %ld2598, ptr %fp2610, align 8
  store ptr %ld2590, ptr %fbip_slot2601
  br label %fbip_merge625
fbip_fresh624:
  call void @march_decrc(ptr %ld2590)
  %hp2611 = call ptr @march_alloc(i64 80)
  %tgp2612 = getelementptr i8, ptr %hp2611, i64 8
  store i32 0, ptr %tgp2612, align 4
  %fp2613 = getelementptr i8, ptr %hp2611, i64 16
  store ptr %ld2591, ptr %fp2613, align 8
  %fp2614 = getelementptr i8, ptr %hp2611, i64 24
  store ptr %ld2592, ptr %fp2614, align 8
  %fp2615 = getelementptr i8, ptr %hp2611, i64 32
  store ptr %ld2593, ptr %fp2615, align 8
  %fp2616 = getelementptr i8, ptr %hp2611, i64 40
  store ptr %ld2594, ptr %fp2616, align 8
  %fp2617 = getelementptr i8, ptr %hp2611, i64 48
  store ptr %ld2595, ptr %fp2617, align 8
  %fp2618 = getelementptr i8, ptr %hp2611, i64 56
  store ptr %ld2596, ptr %fp2618, align 8
  %fp2619 = getelementptr i8, ptr %hp2611, i64 64
  store ptr %ld2597, ptr %fp2619, align 8
  %fp2620 = getelementptr i8, ptr %hp2611, i64 72
  store ptr %ld2598, ptr %fp2620, align 8
  store ptr %hp2611, ptr %fbip_slot2601
  br label %fbip_merge625
fbip_merge625:
  %fbip_r2621 = load ptr, ptr %fbip_slot2601
  store ptr %fbip_r2621, ptr %res_slot2564
  br label %case_merge620
case_default621:
  unreachable
case_merge620:
  %case_r2622 = load ptr, ptr %res_slot2564
  ret ptr %case_r2622
}

define ptr @Http.get_header$Response_V__3337$String(ptr %resp.arg, ptr %name.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld2623 = load ptr, ptr %name.addr
  %cr2624 = call ptr @march_string_to_lowercase(ptr %ld2623)
  %lower_name.addr = alloca ptr
  store ptr %cr2624, ptr %lower_name.addr
  %hp2625 = call ptr @march_alloc(i64 32)
  %tgp2626 = getelementptr i8, ptr %hp2625, i64 8
  store i32 0, ptr %tgp2626, align 4
  %fp2627 = getelementptr i8, ptr %hp2625, i64 16
  store ptr @find$apply$26, ptr %fp2627, align 8
  %ld2628 = load ptr, ptr %lower_name.addr
  %fp2629 = getelementptr i8, ptr %hp2625, i64 24
  store ptr %ld2628, ptr %fp2629, align 8
  %find.addr = alloca ptr
  store ptr %hp2625, ptr %find.addr
  %ld2630 = load ptr, ptr %resp.addr
  %cr2631 = call ptr @Http.response_headers$Response_V__2425(ptr %ld2630)
  %$t684.addr = alloca ptr
  store ptr %cr2631, ptr %$t684.addr
  %ld2632 = load ptr, ptr %find.addr
  %fp2633 = getelementptr i8, ptr %ld2632, i64 16
  %fv2634 = load ptr, ptr %fp2633, align 8
  %ld2635 = load ptr, ptr %$t684.addr
  %cr2636 = call ptr (ptr, ptr) %fv2634(ptr %ld2632, ptr %ld2635)
  ret ptr %cr2636
}

define i64 @Http.response_is_redirect$Response_V__3337(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2637 = load ptr, ptr %resp.addr
  %cr2638 = call ptr @Http.response_status$Response_V__2409(ptr %ld2637)
  %$t677.addr = alloca ptr
  store ptr %cr2638, ptr %$t677.addr
  %ld2639 = load ptr, ptr %$t677.addr
  %s_i28.addr = alloca ptr
  store ptr %ld2639, ptr %s_i28.addr
  %ld2640 = load ptr, ptr %s_i28.addr
  %cr2641 = call i64 @Http.status_code(ptr %ld2640)
  %c_i29.addr = alloca i64
  store i64 %cr2641, ptr %c_i29.addr
  %ld2642 = load i64, ptr %c_i29.addr
  %cmp2643 = icmp sge i64 %ld2642, 300
  %ar2644 = zext i1 %cmp2643 to i64
  %$t537_i30.addr = alloca i64
  store i64 %ar2644, ptr %$t537_i30.addr
  %ld2645 = load i64, ptr %c_i29.addr
  %cmp2646 = icmp slt i64 %ld2645, 400
  %ar2647 = zext i1 %cmp2646 to i64
  %$t538_i31.addr = alloca i64
  store i64 %ar2647, ptr %$t538_i31.addr
  %ld2648 = load i64, ptr %$t537_i30.addr
  %ld2649 = load i64, ptr %$t538_i31.addr
  %ar2650 = and i64 %ld2648, %ld2649
  ret i64 %ar2650
}

define ptr @Http.get_header$Response_V__3284$String(ptr %resp.arg, ptr %name.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld2651 = load ptr, ptr %name.addr
  %cr2652 = call ptr @march_string_to_lowercase(ptr %ld2651)
  %lower_name.addr = alloca ptr
  store ptr %cr2652, ptr %lower_name.addr
  %hp2653 = call ptr @march_alloc(i64 32)
  %tgp2654 = getelementptr i8, ptr %hp2653, i64 8
  store i32 0, ptr %tgp2654, align 4
  %fp2655 = getelementptr i8, ptr %hp2653, i64 16
  store ptr @find$apply$27, ptr %fp2655, align 8
  %ld2656 = load ptr, ptr %lower_name.addr
  %fp2657 = getelementptr i8, ptr %hp2653, i64 24
  store ptr %ld2656, ptr %fp2657, align 8
  %find.addr = alloca ptr
  store ptr %hp2653, ptr %find.addr
  %ld2658 = load ptr, ptr %resp.addr
  %cr2659 = call ptr @Http.response_headers$Response_V__2425(ptr %ld2658)
  %$t684.addr = alloca ptr
  store ptr %cr2659, ptr %$t684.addr
  %ld2660 = load ptr, ptr %find.addr
  %fp2661 = getelementptr i8, ptr %ld2660, i64 16
  %fv2662 = load ptr, ptr %fp2661, align 8
  %ld2663 = load ptr, ptr %$t684.addr
  %cr2664 = call ptr (ptr, ptr) %fv2662(ptr %ld2660, ptr %ld2663)
  ret ptr %cr2664
}

define i64 @Http.response_is_redirect$Response_V__3284(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2665 = load ptr, ptr %resp.addr
  %cr2666 = call ptr @Http.response_status$Response_V__2409(ptr %ld2665)
  %$t677.addr = alloca ptr
  store ptr %cr2666, ptr %$t677.addr
  %ld2667 = load ptr, ptr %$t677.addr
  %s_i32.addr = alloca ptr
  store ptr %ld2667, ptr %s_i32.addr
  %ld2668 = load ptr, ptr %s_i32.addr
  %cr2669 = call i64 @Http.status_code(ptr %ld2668)
  %c_i33.addr = alloca i64
  store i64 %cr2669, ptr %c_i33.addr
  %ld2670 = load i64, ptr %c_i33.addr
  %cmp2671 = icmp sge i64 %ld2670, 300
  %ar2672 = zext i1 %cmp2671 to i64
  %$t537_i34.addr = alloca i64
  store i64 %ar2672, ptr %$t537_i34.addr
  %ld2673 = load i64, ptr %c_i33.addr
  %cmp2674 = icmp slt i64 %ld2673, 400
  %ar2675 = zext i1 %cmp2674 to i64
  %$t538_i35.addr = alloca i64
  store i64 %ar2675, ptr %$t538_i35.addr
  %ld2676 = load i64, ptr %$t537_i34.addr
  %ld2677 = load i64, ptr %$t538_i35.addr
  %ar2678 = and i64 %ld2676, %ld2677
  ret i64 %ar2678
}

define ptr @HttpClient.reconnect_and_retry(ptr %req.arg, i64 %retries_left.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld2679 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2679)
  %ld2680 = load ptr, ptr %req.addr
  %cr2681 = call ptr @HttpTransport.connect$Request_String(ptr %ld2680)
  %$t983.addr = alloca ptr
  store ptr %cr2681, ptr %$t983.addr
  %ld2682 = load ptr, ptr %$t983.addr
  %res_slot2683 = alloca ptr
  %tgp2684 = getelementptr i8, ptr %ld2682, i64 8
  %tag2685 = load i32, ptr %tgp2684, align 4
  switch i32 %tag2685, label %case_default627 [
      i32 1, label %case_br628
      i32 0, label %case_br629
  ]
case_br628:
  %fp2686 = getelementptr i8, ptr %ld2682, i64 16
  %fv2687 = load ptr, ptr %fp2686, align 8
  %$f985.addr = alloca ptr
  store ptr %fv2687, ptr %$f985.addr
  %ld2688 = load ptr, ptr %$f985.addr
  %ce.addr = alloca ptr
  store ptr %ld2688, ptr %ce.addr
  %ld2689 = load ptr, ptr %$t983.addr
  %ld2690 = load ptr, ptr %ce.addr
  %rc2691 = load i64, ptr %ld2689, align 8
  %uniq2692 = icmp eq i64 %rc2691, 1
  %fbip_slot2693 = alloca ptr
  br i1 %uniq2692, label %fbip_reuse630, label %fbip_fresh631
fbip_reuse630:
  %tgp2694 = getelementptr i8, ptr %ld2689, i64 8
  store i32 1, ptr %tgp2694, align 4
  %fp2695 = getelementptr i8, ptr %ld2689, i64 16
  store ptr %ld2690, ptr %fp2695, align 8
  store ptr %ld2689, ptr %fbip_slot2693
  br label %fbip_merge632
fbip_fresh631:
  call void @march_decrc(ptr %ld2689)
  %hp2696 = call ptr @march_alloc(i64 24)
  %tgp2697 = getelementptr i8, ptr %hp2696, i64 8
  store i32 1, ptr %tgp2697, align 4
  %fp2698 = getelementptr i8, ptr %hp2696, i64 16
  store ptr %ld2690, ptr %fp2698, align 8
  store ptr %hp2696, ptr %fbip_slot2693
  br label %fbip_merge632
fbip_merge632:
  %fbip_r2699 = load ptr, ptr %fbip_slot2693
  store ptr %fbip_r2699, ptr %res_slot2683
  br label %case_merge626
case_br629:
  %fp2700 = getelementptr i8, ptr %ld2682, i64 16
  %fv2701 = load ptr, ptr %fp2700, align 8
  %$f986.addr = alloca ptr
  store ptr %fv2701, ptr %$f986.addr
  %freed2702 = call i64 @march_decrc_freed(ptr %ld2682)
  %freed_b2703 = icmp ne i64 %freed2702, 0
  br i1 %freed_b2703, label %br_unique633, label %br_shared634
br_shared634:
  call void @march_incrc(ptr %fv2701)
  br label %br_body635
br_unique633:
  br label %br_body635
br_body635:
  %ld2704 = load ptr, ptr %$f986.addr
  %new_fd.addr = alloca ptr
  store ptr %ld2704, ptr %new_fd.addr
  %ld2705 = load i64, ptr %retries_left.addr
  %ar2706 = sub i64 %ld2705, 1
  %$t984.addr = alloca i64
  store i64 %ar2706, ptr %$t984.addr
  %ld2707 = load ptr, ptr %new_fd.addr
  %ld2708 = load ptr, ptr %req.addr
  %ld2709 = load i64, ptr %$t984.addr
  %cr2710 = call ptr @HttpClient.transport_keepalive$V__3173$Request_String$Int(ptr %ld2707, ptr %ld2708, i64 %ld2709)
  store ptr %cr2710, ptr %res_slot2683
  br label %case_merge626
case_default627:
  unreachable
case_merge626:
  %case_r2711 = load ptr, ptr %res_slot2683
  ret ptr %case_r2711
}

define ptr @HttpTransport.request_on$V__3282$Request_String(ptr %fd.arg, ptr %req.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2712 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2712)
  %ld2713 = load ptr, ptr %req.addr
  %cr2714 = call ptr @Http.method$Request_String(ptr %ld2713)
  %$t783.addr = alloca ptr
  store ptr %cr2714, ptr %$t783.addr
  %ld2715 = load ptr, ptr %$t783.addr
  %cr2716 = call ptr @Http.method_to_string(ptr %ld2715)
  %meth.addr = alloca ptr
  store ptr %cr2716, ptr %meth.addr
  %ld2717 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2717)
  %ld2718 = load ptr, ptr %req.addr
  %cr2719 = call ptr @Http.host$Request_String(ptr %ld2718)
  %req_host.addr = alloca ptr
  store ptr %cr2719, ptr %req_host.addr
  %ld2720 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2720)
  %ld2721 = load ptr, ptr %req.addr
  %cr2722 = call ptr @Http.path$Request_String(ptr %ld2721)
  %req_path.addr = alloca ptr
  store ptr %cr2722, ptr %req_path.addr
  %ld2723 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2723)
  %ld2724 = load ptr, ptr %req.addr
  %cr2725 = call ptr @Http.query$Request_String(ptr %ld2724)
  %req_query.addr = alloca ptr
  store ptr %cr2725, ptr %req_query.addr
  %ld2726 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2726)
  %ld2727 = load ptr, ptr %req.addr
  %cr2728 = call ptr @Http.headers$Request_String(ptr %ld2727)
  %req_headers.addr = alloca ptr
  store ptr %cr2728, ptr %req_headers.addr
  %ld2729 = load ptr, ptr %req.addr
  %cr2730 = call ptr @Http.body$Request_String(ptr %ld2729)
  %req_body.addr = alloca ptr
  store ptr %cr2730, ptr %req_body.addr
  %ld2731 = load ptr, ptr %http_serialize_request.addr
  %fp2732 = getelementptr i8, ptr %ld2731, i64 16
  %fv2733 = load ptr, ptr %fp2732, align 8
  %ld2734 = load ptr, ptr %meth.addr
  %ld2735 = load ptr, ptr %req_host.addr
  %ld2736 = load ptr, ptr %req_path.addr
  %ld2737 = load ptr, ptr %req_query.addr
  %ld2738 = load ptr, ptr %req_headers.addr
  %ld2739 = load ptr, ptr %req_body.addr
  %cr2740 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv2733(ptr %ld2731, ptr %ld2734, ptr %ld2735, ptr %ld2736, ptr %ld2737, ptr %ld2738, ptr %ld2739)
  %raw_request.addr = alloca ptr
  store ptr %cr2740, ptr %raw_request.addr
  %ld2741 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld2741)
  %ld2742 = load ptr, ptr %tcp_send_all.addr
  %fp2743 = getelementptr i8, ptr %ld2742, i64 16
  %fv2744 = load ptr, ptr %fp2743, align 8
  %ld2745 = load ptr, ptr %fd.addr
  %ld2746 = load ptr, ptr %raw_request.addr
  %cr2747 = call ptr (ptr, ptr, ptr) %fv2744(ptr %ld2742, ptr %ld2745, ptr %ld2746)
  %$t784.addr = alloca ptr
  store ptr %cr2747, ptr %$t784.addr
  %ld2748 = load ptr, ptr %$t784.addr
  %res_slot2749 = alloca ptr
  %tgp2750 = getelementptr i8, ptr %ld2748, i64 8
  %tag2751 = load i32, ptr %tgp2750, align 4
  switch i32 %tag2751, label %case_default637 [
      i32 0, label %case_br638
      i32 0, label %case_br639
  ]
case_br638:
  %fp2752 = getelementptr i8, ptr %ld2748, i64 16
  %fv2753 = load ptr, ptr %fp2752, align 8
  %$f799.addr = alloca ptr
  store ptr %fv2753, ptr %$f799.addr
  %freed2754 = call i64 @march_decrc_freed(ptr %ld2748)
  %freed_b2755 = icmp ne i64 %freed2754, 0
  br i1 %freed_b2755, label %br_unique640, label %br_shared641
br_shared641:
  call void @march_incrc(ptr %fv2753)
  br label %br_body642
br_unique640:
  br label %br_body642
br_body642:
  %ld2756 = load ptr, ptr %$f799.addr
  %msg.addr = alloca ptr
  store ptr %ld2756, ptr %msg.addr
  %hp2757 = call ptr @march_alloc(i64 24)
  %tgp2758 = getelementptr i8, ptr %hp2757, i64 8
  store i32 2, ptr %tgp2758, align 4
  %ld2759 = load ptr, ptr %msg.addr
  %fp2760 = getelementptr i8, ptr %hp2757, i64 16
  store ptr %ld2759, ptr %fp2760, align 8
  %$t785.addr = alloca ptr
  store ptr %hp2757, ptr %$t785.addr
  %hp2761 = call ptr @march_alloc(i64 24)
  %tgp2762 = getelementptr i8, ptr %hp2761, i64 8
  store i32 1, ptr %tgp2762, align 4
  %ld2763 = load ptr, ptr %$t785.addr
  %fp2764 = getelementptr i8, ptr %hp2761, i64 16
  store ptr %ld2763, ptr %fp2764, align 8
  store ptr %hp2761, ptr %res_slot2749
  br label %case_merge636
case_br639:
  %fp2765 = getelementptr i8, ptr %ld2748, i64 16
  %fv2766 = load ptr, ptr %fp2765, align 8
  %$f800.addr = alloca ptr
  store ptr %fv2766, ptr %$f800.addr
  %freed2767 = call i64 @march_decrc_freed(ptr %ld2748)
  %freed_b2768 = icmp ne i64 %freed2767, 0
  br i1 %freed_b2768, label %br_unique643, label %br_shared644
br_shared644:
  call void @march_incrc(ptr %fv2766)
  br label %br_body645
br_unique643:
  br label %br_body645
br_body645:
  %ld2769 = load ptr, ptr %tcp_recv_http.addr
  %fp2770 = getelementptr i8, ptr %ld2769, i64 16
  %fv2771 = load ptr, ptr %fp2770, align 8
  %ld2772 = load ptr, ptr %fd.addr
  %cv2773 = inttoptr i64 1048576 to ptr
  %cr2774 = call ptr (ptr, ptr, ptr) %fv2771(ptr %ld2769, ptr %ld2772, ptr %cv2773)
  %$t786.addr = alloca ptr
  store ptr %cr2774, ptr %$t786.addr
  %ld2775 = load ptr, ptr %$t786.addr
  %res_slot2776 = alloca ptr
  %tgp2777 = getelementptr i8, ptr %ld2775, i64 8
  %tag2778 = load i32, ptr %tgp2777, align 4
  switch i32 %tag2778, label %case_default647 [
      i32 0, label %case_br648
      i32 0, label %case_br649
  ]
case_br648:
  %fp2779 = getelementptr i8, ptr %ld2775, i64 16
  %fv2780 = load ptr, ptr %fp2779, align 8
  %$f797.addr = alloca ptr
  store ptr %fv2780, ptr %$f797.addr
  %freed2781 = call i64 @march_decrc_freed(ptr %ld2775)
  %freed_b2782 = icmp ne i64 %freed2781, 0
  br i1 %freed_b2782, label %br_unique650, label %br_shared651
br_shared651:
  call void @march_incrc(ptr %fv2780)
  br label %br_body652
br_unique650:
  br label %br_body652
br_body652:
  %ld2783 = load ptr, ptr %$f797.addr
  %msg_1.addr = alloca ptr
  store ptr %ld2783, ptr %msg_1.addr
  %hp2784 = call ptr @march_alloc(i64 24)
  %tgp2785 = getelementptr i8, ptr %hp2784, i64 8
  store i32 3, ptr %tgp2785, align 4
  %ld2786 = load ptr, ptr %msg_1.addr
  %fp2787 = getelementptr i8, ptr %hp2784, i64 16
  store ptr %ld2786, ptr %fp2787, align 8
  %$t787.addr = alloca ptr
  store ptr %hp2784, ptr %$t787.addr
  %hp2788 = call ptr @march_alloc(i64 24)
  %tgp2789 = getelementptr i8, ptr %hp2788, i64 8
  store i32 1, ptr %tgp2789, align 4
  %ld2790 = load ptr, ptr %$t787.addr
  %fp2791 = getelementptr i8, ptr %hp2788, i64 16
  store ptr %ld2790, ptr %fp2791, align 8
  store ptr %hp2788, ptr %res_slot2776
  br label %case_merge646
case_br649:
  %fp2792 = getelementptr i8, ptr %ld2775, i64 16
  %fv2793 = load ptr, ptr %fp2792, align 8
  %$f798.addr = alloca ptr
  store ptr %fv2793, ptr %$f798.addr
  %freed2794 = call i64 @march_decrc_freed(ptr %ld2775)
  %freed_b2795 = icmp ne i64 %freed2794, 0
  br i1 %freed_b2795, label %br_unique653, label %br_shared654
br_shared654:
  call void @march_incrc(ptr %fv2793)
  br label %br_body655
br_unique653:
  br label %br_body655
br_body655:
  %ld2796 = load ptr, ptr %$f798.addr
  %raw_response.addr = alloca ptr
  store ptr %ld2796, ptr %raw_response.addr
  %ld2797 = load ptr, ptr %http_parse_response.addr
  %fp2798 = getelementptr i8, ptr %ld2797, i64 16
  %fv2799 = load ptr, ptr %fp2798, align 8
  %ld2800 = load ptr, ptr %raw_response.addr
  %cr2801 = call ptr (ptr, ptr) %fv2799(ptr %ld2797, ptr %ld2800)
  %$t788.addr = alloca ptr
  store ptr %cr2801, ptr %$t788.addr
  %ld2802 = load ptr, ptr %$t788.addr
  %res_slot2803 = alloca ptr
  %tgp2804 = getelementptr i8, ptr %ld2802, i64 8
  %tag2805 = load i32, ptr %tgp2804, align 4
  switch i32 %tag2805, label %case_default657 [
      i32 0, label %case_br658
      i32 0, label %case_br659
  ]
case_br658:
  %fp2806 = getelementptr i8, ptr %ld2802, i64 16
  %fv2807 = load ptr, ptr %fp2806, align 8
  %$f792.addr = alloca ptr
  store ptr %fv2807, ptr %$f792.addr
  %freed2808 = call i64 @march_decrc_freed(ptr %ld2802)
  %freed_b2809 = icmp ne i64 %freed2808, 0
  br i1 %freed_b2809, label %br_unique660, label %br_shared661
br_shared661:
  call void @march_incrc(ptr %fv2807)
  br label %br_body662
br_unique660:
  br label %br_body662
br_body662:
  %ld2810 = load ptr, ptr %$f792.addr
  %msg_2.addr = alloca ptr
  store ptr %ld2810, ptr %msg_2.addr
  %hp2811 = call ptr @march_alloc(i64 24)
  %tgp2812 = getelementptr i8, ptr %hp2811, i64 8
  store i32 0, ptr %tgp2812, align 4
  %ld2813 = load ptr, ptr %msg_2.addr
  %fp2814 = getelementptr i8, ptr %hp2811, i64 16
  store ptr %ld2813, ptr %fp2814, align 8
  %$t789.addr = alloca ptr
  store ptr %hp2811, ptr %$t789.addr
  %hp2815 = call ptr @march_alloc(i64 24)
  %tgp2816 = getelementptr i8, ptr %hp2815, i64 8
  store i32 1, ptr %tgp2816, align 4
  %ld2817 = load ptr, ptr %$t789.addr
  %fp2818 = getelementptr i8, ptr %hp2815, i64 16
  store ptr %ld2817, ptr %fp2818, align 8
  store ptr %hp2815, ptr %res_slot2803
  br label %case_merge656
case_br659:
  %fp2819 = getelementptr i8, ptr %ld2802, i64 16
  %fv2820 = load ptr, ptr %fp2819, align 8
  %$f793.addr = alloca ptr
  store ptr %fv2820, ptr %$f793.addr
  %freed2821 = call i64 @march_decrc_freed(ptr %ld2802)
  %freed_b2822 = icmp ne i64 %freed2821, 0
  br i1 %freed_b2822, label %br_unique663, label %br_shared664
br_shared664:
  call void @march_incrc(ptr %fv2820)
  br label %br_body665
br_unique663:
  br label %br_body665
br_body665:
  %ld2823 = load ptr, ptr %$f793.addr
  %res_slot2824 = alloca ptr
  %tgp2825 = getelementptr i8, ptr %ld2823, i64 8
  %tag2826 = load i32, ptr %tgp2825, align 4
  switch i32 %tag2826, label %case_default667 [
      i32 0, label %case_br668
  ]
case_br668:
  %fp2827 = getelementptr i8, ptr %ld2823, i64 16
  %fv2828 = load ptr, ptr %fp2827, align 8
  %$f794.addr = alloca ptr
  store ptr %fv2828, ptr %$f794.addr
  %fp2829 = getelementptr i8, ptr %ld2823, i64 24
  %fv2830 = load ptr, ptr %fp2829, align 8
  %$f795.addr = alloca ptr
  store ptr %fv2830, ptr %$f795.addr
  %fp2831 = getelementptr i8, ptr %ld2823, i64 32
  %fv2832 = load ptr, ptr %fp2831, align 8
  %$f796.addr = alloca ptr
  store ptr %fv2832, ptr %$f796.addr
  %freed2833 = call i64 @march_decrc_freed(ptr %ld2823)
  %freed_b2834 = icmp ne i64 %freed2833, 0
  br i1 %freed_b2834, label %br_unique669, label %br_shared670
br_shared670:
  call void @march_incrc(ptr %fv2832)
  call void @march_incrc(ptr %fv2830)
  call void @march_incrc(ptr %fv2828)
  br label %br_body671
br_unique669:
  br label %br_body671
br_body671:
  %ld2835 = load ptr, ptr %$f796.addr
  %resp_body.addr = alloca ptr
  store ptr %ld2835, ptr %resp_body.addr
  %ld2836 = load ptr, ptr %$f795.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld2836, ptr %resp_headers.addr
  %ld2837 = load ptr, ptr %$f794.addr
  %status_code.addr = alloca ptr
  store ptr %ld2837, ptr %status_code.addr
  %hp2838 = call ptr @march_alloc(i64 24)
  %tgp2839 = getelementptr i8, ptr %hp2838, i64 8
  store i32 0, ptr %tgp2839, align 4
  %ld2840 = load ptr, ptr %status_code.addr
  %fp2841 = getelementptr i8, ptr %hp2838, i64 16
  store ptr %ld2840, ptr %fp2841, align 8
  %$t790.addr = alloca ptr
  store ptr %hp2838, ptr %$t790.addr
  %hp2842 = call ptr @march_alloc(i64 40)
  %tgp2843 = getelementptr i8, ptr %hp2842, i64 8
  store i32 0, ptr %tgp2843, align 4
  %ld2844 = load ptr, ptr %$t790.addr
  %fp2845 = getelementptr i8, ptr %hp2842, i64 16
  store ptr %ld2844, ptr %fp2845, align 8
  %ld2846 = load ptr, ptr %resp_headers.addr
  %fp2847 = getelementptr i8, ptr %hp2842, i64 24
  store ptr %ld2846, ptr %fp2847, align 8
  %ld2848 = load ptr, ptr %resp_body.addr
  %fp2849 = getelementptr i8, ptr %hp2842, i64 32
  store ptr %ld2848, ptr %fp2849, align 8
  %$t791.addr = alloca ptr
  store ptr %hp2842, ptr %$t791.addr
  %hp2850 = call ptr @march_alloc(i64 24)
  %tgp2851 = getelementptr i8, ptr %hp2850, i64 8
  store i32 0, ptr %tgp2851, align 4
  %ld2852 = load ptr, ptr %$t791.addr
  %fp2853 = getelementptr i8, ptr %hp2850, i64 16
  store ptr %ld2852, ptr %fp2853, align 8
  store ptr %hp2850, ptr %res_slot2824
  br label %case_merge666
case_default667:
  unreachable
case_merge666:
  %case_r2854 = load ptr, ptr %res_slot2824
  store ptr %case_r2854, ptr %res_slot2803
  br label %case_merge656
case_default657:
  unreachable
case_merge656:
  %case_r2855 = load ptr, ptr %res_slot2803
  store ptr %case_r2855, ptr %res_slot2776
  br label %case_merge646
case_default647:
  unreachable
case_merge646:
  %case_r2856 = load ptr, ptr %res_slot2776
  store ptr %case_r2856, ptr %res_slot2749
  br label %case_merge636
case_default637:
  unreachable
case_merge636:
  %case_r2857 = load ptr, ptr %res_slot2749
  ret ptr %case_r2857
}

define ptr @Http.body$Request_V__2834(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2858 = load ptr, ptr %req.addr
  %res_slot2859 = alloca ptr
  %tgp2860 = getelementptr i8, ptr %ld2858, i64 8
  %tag2861 = load i32, ptr %tgp2860, align 4
  switch i32 %tag2861, label %case_default673 [
      i32 0, label %case_br674
  ]
case_br674:
  %fp2862 = getelementptr i8, ptr %ld2858, i64 16
  %fv2863 = load ptr, ptr %fp2862, align 8
  %$f599.addr = alloca ptr
  store ptr %fv2863, ptr %$f599.addr
  %fp2864 = getelementptr i8, ptr %ld2858, i64 24
  %fv2865 = load ptr, ptr %fp2864, align 8
  %$f600.addr = alloca ptr
  store ptr %fv2865, ptr %$f600.addr
  %fp2866 = getelementptr i8, ptr %ld2858, i64 32
  %fv2867 = load ptr, ptr %fp2866, align 8
  %$f601.addr = alloca ptr
  store ptr %fv2867, ptr %$f601.addr
  %fp2868 = getelementptr i8, ptr %ld2858, i64 40
  %fv2869 = load ptr, ptr %fp2868, align 8
  %$f602.addr = alloca ptr
  store ptr %fv2869, ptr %$f602.addr
  %fp2870 = getelementptr i8, ptr %ld2858, i64 48
  %fv2871 = load ptr, ptr %fp2870, align 8
  %$f603.addr = alloca ptr
  store ptr %fv2871, ptr %$f603.addr
  %fp2872 = getelementptr i8, ptr %ld2858, i64 56
  %fv2873 = load ptr, ptr %fp2872, align 8
  %$f604.addr = alloca ptr
  store ptr %fv2873, ptr %$f604.addr
  %fp2874 = getelementptr i8, ptr %ld2858, i64 64
  %fv2875 = load ptr, ptr %fp2874, align 8
  %$f605.addr = alloca ptr
  store ptr %fv2875, ptr %$f605.addr
  %fp2876 = getelementptr i8, ptr %ld2858, i64 72
  %fv2877 = load ptr, ptr %fp2876, align 8
  %$f606.addr = alloca ptr
  store ptr %fv2877, ptr %$f606.addr
  %freed2878 = call i64 @march_decrc_freed(ptr %ld2858)
  %freed_b2879 = icmp ne i64 %freed2878, 0
  br i1 %freed_b2879, label %br_unique675, label %br_shared676
br_shared676:
  call void @march_incrc(ptr %fv2877)
  call void @march_incrc(ptr %fv2875)
  call void @march_incrc(ptr %fv2873)
  call void @march_incrc(ptr %fv2871)
  call void @march_incrc(ptr %fv2869)
  call void @march_incrc(ptr %fv2867)
  call void @march_incrc(ptr %fv2865)
  call void @march_incrc(ptr %fv2863)
  br label %br_body677
br_unique675:
  br label %br_body677
br_body677:
  %ld2880 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld2880, ptr %b.addr
  %ld2881 = load ptr, ptr %b.addr
  store ptr %ld2881, ptr %res_slot2859
  br label %case_merge672
case_default673:
  unreachable
case_merge672:
  %case_r2882 = load ptr, ptr %res_slot2859
  ret ptr %case_r2882
}

define ptr @Http.headers$Request_V__2832(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2883 = load ptr, ptr %req.addr
  %res_slot2884 = alloca ptr
  %tgp2885 = getelementptr i8, ptr %ld2883, i64 8
  %tag2886 = load i32, ptr %tgp2885, align 4
  switch i32 %tag2886, label %case_default679 [
      i32 0, label %case_br680
  ]
case_br680:
  %fp2887 = getelementptr i8, ptr %ld2883, i64 16
  %fv2888 = load ptr, ptr %fp2887, align 8
  %$f591.addr = alloca ptr
  store ptr %fv2888, ptr %$f591.addr
  %fp2889 = getelementptr i8, ptr %ld2883, i64 24
  %fv2890 = load ptr, ptr %fp2889, align 8
  %$f592.addr = alloca ptr
  store ptr %fv2890, ptr %$f592.addr
  %fp2891 = getelementptr i8, ptr %ld2883, i64 32
  %fv2892 = load ptr, ptr %fp2891, align 8
  %$f593.addr = alloca ptr
  store ptr %fv2892, ptr %$f593.addr
  %fp2893 = getelementptr i8, ptr %ld2883, i64 40
  %fv2894 = load ptr, ptr %fp2893, align 8
  %$f594.addr = alloca ptr
  store ptr %fv2894, ptr %$f594.addr
  %fp2895 = getelementptr i8, ptr %ld2883, i64 48
  %fv2896 = load ptr, ptr %fp2895, align 8
  %$f595.addr = alloca ptr
  store ptr %fv2896, ptr %$f595.addr
  %fp2897 = getelementptr i8, ptr %ld2883, i64 56
  %fv2898 = load ptr, ptr %fp2897, align 8
  %$f596.addr = alloca ptr
  store ptr %fv2898, ptr %$f596.addr
  %fp2899 = getelementptr i8, ptr %ld2883, i64 64
  %fv2900 = load ptr, ptr %fp2899, align 8
  %$f597.addr = alloca ptr
  store ptr %fv2900, ptr %$f597.addr
  %fp2901 = getelementptr i8, ptr %ld2883, i64 72
  %fv2902 = load ptr, ptr %fp2901, align 8
  %$f598.addr = alloca ptr
  store ptr %fv2902, ptr %$f598.addr
  %freed2903 = call i64 @march_decrc_freed(ptr %ld2883)
  %freed_b2904 = icmp ne i64 %freed2903, 0
  br i1 %freed_b2904, label %br_unique681, label %br_shared682
br_shared682:
  call void @march_incrc(ptr %fv2902)
  call void @march_incrc(ptr %fv2900)
  call void @march_incrc(ptr %fv2898)
  call void @march_incrc(ptr %fv2896)
  call void @march_incrc(ptr %fv2894)
  call void @march_incrc(ptr %fv2892)
  call void @march_incrc(ptr %fv2890)
  call void @march_incrc(ptr %fv2888)
  br label %br_body683
br_unique681:
  br label %br_body683
br_body683:
  %ld2905 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld2905, ptr %h.addr
  %ld2906 = load ptr, ptr %h.addr
  store ptr %ld2906, ptr %res_slot2884
  br label %case_merge678
case_default679:
  unreachable
case_merge678:
  %case_r2907 = load ptr, ptr %res_slot2884
  ret ptr %case_r2907
}

define ptr @Http.query$Request_V__2830(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2908 = load ptr, ptr %req.addr
  %res_slot2909 = alloca ptr
  %tgp2910 = getelementptr i8, ptr %ld2908, i64 8
  %tag2911 = load i32, ptr %tgp2910, align 4
  switch i32 %tag2911, label %case_default685 [
      i32 0, label %case_br686
  ]
case_br686:
  %fp2912 = getelementptr i8, ptr %ld2908, i64 16
  %fv2913 = load ptr, ptr %fp2912, align 8
  %$f583.addr = alloca ptr
  store ptr %fv2913, ptr %$f583.addr
  %fp2914 = getelementptr i8, ptr %ld2908, i64 24
  %fv2915 = load ptr, ptr %fp2914, align 8
  %$f584.addr = alloca ptr
  store ptr %fv2915, ptr %$f584.addr
  %fp2916 = getelementptr i8, ptr %ld2908, i64 32
  %fv2917 = load ptr, ptr %fp2916, align 8
  %$f585.addr = alloca ptr
  store ptr %fv2917, ptr %$f585.addr
  %fp2918 = getelementptr i8, ptr %ld2908, i64 40
  %fv2919 = load ptr, ptr %fp2918, align 8
  %$f586.addr = alloca ptr
  store ptr %fv2919, ptr %$f586.addr
  %fp2920 = getelementptr i8, ptr %ld2908, i64 48
  %fv2921 = load ptr, ptr %fp2920, align 8
  %$f587.addr = alloca ptr
  store ptr %fv2921, ptr %$f587.addr
  %fp2922 = getelementptr i8, ptr %ld2908, i64 56
  %fv2923 = load ptr, ptr %fp2922, align 8
  %$f588.addr = alloca ptr
  store ptr %fv2923, ptr %$f588.addr
  %fp2924 = getelementptr i8, ptr %ld2908, i64 64
  %fv2925 = load ptr, ptr %fp2924, align 8
  %$f589.addr = alloca ptr
  store ptr %fv2925, ptr %$f589.addr
  %fp2926 = getelementptr i8, ptr %ld2908, i64 72
  %fv2927 = load ptr, ptr %fp2926, align 8
  %$f590.addr = alloca ptr
  store ptr %fv2927, ptr %$f590.addr
  %freed2928 = call i64 @march_decrc_freed(ptr %ld2908)
  %freed_b2929 = icmp ne i64 %freed2928, 0
  br i1 %freed_b2929, label %br_unique687, label %br_shared688
br_shared688:
  call void @march_incrc(ptr %fv2927)
  call void @march_incrc(ptr %fv2925)
  call void @march_incrc(ptr %fv2923)
  call void @march_incrc(ptr %fv2921)
  call void @march_incrc(ptr %fv2919)
  call void @march_incrc(ptr %fv2917)
  call void @march_incrc(ptr %fv2915)
  call void @march_incrc(ptr %fv2913)
  br label %br_body689
br_unique687:
  br label %br_body689
br_body689:
  %ld2930 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld2930, ptr %q.addr
  %ld2931 = load ptr, ptr %q.addr
  store ptr %ld2931, ptr %res_slot2909
  br label %case_merge684
case_default685:
  unreachable
case_merge684:
  %case_r2932 = load ptr, ptr %res_slot2909
  ret ptr %case_r2932
}

define ptr @Http.path$Request_V__2828(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2933 = load ptr, ptr %req.addr
  %res_slot2934 = alloca ptr
  %tgp2935 = getelementptr i8, ptr %ld2933, i64 8
  %tag2936 = load i32, ptr %tgp2935, align 4
  switch i32 %tag2936, label %case_default691 [
      i32 0, label %case_br692
  ]
case_br692:
  %fp2937 = getelementptr i8, ptr %ld2933, i64 16
  %fv2938 = load ptr, ptr %fp2937, align 8
  %$f575.addr = alloca ptr
  store ptr %fv2938, ptr %$f575.addr
  %fp2939 = getelementptr i8, ptr %ld2933, i64 24
  %fv2940 = load ptr, ptr %fp2939, align 8
  %$f576.addr = alloca ptr
  store ptr %fv2940, ptr %$f576.addr
  %fp2941 = getelementptr i8, ptr %ld2933, i64 32
  %fv2942 = load ptr, ptr %fp2941, align 8
  %$f577.addr = alloca ptr
  store ptr %fv2942, ptr %$f577.addr
  %fp2943 = getelementptr i8, ptr %ld2933, i64 40
  %fv2944 = load ptr, ptr %fp2943, align 8
  %$f578.addr = alloca ptr
  store ptr %fv2944, ptr %$f578.addr
  %fp2945 = getelementptr i8, ptr %ld2933, i64 48
  %fv2946 = load ptr, ptr %fp2945, align 8
  %$f579.addr = alloca ptr
  store ptr %fv2946, ptr %$f579.addr
  %fp2947 = getelementptr i8, ptr %ld2933, i64 56
  %fv2948 = load ptr, ptr %fp2947, align 8
  %$f580.addr = alloca ptr
  store ptr %fv2948, ptr %$f580.addr
  %fp2949 = getelementptr i8, ptr %ld2933, i64 64
  %fv2950 = load ptr, ptr %fp2949, align 8
  %$f581.addr = alloca ptr
  store ptr %fv2950, ptr %$f581.addr
  %fp2951 = getelementptr i8, ptr %ld2933, i64 72
  %fv2952 = load ptr, ptr %fp2951, align 8
  %$f582.addr = alloca ptr
  store ptr %fv2952, ptr %$f582.addr
  %freed2953 = call i64 @march_decrc_freed(ptr %ld2933)
  %freed_b2954 = icmp ne i64 %freed2953, 0
  br i1 %freed_b2954, label %br_unique693, label %br_shared694
br_shared694:
  call void @march_incrc(ptr %fv2952)
  call void @march_incrc(ptr %fv2950)
  call void @march_incrc(ptr %fv2948)
  call void @march_incrc(ptr %fv2946)
  call void @march_incrc(ptr %fv2944)
  call void @march_incrc(ptr %fv2942)
  call void @march_incrc(ptr %fv2940)
  call void @march_incrc(ptr %fv2938)
  br label %br_body695
br_unique693:
  br label %br_body695
br_body695:
  %ld2955 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld2955, ptr %p.addr
  %ld2956 = load ptr, ptr %p.addr
  store ptr %ld2956, ptr %res_slot2934
  br label %case_merge690
case_default691:
  unreachable
case_merge690:
  %case_r2957 = load ptr, ptr %res_slot2934
  ret ptr %case_r2957
}

define ptr @Http.method$Request_V__2826(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2958 = load ptr, ptr %req.addr
  %res_slot2959 = alloca ptr
  %tgp2960 = getelementptr i8, ptr %ld2958, i64 8
  %tag2961 = load i32, ptr %tgp2960, align 4
  switch i32 %tag2961, label %case_default697 [
      i32 0, label %case_br698
  ]
case_br698:
  %fp2962 = getelementptr i8, ptr %ld2958, i64 16
  %fv2963 = load ptr, ptr %fp2962, align 8
  %$f543.addr = alloca ptr
  store ptr %fv2963, ptr %$f543.addr
  %fp2964 = getelementptr i8, ptr %ld2958, i64 24
  %fv2965 = load ptr, ptr %fp2964, align 8
  %$f544.addr = alloca ptr
  store ptr %fv2965, ptr %$f544.addr
  %fp2966 = getelementptr i8, ptr %ld2958, i64 32
  %fv2967 = load ptr, ptr %fp2966, align 8
  %$f545.addr = alloca ptr
  store ptr %fv2967, ptr %$f545.addr
  %fp2968 = getelementptr i8, ptr %ld2958, i64 40
  %fv2969 = load ptr, ptr %fp2968, align 8
  %$f546.addr = alloca ptr
  store ptr %fv2969, ptr %$f546.addr
  %fp2970 = getelementptr i8, ptr %ld2958, i64 48
  %fv2971 = load ptr, ptr %fp2970, align 8
  %$f547.addr = alloca ptr
  store ptr %fv2971, ptr %$f547.addr
  %fp2972 = getelementptr i8, ptr %ld2958, i64 56
  %fv2973 = load ptr, ptr %fp2972, align 8
  %$f548.addr = alloca ptr
  store ptr %fv2973, ptr %$f548.addr
  %fp2974 = getelementptr i8, ptr %ld2958, i64 64
  %fv2975 = load ptr, ptr %fp2974, align 8
  %$f549.addr = alloca ptr
  store ptr %fv2975, ptr %$f549.addr
  %fp2976 = getelementptr i8, ptr %ld2958, i64 72
  %fv2977 = load ptr, ptr %fp2976, align 8
  %$f550.addr = alloca ptr
  store ptr %fv2977, ptr %$f550.addr
  %freed2978 = call i64 @march_decrc_freed(ptr %ld2958)
  %freed_b2979 = icmp ne i64 %freed2978, 0
  br i1 %freed_b2979, label %br_unique699, label %br_shared700
br_shared700:
  call void @march_incrc(ptr %fv2977)
  call void @march_incrc(ptr %fv2975)
  call void @march_incrc(ptr %fv2973)
  call void @march_incrc(ptr %fv2971)
  call void @march_incrc(ptr %fv2969)
  call void @march_incrc(ptr %fv2967)
  call void @march_incrc(ptr %fv2965)
  call void @march_incrc(ptr %fv2963)
  br label %br_body701
br_unique699:
  br label %br_body701
br_body701:
  %ld2980 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld2980, ptr %m.addr
  %ld2981 = load ptr, ptr %m.addr
  store ptr %ld2981, ptr %res_slot2959
  br label %case_merge696
case_default697:
  unreachable
case_merge696:
  %case_r2982 = load ptr, ptr %res_slot2959
  ret ptr %case_r2982
}

define ptr @Http.port$Request_V__2819(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2983 = load ptr, ptr %req.addr
  %res_slot2984 = alloca ptr
  %tgp2985 = getelementptr i8, ptr %ld2983, i64 8
  %tag2986 = load i32, ptr %tgp2985, align 4
  switch i32 %tag2986, label %case_default703 [
      i32 0, label %case_br704
  ]
case_br704:
  %fp2987 = getelementptr i8, ptr %ld2983, i64 16
  %fv2988 = load ptr, ptr %fp2987, align 8
  %$f567.addr = alloca ptr
  store ptr %fv2988, ptr %$f567.addr
  %fp2989 = getelementptr i8, ptr %ld2983, i64 24
  %fv2990 = load ptr, ptr %fp2989, align 8
  %$f568.addr = alloca ptr
  store ptr %fv2990, ptr %$f568.addr
  %fp2991 = getelementptr i8, ptr %ld2983, i64 32
  %fv2992 = load ptr, ptr %fp2991, align 8
  %$f569.addr = alloca ptr
  store ptr %fv2992, ptr %$f569.addr
  %fp2993 = getelementptr i8, ptr %ld2983, i64 40
  %fv2994 = load ptr, ptr %fp2993, align 8
  %$f570.addr = alloca ptr
  store ptr %fv2994, ptr %$f570.addr
  %fp2995 = getelementptr i8, ptr %ld2983, i64 48
  %fv2996 = load ptr, ptr %fp2995, align 8
  %$f571.addr = alloca ptr
  store ptr %fv2996, ptr %$f571.addr
  %fp2997 = getelementptr i8, ptr %ld2983, i64 56
  %fv2998 = load ptr, ptr %fp2997, align 8
  %$f572.addr = alloca ptr
  store ptr %fv2998, ptr %$f572.addr
  %fp2999 = getelementptr i8, ptr %ld2983, i64 64
  %fv3000 = load ptr, ptr %fp2999, align 8
  %$f573.addr = alloca ptr
  store ptr %fv3000, ptr %$f573.addr
  %fp3001 = getelementptr i8, ptr %ld2983, i64 72
  %fv3002 = load ptr, ptr %fp3001, align 8
  %$f574.addr = alloca ptr
  store ptr %fv3002, ptr %$f574.addr
  %freed3003 = call i64 @march_decrc_freed(ptr %ld2983)
  %freed_b3004 = icmp ne i64 %freed3003, 0
  br i1 %freed_b3004, label %br_unique705, label %br_shared706
br_shared706:
  call void @march_incrc(ptr %fv3002)
  call void @march_incrc(ptr %fv3000)
  call void @march_incrc(ptr %fv2998)
  call void @march_incrc(ptr %fv2996)
  call void @march_incrc(ptr %fv2994)
  call void @march_incrc(ptr %fv2992)
  call void @march_incrc(ptr %fv2990)
  call void @march_incrc(ptr %fv2988)
  br label %br_body707
br_unique705:
  br label %br_body707
br_body707:
  %ld3005 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld3005, ptr %p.addr
  %ld3006 = load ptr, ptr %p.addr
  store ptr %ld3006, ptr %res_slot2984
  br label %case_merge702
case_default703:
  unreachable
case_merge702:
  %case_r3007 = load ptr, ptr %res_slot2984
  ret ptr %case_r3007
}

define ptr @Http.host$Request_V__2816(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3008 = load ptr, ptr %req.addr
  %res_slot3009 = alloca ptr
  %tgp3010 = getelementptr i8, ptr %ld3008, i64 8
  %tag3011 = load i32, ptr %tgp3010, align 4
  switch i32 %tag3011, label %case_default709 [
      i32 0, label %case_br710
  ]
case_br710:
  %fp3012 = getelementptr i8, ptr %ld3008, i64 16
  %fv3013 = load ptr, ptr %fp3012, align 8
  %$f559.addr = alloca ptr
  store ptr %fv3013, ptr %$f559.addr
  %fp3014 = getelementptr i8, ptr %ld3008, i64 24
  %fv3015 = load ptr, ptr %fp3014, align 8
  %$f560.addr = alloca ptr
  store ptr %fv3015, ptr %$f560.addr
  %fp3016 = getelementptr i8, ptr %ld3008, i64 32
  %fv3017 = load ptr, ptr %fp3016, align 8
  %$f561.addr = alloca ptr
  store ptr %fv3017, ptr %$f561.addr
  %fp3018 = getelementptr i8, ptr %ld3008, i64 40
  %fv3019 = load ptr, ptr %fp3018, align 8
  %$f562.addr = alloca ptr
  store ptr %fv3019, ptr %$f562.addr
  %fp3020 = getelementptr i8, ptr %ld3008, i64 48
  %fv3021 = load ptr, ptr %fp3020, align 8
  %$f563.addr = alloca ptr
  store ptr %fv3021, ptr %$f563.addr
  %fp3022 = getelementptr i8, ptr %ld3008, i64 56
  %fv3023 = load ptr, ptr %fp3022, align 8
  %$f564.addr = alloca ptr
  store ptr %fv3023, ptr %$f564.addr
  %fp3024 = getelementptr i8, ptr %ld3008, i64 64
  %fv3025 = load ptr, ptr %fp3024, align 8
  %$f565.addr = alloca ptr
  store ptr %fv3025, ptr %$f565.addr
  %fp3026 = getelementptr i8, ptr %ld3008, i64 72
  %fv3027 = load ptr, ptr %fp3026, align 8
  %$f566.addr = alloca ptr
  store ptr %fv3027, ptr %$f566.addr
  %freed3028 = call i64 @march_decrc_freed(ptr %ld3008)
  %freed_b3029 = icmp ne i64 %freed3028, 0
  br i1 %freed_b3029, label %br_unique711, label %br_shared712
br_shared712:
  call void @march_incrc(ptr %fv3027)
  call void @march_incrc(ptr %fv3025)
  call void @march_incrc(ptr %fv3023)
  call void @march_incrc(ptr %fv3021)
  call void @march_incrc(ptr %fv3019)
  call void @march_incrc(ptr %fv3017)
  call void @march_incrc(ptr %fv3015)
  call void @march_incrc(ptr %fv3013)
  br label %br_body713
br_unique711:
  br label %br_body713
br_body713:
  %ld3030 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld3030, ptr %h.addr
  %ld3031 = load ptr, ptr %h.addr
  store ptr %ld3031, ptr %res_slot3009
  br label %case_merge708
case_default709:
  unreachable
case_merge708:
  %case_r3032 = load ptr, ptr %res_slot3009
  ret ptr %case_r3032
}

define ptr @Http.set_header$Request_String$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld3033 = load ptr, ptr %req.addr
  %res_slot3034 = alloca ptr
  %tgp3035 = getelementptr i8, ptr %ld3033, i64 8
  %tag3036 = load i32, ptr %tgp3035, align 4
  switch i32 %tag3036, label %case_default715 [
      i32 0, label %case_br716
  ]
case_br716:
  %fp3037 = getelementptr i8, ptr %ld3033, i64 16
  %fv3038 = load ptr, ptr %fp3037, align 8
  %$f658.addr = alloca ptr
  store ptr %fv3038, ptr %$f658.addr
  %fp3039 = getelementptr i8, ptr %ld3033, i64 24
  %fv3040 = load ptr, ptr %fp3039, align 8
  %$f659.addr = alloca ptr
  store ptr %fv3040, ptr %$f659.addr
  %fp3041 = getelementptr i8, ptr %ld3033, i64 32
  %fv3042 = load ptr, ptr %fp3041, align 8
  %$f660.addr = alloca ptr
  store ptr %fv3042, ptr %$f660.addr
  %fp3043 = getelementptr i8, ptr %ld3033, i64 40
  %fv3044 = load ptr, ptr %fp3043, align 8
  %$f661.addr = alloca ptr
  store ptr %fv3044, ptr %$f661.addr
  %fp3045 = getelementptr i8, ptr %ld3033, i64 48
  %fv3046 = load ptr, ptr %fp3045, align 8
  %$f662.addr = alloca ptr
  store ptr %fv3046, ptr %$f662.addr
  %fp3047 = getelementptr i8, ptr %ld3033, i64 56
  %fv3048 = load ptr, ptr %fp3047, align 8
  %$f663.addr = alloca ptr
  store ptr %fv3048, ptr %$f663.addr
  %fp3049 = getelementptr i8, ptr %ld3033, i64 64
  %fv3050 = load ptr, ptr %fp3049, align 8
  %$f664.addr = alloca ptr
  store ptr %fv3050, ptr %$f664.addr
  %fp3051 = getelementptr i8, ptr %ld3033, i64 72
  %fv3052 = load ptr, ptr %fp3051, align 8
  %$f665.addr = alloca ptr
  store ptr %fv3052, ptr %$f665.addr
  %ld3053 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld3053, ptr %bd.addr
  %ld3054 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld3054, ptr %hd.addr
  %ld3055 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld3055, ptr %q.addr
  %ld3056 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld3056, ptr %pa.addr
  %ld3057 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld3057, ptr %p.addr
  %ld3058 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld3058, ptr %h.addr
  %ld3059 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld3059, ptr %sc.addr
  %ld3060 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld3060, ptr %m.addr
  %hp3061 = call ptr @march_alloc(i64 32)
  %tgp3062 = getelementptr i8, ptr %hp3061, i64 8
  store i32 0, ptr %tgp3062, align 4
  %ld3063 = load ptr, ptr %name.addr
  %fp3064 = getelementptr i8, ptr %hp3061, i64 16
  store ptr %ld3063, ptr %fp3064, align 8
  %ld3065 = load ptr, ptr %value.addr
  %fp3066 = getelementptr i8, ptr %hp3061, i64 24
  store ptr %ld3065, ptr %fp3066, align 8
  %$t656.addr = alloca ptr
  store ptr %hp3061, ptr %$t656.addr
  %hp3067 = call ptr @march_alloc(i64 32)
  %tgp3068 = getelementptr i8, ptr %hp3067, i64 8
  store i32 1, ptr %tgp3068, align 4
  %ld3069 = load ptr, ptr %$t656.addr
  %fp3070 = getelementptr i8, ptr %hp3067, i64 16
  store ptr %ld3069, ptr %fp3070, align 8
  %ld3071 = load ptr, ptr %hd.addr
  %fp3072 = getelementptr i8, ptr %hp3067, i64 24
  store ptr %ld3071, ptr %fp3072, align 8
  %$t657.addr = alloca ptr
  store ptr %hp3067, ptr %$t657.addr
  %ld3073 = load ptr, ptr %req.addr
  %ld3074 = load ptr, ptr %m.addr
  %ld3075 = load ptr, ptr %sc.addr
  %ld3076 = load ptr, ptr %h.addr
  %ld3077 = load ptr, ptr %p.addr
  %ld3078 = load ptr, ptr %pa.addr
  %ld3079 = load ptr, ptr %q.addr
  %ld3080 = load ptr, ptr %$t657.addr
  %ld3081 = load ptr, ptr %bd.addr
  %rc3082 = load i64, ptr %ld3073, align 8
  %uniq3083 = icmp eq i64 %rc3082, 1
  %fbip_slot3084 = alloca ptr
  br i1 %uniq3083, label %fbip_reuse717, label %fbip_fresh718
fbip_reuse717:
  %tgp3085 = getelementptr i8, ptr %ld3073, i64 8
  store i32 0, ptr %tgp3085, align 4
  %fp3086 = getelementptr i8, ptr %ld3073, i64 16
  store ptr %ld3074, ptr %fp3086, align 8
  %fp3087 = getelementptr i8, ptr %ld3073, i64 24
  store ptr %ld3075, ptr %fp3087, align 8
  %fp3088 = getelementptr i8, ptr %ld3073, i64 32
  store ptr %ld3076, ptr %fp3088, align 8
  %fp3089 = getelementptr i8, ptr %ld3073, i64 40
  store ptr %ld3077, ptr %fp3089, align 8
  %fp3090 = getelementptr i8, ptr %ld3073, i64 48
  store ptr %ld3078, ptr %fp3090, align 8
  %fp3091 = getelementptr i8, ptr %ld3073, i64 56
  store ptr %ld3079, ptr %fp3091, align 8
  %fp3092 = getelementptr i8, ptr %ld3073, i64 64
  store ptr %ld3080, ptr %fp3092, align 8
  %fp3093 = getelementptr i8, ptr %ld3073, i64 72
  store ptr %ld3081, ptr %fp3093, align 8
  store ptr %ld3073, ptr %fbip_slot3084
  br label %fbip_merge719
fbip_fresh718:
  call void @march_decrc(ptr %ld3073)
  %hp3094 = call ptr @march_alloc(i64 80)
  %tgp3095 = getelementptr i8, ptr %hp3094, i64 8
  store i32 0, ptr %tgp3095, align 4
  %fp3096 = getelementptr i8, ptr %hp3094, i64 16
  store ptr %ld3074, ptr %fp3096, align 8
  %fp3097 = getelementptr i8, ptr %hp3094, i64 24
  store ptr %ld3075, ptr %fp3097, align 8
  %fp3098 = getelementptr i8, ptr %hp3094, i64 32
  store ptr %ld3076, ptr %fp3098, align 8
  %fp3099 = getelementptr i8, ptr %hp3094, i64 40
  store ptr %ld3077, ptr %fp3099, align 8
  %fp3100 = getelementptr i8, ptr %hp3094, i64 48
  store ptr %ld3078, ptr %fp3100, align 8
  %fp3101 = getelementptr i8, ptr %hp3094, i64 56
  store ptr %ld3079, ptr %fp3101, align 8
  %fp3102 = getelementptr i8, ptr %hp3094, i64 64
  store ptr %ld3080, ptr %fp3102, align 8
  %fp3103 = getelementptr i8, ptr %hp3094, i64 72
  store ptr %ld3081, ptr %fp3103, align 8
  store ptr %hp3094, ptr %fbip_slot3084
  br label %fbip_merge719
fbip_merge719:
  %fbip_r3104 = load ptr, ptr %fbip_slot3084
  store ptr %fbip_r3104, ptr %res_slot3034
  br label %case_merge714
case_default715:
  unreachable
case_merge714:
  %case_r3105 = load ptr, ptr %res_slot3034
  ret ptr %case_r3105
}

define ptr @Http.response_headers$Response_V__2425(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld3106 = load ptr, ptr %resp.addr
  %res_slot3107 = alloca ptr
  %tgp3108 = getelementptr i8, ptr %ld3106, i64 8
  %tag3109 = load i32, ptr %tgp3108, align 4
  switch i32 %tag3109, label %case_default721 [
      i32 0, label %case_br722
  ]
case_br722:
  %fp3110 = getelementptr i8, ptr %ld3106, i64 16
  %fv3111 = load ptr, ptr %fp3110, align 8
  %$f669.addr = alloca ptr
  store ptr %fv3111, ptr %$f669.addr
  %fp3112 = getelementptr i8, ptr %ld3106, i64 24
  %fv3113 = load ptr, ptr %fp3112, align 8
  %$f670.addr = alloca ptr
  store ptr %fv3113, ptr %$f670.addr
  %fp3114 = getelementptr i8, ptr %ld3106, i64 32
  %fv3115 = load ptr, ptr %fp3114, align 8
  %$f671.addr = alloca ptr
  store ptr %fv3115, ptr %$f671.addr
  %freed3116 = call i64 @march_decrc_freed(ptr %ld3106)
  %freed_b3117 = icmp ne i64 %freed3116, 0
  br i1 %freed_b3117, label %br_unique723, label %br_shared724
br_shared724:
  call void @march_incrc(ptr %fv3115)
  call void @march_incrc(ptr %fv3113)
  call void @march_incrc(ptr %fv3111)
  br label %br_body725
br_unique723:
  br label %br_body725
br_body725:
  %ld3118 = load ptr, ptr %$f670.addr
  %h.addr = alloca ptr
  store ptr %ld3118, ptr %h.addr
  %ld3119 = load ptr, ptr %h.addr
  store ptr %ld3119, ptr %res_slot3107
  br label %case_merge720
case_default721:
  unreachable
case_merge720:
  %case_r3120 = load ptr, ptr %res_slot3107
  ret ptr %case_r3120
}

define ptr @Http.response_status$Response_V__2409(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld3121 = load ptr, ptr %resp.addr
  %res_slot3122 = alloca ptr
  %tgp3123 = getelementptr i8, ptr %ld3121, i64 8
  %tag3124 = load i32, ptr %tgp3123, align 4
  switch i32 %tag3124, label %case_default727 [
      i32 0, label %case_br728
  ]
case_br728:
  %fp3125 = getelementptr i8, ptr %ld3121, i64 16
  %fv3126 = load ptr, ptr %fp3125, align 8
  %$f666.addr = alloca ptr
  store ptr %fv3126, ptr %$f666.addr
  %fp3127 = getelementptr i8, ptr %ld3121, i64 24
  %fv3128 = load ptr, ptr %fp3127, align 8
  %$f667.addr = alloca ptr
  store ptr %fv3128, ptr %$f667.addr
  %fp3129 = getelementptr i8, ptr %ld3121, i64 32
  %fv3130 = load ptr, ptr %fp3129, align 8
  %$f668.addr = alloca ptr
  store ptr %fv3130, ptr %$f668.addr
  %freed3131 = call i64 @march_decrc_freed(ptr %ld3121)
  %freed_b3132 = icmp ne i64 %freed3131, 0
  br i1 %freed_b3132, label %br_unique729, label %br_shared730
br_shared730:
  call void @march_incrc(ptr %fv3130)
  call void @march_incrc(ptr %fv3128)
  call void @march_incrc(ptr %fv3126)
  br label %br_body731
br_unique729:
  br label %br_body731
br_body731:
  %ld3133 = load ptr, ptr %$f666.addr
  %s.addr = alloca ptr
  store ptr %ld3133, ptr %s.addr
  %ld3134 = load ptr, ptr %s.addr
  store ptr %ld3134, ptr %res_slot3122
  br label %case_merge726
case_default727:
  unreachable
case_merge726:
  %case_r3135 = load ptr, ptr %res_slot3122
  ret ptr %case_r3135
}

define ptr @HttpClient.transport_keepalive$V__3173$Request_String$Int(ptr %fd.arg, ptr %req.arg, i64 %retries_left.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld3136 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld3136)
  %ld3137 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3137)
  %ld3138 = load ptr, ptr %fd.addr
  %ld3139 = load ptr, ptr %req.addr
  %cr3140 = call ptr @HttpTransport.request_on$V__3173$Request_String(ptr %ld3138, ptr %ld3139)
  %$t987.addr = alloca ptr
  store ptr %cr3140, ptr %$t987.addr
  %ld3141 = load ptr, ptr %$t987.addr
  %res_slot3142 = alloca ptr
  %tgp3143 = getelementptr i8, ptr %ld3141, i64 8
  %tag3144 = load i32, ptr %tgp3143, align 4
  switch i32 %tag3144, label %case_default733 [
      i32 0, label %case_br734
      i32 1, label %case_br735
  ]
case_br734:
  %fp3145 = getelementptr i8, ptr %ld3141, i64 16
  %fv3146 = load ptr, ptr %fp3145, align 8
  %$f992.addr = alloca ptr
  store ptr %fv3146, ptr %$f992.addr
  %ld3147 = load ptr, ptr %$f992.addr
  %resp.addr = alloca ptr
  store ptr %ld3147, ptr %resp.addr
  %hp3148 = call ptr @march_alloc(i64 32)
  %tgp3149 = getelementptr i8, ptr %hp3148, i64 8
  store i32 0, ptr %tgp3149, align 4
  %ld3150 = load ptr, ptr %fd.addr
  %fp3151 = getelementptr i8, ptr %hp3148, i64 16
  store ptr %ld3150, ptr %fp3151, align 8
  %ld3152 = load ptr, ptr %resp.addr
  %fp3153 = getelementptr i8, ptr %hp3148, i64 24
  store ptr %ld3152, ptr %fp3153, align 8
  %$t988.addr = alloca ptr
  store ptr %hp3148, ptr %$t988.addr
  %ld3154 = load ptr, ptr %$t987.addr
  %ld3155 = load ptr, ptr %$t988.addr
  %rc3156 = load i64, ptr %ld3154, align 8
  %uniq3157 = icmp eq i64 %rc3156, 1
  %fbip_slot3158 = alloca ptr
  br i1 %uniq3157, label %fbip_reuse736, label %fbip_fresh737
fbip_reuse736:
  %tgp3159 = getelementptr i8, ptr %ld3154, i64 8
  store i32 0, ptr %tgp3159, align 4
  %fp3160 = getelementptr i8, ptr %ld3154, i64 16
  store ptr %ld3155, ptr %fp3160, align 8
  store ptr %ld3154, ptr %fbip_slot3158
  br label %fbip_merge738
fbip_fresh737:
  call void @march_decrc(ptr %ld3154)
  %hp3161 = call ptr @march_alloc(i64 24)
  %tgp3162 = getelementptr i8, ptr %hp3161, i64 8
  store i32 0, ptr %tgp3162, align 4
  %fp3163 = getelementptr i8, ptr %hp3161, i64 16
  store ptr %ld3155, ptr %fp3163, align 8
  store ptr %hp3161, ptr %fbip_slot3158
  br label %fbip_merge738
fbip_merge738:
  %fbip_r3164 = load ptr, ptr %fbip_slot3158
  store ptr %fbip_r3164, ptr %res_slot3142
  br label %case_merge732
case_br735:
  %fp3165 = getelementptr i8, ptr %ld3141, i64 16
  %fv3166 = load ptr, ptr %fp3165, align 8
  %$f993.addr = alloca ptr
  store ptr %fv3166, ptr %$f993.addr
  %freed3167 = call i64 @march_decrc_freed(ptr %ld3141)
  %freed_b3168 = icmp ne i64 %freed3167, 0
  br i1 %freed_b3168, label %br_unique739, label %br_shared740
br_shared740:
  call void @march_incrc(ptr %fv3166)
  br label %br_body741
br_unique739:
  br label %br_body741
br_body741:
  %ld3169 = load ptr, ptr %tcp_close.addr
  %fp3170 = getelementptr i8, ptr %ld3169, i64 16
  %fv3171 = load ptr, ptr %fp3170, align 8
  %ld3172 = load ptr, ptr %fd.addr
  %cr3173 = call ptr (ptr, ptr) %fv3171(ptr %ld3169, ptr %ld3172)
  %ld3174 = load i64, ptr %retries_left.addr
  %cmp3175 = icmp sgt i64 %ld3174, 0
  %ar3176 = zext i1 %cmp3175 to i64
  %$t989.addr = alloca i64
  store i64 %ar3176, ptr %$t989.addr
  %ld3177 = load i64, ptr %$t989.addr
  %res_slot3178 = alloca ptr
  %bi3179 = trunc i64 %ld3177 to i1
  br i1 %bi3179, label %case_br744, label %case_default743
case_br744:
  %ld3180 = load i64, ptr %retries_left.addr
  %ar3181 = sub i64 %ld3180, 1
  %$t990.addr = alloca i64
  store i64 %ar3181, ptr %$t990.addr
  %ld3182 = load ptr, ptr %req.addr
  %ld3183 = load i64, ptr %$t990.addr
  %cr3184 = call ptr @HttpClient.reconnect_and_retry(ptr %ld3182, i64 %ld3183)
  store ptr %cr3184, ptr %res_slot3178
  br label %case_merge742
case_default743:
  %hp3185 = call ptr @march_alloc(i64 16)
  %tgp3186 = getelementptr i8, ptr %hp3185, i64 8
  store i32 0, ptr %tgp3186, align 4
  %$t991.addr = alloca ptr
  store ptr %hp3185, ptr %$t991.addr
  %hp3187 = call ptr @march_alloc(i64 24)
  %tgp3188 = getelementptr i8, ptr %hp3187, i64 8
  store i32 1, ptr %tgp3188, align 4
  %ld3189 = load ptr, ptr %$t991.addr
  %fp3190 = getelementptr i8, ptr %hp3187, i64 16
  store ptr %ld3189, ptr %fp3190, align 8
  store ptr %hp3187, ptr %res_slot3178
  br label %case_merge742
case_merge742:
  %case_r3191 = load ptr, ptr %res_slot3178
  store ptr %case_r3191, ptr %res_slot3142
  br label %case_merge732
case_default733:
  unreachable
case_merge732:
  %case_r3192 = load ptr, ptr %res_slot3142
  ret ptr %case_r3192
}

define ptr @HttpTransport.connect$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3193 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3193)
  %ld3194 = load ptr, ptr %req.addr
  %cr3195 = call ptr @Http.host$Request_String(ptr %ld3194)
  %req_host.addr = alloca ptr
  store ptr %cr3195, ptr %req_host.addr
  %ld3196 = load ptr, ptr %req.addr
  %cr3197 = call ptr @Http.port$Request_String(ptr %ld3196)
  %$t777.addr = alloca ptr
  store ptr %cr3197, ptr %$t777.addr
  %ld3198 = load ptr, ptr %$t777.addr
  %res_slot3199 = alloca ptr
  %tgp3200 = getelementptr i8, ptr %ld3198, i64 8
  %tag3201 = load i32, ptr %tgp3200, align 4
  switch i32 %tag3201, label %case_default746 [
      i32 1, label %case_br747
      i32 0, label %case_br748
  ]
case_br747:
  %fp3202 = getelementptr i8, ptr %ld3198, i64 16
  %fv3203 = load ptr, ptr %fp3202, align 8
  %$f778.addr = alloca ptr
  store ptr %fv3203, ptr %$f778.addr
  %ld3204 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld3204)
  %ld3205 = load ptr, ptr %$f778.addr
  %p.addr = alloca ptr
  store ptr %ld3205, ptr %p.addr
  %ld3206 = load ptr, ptr %p.addr
  store ptr %ld3206, ptr %res_slot3199
  br label %case_merge745
case_br748:
  %ld3207 = load ptr, ptr %$t777.addr
  call void @march_decrc(ptr %ld3207)
  %cv3208 = inttoptr i64 80 to ptr
  store ptr %cv3208, ptr %res_slot3199
  br label %case_merge745
case_default746:
  unreachable
case_merge745:
  %case_r3209 = load ptr, ptr %res_slot3199
  %cv3210 = ptrtoint ptr %case_r3209 to i64
  %req_port.addr = alloca i64
  store i64 %cv3210, ptr %req_port.addr
  %ld3211 = load ptr, ptr %tcp_connect.addr
  %fp3212 = getelementptr i8, ptr %ld3211, i64 16
  %fv3213 = load ptr, ptr %fp3212, align 8
  %ld3214 = load ptr, ptr %req_host.addr
  %ld3215 = load i64, ptr %req_port.addr
  %cv3216 = inttoptr i64 %ld3215 to ptr
  %cr3217 = call ptr (ptr, ptr, ptr) %fv3213(ptr %ld3211, ptr %ld3214, ptr %cv3216)
  %$t779.addr = alloca ptr
  store ptr %cr3217, ptr %$t779.addr
  %ld3218 = load ptr, ptr %$t779.addr
  %res_slot3219 = alloca ptr
  %tgp3220 = getelementptr i8, ptr %ld3218, i64 8
  %tag3221 = load i32, ptr %tgp3220, align 4
  switch i32 %tag3221, label %case_default750 [
      i32 0, label %case_br751
      i32 0, label %case_br752
  ]
case_br751:
  %fp3222 = getelementptr i8, ptr %ld3218, i64 16
  %fv3223 = load ptr, ptr %fp3222, align 8
  %$f781.addr = alloca ptr
  store ptr %fv3223, ptr %$f781.addr
  %freed3224 = call i64 @march_decrc_freed(ptr %ld3218)
  %freed_b3225 = icmp ne i64 %freed3224, 0
  br i1 %freed_b3225, label %br_unique753, label %br_shared754
br_shared754:
  call void @march_incrc(ptr %fv3223)
  br label %br_body755
br_unique753:
  br label %br_body755
br_body755:
  %ld3226 = load ptr, ptr %$f781.addr
  %msg.addr = alloca ptr
  store ptr %ld3226, ptr %msg.addr
  %hp3227 = call ptr @march_alloc(i64 24)
  %tgp3228 = getelementptr i8, ptr %hp3227, i64 8
  store i32 0, ptr %tgp3228, align 4
  %ld3229 = load ptr, ptr %msg.addr
  %fp3230 = getelementptr i8, ptr %hp3227, i64 16
  store ptr %ld3229, ptr %fp3230, align 8
  %$t780.addr = alloca ptr
  store ptr %hp3227, ptr %$t780.addr
  %hp3231 = call ptr @march_alloc(i64 24)
  %tgp3232 = getelementptr i8, ptr %hp3231, i64 8
  store i32 1, ptr %tgp3232, align 4
  %ld3233 = load ptr, ptr %$t780.addr
  %fp3234 = getelementptr i8, ptr %hp3231, i64 16
  store ptr %ld3233, ptr %fp3234, align 8
  store ptr %hp3231, ptr %res_slot3219
  br label %case_merge749
case_br752:
  %fp3235 = getelementptr i8, ptr %ld3218, i64 16
  %fv3236 = load ptr, ptr %fp3235, align 8
  %$f782.addr = alloca ptr
  store ptr %fv3236, ptr %$f782.addr
  %freed3237 = call i64 @march_decrc_freed(ptr %ld3218)
  %freed_b3238 = icmp ne i64 %freed3237, 0
  br i1 %freed_b3238, label %br_unique756, label %br_shared757
br_shared757:
  call void @march_incrc(ptr %fv3236)
  br label %br_body758
br_unique756:
  br label %br_body758
br_body758:
  %ld3239 = load ptr, ptr %$f782.addr
  %fd.addr = alloca ptr
  store ptr %ld3239, ptr %fd.addr
  %hp3240 = call ptr @march_alloc(i64 24)
  %tgp3241 = getelementptr i8, ptr %hp3240, i64 8
  store i32 0, ptr %tgp3241, align 4
  %ld3242 = load ptr, ptr %fd.addr
  %fp3243 = getelementptr i8, ptr %hp3240, i64 16
  store ptr %ld3242, ptr %fp3243, align 8
  store ptr %hp3240, ptr %res_slot3219
  br label %case_merge749
case_default750:
  unreachable
case_merge749:
  %case_r3244 = load ptr, ptr %res_slot3219
  ret ptr %case_r3244
}

define ptr @Http.body$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3245 = load ptr, ptr %req.addr
  %res_slot3246 = alloca ptr
  %tgp3247 = getelementptr i8, ptr %ld3245, i64 8
  %tag3248 = load i32, ptr %tgp3247, align 4
  switch i32 %tag3248, label %case_default760 [
      i32 0, label %case_br761
  ]
case_br761:
  %fp3249 = getelementptr i8, ptr %ld3245, i64 16
  %fv3250 = load ptr, ptr %fp3249, align 8
  %$f599.addr = alloca ptr
  store ptr %fv3250, ptr %$f599.addr
  %fp3251 = getelementptr i8, ptr %ld3245, i64 24
  %fv3252 = load ptr, ptr %fp3251, align 8
  %$f600.addr = alloca ptr
  store ptr %fv3252, ptr %$f600.addr
  %fp3253 = getelementptr i8, ptr %ld3245, i64 32
  %fv3254 = load ptr, ptr %fp3253, align 8
  %$f601.addr = alloca ptr
  store ptr %fv3254, ptr %$f601.addr
  %fp3255 = getelementptr i8, ptr %ld3245, i64 40
  %fv3256 = load ptr, ptr %fp3255, align 8
  %$f602.addr = alloca ptr
  store ptr %fv3256, ptr %$f602.addr
  %fp3257 = getelementptr i8, ptr %ld3245, i64 48
  %fv3258 = load ptr, ptr %fp3257, align 8
  %$f603.addr = alloca ptr
  store ptr %fv3258, ptr %$f603.addr
  %fp3259 = getelementptr i8, ptr %ld3245, i64 56
  %fv3260 = load ptr, ptr %fp3259, align 8
  %$f604.addr = alloca ptr
  store ptr %fv3260, ptr %$f604.addr
  %fp3261 = getelementptr i8, ptr %ld3245, i64 64
  %fv3262 = load ptr, ptr %fp3261, align 8
  %$f605.addr = alloca ptr
  store ptr %fv3262, ptr %$f605.addr
  %fp3263 = getelementptr i8, ptr %ld3245, i64 72
  %fv3264 = load ptr, ptr %fp3263, align 8
  %$f606.addr = alloca ptr
  store ptr %fv3264, ptr %$f606.addr
  %freed3265 = call i64 @march_decrc_freed(ptr %ld3245)
  %freed_b3266 = icmp ne i64 %freed3265, 0
  br i1 %freed_b3266, label %br_unique762, label %br_shared763
br_shared763:
  call void @march_incrc(ptr %fv3264)
  call void @march_incrc(ptr %fv3262)
  call void @march_incrc(ptr %fv3260)
  call void @march_incrc(ptr %fv3258)
  call void @march_incrc(ptr %fv3256)
  call void @march_incrc(ptr %fv3254)
  call void @march_incrc(ptr %fv3252)
  call void @march_incrc(ptr %fv3250)
  br label %br_body764
br_unique762:
  br label %br_body764
br_body764:
  %ld3267 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld3267, ptr %b.addr
  %ld3268 = load ptr, ptr %b.addr
  store ptr %ld3268, ptr %res_slot3246
  br label %case_merge759
case_default760:
  unreachable
case_merge759:
  %case_r3269 = load ptr, ptr %res_slot3246
  ret ptr %case_r3269
}

define ptr @Http.query$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3270 = load ptr, ptr %req.addr
  %res_slot3271 = alloca ptr
  %tgp3272 = getelementptr i8, ptr %ld3270, i64 8
  %tag3273 = load i32, ptr %tgp3272, align 4
  switch i32 %tag3273, label %case_default766 [
      i32 0, label %case_br767
  ]
case_br767:
  %fp3274 = getelementptr i8, ptr %ld3270, i64 16
  %fv3275 = load ptr, ptr %fp3274, align 8
  %$f583.addr = alloca ptr
  store ptr %fv3275, ptr %$f583.addr
  %fp3276 = getelementptr i8, ptr %ld3270, i64 24
  %fv3277 = load ptr, ptr %fp3276, align 8
  %$f584.addr = alloca ptr
  store ptr %fv3277, ptr %$f584.addr
  %fp3278 = getelementptr i8, ptr %ld3270, i64 32
  %fv3279 = load ptr, ptr %fp3278, align 8
  %$f585.addr = alloca ptr
  store ptr %fv3279, ptr %$f585.addr
  %fp3280 = getelementptr i8, ptr %ld3270, i64 40
  %fv3281 = load ptr, ptr %fp3280, align 8
  %$f586.addr = alloca ptr
  store ptr %fv3281, ptr %$f586.addr
  %fp3282 = getelementptr i8, ptr %ld3270, i64 48
  %fv3283 = load ptr, ptr %fp3282, align 8
  %$f587.addr = alloca ptr
  store ptr %fv3283, ptr %$f587.addr
  %fp3284 = getelementptr i8, ptr %ld3270, i64 56
  %fv3285 = load ptr, ptr %fp3284, align 8
  %$f588.addr = alloca ptr
  store ptr %fv3285, ptr %$f588.addr
  %fp3286 = getelementptr i8, ptr %ld3270, i64 64
  %fv3287 = load ptr, ptr %fp3286, align 8
  %$f589.addr = alloca ptr
  store ptr %fv3287, ptr %$f589.addr
  %fp3288 = getelementptr i8, ptr %ld3270, i64 72
  %fv3289 = load ptr, ptr %fp3288, align 8
  %$f590.addr = alloca ptr
  store ptr %fv3289, ptr %$f590.addr
  %freed3290 = call i64 @march_decrc_freed(ptr %ld3270)
  %freed_b3291 = icmp ne i64 %freed3290, 0
  br i1 %freed_b3291, label %br_unique768, label %br_shared769
br_shared769:
  call void @march_incrc(ptr %fv3289)
  call void @march_incrc(ptr %fv3287)
  call void @march_incrc(ptr %fv3285)
  call void @march_incrc(ptr %fv3283)
  call void @march_incrc(ptr %fv3281)
  call void @march_incrc(ptr %fv3279)
  call void @march_incrc(ptr %fv3277)
  call void @march_incrc(ptr %fv3275)
  br label %br_body770
br_unique768:
  br label %br_body770
br_body770:
  %ld3292 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld3292, ptr %q.addr
  %ld3293 = load ptr, ptr %q.addr
  store ptr %ld3293, ptr %res_slot3271
  br label %case_merge765
case_default766:
  unreachable
case_merge765:
  %case_r3294 = load ptr, ptr %res_slot3271
  ret ptr %case_r3294
}

define ptr @Http.path$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3295 = load ptr, ptr %req.addr
  %res_slot3296 = alloca ptr
  %tgp3297 = getelementptr i8, ptr %ld3295, i64 8
  %tag3298 = load i32, ptr %tgp3297, align 4
  switch i32 %tag3298, label %case_default772 [
      i32 0, label %case_br773
  ]
case_br773:
  %fp3299 = getelementptr i8, ptr %ld3295, i64 16
  %fv3300 = load ptr, ptr %fp3299, align 8
  %$f575.addr = alloca ptr
  store ptr %fv3300, ptr %$f575.addr
  %fp3301 = getelementptr i8, ptr %ld3295, i64 24
  %fv3302 = load ptr, ptr %fp3301, align 8
  %$f576.addr = alloca ptr
  store ptr %fv3302, ptr %$f576.addr
  %fp3303 = getelementptr i8, ptr %ld3295, i64 32
  %fv3304 = load ptr, ptr %fp3303, align 8
  %$f577.addr = alloca ptr
  store ptr %fv3304, ptr %$f577.addr
  %fp3305 = getelementptr i8, ptr %ld3295, i64 40
  %fv3306 = load ptr, ptr %fp3305, align 8
  %$f578.addr = alloca ptr
  store ptr %fv3306, ptr %$f578.addr
  %fp3307 = getelementptr i8, ptr %ld3295, i64 48
  %fv3308 = load ptr, ptr %fp3307, align 8
  %$f579.addr = alloca ptr
  store ptr %fv3308, ptr %$f579.addr
  %fp3309 = getelementptr i8, ptr %ld3295, i64 56
  %fv3310 = load ptr, ptr %fp3309, align 8
  %$f580.addr = alloca ptr
  store ptr %fv3310, ptr %$f580.addr
  %fp3311 = getelementptr i8, ptr %ld3295, i64 64
  %fv3312 = load ptr, ptr %fp3311, align 8
  %$f581.addr = alloca ptr
  store ptr %fv3312, ptr %$f581.addr
  %fp3313 = getelementptr i8, ptr %ld3295, i64 72
  %fv3314 = load ptr, ptr %fp3313, align 8
  %$f582.addr = alloca ptr
  store ptr %fv3314, ptr %$f582.addr
  %freed3315 = call i64 @march_decrc_freed(ptr %ld3295)
  %freed_b3316 = icmp ne i64 %freed3315, 0
  br i1 %freed_b3316, label %br_unique774, label %br_shared775
br_shared775:
  call void @march_incrc(ptr %fv3314)
  call void @march_incrc(ptr %fv3312)
  call void @march_incrc(ptr %fv3310)
  call void @march_incrc(ptr %fv3308)
  call void @march_incrc(ptr %fv3306)
  call void @march_incrc(ptr %fv3304)
  call void @march_incrc(ptr %fv3302)
  call void @march_incrc(ptr %fv3300)
  br label %br_body776
br_unique774:
  br label %br_body776
br_body776:
  %ld3317 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld3317, ptr %p.addr
  %ld3318 = load ptr, ptr %p.addr
  store ptr %ld3318, ptr %res_slot3296
  br label %case_merge771
case_default772:
  unreachable
case_merge771:
  %case_r3319 = load ptr, ptr %res_slot3296
  ret ptr %case_r3319
}

define ptr @Http.host$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3320 = load ptr, ptr %req.addr
  %res_slot3321 = alloca ptr
  %tgp3322 = getelementptr i8, ptr %ld3320, i64 8
  %tag3323 = load i32, ptr %tgp3322, align 4
  switch i32 %tag3323, label %case_default778 [
      i32 0, label %case_br779
  ]
case_br779:
  %fp3324 = getelementptr i8, ptr %ld3320, i64 16
  %fv3325 = load ptr, ptr %fp3324, align 8
  %$f559.addr = alloca ptr
  store ptr %fv3325, ptr %$f559.addr
  %fp3326 = getelementptr i8, ptr %ld3320, i64 24
  %fv3327 = load ptr, ptr %fp3326, align 8
  %$f560.addr = alloca ptr
  store ptr %fv3327, ptr %$f560.addr
  %fp3328 = getelementptr i8, ptr %ld3320, i64 32
  %fv3329 = load ptr, ptr %fp3328, align 8
  %$f561.addr = alloca ptr
  store ptr %fv3329, ptr %$f561.addr
  %fp3330 = getelementptr i8, ptr %ld3320, i64 40
  %fv3331 = load ptr, ptr %fp3330, align 8
  %$f562.addr = alloca ptr
  store ptr %fv3331, ptr %$f562.addr
  %fp3332 = getelementptr i8, ptr %ld3320, i64 48
  %fv3333 = load ptr, ptr %fp3332, align 8
  %$f563.addr = alloca ptr
  store ptr %fv3333, ptr %$f563.addr
  %fp3334 = getelementptr i8, ptr %ld3320, i64 56
  %fv3335 = load ptr, ptr %fp3334, align 8
  %$f564.addr = alloca ptr
  store ptr %fv3335, ptr %$f564.addr
  %fp3336 = getelementptr i8, ptr %ld3320, i64 64
  %fv3337 = load ptr, ptr %fp3336, align 8
  %$f565.addr = alloca ptr
  store ptr %fv3337, ptr %$f565.addr
  %fp3338 = getelementptr i8, ptr %ld3320, i64 72
  %fv3339 = load ptr, ptr %fp3338, align 8
  %$f566.addr = alloca ptr
  store ptr %fv3339, ptr %$f566.addr
  %freed3340 = call i64 @march_decrc_freed(ptr %ld3320)
  %freed_b3341 = icmp ne i64 %freed3340, 0
  br i1 %freed_b3341, label %br_unique780, label %br_shared781
br_shared781:
  call void @march_incrc(ptr %fv3339)
  call void @march_incrc(ptr %fv3337)
  call void @march_incrc(ptr %fv3335)
  call void @march_incrc(ptr %fv3333)
  call void @march_incrc(ptr %fv3331)
  call void @march_incrc(ptr %fv3329)
  call void @march_incrc(ptr %fv3327)
  call void @march_incrc(ptr %fv3325)
  br label %br_body782
br_unique780:
  br label %br_body782
br_body782:
  %ld3342 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld3342, ptr %h.addr
  %ld3343 = load ptr, ptr %h.addr
  store ptr %ld3343, ptr %res_slot3321
  br label %case_merge777
case_default778:
  unreachable
case_merge777:
  %case_r3344 = load ptr, ptr %res_slot3321
  ret ptr %case_r3344
}

define ptr @Http.method$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3345 = load ptr, ptr %req.addr
  %res_slot3346 = alloca ptr
  %tgp3347 = getelementptr i8, ptr %ld3345, i64 8
  %tag3348 = load i32, ptr %tgp3347, align 4
  switch i32 %tag3348, label %case_default784 [
      i32 0, label %case_br785
  ]
case_br785:
  %fp3349 = getelementptr i8, ptr %ld3345, i64 16
  %fv3350 = load ptr, ptr %fp3349, align 8
  %$f543.addr = alloca ptr
  store ptr %fv3350, ptr %$f543.addr
  %fp3351 = getelementptr i8, ptr %ld3345, i64 24
  %fv3352 = load ptr, ptr %fp3351, align 8
  %$f544.addr = alloca ptr
  store ptr %fv3352, ptr %$f544.addr
  %fp3353 = getelementptr i8, ptr %ld3345, i64 32
  %fv3354 = load ptr, ptr %fp3353, align 8
  %$f545.addr = alloca ptr
  store ptr %fv3354, ptr %$f545.addr
  %fp3355 = getelementptr i8, ptr %ld3345, i64 40
  %fv3356 = load ptr, ptr %fp3355, align 8
  %$f546.addr = alloca ptr
  store ptr %fv3356, ptr %$f546.addr
  %fp3357 = getelementptr i8, ptr %ld3345, i64 48
  %fv3358 = load ptr, ptr %fp3357, align 8
  %$f547.addr = alloca ptr
  store ptr %fv3358, ptr %$f547.addr
  %fp3359 = getelementptr i8, ptr %ld3345, i64 56
  %fv3360 = load ptr, ptr %fp3359, align 8
  %$f548.addr = alloca ptr
  store ptr %fv3360, ptr %$f548.addr
  %fp3361 = getelementptr i8, ptr %ld3345, i64 64
  %fv3362 = load ptr, ptr %fp3361, align 8
  %$f549.addr = alloca ptr
  store ptr %fv3362, ptr %$f549.addr
  %fp3363 = getelementptr i8, ptr %ld3345, i64 72
  %fv3364 = load ptr, ptr %fp3363, align 8
  %$f550.addr = alloca ptr
  store ptr %fv3364, ptr %$f550.addr
  %freed3365 = call i64 @march_decrc_freed(ptr %ld3345)
  %freed_b3366 = icmp ne i64 %freed3365, 0
  br i1 %freed_b3366, label %br_unique786, label %br_shared787
br_shared787:
  call void @march_incrc(ptr %fv3364)
  call void @march_incrc(ptr %fv3362)
  call void @march_incrc(ptr %fv3360)
  call void @march_incrc(ptr %fv3358)
  call void @march_incrc(ptr %fv3356)
  call void @march_incrc(ptr %fv3354)
  call void @march_incrc(ptr %fv3352)
  call void @march_incrc(ptr %fv3350)
  br label %br_body788
br_unique786:
  br label %br_body788
br_body788:
  %ld3367 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld3367, ptr %m.addr
  %ld3368 = load ptr, ptr %m.addr
  store ptr %ld3368, ptr %res_slot3346
  br label %case_merge783
case_default784:
  unreachable
case_merge783:
  %case_r3369 = load ptr, ptr %res_slot3346
  ret ptr %case_r3369
}

define ptr @HttpTransport.request_on$V__3173$Request_String(ptr %fd.arg, ptr %req.arg) {
entry:
  %fd.addr = alloca ptr
  store ptr %fd.arg, ptr %fd.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3370 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3370)
  %ld3371 = load ptr, ptr %req.addr
  %cr3372 = call ptr @Http.method$Request_String(ptr %ld3371)
  %$t783.addr = alloca ptr
  store ptr %cr3372, ptr %$t783.addr
  %ld3373 = load ptr, ptr %$t783.addr
  %cr3374 = call ptr @Http.method_to_string(ptr %ld3373)
  %meth.addr = alloca ptr
  store ptr %cr3374, ptr %meth.addr
  %ld3375 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3375)
  %ld3376 = load ptr, ptr %req.addr
  %cr3377 = call ptr @Http.host$Request_String(ptr %ld3376)
  %req_host.addr = alloca ptr
  store ptr %cr3377, ptr %req_host.addr
  %ld3378 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3378)
  %ld3379 = load ptr, ptr %req.addr
  %cr3380 = call ptr @Http.path$Request_String(ptr %ld3379)
  %req_path.addr = alloca ptr
  store ptr %cr3380, ptr %req_path.addr
  %ld3381 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3381)
  %ld3382 = load ptr, ptr %req.addr
  %cr3383 = call ptr @Http.query$Request_String(ptr %ld3382)
  %req_query.addr = alloca ptr
  store ptr %cr3383, ptr %req_query.addr
  %ld3384 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld3384)
  %ld3385 = load ptr, ptr %req.addr
  %cr3386 = call ptr @Http.headers$Request_String(ptr %ld3385)
  %req_headers.addr = alloca ptr
  store ptr %cr3386, ptr %req_headers.addr
  %ld3387 = load ptr, ptr %req.addr
  %cr3388 = call ptr @Http.body$Request_String(ptr %ld3387)
  %req_body.addr = alloca ptr
  store ptr %cr3388, ptr %req_body.addr
  %ld3389 = load ptr, ptr %http_serialize_request.addr
  %fp3390 = getelementptr i8, ptr %ld3389, i64 16
  %fv3391 = load ptr, ptr %fp3390, align 8
  %ld3392 = load ptr, ptr %meth.addr
  %ld3393 = load ptr, ptr %req_host.addr
  %ld3394 = load ptr, ptr %req_path.addr
  %ld3395 = load ptr, ptr %req_query.addr
  %ld3396 = load ptr, ptr %req_headers.addr
  %ld3397 = load ptr, ptr %req_body.addr
  %cr3398 = call ptr (ptr, ptr, ptr, ptr, ptr, ptr, ptr) %fv3391(ptr %ld3389, ptr %ld3392, ptr %ld3393, ptr %ld3394, ptr %ld3395, ptr %ld3396, ptr %ld3397)
  %raw_request.addr = alloca ptr
  store ptr %cr3398, ptr %raw_request.addr
  %ld3399 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld3399)
  %ld3400 = load ptr, ptr %tcp_send_all.addr
  %fp3401 = getelementptr i8, ptr %ld3400, i64 16
  %fv3402 = load ptr, ptr %fp3401, align 8
  %ld3403 = load ptr, ptr %fd.addr
  %ld3404 = load ptr, ptr %raw_request.addr
  %cr3405 = call ptr (ptr, ptr, ptr) %fv3402(ptr %ld3400, ptr %ld3403, ptr %ld3404)
  %$t784.addr = alloca ptr
  store ptr %cr3405, ptr %$t784.addr
  %ld3406 = load ptr, ptr %$t784.addr
  %res_slot3407 = alloca ptr
  %tgp3408 = getelementptr i8, ptr %ld3406, i64 8
  %tag3409 = load i32, ptr %tgp3408, align 4
  switch i32 %tag3409, label %case_default790 [
      i32 0, label %case_br791
      i32 0, label %case_br792
  ]
case_br791:
  %fp3410 = getelementptr i8, ptr %ld3406, i64 16
  %fv3411 = load ptr, ptr %fp3410, align 8
  %$f799.addr = alloca ptr
  store ptr %fv3411, ptr %$f799.addr
  %freed3412 = call i64 @march_decrc_freed(ptr %ld3406)
  %freed_b3413 = icmp ne i64 %freed3412, 0
  br i1 %freed_b3413, label %br_unique793, label %br_shared794
br_shared794:
  call void @march_incrc(ptr %fv3411)
  br label %br_body795
br_unique793:
  br label %br_body795
br_body795:
  %ld3414 = load ptr, ptr %$f799.addr
  %msg.addr = alloca ptr
  store ptr %ld3414, ptr %msg.addr
  %hp3415 = call ptr @march_alloc(i64 24)
  %tgp3416 = getelementptr i8, ptr %hp3415, i64 8
  store i32 2, ptr %tgp3416, align 4
  %ld3417 = load ptr, ptr %msg.addr
  %fp3418 = getelementptr i8, ptr %hp3415, i64 16
  store ptr %ld3417, ptr %fp3418, align 8
  %$t785.addr = alloca ptr
  store ptr %hp3415, ptr %$t785.addr
  %hp3419 = call ptr @march_alloc(i64 24)
  %tgp3420 = getelementptr i8, ptr %hp3419, i64 8
  store i32 1, ptr %tgp3420, align 4
  %ld3421 = load ptr, ptr %$t785.addr
  %fp3422 = getelementptr i8, ptr %hp3419, i64 16
  store ptr %ld3421, ptr %fp3422, align 8
  store ptr %hp3419, ptr %res_slot3407
  br label %case_merge789
case_br792:
  %fp3423 = getelementptr i8, ptr %ld3406, i64 16
  %fv3424 = load ptr, ptr %fp3423, align 8
  %$f800.addr = alloca ptr
  store ptr %fv3424, ptr %$f800.addr
  %freed3425 = call i64 @march_decrc_freed(ptr %ld3406)
  %freed_b3426 = icmp ne i64 %freed3425, 0
  br i1 %freed_b3426, label %br_unique796, label %br_shared797
br_shared797:
  call void @march_incrc(ptr %fv3424)
  br label %br_body798
br_unique796:
  br label %br_body798
br_body798:
  %ld3427 = load ptr, ptr %tcp_recv_http.addr
  %fp3428 = getelementptr i8, ptr %ld3427, i64 16
  %fv3429 = load ptr, ptr %fp3428, align 8
  %ld3430 = load ptr, ptr %fd.addr
  %cv3431 = inttoptr i64 1048576 to ptr
  %cr3432 = call ptr (ptr, ptr, ptr) %fv3429(ptr %ld3427, ptr %ld3430, ptr %cv3431)
  %$t786.addr = alloca ptr
  store ptr %cr3432, ptr %$t786.addr
  %ld3433 = load ptr, ptr %$t786.addr
  %res_slot3434 = alloca ptr
  %tgp3435 = getelementptr i8, ptr %ld3433, i64 8
  %tag3436 = load i32, ptr %tgp3435, align 4
  switch i32 %tag3436, label %case_default800 [
      i32 0, label %case_br801
      i32 0, label %case_br802
  ]
case_br801:
  %fp3437 = getelementptr i8, ptr %ld3433, i64 16
  %fv3438 = load ptr, ptr %fp3437, align 8
  %$f797.addr = alloca ptr
  store ptr %fv3438, ptr %$f797.addr
  %freed3439 = call i64 @march_decrc_freed(ptr %ld3433)
  %freed_b3440 = icmp ne i64 %freed3439, 0
  br i1 %freed_b3440, label %br_unique803, label %br_shared804
br_shared804:
  call void @march_incrc(ptr %fv3438)
  br label %br_body805
br_unique803:
  br label %br_body805
br_body805:
  %ld3441 = load ptr, ptr %$f797.addr
  %msg_1.addr = alloca ptr
  store ptr %ld3441, ptr %msg_1.addr
  %hp3442 = call ptr @march_alloc(i64 24)
  %tgp3443 = getelementptr i8, ptr %hp3442, i64 8
  store i32 3, ptr %tgp3443, align 4
  %ld3444 = load ptr, ptr %msg_1.addr
  %fp3445 = getelementptr i8, ptr %hp3442, i64 16
  store ptr %ld3444, ptr %fp3445, align 8
  %$t787.addr = alloca ptr
  store ptr %hp3442, ptr %$t787.addr
  %hp3446 = call ptr @march_alloc(i64 24)
  %tgp3447 = getelementptr i8, ptr %hp3446, i64 8
  store i32 1, ptr %tgp3447, align 4
  %ld3448 = load ptr, ptr %$t787.addr
  %fp3449 = getelementptr i8, ptr %hp3446, i64 16
  store ptr %ld3448, ptr %fp3449, align 8
  store ptr %hp3446, ptr %res_slot3434
  br label %case_merge799
case_br802:
  %fp3450 = getelementptr i8, ptr %ld3433, i64 16
  %fv3451 = load ptr, ptr %fp3450, align 8
  %$f798.addr = alloca ptr
  store ptr %fv3451, ptr %$f798.addr
  %freed3452 = call i64 @march_decrc_freed(ptr %ld3433)
  %freed_b3453 = icmp ne i64 %freed3452, 0
  br i1 %freed_b3453, label %br_unique806, label %br_shared807
br_shared807:
  call void @march_incrc(ptr %fv3451)
  br label %br_body808
br_unique806:
  br label %br_body808
br_body808:
  %ld3454 = load ptr, ptr %$f798.addr
  %raw_response.addr = alloca ptr
  store ptr %ld3454, ptr %raw_response.addr
  %ld3455 = load ptr, ptr %http_parse_response.addr
  %fp3456 = getelementptr i8, ptr %ld3455, i64 16
  %fv3457 = load ptr, ptr %fp3456, align 8
  %ld3458 = load ptr, ptr %raw_response.addr
  %cr3459 = call ptr (ptr, ptr) %fv3457(ptr %ld3455, ptr %ld3458)
  %$t788.addr = alloca ptr
  store ptr %cr3459, ptr %$t788.addr
  %ld3460 = load ptr, ptr %$t788.addr
  %res_slot3461 = alloca ptr
  %tgp3462 = getelementptr i8, ptr %ld3460, i64 8
  %tag3463 = load i32, ptr %tgp3462, align 4
  switch i32 %tag3463, label %case_default810 [
      i32 0, label %case_br811
      i32 0, label %case_br812
  ]
case_br811:
  %fp3464 = getelementptr i8, ptr %ld3460, i64 16
  %fv3465 = load ptr, ptr %fp3464, align 8
  %$f792.addr = alloca ptr
  store ptr %fv3465, ptr %$f792.addr
  %freed3466 = call i64 @march_decrc_freed(ptr %ld3460)
  %freed_b3467 = icmp ne i64 %freed3466, 0
  br i1 %freed_b3467, label %br_unique813, label %br_shared814
br_shared814:
  call void @march_incrc(ptr %fv3465)
  br label %br_body815
br_unique813:
  br label %br_body815
br_body815:
  %ld3468 = load ptr, ptr %$f792.addr
  %msg_2.addr = alloca ptr
  store ptr %ld3468, ptr %msg_2.addr
  %hp3469 = call ptr @march_alloc(i64 24)
  %tgp3470 = getelementptr i8, ptr %hp3469, i64 8
  store i32 0, ptr %tgp3470, align 4
  %ld3471 = load ptr, ptr %msg_2.addr
  %fp3472 = getelementptr i8, ptr %hp3469, i64 16
  store ptr %ld3471, ptr %fp3472, align 8
  %$t789.addr = alloca ptr
  store ptr %hp3469, ptr %$t789.addr
  %hp3473 = call ptr @march_alloc(i64 24)
  %tgp3474 = getelementptr i8, ptr %hp3473, i64 8
  store i32 1, ptr %tgp3474, align 4
  %ld3475 = load ptr, ptr %$t789.addr
  %fp3476 = getelementptr i8, ptr %hp3473, i64 16
  store ptr %ld3475, ptr %fp3476, align 8
  store ptr %hp3473, ptr %res_slot3461
  br label %case_merge809
case_br812:
  %fp3477 = getelementptr i8, ptr %ld3460, i64 16
  %fv3478 = load ptr, ptr %fp3477, align 8
  %$f793.addr = alloca ptr
  store ptr %fv3478, ptr %$f793.addr
  %freed3479 = call i64 @march_decrc_freed(ptr %ld3460)
  %freed_b3480 = icmp ne i64 %freed3479, 0
  br i1 %freed_b3480, label %br_unique816, label %br_shared817
br_shared817:
  call void @march_incrc(ptr %fv3478)
  br label %br_body818
br_unique816:
  br label %br_body818
br_body818:
  %ld3481 = load ptr, ptr %$f793.addr
  %res_slot3482 = alloca ptr
  %tgp3483 = getelementptr i8, ptr %ld3481, i64 8
  %tag3484 = load i32, ptr %tgp3483, align 4
  switch i32 %tag3484, label %case_default820 [
      i32 0, label %case_br821
  ]
case_br821:
  %fp3485 = getelementptr i8, ptr %ld3481, i64 16
  %fv3486 = load ptr, ptr %fp3485, align 8
  %$f794.addr = alloca ptr
  store ptr %fv3486, ptr %$f794.addr
  %fp3487 = getelementptr i8, ptr %ld3481, i64 24
  %fv3488 = load ptr, ptr %fp3487, align 8
  %$f795.addr = alloca ptr
  store ptr %fv3488, ptr %$f795.addr
  %fp3489 = getelementptr i8, ptr %ld3481, i64 32
  %fv3490 = load ptr, ptr %fp3489, align 8
  %$f796.addr = alloca ptr
  store ptr %fv3490, ptr %$f796.addr
  %freed3491 = call i64 @march_decrc_freed(ptr %ld3481)
  %freed_b3492 = icmp ne i64 %freed3491, 0
  br i1 %freed_b3492, label %br_unique822, label %br_shared823
br_shared823:
  call void @march_incrc(ptr %fv3490)
  call void @march_incrc(ptr %fv3488)
  call void @march_incrc(ptr %fv3486)
  br label %br_body824
br_unique822:
  br label %br_body824
br_body824:
  %ld3493 = load ptr, ptr %$f796.addr
  %resp_body.addr = alloca ptr
  store ptr %ld3493, ptr %resp_body.addr
  %ld3494 = load ptr, ptr %$f795.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld3494, ptr %resp_headers.addr
  %ld3495 = load ptr, ptr %$f794.addr
  %status_code.addr = alloca ptr
  store ptr %ld3495, ptr %status_code.addr
  %hp3496 = call ptr @march_alloc(i64 24)
  %tgp3497 = getelementptr i8, ptr %hp3496, i64 8
  store i32 0, ptr %tgp3497, align 4
  %ld3498 = load ptr, ptr %status_code.addr
  %fp3499 = getelementptr i8, ptr %hp3496, i64 16
  store ptr %ld3498, ptr %fp3499, align 8
  %$t790.addr = alloca ptr
  store ptr %hp3496, ptr %$t790.addr
  %hp3500 = call ptr @march_alloc(i64 40)
  %tgp3501 = getelementptr i8, ptr %hp3500, i64 8
  store i32 0, ptr %tgp3501, align 4
  %ld3502 = load ptr, ptr %$t790.addr
  %fp3503 = getelementptr i8, ptr %hp3500, i64 16
  store ptr %ld3502, ptr %fp3503, align 8
  %ld3504 = load ptr, ptr %resp_headers.addr
  %fp3505 = getelementptr i8, ptr %hp3500, i64 24
  store ptr %ld3504, ptr %fp3505, align 8
  %ld3506 = load ptr, ptr %resp_body.addr
  %fp3507 = getelementptr i8, ptr %hp3500, i64 32
  store ptr %ld3506, ptr %fp3507, align 8
  %$t791.addr = alloca ptr
  store ptr %hp3500, ptr %$t791.addr
  %hp3508 = call ptr @march_alloc(i64 24)
  %tgp3509 = getelementptr i8, ptr %hp3508, i64 8
  store i32 0, ptr %tgp3509, align 4
  %ld3510 = load ptr, ptr %$t791.addr
  %fp3511 = getelementptr i8, ptr %hp3508, i64 16
  store ptr %ld3510, ptr %fp3511, align 8
  store ptr %hp3508, ptr %res_slot3482
  br label %case_merge819
case_default820:
  unreachable
case_merge819:
  %case_r3512 = load ptr, ptr %res_slot3482
  store ptr %case_r3512, ptr %res_slot3461
  br label %case_merge809
case_default810:
  unreachable
case_merge809:
  %case_r3513 = load ptr, ptr %res_slot3461
  store ptr %case_r3513, ptr %res_slot3434
  br label %case_merge799
case_default800:
  unreachable
case_merge799:
  %case_r3514 = load ptr, ptr %res_slot3434
  store ptr %case_r3514, ptr %res_slot3407
  br label %case_merge789
case_default790:
  unreachable
case_merge789:
  %case_r3515 = load ptr, ptr %res_slot3407
  ret ptr %case_r3515
}

define ptr @Http.port$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3516 = load ptr, ptr %req.addr
  %res_slot3517 = alloca ptr
  %tgp3518 = getelementptr i8, ptr %ld3516, i64 8
  %tag3519 = load i32, ptr %tgp3518, align 4
  switch i32 %tag3519, label %case_default826 [
      i32 0, label %case_br827
  ]
case_br827:
  %fp3520 = getelementptr i8, ptr %ld3516, i64 16
  %fv3521 = load ptr, ptr %fp3520, align 8
  %$f567.addr = alloca ptr
  store ptr %fv3521, ptr %$f567.addr
  %fp3522 = getelementptr i8, ptr %ld3516, i64 24
  %fv3523 = load ptr, ptr %fp3522, align 8
  %$f568.addr = alloca ptr
  store ptr %fv3523, ptr %$f568.addr
  %fp3524 = getelementptr i8, ptr %ld3516, i64 32
  %fv3525 = load ptr, ptr %fp3524, align 8
  %$f569.addr = alloca ptr
  store ptr %fv3525, ptr %$f569.addr
  %fp3526 = getelementptr i8, ptr %ld3516, i64 40
  %fv3527 = load ptr, ptr %fp3526, align 8
  %$f570.addr = alloca ptr
  store ptr %fv3527, ptr %$f570.addr
  %fp3528 = getelementptr i8, ptr %ld3516, i64 48
  %fv3529 = load ptr, ptr %fp3528, align 8
  %$f571.addr = alloca ptr
  store ptr %fv3529, ptr %$f571.addr
  %fp3530 = getelementptr i8, ptr %ld3516, i64 56
  %fv3531 = load ptr, ptr %fp3530, align 8
  %$f572.addr = alloca ptr
  store ptr %fv3531, ptr %$f572.addr
  %fp3532 = getelementptr i8, ptr %ld3516, i64 64
  %fv3533 = load ptr, ptr %fp3532, align 8
  %$f573.addr = alloca ptr
  store ptr %fv3533, ptr %$f573.addr
  %fp3534 = getelementptr i8, ptr %ld3516, i64 72
  %fv3535 = load ptr, ptr %fp3534, align 8
  %$f574.addr = alloca ptr
  store ptr %fv3535, ptr %$f574.addr
  %freed3536 = call i64 @march_decrc_freed(ptr %ld3516)
  %freed_b3537 = icmp ne i64 %freed3536, 0
  br i1 %freed_b3537, label %br_unique828, label %br_shared829
br_shared829:
  call void @march_incrc(ptr %fv3535)
  call void @march_incrc(ptr %fv3533)
  call void @march_incrc(ptr %fv3531)
  call void @march_incrc(ptr %fv3529)
  call void @march_incrc(ptr %fv3527)
  call void @march_incrc(ptr %fv3525)
  call void @march_incrc(ptr %fv3523)
  call void @march_incrc(ptr %fv3521)
  br label %br_body830
br_unique828:
  br label %br_body830
br_body830:
  %ld3538 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld3538, ptr %p.addr
  %ld3539 = load ptr, ptr %p.addr
  store ptr %ld3539, ptr %res_slot3517
  br label %case_merge825
case_default826:
  unreachable
case_merge825:
  %case_r3540 = load ptr, ptr %res_slot3517
  ret ptr %case_r3540
}

define ptr @callback$apply$21(ptr %$clo.arg, ptr %do_request.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %do_request.addr = alloca ptr
  store ptr %do_request.arg, ptr %do_request.addr
  %ld3541 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3541)
  %ld3542 = load ptr, ptr %$clo.addr
  %fp3543 = getelementptr i8, ptr %ld3542, i64 24
  %fv3544 = load ptr, ptr %fp3543, align 8
  %cv3545 = ptrtoint ptr %fv3544 to i64
  %n.addr = alloca i64
  store i64 %cv3545, ptr %n.addr
  %ld3546 = load ptr, ptr %$clo.addr
  %fp3547 = getelementptr i8, ptr %ld3546, i64 32
  %fv3548 = load ptr, ptr %fp3547, align 8
  %req.addr = alloca ptr
  store ptr %fv3548, ptr %req.addr
  %ld3549 = load i64, ptr %n.addr
  %ld3550 = load ptr, ptr %do_request.addr
  %ld3551 = load ptr, ptr %req.addr
  %cr3552 = call ptr @run_keepalive$Int$Fn_Request_String_Result_V__5912_V__5911$Request_String(i64 %ld3549, ptr %ld3550, ptr %ld3551)
  ret ptr %cr3552
}

define ptr @do_request$apply$24(ptr %$clo.arg, ptr %req.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld3553 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3553)
  %ld3554 = load ptr, ptr %$clo.addr
  %fp3555 = getelementptr i8, ptr %ld3554, i64 24
  %fv3556 = load ptr, ptr %fp3555, align 8
  %err_steps.addr = alloca ptr
  store ptr %fv3556, ptr %err_steps.addr
  %ld3557 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3557)
  %ld3558 = load ptr, ptr %$clo.addr
  %fp3559 = getelementptr i8, ptr %ld3558, i64 32
  %fv3560 = load ptr, ptr %fp3559, align 8
  %fd.addr = alloca ptr
  store ptr %fv3560, ptr %fd.addr
  %ld3561 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3561)
  %ld3562 = load ptr, ptr %$clo.addr
  %fp3563 = getelementptr i8, ptr %ld3562, i64 40
  %fv3564 = load ptr, ptr %fp3563, align 8
  %cv3565 = ptrtoint ptr %fv3564 to i64
  %max_redir.addr = alloca i64
  store i64 %cv3565, ptr %max_redir.addr
  %ld3566 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3566)
  %ld3567 = load ptr, ptr %$clo.addr
  %fp3568 = getelementptr i8, ptr %ld3567, i64 48
  %fv3569 = load ptr, ptr %fp3568, align 8
  %cv3570 = ptrtoint ptr %fv3569 to i64
  %max_retries.addr = alloca i64
  store i64 %cv3570, ptr %max_retries.addr
  %ld3571 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3571)
  %ld3572 = load ptr, ptr %$clo.addr
  %fp3573 = getelementptr i8, ptr %ld3572, i64 56
  %fv3574 = load ptr, ptr %fp3573, align 8
  %req_steps.addr = alloca ptr
  store ptr %fv3574, ptr %req_steps.addr
  %ld3575 = load ptr, ptr %$clo.addr
  %fp3576 = getelementptr i8, ptr %ld3575, i64 64
  %fv3577 = load ptr, ptr %fp3576, align 8
  %resp_steps.addr = alloca ptr
  store ptr %fv3577, ptr %resp_steps.addr
  %ld3578 = load ptr, ptr %fd.addr
  %ld3579 = load ptr, ptr %req_steps.addr
  %ld3580 = load ptr, ptr %resp_steps.addr
  %ld3581 = load ptr, ptr %err_steps.addr
  %ld3582 = load i64, ptr %max_redir.addr
  %ld3583 = load i64, ptr %max_retries.addr
  %ld3584 = load ptr, ptr %req.addr
  %cr3585 = call ptr @HttpClient.run_on_fd$V__3282$List_RequestStepEntry$List_ResponseStepEntry$List_ErrorStepEntry$Int$Int$Request_String(ptr %ld3578, ptr %ld3579, ptr %ld3580, ptr %ld3581, i64 %ld3582, i64 %ld3583, ptr %ld3584)
  ret ptr %cr3585
}

define ptr @find$apply$26(ptr %$clo.arg, ptr %hs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %hs.addr = alloca ptr
  store ptr %hs.arg, ptr %hs.addr
  %ld3586 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3586)
  %ld3587 = load ptr, ptr %$clo.addr
  %find.addr = alloca ptr
  store ptr %ld3587, ptr %find.addr
  %ld3588 = load ptr, ptr %$clo.addr
  %fp3589 = getelementptr i8, ptr %ld3588, i64 24
  %fv3590 = load ptr, ptr %fp3589, align 8
  %lower_name.addr = alloca ptr
  store ptr %fv3590, ptr %lower_name.addr
  %ld3591 = load ptr, ptr %hs.addr
  %res_slot3592 = alloca ptr
  %tgp3593 = getelementptr i8, ptr %ld3591, i64 8
  %tag3594 = load i32, ptr %tgp3593, align 4
  switch i32 %tag3594, label %case_default832 [
      i32 0, label %case_br833
      i32 1, label %case_br834
  ]
case_br833:
  %ld3595 = load ptr, ptr %hs.addr
  call void @march_decrc(ptr %ld3595)
  %hp3596 = call ptr @march_alloc(i64 16)
  %tgp3597 = getelementptr i8, ptr %hp3596, i64 8
  store i32 0, ptr %tgp3597, align 4
  store ptr %hp3596, ptr %res_slot3592
  br label %case_merge831
case_br834:
  %fp3598 = getelementptr i8, ptr %ld3591, i64 16
  %fv3599 = load ptr, ptr %fp3598, align 8
  %$f680.addr = alloca ptr
  store ptr %fv3599, ptr %$f680.addr
  %fp3600 = getelementptr i8, ptr %ld3591, i64 24
  %fv3601 = load ptr, ptr %fp3600, align 8
  %$f681.addr = alloca ptr
  store ptr %fv3601, ptr %$f681.addr
  %freed3602 = call i64 @march_decrc_freed(ptr %ld3591)
  %freed_b3603 = icmp ne i64 %freed3602, 0
  br i1 %freed_b3603, label %br_unique835, label %br_shared836
br_shared836:
  call void @march_incrc(ptr %fv3601)
  call void @march_incrc(ptr %fv3599)
  br label %br_body837
br_unique835:
  br label %br_body837
br_body837:
  %ld3604 = load ptr, ptr %$f680.addr
  %res_slot3605 = alloca ptr
  %tgp3606 = getelementptr i8, ptr %ld3604, i64 8
  %tag3607 = load i32, ptr %tgp3606, align 4
  switch i32 %tag3607, label %case_default839 [
      i32 0, label %case_br840
  ]
case_br840:
  %fp3608 = getelementptr i8, ptr %ld3604, i64 16
  %fv3609 = load ptr, ptr %fp3608, align 8
  %$f682.addr = alloca ptr
  store ptr %fv3609, ptr %$f682.addr
  %fp3610 = getelementptr i8, ptr %ld3604, i64 24
  %fv3611 = load ptr, ptr %fp3610, align 8
  %$f683.addr = alloca ptr
  store ptr %fv3611, ptr %$f683.addr
  %freed3612 = call i64 @march_decrc_freed(ptr %ld3604)
  %freed_b3613 = icmp ne i64 %freed3612, 0
  br i1 %freed_b3613, label %br_unique841, label %br_shared842
br_shared842:
  call void @march_incrc(ptr %fv3611)
  call void @march_incrc(ptr %fv3609)
  br label %br_body843
br_unique841:
  br label %br_body843
br_body843:
  %ld3614 = load ptr, ptr %$f681.addr
  %rest.addr = alloca ptr
  store ptr %ld3614, ptr %rest.addr
  %ld3615 = load ptr, ptr %$f683.addr
  %v.addr = alloca ptr
  store ptr %ld3615, ptr %v.addr
  %ld3616 = load ptr, ptr %$f682.addr
  %n.addr = alloca ptr
  store ptr %ld3616, ptr %n.addr
  %ld3617 = load ptr, ptr %n.addr
  %cr3618 = call ptr @march_string_to_lowercase(ptr %ld3617)
  %$t678.addr = alloca ptr
  store ptr %cr3618, ptr %$t678.addr
  %ld3619 = load ptr, ptr %$t678.addr
  %ld3620 = load ptr, ptr %lower_name.addr
  %cr3621 = call i64 @march_string_eq(ptr %ld3619, ptr %ld3620)
  %$t679.addr = alloca i64
  store i64 %cr3621, ptr %$t679.addr
  %ld3622 = load i64, ptr %$t679.addr
  %res_slot3623 = alloca ptr
  %bi3624 = trunc i64 %ld3622 to i1
  br i1 %bi3624, label %case_br846, label %case_default845
case_br846:
  %hp3625 = call ptr @march_alloc(i64 24)
  %tgp3626 = getelementptr i8, ptr %hp3625, i64 8
  store i32 1, ptr %tgp3626, align 4
  %ld3627 = load ptr, ptr %v.addr
  %fp3628 = getelementptr i8, ptr %hp3625, i64 16
  store ptr %ld3627, ptr %fp3628, align 8
  store ptr %hp3625, ptr %res_slot3623
  br label %case_merge844
case_default845:
  %ld3629 = load ptr, ptr %find.addr
  %fp3630 = getelementptr i8, ptr %ld3629, i64 16
  %fv3631 = load ptr, ptr %fp3630, align 8
  %ld3632 = load ptr, ptr %rest.addr
  %cr3633 = call ptr (ptr, ptr) %fv3631(ptr %ld3629, ptr %ld3632)
  store ptr %cr3633, ptr %res_slot3623
  br label %case_merge844
case_merge844:
  %case_r3634 = load ptr, ptr %res_slot3623
  store ptr %case_r3634, ptr %res_slot3605
  br label %case_merge838
case_default839:
  unreachable
case_merge838:
  %case_r3635 = load ptr, ptr %res_slot3605
  store ptr %case_r3635, ptr %res_slot3592
  br label %case_merge831
case_default832:
  unreachable
case_merge831:
  %case_r3636 = load ptr, ptr %res_slot3592
  ret ptr %case_r3636
}

define ptr @find$apply$27(ptr %$clo.arg, ptr %hs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %hs.addr = alloca ptr
  store ptr %hs.arg, ptr %hs.addr
  %ld3637 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld3637)
  %ld3638 = load ptr, ptr %$clo.addr
  %find.addr = alloca ptr
  store ptr %ld3638, ptr %find.addr
  %ld3639 = load ptr, ptr %$clo.addr
  %fp3640 = getelementptr i8, ptr %ld3639, i64 24
  %fv3641 = load ptr, ptr %fp3640, align 8
  %lower_name.addr = alloca ptr
  store ptr %fv3641, ptr %lower_name.addr
  %ld3642 = load ptr, ptr %hs.addr
  %res_slot3643 = alloca ptr
  %tgp3644 = getelementptr i8, ptr %ld3642, i64 8
  %tag3645 = load i32, ptr %tgp3644, align 4
  switch i32 %tag3645, label %case_default848 [
      i32 0, label %case_br849
      i32 1, label %case_br850
  ]
case_br849:
  %ld3646 = load ptr, ptr %hs.addr
  call void @march_decrc(ptr %ld3646)
  %hp3647 = call ptr @march_alloc(i64 16)
  %tgp3648 = getelementptr i8, ptr %hp3647, i64 8
  store i32 0, ptr %tgp3648, align 4
  store ptr %hp3647, ptr %res_slot3643
  br label %case_merge847
case_br850:
  %fp3649 = getelementptr i8, ptr %ld3642, i64 16
  %fv3650 = load ptr, ptr %fp3649, align 8
  %$f680.addr = alloca ptr
  store ptr %fv3650, ptr %$f680.addr
  %fp3651 = getelementptr i8, ptr %ld3642, i64 24
  %fv3652 = load ptr, ptr %fp3651, align 8
  %$f681.addr = alloca ptr
  store ptr %fv3652, ptr %$f681.addr
  %freed3653 = call i64 @march_decrc_freed(ptr %ld3642)
  %freed_b3654 = icmp ne i64 %freed3653, 0
  br i1 %freed_b3654, label %br_unique851, label %br_shared852
br_shared852:
  call void @march_incrc(ptr %fv3652)
  call void @march_incrc(ptr %fv3650)
  br label %br_body853
br_unique851:
  br label %br_body853
br_body853:
  %ld3655 = load ptr, ptr %$f680.addr
  %res_slot3656 = alloca ptr
  %tgp3657 = getelementptr i8, ptr %ld3655, i64 8
  %tag3658 = load i32, ptr %tgp3657, align 4
  switch i32 %tag3658, label %case_default855 [
      i32 0, label %case_br856
  ]
case_br856:
  %fp3659 = getelementptr i8, ptr %ld3655, i64 16
  %fv3660 = load ptr, ptr %fp3659, align 8
  %$f682.addr = alloca ptr
  store ptr %fv3660, ptr %$f682.addr
  %fp3661 = getelementptr i8, ptr %ld3655, i64 24
  %fv3662 = load ptr, ptr %fp3661, align 8
  %$f683.addr = alloca ptr
  store ptr %fv3662, ptr %$f683.addr
  %freed3663 = call i64 @march_decrc_freed(ptr %ld3655)
  %freed_b3664 = icmp ne i64 %freed3663, 0
  br i1 %freed_b3664, label %br_unique857, label %br_shared858
br_shared858:
  call void @march_incrc(ptr %fv3662)
  call void @march_incrc(ptr %fv3660)
  br label %br_body859
br_unique857:
  br label %br_body859
br_body859:
  %ld3665 = load ptr, ptr %$f681.addr
  %rest.addr = alloca ptr
  store ptr %ld3665, ptr %rest.addr
  %ld3666 = load ptr, ptr %$f683.addr
  %v.addr = alloca ptr
  store ptr %ld3666, ptr %v.addr
  %ld3667 = load ptr, ptr %$f682.addr
  %n.addr = alloca ptr
  store ptr %ld3667, ptr %n.addr
  %ld3668 = load ptr, ptr %n.addr
  %cr3669 = call ptr @march_string_to_lowercase(ptr %ld3668)
  %$t678.addr = alloca ptr
  store ptr %cr3669, ptr %$t678.addr
  %ld3670 = load ptr, ptr %$t678.addr
  %ld3671 = load ptr, ptr %lower_name.addr
  %cr3672 = call i64 @march_string_eq(ptr %ld3670, ptr %ld3671)
  %$t679.addr = alloca i64
  store i64 %cr3672, ptr %$t679.addr
  %ld3673 = load i64, ptr %$t679.addr
  %res_slot3674 = alloca ptr
  %bi3675 = trunc i64 %ld3673 to i1
  br i1 %bi3675, label %case_br862, label %case_default861
case_br862:
  %hp3676 = call ptr @march_alloc(i64 24)
  %tgp3677 = getelementptr i8, ptr %hp3676, i64 8
  store i32 1, ptr %tgp3677, align 4
  %ld3678 = load ptr, ptr %v.addr
  %fp3679 = getelementptr i8, ptr %hp3676, i64 16
  store ptr %ld3678, ptr %fp3679, align 8
  store ptr %hp3676, ptr %res_slot3674
  br label %case_merge860
case_default861:
  %ld3680 = load ptr, ptr %find.addr
  %fp3681 = getelementptr i8, ptr %ld3680, i64 16
  %fv3682 = load ptr, ptr %fp3681, align 8
  %ld3683 = load ptr, ptr %rest.addr
  %cr3684 = call ptr (ptr, ptr) %fv3682(ptr %ld3680, ptr %ld3683)
  store ptr %cr3684, ptr %res_slot3674
  br label %case_merge860
case_merge860:
  %case_r3685 = load ptr, ptr %res_slot3674
  store ptr %case_r3685, ptr %res_slot3656
  br label %case_merge854
case_default855:
  unreachable
case_merge854:
  %case_r3686 = load ptr, ptr %res_slot3656
  store ptr %case_r3686, ptr %res_slot3643
  br label %case_merge847
case_default848:
  unreachable
case_merge847:
  %case_r3687 = load ptr, ptr %res_slot3643
  ret ptr %case_r3687
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

