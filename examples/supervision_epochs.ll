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

@.str1 = private unnamed_addr constant [46 x i8] c"=== Epoch-Based Capability Demo (Phase 3) ===\00"
@.str2 = private unnamed_addr constant [1 x i8] c"\00"
@.str3 = private unnamed_addr constant [42 x i8] c"ServiceSupervisor spawned, service pid = \00"
@.str4 = private unnamed_addr constant [16 x i8] c"service alive: \00"
@.str5 = private unnamed_addr constant [1 x i8] c"\00"
@.str6 = private unnamed_addr constant [29 x i8] c"--- Acquiring capability ---\00"
@.str7 = private unnamed_addr constant [51 x i8] c"ERROR: could not get cap \E2\80\94 service already dead?\00"
@.str8 = private unnamed_addr constant [15 x i8] c"cap acquired: \00"
@.str9 = private unnamed_addr constant [1 x i8] c"\00"
@.str10 = private unnamed_addr constant [49 x i8] c"--- send_checked with fresh cap (expect :ok) ---\00"
@.str11 = private unnamed_addr constant [22 x i8] c"send_checked result: \00"
@.str12 = private unnamed_addr constant [1 x i8] c"\00"
@.str13 = private unnamed_addr constant [67 x i8] c"--- Crashing the service (supervisor restarts it with new pid) ---\00"
@.str14 = private unnamed_addr constant [20 x i8] c"old service alive: \00"
@.str15 = private unnamed_addr constant [20 x i8] c"new service pid:   \00"
@.str16 = private unnamed_addr constant [20 x i8] c"new service alive: \00"
@.str17 = private unnamed_addr constant [1 x i8] c"\00"
@.str18 = private unnamed_addr constant [65 x i8] c"--- send_checked with OLD cap (expect :error \E2\80\94 dead actor) ---\00"
@.str19 = private unnamed_addr constant [30 x i8] c"send_checked old cap result: \00"
@.str20 = private unnamed_addr constant [1 x i8] c"\00"
@.str21 = private unnamed_addr constant [53 x i8] c"--- Acquiring fresh cap for new service instance ---\00"
@.str22 = private unnamed_addr constant [31 x i8] c"ERROR: could not get fresh cap\00"
@.str23 = private unnamed_addr constant [19 x i8] c"new cap acquired: \00"
@.str24 = private unnamed_addr constant [30 x i8] c"send_checked new cap result: \00"
@.str25 = private unnamed_addr constant [1 x i8] c"\00"
@.str26 = private unnamed_addr constant [63 x i8] c"New instance starts fresh (value = 42, reset to initial state)\00"
@.str27 = private unnamed_addr constant [1 x i8] c"\00"
@.str28 = private unnamed_addr constant [13 x i8] c"=== Done ===\00"
@.str29 = private unnamed_addr constant [8 x i8] c"service\00"
@.str30 = private unnamed_addr constant [8 x i8] c"service\00"

define void @ServiceSupervisor_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld1 = load ptr, ptr %$msg.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      
  ]
case_default2:
  unreachable
case_merge1:
  %case_r5 = load ptr, ptr %res_slot2
  ret void
}

