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

@.str1 = private unnamed_addr constant [27 x i8] c"--- Fork-join examples ---\00"
@.str2 = private unnamed_addr constant [21 x i8] c"par_sum(1..10000) = \00"
@.str3 = private unnamed_addr constant [33 x i8] c"max collatz steps in 1..10000 = \00"

define i64 @sum_range(i64 %lo.arg, i64 %hi.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %ld1 = load i64, ptr %lo.addr
  %ld2 = load i64, ptr %hi.addr
  %cmp3 = icmp sgt i64 %ld1, %ld2
  %ar4 = zext i1 %cmp3 to i64
  %$t492.addr = alloca i64
  store i64 %ar4, ptr %$t492.addr
  %ld5 = load i64, ptr %$t492.addr
  %res_slot6 = alloca ptr
  switch i64 %ld5, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %cv7 = inttoptr i64 0 to ptr
  store ptr %cv7, ptr %res_slot6
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %lo.addr
  %ar9 = add i64 %ld8, 1
  %$t493.addr = alloca i64
  store i64 %ar9, ptr %$t493.addr
  %ld10 = load i64, ptr %$t493.addr
  %ld11 = load i64, ptr %hi.addr
  %cr12 = call i64 @sum_range(i64 %ld10, i64 %ld11)
  %$t494.addr = alloca i64
  store i64 %cr12, ptr %$t494.addr
  %ld13 = load i64, ptr %lo.addr
  %ld14 = load i64, ptr %$t494.addr
  %ar15 = add i64 %ld13, %ld14
  %cv16 = inttoptr i64 %ar15 to ptr
  store ptr %cv16, ptr %res_slot6
  br label %case_merge1
case_merge1:
  %case_r17 = load ptr, ptr %res_slot6
  %cv18 = ptrtoint ptr %case_r17 to i64
  ret i64 %cv18
}

