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
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)

@.str1 = private unnamed_addr constant [2 x i8] c"[\00"
@.str2 = private unnamed_addr constant [3 x i8] c", \00"
@.str3 = private unnamed_addr constant [2 x i8] c"]\00"
@.str4 = private unnamed_addr constant [3 x i8] c", \00"
@.str5 = private unnamed_addr constant [5 x i8] c"None\00"
@.str6 = private unnamed_addr constant [6 x i8] c"Some(\00"
@.str7 = private unnamed_addr constant [2 x i8] c")\00"
@.str8 = private unnamed_addr constant [1 x i8] c"\00"
@.str9 = private unnamed_addr constant [12 x i8] c"doubled:   \00"
@.str10 = private unnamed_addr constant [1 x i8] c"\00"
@.str11 = private unnamed_addr constant [12 x i8] c"evens:     \00"
@.str12 = private unnamed_addr constant [1 x i8] c"\00"
@.str13 = private unnamed_addr constant [14 x i8] c"sum 1..10  = \00"
@.str14 = private unnamed_addr constant [14 x i8] c"5!         = \00"
@.str15 = private unnamed_addr constant [12 x i8] c"reverse:   \00"
@.str16 = private unnamed_addr constant [1 x i8] c"\00"
@.str17 = private unnamed_addr constant [12 x i8] c"find >7:   \00"
@.str18 = private unnamed_addr constant [12 x i8] c"find >100: \00"
@.str19 = private unnamed_addr constant [12 x i8] c"length:    \00"

define i64 @length(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld1 = load ptr, ptr %lst.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %cv5 = inttoptr i64 0 to ptr
  store ptr %cv5, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp6 = getelementptr i8, ptr %ld1, i64 16
  %fv7 = load ptr, ptr %fp6, align 8
  %$w17.addr = alloca ptr
  store ptr %fv7, ptr %$w17.addr
  %fp8 = getelementptr i8, ptr %ld1, i64 24
  %fv9 = load ptr, ptr %fp8, align 8
  %t.addr = alloca ptr
  store ptr %fv9, ptr %t.addr
  %ld10 = load ptr, ptr %t.addr
  %cr11 = call i64 @length(ptr %ld10)
  %$t18.addr = alloca i64
  store i64 %cr11, ptr %$t18.addr
  %ld12 = load i64, ptr %$t18.addr
  %ar13 = add i64 1, %ld12
  %cv14 = inttoptr i64 %ar13 to ptr
  store ptr %cv14, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r15 = load ptr, ptr %res_slot2
  %cv16 = ptrtoint ptr %case_r15 to i64
  ret i64 %cv16
}

define ptr @map(ptr %f.arg, ptr %lst.arg) {
entry:
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld17 = load ptr, ptr %lst.addr
  %res_slot18 = alloca ptr
  %tgp19 = getelementptr i8, ptr %ld17, i64 8
  %tag20 = load i32, ptr %tgp19, align 4
  switch i32 %tag20, label %case_default6 [
      i32 0, label %case_br7
      i32 1, label %case_br8
  ]
case_br7:
  %hp21 = call ptr @march_alloc(i64 16)
  %tgp22 = getelementptr i8, ptr %hp21, i64 8
  store i32 0, ptr %tgp22, align 4
  store ptr %hp21, ptr %res_slot18
  br label %case_merge5
case_br8:
  %fp23 = getelementptr i8, ptr %ld17, i64 16
  %fv24 = load ptr, ptr %fp23, align 8
  %h.addr = alloca ptr
  store ptr %fv24, ptr %h.addr
  %fp25 = getelementptr i8, ptr %ld17, i64 24
  %fv26 = load ptr, ptr %fp25, align 8
  %t.addr = alloca ptr
  store ptr %fv26, ptr %t.addr
  %ld27 = load ptr, ptr %f.addr
  %fp28 = getelementptr i8, ptr %ld27, i64 16
  %fv29 = load ptr, ptr %fp28, align 8
  %ld30 = load i64, ptr %h.addr
  %cr31 = call i64 (ptr, i64) %fv29(ptr %ld27, i64 %ld30)
  %$t19.addr = alloca i64
  store i64 %cr31, ptr %$t19.addr
  %ld32 = load ptr, ptr %f.addr
  %ld33 = load ptr, ptr %t.addr
  %cr34 = call ptr @map(ptr %ld32, ptr %ld33)
  %$t20.addr = alloca ptr
  store ptr %cr34, ptr %$t20.addr
  %hp35 = call ptr @march_alloc(i64 32)
  %tgp36 = getelementptr i8, ptr %hp35, i64 8
  store i32 1, ptr %tgp36, align 4
  %ld37 = load i64, ptr %$t19.addr
  %cv38 = inttoptr i64 %ld37 to ptr
  %fp39 = getelementptr i8, ptr %hp35, i64 16
  store ptr %cv38, ptr %fp39, align 8
  %ld40 = load ptr, ptr %$t20.addr
  %fp41 = getelementptr i8, ptr %hp35, i64 24
  store ptr %ld40, ptr %fp41, align 8
  store ptr %hp35, ptr %res_slot18
  br label %case_merge5
case_default6:
  unreachable
case_merge5:
  %case_r42 = load ptr, ptr %res_slot18
  ret ptr %case_r42
}

