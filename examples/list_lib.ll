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
  %$w1.addr = alloca ptr
  store ptr %fv7, ptr %$w1.addr
  %fp8 = getelementptr i8, ptr %ld1, i64 24
  %fv9 = load ptr, ptr %fp8, align 8
  %t.addr = alloca ptr
  store ptr %fv9, ptr %t.addr
  %ld10 = load ptr, ptr %t.addr
  %cr11 = call i64 @length(ptr %ld10)
  %$t2.addr = alloca i64
  store i64 %cr11, ptr %$t2.addr
  %ld12 = load i64, ptr %$t2.addr
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
  %$t3.addr = alloca i64
  store i64 %cr31, ptr %$t3.addr
  %ld32 = load ptr, ptr %f.addr
  %ld33 = load ptr, ptr %t.addr
  %cr34 = call ptr @map(ptr %ld32, ptr %ld33)
  %$t4.addr = alloca ptr
  store ptr %cr34, ptr %$t4.addr
  %hp35 = call ptr @march_alloc(i64 32)
  %tgp36 = getelementptr i8, ptr %hp35, i64 8
  store i32 1, ptr %tgp36, align 4
  %ld37 = load i64, ptr %$t3.addr
  %cv38 = inttoptr i64 %ld37 to ptr
  %fp39 = getelementptr i8, ptr %hp35, i64 16
  store ptr %cv38, ptr %fp39, align 8
  %ld40 = load ptr, ptr %$t4.addr
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
  %$t5.addr = alloca i64
  store i64 %cr57, ptr %$t5.addr
  %ld58 = load i64, ptr %$t5.addr
  %res_slot59 = alloca ptr
  switch i64 %ld58, label %case_default14 [
      i64 1, label %case_br15
  ]
case_br15:
  %ld60 = load ptr, ptr %pred.addr
  %ld61 = load ptr, ptr %t.addr
  %cr62 = call ptr @filter(ptr %ld60, ptr %ld61)
  %$t6.addr = alloca ptr
  store ptr %cr62, ptr %$t6.addr
  %hp63 = call ptr @march_alloc(i64 32)
  %tgp64 = getelementptr i8, ptr %hp63, i64 8
  store i32 1, ptr %tgp64, align 4
  %ld65 = load i64, ptr %h.addr
  %cv66 = inttoptr i64 %ld65 to ptr
  %fp67 = getelementptr i8, ptr %hp63, i64 16
  store ptr %cv66, ptr %fp67, align 8
  %ld68 = load ptr, ptr %$t6.addr
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
  %$t7.addr = alloca i64
  store i64 %cr90, ptr %$t7.addr
  %ld91 = load ptr, ptr %f.addr
  %ld92 = load i64, ptr %$t7.addr
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

define i64 @sum(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %hp98 = call ptr @march_alloc(i64 24)
  %tgp99 = getelementptr i8, ptr %hp98, i64 8
  store i32 0, ptr %tgp99, align 4
  %fp100 = getelementptr i8, ptr %hp98, i64 16
  store ptr @$lam8$apply, ptr %fp100, align 8
  %$t9.addr = alloca ptr
  store ptr %hp98, ptr %$t9.addr
  %ld101 = load ptr, ptr %$t9.addr
  %ld102 = load ptr, ptr %lst.addr
  %cr103 = call i64 @fold_left(ptr %ld101, i64 0, ptr %ld102)
  ret i64 %cr103
}

define i64 @product(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %hp104 = call ptr @march_alloc(i64 24)
  %tgp105 = getelementptr i8, ptr %hp104, i64 8
  store i32 0, ptr %tgp105, align 4
  %fp106 = getelementptr i8, ptr %hp104, i64 16
  store ptr @$lam10$apply, ptr %fp106, align 8
  %$t11.addr = alloca ptr
  store ptr %hp104, ptr %$t11.addr
  %ld107 = load ptr, ptr %$t11.addr
  %ld108 = load ptr, ptr %lst.addr
  %cr109 = call i64 @fold_left(ptr %ld107, i64 1, ptr %ld108)
  ret i64 %cr109
}

