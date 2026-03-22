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

@.str1 = private unnamed_addr constant [27 x i8] c"Hello from compiled March!\00"
@.str2 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str3 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str4 = private unnamed_addr constant [10 x i8] c"Not Found\00"
@.str5 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str6 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str7 = private unnamed_addr constant [10 x i8] c"Not Found\00"
@.str8 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str9 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"
@.str10 = private unnamed_addr constant [10 x i8] c"Not Found\00"
@.str11 = private unnamed_addr constant [13 x i8] c"content-type\00"
@.str12 = private unnamed_addr constant [26 x i8] c"text/plain; charset=utf-8\00"

define ptr @HttpServer.method(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld1 = load ptr, ptr %conn.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
  ]
case_br3:
  %fp5 = getelementptr i8, ptr %ld1, i64 16
  %fv6 = load i64, ptr %fp5, align 8
  %$f1742.addr = alloca i64
  store i64 %fv6, ptr %$f1742.addr
  %fp7 = getelementptr i8, ptr %ld1, i64 24
  %fv8 = load ptr, ptr %fp7, align 8
  %$f1743.addr = alloca ptr
  store ptr %fv8, ptr %$f1743.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 32
  %fv10 = load ptr, ptr %fp9, align 8
  %$f1744.addr = alloca ptr
  store ptr %fv10, ptr %$f1744.addr
  %fp11 = getelementptr i8, ptr %ld1, i64 40
  %fv12 = load ptr, ptr %fp11, align 8
  %$f1745.addr = alloca ptr
  store ptr %fv12, ptr %$f1745.addr
  %fp13 = getelementptr i8, ptr %ld1, i64 48
  %fv14 = load ptr, ptr %fp13, align 8
  %$f1746.addr = alloca ptr
  store ptr %fv14, ptr %$f1746.addr
  %fp15 = getelementptr i8, ptr %ld1, i64 56
  %fv16 = load ptr, ptr %fp15, align 8
  %$f1747.addr = alloca ptr
  store ptr %fv16, ptr %$f1747.addr
  %fp17 = getelementptr i8, ptr %ld1, i64 64
  %fv18 = load ptr, ptr %fp17, align 8
  %$f1748.addr = alloca ptr
  store ptr %fv18, ptr %$f1748.addr
  %fp19 = getelementptr i8, ptr %ld1, i64 72
  %fv20 = load i64, ptr %fp19, align 8
  %$f1749.addr = alloca i64
  store i64 %fv20, ptr %$f1749.addr
  %fp21 = getelementptr i8, ptr %ld1, i64 80
  %fv22 = load ptr, ptr %fp21, align 8
  %$f1750.addr = alloca ptr
  store ptr %fv22, ptr %$f1750.addr
  %fp23 = getelementptr i8, ptr %ld1, i64 88
  %fv24 = load ptr, ptr %fp23, align 8
  %$f1751.addr = alloca ptr
  store ptr %fv24, ptr %$f1751.addr
  %fp25 = getelementptr i8, ptr %ld1, i64 96
  %fv26 = load i64, ptr %fp25, align 8
  %$f1752.addr = alloca i64
  store i64 %fv26, ptr %$f1752.addr
  %fp27 = getelementptr i8, ptr %ld1, i64 104
  %fv28 = load ptr, ptr %fp27, align 8
  %$f1753.addr = alloca ptr
  store ptr %fv28, ptr %$f1753.addr
  %fp29 = getelementptr i8, ptr %ld1, i64 112
  %fv30 = load ptr, ptr %fp29, align 8
  %$f1754.addr = alloca ptr
  store ptr %fv30, ptr %$f1754.addr
  %freed31 = call i64 @march_decrc_freed(ptr %ld1)
  %freed_b32 = icmp ne i64 %freed31, 0
  br i1 %freed_b32, label %br_unique4, label %br_shared5
br_shared5:
  call void @march_incrc(ptr %fv30)
  call void @march_incrc(ptr %fv28)
  call void @march_incrc(ptr %fv24)
  call void @march_incrc(ptr %fv22)
  call void @march_incrc(ptr %fv18)
  call void @march_incrc(ptr %fv16)
  call void @march_incrc(ptr %fv14)
  call void @march_incrc(ptr %fv12)
  call void @march_incrc(ptr %fv10)
  call void @march_incrc(ptr %fv8)
  br label %br_body6
br_unique4:
  br label %br_body6
br_body6:
  %ld33 = load ptr, ptr %$f1743.addr
  %m.addr = alloca ptr
  store ptr %ld33, ptr %m.addr
  %ld34 = load ptr, ptr %m.addr
  store ptr %ld34, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r35 = load ptr, ptr %res_slot2
  ret ptr %case_r35
}

define ptr @HttpServer.path_info(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld36 = load ptr, ptr %conn.addr
  %res_slot37 = alloca ptr
  %tgp38 = getelementptr i8, ptr %ld36, i64 8
  %tag39 = load i32, ptr %tgp38, align 4
  switch i32 %tag39, label %case_default8 [
      i32 0, label %case_br9
  ]
case_br9:
  %fp40 = getelementptr i8, ptr %ld36, i64 16
  %fv41 = load i64, ptr %fp40, align 8
  %$f1768.addr = alloca i64
  store i64 %fv41, ptr %$f1768.addr
  %fp42 = getelementptr i8, ptr %ld36, i64 24
  %fv43 = load ptr, ptr %fp42, align 8
  %$f1769.addr = alloca ptr
  store ptr %fv43, ptr %$f1769.addr
  %fp44 = getelementptr i8, ptr %ld36, i64 32
  %fv45 = load ptr, ptr %fp44, align 8
  %$f1770.addr = alloca ptr
  store ptr %fv45, ptr %$f1770.addr
  %fp46 = getelementptr i8, ptr %ld36, i64 40
  %fv47 = load ptr, ptr %fp46, align 8
  %$f1771.addr = alloca ptr
  store ptr %fv47, ptr %$f1771.addr
  %fp48 = getelementptr i8, ptr %ld36, i64 48
  %fv49 = load ptr, ptr %fp48, align 8
  %$f1772.addr = alloca ptr
  store ptr %fv49, ptr %$f1772.addr
  %fp50 = getelementptr i8, ptr %ld36, i64 56
  %fv51 = load ptr, ptr %fp50, align 8
  %$f1773.addr = alloca ptr
  store ptr %fv51, ptr %$f1773.addr
  %fp52 = getelementptr i8, ptr %ld36, i64 64
  %fv53 = load ptr, ptr %fp52, align 8
  %$f1774.addr = alloca ptr
  store ptr %fv53, ptr %$f1774.addr
  %fp54 = getelementptr i8, ptr %ld36, i64 72
  %fv55 = load i64, ptr %fp54, align 8
  %$f1775.addr = alloca i64
  store i64 %fv55, ptr %$f1775.addr
  %fp56 = getelementptr i8, ptr %ld36, i64 80
  %fv57 = load ptr, ptr %fp56, align 8
  %$f1776.addr = alloca ptr
  store ptr %fv57, ptr %$f1776.addr
  %fp58 = getelementptr i8, ptr %ld36, i64 88
  %fv59 = load ptr, ptr %fp58, align 8
  %$f1777.addr = alloca ptr
  store ptr %fv59, ptr %$f1777.addr
  %fp60 = getelementptr i8, ptr %ld36, i64 96
  %fv61 = load i64, ptr %fp60, align 8
  %$f1778.addr = alloca i64
  store i64 %fv61, ptr %$f1778.addr
  %fp62 = getelementptr i8, ptr %ld36, i64 104
  %fv63 = load ptr, ptr %fp62, align 8
  %$f1779.addr = alloca ptr
  store ptr %fv63, ptr %$f1779.addr
  %fp64 = getelementptr i8, ptr %ld36, i64 112
  %fv65 = load ptr, ptr %fp64, align 8
  %$f1780.addr = alloca ptr
  store ptr %fv65, ptr %$f1780.addr
  %freed66 = call i64 @march_decrc_freed(ptr %ld36)
  %freed_b67 = icmp ne i64 %freed66, 0
  br i1 %freed_b67, label %br_unique10, label %br_shared11
br_shared11:
  call void @march_incrc(ptr %fv65)
  call void @march_incrc(ptr %fv63)
  call void @march_incrc(ptr %fv59)
  call void @march_incrc(ptr %fv57)
  call void @march_incrc(ptr %fv53)
  call void @march_incrc(ptr %fv51)
  call void @march_incrc(ptr %fv49)
  call void @march_incrc(ptr %fv47)
  call void @march_incrc(ptr %fv45)
  call void @march_incrc(ptr %fv43)
  br label %br_body12
br_unique10:
  br label %br_body12
br_body12:
  %ld68 = load ptr, ptr %$f1771.addr
  %pi.addr = alloca ptr
  store ptr %ld68, ptr %pi.addr
  %ld69 = load ptr, ptr %pi.addr
  store ptr %ld69, ptr %res_slot37
  br label %case_merge7
case_default8:
  unreachable
case_merge7:
  %case_r70 = load ptr, ptr %res_slot37
  ret ptr %case_r70
}

