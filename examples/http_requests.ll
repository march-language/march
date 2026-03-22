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
@.str16 = private unnamed_addr constant [31 x i8] c"=== Layer 2: HttpTransport ===\00"
@.str17 = private unnamed_addr constant [36 x i8] c"Making a raw GET request via TCP...\00"
@.str18 = private unnamed_addr constant [23 x i8] c"http://httpbin.org/get\00"
@.str19 = private unnamed_addr constant [20 x i8] c"GET httpbin.org/get\00"
@.str20 = private unnamed_addr constant [1 x i8] c"\00"
@.str21 = private unnamed_addr constant [28 x i8] c"=== Layer 3: HttpClient ===\00"
@.str22 = private unnamed_addr constant [9 x i8] c"defaults\00"
@.str23 = private unnamed_addr constant [18 x i8] c"Configured steps:\00"
@.str24 = private unnamed_addr constant [1 x i8] c"\00"
@.str25 = private unnamed_addr constant [46 x i8] c"Making GET request through client pipeline...\00"
@.str26 = private unnamed_addr constant [23 x i8] c"http://httpbin.org/get\00"
@.str27 = private unnamed_addr constant [20 x i8] c"GET httpbin.org/get\00"
@.str28 = private unnamed_addr constant [1 x i8] c"\00"
@.str29 = private unnamed_addr constant [23 x i8] c"Making POST request...\00"
@.str30 = private unnamed_addr constant [24 x i8] c"http://httpbin.org/post\00"
@.str31 = private unnamed_addr constant [17 x i8] c"hello from march\00"
@.str32 = private unnamed_addr constant [22 x i8] c"POST httpbin.org/post\00"
@.str33 = private unnamed_addr constant [1 x i8] c"\00"
@.str34 = private unnamed_addr constant [24 x i8] c"March HTTP Library Demo\00"
@.str35 = private unnamed_addr constant [24 x i8] c"=======================\00"
@.str36 = private unnamed_addr constant [1 x i8] c"\00"
@.str37 = private unnamed_addr constant [6 x i8] c"Done!\00"
@.str38 = private unnamed_addr constant [14 x i8] c": OK (status \00"
@.str39 = private unnamed_addr constant [2 x i8] c")\00"
@.str40 = private unnamed_addr constant [9 x i8] c"  body: \00"
@.str41 = private unnamed_addr constant [8 x i8] c": ERROR\00"
@.str42 = private unnamed_addr constant [17 x i8] c"invalid scheme: \00"
@.str43 = private unnamed_addr constant [13 x i8] c"missing host\00"
@.str44 = private unnamed_addr constant [15 x i8] c"invalid port: \00"
@.str45 = private unnamed_addr constant [16 x i8] c"malformed url: \00"
@.str46 = private unnamed_addr constant [1 x i8] c"\00"
@.str47 = private unnamed_addr constant [14 x i8] c": OK (status \00"
@.str48 = private unnamed_addr constant [2 x i8] c")\00"
@.str49 = private unnamed_addr constant [9 x i8] c"  body: \00"
@.str50 = private unnamed_addr constant [8 x i8] c": ERROR\00"
@.str51 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str52 = private unnamed_addr constant [4 x i8] c"url\00"
@.str53 = private unnamed_addr constant [14 x i8] c"invalid url: \00"
@.str54 = private unnamed_addr constant [4 x i8] c"url\00"
@.str55 = private unnamed_addr constant [1 x i8] c"\00"
@.str56 = private unnamed_addr constant [11 x i8] c"User-Agent\00"
@.str57 = private unnamed_addr constant [10 x i8] c"march/0.1\00"
@.str58 = private unnamed_addr constant [7 x i8] c"Accept\00"
@.str59 = private unnamed_addr constant [4 x i8] c"*/*\00"
@.str60 = private unnamed_addr constant [11 x i8] c"Connection\00"
@.str61 = private unnamed_addr constant [6 x i8] c"close\00"
@.str62 = private unnamed_addr constant [9 x i8] c"location\00"
@.str63 = private unnamed_addr constant [1 x i8] c"\00"
@.str64 = private unnamed_addr constant [1 x i8] c"\00"
@.str65 = private unnamed_addr constant [9 x i8] c"request:\00"
@.str66 = private unnamed_addr constant [10 x i8] c"response:\00"
@.str67 = private unnamed_addr constant [7 x i8] c"error:\00"
@.str68 = private unnamed_addr constant [5 x i8] c"done\00"
@.str69 = private unnamed_addr constant [5 x i8] c"  - \00"

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

define ptr @HttpClient.list_steps(ptr %client.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %hp364 = call ptr @march_alloc(i64 24)
  %tgp365 = getelementptr i8, ptr %hp364, i64 8
  store i32 0, ptr %tgp365, align 4
  %fp366 = getelementptr i8, ptr %hp364, i64 16
  store ptr @list_concat$apply$14, ptr %fp366, align 8
  %list_concat.addr = alloca ptr
  store ptr %hp364, ptr %list_concat.addr
  %hp367 = call ptr @march_alloc(i64 24)
  %tgp368 = getelementptr i8, ptr %hp367, i64 8
  store i32 0, ptr %tgp368, align 4
  %fp369 = getelementptr i8, ptr %hp367, i64 16
  store ptr @req_names$apply$15, ptr %fp369, align 8
  %req_names.addr = alloca ptr
  store ptr %hp367, ptr %req_names.addr
  %hp370 = call ptr @march_alloc(i64 24)
  %tgp371 = getelementptr i8, ptr %hp370, i64 8
  store i32 0, ptr %tgp371, align 4
  %fp372 = getelementptr i8, ptr %hp370, i64 16
  store ptr @resp_names$apply$16, ptr %fp372, align 8
  %resp_names.addr = alloca ptr
  store ptr %hp370, ptr %resp_names.addr
  %hp373 = call ptr @march_alloc(i64 24)
  %tgp374 = getelementptr i8, ptr %hp373, i64 8
  store i32 0, ptr %tgp374, align 4
  %fp375 = getelementptr i8, ptr %hp373, i64 16
  store ptr @err_names$apply$17, ptr %fp375, align 8
  %err_names.addr = alloca ptr
  store ptr %hp373, ptr %err_names.addr
  %ld376 = load ptr, ptr %client.addr
  %res_slot377 = alloca ptr
  %tgp378 = getelementptr i8, ptr %ld376, i64 8
  %tag379 = load i32, ptr %tgp378, align 4
  switch i32 %tag379, label %case_default78 [
      i32 0, label %case_br79
  ]
case_br79:
  %fp380 = getelementptr i8, ptr %ld376, i64 16
  %fv381 = load ptr, ptr %fp380, align 8
  %$f948.addr = alloca ptr
  store ptr %fv381, ptr %$f948.addr
  %fp382 = getelementptr i8, ptr %ld376, i64 24
  %fv383 = load ptr, ptr %fp382, align 8
  %$f949.addr = alloca ptr
  store ptr %fv383, ptr %$f949.addr
  %fp384 = getelementptr i8, ptr %ld376, i64 32
  %fv385 = load ptr, ptr %fp384, align 8
  %$f950.addr = alloca ptr
  store ptr %fv385, ptr %$f950.addr
  %fp386 = getelementptr i8, ptr %ld376, i64 40
  %fv387 = load i64, ptr %fp386, align 8
  %$f951.addr = alloca i64
  store i64 %fv387, ptr %$f951.addr
  %fp388 = getelementptr i8, ptr %ld376, i64 48
  %fv389 = load i64, ptr %fp388, align 8
  %$f952.addr = alloca i64
  store i64 %fv389, ptr %$f952.addr
  %fp390 = getelementptr i8, ptr %ld376, i64 56
  %fv391 = load i64, ptr %fp390, align 8
  %$f953.addr = alloca i64
  store i64 %fv391, ptr %$f953.addr
  %freed392 = call i64 @march_decrc_freed(ptr %ld376)
  %freed_b393 = icmp ne i64 %freed392, 0
  br i1 %freed_b393, label %br_unique80, label %br_shared81
br_shared81:
  call void @march_incrc(ptr %fv385)
  call void @march_incrc(ptr %fv383)
  call void @march_incrc(ptr %fv381)
  br label %br_body82
br_unique80:
  br label %br_body82
br_body82:
  %ld394 = load ptr, ptr %$f950.addr
  %es.addr = alloca ptr
  store ptr %ld394, ptr %es.addr
  %ld395 = load ptr, ptr %$f949.addr
  %rs.addr = alloca ptr
  store ptr %ld395, ptr %rs.addr
  %ld396 = load ptr, ptr %$f948.addr
  %rq.addr = alloca ptr
  store ptr %ld396, ptr %rq.addr
  %ld397 = load ptr, ptr %req_names.addr
  %fp398 = getelementptr i8, ptr %ld397, i64 16
  %fv399 = load ptr, ptr %fp398, align 8
  %ld400 = load ptr, ptr %rq.addr
  %cr401 = call ptr (ptr, ptr) %fv399(ptr %ld397, ptr %ld400)
  %$t944.addr = alloca ptr
  store ptr %cr401, ptr %$t944.addr
  %ld402 = load ptr, ptr %resp_names.addr
  %fp403 = getelementptr i8, ptr %ld402, i64 16
  %fv404 = load ptr, ptr %fp403, align 8
  %ld405 = load ptr, ptr %rs.addr
  %cr406 = call ptr (ptr, ptr) %fv404(ptr %ld402, ptr %ld405)
  %$t945.addr = alloca ptr
  store ptr %cr406, ptr %$t945.addr
  %ld407 = load ptr, ptr %err_names.addr
  %fp408 = getelementptr i8, ptr %ld407, i64 16
  %fv409 = load ptr, ptr %fp408, align 8
  %ld410 = load ptr, ptr %es.addr
  %cr411 = call ptr (ptr, ptr) %fv409(ptr %ld407, ptr %ld410)
  %$t946.addr = alloca ptr
  store ptr %cr411, ptr %$t946.addr
  %ld412 = load ptr, ptr %$t945.addr
  %ld413 = load ptr, ptr %$t946.addr
  %cr414 = call ptr @march_list_concat(ptr %ld412, ptr %ld413)
  %$t947.addr = alloca ptr
  store ptr %cr414, ptr %$t947.addr
  %ld415 = load ptr, ptr %$t944.addr
  %ld416 = load ptr, ptr %$t947.addr
  %cr417 = call ptr @march_list_concat(ptr %ld415, ptr %ld416)
  store ptr %cr417, ptr %res_slot377
  br label %case_merge77
case_default78:
  unreachable
case_merge77:
  %case_r418 = load ptr, ptr %res_slot377
  ret ptr %case_r418
}

define ptr @demo_transport() {
entry:
  %sl419 = call ptr @march_string_lit(ptr @.str16, i64 30)
  call void @march_print(ptr %sl419)
  %sl420 = call ptr @march_string_lit(ptr @.str17, i64 35)
  call void @march_print(ptr %sl420)
  %sl421 = call ptr @march_string_lit(ptr @.str18, i64 22)
  %cr422 = call ptr @HttpTransport.simple_get(ptr %sl421)
  %result.addr = alloca ptr
  store ptr %cr422, ptr %result.addr
  %sl423 = call ptr @march_string_lit(ptr @.str19, i64 19)
  %ld424 = load ptr, ptr %result.addr
  %cr425 = call ptr @print_result$String$Result_Response_String_TransportError(ptr %sl423, ptr %ld424)
  %sl426 = call ptr @march_string_lit(ptr @.str20, i64 0)
  call void @march_print(ptr %sl426)
  %cv427 = inttoptr i64 0 to ptr
  ret ptr %cv427
}

define ptr @demo_client() {
entry:
  %sl428 = call ptr @march_string_lit(ptr @.str21, i64 27)
  call void @march_print(ptr %sl428)
  %hp429 = call ptr @march_alloc(i64 16)
  %tgp430 = getelementptr i8, ptr %hp429, i64 8
  store i32 0, ptr %tgp430, align 4
  %$t880_i23.addr = alloca ptr
  store ptr %hp429, ptr %$t880_i23.addr
  %hp431 = call ptr @march_alloc(i64 16)
  %tgp432 = getelementptr i8, ptr %hp431, i64 8
  store i32 0, ptr %tgp432, align 4
  %$t881_i24.addr = alloca ptr
  store ptr %hp431, ptr %$t881_i24.addr
  %hp433 = call ptr @march_alloc(i64 16)
  %tgp434 = getelementptr i8, ptr %hp433, i64 8
  store i32 0, ptr %tgp434, align 4
  %$t882_i25.addr = alloca ptr
  store ptr %hp433, ptr %$t882_i25.addr
  %hp435 = call ptr @march_alloc(i64 64)
  %tgp436 = getelementptr i8, ptr %hp435, i64 8
  store i32 0, ptr %tgp436, align 4
  %ld437 = load ptr, ptr %$t880_i23.addr
  %fp438 = getelementptr i8, ptr %hp435, i64 16
  store ptr %ld437, ptr %fp438, align 8
  %ld439 = load ptr, ptr %$t881_i24.addr
  %fp440 = getelementptr i8, ptr %hp435, i64 24
  store ptr %ld439, ptr %fp440, align 8
  %ld441 = load ptr, ptr %$t882_i25.addr
  %fp442 = getelementptr i8, ptr %hp435, i64 32
  store ptr %ld441, ptr %fp442, align 8
  %fp443 = getelementptr i8, ptr %hp435, i64 40
  store i64 0, ptr %fp443, align 8
  %fp444 = getelementptr i8, ptr %hp435, i64 48
  store i64 0, ptr %fp444, align 8
  %fp445 = getelementptr i8, ptr %hp435, i64 56
  store i64 0, ptr %fp445, align 8
  %client.addr = alloca ptr
  store ptr %hp435, ptr %client.addr
  %ld446 = load ptr, ptr %client.addr
  %sl447 = call ptr @march_string_lit(ptr @.str22, i64 8)
  %cwrap448 = call ptr @march_alloc(i64 24)
  %cwt449 = getelementptr i8, ptr %cwrap448, i64 8
  store i32 0, ptr %cwt449, align 4
  %cwf450 = getelementptr i8, ptr %cwrap448, i64 16
  store ptr @HttpClient.step_default_headers$clo_wrap, ptr %cwf450, align 8
  %cr451 = call ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__6096_Result_Request_V__6095_V__6094(ptr %ld446, ptr %sl447, ptr %cwrap448)
  %client_1.addr = alloca ptr
  store ptr %cr451, ptr %client_1.addr
  %hp452 = call ptr @march_alloc(i64 24)
  %tgp453 = getelementptr i8, ptr %hp452, i64 8
  store i32 0, ptr %tgp453, align 4
  %fp454 = getelementptr i8, ptr %hp452, i64 16
  store ptr @show_steps$apply$22, ptr %fp454, align 8
  %show_steps.addr = alloca ptr
  store ptr %hp452, ptr %show_steps.addr
  %sl455 = call ptr @march_string_lit(ptr @.str23, i64 17)
  call void @march_print(ptr %sl455)
  %ld456 = load ptr, ptr %client_1.addr
  call void @march_incrc(ptr %ld456)
  %ld457 = load ptr, ptr %client_1.addr
  %cr458 = call ptr @HttpClient.list_steps(ptr %ld457)
  %$t2022.addr = alloca ptr
  store ptr %cr458, ptr %$t2022.addr
  %ld459 = load ptr, ptr %show_steps.addr
  %fp460 = getelementptr i8, ptr %ld459, i64 16
  %fv461 = load ptr, ptr %fp460, align 8
  %ld462 = load ptr, ptr %$t2022.addr
  %cr463 = call ptr (ptr, ptr) %fv461(ptr %ld459, ptr %ld462)
  %sl464 = call ptr @march_string_lit(ptr @.str24, i64 0)
  call void @march_print(ptr %sl464)
  %sl465 = call ptr @march_string_lit(ptr @.str25, i64 45)
  call void @march_print(ptr %sl465)
  %ld466 = load ptr, ptr %client_1.addr
  call void @march_incrc(ptr %ld466)
  %ld467 = load ptr, ptr %client_1.addr
  %sl468 = call ptr @march_string_lit(ptr @.str26, i64 22)
  %cr469 = call ptr @HttpClient.get(ptr %ld467, ptr %sl468)
  %result.addr = alloca ptr
  store ptr %cr469, ptr %result.addr
  %sl470 = call ptr @march_string_lit(ptr @.str27, i64 19)
  %ld471 = load ptr, ptr %result.addr
  %cr472 = call ptr @print_result$String$Result_Response_String_HttpError(ptr %sl470, ptr %ld471)
  %sl473 = call ptr @march_string_lit(ptr @.str28, i64 0)
  call void @march_print(ptr %sl473)
  %sl474 = call ptr @march_string_lit(ptr @.str29, i64 22)
  call void @march_print(ptr %sl474)
  %ld475 = load ptr, ptr %client_1.addr
  %sl476 = call ptr @march_string_lit(ptr @.str30, i64 23)
  %sl477 = call ptr @march_string_lit(ptr @.str31, i64 16)
  %cr478 = call ptr @HttpClient.post(ptr %ld475, ptr %sl476, ptr %sl477)
  %result_1.addr = alloca ptr
  store ptr %cr478, ptr %result_1.addr
  %sl479 = call ptr @march_string_lit(ptr @.str32, i64 21)
  %ld480 = load ptr, ptr %result_1.addr
  %cr481 = call ptr @print_result$String$Result_Response_String_HttpError(ptr %sl479, ptr %ld480)
  %sl482 = call ptr @march_string_lit(ptr @.str33, i64 0)
  call void @march_print(ptr %sl482)
  %cv483 = inttoptr i64 0 to ptr
  ret ptr %cv483
}

define ptr @march_main() {
entry:
  %sl484 = call ptr @march_string_lit(ptr @.str34, i64 23)
  call void @march_print(ptr %sl484)
  %sl485 = call ptr @march_string_lit(ptr @.str35, i64 23)
  call void @march_print(ptr %sl485)
  %sl486 = call ptr @march_string_lit(ptr @.str36, i64 0)
  call void @march_print(ptr %sl486)
  %cr487 = call ptr @demo_transport()
  %cr488 = call ptr @demo_client()
  %sl489 = call ptr @march_string_lit(ptr @.str37, i64 5)
  call void @march_print(ptr %sl489)
  %cv490 = inttoptr i64 0 to ptr
  ret ptr %cv490
}

define ptr @print_result$String$Result_Response_String_TransportError(ptr %label.arg, ptr %result.arg) {
entry:
  %label.addr = alloca ptr
  store ptr %label.arg, ptr %label.addr
  %result.addr = alloca ptr
  store ptr %result.arg, ptr %result.addr
  %ld491 = load ptr, ptr %result.addr
  %res_slot492 = alloca ptr
  %tgp493 = getelementptr i8, ptr %ld491, i64 8
  %tag494 = load i32, ptr %tgp493, align 4
  switch i32 %tag494, label %case_default84 [
      i32 0, label %case_br85
      i32 1, label %case_br86
  ]
case_br85:
  %fp495 = getelementptr i8, ptr %ld491, i64 16
  %fv496 = load ptr, ptr %fp495, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv496, ptr %$f2017.addr
  %freed497 = call i64 @march_decrc_freed(ptr %ld491)
  %freed_b498 = icmp ne i64 %freed497, 0
  br i1 %freed_b498, label %br_unique87, label %br_shared88
br_shared88:
  call void @march_incrc(ptr %fv496)
  br label %br_body89
br_unique87:
  br label %br_body89
br_body89:
  %ld499 = load ptr, ptr %$f2017.addr
  %resp.addr = alloca ptr
  store ptr %ld499, ptr %resp.addr
  %ld500 = load ptr, ptr %label.addr
  %sl501 = call ptr @march_string_lit(ptr @.str38, i64 13)
  %cr502 = call ptr @march_string_concat(ptr %ld500, ptr %sl501)
  %$t2009.addr = alloca ptr
  store ptr %cr502, ptr %$t2009.addr
  %ld503 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld503)
  %ld504 = load ptr, ptr %resp.addr
  %resp_i26.addr = alloca ptr
  store ptr %ld504, ptr %resp_i26.addr
  %ld505 = load ptr, ptr %resp_i26.addr
  %cr506 = call ptr @Http.response_status$Response_V__2518(ptr %ld505)
  %$t675_i27.addr = alloca ptr
  store ptr %cr506, ptr %$t675_i27.addr
  %ld507 = load ptr, ptr %$t675_i27.addr
  %cr508 = call i64 @Http.status_code(ptr %ld507)
  %$t2010.addr = alloca i64
  store i64 %cr508, ptr %$t2010.addr
  %ld509 = load i64, ptr %$t2010.addr
  %cr510 = call ptr @march_int_to_string(i64 %ld509)
  %$t2011.addr = alloca ptr
  store ptr %cr510, ptr %$t2011.addr
  %ld511 = load ptr, ptr %$t2009.addr
  %ld512 = load ptr, ptr %$t2011.addr
  %cr513 = call ptr @march_string_concat(ptr %ld511, ptr %ld512)
  %$t2012.addr = alloca ptr
  store ptr %cr513, ptr %$t2012.addr
  %ld514 = load ptr, ptr %$t2012.addr
  %sl515 = call ptr @march_string_lit(ptr @.str39, i64 1)
  %cr516 = call ptr @march_string_concat(ptr %ld514, ptr %sl515)
  %$t2013.addr = alloca ptr
  store ptr %cr516, ptr %$t2013.addr
  %ld517 = load ptr, ptr %$t2013.addr
  call void @march_print(ptr %ld517)
  %ld518 = load ptr, ptr %resp.addr
  %cr519 = call ptr @Http.response_body$Response_String(ptr %ld518)
  %$t2014.addr = alloca ptr
  store ptr %cr519, ptr %$t2014.addr
  %sl520 = call ptr @march_string_lit(ptr @.str40, i64 8)
  %ld521 = load ptr, ptr %$t2014.addr
  %cr522 = call ptr @march_string_concat(ptr %sl520, ptr %ld521)
  %$t2015.addr = alloca ptr
  store ptr %cr522, ptr %$t2015.addr
  %ld523 = load ptr, ptr %$t2015.addr
  call void @march_print(ptr %ld523)
  %cv524 = inttoptr i64 0 to ptr
  store ptr %cv524, ptr %res_slot492
  br label %case_merge83
case_br86:
  %fp525 = getelementptr i8, ptr %ld491, i64 16
  %fv526 = load ptr, ptr %fp525, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv526, ptr %$f2018.addr
  %freed527 = call i64 @march_decrc_freed(ptr %ld491)
  %freed_b528 = icmp ne i64 %freed527, 0
  br i1 %freed_b528, label %br_unique90, label %br_shared91
br_shared91:
  call void @march_incrc(ptr %fv526)
  br label %br_body92
br_unique90:
  br label %br_body92
br_body92:
  %ld529 = load ptr, ptr %label.addr
  %sl530 = call ptr @march_string_lit(ptr @.str41, i64 7)
  %cr531 = call ptr @march_string_concat(ptr %ld529, ptr %sl530)
  %$t2016.addr = alloca ptr
  store ptr %cr531, ptr %$t2016.addr
  %ld532 = load ptr, ptr %$t2016.addr
  call void @march_print(ptr %ld532)
  %cv533 = inttoptr i64 0 to ptr
  store ptr %cv533, ptr %res_slot492
  br label %case_merge83
case_default84:
  unreachable
case_merge83:
  %case_r534 = load ptr, ptr %res_slot492
  ret ptr %case_r534
}

define ptr @HttpTransport.simple_get(ptr %url.arg) {
entry:
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld535 = load ptr, ptr %url.addr
  %url_i28.addr = alloca ptr
  store ptr %ld535, ptr %url_i28.addr
  %ld536 = load ptr, ptr %url_i28.addr
  %cr537 = call ptr @Http.parse_url(ptr %ld536)
  %$t866.addr = alloca ptr
  store ptr %cr537, ptr %$t866.addr
  %ld538 = load ptr, ptr %$t866.addr
  %res_slot539 = alloca ptr
  %tgp540 = getelementptr i8, ptr %ld538, i64 8
  %tag541 = load i32, ptr %tgp540, align 4
  switch i32 %tag541, label %case_default94 [
      i32 1, label %case_br95
      i32 0, label %case_br96
  ]
case_br95:
  %fp542 = getelementptr i8, ptr %ld538, i64 16
  %fv543 = load ptr, ptr %fp542, align 8
  %$f875.addr = alloca ptr
  store ptr %fv543, ptr %$f875.addr
  %freed544 = call i64 @march_decrc_freed(ptr %ld538)
  %freed_b545 = icmp ne i64 %freed544, 0
  br i1 %freed_b545, label %br_unique97, label %br_shared98
br_shared98:
  call void @march_incrc(ptr %fv543)
  br label %br_body99
br_unique97:
  br label %br_body99
br_body99:
  %ld546 = load ptr, ptr %$f875.addr
  %res_slot547 = alloca ptr
  %tgp548 = getelementptr i8, ptr %ld546, i64 8
  %tag549 = load i32, ptr %tgp548, align 4
  switch i32 %tag549, label %case_default101 [
      i32 0, label %case_br102
      i32 1, label %case_br103
      i32 2, label %case_br104
      i32 3, label %case_br105
  ]
case_br102:
  %fp550 = getelementptr i8, ptr %ld546, i64 16
  %fv551 = load ptr, ptr %fp550, align 8
  %$f876.addr = alloca ptr
  store ptr %fv551, ptr %$f876.addr
  %freed552 = call i64 @march_decrc_freed(ptr %ld546)
  %freed_b553 = icmp ne i64 %freed552, 0
  br i1 %freed_b553, label %br_unique106, label %br_shared107
br_shared107:
  call void @march_incrc(ptr %fv551)
  br label %br_body108
br_unique106:
  br label %br_body108
br_body108:
  %ld554 = load ptr, ptr %$f876.addr
  %s.addr = alloca ptr
  store ptr %ld554, ptr %s.addr
  %sl555 = call ptr @march_string_lit(ptr @.str42, i64 16)
  %ld556 = load ptr, ptr %s.addr
  %cr557 = call ptr @march_string_concat(ptr %sl555, ptr %ld556)
  %$t867.addr = alloca ptr
  store ptr %cr557, ptr %$t867.addr
  %hp558 = call ptr @march_alloc(i64 24)
  %tgp559 = getelementptr i8, ptr %hp558, i64 8
  store i32 0, ptr %tgp559, align 4
  %ld560 = load ptr, ptr %$t867.addr
  %fp561 = getelementptr i8, ptr %hp558, i64 16
  store ptr %ld560, ptr %fp561, align 8
  %$t868.addr = alloca ptr
  store ptr %hp558, ptr %$t868.addr
  %hp562 = call ptr @march_alloc(i64 24)
  %tgp563 = getelementptr i8, ptr %hp562, i64 8
  store i32 1, ptr %tgp563, align 4
  %ld564 = load ptr, ptr %$t868.addr
  %fp565 = getelementptr i8, ptr %hp562, i64 16
  store ptr %ld564, ptr %fp565, align 8
  store ptr %hp562, ptr %res_slot547
  br label %case_merge100
case_br103:
  %ld566 = load ptr, ptr %$f875.addr
  call void @march_decrc(ptr %ld566)
  %hp567 = call ptr @march_alloc(i64 24)
  %tgp568 = getelementptr i8, ptr %hp567, i64 8
  store i32 0, ptr %tgp568, align 4
  %sl569 = call ptr @march_string_lit(ptr @.str43, i64 12)
  %fp570 = getelementptr i8, ptr %hp567, i64 16
  store ptr %sl569, ptr %fp570, align 8
  %$t869.addr = alloca ptr
  store ptr %hp567, ptr %$t869.addr
  %hp571 = call ptr @march_alloc(i64 24)
  %tgp572 = getelementptr i8, ptr %hp571, i64 8
  store i32 1, ptr %tgp572, align 4
  %ld573 = load ptr, ptr %$t869.addr
  %fp574 = getelementptr i8, ptr %hp571, i64 16
  store ptr %ld573, ptr %fp574, align 8
  store ptr %hp571, ptr %res_slot547
  br label %case_merge100
case_br104:
  %fp575 = getelementptr i8, ptr %ld546, i64 16
  %fv576 = load ptr, ptr %fp575, align 8
  %$f877.addr = alloca ptr
  store ptr %fv576, ptr %$f877.addr
  %freed577 = call i64 @march_decrc_freed(ptr %ld546)
  %freed_b578 = icmp ne i64 %freed577, 0
  br i1 %freed_b578, label %br_unique109, label %br_shared110
br_shared110:
  call void @march_incrc(ptr %fv576)
  br label %br_body111
br_unique109:
  br label %br_body111
br_body111:
  %ld579 = load ptr, ptr %$f877.addr
  %s_1.addr = alloca ptr
  store ptr %ld579, ptr %s_1.addr
  %sl580 = call ptr @march_string_lit(ptr @.str44, i64 14)
  %ld581 = load ptr, ptr %s_1.addr
  %cr582 = call ptr @march_string_concat(ptr %sl580, ptr %ld581)
  %$t870.addr = alloca ptr
  store ptr %cr582, ptr %$t870.addr
  %hp583 = call ptr @march_alloc(i64 24)
  %tgp584 = getelementptr i8, ptr %hp583, i64 8
  store i32 0, ptr %tgp584, align 4
  %ld585 = load ptr, ptr %$t870.addr
  %fp586 = getelementptr i8, ptr %hp583, i64 16
  store ptr %ld585, ptr %fp586, align 8
  %$t871.addr = alloca ptr
  store ptr %hp583, ptr %$t871.addr
  %hp587 = call ptr @march_alloc(i64 24)
  %tgp588 = getelementptr i8, ptr %hp587, i64 8
  store i32 1, ptr %tgp588, align 4
  %ld589 = load ptr, ptr %$t871.addr
  %fp590 = getelementptr i8, ptr %hp587, i64 16
  store ptr %ld589, ptr %fp590, align 8
  store ptr %hp587, ptr %res_slot547
  br label %case_merge100
case_br105:
  %fp591 = getelementptr i8, ptr %ld546, i64 16
  %fv592 = load ptr, ptr %fp591, align 8
  %$f878.addr = alloca ptr
  store ptr %fv592, ptr %$f878.addr
  %freed593 = call i64 @march_decrc_freed(ptr %ld546)
  %freed_b594 = icmp ne i64 %freed593, 0
  br i1 %freed_b594, label %br_unique112, label %br_shared113
br_shared113:
  call void @march_incrc(ptr %fv592)
  br label %br_body114
br_unique112:
  br label %br_body114
br_body114:
  %ld595 = load ptr, ptr %$f878.addr
  %s_2.addr = alloca ptr
  store ptr %ld595, ptr %s_2.addr
  %sl596 = call ptr @march_string_lit(ptr @.str45, i64 15)
  %ld597 = load ptr, ptr %s_2.addr
  %cr598 = call ptr @march_string_concat(ptr %sl596, ptr %ld597)
  %$t872.addr = alloca ptr
  store ptr %cr598, ptr %$t872.addr
  %hp599 = call ptr @march_alloc(i64 24)
  %tgp600 = getelementptr i8, ptr %hp599, i64 8
  store i32 0, ptr %tgp600, align 4
  %ld601 = load ptr, ptr %$t872.addr
  %fp602 = getelementptr i8, ptr %hp599, i64 16
  store ptr %ld601, ptr %fp602, align 8
  %$t873.addr = alloca ptr
  store ptr %hp599, ptr %$t873.addr
  %hp603 = call ptr @march_alloc(i64 24)
  %tgp604 = getelementptr i8, ptr %hp603, i64 8
  store i32 1, ptr %tgp604, align 4
  %ld605 = load ptr, ptr %$t873.addr
  %fp606 = getelementptr i8, ptr %hp603, i64 16
  store ptr %ld605, ptr %fp606, align 8
  store ptr %hp603, ptr %res_slot547
  br label %case_merge100
case_default101:
  unreachable
case_merge100:
  %case_r607 = load ptr, ptr %res_slot547
  store ptr %case_r607, ptr %res_slot539
  br label %case_merge93
case_br96:
  %fp608 = getelementptr i8, ptr %ld538, i64 16
  %fv609 = load ptr, ptr %fp608, align 8
  %$f879.addr = alloca ptr
  store ptr %fv609, ptr %$f879.addr
  %freed610 = call i64 @march_decrc_freed(ptr %ld538)
  %freed_b611 = icmp ne i64 %freed610, 0
  br i1 %freed_b611, label %br_unique115, label %br_shared116
br_shared116:
  call void @march_incrc(ptr %fv609)
  br label %br_body117
br_unique115:
  br label %br_body117
br_body117:
  %ld612 = load ptr, ptr %$f879.addr
  %req.addr = alloca ptr
  store ptr %ld612, ptr %req.addr
  %ld613 = load ptr, ptr %req.addr
  %sl614 = call ptr @march_string_lit(ptr @.str46, i64 0)
  %cr615 = call ptr @Http.set_body$Request_T_$String(ptr %ld613, ptr %sl614)
  %$t874.addr = alloca ptr
  store ptr %cr615, ptr %$t874.addr
  %ld616 = load ptr, ptr %$t874.addr
  %cr617 = call ptr @HttpTransport.request$Request_String(ptr %ld616)
  store ptr %cr617, ptr %res_slot539
  br label %case_merge93
case_default94:
  unreachable
case_merge93:
  %case_r618 = load ptr, ptr %res_slot539
  ret ptr %case_r618
}

define ptr @print_result$String$Result_Response_String_HttpError(ptr %label.arg, ptr %result.arg) {
entry:
  %label.addr = alloca ptr
  store ptr %label.arg, ptr %label.addr
  %result.addr = alloca ptr
  store ptr %result.arg, ptr %result.addr
  %ld619 = load ptr, ptr %result.addr
  %res_slot620 = alloca ptr
  %tgp621 = getelementptr i8, ptr %ld619, i64 8
  %tag622 = load i32, ptr %tgp621, align 4
  switch i32 %tag622, label %case_default119 [
      i32 0, label %case_br120
      i32 1, label %case_br121
  ]
case_br120:
  %fp623 = getelementptr i8, ptr %ld619, i64 16
  %fv624 = load ptr, ptr %fp623, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv624, ptr %$f2017.addr
  %freed625 = call i64 @march_decrc_freed(ptr %ld619)
  %freed_b626 = icmp ne i64 %freed625, 0
  br i1 %freed_b626, label %br_unique122, label %br_shared123
br_shared123:
  call void @march_incrc(ptr %fv624)
  br label %br_body124
br_unique122:
  br label %br_body124
br_body124:
  %ld627 = load ptr, ptr %$f2017.addr
  %resp.addr = alloca ptr
  store ptr %ld627, ptr %resp.addr
  %ld628 = load ptr, ptr %label.addr
  %sl629 = call ptr @march_string_lit(ptr @.str47, i64 13)
  %cr630 = call ptr @march_string_concat(ptr %ld628, ptr %sl629)
  %$t2009.addr = alloca ptr
  store ptr %cr630, ptr %$t2009.addr
  %ld631 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld631)
  %ld632 = load ptr, ptr %resp.addr
  %resp_i29.addr = alloca ptr
  store ptr %ld632, ptr %resp_i29.addr
  %ld633 = load ptr, ptr %resp_i29.addr
  %cr634 = call ptr @Http.response_status$Response_V__2518(ptr %ld633)
  %$t675_i30.addr = alloca ptr
  store ptr %cr634, ptr %$t675_i30.addr
  %ld635 = load ptr, ptr %$t675_i30.addr
  %cr636 = call i64 @Http.status_code(ptr %ld635)
  %$t2010.addr = alloca i64
  store i64 %cr636, ptr %$t2010.addr
  %ld637 = load i64, ptr %$t2010.addr
  %cr638 = call ptr @march_int_to_string(i64 %ld637)
  %$t2011.addr = alloca ptr
  store ptr %cr638, ptr %$t2011.addr
  %ld639 = load ptr, ptr %$t2009.addr
  %ld640 = load ptr, ptr %$t2011.addr
  %cr641 = call ptr @march_string_concat(ptr %ld639, ptr %ld640)
  %$t2012.addr = alloca ptr
  store ptr %cr641, ptr %$t2012.addr
  %ld642 = load ptr, ptr %$t2012.addr
  %sl643 = call ptr @march_string_lit(ptr @.str48, i64 1)
  %cr644 = call ptr @march_string_concat(ptr %ld642, ptr %sl643)
  %$t2013.addr = alloca ptr
  store ptr %cr644, ptr %$t2013.addr
  %ld645 = load ptr, ptr %$t2013.addr
  call void @march_print(ptr %ld645)
  %ld646 = load ptr, ptr %resp.addr
  %cr647 = call ptr @Http.response_body$Response_String(ptr %ld646)
  %$t2014.addr = alloca ptr
  store ptr %cr647, ptr %$t2014.addr
  %sl648 = call ptr @march_string_lit(ptr @.str49, i64 8)
  %ld649 = load ptr, ptr %$t2014.addr
  %cr650 = call ptr @march_string_concat(ptr %sl648, ptr %ld649)
  %$t2015.addr = alloca ptr
  store ptr %cr650, ptr %$t2015.addr
  %ld651 = load ptr, ptr %$t2015.addr
  call void @march_print(ptr %ld651)
  %cv652 = inttoptr i64 0 to ptr
  store ptr %cv652, ptr %res_slot620
  br label %case_merge118