define ptr @append(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld110 = load ptr, ptr %xs.addr
  %res_slot111 = alloca ptr
  %tgp112 = getelementptr i8, ptr %ld110, i64 8
  %tag113 = load i32, ptr %tgp112, align 4
  switch i32 %tag113, label %case_default21 [
      i32 0, label %case_br22
      i32 1, label %case_br23
  ]
case_br22:
  %ld114 = load ptr, ptr %ys.addr
  store ptr %ld114, ptr %res_slot111
  br label %case_merge20
case_br23:
  %fp115 = getelementptr i8, ptr %ld110, i64 16
  %fv116 = load ptr, ptr %fp115, align 8
  %h.addr = alloca ptr
  store ptr %fv116, ptr %h.addr
  %fp117 = getelementptr i8, ptr %ld110, i64 24
  %fv118 = load ptr, ptr %fp117, align 8
  %t.addr = alloca ptr
  store ptr %fv118, ptr %t.addr
  %ld119 = load ptr, ptr %t.addr
  %ld120 = load ptr, ptr %ys.addr
  %cr121 = call ptr @append(ptr %ld119, ptr %ld120)
  %$t12.addr = alloca ptr
  store ptr %cr121, ptr %$t12.addr
  %hp122 = call ptr @march_alloc(i64 32)
  %tgp123 = getelementptr i8, ptr %hp122, i64 8
  store i32 1, ptr %tgp123, align 4
  %ld124 = load i64, ptr %h.addr
  %cv125 = inttoptr i64 %ld124 to ptr
  %fp126 = getelementptr i8, ptr %hp122, i64 16
  store ptr %cv125, ptr %fp126, align 8
  %ld127 = load ptr, ptr %$t12.addr
  %fp128 = getelementptr i8, ptr %hp122, i64 24
  store ptr %ld127, ptr %fp128, align 8
  store ptr %hp122, ptr %res_slot111
  br label %case_merge20
case_default21:
  unreachable
case_merge20:
  %case_r129 = load ptr, ptr %res_slot111
  ret ptr %case_r129
}

define ptr @reverse_acc(ptr %lst.arg, ptr %acc.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld130 = load ptr, ptr %lst.addr
  %res_slot131 = alloca ptr
  %tgp132 = getelementptr i8, ptr %ld130, i64 8
  %tag133 = load i32, ptr %tgp132, align 4
  switch i32 %tag133, label %case_default25 [
      i32 0, label %case_br26
      i32 1, label %case_br27
  ]
case_br26:
  %ld134 = load ptr, ptr %acc.addr
  store ptr %ld134, ptr %res_slot131
  br label %case_merge24
case_br27:
  %fp135 = getelementptr i8, ptr %ld130, i64 16
  %fv136 = load ptr, ptr %fp135, align 8
  %h.addr = alloca ptr
  store ptr %fv136, ptr %h.addr
  %fp137 = getelementptr i8, ptr %ld130, i64 24
  %fv138 = load ptr, ptr %fp137, align 8
  %t.addr = alloca ptr
  store ptr %fv138, ptr %t.addr
  %hp139 = call ptr @march_alloc(i64 32)
  %tgp140 = getelementptr i8, ptr %hp139, i64 8
  store i32 1, ptr %tgp140, align 4
  %ld141 = load i64, ptr %h.addr
  %cv142 = inttoptr i64 %ld141 to ptr
  %fp143 = getelementptr i8, ptr %hp139, i64 16
  store ptr %cv142, ptr %fp143, align 8
  %ld144 = load ptr, ptr %acc.addr
  %fp145 = getelementptr i8, ptr %hp139, i64 24
  store ptr %ld144, ptr %fp145, align 8
  %$t13.addr = alloca ptr
  store ptr %hp139, ptr %$t13.addr
  %ld146 = load ptr, ptr %t.addr
  %ld147 = load ptr, ptr %$t13.addr
  %cr148 = call ptr @reverse_acc(ptr %ld146, ptr %ld147)
  store ptr %cr148, ptr %res_slot131
  br label %case_merge24
case_default25:
  unreachable
case_merge24:
  %case_r149 = load ptr, ptr %res_slot131
  ret ptr %case_r149
}