define ptr @filter(ptr %pred.arg, ptr %lst.arg) {
entry:
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld43 = load ptr, ptr %lst.addr
  %res_slot44 = alloca ptr
  %tgp45 = getelementptr i8, ptr %ld43, i64 8
  %tag46 = load i32, ptr %tgp45, align 4
  switch i32 %tag46, label %case_default10 [
      i32 0, label %case_br11
      i32 1, label %case_br12
  ]
case_br11:
  %hp47 = call ptr @march_alloc(i64 16)
  %tgp48 = getelementptr i8, ptr %hp47, i64 8
  store i32 0, ptr %tgp48, align 4
  store ptr %hp47, ptr %res_slot44
  br label %case_merge9
case_br12:
  %fp49 = getelementptr i8, ptr %ld43, i64 16
  %fv50 = load ptr, ptr %fp49, align 8
  %h.addr = alloca ptr
  store ptr %fv50, ptr %h.addr
  %fp51 = getelementptr i8, ptr %ld43, i64 24
  %fv52 = load ptr, ptr %fp51, align 8
  %t.addr = alloca ptr
  store ptr %fv52, ptr %t.addr
  %ld53 = load ptr, ptr %pred.addr
  %fp54 = getelementptr i8, ptr %ld53, i64 16
  %fv55 = load ptr, ptr %fp54, align 8
  %ld56 = load i64, ptr %h.addr
  %cr57 = call i64 (ptr, i64) %fv55(ptr %ld53, i64 %ld56)
  %$t21.addr = alloca i64
  store i64 %cr57, ptr %$t21.addr
  %ld58 = load i64, ptr %$t21.addr
  %res_slot59 = alloca ptr
  switch i64 %ld58, label %case_default14 [
      i64 1, label %case_br15
  ]
case_br15:
  %ld60 = load ptr, ptr %pred.addr
  %ld61 = load ptr, ptr %t.addr
  %cr62 = call ptr @filter(ptr %ld60, ptr %ld61)
  %$t22.addr = alloca ptr
  store ptr %cr62, ptr %$t22.addr
  %hp63 = call ptr @march_alloc(i64 32)
  %tgp64 = getelementptr i8, ptr %hp63, i64 8
  store i32 1, ptr %tgp64, align 4
  %ld65 = load i64, ptr %h.addr
  %cv66 = inttoptr i64 %ld65 to ptr
  %fp67 = getelementptr i8, ptr %hp63, i64 16
  store ptr %cv66, ptr %fp67, align 8
  %ld68 = load ptr, ptr %$t22.addr
  %fp69 = getelementptr i8, ptr %hp63, i64 24
  store ptr %ld68, ptr %fp69, align 8
  store ptr %hp63, ptr %res_slot59
  br label %case_merge13
case_default14:
  %ld70 = load ptr, ptr %pred.addr
  %ld71 = load ptr, ptr %t.addr
  %cr72 = call ptr @filter(ptr %ld70, ptr %ld71)
  store ptr %cr72, ptr %res_slot59
  br label %case_merge13
case_merge13:
  %case_r73 = load ptr, ptr %res_slot59
  store ptr %case_r73, ptr %res_slot44
  br label %case_merge9
case_default10:
  unreachable
case_merge9:
  %case_r74 = load ptr, ptr %res_slot44
  ret ptr %case_r74
}