define i64 @par_sum(i64 %lo.arg, i64 %hi.arg, i64 %threshold.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld19 = load i64, ptr %hi.addr
  %ld20 = load i64, ptr %lo.addr
  %ar21 = sub i64 %ld19, %ld20
  %$t495.addr = alloca i64
  store i64 %ar21, ptr %$t495.addr
  %ld22 = load i64, ptr %$t495.addr
  %ld23 = load i64, ptr %threshold.addr
  %cmp24 = icmp sle i64 %ld22, %ld23
  %ar25 = zext i1 %cmp24 to i64
  %$t496.addr = alloca i64
  store i64 %ar25, ptr %$t496.addr
  %ld26 = load i64, ptr %$t496.addr
  %res_slot27 = alloca ptr
  switch i64 %ld26, label %case_default5 [
      i64 1, label %case_br6
  ]
case_br6:
  %ld28 = load i64, ptr %lo.addr
  %ld29 = load i64, ptr %hi.addr
  %cr30 = call i64 @sum_range(i64 %ld28, i64 %ld29)
  %cv31 = inttoptr i64 %cr30 to ptr
  store ptr %cv31, ptr %res_slot27
  br label %case_merge4
case_default5:
  %ld32 = load i64, ptr %hi.addr
  %ld33 = load i64, ptr %lo.addr
  %ar34 = sub i64 %ld32, %ld33
  %$t497.addr = alloca i64
  store i64 %ar34, ptr %$t497.addr
  %ld35 = load i64, ptr %$t497.addr
  %ar36 = sdiv i64 %ld35, 2
  %$t498.addr = alloca i64
  store i64 %ar36, ptr %$t498.addr
  %ld37 = load i64, ptr %lo.addr
  %ld38 = load i64, ptr %$t498.addr
  %ar39 = add i64 %ld37, %ld38
  %mid.addr = alloca i64
  store i64 %ar39, ptr %mid.addr
  %hp40 = call ptr @march_alloc(i64 48)
  %tgp41 = getelementptr i8, ptr %hp40, i64 8
  store i32 0, ptr %tgp41, align 4
  %fp42 = getelementptr i8, ptr %hp40, i64 16
  store ptr @$lam499$apply, ptr %fp42, align 8
  %ld43 = load i64, ptr %lo.addr
  %fp44 = getelementptr i8, ptr %hp40, i64 24
  store i64 %ld43, ptr %fp44, align 8
  %ld45 = load i64, ptr %mid.addr
  %fp46 = getelementptr i8, ptr %hp40, i64 32
  store i64 %ld45, ptr %fp46, align 8
  %ld47 = load i64, ptr %threshold.addr
  %fp48 = getelementptr i8, ptr %hp40, i64 40
  store i64 %ld47, ptr %fp48, align 8
  %$t500.addr = alloca ptr
  store ptr %hp40, ptr %$t500.addr
  %ld49 = load ptr, ptr %$t500.addr
  %fp50 = getelementptr i8, ptr %ld49, i64 16
  %fv51 = load ptr, ptr %fp50, align 8
  %tsres52 = call i64 %fv51(ptr %ld49, i64 0)
  %hp53 = call ptr @march_alloc(i64 24)
  %tgp54 = getelementptr i8, ptr %hp53, i64 8
  store i32 0, ptr %tgp54, align 4
  %fp55 = getelementptr i8, ptr %hp53, i64 16
  store i64 %tsres52, ptr %fp55, align 8
  %left.addr = alloca ptr
  store ptr %hp53, ptr %left.addr
  %hp56 = call ptr @march_alloc(i64 48)
  %tgp57 = getelementptr i8, ptr %hp56, i64 8
  store i32 0, ptr %tgp57, align 4
  %fp58 = getelementptr i8, ptr %hp56, i64 16
  store ptr @$lam501$apply, ptr %fp58, align 8
  %ld59 = load i64, ptr %hi.addr
  %fp60 = getelementptr i8, ptr %hp56, i64 24
  store i64 %ld59, ptr %fp60, align 8
  %ld61 = load i64, ptr %mid.addr
  %fp62 = getelementptr i8, ptr %hp56, i64 32
  store i64 %ld61, ptr %fp62, align 8
  %ld63 = load i64, ptr %threshold.addr
  %fp64 = getelementptr i8, ptr %hp56, i64 40
  store i64 %ld63, ptr %fp64, align 8
  %$t503.addr = alloca ptr
  store ptr %hp56, ptr %$t503.addr
  %ld65 = load ptr, ptr %$t503.addr
  %fp66 = getelementptr i8, ptr %ld65, i64 16
  %fv67 = load ptr, ptr %fp66, align 8
  %tsres68 = call i64 %fv67(ptr %ld65, i64 0)
  %hp69 = call ptr @march_alloc(i64 24)
  %tgp70 = getelementptr i8, ptr %hp69, i64 8
  store i32 0, ptr %tgp70, align 4
  %fp71 = getelementptr i8, ptr %hp69, i64 16
  store i64 %tsres68, ptr %fp71, align 8
  %right.addr = alloca ptr
  store ptr %hp69, ptr %right.addr
  %ld72 = load ptr, ptr %left.addr
  %fp73 = getelementptr i8, ptr %ld72, i64 16
  %fv74 = load i64, ptr %fp73, align 8
  %l.addr = alloca i64
  store i64 %fv74, ptr %l.addr
  %ld75 = load ptr, ptr %right.addr
  %fp76 = getelementptr i8, ptr %ld75, i64 16
  %fv77 = load i64, ptr %fp76, align 8
  %r.addr = alloca i64
  store i64 %fv77, ptr %r.addr
  %ld78 = load i64, ptr %l.addr
  %ld79 = load i64, ptr %r.addr
  %ar80 = add i64 %ld78, %ld79
  %cv81 = inttoptr i64 %ar80 to ptr
  store ptr %cv81, ptr %res_slot27
  br label %case_merge4
case_merge4:
  %case_r82 = load ptr, ptr %res_slot27
  %cv83 = ptrtoint ptr %case_r82 to i64
  ret i64 %cv83
}

