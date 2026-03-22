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

@.str1 = private unnamed_addr constant [22 x i8] c"not a valid integer: \00"
@.str2 = private unnamed_addr constant [40 x i8] c"--- Example 1: each_row (streaming) ---\00"
@.str3 = private unnamed_addr constant [2 x i8] c",\00"
@.str4 = private unnamed_addr constant [8 x i8] c"Error: \00"
@.str5 = private unnamed_addr constant [7 x i8] c"no age\00"
@.str6 = private unnamed_addr constant [7 x i8] c"no age\00"
@.str7 = private unnamed_addr constant [1 x i8] c"\00"
@.str8 = private unnamed_addr constant [36 x i8] c"--- Example 2: read_all (eager) ---\00"
@.str9 = private unnamed_addr constant [2 x i8] c",\00"
@.str10 = private unnamed_addr constant [8 x i8] c"Error: \00"
@.str11 = private unnamed_addr constant [28 x i8] c"Total rows (incl. header): \00"
@.str12 = private unnamed_addr constant [9 x i8] c"No data.\00"
@.str13 = private unnamed_addr constant [7 x i8] c"nobody\00"
@.str14 = private unnamed_addr constant [16 x i8] c"Oldest person: \00"
@.str15 = private unnamed_addr constant [5 x i8] c"name\00"
@.str16 = private unnamed_addr constant [2 x i8] c"?\00"
@.str17 = private unnamed_addr constant [5 x i8] c"city\00"
@.str18 = private unnamed_addr constant [2 x i8] c"?\00"
@.str19 = private unnamed_addr constant [11 x i8] c" lives in \00"
@.str20 = private unnamed_addr constant [24 x i8] c"/tmp/march_csv_demo.csv\00"
@.str21 = private unnamed_addr constant [24 x i8] c"/tmp/march_tsv_demo.tsv\00"
@.str22 = private unnamed_addr constant [91 x i8] c"name,age,city\0AAlice,30,\22New York\22\0ABob,25,London\0A\22Carol, Jr.\22,42,\22Sao Paulo\22\0ADave,35,Berlin\00"
@.str23 = private unnamed_addr constant [63 x i8] c"product\09price\09qty\0AApple\091.20\0950\0ABanana\090.50\09120\0ACherry\093.00\0930\00"
@.str24 = private unnamed_addr constant [20 x i8] c"All demos complete.\00"
@.str25 = private unnamed_addr constant [41 x i8] c"--- Example 4: TSV with :simple mode ---\00"
@.str26 = private unnamed_addr constant [2 x i8] c"\09\00"
@.str27 = private unnamed_addr constant [40 x i8] c"--- Example 3: each_row_with_header ---\00"
@.str28 = private unnamed_addr constant [2 x i8] c",\00"

define ptr @String.to_int(ptr %s.arg) {
entry:
  %s.addr = alloca ptr
  store ptr %s.arg, ptr %s.addr
  %ld1 = load ptr, ptr %s.addr
  call void @march_incrc(ptr %ld1)
  %ld2 = load ptr, ptr %s.addr
  %cr3 = call ptr @march_string_to_int(ptr %ld2)
  %$t484.addr = alloca ptr
  store ptr %cr3, ptr %$t484.addr
  %ld4 = load ptr, ptr %$t484.addr
  %res_slot5 = alloca ptr
  %tgp6 = getelementptr i8, ptr %ld4, i64 8
  %tag7 = load i32, ptr %tgp6, align 4
  switch i32 %tag7, label %case_default2 [
      i32 1, label %case_br3
      i32 0, label %case_br4
  ]
case_br3:
  %fp8 = getelementptr i8, ptr %ld4, i64 16
  %fv9 = load ptr, ptr %fp8, align 8
  %$f486.addr = alloca ptr
  store ptr %fv9, ptr %$f486.addr
  %ld10 = load ptr, ptr %$t484.addr
  call void @march_decrc(ptr %ld10)
  %ld11 = load ptr, ptr %$f486.addr
  %n.addr = alloca ptr
  store ptr %ld11, ptr %n.addr
  %hp12 = call ptr @march_alloc(i64 24)
  %tgp13 = getelementptr i8, ptr %hp12, i64 8
  store i32 0, ptr %tgp13, align 4
  %ld14 = load ptr, ptr %n.addr
  %fp15 = getelementptr i8, ptr %hp12, i64 16
  store ptr %ld14, ptr %fp15, align 8
  store ptr %hp12, ptr %res_slot5
  br label %case_merge1
case_br4:
  %ld16 = load ptr, ptr %$t484.addr
  call void @march_decrc(ptr %ld16)
  %sl17 = call ptr @march_string_lit(ptr @.str1, i64 21)
  %ld18 = load ptr, ptr %s.addr
  %cr19 = call ptr @march_string_concat(ptr %sl17, ptr %ld18)
  %$t485.addr = alloca ptr
  store ptr %cr19, ptr %$t485.addr
  %hp20 = call ptr @march_alloc(i64 24)
  %tgp21 = getelementptr i8, ptr %hp20, i64 8
  store i32 1, ptr %tgp21, align 4
  %ld22 = load ptr, ptr %$t485.addr
  %fp23 = getelementptr i8, ptr %hp20, i64 16
  store ptr %ld22, ptr %fp23, align 8
  store ptr %hp20, ptr %res_slot5
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r24 = load ptr, ptr %res_slot5
  ret ptr %case_r24
}

define ptr @demo_each_row(ptr %path.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %sl25 = call ptr @march_string_lit(ptr @.str2, i64 39)
  call void @march_println(ptr %sl25)
  %cv26 = inttoptr i64 0 to ptr
  %$t2010.addr = alloca ptr
  store ptr %cv26, ptr %$t2010.addr
  %hp27 = call ptr @march_alloc(i64 24)
  %tgp28 = getelementptr i8, ptr %hp27, i64 8
  store i32 0, ptr %tgp28, align 4
  %fp29 = getelementptr i8, ptr %hp27, i64 16
  store ptr @$lam2011$apply$22, ptr %fp29, align 8
  %$t2012.addr = alloca ptr
  store ptr %hp27, ptr %$t2012.addr
  %ld30 = load ptr, ptr %path.addr
  %sl31 = call ptr @march_string_lit(ptr @.str3, i64 1)
  %ld32 = load ptr, ptr %$t2010.addr
  %ld33 = load ptr, ptr %$t2012.addr
  %cr34 = call ptr @Csv.each_row$String$String$Atom$Fn_V__6177_T_(ptr %ld30, ptr %sl31, ptr %ld32, ptr %ld33)
  %$t2013.addr = alloca ptr
  store ptr %cr34, ptr %$t2013.addr
  %ld35 = load ptr, ptr %$t2013.addr
  %res_slot36 = alloca ptr
  %tgp37 = getelementptr i8, ptr %ld35, i64 8
  %tag38 = load i32, ptr %tgp37, align 4
  switch i32 %tag38, label %case_default6 [
      i32 0, label %case_br7
      i32 1, label %case_br8
  ]
case_br7:
  %fp39 = getelementptr i8, ptr %ld35, i64 16
  %fv40 = load ptr, ptr %fp39, align 8
  %$f2016.addr = alloca ptr
  store ptr %fv40, ptr %$f2016.addr
  %freed41 = call i64 @march_decrc_freed(ptr %ld35)
  %freed_b42 = icmp ne i64 %freed41, 0
  br i1 %freed_b42, label %br_unique9, label %br_shared10
br_shared10:
  call void @march_incrc(ptr %fv40)
  br label %br_body11
br_unique9:
  br label %br_body11
br_body11:
  %cv43 = inttoptr i64 0 to ptr
  store ptr %cv43, ptr %res_slot36
  br label %case_merge5
case_br8:
  %fp44 = getelementptr i8, ptr %ld35, i64 16
  %fv45 = load ptr, ptr %fp44, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv45, ptr %$f2017.addr
  %freed46 = call i64 @march_decrc_freed(ptr %ld35)
  %freed_b47 = icmp ne i64 %freed46, 0
  br i1 %freed_b47, label %br_unique12, label %br_shared13
br_shared13:
  call void @march_incrc(ptr %fv45)
  br label %br_body14
br_unique12:
  br label %br_body14
br_body14:
  %ld48 = load ptr, ptr %$f2017.addr
  %e.addr = alloca ptr
  store ptr %ld48, ptr %e.addr
  %ld49 = load ptr, ptr %e.addr
  %cr50 = call ptr @march_value_to_string(ptr %ld49)
  %$t2014.addr = alloca ptr
  store ptr %cr50, ptr %$t2014.addr
  %sl51 = call ptr @march_string_lit(ptr @.str4, i64 7)
  %ld52 = load ptr, ptr %$t2014.addr
  %cr53 = call ptr @march_string_concat(ptr %sl51, ptr %ld52)
  %$t2015.addr = alloca ptr
  store ptr %cr53, ptr %$t2015.addr
  %ld54 = load ptr, ptr %$t2015.addr
  call void @march_println(ptr %ld54)
  %cv55 = inttoptr i64 0 to ptr
  store ptr %cv55, ptr %res_slot36
  br label %case_merge5
case_default6:
  unreachable
case_merge5:
  %case_r56 = load ptr, ptr %res_slot36
  ret ptr %case_r56
}