define i64 @HttpServer.halted(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld71 = load ptr, ptr %conn.addr
  %res_slot72 = alloca ptr
  %tgp73 = getelementptr i8, ptr %ld71, i64 8
  %tag74 = load i32, ptr %tgp73, align 4
  switch i32 %tag74, label %case_default14 [
      i32 0, label %case_br15
  ]
case_br15:
  %fp75 = getelementptr i8, ptr %ld71, i64 16
  %fv76 = load i64, ptr %fp75, align 8
  %$f1859.addr = alloca i64
  store i64 %fv76, ptr %$f1859.addr
  %fp77 = getelementptr i8, ptr %ld71, i64 24
  %fv78 = load ptr, ptr %fp77, align 8
  %$f1860.addr = alloca ptr
  store ptr %fv78, ptr %$f1860.addr
  %fp79 = getelementptr i8, ptr %ld71, i64 32
  %fv80 = load ptr, ptr %fp79, align 8
  %$f1861.addr = alloca ptr
  store ptr %fv80, ptr %$f1861.addr
  %fp81 = getelementptr i8, ptr %ld71, i64 40
  %fv82 = load ptr, ptr %fp81, align 8
  %$f1862.addr = alloca ptr
  store ptr %fv82, ptr %$f1862.addr
  %fp83 = getelementptr i8, ptr %ld71, i64 48
  %fv84 = load ptr, ptr %fp83, align 8
  %$f1863.addr = alloca ptr
  store ptr %fv84, ptr %$f1863.addr
  %fp85 = getelementptr i8, ptr %ld71, i64 56
  %fv86 = load ptr, ptr %fp85, align 8
  %$f1864.addr = alloca ptr
  store ptr %fv86, ptr %$f1864.addr
  %fp87 = getelementptr i8, ptr %ld71, i64 64
  %fv88 = load ptr, ptr %fp87, align 8
  %$f1865.addr = alloca ptr
  store ptr %fv88, ptr %$f1865.addr
  %fp89 = getelementptr i8, ptr %ld71, i64 72
  %fv90 = load i64, ptr %fp89, align 8
  %$f1866.addr = alloca i64
  store i64 %fv90, ptr %$f1866.addr
  %fp91 = getelementptr i8, ptr %ld71, i64 80
  %fv92 = load ptr, ptr %fp91, align 8
  %$f1867.addr = alloca ptr
  store ptr %fv92, ptr %$f1867.addr
  %fp93 = getelementptr i8, ptr %ld71, i64 88
  %fv94 = load ptr, ptr %fp93, align 8
  %$f1868.addr = alloca ptr
  store ptr %fv94, ptr %$f1868.addr
  %fp95 = getelementptr i8, ptr %ld71, i64 96
  %fv96 = load i64, ptr %fp95, align 8
  %$f1869.addr = alloca i64
  store i64 %fv96, ptr %$f1869.addr
  %fp97 = getelementptr i8, ptr %ld71, i64 104
  %fv98 = load ptr, ptr %fp97, align 8
  %$f1870.addr = alloca ptr
  store ptr %fv98, ptr %$f1870.addr
  %fp99 = getelementptr i8, ptr %ld71, i64 112
  %fv100 = load ptr, ptr %fp99, align 8
  %$f1871.addr = alloca ptr
  store ptr %fv100, ptr %$f1871.addr
  %freed101 = call i64 @march_decrc_freed(ptr %ld71)
  %freed_b102 = icmp ne i64 %freed101, 0
  br i1 %freed_b102, label %br_unique16, label %br_shared17
br_shared17:
  call void @march_incrc(ptr %fv100)
  call void @march_incrc(ptr %fv98)
  call void @march_incrc(ptr %fv94)
  call void @march_incrc(ptr %fv92)
  call void @march_incrc(ptr %fv88)
  call void @march_incrc(ptr %fv86)
  call void @march_incrc(ptr %fv84)
  call void @march_incrc(ptr %fv82)
  call void @march_incrc(ptr %fv80)
  call void @march_incrc(ptr %fv78)
  br label %br_body18
br_unique16:
  br label %br_body18
br_body18:
  %ld103 = load i64, ptr %$f1869.addr
  %h.addr = alloca i64
  store i64 %ld103, ptr %h.addr
  %ld104 = load i64, ptr %h.addr
  %cv105 = inttoptr i64 %ld104 to ptr
  store ptr %cv105, ptr %res_slot72
  br label %case_merge13
case_default14:
  unreachable
case_merge13:
  %case_r106 = load ptr, ptr %res_slot72
  %cv107 = ptrtoint ptr %case_r106 to i64
  ret i64 %cv107
}

define i64 @HttpServer.fd(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld108 = load ptr, ptr %conn.addr
  %res_slot109 = alloca ptr
  %tgp110 = getelementptr i8, ptr %ld108, i64 8
  %tag111 = load i32, ptr %tgp110, align 4
  switch i32 %tag111, label %case_default20 [
      i32 0, label %case_br21
  ]
case_br21:
  %fp112 = getelementptr i8, ptr %ld108, i64 16
  %fv113 = load i64, ptr %fp112, align 8
  %$f1898.addr = alloca i64
  store i64 %fv113, ptr %$f1898.addr
  %fp114 = getelementptr i8, ptr %ld108, i64 24
  %fv115 = load ptr, ptr %fp114, align 8
  %$f1899.addr = alloca ptr
  store ptr %fv115, ptr %$f1899.addr
  %fp116 = getelementptr i8, ptr %ld108, i64 32
  %fv117 = load ptr, ptr %fp116, align 8
  %$f1900.addr = alloca ptr
  store ptr %fv117, ptr %$f1900.addr
  %fp118 = getelementptr i8, ptr %ld108, i64 40
  %fv119 = load ptr, ptr %fp118, align 8
  %$f1901.addr = alloca ptr
  store ptr %fv119, ptr %$f1901.addr
  %fp120 = getelementptr i8, ptr %ld108, i64 48
  %fv121 = load ptr, ptr %fp120, align 8
  %$f1902.addr = alloca ptr
  store ptr %fv121, ptr %$f1902.addr
  %fp122 = getelementptr i8, ptr %ld108, i64 56
  %fv123 = load ptr, ptr %fp122, align 8
  %$f1903.addr = alloca ptr
  store ptr %fv123, ptr %$f1903.addr
  %fp124 = getelementptr i8, ptr %ld108, i64 64
  %fv125 = load ptr, ptr %fp124, align 8
  %$f1904.addr = alloca ptr
  store ptr %fv125, ptr %$f1904.addr
  %fp126 = getelementptr i8, ptr %ld108, i64 72
  %fv127 = load i64, ptr %fp126, align 8
  %$f1905.addr = alloca i64
  store i64 %fv127, ptr %$f1905.addr
  %fp128 = getelementptr i8, ptr %ld108, i64 80
  %fv129 = load ptr, ptr %fp128, align 8
  %$f1906.addr = alloca ptr
  store ptr %fv129, ptr %$f1906.addr
  %fp130 = getelementptr i8, ptr %ld108, i64 88
  %fv131 = load ptr, ptr %fp130, align 8
  %$f1907.addr = alloca ptr
  store ptr %fv131, ptr %$f1907.addr
  %fp132 = getelementptr i8, ptr %ld108, i64 96
  %fv133 = load i64, ptr %fp132, align 8
  %$f1908.addr = alloca i64
  store i64 %fv133, ptr %$f1908.addr
  %fp134 = getelementptr i8, ptr %ld108, i64 104
  %fv135 = load ptr, ptr %fp134, align 8
  %$f1909.addr = alloca ptr
  store ptr %fv135, ptr %$f1909.addr
  %fp136 = getelementptr i8, ptr %ld108, i64 112
  %fv137 = load ptr, ptr %fp136, align 8
  %$f1910.addr = alloca ptr
  store ptr %fv137, ptr %$f1910.addr
  %freed138 = call i64 @march_decrc_freed(ptr %ld108)
  %freed_b139 = icmp ne i64 %freed138, 0
  br i1 %freed_b139, label %br_unique22, label %br_shared23
br_shared23:
  call void @march_incrc(ptr %fv137)
  call void @march_incrc(ptr %fv135)
  call void @march_incrc(ptr %fv131)
  call void @march_incrc(ptr %fv129)
  call void @march_incrc(ptr %fv125)
  call void @march_incrc(ptr %fv123)
  call void @march_incrc(ptr %fv121)
  call void @march_incrc(ptr %fv119)
  call void @march_incrc(ptr %fv117)
  call void @march_incrc(ptr %fv115)
  br label %br_body24
br_unique22:
  br label %br_body24
br_body24:
  %ld140 = load i64, ptr %$f1898.addr
  %f.addr = alloca i64
  store i64 %ld140, ptr %f.addr
  %ld141 = load i64, ptr %f.addr
  %cv142 = inttoptr i64 %ld141 to ptr
  store ptr %cv142, ptr %res_slot109
  br label %case_merge19
case_default20:
  unreachable
case_merge19:
  %case_r143 = load ptr, ptr %res_slot109
  %cv144 = ptrtoint ptr %case_r143 to i64
  ret i64 %cv144
}

