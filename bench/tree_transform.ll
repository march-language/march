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


define ptr @make(i64 %d.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %ld1 = load i64, ptr %d.addr
  %cmp2 = icmp eq i64 %ld1, 0
  %ar3 = zext i1 %cmp2 to i64
  %$t574.addr = alloca i64
  store i64 %ar3, ptr %$t574.addr
  %ld4 = load i64, ptr %$t574.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %hp6 = call ptr @march_alloc(i64 24)
  %tgp7 = getelementptr i8, ptr %hp6, i64 8
  store i32 0, ptr %tgp7, align 4
  %fp8 = getelementptr i8, ptr %hp6, i64 16
  store i64 0, ptr %fp8, align 8
  store ptr %hp6, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %d.addr
  %ar10 = sub i64 %ld9, 1
  %$t575.addr = alloca i64
  store i64 %ar10, ptr %$t575.addr
  %ld11 = load i64, ptr %$t575.addr
  %cr12 = call ptr @make(i64 %ld11)
  %$t576.addr = alloca ptr
  store ptr %cr12, ptr %$t576.addr
  %ld13 = load i64, ptr %d.addr
  %ar14 = sub i64 %ld13, 1
  %$t577.addr = alloca i64
  store i64 %ar14, ptr %$t577.addr
  %ld15 = load i64, ptr %$t577.addr
  %cr16 = call ptr @make(i64 %ld15)
  %$t578.addr = alloca ptr
  store ptr %cr16, ptr %$t578.addr
  %hp17 = call ptr @march_alloc(i64 32)
  %tgp18 = getelementptr i8, ptr %hp17, i64 8
  store i32 1, ptr %tgp18, align 4
  %ld19 = load ptr, ptr %$t576.addr
  %fp20 = getelementptr i8, ptr %hp17, i64 16
  store ptr %ld19, ptr %fp20, align 8
  %ld21 = load ptr, ptr %$t578.addr
  %fp22 = getelementptr i8, ptr %hp17, i64 24
  store ptr %ld21, ptr %fp22, align 8
  store ptr %hp17, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r23 = load ptr, ptr %res_slot5
  ret ptr %case_r23
}