define i64 @fold_left(ptr %f.arg, i64 %acc.arg, ptr %lst.arg) {
entry:
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld75 = load ptr, ptr %lst.addr
  %res_slot76 = alloca ptr
  %tgp77 = getelementptr i8, ptr %ld75, i64 8
  %tag78 = load i32, ptr %tgp77, align 4
  switch i32 %tag78, label %case_default17 [
      i32 0, label %case_br18
      i32 1, label %case_br19
  ]
case_br18:
  %ld79 = load i64, ptr %acc.addr
  %cv80 = inttoptr i64 %ld79 to ptr
  store ptr %cv80, ptr %res_slot76
  br label %case_merge16
case_br19:
  %fp81 = getelementptr i8, ptr %ld75, i64 16
  %fv82 = load ptr, ptr %fp81, align 8
  %h.addr = alloca ptr
  store ptr %fv82, ptr %h.addr
  %fp83 = getelementptr i8, ptr %ld75, i64 24
  %fv84 = load ptr, ptr %fp83, align 8
  %t.addr = alloca ptr
  store ptr %fv84, ptr %t.addr
  %ld85 = load ptr, ptr %f.addr
  %fp86 = getelementptr i8, ptr %ld85, i64 16
  %fv87 = load ptr, ptr %fp86, align 8
  %ld88 = load i64, ptr %acc.addr
  %ld89 = load i64, ptr %h.addr
  %cr90 = call i64 (ptr, i64, i64) %fv87(ptr %ld85, i64 %ld88, i64 %ld89)
  %$t23.addr = alloca i64
  store i64 %cr90, ptr %$t23.addr
  %ld91 = load ptr, ptr %f.addr
  %ld92 = load i64, ptr %$t23.addr
  %ld93 = load ptr, ptr %t.addr
  %cr94 = call i64 @fold_left(ptr %ld91, i64 %ld92, ptr %ld93)
  %cv95 = inttoptr i64 %cr94 to ptr
  store ptr %cv95, ptr %res_slot76
  br label %case_merge16
case_default17:
  unreachable
case_merge16:
  %case_r96 = load ptr, ptr %res_slot76
  %cv97 = ptrtoint ptr %case_r96 to i64
  ret i64 %cv97
}

define ptr @reverse_acc(ptr %lst.arg, ptr %acc.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld98 = load ptr, ptr %lst.addr
  %res_slot99 = alloca ptr
  %tgp100 = getelementptr i8, ptr %ld98, i64 8
  %tag101 = load i32, ptr %tgp100, align 4
  switch i32 %tag101, label %case_default21 [
      i32 0, label %case_br22
      i32 1, label %case_br23
  ]
case_br22:
  %ld102 = load ptr, ptr %acc.addr
  store ptr %ld102, ptr %res_slot99
  br label %case_merge20
case_br23:
  %fp103 = getelementptr i8, ptr %ld98, i64 16
  %fv104 = load ptr, ptr %fp103, align 8
  %h.addr = alloca ptr
  store ptr %fv104, ptr %h.addr
  %fp105 = getelementptr i8, ptr %ld98, i64 24
  %fv106 = load ptr, ptr %fp105, align 8
  %t.addr = alloca ptr
  store ptr %fv106, ptr %t.addr
  %hp107 = call ptr @march_alloc(i64 32)
  %tgp108 = getelementptr i8, ptr %hp107, i64 8
  store i32 1, ptr %tgp108, align 4
  %ld109 = load i64, ptr %h.addr
  %cv110 = inttoptr i64 %ld109 to ptr
  %fp111 = getelementptr i8, ptr %hp107, i64 16
  store ptr %cv110, ptr %fp111, align 8
  %ld112 = load ptr, ptr %acc.addr
  %fp113 = getelementptr i8, ptr %hp107, i64 24
  store ptr %ld112, ptr %fp113, align 8
  %$t29.addr = alloca ptr
  store ptr %hp107, ptr %$t29.addr
  %ld114 = load ptr, ptr %t.addr
  %ld115 = load ptr, ptr %$t29.addr
  %cr116 = call ptr @reverse_acc(ptr %ld114, ptr %ld115)
  store ptr %cr116, ptr %res_slot99
  br label %case_merge20
case_default21:
  unreachable
case_merge20:
  %case_r117 = load ptr, ptr %res_slot99
  ret ptr %case_r117
}