define ptr @reverse(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %hp150 = call ptr @march_alloc(i64 16)
  %tgp151 = getelementptr i8, ptr %hp150, i64 8
  store i32 0, ptr %tgp151, align 4
  %$t14.addr = alloca ptr
  store ptr %hp150, ptr %$t14.addr
  %ld152 = load ptr, ptr %lst.addr
  %ld153 = load ptr, ptr %$t14.addr
  %cr154 = call ptr @reverse_acc(ptr %ld152, ptr %ld153)
  ret ptr %cr154
}

define ptr @find(ptr %pred.arg, ptr %lst.arg) {
entry:
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld155 = load ptr, ptr %lst.addr
  %res_slot156 = alloca ptr
  %tgp157 = getelementptr i8, ptr %ld155, i64 8
  %tag158 = load i32, ptr %tgp157, align 4
  switch i32 %tag158, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %hp159 = call ptr @march_alloc(i64 16)
  %tgp160 = getelementptr i8, ptr %hp159, i64 8
  store i32 0, ptr %tgp160, align 4
  store ptr %hp159, ptr %res_slot156
  br label %case_merge28
case_br31:
  %fp161 = getelementptr i8, ptr %ld155, i64 16
  %fv162 = load ptr, ptr %fp161, align 8
  %h.addr = alloca ptr
  store ptr %fv162, ptr %h.addr
  %fp163 = getelementptr i8, ptr %ld155, i64 24
  %fv164 = load ptr, ptr %fp163, align 8
  %t.addr = alloca ptr
  store ptr %fv164, ptr %t.addr
  %ld165 = load ptr, ptr %pred.addr
  %fp166 = getelementptr i8, ptr %ld165, i64 16
  %fv167 = load ptr, ptr %fp166, align 8
  %ld168 = load i64, ptr %h.addr
  %cr169 = call i64 (ptr, i64) %fv167(ptr %ld165, i64 %ld168)
  %$t15.addr = alloca i64
  store i64 %cr169, ptr %$t15.addr
  %ld170 = load i64, ptr %$t15.addr
  %res_slot171 = alloca ptr
  switch i64 %ld170, label %case_default33 [
      i64 1, label %case_br34
  ]
case_br34:
  %hp172 = call ptr @march_alloc(i64 24)
  %tgp173 = getelementptr i8, ptr %hp172, i64 8
  store i32 1, ptr %tgp173, align 4
  %ld174 = load i64, ptr %h.addr
  %cv175 = inttoptr i64 %ld174 to ptr
  %fp176 = getelementptr i8, ptr %hp172, i64 16
  store ptr %cv175, ptr %fp176, align 8
  store ptr %hp172, ptr %res_slot171
  br label %case_merge32
case_default33:
  %ld177 = load ptr, ptr %pred.addr
  %ld178 = load ptr, ptr %t.addr
  %cr179 = call ptr @find(ptr %ld177, ptr %ld178)
  store ptr %cr179, ptr %res_slot171
  br label %case_merge32
case_merge32:
  %case_r180 = load ptr, ptr %res_slot171
  store ptr %case_r180, ptr %res_slot156
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r181 = load ptr, ptr %res_slot156
  ret ptr %case_r181
}