define ptr @march_main() {
entry:
  %sl6 = call ptr @march_string_lit(ptr @.str1, i64 45)
  call void @march_println(ptr %sl6)
  %sl7 = call ptr @march_string_lit(ptr @.str2, i64 0)
  call void @march_println(ptr %sl7)
  %hp8 = call ptr @march_alloc(i64 24)
  %tgp9 = getelementptr i8, ptr %hp8, i64 8
  store i32 0, ptr %tgp9, align 4
  %fp10 = getelementptr i8, ptr %hp8, i64 16
  store i64 0, ptr %fp10, align 8
  %$init_state_i23.addr = alloca ptr
  store ptr %hp8, ptr %$init_state_i23.addr
  %ld11 = load ptr, ptr %$init_state_i23.addr
  %fp12 = getelementptr i8, ptr %ld11, i64 16
  %fv13 = load i64, ptr %fp12, align 8
  %$init_service_i24.addr = alloca i64
  store i64 %fv13, ptr %$init_service_i24.addr
  %hp14 = call ptr @march_alloc(i64 40)
  %tgp15 = getelementptr i8, ptr %hp14, i64 8
  store i32 0, ptr %tgp15, align 4
  %cwrap16 = call ptr @march_alloc(i64 24)
  %cwt17 = getelementptr i8, ptr %cwrap16, i64 8
  store i32 0, ptr %cwt17, align 4
  %cwf18 = getelementptr i8, ptr %cwrap16, i64 16
  store ptr @ServiceSupervisor_dispatch$clo_wrap, ptr %cwf18, align 8
  %fp19 = getelementptr i8, ptr %hp14, i64 16
  store ptr %cwrap16, ptr %fp19, align 8
  %fp20 = getelementptr i8, ptr %hp14, i64 24
  store i64 1, ptr %fp20, align 8
  %ld21 = load i64, ptr %$init_service_i24.addr
  %fp22 = getelementptr i8, ptr %hp14, i64 32
  store i64 %ld21, ptr %fp22, align 8
  %$spawned_i25.addr = alloca ptr
  store ptr %hp14, ptr %$spawned_i25.addr
  %ld23 = load ptr, ptr %$spawned_i25.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld23, ptr %$raw_actor.addr
  %ld24 = load ptr, ptr %$raw_actor.addr
  %cr25 = call ptr @march_spawn(ptr %ld24)
  %sup.addr = alloca ptr
  store ptr %cr25, ptr %sup.addr
  %ld26 = load ptr, ptr %sup.addr
  call void @march_incrc(ptr %ld26)
  %ld27 = load ptr, ptr %sup.addr
  %cr28 = call ptr @get_service_pid$Pid_V__6041(ptr %ld27)
  %svc.addr = alloca ptr
  store ptr %cr28, ptr %svc.addr
  %ld29 = load ptr, ptr %svc.addr
  call void @march_incrc(ptr %ld29)
  %ld30 = load ptr, ptr %svc.addr
  %cr31 = call ptr @march_value_to_string(ptr %ld30)
  %$t2018.addr = alloca ptr
  store ptr %cr31, ptr %$t2018.addr
  %sl32 = call ptr @march_string_lit(ptr @.str3, i64 41)
  %ld33 = load ptr, ptr %$t2018.addr
  %cr34 = call ptr @march_string_concat(ptr %sl32, ptr %ld33)
  %$t2019.addr = alloca ptr
  store ptr %cr34, ptr %$t2019.addr
  %ld35 = load ptr, ptr %$t2019.addr
  call void @march_println(ptr %ld35)
  %ld36 = load ptr, ptr %svc.addr
  call void @march_incrc(ptr %ld36)
  %ld37 = load ptr, ptr %svc.addr
  %cr38 = call i64 @march_is_alive(ptr %ld37)
  %$t2020.addr = alloca i64
  store i64 %cr38, ptr %$t2020.addr
  %ld39 = load i64, ptr %$t2020.addr
  %cr40 = call ptr @march_bool_to_string(i64 %ld39)
  %$t2021.addr = alloca ptr
  store ptr %cr40, ptr %$t2021.addr
  %sl41 = call ptr @march_string_lit(ptr @.str4, i64 15)
  %ld42 = load ptr, ptr %$t2021.addr
  %cr43 = call ptr @march_string_concat(ptr %sl41, ptr %ld42)
  %$t2022.addr = alloca ptr
  store ptr %cr43, ptr %$t2022.addr
  %ld44 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld44)
  %sl45 = call ptr @march_string_lit(ptr @.str5, i64 0)
  call void @march_println(ptr %sl45)
  %ld46 = load ptr, ptr %svc.addr
  call void @march_incrc(ptr %ld46)
  %ld47 = load ptr, ptr %svc.addr
  %cr48 = call ptr @march_get_cap(ptr %ld47)
  %cap_result.addr = alloca ptr
  store ptr %cr48, ptr %cap_result.addr
  %sl49 = call ptr @march_string_lit(ptr @.str6, i64 28)
  call void @march_println(ptr %sl49)
  %ld50 = load ptr, ptr %cap_result.addr
  %res_slot51 = alloca ptr
  %tgp52 = getelementptr i8, ptr %ld50, i64 8
  %tag53 = load i32, ptr %tgp52, align 4
  switch i32 %tag53, label %case_default4 [
      i32 0, label %case_br5
      i32 1, label %case_br6
  ]