define ptr @HttpServer.put_resp_header(ptr %conn.arg, ptr %name.arg, ptr %value.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %value.addr = alloca ptr
  store ptr %value.arg, ptr %value.addr
  %ld145 = load ptr, ptr %conn.addr
  %res_slot146 = alloca ptr
  %tgp147 = getelementptr i8, ptr %ld145, i64 8
  %tag148 = load i32, ptr %tgp147, align 4
  switch i32 %tag148, label %case_default26 [
      i32 0, label %case_br27
  ]
case_br27:
  %fp149 = getelementptr i8, ptr %ld145, i64 16
  %fv150 = load i64, ptr %fp149, align 8
  %$f1926.addr = alloca i64
  store i64 %fv150, ptr %$f1926.addr
  %fp151 = getelementptr i8, ptr %ld145, i64 24
  %fv152 = load ptr, ptr %fp151, align 8
  %$f1927.addr = alloca ptr
  store ptr %fv152, ptr %$f1927.addr
  %fp153 = getelementptr i8, ptr %ld145, i64 32
  %fv154 = load ptr, ptr %fp153, align 8
  %$f1928.addr = alloca ptr
  store ptr %fv154, ptr %$f1928.addr
  %fp155 = getelementptr i8, ptr %ld145, i64 40
  %fv156 = load ptr, ptr %fp155, align 8
  %$f1929.addr = alloca ptr
  store ptr %fv156, ptr %$f1929.addr
  %fp157 = getelementptr i8, ptr %ld145, i64 48
  %fv158 = load ptr, ptr %fp157, align 8
  %$f1930.addr = alloca ptr
  store ptr %fv158, ptr %$f1930.addr
  %fp159 = getelementptr i8, ptr %ld145, i64 56
  %fv160 = load ptr, ptr %fp159, align 8
  %$f1931.addr = alloca ptr
  store ptr %fv160, ptr %$f1931.addr
  %fp161 = getelementptr i8, ptr %ld145, i64 64
  %fv162 = load ptr, ptr %fp161, align 8
  %$f1932.addr = alloca ptr
  store ptr %fv162, ptr %$f1932.addr
  %fp163 = getelementptr i8, ptr %ld145, i64 72
  %fv164 = load i64, ptr %fp163, align 8
  %$f1933.addr = alloca i64
  store i64 %fv164, ptr %$f1933.addr
  %fp165 = getelementptr i8, ptr %ld145, i64 80
  %fv166 = load ptr, ptr %fp165, align 8
  %$f1934.addr = alloca ptr
  store ptr %fv166, ptr %$f1934.addr
  %fp167 = getelementptr i8, ptr %ld145, i64 88
  %fv168 = load ptr, ptr %fp167, align 8
  %$f1935.addr = alloca ptr
  store ptr %fv168, ptr %$f1935.addr
  %fp169 = getelementptr i8, ptr %ld145, i64 96
  %fv170 = load i64, ptr %fp169, align 8
  %$f1936.addr = alloca i64
  store i64 %fv170, ptr %$f1936.addr
  %fp171 = getelementptr i8, ptr %ld145, i64 104
  %fv172 = load ptr, ptr %fp171, align 8
  %$f1937.addr = alloca ptr
  store ptr %fv172, ptr %$f1937.addr
  %fp173 = getelementptr i8, ptr %ld145, i64 112
  %fv174 = load ptr, ptr %fp173, align 8
  %$f1938.addr = alloca ptr
  store ptr %fv174, ptr %$f1938.addr
  %freed175 = call i64 @march_decrc_freed(ptr %ld145)
  %freed_b176 = icmp ne i64 %freed175, 0
  br i1 %freed_b176, label %br_unique28, label %br_shared29
br_shared29:
  call void @march_incrc(ptr %fv174)
  call void @march_incrc(ptr %fv172)
  call void @march_incrc(ptr %fv168)
  call void @march_incrc(ptr %fv166)
  call void @march_incrc(ptr %fv162)
  call void @march_incrc(ptr %fv160)
  call void @march_incrc(ptr %fv158)
  call void @march_incrc(ptr %fv156)
  call void @march_incrc(ptr %fv154)
  call void @march_incrc(ptr %fv152)
  br label %br_body30
br_unique28:
  br label %br_body30
br_body30:
  %ld177 = load ptr, ptr %$f1938.addr
  %u.addr = alloca ptr
  store ptr %ld177, ptr %u.addr
  %ld178 = load ptr, ptr %$f1937.addr
  %a.addr = alloca ptr
  store ptr %ld178, ptr %a.addr
  %ld179 = load i64, ptr %$f1936.addr
  %h.addr = alloca i64
  store i64 %ld179, ptr %h.addr
  %ld180 = load ptr, ptr %$f1935.addr
  %rbody.addr = alloca ptr
  store ptr %ld180, ptr %rbody.addr
  %ld181 = load ptr, ptr %$f1934.addr
  %rhs.addr = alloca ptr
  store ptr %ld181, ptr %rhs.addr
  %ld182 = load i64, ptr %$f1933.addr
  %s.addr = alloca i64
  store i64 %ld182, ptr %s.addr
  %ld183 = load ptr, ptr %$f1932.addr
  %rb.addr = alloca ptr
  store ptr %ld183, ptr %rb.addr
  %ld184 = load ptr, ptr %$f1931.addr
  %rh.addr = alloca ptr
  store ptr %ld184, ptr %rh.addr
  %ld185 = load ptr, ptr %$f1930.addr
  %qs.addr = alloca ptr
  store ptr %ld185, ptr %qs.addr
  %ld186 = load ptr, ptr %$f1929.addr
  %pi.addr = alloca ptr
  store ptr %ld186, ptr %pi.addr
  %ld187 = load ptr, ptr %$f1928.addr
  %p.addr = alloca ptr
  store ptr %ld187, ptr %p.addr
  %ld188 = load ptr, ptr %$f1927.addr
  %m.addr = alloca ptr
  store ptr %ld188, ptr %m.addr
  %ld189 = load i64, ptr %$f1926.addr
  %fd.addr = alloca i64
  store i64 %ld189, ptr %fd.addr
  %ld190 = load i64, ptr %fd.addr
  %hp191 = call ptr @march_alloc(i64 32)
  %tgp192 = getelementptr i8, ptr %hp191, i64 8
  store i32 0, ptr %tgp192, align 4
  %ld193 = load ptr, ptr %name.addr
  %fp194 = getelementptr i8, ptr %hp191, i64 16
  store ptr %ld193, ptr %fp194, align 8
  %ld195 = load ptr, ptr %value.addr
  %fp196 = getelementptr i8, ptr %hp191, i64 24
  store ptr %ld195, ptr %fp196, align 8
  %$t1924.addr = alloca ptr
  store ptr %hp191, ptr %$t1924.addr
  %hp197 = call ptr @march_alloc(i64 32)
  %tgp198 = getelementptr i8, ptr %hp197, i64 8
  store i32 1, ptr %tgp198, align 4
  %ld199 = load ptr, ptr %$t1924.addr
  %fp200 = getelementptr i8, ptr %hp197, i64 16
  store ptr %ld199, ptr %fp200, align 8
  %ld201 = load ptr, ptr %rhs.addr
  %fp202 = getelementptr i8, ptr %hp197, i64 24
  store ptr %ld201, ptr %fp202, align 8
  %$t1925.addr = alloca ptr
  store ptr %hp197, ptr %$t1925.addr
  %hp203 = call ptr @march_alloc(i64 120)
  %tgp204 = getelementptr i8, ptr %hp203, i64 8
  store i32 0, ptr %tgp204, align 4
  %cv205 = ptrtoint ptr @HttpServer.fd to i64
  %fp206 = getelementptr i8, ptr %hp203, i64 16
  store i64 %cv205, ptr %fp206, align 8
  %ld207 = load ptr, ptr %m.addr
  %fp208 = getelementptr i8, ptr %hp203, i64 24
  store ptr %ld207, ptr %fp208, align 8
  %ld209 = load ptr, ptr %p.addr
  %fp210 = getelementptr i8, ptr %hp203, i64 32
  store ptr %ld209, ptr %fp210, align 8
  %ld211 = load ptr, ptr %pi.addr
  %fp212 = getelementptr i8, ptr %hp203, i64 40
  store ptr %ld211, ptr %fp212, align 8
  %ld213 = load ptr, ptr %qs.addr
  %fp214 = getelementptr i8, ptr %hp203, i64 48
  store ptr %ld213, ptr %fp214, align 8
  %ld215 = load ptr, ptr %rh.addr
  %fp216 = getelementptr i8, ptr %hp203, i64 56
  store ptr %ld215, ptr %fp216, align 8
  %ld217 = load ptr, ptr %rb.addr
  %fp218 = getelementptr i8, ptr %hp203, i64 64
  store ptr %ld217, ptr %fp218, align 8
  %ld219 = load i64, ptr %s.addr
  %fp220 = getelementptr i8, ptr %hp203, i64 72
  store i64 %ld219, ptr %fp220, align 8
  %ld221 = load ptr, ptr %$t1925.addr
  %fp222 = getelementptr i8, ptr %hp203, i64 80
  store ptr %ld221, ptr %fp222, align 8
  %ld223 = load ptr, ptr %rbody.addr
  %fp224 = getelementptr i8, ptr %hp203, i64 88
  store ptr %ld223, ptr %fp224, align 8
  %ld225 = load i64, ptr %h.addr
  %fp226 = getelementptr i8, ptr %hp203, i64 96
  store i64 %ld225, ptr %fp226, align 8
  %ld227 = load ptr, ptr %a.addr
  %fp228 = getelementptr i8, ptr %hp203, i64 104
  store ptr %ld227, ptr %fp228, align 8
  %ld229 = load ptr, ptr %u.addr
  %fp230 = getelementptr i8, ptr %hp203, i64 112
  store ptr %ld229, ptr %fp230, align 8
  store ptr %hp203, ptr %res_slot146
  br label %case_merge25
case_default26:
  unreachable
case_merge25:
  %case_r231 = load ptr, ptr %res_slot146
  ret ptr %case_r231
}

