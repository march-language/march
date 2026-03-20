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
  %$t574.addr = alloca i64
  store i64 %ar3, ptr %$t574.addr
  %ld4 = load i64, ptr %$t574.addr
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
  %$t575.addr = alloca i64
  store i64 %ar9, ptr %$t575.addr
  %ld10 = load i64, ptr %$t575.addr
  %cr11 = call ptr @make(i64 %ld10)
  %$t576.addr = alloca ptr
  store ptr %cr11, ptr %$t576.addr
  %ld12 = load i64, ptr %d.addr
  %ar13 = sub i64 %ld12, 1
  %$t577.addr = alloca i64
  store i64 %ar13, ptr %$t577.addr
  %ld14 = load i64, ptr %$t577.addr
  %cr15 = call ptr @make(i64 %ld14)
  %$t578.addr = alloca ptr
  store ptr %cr15, ptr %$t578.addr
  %hp16 = call ptr @march_alloc(i64 32)
  %tgp17 = getelementptr i8, ptr %hp16, i64 8
  store i32 1, ptr %tgp17, align 4
  %ld18 = load ptr, ptr %$t576.addr
  %fp19 = getelementptr i8, ptr %hp16, i64 16
  store ptr %ld18, ptr %fp19, align 8
  %ld20 = load ptr, ptr %$t578.addr
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
  %freed33 = call i64 @march_decrc_freed(ptr %ld23)
  %freed_b34 = icmp ne i64 %freed33, 0
  br i1 %freed_b34, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv32)
  call void @march_incrc(ptr %fv30)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld35 = load ptr, ptr %l.addr
  %cr36 = call i64 @check(ptr %ld35)
  %$t579.addr = alloca i64
  store i64 %cr36, ptr %$t579.addr
  %ld37 = load ptr, ptr %r.addr
  %cr38 = call i64 @check(ptr %ld37)
  %$t580.addr = alloca i64
  store i64 %cr38, ptr %$t580.addr
  %ld39 = load i64, ptr %$t579.addr
  %ld40 = load i64, ptr %$t580.addr
  %ar41 = add i64 %ld39, %ld40
  %$t581.addr = alloca i64
  store i64 %ar41, ptr %$t581.addr
  %ld42 = load i64, ptr %$t581.addr
  %ar43 = add i64 %ld42, 1
  %cv44 = inttoptr i64 %ar43 to ptr
  store ptr %cv44, ptr %res_slot24
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r45 = load ptr, ptr %res_slot24
  %cv46 = ptrtoint ptr %case_r45 to i64
  ret i64 %cv46
}

define i64 @pow2(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld47 = load i64, ptr %n.addr
  %cmp48 = icmp eq i64 %ld47, 0
  %ar49 = zext i1 %cmp48 to i64
  %$t582.addr = alloca i64
  store i64 %ar49, ptr %$t582.addr
  %ld50 = load i64, ptr %$t582.addr
  %res_slot51 = alloca ptr
  switch i64 %ld50, label %case_default12 [
      i64 1, label %case_br13
  ]
case_br13:
  %cv52 = inttoptr i64 1 to ptr
  store ptr %cv52, ptr %res_slot51
  br label %case_merge11
case_default12:
  %ld53 = load i64, ptr %n.addr
  %ar54 = sub i64 %ld53, 1
  %$t583.addr = alloca i64
  store i64 %ar54, ptr %$t583.addr
  %ld55 = load i64, ptr %$t583.addr
  %cr56 = call i64 @pow2(i64 %ld55)
  %$t584.addr = alloca i64
  store i64 %cr56, ptr %$t584.addr
  %ld57 = load i64, ptr %$t584.addr
  %ld58 = load i64, ptr %$t584.addr
  %ar59 = add i64 %ld57, %ld58
  %sr_s1.addr = alloca i64
  store i64 %ar59, ptr %sr_s1.addr
  %ld60 = load i64, ptr %sr_s1.addr
  %cv61 = inttoptr i64 %ld60 to ptr
  store ptr %cv61, ptr %res_slot51
  br label %case_merge11
case_merge11:
  %case_r62 = load ptr, ptr %res_slot51
  %cv63 = ptrtoint ptr %case_r62 to i64
  ret i64 %cv63
}