define ptr @get_age(ptr %row.arg) {
entry:
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld57 = load ptr, ptr %row.addr
  %res_slot58 = alloca ptr
  %tgp59 = getelementptr i8, ptr %ld57, i64 8
  %tag60 = load i32, ptr %tgp59, align 4
  switch i32 %tag60, label %case_default16 [
      i32 1, label %case_br17
  ]
case_br17:
  %fp61 = getelementptr i8, ptr %ld57, i64 16
  %fv62 = load ptr, ptr %fp61, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv62, ptr %$f2018.addr
  %fp63 = getelementptr i8, ptr %ld57, i64 24
  %fv64 = load ptr, ptr %fp63, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv64, ptr %$f2019.addr
  %freed65 = call i64 @march_decrc_freed(ptr %ld57)
  %freed_b66 = icmp ne i64 %freed65, 0
  br i1 %freed_b66, label %br_unique18, label %br_shared19
br_shared19:
  call void @march_incrc(ptr %fv64)
  call void @march_incrc(ptr %fv62)
  br label %br_body20
br_unique18:
  br label %br_body20
br_body20:
  %ld67 = load ptr, ptr %$f2019.addr
  %res_slot68 = alloca ptr
  %tgp69 = getelementptr i8, ptr %ld67, i64 8
  %tag70 = load i32, ptr %tgp69, align 4
  switch i32 %tag70, label %case_default22 [
      i32 1, label %case_br23
  ]
case_br23:
  %fp71 = getelementptr i8, ptr %ld67, i64 16
  %fv72 = load ptr, ptr %fp71, align 8
  %$f2020.addr = alloca ptr
  store ptr %fv72, ptr %$f2020.addr
  %fp73 = getelementptr i8, ptr %ld67, i64 24
  %fv74 = load ptr, ptr %fp73, align 8
  %$f2021.addr = alloca ptr
  store ptr %fv74, ptr %$f2021.addr
  %freed75 = call i64 @march_decrc_freed(ptr %ld67)
  %freed_b76 = icmp ne i64 %freed75, 0
  br i1 %freed_b76, label %br_unique24, label %br_shared25
br_shared25:
  call void @march_incrc(ptr %fv74)
  call void @march_incrc(ptr %fv72)
  br label %br_body26
br_unique24:
  br label %br_body26
br_body26:
  %ld77 = load ptr, ptr %$f2020.addr
  %age_str.addr = alloca ptr
  store ptr %ld77, ptr %age_str.addr
  %ld78 = load ptr, ptr %age_str.addr
  %cr79 = call ptr @String.to_int(ptr %ld78)
  store ptr %cr79, ptr %res_slot68
  br label %case_merge21
case_default22:
  %ld80 = load ptr, ptr %$f2019.addr
  call void @march_decrc(ptr %ld80)
  %hp81 = call ptr @march_alloc(i64 24)
  %tgp82 = getelementptr i8, ptr %hp81, i64 8
  store i32 1, ptr %tgp82, align 4
  %sl83 = call ptr @march_string_lit(ptr @.str5, i64 6)
  %fp84 = getelementptr i8, ptr %hp81, i64 16
  store ptr %sl83, ptr %fp84, align 8
  store ptr %hp81, ptr %res_slot68
  br label %case_merge21
case_merge21:
  %case_r85 = load ptr, ptr %res_slot68
  store ptr %case_r85, ptr %res_slot58
  br label %case_merge15
case_default16:
  %ld86 = load ptr, ptr %row.addr
  call void @march_decrc(ptr %ld86)
  %hp87 = call ptr @march_alloc(i64 24)
  %tgp88 = getelementptr i8, ptr %hp87, i64 8
  store i32 1, ptr %tgp88, align 4
  %sl89 = call ptr @march_string_lit(ptr @.str6, i64 6)
  %fp90 = getelementptr i8, ptr %hp87, i64 16
  store ptr %sl89, ptr %fp90, align 8
  store ptr %hp87, ptr %res_slot58
  br label %case_merge15
case_merge15:
  %case_r91 = load ptr, ptr %res_slot58
  ret ptr %case_r91
}

define ptr @get_name(ptr %row.arg) {
entry:
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld92 = load ptr, ptr %row.addr
  %res_slot93 = alloca ptr
  %tgp94 = getelementptr i8, ptr %ld92, i64 8
  %tag95 = load i32, ptr %tgp94, align 4
  switch i32 %tag95, label %case_default28 [
      i32 1, label %case_br29
  ]
case_br29:
  %fp96 = getelementptr i8, ptr %ld92, i64 16
  %fv97 = load ptr, ptr %fp96, align 8
  %$f2022.addr = alloca ptr
  store ptr %fv97, ptr %$f2022.addr
  %fp98 = getelementptr i8, ptr %ld92, i64 24
  %fv99 = load ptr, ptr %fp98, align 8
  %$f2023.addr = alloca ptr
  store ptr %fv99, ptr %$f2023.addr
  %freed100 = call i64 @march_decrc_freed(ptr %ld92)
  %freed_b101 = icmp ne i64 %freed100, 0
  br i1 %freed_b101, label %br_unique30, label %br_shared31
br_shared31:
  call void @march_incrc(ptr %fv99)
  call void @march_incrc(ptr %fv97)
  br label %br_body32
br_unique30:
  br label %br_body32
br_body32:
  %ld102 = load ptr, ptr %$f2022.addr
  %name.addr = alloca ptr
  store ptr %ld102, ptr %name.addr
  %ld103 = load ptr, ptr %name.addr
  store ptr %ld103, ptr %res_slot93
  br label %case_merge27
case_default28:
  %ld104 = load ptr, ptr %row.addr
  call void @march_decrc(ptr %ld104)
  %sl105 = call ptr @march_string_lit(ptr @.str7, i64 0)
  store ptr %sl105, ptr %res_slot93
  br label %case_merge27
case_merge27:
  %case_r106 = load ptr, ptr %res_slot93
  ret ptr %case_r106
}

define ptr @find_oldest_loop(ptr %rows.arg, ptr %best_name.arg, i64 %best_age.arg) {
entry:
  %rows.addr = alloca ptr
  store ptr %rows.arg, ptr %rows.addr
  %best_name.addr = alloca ptr
  store ptr %best_name.arg, ptr %best_name.addr
  %best_age.addr = alloca i64
  store i64 %best_age.arg, ptr %best_age.addr
  %ld107 = load ptr, ptr %rows.addr
  %res_slot108 = alloca ptr
  %tgp109 = getelementptr i8, ptr %ld107, i64 8
  %tag110 = load i32, ptr %tgp109, align 4
  switch i32 %tag110, label %case_default34 [
      i32 0, label %case_br35
      i32 1, label %case_br36
  ]
case_br35:
  %ld111 = load ptr, ptr %rows.addr
  call void @march_decrc(ptr %ld111)
  %ld112 = load ptr, ptr %best_name.addr
  store ptr %ld112, ptr %res_slot108
  br label %case_merge33
case_br36:
  %fp113 = getelementptr i8, ptr %ld107, i64 16
  %fv114 = load ptr, ptr %fp113, align 8
  %$f2029.addr = alloca ptr
  store ptr %fv114, ptr %$f2029.addr
  %fp115 = getelementptr i8, ptr %ld107, i64 24
  %fv116 = load ptr, ptr %fp115, align 8
  %$f2030.addr = alloca ptr
  store ptr %fv116, ptr %$f2030.addr
  %freed117 = call i64 @march_decrc_freed(ptr %ld107)
  %freed_b118 = icmp ne i64 %freed117, 0
  br i1 %freed_b118, label %br_unique37, label %br_shared38
br_shared38:
  call void @march_incrc(ptr %fv116)
  call void @march_incrc(ptr %fv114)
  br label %br_body39
br_unique37:
  br label %br_body39
br_body39:
  %ld119 = load ptr, ptr %$f2030.addr
  %rest.addr = alloca ptr
  store ptr %ld119, ptr %rest.addr
  %ld120 = load ptr, ptr %$f2029.addr
  %row.addr = alloca ptr
  store ptr %ld120, ptr %row.addr
  %ld121 = load ptr, ptr %row.addr
  call void @march_incrc(ptr %ld121)
  %ld122 = load ptr, ptr %row.addr
  %cr123 = call ptr @get_age(ptr %ld122)
  %$t2024.addr = alloca ptr
  store ptr %cr123, ptr %$t2024.addr
  %ld124 = load ptr, ptr %$t2024.addr
  %res_slot125 = alloca ptr
  %tgp126 = getelementptr i8, ptr %ld124, i64 8
  %tag127 = load i32, ptr %tgp126, align 4
  switch i32 %tag127, label %case_default41 [
      i32 1, label %case_br42
      i32 0, label %case_br43
  ]
case_br42:
  %fp128 = getelementptr i8, ptr %ld124, i64 16
  %fv129 = load ptr, ptr %fp128, align 8
  %$f2027.addr = alloca ptr
  store ptr %fv129, ptr %$f2027.addr
  %freed130 = call i64 @march_decrc_freed(ptr %ld124)
  %freed_b131 = icmp ne i64 %freed130, 0
  br i1 %freed_b131, label %br_unique44, label %br_shared45
br_shared45:
  call void @march_incrc(ptr %fv129)
  br label %br_body46
br_unique44:
  br label %br_body46
br_body46:
  %ld132 = load ptr, ptr %rest.addr
  %ld133 = load ptr, ptr %best_name.addr
  %ld134 = load i64, ptr %best_age.addr
  %cr135 = call ptr @find_oldest_loop(ptr %ld132, ptr %ld133, i64 %ld134)
  store ptr %cr135, ptr %res_slot125
  br label %case_merge40
case_br43:
  %fp136 = getelementptr i8, ptr %ld124, i64 16
  %fv137 = load ptr, ptr %fp136, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv137, ptr %$f2028.addr
  %ld138 = load ptr, ptr %$t2024.addr
  call void @march_decrc(ptr %ld138)
  %ld139 = load ptr, ptr %$f2028.addr
  %age.addr = alloca ptr
  store ptr %ld139, ptr %age.addr
  %ld140 = load ptr, ptr %age.addr
  %ld141 = load i64, ptr %best_age.addr
  %cv144 = ptrtoint ptr %ld140 to i64
  %cmp142 = icmp sgt i64 %cv144, %ld141
  %ar143 = zext i1 %cmp142 to i64
  %$t2025.addr = alloca i64
  store i64 %ar143, ptr %$t2025.addr
  %ld145 = load i64, ptr %$t2025.addr
  %res_slot146 = alloca ptr
  %bi147 = trunc i64 %ld145 to i1
  br i1 %bi147, label %case_br49, label %case_default48
case_br49:
  %ld148 = load ptr, ptr %row.addr
  %cr149 = call ptr @get_name(ptr %ld148)
  %$t2026.addr = alloca ptr
  store ptr %cr149, ptr %$t2026.addr
  %ld150 = load ptr, ptr %rest.addr
  %ld151 = load ptr, ptr %$t2026.addr
  %ld152 = load ptr, ptr %age.addr
  %cr153 = call ptr @find_oldest_loop(ptr %ld150, ptr %ld151, ptr %ld152)
  store ptr %cr153, ptr %res_slot146
  br label %case_merge47
case_default48:
  %ld154 = load ptr, ptr %rest.addr
  %ld155 = load ptr, ptr %best_name.addr
  %ld156 = load i64, ptr %best_age.addr
  %cr157 = call ptr @find_oldest_loop(ptr %ld154, ptr %ld155, i64 %ld156)
  store ptr %cr157, ptr %res_slot146
  br label %case_merge47
case_merge47:
  %case_r158 = load ptr, ptr %res_slot146
  store ptr %case_r158, ptr %res_slot125
  br label %case_merge40
case_default41:
  unreachable
case_merge40:
  %case_r159 = load ptr, ptr %res_slot125
  store ptr %case_r159, ptr %res_slot108
  br label %case_merge33
case_default34:
  unreachable
case_merge33:
  %case_r160 = load ptr, ptr %res_slot108
  ret ptr %case_r160
}

