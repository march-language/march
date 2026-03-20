; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_println(ptr %s)
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr  @march_float_to_string(double %f)
declare ptr  @march_bool_to_string(i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_join(ptr %list, ptr %sep)
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)


define ptr @insert(i64 %v.arg, ptr %sorted.arg) {
entry:
  %v.addr = alloca i64
  store i64 %v.arg, ptr %v.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %ld1 = load ptr, ptr %sorted.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld5 = load ptr, ptr %sorted.addr
  %rc6 = load i64, ptr %ld5, align 8
  %uniq7 = icmp eq i64 %rc6, 1
  %fbip_slot8 = alloca ptr
  br i1 %uniq7, label %fbip_reuse5, label %fbip_fresh6
fbip_reuse5:
  %tgp9 = getelementptr i8, ptr %ld5, i64 8
  store i32 0, ptr %tgp9, align 4
  store ptr %ld5, ptr %fbip_slot8
  br label %fbip_merge7
fbip_fresh6:
  call void @march_decrc(ptr %ld5)
  %hp10 = call ptr @march_alloc(i64 16)
  %tgp11 = getelementptr i8, ptr %hp10, i64 8
  store i32 0, ptr %tgp11, align 4
  store ptr %hp10, ptr %fbip_slot8
  br label %fbip_merge7
fbip_merge7:
  %fbip_r12 = load ptr, ptr %fbip_slot8
  %$t974.addr = alloca ptr
  store ptr %fbip_r12, ptr %$t974.addr
  %hp13 = call ptr @march_alloc(i64 32)
  %tgp14 = getelementptr i8, ptr %hp13, i64 8
  store i32 1, ptr %tgp14, align 4
  %ld15 = load i64, ptr %v.addr
  %cv16 = inttoptr i64 %ld15 to ptr
  %fp17 = getelementptr i8, ptr %hp13, i64 16
  store ptr %cv16, ptr %fp17, align 8
  %ld18 = load ptr, ptr %$t974.addr
  %fp19 = getelementptr i8, ptr %hp13, i64 24
  store ptr %ld18, ptr %fp19, align 8
  store ptr %hp13, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp20 = getelementptr i8, ptr %ld1, i64 16
  %fv21 = load ptr, ptr %fp20, align 8
  %$f977.addr = alloca ptr
  store ptr %fv21, ptr %$f977.addr
  %fp22 = getelementptr i8, ptr %ld1, i64 24
  %fv23 = load ptr, ptr %fp22, align 8
  %$f978.addr = alloca ptr
  store ptr %fv23, ptr %$f978.addr
  %ld24 = load ptr, ptr %$f978.addr
  %t.addr = alloca ptr
  store ptr %ld24, ptr %t.addr
  %ld25 = load ptr, ptr %$f977.addr
  %h.addr = alloca ptr
  store ptr %ld25, ptr %h.addr
  %ld26 = load i64, ptr %v.addr
  %ld27 = load i64, ptr %h.addr
  %cmp28 = icmp sle i64 %ld26, %ld27
  %ar29 = zext i1 %cmp28 to i64
  %$t975.addr = alloca i64
  store i64 %ar29, ptr %$t975.addr
  %ld30 = load i64, ptr %$t975.addr
  %res_slot31 = alloca ptr
  switch i64 %ld30, label %case_default9 [
      i64 1, label %case_br10
  ]
case_br10:
  %hp32 = call ptr @march_alloc(i64 32)
  %tgp33 = getelementptr i8, ptr %hp32, i64 8
  store i32 1, ptr %tgp33, align 4
  %ld34 = load i64, ptr %v.addr
  %cv35 = inttoptr i64 %ld34 to ptr
  %fp36 = getelementptr i8, ptr %hp32, i64 16
  store ptr %cv35, ptr %fp36, align 8
  %ld37 = load ptr, ptr %sorted.addr
  %fp38 = getelementptr i8, ptr %hp32, i64 24
  store ptr %ld37, ptr %fp38, align 8
  store ptr %hp32, ptr %res_slot31
  br label %case_merge8
case_default9:
  %ld39 = load i64, ptr %v.addr
  %ld40 = load ptr, ptr %t.addr
  %cr41 = call ptr @insert(i64 %ld39, ptr %ld40)
  %$t976.addr = alloca ptr
  store ptr %cr41, ptr %$t976.addr
  %hp42 = call ptr @march_alloc(i64 32)
  %tgp43 = getelementptr i8, ptr %hp42, i64 8
  store i32 1, ptr %tgp43, align 4
  %ld44 = load i64, ptr %h.addr
  %cv45 = inttoptr i64 %ld44 to ptr
  %fp46 = getelementptr i8, ptr %hp42, i64 16
  store ptr %cv45, ptr %fp46, align 8
  %ld47 = load ptr, ptr %$t976.addr
  %fp48 = getelementptr i8, ptr %hp42, i64 24
  store ptr %ld47, ptr %fp48, align 8
  store ptr %hp42, ptr %res_slot31
  br label %case_merge8
case_merge8:
  %case_r49 = load ptr, ptr %res_slot31
  store ptr %case_r49, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r50 = load ptr, ptr %res_slot2
  ret ptr %case_r50
}