define i64 @sum_trees(i64 %iters.arg, i64 %depth.arg, i64 %acc.arg) {
entry:
  %iters.addr = alloca i64
  store i64 %iters.arg, ptr %iters.addr
  %depth.addr = alloca i64
  store i64 %depth.arg, ptr %depth.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld64 = load i64, ptr %iters.addr
  %cmp65 = icmp eq i64 %ld64, 0
  %ar66 = zext i1 %cmp65 to i64
  %$t585.addr = alloca i64
  store i64 %ar66, ptr %$t585.addr
  %ld67 = load i64, ptr %$t585.addr
  %res_slot68 = alloca ptr
  switch i64 %ld67, label %case_default15 [
      i64 1, label %case_br16
  ]
case_br16:
  %ld69 = load i64, ptr %acc.addr
  %cv70 = inttoptr i64 %ld69 to ptr
  store ptr %cv70, ptr %res_slot68
  br label %case_merge14
case_default15:
  %ld71 = load i64, ptr %iters.addr
  %ar72 = sub i64 %ld71, 1
  %$t586.addr = alloca i64
  store i64 %ar72, ptr %$t586.addr
  %ld73 = load i64, ptr %depth.addr
  %cr74 = call ptr @make(i64 %ld73)
  %$t587.addr = alloca ptr
  store ptr %cr74, ptr %$t587.addr
  %ld75 = load ptr, ptr %$t587.addr
  %cr76 = call i64 @check(ptr %ld75)
  %$t588.addr = alloca i64
  store i64 %cr76, ptr %$t588.addr
  %ld77 = load i64, ptr %acc.addr
  %ld78 = load i64, ptr %$t588.addr
  %ar79 = add i64 %ld77, %ld78
  %$t589.addr = alloca i64
  store i64 %ar79, ptr %$t589.addr
  %ld80 = load i64, ptr %$t586.addr
  %ld81 = load i64, ptr %depth.addr
  %ld82 = load i64, ptr %$t589.addr
  %cr83 = call i64 @sum_trees(i64 %ld80, i64 %ld81, i64 %ld82)
  %cv84 = inttoptr i64 %cr83 to ptr
  store ptr %cv84, ptr %res_slot68
  br label %case_merge14
case_merge14:
  %case_r85 = load ptr, ptr %res_slot68
  %cv86 = ptrtoint ptr %case_r85 to i64
  ret i64 %cv86
}