define ptr @demo_read_all(ptr %path.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %sl161 = call ptr @march_string_lit(ptr @.str8, i64 35)
  call void @march_println(ptr %sl161)
  %cv162 = inttoptr i64 0 to ptr
  %$t2031.addr = alloca ptr
  store ptr %cv162, ptr %$t2031.addr
  %ld163 = load ptr, ptr %path.addr
  %sl164 = call ptr @march_string_lit(ptr @.str9, i64 1)
  %ld165 = load ptr, ptr %$t2031.addr
  %cr166 = call ptr @Csv.read_all$String$String$Atom(ptr %ld163, ptr %sl164, ptr %ld165)
  %$t2032.addr = alloca ptr
  store ptr %cr166, ptr %$t2032.addr
  %ld167 = load ptr, ptr %$t2032.addr
  %res_slot168 = alloca ptr
  %tgp169 = getelementptr i8, ptr %ld167, i64 8
  %tag170 = load i32, ptr %tgp169, align 4
  switch i32 %tag170, label %case_default51 [
      i32 1, label %case_br52
      i32 0, label %case_br53
  ]
case_br52:
  %fp171 = getelementptr i8, ptr %ld167, i64 16
  %fv172 = load ptr, ptr %fp171, align 8
  %$f2042.addr = alloca ptr
  store ptr %fv172, ptr %$f2042.addr
  %freed173 = call i64 @march_decrc_freed(ptr %ld167)
  %freed_b174 = icmp ne i64 %freed173, 0
  br i1 %freed_b174, label %br_unique54, label %br_shared55
br_shared55:
  call void @march_incrc(ptr %fv172)
  br label %br_body56
br_unique54:
  br label %br_body56
br_body56:
  %ld175 = load ptr, ptr %$f2042.addr
  %e.addr = alloca ptr
  store ptr %ld175, ptr %e.addr
  %ld176 = load ptr, ptr %e.addr
  %cr177 = call ptr @march_value_to_string(ptr %ld176)
  %$t2033.addr = alloca ptr
  store ptr %cr177, ptr %$t2033.addr
  %sl178 = call ptr @march_string_lit(ptr @.str10, i64 7)
  %ld179 = load ptr, ptr %$t2033.addr
  %cr180 = call ptr @march_string_concat(ptr %sl178, ptr %ld179)
  %$t2034.addr = alloca ptr
  store ptr %cr180, ptr %$t2034.addr
  %ld181 = load ptr, ptr %$t2034.addr
  call void @march_println(ptr %ld181)
  %cv182 = inttoptr i64 0 to ptr
  store ptr %cv182, ptr %res_slot168
  br label %case_merge50
case_br53:
  %fp183 = getelementptr i8, ptr %ld167, i64 16
  %fv184 = load ptr, ptr %fp183, align 8
  %$f2043.addr = alloca ptr
  store ptr %fv184, ptr %$f2043.addr
  %freed185 = call i64 @march_decrc_freed(ptr %ld167)
  %freed_b186 = icmp ne i64 %freed185, 0
  br i1 %freed_b186, label %br_unique57, label %br_shared58
br_shared58:
  call void @march_incrc(ptr %fv184)
  br label %br_body59
br_unique57:
  br label %br_body59
br_body59:
  %ld187 = load ptr, ptr %$f2043.addr
  %rows.addr = alloca ptr
  store ptr %ld187, ptr %rows.addr
  %ld188 = load ptr, ptr %rows.addr
  call void @march_incrc(ptr %ld188)
  %ld189 = load ptr, ptr %rows.addr
  %cr190 = call ptr @List.length$List_List_String(ptr %ld189)
  %$t2035.addr = alloca ptr
  store ptr %cr190, ptr %$t2035.addr
  %ld191 = load ptr, ptr %$t2035.addr
  %cr192 = call ptr @march_value_to_string(ptr %ld191)
  %$t2036.addr = alloca ptr
  store ptr %cr192, ptr %$t2036.addr
  %sl193 = call ptr @march_string_lit(ptr @.str11, i64 27)
  %ld194 = load ptr, ptr %$t2036.addr
  %cr195 = call ptr @march_string_concat(ptr %sl193, ptr %ld194)
  %$t2037.addr = alloca ptr
  store ptr %cr195, ptr %$t2037.addr
  %ld196 = load ptr, ptr %$t2037.addr
  call void @march_println(ptr %ld196)
  %ld197 = load ptr, ptr %rows.addr
  %res_slot198 = alloca ptr
  %tgp199 = getelementptr i8, ptr %ld197, i64 8
  %tag200 = load i32, ptr %tgp199, align 4
  switch i32 %tag200, label %case_default61 [
      i32 0, label %case_br62
      i32 1, label %case_br63
  ]
case_br62:
  %ld201 = load ptr, ptr %rows.addr
  call void @march_decrc(ptr %ld201)
  %sl202 = call ptr @march_string_lit(ptr @.str12, i64 8)
  call void @march_println(ptr %sl202)
  %cv203 = inttoptr i64 0 to ptr
  store ptr %cv203, ptr %res_slot198
  br label %case_merge60
case_br63:
  %fp204 = getelementptr i8, ptr %ld197, i64 16
  %fv205 = load ptr, ptr %fp204, align 8
  %$f2040.addr = alloca ptr
  store ptr %fv205, ptr %$f2040.addr
  %fp206 = getelementptr i8, ptr %ld197, i64 24
  %fv207 = load ptr, ptr %fp206, align 8
  %$f2041.addr = alloca ptr
  store ptr %fv207, ptr %$f2041.addr
  %freed208 = call i64 @march_decrc_freed(ptr %ld197)
  %freed_b209 = icmp ne i64 %freed208, 0
  br i1 %freed_b209, label %br_unique64, label %br_shared65
br_shared65:
  call void @march_incrc(ptr %fv207)
  call void @march_incrc(ptr %fv205)
  br label %br_body66
br_unique64:
  br label %br_body66
br_body66:
  %ld210 = load ptr, ptr %$f2041.addr
  %data_rows.addr = alloca ptr
  store ptr %ld210, ptr %data_rows.addr
  %ar211 = sub i64 0, 1
  %$t2038.addr = alloca i64
  store i64 %ar211, ptr %$t2038.addr
  %ld212 = load ptr, ptr %data_rows.addr
  %sl213 = call ptr @march_string_lit(ptr @.str13, i64 6)
  %ld214 = load i64, ptr %$t2038.addr
  %cr215 = call ptr @find_oldest_loop(ptr %ld212, ptr %sl213, i64 %ld214)
  %oldest.addr = alloca ptr
  store ptr %cr215, ptr %oldest.addr
  %sl216 = call ptr @march_string_lit(ptr @.str14, i64 15)
  %ld217 = load ptr, ptr %oldest.addr
  %cr218 = call ptr @march_string_concat(ptr %sl216, ptr %ld217)
  %$t2039.addr = alloca ptr
  store ptr %cr218, ptr %$t2039.addr
  %ld219 = load ptr, ptr %$t2039.addr
  call void @march_println(ptr %ld219)
  %cv220 = inttoptr i64 0 to ptr
  store ptr %cv220, ptr %res_slot198
  br label %case_merge60
case_default61:
  unreachable
case_merge60:
  %case_r221 = load ptr, ptr %res_slot198
  store ptr %case_r221, ptr %res_slot168
  br label %case_merge50
case_default51:
  unreachable
case_merge50:
  %case_r222 = load ptr, ptr %res_slot168
  ret ptr %case_r222
}

