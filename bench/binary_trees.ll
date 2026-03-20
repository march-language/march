; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
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

@.str1 = private unnamed_addr constant [17 x i8] c" trees of depth \00"
@.str2 = private unnamed_addr constant [9 x i8] c" check: \00"
@.str3 = private unnamed_addr constant [23 x i8] c"stretch tree of depth \00"
@.str4 = private unnamed_addr constant [9 x i8] c" check: \00"
@.str5 = private unnamed_addr constant [26 x i8] c"long lived tree of depth \00"
@.str6 = private unnamed_addr constant [9 x i8] c" check: \00"

define ptr @make(i64 %d.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %ld1 = load i64, ptr %d.addr
  %cmp2 = icmp eq i64 %ld1, 0
  %ar3 = zext i1 %cmp2 to i64
  %$t351.addr = alloca i64
  store i64 %ar3, ptr %$t351.addr
  %ld4 = load i64, ptr %$t351.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %hp6 = call ptr @march_alloc(i64 16)
  %tgp7 = getelementptr i8, ptr %hp6, i64 8
  store i32 0, ptr %tgp7, align 4
  store ptr %hp6, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %d.addr
  %ar9 = sub i64 %ld8, 1
  %$t352.addr = alloca i64
  store i64 %ar9, ptr %$t352.addr
  %ld10 = load i64, ptr %$t352.addr
  %cr11 = call ptr @make(i64 %ld10)
  %$t353.addr = alloca ptr
  store ptr %cr11, ptr %$t353.addr
  %ld12 = load i64, ptr %d.addr
  %ar13 = sub i64 %ld12, 1
  %$t354.addr = alloca i64
  store i64 %ar13, ptr %$t354.addr
  %ld14 = load i64, ptr %$t354.addr
  %cr15 = call ptr @make(i64 %ld14)
  %$t355.addr = alloca ptr
  store ptr %cr15, ptr %$t355.addr
  %hp16 = call ptr @march_alloc(i64 32)
  %tgp17 = getelementptr i8, ptr %hp16, i64 8
  store i32 1, ptr %tgp17, align 4
  %ld18 = load ptr, ptr %$t353.addr
  %fp19 = getelementptr i8, ptr %hp16, i64 16
  store ptr %ld18, ptr %fp19, align 8
  %ld20 = load ptr, ptr %$t355.addr
  %fp21 = getelementptr i8, ptr %hp16, i64 24
  store ptr %ld20, ptr %fp21, align 8
  store ptr %hp16, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r22 = load ptr, ptr %res_slot5
  ret ptr %case_r22
}

define i64 @check(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld23 = load ptr, ptr %t.addr
  %res_slot24 = alloca ptr
  %tgp25 = getelementptr i8, ptr %ld23, i64 8
  %tag26 = load i32, ptr %tgp25, align 4
  switch i32 %tag26, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %ld27 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld27)
  %cv28 = inttoptr i64 1 to ptr
  store ptr %cv28, ptr %res_slot24
  br label %case_merge4
case_br7:
  %fp29 = getelementptr i8, ptr %ld23, i64 16
  %fv30 = load ptr, ptr %fp29, align 8
  %l.addr = alloca ptr
  store ptr %fv30, ptr %l.addr
  %fp31 = getelementptr i8, ptr %ld23, i64 24
  %fv32 = load ptr, ptr %fp31, align 8
  %r.addr = alloca ptr
  store ptr %fv32, ptr %r.addr
  %ld33 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld33)
  %ld34 = load ptr, ptr %l.addr
  %cr35 = call i64 @check(ptr %ld34)
  %$t356.addr = alloca i64
  store i64 %cr35, ptr %$t356.addr
  %ld36 = load ptr, ptr %r.addr
  %cr37 = call i64 @check(ptr %ld36)
  %$t357.addr = alloca i64
  store i64 %cr37, ptr %$t357.addr
  %ld38 = load i64, ptr %$t356.addr
  %ld39 = load i64, ptr %$t357.addr
  %ar40 = add i64 %ld38, %ld39
  %$t358.addr = alloca i64
  store i64 %ar40, ptr %$t358.addr
  %ld41 = load i64, ptr %$t358.addr
  %ar42 = add i64 %ld41, 1
  %cv43 = inttoptr i64 %ar42 to ptr
  store ptr %cv43, ptr %res_slot24
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r44 = load ptr, ptr %res_slot24
  %cv45 = ptrtoint ptr %case_r44 to i64
  ret i64 %cv45
}