define ptr @range(i64 %lo.arg, i64 %hi.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %ld182 = load i64, ptr %lo.addr
  %ld183 = load i64, ptr %hi.addr
  %cmp184 = icmp sgt i64 %ld182, %ld183
  %ar185 = zext i1 %cmp184 to i64
  %$t16.addr = alloca i64
  store i64 %ar185, ptr %$t16.addr
  %ld186 = load i64, ptr %$t16.addr
  %res_slot187 = alloca ptr
  switch i64 %ld186, label %case_default36 [
      i64 1, label %case_br37
  ]
case_br37:
  %hp188 = call ptr @march_alloc(i64 16)
  %tgp189 = getelementptr i8, ptr %hp188, i64 8
  store i32 0, ptr %tgp189, align 4
  store ptr %hp188, ptr %res_slot187
  br label %case_merge35
case_default36:
  %ld190 = load i64, ptr %lo.addr
  %ar191 = add i64 %ld190, 1
  %$t17.addr = alloca i64
  store i64 %ar191, ptr %$t17.addr
  %ld192 = load i64, ptr %$t17.addr
  %ld193 = load i64, ptr %hi.addr
  %cr194 = call ptr @range(i64 %ld192, i64 %ld193)
  %$t18.addr = alloca ptr
  store ptr %cr194, ptr %$t18.addr
  %hp195 = call ptr @march_alloc(i64 32)
  %tgp196 = getelementptr i8, ptr %hp195, i64 8
  store i32 1, ptr %tgp196, align 4
  %ld197 = load i64, ptr %lo.addr
  %cv198 = inttoptr i64 %ld197 to ptr
  %fp199 = getelementptr i8, ptr %hp195, i64 16
  store ptr %cv198, ptr %fp199, align 8
  %ld200 = load ptr, ptr %$t18.addr
  %fp201 = getelementptr i8, ptr %hp195, i64 24
  store ptr %ld200, ptr %fp201, align 8
  store ptr %hp195, ptr %res_slot187
  br label %case_merge35
case_merge35:
  %case_r202 = load ptr, ptr %res_slot187
  ret ptr %case_r202
}

define void @print_list(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %sl203 = call ptr @march_string_lit(ptr @.str1, i64 1)
  call void @march_print(ptr %sl203)
  %ld204 = load ptr, ptr %lst.addr
  %res_slot205 = alloca ptr
  %tgp206 = getelementptr i8, ptr %ld204, i64 8
  %tag207 = load i32, ptr %tgp206, align 4
  switch i32 %tag207, label %case_default39 [
      i32 0, label %case_br40
      i32 1, label %case_br41
  ]
case_br40:
  %cv208 = inttoptr i64 0 to ptr
  store ptr %cv208, ptr %res_slot205
  br label %case_merge38
case_br41:
  %fp209 = getelementptr i8, ptr %ld204, i64 16
  %fv210 = load ptr, ptr %fp209, align 8
  %h.addr = alloca ptr
  store ptr %fv210, ptr %h.addr
  %fp211 = getelementptr i8, ptr %ld204, i64 24
  %fv212 = load ptr, ptr %fp211, align 8
  %t.addr = alloca ptr
  store ptr %fv212, ptr %t.addr
  %ld213 = load i64, ptr %h.addr
  %cr214 = call ptr @march_int_to_string(i64 %ld213)
  %$t19.addr = alloca ptr
  store ptr %cr214, ptr %$t19.addr
  %ld215 = load ptr, ptr %$t19.addr
  call void @march_print(ptr %ld215)
  %ld216 = load ptr, ptr %t.addr
  %res_slot217 = alloca ptr
  %tgp218 = getelementptr i8, ptr %ld216, i64 8
  %tag219 = load i32, ptr %tgp218, align 4
  switch i32 %tag219, label %case_default43 [
      i32 0, label %case_br44
  ]
case_br44:
  %cv220 = inttoptr i64 0 to ptr
  store ptr %cv220, ptr %res_slot217
  br label %case_merge42
case_default43:
  %sl221 = call ptr @march_string_lit(ptr @.str2, i64 2)
  call void @march_print(ptr %sl221)
  %ld222 = load ptr, ptr %t.addr
  %cr223 = call ptr @print_list_tail(ptr %ld222)
  store ptr %cr223, ptr %res_slot217
  br label %case_merge42
case_merge42:
  %case_r224 = load ptr, ptr %res_slot217
  store ptr %case_r224, ptr %res_slot205
  br label %case_merge38
case_default39:
  unreachable
case_merge38:
  %case_r225 = load ptr, ptr %res_slot205
  %sl226 = call ptr @march_string_lit(ptr @.str3, i64 1)
  call void @march_print(ptr %sl226)
  ret void
}