define ptr @inc_leaves(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld24 = load ptr, ptr %t.addr
  %res_slot25 = alloca ptr
  %tgp26 = getelementptr i8, ptr %ld24, i64 8
  %tag27 = load i32, ptr %tgp26, align 4
  switch i32 %tag27, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %fp28 = getelementptr i8, ptr %ld24, i64 16
  %fv29 = load i64, ptr %fp28, align 8
  %n.addr = alloca i64
  store i64 %fv29, ptr %n.addr
  %ld30 = load i64, ptr %n.addr
  %ar31 = add i64 %ld30, 1
  %$t579.addr = alloca i64
  store i64 %ar31, ptr %$t579.addr
  %ld32 = load ptr, ptr %t.addr
  %ld33 = load i64, ptr %$t579.addr
  %rc34 = load i64, ptr %ld32, align 8
  %uniq35 = icmp eq i64 %rc34, 1
  %fbip_slot36 = alloca ptr
  br i1 %uniq35, label %fbip_reuse8, label %fbip_fresh9
fbip_reuse8:
  %tgp37 = getelementptr i8, ptr %ld32, i64 8
  store i32 0, ptr %tgp37, align 4
  %fp38 = getelementptr i8, ptr %ld32, i64 16
  store i64 %ld33, ptr %fp38, align 8
  store ptr %ld32, ptr %fbip_slot36
  br label %fbip_merge10
fbip_fresh9:
  call void @march_decrc(ptr %ld32)
  %hp39 = call ptr @march_alloc(i64 24)
  %tgp40 = getelementptr i8, ptr %hp39, i64 8
  store i32 0, ptr %tgp40, align 4
  %fp41 = getelementptr i8, ptr %hp39, i64 16
  store i64 %ld33, ptr %fp41, align 8
  store ptr %hp39, ptr %fbip_slot36
  br label %fbip_merge10
fbip_merge10:
  %fbip_r42 = load ptr, ptr %fbip_slot36
  store ptr %fbip_r42, ptr %res_slot25
  br label %case_merge4
case_br7:
  %fp43 = getelementptr i8, ptr %ld24, i64 16
  %fv44 = load ptr, ptr %fp43, align 8
  %l.addr = alloca ptr
  store ptr %fv44, ptr %l.addr
  %fp45 = getelementptr i8, ptr %ld24, i64 24
  %fv46 = load ptr, ptr %fp45, align 8
  %r.addr = alloca ptr
  store ptr %fv46, ptr %r.addr
  %ld47 = load ptr, ptr %l.addr
  %cr48 = call ptr @inc_leaves(ptr %ld47)
  %$t580.addr = alloca ptr
  store ptr %cr48, ptr %$t580.addr
  %ld49 = load ptr, ptr %r.addr
  %cr50 = call ptr @inc_leaves(ptr %ld49)
  %$t581.addr = alloca ptr
  store ptr %cr50, ptr %$t581.addr
  %ld51 = load ptr, ptr %t.addr
  %ld52 = load ptr, ptr %$t580.addr
  %ld53 = load ptr, ptr %$t581.addr
  %rc54 = load i64, ptr %ld51, align 8
  %uniq55 = icmp eq i64 %rc54, 1
  %fbip_slot56 = alloca ptr
  br i1 %uniq55, label %fbip_reuse11, label %fbip_fresh12
fbip_reuse11:
  %tgp57 = getelementptr i8, ptr %ld51, i64 8
  store i32 1, ptr %tgp57, align 4
  %fp58 = getelementptr i8, ptr %ld51, i64 16
  store ptr %ld52, ptr %fp58, align 8
  %fp59 = getelementptr i8, ptr %ld51, i64 24
  store ptr %ld53, ptr %fp59, align 8
  store ptr %ld51, ptr %fbip_slot56
  br label %fbip_merge13
fbip_fresh12:
  call void @march_decrc(ptr %ld51)
  %hp60 = call ptr @march_alloc(i64 32)
  %tgp61 = getelementptr i8, ptr %hp60, i64 8
  store i32 1, ptr %tgp61, align 4
  %fp62 = getelementptr i8, ptr %hp60, i64 16
  store ptr %ld52, ptr %fp62, align 8
  %fp63 = getelementptr i8, ptr %hp60, i64 24
  store ptr %ld53, ptr %fp63, align 8
  store ptr %hp60, ptr %fbip_slot56
  br label %fbip_merge13
fbip_merge13:
  %fbip_r64 = load ptr, ptr %fbip_slot56
  store ptr %fbip_r64, ptr %res_slot25
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r65 = load ptr, ptr %res_slot25
  ret ptr %case_r65
}

define i64 @sum_leaves(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld66 = load ptr, ptr %t.addr
  %res_slot67 = alloca ptr
  %tgp68 = getelementptr i8, ptr %ld66, i64 8
  %tag69 = load i32, ptr %tgp68, align 4
  switch i32 %tag69, label %case_default15 [
      i32 0, label %case_br16
      i32 1, label %case_br17
  ]
case_br16:
  %fp70 = getelementptr i8, ptr %ld66, i64 16
  %fv71 = load i64, ptr %fp70, align 8
  %n.addr = alloca i64
  store i64 %fv71, ptr %n.addr
  %ld72 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld72)
  %ld73 = load i64, ptr %n.addr
  %cv74 = inttoptr i64 %ld73 to ptr
  store ptr %cv74, ptr %res_slot67
  br label %case_merge14
case_br17:
  %fp75 = getelementptr i8, ptr %ld66, i64 16
  %fv76 = load ptr, ptr %fp75, align 8
  %l.addr = alloca ptr
  store ptr %fv76, ptr %l.addr
  %fp77 = getelementptr i8, ptr %ld66, i64 24
  %fv78 = load ptr, ptr %fp77, align 8
  %r.addr = alloca ptr
  store ptr %fv78, ptr %r.addr
  %freed79 = call i64 @march_decrc_freed(ptr %ld66)
  %freed_b80 = icmp ne i64 %freed79, 0
  br i1 %freed_b80, label %br_unique18, label %br_shared19