define void @run_depths(i64 %d.arg, i64 %max_depth.arg, i64 %min_depth.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %max_depth.addr = alloca i64
  store i64 %max_depth.arg, ptr %max_depth.addr
  %min_depth.addr = alloca i64
  store i64 %min_depth.arg, ptr %min_depth.addr
  %ld87 = load i64, ptr %d.addr
  %ld88 = load i64, ptr %max_depth.addr
  %cmp89 = icmp sgt i64 %ld87, %ld88
  %ar90 = zext i1 %cmp89 to i64
  %$t590.addr = alloca i64
  store i64 %ar90, ptr %$t590.addr
  %ld91 = load i64, ptr %$t590.addr
  %res_slot92 = alloca ptr
  switch i64 %ld91, label %case_default18 [
      i64 1, label %case_br19
  ]
case_br19:
  %cv93 = inttoptr i64 0 to ptr
  store ptr %cv93, ptr %res_slot92
  br label %case_merge17
case_default18:
  %ld94 = load i64, ptr %max_depth.addr
  %ld95 = load i64, ptr %d.addr
  %ar96 = sub i64 %ld94, %ld95
  %$t591.addr = alloca i64
  store i64 %ar96, ptr %$t591.addr
  %ld97 = load i64, ptr %$t591.addr
  %ld98 = load i64, ptr %min_depth.addr
  %ar99 = add i64 %ld97, %ld98
  %$t592.addr = alloca i64
  store i64 %ar99, ptr %$t592.addr
  %ld100 = load i64, ptr %$t592.addr
  %cr101 = call i64 @pow2(i64 %ld100)
  %iters.addr = alloca i64
  store i64 %cr101, ptr %iters.addr
  %ld102 = load i64, ptr %iters.addr
  %ld103 = load i64, ptr %d.addr
  %cr104 = call i64 @sum_trees(i64 %ld102, i64 %ld103, i64 0)
  %s.addr = alloca i64
  store i64 %cr104, ptr %s.addr
  %ld105 = load i64, ptr %iters.addr
  %cr106 = call ptr @march_int_to_string(i64 %ld105)
  %$t593.addr = alloca ptr
  store ptr %cr106, ptr %$t593.addr
  %ld107 = load ptr, ptr %$t593.addr
  %sl108 = call ptr @march_string_lit(ptr @.str1, i64 16)
  %cr109 = call ptr @march_string_concat(ptr %ld107, ptr %sl108)
  %$t594.addr = alloca ptr
  store ptr %cr109, ptr %$t594.addr
  %ld110 = load i64, ptr %d.addr
  %cr111 = call ptr @march_int_to_string(i64 %ld110)
  %$t595.addr = alloca ptr
  store ptr %cr111, ptr %$t595.addr
  %ld112 = load ptr, ptr %$t594.addr
  %ld113 = load ptr, ptr %$t595.addr
  %cr114 = call ptr @march_string_concat(ptr %ld112, ptr %ld113)
  %$t596.addr = alloca ptr
  store ptr %cr114, ptr %$t596.addr
  %ld115 = load ptr, ptr %$t596.addr
  %sl116 = call ptr @march_string_lit(ptr @.str2, i64 8)
  %cr117 = call ptr @march_string_concat(ptr %ld115, ptr %sl116)
  %$t597.addr = alloca ptr
  store ptr %cr117, ptr %$t597.addr
  %ld118 = load i64, ptr %s.addr
  %cr119 = call ptr @march_int_to_string(i64 %ld118)
  %$t598.addr = alloca ptr
  store ptr %cr119, ptr %$t598.addr
  %ld120 = load ptr, ptr %$t597.addr
  %ld121 = load ptr, ptr %$t598.addr
  %cr122 = call ptr @march_string_concat(ptr %ld120, ptr %ld121)
  %$t599.addr = alloca ptr
  store ptr %cr122, ptr %$t599.addr
  %ld123 = load ptr, ptr %$t599.addr
  call void @march_println(ptr %ld123)
  %ld124 = load i64, ptr %d.addr
  %ar125 = add i64 %ld124, 2
  %$t600.addr = alloca i64
  store i64 %ar125, ptr %$t600.addr
  %ld126 = load i64, ptr %$t600.addr
  %ld127 = load i64, ptr %max_depth.addr
  %ld128 = load i64, ptr %min_depth.addr
  %cr129 = call ptr @run_depths(i64 %ld126, i64 %ld127, i64 %ld128)
  store ptr %cr129, ptr %res_slot92
  br label %case_merge17
case_merge17:
  %case_r130 = load ptr, ptr %res_slot92
  ret void
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 15, ptr %n.addr
  %min_depth.addr = alloca i64
  store i64 4, ptr %min_depth.addr
  %ld131 = load i64, ptr %min_depth.addr
  %ar132 = add i64 %ld131, 2
  %$t601.addr = alloca i64
  store i64 %ar132, ptr %$t601.addr
  %ld133 = load i64, ptr %n.addr
  %ld134 = load i64, ptr %$t601.addr
  %cmp135 = icmp sgt i64 %ld133, %ld134
  %ar136 = zext i1 %cmp135 to i64
  %$t602.addr = alloca i64
  store i64 %ar136, ptr %$t602.addr
  %ld137 = load i64, ptr %$t602.addr
  %res_slot138 = alloca ptr
  switch i64 %ld137, label %case_default21 [
      i64 1, label %case_br22
  ]
case_br22:
  %ld139 = load i64, ptr %n.addr
  %cv140 = inttoptr i64 %ld139 to ptr
  store ptr %cv140, ptr %res_slot138
  br label %case_merge20
case_default21:
  %ld141 = load i64, ptr %min_depth.addr
  %ar142 = add i64 %ld141, 2
  %cv143 = inttoptr i64 %ar142 to ptr
  store ptr %cv143, ptr %res_slot138
  br label %case_merge20
case_merge20:
  %case_r144 = load ptr, ptr %res_slot138
  %cv145 = ptrtoint ptr %case_r144 to i64
  %max_depth.addr = alloca i64
  store i64 %cv145, ptr %max_depth.addr
  %ld146 = load i64, ptr %max_depth.addr
  %ar147 = add i64 %ld146, 1
  %stretch.addr = alloca i64
  store i64 %ar147, ptr %stretch.addr
  %ld148 = load i64, ptr %stretch.addr
  %cr149 = call ptr @march_int_to_string(i64 %ld148)
  %$t603.addr = alloca ptr
  store ptr %cr149, ptr %$t603.addr
  %sl150 = call ptr @march_string_lit(ptr @.str3, i64 22)
  %ld151 = load ptr, ptr %$t603.addr
  %cr152 = call ptr @march_string_concat(ptr %sl150, ptr %ld151)
  %$t604.addr = alloca ptr
  store ptr %cr152, ptr %$t604.addr
  %ld153 = load ptr, ptr %$t604.addr
  %sl154 = call ptr @march_string_lit(ptr @.str4, i64 8)
  %cr155 = call ptr @march_string_concat(ptr %ld153, ptr %sl154)
  %$t605.addr = alloca ptr
  store ptr %cr155, ptr %$t605.addr
  %ld156 = load i64, ptr %stretch.addr
  %cr157 = call ptr @make(i64 %ld156)
  %$t606.addr = alloca ptr
  store ptr %cr157, ptr %$t606.addr
  %ld158 = load ptr, ptr %$t606.addr
  %cr159 = call i64 @check(ptr %ld158)
  %$t607.addr = alloca i64
  store i64 %cr159, ptr %$t607.addr
  %ld160 = load i64, ptr %$t607.addr
  %cr161 = call ptr @march_int_to_string(i64 %ld160)
  %$t608.addr = alloca ptr
  store ptr %cr161, ptr %$t608.addr
  %ld162 = load ptr, ptr %$t605.addr
  %ld163 = load ptr, ptr %$t608.addr
  %cr164 = call ptr @march_string_concat(ptr %ld162, ptr %ld163)
  %$t609.addr = alloca ptr
  store ptr %cr164, ptr %$t609.addr
  %ld165 = load ptr, ptr %$t609.addr
  call void @march_println(ptr %ld165)
  %ld166 = load i64, ptr %max_depth.addr
  %cr167 = call ptr @make(i64 %ld166)
  %long_lived.addr = alloca ptr
  store ptr %cr167, ptr %long_lived.addr
  %ld168 = load i64, ptr %min_depth.addr
  %ld169 = load i64, ptr %max_depth.addr
  %ld170 = load i64, ptr %min_depth.addr
  %cr171 = call ptr @run_depths(i64 %ld168, i64 %ld169, i64 %ld170)
  %ld172 = load i64, ptr %max_depth.addr
  %cr173 = call ptr @march_int_to_string(i64 %ld172)
  %$t610.addr = alloca ptr
  store ptr %cr173, ptr %$t610.addr
  %sl174 = call ptr @march_string_lit(ptr @.str5, i64 25)
  %ld175 = load ptr, ptr %$t610.addr
  %cr176 = call ptr @march_string_concat(ptr %sl174, ptr %ld175)
  %$t611.addr = alloca ptr
  store ptr %cr176, ptr %$t611.addr
  %ld177 = load ptr, ptr %$t611.addr
  %sl178 = call ptr @march_string_lit(ptr @.str6, i64 8)
  %cr179 = call ptr @march_string_concat(ptr %ld177, ptr %sl178)
  %$t612.addr = alloca ptr
  store ptr %cr179, ptr %$t612.addr
  %ld180 = load ptr, ptr %long_lived.addr
  %cr181 = call i64 @check(ptr %ld180)
  %$t613.addr = alloca i64
  store i64 %cr181, ptr %$t613.addr
  %ld182 = load i64, ptr %$t613.addr
  %cr183 = call ptr @march_int_to_string(i64 %ld182)
  %$t614.addr = alloca ptr
  store ptr %cr183, ptr %$t614.addr
  %ld184 = load ptr, ptr %$t612.addr
  %ld185 = load ptr, ptr %$t614.addr
  %cr186 = call ptr @march_string_concat(ptr %ld184, ptr %ld185)
  %$t615.addr = alloca ptr
  store ptr %cr186, ptr %$t615.addr
  %ld187 = load ptr, ptr %$t615.addr
  call void @march_println(ptr %ld187)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