case_br121:
  %fp653 = getelementptr i8, ptr %ld619, i64 16
  %fv654 = load ptr, ptr %fp653, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv654, ptr %$f2018.addr
  %freed655 = call i64 @march_decrc_freed(ptr %ld619)
  %freed_b656 = icmp ne i64 %freed655, 0
  br i1 %freed_b656, label %br_unique125, label %br_shared126
br_shared126:
  call void @march_incrc(ptr %fv654)
  br label %br_body127
br_unique125:
  br label %br_body127
br_body127:
  %ld657 = load ptr, ptr %label.addr
  %sl658 = call ptr @march_string_lit(ptr @.str50, i64 7)
  %cr659 = call ptr @march_string_concat(ptr %ld657, ptr %sl658)
  %$t2016.addr = alloca ptr
  store ptr %cr659, ptr %$t2016.addr
  %ld660 = load ptr, ptr %$t2016.addr
  call void @march_print(ptr %ld660)
  %cv661 = inttoptr i64 0 to ptr
  store ptr %cv661, ptr %res_slot620
  br label %case_merge118
case_default119:
  unreachable
case_merge118:
  %case_r662 = load ptr, ptr %res_slot620
  ret ptr %case_r662
}

define ptr @HttpClient.post(ptr %client.arg, ptr %url.arg, ptr %bdy.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %bdy.addr = alloca ptr
  store ptr %bdy.arg, ptr %bdy.addr
  %ld663 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld663)
  %ld664 = load ptr, ptr %url.addr
  %ld665 = load ptr, ptr %bdy.addr
  %cr666 = call ptr @Http.post$String$String(ptr %ld664, ptr %ld665)
  %$t1104.addr = alloca ptr
  store ptr %cr666, ptr %$t1104.addr
  %ld667 = load ptr, ptr %$t1104.addr
  %res_slot668 = alloca ptr
  %tgp669 = getelementptr i8, ptr %ld667, i64 8
  %tag670 = load i32, ptr %tgp669, align 4
  switch i32 %tag670, label %case_default129 [
      i32 1, label %case_br130
      i32 0, label %case_br131
  ]
case_br130:
  %fp671 = getelementptr i8, ptr %ld667, i64 16
  %fv672 = load ptr, ptr %fp671, align 8
  %$f1107.addr = alloca ptr
  store ptr %fv672, ptr %$f1107.addr
  %sl673 = call ptr @march_string_lit(ptr @.str51, i64 13)
  %ld674 = load ptr, ptr %url.addr
  %cr675 = call ptr @march_string_concat(ptr %sl673, ptr %ld674)
  %$t1105.addr = alloca ptr
  store ptr %cr675, ptr %$t1105.addr
  %hp676 = call ptr @march_alloc(i64 32)
  %tgp677 = getelementptr i8, ptr %hp676, i64 8
  store i32 1, ptr %tgp677, align 4
  %sl678 = call ptr @march_string_lit(ptr @.str52, i64 3)
  %fp679 = getelementptr i8, ptr %hp676, i64 16
  store ptr %sl678, ptr %fp679, align 8
  %ld680 = load ptr, ptr %$t1105.addr
  %fp681 = getelementptr i8, ptr %hp676, i64 24
  store ptr %ld680, ptr %fp681, align 8
  %$t1106.addr = alloca ptr
  store ptr %hp676, ptr %$t1106.addr
  %ld682 = load ptr, ptr %$t1104.addr
  %ld683 = load ptr, ptr %$t1106.addr
  %rc684 = load i64, ptr %ld682, align 8
  %uniq685 = icmp eq i64 %rc684, 1
  %fbip_slot686 = alloca ptr
  br i1 %uniq685, label %fbip_reuse132, label %fbip_fresh133
fbip_reuse132:
  %tgp687 = getelementptr i8, ptr %ld682, i64 8
  store i32 1, ptr %tgp687, align 4
  %fp688 = getelementptr i8, ptr %ld682, i64 16
  store ptr %ld683, ptr %fp688, align 8
  store ptr %ld682, ptr %fbip_slot686
  br label %fbip_merge134
fbip_fresh133:
  call void @march_decrc(ptr %ld682)
  %hp689 = call ptr @march_alloc(i64 24)
  %tgp690 = getelementptr i8, ptr %hp689, i64 8
  store i32 1, ptr %tgp690, align 4
  %fp691 = getelementptr i8, ptr %hp689, i64 16
  store ptr %ld683, ptr %fp691, align 8
  store ptr %hp689, ptr %fbip_slot686
  br label %fbip_merge134
fbip_merge134:
  %fbip_r692 = load ptr, ptr %fbip_slot686
  store ptr %fbip_r692, ptr %res_slot668
  br label %case_merge128
case_br131:
  %fp693 = getelementptr i8, ptr %ld667, i64 16
  %fv694 = load ptr, ptr %fp693, align 8
  %$f1108.addr = alloca ptr
  store ptr %fv694, ptr %$f1108.addr
  %freed695 = call i64 @march_decrc_freed(ptr %ld667)
  %freed_b696 = icmp ne i64 %freed695, 0
  br i1 %freed_b696, label %br_unique135, label %br_shared136
br_shared136:
  call void @march_incrc(ptr %fv694)
  br label %br_body137
br_unique135:
  br label %br_body137
br_body137:
  %ld697 = load ptr, ptr %$f1108.addr
  %req.addr = alloca ptr
  store ptr %ld697, ptr %req.addr
  %ld698 = load ptr, ptr %client.addr
  %ld699 = load ptr, ptr %req.addr
  %cr700 = call ptr @HttpClient.run(ptr %ld698, ptr %ld699)
  store ptr %cr700, ptr %res_slot668
  br label %case_merge128
case_default129:
  unreachable
case_merge128:
  %case_r701 = load ptr, ptr %res_slot668
  ret ptr %case_r701
}

define ptr @HttpClient.get(ptr %client.arg, ptr %url.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %ld702 = load ptr, ptr %url.addr
  call void @march_incrc(ptr %ld702)
  %ld703 = load ptr, ptr %url.addr
  %url_i31.addr = alloca ptr
  store ptr %ld703, ptr %url_i31.addr
  %ld704 = load ptr, ptr %url_i31.addr
  %cr705 = call ptr @Http.parse_url(ptr %ld704)
  %$t1098.addr = alloca ptr
  store ptr %cr705, ptr %$t1098.addr
  %ld706 = load ptr, ptr %$t1098.addr
  %res_slot707 = alloca ptr
  %tgp708 = getelementptr i8, ptr %ld706, i64 8
  %tag709 = load i32, ptr %tgp708, align 4
  switch i32 %tag709, label %case_default139 [
      i32 1, label %case_br140
      i32 0, label %case_br141
  ]
case_br140:
  %fp710 = getelementptr i8, ptr %ld706, i64 16
  %fv711 = load ptr, ptr %fp710, align 8
  %$f1102.addr = alloca ptr
  store ptr %fv711, ptr %$f1102.addr
  %sl712 = call ptr @march_string_lit(ptr @.str53, i64 13)
  %ld713 = load ptr, ptr %url.addr
  %cr714 = call ptr @march_string_concat(ptr %sl712, ptr %ld713)
  %$t1099.addr = alloca ptr
  store ptr %cr714, ptr %$t1099.addr
  %hp715 = call ptr @march_alloc(i64 32)
  %tgp716 = getelementptr i8, ptr %hp715, i64 8
  store i32 1, ptr %tgp716, align 4
  %sl717 = call ptr @march_string_lit(ptr @.str54, i64 3)
  %fp718 = getelementptr i8, ptr %hp715, i64 16
  store ptr %sl717, ptr %fp718, align 8
  %ld719 = load ptr, ptr %$t1099.addr
  %fp720 = getelementptr i8, ptr %hp715, i64 24
  store ptr %ld719, ptr %fp720, align 8
  %$t1100.addr = alloca ptr
  store ptr %hp715, ptr %$t1100.addr
  %ld721 = load ptr, ptr %$t1098.addr
  %ld722 = load ptr, ptr %$t1100.addr
  %rc723 = load i64, ptr %ld721, align 8
  %uniq724 = icmp eq i64 %rc723, 1
  %fbip_slot725 = alloca ptr
  br i1 %uniq724, label %fbip_reuse142, label %fbip_fresh143
fbip_reuse142:
  %tgp726 = getelementptr i8, ptr %ld721, i64 8
  store i32 1, ptr %tgp726, align 4
  %fp727 = getelementptr i8, ptr %ld721, i64 16
  store ptr %ld722, ptr %fp727, align 8
  store ptr %ld721, ptr %fbip_slot725
  br label %fbip_merge144
fbip_fresh143:
  call void @march_decrc(ptr %ld721)
  %hp728 = call ptr @march_alloc(i64 24)
  %tgp729 = getelementptr i8, ptr %hp728, i64 8
  store i32 1, ptr %tgp729, align 4
  %fp730 = getelementptr i8, ptr %hp728, i64 16
  store ptr %ld722, ptr %fp730, align 8
  store ptr %hp728, ptr %fbip_slot725
  br label %fbip_merge144
fbip_merge144:
  %fbip_r731 = load ptr, ptr %fbip_slot725
  store ptr %fbip_r731, ptr %res_slot707
  br label %case_merge138
case_br141:
  %fp732 = getelementptr i8, ptr %ld706, i64 16
  %fv733 = load ptr, ptr %fp732, align 8
  %$f1103.addr = alloca ptr
  store ptr %fv733, ptr %$f1103.addr
  %freed734 = call i64 @march_decrc_freed(ptr %ld706)
  %freed_b735 = icmp ne i64 %freed734, 0
  br i1 %freed_b735, label %br_unique145, label %br_shared146
br_shared146:
  call void @march_incrc(ptr %fv733)
  br label %br_body147
br_unique145:
  br label %br_body147
br_body147:
  %ld736 = load ptr, ptr %$f1103.addr
  %req.addr = alloca ptr
  store ptr %ld736, ptr %req.addr
  %ld737 = load ptr, ptr %req.addr
  %sl738 = call ptr @march_string_lit(ptr @.str55, i64 0)
  %cr739 = call ptr @Http.set_body$Request_T_$String(ptr %ld737, ptr %sl738)
  %$t1101.addr = alloca ptr
  store ptr %cr739, ptr %$t1101.addr
  %ld740 = load ptr, ptr %client.addr
  %ld741 = load ptr, ptr %$t1101.addr
  %cr742 = call ptr @HttpClient.run(ptr %ld740, ptr %ld741)
  store ptr %cr742, ptr %res_slot707
  br label %case_merge138
case_default139:
  unreachable
case_merge138:
  %case_r743 = load ptr, ptr %res_slot707
  ret ptr %case_r743
}

define ptr @HttpClient.step_default_headers(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld744 = load ptr, ptr %req.addr
  %sl745 = call ptr @march_string_lit(ptr @.str56, i64 10)
  %sl746 = call ptr @march_string_lit(ptr @.str57, i64 9)
  %cr747 = call ptr @Http.set_header$Request_V__3638$String$String(ptr %ld744, ptr %sl745, ptr %sl746)
  %req_1.addr = alloca ptr
  store ptr %cr747, ptr %req_1.addr
  %ld748 = load ptr, ptr %req_1.addr
  %sl749 = call ptr @march_string_lit(ptr @.str58, i64 6)
  %sl750 = call ptr @march_string_lit(ptr @.str59, i64 3)
  %cr751 = call ptr @Http.set_header$Request_V__3640$String$String(ptr %ld748, ptr %sl749, ptr %sl750)
  %req_2.addr = alloca ptr
  store ptr %cr751, ptr %req_2.addr
  %hp752 = call ptr @march_alloc(i64 24)
  %tgp753 = getelementptr i8, ptr %hp752, i64 8
  store i32 0, ptr %tgp753, align 4
  %ld754 = load ptr, ptr %req_2.addr
  %fp755 = getelementptr i8, ptr %hp752, i64 16
  store ptr %ld754, ptr %fp755, align 8
  ret ptr %hp752
}

define ptr @HttpClient.add_request_step$Client$String$Fn_Request_V__6096_Result_Request_V__6095_V__6094(ptr %client.arg, ptr %name.arg, ptr %step.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %step.addr = alloca ptr
  store ptr %step.arg, ptr %step.addr
  %ld756 = load ptr, ptr %client.addr
  %res_slot757 = alloca ptr
  %tgp758 = getelementptr i8, ptr %ld756, i64 8
  %tag759 = load i32, ptr %tgp758, align 4
  switch i32 %tag759, label %case_default149 [
      i32 0, label %case_br150
  ]
case_br150:
  %fp760 = getelementptr i8, ptr %ld756, i64 16
  %fv761 = load ptr, ptr %fp760, align 8
  %$f889.addr = alloca ptr
  store ptr %fv761, ptr %$f889.addr
  %fp762 = getelementptr i8, ptr %ld756, i64 24
  %fv763 = load ptr, ptr %fp762, align 8
  %$f890.addr = alloca ptr
  store ptr %fv763, ptr %$f890.addr
  %fp764 = getelementptr i8, ptr %ld756, i64 32
  %fv765 = load ptr, ptr %fp764, align 8
  %$f891.addr = alloca ptr
  store ptr %fv765, ptr %$f891.addr
  %fp766 = getelementptr i8, ptr %ld756, i64 40
  %fv767 = load i64, ptr %fp766, align 8
  %$f892.addr = alloca i64
  store i64 %fv767, ptr %$f892.addr
  %fp768 = getelementptr i8, ptr %ld756, i64 48
  %fv769 = load i64, ptr %fp768, align 8
  %$f893.addr = alloca i64
  store i64 %fv769, ptr %$f893.addr
  %fp770 = getelementptr i8, ptr %ld756, i64 56
  %fv771 = load i64, ptr %fp770, align 8
  %$f894.addr = alloca i64
  store i64 %fv771, ptr %$f894.addr
  %ld772 = load i64, ptr %$f894.addr
  %backoff.addr = alloca i64
  store i64 %ld772, ptr %backoff.addr
  %ld773 = load i64, ptr %$f893.addr
  %retries.addr = alloca i64
  store i64 %ld773, ptr %retries.addr
  %ld774 = load i64, ptr %$f892.addr
  %redir.addr = alloca i64
  store i64 %ld774, ptr %redir.addr
  %ld775 = load ptr, ptr %$f891.addr
  %err_steps.addr = alloca ptr
  store ptr %ld775, ptr %err_steps.addr
  %ld776 = load ptr, ptr %$f890.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld776, ptr %resp_steps.addr
  %ld777 = load ptr, ptr %$f889.addr
  %req_steps.addr = alloca ptr
  store ptr %ld777, ptr %req_steps.addr
  %hp778 = call ptr @march_alloc(i64 32)
  %tgp779 = getelementptr i8, ptr %hp778, i64 8
  store i32 0, ptr %tgp779, align 4
  %ld780 = load ptr, ptr %name.addr
  %fp781 = getelementptr i8, ptr %hp778, i64 16
  store ptr %ld780, ptr %fp781, align 8
  %ld782 = load ptr, ptr %step.addr
  %fp783 = getelementptr i8, ptr %hp778, i64 24
  store ptr %ld782, ptr %fp783, align 8
  %$t887.addr = alloca ptr
  store ptr %hp778, ptr %$t887.addr
  %ld784 = load ptr, ptr %req_steps.addr
  %ld785 = load ptr, ptr %$t887.addr
  %cr786 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld784, ptr %ld785)
  %$t888.addr = alloca ptr
  store ptr %cr786, ptr %$t888.addr
  %ld787 = load ptr, ptr %client.addr
  %ld788 = load ptr, ptr %$t888.addr
  %ld789 = load ptr, ptr %resp_steps.addr
  %ld790 = load ptr, ptr %err_steps.addr
  %ld791 = load i64, ptr %redir.addr
  %ld792 = load i64, ptr %retries.addr
  %ld793 = load i64, ptr %backoff.addr
  %rc794 = load i64, ptr %ld787, align 8
  %uniq795 = icmp eq i64 %rc794, 1
  %fbip_slot796 = alloca ptr
  br i1 %uniq795, label %fbip_reuse151, label %fbip_fresh152
fbip_reuse151:
  %tgp797 = getelementptr i8, ptr %ld787, i64 8
  store i32 0, ptr %tgp797, align 4
  %fp798 = getelementptr i8, ptr %ld787, i64 16
  store ptr %ld788, ptr %fp798, align 8
  %fp799 = getelementptr i8, ptr %ld787, i64 24
  store ptr %ld789, ptr %fp799, align 8
  %fp800 = getelementptr i8, ptr %ld787, i64 32
  store ptr %ld790, ptr %fp800, align 8
  %fp801 = getelementptr i8, ptr %ld787, i64 40
  store i64 %ld791, ptr %fp801, align 8
  %fp802 = getelementptr i8, ptr %ld787, i64 48
  store i64 %ld792, ptr %fp802, align 8
  %fp803 = getelementptr i8, ptr %ld787, i64 56
  store i64 %ld793, ptr %fp803, align 8
  store ptr %ld787, ptr %fbip_slot796
  br label %fbip_merge153
fbip_fresh152:
  call void @march_decrc(ptr %ld787)
  %hp804 = call ptr @march_alloc(i64 64)
  %tgp805 = getelementptr i8, ptr %hp804, i64 8
  store i32 0, ptr %tgp805, align 4
  %fp806 = getelementptr i8, ptr %hp804, i64 16
  store ptr %ld788, ptr %fp806, align 8
  %fp807 = getelementptr i8, ptr %hp804, i64 24
  store ptr %ld789, ptr %fp807, align 8
  %fp808 = getelementptr i8, ptr %hp804, i64 32
  store ptr %ld790, ptr %fp808, align 8
  %fp809 = getelementptr i8, ptr %hp804, i64 40
  store i64 %ld791, ptr %fp809, align 8
  %fp810 = getelementptr i8, ptr %hp804, i64 48
  store i64 %ld792, ptr %fp810, align 8
  %fp811 = getelementptr i8, ptr %hp804, i64 56
  store i64 %ld793, ptr %fp811, align 8
  store ptr %hp804, ptr %fbip_slot796
  br label %fbip_merge153
fbip_merge153:
  %fbip_r812 = load ptr, ptr %fbip_slot796
  store ptr %fbip_r812, ptr %res_slot757
  br label %case_merge148
case_default149:
  unreachable
case_merge148:
  %case_r813 = load ptr, ptr %res_slot757
  ret ptr %case_r813
}

define ptr @Http.response_body$Response_String(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld814 = load ptr, ptr %resp.addr
  %res_slot815 = alloca ptr
  %tgp816 = getelementptr i8, ptr %ld814, i64 8
  %tag817 = load i32, ptr %tgp816, align 4
  switch i32 %tag817, label %case_default155 [
      i32 0, label %case_br156
  ]
case_br156:
  %fp818 = getelementptr i8, ptr %ld814, i64 16
  %fv819 = load ptr, ptr %fp818, align 8
  %$f672.addr = alloca ptr
  store ptr %fv819, ptr %$f672.addr
  %fp820 = getelementptr i8, ptr %ld814, i64 24
  %fv821 = load ptr, ptr %fp820, align 8
  %$f673.addr = alloca ptr
  store ptr %fv821, ptr %$f673.addr
  %fp822 = getelementptr i8, ptr %ld814, i64 32
  %fv823 = load ptr, ptr %fp822, align 8
  %$f674.addr = alloca ptr
  store ptr %fv823, ptr %$f674.addr
  %freed824 = call i64 @march_decrc_freed(ptr %ld814)
  %freed_b825 = icmp ne i64 %freed824, 0
  br i1 %freed_b825, label %br_unique157, label %br_shared158
br_shared158:
  call void @march_incrc(ptr %fv823)
  call void @march_incrc(ptr %fv821)
  call void @march_incrc(ptr %fv819)
  br label %br_body159
br_unique157:
  br label %br_body159
br_body159:
  %ld826 = load ptr, ptr %$f674.addr
  %b.addr = alloca ptr
  store ptr %ld826, ptr %b.addr
  %ld827 = load ptr, ptr %b.addr
  store ptr %ld827, ptr %res_slot815
  br label %case_merge154
case_default155:
  unreachable
case_merge154:
  %case_r828 = load ptr, ptr %res_slot815
  ret ptr %case_r828
}

define ptr @HttpTransport.request$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld829 = load ptr, ptr %req.addr
  %sl830 = call ptr @march_string_lit(ptr @.str60, i64 10)
  %sl831 = call ptr @march_string_lit(ptr @.str61, i64 5)
  %cr832 = call ptr @Http.set_header$Request_String$String$String(ptr %ld829, ptr %sl830, ptr %sl831)
  %req_1.addr = alloca ptr
  store ptr %cr832, ptr %req_1.addr
  %ld833 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld833)
  %ld834 = load ptr, ptr %req_1.addr
  %cr835 = call ptr @Http.host$Request_V__2936(ptr %ld834)
  %req_host.addr = alloca ptr
  store ptr %cr835, ptr %req_host.addr
  %ld836 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld836)
  %ld837 = load ptr, ptr %req_1.addr
  %cr838 = call ptr @Http.port$Request_V__2939(ptr %ld837)
  %$t837.addr = alloca ptr
  store ptr %cr838, ptr %$t837.addr
  %ld839 = load ptr, ptr %$t837.addr
  %res_slot840 = alloca ptr
  %tgp841 = getelementptr i8, ptr %ld839, i64 8
  %tag842 = load i32, ptr %tgp841, align 4
  switch i32 %tag842, label %case_default161 [
      i32 1, label %case_br162
      i32 0, label %case_br163
  ]
case_br162:
  %fp843 = getelementptr i8, ptr %ld839, i64 16
  %fv844 = load ptr, ptr %fp843, align 8
  %$f838.addr = alloca ptr
  store ptr %fv844, ptr %$f838.addr
  %ld845 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld845)
  %ld846 = load ptr, ptr %$f838.addr
  %p.addr = alloca ptr
  store ptr %ld846, ptr %p.addr
  %ld847 = load ptr, ptr %p.addr
  store ptr %ld847, ptr %res_slot840
  br label %case_merge160
case_br163:
  %ld848 = load ptr, ptr %$t837.addr
  call void @march_decrc(ptr %ld848)
  %cv849 = inttoptr i64 80 to ptr
  store ptr %cv849, ptr %res_slot840
  br label %case_merge160
case_default161:
  unreachable
case_merge160:
  %case_r850 = load ptr, ptr %res_slot840
  %cv851 = ptrtoint ptr %case_r850 to i64
  %req_port.addr = alloca i64
  store i64 %cv851, ptr %req_port.addr
  %ld852 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld852)
  %ld853 = load ptr, ptr %req_1.addr
  %cr854 = call ptr @Http.method$Request_V__2946(ptr %ld853)
  %$t839.addr = alloca ptr
  store ptr %cr854, ptr %$t839.addr
  %ld855 = load ptr, ptr %$t839.addr
  %cr856 = call ptr @Http.method_to_string(ptr %ld855)
  %$t840.addr = alloca ptr
  store ptr %cr856, ptr %$t840.addr
  %ld857 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld857)
  %ld858 = load ptr, ptr %req_1.addr
  %cr859 = call ptr @Http.path$Request_V__2948(ptr %ld858)
  %$t841.addr = alloca ptr
  store ptr %cr859, ptr %$t841.addr
  %ld860 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld860)
  %ld861 = load ptr, ptr %req_1.addr
  %cr862 = call ptr @Http.query$Request_V__2950(ptr %ld861)
  %$t842.addr = alloca ptr
  store ptr %cr862, ptr %$t842.addr
  %ld863 = load ptr, ptr %req_1.addr
  call void @march_incrc(ptr %ld863)
  %ld864 = load ptr, ptr %req_1.addr
  %cr865 = call ptr @Http.headers$Request_V__2952(ptr %ld864)
  %$t843.addr = alloca ptr
  store ptr %cr865, ptr %$t843.addr
  %ld866 = load ptr, ptr %req_1.addr
  %cr867 = call ptr @Http.body$Request_V__2954(ptr %ld866)
  %$t844.addr = alloca ptr
  store ptr %cr867, ptr %$t844.addr
  %ld868 = load ptr, ptr %req_host.addr
  call void @march_incrc(ptr %ld868)
  %ld869 = load ptr, ptr %$t840.addr
  %ld870 = load ptr, ptr %req_host.addr
  %ld871 = load ptr, ptr %$t841.addr
  %ld872 = load ptr, ptr %$t842.addr
  %ld873 = load ptr, ptr %$t843.addr
  %ld874 = load ptr, ptr %$t844.addr
  %cr875 = call ptr @http_serialize_request(ptr %ld869, ptr %ld870, ptr %ld871, ptr %ld872, ptr %ld873, ptr %ld874)
  %raw_request.addr = alloca ptr
  store ptr %cr875, ptr %raw_request.addr
  %ld876 = load ptr, ptr %req_host.addr
  %ld877 = load i64, ptr %req_port.addr
  %cr878 = call ptr @tcp_connect(ptr %ld876, i64 %ld877)
  %$t845.addr = alloca ptr
  store ptr %cr878, ptr %$t845.addr
  %ld879 = load ptr, ptr %$t845.addr
  %res_slot880 = alloca ptr
  %tgp881 = getelementptr i8, ptr %ld879, i64 8
  %tag882 = load i32, ptr %tgp881, align 4
  switch i32 %tag882, label %case_default165 [
      i32 1, label %case_br166
      i32 0, label %case_br167
  ]
case_br166:
  %fp883 = getelementptr i8, ptr %ld879, i64 16
  %fv884 = load ptr, ptr %fp883, align 8
  %$f864.addr = alloca ptr
  store ptr %fv884, ptr %$f864.addr
  %freed885 = call i64 @march_decrc_freed(ptr %ld879)
  %freed_b886 = icmp ne i64 %freed885, 0
  br i1 %freed_b886, label %br_unique168, label %br_shared169
br_shared169:
  call void @march_incrc(ptr %fv884)
  br label %br_body170
br_unique168:
  br label %br_body170
br_body170:
  %ld887 = load ptr, ptr %$f864.addr
  %msg.addr = alloca ptr
  store ptr %ld887, ptr %msg.addr
  %hp888 = call ptr @march_alloc(i64 24)
  %tgp889 = getelementptr i8, ptr %hp888, i64 8
  store i32 0, ptr %tgp889, align 4
  %ld890 = load ptr, ptr %msg.addr
  %fp891 = getelementptr i8, ptr %hp888, i64 16
  store ptr %ld890, ptr %fp891, align 8
  %$t846.addr = alloca ptr
  store ptr %hp888, ptr %$t846.addr
  %hp892 = call ptr @march_alloc(i64 24)
  %tgp893 = getelementptr i8, ptr %hp892, i64 8
  store i32 1, ptr %tgp893, align 4
  %ld894 = load ptr, ptr %$t846.addr
  %fp895 = getelementptr i8, ptr %hp892, i64 16
  store ptr %ld894, ptr %fp895, align 8
  store ptr %hp892, ptr %res_slot880
  br label %case_merge164
case_br167:
  %fp896 = getelementptr i8, ptr %ld879, i64 16
  %fv897 = load ptr, ptr %fp896, align 8
  %$f865.addr = alloca ptr
  store ptr %fv897, ptr %$f865.addr
  %freed898 = call i64 @march_decrc_freed(ptr %ld879)
  %freed_b899 = icmp ne i64 %freed898, 0
  br i1 %freed_b899, label %br_unique171, label %br_shared172
br_shared172:
  call void @march_incrc(ptr %fv897)
  br label %br_body173
br_unique171:
  br label %br_body173
br_body173:
  %ld900 = load ptr, ptr %$f865.addr
  %fd.addr = alloca ptr
  store ptr %ld900, ptr %fd.addr
  %ld901 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld901)
  %ld902 = load ptr, ptr %fd.addr
  %ld903 = load ptr, ptr %raw_request.addr
  %cr904 = call ptr @march_tcp_send_all(ptr %ld902, ptr %ld903)
  %$t847.addr = alloca ptr
  store ptr %cr904, ptr %$t847.addr
  %ld905 = load ptr, ptr %$t847.addr
  %res_slot906 = alloca ptr
  %tgp907 = getelementptr i8, ptr %ld905, i64 8
  %tag908 = load i32, ptr %tgp907, align 4
  switch i32 %tag908, label %case_default175 [
      i32 1, label %case_br176
      i32 0, label %case_br177
  ]
case_br176:
  %fp909 = getelementptr i8, ptr %ld905, i64 16
  %fv910 = load ptr, ptr %fp909, align 8
  %$f862.addr = alloca ptr
  store ptr %fv910, ptr %$f862.addr
  %freed911 = call i64 @march_decrc_freed(ptr %ld905)
  %freed_b912 = icmp ne i64 %freed911, 0
  br i1 %freed_b912, label %br_unique178, label %br_shared179
br_shared179:
  call void @march_incrc(ptr %fv910)
  br label %br_body180
br_unique178:
  br label %br_body180
br_body180:
  %ld913 = load ptr, ptr %$f862.addr
  %msg_1.addr = alloca ptr
  store ptr %ld913, ptr %msg_1.addr
  %ld914 = load ptr, ptr %fd.addr
  %cr915 = call ptr @march_tcp_close(ptr %ld914)
  %hp916 = call ptr @march_alloc(i64 24)
  %tgp917 = getelementptr i8, ptr %hp916, i64 8
  store i32 2, ptr %tgp917, align 4
  %ld918 = load ptr, ptr %msg_1.addr
  %fp919 = getelementptr i8, ptr %hp916, i64 16
  store ptr %ld918, ptr %fp919, align 8
  %$t848.addr = alloca ptr
  store ptr %hp916, ptr %$t848.addr
  %hp920 = call ptr @march_alloc(i64 24)
  %tgp921 = getelementptr i8, ptr %hp920, i64 8
  store i32 1, ptr %tgp921, align 4
  %ld922 = load ptr, ptr %$t848.addr
  %fp923 = getelementptr i8, ptr %hp920, i64 16
  store ptr %ld922, ptr %fp923, align 8
  store ptr %hp920, ptr %res_slot906
  br label %case_merge174
case_br177:
  %fp924 = getelementptr i8, ptr %ld905, i64 16
  %fv925 = load ptr, ptr %fp924, align 8
  %$f863.addr = alloca ptr
  store ptr %fv925, ptr %$f863.addr
  %freed926 = call i64 @march_decrc_freed(ptr %ld905)
  %freed_b927 = icmp ne i64 %freed926, 0
  br i1 %freed_b927, label %br_unique181, label %br_shared182
br_shared182:
  call void @march_incrc(ptr %fv925)
  br label %br_body183
br_unique181:
  br label %br_body183
br_body183:
  %ld928 = load ptr, ptr %fd.addr
  call void @march_incrc(ptr %ld928)
  %ld929 = load ptr, ptr %fd.addr
  %cr930 = call ptr @tcp_recv_all(ptr %ld929, i64 1048576, i64 30000)
  %$t849.addr = alloca ptr
  store ptr %cr930, ptr %$t849.addr
  %ld931 = load ptr, ptr %$t849.addr
  %res_slot932 = alloca ptr
  %tgp933 = getelementptr i8, ptr %ld931, i64 8
  %tag934 = load i32, ptr %tgp933, align 4
  switch i32 %tag934, label %case_default185 [
      i32 1, label %case_br186
      i32 0, label %case_br187
  ]
case_br186:
  %fp935 = getelementptr i8, ptr %ld931, i64 16
  %fv936 = load ptr, ptr %fp935, align 8
  %$f860.addr = alloca ptr
  store ptr %fv936, ptr %$f860.addr
  %freed937 = call i64 @march_decrc_freed(ptr %ld931)
  %freed_b938 = icmp ne i64 %freed937, 0
  br i1 %freed_b938, label %br_unique188, label %br_shared189
br_shared189:
  call void @march_incrc(ptr %fv936)
  br label %br_body190
br_unique188:
  br label %br_body190
br_body190:
  %ld939 = load ptr, ptr %$f860.addr
  %msg_2.addr = alloca ptr
  store ptr %ld939, ptr %msg_2.addr
  %ld940 = load ptr, ptr %fd.addr
  %cr941 = call ptr @march_tcp_close(ptr %ld940)
  %hp942 = call ptr @march_alloc(i64 24)
  %tgp943 = getelementptr i8, ptr %hp942, i64 8
  store i32 3, ptr %tgp943, align 4
  %ld944 = load ptr, ptr %msg_2.addr
  %fp945 = getelementptr i8, ptr %hp942, i64 16
  store ptr %ld944, ptr %fp945, align 8
  %$t850.addr = alloca ptr
  store ptr %hp942, ptr %$t850.addr
  %hp946 = call ptr @march_alloc(i64 24)
  %tgp947 = getelementptr i8, ptr %hp946, i64 8
  store i32 1, ptr %tgp947, align 4
  %ld948 = load ptr, ptr %$t850.addr
  %fp949 = getelementptr i8, ptr %hp946, i64 16
  store ptr %ld948, ptr %fp949, align 8
  store ptr %hp946, ptr %res_slot932
  br label %case_merge184
case_br187:
  %fp950 = getelementptr i8, ptr %ld931, i64 16
  %fv951 = load ptr, ptr %fp950, align 8
  %$f861.addr = alloca ptr
  store ptr %fv951, ptr %$f861.addr
  %freed952 = call i64 @march_decrc_freed(ptr %ld931)
  %freed_b953 = icmp ne i64 %freed952, 0
  br i1 %freed_b953, label %br_unique191, label %br_shared192
br_shared192:
  call void @march_incrc(ptr %fv951)
  br label %br_body193
br_unique191:
  br label %br_body193
br_body193:
  %ld954 = load ptr, ptr %$f861.addr
  %raw_response.addr = alloca ptr
  store ptr %ld954, ptr %raw_response.addr
  %ld955 = load ptr, ptr %fd.addr
  %cr956 = call ptr @march_tcp_close(ptr %ld955)
  %ld957 = load ptr, ptr %raw_response.addr
  %cr958 = call ptr @http_parse_response(ptr %ld957)
  %$t851.addr = alloca ptr
  store ptr %cr958, ptr %$t851.addr
  %ld959 = load ptr, ptr %$t851.addr
  %res_slot960 = alloca ptr
  %tgp961 = getelementptr i8, ptr %ld959, i64 8
  %tag962 = load i32, ptr %tgp961, align 4
  switch i32 %tag962, label %case_default195 [
      i32 1, label %case_br196
      i32 0, label %case_br197
  ]
case_br196:
  %fp963 = getelementptr i8, ptr %ld959, i64 16
  %fv964 = load ptr, ptr %fp963, align 8
  %$f855.addr = alloca ptr
  store ptr %fv964, ptr %$f855.addr
  %freed965 = call i64 @march_decrc_freed(ptr %ld959)
  %freed_b966 = icmp ne i64 %freed965, 0
  br i1 %freed_b966, label %br_unique198, label %br_shared199
br_shared199:
  call void @march_incrc(ptr %fv964)
  br label %br_body200
br_unique198:
  br label %br_body200