define i64 @pow2(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld46 = load i64, ptr %n.addr
  %cmp47 = icmp eq i64 %ld46, 0
  %ar48 = zext i1 %cmp47 to i64
  %$t359.addr = alloca i64
  store i64 %ar48, ptr %$t359.addr
  %ld49 = load i64, ptr %$t359.addr
  %res_slot50 = alloca ptr
  switch i64 %ld49, label %case_default9 [
      i64 1, label %case_br10
  ]
case_br10:
  %cv51 = inttoptr i64 1 to ptr
  store ptr %cv51, ptr %res_slot50
  br label %case_merge8
case_default9:
  %ld52 = load i64, ptr %n.addr
  %ar53 = sub i64 %ld52, 1
  %$t360.addr = alloca i64
  store i64 %ar53, ptr %$t360.addr
  %ld54 = load i64, ptr %$t360.addr
  %cr55 = call i64 @pow2(i64 %ld54)
  %$t361.addr = alloca i64
  store i64 %cr55, ptr %$t361.addr
  %ld56 = load i64, ptr %$t361.addr
  %ld57 = load i64, ptr %$t361.addr
  %ar58 = add i64 %ld56, %ld57
  %sr_s1.addr = alloca i64
  store i64 %ar58, ptr %sr_s1.addr
  %ld59 = load i64, ptr %sr_s1.addr
  %cv60 = inttoptr i64 %ld59 to ptr
  store ptr %cv60, ptr %res_slot50
  br label %case_merge8
case_merge8:
  %case_r61 = load ptr, ptr %res_slot50
  %cv62 = ptrtoint ptr %case_r61 to i64
  ret i64 %cv62
}

define i64 @sum_trees(i64 %iters.arg, i64 %depth.arg, i64 %acc.arg) {
entry:
  %iters.addr = alloca i64
  store i64 %iters.arg, ptr %iters.addr
  %depth.addr = alloca i64
  store i64 %depth.arg, ptr %depth.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld63 = load i64, ptr %iters.addr
  %cmp64 = icmp eq i64 %ld63, 0
  %ar65 = zext i1 %cmp64 to i64
  %$t362.addr = alloca i64
  store i64 %ar65, ptr %$t362.addr
  %ld66 = load i64, ptr %$t362.addr
  %res_slot67 = alloca ptr
  switch i64 %ld66, label %case_default12 [
      i64 1, label %case_br13
  ]
case_br13:
  %ld68 = load i64, ptr %acc.addr
  %cv69 = inttoptr i64 %ld68 to ptr
  store ptr %cv69, ptr %res_slot67
  br label %case_merge11
case_default12:
  %ld70 = load i64, ptr %iters.addr
  %ar71 = sub i64 %ld70, 1
  %$t363.addr = alloca i64
  store i64 %ar71, ptr %$t363.addr
  %ld72 = load i64, ptr %depth.addr
  %cr73 = call ptr @make(i64 %ld72)
  %$t364.addr = alloca ptr
  store ptr %cr73, ptr %$t364.addr
  %ld74 = load ptr, ptr %$t364.addr
  %cr75 = call i64 @check(ptr %ld74)
  %$t365.addr = alloca i64
  store i64 %cr75, ptr %$t365.addr
  %ld76 = load i64, ptr %acc.addr
  %ld77 = load i64, ptr %$t365.addr
  %ar78 = add i64 %ld76, %ld77
  %$t366.addr = alloca i64
  store i64 %ar78, ptr %$t366.addr
  %ld79 = load i64, ptr %$t363.addr
  %ld80 = load i64, ptr %depth.addr
  %ld81 = load i64, ptr %$t366.addr
  %cr82 = call i64 @sum_trees(i64 %ld79, i64 %ld80, i64 %ld81)
  %cv83 = inttoptr i64 %cr82 to ptr
  store ptr %cv83, ptr %res_slot67
  br label %case_merge11
case_merge11:
  %case_r84 = load ptr, ptr %res_slot67
  %cv85 = ptrtoint ptr %case_r84 to i64
  ret i64 %cv85
}