define i64 @collatz(i64 %n.arg, i64 %steps.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %steps.addr = alloca i64
  store i64 %steps.arg, ptr %steps.addr
  %ld84 = load i64, ptr %n.addr
  %cmp85 = icmp eq i64 %ld84, 1
  %ar86 = zext i1 %cmp85 to i64
  %$t505.addr = alloca i64
  store i64 %ar86, ptr %$t505.addr
  %ld87 = load i64, ptr %$t505.addr
  %res_slot88 = alloca ptr
  switch i64 %ld87, label %case_default8 [
      i64 1, label %case_br9
  ]
case_br9:
  %ld89 = load i64, ptr %steps.addr
  %cv90 = inttoptr i64 %ld89 to ptr
  store ptr %cv90, ptr %res_slot88
  br label %case_merge7
case_default8:
  %ld91 = load i64, ptr %n.addr
  %ar92 = srem i64 %ld91, 2
  %$t506.addr = alloca i64
  store i64 %ar92, ptr %$t506.addr
  %ld93 = load i64, ptr %$t506.addr
  %cmp94 = icmp eq i64 %ld93, 0
  %ar95 = zext i1 %cmp94 to i64
  %$t507.addr = alloca i64
  store i64 %ar95, ptr %$t507.addr
  %ld96 = load i64, ptr %$t507.addr
  %res_slot97 = alloca ptr
  switch i64 %ld96, label %case_default11 [
      i64 1, label %case_br12
  ]
case_br12:
  %ld98 = load i64, ptr %n.addr
  %ar99 = sdiv i64 %ld98, 2
  %$t508.addr = alloca i64
  store i64 %ar99, ptr %$t508.addr
  %ld100 = load i64, ptr %steps.addr
  %ar101 = add i64 %ld100, 1
  %$t509.addr = alloca i64
  store i64 %ar101, ptr %$t509.addr
  %ld102 = load i64, ptr %$t508.addr
  %ld103 = load i64, ptr %$t509.addr
  %cr104 = call i64 @collatz(i64 %ld102, i64 %ld103)
  %cv105 = inttoptr i64 %cr104 to ptr
  store ptr %cv105, ptr %res_slot97
  br label %case_merge10
case_default11:
  %ld106 = load i64, ptr %n.addr
  %ar107 = mul i64 3, %ld106
  %$t510.addr = alloca i64
  store i64 %ar107, ptr %$t510.addr
  %ld108 = load i64, ptr %$t510.addr
  %ar109 = add i64 %ld108, 1
  %$t511.addr = alloca i64
  store i64 %ar109, ptr %$t511.addr
  %ld110 = load i64, ptr %steps.addr
  %ar111 = add i64 %ld110, 1
  %$t512.addr = alloca i64
  store i64 %ar111, ptr %$t512.addr
  %ld112 = load i64, ptr %$t511.addr
  %ld113 = load i64, ptr %$t512.addr
  %cr114 = call i64 @collatz(i64 %ld112, i64 %ld113)
  %cv115 = inttoptr i64 %cr114 to ptr
  store ptr %cv115, ptr %res_slot97
  br label %case_merge10
case_merge10:
  %case_r116 = load ptr, ptr %res_slot97
  store ptr %case_r116, ptr %res_slot88
  br label %case_merge7
case_merge7:
  %case_r117 = load ptr, ptr %res_slot88
  %cv118 = ptrtoint ptr %case_r117 to i64
  ret i64 %cv118
}