define ptr @print_name_city(ptr %header.arg, ptr %row.arg) {
entry:
  %header.addr = alloca ptr
  store ptr %header.arg, ptr %header.addr
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld223 = load ptr, ptr %header.addr
  call void @march_incrc(ptr %ld223)
  %ld224 = load ptr, ptr %row.addr
  call void @march_incrc(ptr %ld224)
  %ld225 = load ptr, ptr %header.addr
  %header_i26.addr = alloca ptr
  store ptr %ld225, ptr %header_i26.addr
  %ld226 = load ptr, ptr %row.addr
  %row_i27.addr = alloca ptr
  store ptr %ld226, ptr %row_i27.addr
  %sl227 = call ptr @march_string_lit(ptr @.str15, i64 4)
  %name_i28.addr = alloca ptr
  store ptr %sl227, ptr %name_i28.addr
  %ld228 = load ptr, ptr %header_i26.addr
  %ld229 = load ptr, ptr %row_i27.addr
  %ld230 = load ptr, ptr %name_i28.addr
  %cr231 = call ptr @get_field_loop$List_String$List_String$String(ptr %ld228, ptr %ld229, ptr %ld230)
  %$t2049.addr = alloca ptr
  store ptr %cr231, ptr %$t2049.addr
  %ld232 = load ptr, ptr %$t2049.addr
  %res_slot233 = alloca ptr
  %tgp234 = getelementptr i8, ptr %ld232, i64 8
  %tag235 = load i32, ptr %tgp234, align 4
  switch i32 %tag235, label %case_default68 [
      i32 1, label %case_br69
      i32 0, label %case_br70
  ]
case_br69:
  %fp236 = getelementptr i8, ptr %ld232, i64 16
  %fv237 = load ptr, ptr %fp236, align 8
  %$f2050.addr = alloca ptr
  store ptr %fv237, ptr %$f2050.addr
  %freed238 = call i64 @march_decrc_freed(ptr %ld232)
  %freed_b239 = icmp ne i64 %freed238, 0
  br i1 %freed_b239, label %br_unique71, label %br_shared72
br_shared72:
  call void @march_incrc(ptr %fv237)
  br label %br_body73
br_unique71:
  br label %br_body73
br_body73:
  %ld240 = load ptr, ptr %$f2050.addr
  %v.addr = alloca ptr
  store ptr %ld240, ptr %v.addr
  %ld241 = load ptr, ptr %v.addr
  store ptr %ld241, ptr %res_slot233
  br label %case_merge67
case_br70:
  %ld242 = load ptr, ptr %$t2049.addr
  call void @march_decrc(ptr %ld242)
  %sl243 = call ptr @march_string_lit(ptr @.str16, i64 1)
  store ptr %sl243, ptr %res_slot233
  br label %case_merge67
case_default68:
  unreachable
case_merge67:
  %case_r244 = load ptr, ptr %res_slot233
  %name.addr = alloca ptr
  store ptr %case_r244, ptr %name.addr
  %ld245 = load ptr, ptr %header.addr
  %header_i23.addr = alloca ptr
  store ptr %ld245, ptr %header_i23.addr
  %ld246 = load ptr, ptr %row.addr
  %row_i24.addr = alloca ptr
  store ptr %ld246, ptr %row_i24.addr
  %sl247 = call ptr @march_string_lit(ptr @.str17, i64 4)
  %name_i25.addr = alloca ptr
  store ptr %sl247, ptr %name_i25.addr
  %ld248 = load ptr, ptr %header_i23.addr
  %ld249 = load ptr, ptr %row_i24.addr
  %ld250 = load ptr, ptr %name_i25.addr
  %cr251 = call ptr @get_field_loop$List_String$List_String$String(ptr %ld248, ptr %ld249, ptr %ld250)
  %$t2051.addr = alloca ptr
  store ptr %cr251, ptr %$t2051.addr
  %ld252 = load ptr, ptr %$t2051.addr
  %res_slot253 = alloca ptr
  %tgp254 = getelementptr i8, ptr %ld252, i64 8
  %tag255 = load i32, ptr %tgp254, align 4
  switch i32 %tag255, label %case_default75 [
      i32 1, label %case_br76
      i32 0, label %case_br77
  ]
case_br76:
  %fp256 = getelementptr i8, ptr %ld252, i64 16
  %fv257 = load ptr, ptr %fp256, align 8
  %$f2052.addr = alloca ptr
  store ptr %fv257, ptr %$f2052.addr
  %freed258 = call i64 @march_decrc_freed(ptr %ld252)
  %freed_b259 = icmp ne i64 %freed258, 0
  br i1 %freed_b259, label %br_unique78, label %br_shared79
br_shared79:
  call void @march_incrc(ptr %fv257)
  br label %br_body80
br_unique78:
  br label %br_body80
br_body80:
  %ld260 = load ptr, ptr %$f2052.addr
  %v_1.addr = alloca ptr
  store ptr %ld260, ptr %v_1.addr
  %ld261 = load ptr, ptr %v_1.addr
  store ptr %ld261, ptr %res_slot253
  br label %case_merge74
case_br77:
  %ld262 = load ptr, ptr %$t2051.addr
  call void @march_decrc(ptr %ld262)
  %sl263 = call ptr @march_string_lit(ptr @.str18, i64 1)
  store ptr %sl263, ptr %res_slot253
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r264 = load ptr, ptr %res_slot253
  %city.addr = alloca ptr
  store ptr %case_r264, ptr %city.addr
  %ld265 = load ptr, ptr %name.addr
  %sl266 = call ptr @march_string_lit(ptr @.str19, i64 10)
  %cr267 = call ptr @march_string_concat(ptr %ld265, ptr %sl266)
  %$t2053.addr = alloca ptr
  store ptr %cr267, ptr %$t2053.addr
  %ld268 = load ptr, ptr %$t2053.addr
  %ld269 = load ptr, ptr %city.addr
  %cr270 = call ptr @march_string_concat(ptr %ld268, ptr %ld269)
  %$t2054.addr = alloca ptr
  store ptr %cr270, ptr %$t2054.addr
  %ld271 = load ptr, ptr %$t2054.addr
  call void @march_println(ptr %ld271)
  %cv272 = inttoptr i64 0 to ptr
  ret ptr %cv272
}

define ptr @march_main() {
entry:
  %sl273 = call ptr @march_string_lit(ptr @.str20, i64 23)
  %csv_path.addr = alloca ptr
  store ptr %sl273, ptr %csv_path.addr
  %sl274 = call ptr @march_string_lit(ptr @.str21, i64 23)
  %tsv_path.addr = alloca ptr
  store ptr %sl274, ptr %tsv_path.addr
  %ld275 = load ptr, ptr %csv_path.addr
  call void @march_incrc(ptr %ld275)
  %ld276 = load ptr, ptr %csv_path.addr
  %path_i31.addr = alloca ptr
  store ptr %ld276, ptr %path_i31.addr
  %sl277 = call ptr @march_string_lit(ptr @.str22, i64 90)
  %content_i32.addr = alloca ptr
  store ptr %sl277, ptr %content_i32.addr
  %ld278 = load ptr, ptr %path_i31.addr
  %ld279 = load ptr, ptr %content_i32.addr
  %cr280 = call ptr @File.write(ptr %ld278, ptr %ld279)
  %ld281 = load ptr, ptr %tsv_path.addr
  call void @march_incrc(ptr %ld281)
  %ld282 = load ptr, ptr %tsv_path.addr
  %path_i29.addr = alloca ptr
  store ptr %ld282, ptr %path_i29.addr
  %sl283 = call ptr @march_string_lit(ptr @.str23, i64 62)
  %content_i30.addr = alloca ptr
  store ptr %sl283, ptr %content_i30.addr
  %ld284 = load ptr, ptr %path_i29.addr
  %ld285 = load ptr, ptr %content_i30.addr
  %cr286 = call ptr @File.write(ptr %ld284, ptr %ld285)
  %ld287 = load ptr, ptr %csv_path.addr
  call void @march_incrc(ptr %ld287)
  %ld288 = load ptr, ptr %csv_path.addr
  %cr289 = call ptr @demo_each_row(ptr %ld288)
  %ld290 = load ptr, ptr %csv_path.addr
  call void @march_incrc(ptr %ld290)
  %ld291 = load ptr, ptr %csv_path.addr
  %cr292 = call ptr @demo_read_all(ptr %ld291)
  %ld293 = load ptr, ptr %csv_path.addr
  %cr294 = call ptr @demo_with_header(ptr %ld293)
  %ld295 = load ptr, ptr %tsv_path.addr
  %cr296 = call ptr @demo_tsv(ptr %ld295)
  %sl297 = call ptr @march_string_lit(ptr @.str24, i64 19)
  call void @march_println(ptr %sl297)
  %cv298 = inttoptr i64 0 to ptr
  ret ptr %cv298
}

