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

@.str1 = private unnamed_addr constant [8 x i8] c"Hello, \00"
@.str2 = private unnamed_addr constant [2 x i8] c"!\00"
@.str3 = private unnamed_addr constant [3 x i8] c": \00"
@.str4 = private unnamed_addr constant [26 x i8] c"[simulated response from \00"
@.str5 = private unnamed_addr constant [2 x i8] c"]\00"
@.str6 = private unnamed_addr constant [18 x i8] c"narrowed-cap user\00"
@.str7 = private unnamed_addr constant [24 x i8] c"https://example.com/api\00"
@.str8 = private unnamed_addr constant [15 x i8] c"fetch result: \00"
@.str9 = private unnamed_addr constant [8 x i8] c": empty\00"
@.str10 = private unnamed_addr constant [7 x i8] c" first\00"
@.str11 = private unnamed_addr constant [33 x i8] c"=== Capability Security Demo ===\00"
@.str12 = private unnamed_addr constant [1 x i8] c"\00"
@.str13 = private unnamed_addr constant [46 x i8] c"--- Pure functions (no capability needed) ---\00"
@.str14 = private unnamed_addr constant [13 x i8] c"add(3, 4) = \00"
@.str15 = private unnamed_addr constant [6 x i8] c"March\00"
@.str16 = private unnamed_addr constant [13 x i8] c"greeting  = \00"
@.str17 = private unnamed_addr constant [13 x i8] c"square(7) = \00"
@.str18 = private unnamed_addr constant [1 x i8] c"\00"
@.str19 = private unnamed_addr constant [27 x i8] c"--- Console capability ---\00"
@.str20 = private unnamed_addr constant [6 x i8] c"Alice\00"
@.str21 = private unnamed_addr constant [4 x i8] c"Bob\00"
@.str22 = private unnamed_addr constant [11 x i8] c"square(12)\00"
@.str23 = private unnamed_addr constant [1 x i8] c"\00"
@.str24 = private unnamed_addr constant [27 x i8] c"--- Network capability ---\00"
@.str25 = private unnamed_addr constant [30 x i8] c"https://api.example.com/users\00"
@.str26 = private unnamed_addr constant [11 x i8] c"response: \00"
@.str27 = private unnamed_addr constant [30 x i8] c"https://api.example.com/posts\00"
@.str28 = private unnamed_addr constant [11 x i8] c"response: \00"
@.str29 = private unnamed_addr constant [1 x i8] c"\00"
@.str30 = private unnamed_addr constant [29 x i8] c"--- Capability narrowing ---\00"
@.str31 = private unnamed_addr constant [1 x i8] c"\00"
@.str32 = private unnamed_addr constant [40 x i8] c"--- Higher-order capability passing ---\00"
@.str33 = private unnamed_addr constant [5 x i8] c"nums\00"
@.str34 = private unnamed_addr constant [1 x i8] c"\00"
@.str35 = private unnamed_addr constant [13 x i8] c"=== Done ===\00"
@.str36 = private unnamed_addr constant [17 x i8] c"head: empty list\00"

define ptr @format_greeting(ptr %name.arg) {
entry:
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %sl1 = call ptr @march_string_lit(ptr @.str1, i64 7)
  %ld2 = load ptr, ptr %name.addr
  %cr3 = call ptr @march_string_concat(ptr %sl1, ptr %ld2)
  %$t2009.addr = alloca ptr
  store ptr %cr3, ptr %$t2009.addr
  %ld4 = load ptr, ptr %$t2009.addr
  %sl5 = call ptr @march_string_lit(ptr @.str2, i64 1)
  %cr6 = call ptr @march_string_concat(ptr %ld4, ptr %sl5)
  ret ptr %cr6
}

define void @greet(ptr %cap.arg, ptr %name.arg) {
entry:
  %cap.addr = alloca ptr
  store ptr %cap.arg, ptr %cap.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld7 = load ptr, ptr %name.addr
  %cr8 = call ptr @format_greeting(ptr %ld7)
  %$t2010.addr = alloca ptr
  store ptr %cr8, ptr %$t2010.addr
  %ld9 = load ptr, ptr %$t2010.addr
  call void @march_println(ptr %ld9)
  ret void
}