define ptr @find(ptr %pred.arg, ptr %lst.arg) {
entry:
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld118 = load ptr, ptr %lst.addr
  %res_slot119 = alloca ptr
  %tgp120 = getelementptr i8, ptr %ld118, i64 8
  %tag121 = load i32, ptr %tgp120, align 4
  switch i32 %tag121, label %case_default25 [
      i32 0, label %case_br26
      i32 1, label %case_br27
  ]
case_br26:
  %hp122 = call ptr @march_alloc(i64 16)
  %tgp123 = getelementptr i8, ptr %hp122, i64 8
  store i32 0, ptr %tgp123, align 4
  store ptr %hp122, ptr %res_slot119
  br label %case_merge24
case_br27:
  %fp124 = getelementptr i8, ptr %ld118, i64 16
  %fv125 = load ptr, ptr %fp124, align 8
  %h.addr = alloca ptr
  store ptr %fv125, ptr %h.addr
  %fp126 = getelementptr i8, ptr %ld118, i64 24
  %fv127 = load ptr, ptr %fp126, align 8
  %t.addr = alloca ptr
  store ptr %fv127, ptr %t.addr
  %ld128 = load ptr, ptr %pred.addr
  %fp129 = getelementptr i8, ptr %ld128, i64 16
  %fv130 = load ptr, ptr %fp129, align 8
  %ld131 = load i64, ptr %h.addr
  %cr132 = call i64 (ptr, i64) %fv130(ptr %ld128, i64 %ld131)
  %$t31.addr = alloca i64
  store i64 %cr132, ptr %$t31.addr
  %ld133 = load i64, ptr %$t31.addr
  %res_slot134 = alloca ptr
  switch i64 %ld133, label %case_default29 [
      i64 1, label %case_br30
  ]
case_br30:
  %hp135 = call ptr @march_alloc(i64 24)
  %tgp136 = getelementptr i8, ptr %hp135, i64 8
  store i32 1, ptr %tgp136, align 4
  %ld137 = load i64, ptr %h.addr
  %cv138 = inttoptr i64 %ld137 to ptr
  %fp139 = getelementptr i8, ptr %hp135, i64 16
  store ptr %cv138, ptr %fp139, align 8
  store ptr %hp135, ptr %res_slot134
  br label %case_merge28
case_default29:
  %ld140 = load ptr, ptr %pred.addr
  %ld141 = load ptr, ptr %t.addr
  %cr142 = call ptr @find(ptr %ld140, ptr %ld141)
  store ptr %cr142, ptr %res_slot134
  br label %case_merge28
case_merge28:
  %case_r143 = load ptr, ptr %res_slot134
  store ptr %case_r143, ptr %res_slot119
  br label %case_merge24
case_default25:
  unreachable
case_merge24:
  %case_r144 = load ptr, ptr %res_slot119
  ret ptr %case_r144
}

define ptr @range(i64 %lo.arg, i64 %hi.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %ld145 = load i64, ptr %lo.addr
  %ld146 = load i64, ptr %hi.addr
  %cmp147 = icmp sgt i64 %ld145, %ld146
  %ar148 = zext i1 %cmp147 to i64
  %$t32.addr = alloca i64
  store i64 %ar148, ptr %$t32.addr
  %ld149 = load i64, ptr %$t32.addr
  %res_slot150 = alloca ptr
  switch i64 %ld149, label %case_default32 [
      i64 1, label %case_br33
  ]
case_br33:
  %hp151 = call ptr @march_alloc(i64 16)
  %tgp152 = getelementptr i8, ptr %hp151, i64 8
  store i32 0, ptr %tgp152, align 4
  store ptr %hp151, ptr %res_slot150
  br label %case_merge31
case_default32:
  %ld153 = load i64, ptr %lo.addr
  %ar154 = add i64 %ld153, 1
  %$t33.addr = alloca i64
  store i64 %ar154, ptr %$t33.addr
  %ld155 = load i64, ptr %$t33.addr
  %ld156 = load i64, ptr %hi.addr
  %cr157 = call ptr @range(i64 %ld155, i64 %ld156)
  %$t34.addr = alloca ptr
  store ptr %cr157, ptr %$t34.addr
  %hp158 = call ptr @march_alloc(i64 32)
  %tgp159 = getelementptr i8, ptr %hp158, i64 8
  store i32 1, ptr %tgp159, align 4
  %ld160 = load i64, ptr %lo.addr
  %cv161 = inttoptr i64 %ld160 to ptr
  %fp162 = getelementptr i8, ptr %hp158, i64 16
  store ptr %cv161, ptr %fp162, align 8
  %ld163 = load ptr, ptr %$t34.addr
  %fp164 = getelementptr i8, ptr %hp158, i64 24
  store ptr %ld163, ptr %fp164, align 8
  store ptr %hp158, ptr %res_slot150
  br label %case_merge31
case_merge31:
  %case_r165 = load ptr, ptr %res_slot150
  ret ptr %case_r165
}