define i64 @max_collatz(i64 %lo.arg, i64 %hi.arg, i64 %threshold.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld119 = load i64, ptr %hi.addr
  %ld120 = load i64, ptr %lo.addr
  %ar121 = sub i64 %ld119, %ld120
  %$t513.addr = alloca i64
  store i64 %ar121, ptr %$t513.addr
  %ld122 = load i64, ptr %$t513.addr
  %ld123 = load i64, ptr %threshold.addr
  %cmp124 = icmp sle i64 %ld122, %ld123
  %ar125 = zext i1 %cmp124 to i64
  %$t514.addr = alloca i64
  store i64 %ar125, ptr %$t514.addr
  %ld126 = load i64, ptr %$t514.addr
  %res_slot127 = alloca ptr
  switch i64 %ld126, label %case_default14 [
      i64 1, label %case_br15
  ]
case_br15:
  %ld128 = load i64, ptr %lo.addr
  %ld129 = load i64, ptr %hi.addr
  %cr130 = call i64 @max_collatz_seq(i64 %ld128, i64 %ld129, i64 0)
  %cv131 = inttoptr i64 %cr130 to ptr
  store ptr %cv131, ptr %res_slot127
  br label %case_merge13
case_default14:
  %ld132 = load i64, ptr %hi.addr
  %ld133 = load i64, ptr %lo.addr
  %ar134 = sub i64 %ld132, %ld133
  %$t515.addr = alloca i64
  store i64 %ar134, ptr %$t515.addr
  %ld135 = load i64, ptr %$t515.addr
  %ar136 = sdiv i64 %ld135, 2
  %$t516.addr = alloca i64
  store i64 %ar136, ptr %$t516.addr
  %ld137 = load i64, ptr %lo.addr
  %ld138 = load i64, ptr %$t516.addr
  %ar139 = add i64 %ld137, %ld138
  %mid.addr = alloca i64
  store i64 %ar139, ptr %mid.addr
  %hp140 = call ptr @march_alloc(i64 48)
  %tgp141 = getelementptr i8, ptr %hp140, i64 8
  store i32 0, ptr %tgp141, align 4
  %fp142 = getelementptr i8, ptr %hp140, i64 16
  store ptr @$lam517$apply, ptr %fp142, align 8
  %ld143 = load i64, ptr %lo.addr
  %fp144 = getelementptr i8, ptr %hp140, i64 24
  store i64 %ld143, ptr %fp144, align 8
  %ld145 = load i64, ptr %mid.addr
  %fp146 = getelementptr i8, ptr %hp140, i64 32
  store i64 %ld145, ptr %fp146, align 8
  %ld147 = load i64, ptr %threshold.addr
  %fp148 = getelementptr i8, ptr %hp140, i64 40
  store i64 %ld147, ptr %fp148, align 8
  %$t518.addr = alloca ptr
  store ptr %hp140, ptr %$t518.addr
  %ld149 = load ptr, ptr %$t518.addr
  %fp150 = getelementptr i8, ptr %ld149, i64 16
  %fv151 = load ptr, ptr %fp150, align 8
  %tsres152 = call i64 %fv151(ptr %ld149, i64 0)
  %hp153 = call ptr @march_alloc(i64 24)
  %tgp154 = getelementptr i8, ptr %hp153, i64 8
  store i32 0, ptr %tgp154, align 4
  %fp155 = getelementptr i8, ptr %hp153, i64 16
  store i64 %tsres152, ptr %fp155, align 8
  %left.addr = alloca ptr
  store ptr %hp153, ptr %left.addr
  %hp156 = call ptr @march_alloc(i64 48)
  %tgp157 = getelementptr i8, ptr %hp156, i64 8
  store i32 0, ptr %tgp157, align 4
  %fp158 = getelementptr i8, ptr %hp156, i64 16
  store ptr @$lam519$apply, ptr %fp158, align 8
  %ld159 = load i64, ptr %hi.addr
  %fp160 = getelementptr i8, ptr %hp156, i64 24
  store i64 %ld159, ptr %fp160, align 8
  %ld161 = load i64, ptr %mid.addr
  %fp162 = getelementptr i8, ptr %hp156, i64 32
  store i64 %ld161, ptr %fp162, align 8
  %ld163 = load i64, ptr %threshold.addr
  %fp164 = getelementptr i8, ptr %hp156, i64 40
  store i64 %ld163, ptr %fp164, align 8
  %$t521.addr = alloca ptr
  store ptr %hp156, ptr %$t521.addr
  %ld165 = load ptr, ptr %$t521.addr
  %fp166 = getelementptr i8, ptr %ld165, i64 16
  %fv167 = load ptr, ptr %fp166, align 8
  %tsres168 = call i64 %fv167(ptr %ld165, i64 0)
  %hp169 = call ptr @march_alloc(i64 24)
  %tgp170 = getelementptr i8, ptr %hp169, i64 8
  store i32 0, ptr %tgp170, align 4
  %fp171 = getelementptr i8, ptr %hp169, i64 16
  store i64 %tsres168, ptr %fp171, align 8
  %right.addr = alloca ptr
  store ptr %hp169, ptr %right.addr
  %ld172 = load ptr, ptr %left.addr
  %fp173 = getelementptr i8, ptr %ld172, i64 16
  %fv174 = load i64, ptr %fp173, align 8
  %l.addr = alloca i64
  store i64 %fv174, ptr %l.addr
  %ld175 = load ptr, ptr %right.addr
  %fp176 = getelementptr i8, ptr %ld175, i64 16
  %fv177 = load i64, ptr %fp176, align 8
  %r.addr = alloca i64
  store i64 %fv177, ptr %r.addr
  %ld178 = load i64, ptr %l.addr
  %a_i1.addr = alloca i64
  store i64 %ld178, ptr %a_i1.addr
  %ld179 = load i64, ptr %r.addr
  %b_i2.addr = alloca i64
  store i64 %ld179, ptr %b_i2.addr
  %ld180 = load i64, ptr %a_i1.addr
  %ld181 = load i64, ptr %b_i2.addr
  %cmp182 = icmp sgt i64 %ld180, %ld181
  %ar183 = zext i1 %cmp182 to i64
  %$t504_i3.addr = alloca i64
  store i64 %ar183, ptr %$t504_i3.addr
  %ld184 = load i64, ptr %$t504_i3.addr
  %res_slot185 = alloca ptr
  switch i64 %ld184, label %case_default17 [
      i64 1, label %case_br18
  ]
case_br18:
  %ld186 = load i64, ptr %a_i1.addr
  %cv187 = inttoptr i64 %ld186 to ptr
  store ptr %cv187, ptr %res_slot185
  br label %case_merge16
case_default17:
  %ld188 = load i64, ptr %b_i2.addr
  %cv189 = inttoptr i64 %ld188 to ptr
  store ptr %cv189, ptr %res_slot185
  br label %case_merge16
case_merge16:
  %case_r190 = load ptr, ptr %res_slot185
  store ptr %case_r190, ptr %res_slot127
  br label %case_merge13
case_merge13:
  %case_r191 = load ptr, ptr %res_slot127
  %cv192 = ptrtoint ptr %case_r191 to i64
  ret i64 %cv192
}