case_br5:
  %ld54 = load ptr, ptr %cap_result.addr
  call void @march_decrc(ptr %ld54)
  %sl55 = call ptr @march_string_lit(ptr @.str7, i64 50)
  call void @march_println(ptr %sl55)
  %cv56 = inttoptr i64 0 to ptr
  store ptr %cv56, ptr %res_slot51
  br label %case_merge3
case_br6:
  %fp57 = getelementptr i8, ptr %ld50, i64 16
  %fv58 = load ptr, ptr %fp57, align 8
  %$f2045.addr = alloca ptr
  store ptr %fv58, ptr %$f2045.addr
  %freed59 = call i64 @march_decrc_freed(ptr %ld50)
  %freed_b60 = icmp ne i64 %freed59, 0
  br i1 %freed_b60, label %br_unique7, label %br_shared8
br_shared8:
  call void @march_incrc(ptr %fv58)
  br label %br_body9
br_unique7:
  br label %br_body9
br_body9:
  %ld61 = load ptr, ptr %$f2045.addr
  %cap.addr = alloca ptr
  store ptr %ld61, ptr %cap.addr
  %ld62 = load ptr, ptr %cap.addr
  call void @march_incrc(ptr %ld62)
  %ld63 = load ptr, ptr %cap.addr
  %cr64 = call ptr @march_value_to_string(ptr %ld63)
  %$t2023.addr = alloca ptr
  store ptr %cr64, ptr %$t2023.addr
  %sl65 = call ptr @march_string_lit(ptr @.str8, i64 14)
  %ld66 = load ptr, ptr %$t2023.addr
  %cr67 = call ptr @march_string_concat(ptr %sl65, ptr %ld66)
  %$t2024.addr = alloca ptr
  store ptr %cr67, ptr %$t2024.addr
  %ld68 = load ptr, ptr %$t2024.addr
  call void @march_println(ptr %ld68)
  %sl69 = call ptr @march_string_lit(ptr @.str9, i64 0)
  call void @march_println(ptr %sl69)
  %sl70 = call ptr @march_string_lit(ptr @.str10, i64 48)
  call void @march_println(ptr %sl70)
  %hp71 = call ptr @march_alloc(i64 16)
  %tgp72 = getelementptr i8, ptr %hp71, i64 8
  store i32 0, ptr %tgp72, align 4
  %$t2025.addr = alloca ptr
  store ptr %hp71, ptr %$t2025.addr
  %ld73 = load ptr, ptr %cap.addr
  call void @march_incrc(ptr %ld73)
  %ld74 = load ptr, ptr %cap.addr
  %ld75 = load ptr, ptr %$t2025.addr
  call void @march_send_checked(ptr %ld74, ptr %ld75)
  %cv76 = inttoptr i64 0 to ptr
  %r1.addr = alloca ptr
  store ptr %cv76, ptr %r1.addr
  call void @march_run_until_idle()
  %ld77 = load ptr, ptr %r1.addr
  %cr78 = call ptr @march_value_to_string(ptr %ld77)
  %$t2026.addr = alloca ptr
  store ptr %cr78, ptr %$t2026.addr
  %sl79 = call ptr @march_string_lit(ptr @.str11, i64 21)
  %ld80 = load ptr, ptr %$t2026.addr
  %cr81 = call ptr @march_string_concat(ptr %sl79, ptr %ld80)
  %$t2027.addr = alloca ptr
  store ptr %cr81, ptr %$t2027.addr
  %ld82 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld82)
  %sl83 = call ptr @march_string_lit(ptr @.str12, i64 0)
  call void @march_println(ptr %sl83)
  %sl84 = call ptr @march_string_lit(ptr @.str13, i64 66)
  call void @march_println(ptr %sl84)
  %ld85 = load ptr, ptr %svc.addr
  call void @march_incrc(ptr %ld85)
  %ld86 = load ptr, ptr %svc.addr
  call void @march_kill(ptr %ld86)
  %ld87 = load ptr, ptr %svc.addr
  %cr88 = call i64 @march_is_alive(ptr %ld87)
  %$t2028.addr = alloca i64
  store i64 %cr88, ptr %$t2028.addr
  %ld89 = load i64, ptr %$t2028.addr
  %cr90 = call ptr @march_bool_to_string(i64 %ld89)
  %$t2029.addr = alloca ptr
  store ptr %cr90, ptr %$t2029.addr
  %sl91 = call ptr @march_string_lit(ptr @.str14, i64 19)
  %ld92 = load ptr, ptr %$t2029.addr
  %cr93 = call ptr @march_string_concat(ptr %sl91, ptr %ld92)
  %$t2030.addr = alloca ptr
  store ptr %cr93, ptr %$t2030.addr
  %ld94 = load ptr, ptr %$t2030.addr
  call void @march_println(ptr %ld94)
  %ld95 = load ptr, ptr %sup.addr
  %cr96 = call ptr @get_service_pid$Pid_V__6065(ptr %ld95)
  %svc2.addr = alloca ptr
  store ptr %cr96, ptr %svc2.addr
  %ld97 = load ptr, ptr %svc2.addr
  call void @march_incrc(ptr %ld97)
  %ld98 = load ptr, ptr %svc2.addr
  %cr99 = call ptr @march_value_to_string(ptr %ld98)
  %$t2031.addr = alloca ptr
  store ptr %cr99, ptr %$t2031.addr
  %sl100 = call ptr @march_string_lit(ptr @.str15, i64 19)
  %ld101 = load ptr, ptr %$t2031.addr
  %cr102 = call ptr @march_string_concat(ptr %sl100, ptr %ld101)
  %$t2032.addr = alloca ptr
  store ptr %cr102, ptr %$t2032.addr
  %ld103 = load ptr, ptr %$t2032.addr
  call void @march_println(ptr %ld103)
  %ld104 = load ptr, ptr %svc2.addr
  call void @march_incrc(ptr %ld104)
  %ld105 = load ptr, ptr %svc2.addr
  %cr106 = call i64 @march_is_alive(ptr %ld105)
  %$t2033.addr = alloca i64
  store i64 %cr106, ptr %$t2033.addr
  %ld107 = load i64, ptr %$t2033.addr
  %cr108 = call ptr @march_bool_to_string(i64 %ld107)
  %$t2034.addr = alloca ptr
  store ptr %cr108, ptr %$t2034.addr
  %sl109 = call ptr @march_string_lit(ptr @.str16, i64 19)
  %ld110 = load ptr, ptr %$t2034.addr
  %cr111 = call ptr @march_string_concat(ptr %sl109, ptr %ld110)
  %$t2035.addr = alloca ptr
  store ptr %cr111, ptr %$t2035.addr
  %ld112 = load ptr, ptr %$t2035.addr
  call void @march_println(ptr %ld112)
  %sl113 = call ptr @march_string_lit(ptr @.str17, i64 0)
  call void @march_println(ptr %sl113)
  %sl114 = call ptr @march_string_lit(ptr @.str18, i64 64)
  call void @march_println(ptr %sl114)
  %hp115 = call ptr @march_alloc(i64 16)
  %tgp116 = getelementptr i8, ptr %hp115, i64 8
  store i32 0, ptr %tgp116, align 4
  %$t2036.addr = alloca ptr
  store ptr %hp115, ptr %$t2036.addr
  %ld117 = load ptr, ptr %cap.addr
  %ld118 = load ptr, ptr %$t2036.addr
  call void @march_send_checked(ptr %ld117, ptr %ld118)
  %cv119 = inttoptr i64 0 to ptr
  %r2.addr = alloca ptr
  store ptr %cv119, ptr %r2.addr
  %ld120 = load ptr, ptr %r2.addr
  %cr121 = call ptr @march_value_to_string(ptr %ld120)
  %$t2037.addr = alloca ptr
  store ptr %cr121, ptr %$t2037.addr
  %sl122 = call ptr @march_string_lit(ptr @.str19, i64 29)
  %ld123 = load ptr, ptr %$t2037.addr
  %cr124 = call ptr @march_string_concat(ptr %sl122, ptr %ld123)
  %$t2038.addr = alloca ptr
  store ptr %cr124, ptr %$t2038.addr
  %ld125 = load ptr, ptr %$t2038.addr
  call void @march_println(ptr %ld125)
  %sl126 = call ptr @march_string_lit(ptr @.str20, i64 0)
  call void @march_println(ptr %sl126)
  %sl127 = call ptr @march_string_lit(ptr @.str21, i64 52)
  call void @march_println(ptr %sl127)
  %ld128 = load ptr, ptr %svc2.addr
  %cr129 = call ptr @march_get_cap(ptr %ld128)
  %cap2_result.addr = alloca ptr
  store ptr %cr129, ptr %cap2_result.addr
  %ld130 = load ptr, ptr %cap2_result.addr
  %res_slot131 = alloca ptr
  %tgp132 = getelementptr i8, ptr %ld130, i64 8
  %tag133 = load i32, ptr %tgp132, align 4
  switch i32 %tag133, label %case_default11 [
      i32 0, label %case_br12
      i32 1, label %case_br13
  ]