define void @print_list(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %sl166 = call ptr @march_string_lit(ptr @.str1, i64 1)
  call void @march_print(ptr %sl166)
  %ld167 = load ptr, ptr %lst.addr
  %res_slot168 = alloca ptr
  %tgp169 = getelementptr i8, ptr %ld167, i64 8
  %tag170 = load i32, ptr %tgp169, align 4
  switch i32 %tag170, label %case_default35 [
      i32 0, label %case_br36
      i32 1, label %case_br37
  ]
case_br36:
  %cv171 = inttoptr i64 0 to ptr
  store ptr %cv171, ptr %res_slot168
  br label %case_merge34
case_br37:
  %fp172 = getelementptr i8, ptr %ld167, i64 16
  %fv173 = load ptr, ptr %fp172, align 8
  %h.addr = alloca ptr
  store ptr %fv173, ptr %h.addr
  %fp174 = getelementptr i8, ptr %ld167, i64 24
  %fv175 = load ptr, ptr %fp174, align 8
  %t.addr = alloca ptr
  store ptr %fv175, ptr %t.addr
  %ld176 = load i64, ptr %h.addr
  %cr177 = call ptr @march_int_to_string(i64 %ld176)
  %$t35.addr = alloca ptr
  store ptr %cr177, ptr %$t35.addr
  %ld178 = load ptr, ptr %$t35.addr
  call void @march_print(ptr %ld178)
  %ld179 = load ptr, ptr %t.addr
  %res_slot180 = alloca ptr
  %tgp181 = getelementptr i8, ptr %ld179, i64 8
  %tag182 = load i32, ptr %tgp181, align 4
  switch i32 %tag182, label %case_default39 [
      i32 0, label %case_br40
  ]
case_br40:
  %cv183 = inttoptr i64 0 to ptr
  store ptr %cv183, ptr %res_slot180
  br label %case_merge38
case_default39:
  %sl184 = call ptr @march_string_lit(ptr @.str2, i64 2)
  call void @march_print(ptr %sl184)
  %ld185 = load ptr, ptr %t.addr
  %cr186 = call ptr @print_list_tail(ptr %ld185)
  store ptr %cr186, ptr %res_slot180
  br label %case_merge38
case_merge38:
  %case_r187 = load ptr, ptr %res_slot180
  store ptr %case_r187, ptr %res_slot168
  br label %case_merge34
case_default35:
  unreachable
case_merge34:
  %case_r188 = load ptr, ptr %res_slot168
  %sl189 = call ptr @march_string_lit(ptr @.str3, i64 1)
  call void @march_print(ptr %sl189)
  ret void
}

define void @print_list_tail(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld190 = load ptr, ptr %lst.addr
  %res_slot191 = alloca ptr
  %tgp192 = getelementptr i8, ptr %ld190, i64 8
  %tag193 = load i32, ptr %tgp192, align 4
  switch i32 %tag193, label %case_default42 [
      i32 0, label %case_br43
      i32 1, label %case_br44
  ]
case_br43:
  %cv194 = inttoptr i64 0 to ptr
  store ptr %cv194, ptr %res_slot191
  br label %case_merge41
case_br44:
  %fp195 = getelementptr i8, ptr %ld190, i64 16
  %fv196 = load ptr, ptr %fp195, align 8
  %h.addr = alloca ptr
  store ptr %fv196, ptr %h.addr
  %fp197 = getelementptr i8, ptr %ld190, i64 24
  %fv198 = load ptr, ptr %fp197, align 8
  %t.addr = alloca ptr
  store ptr %fv198, ptr %t.addr
  %ld199 = load i64, ptr %h.addr
  %cr200 = call ptr @march_int_to_string(i64 %ld199)
  %$t36.addr = alloca ptr
  store ptr %cr200, ptr %$t36.addr
  %ld201 = load ptr, ptr %$t36.addr
  call void @march_print(ptr %ld201)
  %ld202 = load ptr, ptr %t.addr
  %res_slot203 = alloca ptr
  %tgp204 = getelementptr i8, ptr %ld202, i64 8
  %tag205 = load i32, ptr %tgp204, align 4
  switch i32 %tag205, label %case_default46 [
      i32 0, label %case_br47
  ]
case_br47:
  %cv206 = inttoptr i64 0 to ptr
  store ptr %cv206, ptr %res_slot203
  br label %case_merge45
case_default46:
  %sl207 = call ptr @march_string_lit(ptr @.str4, i64 2)
  call void @march_print(ptr %sl207)
  %ld208 = load ptr, ptr %t.addr
  %cr209 = call ptr @print_list_tail(ptr %ld208)
  store ptr %cr209, ptr %res_slot203
  br label %case_merge45
case_merge45:
  %case_r210 = load ptr, ptr %res_slot203
  store ptr %case_r210, ptr %res_slot191
  br label %case_merge41
case_default42:
  unreachable
case_merge41:
  %case_r211 = load ptr, ptr %res_slot191
  ret void
}