br_body200:
  %ld967 = load ptr, ptr %$f855.addr
  %msg_3.addr = alloca ptr
  store ptr %ld967, ptr %msg_3.addr
  %hp968 = call ptr @march_alloc(i64 24)
  %tgp969 = getelementptr i8, ptr %hp968, i64 8
  store i32 0, ptr %tgp969, align 4
  %ld970 = load ptr, ptr %msg_3.addr
  %fp971 = getelementptr i8, ptr %hp968, i64 16
  store ptr %ld970, ptr %fp971, align 8
  %$t852.addr = alloca ptr
  store ptr %hp968, ptr %$t852.addr
  %hp972 = call ptr @march_alloc(i64 24)
  %tgp973 = getelementptr i8, ptr %hp972, i64 8
  store i32 1, ptr %tgp973, align 4
  %ld974 = load ptr, ptr %$t852.addr
  %fp975 = getelementptr i8, ptr %hp972, i64 16
  store ptr %ld974, ptr %fp975, align 8
  store ptr %hp972, ptr %res_slot960
  br label %case_merge194
case_br197:
  %fp976 = getelementptr i8, ptr %ld959, i64 16
  %fv977 = load ptr, ptr %fp976, align 8
  %$f856.addr = alloca ptr
  store ptr %fv977, ptr %$f856.addr
  %freed978 = call i64 @march_decrc_freed(ptr %ld959)
  %freed_b979 = icmp ne i64 %freed978, 0
  br i1 %freed_b979, label %br_unique201, label %br_shared202
br_shared202:
  call void @march_incrc(ptr %fv977)
  br label %br_body203
br_unique201:
  br label %br_body203
br_body203:
  %ld980 = load ptr, ptr %$f856.addr
  %res_slot981 = alloca ptr
  %tgp982 = getelementptr i8, ptr %ld980, i64 8
  %tag983 = load i32, ptr %tgp982, align 4
  switch i32 %tag983, label %case_default205 [
      i32 0, label %case_br206
  ]
case_br206:
  %fp984 = getelementptr i8, ptr %ld980, i64 16
  %fv985 = load ptr, ptr %fp984, align 8
  %$f857.addr = alloca ptr
  store ptr %fv985, ptr %$f857.addr
  %fp986 = getelementptr i8, ptr %ld980, i64 24
  %fv987 = load ptr, ptr %fp986, align 8
  %$f858.addr = alloca ptr
  store ptr %fv987, ptr %$f858.addr
  %fp988 = getelementptr i8, ptr %ld980, i64 32
  %fv989 = load ptr, ptr %fp988, align 8
  %$f859.addr = alloca ptr
  store ptr %fv989, ptr %$f859.addr
  %freed990 = call i64 @march_decrc_freed(ptr %ld980)
  %freed_b991 = icmp ne i64 %freed990, 0
  br i1 %freed_b991, label %br_unique207, label %br_shared208
br_shared208:
  call void @march_incrc(ptr %fv989)
  call void @march_incrc(ptr %fv987)
  call void @march_incrc(ptr %fv985)
  br label %br_body209
br_unique207:
  br label %br_body209
br_body209:
  %ld992 = load ptr, ptr %$f859.addr
  %resp_body.addr = alloca ptr
  store ptr %ld992, ptr %resp_body.addr
  %ld993 = load ptr, ptr %$f858.addr
  %resp_headers.addr = alloca ptr
  store ptr %ld993, ptr %resp_headers.addr
  %ld994 = load ptr, ptr %$f857.addr
  %status_code.addr = alloca ptr
  store ptr %ld994, ptr %status_code.addr
  %hp995 = call ptr @march_alloc(i64 24)
  %tgp996 = getelementptr i8, ptr %hp995, i64 8
  store i32 0, ptr %tgp996, align 4
  %ld997 = load ptr, ptr %status_code.addr
  %cv998 = ptrtoint ptr %ld997 to i64
  %fp999 = getelementptr i8, ptr %hp995, i64 16
  store i64 %cv998, ptr %fp999, align 8
  %$t853.addr = alloca ptr
  store ptr %hp995, ptr %$t853.addr
  %hp1000 = call ptr @march_alloc(i64 40)
  %tgp1001 = getelementptr i8, ptr %hp1000, i64 8
  store i32 0, ptr %tgp1001, align 4
  %ld1002 = load ptr, ptr %$t853.addr
  %fp1003 = getelementptr i8, ptr %hp1000, i64 16
  store ptr %ld1002, ptr %fp1003, align 8
  %ld1004 = load ptr, ptr %resp_headers.addr
  %fp1005 = getelementptr i8, ptr %hp1000, i64 24
  store ptr %ld1004, ptr %fp1005, align 8
  %ld1006 = load ptr, ptr %resp_body.addr
  %fp1007 = getelementptr i8, ptr %hp1000, i64 32
  store ptr %ld1006, ptr %fp1007, align 8
  %$t854.addr = alloca ptr
  store ptr %hp1000, ptr %$t854.addr
  %hp1008 = call ptr @march_alloc(i64 24)
  %tgp1009 = getelementptr i8, ptr %hp1008, i64 8
  store i32 0, ptr %tgp1009, align 4
  %ld1010 = load ptr, ptr %$t854.addr
  %fp1011 = getelementptr i8, ptr %hp1008, i64 16
  store ptr %ld1010, ptr %fp1011, align 8
  store ptr %hp1008, ptr %res_slot981
  br label %case_merge204
case_default205:
  unreachable
case_merge204:
  %case_r1012 = load ptr, ptr %res_slot981
  store ptr %case_r1012, ptr %res_slot960
  br label %case_merge194
case_default195:
  unreachable
case_merge194:
  %case_r1013 = load ptr, ptr %res_slot960
  store ptr %case_r1013, ptr %res_slot932
  br label %case_merge184
case_default185:
  unreachable
case_merge184:
  %case_r1014 = load ptr, ptr %res_slot932
  store ptr %case_r1014, ptr %res_slot906
  br label %case_merge174
case_default175:
  unreachable
case_merge174:
  %case_r1015 = load ptr, ptr %res_slot906
  store ptr %case_r1015, ptr %res_slot880
  br label %case_merge164
case_default165:
  unreachable
case_merge164:
  %case_r1016 = load ptr, ptr %res_slot880
  ret ptr %case_r1016
}

define ptr @Http.set_body$Request_T_$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld1017 = load ptr, ptr %req.addr
  %res_slot1018 = alloca ptr
  %tgp1019 = getelementptr i8, ptr %ld1017, i64 8
  %tag1020 = load i32, ptr %tgp1019, align 4
  switch i32 %tag1020, label %case_default211 [
      i32 0, label %case_br212
  ]
case_br212:
  %fp1021 = getelementptr i8, ptr %ld1017, i64 16
  %fv1022 = load ptr, ptr %fp1021, align 8
  %$f648.addr = alloca ptr
  store ptr %fv1022, ptr %$f648.addr
  %fp1023 = getelementptr i8, ptr %ld1017, i64 24
  %fv1024 = load ptr, ptr %fp1023, align 8
  %$f649.addr = alloca ptr
  store ptr %fv1024, ptr %$f649.addr
  %fp1025 = getelementptr i8, ptr %ld1017, i64 32
  %fv1026 = load ptr, ptr %fp1025, align 8
  %$f650.addr = alloca ptr
  store ptr %fv1026, ptr %$f650.addr
  %fp1027 = getelementptr i8, ptr %ld1017, i64 40
  %fv1028 = load ptr, ptr %fp1027, align 8
  %$f651.addr = alloca ptr
  store ptr %fv1028, ptr %$f651.addr
  %fp1029 = getelementptr i8, ptr %ld1017, i64 48
  %fv1030 = load ptr, ptr %fp1029, align 8
  %$f652.addr = alloca ptr
  store ptr %fv1030, ptr %$f652.addr
  %fp1031 = getelementptr i8, ptr %ld1017, i64 56
  %fv1032 = load ptr, ptr %fp1031, align 8
  %$f653.addr = alloca ptr
  store ptr %fv1032, ptr %$f653.addr
  %fp1033 = getelementptr i8, ptr %ld1017, i64 64
  %fv1034 = load ptr, ptr %fp1033, align 8
  %$f654.addr = alloca ptr
  store ptr %fv1034, ptr %$f654.addr
  %fp1035 = getelementptr i8, ptr %ld1017, i64 72
  %fv1036 = load ptr, ptr %fp1035, align 8
  %$f655.addr = alloca ptr
  store ptr %fv1036, ptr %$f655.addr
  %ld1037 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld1037, ptr %hd.addr
  %ld1038 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld1038, ptr %q.addr
  %ld1039 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld1039, ptr %pa.addr
  %ld1040 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld1040, ptr %p.addr
  %ld1041 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld1041, ptr %h.addr
  %ld1042 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld1042, ptr %sc.addr
  %ld1043 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld1043, ptr %m.addr
  %ld1044 = load ptr, ptr %req.addr
  %ld1045 = load ptr, ptr %m.addr
  %ld1046 = load ptr, ptr %sc.addr
  %ld1047 = load ptr, ptr %h.addr
  %ld1048 = load ptr, ptr %p.addr
  %ld1049 = load ptr, ptr %pa.addr
  %ld1050 = load ptr, ptr %q.addr
  %ld1051 = load ptr, ptr %hd.addr
  %ld1052 = load ptr, ptr %new_body.addr
  %rc1053 = load i64, ptr %ld1044, align 8
  %uniq1054 = icmp eq i64 %rc1053, 1
  %fbip_slot1055 = alloca ptr
  br i1 %uniq1054, label %fbip_reuse213, label %fbip_fresh214
fbip_reuse213:
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
  br label %fbip_merge215
fbip_fresh214:
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
  br label %fbip_merge215
fbip_merge215:
  %fbip_r1075 = load ptr, ptr %fbip_slot1055
  store ptr %fbip_r1075, ptr %res_slot1018
  br label %case_merge210
case_default211:
  unreachable
case_merge210:
  %case_r1076 = load ptr, ptr %res_slot1018
  ret ptr %case_r1076
}

define ptr @HttpClient.run(ptr %client.arg, ptr %req.arg) {
entry:
  %client.addr = alloca ptr
  store ptr %client.arg, ptr %client.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1077 = load ptr, ptr %client.addr
  %res_slot1078 = alloca ptr
  %tgp1079 = getelementptr i8, ptr %ld1077, i64 8
  %tag1080 = load i32, ptr %tgp1079, align 4
  switch i32 %tag1080, label %case_default217 [
      i32 0, label %case_br218
  ]
case_br218:
  %fp1081 = getelementptr i8, ptr %ld1077, i64 16
  %fv1082 = load ptr, ptr %fp1081, align 8
  %$f1052.addr = alloca ptr
  store ptr %fv1082, ptr %$f1052.addr
  %fp1083 = getelementptr i8, ptr %ld1077, i64 24
  %fv1084 = load ptr, ptr %fp1083, align 8
  %$f1053.addr = alloca ptr
  store ptr %fv1084, ptr %$f1053.addr
  %fp1085 = getelementptr i8, ptr %ld1077, i64 32
  %fv1086 = load ptr, ptr %fp1085, align 8
  %$f1054.addr = alloca ptr
  store ptr %fv1086, ptr %$f1054.addr
  %fp1087 = getelementptr i8, ptr %ld1077, i64 40
  %fv1088 = load i64, ptr %fp1087, align 8
  %$f1055.addr = alloca i64
  store i64 %fv1088, ptr %$f1055.addr
  %fp1089 = getelementptr i8, ptr %ld1077, i64 48
  %fv1090 = load i64, ptr %fp1089, align 8
  %$f1056.addr = alloca i64
  store i64 %fv1090, ptr %$f1056.addr
  %fp1091 = getelementptr i8, ptr %ld1077, i64 56
  %fv1092 = load i64, ptr %fp1091, align 8
  %$f1057.addr = alloca i64
  store i64 %fv1092, ptr %$f1057.addr
  %freed1093 = call i64 @march_decrc_freed(ptr %ld1077)
  %freed_b1094 = icmp ne i64 %freed1093, 0
  br i1 %freed_b1094, label %br_unique219, label %br_shared220
br_shared220:
  call void @march_incrc(ptr %fv1086)
  call void @march_incrc(ptr %fv1084)
  call void @march_incrc(ptr %fv1082)
  br label %br_body221
br_unique219:
  br label %br_body221
br_body221:
  %ld1095 = load i64, ptr %$f1056.addr
  %max_retries.addr = alloca i64
  store i64 %ld1095, ptr %max_retries.addr
  %ld1096 = load i64, ptr %$f1055.addr
  %max_redir.addr = alloca i64
  store i64 %ld1096, ptr %max_redir.addr
  %ld1097 = load ptr, ptr %$f1054.addr
  %err_steps.addr = alloca ptr
  store ptr %ld1097, ptr %err_steps.addr
  %ld1098 = load ptr, ptr %$f1053.addr
  %resp_steps.addr = alloca ptr
  store ptr %ld1098, ptr %resp_steps.addr
  %ld1099 = load ptr, ptr %$f1052.addr
  %req_steps.addr = alloca ptr
  store ptr %ld1099, ptr %req_steps.addr
  %ld1100 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1100)
  %ld1101 = load ptr, ptr %req_steps.addr
  %ld1102 = load ptr, ptr %req.addr
  %cr1103 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld1101, ptr %ld1102)
  %$t1037.addr = alloca ptr
  store ptr %cr1103, ptr %$t1037.addr
  %ld1104 = load ptr, ptr %$t1037.addr
  %res_slot1105 = alloca ptr
  %tgp1106 = getelementptr i8, ptr %ld1104, i64 8
  %tag1107 = load i32, ptr %tgp1106, align 4
  switch i32 %tag1107, label %case_default223 [
      i32 1, label %case_br224
      i32 0, label %case_br225
  ]
case_br224:
  %fp1108 = getelementptr i8, ptr %ld1104, i64 16
  %fv1109 = load ptr, ptr %fp1108, align 8
  %$f1050.addr = alloca ptr
  store ptr %fv1109, ptr %$f1050.addr
  %freed1110 = call i64 @march_decrc_freed(ptr %ld1104)
  %freed_b1111 = icmp ne i64 %freed1110, 0
  br i1 %freed_b1111, label %br_unique226, label %br_shared227
br_shared227:
  call void @march_incrc(ptr %fv1109)
  br label %br_body228
br_unique226:
  br label %br_body228
br_body228:
  %ld1112 = load ptr, ptr %$f1050.addr
  %e.addr = alloca ptr
  store ptr %ld1112, ptr %e.addr
  %ld1113 = load ptr, ptr %err_steps.addr
  %ld1114 = load ptr, ptr %req.addr
  %ld1115 = load ptr, ptr %e.addr
  %cr1116 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1113, ptr %ld1114, ptr %ld1115)
  store ptr %cr1116, ptr %res_slot1105
  br label %case_merge222
case_br225:
  %fp1117 = getelementptr i8, ptr %ld1104, i64 16
  %fv1118 = load ptr, ptr %fp1117, align 8
  %$f1051.addr = alloca ptr
  store ptr %fv1118, ptr %$f1051.addr
  %freed1119 = call i64 @march_decrc_freed(ptr %ld1104)
  %freed_b1120 = icmp ne i64 %freed1119, 0
  br i1 %freed_b1120, label %br_unique229, label %br_shared230
br_shared230:
  call void @march_incrc(ptr %fv1118)
  br label %br_body231
br_unique229:
  br label %br_body231
br_body231:
  %ld1121 = load ptr, ptr %$f1051.addr
  %transformed_req.addr = alloca ptr
  store ptr %ld1121, ptr %transformed_req.addr
  %ld1122 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld1122)
  %ld1123 = load ptr, ptr %transformed_req.addr
  %ld1124 = load i64, ptr %max_retries.addr
  %cr1125 = call ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %ld1123, i64 %ld1124)
  %$t1038.addr = alloca ptr
  store ptr %cr1125, ptr %$t1038.addr
  %ld1126 = load ptr, ptr %$t1038.addr
  %res_slot1127 = alloca ptr
  %tgp1128 = getelementptr i8, ptr %ld1126, i64 8
  %tag1129 = load i32, ptr %tgp1128, align 4
  switch i32 %tag1129, label %case_default233 [
      i32 1, label %case_br234
      i32 0, label %case_br235
  ]
case_br234:
  %fp1130 = getelementptr i8, ptr %ld1126, i64 16
  %fv1131 = load ptr, ptr %fp1130, align 8
  %$f1048.addr = alloca ptr
  store ptr %fv1131, ptr %$f1048.addr
  %freed1132 = call i64 @march_decrc_freed(ptr %ld1126)
  %freed_b1133 = icmp ne i64 %freed1132, 0
  br i1 %freed_b1133, label %br_unique236, label %br_shared237
br_shared237:
  call void @march_incrc(ptr %fv1131)
  br label %br_body238
br_unique236:
  br label %br_body238
br_body238:
  %ld1134 = load ptr, ptr %$f1048.addr
  %transport_err.addr = alloca ptr
  store ptr %ld1134, ptr %transport_err.addr
  %hp1135 = call ptr @march_alloc(i64 24)
  %tgp1136 = getelementptr i8, ptr %hp1135, i64 8
  store i32 0, ptr %tgp1136, align 4
  %ld1137 = load ptr, ptr %transport_err.addr
  %fp1138 = getelementptr i8, ptr %hp1135, i64 16
  store ptr %ld1137, ptr %fp1138, align 8
  %$t1039.addr = alloca ptr
  store ptr %hp1135, ptr %$t1039.addr
  %ld1139 = load ptr, ptr %err_steps.addr
  %ld1140 = load ptr, ptr %transformed_req.addr
  %ld1141 = load ptr, ptr %$t1039.addr
  %cr1142 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1139, ptr %ld1140, ptr %ld1141)
  store ptr %cr1142, ptr %res_slot1127
  br label %case_merge232
case_br235:
  %fp1143 = getelementptr i8, ptr %ld1126, i64 16
  %fv1144 = load ptr, ptr %fp1143, align 8
  %$f1049.addr = alloca ptr
  store ptr %fv1144, ptr %$f1049.addr
  %freed1145 = call i64 @march_decrc_freed(ptr %ld1126)
  %freed_b1146 = icmp ne i64 %freed1145, 0
  br i1 %freed_b1146, label %br_unique239, label %br_shared240
br_shared240:
  call void @march_incrc(ptr %fv1144)
  br label %br_body241
br_unique239:
  br label %br_body241
br_body241:
  %ld1147 = load ptr, ptr %$f1049.addr
  %resp.addr = alloca ptr
  store ptr %ld1147, ptr %resp.addr
  %ld1148 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld1148)
  %ld1149 = load ptr, ptr %transformed_req.addr
  %ld1150 = load ptr, ptr %resp.addr
  %ld1151 = load i64, ptr %max_redir.addr
  %cr1152 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3459$Int$Int(ptr %ld1149, ptr %ld1150, i64 %ld1151, i64 0)
  %$t1040.addr = alloca ptr
  store ptr %cr1152, ptr %$t1040.addr
  %ld1153 = load ptr, ptr %$t1040.addr
  %res_slot1154 = alloca ptr
  %tgp1155 = getelementptr i8, ptr %ld1153, i64 8
  %tag1156 = load i32, ptr %tgp1155, align 4
  switch i32 %tag1156, label %case_default243 [
      i32 1, label %case_br244
      i32 0, label %case_br245
  ]
case_br244:
  %fp1157 = getelementptr i8, ptr %ld1153, i64 16
  %fv1158 = load ptr, ptr %fp1157, align 8
  %$f1046.addr = alloca ptr
  store ptr %fv1158, ptr %$f1046.addr
  %freed1159 = call i64 @march_decrc_freed(ptr %ld1153)
  %freed_b1160 = icmp ne i64 %freed1159, 0
  br i1 %freed_b1160, label %br_unique246, label %br_shared247
br_shared247:
  call void @march_incrc(ptr %fv1158)
  br label %br_body248
br_unique246:
  br label %br_body248
br_body248:
  %ld1161 = load ptr, ptr %$f1046.addr
  %e_1.addr = alloca ptr
  store ptr %ld1161, ptr %e_1.addr
  %ld1162 = load ptr, ptr %err_steps.addr
  %ld1163 = load ptr, ptr %transformed_req.addr
  %ld1164 = load ptr, ptr %e_1.addr
  %cr1165 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1162, ptr %ld1163, ptr %ld1164)
  store ptr %cr1165, ptr %res_slot1154
  br label %case_merge242
case_br245:
  %fp1166 = getelementptr i8, ptr %ld1153, i64 16
  %fv1167 = load ptr, ptr %fp1166, align 8
  %$f1047.addr = alloca ptr
  store ptr %fv1167, ptr %$f1047.addr
  %freed1168 = call i64 @march_decrc_freed(ptr %ld1153)
  %freed_b1169 = icmp ne i64 %freed1168, 0
  br i1 %freed_b1169, label %br_unique249, label %br_shared250
br_shared250:
  call void @march_incrc(ptr %fv1167)
  br label %br_body251
br_unique249:
  br label %br_body251
br_body251:
  %ld1170 = load ptr, ptr %$f1047.addr
  %final_resp.addr = alloca ptr
  store ptr %ld1170, ptr %final_resp.addr
  %ld1171 = load ptr, ptr %transformed_req.addr
  call void @march_incrc(ptr %ld1171)
  %ld1172 = load ptr, ptr %resp_steps.addr
  %ld1173 = load ptr, ptr %transformed_req.addr
  %ld1174 = load ptr, ptr %final_resp.addr
  %cr1175 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3459(ptr %ld1172, ptr %ld1173, ptr %ld1174)
  %$t1041.addr = alloca ptr
  store ptr %cr1175, ptr %$t1041.addr
  %ld1176 = load ptr, ptr %$t1041.addr
  %res_slot1177 = alloca ptr
  %tgp1178 = getelementptr i8, ptr %ld1176, i64 8
  %tag1179 = load i32, ptr %tgp1178, align 4
  switch i32 %tag1179, label %case_default253 [
      i32 1, label %case_br254
      i32 0, label %case_br255
  ]
case_br254:
  %fp1180 = getelementptr i8, ptr %ld1176, i64 16
  %fv1181 = load ptr, ptr %fp1180, align 8
  %$f1042.addr = alloca ptr
  store ptr %fv1181, ptr %$f1042.addr
  %freed1182 = call i64 @march_decrc_freed(ptr %ld1176)
  %freed_b1183 = icmp ne i64 %freed1182, 0
  br i1 %freed_b1183, label %br_unique256, label %br_shared257
br_shared257:
  call void @march_incrc(ptr %fv1181)
  br label %br_body258
br_unique256:
  br label %br_body258
br_body258:
  %ld1184 = load ptr, ptr %$f1042.addr
  %e_2.addr = alloca ptr
  store ptr %ld1184, ptr %e_2.addr
  %ld1185 = load ptr, ptr %err_steps.addr
  %ld1186 = load ptr, ptr %transformed_req.addr
  %ld1187 = load ptr, ptr %e_2.addr
  %cr1188 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1185, ptr %ld1186, ptr %ld1187)
  store ptr %cr1188, ptr %res_slot1177
  br label %case_merge252
case_br255:
  %fp1189 = getelementptr i8, ptr %ld1176, i64 16
  %fv1190 = load ptr, ptr %fp1189, align 8
  %$f1043.addr = alloca ptr
  store ptr %fv1190, ptr %$f1043.addr
  %freed1191 = call i64 @march_decrc_freed(ptr %ld1176)
  %freed_b1192 = icmp ne i64 %freed1191, 0
  br i1 %freed_b1192, label %br_unique259, label %br_shared260
br_shared260:
  call void @march_incrc(ptr %fv1190)
  br label %br_body261
br_unique259:
  br label %br_body261
br_body261:
  %ld1193 = load ptr, ptr %$f1043.addr
  %res_slot1194 = alloca ptr
  %tgp1195 = getelementptr i8, ptr %ld1193, i64 8
  %tag1196 = load i32, ptr %tgp1195, align 4
  switch i32 %tag1196, label %case_default263 [
      i32 0, label %case_br264
  ]
case_br264:
  %fp1197 = getelementptr i8, ptr %ld1193, i64 16
  %fv1198 = load ptr, ptr %fp1197, align 8
  %$f1044.addr = alloca ptr
  store ptr %fv1198, ptr %$f1044.addr
  %fp1199 = getelementptr i8, ptr %ld1193, i64 24
  %fv1200 = load ptr, ptr %fp1199, align 8
  %$f1045.addr = alloca ptr
  store ptr %fv1200, ptr %$f1045.addr
  %freed1201 = call i64 @march_decrc_freed(ptr %ld1193)
  %freed_b1202 = icmp ne i64 %freed1201, 0
  br i1 %freed_b1202, label %br_unique265, label %br_shared266
br_shared266:
  call void @march_incrc(ptr %fv1200)
  call void @march_incrc(ptr %fv1198)
  br label %br_body267
br_unique265:
  br label %br_body267
br_body267:
  %ld1203 = load ptr, ptr %$f1045.addr
  %response.addr = alloca ptr
  store ptr %ld1203, ptr %response.addr
  %hp1204 = call ptr @march_alloc(i64 24)
  %tgp1205 = getelementptr i8, ptr %hp1204, i64 8
  store i32 0, ptr %tgp1205, align 4
  %ld1206 = load ptr, ptr %response.addr
  %fp1207 = getelementptr i8, ptr %hp1204, i64 16
  store ptr %ld1206, ptr %fp1207, align 8
  store ptr %hp1204, ptr %res_slot1194
  br label %case_merge262
case_default263:
  unreachable
case_merge262:
  %case_r1208 = load ptr, ptr %res_slot1194
  store ptr %case_r1208, ptr %res_slot1177
  br label %case_merge252
case_default253:
  unreachable
case_merge252:
  %case_r1209 = load ptr, ptr %res_slot1177
  store ptr %case_r1209, ptr %res_slot1154
  br label %case_merge242
case_default243:
  unreachable
case_merge242:
  %case_r1210 = load ptr, ptr %res_slot1154
  store ptr %case_r1210, ptr %res_slot1127
  br label %case_merge232
case_default233:
  unreachable
case_merge232:
  %case_r1211 = load ptr, ptr %res_slot1127
  store ptr %case_r1211, ptr %res_slot1105
  br label %case_merge222
case_default223:
  unreachable
case_merge222:
  %case_r1212 = load ptr, ptr %res_slot1105
  store ptr %case_r1212, ptr %res_slot1078
  br label %case_merge216
case_default217:
  unreachable
case_merge216:
  %case_r1213 = load ptr, ptr %res_slot1078
  ret ptr %case_r1213
}

define ptr @Http.post$String$String(ptr %url.arg, ptr %bdy.arg) {
entry:
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %bdy.addr = alloca ptr
  store ptr %bdy.arg, ptr %bdy.addr
  %ld1214 = load ptr, ptr %url.addr
  %cr1215 = call ptr @Http.parse_url(ptr %ld1214)
  %$t726.addr = alloca ptr
  store ptr %cr1215, ptr %$t726.addr
  %ld1216 = load ptr, ptr %$t726.addr
  %res_slot1217 = alloca ptr
  %tgp1218 = getelementptr i8, ptr %ld1216, i64 8
  %tag1219 = load i32, ptr %tgp1218, align 4
  switch i32 %tag1219, label %case_default269 [
      i32 0, label %case_br270
      i32 1, label %case_br271
  ]
case_br270:
  %fp1220 = getelementptr i8, ptr %ld1216, i64 16
  %fv1221 = load ptr, ptr %fp1220, align 8
  %$f730.addr = alloca ptr
  store ptr %fv1221, ptr %$f730.addr
  %ld1222 = load ptr, ptr %$f730.addr
  %req.addr = alloca ptr
  store ptr %ld1222, ptr %req.addr
  %ld1223 = load ptr, ptr %req.addr
  %ld1224 = load ptr, ptr %bdy.addr
  %cr1225 = call ptr @Http.set_body$Request_T_$V__2631(ptr %ld1223, ptr %ld1224)
  %$t727.addr = alloca ptr
  store ptr %cr1225, ptr %$t727.addr
  %hp1226 = call ptr @march_alloc(i64 16)
  %tgp1227 = getelementptr i8, ptr %hp1226, i64 8
  store i32 1, ptr %tgp1227, align 4
  %$t728.addr = alloca ptr
  store ptr %hp1226, ptr %$t728.addr
  %ld1228 = load ptr, ptr %$t727.addr
  %ld1229 = load ptr, ptr %$t728.addr
  %cr1230 = call ptr @Http.set_method$Request_V__2631$Method(ptr %ld1228, ptr %ld1229)
  %$t729.addr = alloca ptr
  store ptr %cr1230, ptr %$t729.addr
  %ld1231 = load ptr, ptr %$t726.addr
  %ld1232 = load ptr, ptr %$t729.addr
  %rc1233 = load i64, ptr %ld1231, align 8
  %uniq1234 = icmp eq i64 %rc1233, 1
  %fbip_slot1235 = alloca ptr
  br i1 %uniq1234, label %fbip_reuse272, label %fbip_fresh273
fbip_reuse272:
  %tgp1236 = getelementptr i8, ptr %ld1231, i64 8
  store i32 0, ptr %tgp1236, align 4
  %fp1237 = getelementptr i8, ptr %ld1231, i64 16
  store ptr %ld1232, ptr %fp1237, align 8
  store ptr %ld1231, ptr %fbip_slot1235
  br label %fbip_merge274
fbip_fresh273:
  call void @march_decrc(ptr %ld1231)
  %hp1238 = call ptr @march_alloc(i64 24)
  %tgp1239 = getelementptr i8, ptr %hp1238, i64 8
  store i32 0, ptr %tgp1239, align 4
  %fp1240 = getelementptr i8, ptr %hp1238, i64 16
  store ptr %ld1232, ptr %fp1240, align 8
  store ptr %hp1238, ptr %fbip_slot1235
  br label %fbip_merge274
fbip_merge274:
  %fbip_r1241 = load ptr, ptr %fbip_slot1235
  store ptr %fbip_r1241, ptr %res_slot1217
  br label %case_merge268
case_br271:
  %fp1242 = getelementptr i8, ptr %ld1216, i64 16
  %fv1243 = load ptr, ptr %fp1242, align 8
  %$f731.addr = alloca ptr
  store ptr %fv1243, ptr %$f731.addr
  %ld1244 = load ptr, ptr %$f731.addr
  %e.addr = alloca ptr
  store ptr %ld1244, ptr %e.addr
  %ld1245 = load ptr, ptr %$t726.addr
  %ld1246 = load ptr, ptr %e.addr
  %rc1247 = load i64, ptr %ld1245, align 8
  %uniq1248 = icmp eq i64 %rc1247, 1
  %fbip_slot1249 = alloca ptr
  br i1 %uniq1248, label %fbip_reuse275, label %fbip_fresh276
fbip_reuse275:
  %tgp1250 = getelementptr i8, ptr %ld1245, i64 8
  store i32 1, ptr %tgp1250, align 4
  %fp1251 = getelementptr i8, ptr %ld1245, i64 16
  store ptr %ld1246, ptr %fp1251, align 8
  store ptr %ld1245, ptr %fbip_slot1249
  br label %fbip_merge277
fbip_fresh276:
  call void @march_decrc(ptr %ld1245)
  %hp1252 = call ptr @march_alloc(i64 24)
  %tgp1253 = getelementptr i8, ptr %hp1252, i64 8
  store i32 1, ptr %tgp1253, align 4
  %fp1254 = getelementptr i8, ptr %hp1252, i64 16
  store ptr %ld1246, ptr %fp1254, align 8
  store ptr %hp1252, ptr %fbip_slot1249
  br label %fbip_merge277
fbip_merge277:
  %fbip_r1255 = load ptr, ptr %fbip_slot1249
  store ptr %fbip_r1255, ptr %res_slot1217
  br label %case_merge268
case_default269:
  unreachable
case_merge268:
  %case_r1256 = load ptr, ptr %res_slot1217
  ret ptr %case_r1256
}

define ptr @Http.set_header$Request_V__3640$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1257 = load ptr, ptr %req.addr
  %res_slot1258 = alloca ptr
  %tgp1259 = getelementptr i8, ptr %ld1257, i64 8
  %tag1260 = load i32, ptr %tgp1259, align 4
  switch i32 %tag1260, label %case_default279 [
      i32 0, label %case_br280
  ]
case_br280:
  %fp1261 = getelementptr i8, ptr %ld1257, i64 16
  %fv1262 = load ptr, ptr %fp1261, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1262, ptr %$f658.addr
  %fp1263 = getelementptr i8, ptr %ld1257, i64 24
  %fv1264 = load ptr, ptr %fp1263, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1264, ptr %$f659.addr
  %fp1265 = getelementptr i8, ptr %ld1257, i64 32
  %fv1266 = load ptr, ptr %fp1265, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1266, ptr %$f660.addr
  %fp1267 = getelementptr i8, ptr %ld1257, i64 40
  %fv1268 = load ptr, ptr %fp1267, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1268, ptr %$f661.addr
  %fp1269 = getelementptr i8, ptr %ld1257, i64 48
  %fv1270 = load ptr, ptr %fp1269, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1270, ptr %$f662.addr
  %fp1271 = getelementptr i8, ptr %ld1257, i64 56
  %fv1272 = load ptr, ptr %fp1271, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1272, ptr %$f663.addr
  %fp1273 = getelementptr i8, ptr %ld1257, i64 64
  %fv1274 = load ptr, ptr %fp1273, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1274, ptr %$f664.addr
  %fp1275 = getelementptr i8, ptr %ld1257, i64 72
  %fv1276 = load ptr, ptr %fp1275, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1276, ptr %$f665.addr
  %ld1277 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1277, ptr %bd.addr
  %ld1278 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1278, ptr %hd.addr
  %ld1279 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1279, ptr %q.addr
  %ld1280 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1280, ptr %pa.addr
  %ld1281 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1281, ptr %p.addr
  %ld1282 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1282, ptr %h.addr
  %ld1283 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1283, ptr %sc.addr
  %ld1284 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1284, ptr %m.addr
  %hp1285 = call ptr @march_alloc(i64 32)
  %tgp1286 = getelementptr i8, ptr %hp1285, i64 8
  store i32 0, ptr %tgp1286, align 4
  %ld1287 = load ptr, ptr %name.addr
  %fp1288 = getelementptr i8, ptr %hp1285, i64 16
  store ptr %ld1287, ptr %fp1288, align 8
  %ld1289 = load ptr, ptr %value.addr
  %fp1290 = getelementptr i8, ptr %hp1285, i64 24
  store ptr %ld1289, ptr %fp1290, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1285, ptr %$t656.addr
  %hp1291 = call ptr @march_alloc(i64 32)
  %tgp1292 = getelementptr i8, ptr %hp1291, i64 8
  store i32 1, ptr %tgp1292, align 4
  %ld1293 = load ptr, ptr %$t656.addr
  %fp1294 = getelementptr i8, ptr %hp1291, i64 16
  store ptr %ld1293, ptr %fp1294, align 8
  %ld1295 = load ptr, ptr %hd.addr
  %fp1296 = getelementptr i8, ptr %hp1291, i64 24
  store ptr %ld1295, ptr %fp1296, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1291, ptr %$t657.addr
  %ld1297 = load ptr, ptr %req.addr
  %ld1298 = load ptr, ptr %m.addr
  %ld1299 = load ptr, ptr %sc.addr
  %ld1300 = load ptr, ptr %h.addr
  %ld1301 = load ptr, ptr %p.addr
  %ld1302 = load ptr, ptr %pa.addr
  %ld1303 = load ptr, ptr %q.addr
  %ld1304 = load ptr, ptr %$t657.addr
  %ld1305 = load ptr, ptr %bd.addr
  %rc1306 = load i64, ptr %ld1297, align 8
  %uniq1307 = icmp eq i64 %rc1306, 1
  %fbip_slot1308 = alloca ptr
  br i1 %uniq1307, label %fbip_reuse281, label %fbip_fresh282
fbip_reuse281:
  %tgp1309 = getelementptr i8, ptr %ld1297, i64 8
  store i32 0, ptr %tgp1309, align 4
  %fp1310 = getelementptr i8, ptr %ld1297, i64 16
  store ptr %ld1298, ptr %fp1310, align 8
  %fp1311 = getelementptr i8, ptr %ld1297, i64 24
  store ptr %ld1299, ptr %fp1311, align 8
  %fp1312 = getelementptr i8, ptr %ld1297, i64 32
  store ptr %ld1300, ptr %fp1312, align 8
  %fp1313 = getelementptr i8, ptr %ld1297, i64 40
  store ptr %ld1301, ptr %fp1313, align 8
  %fp1314 = getelementptr i8, ptr %ld1297, i64 48
  store ptr %ld1302, ptr %fp1314, align 8
  %fp1315 = getelementptr i8, ptr %ld1297, i64 56
  store ptr %ld1303, ptr %fp1315, align 8
  %fp1316 = getelementptr i8, ptr %ld1297, i64 64
  store ptr %ld1304, ptr %fp1316, align 8
  %fp1317 = getelementptr i8, ptr %ld1297, i64 72
  store ptr %ld1305, ptr %fp1317, align 8
  store ptr %ld1297, ptr %fbip_slot1308
  br label %fbip_merge283