define ptr @insertion_sort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp51 = call ptr @march_alloc(i64 24)
  %tgp52 = getelementptr i8, ptr %hp51, i64 8
  store i32 0, ptr %tgp52, align 4
  %fp53 = getelementptr i8, ptr %hp51, i64 16
  store ptr @go$apply$19, ptr %fp53, align 8
  %go.addr = alloca ptr
  store ptr %hp51, ptr %go.addr
  %hp54 = call ptr @march_alloc(i64 16)
  %tgp55 = getelementptr i8, ptr %hp54, i64 8
  store i32 0, ptr %tgp55, align 4
  %$t982.addr = alloca ptr
  store ptr %hp54, ptr %$t982.addr
  %ld56 = load ptr, ptr %go.addr
  %fp57 = getelementptr i8, ptr %ld56, i64 16
  %fv58 = load ptr, ptr %fp57, align 8
  %ld59 = load ptr, ptr %xs.addr
  %ld60 = load ptr, ptr %$t982.addr
  %cr61 = call ptr (ptr, ptr, ptr) %fv58(ptr %ld56, ptr %ld59, ptr %ld60)
  ret ptr %cr61
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld62 = load i64, ptr %n.addr
  %cmp63 = icmp eq i64 %ld62, 0
  %ar64 = zext i1 %cmp63 to i64
  %$t983.addr = alloca i64
  store i64 %ar64, ptr %$t983.addr
  %ld65 = load i64, ptr %$t983.addr
  %res_slot66 = alloca ptr
  switch i64 %ld65, label %case_default12 [
      i64 1, label %case_br13
  ]
case_br13:
  %ld67 = load ptr, ptr %acc.addr
  store ptr %ld67, ptr %res_slot66
  br label %case_merge11
case_default12:
  %ld68 = load i64, ptr %seed.addr
  %ar69 = mul i64 %ld68, 1664525
  %$t984.addr = alloca i64
  store i64 %ar69, ptr %$t984.addr
  %ld70 = load i64, ptr %$t984.addr
  %ar71 = add i64 %ld70, 1013904223
  %$t985.addr = alloca i64
  store i64 %ar71, ptr %$t985.addr
  %ld72 = load i64, ptr %$t985.addr
  %ar73 = srem i64 %ld72, 1000000
  %next.addr = alloca i64
  store i64 %ar73, ptr %next.addr
  %ld74 = load i64, ptr %n.addr
  %ar75 = sub i64 %ld74, 1
  %$t986.addr = alloca i64
  store i64 %ar75, ptr %$t986.addr
  %ld76 = load i64, ptr %next.addr
  %ar77 = srem i64 %ld76, 100000
  %$t987.addr = alloca i64
  store i64 %ar77, ptr %$t987.addr
  %hp78 = call ptr @march_alloc(i64 32)
  %tgp79 = getelementptr i8, ptr %hp78, i64 8
  store i32 1, ptr %tgp79, align 4
  %ld80 = load i64, ptr %$t987.addr
  %cv81 = inttoptr i64 %ld80 to ptr
  %fp82 = getelementptr i8, ptr %hp78, i64 16
  store ptr %cv81, ptr %fp82, align 8
  %ld83 = load ptr, ptr %acc.addr
  %fp84 = getelementptr i8, ptr %hp78, i64 24
  store ptr %ld83, ptr %fp84, align 8
  %$t988.addr = alloca ptr
  store ptr %hp78, ptr %$t988.addr
  %ld85 = load i64, ptr %$t986.addr
  %ld86 = load i64, ptr %next.addr
  %ld87 = load ptr, ptr %$t988.addr
  %cr88 = call ptr @gen_list(i64 %ld85, i64 %ld86, ptr %ld87)
  store ptr %cr88, ptr %res_slot66
  br label %case_merge11
case_merge11:
  %case_r89 = load ptr, ptr %res_slot66
  ret ptr %case_r89
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld90 = load ptr, ptr %xs.addr
  %res_slot91 = alloca ptr
  %tgp92 = getelementptr i8, ptr %ld90, i64 8
  %tag93 = load i32, ptr %tgp92, align 4
  switch i32 %tag93, label %case_default15 [
      i32 0, label %case_br16
      i32 1, label %case_br17
  ]
case_br16:
  %ld94 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld94)
  %cv95 = inttoptr i64 0 to ptr
  store ptr %cv95, ptr %res_slot91
  br label %case_merge14