define ptr @Csv.each_row$String$String$Atom$Fn_V__6177_T_(ptr %path.arg, ptr %delimiter.arg, ptr %mode.arg, ptr %callback.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %delimiter.addr = alloca ptr
  store ptr %delimiter.arg, ptr %delimiter.addr
  %mode.addr = alloca ptr
  store ptr %mode.arg, ptr %mode.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld299 = load ptr, ptr %path.addr
  %ld300 = load ptr, ptr %delimiter.addr
  %ld301 = load ptr, ptr %mode.addr
  %cr302 = call ptr @csv_open(ptr %ld299, ptr %ld300, ptr %ld301)
  %$t1701.addr = alloca ptr
  store ptr %cr302, ptr %$t1701.addr
  %ld303 = load ptr, ptr %$t1701.addr
  %res_slot304 = alloca ptr
  %tgp305 = getelementptr i8, ptr %ld303, i64 8
  %tag306 = load i32, ptr %tgp305, align 4
  switch i32 %tag306, label %case_default82 [
      i32 1, label %case_br83
      i32 0, label %case_br84
  ]
case_br83:
  %fp307 = getelementptr i8, ptr %ld303, i64 16
  %fv308 = load ptr, ptr %fp307, align 8
  %$f1703.addr = alloca ptr
  store ptr %fv308, ptr %$f1703.addr
  %freed309 = call i64 @march_decrc_freed(ptr %ld303)
  %freed_b310 = icmp ne i64 %freed309, 0
  br i1 %freed_b310, label %br_unique85, label %br_shared86
br_shared86:
  call void @march_incrc(ptr %fv308)
  br label %br_body87
br_unique85:
  br label %br_body87
br_body87:
  %ld311 = load ptr, ptr %$f1703.addr
  %e.addr = alloca ptr
  store ptr %ld311, ptr %e.addr
  %hp312 = call ptr @march_alloc(i64 24)
  %tgp313 = getelementptr i8, ptr %hp312, i64 8
  store i32 1, ptr %tgp313, align 4
  %ld314 = load ptr, ptr %e.addr
  %fp315 = getelementptr i8, ptr %hp312, i64 16
  store ptr %ld314, ptr %fp315, align 8
  store ptr %hp312, ptr %res_slot304
  br label %case_merge81
case_br84:
  %fp316 = getelementptr i8, ptr %ld303, i64 16
  %fv317 = load ptr, ptr %fp316, align 8
  %$f1704.addr = alloca ptr
  store ptr %fv317, ptr %$f1704.addr
  %freed318 = call i64 @march_decrc_freed(ptr %ld303)
  %freed_b319 = icmp ne i64 %freed318, 0
  br i1 %freed_b319, label %br_unique88, label %br_shared89
br_shared89:
  call void @march_incrc(ptr %fv317)
  br label %br_body90
br_unique88:
  br label %br_body90
br_body90:
  %ld320 = load ptr, ptr %$f1704.addr
  %handle.addr = alloca ptr
  store ptr %ld320, ptr %handle.addr
  %ld321 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld321)
  %ld322 = load ptr, ptr %handle.addr
  %ld323 = load ptr, ptr %callback.addr
  %cr324 = call ptr @Csv.each_row_loop$V__5509$Fn_V__6177_T_(ptr %ld322, ptr %ld323)
  %ld325 = load ptr, ptr %handle.addr
  %cr326 = call ptr @csv_close(ptr %ld325)
  %cv327 = inttoptr i64 0 to ptr
  %$t1702.addr = alloca ptr
  store ptr %cv327, ptr %$t1702.addr
  %hp328 = call ptr @march_alloc(i64 24)
  %tgp329 = getelementptr i8, ptr %hp328, i64 8
  store i32 0, ptr %tgp329, align 4
  %ld330 = load ptr, ptr %$t1702.addr
  %fp331 = getelementptr i8, ptr %hp328, i64 16
  store ptr %ld330, ptr %fp331, align 8
  store ptr %hp328, ptr %res_slot304
  br label %case_merge81
case_default82:
  unreachable
case_merge81:
  %case_r332 = load ptr, ptr %res_slot304
  ret ptr %case_r332
}

define ptr @print_row$V__6177(ptr %row.arg) {
entry:
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld333 = load ptr, ptr %row.addr
  %cr334 = call ptr @march_value_to_string(ptr %ld333)
  %$t2009.addr = alloca ptr
  store ptr %cr334, ptr %$t2009.addr
  %ld335 = load ptr, ptr %$t2009.addr
  call void @march_print(ptr %ld335)
  %cv336 = inttoptr i64 0 to ptr
  ret ptr %cv336
}

define i64 @List.length$List_List_String(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp337 = call ptr @march_alloc(i64 24)
  %tgp338 = getelementptr i8, ptr %hp337, i64 8
  store i32 0, ptr %tgp338, align 4
  %fp339 = getelementptr i8, ptr %hp337, i64 16
  store ptr @go$apply$25, ptr %fp339, align 8
  %go.addr = alloca ptr
  store ptr %hp337, ptr %go.addr
  %ld340 = load ptr, ptr %go.addr
  %fp341 = getelementptr i8, ptr %ld340, i64 16
  %fv342 = load ptr, ptr %fp341, align 8
  %ld343 = load ptr, ptr %xs.addr
  %cr344 = call i64 (ptr, ptr, i64) %fv342(ptr %ld340, ptr %ld343, i64 0)
  ret i64 %cr344
}

define ptr @Csv.read_all$String$String$Atom(ptr %path.arg, ptr %delimiter.arg, ptr %mode.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %delimiter.addr = alloca ptr
  store ptr %delimiter.arg, ptr %delimiter.addr
  %mode.addr = alloca ptr
  store ptr %mode.arg, ptr %mode.addr
  %ld345 = load ptr, ptr %path.addr
  %ld346 = load ptr, ptr %delimiter.addr
  %ld347 = load ptr, ptr %mode.addr
  %cr348 = call ptr @csv_open(ptr %ld345, ptr %ld346, ptr %ld347)
  %$t1708.addr = alloca ptr
  store ptr %cr348, ptr %$t1708.addr
  %ld349 = load ptr, ptr %$t1708.addr
  %res_slot350 = alloca ptr
  %tgp351 = getelementptr i8, ptr %ld349, i64 8
  %tag352 = load i32, ptr %tgp351, align 4
  switch i32 %tag352, label %case_default92 [
      i32 1, label %case_br93
      i32 0, label %case_br94
  ]
case_br93:
  %fp353 = getelementptr i8, ptr %ld349, i64 16
  %fv354 = load ptr, ptr %fp353, align 8
  %$f1710.addr = alloca ptr
  store ptr %fv354, ptr %$f1710.addr
  %freed355 = call i64 @march_decrc_freed(ptr %ld349)
  %freed_b356 = icmp ne i64 %freed355, 0
  br i1 %freed_b356, label %br_unique95, label %br_shared96
br_shared96:
  call void @march_incrc(ptr %fv354)
  br label %br_body97
br_unique95:
  br label %br_body97
br_body97:
  %ld357 = load ptr, ptr %$f1710.addr
  %e.addr = alloca ptr
  store ptr %ld357, ptr %e.addr
  %hp358 = call ptr @march_alloc(i64 24)
  %tgp359 = getelementptr i8, ptr %hp358, i64 8
  store i32 1, ptr %tgp359, align 4
  %ld360 = load ptr, ptr %e.addr
  %fp361 = getelementptr i8, ptr %hp358, i64 16
  store ptr %ld360, ptr %fp361, align 8
  store ptr %hp358, ptr %res_slot350
  br label %case_merge91
case_br94:
  %fp362 = getelementptr i8, ptr %ld349, i64 16
  %fv363 = load ptr, ptr %fp362, align 8
  %$f1711.addr = alloca ptr
  store ptr %fv363, ptr %$f1711.addr
  %freed364 = call i64 @march_decrc_freed(ptr %ld349)
  %freed_b365 = icmp ne i64 %freed364, 0
  br i1 %freed_b365, label %br_unique98, label %br_shared99
br_shared99:
  call void @march_incrc(ptr %fv363)
  br label %br_body100
br_unique98:
  br label %br_body100
br_body100:
  %ld366 = load ptr, ptr %$f1711.addr
  %handle.addr = alloca ptr
  store ptr %ld366, ptr %handle.addr
  %hp367 = call ptr @march_alloc(i64 16)
  %tgp368 = getelementptr i8, ptr %hp367, i64 8
  store i32 0, ptr %tgp368, align 4
  %$t1709.addr = alloca ptr
  store ptr %hp367, ptr %$t1709.addr
  %ld369 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld369)
  %ld370 = load ptr, ptr %handle.addr
  %ld371 = load ptr, ptr %$t1709.addr
  %cr372 = call ptr @Csv.collect_loop$V__5533$List_String(ptr %ld370, ptr %ld371)
  %rows.addr = alloca ptr
  store ptr %cr372, ptr %rows.addr
  %ld373 = load ptr, ptr %handle.addr
  %cr374 = call ptr @csv_close(ptr %ld373)
  %hp375 = call ptr @march_alloc(i64 24)
  %tgp376 = getelementptr i8, ptr %hp375, i64 8
  store i32 0, ptr %tgp376, align 4
  %ld377 = load ptr, ptr %rows.addr
  %fp378 = getelementptr i8, ptr %hp375, i64 16
  store ptr %ld377, ptr %fp378, align 8
  store ptr %hp375, ptr %res_slot350
  br label %case_merge91