define void @print_result(ptr %cap.arg, ptr %label.arg, i64 %value.arg) {
entry:
  %cap.addr = alloca ptr
  store ptr %cap.arg, ptr %cap.addr
  %label.addr = alloca ptr
  store ptr %label.arg, ptr %label.addr
  %value.addr = alloca i64
  store i64 %value.arg, ptr %value.addr
  %ld10 = load ptr, ptr %label.addr
  %sl11 = call ptr @march_string_lit(ptr @.str3, i64 2)
  %cr12 = call ptr @march_string_concat(ptr %ld10, ptr %sl11)
  %$t2011.addr = alloca ptr
  store ptr %cr12, ptr %$t2011.addr
  %ld13 = load i64, ptr %value.addr
  %cr14 = call ptr @march_int_to_string(i64 %ld13)
  %$t2012.addr = alloca ptr
  store ptr %cr14, ptr %$t2012.addr
  %ld15 = load ptr, ptr %$t2011.addr
  %ld16 = load ptr, ptr %$t2012.addr
  %cr17 = call ptr @march_string_concat(ptr %ld15, ptr %ld16)
  %$t2013.addr = alloca ptr
  store ptr %cr17, ptr %$t2013.addr
  %ld18 = load ptr, ptr %$t2013.addr
  call void @march_println(ptr %ld18)
  ret void
}

define ptr @simulate_fetch(ptr %cap.arg, ptr %url.arg) {
entry:
  %cap.addr = alloca ptr
  store ptr %cap.arg, ptr %cap.addr
  %url.addr = alloca ptr
  store ptr %url.arg, ptr %url.addr
  %sl19 = call ptr @march_string_lit(ptr @.str4, i64 25)
  %ld20 = load ptr, ptr %url.addr
  %cr21 = call ptr @march_string_concat(ptr %sl19, ptr %ld20)
  %$t2014.addr = alloca ptr
  store ptr %cr21, ptr %$t2014.addr
  %ld22 = load ptr, ptr %$t2014.addr
  %sl23 = call ptr @march_string_lit(ptr @.str5, i64 1)
  %cr24 = call ptr @march_string_concat(ptr %ld22, ptr %sl23)
  ret ptr %cr24
}

define void @demo_narrowing(ptr %cap.arg) {
entry:
  %cap.addr = alloca ptr
  store ptr %cap.arg, ptr %cap.addr
  %ld25 = load ptr, ptr %cap.addr
  call void @march_incrc(ptr %ld25)
  %ld26 = load ptr, ptr %cap.addr
  %cr27 = call ptr @march_cap_narrow(ptr %ld26)
  %console_cap.addr = alloca ptr
  store ptr %cr27, ptr %console_cap.addr
  %ld28 = load ptr, ptr %cap.addr
  %cr29 = call ptr @march_cap_narrow(ptr %ld28)
  %net_cap.addr = alloca ptr
  store ptr %cr29, ptr %net_cap.addr
  %ld30 = load ptr, ptr %console_cap.addr
  %sl31 = call ptr @march_string_lit(ptr @.str6, i64 17)
  %cr32 = call ptr @greet(ptr %ld30, ptr %sl31)
  %ld33 = load ptr, ptr %net_cap.addr
  %sl34 = call ptr @march_string_lit(ptr @.str7, i64 23)
  %cr35 = call ptr @simulate_fetch(ptr %ld33, ptr %sl34)
  %resp.addr = alloca ptr
  store ptr %cr35, ptr %resp.addr
  %sl36 = call ptr @march_string_lit(ptr @.str8, i64 14)
  %ld37 = load ptr, ptr %resp.addr
  %cr38 = call ptr @march_string_concat(ptr %sl36, ptr %ld37)
  %$t2015.addr = alloca ptr
  store ptr %cr38, ptr %$t2015.addr
  %ld39 = load ptr, ptr %$t2015.addr
  call void @march_println(ptr %ld39)
  ret void
}