define ptr @HttpServer.send_resp(ptr %conn.arg, i64 %resp_status.arg, ptr %body.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %resp_status.addr = alloca i64
  store i64 %resp_status.arg, ptr %resp_status.addr
  %body.addr = alloca ptr
  store ptr %body.arg, ptr %body.addr
  %ld232 = load ptr, ptr %conn.addr
  %res_slot233 = alloca ptr
  %tgp234 = getelementptr i8, ptr %ld232, i64 8
  %tag235 = load i32, ptr %tgp234, align 4
  switch i32 %tag235, label %case_default32 [
      i32 0, label %case_br33
  ]
case_br33:
  %fp236 = getelementptr i8, ptr %ld232, i64 16
  %fv237 = load i64, ptr %fp236, align 8
  %$f1954.addr = alloca i64
  store i64 %fv237, ptr %$f1954.addr
  %fp238 = getelementptr i8, ptr %ld232, i64 24
  %fv239 = load ptr, ptr %fp238, align 8
  %$f1955.addr = alloca ptr
  store ptr %fv239, ptr %$f1955.addr
  %fp240 = getelementptr i8, ptr %ld232, i64 32
  %fv241 = load ptr, ptr %fp240, align 8
  %$f1956.addr = alloca ptr
  store ptr %fv241, ptr %$f1956.addr
  %fp242 = getelementptr i8, ptr %ld232, i64 40
  %fv243 = load ptr, ptr %fp242, align 8
  %$f1957.addr = alloca ptr
  store ptr %fv243, ptr %$f1957.addr
  %fp244 = getelementptr i8, ptr %ld232, i64 48
  %fv245 = load ptr, ptr %fp244, align 8
  %$f1958.addr = alloca ptr
  store ptr %fv245, ptr %$f1958.addr
  %fp246 = getelementptr i8, ptr %ld232, i64 56
  %fv247 = load ptr, ptr %fp246, align 8
  %$f1959.addr = alloca ptr
  store ptr %fv247, ptr %$f1959.addr
  %fp248 = getelementptr i8, ptr %ld232, i64 64
  %fv249 = load ptr, ptr %fp248, align 8
  %$f1960.addr = alloca ptr
  store ptr %fv249, ptr %$f1960.addr
  %fp250 = getelementptr i8, ptr %ld232, i64 72
  %fv251 = load i64, ptr %fp250, align 8
  %$f1961.addr = alloca i64
  store i64 %fv251, ptr %$f1961.addr
  %fp252 = getelementptr i8, ptr %ld232, i64 80
  %fv253 = load ptr, ptr %fp252, align 8
  %$f1962.addr = alloca ptr
  store ptr %fv253, ptr %$f1962.addr
  %fp254 = getelementptr i8, ptr %ld232, i64 88
  %fv255 = load ptr, ptr %fp254, align 8
  %$f1963.addr = alloca ptr
  store ptr %fv255, ptr %$f1963.addr
  %fp256 = getelementptr i8, ptr %ld232, i64 96
  %fv257 = load i64, ptr %fp256, align 8
  %$f1964.addr = alloca i64
  store i64 %fv257, ptr %$f1964.addr
  %fp258 = getelementptr i8, ptr %ld232, i64 104
  %fv259 = load ptr, ptr %fp258, align 8
  %$f1965.addr = alloca ptr
  store ptr %fv259, ptr %$f1965.addr
  %fp260 = getelementptr i8, ptr %ld232, i64 112
  %fv261 = load ptr, ptr %fp260, align 8
  %$f1966.addr = alloca ptr
  store ptr %fv261, ptr %$f1966.addr
  %freed262 = call i64 @march_decrc_freed(ptr %ld232)
  %freed_b263 = icmp ne i64 %freed262, 0
  br i1 %freed_b263, label %br_unique34, label %br_shared35
br_shared35:
  call void @march_incrc(ptr %fv261)
  call void @march_incrc(ptr %fv259)
  call void @march_incrc(ptr %fv255)
  call void @march_incrc(ptr %fv253)
  call void @march_incrc(ptr %fv249)
  call void @march_incrc(ptr %fv247)
  call void @march_incrc(ptr %fv245)
  call void @march_incrc(ptr %fv243)
  call void @march_incrc(ptr %fv241)
  call void @march_incrc(ptr %fv239)
  br label %br_body36
br_unique34:
  br label %br_body36
br_body36:
  %ld264 = load ptr, ptr %$f1966.addr
  %u.addr = alloca ptr
  store ptr %ld264, ptr %u.addr
  %ld265 = load ptr, ptr %$f1965.addr
  %a.addr = alloca ptr
  store ptr %ld265, ptr %a.addr
  %ld266 = load ptr, ptr %$f1962.addr
  %rhs.addr = alloca ptr
  store ptr %ld266, ptr %rhs.addr
  %ld267 = load ptr, ptr %$f1960.addr
  %rb.addr = alloca ptr
  store ptr %ld267, ptr %rb.addr
  %ld268 = load ptr, ptr %$f1959.addr
  %rh.addr = alloca ptr
  store ptr %ld268, ptr %rh.addr
  %ld269 = load ptr, ptr %$f1958.addr
  %qs.addr = alloca ptr
  store ptr %ld269, ptr %qs.addr
  %ld270 = load ptr, ptr %$f1957.addr
  %pi.addr = alloca ptr
  store ptr %ld270, ptr %pi.addr
  %ld271 = load ptr, ptr %$f1956.addr
  %p.addr = alloca ptr
  store ptr %ld271, ptr %p.addr
  %ld272 = load ptr, ptr %$f1955.addr
  %m.addr = alloca ptr
  store ptr %ld272, ptr %m.addr
  %ld273 = load i64, ptr %$f1954.addr
  %fd.addr = alloca i64
  store i64 %ld273, ptr %fd.addr
  %ld274 = load i64, ptr %fd.addr
  %hp275 = call ptr @march_alloc(i64 120)
  %tgp276 = getelementptr i8, ptr %hp275, i64 8
  store i32 0, ptr %tgp276, align 4
  %cv277 = ptrtoint ptr @HttpServer.fd to i64
  %fp278 = getelementptr i8, ptr %hp275, i64 16
  store i64 %cv277, ptr %fp278, align 8
  %ld279 = load ptr, ptr %m.addr
  %fp280 = getelementptr i8, ptr %hp275, i64 24
  store ptr %ld279, ptr %fp280, align 8
  %ld281 = load ptr, ptr %p.addr
  %fp282 = getelementptr i8, ptr %hp275, i64 32
  store ptr %ld281, ptr %fp282, align 8
  %ld283 = load ptr, ptr %pi.addr
  %fp284 = getelementptr i8, ptr %hp275, i64 40
  store ptr %ld283, ptr %fp284, align 8
  %ld285 = load ptr, ptr %qs.addr
  %fp286 = getelementptr i8, ptr %hp275, i64 48
  store ptr %ld285, ptr %fp286, align 8
  %ld287 = load ptr, ptr %rh.addr
  %fp288 = getelementptr i8, ptr %hp275, i64 56
  store ptr %ld287, ptr %fp288, align 8
  %ld289 = load ptr, ptr %rb.addr
  %fp290 = getelementptr i8, ptr %hp275, i64 64
  store ptr %ld289, ptr %fp290, align 8
  %ld291 = load i64, ptr %resp_status.addr
  %fp292 = getelementptr i8, ptr %hp275, i64 72
  store i64 %ld291, ptr %fp292, align 8
  %ld293 = load ptr, ptr %rhs.addr
  %fp294 = getelementptr i8, ptr %hp275, i64 80
  store ptr %ld293, ptr %fp294, align 8
  %ld295 = load ptr, ptr %body.addr
  %fp296 = getelementptr i8, ptr %hp275, i64 88
  store ptr %ld295, ptr %fp296, align 8
  %fp297 = getelementptr i8, ptr %hp275, i64 96
  store i64 1, ptr %fp297, align 8
  %ld298 = load ptr, ptr %a.addr
  %fp299 = getelementptr i8, ptr %hp275, i64 104
  store ptr %ld298, ptr %fp299, align 8
  %ld300 = load ptr, ptr %u.addr
  %fp301 = getelementptr i8, ptr %hp275, i64 112
  store ptr %ld300, ptr %fp301, align 8
  store ptr %hp275, ptr %res_slot233
  br label %case_merge31
case_default32:
  unreachable
case_merge31:
  %case_r302 = load ptr, ptr %res_slot233
  ret ptr %case_r302
}