define i64 @max_collatz_seq(i64 %lo.arg, i64 %hi.arg, i64 %best.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %best.addr = alloca i64
  store i64 %best.arg, ptr %best.addr
  %ld193 = load i64, ptr %lo.addr
  %ld194 = load i64, ptr %hi.addr
  %cmp195 = icmp sgt i64 %ld193, %ld194
  %ar196 = zext i1 %cmp195 to i64
  %$t522.addr = alloca i64
  store i64 %ar196, ptr %$t522.addr
  %ld197 = load i64, ptr %$t522.addr
  %res_slot198 = alloca ptr
  switch i64 %ld197, label %case_default20 [
      i64 1, label %case_br21
  ]
case_br21:
  %ld199 = load i64, ptr %best.addr
  %cv200 = inttoptr i64 %ld199 to ptr
  store ptr %cv200, ptr %res_slot198
  br label %case_merge19
case_default20:
  %ld201 = load i64, ptr %lo.addr
  %cr202 = call i64 @collatz(i64 %ld201, i64 0)
  %steps.addr = alloca i64
  store i64 %cr202, ptr %steps.addr
  %ld203 = load i64, ptr %lo.addr
  %ar204 = add i64 %ld203, 1
  %$t523.addr = alloca i64
  store i64 %ar204, ptr %$t523.addr
  %ld205 = load i64, ptr %steps.addr
  %a_i4.addr = alloca i64
  store i64 %ld205, ptr %a_i4.addr
  %ld206 = load i64, ptr %best.addr
  %b_i5.addr = alloca i64
  store i64 %ld206, ptr %b_i5.addr
  %ld207 = load i64, ptr %a_i4.addr
  %ld208 = load i64, ptr %b_i5.addr
  %cmp209 = icmp sgt i64 %ld207, %ld208
  %ar210 = zext i1 %cmp209 to i64
  %$t504_i6.addr = alloca i64
  store i64 %ar210, ptr %$t504_i6.addr
  %ld211 = load i64, ptr %$t504_i6.addr
  %res_slot212 = alloca ptr
  switch i64 %ld211, label %case_default23 [
      i64 1, label %case_br24
  ]
case_br24:
  %ld213 = load i64, ptr %a_i4.addr
  %cv214 = inttoptr i64 %ld213 to ptr
  store ptr %cv214, ptr %res_slot212
  br label %case_merge22
case_default23:
  %ld215 = load i64, ptr %b_i5.addr
  %cv216 = inttoptr i64 %ld215 to ptr
  store ptr %cv216, ptr %res_slot212
  br label %case_merge22
case_merge22:
  %case_r217 = load ptr, ptr %res_slot212
  %cv218 = ptrtoint ptr %case_r217 to i64
  %$t524.addr = alloca i64
  store i64 %cv218, ptr %$t524.addr
  %ld219 = load i64, ptr %$t523.addr
  %ld220 = load i64, ptr %hi.addr
  %ld221 = load i64, ptr %$t524.addr
  %cr222 = call i64 @max_collatz_seq(i64 %ld219, i64 %ld220, i64 %ld221)
  %cv223 = inttoptr i64 %cr222 to ptr
  store ptr %cv223, ptr %res_slot198
  br label %case_merge19
case_merge19:
  %case_r224 = load ptr, ptr %res_slot198
  %cv225 = ptrtoint ptr %case_r224 to i64
  ret i64 %cv225
}