define void @print_list_tail(ptr %lst.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %ld227 = load ptr, ptr %lst.addr
  %res_slot228 = alloca ptr
  %tgp229 = getelementptr i8, ptr %ld227, i64 8
  %tag230 = load i32, ptr %tgp229, align 4
  switch i32 %tag230, label %case_default46 [
      i32 0, label %case_br47
      i32 1, label %case_br48
  ]
case_br47:
  %cv231 = inttoptr i64 0 to ptr
  store ptr %cv231, ptr %res_slot228
  br label %case_merge45
case_br48:
  %fp232 = getelementptr i8, ptr %ld227, i64 16
  %fv233 = load ptr, ptr %fp232, align 8
  %h.addr = alloca ptr
  store ptr %fv233, ptr %h.addr
  %fp234 = getelementptr i8, ptr %ld227, i64 24
  %fv235 = load ptr, ptr %fp234, align 8
  %t.addr = alloca ptr
  store ptr %fv235, ptr %t.addr
  %ld236 = load i64, ptr %h.addr
  %cr237 = call ptr @march_int_to_string(i64 %ld236)
  %$t20.addr = alloca ptr
  store ptr %cr237, ptr %$t20.addr
  %ld238 = load ptr, ptr %$t20.addr
  call void @march_print(ptr %ld238)
  %ld239 = load ptr, ptr %t.addr
  %res_slot240 = alloca ptr
  %tgp241 = getelementptr i8, ptr %ld239, i64 8
  %tag242 = load i32, ptr %tgp241, align 4
  switch i32 %tag242, label %case_default50 [
      i32 0, label %case_br51
  ]
case_br51:
  %cv243 = inttoptr i64 0 to ptr
  store ptr %cv243, ptr %res_slot240
  br label %case_merge49
case_default50:
  %sl244 = call ptr @march_string_lit(ptr @.str4, i64 2)
  call void @march_print(ptr %sl244)
  %ld245 = load ptr, ptr %t.addr
  %cr246 = call ptr @print_list_tail(ptr %ld245)
  store ptr %cr246, ptr %res_slot240
  br label %case_merge49
case_merge49:
  %case_r247 = load ptr, ptr %res_slot240
  store ptr %case_r247, ptr %res_slot228
  br label %case_merge45
case_default46:
  unreachable
case_merge45:
  %case_r248 = load ptr, ptr %res_slot228
  ret void
}

define ptr @option_to_string(ptr %o.arg) {
entry:
  %o.addr = alloca ptr
  store ptr %o.arg, ptr %o.addr
  %ld249 = load ptr, ptr %o.addr
  %res_slot250 = alloca ptr
  %tgp251 = getelementptr i8, ptr %ld249, i64 8
  %tag252 = load i32, ptr %tgp251, align 4
  switch i32 %tag252, label %case_default53 [
      i32 0, label %case_br54
      i32 1, label %case_br55
  ]
case_br54:
  %sl253 = call ptr @march_string_lit(ptr @.str5, i64 4)
  store ptr %sl253, ptr %res_slot250
  br label %case_merge52
case_br55:
  %fp254 = getelementptr i8, ptr %ld249, i64 16
  %fv255 = load ptr, ptr %fp254, align 8
  %x.addr = alloca ptr
  store ptr %fv255, ptr %x.addr
  %ld256 = load i64, ptr %x.addr
  %cr257 = call ptr @march_int_to_string(i64 %ld256)
  %$t21.addr = alloca ptr
  store ptr %cr257, ptr %$t21.addr
  %sl258 = call ptr @march_string_lit(ptr @.str6, i64 5)
  %ld259 = load ptr, ptr %$t21.addr
  %cr260 = call ptr @march_string_concat(ptr %sl258, ptr %ld259)
  %$t22.addr = alloca ptr
  store ptr %cr260, ptr %$t22.addr
  %ld261 = load ptr, ptr %$t22.addr
  %sl262 = call ptr @march_string_lit(ptr @.str7, i64 1)
  %cr263 = call ptr @march_string_concat(ptr %ld261, ptr %sl262)
  store ptr %cr263, ptr %res_slot250
  br label %case_merge52
case_default53:
  unreachable
case_merge52:
  %case_r264 = load ptr, ptr %res_slot250
  ret ptr %case_r264
}