define ptr @option_to_string(ptr %o.arg) {
entry:
  %o.addr = alloca ptr
  store ptr %o.arg, ptr %o.addr
  %ld212 = load ptr, ptr %o.addr
  %res_slot213 = alloca ptr
  %tgp214 = getelementptr i8, ptr %ld212, i64 8
  %tag215 = load i32, ptr %tgp214, align 4
  switch i32 %tag215, label %case_default49 [
      i32 0, label %case_br50
      i32 1, label %case_br51
  ]
case_br50:
  %sl216 = call ptr @march_string_lit(ptr @.str5, i64 4)
  store ptr %sl216, ptr %res_slot213
  br label %case_merge48
case_br51:
  %fp217 = getelementptr i8, ptr %ld212, i64 16
  %fv218 = load ptr, ptr %fp217, align 8
  %x.addr = alloca ptr
  store ptr %fv218, ptr %x.addr
  %ld219 = load i64, ptr %x.addr
  %cr220 = call ptr @march_int_to_string(i64 %ld219)
  %$t37.addr = alloca ptr
  store ptr %cr220, ptr %$t37.addr
  %sl221 = call ptr @march_string_lit(ptr @.str6, i64 5)
  %ld222 = load ptr, ptr %$t37.addr
  %cr223 = call ptr @march_string_concat(ptr %sl221, ptr %ld222)
  %$t38.addr = alloca ptr
  store ptr %cr223, ptr %$t38.addr
  %ld224 = load ptr, ptr %$t38.addr
  %sl225 = call ptr @march_string_lit(ptr @.str7, i64 1)
  %cr226 = call ptr @march_string_concat(ptr %ld224, ptr %sl225)
  store ptr %cr226, ptr %res_slot213
  br label %case_merge48
case_default49:
  unreachable
case_merge48:
  %case_r227 = load ptr, ptr %res_slot213
  ret ptr %case_r227
}