define void @march_main() {
entry:
  %sl226 = call ptr @march_string_lit(ptr @.str1, i64 26)
  call void @march_println(ptr %sl226)
  %cr227 = call i64 @par_sum(i64 1, i64 10000, i64 500)
  %total.addr = alloca i64
  store i64 %cr227, ptr %total.addr
  %ld228 = load i64, ptr %total.addr
  %cr229 = call ptr @march_int_to_string(i64 %ld228)
  %$t525.addr = alloca ptr
  store ptr %cr229, ptr %$t525.addr
  %sl230 = call ptr @march_string_lit(ptr @.str2, i64 20)
  %ld231 = load ptr, ptr %$t525.addr
  %cr232 = call ptr @march_string_concat(ptr %sl230, ptr %ld231)
  %$t526.addr = alloca ptr
  store ptr %cr232, ptr %$t526.addr
  %ld233 = load ptr, ptr %$t526.addr
  call void @march_println(ptr %ld233)
  %cr234 = call i64 @max_collatz(i64 1, i64 10000, i64 500)
  %max_steps.addr = alloca i64
  store i64 %cr234, ptr %max_steps.addr
  %ld235 = load i64, ptr %max_steps.addr
  %cr236 = call ptr @march_int_to_string(i64 %ld235)
  %$t527.addr = alloca ptr
  store ptr %cr236, ptr %$t527.addr
  %sl237 = call ptr @march_string_lit(ptr @.str3, i64 32)
  %ld238 = load ptr, ptr %$t527.addr
  %cr239 = call ptr @march_string_concat(ptr %sl237, ptr %ld238)
  %$t528.addr = alloca ptr
  store ptr %cr239, ptr %$t528.addr
  %ld240 = load ptr, ptr %$t528.addr
  call void @march_println(ptr %ld240)
  ret void
}

define i64 @$lam499$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld241 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld241)
  %ld242 = load ptr, ptr %$clo.addr
  %fp243 = getelementptr i8, ptr %ld242, i64 24
  %fv244 = load ptr, ptr %fp243, align 8
  %cv245 = ptrtoint ptr %fv244 to i64
  %lo.addr = alloca i64
  store i64 %cv245, ptr %lo.addr
  %ld246 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld246)
  %ld247 = load ptr, ptr %$clo.addr
  %fp248 = getelementptr i8, ptr %ld247, i64 32
  %fv249 = load ptr, ptr %fp248, align 8
  %cv250 = ptrtoint ptr %fv249 to i64
  %mid.addr = alloca i64
  store i64 %cv250, ptr %mid.addr
  %ld251 = load ptr, ptr %$clo.addr
  %fp252 = getelementptr i8, ptr %ld251, i64 40
  %fv253 = load i64, ptr %fp252, align 8
  %threshold.addr = alloca i64
  store i64 %fv253, ptr %threshold.addr
  %ld254 = load i64, ptr %lo.addr
  %ld255 = load i64, ptr %mid.addr
  %ld256 = load i64, ptr %threshold.addr
  %cr257 = call i64 @par_sum(i64 %ld254, i64 %ld255, i64 %ld256)
  ret i64 %cr257
}