fbip_fresh282:
  call void @march_decrc(ptr %ld1297)
  %hp1318 = call ptr @march_alloc(i64 80)
  %tgp1319 = getelementptr i8, ptr %hp1318, i64 8
  store i32 0, ptr %tgp1319, align 4
  %fp1320 = getelementptr i8, ptr %hp1318, i64 16
  store ptr %ld1298, ptr %fp1320, align 8
  %fp1321 = getelementptr i8, ptr %hp1318, i64 24
  store ptr %ld1299, ptr %fp1321, align 8
  %fp1322 = getelementptr i8, ptr %hp1318, i64 32
  store ptr %ld1300, ptr %fp1322, align 8
  %fp1323 = getelementptr i8, ptr %hp1318, i64 40
  store ptr %ld1301, ptr %fp1323, align 8
  %fp1324 = getelementptr i8, ptr %hp1318, i64 48
  store ptr %ld1302, ptr %fp1324, align 8
  %fp1325 = getelementptr i8, ptr %hp1318, i64 56
  store ptr %ld1303, ptr %fp1325, align 8
  %fp1326 = getelementptr i8, ptr %hp1318, i64 64
  store ptr %ld1304, ptr %fp1326, align 8
  %fp1327 = getelementptr i8, ptr %hp1318, i64 72
  store ptr %ld1305, ptr %fp1327, align 8
  store ptr %hp1318, ptr %fbip_slot1308
  br label %fbip_merge283
fbip_merge283:
  %fbip_r1328 = load ptr, ptr %fbip_slot1308
  store ptr %fbip_r1328, ptr %res_slot1258
  br label %case_merge278
case_default279:
  unreachable
case_merge278:
  %case_r1329 = load ptr, ptr %res_slot1258
  ret ptr %case_r1329
}

define ptr @Http.set_header$Request_V__3638$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1330 = load ptr, ptr %req.addr
  %res_slot1331 = alloca ptr
  %tgp1332 = getelementptr i8, ptr %ld1330, i64 8
  %tag1333 = load i32, ptr %tgp1332, align 4
  switch i32 %tag1333, label %case_default285 [
      i32 0, label %case_br286
  ]
case_br286:
  %fp1334 = getelementptr i8, ptr %ld1330, i64 16
  %fv1335 = load ptr, ptr %fp1334, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1335, ptr %$f658.addr
  %fp1336 = getelementptr i8, ptr %ld1330, i64 24
  %fv1337 = load ptr, ptr %fp1336, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1337, ptr %$f659.addr
  %fp1338 = getelementptr i8, ptr %ld1330, i64 32
  %fv1339 = load ptr, ptr %fp1338, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1339, ptr %$f660.addr
  %fp1340 = getelementptr i8, ptr %ld1330, i64 40
  %fv1341 = load ptr, ptr %fp1340, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1341, ptr %$f661.addr
  %fp1342 = getelementptr i8, ptr %ld1330, i64 48
  %fv1343 = load ptr, ptr %fp1342, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1343, ptr %$f662.addr
  %fp1344 = getelementptr i8, ptr %ld1330, i64 56
  %fv1345 = load ptr, ptr %fp1344, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1345, ptr %$f663.addr
  %fp1346 = getelementptr i8, ptr %ld1330, i64 64
  %fv1347 = load ptr, ptr %fp1346, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1347, ptr %$f664.addr
  %fp1348 = getelementptr i8, ptr %ld1330, i64 72
  %fv1349 = load ptr, ptr %fp1348, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1349, ptr %$f665.addr
  %ld1350 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1350, ptr %bd.addr
  %ld1351 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1351, ptr %hd.addr
  %ld1352 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1352, ptr %q.addr
  %ld1353 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1353, ptr %pa.addr
  %ld1354 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1354, ptr %p.addr
  %ld1355 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1355, ptr %h.addr
  %ld1356 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1356, ptr %sc.addr
  %ld1357 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1357, ptr %m.addr
  %hp1358 = call ptr @march_alloc(i64 32)
  %tgp1359 = getelementptr i8, ptr %hp1358, i64 8
  store i32 0, ptr %tgp1359, align 4
  %ld1360 = load ptr, ptr %name.addr
  %fp1361 = getelementptr i8, ptr %hp1358, i64 16
  store ptr %ld1360, ptr %fp1361, align 8
  %ld1362 = load ptr, ptr %value.addr
  %fp1363 = getelementptr i8, ptr %hp1358, i64 24
  store ptr %ld1362, ptr %fp1363, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1358, ptr %$t656.addr
  %hp1364 = call ptr @march_alloc(i64 32)
  %tgp1365 = getelementptr i8, ptr %hp1364, i64 8
  store i32 1, ptr %tgp1365, align 4
  %ld1366 = load ptr, ptr %$t656.addr
  %fp1367 = getelementptr i8, ptr %hp1364, i64 16
  store ptr %ld1366, ptr %fp1367, align 8
  %ld1368 = load ptr, ptr %hd.addr
  %fp1369 = getelementptr i8, ptr %hp1364, i64 24
  store ptr %ld1368, ptr %fp1369, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1364, ptr %$t657.addr
  %ld1370 = load ptr, ptr %req.addr
  %ld1371 = load ptr, ptr %m.addr
  %ld1372 = load ptr, ptr %sc.addr
  %ld1373 = load ptr, ptr %h.addr
  %ld1374 = load ptr, ptr %p.addr
  %ld1375 = load ptr, ptr %pa.addr
  %ld1376 = load ptr, ptr %q.addr
  %ld1377 = load ptr, ptr %$t657.addr
  %ld1378 = load ptr, ptr %bd.addr
  %rc1379 = load i64, ptr %ld1370, align 8
  %uniq1380 = icmp eq i64 %rc1379, 1
  %fbip_slot1381 = alloca ptr
  br i1 %uniq1380, label %fbip_reuse287, label %fbip_fresh288
fbip_reuse287:
  %tgp1382 = getelementptr i8, ptr %ld1370, i64 8
  store i32 0, ptr %tgp1382, align 4
  %fp1383 = getelementptr i8, ptr %ld1370, i64 16
  store ptr %ld1371, ptr %fp1383, align 8
  %fp1384 = getelementptr i8, ptr %ld1370, i64 24
  store ptr %ld1372, ptr %fp1384, align 8
  %fp1385 = getelementptr i8, ptr %ld1370, i64 32
  store ptr %ld1373, ptr %fp1385, align 8
  %fp1386 = getelementptr i8, ptr %ld1370, i64 40
  store ptr %ld1374, ptr %fp1386, align 8
  %fp1387 = getelementptr i8, ptr %ld1370, i64 48
  store ptr %ld1375, ptr %fp1387, align 8
  %fp1388 = getelementptr i8, ptr %ld1370, i64 56
  store ptr %ld1376, ptr %fp1388, align 8
  %fp1389 = getelementptr i8, ptr %ld1370, i64 64
  store ptr %ld1377, ptr %fp1389, align 8
  %fp1390 = getelementptr i8, ptr %ld1370, i64 72
  store ptr %ld1378, ptr %fp1390, align 8
  store ptr %ld1370, ptr %fbip_slot1381
  br label %fbip_merge289
fbip_fresh288:
  call void @march_decrc(ptr %ld1370)
  %hp1391 = call ptr @march_alloc(i64 80)
  %tgp1392 = getelementptr i8, ptr %hp1391, i64 8
  store i32 0, ptr %tgp1392, align 4
  %fp1393 = getelementptr i8, ptr %hp1391, i64 16
  store ptr %ld1371, ptr %fp1393, align 8
  %fp1394 = getelementptr i8, ptr %hp1391, i64 24
  store ptr %ld1372, ptr %fp1394, align 8
  %fp1395 = getelementptr i8, ptr %hp1391, i64 32
  store ptr %ld1373, ptr %fp1395, align 8
  %fp1396 = getelementptr i8, ptr %hp1391, i64 40
  store ptr %ld1374, ptr %fp1396, align 8
  %fp1397 = getelementptr i8, ptr %hp1391, i64 48
  store ptr %ld1375, ptr %fp1397, align 8
  %fp1398 = getelementptr i8, ptr %hp1391, i64 56
  store ptr %ld1376, ptr %fp1398, align 8
  %fp1399 = getelementptr i8, ptr %hp1391, i64 64
  store ptr %ld1377, ptr %fp1399, align 8
  %fp1400 = getelementptr i8, ptr %hp1391, i64 72
  store ptr %ld1378, ptr %fp1400, align 8
  store ptr %hp1391, ptr %fbip_slot1381
  br label %fbip_merge289
fbip_merge289:
  %fbip_r1401 = load ptr, ptr %fbip_slot1381
  store ptr %fbip_r1401, ptr %res_slot1331
  br label %case_merge284
case_default285:
  unreachable
case_merge284:
  %case_r1402 = load ptr, ptr %res_slot1331
  ret ptr %case_r1402
}

define ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %xs.arg, ptr %x.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld1403 = load ptr, ptr %xs.addr
  %res_slot1404 = alloca ptr
  %tgp1405 = getelementptr i8, ptr %ld1403, i64 8
  %tag1406 = load i32, ptr %tgp1405, align 4
  switch i32 %tag1406, label %case_default291 [
      i32 0, label %case_br292
      i32 1, label %case_br293
  ]
case_br292:
  %ld1407 = load ptr, ptr %xs.addr
  %rc1408 = load i64, ptr %ld1407, align 8
  %uniq1409 = icmp eq i64 %rc1408, 1
  %fbip_slot1410 = alloca ptr
  br i1 %uniq1409, label %fbip_reuse294, label %fbip_fresh295
fbip_reuse294:
  %tgp1411 = getelementptr i8, ptr %ld1407, i64 8
  store i32 0, ptr %tgp1411, align 4
  store ptr %ld1407, ptr %fbip_slot1410
  br label %fbip_merge296
fbip_fresh295:
  call void @march_decrc(ptr %ld1407)
  %hp1412 = call ptr @march_alloc(i64 16)
  %tgp1413 = getelementptr i8, ptr %hp1412, i64 8
  store i32 0, ptr %tgp1413, align 4
  store ptr %hp1412, ptr %fbip_slot1410
  br label %fbip_merge296
fbip_merge296:
  %fbip_r1414 = load ptr, ptr %fbip_slot1410
  %$t883.addr = alloca ptr
  store ptr %fbip_r1414, ptr %$t883.addr
  %hp1415 = call ptr @march_alloc(i64 32)
  %tgp1416 = getelementptr i8, ptr %hp1415, i64 8
  store i32 1, ptr %tgp1416, align 4
  %ld1417 = load ptr, ptr %x.addr
  %fp1418 = getelementptr i8, ptr %hp1415, i64 16
  store ptr %ld1417, ptr %fp1418, align 8
  %ld1419 = load ptr, ptr %$t883.addr
  %fp1420 = getelementptr i8, ptr %hp1415, i64 24
  store ptr %ld1419, ptr %fp1420, align 8
  store ptr %hp1415, ptr %res_slot1404
  br label %case_merge290
case_br293:
  %fp1421 = getelementptr i8, ptr %ld1403, i64 16
  %fv1422 = load ptr, ptr %fp1421, align 8
  %$f885.addr = alloca ptr
  store ptr %fv1422, ptr %$f885.addr
  %fp1423 = getelementptr i8, ptr %ld1403, i64 24
  %fv1424 = load ptr, ptr %fp1423, align 8
  %$f886.addr = alloca ptr
  store ptr %fv1424, ptr %$f886.addr
  %ld1425 = load ptr, ptr %$f886.addr
  %t.addr = alloca ptr
  store ptr %ld1425, ptr %t.addr
  %ld1426 = load ptr, ptr %$f885.addr
  %h.addr = alloca ptr
  store ptr %ld1426, ptr %h.addr
  %ld1427 = load ptr, ptr %t.addr
  %ld1428 = load ptr, ptr %x.addr
  %cr1429 = call ptr @HttpClient.append_to_list$List_RequestStepEntry$RequestStepEntry(ptr %ld1427, ptr %ld1428)
  %$t884.addr = alloca ptr
  store ptr %cr1429, ptr %$t884.addr
  %ld1430 = load ptr, ptr %xs.addr
  %ld1431 = load ptr, ptr %h.addr
  %ld1432 = load ptr, ptr %$t884.addr
  %rc1433 = load i64, ptr %ld1430, align 8
  %uniq1434 = icmp eq i64 %rc1433, 1
  %fbip_slot1435 = alloca ptr
  br i1 %uniq1434, label %fbip_reuse297, label %fbip_fresh298
fbip_reuse297:
  %tgp1436 = getelementptr i8, ptr %ld1430, i64 8
  store i32 1, ptr %tgp1436, align 4
  %fp1437 = getelementptr i8, ptr %ld1430, i64 16
  store ptr %ld1431, ptr %fp1437, align 8
  %fp1438 = getelementptr i8, ptr %ld1430, i64 24
  store ptr %ld1432, ptr %fp1438, align 8
  store ptr %ld1430, ptr %fbip_slot1435
  br label %fbip_merge299
fbip_fresh298:
  call void @march_decrc(ptr %ld1430)
  %hp1439 = call ptr @march_alloc(i64 32)
  %tgp1440 = getelementptr i8, ptr %hp1439, i64 8
  store i32 1, ptr %tgp1440, align 4
  %fp1441 = getelementptr i8, ptr %hp1439, i64 16
  store ptr %ld1431, ptr %fp1441, align 8
  %fp1442 = getelementptr i8, ptr %hp1439, i64 24
  store ptr %ld1432, ptr %fp1442, align 8
  store ptr %hp1439, ptr %fbip_slot1435
  br label %fbip_merge299
fbip_merge299:
  %fbip_r1443 = load ptr, ptr %fbip_slot1435
  store ptr %fbip_r1443, ptr %res_slot1404
  br label %case_merge290
case_default291:
  unreachable
case_merge290:
  %case_r1444 = load ptr, ptr %res_slot1404
  ret ptr %case_r1444
}

define ptr @Http.response_status$Response_V__2518(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1445 = load ptr, ptr %resp.addr
  %res_slot1446 = alloca ptr
  %tgp1447 = getelementptr i8, ptr %ld1445, i64 8
  %tag1448 = load i32, ptr %tgp1447, align 4
  switch i32 %tag1448, label %case_default301 [
      i32 0, label %case_br302
  ]
case_br302:
  %fp1449 = getelementptr i8, ptr %ld1445, i64 16
  %fv1450 = load ptr, ptr %fp1449, align 8
  %$f666.addr = alloca ptr
  store ptr %fv1450, ptr %$f666.addr
  %fp1451 = getelementptr i8, ptr %ld1445, i64 24
  %fv1452 = load ptr, ptr %fp1451, align 8
  %$f667.addr = alloca ptr
  store ptr %fv1452, ptr %$f667.addr
  %fp1453 = getelementptr i8, ptr %ld1445, i64 32
  %fv1454 = load ptr, ptr %fp1453, align 8
  %$f668.addr = alloca ptr
  store ptr %fv1454, ptr %$f668.addr
  %freed1455 = call i64 @march_decrc_freed(ptr %ld1445)
  %freed_b1456 = icmp ne i64 %freed1455, 0
  br i1 %freed_b1456, label %br_unique303, label %br_shared304
br_shared304:
  call void @march_incrc(ptr %fv1454)
  call void @march_incrc(ptr %fv1452)
  call void @march_incrc(ptr %fv1450)
  br label %br_body305
br_unique303:
  br label %br_body305
br_body305:
  %ld1457 = load ptr, ptr %$f666.addr
  %s.addr = alloca ptr
  store ptr %ld1457, ptr %s.addr
  %ld1458 = load ptr, ptr %s.addr
  store ptr %ld1458, ptr %res_slot1446
  br label %case_merge300
case_default301:
  unreachable
case_merge300:
  %case_r1459 = load ptr, ptr %res_slot1446
  ret ptr %case_r1459
}

define ptr @Http.body$Request_V__2954(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1460 = load ptr, ptr %req.addr
  %res_slot1461 = alloca ptr
  %tgp1462 = getelementptr i8, ptr %ld1460, i64 8
  %tag1463 = load i32, ptr %tgp1462, align 4
  switch i32 %tag1463, label %case_default307 [
      i32 0, label %case_br308
  ]
case_br308:
  %fp1464 = getelementptr i8, ptr %ld1460, i64 16
  %fv1465 = load ptr, ptr %fp1464, align 8
  %$f599.addr = alloca ptr
  store ptr %fv1465, ptr %$f599.addr
  %fp1466 = getelementptr i8, ptr %ld1460, i64 24
  %fv1467 = load ptr, ptr %fp1466, align 8
  %$f600.addr = alloca ptr
  store ptr %fv1467, ptr %$f600.addr
  %fp1468 = getelementptr i8, ptr %ld1460, i64 32
  %fv1469 = load ptr, ptr %fp1468, align 8
  %$f601.addr = alloca ptr
  store ptr %fv1469, ptr %$f601.addr
  %fp1470 = getelementptr i8, ptr %ld1460, i64 40
  %fv1471 = load ptr, ptr %fp1470, align 8
  %$f602.addr = alloca ptr
  store ptr %fv1471, ptr %$f602.addr
  %fp1472 = getelementptr i8, ptr %ld1460, i64 48
  %fv1473 = load ptr, ptr %fp1472, align 8
  %$f603.addr = alloca ptr
  store ptr %fv1473, ptr %$f603.addr
  %fp1474 = getelementptr i8, ptr %ld1460, i64 56
  %fv1475 = load ptr, ptr %fp1474, align 8
  %$f604.addr = alloca ptr
  store ptr %fv1475, ptr %$f604.addr
  %fp1476 = getelementptr i8, ptr %ld1460, i64 64
  %fv1477 = load ptr, ptr %fp1476, align 8
  %$f605.addr = alloca ptr
  store ptr %fv1477, ptr %$f605.addr
  %fp1478 = getelementptr i8, ptr %ld1460, i64 72
  %fv1479 = load ptr, ptr %fp1478, align 8
  %$f606.addr = alloca ptr
  store ptr %fv1479, ptr %$f606.addr
  %freed1480 = call i64 @march_decrc_freed(ptr %ld1460)
  %freed_b1481 = icmp ne i64 %freed1480, 0
  br i1 %freed_b1481, label %br_unique309, label %br_shared310
br_shared310:
  call void @march_incrc(ptr %fv1479)
  call void @march_incrc(ptr %fv1477)
  call void @march_incrc(ptr %fv1475)
  call void @march_incrc(ptr %fv1473)
  call void @march_incrc(ptr %fv1471)
  call void @march_incrc(ptr %fv1469)
  call void @march_incrc(ptr %fv1467)
  call void @march_incrc(ptr %fv1465)
  br label %br_body311
br_unique309:
  br label %br_body311
br_body311:
  %ld1482 = load ptr, ptr %$f606.addr
  %b.addr = alloca ptr
  store ptr %ld1482, ptr %b.addr
  %ld1483 = load ptr, ptr %b.addr
  store ptr %ld1483, ptr %res_slot1461
  br label %case_merge306
case_default307:
  unreachable
case_merge306:
  %case_r1484 = load ptr, ptr %res_slot1461
  ret ptr %case_r1484
}

define ptr @Http.headers$Request_V__2952(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1485 = load ptr, ptr %req.addr
  %res_slot1486 = alloca ptr
  %tgp1487 = getelementptr i8, ptr %ld1485, i64 8
  %tag1488 = load i32, ptr %tgp1487, align 4
  switch i32 %tag1488, label %case_default313 [
      i32 0, label %case_br314
  ]
case_br314:
  %fp1489 = getelementptr i8, ptr %ld1485, i64 16
  %fv1490 = load ptr, ptr %fp1489, align 8
  %$f591.addr = alloca ptr
  store ptr %fv1490, ptr %$f591.addr
  %fp1491 = getelementptr i8, ptr %ld1485, i64 24
  %fv1492 = load ptr, ptr %fp1491, align 8
  %$f592.addr = alloca ptr
  store ptr %fv1492, ptr %$f592.addr
  %fp1493 = getelementptr i8, ptr %ld1485, i64 32
  %fv1494 = load ptr, ptr %fp1493, align 8
  %$f593.addr = alloca ptr
  store ptr %fv1494, ptr %$f593.addr
  %fp1495 = getelementptr i8, ptr %ld1485, i64 40
  %fv1496 = load ptr, ptr %fp1495, align 8
  %$f594.addr = alloca ptr
  store ptr %fv1496, ptr %$f594.addr
  %fp1497 = getelementptr i8, ptr %ld1485, i64 48
  %fv1498 = load ptr, ptr %fp1497, align 8
  %$f595.addr = alloca ptr
  store ptr %fv1498, ptr %$f595.addr
  %fp1499 = getelementptr i8, ptr %ld1485, i64 56
  %fv1500 = load ptr, ptr %fp1499, align 8
  %$f596.addr = alloca ptr
  store ptr %fv1500, ptr %$f596.addr
  %fp1501 = getelementptr i8, ptr %ld1485, i64 64
  %fv1502 = load ptr, ptr %fp1501, align 8
  %$f597.addr = alloca ptr
  store ptr %fv1502, ptr %$f597.addr
  %fp1503 = getelementptr i8, ptr %ld1485, i64 72
  %fv1504 = load ptr, ptr %fp1503, align 8
  %$f598.addr = alloca ptr
  store ptr %fv1504, ptr %$f598.addr
  %freed1505 = call i64 @march_decrc_freed(ptr %ld1485)
  %freed_b1506 = icmp ne i64 %freed1505, 0
  br i1 %freed_b1506, label %br_unique315, label %br_shared316
br_shared316:
  call void @march_incrc(ptr %fv1504)
  call void @march_incrc(ptr %fv1502)
  call void @march_incrc(ptr %fv1500)
  call void @march_incrc(ptr %fv1498)
  call void @march_incrc(ptr %fv1496)
  call void @march_incrc(ptr %fv1494)
  call void @march_incrc(ptr %fv1492)
  call void @march_incrc(ptr %fv1490)
  br label %br_body317
br_unique315:
  br label %br_body317
br_body317:
  %ld1507 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld1507, ptr %h.addr
  %ld1508 = load ptr, ptr %h.addr
  store ptr %ld1508, ptr %res_slot1486
  br label %case_merge312
case_default313:
  unreachable
case_merge312:
  %case_r1509 = load ptr, ptr %res_slot1486
  ret ptr %case_r1509
}

define ptr @Http.query$Request_V__2950(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1510 = load ptr, ptr %req.addr
  %res_slot1511 = alloca ptr
  %tgp1512 = getelementptr i8, ptr %ld1510, i64 8
  %tag1513 = load i32, ptr %tgp1512, align 4
  switch i32 %tag1513, label %case_default319 [
      i32 0, label %case_br320
  ]
case_br320:
  %fp1514 = getelementptr i8, ptr %ld1510, i64 16
  %fv1515 = load ptr, ptr %fp1514, align 8
  %$f583.addr = alloca ptr
  store ptr %fv1515, ptr %$f583.addr
  %fp1516 = getelementptr i8, ptr %ld1510, i64 24
  %fv1517 = load ptr, ptr %fp1516, align 8
  %$f584.addr = alloca ptr
  store ptr %fv1517, ptr %$f584.addr
  %fp1518 = getelementptr i8, ptr %ld1510, i64 32
  %fv1519 = load ptr, ptr %fp1518, align 8
  %$f585.addr = alloca ptr
  store ptr %fv1519, ptr %$f585.addr
  %fp1520 = getelementptr i8, ptr %ld1510, i64 40
  %fv1521 = load ptr, ptr %fp1520, align 8
  %$f586.addr = alloca ptr
  store ptr %fv1521, ptr %$f586.addr
  %fp1522 = getelementptr i8, ptr %ld1510, i64 48
  %fv1523 = load ptr, ptr %fp1522, align 8
  %$f587.addr = alloca ptr
  store ptr %fv1523, ptr %$f587.addr
  %fp1524 = getelementptr i8, ptr %ld1510, i64 56
  %fv1525 = load ptr, ptr %fp1524, align 8
  %$f588.addr = alloca ptr
  store ptr %fv1525, ptr %$f588.addr
  %fp1526 = getelementptr i8, ptr %ld1510, i64 64
  %fv1527 = load ptr, ptr %fp1526, align 8
  %$f589.addr = alloca ptr
  store ptr %fv1527, ptr %$f589.addr
  %fp1528 = getelementptr i8, ptr %ld1510, i64 72
  %fv1529 = load ptr, ptr %fp1528, align 8
  %$f590.addr = alloca ptr
  store ptr %fv1529, ptr %$f590.addr
  %freed1530 = call i64 @march_decrc_freed(ptr %ld1510)
  %freed_b1531 = icmp ne i64 %freed1530, 0
  br i1 %freed_b1531, label %br_unique321, label %br_shared322
br_shared322:
  call void @march_incrc(ptr %fv1529)
  call void @march_incrc(ptr %fv1527)
  call void @march_incrc(ptr %fv1525)
  call void @march_incrc(ptr %fv1523)
  call void @march_incrc(ptr %fv1521)
  call void @march_incrc(ptr %fv1519)
  call void @march_incrc(ptr %fv1517)
  call void @march_incrc(ptr %fv1515)
  br label %br_body323
br_unique321:
  br label %br_body323
br_body323:
  %ld1532 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld1532, ptr %q.addr
  %ld1533 = load ptr, ptr %q.addr
  store ptr %ld1533, ptr %res_slot1511
  br label %case_merge318
case_default319:
  unreachable
case_merge318:
  %case_r1534 = load ptr, ptr %res_slot1511
  ret ptr %case_r1534
}

define ptr @Http.path$Request_V__2948(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1535 = load ptr, ptr %req.addr
  %res_slot1536 = alloca ptr
  %tgp1537 = getelementptr i8, ptr %ld1535, i64 8
  %tag1538 = load i32, ptr %tgp1537, align 4
  switch i32 %tag1538, label %case_default325 [
      i32 0, label %case_br326
  ]
case_br326:
  %fp1539 = getelementptr i8, ptr %ld1535, i64 16
  %fv1540 = load ptr, ptr %fp1539, align 8
  %$f575.addr = alloca ptr
  store ptr %fv1540, ptr %$f575.addr
  %fp1541 = getelementptr i8, ptr %ld1535, i64 24
  %fv1542 = load ptr, ptr %fp1541, align 8
  %$f576.addr = alloca ptr
  store ptr %fv1542, ptr %$f576.addr
  %fp1543 = getelementptr i8, ptr %ld1535, i64 32
  %fv1544 = load ptr, ptr %fp1543, align 8
  %$f577.addr = alloca ptr
  store ptr %fv1544, ptr %$f577.addr
  %fp1545 = getelementptr i8, ptr %ld1535, i64 40
  %fv1546 = load ptr, ptr %fp1545, align 8
  %$f578.addr = alloca ptr
  store ptr %fv1546, ptr %$f578.addr
  %fp1547 = getelementptr i8, ptr %ld1535, i64 48
  %fv1548 = load ptr, ptr %fp1547, align 8
  %$f579.addr = alloca ptr
  store ptr %fv1548, ptr %$f579.addr
  %fp1549 = getelementptr i8, ptr %ld1535, i64 56
  %fv1550 = load ptr, ptr %fp1549, align 8
  %$f580.addr = alloca ptr
  store ptr %fv1550, ptr %$f580.addr
  %fp1551 = getelementptr i8, ptr %ld1535, i64 64
  %fv1552 = load ptr, ptr %fp1551, align 8
  %$f581.addr = alloca ptr
  store ptr %fv1552, ptr %$f581.addr
  %fp1553 = getelementptr i8, ptr %ld1535, i64 72
  %fv1554 = load ptr, ptr %fp1553, align 8
  %$f582.addr = alloca ptr
  store ptr %fv1554, ptr %$f582.addr
  %freed1555 = call i64 @march_decrc_freed(ptr %ld1535)
  %freed_b1556 = icmp ne i64 %freed1555, 0
  br i1 %freed_b1556, label %br_unique327, label %br_shared328
br_shared328:
  call void @march_incrc(ptr %fv1554)
  call void @march_incrc(ptr %fv1552)
  call void @march_incrc(ptr %fv1550)
  call void @march_incrc(ptr %fv1548)
  call void @march_incrc(ptr %fv1546)
  call void @march_incrc(ptr %fv1544)
  call void @march_incrc(ptr %fv1542)
  call void @march_incrc(ptr %fv1540)
  br label %br_body329
br_unique327:
  br label %br_body329
br_body329:
  %ld1557 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld1557, ptr %p.addr
  %ld1558 = load ptr, ptr %p.addr
  store ptr %ld1558, ptr %res_slot1536
  br label %case_merge324
case_default325:
  unreachable
case_merge324:
  %case_r1559 = load ptr, ptr %res_slot1536
  ret ptr %case_r1559
}

define ptr @Http.method$Request_V__2946(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1560 = load ptr, ptr %req.addr
  %res_slot1561 = alloca ptr
  %tgp1562 = getelementptr i8, ptr %ld1560, i64 8
  %tag1563 = load i32, ptr %tgp1562, align 4
  switch i32 %tag1563, label %case_default331 [
      i32 0, label %case_br332
  ]
case_br332:
  %fp1564 = getelementptr i8, ptr %ld1560, i64 16
  %fv1565 = load ptr, ptr %fp1564, align 8
  %$f543.addr = alloca ptr
  store ptr %fv1565, ptr %$f543.addr
  %fp1566 = getelementptr i8, ptr %ld1560, i64 24
  %fv1567 = load ptr, ptr %fp1566, align 8
  %$f544.addr = alloca ptr
  store ptr %fv1567, ptr %$f544.addr
  %fp1568 = getelementptr i8, ptr %ld1560, i64 32
  %fv1569 = load ptr, ptr %fp1568, align 8
  %$f545.addr = alloca ptr
  store ptr %fv1569, ptr %$f545.addr
  %fp1570 = getelementptr i8, ptr %ld1560, i64 40
  %fv1571 = load ptr, ptr %fp1570, align 8
  %$f546.addr = alloca ptr
  store ptr %fv1571, ptr %$f546.addr
  %fp1572 = getelementptr i8, ptr %ld1560, i64 48
  %fv1573 = load ptr, ptr %fp1572, align 8
  %$f547.addr = alloca ptr
  store ptr %fv1573, ptr %$f547.addr
  %fp1574 = getelementptr i8, ptr %ld1560, i64 56
  %fv1575 = load ptr, ptr %fp1574, align 8
  %$f548.addr = alloca ptr
  store ptr %fv1575, ptr %$f548.addr
  %fp1576 = getelementptr i8, ptr %ld1560, i64 64
  %fv1577 = load ptr, ptr %fp1576, align 8
  %$f549.addr = alloca ptr
  store ptr %fv1577, ptr %$f549.addr
  %fp1578 = getelementptr i8, ptr %ld1560, i64 72
  %fv1579 = load ptr, ptr %fp1578, align 8
  %$f550.addr = alloca ptr
  store ptr %fv1579, ptr %$f550.addr
  %freed1580 = call i64 @march_decrc_freed(ptr %ld1560)
  %freed_b1581 = icmp ne i64 %freed1580, 0
  br i1 %freed_b1581, label %br_unique333, label %br_shared334
br_shared334:
  call void @march_incrc(ptr %fv1579)
  call void @march_incrc(ptr %fv1577)
  call void @march_incrc(ptr %fv1575)
  call void @march_incrc(ptr %fv1573)
  call void @march_incrc(ptr %fv1571)
  call void @march_incrc(ptr %fv1569)
  call void @march_incrc(ptr %fv1567)
  call void @march_incrc(ptr %fv1565)
  br label %br_body335
br_unique333:
  br label %br_body335
br_body335:
  %ld1582 = load ptr, ptr %$f543.addr
  %m.addr = alloca ptr
  store ptr %ld1582, ptr %m.addr
  %ld1583 = load ptr, ptr %m.addr
  store ptr %ld1583, ptr %res_slot1561
  br label %case_merge330
case_default331:
  unreachable
case_merge330:
  %case_r1584 = load ptr, ptr %res_slot1561
  ret ptr %case_r1584
}

define ptr @Http.port$Request_V__2939(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1585 = load ptr, ptr %req.addr
  %res_slot1586 = alloca ptr
  %tgp1587 = getelementptr i8, ptr %ld1585, i64 8
  %tag1588 = load i32, ptr %tgp1587, align 4
  switch i32 %tag1588, label %case_default337 [
      i32 0, label %case_br338
  ]
case_br338:
  %fp1589 = getelementptr i8, ptr %ld1585, i64 16
  %fv1590 = load ptr, ptr %fp1589, align 8
  %$f567.addr = alloca ptr
  store ptr %fv1590, ptr %$f567.addr
  %fp1591 = getelementptr i8, ptr %ld1585, i64 24
  %fv1592 = load ptr, ptr %fp1591, align 8
  %$f568.addr = alloca ptr
  store ptr %fv1592, ptr %$f568.addr
  %fp1593 = getelementptr i8, ptr %ld1585, i64 32
  %fv1594 = load ptr, ptr %fp1593, align 8
  %$f569.addr = alloca ptr
  store ptr %fv1594, ptr %$f569.addr
  %fp1595 = getelementptr i8, ptr %ld1585, i64 40
  %fv1596 = load ptr, ptr %fp1595, align 8
  %$f570.addr = alloca ptr
  store ptr %fv1596, ptr %$f570.addr
  %fp1597 = getelementptr i8, ptr %ld1585, i64 48
  %fv1598 = load ptr, ptr %fp1597, align 8
  %$f571.addr = alloca ptr
  store ptr %fv1598, ptr %$f571.addr
  %fp1599 = getelementptr i8, ptr %ld1585, i64 56
  %fv1600 = load ptr, ptr %fp1599, align 8
  %$f572.addr = alloca ptr
  store ptr %fv1600, ptr %$f572.addr
  %fp1601 = getelementptr i8, ptr %ld1585, i64 64
  %fv1602 = load ptr, ptr %fp1601, align 8
  %$f573.addr = alloca ptr
  store ptr %fv1602, ptr %$f573.addr
  %fp1603 = getelementptr i8, ptr %ld1585, i64 72
  %fv1604 = load ptr, ptr %fp1603, align 8
  %$f574.addr = alloca ptr
  store ptr %fv1604, ptr %$f574.addr
  %freed1605 = call i64 @march_decrc_freed(ptr %ld1585)
  %freed_b1606 = icmp ne i64 %freed1605, 0
  br i1 %freed_b1606, label %br_unique339, label %br_shared340
br_shared340:
  call void @march_incrc(ptr %fv1604)
  call void @march_incrc(ptr %fv1602)
  call void @march_incrc(ptr %fv1600)
  call void @march_incrc(ptr %fv1598)
  call void @march_incrc(ptr %fv1596)
  call void @march_incrc(ptr %fv1594)
  call void @march_incrc(ptr %fv1592)
  call void @march_incrc(ptr %fv1590)
  br label %br_body341
br_unique339:
  br label %br_body341
br_body341:
  %ld1607 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld1607, ptr %p.addr
  %ld1608 = load ptr, ptr %p.addr
  store ptr %ld1608, ptr %res_slot1586
  br label %case_merge336
case_default337:
  unreachable
case_merge336:
  %case_r1609 = load ptr, ptr %res_slot1586
  ret ptr %case_r1609
}