define ptr @HttpServer.run_pipeline(ptr %conn.arg, ptr %plugs.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %plugs.addr = alloca ptr
  store ptr %plugs.arg, ptr %plugs.addr
  %ld303 = load ptr, ptr %plugs.addr
  %res_slot304 = alloca ptr
  %tgp305 = getelementptr i8, ptr %ld303, i64 8
  %tag306 = load i32, ptr %tgp305, align 4
  switch i32 %tag306, label %case_default38 [
      i32 0, label %case_br39
      i32 1, label %case_br40
  ]
case_br39:
  %ld307 = load ptr, ptr %plugs.addr
  call void @march_decrc(ptr %ld307)
  %ld308 = load ptr, ptr %conn.addr
  store ptr %ld308, ptr %res_slot304
  br label %case_merge37
case_br40:
  %fp309 = getelementptr i8, ptr %ld303, i64 16
  %fv310 = load ptr, ptr %fp309, align 8
  %$f1986.addr = alloca ptr
  store ptr %fv310, ptr %$f1986.addr
  %fp311 = getelementptr i8, ptr %ld303, i64 24
  %fv312 = load ptr, ptr %fp311, align 8
  %$f1987.addr = alloca ptr
  store ptr %fv312, ptr %$f1987.addr
  %freed313 = call i64 @march_decrc_freed(ptr %ld303)
  %freed_b314 = icmp ne i64 %freed313, 0
  br i1 %freed_b314, label %br_unique41, label %br_shared42
br_shared42:
  call void @march_incrc(ptr %fv312)
  call void @march_incrc(ptr %fv310)
  br label %br_body43
br_unique41:
  br label %br_body43
br_body43:
  %ld315 = load ptr, ptr %$f1987.addr
  %rest.addr = alloca ptr
  store ptr %ld315, ptr %rest.addr
  %ld316 = load ptr, ptr %$f1986.addr
  %f.addr = alloca ptr
  store ptr %ld316, ptr %f.addr
  %ld317 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld317)
  %ld318 = load ptr, ptr %conn.addr
  %cr319 = call i64 @HttpServer.halted(ptr %ld318)
  %$t1984.addr = alloca i64
  store i64 %cr319, ptr %$t1984.addr
  %ld320 = load i64, ptr %$t1984.addr
  %res_slot321 = alloca ptr
  %bi322 = trunc i64 %ld320 to i1
  br i1 %bi322, label %case_br46, label %case_default45
case_br46:
  %ld323 = load ptr, ptr %conn.addr
  store ptr %ld323, ptr %res_slot321
  br label %case_merge44
case_default45:
  %ld324 = load ptr, ptr %f.addr
  %fp325 = getelementptr i8, ptr %ld324, i64 16
  %fv326 = load ptr, ptr %fp325, align 8
  %ld327 = load ptr, ptr %conn.addr
  %cr328 = call ptr (ptr, ptr) %fv326(ptr %ld324, ptr %ld327)
  %$t1985.addr = alloca ptr
  store ptr %cr328, ptr %$t1985.addr
  %ld329 = load ptr, ptr %$t1985.addr
  %ld330 = load ptr, ptr %rest.addr
  %cr331 = call ptr @HttpServer.run_pipeline(ptr %ld329, ptr %ld330)
  store ptr %cr331, ptr %res_slot321
  br label %case_merge44
case_merge44:
  %case_r332 = load ptr, ptr %res_slot321
  store ptr %case_r332, ptr %res_slot304
  br label %case_merge37
case_default38:
  unreachable
case_merge37:
  %case_r333 = load ptr, ptr %res_slot304
  ret ptr %case_r333
}

define ptr @march_main() {
entry:
  %port_i23.addr = alloca i64
  store i64 8080, ptr %port_i23.addr
  %hp334 = call ptr @march_alloc(i64 16)
  %tgp335 = getelementptr i8, ptr %hp334, i64 8
  store i32 0, ptr %tgp335, align 4
  %$t1988_i24.addr = alloca ptr
  store ptr %hp334, ptr %$t1988_i24.addr
  %hp336 = call ptr @march_alloc(i64 48)
  %tgp337 = getelementptr i8, ptr %hp336, i64 8
  store i32 0, ptr %tgp337, align 4
  %ld338 = load i64, ptr %port_i23.addr
  %fp339 = getelementptr i8, ptr %hp336, i64 16
  store i64 %ld338, ptr %fp339, align 8
  %ld340 = load ptr, ptr %$t1988_i24.addr
  %fp341 = getelementptr i8, ptr %hp336, i64 24
  store ptr %ld340, ptr %fp341, align 8
  %fp342 = getelementptr i8, ptr %hp336, i64 32
  store i64 1000, ptr %fp342, align 8
  %fp343 = getelementptr i8, ptr %hp336, i64 40
  store i64 60, ptr %fp343, align 8
  %$t2014.addr = alloca ptr
  store ptr %hp336, ptr %$t2014.addr
  %ld344 = load ptr, ptr %$t2014.addr
  %cwrap345 = call ptr @march_alloc(i64 24)
  %cwt346 = getelementptr i8, ptr %cwrap345, i64 8
  store i32 0, ptr %cwt346, align 4
  %cwf347 = getelementptr i8, ptr %cwrap345, i64 16
  store ptr @router$clo_wrap, ptr %cwf347, align 8
  %cr348 = call ptr @HttpServer.plug$Server$Fn_V__6027_V__6030(ptr %ld344, ptr %cwrap345)
  %$t2015.addr = alloca ptr
  store ptr %cr348, ptr %$t2015.addr
  %ld349 = load ptr, ptr %$t2015.addr
  %cr350 = call ptr @HttpServer.listen(ptr %ld349)
  ret ptr %cr350
}