case_br17:
  %fp96 = getelementptr i8, ptr %ld90, i64 16
  %fv97 = load ptr, ptr %fp96, align 8
  %$f989.addr = alloca ptr
  store ptr %fv97, ptr %$f989.addr
  %fp98 = getelementptr i8, ptr %ld90, i64 24
  %fv99 = load ptr, ptr %fp98, align 8
  %$f990.addr = alloca ptr
  store ptr %fv99, ptr %$f990.addr
  %freed100 = call i64 @march_decrc_freed(ptr %ld90)
  %freed_b101 = icmp ne i64 %freed100, 0
  br i1 %freed_b101, label %br_unique18, label %br_shared19
br_shared19:
  call void @march_incrc(ptr %fv99)
  br label %br_body20
br_unique18:
  br label %br_body20
br_body20:
  %ld102 = load ptr, ptr %$f989.addr
  %h.addr = alloca ptr
  store ptr %ld102, ptr %h.addr
  %ld103 = load i64, ptr %h.addr
  %cv104 = inttoptr i64 %ld103 to ptr
  store ptr %cv104, ptr %res_slot91
  br label %case_merge14
case_default15:
  unreachable
case_merge14:
  %case_r105 = load ptr, ptr %res_slot91
  %cv106 = ptrtoint ptr %case_r105 to i64
  ret i64 %cv106
}

define void @march_main() {
entry:
  %hp107 = call ptr @march_alloc(i64 16)
  %tgp108 = getelementptr i8, ptr %hp107, i64 8
  store i32 0, ptr %tgp108, align 4
  %$t991.addr = alloca ptr
  store ptr %hp107, ptr %$t991.addr
  %ld109 = load ptr, ptr %$t991.addr
  %cr110 = call ptr @gen_list(i64 2000, i64 42, ptr %ld109)
  %xs.addr = alloca ptr
  store ptr %cr110, ptr %xs.addr
  %ld111 = load ptr, ptr %xs.addr
  %cr112 = call ptr @insertion_sort(ptr %ld111)
  %sorted.addr = alloca ptr
  store ptr %cr112, ptr %sorted.addr
  %ld113 = load ptr, ptr %sorted.addr
  %cr114 = call i64 @head(ptr %ld113)
  %$t992.addr = alloca i64
  store i64 %cr114, ptr %$t992.addr
  %ld115 = load i64, ptr %$t992.addr
  %cr116 = call ptr @march_int_to_string(i64 %ld115)
  %$t993.addr = alloca ptr
  store ptr %cr116, ptr %$t993.addr
  %ld117 = load ptr, ptr %$t993.addr
  call void @march_println(ptr %ld117)
  ret void
}

define ptr @go$apply$19(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld118 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld118, ptr %go.addr
  %ld119 = load ptr, ptr %lst.addr
  %res_slot120 = alloca ptr
  %tgp121 = getelementptr i8, ptr %ld119, i64 8
  %tag122 = load i32, ptr %tgp121, align 4
  switch i32 %tag122, label %case_default22 [
      i32 0, label %case_br23
      i32 1, label %case_br24
  ]
case_br23:
  %ld123 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld123)
  %ld124 = load ptr, ptr %acc.addr
  store ptr %ld124, ptr %res_slot120
  br label %case_merge21
case_br24:
  %fp125 = getelementptr i8, ptr %ld119, i64 16
  %fv126 = load ptr, ptr %fp125, align 8
  %$f980.addr = alloca ptr
  store ptr %fv126, ptr %$f980.addr
  %fp127 = getelementptr i8, ptr %ld119, i64 24
  %fv128 = load ptr, ptr %fp127, align 8
  %$f981.addr = alloca ptr
  store ptr %fv128, ptr %$f981.addr
  %freed129 = call i64 @march_decrc_freed(ptr %ld119)
  %freed_b130 = icmp ne i64 %freed129, 0
  br i1 %freed_b130, label %br_unique25, label %br_shared26
br_shared26:
  call void @march_incrc(ptr %fv128)
  br label %br_body27
br_unique25:
  br label %br_body27
br_body27:
  %ld131 = load ptr, ptr %$f981.addr
  %t.addr = alloca ptr
  store ptr %ld131, ptr %t.addr
  %ld132 = load ptr, ptr %$f980.addr
  %h.addr = alloca ptr
  store ptr %ld132, ptr %h.addr
  %ld133 = load i64, ptr %h.addr
  %ld134 = load ptr, ptr %acc.addr
  %cr135 = call ptr @insert(i64 %ld133, ptr %ld134)
  %$t979.addr = alloca ptr
  store ptr %cr135, ptr %$t979.addr
  %ld136 = load ptr, ptr %go.addr
  %fp137 = getelementptr i8, ptr %ld136, i64 16
  %fv138 = load ptr, ptr %fp137, align 8
  %ld139 = load ptr, ptr %t.addr
  %ld140 = load ptr, ptr %$t979.addr
  %cr141 = call ptr (ptr, ptr, ptr) %fv138(ptr %ld136, ptr %ld139, ptr %ld140)
  store ptr %cr141, ptr %res_slot120
  br label %case_merge21
case_default22:
  unreachable
case_merge21:
  %case_r142 = load ptr, ptr %res_slot120
  ret ptr %case_r142
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
