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
@.str10 = private unnamed_addr constant [40 x i8] c"Counter server on http://localhost:8080\00"
@.str11 = private unnamed_addr constant [33 x i8] c"  GET  /count     - read counter\00"
@.str12 = private unnamed_addr constant [33 x i8] c"  POST /increment - add N (body)\00"
@.str13 = private unnamed_addr constant [38 x i8] c"  POST /decrement - subtract N (body)\00"
@.str14 = private unnamed_addr constant [4 x i8] c"GET\00"
@.str15 = private unnamed_addr constant [7 x i8] c"/count\00"
@.str16 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str17 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str18 = private unnamed_addr constant [10 x i8] c"Not Found\00"
@.str19 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str20 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str21 = private unnamed_addr constant [5 x i8] c"POST\00"
@.str22 = private unnamed_addr constant [19 x i8] c"Method Not Allowed\00"
@.str23 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str24 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str25 = private unnamed_addr constant [37 x i8] c"Bad Request: body must be an integer\00"
@.str26 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str27 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str28 = private unnamed_addr constant [11 x i8] c"/increment\00"
@.str29 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str30 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str31 = private unnamed_addr constant [11 x i8] c"/decrement\00"
@.str32 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str33 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str34 = private unnamed_addr constant [10 x i8] c"Not Found\00"
@.str35 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str36 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"

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

define ptr @HttpServer.method(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld30 = load ptr, ptr %conn.addr
  %res_slot31 = alloca ptr
  %tgp32 = getelementptr i8, ptr %ld30, i64 8
  %tag33 = load i32, ptr %tgp32, align 4
  switch i32 %tag33, label %case_default17 [
      i32 0, label %case_br18
  ]
case_br18:
  %fp34 = getelementptr i8, ptr %ld30, i64 16
  %fv35 = load i64, ptr %fp34, align 8
  %$f1742.addr = alloca i64
  store i64 %fv35, ptr %$f1742.addr
  %fp36 = getelementptr i8, ptr %ld30, i64 24
  %fv37 = load ptr, ptr %fp36, align 8
  %$f1743.addr = alloca ptr
  store ptr %fv37, ptr %$f1743.addr
  %fp38 = getelementptr i8, ptr %ld30, i64 32
  %fv39 = load ptr, ptr %fp38, align 8
  %$f1744.addr = alloca ptr
  store ptr %fv39, ptr %$f1744.addr
  %fp40 = getelementptr i8, ptr %ld30, i64 40
  %fv41 = load ptr, ptr %fp40, align 8
  %$f1745.addr = alloca ptr
  store ptr %fv41, ptr %$f1745.addr
  %fp42 = getelementptr i8, ptr %ld30, i64 48
  %fv43 = load ptr, ptr %fp42, align 8
  %$f1746.addr = alloca ptr
  store ptr %fv43, ptr %$f1746.addr
  %fp44 = getelementptr i8, ptr %ld30, i64 56
  %fv45 = load ptr, ptr %fp44, align 8
  %$f1747.addr = alloca ptr
  store ptr %fv45, ptr %$f1747.addr
  %fp46 = getelementptr i8, ptr %ld30, i64 64
  %fv47 = load ptr, ptr %fp46, align 8
  %$f1748.addr = alloca ptr
  store ptr %fv47, ptr %$f1748.addr
  %fp48 = getelementptr i8, ptr %ld30, i64 72
  %fv49 = load i64, ptr %fp48, align 8
  %$f1749.addr = alloca i64
  store i64 %fv49, ptr %$f1749.addr
  %fp50 = getelementptr i8, ptr %ld30, i64 80
  %fv51 = load ptr, ptr %fp50, align 8
  %$f1750.addr = alloca ptr
  store ptr %fv51, ptr %$f1750.addr
  %fp52 = getelementptr i8, ptr %ld30, i64 88
  %fv53 = load ptr, ptr %fp52, align 8
  %$f1751.addr = alloca ptr
  store ptr %fv53, ptr %$f1751.addr
  %fp54 = getelementptr i8, ptr %ld30, i64 96
  %fv55 = load i64, ptr %fp54, align 8
  %$f1752.addr = alloca i64
  store i64 %fv55, ptr %$f1752.addr
  %fp56 = getelementptr i8, ptr %ld30, i64 104
  %fv57 = load ptr, ptr %fp56, align 8
  %$f1753.addr = alloca ptr
  store ptr %fv57, ptr %$f1753.addr
  %fp58 = getelementptr i8, ptr %ld30, i64 112
  %fv59 = load ptr, ptr %fp58, align 8
  %$f1754.addr = alloca ptr
  store ptr %fv59, ptr %$f1754.addr
  %freed60 = call i64 @march_decrc_freed(ptr %ld30)
  %freed_b61 = icmp ne i64 %freed60, 0
  br i1 %freed_b61, label %br_unique19, label %br_shared20
br_shared20:
  call void @march_incrc(ptr %fv59)
  call void @march_incrc(ptr %fv57)
  call void @march_incrc(ptr %fv53)
  call void @march_incrc(ptr %fv51)
  call void @march_incrc(ptr %fv47)
  call void @march_incrc(ptr %fv45)
  call void @march_incrc(ptr %fv43)
  call void @march_incrc(ptr %fv41)
  call void @march_incrc(ptr %fv39)
  call void @march_incrc(ptr %fv37)
  br label %br_body21
br_unique19:
  br label %br_body21
br_body21:
  %ld62 = load ptr, ptr %$f1743.addr
  %m.addr = alloca ptr
  store ptr %ld62, ptr %m.addr
  %ld63 = load ptr, ptr %m.addr
  store ptr %ld63, ptr %res_slot31
  br label %case_merge16
case_default17:
  unreachable
case_merge16:
  %case_r64 = load ptr, ptr %res_slot31
  ret ptr %case_r64
}

define ptr @HttpServer.path(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld65 = load ptr, ptr %conn.addr
  %res_slot66 = alloca ptr
  %tgp67 = getelementptr i8, ptr %ld65, i64 8
  %tag68 = load i32, ptr %tgp67, align 4
  switch i32 %tag68, label %case_default23 [
      i32 0, label %case_br24
  ]
case_br24:
  %fp69 = getelementptr i8, ptr %ld65, i64 16
  %fv70 = load i64, ptr %fp69, align 8
  %$f1755.addr = alloca i64
  store i64 %fv70, ptr %$f1755.addr
  %fp71 = getelementptr i8, ptr %ld65, i64 24
  %fv72 = load ptr, ptr %fp71, align 8
  %$f1756.addr = alloca ptr
  store ptr %fv72, ptr %$f1756.addr
  %fp73 = getelementptr i8, ptr %ld65, i64 32
  %fv74 = load ptr, ptr %fp73, align 8
  %$f1757.addr = alloca ptr
  store ptr %fv74, ptr %$f1757.addr
  %fp75 = getelementptr i8, ptr %ld65, i64 40
  %fv76 = load ptr, ptr %fp75, align 8
  %$f1758.addr = alloca ptr
  store ptr %fv76, ptr %$f1758.addr
  %fp77 = getelementptr i8, ptr %ld65, i64 48
  %fv78 = load ptr, ptr %fp77, align 8
  %$f1759.addr = alloca ptr
  store ptr %fv78, ptr %$f1759.addr
  %fp79 = getelementptr i8, ptr %ld65, i64 56
  %fv80 = load ptr, ptr %fp79, align 8
  %$f1760.addr = alloca ptr
  store ptr %fv80, ptr %$f1760.addr
  %fp81 = getelementptr i8, ptr %ld65, i64 64
  %fv82 = load ptr, ptr %fp81, align 8
  %$f1761.addr = alloca ptr
  store ptr %fv82, ptr %$f1761.addr
  %fp83 = getelementptr i8, ptr %ld65, i64 72
  %fv84 = load i64, ptr %fp83, align 8
  %$f1762.addr = alloca i64
  store i64 %fv84, ptr %$f1762.addr
  %fp85 = getelementptr i8, ptr %ld65, i64 80
  %fv86 = load ptr, ptr %fp85, align 8
  %$f1763.addr = alloca ptr
  store ptr %fv86, ptr %$f1763.addr
  %fp87 = getelementptr i8, ptr %ld65, i64 88
  %fv88 = load ptr, ptr %fp87, align 8
  %$f1764.addr = alloca ptr
  store ptr %fv88, ptr %$f1764.addr
  %fp89 = getelementptr i8, ptr %ld65, i64 96
  %fv90 = load i64, ptr %fp89, align 8
  %$f1765.addr = alloca i64
  store i64 %fv90, ptr %$f1765.addr
  %fp91 = getelementptr i8, ptr %ld65, i64 104
  %fv92 = load ptr, ptr %fp91, align 8
  %$f1766.addr = alloca ptr
  store ptr %fv92, ptr %$f1766.addr
  %fp93 = getelementptr i8, ptr %ld65, i64 112
  %fv94 = load ptr, ptr %fp93, align 8
  %$f1767.addr = alloca ptr
  store ptr %fv94, ptr %$f1767.addr
  %freed95 = call i64 @march_decrc_freed(ptr %ld65)
  %freed_b96 = icmp ne i64 %freed95, 0
  br i1 %freed_b96, label %br_unique25, label %br_shared26
br_shared26:
  call void @march_incrc(ptr %fv94)
  call void @march_incrc(ptr %fv92)
  call void @march_incrc(ptr %fv88)
  call void @march_incrc(ptr %fv86)
  call void @march_incrc(ptr %fv82)
  call void @march_incrc(ptr %fv80)
  call void @march_incrc(ptr %fv78)
  call void @march_incrc(ptr %fv76)
  call void @march_incrc(ptr %fv74)
  call void @march_incrc(ptr %fv72)
  br label %br_body27
br_unique25:
  br label %br_body27
br_body27:
  %ld97 = load ptr, ptr %$f1757.addr
  %p.addr = alloca ptr
  store ptr %ld97, ptr %p.addr
  %ld98 = load ptr, ptr %p.addr
  store ptr %ld98, ptr %res_slot66
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r99 = load ptr, ptr %res_slot66
  ret ptr %case_r99
}

define ptr @HttpServer.req_body(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld100 = load ptr, ptr %conn.addr
  %res_slot101 = alloca ptr
  %tgp102 = getelementptr i8, ptr %ld100, i64 8
  %tag103 = load i32, ptr %tgp102, align 4
  switch i32 %tag103, label %case_default29 [
      i32 0, label %case_br30
  ]
case_br30:
  %fp104 = getelementptr i8, ptr %ld100, i64 16
  %fv105 = load i64, ptr %fp104, align 8
  %$f1807.addr = alloca i64
  store i64 %fv105, ptr %$f1807.addr
  %fp106 = getelementptr i8, ptr %ld100, i64 24
  %fv107 = load ptr, ptr %fp106, align 8
  %$f1808.addr = alloca ptr
  store ptr %fv107, ptr %$f1808.addr
  %fp108 = getelementptr i8, ptr %ld100, i64 32
  %fv109 = load ptr, ptr %fp108, align 8
  %$f1809.addr = alloca ptr
  store ptr %fv109, ptr %$f1809.addr
  %fp110 = getelementptr i8, ptr %ld100, i64 40
  %fv111 = load ptr, ptr %fp110, align 8
  %$f1810.addr = alloca ptr
  store ptr %fv111, ptr %$f1810.addr
  %fp112 = getelementptr i8, ptr %ld100, i64 48
  %fv113 = load ptr, ptr %fp112, align 8
  %$f1811.addr = alloca ptr
  store ptr %fv113, ptr %$f1811.addr
  %fp114 = getelementptr i8, ptr %ld100, i64 56
  %fv115 = load ptr, ptr %fp114, align 8
  %$f1812.addr = alloca ptr
  store ptr %fv115, ptr %$f1812.addr
  %fp116 = getelementptr i8, ptr %ld100, i64 64
  %fv117 = load ptr, ptr %fp116, align 8
  %$f1813.addr = alloca ptr
  store ptr %fv117, ptr %$f1813.addr
  %fp118 = getelementptr i8, ptr %ld100, i64 72
  %fv119 = load i64, ptr %fp118, align 8
  %$f1814.addr = alloca i64
  store i64 %fv119, ptr %$f1814.addr
  %fp120 = getelementptr i8, ptr %ld100, i64 80
  %fv121 = load ptr, ptr %fp120, align 8
  %$f1815.addr = alloca ptr
  store ptr %fv121, ptr %$f1815.addr
  %fp122 = getelementptr i8, ptr %ld100, i64 88
  %fv123 = load ptr, ptr %fp122, align 8
  %$f1816.addr = alloca ptr
  store ptr %fv123, ptr %$f1816.addr
  %fp124 = getelementptr i8, ptr %ld100, i64 96
  %fv125 = load i64, ptr %fp124, align 8
  %$f1817.addr = alloca i64
  store i64 %fv125, ptr %$f1817.addr
  %fp126 = getelementptr i8, ptr %ld100, i64 104
  %fv127 = load ptr, ptr %fp126, align 8
  %$f1818.addr = alloca ptr
  store ptr %fv127, ptr %$f1818.addr
  %fp128 = getelementptr i8, ptr %ld100, i64 112
  %fv129 = load ptr, ptr %fp128, align 8
  %$f1819.addr = alloca ptr
  store ptr %fv129, ptr %$f1819.addr
  %freed130 = call i64 @march_decrc_freed(ptr %ld100)
  %freed_b131 = icmp ne i64 %freed130, 0
  br i1 %freed_b131, label %br_unique31, label %br_shared32
br_shared32:
  call void @march_incrc(ptr %fv129)
  call void @march_incrc(ptr %fv127)
  call void @march_incrc(ptr %fv123)
  call void @march_incrc(ptr %fv121)
  call void @march_incrc(ptr %fv117)
  call void @march_incrc(ptr %fv115)
  call void @march_incrc(ptr %fv113)
  call void @march_incrc(ptr %fv111)
  call void @march_incrc(ptr %fv109)
  call void @march_incrc(ptr %fv107)
  br label %br_body33
br_unique31:
  br label %br_body33
br_body33:
  %ld132 = load ptr, ptr %$f1813.addr
  %rb.addr = alloca ptr
  store ptr %ld132, ptr %rb.addr
  %ld133 = load ptr, ptr %rb.addr
  store ptr %ld133, ptr %res_slot101
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r134 = load ptr, ptr %res_slot101
  ret ptr %case_r134
}