define ptr @HttpServer.listen(ptr %server.arg) {
entry:
  %server.addr = alloca ptr
  store ptr %server.arg, ptr %server.addr
  %ld351 = load ptr, ptr %server.addr
  %res_slot352 = alloca ptr
  %tgp353 = getelementptr i8, ptr %ld351, i64 8
  %tag354 = load i32, ptr %tgp353, align 4
  switch i32 %tag354, label %case_default48 [
      i32 0, label %case_br49
  ]
case_br49:
  %fp355 = getelementptr i8, ptr %ld351, i64 16
  %fv356 = load i64, ptr %fp355, align 8
  %$f2005.addr = alloca i64
  store i64 %fv356, ptr %$f2005.addr
  %fp357 = getelementptr i8, ptr %ld351, i64 24
  %fv358 = load ptr, ptr %fp357, align 8
  %$f2006.addr = alloca ptr
  store ptr %fv358, ptr %$f2006.addr
  %fp359 = getelementptr i8, ptr %ld351, i64 32
  %fv360 = load i64, ptr %fp359, align 8
  %$f2007.addr = alloca i64
  store i64 %fv360, ptr %$f2007.addr
  %fp361 = getelementptr i8, ptr %ld351, i64 40
  %fv362 = load i64, ptr %fp361, align 8
  %$f2008.addr = alloca i64
  store i64 %fv362, ptr %$f2008.addr
  %freed363 = call i64 @march_decrc_freed(ptr %ld351)
  %freed_b364 = icmp ne i64 %freed363, 0
  br i1 %freed_b364, label %br_unique50, label %br_shared51
br_shared51:
  call void @march_incrc(ptr %fv358)
  br label %br_body52
br_unique50:
  br label %br_body52
br_body52:
  %ld365 = load i64, ptr %$f2008.addr
  %it.addr = alloca i64
  store i64 %ld365, ptr %it.addr
  %ld366 = load i64, ptr %$f2007.addr
  %mc.addr = alloca i64
  store i64 %ld366, ptr %mc.addr
  %ld367 = load ptr, ptr %$f2006.addr
  %plugs.addr = alloca ptr
  store ptr %ld367, ptr %plugs.addr
  %ld368 = load i64, ptr %$f2005.addr
  %port.addr = alloca i64
  store i64 %ld368, ptr %port.addr
  %hp369 = call ptr @march_alloc(i64 32)
  %tgp370 = getelementptr i8, ptr %hp369, i64 8
  store i32 0, ptr %tgp370, align 4
  %fp371 = getelementptr i8, ptr %hp369, i64 16
  store ptr @$lam2004$apply$24, ptr %fp371, align 8
  %ld372 = load ptr, ptr %plugs.addr
  %fp373 = getelementptr i8, ptr %hp369, i64 24
  store ptr %ld372, ptr %fp373, align 8
  %pipeline_fn.addr = alloca ptr
  store ptr %hp369, ptr %pipeline_fn.addr
  %ld374 = load i64, ptr %port.addr
  %ld375 = load i64, ptr %mc.addr
  %ld376 = load i64, ptr %it.addr
  %ld377 = load ptr, ptr %pipeline_fn.addr
  %cr378 = call ptr @march_http_server_listen(i64 %ld374, i64 %ld375, i64 %ld376, ptr %ld377)
  store ptr %cr378, ptr %res_slot352
  br label %case_merge47
case_default48:
  unreachable
case_merge47:
  %case_r379 = load ptr, ptr %res_slot352
  ret ptr %case_r379
}

define ptr @router(ptr %conn.arg) {
entry:
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld380 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld380)
  %ld381 = load ptr, ptr %conn.addr
  %cr382 = call ptr @HttpServer.method(ptr %ld381)
  %$t2009.addr = alloca ptr
  store ptr %cr382, ptr %$t2009.addr
  %ld383 = load ptr, ptr %conn.addr
  call void @march_incrc(ptr %ld383)
  %ld384 = load ptr, ptr %conn.addr
  %cr385 = call ptr @HttpServer.path_info(ptr %ld384)
  %$t2010.addr = alloca ptr
  store ptr %cr385, ptr %$t2010.addr
  %hp386 = call ptr @march_alloc(i64 32)
  %tgp387 = getelementptr i8, ptr %hp386, i64 8
  store i32 0, ptr %tgp387, align 4
  %ld388 = load ptr, ptr %$t2009.addr
  %fp389 = getelementptr i8, ptr %hp386, i64 16
  store ptr %ld388, ptr %fp389, align 8
  %ld390 = load ptr, ptr %$t2010.addr
  %fp391 = getelementptr i8, ptr %hp386, i64 24
  store ptr %ld390, ptr %fp391, align 8
  %$t2011.addr = alloca ptr
  store ptr %hp386, ptr %$t2011.addr
  %ld392 = load ptr, ptr %$t2011.addr
  %res_slot393 = alloca ptr
  %tgp394 = getelementptr i8, ptr %ld392, i64 8
  %tag395 = load i32, ptr %tgp394, align 4
  switch i32 %tag395, label %case_default54 [
      i32 0, label %case_br55
  ]
case_br55:
  %fp396 = getelementptr i8, ptr %ld392, i64 16
  %fv397 = load ptr, ptr %fp396, align 8
  %$f2012.addr = alloca ptr
  store ptr %fv397, ptr %$f2012.addr
  %fp398 = getelementptr i8, ptr %ld392, i64 24
  %fv399 = load ptr, ptr %fp398, align 8
  %$f2013.addr = alloca ptr
  store ptr %fv399, ptr %$f2013.addr
  %ld400 = load ptr, ptr %$f2012.addr
  %res_slot401 = alloca ptr
  %tgp402 = getelementptr i8, ptr %ld400, i64 8
  %tag403 = load i32, ptr %tgp402, align 4
  switch i32 %tag403, label %case_default57 [
      i32 0, label %case_br58
  ]
case_br58:
  %ld404 = load ptr, ptr %$f2012.addr
  call void @march_decrc(ptr %ld404)
  %ld405 = load ptr, ptr %$f2013.addr
  %res_slot406 = alloca ptr
  %tgp407 = getelementptr i8, ptr %ld405, i64 8
  %tag408 = load i32, ptr %tgp407, align 4
  switch i32 %tag408, label %case_default60 [
      i32 0, label %case_br61
  ]
case_br61:
  %ld409 = load ptr, ptr %$f2013.addr
  call void @march_decrc(ptr %ld409)
  %ld410 = load ptr, ptr %conn.addr
  %conn_i37.addr = alloca ptr
  store ptr %ld410, ptr %conn_i37.addr
  %resp_status_i38.addr = alloca i64
  store i64 200, ptr %resp_status_i38.addr
  %sl411 = call ptr @march_string_lit(ptr @.str1, i64 26)
  %body_i39.addr = alloca ptr
  store ptr %sl411, ptr %body_i39.addr
  %ld412 = load ptr, ptr %conn_i37.addr
  %sl413 = call ptr @march_string_lit(ptr @.str2, i64 12)
  %sl414 = call ptr @march_string_lit(ptr @.str3, i64 25)
  %cr415 = call ptr @HttpServer.put_resp_header(ptr %ld412, ptr %sl413, ptr %sl414)
  %$t1980_i40.addr = alloca ptr
  store ptr %cr415, ptr %$t1980_i40.addr
  %ld416 = load ptr, ptr %$t1980_i40.addr
  %ld417 = load i64, ptr %resp_status_i38.addr
  %ld418 = load ptr, ptr %body_i39.addr
  %cr419 = call ptr @HttpServer.send_resp(ptr %ld416, i64 %ld417, ptr %ld418)
  store ptr %cr419, ptr %res_slot406
  br label %case_merge59
case_default60:
  %ld420 = load ptr, ptr %$f2013.addr
  call void @march_decrc(ptr %ld420)
  %ld421 = load ptr, ptr %conn.addr
  %conn_i33.addr = alloca ptr
  store ptr %ld421, ptr %conn_i33.addr
  %resp_status_i34.addr = alloca i64
  store i64 404, ptr %resp_status_i34.addr
  %sl422 = call ptr @march_string_lit(ptr @.str4, i64 9)
  %body_i35.addr = alloca ptr
  store ptr %sl422, ptr %body_i35.addr
  %ld423 = load ptr, ptr %conn_i33.addr
  %sl424 = call ptr @march_string_lit(ptr @.str5, i64 12)
  %sl425 = call ptr @march_string_lit(ptr @.str6, i64 25)
  %cr426 = call ptr @HttpServer.put_resp_header(ptr %ld423, ptr %sl424, ptr %sl425)
  %$t1980_i36.addr = alloca ptr
  store ptr %cr426, ptr %$t1980_i36.addr
  %ld427 = load ptr, ptr %$t1980_i36.addr
  %ld428 = load i64, ptr %resp_status_i34.addr
  %ld429 = load ptr, ptr %body_i35.addr
  %cr430 = call ptr @HttpServer.send_resp(ptr %ld427, i64 %ld428, ptr %ld429)
  store ptr %cr430, ptr %res_slot406
  br label %case_merge59