case_default92:
  unreachable
case_merge91:
  %case_r379 = load ptr, ptr %res_slot350
  ret ptr %case_r379
}

define ptr @demo_tsv(ptr %path.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %sl380 = call ptr @march_string_lit(ptr @.str25, i64 40)
  call void @march_println(ptr %sl380)
  %cv381 = inttoptr i64 0 to ptr
  %$t2058.addr = alloca ptr
  store ptr %cv381, ptr %$t2058.addr
  %hp382 = call ptr @march_alloc(i64 24)
  %tgp383 = getelementptr i8, ptr %hp382, i64 8
  store i32 0, ptr %tgp383, align 4
  %fp384 = getelementptr i8, ptr %hp382, i64 16
  store ptr @$lam2059$apply$26, ptr %fp384, align 8
  %$t2061.addr = alloca ptr
  store ptr %hp382, ptr %$t2061.addr
  %ld385 = load ptr, ptr %path.addr
  %sl386 = call ptr @march_string_lit(ptr @.str26, i64 1)
  %ld387 = load ptr, ptr %$t2058.addr
  %ld388 = load ptr, ptr %$t2061.addr
  %cr389 = call ptr @Csv.each_row$String$String$Atom$Fn_V__6177_T_(ptr %ld385, ptr %sl386, ptr %ld387, ptr %ld388)
  ret ptr %cr389
}

define ptr @demo_with_header(ptr %path.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %sl390 = call ptr @march_string_lit(ptr @.str27, i64 39)
  call void @march_println(ptr %sl390)
  %cv391 = inttoptr i64 0 to ptr
  %$t2055.addr = alloca ptr
  store ptr %cv391, ptr %$t2055.addr
  %hp392 = call ptr @march_alloc(i64 24)
  %tgp393 = getelementptr i8, ptr %hp392, i64 8
  store i32 0, ptr %tgp393, align 4
  %fp394 = getelementptr i8, ptr %hp392, i64 16
  store ptr @$lam2056$apply$27, ptr %fp394, align 8
  %$t2057.addr = alloca ptr
  store ptr %hp392, ptr %$t2057.addr
  %ld395 = load ptr, ptr %path.addr
  %sl396 = call ptr @march_string_lit(ptr @.str28, i64 1)
  %ld397 = load ptr, ptr %$t2055.addr
  %ld398 = load ptr, ptr %$t2057.addr
  %cr399 = call ptr @Csv.each_row_with_header$String$String$Atom$Fn_List_String_List_String_T_(ptr %ld395, ptr %sl396, ptr %ld397, ptr %ld398)
  ret ptr %cr399
}

define ptr @Csv.each_row_loop$V__5509$Fn_V__6177_T_(ptr %handle.arg, ptr %callback.arg) {
entry:
  %handle.addr = alloca ptr
  store ptr %handle.arg, ptr %handle.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld400 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld400)
  %ld401 = load ptr, ptr %handle.addr
  %cr402 = call ptr @csv_next_row(ptr %ld401)
  %$t1699.addr = alloca ptr
  store ptr %cr402, ptr %$t1699.addr
  %ld403 = load ptr, ptr %$t1699.addr
  %res_slot404 = alloca ptr
  %tgp405 = getelementptr i8, ptr %ld403, i64 8
  %tag406 = load i32, ptr %tgp405, align 4
  switch i32 %tag406, label %case_default102 [
      i32 0, label %case_br103
  ]
case_br103:
  %fp407 = getelementptr i8, ptr %ld403, i64 16
  %fv408 = load ptr, ptr %fp407, align 8
  %$f1700.addr = alloca ptr
  store ptr %fv408, ptr %$f1700.addr
  %freed409 = call i64 @march_decrc_freed(ptr %ld403)
  %freed_b410 = icmp ne i64 %freed409, 0
  br i1 %freed_b410, label %br_unique104, label %br_shared105
br_shared105:
  call void @march_incrc(ptr %fv408)
  br label %br_body106
br_unique104:
  br label %br_body106
br_body106:
  %ld411 = load ptr, ptr %$f1700.addr
  %fields.addr = alloca ptr
  store ptr %ld411, ptr %fields.addr
  %ld412 = load ptr, ptr %callback.addr
  %fp413 = getelementptr i8, ptr %ld412, i64 16
  %fv414 = load ptr, ptr %fp413, align 8
  %ld415 = load ptr, ptr %fields.addr
  %cr416 = call ptr (ptr, ptr) %fv414(ptr %ld412, ptr %ld415)
  %ld417 = load ptr, ptr %handle.addr
  %ld418 = load ptr, ptr %callback.addr
  %cr419 = call ptr @Csv.each_row_loop$V__5509$Fn_V__6177_T_(ptr %ld417, ptr %ld418)
  store ptr %cr419, ptr %res_slot404
  br label %case_merge101
case_default102:
  unreachable
case_merge101:
  %case_r420 = load ptr, ptr %res_slot404
  ret ptr %case_r420
}

define ptr @Csv.collect_loop$V__5533$List_String(ptr %handle.arg, ptr %acc.arg) {
entry:
  %handle.addr = alloca ptr
  store ptr %handle.arg, ptr %handle.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld421 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld421)
  %ld422 = load ptr, ptr %handle.addr
  %cr423 = call ptr @csv_next_row(ptr %ld422)
  %$t1705.addr = alloca ptr
  store ptr %cr423, ptr %$t1705.addr
  %ld424 = load ptr, ptr %$t1705.addr
  %res_slot425 = alloca ptr
  %tgp426 = getelementptr i8, ptr %ld424, i64 8
  %tag427 = load i32, ptr %tgp426, align 4
  switch i32 %tag427, label %case_default108 [
      i32 0, label %case_br109
  ]
case_br109:
  %fp428 = getelementptr i8, ptr %ld424, i64 16
  %fv429 = load ptr, ptr %fp428, align 8
  %$f1707.addr = alloca ptr
  store ptr %fv429, ptr %$f1707.addr
  %freed430 = call i64 @march_decrc_freed(ptr %ld424)
  %freed_b431 = icmp ne i64 %freed430, 0
  br i1 %freed_b431, label %br_unique110, label %br_shared111
br_shared111:
  call void @march_incrc(ptr %fv429)
  br label %br_body112
br_unique110:
  br label %br_body112
br_body112:
  %ld432 = load ptr, ptr %$f1707.addr
  %fields.addr = alloca ptr
  store ptr %ld432, ptr %fields.addr
  %hp433 = call ptr @march_alloc(i64 32)
  %tgp434 = getelementptr i8, ptr %hp433, i64 8
  store i32 1, ptr %tgp434, align 4
  %ld435 = load ptr, ptr %fields.addr
  %fp436 = getelementptr i8, ptr %hp433, i64 16
  store ptr %ld435, ptr %fp436, align 8
  %ld437 = load ptr, ptr %acc.addr
  %fp438 = getelementptr i8, ptr %hp433, i64 24
  store ptr %ld437, ptr %fp438, align 8
  %$t1706.addr = alloca ptr
  store ptr %hp433, ptr %$t1706.addr
  %ld439 = load ptr, ptr %handle.addr
  %ld440 = load ptr, ptr %$t1706.addr
  %cr441 = call ptr @Csv.collect_loop$V__5533$List_String(ptr %ld439, ptr %ld440)
  store ptr %cr441, ptr %res_slot425
  br label %case_merge107
case_default108:
  unreachable
case_merge107:
  %case_r442 = load ptr, ptr %res_slot425
  ret ptr %case_r442
}