define i64 @HttpServer.halted(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld135 = load ptr, ptr %conn.addr
  %res_slot136 = alloca ptr
  %tgp137 = getelementptr i8, ptr %ld135, i64 8
  %tag138 = load i32, ptr %tgp137, align 4
  switch i32 %tag138, label %case_default35 [
      i32 0, label %case_br36
  ]
case_br36:
  %fp139 = getelementptr i8, ptr %ld135, i64 16
  %fv140 = load i64, ptr %fp139, align 8
  %$f1859.addr = alloca i64
  store i64 %fv140, ptr %$f1859.addr
  %fp141 = getelementptr i8, ptr %ld135, i64 24
  %fv142 = load ptr, ptr %fp141, align 8
  %$f1860.addr = alloca ptr
  store ptr %fv142, ptr %$f1860.addr
  %fp143 = getelementptr i8, ptr %ld135, i64 32
  %fv144 = load ptr, ptr %fp143, align 8
  %$f1861.addr = alloca ptr
  store ptr %fv144, ptr %$f1861.addr
  %fp145 = getelementptr i8, ptr %ld135, i64 40
  %fv146 = load ptr, ptr %fp145, align 8
  %$f1862.addr = alloca ptr
  store ptr %fv146, ptr %$f1862.addr
  %fp147 = getelementptr i8, ptr %ld135, i64 48
  %fv148 = load ptr, ptr %fp147, align 8
  %$f1863.addr = alloca ptr
  store ptr %fv148, ptr %$f1863.addr
  %fp149 = getelementptr i8, ptr %ld135, i64 56
  %fv150 = load ptr, ptr %fp149, align 8
  %$f1864.addr = alloca ptr
  store ptr %fv150, ptr %$f1864.addr
  %fp151 = getelementptr i8, ptr %ld135, i64 64
  %fv152 = load ptr, ptr %fp151, align 8
  %$f1865.addr = alloca ptr
  store ptr %fv152, ptr %$f1865.addr
  %fp153 = getelementptr i8, ptr %ld135, i64 72
  %fv154 = load i64, ptr %fp153, align 8
  %$f1866.addr = alloca i64
  store i64 %fv154, ptr %$f1866.addr
  %fp155 = getelementptr i8, ptr %ld135, i64 80
  %fv156 = load ptr, ptr %fp155, align 8
  %$f1867.addr = alloca ptr
  store ptr %fv156, ptr %$f1867.addr
  %fp157 = getelementptr i8, ptr %ld135, i64 88
  %fv158 = load ptr, ptr %fp157, align 8
  %$f1868.addr = alloca ptr
  store ptr %fv158, ptr %$f1868.addr
  %fp159 = getelementptr i8, ptr %ld135, i64 96
  %fv160 = load i64, ptr %fp159, align 8
  %$f1869.addr = alloca i64
  store i64 %fv160, ptr %$f1869.addr
  %fp161 = getelementptr i8, ptr %ld135, i64 104
  %fv162 = load ptr, ptr %fp161, align 8
  %$f1870.addr = alloca ptr
  store ptr %fv162, ptr %$f1870.addr
  %fp163 = getelementptr i8, ptr %ld135, i64 112
  %fv164 = load ptr, ptr %fp163, align 8
  %$f1871.addr = alloca ptr
  store ptr %fv164, ptr %$f1871.addr
  %freed165 = call i64 @march_decrc_freed(ptr %ld135)
  %freed_b166 = icmp ne i64 %freed165, 0
  br i1 %freed_b166, label %br_unique37, label %br_shared38
br_shared38:
  call void @march_incrc(ptr %fv164)
  call void @march_incrc(ptr %fv162)
  call void @march_incrc(ptr %fv158)
  call void @march_incrc(ptr %fv156)
  call void @march_incrc(ptr %fv152)
  call void @march_incrc(ptr %fv150)
  call void @march_incrc(ptr %fv148)
  call void @march_incrc(ptr %fv146)
  call void @march_incrc(ptr %fv144)
  call void @march_incrc(ptr %fv142)
  br label %br_body39
br_unique37:
  br label %br_body39
br_body39:
  %ld167 = load i64, ptr %$f1869.addr
  %h.addr = alloca i64
  store i64 %ld167, ptr %h.addr
  %ld168 = load i64, ptr %h.addr
  %cv169 = inttoptr i64 %ld168 to ptr
  store ptr %cv169, ptr %res_slot136
  br label %case_merge34
case_default35:
  unreachable
case_merge34:
  %case_r170 = load ptr, ptr %res_slot136
  %cv171 = ptrtoint ptr %case_r170 to i64
  ret i64 %cv171
}

define i64 @HttpServer.fd(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld172 = load ptr, ptr %conn.addr
  %res_slot173 = alloca ptr
  %tgp174 = getelementptr i8, ptr %ld172, i64 8
  %tag175 = load i32, ptr %tgp174, align 4
  switch i32 %tag175, label %case_default41 [
      i32 0, label %case_br42
  ]
case_br42:
  %fp176 = getelementptr i8, ptr %ld172, i64 16
  %fv177 = load i64, ptr %fp176, align 8
  %$f1898.addr = alloca i64
  store i64 %fv177, ptr %$f1898.addr
  %fp178 = getelementptr i8, ptr %ld172, i64 24
  %fv179 = load ptr, ptr %fp178, align 8
  %$f1899.addr = alloca ptr
  store ptr %fv179, ptr %$f1899.addr
  %fp180 = getelementptr i8, ptr %ld172, i64 32
  %fv181 = load ptr, ptr %fp180, align 8
  %$f1900.addr = alloca ptr
  store ptr %fv181, ptr %$f1900.addr
  %fp182 = getelementptr i8, ptr %ld172, i64 40
  %fv183 = load ptr, ptr %fp182, align 8
  %$f1901.addr = alloca ptr
  store ptr %fv183, ptr %$f1901.addr
  %fp184 = getelementptr i8, ptr %ld172, i64 48
  %fv185 = load ptr, ptr %fp184, align 8
  %$f1902.addr = alloca ptr
  store ptr %fv185, ptr %$f1902.addr
  %fp186 = getelementptr i8, ptr %ld172, i64 56
  %fv187 = load ptr, ptr %fp186, align 8
  %$f1903.addr = alloca ptr
  store ptr %fv187, ptr %$f1903.addr
  %fp188 = getelementptr i8, ptr %ld172, i64 64
  %fv189 = load ptr, ptr %fp188, align 8
  %$f1904.addr = alloca ptr
  store ptr %fv189, ptr %$f1904.addr
  %fp190 = getelementptr i8, ptr %ld172, i64 72
  %fv191 = load i64, ptr %fp190, align 8
  %$f1905.addr = alloca i64
  store i64 %fv191, ptr %$f1905.addr
  %fp192 = getelementptr i8, ptr %ld172, i64 80
  %fv193 = load ptr, ptr %fp192, align 8
  %$f1906.addr = alloca ptr
  store ptr %fv193, ptr %$f1906.addr
  %fp194 = getelementptr i8, ptr %ld172, i64 88
  %fv195 = load ptr, ptr %fp194, align 8
  %$f1907.addr = alloca ptr
  store ptr %fv195, ptr %$f1907.addr
  %fp196 = getelementptr i8, ptr %ld172, i64 96
  %fv197 = load i64, ptr %fp196, align 8
  %$f1908.addr = alloca i64
  store i64 %fv197, ptr %$f1908.addr
  %fp198 = getelementptr i8, ptr %ld172, i64 104
  %fv199 = load ptr, ptr %fp198, align 8
  %$f1909.addr = alloca ptr
  store ptr %fv199, ptr %$f1909.addr
  %fp200 = getelementptr i8, ptr %ld172, i64 112
  %fv201 = load ptr, ptr %fp200, align 8
  %$f1910.addr = alloca ptr
  store ptr %fv201, ptr %$f1910.addr
  %freed202 = call i64 @march_decrc_freed(ptr %ld172)
  %freed_b203 = icmp ne i64 %freed202, 0
  br i1 %freed_b203, label %br_unique43, label %br_shared44
br_shared44:
  call void @march_incrc(ptr %fv201)
  call void @march_incrc(ptr %fv199)
  call void @march_incrc(ptr %fv195)
  call void @march_incrc(ptr %fv193)
  call void @march_incrc(ptr %fv189)
  call void @march_incrc(ptr %fv187)
  call void @march_incrc(ptr %fv185)
  call void @march_incrc(ptr %fv183)
  call void @march_incrc(ptr %fv181)
  call void @march_incrc(ptr %fv179)
  br label %br_body45
br_unique43:
  br label %br_body45
br_body45:
  %ld204 = load i64, ptr %$f1898.addr
  %f.addr = alloca i64
  store i64 %ld204, ptr %f.addr
  %ld205 = load i64, ptr %f.addr
  %cv206 = inttoptr i64 %ld205 to ptr
  store ptr %cv206, ptr %res_slot173
  br label %case_merge40
case_default41:
  unreachable
case_merge40:
  %case_r207 = load ptr, ptr %res_slot173
  %cv208 = ptrtoint ptr %case_r207 to i64
  ret i64 %cv208
}