define void @march_main() {
entry:
  %cr228 = call ptr @range(i64 1, i64 10)
  %nums.addr = alloca ptr
  store ptr %cr228, ptr %nums.addr
  %ld229 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld229)
  %ld230 = load ptr, ptr %nums.addr
  %cr231 = call ptr @print_list(ptr %ld230)
  %sl232 = call ptr @march_string_lit(ptr @.str8, i64 0)
  call void @march_println(ptr %sl232)
  %hp233 = call ptr @march_alloc(i64 24)
  %tgp234 = getelementptr i8, ptr %hp233, i64 8
  store i32 0, ptr %tgp234, align 4
  %ld235 = load ptr, ptr %$lam39$apply.addr
  %fp236 = getelementptr i8, ptr %hp233, i64 16
  store ptr %ld235, ptr %fp236, align 8
  %$t40.addr = alloca ptr
  store ptr %hp233, ptr %$t40.addr
  %ld237 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld237)
  %ld238 = load ptr, ptr %$t40.addr
  %ld239 = load ptr, ptr %nums.addr
  %cr240 = call ptr @map(ptr %ld238, ptr %ld239)
  %doubled.addr = alloca ptr
  store ptr %cr240, ptr %doubled.addr
  %sl241 = call ptr @march_string_lit(ptr @.str9, i64 11)
  call void @march_print(ptr %sl241)
  %ld242 = load ptr, ptr %doubled.addr
  %cr243 = call ptr @print_list(ptr %ld242)
  %sl244 = call ptr @march_string_lit(ptr @.str10, i64 0)
  call void @march_println(ptr %sl244)
  %hp245 = call ptr @march_alloc(i64 24)
  %tgp246 = getelementptr i8, ptr %hp245, i64 8
  store i32 0, ptr %tgp246, align 4
  %ld247 = load ptr, ptr %$lam41$apply.addr
  %fp248 = getelementptr i8, ptr %hp245, i64 16
  store ptr %ld247, ptr %fp248, align 8
  %$t43.addr = alloca ptr
  store ptr %hp245, ptr %$t43.addr
  %ld249 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld249)
  %ld250 = load ptr, ptr %$t43.addr
  %ld251 = load ptr, ptr %nums.addr
  %cr252 = call ptr @filter(ptr %ld250, ptr %ld251)
  %evens.addr = alloca ptr
  store ptr %cr252, ptr %evens.addr
  %sl253 = call ptr @march_string_lit(ptr @.str11, i64 11)
  call void @march_print(ptr %sl253)
  %ld254 = load ptr, ptr %evens.addr
  %cr255 = call ptr @print_list(ptr %ld254)
  %sl256 = call ptr @march_string_lit(ptr @.str12, i64 0)
  call void @march_println(ptr %sl256)
  %ld257 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld257)
  %ld258 = load ptr, ptr %nums.addr
  %lst_i5.addr = alloca ptr
  store ptr %ld258, ptr %lst_i5.addr
  %hp259 = call ptr @march_alloc(i64 24)
  %tgp260 = getelementptr i8, ptr %hp259, i64 8
  store i32 0, ptr %tgp260, align 4
  %ld261 = load ptr, ptr %$lam24$apply.addr
  %fp262 = getelementptr i8, ptr %hp259, i64 16
  store ptr %ld261, ptr %fp262, align 8
  %$t25_i6.addr = alloca ptr
  store ptr %hp259, ptr %$t25_i6.addr
  %ld263 = load ptr, ptr %$t25_i6.addr
  %ld264 = load ptr, ptr %lst_i5.addr
  %cr265 = call i64 @fold_left(ptr %ld263, i64 0, ptr %ld264)
  %s.addr = alloca i64
  store i64 %cr265, ptr %s.addr
  %ld266 = load i64, ptr %s.addr
  %cr267 = call ptr @march_int_to_string(i64 %ld266)
  %$t44.addr = alloca ptr
  store ptr %cr267, ptr %$t44.addr
  %sl268 = call ptr @march_string_lit(ptr @.str13, i64 13)
  %ld269 = load ptr, ptr %$t44.addr
  %cr270 = call ptr @march_string_concat(ptr %sl268, ptr %ld269)
  %$t45.addr = alloca ptr
  store ptr %cr270, ptr %$t45.addr
  %ld271 = load ptr, ptr %$t45.addr
  call void @march_println(ptr %ld271)
  %cr272 = call ptr @range(i64 1, i64 5)
  %$t46.addr = alloca ptr
  store ptr %cr272, ptr %$t46.addr
  %ld273 = load ptr, ptr %$t46.addr
  %lst_i3.addr = alloca ptr
  store ptr %ld273, ptr %lst_i3.addr
  %hp274 = call ptr @march_alloc(i64 24)
  %tgp275 = getelementptr i8, ptr %hp274, i64 8
  store i32 0, ptr %tgp275, align 4
  %ld276 = load ptr, ptr %$lam26$apply.addr
  %fp277 = getelementptr i8, ptr %hp274, i64 16
  store ptr %ld276, ptr %fp277, align 8
  %$t27_i4.addr = alloca ptr
  store ptr %hp274, ptr %$t27_i4.addr
  %ld278 = load ptr, ptr %$t27_i4.addr
  %ld279 = load ptr, ptr %lst_i3.addr
  %cr280 = call i64 @fold_left(ptr %ld278, i64 1, ptr %ld279)
  %p.addr = alloca i64
  store i64 %cr280, ptr %p.addr
  %ld281 = load i64, ptr %p.addr
  %cr282 = call ptr @march_int_to_string(i64 %ld281)
  %$t47.addr = alloca ptr
  store ptr %cr282, ptr %$t47.addr
  %sl283 = call ptr @march_string_lit(ptr @.str14, i64 13)
  %ld284 = load ptr, ptr %$t47.addr
  %cr285 = call ptr @march_string_concat(ptr %sl283, ptr %ld284)
  %$t48.addr = alloca ptr
  store ptr %cr285, ptr %$t48.addr
  %ld286 = load ptr, ptr %$t48.addr
  call void @march_println(ptr %ld286)
  %cr287 = call ptr @range(i64 1, i64 5)
  %$t49.addr = alloca ptr
  store ptr %cr287, ptr %$t49.addr
  %ld288 = load ptr, ptr %$t49.addr
  %lst_i1.addr = alloca ptr
  store ptr %ld288, ptr %lst_i1.addr
  %hp289 = call ptr @march_alloc(i64 16)
  %tgp290 = getelementptr i8, ptr %hp289, i64 8
  store i32 0, ptr %tgp290, align 4
  %$t30_i2.addr = alloca ptr
  store ptr %hp289, ptr %$t30_i2.addr
  %ld291 = load ptr, ptr %lst_i1.addr
  %ld292 = load ptr, ptr %$t30_i2.addr
  %cr293 = call ptr @reverse_acc(ptr %ld291, ptr %ld292)
  %rev.addr = alloca ptr
  store ptr %cr293, ptr %rev.addr
  %sl294 = call ptr @march_string_lit(ptr @.str15, i64 11)
  call void @march_print(ptr %sl294)
  %ld295 = load ptr, ptr %rev.addr
  %cr296 = call ptr @print_list(ptr %ld295)
  %sl297 = call ptr @march_string_lit(ptr @.str16, i64 0)
  call void @march_println(ptr %sl297)
  %hp298 = call ptr @march_alloc(i64 24)
  %tgp299 = getelementptr i8, ptr %hp298, i64 8
  store i32 0, ptr %tgp299, align 4
  %ld300 = load ptr, ptr %$lam50$apply.addr
  %fp301 = getelementptr i8, ptr %hp298, i64 16
  store ptr %ld300, ptr %fp301, align 8
  %$t51.addr = alloca ptr
  store ptr %hp298, ptr %$t51.addr
  %ld302 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld302)
  %ld303 = load ptr, ptr %$t51.addr
  %ld304 = load ptr, ptr %nums.addr
  %cr305 = call ptr @find(ptr %ld303, ptr %ld304)
  %big.addr = alloca ptr
  store ptr %cr305, ptr %big.addr
  %ld306 = load ptr, ptr %big.addr
  %cr307 = call ptr @option_to_string(ptr %ld306)
  %$t52.addr = alloca ptr
  store ptr %cr307, ptr %$t52.addr
  %sl308 = call ptr @march_string_lit(ptr @.str17, i64 11)
  %ld309 = load ptr, ptr %$t52.addr
  %cr310 = call ptr @march_string_concat(ptr %sl308, ptr %ld309)
  %$t53.addr = alloca ptr
  store ptr %cr310, ptr %$t53.addr
  %ld311 = load ptr, ptr %$t53.addr
  call void @march_println(ptr %ld311)
  %hp312 = call ptr @march_alloc(i64 24)
  %tgp313 = getelementptr i8, ptr %hp312, i64 8
  store i32 0, ptr %tgp313, align 4
  %ld314 = load ptr, ptr %$lam54$apply.addr
  %fp315 = getelementptr i8, ptr %hp312, i64 16
  store ptr %ld314, ptr %fp315, align 8
  %$t55.addr = alloca ptr
  store ptr %hp312, ptr %$t55.addr
  %ld316 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld316)
  %ld317 = load ptr, ptr %$t55.addr
  %ld318 = load ptr, ptr %nums.addr
  %cr319 = call ptr @find(ptr %ld317, ptr %ld318)
  %none.addr = alloca ptr
  store ptr %cr319, ptr %none.addr
  %ld320 = load ptr, ptr %none.addr
  %cr321 = call ptr @option_to_string(ptr %ld320)
  %$t56.addr = alloca ptr
  store ptr %cr321, ptr %$t56.addr
  %sl322 = call ptr @march_string_lit(ptr @.str18, i64 11)
  %ld323 = load ptr, ptr %$t56.addr
  %cr324 = call ptr @march_string_concat(ptr %sl322, ptr %ld323)
  %$t57.addr = alloca ptr
  store ptr %cr324, ptr %$t57.addr
  %ld325 = load ptr, ptr %$t57.addr
  call void @march_println(ptr %ld325)
  %ld326 = load ptr, ptr %nums.addr
  %cr327 = call i64 @length(ptr %ld326)
  %$t58.addr = alloca i64
  store i64 %cr327, ptr %$t58.addr
  %ld328 = load i64, ptr %$t58.addr
  %cr329 = call ptr @march_int_to_string(i64 %ld328)
  %$t59.addr = alloca ptr
  store ptr %cr329, ptr %$t59.addr
  %sl330 = call ptr @march_string_lit(ptr @.str19, i64 11)
  %ld331 = load ptr, ptr %$t59.addr
  %cr332 = call ptr @march_string_concat(ptr %sl330, ptr %ld331)
  %$t60.addr = alloca ptr
  store ptr %cr332, ptr %$t60.addr
  %ld333 = load ptr, ptr %$t60.addr
  call void @march_println(ptr %ld333)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