define void @march_main() {
entry:
  %cr265 = call ptr @range(i64 1, i64 10)
  %nums.addr = alloca ptr
  store ptr %cr265, ptr %nums.addr
  %ld266 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld266)
  %ld267 = load ptr, ptr %nums.addr
  %cr268 = call ptr @print_list(ptr %ld267)
  %sl269 = call ptr @march_string_lit(ptr @.str8, i64 0)
  call void @march_println(ptr %sl269)
  %hp270 = call ptr @march_alloc(i64 24)
  %tgp271 = getelementptr i8, ptr %hp270, i64 8
  store i32 0, ptr %tgp271, align 4
  %fp272 = getelementptr i8, ptr %hp270, i64 16
  store ptr @$lam23$apply, ptr %fp272, align 8
  %$t24.addr = alloca ptr
  store ptr %hp270, ptr %$t24.addr
  %ld273 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld273)
  %ld274 = load ptr, ptr %$t24.addr
  %ld275 = load ptr, ptr %nums.addr
  %cr276 = call ptr @map(ptr %ld274, ptr %ld275)
  %doubled.addr = alloca ptr
  store ptr %cr276, ptr %doubled.addr
  %sl277 = call ptr @march_string_lit(ptr @.str9, i64 11)
  call void @march_print(ptr %sl277)
  %ld278 = load ptr, ptr %doubled.addr
  %cr279 = call ptr @print_list(ptr %ld278)
  %sl280 = call ptr @march_string_lit(ptr @.str10, i64 0)
  call void @march_println(ptr %sl280)
  %hp281 = call ptr @march_alloc(i64 24)
  %tgp282 = getelementptr i8, ptr %hp281, i64 8
  store i32 0, ptr %tgp282, align 4
  %fp283 = getelementptr i8, ptr %hp281, i64 16
  store ptr @$lam25$apply, ptr %fp283, align 8
  %$t27.addr = alloca ptr
  store ptr %hp281, ptr %$t27.addr
  %ld284 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld284)
  %ld285 = load ptr, ptr %$t27.addr
  %ld286 = load ptr, ptr %nums.addr
  %cr287 = call ptr @filter(ptr %ld285, ptr %ld286)
  %evens.addr = alloca ptr
  store ptr %cr287, ptr %evens.addr
  %sl288 = call ptr @march_string_lit(ptr @.str11, i64 11)
  call void @march_print(ptr %sl288)
  %ld289 = load ptr, ptr %evens.addr
  %cr290 = call ptr @print_list(ptr %ld289)
  %sl291 = call ptr @march_string_lit(ptr @.str12, i64 0)
  call void @march_println(ptr %sl291)
  %ld292 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld292)
  %ld293 = load ptr, ptr %nums.addr
  %cr294 = call i64 @sum(ptr %ld293)
  %s.addr = alloca i64
  store i64 %cr294, ptr %s.addr
  %ld295 = load i64, ptr %s.addr
  %cr296 = call ptr @march_int_to_string(i64 %ld295)
  %$t28.addr = alloca ptr
  store ptr %cr296, ptr %$t28.addr
  %sl297 = call ptr @march_string_lit(ptr @.str13, i64 13)
  %ld298 = load ptr, ptr %$t28.addr
  %cr299 = call ptr @march_string_concat(ptr %sl297, ptr %ld298)
  %$t29.addr = alloca ptr
  store ptr %cr299, ptr %$t29.addr
  %ld300 = load ptr, ptr %$t29.addr
  call void @march_println(ptr %ld300)
  %cr301 = call ptr @range(i64 1, i64 5)
  %$t30.addr = alloca ptr
  store ptr %cr301, ptr %$t30.addr
  %ld302 = load ptr, ptr %$t30.addr
  %cr303 = call i64 @product(ptr %ld302)
  %p.addr = alloca i64
  store i64 %cr303, ptr %p.addr
  %ld304 = load i64, ptr %p.addr
  %cr305 = call ptr @march_int_to_string(i64 %ld304)
  %$t31.addr = alloca ptr
  store ptr %cr305, ptr %$t31.addr
  %sl306 = call ptr @march_string_lit(ptr @.str14, i64 13)
  %ld307 = load ptr, ptr %$t31.addr
  %cr308 = call ptr @march_string_concat(ptr %sl306, ptr %ld307)
  %$t32.addr = alloca ptr
  store ptr %cr308, ptr %$t32.addr
  %ld309 = load ptr, ptr %$t32.addr
  call void @march_println(ptr %ld309)
  %cr310 = call ptr @range(i64 1, i64 5)
  %$t33.addr = alloca ptr
  store ptr %cr310, ptr %$t33.addr
  %ld311 = load ptr, ptr %$t33.addr
  %cr312 = call ptr @reverse(ptr %ld311)
  %rev.addr = alloca ptr
  store ptr %cr312, ptr %rev.addr
  %sl313 = call ptr @march_string_lit(ptr @.str15, i64 11)
  call void @march_print(ptr %sl313)
  %ld314 = load ptr, ptr %rev.addr
  %cr315 = call ptr @print_list(ptr %ld314)
  %sl316 = call ptr @march_string_lit(ptr @.str16, i64 0)
  call void @march_println(ptr %sl316)
  %hp317 = call ptr @march_alloc(i64 24)
  %tgp318 = getelementptr i8, ptr %hp317, i64 8
  store i32 0, ptr %tgp318, align 4
  %fp319 = getelementptr i8, ptr %hp317, i64 16
  store ptr @$lam34$apply, ptr %fp319, align 8
  %$t35.addr = alloca ptr
  store ptr %hp317, ptr %$t35.addr
  %ld320 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld320)
  %ld321 = load ptr, ptr %$t35.addr
  %ld322 = load ptr, ptr %nums.addr
  %cr323 = call ptr @find(ptr %ld321, ptr %ld322)
  %big.addr = alloca ptr
  store ptr %cr323, ptr %big.addr
  %ld324 = load ptr, ptr %big.addr
  %cr325 = call ptr @option_to_string(ptr %ld324)
  %$t36.addr = alloca ptr
  store ptr %cr325, ptr %$t36.addr
  %sl326 = call ptr @march_string_lit(ptr @.str17, i64 11)
  %ld327 = load ptr, ptr %$t36.addr
  %cr328 = call ptr @march_string_concat(ptr %sl326, ptr %ld327)
  %$t37.addr = alloca ptr
  store ptr %cr328, ptr %$t37.addr
  %ld329 = load ptr, ptr %$t37.addr
  call void @march_println(ptr %ld329)
  %hp330 = call ptr @march_alloc(i64 24)
  %tgp331 = getelementptr i8, ptr %hp330, i64 8
  store i32 0, ptr %tgp331, align 4
  %fp332 = getelementptr i8, ptr %hp330, i64 16
  store ptr @$lam38$apply, ptr %fp332, align 8
  %$t39.addr = alloca ptr
  store ptr %hp330, ptr %$t39.addr
  %ld333 = load ptr, ptr %nums.addr
  call void @march_incrc(ptr %ld333)
  %ld334 = load ptr, ptr %$t39.addr
  %ld335 = load ptr, ptr %nums.addr
  %cr336 = call ptr @find(ptr %ld334, ptr %ld335)
  %none.addr = alloca ptr
  store ptr %cr336, ptr %none.addr
  %ld337 = load ptr, ptr %none.addr
  %cr338 = call ptr @option_to_string(ptr %ld337)
  %$t40.addr = alloca ptr
  store ptr %cr338, ptr %$t40.addr
  %sl339 = call ptr @march_string_lit(ptr @.str18, i64 11)
  %ld340 = load ptr, ptr %$t40.addr
  %cr341 = call ptr @march_string_concat(ptr %sl339, ptr %ld340)
  %$t41.addr = alloca ptr
  store ptr %cr341, ptr %$t41.addr
  %ld342 = load ptr, ptr %$t41.addr
  call void @march_println(ptr %ld342)
  %ld343 = load ptr, ptr %nums.addr
  %cr344 = call i64 @length(ptr %ld343)
  %$t42.addr = alloca i64
  store i64 %cr344, ptr %$t42.addr
  %ld345 = load i64, ptr %$t42.addr
  %cr346 = call ptr @march_int_to_string(i64 %ld345)
  %$t43.addr = alloca ptr
  store ptr %cr346, ptr %$t43.addr
  %sl347 = call ptr @march_string_lit(ptr @.str19, i64 11)
  %ld348 = load ptr, ptr %$t43.addr
  %cr349 = call ptr @march_string_concat(ptr %sl347, ptr %ld348)
  %$t44.addr = alloca ptr
  store ptr %cr349, ptr %$t44.addr
  %ld350 = load ptr, ptr %$t44.addr
  call void @march_println(ptr %ld350)
  ret void
}