define ptr @HttpServer.put_resp_header(ptr %conn.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld209 = load ptr, ptr %conn.addr
  %res_slot210 = alloca ptr
  %tgp211 = getelementptr i8, ptr %ld209, i64 8
  %tag212 = load i32, ptr %tgp211, align 4
  switch i32 %tag212, label %case_default47 [
      i32 0, label %case_br48
  ]
case_br48:
  %fp213 = getelementptr i8, ptr %ld209, i64 16
  %fv214 = load i64, ptr %fp213, align 8
  %$f1926.addr = alloca i64
  store i64 %fv214, ptr %$f1926.addr
  %fp215 = getelementptr i8, ptr %ld209, i64 24
  %fv216 = load ptr, ptr %fp215, align 8
  %$f1927.addr = alloca ptr
  store ptr %fv216, ptr %$f1927.addr
  %fp217 = getelementptr i8, ptr %ld209, i64 32
  %fv218 = load ptr, ptr %fp217, align 8
  %$f1928.addr = alloca ptr
  store ptr %fv218, ptr %$f1928.addr
  %fp219 = getelementptr i8, ptr %ld209, i64 40
  %fv220 = load ptr, ptr %fp219, align 8
  %$f1929.addr = alloca ptr
  store ptr %fv220, ptr %$f1929.addr
  %fp221 = getelementptr i8, ptr %ld209, i64 48
  %fv222 = load ptr, ptr %fp221, align 8
  %$f1930.addr = alloca ptr
  store ptr %fv222, ptr %$f1930.addr
  %fp223 = getelementptr i8, ptr %ld209, i64 56
  %fv224 = load ptr, ptr %fp223, align 8
  %$f1931.addr = alloca ptr
  store ptr %fv224, ptr %$f1931.addr
  %fp225 = getelementptr i8, ptr %ld209, i64 64
  %fv226 = load ptr, ptr %fp225, align 8
  %$f1932.addr = alloca ptr
  store ptr %fv226, ptr %$f1932.addr
  %fp227 = getelementptr i8, ptr %ld209, i64 72
  %fv228 = load i64, ptr %fp227, align 8
  %$f1933.addr = alloca i64
  store i64 %fv228, ptr %$f1933.addr
  %fp229 = getelementptr i8, ptr %ld209, i64 80
  %fv230 = load ptr, ptr %fp229, align 8
  %$f1934.addr = alloca ptr
  store ptr %fv230, ptr %$f1934.addr
  %fp231 = getelementptr i8, ptr %ld209, i64 88
  %fv232 = load ptr, ptr %fp231, align 8
  %$f1935.addr = alloca ptr
  store ptr %fv232, ptr %$f1935.addr
  %fp233 = getelementptr i8, ptr %ld209, i64 96
  %fv234 = load i64, ptr %fp233, align 8
  %$f1936.addr = alloca i64
  store i64 %fv234, ptr %$f1936.addr
  %fp235 = getelementptr i8, ptr %ld209, i64 104
  %fv236 = load ptr, ptr %fp235, align 8
  %$f1937.addr = alloca ptr
  store ptr %fv236, ptr %$f1937.addr
  %fp237 = getelementptr i8, ptr %ld209, i64 112
  %fv238 = load ptr, ptr %fp237, align 8
  %$f1938.addr = alloca ptr
  store ptr %fv238, ptr %$f1938.addr
  %freed239 = call i64 @march_decrc_freed(ptr %ld209)
  %freed_b240 = icmp ne i64 %freed239, 0
  br i1 %freed_b240, label %br_unique49, label %br_shared50
br_shared50:
  call void @march_incrc(ptr %fv238)
  call void @march_incrc(ptr %fv236)
  call void @march_incrc(ptr %fv232)
  call void @march_incrc(ptr %fv230)
  call void @march_incrc(ptr %fv226)
  call void @march_incrc(ptr %fv224)
  call void @march_incrc(ptr %fv222)
  call void @march_incrc(ptr %fv220)
  call void @march_incrc(ptr %fv218)
  call void @march_incrc(ptr %fv216)
  br label %br_body51
br_unique49:
  br label %br_body51
br_body51:
  %ld241 = load ptr, ptr %$f1938.addr
  %u.addr = alloca ptr
  store ptr %ld241, ptr %u.addr
  %ld242 = load ptr, ptr %$f1937.addr
  %a.addr = alloca ptr
  store ptr %ld242, ptr %a.addr
  %ld243 = load i64, ptr %$f1936.addr
  %h.addr = alloca i64
  store i64 %ld243, ptr %h.addr
  %ld244 = load ptr, ptr %$f1935.addr
  %rbody.addr = alloca ptr
  store ptr %ld244, ptr %rbody.addr
  %ld245 = load ptr, ptr %$f1934.addr
  %rhs.addr = alloca ptr
  store ptr %ld245, ptr %rhs.addr
  %ld246 = load i64, ptr %$f1933.addr
  %s.addr = alloca i64
  store i64 %ld246, ptr %s.addr
  %ld247 = load ptr, ptr %$f1932.addr
  %rb.addr = alloca ptr
  store ptr %ld247, ptr %rb.addr
  %ld248 = load ptr, ptr %$f1931.addr
  %rh.addr = alloca ptr
  store ptr %ld248, ptr %rh.addr
  %ld249 = load ptr, ptr %$f1930.addr
  %qs.addr = alloca ptr
  store ptr %ld249, ptr %qs.addr
  %ld250 = load ptr, ptr %$f1929.addr
  %pi.addr = alloca ptr
  store ptr %ld250, ptr %pi.addr
  %ld251 = load ptr, ptr %$f1928.addr
  %p.addr = alloca ptr
  store ptr %ld251, ptr %p.addr
  %ld252 = load ptr, ptr %$f1927.addr
  %m.addr = alloca ptr
  store ptr %ld252, ptr %m.addr
  %ld253 = load i64, ptr %$f1926.addr
  %fd.addr = alloca i64
  store i64 %ld253, ptr %fd.addr
  %ld254 = load i64, ptr %fd.addr
  %hp255 = call ptr @march_alloc(i64 32)
  %tgp256 = getelementptr i8, ptr %hp255, i64 8
  store i32 0, ptr %tgp256, align 4
  %ld257 = load ptr, ptr %name.addr
  %fp258 = getelementptr i8, ptr %hp255, i64 16
  store ptr %ld257, ptr %fp258, align 8
  %ld259 = load ptr, ptr %value.addr
  %fp260 = getelementptr i8, ptr %hp255, i64 24
  store ptr %ld259, ptr %fp260, align 8
  %$t1924.addr = alloca ptr
  store ptr %hp255, ptr %$t1924.addr
  %hp261 = call ptr @march_alloc(i64 32)
  %tgp262 = getelementptr i8, ptr %hp261, i64 8
  store i32 1, ptr %tgp262, align 4
  %ld263 = load ptr, ptr %$t1924.addr
  %fp264 = getelementptr i8, ptr %hp261, i64 16
  store ptr %ld263, ptr %fp264, align 8
  %ld265 = load ptr, ptr %rhs.addr
  %fp266 = getelementptr i8, ptr %hp261, i64 24
  store ptr %ld265, ptr %fp266, align 8
  %$t1925.addr = alloca ptr
  store ptr %hp261, ptr %$t1925.addr
  %hp267 = call ptr @march_alloc(i64 120)
  %tgp268 = getelementptr i8, ptr %hp267, i64 8
  store i32 0, ptr %tgp268, align 4
  %cv269 = ptrtoint ptr @HttpServer.fd to i64
  %fp270 = getelementptr i8, ptr %hp267, i64 16
  store i64 %cv269, ptr %fp270, align 8
  %ld271 = load ptr, ptr %m.addr
  %fp272 = getelementptr i8, ptr %hp267, i64 24
  store ptr %ld271, ptr %fp272, align 8
  %ld273 = load ptr, ptr %p.addr
  %fp274 = getelementptr i8, ptr %hp267, i64 32
  store ptr %ld273, ptr %fp274, align 8
  %ld275 = load ptr, ptr %pi.addr
  %fp276 = getelementptr i8, ptr %hp267, i64 40
  store ptr %ld275, ptr %fp276, align 8
  %ld277 = load ptr, ptr %qs.addr
  %fp278 = getelementptr i8, ptr %hp267, i64 48
  store ptr %ld277, ptr %fp278, align 8
  %ld279 = load ptr, ptr %rh.addr
  %fp280 = getelementptr i8, ptr %hp267, i64 56
  store ptr %ld279, ptr %fp280, align 8
  %ld281 = load ptr, ptr %rb.addr
  %fp282 = getelementptr i8, ptr %hp267, i64 64
  store ptr %ld281, ptr %fp282, align 8
  %ld283 = load i64, ptr %s.addr
  %fp284 = getelementptr i8, ptr %hp267, i64 72
  store i64 %ld283, ptr %fp284, align 8
  %ld285 = load ptr, ptr %$t1925.addr
  %fp286 = getelementptr i8, ptr %hp267, i64 80
  store ptr %ld285, ptr %fp286, align 8
  %ld287 = load ptr, ptr %rbody.addr
  %fp288 = getelementptr i8, ptr %hp267, i64 88
  store ptr %ld287, ptr %fp288, align 8
  %ld289 = load i64, ptr %h.addr
  %fp290 = getelementptr i8, ptr %hp267, i64 96
  store i64 %ld289, ptr %fp290, align 8
  %ld291 = load ptr, ptr %a.addr
  %fp292 = getelementptr i8, ptr %hp267, i64 104
  store ptr %ld291, ptr %fp292, align 8
  %ld293 = load ptr, ptr %u.addr
  %fp294 = getelementptr i8, ptr %hp267, i64 112
  store ptr %ld293, ptr %fp294, align 8
  store ptr %hp267, ptr %res_slot210
  br label %case_merge46
case_default47:
  unreachable
case_merge46:
  %case_r295 = load ptr, ptr %res_slot210
  ret ptr %case_r295
}