define ptr @Http.host$Request_V__2936(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld1610 = load ptr, ptr %req.addr
  %res_slot1611 = alloca ptr
  %tgp1612 = getelementptr i8, ptr %ld1610, i64 8
  %tag1613 = load i32, ptr %tgp1612, align 4
  switch i32 %tag1613, label %case_default343 [
      i32 0, label %case_br344
  ]
case_br344:
  %fp1614 = getelementptr i8, ptr %ld1610, i64 16
  %fv1615 = load ptr, ptr %fp1614, align 8
  %$f559.addr = alloca ptr
  store ptr %fv1615, ptr %$f559.addr
  %fp1616 = getelementptr i8, ptr %ld1610, i64 24
  %fv1617 = load ptr, ptr %fp1616, align 8
  %$f560.addr = alloca ptr
  store ptr %fv1617, ptr %$f560.addr
  %fp1618 = getelementptr i8, ptr %ld1610, i64 32
  %fv1619 = load ptr, ptr %fp1618, align 8
  %$f561.addr = alloca ptr
  store ptr %fv1619, ptr %$f561.addr
  %fp1620 = getelementptr i8, ptr %ld1610, i64 40
  %fv1621 = load ptr, ptr %fp1620, align 8
  %$f562.addr = alloca ptr
  store ptr %fv1621, ptr %$f562.addr
  %fp1622 = getelementptr i8, ptr %ld1610, i64 48
  %fv1623 = load ptr, ptr %fp1622, align 8
  %$f563.addr = alloca ptr
  store ptr %fv1623, ptr %$f563.addr
  %fp1624 = getelementptr i8, ptr %ld1610, i64 56
  %fv1625 = load ptr, ptr %fp1624, align 8
  %$f564.addr = alloca ptr
  store ptr %fv1625, ptr %$f564.addr
  %fp1626 = getelementptr i8, ptr %ld1610, i64 64
  %fv1627 = load ptr, ptr %fp1626, align 8
  %$f565.addr = alloca ptr
  store ptr %fv1627, ptr %$f565.addr
  %fp1628 = getelementptr i8, ptr %ld1610, i64 72
  %fv1629 = load ptr, ptr %fp1628, align 8
  %$f566.addr = alloca ptr
  store ptr %fv1629, ptr %$f566.addr
  %freed1630 = call i64 @march_decrc_freed(ptr %ld1610)
  %freed_b1631 = icmp ne i64 %freed1630, 0
  br i1 %freed_b1631, label %br_unique345, label %br_shared346
br_shared346:
  call void @march_incrc(ptr %fv1629)
  call void @march_incrc(ptr %fv1627)
  call void @march_incrc(ptr %fv1625)
  call void @march_incrc(ptr %fv1623)
  call void @march_incrc(ptr %fv1621)
  call void @march_incrc(ptr %fv1619)
  call void @march_incrc(ptr %fv1617)
  call void @march_incrc(ptr %fv1615)
  br label %br_body347
br_unique345:
  br label %br_body347
br_body347:
  %ld1632 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld1632, ptr %h.addr
  %ld1633 = load ptr, ptr %h.addr
  store ptr %ld1633, ptr %res_slot1611
  br label %case_merge342
case_default343:
  unreachable
case_merge342:
  %case_r1634 = load ptr, ptr %res_slot1611
  ret ptr %case_r1634
}

define ptr @Http.set_header$Request_String$String$String(ptr %req.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld1635 = load ptr, ptr %req.addr
  %res_slot1636 = alloca ptr
  %tgp1637 = getelementptr i8, ptr %ld1635, i64 8
  %tag1638 = load i32, ptr %tgp1637, align 4
  switch i32 %tag1638, label %case_default349 [
      i32 0, label %case_br350
  ]
case_br350:
  %fp1639 = getelementptr i8, ptr %ld1635, i64 16
  %fv1640 = load ptr, ptr %fp1639, align 8
  %$f658.addr = alloca ptr
  store ptr %fv1640, ptr %$f658.addr
  %fp1641 = getelementptr i8, ptr %ld1635, i64 24
  %fv1642 = load ptr, ptr %fp1641, align 8
  %$f659.addr = alloca ptr
  store ptr %fv1642, ptr %$f659.addr
  %fp1643 = getelementptr i8, ptr %ld1635, i64 32
  %fv1644 = load ptr, ptr %fp1643, align 8
  %$f660.addr = alloca ptr
  store ptr %fv1644, ptr %$f660.addr
  %fp1645 = getelementptr i8, ptr %ld1635, i64 40
  %fv1646 = load ptr, ptr %fp1645, align 8
  %$f661.addr = alloca ptr
  store ptr %fv1646, ptr %$f661.addr
  %fp1647 = getelementptr i8, ptr %ld1635, i64 48
  %fv1648 = load ptr, ptr %fp1647, align 8
  %$f662.addr = alloca ptr
  store ptr %fv1648, ptr %$f662.addr
  %fp1649 = getelementptr i8, ptr %ld1635, i64 56
  %fv1650 = load ptr, ptr %fp1649, align 8
  %$f663.addr = alloca ptr
  store ptr %fv1650, ptr %$f663.addr
  %fp1651 = getelementptr i8, ptr %ld1635, i64 64
  %fv1652 = load ptr, ptr %fp1651, align 8
  %$f664.addr = alloca ptr
  store ptr %fv1652, ptr %$f664.addr
  %fp1653 = getelementptr i8, ptr %ld1635, i64 72
  %fv1654 = load ptr, ptr %fp1653, align 8
  %$f665.addr = alloca ptr
  store ptr %fv1654, ptr %$f665.addr
  %ld1655 = load ptr, ptr %$f665.addr
  %bd.addr = alloca ptr
  store ptr %ld1655, ptr %bd.addr
  %ld1656 = load ptr, ptr %$f664.addr
  %hd.addr = alloca ptr
  store ptr %ld1656, ptr %hd.addr
  %ld1657 = load ptr, ptr %$f663.addr
  %q.addr = alloca ptr
  store ptr %ld1657, ptr %q.addr
  %ld1658 = load ptr, ptr %$f662.addr
  %pa.addr = alloca ptr
  store ptr %ld1658, ptr %pa.addr
  %ld1659 = load ptr, ptr %$f661.addr
  %p.addr = alloca ptr
  store ptr %ld1659, ptr %p.addr
  %ld1660 = load ptr, ptr %$f660.addr
  %h.addr = alloca ptr
  store ptr %ld1660, ptr %h.addr
  %ld1661 = load ptr, ptr %$f659.addr
  %sc.addr = alloca ptr
  store ptr %ld1661, ptr %sc.addr
  %ld1662 = load ptr, ptr %$f658.addr
  %m.addr = alloca ptr
  store ptr %ld1662, ptr %m.addr
  %hp1663 = call ptr @march_alloc(i64 32)
  %tgp1664 = getelementptr i8, ptr %hp1663, i64 8
  store i32 0, ptr %tgp1664, align 4
  %ld1665 = load ptr, ptr %name.addr
  %fp1666 = getelementptr i8, ptr %hp1663, i64 16
  store ptr %ld1665, ptr %fp1666, align 8
  %ld1667 = load ptr, ptr %value.addr
  %fp1668 = getelementptr i8, ptr %hp1663, i64 24
  store ptr %ld1667, ptr %fp1668, align 8
  %$t656.addr = alloca ptr
  store ptr %hp1663, ptr %$t656.addr
  %hp1669 = call ptr @march_alloc(i64 32)
  %tgp1670 = getelementptr i8, ptr %hp1669, i64 8
  store i32 1, ptr %tgp1670, align 4
  %ld1671 = load ptr, ptr %$t656.addr
  %fp1672 = getelementptr i8, ptr %hp1669, i64 16
  store ptr %ld1671, ptr %fp1672, align 8
  %ld1673 = load ptr, ptr %hd.addr
  %fp1674 = getelementptr i8, ptr %hp1669, i64 24
  store ptr %ld1673, ptr %fp1674, align 8
  %$t657.addr = alloca ptr
  store ptr %hp1669, ptr %$t657.addr
  %ld1675 = load ptr, ptr %req.addr
  %ld1676 = load ptr, ptr %m.addr
  %ld1677 = load ptr, ptr %sc.addr
  %ld1678 = load ptr, ptr %h.addr
  %ld1679 = load ptr, ptr %p.addr
  %ld1680 = load ptr, ptr %pa.addr
  %ld1681 = load ptr, ptr %q.addr
  %ld1682 = load ptr, ptr %$t657.addr
  %ld1683 = load ptr, ptr %bd.addr
  %rc1684 = load i64, ptr %ld1675, align 8
  %uniq1685 = icmp eq i64 %rc1684, 1
  %fbip_slot1686 = alloca ptr
  br i1 %uniq1685, label %fbip_reuse351, label %fbip_fresh352
fbip_reuse351:
  %tgp1687 = getelementptr i8, ptr %ld1675, i64 8
  store i32 0, ptr %tgp1687, align 4
  %fp1688 = getelementptr i8, ptr %ld1675, i64 16
  store ptr %ld1676, ptr %fp1688, align 8
  %fp1689 = getelementptr i8, ptr %ld1675, i64 24
  store ptr %ld1677, ptr %fp1689, align 8
  %fp1690 = getelementptr i8, ptr %ld1675, i64 32
  store ptr %ld1678, ptr %fp1690, align 8
  %fp1691 = getelementptr i8, ptr %ld1675, i64 40
  store ptr %ld1679, ptr %fp1691, align 8
  %fp1692 = getelementptr i8, ptr %ld1675, i64 48
  store ptr %ld1680, ptr %fp1692, align 8
  %fp1693 = getelementptr i8, ptr %ld1675, i64 56
  store ptr %ld1681, ptr %fp1693, align 8
  %fp1694 = getelementptr i8, ptr %ld1675, i64 64
  store ptr %ld1682, ptr %fp1694, align 8
  %fp1695 = getelementptr i8, ptr %ld1675, i64 72
  store ptr %ld1683, ptr %fp1695, align 8
  store ptr %ld1675, ptr %fbip_slot1686
  br label %fbip_merge353
fbip_fresh352:
  call void @march_decrc(ptr %ld1675)
  %hp1696 = call ptr @march_alloc(i64 80)
  %tgp1697 = getelementptr i8, ptr %hp1696, i64 8
  store i32 0, ptr %tgp1697, align 4
  %fp1698 = getelementptr i8, ptr %hp1696, i64 16
  store ptr %ld1676, ptr %fp1698, align 8
  %fp1699 = getelementptr i8, ptr %hp1696, i64 24
  store ptr %ld1677, ptr %fp1699, align 8
  %fp1700 = getelementptr i8, ptr %hp1696, i64 32
  store ptr %ld1678, ptr %fp1700, align 8
  %fp1701 = getelementptr i8, ptr %hp1696, i64 40
  store ptr %ld1679, ptr %fp1701, align 8
  %fp1702 = getelementptr i8, ptr %hp1696, i64 48
  store ptr %ld1680, ptr %fp1702, align 8
  %fp1703 = getelementptr i8, ptr %hp1696, i64 56
  store ptr %ld1681, ptr %fp1703, align 8
  %fp1704 = getelementptr i8, ptr %hp1696, i64 64
  store ptr %ld1682, ptr %fp1704, align 8
  %fp1705 = getelementptr i8, ptr %hp1696, i64 72
  store ptr %ld1683, ptr %fp1705, align 8
  store ptr %hp1696, ptr %fbip_slot1686
  br label %fbip_merge353
fbip_merge353:
  %fbip_r1706 = load ptr, ptr %fbip_slot1686
  store ptr %fbip_r1706, ptr %res_slot1636
  br label %case_merge348
case_default349:
  unreachable
case_merge348:
  %case_r1707 = load ptr, ptr %res_slot1636
  ret ptr %case_r1707
}

define ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %steps.arg, ptr %req.arg, ptr %err.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %err.addr = alloca ptr
  store ptr %err.arg, ptr %err.addr
  %ld1708 = load ptr, ptr %steps.addr
  %res_slot1709 = alloca ptr
  %tgp1710 = getelementptr i8, ptr %ld1708, i64 8
  %tag1711 = load i32, ptr %tgp1710, align 4
  switch i32 %tag1711, label %case_default355 [
      i32 0, label %case_br356
      i32 1, label %case_br357
  ]
case_br356:
  %ld1712 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1712)
  %hp1713 = call ptr @march_alloc(i64 24)
  %tgp1714 = getelementptr i8, ptr %hp1713, i64 8
  store i32 1, ptr %tgp1714, align 4
  %ld1715 = load ptr, ptr %err.addr
  %fp1716 = getelementptr i8, ptr %hp1713, i64 16
  store ptr %ld1715, ptr %fp1716, align 8
  store ptr %hp1713, ptr %res_slot1709
  br label %case_merge354
case_br357:
  %fp1717 = getelementptr i8, ptr %ld1708, i64 16
  %fv1718 = load ptr, ptr %fp1717, align 8
  %$f974.addr = alloca ptr
  store ptr %fv1718, ptr %$f974.addr
  %fp1719 = getelementptr i8, ptr %ld1708, i64 24
  %fv1720 = load ptr, ptr %fp1719, align 8
  %$f975.addr = alloca ptr
  store ptr %fv1720, ptr %$f975.addr
  %freed1721 = call i64 @march_decrc_freed(ptr %ld1708)
  %freed_b1722 = icmp ne i64 %freed1721, 0
  br i1 %freed_b1722, label %br_unique358, label %br_shared359
br_shared359:
  call void @march_incrc(ptr %fv1720)
  call void @march_incrc(ptr %fv1718)
  br label %br_body360
br_unique358:
  br label %br_body360
br_body360:
  %ld1723 = load ptr, ptr %$f974.addr
  %res_slot1724 = alloca ptr
  %tgp1725 = getelementptr i8, ptr %ld1723, i64 8
  %tag1726 = load i32, ptr %tgp1725, align 4
  switch i32 %tag1726, label %case_default362 [
      i32 0, label %case_br363
  ]
case_br363:
  %fp1727 = getelementptr i8, ptr %ld1723, i64 16
  %fv1728 = load ptr, ptr %fp1727, align 8
  %$f976.addr = alloca ptr
  store ptr %fv1728, ptr %$f976.addr
  %fp1729 = getelementptr i8, ptr %ld1723, i64 24
  %fv1730 = load ptr, ptr %fp1729, align 8
  %$f977.addr = alloca ptr
  store ptr %fv1730, ptr %$f977.addr
  %freed1731 = call i64 @march_decrc_freed(ptr %ld1723)
  %freed_b1732 = icmp ne i64 %freed1731, 0
  br i1 %freed_b1732, label %br_unique364, label %br_shared365
br_shared365:
  call void @march_incrc(ptr %fv1730)
  call void @march_incrc(ptr %fv1728)
  br label %br_body366
br_unique364:
  br label %br_body366
br_body366:
  %ld1733 = load ptr, ptr %$f975.addr
  %rest.addr = alloca ptr
  store ptr %ld1733, ptr %rest.addr
  %ld1734 = load ptr, ptr %$f977.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1734, ptr %step_fn.addr
  %ld1735 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld1735)
  %ld1736 = load ptr, ptr %step_fn.addr
  %fp1737 = getelementptr i8, ptr %ld1736, i64 16
  %fv1738 = load ptr, ptr %fp1737, align 8
  %ld1739 = load ptr, ptr %req.addr
  %ld1740 = load ptr, ptr %err.addr
  %cr1741 = call ptr (ptr, ptr, ptr) %fv1738(ptr %ld1736, ptr %ld1739, ptr %ld1740)
  %$t971.addr = alloca ptr
  store ptr %cr1741, ptr %$t971.addr
  %ld1742 = load ptr, ptr %$t971.addr
  %res_slot1743 = alloca ptr
  %tgp1744 = getelementptr i8, ptr %ld1742, i64 8
  %tag1745 = load i32, ptr %tgp1744, align 4
  switch i32 %tag1745, label %case_default368 [
      i32 0, label %case_br369
      i32 1, label %case_br370
  ]
case_br369:
  %fp1746 = getelementptr i8, ptr %ld1742, i64 16
  %fv1747 = load ptr, ptr %fp1746, align 8
  %$f972.addr = alloca ptr
  store ptr %fv1747, ptr %$f972.addr
  %freed1748 = call i64 @march_decrc_freed(ptr %ld1742)
  %freed_b1749 = icmp ne i64 %freed1748, 0
  br i1 %freed_b1749, label %br_unique371, label %br_shared372
br_shared372:
  call void @march_incrc(ptr %fv1747)
  br label %br_body373
br_unique371:
  br label %br_body373
br_body373:
  %ld1750 = load ptr, ptr %$f972.addr
  %resp.addr = alloca ptr
  store ptr %ld1750, ptr %resp.addr
  %hp1751 = call ptr @march_alloc(i64 24)
  %tgp1752 = getelementptr i8, ptr %hp1751, i64 8
  store i32 0, ptr %tgp1752, align 4
  %ld1753 = load ptr, ptr %resp.addr
  %fp1754 = getelementptr i8, ptr %hp1751, i64 16
  store ptr %ld1753, ptr %fp1754, align 8
  store ptr %hp1751, ptr %res_slot1743
  br label %case_merge367
case_br370:
  %fp1755 = getelementptr i8, ptr %ld1742, i64 16
  %fv1756 = load ptr, ptr %fp1755, align 8
  %$f973.addr = alloca ptr
  store ptr %fv1756, ptr %$f973.addr
  %freed1757 = call i64 @march_decrc_freed(ptr %ld1742)
  %freed_b1758 = icmp ne i64 %freed1757, 0
  br i1 %freed_b1758, label %br_unique374, label %br_shared375
br_shared375:
  call void @march_incrc(ptr %fv1756)
  br label %br_body376
br_unique374:
  br label %br_body376
br_body376:
  %ld1759 = load ptr, ptr %$f973.addr
  %new_err.addr = alloca ptr
  store ptr %ld1759, ptr %new_err.addr
  %ld1760 = load ptr, ptr %rest.addr
  %ld1761 = load ptr, ptr %req.addr
  %ld1762 = load ptr, ptr %new_err.addr
  %cr1763 = call ptr @HttpClient.run_error_steps$List_ErrorStepEntry$Request_String$HttpError(ptr %ld1760, ptr %ld1761, ptr %ld1762)
  store ptr %cr1763, ptr %res_slot1743
  br label %case_merge367
case_default368:
  unreachable
case_merge367:
  %case_r1764 = load ptr, ptr %res_slot1743
  store ptr %case_r1764, ptr %res_slot1724
  br label %case_merge361
case_default362:
  unreachable
case_merge361:
  %case_r1765 = load ptr, ptr %res_slot1724
  store ptr %case_r1765, ptr %res_slot1709
  br label %case_merge354
case_default355:
  unreachable
case_merge354:
  %case_r1766 = load ptr, ptr %res_slot1709
  ret ptr %case_r1766
}

define ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3459(ptr %steps.arg, ptr %req.arg, ptr %resp.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld1767 = load ptr, ptr %steps.addr
  %res_slot1768 = alloca ptr
  %tgp1769 = getelementptr i8, ptr %ld1767, i64 8
  %tag1770 = load i32, ptr %tgp1769, align 4
  switch i32 %tag1770, label %case_default378 [
      i32 0, label %case_br379
      i32 1, label %case_br380
  ]
case_br379:
  %ld1771 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld1771)
  %hp1772 = call ptr @march_alloc(i64 32)
  %tgp1773 = getelementptr i8, ptr %hp1772, i64 8
  store i32 0, ptr %tgp1773, align 4
  %ld1774 = load ptr, ptr %req.addr
  %fp1775 = getelementptr i8, ptr %hp1772, i64 16
  store ptr %ld1774, ptr %fp1775, align 8
  %ld1776 = load ptr, ptr %resp.addr
  %fp1777 = getelementptr i8, ptr %hp1772, i64 24
  store ptr %ld1776, ptr %fp1777, align 8
  %$t961.addr = alloca ptr
  store ptr %hp1772, ptr %$t961.addr
  %hp1778 = call ptr @march_alloc(i64 24)
  %tgp1779 = getelementptr i8, ptr %hp1778, i64 8
  store i32 0, ptr %tgp1779, align 4
  %ld1780 = load ptr, ptr %$t961.addr
  %fp1781 = getelementptr i8, ptr %hp1778, i64 16
  store ptr %ld1780, ptr %fp1781, align 8
  store ptr %hp1778, ptr %res_slot1768
  br label %case_merge377
case_br380:
  %fp1782 = getelementptr i8, ptr %ld1767, i64 16
  %fv1783 = load ptr, ptr %fp1782, align 8
  %$f967.addr = alloca ptr
  store ptr %fv1783, ptr %$f967.addr
  %fp1784 = getelementptr i8, ptr %ld1767, i64 24
  %fv1785 = load ptr, ptr %fp1784, align 8
  %$f968.addr = alloca ptr
  store ptr %fv1785, ptr %$f968.addr
  %freed1786 = call i64 @march_decrc_freed(ptr %ld1767)
  %freed_b1787 = icmp ne i64 %freed1786, 0
  br i1 %freed_b1787, label %br_unique381, label %br_shared382
br_shared382:
  call void @march_incrc(ptr %fv1785)
  call void @march_incrc(ptr %fv1783)
  br label %br_body383
br_unique381:
  br label %br_body383
br_body383:
  %ld1788 = load ptr, ptr %$f967.addr
  %res_slot1789 = alloca ptr
  %tgp1790 = getelementptr i8, ptr %ld1788, i64 8
  %tag1791 = load i32, ptr %tgp1790, align 4
  switch i32 %tag1791, label %case_default385 [
      i32 0, label %case_br386
  ]
case_br386:
  %fp1792 = getelementptr i8, ptr %ld1788, i64 16
  %fv1793 = load ptr, ptr %fp1792, align 8
  %$f969.addr = alloca ptr
  store ptr %fv1793, ptr %$f969.addr
  %fp1794 = getelementptr i8, ptr %ld1788, i64 24
  %fv1795 = load ptr, ptr %fp1794, align 8
  %$f970.addr = alloca ptr
  store ptr %fv1795, ptr %$f970.addr
  %freed1796 = call i64 @march_decrc_freed(ptr %ld1788)
  %freed_b1797 = icmp ne i64 %freed1796, 0
  br i1 %freed_b1797, label %br_unique387, label %br_shared388
br_shared388:
  call void @march_incrc(ptr %fv1795)
  call void @march_incrc(ptr %fv1793)
  br label %br_body389
br_unique387:
  br label %br_body389
br_body389:
  %ld1798 = load ptr, ptr %$f968.addr
  %rest.addr = alloca ptr
  store ptr %ld1798, ptr %rest.addr
  %ld1799 = load ptr, ptr %$f970.addr
  %step_fn.addr = alloca ptr
  store ptr %ld1799, ptr %step_fn.addr
  %ld1800 = load ptr, ptr %step_fn.addr
  %fp1801 = getelementptr i8, ptr %ld1800, i64 16
  %fv1802 = load ptr, ptr %fp1801, align 8
  %ld1803 = load ptr, ptr %req.addr
  %ld1804 = load ptr, ptr %resp.addr
  %cr1805 = call ptr (ptr, ptr, ptr) %fv1802(ptr %ld1800, ptr %ld1803, ptr %ld1804)
  %$t962.addr = alloca ptr
  store ptr %cr1805, ptr %$t962.addr
  %ld1806 = load ptr, ptr %$t962.addr
  %res_slot1807 = alloca ptr
  %tgp1808 = getelementptr i8, ptr %ld1806, i64 8
  %tag1809 = load i32, ptr %tgp1808, align 4
  switch i32 %tag1809, label %case_default391 [
      i32 1, label %case_br392
      i32 0, label %case_br393
  ]
case_br392:
  %fp1810 = getelementptr i8, ptr %ld1806, i64 16
  %fv1811 = load ptr, ptr %fp1810, align 8
  %$f963.addr = alloca ptr
  store ptr %fv1811, ptr %$f963.addr
  %ld1812 = load ptr, ptr %$f963.addr
  %e.addr = alloca ptr
  store ptr %ld1812, ptr %e.addr
  %ld1813 = load ptr, ptr %$t962.addr
  %ld1814 = load ptr, ptr %e.addr
  %rc1815 = load i64, ptr %ld1813, align 8
  %uniq1816 = icmp eq i64 %rc1815, 1
  %fbip_slot1817 = alloca ptr
  br i1 %uniq1816, label %fbip_reuse394, label %fbip_fresh395
fbip_reuse394:
  %tgp1818 = getelementptr i8, ptr %ld1813, i64 8
  store i32 1, ptr %tgp1818, align 4
  %fp1819 = getelementptr i8, ptr %ld1813, i64 16
  store ptr %ld1814, ptr %fp1819, align 8
  store ptr %ld1813, ptr %fbip_slot1817
  br label %fbip_merge396
fbip_fresh395:
  call void @march_decrc(ptr %ld1813)
  %hp1820 = call ptr @march_alloc(i64 24)
  %tgp1821 = getelementptr i8, ptr %hp1820, i64 8
  store i32 1, ptr %tgp1821, align 4
  %fp1822 = getelementptr i8, ptr %hp1820, i64 16
  store ptr %ld1814, ptr %fp1822, align 8
  store ptr %hp1820, ptr %fbip_slot1817
  br label %fbip_merge396
fbip_merge396:
  %fbip_r1823 = load ptr, ptr %fbip_slot1817
  store ptr %fbip_r1823, ptr %res_slot1807
  br label %case_merge390
case_br393:
  %fp1824 = getelementptr i8, ptr %ld1806, i64 16
  %fv1825 = load ptr, ptr %fp1824, align 8
  %$f964.addr = alloca ptr
  store ptr %fv1825, ptr %$f964.addr
  %freed1826 = call i64 @march_decrc_freed(ptr %ld1806)
  %freed_b1827 = icmp ne i64 %freed1826, 0
  br i1 %freed_b1827, label %br_unique397, label %br_shared398
br_shared398:
  call void @march_incrc(ptr %fv1825)
  br label %br_body399
br_unique397:
  br label %br_body399
br_body399:
  %ld1828 = load ptr, ptr %$f964.addr
  %res_slot1829 = alloca ptr
  %tgp1830 = getelementptr i8, ptr %ld1828, i64 8
  %tag1831 = load i32, ptr %tgp1830, align 4
  switch i32 %tag1831, label %case_default401 [
      i32 0, label %case_br402
  ]
case_br402:
  %fp1832 = getelementptr i8, ptr %ld1828, i64 16
  %fv1833 = load ptr, ptr %fp1832, align 8
  %$f965.addr = alloca ptr
  store ptr %fv1833, ptr %$f965.addr
  %fp1834 = getelementptr i8, ptr %ld1828, i64 24
  %fv1835 = load ptr, ptr %fp1834, align 8
  %$f966.addr = alloca ptr
  store ptr %fv1835, ptr %$f966.addr
  %freed1836 = call i64 @march_decrc_freed(ptr %ld1828)
  %freed_b1837 = icmp ne i64 %freed1836, 0
  br i1 %freed_b1837, label %br_unique403, label %br_shared404
br_shared404:
  call void @march_incrc(ptr %fv1835)
  call void @march_incrc(ptr %fv1833)
  br label %br_body405
br_unique403:
  br label %br_body405
br_body405:
  %ld1838 = load ptr, ptr %$f966.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1838, ptr %new_resp.addr
  %ld1839 = load ptr, ptr %$f965.addr
  %new_req.addr = alloca ptr
  store ptr %ld1839, ptr %new_req.addr
  %ld1840 = load ptr, ptr %rest.addr
  %ld1841 = load ptr, ptr %new_req.addr
  %ld1842 = load ptr, ptr %new_resp.addr
  %cr1843 = call ptr @HttpClient.run_response_steps$List_ResponseStepEntry$Request_String$Response_V__3459(ptr %ld1840, ptr %ld1841, ptr %ld1842)
  store ptr %cr1843, ptr %res_slot1829
  br label %case_merge400
case_default401:
  unreachable
case_merge400:
  %case_r1844 = load ptr, ptr %res_slot1829
  store ptr %case_r1844, ptr %res_slot1807
  br label %case_merge390
case_default391:
  unreachable
case_merge390:
  %case_r1845 = load ptr, ptr %res_slot1807
  store ptr %case_r1845, ptr %res_slot1789
  br label %case_merge384
case_default385:
  unreachable
case_merge384:
  %case_r1846 = load ptr, ptr %res_slot1789
  store ptr %case_r1846, ptr %res_slot1768
  br label %case_merge377
case_default378:
  unreachable
case_merge377:
  %case_r1847 = load ptr, ptr %res_slot1768
  ret ptr %case_r1847
}

define ptr @HttpClient.handle_redirects$Request_String$Response_V__3459$Int$Int(ptr %req.arg, ptr %resp.arg, i64 %max.arg, i64 %count.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %max.addr = alloca i64
  store i64 %max.arg, ptr %max.addr
  %count.addr = alloca i64
  store i64 %count.arg, ptr %count.addr
  %ld1848 = load i64, ptr %max.addr
  %cmp1849 = icmp eq i64 %ld1848, 0
  %ar1850 = zext i1 %cmp1849 to i64
  %$t994.addr = alloca i64
  store i64 %ar1850, ptr %$t994.addr
  %ld1851 = load i64, ptr %$t994.addr
  %res_slot1852 = alloca ptr
  %bi1853 = trunc i64 %ld1851 to i1
  br i1 %bi1853, label %case_br408, label %case_default407
case_br408:
  %hp1854 = call ptr @march_alloc(i64 24)
  %tgp1855 = getelementptr i8, ptr %hp1854, i64 8
  store i32 0, ptr %tgp1855, align 4
  %ld1856 = load ptr, ptr %resp.addr
  %fp1857 = getelementptr i8, ptr %hp1854, i64 16
  store ptr %ld1856, ptr %fp1857, align 8
  store ptr %hp1854, ptr %res_slot1852
  br label %case_merge406
case_default407:
  %ld1858 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1858)
  %ld1859 = load ptr, ptr %resp.addr
  %cr1860 = call i64 @Http.response_is_redirect$Response_V__3459(ptr %ld1859)
  %$t995.addr = alloca i64
  store i64 %cr1860, ptr %$t995.addr
  %ld1861 = load i64, ptr %$t995.addr
  %ar1862 = xor i64 %ld1861, 1
  %$t996.addr = alloca i64
  store i64 %ar1862, ptr %$t996.addr
  %ld1863 = load i64, ptr %$t996.addr
  %res_slot1864 = alloca ptr
  %bi1865 = trunc i64 %ld1863 to i1
  br i1 %bi1865, label %case_br411, label %case_default410
case_br411:
  %hp1866 = call ptr @march_alloc(i64 24)
  %tgp1867 = getelementptr i8, ptr %hp1866, i64 8
  store i32 0, ptr %tgp1867, align 4
  %ld1868 = load ptr, ptr %resp.addr
  %fp1869 = getelementptr i8, ptr %hp1866, i64 16
  store ptr %ld1868, ptr %fp1869, align 8
  store ptr %hp1866, ptr %res_slot1864
  br label %case_merge409
case_default410:
  %ld1870 = load i64, ptr %count.addr
  %ld1871 = load i64, ptr %max.addr
  %cmp1872 = icmp sge i64 %ld1870, %ld1871
  %ar1873 = zext i1 %cmp1872 to i64
  %$t997.addr = alloca i64
  store i64 %ar1873, ptr %$t997.addr
  %ld1874 = load i64, ptr %$t997.addr
  %res_slot1875 = alloca ptr
  %bi1876 = trunc i64 %ld1874 to i1
  br i1 %bi1876, label %case_br414, label %case_default413
case_br414:
  %hp1877 = call ptr @march_alloc(i64 24)
  %tgp1878 = getelementptr i8, ptr %hp1877, i64 8
  store i32 2, ptr %tgp1878, align 4
  %ld1879 = load i64, ptr %count.addr
  %fp1880 = getelementptr i8, ptr %hp1877, i64 16
  store i64 %ld1879, ptr %fp1880, align 8
  %$t998.addr = alloca ptr
  store ptr %hp1877, ptr %$t998.addr
  %hp1881 = call ptr @march_alloc(i64 24)
  %tgp1882 = getelementptr i8, ptr %hp1881, i64 8
  store i32 1, ptr %tgp1882, align 4
  %ld1883 = load ptr, ptr %$t998.addr
  %fp1884 = getelementptr i8, ptr %hp1881, i64 16
  store ptr %ld1883, ptr %fp1884, align 8
  store ptr %hp1881, ptr %res_slot1875
  br label %case_merge412
case_default413:
  %ld1885 = load ptr, ptr %resp.addr
  call void @march_incrc(ptr %ld1885)
  %ld1886 = load ptr, ptr %resp.addr
  %sl1887 = call ptr @march_string_lit(ptr @.str62, i64 8)
  %cr1888 = call ptr @Http.get_header$Response_V__3459$String(ptr %ld1886, ptr %sl1887)
  %$t999.addr = alloca ptr
  store ptr %cr1888, ptr %$t999.addr
  %ld1889 = load ptr, ptr %$t999.addr
  %res_slot1890 = alloca ptr
  %tgp1891 = getelementptr i8, ptr %ld1889, i64 8
  %tag1892 = load i32, ptr %tgp1891, align 4
  switch i32 %tag1892, label %case_default416 [
      i32 0, label %case_br417
      i32 1, label %case_br418
  ]
case_br417:
  %ld1893 = load ptr, ptr %$t999.addr
  call void @march_decrc(ptr %ld1893)
  %hp1894 = call ptr @march_alloc(i64 24)
  %tgp1895 = getelementptr i8, ptr %hp1894, i64 8
  store i32 0, ptr %tgp1895, align 4
  %ld1896 = load ptr, ptr %resp.addr
  %fp1897 = getelementptr i8, ptr %hp1894, i64 16
  store ptr %ld1896, ptr %fp1897, align 8
  store ptr %hp1894, ptr %res_slot1890
  br label %case_merge415
case_br418:
  %fp1898 = getelementptr i8, ptr %ld1889, i64 16
  %fv1899 = load ptr, ptr %fp1898, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv1899, ptr %$f1018.addr
  %freed1900 = call i64 @march_decrc_freed(ptr %ld1889)
  %freed_b1901 = icmp ne i64 %freed1900, 0
  br i1 %freed_b1901, label %br_unique419, label %br_shared420
br_shared420:
  call void @march_incrc(ptr %fv1899)
  br label %br_body421
br_unique419:
  br label %br_body421
br_body421:
  %ld1902 = load ptr, ptr %$f1018.addr
  %location.addr = alloca ptr
  store ptr %ld1902, ptr %location.addr
  %ld1903 = load ptr, ptr %location.addr
  call void @march_incrc(ptr %ld1903)
  %ld1904 = load ptr, ptr %location.addr
  %cr1905 = call ptr @Http.parse_url(ptr %ld1904)
  %$t1000.addr = alloca ptr
  store ptr %cr1905, ptr %$t1000.addr
  %ld1906 = load ptr, ptr %$t1000.addr
  %res_slot1907 = alloca ptr
  %tgp1908 = getelementptr i8, ptr %ld1906, i64 8
  %tag1909 = load i32, ptr %tgp1908, align 4
  switch i32 %tag1909, label %case_default423 [
      i32 0, label %case_br424
      i32 1, label %case_br425
  ]
case_br424:
  %fp1910 = getelementptr i8, ptr %ld1906, i64 16
  %fv1911 = load ptr, ptr %fp1910, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv1911, ptr %$f1011.addr
  %freed1912 = call i64 @march_decrc_freed(ptr %ld1906)
  %freed_b1913 = icmp ne i64 %freed1912, 0
  br i1 %freed_b1913, label %br_unique426, label %br_shared427
br_shared427:
  call void @march_incrc(ptr %fv1911)
  br label %br_body428
br_unique426:
  br label %br_body428