case_merge59:
  %case_r431 = load ptr, ptr %res_slot406
  store ptr %case_r431, ptr %res_slot401
  br label %case_merge56
case_default57:
  %ld432 = load ptr, ptr %$f2012.addr
  call void @march_decrc(ptr %ld432)
  %ld433 = load ptr, ptr %conn.addr
  %conn_i29.addr = alloca ptr
  store ptr %ld433, ptr %conn_i29.addr
  %resp_status_i30.addr = alloca i64
  store i64 404, ptr %resp_status_i30.addr
  %sl434 = call ptr @march_string_lit(ptr @.str7, i64 9)
  %body_i31.addr = alloca ptr
  store ptr %sl434, ptr %body_i31.addr
  %ld435 = load ptr, ptr %conn_i29.addr
  %sl436 = call ptr @march_string_lit(ptr @.str8, i64 12)
  %sl437 = call ptr @march_string_lit(ptr @.str9, i64 25)
  %cr438 = call ptr @HttpServer.put_resp_header(ptr %ld435, ptr %sl436, ptr %sl437)
  %$t1980_i32.addr = alloca ptr
  store ptr %cr438, ptr %$t1980_i32.addr
  %ld439 = load ptr, ptr %$t1980_i32.addr
  %ld440 = load i64, ptr %resp_status_i30.addr
  %ld441 = load ptr, ptr %body_i31.addr
  %cr442 = call ptr @HttpServer.send_resp(ptr %ld439, i64 %ld440, ptr %ld441)
  store ptr %cr442, ptr %res_slot401
  br label %case_merge56
case_merge56:
  %case_r443 = load ptr, ptr %res_slot401
  store ptr %case_r443, ptr %res_slot393
  br label %case_merge53
case_default54:
  %ld444 = load ptr, ptr %conn.addr
  %conn_i25.addr = alloca ptr
  store ptr %ld444, ptr %conn_i25.addr
  %resp_status_i26.addr = alloca i64
  store i64 404, ptr %resp_status_i26.addr
  %sl445 = call ptr @march_string_lit(ptr @.str10, i64 9)
  %body_i27.addr = alloca ptr
  store ptr %sl445, ptr %body_i27.addr
  %ld446 = load ptr, ptr %conn_i25.addr
  %sl447 = call ptr @march_string_lit(ptr @.str11, i64 12)
  %sl448 = call ptr @march_string_lit(ptr @.str12, i64 25)
  %cr449 = call ptr @HttpServer.put_resp_header(ptr %ld446, ptr %sl447, ptr %sl448)
  %$t1980_i28.addr = alloca ptr
  store ptr %cr449, ptr %$t1980_i28.addr
  %ld450 = load ptr, ptr %$t1980_i28.addr
  %ld451 = load i64, ptr %resp_status_i26.addr
  %ld452 = load ptr, ptr %body_i27.addr
  %cr453 = call ptr @HttpServer.send_resp(ptr %ld450, i64 %ld451, ptr %ld452)
  store ptr %cr453, ptr %res_slot393
  br label %case_merge53
case_merge53:
  %case_r454 = load ptr, ptr %res_slot393
  ret ptr %case_r454
}

define ptr @HttpServer.plug$Server$Fn_V__6027_V__6030(ptr %server.arg, ptr %p.arg) {
entry:
  %server.addr = alloca ptr
  store ptr %server.arg, ptr %server.addr
  %p.addr = alloca ptr
  store ptr %p.arg, ptr %p.addr
  %ld455 = load ptr, ptr %server.addr
  %res_slot456 = alloca ptr
  %tgp457 = getelementptr i8, ptr %ld455, i64 8
  %tag458 = load i32, ptr %tgp457, align 4
  switch i32 %tag458, label %case_default63 [
      i32 0, label %case_br64
  ]
case_br64:
  %fp459 = getelementptr i8, ptr %ld455, i64 16
  %fv460 = load i64, ptr %fp459, align 8
  %$f1992.addr = alloca i64
  store i64 %fv460, ptr %$f1992.addr
  %fp461 = getelementptr i8, ptr %ld455, i64 24
  %fv462 = load ptr, ptr %fp461, align 8
  %$f1993.addr = alloca ptr
  store ptr %fv462, ptr %$f1993.addr
  %fp463 = getelementptr i8, ptr %ld455, i64 32
  %fv464 = load i64, ptr %fp463, align 8
  %$f1994.addr = alloca i64
  store i64 %fv464, ptr %$f1994.addr
  %fp465 = getelementptr i8, ptr %ld455, i64 40
  %fv466 = load i64, ptr %fp465, align 8
  %$f1995.addr = alloca i64
  store i64 %fv466, ptr %$f1995.addr
  %ld467 = load i64, ptr %$f1995.addr
  %it.addr = alloca i64
  store i64 %ld467, ptr %it.addr
  %ld468 = load i64, ptr %$f1994.addr
  %mc.addr = alloca i64
  store i64 %ld468, ptr %mc.addr
  %ld469 = load ptr, ptr %$f1993.addr
  %plugs.addr = alloca ptr
  store ptr %ld469, ptr %plugs.addr
  %ld470 = load i64, ptr %$f1992.addr
  %port.addr = alloca i64
  store i64 %ld470, ptr %port.addr
  %hp471 = call ptr @march_alloc(i64 16)
  %tgp472 = getelementptr i8, ptr %hp471, i64 8
  store i32 0, ptr %tgp472, align 4
  %$t1989.addr = alloca ptr
  store ptr %hp471, ptr %$t1989.addr
  %hp473 = call ptr @march_alloc(i64 32)
  %tgp474 = getelementptr i8, ptr %hp473, i64 8
  store i32 1, ptr %tgp474, align 4
  %ld475 = load ptr, ptr %p.addr
  %fp476 = getelementptr i8, ptr %hp473, i64 16
  store ptr %ld475, ptr %fp476, align 8
  %ld477 = load ptr, ptr %$t1989.addr
  %fp478 = getelementptr i8, ptr %hp473, i64 24
  store ptr %ld477, ptr %fp478, align 8
  %$t1990.addr = alloca ptr
  store ptr %hp473, ptr %$t1990.addr
  %ld479 = load ptr, ptr %plugs.addr
  %ld480 = load ptr, ptr %$t1990.addr
  %cr481 = call ptr @List.append$List_Fn_Conn_Conn$List_Fn_Conn_Conn(ptr %ld479, ptr %ld480)
  %$t1991.addr = alloca ptr
  store ptr %cr481, ptr %$t1991.addr
  %ld482 = load ptr, ptr %server.addr
  %ld483 = load i64, ptr %port.addr
  %ld484 = load ptr, ptr %$t1991.addr
  %ld485 = load i64, ptr %mc.addr
  %ld486 = load i64, ptr %it.addr
  %rc487 = load i64, ptr %ld482, align 8
  %uniq488 = icmp eq i64 %rc487, 1
  %fbip_slot489 = alloca ptr
  br i1 %uniq488, label %fbip_reuse65, label %fbip_fresh66
fbip_reuse65:
  %tgp490 = getelementptr i8, ptr %ld482, i64 8
  store i32 0, ptr %tgp490, align 4
  %fp491 = getelementptr i8, ptr %ld482, i64 16
  store i64 %ld483, ptr %fp491, align 8
  %fp492 = getelementptr i8, ptr %ld482, i64 24
  store ptr %ld484, ptr %fp492, align 8
  %fp493 = getelementptr i8, ptr %ld482, i64 32
  store i64 %ld485, ptr %fp493, align 8
  %fp494 = getelementptr i8, ptr %ld482, i64 40
  store i64 %ld486, ptr %fp494, align 8
  store ptr %ld482, ptr %fbip_slot489
  br label %fbip_merge67
fbip_fresh66:
  call void @march_decrc(ptr %ld482)
  %hp495 = call ptr @march_alloc(i64 48)
  %tgp496 = getelementptr i8, ptr %hp495, i64 8
  store i32 0, ptr %tgp496, align 4
  %fp497 = getelementptr i8, ptr %hp495, i64 16
  store i64 %ld483, ptr %fp497, align 8
  %fp498 = getelementptr i8, ptr %hp495, i64 24
  store ptr %ld484, ptr %fp498, align 8
  %fp499 = getelementptr i8, ptr %hp495, i64 32
  store i64 %ld485, ptr %fp499, align 8
  %fp500 = getelementptr i8, ptr %hp495, i64 40
  store i64 %ld486, ptr %fp500, align 8
  store ptr %hp495, ptr %fbip_slot489
  br label %fbip_merge67
fbip_merge67:
  %fbip_r501 = load ptr, ptr %fbip_slot489
  store ptr %fbip_r501, ptr %res_slot456
  br label %case_merge62
case_default63:
  unreachable
case_merge62:
  %case_r502 = load ptr, ptr %res_slot456
  ret ptr %case_r502
}