define ptr @HttpServer.send_resp(ptr %conn.arg, i64 %resp_status.arg, ptr %body.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %resp_status.addr = alloca i64
  store i64 %resp_status.arg, ptr %resp_status.addr
  %body.addr = alloca ptr
  store ptr %body.arg, ptr %body.addr
  %ld296 = load ptr, ptr %conn.addr
  %res_slot297 = alloca ptr
  %tgp298 = getelementptr i8, ptr %ld296, i64 8
  %tag299 = load i32, ptr %tgp298, align 4
  switch i32 %tag299, label %case_default53 [
      i32 0, label %case_br54
  ]
case_br54:
  %fp300 = getelementptr i8, ptr %ld296, i64 16
  %fv301 = load i64, ptr %fp300, align 8
  %$f1954.addr = alloca i64
  store i64 %fv301, ptr %$f1954.addr
  %fp302 = getelementptr i8, ptr %ld296, i64 24
  %fv303 = load ptr, ptr %fp302, align 8
  %$f1955.addr = alloca ptr
  store ptr %fv303, ptr %$f1955.addr
  %fp304 = getelementptr i8, ptr %ld296, i64 32
  %fv305 = load ptr, ptr %fp304, align 8
  %$f1956.addr = alloca ptr
  store ptr %fv305, ptr %$f1956.addr
  %fp306 = getelementptr i8, ptr %ld296, i64 40
  %fv307 = load ptr, ptr %fp306, align 8
  %$f1957.addr = alloca ptr
  store ptr %fv307, ptr %$f1957.addr
  %fp308 = getelementptr i8, ptr %ld296, i64 48
  %fv309 = load ptr, ptr %fp308, align 8
  %$f1958.addr = alloca ptr
  store ptr %fv309, ptr %$f1958.addr
  %fp310 = getelementptr i8, ptr %ld296, i64 56
  %fv311 = load ptr, ptr %fp310, align 8
  %$f1959.addr = alloca ptr
  store ptr %fv311, ptr %$f1959.addr
  %fp312 = getelementptr i8, ptr %ld296, i64 64
  %fv313 = load ptr, ptr %fp312, align 8
  %$f1960.addr = alloca ptr
  store ptr %fv313, ptr %$f1960.addr
  %fp314 = getelementptr i8, ptr %ld296, i64 72
  %fv315 = load i64, ptr %fp314, align 8
  %$f1961.addr = alloca i64
  store i64 %fv315, ptr %$f1961.addr
  %fp316 = getelementptr i8, ptr %ld296, i64 80
  %fv317 = load ptr, ptr %fp316, align 8
  %$f1962.addr = alloca ptr
  store ptr %fv317, ptr %$f1962.addr
  %fp318 = getelementptr i8, ptr %ld296, i64 88
  %fv319 = load ptr, ptr %fp318, align 8
  %$f1963.addr = alloca ptr
  store ptr %fv319, ptr %$f1963.addr
  %fp320 = getelementptr i8, ptr %ld296, i64 96
  %fv321 = load i64, ptr %fp320, align 8
  %$f1964.addr = alloca i64
  store i64 %fv321, ptr %$f1964.addr
  %fp322 = getelementptr i8, ptr %ld296, i64 104
  %fv323 = load ptr, ptr %fp322, align 8
  %$f1965.addr = alloca ptr
  store ptr %fv323, ptr %$f1965.addr
  %fp324 = getelementptr i8, ptr %ld296, i64 112
  %fv325 = load ptr, ptr %fp324, align 8
  %$f1966.addr = alloca ptr
  store ptr %fv325, ptr %$f1966.addr
  %freed326 = call i64 @march_decrc_freed(ptr %ld296)
  %freed_b327 = icmp ne i64 %freed326, 0
  br i1 %freed_b327, label %br_unique55, label %br_shared56
br_shared56:
  call void @march_incrc(ptr %fv325)
  call void @march_incrc(ptr %fv323)
  call void @march_incrc(ptr %fv319)
  call void @march_incrc(ptr %fv317)
  call void @march_incrc(ptr %fv313)
  call void @march_incrc(ptr %fv311)
  call void @march_incrc(ptr %fv309)
  call void @march_incrc(ptr %fv307)
  call void @march_incrc(ptr %fv305)
  call void @march_incrc(ptr %fv303)
  br label %br_body57
br_unique55:
  br label %br_body57
br_body57:
  %ld328 = load ptr, ptr %$f1966.addr
  %u.addr = alloca ptr
  store ptr %ld328, ptr %u.addr
  %ld329 = load ptr, ptr %$f1965.addr
  %a.addr = alloca ptr
  store ptr %ld329, ptr %a.addr
  %ld330 = load ptr, ptr %$f1962.addr
  %rhs.addr = alloca ptr
  store ptr %ld330, ptr %rhs.addr
  %ld331 = load ptr, ptr %$f1960.addr
  %rb.addr = alloca ptr
  store ptr %ld331, ptr %rb.addr
  %ld332 = load ptr, ptr %$f1959.addr
  %rh.addr = alloca ptr
  store ptr %ld332, ptr %rh.addr
  %ld333 = load ptr, ptr %$f1958.addr
  %qs.addr = alloca ptr
  store ptr %ld333, ptr %qs.addr
  %ld334 = load ptr, ptr %$f1957.addr
  %pi.addr = alloca ptr
  store ptr %ld334, ptr %pi.addr
  %ld335 = load ptr, ptr %$f1956.addr
  %p.addr = alloca ptr
  store ptr %ld335, ptr %p.addr
  %ld336 = load ptr, ptr %$f1955.addr
  %m.addr = alloca ptr
  store ptr %ld336, ptr %m.addr
  %ld337 = load i64, ptr %$f1954.addr
  %fd.addr = alloca i64
  store i64 %ld337, ptr %fd.addr
  %ld338 = load i64, ptr %fd.addr
  %hp339 = call ptr @march_alloc(i64 120)
  %tgp340 = getelementptr i8, ptr %hp339, i64 8
  store i32 0, ptr %tgp340, align 4
  %cv341 = ptrtoint ptr @HttpServer.fd to i64
  %fp342 = getelementptr i8, ptr %hp339, i64 16
  store i64 %cv341, ptr %fp342, align 8
  %ld343 = load ptr, ptr %m.addr
  %fp344 = getelementptr i8, ptr %hp339, i64 24
  store ptr %ld343, ptr %fp344, align 8
  %ld345 = load ptr, ptr %p.addr
  %fp346 = getelementptr i8, ptr %hp339, i64 32
  store ptr %ld345, ptr %fp346, align 8
  %ld347 = load ptr, ptr %pi.addr
  %fp348 = getelementptr i8, ptr %hp339, i64 40
  store ptr %ld347, ptr %fp348, align 8
  %ld349 = load ptr, ptr %qs.addr
  %fp350 = getelementptr i8, ptr %hp339, i64 48
  store ptr %ld349, ptr %fp350, align 8
  %ld351 = load ptr, ptr %rh.addr
  %fp352 = getelementptr i8, ptr %hp339, i64 56
  store ptr %ld351, ptr %fp352, align 8
  %ld353 = load ptr, ptr %rb.addr
  %fp354 = getelementptr i8, ptr %hp339, i64 64
  store ptr %ld353, ptr %fp354, align 8
  %ld355 = load i64, ptr %resp_status.addr
  %fp356 = getelementptr i8, ptr %hp339, i64 72
  store i64 %ld355, ptr %fp356, align 8
  %ld357 = load ptr, ptr %rhs.addr
  %fp358 = getelementptr i8, ptr %hp339, i64 80
  store ptr %ld357, ptr %fp358, align 8
  %ld359 = load ptr, ptr %body.addr
  %fp360 = getelementptr i8, ptr %hp339, i64 88
  store ptr %ld359, ptr %fp360, align 8
  %fp361 = getelementptr i8, ptr %hp339, i64 96
  store i64 1, ptr %fp361, align 8
  %ld362 = load ptr, ptr %a.addr
  %fp363 = getelementptr i8, ptr %hp339, i64 104
  store ptr %ld362, ptr %fp363, align 8
  %ld364 = load ptr, ptr %u.addr
  %fp365 = getelementptr i8, ptr %hp339, i64 112
  store ptr %ld364, ptr %fp365, align 8
  store ptr %hp339, ptr %res_slot297
  br label %case_merge52
case_default53:
  unreachable
case_merge52:
  %case_r366 = load ptr, ptr %res_slot297
  ret ptr %case_r366
}

define ptr @HttpServer.run_pipeline(ptr %conn.arg, ptr %plugs.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %plugs.addr = alloca ptr
  store ptr %plugs.arg, ptr %plugs.addr
  %ld367 = load ptr, ptr %plugs.addr
  %res_slot368 = alloca ptr
  %tgp369 = getelementptr i8, ptr %ld367, i64 8
  %tag370 = load i32, ptr %tgp369, align 4
  switch i32 %tag370, label %case_default59 [
      i32 0, label %case_br60
      i32 1, label %case_br61
  ]
case_br60:
  %ld371 = load ptr, ptr %plugs.addr
  call void @march_decrc(ptr %ld371)
  %ld372 = load ptr, ptr %conn.addr
  store ptr %ld372, ptr %res_slot368
  br label %case_merge58
case_br61:
  %fp373 = getelementptr i8, ptr %ld367, i64 16
  %fv374 = load ptr, ptr %fp373, align 8
  %$f1986.addr = alloca ptr
  store ptr %fv374, ptr %$f1986.addr
  %fp375 = getelementptr i8, ptr %ld367, i64 24
  %fv376 = load ptr, ptr %fp375, align 8
  %$f1987.addr = alloca ptr
  store ptr %fv376, ptr %$f1987.addr
  %freed377 = call i64 @march_decrc_freed(ptr %ld367)
  %freed_b378 = icmp ne i64 %freed377, 0
  br i1 %freed_b378, label %br_unique62, label %br_shared63
br_shared63:
  call void @march_incrc(ptr %fv376)
  call void @march_incrc(ptr %fv374)
  br label %br_body64
br_unique62:
  br label %br_body64
br_body64:
  %ld379 = load ptr, ptr %$f1987.addr
  %rest.addr = alloca ptr
  store ptr %ld379, ptr %rest.addr
  %ld380 = load ptr, ptr %$f1986.addr
  %f.addr = alloca ptr
  store ptr %ld380, ptr %f.addr
  %ld381 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld381)
  %ld382 = load ptr, ptr %conn.addr
  %cr383 = call i64 @HttpServer.halted(ptr %ld382)
  %$t1984.addr = alloca i64
  store i64 %cr383, ptr %$t1984.addr
  %ld384 = load i64, ptr %$t1984.addr
  %res_slot385 = alloca ptr
  %bi386 = trunc i64 %ld384 to i1
  br i1 %bi386, label %case_br67, label %case_default66
case_br67:
  %ld387 = load ptr, ptr %conn.addr
  store ptr %ld387, ptr %res_slot385
  br label %case_merge65
case_default66:
  %ld388 = load ptr, ptr %f.addr
  %fp389 = getelementptr i8, ptr %ld388, i64 16
  %fv390 = load ptr, ptr %fp389, align 8
  %ld391 = load ptr, ptr %conn.addr
  %cr392 = call ptr (ptr, ptr) %fv390(ptr %ld388, ptr %ld391)
  %$t1985.addr = alloca ptr
  store ptr %cr392, ptr %$t1985.addr
  %ld393 = load ptr, ptr %$t1985.addr
  %ld394 = load ptr, ptr %rest.addr
  %cr395 = call ptr @HttpServer.run_pipeline(ptr %ld393, ptr %ld394)
  store ptr %cr395, ptr %res_slot385
  br label %case_merge65
case_merge65:
  %case_r396 = load ptr, ptr %res_slot385
  store ptr %case_r396, ptr %res_slot368
  br label %case_merge58
case_default59:
  unreachable
case_merge58:
  %case_r397 = load ptr, ptr %res_slot368
  ret ptr %case_r397
}

define void @Counter_Increment(ptr %$actor.arg, i64 %n.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld398 = load ptr, ptr %$actor.addr
  %fp399 = getelementptr i8, ptr %ld398, i64 16
  %fv400 = load ptr, ptr %fp399, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv400, ptr %$dispatch_v.addr
  %ld401 = load ptr, ptr %$actor.addr
  %fp402 = getelementptr i8, ptr %ld401, i64 24
  %fv403 = load i64, ptr %fp402, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv403, ptr %$alive_v.addr
  %ld404 = load ptr, ptr %$actor.addr
  %fp405 = getelementptr i8, ptr %ld404, i64 32
  %fv406 = load i64, ptr %fp405, align 8
  %$sf_count.addr = alloca i64
  store i64 %fv406, ptr %$sf_count.addr
  %hp407 = call ptr @march_alloc(i64 24)
  %tgp408 = getelementptr i8, ptr %hp407, i64 8
  store i32 0, ptr %tgp408, align 4
  %ld409 = load i64, ptr %$sf_count.addr
  %fp410 = getelementptr i8, ptr %hp407, i64 16
  store i64 %ld409, ptr %fp410, align 8
  %state.addr = alloca ptr
  store ptr %hp407, ptr %state.addr
  %ld411 = load ptr, ptr %state.addr
  %fp412 = getelementptr i8, ptr %ld411, i64 16
  %fv413 = load i64, ptr %fp412, align 8
  %$t2009.addr = alloca i64
  store i64 %fv413, ptr %$t2009.addr
  %ld414 = load i64, ptr %$t2009.addr
  %ld415 = load i64, ptr %n.addr
  %ar416 = add i64 %ld414, %ld415
  %$t2010.addr = alloca i64
  store i64 %ar416, ptr %$t2010.addr
  %ld417 = load ptr, ptr %state.addr
  %hp418 = call ptr @march_alloc(i64 24)
  %tgp419 = getelementptr i8, ptr %hp418, i64 8
  store i32 0, ptr %tgp419, align 4
  %fp420 = getelementptr i8, ptr %ld417, i64 16
  %fv421 = load i64, ptr %fp420, align 8
  %fp422 = getelementptr i8, ptr %hp418, i64 16
  store i64 %fv421, ptr %fp422, align 8
  %ld423 = load i64, ptr %$t2010.addr
  %fp424 = getelementptr i8, ptr %hp418, i64 16
  store i64 %ld423, ptr %fp424, align 8
  %$result.addr = alloca ptr
  store ptr %hp418, ptr %$result.addr
  %ld425 = load ptr, ptr %$result.addr
  %fp426 = getelementptr i8, ptr %ld425, i64 16
  %fv427 = load i64, ptr %fp426, align 8
  %$nf_count.addr = alloca i64
  store i64 %fv427, ptr %$nf_count.addr
  %ld428 = load ptr, ptr %$actor.addr
  %ld429 = load ptr, ptr %$dispatch_v.addr
  %ld430 = load i64, ptr %$alive_v.addr
  %ld431 = load i64, ptr %$nf_count.addr
  %rc432 = load i64, ptr %ld428, align 8
  %uniq433 = icmp eq i64 %rc432, 1
  %fbip_slot434 = alloca ptr
  br i1 %uniq433, label %fbip_reuse68, label %fbip_fresh69
fbip_reuse68:
  %tgp435 = getelementptr i8, ptr %ld428, i64 8
  store i32 0, ptr %tgp435, align 4
  %fp436 = getelementptr i8, ptr %ld428, i64 16
  store ptr %ld429, ptr %fp436, align 8
  %fp437 = getelementptr i8, ptr %ld428, i64 24
  store i64 %ld430, ptr %fp437, align 8
  %fp438 = getelementptr i8, ptr %ld428, i64 32
  store i64 %ld431, ptr %fp438, align 8
  store ptr %ld428, ptr %fbip_slot434
  br label %fbip_merge70
fbip_fresh69:
  call void @march_decrc(ptr %ld428)
  %hp439 = call ptr @march_alloc(i64 40)
  %tgp440 = getelementptr i8, ptr %hp439, i64 8
  store i32 0, ptr %tgp440, align 4
  %fp441 = getelementptr i8, ptr %hp439, i64 16
  store ptr %ld429, ptr %fp441, align 8
  %fp442 = getelementptr i8, ptr %hp439, i64 24
  store i64 %ld430, ptr %fp442, align 8
  %fp443 = getelementptr i8, ptr %hp439, i64 32
  store i64 %ld431, ptr %fp443, align 8
  store ptr %hp439, ptr %fbip_slot434
  br label %fbip_merge70
fbip_merge70:
  %fbip_r444 = load ptr, ptr %fbip_slot434
  ret void
}