define void @run_with_logging(ptr %cap.arg, ptr %items.arg, ptr %label.arg) {
entry:
  %cap.addr = alloca ptr
  store ptr %cap.arg, ptr %cap.addr
  %items.addr = alloca ptr
  store ptr %items.arg, ptr %items.addr
  %label.addr = alloca ptr
  store ptr %label.arg, ptr %label.addr
  %ld40 = load ptr, ptr %items.addr
  call void @march_incrc(ptr %ld40)
  %ld41 = load ptr, ptr %items.addr
  %cr42 = call i64 @is_nil$List_Int(ptr %ld41)
  %$t2016.addr = alloca i64
  store i64 %cr42, ptr %$t2016.addr
  %ld43 = load i64, ptr %$t2016.addr
  %res_slot44 = alloca ptr
  %bi45 = trunc i64 %ld43 to i1
  br i1 %bi45, label %case_br3, label %case_default2
case_br3:
  %ld46 = load ptr, ptr %label.addr
  %sl47 = call ptr @march_string_lit(ptr @.str9, i64 7)
  %cr48 = call ptr @march_string_concat(ptr %ld46, ptr %sl47)
  %$t2017.addr = alloca ptr
  store ptr %cr48, ptr %$t2017.addr
  %ld49 = load ptr, ptr %$t2017.addr
  call void @march_println(ptr %ld49)
  %cv50 = inttoptr i64 0 to ptr
  store ptr %cv50, ptr %res_slot44
  br label %case_merge1
case_default2:
  %ld51 = load ptr, ptr %label.addr
  %sl52 = call ptr @march_string_lit(ptr @.str10, i64 6)
  %cr53 = call ptr @march_string_concat(ptr %ld51, ptr %sl52)
  %$t2018.addr = alloca ptr
  store ptr %cr53, ptr %$t2018.addr
  %ld54 = load ptr, ptr %items.addr
  %cr55 = call i64 @head$List_Int(ptr %ld54)
  %$t2019.addr = alloca i64
  store i64 %cr55, ptr %$t2019.addr
  %ld56 = load ptr, ptr %cap.addr
  %ld57 = load ptr, ptr %$t2018.addr
  %ld58 = load i64, ptr %$t2019.addr
  %cr59 = call ptr @print_result(ptr %ld56, ptr %ld57, i64 %ld58)
  store ptr %cr59, ptr %res_slot44
  br label %case_merge1
case_merge1:
  %case_r60 = load ptr, ptr %res_slot44
  ret void
}