define void @run_depths(i64 %d.arg, i64 %max_depth.arg, i64 %min_depth.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %max_depth.addr = alloca i64
  store i64 %max_depth.arg, ptr %max_depth.addr
  %min_depth.addr = alloca i64
  store i64 %min_depth.arg, ptr %min_depth.addr
  %ld86 = load i64, ptr %d.addr
  %ld87 = load i64, ptr %max_depth.addr
  %cmp88 = icmp sgt i64 %ld86, %ld87
  %ar89 = zext i1 %cmp88 to i64
  %$t367.addr = alloca i64
  store i64 %ar89, ptr %$t367.addr
  %ld90 = load i64, ptr %$t367.addr
  %res_slot91 = alloca ptr
  switch i64 %ld90, label %case_default15 [
      i64 1, label %case_br16
  ]
case_br16:
  %cv92 = inttoptr i64 0 to ptr
  store ptr %cv92, ptr %res_slot91
  br label %case_merge14
case_default15:
  %ld93 = load i64, ptr %max_depth.addr
  %ld94 = load i64, ptr %d.addr
  %ar95 = sub i64 %ld93, %ld94
  %$t368.addr = alloca i64
  store i64 %ar95, ptr %$t368.addr
  %ld96 = load i64, ptr %$t368.addr
  %ld97 = load i64, ptr %min_depth.addr
  %ar98 = add i64 %ld96, %ld97
  %$t369.addr = alloca i64
  store i64 %ar98, ptr %$t369.addr
  %ld99 = load i64, ptr %$t369.addr
  %cr100 = call i64 @pow2(i64 %ld99)
  %iters.addr = alloca i64
  store i64 %cr100, ptr %iters.addr
  %ld101 = load i64, ptr %iters.addr
  %ld102 = load i64, ptr %d.addr
  %cr103 = call i64 @sum_trees(i64 %ld101, i64 %ld102, i64 0)
  %s.addr = alloca i64
  store i64 %cr103, ptr %s.addr
  %ld104 = load i64, ptr %iters.addr
  %cr105 = call ptr @march_int_to_string(i64 %ld104)
  %$t370.addr = alloca ptr
  store ptr %cr105, ptr %$t370.addr
  %ld106 = load ptr, ptr %$t370.addr
  %sl107 = call ptr @march_string_lit(ptr @.str1, i64 16)
  %cr108 = call ptr @march_string_concat(ptr %ld106, ptr %sl107)
  %$t371.addr = alloca ptr
  store ptr %cr108, ptr %$t371.addr
  %ld109 = load i64, ptr %d.addr
  %cr110 = call ptr @march_int_to_string(i64 %ld109)
  %$t372.addr = alloca ptr
  store ptr %cr110, ptr %$t372.addr
  %ld111 = load ptr, ptr %$t371.addr
  %ld112 = load ptr, ptr %$t372.addr
  %cr113 = call ptr @march_string_concat(ptr %ld111, ptr %ld112)
  %$t373.addr = alloca ptr
  store ptr %cr113, ptr %$t373.addr
  %ld114 = load ptr, ptr %$t373.addr
  %sl115 = call ptr @march_string_lit(ptr @.str2, i64 8)
  %cr116 = call ptr @march_string_concat(ptr %ld114, ptr %sl115)
  %$t374.addr = alloca ptr
  store ptr %cr116, ptr %$t374.addr
  %ld117 = load i64, ptr %s.addr
  %cr118 = call ptr @march_int_to_string(i64 %ld117)
  %$t375.addr = alloca ptr
  store ptr %cr118, ptr %$t375.addr
  %ld119 = load ptr, ptr %$t374.addr
  %ld120 = load ptr, ptr %$t375.addr
  %cr121 = call ptr @march_string_concat(ptr %ld119, ptr %ld120)
  %$t376.addr = alloca ptr
  store ptr %cr121, ptr %$t376.addr
  %ld122 = load ptr, ptr %$t376.addr
  call void @march_println(ptr %ld122)
  %ld123 = load i64, ptr %d.addr
  %ar124 = add i64 %ld123, 2
  %$t377.addr = alloca i64
  store i64 %ar124, ptr %$t377.addr
  %ld125 = load i64, ptr %$t377.addr
  %ld126 = load i64, ptr %max_depth.addr
  %ld127 = load i64, ptr %min_depth.addr
  %cr128 = call ptr @run_depths(i64 %ld125, i64 %ld126, i64 %ld127)
  store ptr %cr128, ptr %res_slot91
  br label %case_merge14
case_merge14:
  %case_r129 = load ptr, ptr %res_slot91
  ret void
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 15, ptr %n.addr
  %min_depth.addr = alloca i64
  store i64 4, ptr %min_depth.addr
  %ld130 = load i64, ptr %min_depth.addr
  %ar131 = add i64 %ld130, 2
  %$t378.addr = alloca i64
  store i64 %ar131, ptr %$t378.addr
  %ld132 = load i64, ptr %n.addr
  %ld133 = load i64, ptr %$t378.addr
  %cmp134 = icmp sgt i64 %ld132, %ld133
  %ar135 = zext i1 %cmp134 to i64
  %$t379.addr = alloca i64
  store i64 %ar135, ptr %$t379.addr
  %ld136 = load i64, ptr %$t379.addr
  %res_slot137 = alloca ptr
  switch i64 %ld136, label %case_default18 [
      i64 1, label %case_br19
  ]
case_br19:
  %ld138 = load i64, ptr %n.addr
  %cv139 = inttoptr i64 %ld138 to ptr
  store ptr %cv139, ptr %res_slot137
  br label %case_merge17
case_default18:
  %ld140 = load i64, ptr %min_depth.addr
  %ar141 = add i64 %ld140, 2
  %cv142 = inttoptr i64 %ar141 to ptr
  store ptr %cv142, ptr %res_slot137
  br label %case_merge17
case_merge17:
  %case_r143 = load ptr, ptr %res_slot137
  %cv144 = ptrtoint ptr %case_r143 to i64
  %max_depth.addr = alloca i64
  store i64 %cv144, ptr %max_depth.addr
  %ld145 = load i64, ptr %max_depth.addr
  %ar146 = add i64 %ld145, 1
  %stretch.addr = alloca i64
  store i64 %ar146, ptr %stretch.addr
  %ld147 = load i64, ptr %stretch.addr
  %cr148 = call ptr @march_int_to_string(i64 %ld147)
  %$t380.addr = alloca ptr
  store ptr %cr148, ptr %$t380.addr
  %sl149 = call ptr @march_string_lit(ptr @.str3, i64 22)
  %ld150 = load ptr, ptr %$t380.addr
  %cr151 = call ptr @march_string_concat(ptr %sl149, ptr %ld150)
  %$t381.addr = alloca ptr
  store ptr %cr151, ptr %$t381.addr
  %ld152 = load ptr, ptr %$t381.addr
  %sl153 = call ptr @march_string_lit(ptr @.str4, i64 8)
  %cr154 = call ptr @march_string_concat(ptr %ld152, ptr %sl153)
  %$t382.addr = alloca ptr
  store ptr %cr154, ptr %$t382.addr
  %ld155 = load i64, ptr %stretch.addr
  %cr156 = call ptr @make(i64 %ld155)
  %$t383.addr = alloca ptr
  store ptr %cr156, ptr %$t383.addr
  %ld157 = load ptr, ptr %$t383.addr
  %cr158 = call i64 @check(ptr %ld157)
  %$t384.addr = alloca i64
  store i64 %cr158, ptr %$t384.addr
  %ld159 = load i64, ptr %$t384.addr
  %cr160 = call ptr @march_int_to_string(i64 %ld159)
  %$t385.addr = alloca ptr
  store ptr %cr160, ptr %$t385.addr
  %ld161 = load ptr, ptr %$t382.addr
  %ld162 = load ptr, ptr %$t385.addr
  %cr163 = call ptr @march_string_concat(ptr %ld161, ptr %ld162)
  %$t386.addr = alloca ptr
  store ptr %cr163, ptr %$t386.addr
  %ld164 = load ptr, ptr %$t386.addr
  call void @march_println(ptr %ld164)
  %ld165 = load i64, ptr %max_depth.addr
  %cr166 = call ptr @make(i64 %ld165)
  %long_lived.addr = alloca ptr
  store ptr %cr166, ptr %long_lived.addr
  %ld167 = load i64, ptr %min_depth.addr
  %ld168 = load i64, ptr %max_depth.addr
  %ld169 = load i64, ptr %min_depth.addr
  %cr170 = call ptr @run_depths(i64 %ld167, i64 %ld168, i64 %ld169)
  %ld171 = load i64, ptr %max_depth.addr
  %cr172 = call ptr @march_int_to_string(i64 %ld171)
  %$t387.addr = alloca ptr
  store ptr %cr172, ptr %$t387.addr
  %sl173 = call ptr @march_string_lit(ptr @.str5, i64 25)
  %ld174 = load ptr, ptr %$t387.addr
  %cr175 = call ptr @march_string_concat(ptr %sl173, ptr %ld174)
  %$t388.addr = alloca ptr
  store ptr %cr175, ptr %$t388.addr
  %ld176 = load ptr, ptr %$t388.addr
  %sl177 = call ptr @march_string_lit(ptr @.str6, i64 8)
  %cr178 = call ptr @march_string_concat(ptr %ld176, ptr %sl177)
  %$t389.addr = alloca ptr
  store ptr %cr178, ptr %$t389.addr
  %ld179 = load ptr, ptr %long_lived.addr
  %cr180 = call i64 @check(ptr %ld179)
  %$t390.addr = alloca i64
  store i64 %cr180, ptr %$t390.addr
  %ld181 = load i64, ptr %$t390.addr
  %cr182 = call ptr @march_int_to_string(i64 %ld181)
  %$t391.addr = alloca ptr
  store ptr %cr182, ptr %$t391.addr
  %ld183 = load ptr, ptr %$t389.addr
  %ld184 = load ptr, ptr %$t391.addr
  %cr185 = call ptr @march_string_concat(ptr %ld183, ptr %ld184)
  %$t392.addr = alloca ptr
  store ptr %cr185, ptr %$t392.addr
  %ld186 = load ptr, ptr %$t392.addr
  call void @march_println(ptr %ld186)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