define void @Counter_Decrement(ptr %$actor.arg, i64 %n.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld445 = load ptr, ptr %$actor.addr
  %fp446 = getelementptr i8, ptr %ld445, i64 16
  %fv447 = load ptr, ptr %fp446, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv447, ptr %$dispatch_v.addr
  %ld448 = load ptr, ptr %$actor.addr
  %fp449 = getelementptr i8, ptr %ld448, i64 24
  %fv450 = load i64, ptr %fp449, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv450, ptr %$alive_v.addr
  %ld451 = load ptr, ptr %$actor.addr
  %fp452 = getelementptr i8, ptr %ld451, i64 32
  %fv453 = load i64, ptr %fp452, align 8
  %$sf_count.addr = alloca i64
  store i64 %fv453, ptr %$sf_count.addr
  %hp454 = call ptr @march_alloc(i64 24)
  %tgp455 = getelementptr i8, ptr %hp454, i64 8
  store i32 0, ptr %tgp455, align 4
  %ld456 = load i64, ptr %$sf_count.addr
  %fp457 = getelementptr i8, ptr %hp454, i64 16
  store i64 %ld456, ptr %fp457, align 8
  %state.addr = alloca ptr
  store ptr %hp454, ptr %state.addr
  %ld458 = load ptr, ptr %state.addr
  %fp459 = getelementptr i8, ptr %ld458, i64 16
  %fv460 = load i64, ptr %fp459, align 8
  %$t2011.addr = alloca i64
  store i64 %fv460, ptr %$t2011.addr
  %ld461 = load i64, ptr %$t2011.addr
  %ld462 = load i64, ptr %n.addr
  %ar463 = sub i64 %ld461, %ld462
  %$t2012.addr = alloca i64
  store i64 %ar463, ptr %$t2012.addr
  %ld464 = load ptr, ptr %state.addr
  %hp465 = call ptr @march_alloc(i64 24)
  %tgp466 = getelementptr i8, ptr %hp465, i64 8
  store i32 0, ptr %tgp466, align 4
  %fp467 = getelementptr i8, ptr %ld464, i64 16
  %fv468 = load i64, ptr %fp467, align 8
  %fp469 = getelementptr i8, ptr %hp465, i64 16
  store i64 %fv468, ptr %fp469, align 8
  %ld470 = load i64, ptr %$t2012.addr
  %fp471 = getelementptr i8, ptr %hp465, i64 16
  store i64 %ld470, ptr %fp471, align 8
  %$result.addr = alloca ptr
  store ptr %hp465, ptr %$result.addr
  %ld472 = load ptr, ptr %$result.addr
  %fp473 = getelementptr i8, ptr %ld472, i64 16
  %fv474 = load i64, ptr %fp473, align 8
  %$nf_count.addr = alloca i64
  store i64 %fv474, ptr %$nf_count.addr
  %ld475 = load ptr, ptr %$actor.addr
  %ld476 = load ptr, ptr %$dispatch_v.addr
  %ld477 = load i64, ptr %$alive_v.addr
  %ld478 = load i64, ptr %$nf_count.addr
  %rc479 = load i64, ptr %ld475, align 8
  %uniq480 = icmp eq i64 %rc479, 1
  %fbip_slot481 = alloca ptr
  br i1 %uniq480, label %fbip_reuse71, label %fbip_fresh72
fbip_reuse71:
  %tgp482 = getelementptr i8, ptr %ld475, i64 8
  store i32 0, ptr %tgp482, align 4
  %fp483 = getelementptr i8, ptr %ld475, i64 16
  store ptr %ld476, ptr %fp483, align 8
  %fp484 = getelementptr i8, ptr %ld475, i64 24
  store i64 %ld477, ptr %fp484, align 8
  %fp485 = getelementptr i8, ptr %ld475, i64 32
  store i64 %ld478, ptr %fp485, align 8
  store ptr %ld475, ptr %fbip_slot481
  br label %fbip_merge73
fbip_fresh72:
  call void @march_decrc(ptr %ld475)
  %hp486 = call ptr @march_alloc(i64 40)
  %tgp487 = getelementptr i8, ptr %hp486, i64 8
  store i32 0, ptr %tgp487, align 4
  %fp488 = getelementptr i8, ptr %hp486, i64 16
  store ptr %ld476, ptr %fp488, align 8
  %fp489 = getelementptr i8, ptr %hp486, i64 24
  store i64 %ld477, ptr %fp489, align 8
  %fp490 = getelementptr i8, ptr %hp486, i64 32
  store i64 %ld478, ptr %fp490, align 8
  store ptr %hp486, ptr %fbip_slot481
  br label %fbip_merge73
fbip_merge73:
  %fbip_r491 = load ptr, ptr %fbip_slot481
  ret void
}

define void @Counter_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld492 = load ptr, ptr %$msg.addr
  %res_slot493 = alloca ptr
  %tgp494 = getelementptr i8, ptr %ld492, i64 8
  %tag495 = load i32, ptr %tgp494, align 4
  switch i32 %tag495, label %case_default75 [
      i32 0, label %case_br76
      i32 1, label %case_br77
  ]
case_br76:
  %fp496 = getelementptr i8, ptr %ld492, i64 16
  %fv497 = load i64, ptr %fp496, align 8
  %$Increment_n.addr = alloca i64
  store i64 %fv497, ptr %$Increment_n.addr
  %ld498 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld498)
  %ld499 = load ptr, ptr %$actor.addr
  %ld500 = load i64, ptr %$Increment_n.addr
  call void @Counter_Increment(ptr %ld499, i64 %ld500)
  %cv501 = inttoptr i64 0 to ptr
  store ptr %cv501, ptr %res_slot493
  br label %case_merge74
case_br77:
  %fp502 = getelementptr i8, ptr %ld492, i64 16
  %fv503 = load i64, ptr %fp502, align 8
  %$Decrement_n.addr = alloca i64
  store i64 %fv503, ptr %$Decrement_n.addr
  %ld504 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld504)
  %ld505 = load ptr, ptr %$actor.addr
  %ld506 = load i64, ptr %$Decrement_n.addr
  call void @Counter_Decrement(ptr %ld505, i64 %ld506)
  %cv507 = inttoptr i64 0 to ptr
  store ptr %cv507, ptr %res_slot493
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r508 = load ptr, ptr %res_slot493
  ret void
}

define void @march_main() {
entry:
  %hp509 = call ptr @march_alloc(i64 24)
  %tgp510 = getelementptr i8, ptr %hp509, i64 8
  store i32 0, ptr %tgp510, align 4
  %fp511 = getelementptr i8, ptr %hp509, i64 16
  store i64 0, ptr %fp511, align 8
  %$init_state_i25.addr = alloca ptr
  store ptr %hp509, ptr %$init_state_i25.addr
  %ld512 = load ptr, ptr %$init_state_i25.addr
  %fp513 = getelementptr i8, ptr %ld512, i64 16
  %fv514 = load i64, ptr %fp513, align 8
  %$init_count_i26.addr = alloca i64
  store i64 %fv514, ptr %$init_count_i26.addr
  %hp515 = call ptr @march_alloc(i64 40)
  %tgp516 = getelementptr i8, ptr %hp515, i64 8
  store i32 0, ptr %tgp516, align 4
  %cwrap517 = call ptr @march_alloc(i64 24)
  %cwt518 = getelementptr i8, ptr %cwrap517, i64 8
  store i32 0, ptr %cwt518, align 4
  %cwf519 = getelementptr i8, ptr %cwrap517, i64 16
  store ptr @Counter_dispatch$clo_wrap, ptr %cwf519, align 8
  %fp520 = getelementptr i8, ptr %hp515, i64 16
  store ptr %cwrap517, ptr %fp520, align 8
  %fp521 = getelementptr i8, ptr %hp515, i64 24
  store i64 1, ptr %fp521, align 8
  %ld522 = load i64, ptr %$init_count_i26.addr
  %fp523 = getelementptr i8, ptr %hp515, i64 32
  store i64 %ld522, ptr %fp523, align 8
  %$spawned_i27.addr = alloca ptr
  store ptr %hp515, ptr %$spawned_i27.addr
  %ld524 = load ptr, ptr %$spawned_i27.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld524, ptr %$raw_actor.addr
  %ld525 = load ptr, ptr %$raw_actor.addr
  %cr526 = call ptr @march_spawn(ptr %ld525)
  %counter.addr = alloca ptr
  store ptr %cr526, ptr %counter.addr
  %sl527 = call ptr @march_string_lit(ptr @.str10, i64 39)
  call void @march_println(ptr %sl527)
  %sl528 = call ptr @march_string_lit(ptr @.str11, i64 32)
  call void @march_println(ptr %sl528)
  %sl529 = call ptr @march_string_lit(ptr @.str12, i64 32)
  call void @march_println(ptr %sl529)
  %sl530 = call ptr @march_string_lit(ptr @.str13, i64 37)
  call void @march_println(ptr %sl530)
  %port_i23.addr = alloca i64
  store i64 8080, ptr %port_i23.addr
  %hp531 = call ptr @march_alloc(i64 16)
  %tgp532 = getelementptr i8, ptr %hp531, i64 8
  store i32 0, ptr %tgp532, align 4
  %$t1988_i24.addr = alloca ptr
  store ptr %hp531, ptr %$t1988_i24.addr
  %hp533 = call ptr @march_alloc(i64 48)
  %tgp534 = getelementptr i8, ptr %hp533, i64 8
  store i32 0, ptr %tgp534, align 4
  %ld535 = load i64, ptr %port_i23.addr
  %fp536 = getelementptr i8, ptr %hp533, i64 16
  store i64 %ld535, ptr %fp536, align 8
  %ld537 = load ptr, ptr %$t1988_i24.addr
  %fp538 = getelementptr i8, ptr %hp533, i64 24
  store ptr %ld537, ptr %fp538, align 8
  %fp539 = getelementptr i8, ptr %hp533, i64 32
  store i64 1000, ptr %fp539, align 8
  %fp540 = getelementptr i8, ptr %hp533, i64 40
  store i64 60, ptr %fp540, align 8
  %$t2028.addr = alloca ptr
  store ptr %hp533, ptr %$t2028.addr
  %hp541 = call ptr @march_alloc(i64 32)
  %tgp542 = getelementptr i8, ptr %hp541, i64 8
  store i32 0, ptr %tgp542, align 4
  %fp543 = getelementptr i8, ptr %hp541, i64 16
  store ptr @$lam2029$apply$22, ptr %fp543, align 8
  %ld544 = load ptr, ptr %counter.addr
  %fp545 = getelementptr i8, ptr %hp541, i64 24
  store ptr %ld544, ptr %fp545, align 8
  %$t2030.addr = alloca ptr
  store ptr %hp541, ptr %$t2030.addr
  %ld546 = load ptr, ptr %$t2028.addr
  %ld547 = load ptr, ptr %$t2030.addr
  %cr548 = call ptr @HttpServer.plug$Server$Fn_V__6048_V__6055(ptr %ld546, ptr %ld547)
  %$t2031.addr = alloca ptr
  store ptr %cr548, ptr %$t2031.addr
  %ld549 = load ptr, ptr %$t2031.addr
  %cr550 = call ptr @HttpServer.listen(ptr %ld549)
  ret void
}