define ptr @List.append$List_Fn_Conn_Conn$List_Fn_Conn_Conn(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld503 = load ptr, ptr %xs.addr
  %res_slot504 = alloca ptr
  %tgp505 = getelementptr i8, ptr %ld503, i64 8
  %tag506 = load i32, ptr %tgp505, align 4
  switch i32 %tag506, label %case_default69 [
      i32 0, label %case_br70
      i32 1, label %case_br71
  ]
case_br70:
  %ld507 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld507)
  %ld508 = load ptr, ptr %ys.addr
  store ptr %ld508, ptr %res_slot504
  br label %case_merge68
case_br71:
  %fp509 = getelementptr i8, ptr %ld503, i64 16
  %fv510 = load ptr, ptr %fp509, align 8
  %$f131.addr = alloca ptr
  store ptr %fv510, ptr %$f131.addr
  %fp511 = getelementptr i8, ptr %ld503, i64 24
  %fv512 = load ptr, ptr %fp511, align 8
  %$f132.addr = alloca ptr
  store ptr %fv512, ptr %$f132.addr
  %ld513 = load ptr, ptr %$f132.addr
  %t.addr = alloca ptr
  store ptr %ld513, ptr %t.addr
  %ld514 = load ptr, ptr %$f131.addr
  %h.addr = alloca ptr
  store ptr %ld514, ptr %h.addr
  %ld515 = load ptr, ptr %t.addr
  %ld516 = load ptr, ptr %ys.addr
  %cr517 = call ptr @List.append$List_V__740$List_V__740(ptr %ld515, ptr %ld516)
  %$t130.addr = alloca ptr
  store ptr %cr517, ptr %$t130.addr
  %ld518 = load ptr, ptr %xs.addr
  %ld519 = load ptr, ptr %h.addr
  %ld520 = load ptr, ptr %$t130.addr
  %rc521 = load i64, ptr %ld518, align 8
  %uniq522 = icmp eq i64 %rc521, 1
  %fbip_slot523 = alloca ptr
  br i1 %uniq522, label %fbip_reuse72, label %fbip_fresh73
fbip_reuse72:
  %tgp524 = getelementptr i8, ptr %ld518, i64 8
  store i32 1, ptr %tgp524, align 4
  %fp525 = getelementptr i8, ptr %ld518, i64 16
  store ptr %ld519, ptr %fp525, align 8
  %fp526 = getelementptr i8, ptr %ld518, i64 24
  store ptr %ld520, ptr %fp526, align 8
  store ptr %ld518, ptr %fbip_slot523
  br label %fbip_merge74
fbip_fresh73:
  call void @march_decrc(ptr %ld518)
  %hp527 = call ptr @march_alloc(i64 32)
  %tgp528 = getelementptr i8, ptr %hp527, i64 8
  store i32 1, ptr %tgp528, align 4
  %fp529 = getelementptr i8, ptr %hp527, i64 16
  store ptr %ld519, ptr %fp529, align 8
  %fp530 = getelementptr i8, ptr %hp527, i64 24
  store ptr %ld520, ptr %fp530, align 8
  store ptr %hp527, ptr %fbip_slot523
  br label %fbip_merge74
fbip_merge74:
  %fbip_r531 = load ptr, ptr %fbip_slot523
  store ptr %fbip_r531, ptr %res_slot504
  br label %case_merge68
case_default69:
  unreachable
case_merge68:
  %case_r532 = load ptr, ptr %res_slot504
  ret ptr %case_r532
}

define ptr @List.append$List_V__740$List_V__740(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld533 = load ptr, ptr %xs.addr
  %res_slot534 = alloca ptr
  %tgp535 = getelementptr i8, ptr %ld533, i64 8
  %tag536 = load i32, ptr %tgp535, align 4
  switch i32 %tag536, label %case_default76 [
      i32 0, label %case_br77
      i32 1, label %case_br78
  ]
case_br77:
  %ld537 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld537)
  %ld538 = load ptr, ptr %ys.addr
  store ptr %ld538, ptr %res_slot534
  br label %case_merge75
case_br78:
  %fp539 = getelementptr i8, ptr %ld533, i64 16
  %fv540 = load ptr, ptr %fp539, align 8
  %$f131.addr = alloca ptr
  store ptr %fv540, ptr %$f131.addr
  %fp541 = getelementptr i8, ptr %ld533, i64 24
  %fv542 = load ptr, ptr %fp541, align 8
  %$f132.addr = alloca ptr
  store ptr %fv542, ptr %$f132.addr
  %ld543 = load ptr, ptr %$f132.addr
  %t.addr = alloca ptr
  store ptr %ld543, ptr %t.addr
  %ld544 = load ptr, ptr %$f131.addr
  %h.addr = alloca ptr
  store ptr %ld544, ptr %h.addr
  %ld545 = load ptr, ptr %t.addr
  %ld546 = load ptr, ptr %ys.addr
  %cr547 = call ptr @List.append$List_V__740$List_V__740(ptr %ld545, ptr %ld546)
  %$t130.addr = alloca ptr
  store ptr %cr547, ptr %$t130.addr
  %ld548 = load ptr, ptr %xs.addr
  %ld549 = load ptr, ptr %h.addr
  %ld550 = load ptr, ptr %$t130.addr
  %rc551 = load i64, ptr %ld548, align 8
  %uniq552 = icmp eq i64 %rc551, 1
  %fbip_slot553 = alloca ptr
  br i1 %uniq552, label %fbip_reuse79, label %fbip_fresh80
fbip_reuse79:
  %tgp554 = getelementptr i8, ptr %ld548, i64 8
  store i32 1, ptr %tgp554, align 4
  %fp555 = getelementptr i8, ptr %ld548, i64 16
  store ptr %ld549, ptr %fp555, align 8
  %fp556 = getelementptr i8, ptr %ld548, i64 24
  store ptr %ld550, ptr %fp556, align 8
  store ptr %ld548, ptr %fbip_slot553
  br label %fbip_merge81
fbip_fresh80:
  call void @march_decrc(ptr %ld548)
  %hp557 = call ptr @march_alloc(i64 32)
  %tgp558 = getelementptr i8, ptr %hp557, i64 8
  store i32 1, ptr %tgp558, align 4
  %fp559 = getelementptr i8, ptr %hp557, i64 16
  store ptr %ld549, ptr %fp559, align 8
  %fp560 = getelementptr i8, ptr %hp557, i64 24
  store ptr %ld550, ptr %fp560, align 8
  store ptr %hp557, ptr %fbip_slot553
  br label %fbip_merge81
fbip_merge81:
  %fbip_r561 = load ptr, ptr %fbip_slot553
  store ptr %fbip_r561, ptr %res_slot534
  br label %case_merge75
case_default76:
  unreachable
case_merge75:
  %case_r562 = load ptr, ptr %res_slot534
  ret ptr %case_r562
}

define ptr @$lam2004$apply$24(ptr %$clo.arg, ptr %conn.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %conn.addr = alloca ptr
  store ptr %conn.arg, ptr %conn.addr
  %ld563 = load ptr, ptr %$clo.addr
  %fp564 = getelementptr i8, ptr %ld563, i64 24
  %fv565 = load ptr, ptr %fp564, align 8
  %plugs.addr = alloca ptr
  store ptr %fv565, ptr %plugs.addr
  %ld566 = load ptr, ptr %conn.addr
  %ld567 = load ptr, ptr %plugs.addr
  %cr568 = call ptr @HttpServer.run_pipeline(ptr %ld566, ptr %ld567)
  ret ptr %cr568
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @router$clo_wrap(ptr %_clo, ptr %a0) {
entry:
  %r = call ptr @router(ptr %a0)
  ret ptr %r
}