define ptr @get_field_loop$List_String$List_String$String(ptr %hs.arg, ptr %rs.arg, ptr %name.arg) {
entry:
  %hs.addr = alloca ptr
  store ptr %hs.arg, ptr %hs.addr
  %rs.addr = alloca ptr
  store ptr %rs.arg, ptr %rs.addr
  %name.addr = alloca ptr
  store ptr %name.arg, ptr %name.addr
  %ld443 = load ptr, ptr %hs.addr
  %res_slot444 = alloca ptr
  %tgp445 = getelementptr i8, ptr %ld443, i64 8
  %tag446 = load i32, ptr %tgp445, align 4
  switch i32 %tag446, label %case_default114 [
      i32 0, label %case_br115
      i32 1, label %case_br116
  ]
case_br115:
  %ld447 = load ptr, ptr %hs.addr
  call void @march_decrc(ptr %ld447)
  %hp448 = call ptr @march_alloc(i64 16)
  %tgp449 = getelementptr i8, ptr %hp448, i64 8
  store i32 0, ptr %tgp449, align 4
  store ptr %hp448, ptr %res_slot444
  br label %case_merge113
case_br116:
  %fp450 = getelementptr i8, ptr %ld443, i64 16
  %fv451 = load ptr, ptr %fp450, align 8
  %$f2047.addr = alloca ptr
  store ptr %fv451, ptr %$f2047.addr
  %fp452 = getelementptr i8, ptr %ld443, i64 24
  %fv453 = load ptr, ptr %fp452, align 8
  %$f2048.addr = alloca ptr
  store ptr %fv453, ptr %$f2048.addr
  %freed454 = call i64 @march_decrc_freed(ptr %ld443)
  %freed_b455 = icmp ne i64 %freed454, 0
  br i1 %freed_b455, label %br_unique117, label %br_shared118
br_shared118:
  call void @march_incrc(ptr %fv453)
  call void @march_incrc(ptr %fv451)
  br label %br_body119
br_unique117:
  br label %br_body119
br_body119:
  %ld456 = load ptr, ptr %$f2048.addr
  %rh.addr = alloca ptr
  store ptr %ld456, ptr %rh.addr
  %ld457 = load ptr, ptr %$f2047.addr
  %h.addr = alloca ptr
  store ptr %ld457, ptr %h.addr
  %ld458 = load ptr, ptr %rs.addr
  %res_slot459 = alloca ptr
  %tgp460 = getelementptr i8, ptr %ld458, i64 8
  %tag461 = load i32, ptr %tgp460, align 4
  switch i32 %tag461, label %case_default121 [
      i32 0, label %case_br122
      i32 1, label %case_br123
  ]
case_br122:
  %ld462 = load ptr, ptr %rs.addr
  call void @march_decrc(ptr %ld462)
  %hp463 = call ptr @march_alloc(i64 16)
  %tgp464 = getelementptr i8, ptr %hp463, i64 8
  store i32 0, ptr %tgp464, align 4
  store ptr %hp463, ptr %res_slot459
  br label %case_merge120
case_br123:
  %fp465 = getelementptr i8, ptr %ld458, i64 16
  %fv466 = load ptr, ptr %fp465, align 8
  %$f2045.addr = alloca ptr
  store ptr %fv466, ptr %$f2045.addr
  %fp467 = getelementptr i8, ptr %ld458, i64 24
  %fv468 = load ptr, ptr %fp467, align 8
  %$f2046.addr = alloca ptr
  store ptr %fv468, ptr %$f2046.addr
  %freed469 = call i64 @march_decrc_freed(ptr %ld458)
  %freed_b470 = icmp ne i64 %freed469, 0
  br i1 %freed_b470, label %br_unique124, label %br_shared125
br_shared125:
  call void @march_incrc(ptr %fv468)
  call void @march_incrc(ptr %fv466)
  br label %br_body126
br_unique124:
  br label %br_body126
br_body126:
  %ld471 = load ptr, ptr %$f2046.addr
  %rv.addr = alloca ptr
  store ptr %ld471, ptr %rv.addr
  %ld472 = load ptr, ptr %$f2045.addr
  %v.addr = alloca ptr
  store ptr %ld472, ptr %v.addr
  %ld473 = load ptr, ptr %name.addr
  call void @march_incrc(ptr %ld473)
  %ld474 = load ptr, ptr %h.addr
  %ld475 = load ptr, ptr %name.addr
  %cr476 = call i64 @march_string_eq(ptr %ld474, ptr %ld475)
  %$t2044.addr = alloca i64
  store i64 %cr476, ptr %$t2044.addr
  %ld477 = load i64, ptr %$t2044.addr
  %res_slot478 = alloca ptr
  %bi479 = trunc i64 %ld477 to i1
  br i1 %bi479, label %case_br129, label %case_default128
case_br129:
  %hp480 = call ptr @march_alloc(i64 24)
  %tgp481 = getelementptr i8, ptr %hp480, i64 8
  store i32 1, ptr %tgp481, align 4
  %ld482 = load ptr, ptr %v.addr
  %fp483 = getelementptr i8, ptr %hp480, i64 16
  store ptr %ld482, ptr %fp483, align 8
  store ptr %hp480, ptr %res_slot478
  br label %case_merge127
case_default128:
  %ld484 = load ptr, ptr %rh.addr
  %ld485 = load ptr, ptr %rv.addr
  %ld486 = load ptr, ptr %name.addr
  %cr487 = call ptr @get_field_loop$List_String$List_String$String(ptr %ld484, ptr %ld485, ptr %ld486)
  store ptr %cr487, ptr %res_slot478
  br label %case_merge127
case_merge127:
  %case_r488 = load ptr, ptr %res_slot478
  store ptr %case_r488, ptr %res_slot459
  br label %case_merge120
case_default121:
  unreachable
case_merge120:
  %case_r489 = load ptr, ptr %res_slot459
  store ptr %case_r489, ptr %res_slot444
  br label %case_merge113
case_default114:
  unreachable
case_merge113:
  %case_r490 = load ptr, ptr %res_slot444
  ret ptr %case_r490
}

define ptr @Csv.each_row_with_header$String$String$Atom$Fn_List_String_List_String_T_(ptr %path.arg, ptr %delimiter.arg, ptr %mode.arg, ptr %callback.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %delimiter.addr = alloca ptr
  store ptr %delimiter.arg, ptr %delimiter.addr
  %mode.addr = alloca ptr
  store ptr %mode.arg, ptr %mode.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld491 = load ptr, ptr %path.addr
  %ld492 = load ptr, ptr %delimiter.addr
  %ld493 = load ptr, ptr %mode.addr
  %cr494 = call ptr @csv_open(ptr %ld491, ptr %ld492, ptr %ld493)
  %$t1714.addr = alloca ptr
  store ptr %cr494, ptr %$t1714.addr
  %ld495 = load ptr, ptr %$t1714.addr
  %res_slot496 = alloca ptr
  %tgp497 = getelementptr i8, ptr %ld495, i64 8
  %tag498 = load i32, ptr %tgp497, align 4
  switch i32 %tag498, label %case_default131 [
      i32 1, label %case_br132
      i32 0, label %case_br133
  ]
case_br132:
  %fp499 = getelementptr i8, ptr %ld495, i64 16
  %fv500 = load ptr, ptr %fp499, align 8
  %$f1719.addr = alloca ptr
  store ptr %fv500, ptr %$f1719.addr
  %freed501 = call i64 @march_decrc_freed(ptr %ld495)
  %freed_b502 = icmp ne i64 %freed501, 0
  br i1 %freed_b502, label %br_unique134, label %br_shared135
br_shared135:
  call void @march_incrc(ptr %fv500)
  br label %br_body136
br_unique134:
  br label %br_body136
br_body136:
  %ld503 = load ptr, ptr %$f1719.addr
  %e.addr = alloca ptr
  store ptr %ld503, ptr %e.addr
  %hp504 = call ptr @march_alloc(i64 24)
  %tgp505 = getelementptr i8, ptr %hp504, i64 8
  store i32 1, ptr %tgp505, align 4
  %ld506 = load ptr, ptr %e.addr
  %fp507 = getelementptr i8, ptr %hp504, i64 16
  store ptr %ld506, ptr %fp507, align 8
  store ptr %hp504, ptr %res_slot496
  br label %case_merge130
case_br133:
  %fp508 = getelementptr i8, ptr %ld495, i64 16
  %fv509 = load ptr, ptr %fp508, align 8
  %$f1720.addr = alloca ptr
  store ptr %fv509, ptr %$f1720.addr
  %freed510 = call i64 @march_decrc_freed(ptr %ld495)
  %freed_b511 = icmp ne i64 %freed510, 0
  br i1 %freed_b511, label %br_unique137, label %br_shared138
br_shared138:
  call void @march_incrc(ptr %fv509)
  br label %br_body139
br_unique137:
  br label %br_body139
br_body139:
  %ld512 = load ptr, ptr %$f1720.addr
  %handle.addr = alloca ptr
  store ptr %ld512, ptr %handle.addr
  %ld513 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld513)
  %ld514 = load ptr, ptr %handle.addr
  %cr515 = call ptr @csv_next_row(ptr %ld514)
  %$t1715.addr = alloca ptr
  store ptr %cr515, ptr %$t1715.addr
  %ld516 = load ptr, ptr %$t1715.addr
  %res_slot517 = alloca ptr
  %tgp518 = getelementptr i8, ptr %ld516, i64 8
  %tag519 = load i32, ptr %tgp518, align 4
  switch i32 %tag519, label %case_default141 [
      i32 0, label %case_br142
  ]