case_br12:
  %ld134 = load ptr, ptr %cap2_result.addr
  call void @march_decrc(ptr %ld134)
  %sl135 = call ptr @march_string_lit(ptr @.str22, i64 30)
  call void @march_println(ptr %sl135)
  %cv136 = inttoptr i64 0 to ptr
  store ptr %cv136, ptr %res_slot131
  br label %case_merge10
case_br13:
  %fp137 = getelementptr i8, ptr %ld130, i64 16
  %fv138 = load ptr, ptr %fp137, align 8
  %$f2044.addr = alloca ptr
  store ptr %fv138, ptr %$f2044.addr
  %freed139 = call i64 @march_decrc_freed(ptr %ld130)
  %freed_b140 = icmp ne i64 %freed139, 0
  br i1 %freed_b140, label %br_unique14, label %br_shared15
br_shared15:
  call void @march_incrc(ptr %fv138)
  br label %br_body16
br_unique14:
  br label %br_body16
br_body16:
  %ld141 = load ptr, ptr %$f2044.addr
  %cap2.addr = alloca ptr
  store ptr %ld141, ptr %cap2.addr
  %ld142 = load ptr, ptr %cap2.addr
  call void @march_incrc(ptr %ld142)
  %ld143 = load ptr, ptr %cap2.addr
  %cr144 = call ptr @march_value_to_string(ptr %ld143)
  %$t2039.addr = alloca ptr
  store ptr %cr144, ptr %$t2039.addr
  %sl145 = call ptr @march_string_lit(ptr @.str23, i64 18)
  %ld146 = load ptr, ptr %$t2039.addr
  %cr147 = call ptr @march_string_concat(ptr %sl145, ptr %ld146)
  %$t2040.addr = alloca ptr
  store ptr %cr147, ptr %$t2040.addr
  %ld148 = load ptr, ptr %$t2040.addr
  call void @march_println(ptr %ld148)
  %hp149 = call ptr @march_alloc(i64 16)
  %tgp150 = getelementptr i8, ptr %hp149, i64 8
  store i32 0, ptr %tgp150, align 4
  %$t2041.addr = alloca ptr
  store ptr %hp149, ptr %$t2041.addr
  %ld151 = load ptr, ptr %cap2.addr
  %ld152 = load ptr, ptr %$t2041.addr
  call void @march_send_checked(ptr %ld151, ptr %ld152)
  %cv153 = inttoptr i64 0 to ptr
  %r3.addr = alloca ptr
  store ptr %cv153, ptr %r3.addr
  call void @march_run_until_idle()
  %ld154 = load ptr, ptr %r3.addr
  %cr155 = call ptr @march_value_to_string(ptr %ld154)
  %$t2042.addr = alloca ptr
  store ptr %cr155, ptr %$t2042.addr
  %sl156 = call ptr @march_string_lit(ptr @.str24, i64 29)
  %ld157 = load ptr, ptr %$t2042.addr
  %cr158 = call ptr @march_string_concat(ptr %sl156, ptr %ld157)
  %$t2043.addr = alloca ptr
  store ptr %cr158, ptr %$t2043.addr
  %ld159 = load ptr, ptr %$t2043.addr
  call void @march_println(ptr %ld159)
  %sl160 = call ptr @march_string_lit(ptr @.str25, i64 0)
  call void @march_println(ptr %sl160)
  %sl161 = call ptr @march_string_lit(ptr @.str26, i64 62)
  call void @march_println(ptr %sl161)
  %cv162 = inttoptr i64 0 to ptr
  store ptr %cv162, ptr %res_slot131
  br label %case_merge10