define void @march_main() {
entry:
  %cap.addr = alloca ptr
  store ptr null, ptr %cap.addr
  %sl61 = call ptr @march_string_lit(ptr @.str11, i64 32)
  call void @march_println(ptr %sl61)
  %sl62 = call ptr @march_string_lit(ptr @.str12, i64 0)
  call void @march_println(ptr %sl62)
  %sl63 = call ptr @march_string_lit(ptr @.str13, i64 45)
  call void @march_println(ptr %sl63)
  %x_i25.addr = alloca i64
  store i64 3, ptr %x_i25.addr
  %y_i26.addr = alloca i64
  store i64 4, ptr %y_i26.addr
  %ld64 = load i64, ptr %x_i25.addr
  %ld65 = load i64, ptr %y_i26.addr
  %ar66 = add i64 %ld64, %ld65
  %sum.addr = alloca i64
  store i64 %ar66, ptr %sum.addr
  %ld67 = load i64, ptr %sum.addr
  %cr68 = call ptr @march_int_to_string(i64 %ld67)
  %$t2020.addr = alloca ptr
  store ptr %cr68, ptr %$t2020.addr
  %sl69 = call ptr @march_string_lit(ptr @.str14, i64 12)
  %ld70 = load ptr, ptr %$t2020.addr
  %cr71 = call ptr @march_string_concat(ptr %sl69, ptr %ld70)
  %$t2021.addr = alloca ptr
  store ptr %cr71, ptr %$t2021.addr
  %ld72 = load ptr, ptr %$t2021.addr
  call void @march_println(ptr %ld72)
  %sl73 = call ptr @march_string_lit(ptr @.str15, i64 5)
  %cr74 = call ptr @format_greeting(ptr %sl73)
  %msg.addr = alloca ptr
  store ptr %cr74, ptr %msg.addr
  %sl75 = call ptr @march_string_lit(ptr @.str16, i64 12)
  %ld76 = load ptr, ptr %msg.addr
  %cr77 = call ptr @march_string_concat(ptr %sl75, ptr %ld76)
  %$t2022.addr = alloca ptr
  store ptr %cr77, ptr %$t2022.addr
  %ld78 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld78)
  %n_i24.addr = alloca i64
  store i64 7, ptr %n_i24.addr
  %ld79 = load i64, ptr %n_i24.addr
  %ld80 = load i64, ptr %n_i24.addr
  %ar81 = mul i64 %ld79, %ld80
  %sq.addr = alloca i64
  store i64 %ar81, ptr %sq.addr
  %ld82 = load i64, ptr %sq.addr
  %cr83 = call ptr @march_int_to_string(i64 %ld82)
  %$t2023.addr = alloca ptr
  store ptr %cr83, ptr %$t2023.addr
  %sl84 = call ptr @march_string_lit(ptr @.str17, i64 12)
  %ld85 = load ptr, ptr %$t2023.addr
  %cr86 = call ptr @march_string_concat(ptr %sl84, ptr %ld85)
  %$t2024.addr = alloca ptr
  store ptr %cr86, ptr %$t2024.addr
  %ld87 = load ptr, ptr %$t2024.addr
  call void @march_println(ptr %ld87)
  %sl88 = call ptr @march_string_lit(ptr @.str18, i64 0)
  call void @march_println(ptr %sl88)
  %ld89 = load ptr, ptr %cap.addr
  call void @march_incrc(ptr %ld89)
  %ld90 = load ptr, ptr %cap.addr
  %cr91 = call ptr @march_cap_narrow(ptr %ld90)
  %console_cap.addr = alloca ptr
  store ptr %cr91, ptr %console_cap.addr
  %ld92 = load ptr, ptr %cap.addr
  call void @march_incrc(ptr %ld92)
  %ld93 = load ptr, ptr %cap.addr
  %cr94 = call ptr @march_cap_narrow(ptr %ld93)
  %net_cap.addr = alloca ptr
  store ptr %cr94, ptr %net_cap.addr
  %sl95 = call ptr @march_string_lit(ptr @.str19, i64 26)
  call void @march_println(ptr %sl95)
  %ld96 = load ptr, ptr %console_cap.addr
  call void @march_incrc(ptr %ld96)
  %ld97 = load ptr, ptr %console_cap.addr
  %sl98 = call ptr @march_string_lit(ptr @.str20, i64 5)
  %cr99 = call ptr @greet(ptr %ld97, ptr %sl98)
  %ld100 = load ptr, ptr %console_cap.addr
  call void @march_incrc(ptr %ld100)
  %ld101 = load ptr, ptr %console_cap.addr
  %sl102 = call ptr @march_string_lit(ptr @.str21, i64 3)
  %cr103 = call ptr @greet(ptr %ld101, ptr %sl102)
  %n_i23.addr = alloca i64
  store i64 12, ptr %n_i23.addr
  %ld104 = load i64, ptr %n_i23.addr
  %ld105 = load i64, ptr %n_i23.addr
  %ar106 = mul i64 %ld104, %ld105
  %$t2025.addr = alloca i64
  store i64 %ar106, ptr %$t2025.addr
  %ld107 = load ptr, ptr %console_cap.addr
  call void @march_incrc(ptr %ld107)
  %ld108 = load ptr, ptr %console_cap.addr
  %sl109 = call ptr @march_string_lit(ptr @.str22, i64 10)
  %ld110 = load i64, ptr %$t2025.addr
  %cr111 = call ptr @print_result(ptr %ld108, ptr %sl109, i64 %ld110)
  %sl112 = call ptr @march_string_lit(ptr @.str23, i64 0)
  call void @march_println(ptr %sl112)
  %sl113 = call ptr @march_string_lit(ptr @.str24, i64 26)
  call void @march_println(ptr %sl113)
  %ld114 = load ptr, ptr %net_cap.addr
  call void @march_incrc(ptr %ld114)
  %ld115 = load ptr, ptr %net_cap.addr
  %sl116 = call ptr @march_string_lit(ptr @.str25, i64 29)
  %cr117 = call ptr @simulate_fetch(ptr %ld115, ptr %sl116)
  %resp1.addr = alloca ptr
  store ptr %cr117, ptr %resp1.addr
  %sl118 = call ptr @march_string_lit(ptr @.str26, i64 10)
  %ld119 = load ptr, ptr %resp1.addr
  %cr120 = call ptr @march_string_concat(ptr %sl118, ptr %ld119)
  %$t2026.addr = alloca ptr
  store ptr %cr120, ptr %$t2026.addr
  %ld121 = load ptr, ptr %$t2026.addr
  call void @march_println(ptr %ld121)
  %ld122 = load ptr, ptr %net_cap.addr
  %sl123 = call ptr @march_string_lit(ptr @.str27, i64 29)
  %cr124 = call ptr @simulate_fetch(ptr %ld122, ptr %sl123)
  %resp2.addr = alloca ptr
  store ptr %cr124, ptr %resp2.addr
  %sl125 = call ptr @march_string_lit(ptr @.str28, i64 10)
  %ld126 = load ptr, ptr %resp2.addr
  %cr127 = call ptr @march_string_concat(ptr %sl125, ptr %ld126)
  %$t2027.addr = alloca ptr
  store ptr %cr127, ptr %$t2027.addr
  %ld128 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld128)
  %sl129 = call ptr @march_string_lit(ptr @.str29, i64 0)
  call void @march_println(ptr %sl129)
  %sl130 = call ptr @march_string_lit(ptr @.str30, i64 28)
  call void @march_println(ptr %sl130)
  %ld131 = load ptr, ptr %cap.addr
  %cr132 = call ptr @demo_narrowing(ptr %ld131)
  %sl133 = call ptr @march_string_lit(ptr @.str31, i64 0)
  call void @march_println(ptr %sl133)
  %sl134 = call ptr @march_string_lit(ptr @.str32, i64 39)
  call void @march_println(ptr %sl134)
  %hp135 = call ptr @march_alloc(i64 16)
  %tgp136 = getelementptr i8, ptr %hp135, i64 8
  store i32 0, ptr %tgp136, align 4
  %$t2028.addr = alloca ptr
  store ptr %hp135, ptr %$t2028.addr
  %hp137 = call ptr @march_alloc(i64 32)
  %tgp138 = getelementptr i8, ptr %hp137, i64 8
  store i32 1, ptr %tgp138, align 4
  %cv139 = inttoptr i64 30 to ptr
  %fp140 = getelementptr i8, ptr %hp137, i64 16
  store ptr %cv139, ptr %fp140, align 8
  %ld141 = load ptr, ptr %$t2028.addr
  %fp142 = getelementptr i8, ptr %hp137, i64 24
  store ptr %ld141, ptr %fp142, align 8
  %$t2029.addr = alloca ptr
  store ptr %hp137, ptr %$t2029.addr
  %hp143 = call ptr @march_alloc(i64 32)
  %tgp144 = getelementptr i8, ptr %hp143, i64 8
  store i32 1, ptr %tgp144, align 4
  %cv145 = inttoptr i64 20 to ptr
  %fp146 = getelementptr i8, ptr %hp143, i64 16
  store ptr %cv145, ptr %fp146, align 8
  %ld147 = load ptr, ptr %$t2029.addr
  %fp148 = getelementptr i8, ptr %hp143, i64 24
  store ptr %ld147, ptr %fp148, align 8
  %$t2030.addr = alloca ptr
  store ptr %hp143, ptr %$t2030.addr
  %hp149 = call ptr @march_alloc(i64 32)
  %tgp150 = getelementptr i8, ptr %hp149, i64 8
  store i32 1, ptr %tgp150, align 4
  %cv151 = inttoptr i64 10 to ptr
  %fp152 = getelementptr i8, ptr %hp149, i64 16
  store ptr %cv151, ptr %fp152, align 8
  %ld153 = load ptr, ptr %$t2030.addr
  %fp154 = getelementptr i8, ptr %hp149, i64 24
  store ptr %ld153, ptr %fp154, align 8
  %nums.addr = alloca ptr
  store ptr %hp149, ptr %nums.addr
  %ld155 = load ptr, ptr %console_cap.addr
  %ld156 = load ptr, ptr %nums.addr
  %sl157 = call ptr @march_string_lit(ptr @.str33, i64 4)
  %cr158 = call ptr @run_with_logging(ptr %ld155, ptr %ld156, ptr %sl157)
  %sl159 = call ptr @march_string_lit(ptr @.str34, i64 0)
  call void @march_println(ptr %sl159)
  %sl160 = call ptr @march_string_lit(ptr @.str35, i64 12)
  call void @march_println(ptr %sl160)
  ret void
}