case_br142:
  %fp520 = getelementptr i8, ptr %ld516, i64 16
  %fv521 = load ptr, ptr %fp520, align 8
  %$f1718.addr = alloca ptr
  store ptr %fv521, ptr %$f1718.addr
  %freed522 = call i64 @march_decrc_freed(ptr %ld516)
  %freed_b523 = icmp ne i64 %freed522, 0
  br i1 %freed_b523, label %br_unique143, label %br_shared144
br_shared144:
  call void @march_incrc(ptr %fv521)
  br label %br_body145
br_unique143:
  br label %br_body145
br_body145:
  %ld524 = load ptr, ptr %$f1718.addr
  %header.addr = alloca ptr
  store ptr %ld524, ptr %header.addr
  %ld525 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld525)
  %ld526 = load ptr, ptr %handle.addr
  %ld527 = load ptr, ptr %header.addr
  %ld528 = load ptr, ptr %callback.addr
  %cr529 = call ptr @Csv.with_header_loop$V__5569$List_String$Fn_List_String_List_String_T_(ptr %ld526, ptr %ld527, ptr %ld528)
  %ld530 = load ptr, ptr %handle.addr
  %cr531 = call ptr @csv_close(ptr %ld530)
  %cv532 = inttoptr i64 0 to ptr
  %$t1717.addr = alloca ptr
  store ptr %cv532, ptr %$t1717.addr
  %hp533 = call ptr @march_alloc(i64 24)
  %tgp534 = getelementptr i8, ptr %hp533, i64 8
  store i32 0, ptr %tgp534, align 4
  %ld535 = load ptr, ptr %$t1717.addr
  %fp536 = getelementptr i8, ptr %hp533, i64 16
  store ptr %ld535, ptr %fp536, align 8
  store ptr %hp533, ptr %res_slot517
  br label %case_merge140
case_default141:
  unreachable
case_merge140:
  %case_r537 = load ptr, ptr %res_slot517
  store ptr %case_r537, ptr %res_slot496
  br label %case_merge130
case_default131:
  unreachable
case_merge130:
  %case_r538 = load ptr, ptr %res_slot496
  ret ptr %case_r538
}

define ptr @File.write(ptr %path.arg, ptr %data.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %data.addr = alloca ptr
  store ptr %data.arg, ptr %data.addr
  %ld539 = load ptr, ptr %file_write.addr
  %fp540 = getelementptr i8, ptr %ld539, i64 16
  %fv541 = load ptr, ptr %fp540, align 8
  %ld542 = load ptr, ptr %path.addr
  %ld543 = load ptr, ptr %data.addr
  %cr544 = call ptr (ptr, ptr, ptr) %fv541(ptr %ld539, ptr %ld542, ptr %ld543)
  ret ptr %cr544
}

define ptr @Csv.with_header_loop$V__5569$List_String$Fn_List_String_List_String_T_(ptr %handle.arg, ptr %header.arg, ptr %callback.arg) {
entry:
  %handle.addr = alloca ptr
  store ptr %handle.arg, ptr %handle.addr
  %header.addr = alloca ptr
  store ptr %header.arg, ptr %header.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld545 = load ptr, ptr %handle.addr
  call void @march_incrc(ptr %ld545)
  %ld546 = load ptr, ptr %handle.addr
  %cr547 = call ptr @csv_next_row(ptr %ld546)
  %$t1712.addr = alloca ptr
  store ptr %cr547, ptr %$t1712.addr
  %ld548 = load ptr, ptr %$t1712.addr
  %res_slot549 = alloca ptr
  %tgp550 = getelementptr i8, ptr %ld548, i64 8
  %tag551 = load i32, ptr %tgp550, align 4
  switch i32 %tag551, label %case_default147 [
      i32 0, label %case_br148
  ]
case_br148:
  %fp552 = getelementptr i8, ptr %ld548, i64 16
  %fv553 = load ptr, ptr %fp552, align 8
  %$f1713.addr = alloca ptr
  store ptr %fv553, ptr %$f1713.addr
  %freed554 = call i64 @march_decrc_freed(ptr %ld548)
  %freed_b555 = icmp ne i64 %freed554, 0
  br i1 %freed_b555, label %br_unique149, label %br_shared150
br_shared150:
  call void @march_incrc(ptr %fv553)
  br label %br_body151
br_unique149:
  br label %br_body151
br_body151:
  %ld556 = load ptr, ptr %$f1713.addr
  %fields.addr = alloca ptr
  store ptr %ld556, ptr %fields.addr
  %ld557 = load ptr, ptr %header.addr
  call void @march_incrc(ptr %ld557)
  %ld558 = load ptr, ptr %callback.addr
  %fp559 = getelementptr i8, ptr %ld558, i64 16
  %fv560 = load ptr, ptr %fp559, align 8
  %ld561 = load ptr, ptr %header.addr
  %ld562 = load ptr, ptr %fields.addr
  %cr563 = call ptr (ptr, ptr, ptr) %fv560(ptr %ld558, ptr %ld561, ptr %ld562)
  %ld564 = load ptr, ptr %handle.addr
  %ld565 = load ptr, ptr %header.addr
  %ld566 = load ptr, ptr %callback.addr
  %cr567 = call ptr @Csv.with_header_loop$V__5569$List_String$Fn_List_String_List_String_T_(ptr %ld564, ptr %ld565, ptr %ld566)
  store ptr %cr567, ptr %res_slot549
  br label %case_merge146
case_default147:
  unreachable
case_merge146:
  %case_r568 = load ptr, ptr %res_slot549
  ret ptr %case_r568
}

define ptr @$lam2011$apply$22(ptr %$clo.arg, ptr %row.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld569 = load ptr, ptr %row.addr
  %cr570 = call ptr @print_row$V__6177(ptr %ld569)
  ret ptr %cr570
}

define i64 @go$apply$25(ptr %$clo.arg, ptr %lst.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld571 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld571, ptr %go.addr
  %ld572 = load ptr, ptr %lst.addr
  %res_slot573 = alloca ptr
  %tgp574 = getelementptr i8, ptr %ld572, i64 8
  %tag575 = load i32, ptr %tgp574, align 4
  switch i32 %tag575, label %case_default153 [
      i32 0, label %case_br154
      i32 1, label %case_br155
  ]
case_br154:
  %ld576 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld576)
  %ld577 = load i64, ptr %acc.addr
  %cv578 = inttoptr i64 %ld577 to ptr
  store ptr %cv578, ptr %res_slot573
  br label %case_merge152
case_br155:
  %fp579 = getelementptr i8, ptr %ld572, i64 16
  %fv580 = load ptr, ptr %fp579, align 8
  %$f124.addr = alloca ptr
  store ptr %fv580, ptr %$f124.addr
  %fp581 = getelementptr i8, ptr %ld572, i64 24
  %fv582 = load ptr, ptr %fp581, align 8
  %$f125.addr = alloca ptr
  store ptr %fv582, ptr %$f125.addr
  %freed583 = call i64 @march_decrc_freed(ptr %ld572)
  %freed_b584 = icmp ne i64 %freed583, 0
  br i1 %freed_b584, label %br_unique156, label %br_shared157
br_shared157:
  call void @march_incrc(ptr %fv582)
  call void @march_incrc(ptr %fv580)
  br label %br_body158
br_unique156:
  br label %br_body158
br_body158:
  %ld585 = load ptr, ptr %$f125.addr
  %t.addr = alloca ptr
  store ptr %ld585, ptr %t.addr
  %ld586 = load i64, ptr %acc.addr
  %ar587 = add i64 %ld586, 1
  %$t123.addr = alloca i64
  store i64 %ar587, ptr %$t123.addr
  %ld588 = load ptr, ptr %go.addr
  %fp589 = getelementptr i8, ptr %ld588, i64 16
  %fv590 = load ptr, ptr %fp589, align 8
  %ld591 = load ptr, ptr %t.addr
  %ld592 = load i64, ptr %$t123.addr
  %cr593 = call i64 (ptr, ptr, i64) %fv590(ptr %ld588, ptr %ld591, i64 %ld592)
  %cv594 = inttoptr i64 %cr593 to ptr
  store ptr %cv594, ptr %res_slot573
  br label %case_merge152
case_default153:
  unreachable
case_merge152:
  %case_r595 = load ptr, ptr %res_slot573
  %cv596 = ptrtoint ptr %case_r595 to i64
  ret i64 %cv596
}

define ptr @$lam2059$apply$26(ptr %$clo.arg, ptr %row.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld597 = load ptr, ptr %row.addr
  %cr598 = call ptr @march_value_to_string(ptr %ld597)
  %$t2060.addr = alloca ptr
  store ptr %cr598, ptr %$t2060.addr
  %ld599 = load ptr, ptr %$t2060.addr
  call void @march_println(ptr %ld599)
  %cv600 = inttoptr i64 0 to ptr
  ret ptr %cv600
}

define ptr @$lam2056$apply$27(ptr %$clo.arg, ptr %header.arg, ptr %row.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %header.addr = alloca ptr
  store ptr %header.arg, ptr %header.addr
  %row.addr = alloca ptr
  store ptr %row.arg, ptr %row.addr
  %ld601 = load ptr, ptr %header.addr
  %ld602 = load ptr, ptr %row.addr
  %cr603 = call ptr @print_name_city(ptr %ld601, ptr %ld602)
  ret ptr %cr603
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