case_default11:
  unreachable
case_merge10:
  %case_r163 = load ptr, ptr %res_slot131
  store ptr %case_r163, ptr %res_slot51
  br label %case_merge3
case_default4:
  unreachable
case_merge3:
  %case_r164 = load ptr, ptr %res_slot51
  %sl165 = call ptr @march_string_lit(ptr @.str27, i64 0)
  call void @march_println(ptr %sl165)
  %sl166 = call ptr @march_string_lit(ptr @.str28, i64 12)
  call void @march_println(ptr %sl166)
  %cv167 = inttoptr i64 0 to ptr
  ret ptr %cv167
}

define ptr @get_service_pid$Pid_V__6065(ptr %sup.arg) {
entry:
  %sup.addr = alloca ptr
  store ptr %sup.arg, ptr %sup.addr
  %ld168 = load ptr, ptr %sup.addr
  %sl169 = call ptr @march_string_lit(ptr @.str29, i64 7)
  %cr170 = call ptr @march_get_actor_field(ptr %ld168, ptr %sl169)
  %$t2015.addr = alloca ptr
  store ptr %cr170, ptr %$t2015.addr
  %ld171 = load ptr, ptr %$t2015.addr
  %res_slot172 = alloca ptr
  %tgp173 = getelementptr i8, ptr %ld171, i64 8
  %tag174 = load i32, ptr %tgp173, align 4
  switch i32 %tag174, label %case_default18 [
      i32 0, label %case_br19
      i32 1, label %case_br20
  ]
case_br19:
  %ld175 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld175)
  %ar176 = sub i64 0, 1
  %$t2016.addr = alloca i64
  store i64 %ar176, ptr %$t2016.addr
  %ld177 = load i64, ptr %$t2016.addr
  %cr178 = call ptr @march_pid_of_int(i64 %ld177)
  store ptr %cr178, ptr %res_slot172
  br label %case_merge17