br_body428:
  %ld1914 = load ptr, ptr %$f1011.addr
  %parsed.addr = alloca ptr
  store ptr %ld1914, ptr %parsed.addr
  %hp1915 = call ptr @march_alloc(i64 16)
  %tgp1916 = getelementptr i8, ptr %hp1915, i64 8
  store i32 0, ptr %tgp1916, align 4
  %$t1001.addr = alloca ptr
  store ptr %hp1915, ptr %$t1001.addr
  %ld1917 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1917)
  %ld1918 = load ptr, ptr %parsed.addr
  %cr1919 = call ptr @Http.scheme$Request_T_(ptr %ld1918)
  %$t1002.addr = alloca ptr
  store ptr %cr1919, ptr %$t1002.addr
  %ld1920 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1920)
  %ld1921 = load ptr, ptr %parsed.addr
  %cr1922 = call ptr @Http.host$Request_T_(ptr %ld1921)
  %$t1003.addr = alloca ptr
  store ptr %cr1922, ptr %$t1003.addr
  %ld1923 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1923)
  %ld1924 = load ptr, ptr %parsed.addr
  %cr1925 = call ptr @Http.port$Request_T_(ptr %ld1924)
  %$t1004.addr = alloca ptr
  store ptr %cr1925, ptr %$t1004.addr
  %ld1926 = load ptr, ptr %parsed.addr
  call void @march_incrc(ptr %ld1926)
  %ld1927 = load ptr, ptr %parsed.addr
  %cr1928 = call ptr @Http.path$Request_T_(ptr %ld1927)
  %$t1005.addr = alloca ptr
  store ptr %cr1928, ptr %$t1005.addr
  %ld1929 = load ptr, ptr %parsed.addr
  %cr1930 = call ptr @Http.query$Request_T_(ptr %ld1929)
  %$t1006.addr = alloca ptr
  store ptr %cr1930, ptr %$t1006.addr
  %ld1931 = load ptr, ptr %req.addr
  %cr1932 = call ptr @Http.headers$Request_String(ptr %ld1931)
  %$t1007.addr = alloca ptr
  store ptr %cr1932, ptr %$t1007.addr
  %hp1933 = call ptr @march_alloc(i64 80)
  %tgp1934 = getelementptr i8, ptr %hp1933, i64 8
  store i32 0, ptr %tgp1934, align 4
  %ld1935 = load ptr, ptr %$t1001.addr
  %fp1936 = getelementptr i8, ptr %hp1933, i64 16
  store ptr %ld1935, ptr %fp1936, align 8
  %ld1937 = load ptr, ptr %$t1002.addr
  %fp1938 = getelementptr i8, ptr %hp1933, i64 24
  store ptr %ld1937, ptr %fp1938, align 8
  %ld1939 = load ptr, ptr %$t1003.addr
  %fp1940 = getelementptr i8, ptr %hp1933, i64 32
  store ptr %ld1939, ptr %fp1940, align 8
  %ld1941 = load ptr, ptr %$t1004.addr
  %fp1942 = getelementptr i8, ptr %hp1933, i64 40
  store ptr %ld1941, ptr %fp1942, align 8
  %ld1943 = load ptr, ptr %$t1005.addr
  %fp1944 = getelementptr i8, ptr %hp1933, i64 48
  store ptr %ld1943, ptr %fp1944, align 8
  %ld1945 = load ptr, ptr %$t1006.addr
  %fp1946 = getelementptr i8, ptr %hp1933, i64 56
  store ptr %ld1945, ptr %fp1946, align 8
  %ld1947 = load ptr, ptr %$t1007.addr
  %fp1948 = getelementptr i8, ptr %hp1933, i64 64
  store ptr %ld1947, ptr %fp1948, align 8
  %sl1949 = call ptr @march_string_lit(ptr @.str63, i64 0)
  %fp1950 = getelementptr i8, ptr %hp1933, i64 72
  store ptr %sl1949, ptr %fp1950, align 8
  store ptr %hp1933, ptr %res_slot1907
  br label %case_merge422
case_br425:
  %fp1951 = getelementptr i8, ptr %ld1906, i64 16
  %fv1952 = load ptr, ptr %fp1951, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv1952, ptr %$f1012.addr
  %freed1953 = call i64 @march_decrc_freed(ptr %ld1906)
  %freed_b1954 = icmp ne i64 %freed1953, 0
  br i1 %freed_b1954, label %br_unique429, label %br_shared430
br_shared430:
  call void @march_incrc(ptr %fv1952)
  br label %br_body431
br_unique429:
  br label %br_body431
br_body431:
  %ld1955 = load ptr, ptr %req.addr
  %ld1956 = load ptr, ptr %location.addr
  %cr1957 = call ptr @Http.set_path$Request_String$String(ptr %ld1955, ptr %ld1956)
  %$t1008.addr = alloca ptr
  store ptr %cr1957, ptr %$t1008.addr
  %hp1958 = call ptr @march_alloc(i64 16)
  %tgp1959 = getelementptr i8, ptr %hp1958, i64 8
  store i32 0, ptr %tgp1959, align 4
  %$t1009.addr = alloca ptr
  store ptr %hp1958, ptr %$t1009.addr
  %ld1960 = load ptr, ptr %$t1008.addr
  %ld1961 = load ptr, ptr %$t1009.addr
  %cr1962 = call ptr @Http.set_method$Request_String$Method(ptr %ld1960, ptr %ld1961)
  %$t1010.addr = alloca ptr
  store ptr %cr1962, ptr %$t1010.addr
  %ld1963 = load ptr, ptr %$t1010.addr
  %sl1964 = call ptr @march_string_lit(ptr @.str64, i64 0)
  %cr1965 = call ptr @Http.set_body$Request_String$String(ptr %ld1963, ptr %sl1964)
  store ptr %cr1965, ptr %res_slot1907
  br label %case_merge422
case_default423:
  unreachable
case_merge422:
  %case_r1966 = load ptr, ptr %res_slot1907
  %redirect_req.addr = alloca ptr
  store ptr %case_r1966, ptr %redirect_req.addr
  %ld1967 = load ptr, ptr %redirect_req.addr
  call void @march_incrc(ptr %ld1967)
  %ld1968 = load ptr, ptr %redirect_req.addr
  %cr1969 = call ptr @HttpTransport.request$Request_String(ptr %ld1968)
  %$t1013.addr = alloca ptr
  store ptr %cr1969, ptr %$t1013.addr
  %ld1970 = load ptr, ptr %$t1013.addr
  %res_slot1971 = alloca ptr
  %tgp1972 = getelementptr i8, ptr %ld1970, i64 8
  %tag1973 = load i32, ptr %tgp1972, align 4
  switch i32 %tag1973, label %case_default433 [
      i32 1, label %case_br434
      i32 0, label %case_br435
  ]
case_br434:
  %fp1974 = getelementptr i8, ptr %ld1970, i64 16
  %fv1975 = load ptr, ptr %fp1974, align 8
  %$f1016.addr = alloca ptr
  store ptr %fv1975, ptr %$f1016.addr
  %ld1976 = load ptr, ptr %$f1016.addr
  %e.addr = alloca ptr
  store ptr %ld1976, ptr %e.addr
  %hp1977 = call ptr @march_alloc(i64 24)
  %tgp1978 = getelementptr i8, ptr %hp1977, i64 8
  store i32 0, ptr %tgp1978, align 4
  %ld1979 = load ptr, ptr %e.addr
  %fp1980 = getelementptr i8, ptr %hp1977, i64 16
  store ptr %ld1979, ptr %fp1980, align 8
  %$t1014.addr = alloca ptr
  store ptr %hp1977, ptr %$t1014.addr
  %ld1981 = load ptr, ptr %$t1013.addr
  %ld1982 = load ptr, ptr %$t1014.addr
  %rc1983 = load i64, ptr %ld1981, align 8
  %uniq1984 = icmp eq i64 %rc1983, 1
  %fbip_slot1985 = alloca ptr
  br i1 %uniq1984, label %fbip_reuse436, label %fbip_fresh437
fbip_reuse436:
  %tgp1986 = getelementptr i8, ptr %ld1981, i64 8
  store i32 1, ptr %tgp1986, align 4
  %fp1987 = getelementptr i8, ptr %ld1981, i64 16
  store ptr %ld1982, ptr %fp1987, align 8
  store ptr %ld1981, ptr %fbip_slot1985
  br label %fbip_merge438
fbip_fresh437:
  call void @march_decrc(ptr %ld1981)
  %hp1988 = call ptr @march_alloc(i64 24)
  %tgp1989 = getelementptr i8, ptr %hp1988, i64 8
  store i32 1, ptr %tgp1989, align 4
  %fp1990 = getelementptr i8, ptr %hp1988, i64 16
  store ptr %ld1982, ptr %fp1990, align 8
  store ptr %hp1988, ptr %fbip_slot1985
  br label %fbip_merge438
fbip_merge438:
  %fbip_r1991 = load ptr, ptr %fbip_slot1985
  store ptr %fbip_r1991, ptr %res_slot1971
  br label %case_merge432
case_br435:
  %fp1992 = getelementptr i8, ptr %ld1970, i64 16
  %fv1993 = load ptr, ptr %fp1992, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv1993, ptr %$f1017.addr
  %freed1994 = call i64 @march_decrc_freed(ptr %ld1970)
  %freed_b1995 = icmp ne i64 %freed1994, 0
  br i1 %freed_b1995, label %br_unique439, label %br_shared440
br_shared440:
  call void @march_incrc(ptr %fv1993)
  br label %br_body441
br_unique439:
  br label %br_body441
br_body441:
  %ld1996 = load ptr, ptr %$f1017.addr
  %new_resp.addr = alloca ptr
  store ptr %ld1996, ptr %new_resp.addr
  %ld1997 = load i64, ptr %count.addr
  %ar1998 = add i64 %ld1997, 1
  %$t1015.addr = alloca i64
  store i64 %ar1998, ptr %$t1015.addr
  %ld1999 = load ptr, ptr %redirect_req.addr
  %ld2000 = load ptr, ptr %new_resp.addr
  %ld2001 = load i64, ptr %max.addr
  %ld2002 = load i64, ptr %$t1015.addr
  %cr2003 = call ptr @HttpClient.handle_redirects$Request_String$Response_V__3459$Int$Int(ptr %ld1999, ptr %ld2000, i64 %ld2001, i64 %ld2002)
  store ptr %cr2003, ptr %res_slot1971
  br label %case_merge432
case_default433:
  unreachable
case_merge432:
  %case_r2004 = load ptr, ptr %res_slot1971
  store ptr %case_r2004, ptr %res_slot1890
  br label %case_merge415
case_default416:
  unreachable
case_merge415:
  %case_r2005 = load ptr, ptr %res_slot1890
  store ptr %case_r2005, ptr %res_slot1875
  br label %case_merge412
case_merge412:
  %case_r2006 = load ptr, ptr %res_slot1875
  store ptr %case_r2006, ptr %res_slot1864
  br label %case_merge409
case_merge409:
  %case_r2007 = load ptr, ptr %res_slot1864
  store ptr %case_r2007, ptr %res_slot1852
  br label %case_merge406
case_merge406:
  %case_r2008 = load ptr, ptr %res_slot1852
  ret ptr %case_r2008
}

define ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %req.arg, i64 %retries_left.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %retries_left.addr = alloca i64
  store i64 %retries_left.arg, ptr %retries_left.addr
  %ld2009 = load ptr, ptr %req.addr
  call void @march_incrc(ptr %ld2009)
  %ld2010 = load ptr, ptr %req.addr
  %cr2011 = call ptr @HttpTransport.request$Request_String(ptr %ld2010)
  %$t978.addr = alloca ptr
  store ptr %cr2011, ptr %$t978.addr
  %ld2012 = load ptr, ptr %$t978.addr
  %res_slot2013 = alloca ptr
  %tgp2014 = getelementptr i8, ptr %ld2012, i64 8
  %tag2015 = load i32, ptr %tgp2014, align 4
  switch i32 %tag2015, label %case_default443 [
      i32 0, label %case_br444
      i32 1, label %case_br445
  ]
case_br444:
  %fp2016 = getelementptr i8, ptr %ld2012, i64 16
  %fv2017 = load ptr, ptr %fp2016, align 8
  %$f981.addr = alloca ptr
  store ptr %fv2017, ptr %$f981.addr
  %ld2018 = load ptr, ptr %$f981.addr
  %resp.addr = alloca ptr
  store ptr %ld2018, ptr %resp.addr
  %ld2019 = load ptr, ptr %$t978.addr
  %ld2020 = load ptr, ptr %resp.addr
  %rc2021 = load i64, ptr %ld2019, align 8
  %uniq2022 = icmp eq i64 %rc2021, 1
  %fbip_slot2023 = alloca ptr
  br i1 %uniq2022, label %fbip_reuse446, label %fbip_fresh447
fbip_reuse446:
  %tgp2024 = getelementptr i8, ptr %ld2019, i64 8
  store i32 0, ptr %tgp2024, align 4
  %fp2025 = getelementptr i8, ptr %ld2019, i64 16
  store ptr %ld2020, ptr %fp2025, align 8
  store ptr %ld2019, ptr %fbip_slot2023
  br label %fbip_merge448
fbip_fresh447:
  call void @march_decrc(ptr %ld2019)
  %hp2026 = call ptr @march_alloc(i64 24)
  %tgp2027 = getelementptr i8, ptr %hp2026, i64 8
  store i32 0, ptr %tgp2027, align 4
  %fp2028 = getelementptr i8, ptr %hp2026, i64 16
  store ptr %ld2020, ptr %fp2028, align 8
  store ptr %hp2026, ptr %fbip_slot2023
  br label %fbip_merge448
fbip_merge448:
  %fbip_r2029 = load ptr, ptr %fbip_slot2023
  store ptr %fbip_r2029, ptr %res_slot2013
  br label %case_merge442
case_br445:
  %fp2030 = getelementptr i8, ptr %ld2012, i64 16
  %fv2031 = load ptr, ptr %fp2030, align 8
  %$f982.addr = alloca ptr
  store ptr %fv2031, ptr %$f982.addr
  %freed2032 = call i64 @march_decrc_freed(ptr %ld2012)
  %freed_b2033 = icmp ne i64 %freed2032, 0
  br i1 %freed_b2033, label %br_unique449, label %br_shared450
br_shared450:
  call void @march_incrc(ptr %fv2031)
  br label %br_body451
br_unique449:
  br label %br_body451
br_body451:
  %ld2034 = load ptr, ptr %$f982.addr
  %e.addr = alloca ptr
  store ptr %ld2034, ptr %e.addr
  %ld2035 = load i64, ptr %retries_left.addr
  %cmp2036 = icmp sgt i64 %ld2035, 0
  %ar2037 = zext i1 %cmp2036 to i64
  %$t979.addr = alloca i64
  store i64 %ar2037, ptr %$t979.addr
  %ld2038 = load i64, ptr %$t979.addr
  %res_slot2039 = alloca ptr
  %bi2040 = trunc i64 %ld2038 to i1
  br i1 %bi2040, label %case_br454, label %case_default453
case_br454:
  %ld2041 = load i64, ptr %retries_left.addr
  %ar2042 = sub i64 %ld2041, 1
  %$t980.addr = alloca i64
  store i64 %ar2042, ptr %$t980.addr
  %ld2043 = load ptr, ptr %req.addr
  %ld2044 = load i64, ptr %$t980.addr
  %cr2045 = call ptr @HttpClient.transport_with_retry$Request_String$Int(ptr %ld2043, i64 %ld2044)
  store ptr %cr2045, ptr %res_slot2039
  br label %case_merge452
case_default453:
  %hp2046 = call ptr @march_alloc(i64 24)
  %tgp2047 = getelementptr i8, ptr %hp2046, i64 8
  store i32 1, ptr %tgp2047, align 4
  %ld2048 = load ptr, ptr %e.addr
  %fp2049 = getelementptr i8, ptr %hp2046, i64 16
  store ptr %ld2048, ptr %fp2049, align 8
  store ptr %hp2046, ptr %res_slot2039
  br label %case_merge452
case_merge452:
  %case_r2050 = load ptr, ptr %res_slot2039
  store ptr %case_r2050, ptr %res_slot2013
  br label %case_merge442
case_default443:
  unreachable
case_merge442:
  %case_r2051 = load ptr, ptr %res_slot2013
  ret ptr %case_r2051
}

define ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %steps.arg, ptr %req.arg) {
entry:
  %steps.addr = alloca ptr
  store ptr %steps.arg, ptr %steps.addr
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2052 = load ptr, ptr %steps.addr
  %res_slot2053 = alloca ptr
  %tgp2054 = getelementptr i8, ptr %ld2052, i64 8
  %tag2055 = load i32, ptr %tgp2054, align 4
  switch i32 %tag2055, label %case_default456 [
      i32 0, label %case_br457
      i32 1, label %case_br458
  ]
case_br457:
  %ld2056 = load ptr, ptr %steps.addr
  call void @march_decrc(ptr %ld2056)
  %hp2057 = call ptr @march_alloc(i64 24)
  %tgp2058 = getelementptr i8, ptr %hp2057, i64 8
  store i32 0, ptr %tgp2058, align 4
  %ld2059 = load ptr, ptr %req.addr
  %fp2060 = getelementptr i8, ptr %hp2057, i64 16
  store ptr %ld2059, ptr %fp2060, align 8
  store ptr %hp2057, ptr %res_slot2053
  br label %case_merge455
case_br458:
  %fp2061 = getelementptr i8, ptr %ld2052, i64 16
  %fv2062 = load ptr, ptr %fp2061, align 8
  %$f957.addr = alloca ptr
  store ptr %fv2062, ptr %$f957.addr
  %fp2063 = getelementptr i8, ptr %ld2052, i64 24
  %fv2064 = load ptr, ptr %fp2063, align 8
  %$f958.addr = alloca ptr
  store ptr %fv2064, ptr %$f958.addr
  %freed2065 = call i64 @march_decrc_freed(ptr %ld2052)
  %freed_b2066 = icmp ne i64 %freed2065, 0
  br i1 %freed_b2066, label %br_unique459, label %br_shared460
br_shared460:
  call void @march_incrc(ptr %fv2064)
  call void @march_incrc(ptr %fv2062)
  br label %br_body461
br_unique459:
  br label %br_body461
br_body461:
  %ld2067 = load ptr, ptr %$f957.addr
  %res_slot2068 = alloca ptr
  %tgp2069 = getelementptr i8, ptr %ld2067, i64 8
  %tag2070 = load i32, ptr %tgp2069, align 4
  switch i32 %tag2070, label %case_default463 [
      i32 0, label %case_br464
  ]
case_br464:
  %fp2071 = getelementptr i8, ptr %ld2067, i64 16
  %fv2072 = load ptr, ptr %fp2071, align 8
  %$f959.addr = alloca ptr
  store ptr %fv2072, ptr %$f959.addr
  %fp2073 = getelementptr i8, ptr %ld2067, i64 24
  %fv2074 = load ptr, ptr %fp2073, align 8
  %$f960.addr = alloca ptr
  store ptr %fv2074, ptr %$f960.addr
  %freed2075 = call i64 @march_decrc_freed(ptr %ld2067)
  %freed_b2076 = icmp ne i64 %freed2075, 0
  br i1 %freed_b2076, label %br_unique465, label %br_shared466
br_shared466:
  call void @march_incrc(ptr %fv2074)
  call void @march_incrc(ptr %fv2072)
  br label %br_body467
br_unique465:
  br label %br_body467
br_body467:
  %ld2077 = load ptr, ptr %$f958.addr
  %rest.addr = alloca ptr
  store ptr %ld2077, ptr %rest.addr
  %ld2078 = load ptr, ptr %$f960.addr
  %step_fn.addr = alloca ptr
  store ptr %ld2078, ptr %step_fn.addr
  %ld2079 = load ptr, ptr %step_fn.addr
  %fp2080 = getelementptr i8, ptr %ld2079, i64 16
  %fv2081 = load ptr, ptr %fp2080, align 8
  %ld2082 = load ptr, ptr %req.addr
  %cr2083 = call ptr (ptr, ptr) %fv2081(ptr %ld2079, ptr %ld2082)
  %$t954.addr = alloca ptr
  store ptr %cr2083, ptr %$t954.addr
  %ld2084 = load ptr, ptr %$t954.addr
  %res_slot2085 = alloca ptr
  %tgp2086 = getelementptr i8, ptr %ld2084, i64 8
  %tag2087 = load i32, ptr %tgp2086, align 4
  switch i32 %tag2087, label %case_default469 [
      i32 1, label %case_br470
      i32 0, label %case_br471
  ]
case_br470:
  %fp2088 = getelementptr i8, ptr %ld2084, i64 16
  %fv2089 = load ptr, ptr %fp2088, align 8
  %$f955.addr = alloca ptr
  store ptr %fv2089, ptr %$f955.addr
  %ld2090 = load ptr, ptr %$f955.addr
  %e.addr = alloca ptr
  store ptr %ld2090, ptr %e.addr
  %ld2091 = load ptr, ptr %$t954.addr
  %ld2092 = load ptr, ptr %e.addr
  %rc2093 = load i64, ptr %ld2091, align 8
  %uniq2094 = icmp eq i64 %rc2093, 1
  %fbip_slot2095 = alloca ptr
  br i1 %uniq2094, label %fbip_reuse472, label %fbip_fresh473
fbip_reuse472:
  %tgp2096 = getelementptr i8, ptr %ld2091, i64 8
  store i32 1, ptr %tgp2096, align 4
  %fp2097 = getelementptr i8, ptr %ld2091, i64 16
  store ptr %ld2092, ptr %fp2097, align 8
  store ptr %ld2091, ptr %fbip_slot2095
  br label %fbip_merge474
fbip_fresh473:
  call void @march_decrc(ptr %ld2091)
  %hp2098 = call ptr @march_alloc(i64 24)
  %tgp2099 = getelementptr i8, ptr %hp2098, i64 8
  store i32 1, ptr %tgp2099, align 4
  %fp2100 = getelementptr i8, ptr %hp2098, i64 16
  store ptr %ld2092, ptr %fp2100, align 8
  store ptr %hp2098, ptr %fbip_slot2095
  br label %fbip_merge474
fbip_merge474:
  %fbip_r2101 = load ptr, ptr %fbip_slot2095
  store ptr %fbip_r2101, ptr %res_slot2085
  br label %case_merge468
case_br471:
  %fp2102 = getelementptr i8, ptr %ld2084, i64 16
  %fv2103 = load ptr, ptr %fp2102, align 8
  %$f956.addr = alloca ptr
  store ptr %fv2103, ptr %$f956.addr
  %freed2104 = call i64 @march_decrc_freed(ptr %ld2084)
  %freed_b2105 = icmp ne i64 %freed2104, 0
  br i1 %freed_b2105, label %br_unique475, label %br_shared476
br_shared476:
  call void @march_incrc(ptr %fv2103)
  br label %br_body477
br_unique475:
  br label %br_body477
br_body477:
  %ld2106 = load ptr, ptr %$f956.addr
  %new_req.addr = alloca ptr
  store ptr %ld2106, ptr %new_req.addr
  %ld2107 = load ptr, ptr %rest.addr
  %ld2108 = load ptr, ptr %new_req.addr
  %cr2109 = call ptr @HttpClient.run_request_steps$List_RequestStepEntry$Request_String(ptr %ld2107, ptr %ld2108)
  store ptr %cr2109, ptr %res_slot2085
  br label %case_merge468
case_default469:
  unreachable
case_merge468:
  %case_r2110 = load ptr, ptr %res_slot2085
  store ptr %case_r2110, ptr %res_slot2068
  br label %case_merge462
case_default463:
  unreachable
case_merge462:
  %case_r2111 = load ptr, ptr %res_slot2068
  store ptr %case_r2111, ptr %res_slot2053
  br label %case_merge455
case_default456:
  unreachable
case_merge455:
  %case_r2112 = load ptr, ptr %res_slot2053
  ret ptr %case_r2112
}

define ptr @Http.set_method$Request_V__2631$Method(ptr %req.arg, ptr %m.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %m.addr = alloca ptr
  store ptr %m.arg, ptr %m.addr
  %ld2113 = load ptr, ptr %req.addr
  %res_slot2114 = alloca ptr
  %tgp2115 = getelementptr i8, ptr %ld2113, i64 8
  %tag2116 = load i32, ptr %tgp2115, align 4
  switch i32 %tag2116, label %case_default479 [
      i32 0, label %case_br480
  ]
case_br480:
  %fp2117 = getelementptr i8, ptr %ld2113, i64 16
  %fv2118 = load ptr, ptr %fp2117, align 8
  %$f607.addr = alloca ptr
  store ptr %fv2118, ptr %$f607.addr
  %fp2119 = getelementptr i8, ptr %ld2113, i64 24
  %fv2120 = load ptr, ptr %fp2119, align 8
  %$f608.addr = alloca ptr
  store ptr %fv2120, ptr %$f608.addr
  %fp2121 = getelementptr i8, ptr %ld2113, i64 32
  %fv2122 = load ptr, ptr %fp2121, align 8
  %$f609.addr = alloca ptr
  store ptr %fv2122, ptr %$f609.addr
  %fp2123 = getelementptr i8, ptr %ld2113, i64 40
  %fv2124 = load ptr, ptr %fp2123, align 8
  %$f610.addr = alloca ptr
  store ptr %fv2124, ptr %$f610.addr
  %fp2125 = getelementptr i8, ptr %ld2113, i64 48
  %fv2126 = load ptr, ptr %fp2125, align 8
  %$f611.addr = alloca ptr
  store ptr %fv2126, ptr %$f611.addr
  %fp2127 = getelementptr i8, ptr %ld2113, i64 56
  %fv2128 = load ptr, ptr %fp2127, align 8
  %$f612.addr = alloca ptr
  store ptr %fv2128, ptr %$f612.addr
  %fp2129 = getelementptr i8, ptr %ld2113, i64 64
  %fv2130 = load ptr, ptr %fp2129, align 8
  %$f613.addr = alloca ptr
  store ptr %fv2130, ptr %$f613.addr
  %fp2131 = getelementptr i8, ptr %ld2113, i64 72
  %fv2132 = load ptr, ptr %fp2131, align 8
  %$f614.addr = alloca ptr
  store ptr %fv2132, ptr %$f614.addr
  %ld2133 = load ptr, ptr %$f614.addr
  %bd.addr = alloca ptr
  store ptr %ld2133, ptr %bd.addr
  %ld2134 = load ptr, ptr %$f613.addr
  %hd.addr = alloca ptr
  store ptr %ld2134, ptr %hd.addr
  %ld2135 = load ptr, ptr %$f612.addr
  %q.addr = alloca ptr
  store ptr %ld2135, ptr %q.addr
  %ld2136 = load ptr, ptr %$f611.addr
  %pa.addr = alloca ptr
  store ptr %ld2136, ptr %pa.addr
  %ld2137 = load ptr, ptr %$f610.addr
  %p.addr = alloca ptr
  store ptr %ld2137, ptr %p.addr
  %ld2138 = load ptr, ptr %$f609.addr
  %h.addr = alloca ptr
  store ptr %ld2138, ptr %h.addr
  %ld2139 = load ptr, ptr %$f608.addr
  %sc.addr = alloca ptr
  store ptr %ld2139, ptr %sc.addr
  %ld2140 = load ptr, ptr %req.addr
  %ld2141 = load ptr, ptr %m.addr
  %ld2142 = load ptr, ptr %sc.addr
  %ld2143 = load ptr, ptr %h.addr
  %ld2144 = load ptr, ptr %p.addr
  %ld2145 = load ptr, ptr %pa.addr
  %ld2146 = load ptr, ptr %q.addr
  %ld2147 = load ptr, ptr %hd.addr
  %ld2148 = load ptr, ptr %bd.addr
  %rc2149 = load i64, ptr %ld2140, align 8
  %uniq2150 = icmp eq i64 %rc2149, 1
  %fbip_slot2151 = alloca ptr
  br i1 %uniq2150, label %fbip_reuse481, label %fbip_fresh482
fbip_reuse481:
  %tgp2152 = getelementptr i8, ptr %ld2140, i64 8
  store i32 0, ptr %tgp2152, align 4
  %fp2153 = getelementptr i8, ptr %ld2140, i64 16
  store ptr %ld2141, ptr %fp2153, align 8
  %fp2154 = getelementptr i8, ptr %ld2140, i64 24
  store ptr %ld2142, ptr %fp2154, align 8
  %fp2155 = getelementptr i8, ptr %ld2140, i64 32
  store ptr %ld2143, ptr %fp2155, align 8
  %fp2156 = getelementptr i8, ptr %ld2140, i64 40
  store ptr %ld2144, ptr %fp2156, align 8
  %fp2157 = getelementptr i8, ptr %ld2140, i64 48
  store ptr %ld2145, ptr %fp2157, align 8
  %fp2158 = getelementptr i8, ptr %ld2140, i64 56
  store ptr %ld2146, ptr %fp2158, align 8
  %fp2159 = getelementptr i8, ptr %ld2140, i64 64
  store ptr %ld2147, ptr %fp2159, align 8
  %fp2160 = getelementptr i8, ptr %ld2140, i64 72
  store ptr %ld2148, ptr %fp2160, align 8
  store ptr %ld2140, ptr %fbip_slot2151
  br label %fbip_merge483
fbip_fresh482:
  call void @march_decrc(ptr %ld2140)
  %hp2161 = call ptr @march_alloc(i64 80)
  %tgp2162 = getelementptr i8, ptr %hp2161, i64 8
  store i32 0, ptr %tgp2162, align 4
  %fp2163 = getelementptr i8, ptr %hp2161, i64 16
  store ptr %ld2141, ptr %fp2163, align 8
  %fp2164 = getelementptr i8, ptr %hp2161, i64 24
  store ptr %ld2142, ptr %fp2164, align 8
  %fp2165 = getelementptr i8, ptr %hp2161, i64 32
  store ptr %ld2143, ptr %fp2165, align 8
  %fp2166 = getelementptr i8, ptr %hp2161, i64 40
  store ptr %ld2144, ptr %fp2166, align 8
  %fp2167 = getelementptr i8, ptr %hp2161, i64 48
  store ptr %ld2145, ptr %fp2167, align 8
  %fp2168 = getelementptr i8, ptr %hp2161, i64 56
  store ptr %ld2146, ptr %fp2168, align 8
  %fp2169 = getelementptr i8, ptr %hp2161, i64 64
  store ptr %ld2147, ptr %fp2169, align 8
  %fp2170 = getelementptr i8, ptr %hp2161, i64 72
  store ptr %ld2148, ptr %fp2170, align 8
  store ptr %hp2161, ptr %fbip_slot2151
  br label %fbip_merge483
fbip_merge483:
  %fbip_r2171 = load ptr, ptr %fbip_slot2151
  store ptr %fbip_r2171, ptr %res_slot2114
  br label %case_merge478
case_default479:
  unreachable
case_merge478:
  %case_r2172 = load ptr, ptr %res_slot2114
  ret ptr %case_r2172
}

define ptr @Http.set_body$Request_T_$V__2631(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld2173 = load ptr, ptr %req.addr
  %res_slot2174 = alloca ptr
  %tgp2175 = getelementptr i8, ptr %ld2173, i64 8
  %tag2176 = load i32, ptr %tgp2175, align 4
  switch i32 %tag2176, label %case_default485 [
      i32 0, label %case_br486
  ]
case_br486:
  %fp2177 = getelementptr i8, ptr %ld2173, i64 16
  %fv2178 = load ptr, ptr %fp2177, align 8
  %$f648.addr = alloca ptr
  store ptr %fv2178, ptr %$f648.addr
  %fp2179 = getelementptr i8, ptr %ld2173, i64 24
  %fv2180 = load ptr, ptr %fp2179, align 8
  %$f649.addr = alloca ptr
  store ptr %fv2180, ptr %$f649.addr
  %fp2181 = getelementptr i8, ptr %ld2173, i64 32
  %fv2182 = load ptr, ptr %fp2181, align 8
  %$f650.addr = alloca ptr
  store ptr %fv2182, ptr %$f650.addr
  %fp2183 = getelementptr i8, ptr %ld2173, i64 40
  %fv2184 = load ptr, ptr %fp2183, align 8
  %$f651.addr = alloca ptr
  store ptr %fv2184, ptr %$f651.addr
  %fp2185 = getelementptr i8, ptr %ld2173, i64 48
  %fv2186 = load ptr, ptr %fp2185, align 8
  %$f652.addr = alloca ptr
  store ptr %fv2186, ptr %$f652.addr
  %fp2187 = getelementptr i8, ptr %ld2173, i64 56
  %fv2188 = load ptr, ptr %fp2187, align 8
  %$f653.addr = alloca ptr
  store ptr %fv2188, ptr %$f653.addr
  %fp2189 = getelementptr i8, ptr %ld2173, i64 64
  %fv2190 = load ptr, ptr %fp2189, align 8
  %$f654.addr = alloca ptr
  store ptr %fv2190, ptr %$f654.addr
  %fp2191 = getelementptr i8, ptr %ld2173, i64 72
  %fv2192 = load ptr, ptr %fp2191, align 8
  %$f655.addr = alloca ptr
  store ptr %fv2192, ptr %$f655.addr
  %ld2193 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld2193, ptr %hd.addr
  %ld2194 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld2194, ptr %q.addr
  %ld2195 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld2195, ptr %pa.addr
  %ld2196 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld2196, ptr %p.addr
  %ld2197 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld2197, ptr %h.addr
  %ld2198 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld2198, ptr %sc.addr
  %ld2199 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld2199, ptr %m.addr
  %ld2200 = load ptr, ptr %req.addr
  %ld2201 = load ptr, ptr %m.addr
  %ld2202 = load ptr, ptr %sc.addr
  %ld2203 = load ptr, ptr %h.addr
  %ld2204 = load ptr, ptr %p.addr
  %ld2205 = load ptr, ptr %pa.addr
  %ld2206 = load ptr, ptr %q.addr
  %ld2207 = load ptr, ptr %hd.addr
  %ld2208 = load ptr, ptr %new_body.addr
  %rc2209 = load i64, ptr %ld2200, align 8
  %uniq2210 = icmp eq i64 %rc2209, 1
  %fbip_slot2211 = alloca ptr
  br i1 %uniq2210, label %fbip_reuse487, label %fbip_fresh488
fbip_reuse487:
  %tgp2212 = getelementptr i8, ptr %ld2200, i64 8
  store i32 0, ptr %tgp2212, align 4
  %fp2213 = getelementptr i8, ptr %ld2200, i64 16
  store ptr %ld2201, ptr %fp2213, align 8
  %fp2214 = getelementptr i8, ptr %ld2200, i64 24
  store ptr %ld2202, ptr %fp2214, align 8
  %fp2215 = getelementptr i8, ptr %ld2200, i64 32
  store ptr %ld2203, ptr %fp2215, align 8
  %fp2216 = getelementptr i8, ptr %ld2200, i64 40
  store ptr %ld2204, ptr %fp2216, align 8
  %fp2217 = getelementptr i8, ptr %ld2200, i64 48
  store ptr %ld2205, ptr %fp2217, align 8
  %fp2218 = getelementptr i8, ptr %ld2200, i64 56
  store ptr %ld2206, ptr %fp2218, align 8
  %fp2219 = getelementptr i8, ptr %ld2200, i64 64
  store ptr %ld2207, ptr %fp2219, align 8
  %fp2220 = getelementptr i8, ptr %ld2200, i64 72
  store ptr %ld2208, ptr %fp2220, align 8
  store ptr %ld2200, ptr %fbip_slot2211
  br label %fbip_merge489
fbip_fresh488:
  call void @march_decrc(ptr %ld2200)
  %hp2221 = call ptr @march_alloc(i64 80)
  %tgp2222 = getelementptr i8, ptr %hp2221, i64 8
  store i32 0, ptr %tgp2222, align 4
  %fp2223 = getelementptr i8, ptr %hp2221, i64 16
  store ptr %ld2201, ptr %fp2223, align 8
  %fp2224 = getelementptr i8, ptr %hp2221, i64 24
  store ptr %ld2202, ptr %fp2224, align 8
  %fp2225 = getelementptr i8, ptr %hp2221, i64 32
  store ptr %ld2203, ptr %fp2225, align 8
  %fp2226 = getelementptr i8, ptr %hp2221, i64 40
  store ptr %ld2204, ptr %fp2226, align 8
  %fp2227 = getelementptr i8, ptr %hp2221, i64 48
  store ptr %ld2205, ptr %fp2227, align 8
  %fp2228 = getelementptr i8, ptr %hp2221, i64 56
  store ptr %ld2206, ptr %fp2228, align 8
  %fp2229 = getelementptr i8, ptr %hp2221, i64 64
  store ptr %ld2207, ptr %fp2229, align 8
  %fp2230 = getelementptr i8, ptr %hp2221, i64 72
  store ptr %ld2208, ptr %fp2230, align 8
  store ptr %hp2221, ptr %fbip_slot2211
  br label %fbip_merge489
fbip_merge489:
  %fbip_r2231 = load ptr, ptr %fbip_slot2211
  store ptr %fbip_r2231, ptr %res_slot2174
  br label %case_merge484
case_default485:
  unreachable
case_merge484:
  %case_r2232 = load ptr, ptr %res_slot2174
  ret ptr %case_r2232
}