define ptr @HttpServer.listen(ptr %server.arg) {
entry:
  %server.addr = alloca ptr
  store ptr %server.arg, ptr %server.addr
  %ld551 = load ptr, ptr %server.addr
  %res_slot552 = alloca ptr
  %tgp553 = getelementptr i8, ptr %ld551, i64 8
  %tag554 = load i32, ptr %tgp553, align 4
  switch i32 %tag554, label %case_default79 [
      i32 0, label %case_br80
  ]
case_br80:
  %fp555 = getelementptr i8, ptr %ld551, i64 16
  %fv556 = load i64, ptr %fp555, align 8
  %$f2005.addr = alloca i64
  store i64 %fv556, ptr %$f2005.addr
  %fp557 = getelementptr i8, ptr %ld551, i64 24
  %fv558 = load ptr, ptr %fp557, align 8
  %$f2006.addr = alloca ptr
  store ptr %fv558, ptr %$f2006.addr
  %fp559 = getelementptr i8, ptr %ld551, i64 32
  %fv560 = load i64, ptr %fp559, align 8
  %$f2007.addr = alloca i64
  store i64 %fv560, ptr %$f2007.addr
  %fp561 = getelementptr i8, ptr %ld551, i64 40
  %fv562 = load i64, ptr %fp561, align 8
  %$f2008.addr = alloca i64
  store i64 %fv562, ptr %$f2008.addr
  %freed563 = call i64 @march_decrc_freed(ptr %ld551)
  %freed_b564 = icmp ne i64 %freed563, 0
  br i1 %freed_b564, label %br_unique81, label %br_shared82
br_shared82:
  call void @march_incrc(ptr %fv558)
  br label %br_body83
br_unique81:
  br label %br_body83
br_body83:
  %ld565 = load i64, ptr %$f2008.addr
  %it.addr = alloca i64
  store i64 %ld565, ptr %it.addr
  %ld566 = load i64, ptr %$f2007.addr
  %mc.addr = alloca i64
  store i64 %ld566, ptr %mc.addr
  %ld567 = load ptr, ptr %$f2006.addr
  %plugs.addr = alloca ptr
  store ptr %ld567, ptr %plugs.addr
  %ld568 = load i64, ptr %$f2005.addr
  %port.addr = alloca i64
  store i64 %ld568, ptr %port.addr
  %hp569 = call ptr @march_alloc(i64 32)
  %tgp570 = getelementptr i8, ptr %hp569, i64 8
  store i32 0, ptr %tgp570, align 4
  %fp571 = getelementptr i8, ptr %hp569, i64 16
  store ptr @$lam2004$apply$25, ptr %fp571, align 8
  %ld572 = load ptr, ptr %plugs.addr
  %fp573 = getelementptr i8, ptr %hp569, i64 24
  store ptr %ld572, ptr %fp573, align 8
  %pipeline_fn.addr = alloca ptr
  store ptr %hp569, ptr %pipeline_fn.addr
  %ld574 = load i64, ptr %port.addr
  %ld575 = load i64, ptr %mc.addr
  %ld576 = load i64, ptr %it.addr
  %ld577 = load ptr, ptr %pipeline_fn.addr
  %cr578 = call ptr @march_http_server_listen(i64 %ld574, i64 %ld575, i64 %ld576, ptr %ld577)
  store ptr %cr578, ptr %res_slot552
  br label %case_merge78
case_default79:
  unreachable
case_merge78:
  %case_r579 = load ptr, ptr %res_slot552
  ret ptr %case_r579
}

define ptr @HttpServer.plug$Server$Fn_V__6048_V__6055(ptr %server.arg, ptr %p.arg) {
entry:
  %server.addr = alloca ptr
  store ptr %server.arg, ptr %server.addr
  %p.addr = alloca ptr
  store ptr %p.arg, ptr %p.addr
  %ld580 = load ptr, ptr %server.addr
  %res_slot581 = alloca ptr
  %tgp582 = getelementptr i8, ptr %ld580, i64 8
  %tag583 = load i32, ptr %tgp582, align 4
  switch i32 %tag583, label %case_default85 [
      i32 0, label %case_br86
  ]
case_br86:
  %fp584 = getelementptr i8, ptr %ld580, i64 16
  %fv585 = load i64, ptr %fp584, align 8
  %$f1992.addr = alloca i64
  store i64 %fv585, ptr %$f1992.addr
  %fp586 = getelementptr i8, ptr %ld580, i64 24
  %fv587 = load ptr, ptr %fp586, align 8
  %$f1993.addr = alloca ptr
  store ptr %fv587, ptr %$f1993.addr
  %fp588 = getelementptr i8, ptr %ld580, i64 32
  %fv589 = load i64, ptr %fp588, align 8
  %$f1994.addr = alloca i64
  store i64 %fv589, ptr %$f1994.addr
  %fp590 = getelementptr i8, ptr %ld580, i64 40
  %fv591 = load i64, ptr %fp590, align 8
  %$f1995.addr = alloca i64
  store i64 %fv591, ptr %$f1995.addr
  %ld592 = load i64, ptr %$f1995.addr
  %it.addr = alloca i64
  store i64 %ld592, ptr %it.addr
  %ld593 = load i64, ptr %$f1994.addr
  %mc.addr = alloca i64
  store i64 %ld593, ptr %mc.addr
  %ld594 = load ptr, ptr %$f1993.addr
  %plugs.addr = alloca ptr
  store ptr %ld594, ptr %plugs.addr
  %ld595 = load i64, ptr %$f1992.addr
  %port.addr = alloca i64
  store i64 %ld595, ptr %port.addr
  %hp596 = call ptr @march_alloc(i64 16)
  %tgp597 = getelementptr i8, ptr %hp596, i64 8
  store i32 0, ptr %tgp597, align 4
  %$t1989.addr = alloca ptr
  store ptr %hp596, ptr %$t1989.addr
  %hp598 = call ptr @march_alloc(i64 32)
  %tgp599 = getelementptr i8, ptr %hp598, i64 8
  store i32 1, ptr %tgp599, align 4
  %ld600 = load ptr, ptr %p.addr
  %fp601 = getelementptr i8, ptr %hp598, i64 16
  store ptr %ld600, ptr %fp601, align 8
  %ld602 = load ptr, ptr %$t1989.addr
  %fp603 = getelementptr i8, ptr %hp598, i64 24
  store ptr %ld602, ptr %fp603, align 8
  %$t1990.addr = alloca ptr
  store ptr %hp598, ptr %$t1990.addr
  %ld604 = load ptr, ptr %plugs.addr
  %ld605 = load ptr, ptr %$t1990.addr
  %cr606 = call ptr @List.append$List_Fn_Conn_Conn$List_Fn_Conn_Conn(ptr %ld604, ptr %ld605)
  %$t1991.addr = alloca ptr
  store ptr %cr606, ptr %$t1991.addr
  %ld607 = load ptr, ptr %server.addr
  %ld608 = load i64, ptr %port.addr
  %ld609 = load ptr, ptr %$t1991.addr
  %ld610 = load i64, ptr %mc.addr
  %ld611 = load i64, ptr %it.addr
  %rc612 = load i64, ptr %ld607, align 8
  %uniq613 = icmp eq i64 %rc612, 1
  %fbip_slot614 = alloca ptr
  br i1 %uniq613, label %fbip_reuse87, label %fbip_fresh88
fbip_reuse87:
  %tgp615 = getelementptr i8, ptr %ld607, i64 8
  store i32 0, ptr %tgp615, align 4
  %fp616 = getelementptr i8, ptr %ld607, i64 16
  store i64 %ld608, ptr %fp616, align 8
  %fp617 = getelementptr i8, ptr %ld607, i64 24
  store ptr %ld609, ptr %fp617, align 8
  %fp618 = getelementptr i8, ptr %ld607, i64 32
  store i64 %ld610, ptr %fp618, align 8
  %fp619 = getelementptr i8, ptr %ld607, i64 40
  store i64 %ld611, ptr %fp619, align 8
  store ptr %ld607, ptr %fbip_slot614
  br label %fbip_merge89
fbip_fresh88:
  call void @march_decrc(ptr %ld607)
  %hp620 = call ptr @march_alloc(i64 48)
  %tgp621 = getelementptr i8, ptr %hp620, i64 8
  store i32 0, ptr %tgp621, align 4
  %fp622 = getelementptr i8, ptr %hp620, i64 16
  store i64 %ld608, ptr %fp622, align 8
  %fp623 = getelementptr i8, ptr %hp620, i64 24
  store ptr %ld609, ptr %fp623, align 8
  %fp624 = getelementptr i8, ptr %hp620, i64 32
  store i64 %ld610, ptr %fp624, align 8
  %fp625 = getelementptr i8, ptr %hp620, i64 40
  store i64 %ld611, ptr %fp625, align 8
  store ptr %hp620, ptr %fbip_slot614
  br label %fbip_merge89
fbip_merge89:
  %fbip_r626 = load ptr, ptr %fbip_slot614
  store ptr %fbip_r626, ptr %res_slot581
  br label %case_merge84
case_default85:
  unreachable
case_merge84:
  %case_r627 = load ptr, ptr %res_slot581
  ret ptr %case_r627
}

define ptr @router$Pid_V__6083$V__6048(ptr %counter.arg, ptr %conn.arg) {
entry:
  %counter.addr = alloca ptr
  store ptr %counter.arg, ptr %counter.addr
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld628 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld628)
  %ld629 = load ptr, ptr %conn.addr
  %cr630 = call ptr @HttpServer.method(ptr %ld629)
  %$t2023.addr = alloca ptr
  store ptr %cr630, ptr %$t2023.addr
  %ld631 = load ptr, ptr %$t2023.addr
  %cr632 = call ptr @Http.method_to_string(ptr %ld631)
  %m.addr = alloca ptr
  store ptr %cr632, ptr %m.addr
  %ld633 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld633)
  %ld634 = load ptr, ptr %conn.addr
  %cr635 = call ptr @HttpServer.path(ptr %ld634)
  %p.addr = alloca ptr
  store ptr %cr635, ptr %p.addr
  %ld636 = load ptr, ptr %m.addr
  call void @march_incrc(ptr %ld636)
  %ld637 = load ptr, ptr %m.addr
  %sl638 = call ptr @march_string_lit(ptr @.str14, i64 3)
  %cr639 = call i64 @march_string_eq(ptr %ld637, ptr %sl638)
  %$t2024.addr = alloca i64
  store i64 %cr639, ptr %$t2024.addr
  %ld640 = load i64, ptr %$t2024.addr
  %res_slot641 = alloca ptr
  %bi642 = trunc i64 %ld640 to i1
  br i1 %bi642, label %case_br92, label %case_default91
case_br92:
  %ld643 = load ptr, ptr %p.addr
  %sl644 = call ptr @march_string_lit(ptr @.str15, i64 6)
  %cr645 = call i64 @march_string_eq(ptr %ld643, ptr %sl644)
  %$t2025.addr = alloca i64
  store i64 %cr645, ptr %$t2025.addr
  %ld646 = load i64, ptr %$t2025.addr
  %res_slot647 = alloca ptr
  %bi648 = trunc i64 %ld646 to i1
  br i1 %bi648, label %case_br95, label %case_default94
case_br95:
  %ld649 = load ptr, ptr %counter.addr
  %counter_i40.addr = alloca ptr
  store ptr %ld649, ptr %counter_i40.addr
  %ld650 = load ptr, ptr %counter_i40.addr
  %cr651 = call i64 @march_actor_get_int(ptr %ld650, i64 0)
  %$t2013_i41.addr = alloca i64
  store i64 %cr651, ptr %$t2013_i41.addr
  %ld652 = load i64, ptr %$t2013_i41.addr
  %cr653 = call ptr @march_int_to_string(i64 %ld652)
  %$t2026.addr = alloca ptr
  store ptr %cr653, ptr %$t2026.addr
  %ld654 = load ptr, ptr %conn.addr
  %conn_i36.addr = alloca ptr
  store ptr %ld654, ptr %conn_i36.addr
  %resp_status_i37.addr = alloca i64
  store i64 200, ptr %resp_status_i37.addr
  %ld655 = load ptr, ptr %$t2026.addr
  %body_i38.addr = alloca ptr
  store ptr %ld655, ptr %body_i38.addr
  %ld656 = load ptr, ptr %conn_i36.addr
  %sl657 = call ptr @march_string_lit(ptr @.str16, i64 12)
  %sl658 = call ptr @march_string_lit(ptr @.str17, i64 25)
  %cr659 = call ptr @HttpServer.put_resp_header(ptr %ld656, ptr %sl657, ptr %sl658)
  %$t1980_i39.addr = alloca ptr
  store ptr %cr659, ptr %$t1980_i39.addr
  %ld660 = load ptr, ptr %$t1980_i39.addr
  %ld661 = load i64, ptr %resp_status_i37.addr
  %ld662 = load ptr, ptr %body_i38.addr
  %cr663 = call ptr @HttpServer.send_resp(ptr %ld660, i64 %ld661, ptr %ld662)
  store ptr %cr663, ptr %res_slot647
  br label %case_merge93