case_br20:
  %fp179 = getelementptr i8, ptr %ld171, i64 16
  %fv180 = load ptr, ptr %fp179, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv180, ptr %$f2017.addr
  %ld181 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld181)
  %ld182 = load ptr, ptr %$f2017.addr
  %n.addr = alloca ptr
  store ptr %ld182, ptr %n.addr
  %ld183 = load ptr, ptr %n.addr
  %cr184 = call ptr @march_pid_of_int(ptr %ld183)
  store ptr %cr184, ptr %res_slot172
  br label %case_merge17
case_default18:
  unreachable
case_merge17:
  %case_r185 = load ptr, ptr %res_slot172
  ret ptr %case_r185
}

define ptr @get_service_pid$Pid_V__6041(ptr %sup.arg) {
entry:
  %sup.addr = alloca ptr
  store ptr %sup.arg, ptr %sup.addr
  %ld186 = load ptr, ptr %sup.addr
  %sl187 = call ptr @march_string_lit(ptr @.str30, i64 7)
  %cr188 = call ptr @march_get_actor_field(ptr %ld186, ptr %sl187)
  %$t2015.addr = alloca ptr
  store ptr %cr188, ptr %$t2015.addr
  %ld189 = load ptr, ptr %$t2015.addr
  %res_slot190 = alloca ptr
  %tgp191 = getelementptr i8, ptr %ld189, i64 8
  %tag192 = load i32, ptr %tgp191, align 4
  switch i32 %tag192, label %case_default22 [
      i32 0, label %case_br23
      i32 1, label %case_br24
  ]
case_br23:
  %ld193 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld193)
  %ar194 = sub i64 0, 1
  %$t2016.addr = alloca i64
  store i64 %ar194, ptr %$t2016.addr
  %ld195 = load i64, ptr %$t2016.addr
  %cr196 = call ptr @march_pid_of_int(i64 %ld195)
  store ptr %cr196, ptr %res_slot190
  br label %case_merge21
case_br24:
  %fp197 = getelementptr i8, ptr %ld189, i64 16
  %fv198 = load ptr, ptr %fp197, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv198, ptr %$f2017.addr
  %ld199 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld199)
  %ld200 = load ptr, ptr %$f2017.addr
  %n.addr = alloca ptr
  store ptr %ld200, ptr %n.addr
  %ld201 = load ptr, ptr %n.addr
  %cr202 = call ptr @march_pid_of_int(ptr %ld201)
  store ptr %cr202, ptr %res_slot190
  br label %case_merge21
case_default22:
  unreachable
case_merge21:
  %case_r203 = load ptr, ptr %res_slot190
  ret ptr %case_r203
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @ServiceSupervisor_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @ServiceSupervisor_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