define ptr @Http.headers$Request_String(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2233 = load ptr, ptr %req.addr
  %res_slot2234 = alloca ptr
  %tgp2235 = getelementptr i8, ptr %ld2233, i64 8
  %tag2236 = load i32, ptr %tgp2235, align 4
  switch i32 %tag2236, label %case_default491 [
      i32 0, label %case_br492
  ]
case_br492:
  %fp2237 = getelementptr i8, ptr %ld2233, i64 16
  %fv2238 = load ptr, ptr %fp2237, align 8
  %$f591.addr = alloca ptr
  store ptr %fv2238, ptr %$f591.addr
  %fp2239 = getelementptr i8, ptr %ld2233, i64 24
  %fv2240 = load ptr, ptr %fp2239, align 8
  %$f592.addr = alloca ptr
  store ptr %fv2240, ptr %$f592.addr
  %fp2241 = getelementptr i8, ptr %ld2233, i64 32
  %fv2242 = load ptr, ptr %fp2241, align 8
  %$f593.addr = alloca ptr
  store ptr %fv2242, ptr %$f593.addr
  %fp2243 = getelementptr i8, ptr %ld2233, i64 40
  %fv2244 = load ptr, ptr %fp2243, align 8
  %$f594.addr = alloca ptr
  store ptr %fv2244, ptr %$f594.addr
  %fp2245 = getelementptr i8, ptr %ld2233, i64 48
  %fv2246 = load ptr, ptr %fp2245, align 8
  %$f595.addr = alloca ptr
  store ptr %fv2246, ptr %$f595.addr
  %fp2247 = getelementptr i8, ptr %ld2233, i64 56
  %fv2248 = load ptr, ptr %fp2247, align 8
  %$f596.addr = alloca ptr
  store ptr %fv2248, ptr %$f596.addr
  %fp2249 = getelementptr i8, ptr %ld2233, i64 64
  %fv2250 = load ptr, ptr %fp2249, align 8
  %$f597.addr = alloca ptr
  store ptr %fv2250, ptr %$f597.addr
  %fp2251 = getelementptr i8, ptr %ld2233, i64 72
  %fv2252 = load ptr, ptr %fp2251, align 8
  %$f598.addr = alloca ptr
  store ptr %fv2252, ptr %$f598.addr
  %freed2253 = call i64 @march_decrc_freed(ptr %ld2233)
  %freed_b2254 = icmp ne i64 %freed2253, 0
  br i1 %freed_b2254, label %br_unique493, label %br_shared494
br_shared494:
  call void @march_incrc(ptr %fv2252)
  call void @march_incrc(ptr %fv2250)
  call void @march_incrc(ptr %fv2248)
  call void @march_incrc(ptr %fv2246)
  call void @march_incrc(ptr %fv2244)
  call void @march_incrc(ptr %fv2242)
  call void @march_incrc(ptr %fv2240)
  call void @march_incrc(ptr %fv2238)
  br label %br_body495
br_unique493:
  br label %br_body495
br_body495:
  %ld2255 = load ptr, ptr %$f597.addr
  %h.addr = alloca ptr
  store ptr %ld2255, ptr %h.addr
  %ld2256 = load ptr, ptr %h.addr
  store ptr %ld2256, ptr %res_slot2234
  br label %case_merge490
case_default491:
  unreachable
case_merge490:
  %case_r2257 = load ptr, ptr %res_slot2234
  ret ptr %case_r2257
}

define ptr @Http.query$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2258 = load ptr, ptr %req.addr
  %res_slot2259 = alloca ptr
  %tgp2260 = getelementptr i8, ptr %ld2258, i64 8
  %tag2261 = load i32, ptr %tgp2260, align 4
  switch i32 %tag2261, label %case_default497 [
      i32 0, label %case_br498
  ]
case_br498:
  %fp2262 = getelementptr i8, ptr %ld2258, i64 16
  %fv2263 = load ptr, ptr %fp2262, align 8
  %$f583.addr = alloca ptr
  store ptr %fv2263, ptr %$f583.addr
  %fp2264 = getelementptr i8, ptr %ld2258, i64 24
  %fv2265 = load ptr, ptr %fp2264, align 8
  %$f584.addr = alloca ptr
  store ptr %fv2265, ptr %$f584.addr
  %fp2266 = getelementptr i8, ptr %ld2258, i64 32
  %fv2267 = load ptr, ptr %fp2266, align 8
  %$f585.addr = alloca ptr
  store ptr %fv2267, ptr %$f585.addr
  %fp2268 = getelementptr i8, ptr %ld2258, i64 40
  %fv2269 = load ptr, ptr %fp2268, align 8
  %$f586.addr = alloca ptr
  store ptr %fv2269, ptr %$f586.addr
  %fp2270 = getelementptr i8, ptr %ld2258, i64 48
  %fv2271 = load ptr, ptr %fp2270, align 8
  %$f587.addr = alloca ptr
  store ptr %fv2271, ptr %$f587.addr
  %fp2272 = getelementptr i8, ptr %ld2258, i64 56
  %fv2273 = load ptr, ptr %fp2272, align 8
  %$f588.addr = alloca ptr
  store ptr %fv2273, ptr %$f588.addr
  %fp2274 = getelementptr i8, ptr %ld2258, i64 64
  %fv2275 = load ptr, ptr %fp2274, align 8
  %$f589.addr = alloca ptr
  store ptr %fv2275, ptr %$f589.addr
  %fp2276 = getelementptr i8, ptr %ld2258, i64 72
  %fv2277 = load ptr, ptr %fp2276, align 8
  %$f590.addr = alloca ptr
  store ptr %fv2277, ptr %$f590.addr
  %freed2278 = call i64 @march_decrc_freed(ptr %ld2258)
  %freed_b2279 = icmp ne i64 %freed2278, 0
  br i1 %freed_b2279, label %br_unique499, label %br_shared500
br_shared500:
  call void @march_incrc(ptr %fv2277)
  call void @march_incrc(ptr %fv2275)
  call void @march_incrc(ptr %fv2273)
  call void @march_incrc(ptr %fv2271)
  call void @march_incrc(ptr %fv2269)
  call void @march_incrc(ptr %fv2267)
  call void @march_incrc(ptr %fv2265)
  call void @march_incrc(ptr %fv2263)
  br label %br_body501
br_unique499:
  br label %br_body501
br_body501:
  %ld2280 = load ptr, ptr %$f588.addr
  %q.addr = alloca ptr
  store ptr %ld2280, ptr %q.addr
  %ld2281 = load ptr, ptr %q.addr
  store ptr %ld2281, ptr %res_slot2259
  br label %case_merge496
case_default497:
  unreachable
case_merge496:
  %case_r2282 = load ptr, ptr %res_slot2259
  ret ptr %case_r2282
}

define ptr @Http.path$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2283 = load ptr, ptr %req.addr
  %res_slot2284 = alloca ptr
  %tgp2285 = getelementptr i8, ptr %ld2283, i64 8
  %tag2286 = load i32, ptr %tgp2285, align 4
  switch i32 %tag2286, label %case_default503 [
      i32 0, label %case_br504
  ]
case_br504:
  %fp2287 = getelementptr i8, ptr %ld2283, i64 16
  %fv2288 = load ptr, ptr %fp2287, align 8
  %$f575.addr = alloca ptr
  store ptr %fv2288, ptr %$f575.addr
  %fp2289 = getelementptr i8, ptr %ld2283, i64 24
  %fv2290 = load ptr, ptr %fp2289, align 8
  %$f576.addr = alloca ptr
  store ptr %fv2290, ptr %$f576.addr
  %fp2291 = getelementptr i8, ptr %ld2283, i64 32
  %fv2292 = load ptr, ptr %fp2291, align 8
  %$f577.addr = alloca ptr
  store ptr %fv2292, ptr %$f577.addr
  %fp2293 = getelementptr i8, ptr %ld2283, i64 40
  %fv2294 = load ptr, ptr %fp2293, align 8
  %$f578.addr = alloca ptr
  store ptr %fv2294, ptr %$f578.addr
  %fp2295 = getelementptr i8, ptr %ld2283, i64 48
  %fv2296 = load ptr, ptr %fp2295, align 8
  %$f579.addr = alloca ptr
  store ptr %fv2296, ptr %$f579.addr
  %fp2297 = getelementptr i8, ptr %ld2283, i64 56
  %fv2298 = load ptr, ptr %fp2297, align 8
  %$f580.addr = alloca ptr
  store ptr %fv2298, ptr %$f580.addr
  %fp2299 = getelementptr i8, ptr %ld2283, i64 64
  %fv2300 = load ptr, ptr %fp2299, align 8
  %$f581.addr = alloca ptr
  store ptr %fv2300, ptr %$f581.addr
  %fp2301 = getelementptr i8, ptr %ld2283, i64 72
  %fv2302 = load ptr, ptr %fp2301, align 8
  %$f582.addr = alloca ptr
  store ptr %fv2302, ptr %$f582.addr
  %freed2303 = call i64 @march_decrc_freed(ptr %ld2283)
  %freed_b2304 = icmp ne i64 %freed2303, 0
  br i1 %freed_b2304, label %br_unique505, label %br_shared506
br_shared506:
  call void @march_incrc(ptr %fv2302)
  call void @march_incrc(ptr %fv2300)
  call void @march_incrc(ptr %fv2298)
  call void @march_incrc(ptr %fv2296)
  call void @march_incrc(ptr %fv2294)
  call void @march_incrc(ptr %fv2292)
  call void @march_incrc(ptr %fv2290)
  call void @march_incrc(ptr %fv2288)
  br label %br_body507
br_unique505:
  br label %br_body507
br_body507:
  %ld2305 = load ptr, ptr %$f579.addr
  %p.addr = alloca ptr
  store ptr %ld2305, ptr %p.addr
  %ld2306 = load ptr, ptr %p.addr
  store ptr %ld2306, ptr %res_slot2284
  br label %case_merge502
case_default503:
  unreachable
case_merge502:
  %case_r2307 = load ptr, ptr %res_slot2284
  ret ptr %case_r2307
}

define ptr @Http.port$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2308 = load ptr, ptr %req.addr
  %res_slot2309 = alloca ptr
  %tgp2310 = getelementptr i8, ptr %ld2308, i64 8
  %tag2311 = load i32, ptr %tgp2310, align 4
  switch i32 %tag2311, label %case_default509 [
      i32 0, label %case_br510
  ]
case_br510:
  %fp2312 = getelementptr i8, ptr %ld2308, i64 16
  %fv2313 = load ptr, ptr %fp2312, align 8
  %$f567.addr = alloca ptr
  store ptr %fv2313, ptr %$f567.addr
  %fp2314 = getelementptr i8, ptr %ld2308, i64 24
  %fv2315 = load ptr, ptr %fp2314, align 8
  %$f568.addr = alloca ptr
  store ptr %fv2315, ptr %$f568.addr
  %fp2316 = getelementptr i8, ptr %ld2308, i64 32
  %fv2317 = load ptr, ptr %fp2316, align 8
  %$f569.addr = alloca ptr
  store ptr %fv2317, ptr %$f569.addr
  %fp2318 = getelementptr i8, ptr %ld2308, i64 40
  %fv2319 = load ptr, ptr %fp2318, align 8
  %$f570.addr = alloca ptr
  store ptr %fv2319, ptr %$f570.addr
  %fp2320 = getelementptr i8, ptr %ld2308, i64 48
  %fv2321 = load ptr, ptr %fp2320, align 8
  %$f571.addr = alloca ptr
  store ptr %fv2321, ptr %$f571.addr
  %fp2322 = getelementptr i8, ptr %ld2308, i64 56
  %fv2323 = load ptr, ptr %fp2322, align 8
  %$f572.addr = alloca ptr
  store ptr %fv2323, ptr %$f572.addr
  %fp2324 = getelementptr i8, ptr %ld2308, i64 64
  %fv2325 = load ptr, ptr %fp2324, align 8
  %$f573.addr = alloca ptr
  store ptr %fv2325, ptr %$f573.addr
  %fp2326 = getelementptr i8, ptr %ld2308, i64 72
  %fv2327 = load ptr, ptr %fp2326, align 8
  %$f574.addr = alloca ptr
  store ptr %fv2327, ptr %$f574.addr
  %freed2328 = call i64 @march_decrc_freed(ptr %ld2308)
  %freed_b2329 = icmp ne i64 %freed2328, 0
  br i1 %freed_b2329, label %br_unique511, label %br_shared512
br_shared512:
  call void @march_incrc(ptr %fv2327)
  call void @march_incrc(ptr %fv2325)
  call void @march_incrc(ptr %fv2323)
  call void @march_incrc(ptr %fv2321)
  call void @march_incrc(ptr %fv2319)
  call void @march_incrc(ptr %fv2317)
  call void @march_incrc(ptr %fv2315)
  call void @march_incrc(ptr %fv2313)
  br label %br_body513
br_unique511:
  br label %br_body513
br_body513:
  %ld2330 = load ptr, ptr %$f570.addr
  %p.addr = alloca ptr
  store ptr %ld2330, ptr %p.addr
  %ld2331 = load ptr, ptr %p.addr
  store ptr %ld2331, ptr %res_slot2309
  br label %case_merge508
case_default509:
  unreachable
case_merge508:
  %case_r2332 = load ptr, ptr %res_slot2309
  ret ptr %case_r2332
}

define ptr @Http.host$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2333 = load ptr, ptr %req.addr
  %res_slot2334 = alloca ptr
  %tgp2335 = getelementptr i8, ptr %ld2333, i64 8
  %tag2336 = load i32, ptr %tgp2335, align 4
  switch i32 %tag2336, label %case_default515 [
      i32 0, label %case_br516
  ]
case_br516:
  %fp2337 = getelementptr i8, ptr %ld2333, i64 16
  %fv2338 = load ptr, ptr %fp2337, align 8
  %$f559.addr = alloca ptr
  store ptr %fv2338, ptr %$f559.addr
  %fp2339 = getelementptr i8, ptr %ld2333, i64 24
  %fv2340 = load ptr, ptr %fp2339, align 8
  %$f560.addr = alloca ptr
  store ptr %fv2340, ptr %$f560.addr
  %fp2341 = getelementptr i8, ptr %ld2333, i64 32
  %fv2342 = load ptr, ptr %fp2341, align 8
  %$f561.addr = alloca ptr
  store ptr %fv2342, ptr %$f561.addr
  %fp2343 = getelementptr i8, ptr %ld2333, i64 40
  %fv2344 = load ptr, ptr %fp2343, align 8
  %$f562.addr = alloca ptr
  store ptr %fv2344, ptr %$f562.addr
  %fp2345 = getelementptr i8, ptr %ld2333, i64 48
  %fv2346 = load ptr, ptr %fp2345, align 8
  %$f563.addr = alloca ptr
  store ptr %fv2346, ptr %$f563.addr
  %fp2347 = getelementptr i8, ptr %ld2333, i64 56
  %fv2348 = load ptr, ptr %fp2347, align 8
  %$f564.addr = alloca ptr
  store ptr %fv2348, ptr %$f564.addr
  %fp2349 = getelementptr i8, ptr %ld2333, i64 64
  %fv2350 = load ptr, ptr %fp2349, align 8
  %$f565.addr = alloca ptr
  store ptr %fv2350, ptr %$f565.addr
  %fp2351 = getelementptr i8, ptr %ld2333, i64 72
  %fv2352 = load ptr, ptr %fp2351, align 8
  %$f566.addr = alloca ptr
  store ptr %fv2352, ptr %$f566.addr
  %freed2353 = call i64 @march_decrc_freed(ptr %ld2333)
  %freed_b2354 = icmp ne i64 %freed2353, 0
  br i1 %freed_b2354, label %br_unique517, label %br_shared518
br_shared518:
  call void @march_incrc(ptr %fv2352)
  call void @march_incrc(ptr %fv2350)
  call void @march_incrc(ptr %fv2348)
  call void @march_incrc(ptr %fv2346)
  call void @march_incrc(ptr %fv2344)
  call void @march_incrc(ptr %fv2342)
  call void @march_incrc(ptr %fv2340)
  call void @march_incrc(ptr %fv2338)
  br label %br_body519
br_unique517:
  br label %br_body519
br_body519:
  %ld2355 = load ptr, ptr %$f561.addr
  %h.addr = alloca ptr
  store ptr %ld2355, ptr %h.addr
  %ld2356 = load ptr, ptr %h.addr
  store ptr %ld2356, ptr %res_slot2334
  br label %case_merge514
case_default515:
  unreachable
case_merge514:
  %case_r2357 = load ptr, ptr %res_slot2334
  ret ptr %case_r2357
}

define ptr @Http.scheme$Request_T_(ptr %req.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %ld2358 = load ptr, ptr %req.addr
  %res_slot2359 = alloca ptr
  %tgp2360 = getelementptr i8, ptr %ld2358, i64 8
  %tag2361 = load i32, ptr %tgp2360, align 4
  switch i32 %tag2361, label %case_default521 [
      i32 0, label %case_br522
  ]
case_br522:
  %fp2362 = getelementptr i8, ptr %ld2358, i64 16
  %fv2363 = load ptr, ptr %fp2362, align 8
  %$f551.addr = alloca ptr
  store ptr %fv2363, ptr %$f551.addr
  %fp2364 = getelementptr i8, ptr %ld2358, i64 24
  %fv2365 = load ptr, ptr %fp2364, align 8
  %$f552.addr = alloca ptr
  store ptr %fv2365, ptr %$f552.addr
  %fp2366 = getelementptr i8, ptr %ld2358, i64 32
  %fv2367 = load ptr, ptr %fp2366, align 8
  %$f553.addr = alloca ptr
  store ptr %fv2367, ptr %$f553.addr
  %fp2368 = getelementptr i8, ptr %ld2358, i64 40
  %fv2369 = load ptr, ptr %fp2368, align 8
  %$f554.addr = alloca ptr
  store ptr %fv2369, ptr %$f554.addr
  %fp2370 = getelementptr i8, ptr %ld2358, i64 48
  %fv2371 = load ptr, ptr %fp2370, align 8
  %$f555.addr = alloca ptr
  store ptr %fv2371, ptr %$f555.addr
  %fp2372 = getelementptr i8, ptr %ld2358, i64 56
  %fv2373 = load ptr, ptr %fp2372, align 8
  %$f556.addr = alloca ptr
  store ptr %fv2373, ptr %$f556.addr
  %fp2374 = getelementptr i8, ptr %ld2358, i64 64
  %fv2375 = load ptr, ptr %fp2374, align 8
  %$f557.addr = alloca ptr
  store ptr %fv2375, ptr %$f557.addr
  %fp2376 = getelementptr i8, ptr %ld2358, i64 72
  %fv2377 = load ptr, ptr %fp2376, align 8
  %$f558.addr = alloca ptr
  store ptr %fv2377, ptr %$f558.addr
  %freed2378 = call i64 @march_decrc_freed(ptr %ld2358)
  %freed_b2379 = icmp ne i64 %freed2378, 0
  br i1 %freed_b2379, label %br_unique523, label %br_shared524
br_shared524:
  call void @march_incrc(ptr %fv2377)
  call void @march_incrc(ptr %fv2375)
  call void @march_incrc(ptr %fv2373)
  call void @march_incrc(ptr %fv2371)
  call void @march_incrc(ptr %fv2369)
  call void @march_incrc(ptr %fv2367)
  call void @march_incrc(ptr %fv2365)
  call void @march_incrc(ptr %fv2363)
  br label %br_body525
br_unique523:
  br label %br_body525
br_body525:
  %ld2380 = load ptr, ptr %$f552.addr
  %s.addr = alloca ptr
  store ptr %ld2380, ptr %s.addr
  %ld2381 = load ptr, ptr %s.addr
  store ptr %ld2381, ptr %res_slot2359
  br label %case_merge520
case_default521:
  unreachable
case_merge520:
  %case_r2382 = load ptr, ptr %res_slot2359
  ret ptr %case_r2382
}

define ptr @Http.set_body$Request_String$String(ptr %req.arg, ptr %new_body.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_body.addr = alloca ptr
  store ptr %new_body.arg, ptr %new_body.addr
  %ld2383 = load ptr, ptr %req.addr
  %res_slot2384 = alloca ptr
  %tgp2385 = getelementptr i8, ptr %ld2383, i64 8
  %tag2386 = load i32, ptr %tgp2385, align 4
  switch i32 %tag2386, label %case_default527 [
      i32 0, label %case_br528
  ]
case_br528:
  %fp2387 = getelementptr i8, ptr %ld2383, i64 16
  %fv2388 = load ptr, ptr %fp2387, align 8
  %$f648.addr = alloca ptr
  store ptr %fv2388, ptr %$f648.addr
  %fp2389 = getelementptr i8, ptr %ld2383, i64 24
  %fv2390 = load ptr, ptr %fp2389, align 8
  %$f649.addr = alloca ptr
  store ptr %fv2390, ptr %$f649.addr
  %fp2391 = getelementptr i8, ptr %ld2383, i64 32
  %fv2392 = load ptr, ptr %fp2391, align 8
  %$f650.addr = alloca ptr
  store ptr %fv2392, ptr %$f650.addr
  %fp2393 = getelementptr i8, ptr %ld2383, i64 40
  %fv2394 = load ptr, ptr %fp2393, align 8
  %$f651.addr = alloca ptr
  store ptr %fv2394, ptr %$f651.addr
  %fp2395 = getelementptr i8, ptr %ld2383, i64 48
  %fv2396 = load ptr, ptr %fp2395, align 8
  %$f652.addr = alloca ptr
  store ptr %fv2396, ptr %$f652.addr
  %fp2397 = getelementptr i8, ptr %ld2383, i64 56
  %fv2398 = load ptr, ptr %fp2397, align 8
  %$f653.addr = alloca ptr
  store ptr %fv2398, ptr %$f653.addr
  %fp2399 = getelementptr i8, ptr %ld2383, i64 64
  %fv2400 = load ptr, ptr %fp2399, align 8
  %$f654.addr = alloca ptr
  store ptr %fv2400, ptr %$f654.addr
  %fp2401 = getelementptr i8, ptr %ld2383, i64 72
  %fv2402 = load ptr, ptr %fp2401, align 8
  %$f655.addr = alloca ptr
  store ptr %fv2402, ptr %$f655.addr
  %ld2403 = load ptr, ptr %$f654.addr
  %hd.addr = alloca ptr
  store ptr %ld2403, ptr %hd.addr
  %ld2404 = load ptr, ptr %$f653.addr
  %q.addr = alloca ptr
  store ptr %ld2404, ptr %q.addr
  %ld2405 = load ptr, ptr %$f652.addr
  %pa.addr = alloca ptr
  store ptr %ld2405, ptr %pa.addr
  %ld2406 = load ptr, ptr %$f651.addr
  %p.addr = alloca ptr
  store ptr %ld2406, ptr %p.addr
  %ld2407 = load ptr, ptr %$f650.addr
  %h.addr = alloca ptr
  store ptr %ld2407, ptr %h.addr
  %ld2408 = load ptr, ptr %$f649.addr
  %sc.addr = alloca ptr
  store ptr %ld2408, ptr %sc.addr
  %ld2409 = load ptr, ptr %$f648.addr
  %m.addr = alloca ptr
  store ptr %ld2409, ptr %m.addr
  %ld2410 = load ptr, ptr %req.addr
  %ld2411 = load ptr, ptr %m.addr
  %ld2412 = load ptr, ptr %sc.addr
  %ld2413 = load ptr, ptr %h.addr
  %ld2414 = load ptr, ptr %p.addr
  %ld2415 = load ptr, ptr %pa.addr
  %ld2416 = load ptr, ptr %q.addr
  %ld2417 = load ptr, ptr %hd.addr
  %ld2418 = load ptr, ptr %new_body.addr
  %rc2419 = load i64, ptr %ld2410, align 8
  %uniq2420 = icmp eq i64 %rc2419, 1
  %fbip_slot2421 = alloca ptr
  br i1 %uniq2420, label %fbip_reuse529, label %fbip_fresh530
fbip_reuse529:
  %tgp2422 = getelementptr i8, ptr %ld2410, i64 8
  store i32 0, ptr %tgp2422, align 4
  %fp2423 = getelementptr i8, ptr %ld2410, i64 16
  store ptr %ld2411, ptr %fp2423, align 8
  %fp2424 = getelementptr i8, ptr %ld2410, i64 24
  store ptr %ld2412, ptr %fp2424, align 8
  %fp2425 = getelementptr i8, ptr %ld2410, i64 32
  store ptr %ld2413, ptr %fp2425, align 8
  %fp2426 = getelementptr i8, ptr %ld2410, i64 40
  store ptr %ld2414, ptr %fp2426, align 8
  %fp2427 = getelementptr i8, ptr %ld2410, i64 48
  store ptr %ld2415, ptr %fp2427, align 8
  %fp2428 = getelementptr i8, ptr %ld2410, i64 56
  store ptr %ld2416, ptr %fp2428, align 8
  %fp2429 = getelementptr i8, ptr %ld2410, i64 64
  store ptr %ld2417, ptr %fp2429, align 8
  %fp2430 = getelementptr i8, ptr %ld2410, i64 72
  store ptr %ld2418, ptr %fp2430, align 8
  store ptr %ld2410, ptr %fbip_slot2421
  br label %fbip_merge531
fbip_fresh530:
  call void @march_decrc(ptr %ld2410)
  %hp2431 = call ptr @march_alloc(i64 80)
  %tgp2432 = getelementptr i8, ptr %hp2431, i64 8
  store i32 0, ptr %tgp2432, align 4
  %fp2433 = getelementptr i8, ptr %hp2431, i64 16
  store ptr %ld2411, ptr %fp2433, align 8
  %fp2434 = getelementptr i8, ptr %hp2431, i64 24
  store ptr %ld2412, ptr %fp2434, align 8
  %fp2435 = getelementptr i8, ptr %hp2431, i64 32
  store ptr %ld2413, ptr %fp2435, align 8
  %fp2436 = getelementptr i8, ptr %hp2431, i64 40
  store ptr %ld2414, ptr %fp2436, align 8
  %fp2437 = getelementptr i8, ptr %hp2431, i64 48
  store ptr %ld2415, ptr %fp2437, align 8
  %fp2438 = getelementptr i8, ptr %hp2431, i64 56
  store ptr %ld2416, ptr %fp2438, align 8
  %fp2439 = getelementptr i8, ptr %hp2431, i64 64
  store ptr %ld2417, ptr %fp2439, align 8
  %fp2440 = getelementptr i8, ptr %hp2431, i64 72
  store ptr %ld2418, ptr %fp2440, align 8
  store ptr %hp2431, ptr %fbip_slot2421
  br label %fbip_merge531
fbip_merge531:
  %fbip_r2441 = load ptr, ptr %fbip_slot2421
  store ptr %fbip_r2441, ptr %res_slot2384
  br label %case_merge526
case_default527:
  unreachable
case_merge526:
  %case_r2442 = load ptr, ptr %res_slot2384
  ret ptr %case_r2442
}

define ptr @Http.set_method$Request_String$Method(ptr %req.arg, ptr %m.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %m.addr = alloca ptr
  store ptr %m.arg, ptr %m.addr
  %ld2443 = load ptr, ptr %req.addr
  %res_slot2444 = alloca ptr
  %tgp2445 = getelementptr i8, ptr %ld2443, i64 8
  %tag2446 = load i32, ptr %tgp2445, align 4
  switch i32 %tag2446, label %case_default533 [
      i32 0, label %case_br534
  ]
case_br534:
  %fp2447 = getelementptr i8, ptr %ld2443, i64 16
  %fv2448 = load ptr, ptr %fp2447, align 8
  %$f607.addr = alloca ptr
  store ptr %fv2448, ptr %$f607.addr
  %fp2449 = getelementptr i8, ptr %ld2443, i64 24
  %fv2450 = load ptr, ptr %fp2449, align 8
  %$f608.addr = alloca ptr
  store ptr %fv2450, ptr %$f608.addr
  %fp2451 = getelementptr i8, ptr %ld2443, i64 32
  %fv2452 = load ptr, ptr %fp2451, align 8
  %$f609.addr = alloca ptr
  store ptr %fv2452, ptr %$f609.addr
  %fp2453 = getelementptr i8, ptr %ld2443, i64 40
  %fv2454 = load ptr, ptr %fp2453, align 8
  %$f610.addr = alloca ptr
  store ptr %fv2454, ptr %$f610.addr
  %fp2455 = getelementptr i8, ptr %ld2443, i64 48
  %fv2456 = load ptr, ptr %fp2455, align 8
  %$f611.addr = alloca ptr
  store ptr %fv2456, ptr %$f611.addr
  %fp2457 = getelementptr i8, ptr %ld2443, i64 56
  %fv2458 = load ptr, ptr %fp2457, align 8
  %$f612.addr = alloca ptr
  store ptr %fv2458, ptr %$f612.addr
  %fp2459 = getelementptr i8, ptr %ld2443, i64 64
  %fv2460 = load ptr, ptr %fp2459, align 8
  %$f613.addr = alloca ptr
  store ptr %fv2460, ptr %$f613.addr
  %fp2461 = getelementptr i8, ptr %ld2443, i64 72
  %fv2462 = load ptr, ptr %fp2461, align 8
  %$f614.addr = alloca ptr
  store ptr %fv2462, ptr %$f614.addr
  %ld2463 = load ptr, ptr %$f614.addr
  %bd.addr = alloca ptr
  store ptr %ld2463, ptr %bd.addr
  %ld2464 = load ptr, ptr %$f613.addr
  %hd.addr = alloca ptr
  store ptr %ld2464, ptr %hd.addr
  %ld2465 = load ptr, ptr %$f612.addr
  %q.addr = alloca ptr
  store ptr %ld2465, ptr %q.addr
  %ld2466 = load ptr, ptr %$f611.addr
  %pa.addr = alloca ptr
  store ptr %ld2466, ptr %pa.addr
  %ld2467 = load ptr, ptr %$f610.addr
  %p.addr = alloca ptr
  store ptr %ld2467, ptr %p.addr
  %ld2468 = load ptr, ptr %$f609.addr
  %h.addr = alloca ptr
  store ptr %ld2468, ptr %h.addr
  %ld2469 = load ptr, ptr %$f608.addr
  %sc.addr = alloca ptr
  store ptr %ld2469, ptr %sc.addr
  %ld2470 = load ptr, ptr %req.addr
  %ld2471 = load ptr, ptr %m.addr
  %ld2472 = load ptr, ptr %sc.addr
  %ld2473 = load ptr, ptr %h.addr
  %ld2474 = load ptr, ptr %p.addr
  %ld2475 = load ptr, ptr %pa.addr
  %ld2476 = load ptr, ptr %q.addr
  %ld2477 = load ptr, ptr %hd.addr
  %ld2478 = load ptr, ptr %bd.addr
  %rc2479 = load i64, ptr %ld2470, align 8
  %uniq2480 = icmp eq i64 %rc2479, 1
  %fbip_slot2481 = alloca ptr
  br i1 %uniq2480, label %fbip_reuse535, label %fbip_fresh536
fbip_reuse535:
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
  br label %fbip_merge537
fbip_fresh536:
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
  br label %fbip_merge537
fbip_merge537:
  %fbip_r2501 = load ptr, ptr %fbip_slot2481
  store ptr %fbip_r2501, ptr %res_slot2444
  br label %case_merge532
case_default533:
  unreachable
case_merge532:
  %case_r2502 = load ptr, ptr %res_slot2444
  ret ptr %case_r2502
}

define ptr @Http.set_path$Request_String$String(ptr %req.arg, ptr %new_path.arg) {
entry:
  %req.addr = alloca ptr
  store ptr %req.arg, ptr %req.addr
  %new_path.addr = alloca ptr
  store ptr %new_path.arg, ptr %new_path.addr
  %ld2503 = load ptr, ptr %req.addr
  %res_slot2504 = alloca ptr
  %tgp2505 = getelementptr i8, ptr %ld2503, i64 8
  %tag2506 = load i32, ptr %tgp2505, align 4
  switch i32 %tag2506, label %case_default539 [
      i32 0, label %case_br540
  ]
case_br540:
  %fp2507 = getelementptr i8, ptr %ld2503, i64 16
  %fv2508 = load ptr, ptr %fp2507, align 8
  %$f640.addr = alloca ptr
  store ptr %fv2508, ptr %$f640.addr
  %fp2509 = getelementptr i8, ptr %ld2503, i64 24
  %fv2510 = load ptr, ptr %fp2509, align 8
  %$f641.addr = alloca ptr
  store ptr %fv2510, ptr %$f641.addr
  %fp2511 = getelementptr i8, ptr %ld2503, i64 32
  %fv2512 = load ptr, ptr %fp2511, align 8
  %$f642.addr = alloca ptr
  store ptr %fv2512, ptr %$f642.addr
  %fp2513 = getelementptr i8, ptr %ld2503, i64 40
  %fv2514 = load ptr, ptr %fp2513, align 8
  %$f643.addr = alloca ptr
  store ptr %fv2514, ptr %$f643.addr
  %fp2515 = getelementptr i8, ptr %ld2503, i64 48
  %fv2516 = load ptr, ptr %fp2515, align 8
  %$f644.addr = alloca ptr
  store ptr %fv2516, ptr %$f644.addr
  %fp2517 = getelementptr i8, ptr %ld2503, i64 56
  %fv2518 = load ptr, ptr %fp2517, align 8
  %$f645.addr = alloca ptr
  store ptr %fv2518, ptr %$f645.addr
  %fp2519 = getelementptr i8, ptr %ld2503, i64 64
  %fv2520 = load ptr, ptr %fp2519, align 8
  %$f646.addr = alloca ptr
  store ptr %fv2520, ptr %$f646.addr
  %fp2521 = getelementptr i8, ptr %ld2503, i64 72
  %fv2522 = load ptr, ptr %fp2521, align 8
  %$f647.addr = alloca ptr
  store ptr %fv2522, ptr %$f647.addr
  %ld2523 = load ptr, ptr %$f647.addr
  %bd.addr = alloca ptr
  store ptr %ld2523, ptr %bd.addr
  %ld2524 = load ptr, ptr %$f646.addr
  %hd.addr = alloca ptr
  store ptr %ld2524, ptr %hd.addr
  %ld2525 = load ptr, ptr %$f645.addr
  %q.addr = alloca ptr
  store ptr %ld2525, ptr %q.addr
  %ld2526 = load ptr, ptr %$f643.addr
  %p.addr = alloca ptr
  store ptr %ld2526, ptr %p.addr
  %ld2527 = load ptr, ptr %$f642.addr
  %h.addr = alloca ptr
  store ptr %ld2527, ptr %h.addr
  %ld2528 = load ptr, ptr %$f641.addr
  %sc.addr = alloca ptr
  store ptr %ld2528, ptr %sc.addr
  %ld2529 = load ptr, ptr %$f640.addr
  %m.addr = alloca ptr
  store ptr %ld2529, ptr %m.addr
  %ld2530 = load ptr, ptr %req.addr
  %ld2531 = load ptr, ptr %m.addr
  %ld2532 = load ptr, ptr %sc.addr
  %ld2533 = load ptr, ptr %h.addr
  %ld2534 = load ptr, ptr %p.addr
  %ld2535 = load ptr, ptr %new_path.addr
  %ld2536 = load ptr, ptr %q.addr
  %ld2537 = load ptr, ptr %hd.addr
  %ld2538 = load ptr, ptr %bd.addr
  %rc2539 = load i64, ptr %ld2530, align 8
  %uniq2540 = icmp eq i64 %rc2539, 1
  %fbip_slot2541 = alloca ptr
  br i1 %uniq2540, label %fbip_reuse541, label %fbip_fresh542
fbip_reuse541:
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
  br label %fbip_merge543
fbip_fresh542:
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
  br label %fbip_merge543
fbip_merge543:
  %fbip_r2561 = load ptr, ptr %fbip_slot2541
  store ptr %fbip_r2561, ptr %res_slot2504
  br label %case_merge538
case_default539:
  unreachable
case_merge538:
  %case_r2562 = load ptr, ptr %res_slot2504
  ret ptr %case_r2562
}