case_default94:
  %ld664 = load ptr, ptr %conn.addr
  %conn_i32.addr = alloca ptr
  store ptr %ld664, ptr %conn_i32.addr
  %resp_status_i33.addr = alloca i64
  store i64 404, ptr %resp_status_i33.addr
  %sl665 = call ptr @march_string_lit(ptr @.str18, i64 9)
  %body_i34.addr = alloca ptr
  store ptr %sl665, ptr %body_i34.addr
  %ld666 = load ptr, ptr %conn_i32.addr
  %sl667 = call ptr @march_string_lit(ptr @.str19, i64 12)
  %sl668 = call ptr @march_string_lit(ptr @.str20, i64 25)
  %cr669 = call ptr @HttpServer.put_resp_header(ptr %ld666, ptr %sl667, ptr %sl668)
  %$t1980_i35.addr = alloca ptr
  store ptr %cr669, ptr %$t1980_i35.addr
  %ld670 = load ptr, ptr %$t1980_i35.addr
  %ld671 = load i64, ptr %resp_status_i33.addr
  %ld672 = load ptr, ptr %body_i34.addr
  %cr673 = call ptr @HttpServer.send_resp(ptr %ld670, i64 %ld671, ptr %ld672)
  store ptr %cr673, ptr %res_slot647
  br label %case_merge93
case_merge93:
  %case_r674 = load ptr, ptr %res_slot647
  store ptr %case_r674, ptr %res_slot641
  br label %case_merge90
case_default91:
  %ld675 = load ptr, ptr %m.addr
  %sl676 = call ptr @march_string_lit(ptr @.str21, i64 4)
  %cr677 = call i64 @march_string_eq(ptr %ld675, ptr %sl676)
  %$t2027.addr = alloca i64
  store i64 %cr677, ptr %$t2027.addr
  %ld678 = load i64, ptr %$t2027.addr
  %res_slot679 = alloca ptr
  %bi680 = trunc i64 %ld678 to i1
  br i1 %bi680, label %case_br98, label %case_default97
case_br98:
  %ld681 = load ptr, ptr %counter.addr
  %ld682 = load ptr, ptr %conn.addr
  %cr683 = call ptr @handle_post$Pid_V__6083$V__6048(ptr %ld681, ptr %ld682)
  store ptr %cr683, ptr %res_slot679
  br label %case_merge96
case_default97:
  %ld684 = load ptr, ptr %conn.addr
  %conn_i28.addr = alloca ptr
  store ptr %ld684, ptr %conn_i28.addr
  %resp_status_i29.addr = alloca i64
  store i64 405, ptr %resp_status_i29.addr
  %sl685 = call ptr @march_string_lit(ptr @.str22, i64 18)
  %body_i30.addr = alloca ptr
  store ptr %sl685, ptr %body_i30.addr
  %ld686 = load ptr, ptr %conn_i28.addr
  %sl687 = call ptr @march_string_lit(ptr @.str23, i64 12)
  %sl688 = call ptr @march_string_lit(ptr @.str24, i64 25)
  %cr689 = call ptr @HttpServer.put_resp_header(ptr %ld686, ptr %sl687, ptr %sl688)
  %$t1980_i31.addr = alloca ptr
  store ptr %cr689, ptr %$t1980_i31.addr
  %ld690 = load ptr, ptr %$t1980_i31.addr
  %ld691 = load i64, ptr %resp_status_i29.addr
  %ld692 = load ptr, ptr %body_i30.addr
  %cr693 = call ptr @HttpServer.send_resp(ptr %ld690, i64 %ld691, ptr %ld692)
  store ptr %cr693, ptr %res_slot679
  br label %case_merge96
case_merge96:
  %case_r694 = load ptr, ptr %res_slot679
  store ptr %case_r694, ptr %res_slot641
  br label %case_merge90
case_merge90:
  %case_r695 = load ptr, ptr %res_slot641
  ret ptr %case_r695
}

define ptr @List.append$List_Fn_Conn_Conn$List_Fn_Conn_Conn(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld696 = load ptr, ptr %xs.addr
  %res_slot697 = alloca ptr
  %tgp698 = getelementptr i8, ptr %ld696, i64 8
  %tag699 = load i32, ptr %tgp698, align 4
  switch i32 %tag699, label %case_default100 [
      i32 0, label %case_br101
      i32 1, label %case_br102
  ]
case_br101:
  %ld700 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld700)
  %ld701 = load ptr, ptr %ys.addr
  store ptr %ld701, ptr %res_slot697
  br label %case_merge99
case_br102:
  %fp702 = getelementptr i8, ptr %ld696, i64 16
  %fv703 = load ptr, ptr %fp702, align 8
  %$f131.addr = alloca ptr
  store ptr %fv703, ptr %$f131.addr
  %fp704 = getelementptr i8, ptr %ld696, i64 24
  %fv705 = load ptr, ptr %fp704, align 8
  %$f132.addr = alloca ptr
  store ptr %fv705, ptr %$f132.addr
  %ld706 = load ptr, ptr %$f132.addr
  %t.addr = alloca ptr
  store ptr %ld706, ptr %t.addr
  %ld707 = load ptr, ptr %$f131.addr
  %h.addr = alloca ptr
  store ptr %ld707, ptr %h.addr
  %ld708 = load ptr, ptr %t.addr
  %ld709 = load ptr, ptr %ys.addr
  %cr710 = call ptr @List.append$List_V__744$List_V__744(ptr %ld708, ptr %ld709)
  %$t130.addr = alloca ptr
  store ptr %cr710, ptr %$t130.addr
  %ld711 = load ptr, ptr %xs.addr
  %ld712 = load ptr, ptr %h.addr
  %ld713 = load ptr, ptr %$t130.addr
  %rc714 = load i64, ptr %ld711, align 8
  %uniq715 = icmp eq i64 %rc714, 1
  %fbip_slot716 = alloca ptr
  br i1 %uniq715, label %fbip_reuse103, label %fbip_fresh104
fbip_reuse103:
  %tgp717 = getelementptr i8, ptr %ld711, i64 8
  store i32 1, ptr %tgp717, align 4
  %fp718 = getelementptr i8, ptr %ld711, i64 16
  store ptr %ld712, ptr %fp718, align 8
  %fp719 = getelementptr i8, ptr %ld711, i64 24
  store ptr %ld713, ptr %fp719, align 8
  store ptr %ld711, ptr %fbip_slot716
  br label %fbip_merge105
fbip_fresh104:
  call void @march_decrc(ptr %ld711)
  %hp720 = call ptr @march_alloc(i64 32)
  %tgp721 = getelementptr i8, ptr %hp720, i64 8
  store i32 1, ptr %tgp721, align 4
  %fp722 = getelementptr i8, ptr %hp720, i64 16
  store ptr %ld712, ptr %fp722, align 8
  %fp723 = getelementptr i8, ptr %hp720, i64 24
  store ptr %ld713, ptr %fp723, align 8
  store ptr %hp720, ptr %fbip_slot716
  br label %fbip_merge105
fbip_merge105:
  %fbip_r724 = load ptr, ptr %fbip_slot716
  store ptr %fbip_r724, ptr %res_slot697
  br label %case_merge99
case_default100:
  unreachable
case_merge99:
  %case_r725 = load ptr, ptr %res_slot697
  ret ptr %case_r725
}

define ptr @handle_post$Pid_V__6083$V__6048(ptr %counter.arg, ptr %conn.arg) {
entry:
  %counter.addr = alloca ptr
  store ptr %counter.arg, ptr %counter.addr
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld726 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld726)
  %ld727 = load ptr, ptr %conn.addr
  %cr728 = call ptr @HttpServer.path(ptr %ld727)
  %p.addr = alloca ptr
  store ptr %cr728, ptr %p.addr
  %ld729 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld729)
  %ld730 = load ptr, ptr %conn.addr
  %cr731 = call ptr @HttpServer.req_body(ptr %ld730)
  %body.addr = alloca ptr
  store ptr %cr731, ptr %body.addr
  %ld732 = load ptr, ptr %body.addr
  %cr733 = call ptr @march_string_to_int(ptr %ld732)
  %maybe_n.addr = alloca ptr
  store ptr %cr733, ptr %maybe_n.addr
  %ld734 = load ptr, ptr %maybe_n.addr
  %res_slot735 = alloca ptr
  %tgp736 = getelementptr i8, ptr %ld734, i64 8
  %tag737 = load i32, ptr %tgp736, align 4
  switch i32 %tag737, label %case_default107 [
      i32 0, label %case_br108
      i32 1, label %case_br109
  ]
case_br108:
  %ld738 = load ptr, ptr %maybe_n.addr
  call void @march_decrc(ptr %ld738)
  %ld739 = load ptr, ptr %conn.addr
  %conn_i42.addr = alloca ptr
  store ptr %ld739, ptr %conn_i42.addr
  %resp_status_i43.addr = alloca i64
  store i64 400, ptr %resp_status_i43.addr
  %sl740 = call ptr @march_string_lit(ptr @.str25, i64 36)
  %body_i44.addr = alloca ptr
  store ptr %sl740, ptr %body_i44.addr
  %ld741 = load ptr, ptr %conn_i42.addr
  %sl742 = call ptr @march_string_lit(ptr @.str26, i64 12)
  %sl743 = call ptr @march_string_lit(ptr @.str27, i64 25)
  %cr744 = call ptr @HttpServer.put_resp_header(ptr %ld741, ptr %sl742, ptr %sl743)
  %$t1980_i45.addr = alloca ptr
  store ptr %cr744, ptr %$t1980_i45.addr
  %ld745 = load ptr, ptr %$t1980_i45.addr
  %ld746 = load i64, ptr %resp_status_i43.addr
  %ld747 = load ptr, ptr %body_i44.addr
  %cr748 = call ptr @HttpServer.send_resp(ptr %ld745, i64 %ld746, ptr %ld747)
  store ptr %cr748, ptr %res_slot735
  br label %case_merge106
case_br109:
  %fp749 = getelementptr i8, ptr %ld734, i64 16
  %fv750 = load ptr, ptr %fp749, align 8
  %$f2022.addr = alloca ptr
  store ptr %fv750, ptr %$f2022.addr
  %ld751 = load ptr, ptr %maybe_n.addr
  call void @march_decrc(ptr %ld751)
  %ld752 = load ptr, ptr %$f2022.addr
  %n.addr = alloca ptr
  store ptr %ld752, ptr %n.addr
  %ld753 = load ptr, ptr %p.addr
  call void @march_incrc(ptr %ld753)
  %ld754 = load ptr, ptr %p.addr
  %sl755 = call ptr @march_string_lit(ptr @.str28, i64 10)
  %cr756 = call i64 @march_string_eq(ptr %ld754, ptr %sl755)
  %$t2018.addr = alloca i64
  store i64 %cr756, ptr %$t2018.addr
  %ld757 = load i64, ptr %$t2018.addr
  %res_slot758 = alloca ptr
  %bi759 = trunc i64 %ld757 to i1
  br i1 %bi759, label %case_br112, label %case_default111
case_br112:
  %ld760 = load ptr, ptr %counter.addr
  %ld761 = load ptr, ptr %n.addr
  %cr762 = call ptr @do_increment$Pid_V__6083$Int(ptr %ld760, ptr %ld761)
  %$t2019.addr = alloca ptr
  store ptr %cr762, ptr %$t2019.addr
  %ld763 = load ptr, ptr %conn.addr
  %conn_i54.addr = alloca ptr
  store ptr %ld763, ptr %conn_i54.addr
  %resp_status_i55.addr = alloca i64
  store i64 200, ptr %resp_status_i55.addr
  %ld764 = load ptr, ptr %$t2019.addr
  %body_i56.addr = alloca ptr
  store ptr %ld764, ptr %body_i56.addr
  %ld765 = load ptr, ptr %conn_i54.addr
  %sl766 = call ptr @march_string_lit(ptr @.str29, i64 12)
  %sl767 = call ptr @march_string_lit(ptr @.str30, i64 25)
  %cr768 = call ptr @HttpServer.put_resp_header(ptr %ld765, ptr %sl766, ptr %sl767)
  %$t1980_i57.addr = alloca ptr
  store ptr %cr768, ptr %$t1980_i57.addr
  %ld769 = load ptr, ptr %$t1980_i57.addr
  %ld770 = load i64, ptr %resp_status_i55.addr
  %ld771 = load ptr, ptr %body_i56.addr
  %cr772 = call ptr @HttpServer.send_resp(ptr %ld769, i64 %ld770, ptr %ld771)
  store ptr %cr772, ptr %res_slot758
  br label %case_merge110