br_shared19:
  call void @march_incrc(ptr %fv78)
  call void @march_incrc(ptr %fv76)
  br label %br_body20
br_unique18:
  br label %br_body20
br_body20:
  %ld81 = load ptr, ptr %l.addr
  %cr82 = call i64 @sum_leaves(ptr %ld81)
  %$t582.addr = alloca i64
  store i64 %cr82, ptr %$t582.addr
  %ld83 = load ptr, ptr %r.addr
  %cr84 = call i64 @sum_leaves(ptr %ld83)
  %$t583.addr = alloca i64
  store i64 %cr84, ptr %$t583.addr
  %ld85 = load i64, ptr %$t582.addr
  %ld86 = load i64, ptr %$t583.addr
  %ar87 = add i64 %ld85, %ld86
  %cv88 = inttoptr i64 %ar87 to ptr
  store ptr %cv88, ptr %res_slot67
  br label %case_merge14
case_default15:
  unreachable
case_merge14:
  %case_r89 = load ptr, ptr %res_slot67
  %cv90 = ptrtoint ptr %case_r89 to i64
  ret i64 %cv90
}

define ptr @repeat(ptr %t.arg, i64 %n.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld91 = load i64, ptr %n.addr
  %cmp92 = icmp eq i64 %ld91, 0
  %ar93 = zext i1 %cmp92 to i64
  %$t584.addr = alloca i64
  store i64 %ar93, ptr %$t584.addr
  %ld94 = load i64, ptr %$t584.addr
  %res_slot95 = alloca ptr
  switch i64 %ld94, label %case_default22 [
      i64 1, label %case_br23
  ]
case_br23:
  %ld96 = load ptr, ptr %t.addr
  store ptr %ld96, ptr %res_slot95
  br label %case_merge21
case_default22:
  %ld97 = load ptr, ptr %t.addr
  %cr98 = call ptr @inc_leaves(ptr %ld97)
  %$t585.addr = alloca ptr
  store ptr %cr98, ptr %$t585.addr
  %ld99 = load i64, ptr %n.addr
  %ar100 = sub i64 %ld99, 1
  %$t586.addr = alloca i64
  store i64 %ar100, ptr %$t586.addr
  %ld101 = load ptr, ptr %$t585.addr
  %ld102 = load i64, ptr %$t586.addr
  %cr103 = call ptr @repeat(ptr %ld101, i64 %ld102)
  store ptr %cr103, ptr %res_slot95
  br label %case_merge21
case_merge21:
  %case_r104 = load ptr, ptr %res_slot95
  ret ptr %case_r104
}

define void @march_main() {
entry:
  %depth.addr = alloca i64
  store i64 20, ptr %depth.addr
  %passes.addr = alloca i64
  store i64 100, ptr %passes.addr
  %ld105 = load i64, ptr %depth.addr
  %cr106 = call ptr @make(i64 %ld105)
  %t.addr = alloca ptr
  store ptr %cr106, ptr %t.addr
  %ld107 = load ptr, ptr %t.addr
  %ld108 = load i64, ptr %passes.addr
  %cr109 = call ptr @repeat(ptr %ld107, i64 %ld108)
  %t2.addr = alloca ptr
  store ptr %cr109, ptr %t2.addr
  %ld110 = load ptr, ptr %t2.addr
  %cr111 = call i64 @sum_leaves(ptr %ld110)
  %$t587.addr = alloca i64
  store i64 %cr111, ptr %$t587.addr
  %ld112 = load i64, ptr %$t587.addr
  %cr113 = call ptr @march_int_to_string(i64 %ld112)
  %$t588.addr = alloca ptr
  store ptr %cr113, ptr %$t588.addr
  %ld114 = load ptr, ptr %$t588.addr
  call void @march_println(ptr %ld114)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