define i64 @head$List_Int(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld161 = load ptr, ptr %xs.addr
  %res_slot162 = alloca ptr
  %tgp163 = getelementptr i8, ptr %ld161, i64 8
  %tag164 = load i32, ptr %tgp163, align 4
  switch i32 %tag164, label %case_default5 [
      i32 1, label %case_br6
      i32 0, label %case_br7
  ]
case_br6:
  %fp165 = getelementptr i8, ptr %ld161, i64 16
  %fv166 = load ptr, ptr %fp165, align 8
  %$f3.addr = alloca ptr
  store ptr %fv166, ptr %$f3.addr
  %fp167 = getelementptr i8, ptr %ld161, i64 24
  %fv168 = load ptr, ptr %fp167, align 8
  %$f4.addr = alloca ptr
  store ptr %fv168, ptr %$f4.addr
  %freed169 = call i64 @march_decrc_freed(ptr %ld161)
  %freed_b170 = icmp ne i64 %freed169, 0
  br i1 %freed_b170, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv168)
  call void @march_incrc(ptr %fv166)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld171 = load ptr, ptr %$f3.addr
  %h.addr = alloca ptr
  store ptr %ld171, ptr %h.addr
  %ld172 = load ptr, ptr %h.addr
  store ptr %ld172, ptr %res_slot162
  br label %case_merge4