case_default111:
  %ld773 = load ptr, ptr %p.addr
  %sl774 = call ptr @march_string_lit(ptr @.str31, i64 10)
  %cr775 = call i64 @march_string_eq(ptr %ld773, ptr %sl774)
  %$t2020.addr = alloca i64
  store i64 %cr775, ptr %$t2020.addr
  %ld776 = load i64, ptr %$t2020.addr
  %res_slot777 = alloca ptr
  %bi778 = trunc i64 %ld776 to i1
  br i1 %bi778, label %case_br115, label %case_default114
case_br115:
  %ld779 = load ptr, ptr %counter.addr
  %ld780 = load ptr, ptr %n.addr
  %cr781 = call ptr @do_decrement$Pid_V__6083$Int(ptr %ld779, ptr %ld780)
  %$t2021.addr = alloca ptr
  store ptr %cr781, ptr %$t2021.addr
  %ld782 = load ptr, ptr %conn.addr
  %conn_i50.addr = alloca ptr
  store ptr %ld782, ptr %conn_i50.addr
  %resp_status_i51.addr = alloca i64
  store i64 200, ptr %resp_status_i51.addr
  %ld783 = load ptr, ptr %$t2021.addr
  %body_i52.addr = alloca ptr
  store ptr %ld783, ptr %body_i52.addr
  %ld784 = load ptr, ptr %conn_i50.addr
  %sl785 = call ptr @march_string_lit(ptr @.str32, i64 12)
  %sl786 = call ptr @march_string_lit(ptr @.str33, i64 25)
  %cr787 = call ptr @HttpServer.put_resp_header(ptr %ld784, ptr %sl785, ptr %sl786)
  %$t1980_i53.addr = alloca ptr
  store ptr %cr787, ptr %$t1980_i53.addr
  %ld788 = load ptr, ptr %$t1980_i53.addr
  %ld789 = load i64, ptr %resp_status_i51.addr
  %ld790 = load ptr, ptr %body_i52.addr
  %cr791 = call ptr @HttpServer.send_resp(ptr %ld788, i64 %ld789, ptr %ld790)
  store ptr %cr791, ptr %res_slot777
  br label %case_merge113
case_default114:
  %ld792 = load ptr, ptr %conn.addr
  %conn_i46.addr = alloca ptr
  store ptr %ld792, ptr %conn_i46.addr
  %resp_status_i47.addr = alloca i64
  store i64 404, ptr %resp_status_i47.addr
  %sl793 = call ptr @march_string_lit(ptr @.str34, i64 9)
  %body_i48.addr = alloca ptr
  store ptr %sl793, ptr %body_i48.addr
  %ld794 = load ptr, ptr %conn_i46.addr
  %sl795 = call ptr @march_string_lit(ptr @.str35, i64 12)
  %sl796 = call ptr @march_string_lit(ptr @.str36, i64 25)
  %cr797 = call ptr @HttpServer.put_resp_header(ptr %ld794, ptr %sl795, ptr %sl796)
  %$t1980_i49.addr = alloca ptr
  store ptr %cr797, ptr %$t1980_i49.addr
  %ld798 = load ptr, ptr %$t1980_i49.addr
  %ld799 = load i64, ptr %resp_status_i47.addr
  %ld800 = load ptr, ptr %body_i48.addr
  %cr801 = call ptr @HttpServer.send_resp(ptr %ld798, i64 %ld799, ptr %ld800)
  store ptr %cr801, ptr %res_slot777
  br label %case_merge113
case_merge113:
  %case_r802 = load ptr, ptr %res_slot777
  store ptr %case_r802, ptr %res_slot758
  br label %case_merge110
case_merge110:
  %case_r803 = load ptr, ptr %res_slot758
  store ptr %case_r803, ptr %res_slot735
  br label %case_merge106
case_default107:
  unreachable
case_merge106:
  %case_r804 = load ptr, ptr %res_slot735
  ret ptr %case_r804
}

define ptr @List.append$List_V__744$List_V__744(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld805 = load ptr, ptr %xs.addr
  %res_slot806 = alloca ptr
  %tgp807 = getelementptr i8, ptr %ld805, i64 8
  %tag808 = load i32, ptr %tgp807, align 4
  switch i32 %tag808, label %case_default117 [
      i32 0, label %case_br118
      i32 1, label %case_br119
  ]
case_br118:
  %ld809 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld809)
  %ld810 = load ptr, ptr %ys.addr
  store ptr %ld810, ptr %res_slot806
  br label %case_merge116
case_br119:
  %fp811 = getelementptr i8, ptr %ld805, i64 16
  %fv812 = load ptr, ptr %fp811, align 8
  %$f131.addr = alloca ptr
  store ptr %fv812, ptr %$f131.addr
  %fp813 = getelementptr i8, ptr %ld805, i64 24
  %fv814 = load ptr, ptr %fp813, align 8
  %$f132.addr = alloca ptr
  store ptr %fv814, ptr %$f132.addr
  %ld815 = load ptr, ptr %$f132.addr
  %t.addr = alloca ptr
  store ptr %ld815, ptr %t.addr
  %ld816 = load ptr, ptr %$f131.addr
  %h.addr = alloca ptr
  store ptr %ld816, ptr %h.addr
  %ld817 = load ptr, ptr %t.addr
  %ld818 = load ptr, ptr %ys.addr
  %cr819 = call ptr @List.append$List_V__744$List_V__744(ptr %ld817, ptr %ld818)
  %$t130.addr = alloca ptr
  store ptr %cr819, ptr %$t130.addr
  %ld820 = load ptr, ptr %xs.addr
  %ld821 = load ptr, ptr %h.addr
  %ld822 = load ptr, ptr %$t130.addr
  %rc823 = load i64, ptr %ld820, align 8
  %uniq824 = icmp eq i64 %rc823, 1
  %fbip_slot825 = alloca ptr
  br i1 %uniq824, label %fbip_reuse120, label %fbip_fresh121
fbip_reuse120:
  %tgp826 = getelementptr i8, ptr %ld820, i64 8
  store i32 1, ptr %tgp826, align 4
  %fp827 = getelementptr i8, ptr %ld820, i64 16
  store ptr %ld821, ptr %fp827, align 8
  %fp828 = getelementptr i8, ptr %ld820, i64 24
  store ptr %ld822, ptr %fp828, align 8
  store ptr %ld820, ptr %fbip_slot825
  br label %fbip_merge122
fbip_fresh121:
  call void @march_decrc(ptr %ld820)
  %hp829 = call ptr @march_alloc(i64 32)
  %tgp830 = getelementptr i8, ptr %hp829, i64 8
  store i32 1, ptr %tgp830, align 4
  %fp831 = getelementptr i8, ptr %hp829, i64 16
  store ptr %ld821, ptr %fp831, align 8
  %fp832 = getelementptr i8, ptr %hp829, i64 24
  store ptr %ld822, ptr %fp832, align 8
  store ptr %hp829, ptr %fbip_slot825
  br label %fbip_merge122
fbip_merge122:
  %fbip_r833 = load ptr, ptr %fbip_slot825
  store ptr %fbip_r833, ptr %res_slot806
  br label %case_merge116
case_default117:
  unreachable
case_merge116:
  %case_r834 = load ptr, ptr %res_slot806
  ret ptr %case_r834
}

define ptr @do_increment$Pid_V__6083$Int(ptr %counter.arg, i64 %n.arg) {
entry:
  %counter.addr = alloca ptr
  store ptr %counter.arg, ptr %counter.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %hp835 = call ptr @march_alloc(i64 24)
  %tgp836 = getelementptr i8, ptr %hp835, i64 8
  store i32 0, ptr %tgp836, align 4
  %ld837 = load i64, ptr %n.addr
  %fp838 = getelementptr i8, ptr %hp835, i64 16
  store i64 %ld837, ptr %fp838, align 8
  %$t2014.addr = alloca ptr
  store ptr %hp835, ptr %$t2014.addr
  %ld839 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld839)
  %ld840 = load ptr, ptr %counter.addr
  %ld841 = load ptr, ptr %$t2014.addr
  %cr842 = call ptr @march_send(ptr %ld840, ptr %ld841)
  %$p2015.addr = alloca ptr
  store ptr %cr842, ptr %$p2015.addr
  %ld843 = load ptr, ptr %$p2015.addr
  call void @march_decrc(ptr %ld843)
  %ld844 = load ptr, ptr %counter.addr
  %counter_i58.addr = alloca ptr
  store ptr %ld844, ptr %counter_i58.addr
  %ld845 = load ptr, ptr %counter_i58.addr
  %cr846 = call i64 @march_actor_get_int(ptr %ld845, i64 0)
  %$t2013_i59.addr = alloca i64
  store i64 %cr846, ptr %$t2013_i59.addr
  %ld847 = load i64, ptr %$t2013_i59.addr
  %cr848 = call ptr @march_int_to_string(i64 %ld847)
  ret ptr %cr848
}

define ptr @do_decrement$Pid_V__6083$Int(ptr %counter.arg, i64 %n.arg) {
entry:
  %counter.addr = alloca ptr
  store ptr %counter.arg, ptr %counter.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %hp849 = call ptr @march_alloc(i64 24)
  %tgp850 = getelementptr i8, ptr %hp849, i64 8
  store i32 1, ptr %tgp850, align 4
  %ld851 = load i64, ptr %n.addr
  %fp852 = getelementptr i8, ptr %hp849, i64 16
  store i64 %ld851, ptr %fp852, align 8
  %$t2016.addr = alloca ptr
  store ptr %hp849, ptr %$t2016.addr
  %ld853 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld853)
  %ld854 = load ptr, ptr %counter.addr
  %ld855 = load ptr, ptr %$t2016.addr
  %cr856 = call ptr @march_send(ptr %ld854, ptr %ld855)
  %$p2017.addr = alloca ptr
  store ptr %cr856, ptr %$p2017.addr
  %ld857 = load ptr, ptr %$p2017.addr
  call void @march_decrc(ptr %ld857)
  %ld858 = load ptr, ptr %counter.addr
  %counter_i60.addr = alloca ptr
  store ptr %ld858, ptr %counter_i60.addr
  %ld859 = load ptr, ptr %counter_i60.addr
  %cr860 = call i64 @march_actor_get_int(ptr %ld859, i64 0)
  %$t2013_i61.addr = alloca i64
  store i64 %cr860, ptr %$t2013_i61.addr
  %ld861 = load i64, ptr %$t2013_i61.addr
  %cr862 = call ptr @march_int_to_string(i64 %ld861)
  ret ptr %cr862
}

define ptr @$lam2029$apply$22(ptr %$clo.arg, ptr %conn.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld863 = load ptr, ptr %$clo.addr
  %fp864 = getelementptr i8, ptr %ld863, i64 24
  %fv865 = load ptr, ptr %fp864, align 8
  %counter.addr = alloca ptr
  store ptr %fv865, ptr %counter.addr
  %ld866 = load ptr, ptr %counter.addr
  %ld867 = load ptr, ptr %conn.addr
  %cr868 = call ptr @router$Pid_V__6083$V__6048(ptr %ld866, ptr %ld867)
  ret ptr %cr868
}

define ptr @$lam2004$apply$25(ptr %$clo.arg, ptr %conn.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld869 = load ptr, ptr %$clo.addr
  %fp870 = getelementptr i8, ptr %ld869, i64 24
  %fv871 = load ptr, ptr %fp870, align 8
  %plugs.addr = alloca ptr
  store ptr %fv871, ptr %plugs.addr
  %ld872 = load ptr, ptr %conn.addr
  %ld873 = load ptr, ptr %plugs.addr
  %cr874 = call ptr @HttpServer.run_pipeline(ptr %ld872, ptr %ld873)
  ret ptr %cr874
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @Counter_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Counter_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