define ptr @$lam8$apply(ptr %$clo.arg, ptr %a.arg, ptr %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %b.addr = alloca ptr
  store ptr %b.arg, ptr %b.addr
  %ld351 = load i64, ptr %a.addr
  %ld352 = load i64, ptr %b.addr
  %ar353 = add i64 %ld351, %ld352
  %cv354 = inttoptr i64 %ar353 to ptr
  ret ptr %cv354
}

define ptr @$lam10$apply(ptr %$clo.arg, ptr %a.arg, ptr %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %b.addr = alloca ptr
  store ptr %b.arg, ptr %b.addr
  %ld355 = load i64, ptr %a.addr
  %ld356 = load i64, ptr %b.addr
  %ar357 = mul i64 %ld355, %ld356
  %cv358 = inttoptr i64 %ar357 to ptr
  ret ptr %cv358
}

define ptr @$lam23$apply(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld359 = load i64, ptr %x.addr
  %ar360 = mul i64 %ld359, 2
  %cv361 = inttoptr i64 %ar360 to ptr
  ret ptr %cv361
}

define ptr @$lam25$apply(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld362 = load i64, ptr %x.addr
  %ar363 = srem i64 %ld362, 2
  %$t26.addr = alloca i64
  store i64 %ar363, ptr %$t26.addr
  %ld364 = load i64, ptr %$t26.addr
  %cmp365 = icmp eq i64 %ld364, 0
  %ar366 = zext i1 %cmp365 to i64
  %cv367 = inttoptr i64 %ar366 to ptr
  ret ptr %cv367
}

define ptr @$lam34$apply(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld368 = load i64, ptr %x.addr
  %cmp369 = icmp sgt i64 %ld368, 7
  %ar370 = zext i1 %cmp369 to i64
  %cv371 = inttoptr i64 %ar370 to ptr
  ret ptr %cv371
}

define ptr @$lam38$apply(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld372 = load i64, ptr %x.addr
  %cmp373 = icmp sgt i64 %ld372, 100
  %ar374 = zext i1 %cmp373 to i64
  %cv375 = inttoptr i64 %ar374 to ptr
  ret ptr %cv375
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