define ptr @Http.get_header$Response_V__3459$String(ptr %resp.arg, ptr %name.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld2563 = load ptr, ptr %name.addr
  %cr2564 = call ptr @march_string_to_lowercase(ptr %ld2563)
  %lower_name.addr = alloca ptr
  store ptr %cr2564, ptr %lower_name.addr
  %hp2565 = call ptr @march_alloc(i64 32)
  %tgp2566 = getelementptr i8, ptr %hp2565, i64 8
  store i32 0, ptr %tgp2566, align 4
  %fp2567 = getelementptr i8, ptr %hp2565, i64 16
  store ptr @find$apply$26, ptr %fp2567, align 8
  %ld2568 = load ptr, ptr %lower_name.addr
  %fp2569 = getelementptr i8, ptr %hp2565, i64 24
  store ptr %ld2568, ptr %fp2569, align 8
  %find.addr = alloca ptr
  store ptr %hp2565, ptr %find.addr
  %ld2570 = load ptr, ptr %resp.addr
  %cr2571 = call ptr @Http.response_headers$Response_V__2540(ptr %ld2570)
  %$t684.addr = alloca ptr
  store ptr %cr2571, ptr %$t684.addr
  %ld2572 = load ptr, ptr %find.addr
  %fp2573 = getelementptr i8, ptr %ld2572, i64 16
  %fv2574 = load ptr, ptr %fp2573, align 8
  %ld2575 = load ptr, ptr %$t684.addr
  %cr2576 = call ptr (ptr, ptr) %fv2574(ptr %ld2572, ptr %ld2575)
  ret ptr %cr2576
}

define i64 @Http.response_is_redirect$Response_V__3459(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2577 = load ptr, ptr %resp.addr
  %cr2578 = call ptr @Http.response_status$Response_V__2524(ptr %ld2577)
  %$t677.addr = alloca ptr
  store ptr %cr2578, ptr %$t677.addr
  %ld2579 = load ptr, ptr %$t677.addr
  %s_i32.addr = alloca ptr
  store ptr %ld2579, ptr %s_i32.addr
  %ld2580 = load ptr, ptr %s_i32.addr
  %cr2581 = call i64 @Http.status_code(ptr %ld2580)
  %c_i33.addr = alloca i64
  store i64 %cr2581, ptr %c_i33.addr
  %ld2582 = load i64, ptr %c_i33.addr
  %cmp2583 = icmp sge i64 %ld2582, 300
  %ar2584 = zext i1 %cmp2583 to i64
  %$t537_i34.addr = alloca i64
  store i64 %ar2584, ptr %$t537_i34.addr
  %ld2585 = load i64, ptr %c_i33.addr
  %cmp2586 = icmp slt i64 %ld2585, 400
  %ar2587 = zext i1 %cmp2586 to i64
  %$t538_i35.addr = alloca i64
  store i64 %ar2587, ptr %$t538_i35.addr
  %ld2588 = load i64, ptr %$t537_i34.addr
  %ld2589 = load i64, ptr %$t538_i35.addr
  %ar2590 = and i64 %ld2588, %ld2589
  ret i64 %ar2590
}

define ptr @Http.response_headers$Response_V__2540(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2591 = load ptr, ptr %resp.addr
  %res_slot2592 = alloca ptr
  %tgp2593 = getelementptr i8, ptr %ld2591, i64 8
  %tag2594 = load i32, ptr %tgp2593, align 4
  switch i32 %tag2594, label %case_default545 [
      i32 0, label %case_br546
  ]
case_br546:
  %fp2595 = getelementptr i8, ptr %ld2591, i64 16
  %fv2596 = load ptr, ptr %fp2595, align 8
  %$f669.addr = alloca ptr
  store ptr %fv2596, ptr %$f669.addr
  %fp2597 = getelementptr i8, ptr %ld2591, i64 24
  %fv2598 = load ptr, ptr %fp2597, align 8
  %$f670.addr = alloca ptr
  store ptr %fv2598, ptr %$f670.addr
  %fp2599 = getelementptr i8, ptr %ld2591, i64 32
  %fv2600 = load ptr, ptr %fp2599, align 8
  %$f671.addr = alloca ptr
  store ptr %fv2600, ptr %$f671.addr
  %freed2601 = call i64 @march_decrc_freed(ptr %ld2591)
  %freed_b2602 = icmp ne i64 %freed2601, 0
  br i1 %freed_b2602, label %br_unique547, label %br_shared548
br_shared548:
  call void @march_incrc(ptr %fv2600)
  call void @march_incrc(ptr %fv2598)
  call void @march_incrc(ptr %fv2596)
  br label %br_body549
br_unique547:
  br label %br_body549
br_body549:
  %ld2603 = load ptr, ptr %$f670.addr
  %h.addr = alloca ptr
  store ptr %ld2603, ptr %h.addr
  %ld2604 = load ptr, ptr %h.addr
  store ptr %ld2604, ptr %res_slot2592
  br label %case_merge544
case_default545:
  unreachable
case_merge544:
  %case_r2605 = load ptr, ptr %res_slot2592
  ret ptr %case_r2605
}

define ptr @Http.response_status$Response_V__2524(ptr %resp.arg) {
entry:
  %resp.addr = alloca ptr
  store ptr %resp.arg, ptr %resp.addr
  %ld2606 = load ptr, ptr %resp.addr
  %res_slot2607 = alloca ptr
  %tgp2608 = getelementptr i8, ptr %ld2606, i64 8
  %tag2609 = load i32, ptr %tgp2608, align 4
  switch i32 %tag2609, label %case_default551 [
      i32 0, label %case_br552
  ]
case_br552:
  %fp2610 = getelementptr i8, ptr %ld2606, i64 16
  %fv2611 = load ptr, ptr %fp2610, align 8
  %$f666.addr = alloca ptr
  store ptr %fv2611, ptr %$f666.addr
  %fp2612 = getelementptr i8, ptr %ld2606, i64 24
  %fv2613 = load ptr, ptr %fp2612, align 8
  %$f667.addr = alloca ptr
  store ptr %fv2613, ptr %$f667.addr
  %fp2614 = getelementptr i8, ptr %ld2606, i64 32
  %fv2615 = load ptr, ptr %fp2614, align 8
  %$f668.addr = alloca ptr
  store ptr %fv2615, ptr %$f668.addr
  %freed2616 = call i64 @march_decrc_freed(ptr %ld2606)
  %freed_b2617 = icmp ne i64 %freed2616, 0
  br i1 %freed_b2617, label %br_unique553, label %br_shared554
br_shared554:
  call void @march_incrc(ptr %fv2615)
  call void @march_incrc(ptr %fv2613)
  call void @march_incrc(ptr %fv2611)
  br label %br_body555
br_unique553:
  br label %br_body555
br_body555:
  %ld2618 = load ptr, ptr %$f666.addr
  %s.addr = alloca ptr
  store ptr %ld2618, ptr %s.addr
  %ld2619 = load ptr, ptr %s.addr
  store ptr %ld2619, ptr %res_slot2607
  br label %case_merge550
case_default551:
  unreachable
case_merge550:
  %case_r2620 = load ptr, ptr %res_slot2607
  ret ptr %case_r2620
}

define ptr @list_concat$apply$14(ptr %$clo.arg, ptr %a.arg, ptr %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %b.addr = alloca ptr
  store ptr %b.arg, ptr %b.addr
  %ld2621 = load ptr, ptr %a.addr
  %res_slot2622 = alloca ptr
  %tgp2623 = getelementptr i8, ptr %ld2621, i64 8
  %tag2624 = load i32, ptr %tgp2623, align 4
  switch i32 %tag2624, label %case_default557 [
      i32 0, label %case_br558
      i32 1, label %case_br559
  ]
case_br558:
  %ld2625 = load ptr, ptr %a.addr
  call void @march_decrc(ptr %ld2625)
  %ld2626 = load ptr, ptr %b.addr
  store ptr %ld2626, ptr %res_slot2622
  br label %case_merge556
case_br559:
  %fp2627 = getelementptr i8, ptr %ld2621, i64 16
  %fv2628 = load ptr, ptr %fp2627, align 8
  %$f924.addr = alloca ptr
  store ptr %fv2628, ptr %$f924.addr
  %fp2629 = getelementptr i8, ptr %ld2621, i64 24
  %fv2630 = load ptr, ptr %fp2629, align 8
  %$f925.addr = alloca ptr
  store ptr %fv2630, ptr %$f925.addr
  %ld2631 = load ptr, ptr %$f925.addr
  %t.addr = alloca ptr
  store ptr %ld2631, ptr %t.addr
  %ld2632 = load ptr, ptr %$f924.addr
  %h.addr = alloca ptr
  store ptr %ld2632, ptr %h.addr
  %ld2633 = load ptr, ptr %t.addr
  %ld2634 = load ptr, ptr %b.addr
  %cr2635 = call ptr @march_list_concat(ptr %ld2633, ptr %ld2634)
  %$t923.addr = alloca ptr
  store ptr %cr2635, ptr %$t923.addr
  %ld2636 = load ptr, ptr %a.addr
  %ld2637 = load ptr, ptr %h.addr
  %ld2638 = load ptr, ptr %$t923.addr
  %rc2639 = load i64, ptr %ld2636, align 8
  %uniq2640 = icmp eq i64 %rc2639, 1
  %fbip_slot2641 = alloca ptr
  br i1 %uniq2640, label %fbip_reuse560, label %fbip_fresh561
fbip_reuse560:
  %tgp2642 = getelementptr i8, ptr %ld2636, i64 8
  store i32 1, ptr %tgp2642, align 4
  %fp2643 = getelementptr i8, ptr %ld2636, i64 16
  store ptr %ld2637, ptr %fp2643, align 8
  %fp2644 = getelementptr i8, ptr %ld2636, i64 24
  store ptr %ld2638, ptr %fp2644, align 8
  store ptr %ld2636, ptr %fbip_slot2641
  br label %fbip_merge562
fbip_fresh561:
  call void @march_decrc(ptr %ld2636)
  %hp2645 = call ptr @march_alloc(i64 32)
  %tgp2646 = getelementptr i8, ptr %hp2645, i64 8
  store i32 1, ptr %tgp2646, align 4
  %fp2647 = getelementptr i8, ptr %hp2645, i64 16
  store ptr %ld2637, ptr %fp2647, align 8
  %fp2648 = getelementptr i8, ptr %hp2645, i64 24
  store ptr %ld2638, ptr %fp2648, align 8
  store ptr %hp2645, ptr %fbip_slot2641
  br label %fbip_merge562
fbip_merge562:
  %fbip_r2649 = load ptr, ptr %fbip_slot2641
  store ptr %fbip_r2649, ptr %res_slot2622
  br label %case_merge556
case_default557:
  unreachable
case_merge556:
  %case_r2650 = load ptr, ptr %res_slot2622
  ret ptr %case_r2650
}

define ptr @req_names$apply$15(ptr %$clo.arg, ptr %xs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld2651 = load ptr, ptr %$clo.addr
  %req_names.addr = alloca ptr
  store ptr %ld2651, ptr %req_names.addr
  %ld2652 = load ptr, ptr %xs.addr
  %res_slot2653 = alloca ptr
  %tgp2654 = getelementptr i8, ptr %ld2652, i64 8
  %tag2655 = load i32, ptr %tgp2654, align 4
  switch i32 %tag2655, label %case_default564 [
      i32 0, label %case_br565
      i32 1, label %case_br566
  ]
case_br565:
  %ld2656 = load ptr, ptr %xs.addr
  %rc2657 = load i64, ptr %ld2656, align 8
  %uniq2658 = icmp eq i64 %rc2657, 1
  %fbip_slot2659 = alloca ptr
  br i1 %uniq2658, label %fbip_reuse567, label %fbip_fresh568
fbip_reuse567:
  %tgp2660 = getelementptr i8, ptr %ld2656, i64 8
  store i32 0, ptr %tgp2660, align 4
  store ptr %ld2656, ptr %fbip_slot2659
  br label %fbip_merge569
fbip_fresh568:
  call void @march_decrc(ptr %ld2656)
  %hp2661 = call ptr @march_alloc(i64 16)
  %tgp2662 = getelementptr i8, ptr %hp2661, i64 8
  store i32 0, ptr %tgp2662, align 4
  store ptr %hp2661, ptr %fbip_slot2659
  br label %fbip_merge569
fbip_merge569:
  %fbip_r2663 = load ptr, ptr %fbip_slot2659
  store ptr %fbip_r2663, ptr %res_slot2653
  br label %case_merge563
case_br566:
  %fp2664 = getelementptr i8, ptr %ld2652, i64 16
  %fv2665 = load ptr, ptr %fp2664, align 8
  %$f928.addr = alloca ptr
  store ptr %fv2665, ptr %$f928.addr
  %fp2666 = getelementptr i8, ptr %ld2652, i64 24
  %fv2667 = load ptr, ptr %fp2666, align 8
  %$f929.addr = alloca ptr
  store ptr %fv2667, ptr %$f929.addr
  %freed2668 = call i64 @march_decrc_freed(ptr %ld2652)
  %freed_b2669 = icmp ne i64 %freed2668, 0
  br i1 %freed_b2669, label %br_unique570, label %br_shared571
br_shared571:
  call void @march_incrc(ptr %fv2667)
  call void @march_incrc(ptr %fv2665)
  br label %br_body572
br_unique570:
  br label %br_body572
br_body572:
  %ld2670 = load ptr, ptr %$f928.addr
  %res_slot2671 = alloca ptr
  %tgp2672 = getelementptr i8, ptr %ld2670, i64 8
  %tag2673 = load i32, ptr %tgp2672, align 4
  switch i32 %tag2673, label %case_default574 [
      i32 0, label %case_br575
  ]
case_br575:
  %fp2674 = getelementptr i8, ptr %ld2670, i64 16
  %fv2675 = load ptr, ptr %fp2674, align 8
  %$f930.addr = alloca ptr
  store ptr %fv2675, ptr %$f930.addr
  %fp2676 = getelementptr i8, ptr %ld2670, i64 24
  %fv2677 = load ptr, ptr %fp2676, align 8
  %$f931.addr = alloca ptr
  store ptr %fv2677, ptr %$f931.addr
  %freed2678 = call i64 @march_decrc_freed(ptr %ld2670)
  %freed_b2679 = icmp ne i64 %freed2678, 0
  br i1 %freed_b2679, label %br_unique576, label %br_shared577
br_shared577:
  call void @march_incrc(ptr %fv2677)
  call void @march_incrc(ptr %fv2675)
  br label %br_body578
br_unique576:
  br label %br_body578
br_body578:
  %ld2680 = load ptr, ptr %$f929.addr
  %rest.addr = alloca ptr
  store ptr %ld2680, ptr %rest.addr
  %ld2681 = load ptr, ptr %$f930.addr
  %n.addr = alloca ptr
  store ptr %ld2681, ptr %n.addr
  %sl2682 = call ptr @march_string_lit(ptr @.str65, i64 8)
  %ld2683 = load ptr, ptr %n.addr
  %cr2684 = call ptr @march_string_concat(ptr %sl2682, ptr %ld2683)
  %$t926.addr = alloca ptr
  store ptr %cr2684, ptr %$t926.addr
  %ld2685 = load ptr, ptr %req_names.addr
  %fp2686 = getelementptr i8, ptr %ld2685, i64 16
  %fv2687 = load ptr, ptr %fp2686, align 8
  %ld2688 = load ptr, ptr %rest.addr
  %cr2689 = call ptr (ptr, ptr) %fv2687(ptr %ld2685, ptr %ld2688)
  %$t927.addr = alloca ptr
  store ptr %cr2689, ptr %$t927.addr
  %hp2690 = call ptr @march_alloc(i64 32)
  %tgp2691 = getelementptr i8, ptr %hp2690, i64 8
  store i32 1, ptr %tgp2691, align 4
  %ld2692 = load ptr, ptr %$t926.addr
  %fp2693 = getelementptr i8, ptr %hp2690, i64 16
  store ptr %ld2692, ptr %fp2693, align 8
  %ld2694 = load ptr, ptr %$t927.addr
  %fp2695 = getelementptr i8, ptr %hp2690, i64 24
  store ptr %ld2694, ptr %fp2695, align 8
  store ptr %hp2690, ptr %res_slot2671
  br label %case_merge573
case_default574:
  unreachable
case_merge573:
  %case_r2696 = load ptr, ptr %res_slot2671
  store ptr %case_r2696, ptr %res_slot2653
  br label %case_merge563
case_default564:
  unreachable
case_merge563:
  %case_r2697 = load ptr, ptr %res_slot2653
  ret ptr %case_r2697
}

define ptr @resp_names$apply$16(ptr %$clo.arg, ptr %xs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld2698 = load ptr, ptr %$clo.addr
  %resp_names.addr = alloca ptr
  store ptr %ld2698, ptr %resp_names.addr
  %ld2699 = load ptr, ptr %xs.addr
  %res_slot2700 = alloca ptr
  %tgp2701 = getelementptr i8, ptr %ld2699, i64 8
  %tag2702 = load i32, ptr %tgp2701, align 4
  switch i32 %tag2702, label %case_default580 [
      i32 0, label %case_br581
      i32 1, label %case_br582
  ]
case_br581:
  %ld2703 = load ptr, ptr %xs.addr
  %rc2704 = load i64, ptr %ld2703, align 8
  %uniq2705 = icmp eq i64 %rc2704, 1
  %fbip_slot2706 = alloca ptr
  br i1 %uniq2705, label %fbip_reuse583, label %fbip_fresh584
fbip_reuse583:
  %tgp2707 = getelementptr i8, ptr %ld2703, i64 8
  store i32 0, ptr %tgp2707, align 4
  store ptr %ld2703, ptr %fbip_slot2706
  br label %fbip_merge585
fbip_fresh584:
  call void @march_decrc(ptr %ld2703)
  %hp2708 = call ptr @march_alloc(i64 16)
  %tgp2709 = getelementptr i8, ptr %hp2708, i64 8
  store i32 0, ptr %tgp2709, align 4
  store ptr %hp2708, ptr %fbip_slot2706
  br label %fbip_merge585
fbip_merge585:
  %fbip_r2710 = load ptr, ptr %fbip_slot2706
  store ptr %fbip_r2710, ptr %res_slot2700
  br label %case_merge579
case_br582:
  %fp2711 = getelementptr i8, ptr %ld2699, i64 16
  %fv2712 = load ptr, ptr %fp2711, align 8
  %$f934.addr = alloca ptr
  store ptr %fv2712, ptr %$f934.addr
  %fp2713 = getelementptr i8, ptr %ld2699, i64 24
  %fv2714 = load ptr, ptr %fp2713, align 8
  %$f935.addr = alloca ptr
  store ptr %fv2714, ptr %$f935.addr
  %freed2715 = call i64 @march_decrc_freed(ptr %ld2699)
  %freed_b2716 = icmp ne i64 %freed2715, 0
  br i1 %freed_b2716, label %br_unique586, label %br_shared587
br_shared587:
  call void @march_incrc(ptr %fv2714)
  call void @march_incrc(ptr %fv2712)
  br label %br_body588
br_unique586:
  br label %br_body588
br_body588:
  %ld2717 = load ptr, ptr %$f934.addr
  %res_slot2718 = alloca ptr
  %tgp2719 = getelementptr i8, ptr %ld2717, i64 8
  %tag2720 = load i32, ptr %tgp2719, align 4
  switch i32 %tag2720, label %case_default590 [
      i32 0, label %case_br591
  ]
case_br591:
  %fp2721 = getelementptr i8, ptr %ld2717, i64 16
  %fv2722 = load ptr, ptr %fp2721, align 8
  %$f936.addr = alloca ptr
  store ptr %fv2722, ptr %$f936.addr
  %fp2723 = getelementptr i8, ptr %ld2717, i64 24
  %fv2724 = load ptr, ptr %fp2723, align 8
  %$f937.addr = alloca ptr
  store ptr %fv2724, ptr %$f937.addr
  %freed2725 = call i64 @march_decrc_freed(ptr %ld2717)
  %freed_b2726 = icmp ne i64 %freed2725, 0
  br i1 %freed_b2726, label %br_unique592, label %br_shared593
br_shared593:
  call void @march_incrc(ptr %fv2724)
  call void @march_incrc(ptr %fv2722)
  br label %br_body594
br_unique592:
  br label %br_body594
br_body594:
  %ld2727 = load ptr, ptr %$f935.addr
  %rest.addr = alloca ptr
  store ptr %ld2727, ptr %rest.addr
  %ld2728 = load ptr, ptr %$f936.addr
  %n.addr = alloca ptr
  store ptr %ld2728, ptr %n.addr
  %sl2729 = call ptr @march_string_lit(ptr @.str66, i64 9)
  %ld2730 = load ptr, ptr %n.addr
  %cr2731 = call ptr @march_string_concat(ptr %sl2729, ptr %ld2730)
  %$t932.addr = alloca ptr
  store ptr %cr2731, ptr %$t932.addr
  %ld2732 = load ptr, ptr %resp_names.addr
  %fp2733 = getelementptr i8, ptr %ld2732, i64 16
  %fv2734 = load ptr, ptr %fp2733, align 8
  %ld2735 = load ptr, ptr %rest.addr
  %cr2736 = call ptr (ptr, ptr) %fv2734(ptr %ld2732, ptr %ld2735)
  %$t933.addr = alloca ptr
  store ptr %cr2736, ptr %$t933.addr
  %hp2737 = call ptr @march_alloc(i64 32)
  %tgp2738 = getelementptr i8, ptr %hp2737, i64 8
  store i32 1, ptr %tgp2738, align 4
  %ld2739 = load ptr, ptr %$t932.addr
  %fp2740 = getelementptr i8, ptr %hp2737, i64 16
  store ptr %ld2739, ptr %fp2740, align 8
  %ld2741 = load ptr, ptr %$t933.addr
  %fp2742 = getelementptr i8, ptr %hp2737, i64 24
  store ptr %ld2741, ptr %fp2742, align 8
  store ptr %hp2737, ptr %res_slot2718
  br label %case_merge589
case_default590:
  unreachable
case_merge589:
  %case_r2743 = load ptr, ptr %res_slot2718
  store ptr %case_r2743, ptr %res_slot2700
  br label %case_merge579
case_default580:
  unreachable
case_merge579:
  %case_r2744 = load ptr, ptr %res_slot2700
  ret ptr %case_r2744
}

define ptr @err_names$apply$17(ptr %$clo.arg, ptr %xs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld2745 = load ptr, ptr %$clo.addr
  %err_names.addr = alloca ptr
  store ptr %ld2745, ptr %err_names.addr
  %ld2746 = load ptr, ptr %xs.addr
  %res_slot2747 = alloca ptr
  %tgp2748 = getelementptr i8, ptr %ld2746, i64 8
  %tag2749 = load i32, ptr %tgp2748, align 4
  switch i32 %tag2749, label %case_default596 [
      i32 0, label %case_br597
      i32 1, label %case_br598
  ]
case_br597:
  %ld2750 = load ptr, ptr %xs.addr
  %rc2751 = load i64, ptr %ld2750, align 8
  %uniq2752 = icmp eq i64 %rc2751, 1
  %fbip_slot2753 = alloca ptr
  br i1 %uniq2752, label %fbip_reuse599, label %fbip_fresh600
fbip_reuse599:
  %tgp2754 = getelementptr i8, ptr %ld2750, i64 8
  store i32 0, ptr %tgp2754, align 4
  store ptr %ld2750, ptr %fbip_slot2753
  br label %fbip_merge601
fbip_fresh600:
  call void @march_decrc(ptr %ld2750)
  %hp2755 = call ptr @march_alloc(i64 16)
  %tgp2756 = getelementptr i8, ptr %hp2755, i64 8
  store i32 0, ptr %tgp2756, align 4
  store ptr %hp2755, ptr %fbip_slot2753
  br label %fbip_merge601
fbip_merge601:
  %fbip_r2757 = load ptr, ptr %fbip_slot2753
  store ptr %fbip_r2757, ptr %res_slot2747
  br label %case_merge595
case_br598:
  %fp2758 = getelementptr i8, ptr %ld2746, i64 16
  %fv2759 = load ptr, ptr %fp2758, align 8
  %$f940.addr = alloca ptr
  store ptr %fv2759, ptr %$f940.addr
  %fp2760 = getelementptr i8, ptr %ld2746, i64 24
  %fv2761 = load ptr, ptr %fp2760, align 8
  %$f941.addr = alloca ptr
  store ptr %fv2761, ptr %$f941.addr
  %freed2762 = call i64 @march_decrc_freed(ptr %ld2746)
  %freed_b2763 = icmp ne i64 %freed2762, 0
  br i1 %freed_b2763, label %br_unique602, label %br_shared603
br_shared603:
  call void @march_incrc(ptr %fv2761)
  call void @march_incrc(ptr %fv2759)
  br label %br_body604
br_unique602:
  br label %br_body604
br_body604:
  %ld2764 = load ptr, ptr %$f940.addr
  %res_slot2765 = alloca ptr
  %tgp2766 = getelementptr i8, ptr %ld2764, i64 8
  %tag2767 = load i32, ptr %tgp2766, align 4
  switch i32 %tag2767, label %case_default606 [
      i32 0, label %case_br607
  ]
case_br607:
  %fp2768 = getelementptr i8, ptr %ld2764, i64 16
  %fv2769 = load ptr, ptr %fp2768, align 8
  %$f942.addr = alloca ptr
  store ptr %fv2769, ptr %$f942.addr
  %fp2770 = getelementptr i8, ptr %ld2764, i64 24
  %fv2771 = load ptr, ptr %fp2770, align 8
  %$f943.addr = alloca ptr
  store ptr %fv2771, ptr %$f943.addr
  %freed2772 = call i64 @march_decrc_freed(ptr %ld2764)
  %freed_b2773 = icmp ne i64 %freed2772, 0
  br i1 %freed_b2773, label %br_unique608, label %br_shared609
br_shared609:
  call void @march_incrc(ptr %fv2771)
  call void @march_incrc(ptr %fv2769)
  br label %br_body610
br_unique608:
  br label %br_body610
br_body610:
  %ld2774 = load ptr, ptr %$f941.addr
  %rest.addr = alloca ptr
  store ptr %ld2774, ptr %rest.addr
  %ld2775 = load ptr, ptr %$f942.addr
  %n.addr = alloca ptr
  store ptr %ld2775, ptr %n.addr
  %sl2776 = call ptr @march_string_lit(ptr @.str67, i64 6)
  %ld2777 = load ptr, ptr %n.addr
  %cr2778 = call ptr @march_string_concat(ptr %sl2776, ptr %ld2777)
  %$t938.addr = alloca ptr
  store ptr %cr2778, ptr %$t938.addr
  %ld2779 = load ptr, ptr %err_names.addr
  %fp2780 = getelementptr i8, ptr %ld2779, i64 16
  %fv2781 = load ptr, ptr %fp2780, align 8
  %ld2782 = load ptr, ptr %rest.addr
  %cr2783 = call ptr (ptr, ptr) %fv2781(ptr %ld2779, ptr %ld2782)
  %$t939.addr = alloca ptr
  store ptr %cr2783, ptr %$t939.addr
  %hp2784 = call ptr @march_alloc(i64 32)
  %tgp2785 = getelementptr i8, ptr %hp2784, i64 8
  store i32 1, ptr %tgp2785, align 4
  %ld2786 = load ptr, ptr %$t938.addr
  %fp2787 = getelementptr i8, ptr %hp2784, i64 16
  store ptr %ld2786, ptr %fp2787, align 8
  %ld2788 = load ptr, ptr %$t939.addr
  %fp2789 = getelementptr i8, ptr %hp2784, i64 24
  store ptr %ld2788, ptr %fp2789, align 8
  store ptr %hp2784, ptr %res_slot2765
  br label %case_merge605
case_default606:
  unreachable
case_merge605:
  %case_r2790 = load ptr, ptr %res_slot2765
  store ptr %case_r2790, ptr %res_slot2747
  br label %case_merge595
case_default596:
  unreachable
case_merge595:
  %case_r2791 = load ptr, ptr %res_slot2747
  ret ptr %case_r2791
}

define ptr @show_steps$apply$22(ptr %$clo.arg, ptr %xs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld2792 = load ptr, ptr %$clo.addr
  %show_steps.addr = alloca ptr
  store ptr %ld2792, ptr %show_steps.addr
  %ld2793 = load ptr, ptr %xs.addr
  %res_slot2794 = alloca ptr
  %tgp2795 = getelementptr i8, ptr %ld2793, i64 8
  %tag2796 = load i32, ptr %tgp2795, align 4
  switch i32 %tag2796, label %case_default612 [
      i32 0, label %case_br613
      i32 1, label %case_br614
  ]
case_br613:
  %ld2797 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld2797)
  %sl2798 = call ptr @march_string_lit(ptr @.str68, i64 4)
  store ptr %sl2798, ptr %res_slot2794
  br label %case_merge611
case_br614:
  %fp2799 = getelementptr i8, ptr %ld2793, i64 16
  %fv2800 = load ptr, ptr %fp2799, align 8
  %$f2020.addr = alloca ptr
  store ptr %fv2800, ptr %$f2020.addr
  %fp2801 = getelementptr i8, ptr %ld2793, i64 24
  %fv2802 = load ptr, ptr %fp2801, align 8
  %$f2021.addr = alloca ptr
  store ptr %fv2802, ptr %$f2021.addr
  %freed2803 = call i64 @march_decrc_freed(ptr %ld2793)
  %freed_b2804 = icmp ne i64 %freed2803, 0
  br i1 %freed_b2804, label %br_unique615, label %br_shared616
br_shared616:
  call void @march_incrc(ptr %fv2802)
  call void @march_incrc(ptr %fv2800)
  br label %br_body617
br_unique615:
  br label %br_body617
br_body617:
  %ld2805 = load ptr, ptr %$f2021.addr
  %t.addr = alloca ptr
  store ptr %ld2805, ptr %t.addr
  %ld2806 = load ptr, ptr %$f2020.addr
  %h.addr = alloca ptr
  store ptr %ld2806, ptr %h.addr
  %sl2807 = call ptr @march_string_lit(ptr @.str69, i64 4)
  %ld2808 = load ptr, ptr %h.addr
  %cr2809 = call ptr @march_string_concat(ptr %sl2807, ptr %ld2808)
  %$t2019.addr = alloca ptr
  store ptr %cr2809, ptr %$t2019.addr
  %ld2810 = load ptr, ptr %$t2019.addr
  call void @march_print(ptr %ld2810)
  %ld2811 = load ptr, ptr %show_steps.addr
  %fp2812 = getelementptr i8, ptr %ld2811, i64 16
  %fv2813 = load ptr, ptr %fp2812, align 8
  %ld2814 = load ptr, ptr %t.addr
  %cr2815 = call ptr (ptr, ptr) %fv2813(ptr %ld2811, ptr %ld2814)
  store ptr %cr2815, ptr %res_slot2794
  br label %case_merge611
case_default612:
  unreachable
case_merge611:
  %case_r2816 = load ptr, ptr %res_slot2794
  ret ptr %case_r2816
}

define ptr @find$apply$26(ptr %$clo.arg, ptr %hs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %hs.addr = alloca ptr
  store ptr %hs.arg, ptr %hs.addr
  %ld2817 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld2817)
  %ld2818 = load ptr, ptr %$clo.addr
  %find.addr = alloca ptr
  store ptr %ld2818, ptr %find.addr
  %ld2819 = load ptr, ptr %$clo.addr
  %fp2820 = getelementptr i8, ptr %ld2819, i64 24
  %fv2821 = load ptr, ptr %fp2820, align 8
  %lower_name.addr = alloca ptr
  store ptr %fv2821, ptr %lower_name.addr
  %ld2822 = load ptr, ptr %hs.addr
  %res_slot2823 = alloca ptr
  %tgp2824 = getelementptr i8, ptr %ld2822, i64 8
  %tag2825 = load i32, ptr %tgp2824, align 4
  switch i32 %tag2825, label %case_default619 [
      i32 0, label %case_br620
      i32 1, label %case_br621
  ]
case_br620:
  %ld2826 = load ptr, ptr %hs.addr
  call void @march_decrc(ptr %ld2826)
  %hp2827 = call ptr @march_alloc(i64 16)
  %tgp2828 = getelementptr i8, ptr %hp2827, i64 8
  store i32 0, ptr %tgp2828, align 4
  store ptr %hp2827, ptr %res_slot2823
  br label %case_merge618
case_br621:
  %fp2829 = getelementptr i8, ptr %ld2822, i64 16
  %fv2830 = load ptr, ptr %fp2829, align 8
  %$f680.addr = alloca ptr
  store ptr %fv2830, ptr %$f680.addr
  %fp2831 = getelementptr i8, ptr %ld2822, i64 24
  %fv2832 = load ptr, ptr %fp2831, align 8
  %$f681.addr = alloca ptr
  store ptr %fv2832, ptr %$f681.addr
  %freed2833 = call i64 @march_decrc_freed(ptr %ld2822)
  %freed_b2834 = icmp ne i64 %freed2833, 0
  br i1 %freed_b2834, label %br_unique622, label %br_shared623
br_shared623:
  call void @march_incrc(ptr %fv2832)
  call void @march_incrc(ptr %fv2830)
  br label %br_body624
br_unique622:
  br label %br_body624
br_body624:
  %ld2835 = load ptr, ptr %$f680.addr
  %res_slot2836 = alloca ptr
  %tgp2837 = getelementptr i8, ptr %ld2835, i64 8
  %tag2838 = load i32, ptr %tgp2837, align 4
  switch i32 %tag2838, label %case_default626 [
      i32 0, label %case_br627
  ]
case_br627:
  %fp2839 = getelementptr i8, ptr %ld2835, i64 16
  %fv2840 = load ptr, ptr %fp2839, align 8
  %$f682.addr = alloca ptr
  store ptr %fv2840, ptr %$f682.addr
  %fp2841 = getelementptr i8, ptr %ld2835, i64 24
  %fv2842 = load ptr, ptr %fp2841, align 8
  %$f683.addr = alloca ptr
  store ptr %fv2842, ptr %$f683.addr
  %freed2843 = call i64 @march_decrc_freed(ptr %ld2835)
  %freed_b2844 = icmp ne i64 %freed2843, 0
  br i1 %freed_b2844, label %br_unique628, label %br_shared629
br_shared629:
  call void @march_incrc(ptr %fv2842)
  call void @march_incrc(ptr %fv2840)
  br label %br_body630
br_unique628:
  br label %br_body630
br_body630:
  %ld2845 = load ptr, ptr %$f681.addr
  %rest.addr = alloca ptr
  store ptr %ld2845, ptr %rest.addr
  %ld2846 = load ptr, ptr %$f683.addr
  %v.addr = alloca ptr
  store ptr %ld2846, ptr %v.addr
  %ld2847 = load ptr, ptr %$f682.addr
  %n.addr = alloca ptr
  store ptr %ld2847, ptr %n.addr
  %ld2848 = load ptr, ptr %n.addr
  %cr2849 = call ptr @march_string_to_lowercase(ptr %ld2848)
  %$t678.addr = alloca ptr
  store ptr %cr2849, ptr %$t678.addr
  %ld2850 = load ptr, ptr %$t678.addr
  %ld2851 = load ptr, ptr %lower_name.addr
  %cr2852 = call i64 @march_string_eq(ptr %ld2850, ptr %ld2851)
  %$t679.addr = alloca i64
  store i64 %cr2852, ptr %$t679.addr
  %ld2853 = load i64, ptr %$t679.addr
  %res_slot2854 = alloca ptr
  %bi2855 = trunc i64 %ld2853 to i1
  br i1 %bi2855, label %case_br633, label %case_default632
case_br633:
  %hp2856 = call ptr @march_alloc(i64 24)
  %tgp2857 = getelementptr i8, ptr %hp2856, i64 8
  store i32 1, ptr %tgp2857, align 4
  %ld2858 = load ptr, ptr %v.addr
  %fp2859 = getelementptr i8, ptr %hp2856, i64 16
  store ptr %ld2858, ptr %fp2859, align 8
  store ptr %hp2856, ptr %res_slot2854
  br label %case_merge631
case_default632:
  %ld2860 = load ptr, ptr %find.addr
  %fp2861 = getelementptr i8, ptr %ld2860, i64 16
  %fv2862 = load ptr, ptr %fp2861, align 8
  %ld2863 = load ptr, ptr %rest.addr
  %cr2864 = call ptr (ptr, ptr) %fv2862(ptr %ld2860, ptr %ld2863)
  store ptr %cr2864, ptr %res_slot2854
  br label %case_merge631
case_merge631:
  %case_r2865 = load ptr, ptr %res_slot2854
  store ptr %case_r2865, ptr %res_slot2836
  br label %case_merge625
case_default626:
  unreachable
case_merge625:
  %case_r2866 = load ptr, ptr %res_slot2836
  store ptr %case_r2866, ptr %res_slot2823
  br label %case_merge618
case_default619:
  unreachable
case_merge618:
  %case_r2867 = load ptr, ptr %res_slot2823
  ret ptr %case_r2867
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