define i64 @$lam501$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld258 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld258)
  %ld259 = load ptr, ptr %$clo.addr
  %fp260 = getelementptr i8, ptr %ld259, i64 24
  %fv261 = load ptr, ptr %fp260, align 8
  %cv262 = ptrtoint ptr %fv261 to i64
  %hi.addr = alloca i64
  store i64 %cv262, ptr %hi.addr
  %ld263 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld263)
  %ld264 = load ptr, ptr %$clo.addr
  %fp265 = getelementptr i8, ptr %ld264, i64 32
  %fv266 = load ptr, ptr %fp265, align 8
  %cv267 = ptrtoint ptr %fv266 to i64
  %mid.addr = alloca i64
  store i64 %cv267, ptr %mid.addr
  %ld268 = load ptr, ptr %$clo.addr
  %fp269 = getelementptr i8, ptr %ld268, i64 40
  %fv270 = load i64, ptr %fp269, align 8
  %threshold.addr = alloca i64
  store i64 %fv270, ptr %threshold.addr
  %ld271 = load i64, ptr %mid.addr
  %ar272 = add i64 %ld271, 1
  %$t502.addr = alloca i64
  store i64 %ar272, ptr %$t502.addr
  %ld273 = load i64, ptr %$t502.addr
  %ld274 = load i64, ptr %hi.addr
  %ld275 = load i64, ptr %threshold.addr
  %cr276 = call i64 @par_sum(i64 %ld273, i64 %ld274, i64 %ld275)
  ret i64 %cr276
}

define i64 @$lam517$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld277 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld277)
  %ld278 = load ptr, ptr %$clo.addr
  %fp279 = getelementptr i8, ptr %ld278, i64 24
  %fv280 = load ptr, ptr %fp279, align 8
  %cv281 = ptrtoint ptr %fv280 to i64
  %lo.addr = alloca i64
  store i64 %cv281, ptr %lo.addr
  %ld282 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld282)
  %ld283 = load ptr, ptr %$clo.addr
  %fp284 = getelementptr i8, ptr %ld283, i64 32
  %fv285 = load ptr, ptr %fp284, align 8
  %cv286 = ptrtoint ptr %fv285 to i64
  %mid.addr = alloca i64
  store i64 %cv286, ptr %mid.addr
  %ld287 = load ptr, ptr %$clo.addr
  %fp288 = getelementptr i8, ptr %ld287, i64 40
  %fv289 = load i64, ptr %fp288, align 8
  %threshold.addr = alloca i64
  store i64 %fv289, ptr %threshold.addr
  %ld290 = load i64, ptr %lo.addr
  %ld291 = load i64, ptr %mid.addr
  %ld292 = load i64, ptr %threshold.addr
  %cr293 = call i64 @max_collatz(i64 %ld290, i64 %ld291, i64 %ld292)
  ret i64 %cr293
}

define i64 @$lam519$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld294 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld294)
  %ld295 = load ptr, ptr %$clo.addr
  %fp296 = getelementptr i8, ptr %ld295, i64 24
  %fv297 = load ptr, ptr %fp296, align 8
  %cv298 = ptrtoint ptr %fv297 to i64
  %hi.addr = alloca i64
  store i64 %cv298, ptr %hi.addr
  %ld299 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld299)
  %ld300 = load ptr, ptr %$clo.addr
  %fp301 = getelementptr i8, ptr %ld300, i64 32
  %fv302 = load ptr, ptr %fp301, align 8
  %cv303 = ptrtoint ptr %fv302 to i64
  %mid.addr = alloca i64
  store i64 %cv303, ptr %mid.addr
  %ld304 = load ptr, ptr %$clo.addr
  %fp305 = getelementptr i8, ptr %ld304, i64 40
  %fv306 = load i64, ptr %fp305, align 8
  %threshold.addr = alloca i64
  store i64 %fv306, ptr %threshold.addr
  %ld307 = load i64, ptr %mid.addr
  %ar308 = add i64 %ld307, 1
  %$t520.addr = alloca i64
  store i64 %ar308, ptr %$t520.addr
  %ld309 = load i64, ptr %$t520.addr
  %ld310 = load i64, ptr %hi.addr
  %ld311 = load i64, ptr %threshold.addr
  %cr312 = call i64 @max_collatz(i64 %ld309, i64 %ld310, i64 %ld311)
  ret i64 %cr312
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