case_br7:
  %ld173 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld173)
  %sl174 = call ptr @march_string_lit(ptr @.str36, i64 16)
  call void @march_panic(ptr %sl174)
  %cv175 = inttoptr i64 0 to ptr
  store ptr %cv175, ptr %res_slot162
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r176 = load ptr, ptr %res_slot162
  %cv177 = ptrtoint ptr %case_r176 to i64
  ret i64 %cv177
}

define i64 @is_nil$List_Int(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld178 = load ptr, ptr %xs.addr
  %res_slot179 = alloca ptr
  %tgp180 = getelementptr i8, ptr %ld178, i64 8
  %tag181 = load i32, ptr %tgp180, align 4
  switch i32 %tag181, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld182 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld182)
  %cv183 = inttoptr i64 1 to ptr
  store ptr %cv183, ptr %res_slot179
  br label %case_merge11
case_br14:
  %fp184 = getelementptr i8, ptr %ld178, i64 16
  %fv185 = load ptr, ptr %fp184, align 8
  %$f9.addr = alloca ptr
  store ptr %fv185, ptr %$f9.addr
  %fp186 = getelementptr i8, ptr %ld178, i64 24
  %fv187 = load ptr, ptr %fp186, align 8
  %$f10.addr = alloca ptr
  store ptr %fv187, ptr %$f10.addr
  %freed188 = call i64 @march_decrc_freed(ptr %ld178)
  %freed_b189 = icmp ne i64 %freed188, 0
  br i1 %freed_b189, label %br_unique15, label %br_shared16
br_shared16:
  call void @march_incrc(ptr %fv187)
  call void @march_incrc(ptr %fv185)
  br label %br_body17
br_unique15:
  br label %br_body17
br_body17:
  %cv190 = inttoptr i64 0 to ptr
  store ptr %cv190, ptr %res_slot179
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r191 = load ptr, ptr %res_slot179
  %cv192 = ptrtoint ptr %case_r191 to i64
  ret i64 %cv192
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
