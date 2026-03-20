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

@.str1 = private unnamed_addr constant [31 x i8] c"--- Work-stealing examples ---\00"
@.str2 = private unnamed_addr constant [15 x i8] c"par_fib(30) = \00"
@.str3 = private unnamed_addr constant [34 x i8] c"mixed tiers: fib(20) + fib(25) = \00"

define i64 @fib(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp slt i64 %ld1, 2
  %ar3 = zext i1 %cmp2 to i64
  %$t492.addr = alloca i64
  store i64 %ar3, ptr %$t492.addr
  %ld4 = load i64, ptr %$t492.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld6 = load i64, ptr %n.addr
  %cv7 = inttoptr i64 %ld6 to ptr
  store ptr %cv7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %n.addr
  %ar9 = sub i64 %ld8, 1
  %$t493.addr = alloca i64
  store i64 %ar9, ptr %$t493.addr
  %ld10 = load i64, ptr %$t493.addr
  %cr11 = call i64 @fib(i64 %ld10)
  %$t494.addr = alloca i64
  store i64 %cr11, ptr %$t494.addr
  %ld12 = load i64, ptr %n.addr
  %ar13 = sub i64 %ld12, 2
  %$t495.addr = alloca i64
  store i64 %ar13, ptr %$t495.addr
  %ld14 = load i64, ptr %$t495.addr
  %cr15 = call i64 @fib(i64 %ld14)
  %$t496.addr = alloca i64
  store i64 %cr15, ptr %$t496.addr
  %ld16 = load i64, ptr %$t494.addr
  %ld17 = load i64, ptr %$t496.addr
  %ar18 = add i64 %ld16, %ld17
  %cv19 = inttoptr i64 %ar18 to ptr
  store ptr %cv19, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r20 = load ptr, ptr %res_slot5
  %cv21 = ptrtoint ptr %case_r20 to i64
  ret i64 %cv21
}

define i64 @par_fib(ptr %pool.arg, i64 %n.arg, i64 %threshold.arg) {
entry:
  %pool.addr = alloca ptr
  store ptr %pool.arg, ptr %pool.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld22 = load i64, ptr %n.addr
  %cmp23 = icmp slt i64 %ld22, 2
  %ar24 = zext i1 %cmp23 to i64
  %$t497.addr = alloca i64
  store i64 %ar24, ptr %$t497.addr
  %ld25 = load i64, ptr %$t497.addr
  %res_slot26 = alloca ptr
  switch i64 %ld25, label %case_default5 [
      i64 1, label %case_br6
  ]
case_br6:
  %ld27 = load i64, ptr %n.addr
  %cv28 = inttoptr i64 %ld27 to ptr
  store ptr %cv28, ptr %res_slot26
  br label %case_merge4
case_default5:
  %ld29 = load i64, ptr %n.addr
  %ld30 = load i64, ptr %threshold.addr
  %cmp31 = icmp sle i64 %ld29, %ld30
  %ar32 = zext i1 %cmp31 to i64
  %$t498.addr = alloca i64
  store i64 %ar32, ptr %$t498.addr
  %ld33 = load i64, ptr %$t498.addr
  %res_slot34 = alloca ptr
  switch i64 %ld33, label %case_default8 [
      i64 1, label %case_br9
  ]
case_br9:
  %ld35 = load i64, ptr %n.addr
  %cr36 = call i64 @fib(i64 %ld35)
  %cv37 = inttoptr i64 %cr36 to ptr
  store ptr %cv37, ptr %res_slot34
  br label %case_merge7
case_default8:
  %ld38 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld38)
  %hp39 = call ptr @march_alloc(i64 48)
  %tgp40 = getelementptr i8, ptr %hp39, i64 8
  store i32 0, ptr %tgp40, align 4
  %fp41 = getelementptr i8, ptr %hp39, i64 16
  store ptr @$lam499$apply, ptr %fp41, align 8
  %ld42 = load i64, ptr %n.addr
  %fp43 = getelementptr i8, ptr %hp39, i64 24
  store i64 %ld42, ptr %fp43, align 8
  %ld44 = load ptr, ptr %pool.addr
  %fp45 = getelementptr i8, ptr %hp39, i64 32
  store ptr %ld44, ptr %fp45, align 8
  %ld46 = load i64, ptr %threshold.addr
  %fp47 = getelementptr i8, ptr %hp39, i64 40
  store i64 %ld46, ptr %fp47, align 8
  %$t501.addr = alloca ptr
  store ptr %hp39, ptr %$t501.addr
  %ld48 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld48)
  %ld49 = load ptr, ptr %$t501.addr
  %fp50 = getelementptr i8, ptr %ld49, i64 16
  %fv51 = load ptr, ptr %fp50, align 8
  %tsres52 = call i64 %fv51(ptr %ld49, i64 0)
  %hp53 = call ptr @march_alloc(i64 24)
  %tgp54 = getelementptr i8, ptr %hp53, i64 8
  store i32 0, ptr %tgp54, align 4
  %fp55 = getelementptr i8, ptr %hp53, i64 16
  store i64 %tsres52, ptr %fp55, align 8
  %t1.addr = alloca ptr
  store ptr %hp53, ptr %t1.addr
  %ld56 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld56)
  %hp57 = call ptr @march_alloc(i64 48)
  %tgp58 = getelementptr i8, ptr %hp57, i64 8
  store i32 0, ptr %tgp58, align 4
  %fp59 = getelementptr i8, ptr %hp57, i64 16
  store ptr @$lam502$apply, ptr %fp59, align 8
  %ld60 = load i64, ptr %n.addr
  %fp61 = getelementptr i8, ptr %hp57, i64 24
  store i64 %ld60, ptr %fp61, align 8
  %ld62 = load ptr, ptr %pool.addr
  %fp63 = getelementptr i8, ptr %hp57, i64 32
  store ptr %ld62, ptr %fp63, align 8
  %ld64 = load i64, ptr %threshold.addr
  %fp65 = getelementptr i8, ptr %hp57, i64 40
  store i64 %ld64, ptr %fp65, align 8
  %$t504.addr = alloca ptr
  store ptr %hp57, ptr %$t504.addr
  %ld66 = load ptr, ptr %$t504.addr
  %fp67 = getelementptr i8, ptr %ld66, i64 16
  %fv68 = load ptr, ptr %fp67, align 8
  %tsres69 = call i64 %fv68(ptr %ld66, i64 0)
  %hp70 = call ptr @march_alloc(i64 24)
  %tgp71 = getelementptr i8, ptr %hp70, i64 8
  store i32 0, ptr %tgp71, align 4
  %fp72 = getelementptr i8, ptr %hp70, i64 16
  store i64 %tsres69, ptr %fp72, align 8
  %t2.addr = alloca ptr
  store ptr %hp70, ptr %t2.addr
  %ld73 = load ptr, ptr %t1.addr
  %fp74 = getelementptr i8, ptr %ld73, i64 16
  %fv75 = load i64, ptr %fp74, align 8
  %r1.addr = alloca i64
  store i64 %fv75, ptr %r1.addr
  %ld76 = load ptr, ptr %t2.addr
  %fp77 = getelementptr i8, ptr %ld76, i64 16
  %fv78 = load i64, ptr %fp77, align 8
  %r2.addr = alloca i64
  store i64 %fv78, ptr %r2.addr
  %ld79 = load i64, ptr %r1.addr
  %ld80 = load i64, ptr %r2.addr
  %ar81 = add i64 %ld79, %ld80
  %cv82 = inttoptr i64 %ar81 to ptr
  store ptr %cv82, ptr %res_slot34
  br label %case_merge7
case_merge7:
  %case_r83 = load ptr, ptr %res_slot34
  store ptr %case_r83, ptr %res_slot26
  br label %case_merge4
case_merge4:
  %case_r84 = load ptr, ptr %res_slot26
  %cv85 = ptrtoint ptr %case_r84 to i64
  ret i64 %cv85
}

define i64 @mixed_tiers(ptr %pool.arg) {
entry:
  %pool.addr = alloca ptr
  store ptr %pool.arg, ptr %pool.addr
  %hp86 = call ptr @march_alloc(i64 24)
  %tgp87 = getelementptr i8, ptr %hp86, i64 8
  store i32 0, ptr %tgp87, align 4
  %fp88 = getelementptr i8, ptr %hp86, i64 16
  store ptr @$lam507$apply, ptr %fp88, align 8
  %$t508.addr = alloca ptr
  store ptr %hp86, ptr %$t508.addr
  %ld89 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld89)
  %ld90 = load ptr, ptr %$t508.addr
  %fp91 = getelementptr i8, ptr %ld90, i64 16
  %fv92 = load ptr, ptr %fp91, align 8
  %tsres93 = call i64 %fv92(ptr %ld90, i64 0)
  %hp94 = call ptr @march_alloc(i64 24)
  %tgp95 = getelementptr i8, ptr %hp94, i64 8
  store i32 0, ptr %tgp95, align 4
  %fp96 = getelementptr i8, ptr %hp94, i64 16
  store i64 %tsres93, ptr %fp96, align 8
  %t1.addr = alloca ptr
  store ptr %hp94, ptr %t1.addr
  %hp97 = call ptr @march_alloc(i64 24)
  %tgp98 = getelementptr i8, ptr %hp97, i64 8
  store i32 0, ptr %tgp98, align 4
  %fp99 = getelementptr i8, ptr %hp97, i64 16
  store ptr @$lam509$apply, ptr %fp99, align 8
  %$t510.addr = alloca ptr
  store ptr %hp97, ptr %$t510.addr
  %ld100 = load ptr, ptr %$t510.addr
  %fp101 = getelementptr i8, ptr %ld100, i64 16
  %fv102 = load ptr, ptr %fp101, align 8
  %tsres103 = call i64 %fv102(ptr %ld100, i64 0)
  %hp104 = call ptr @march_alloc(i64 24)
  %tgp105 = getelementptr i8, ptr %hp104, i64 8
  store i32 0, ptr %tgp105, align 4
  %fp106 = getelementptr i8, ptr %hp104, i64 16
  store i64 %tsres103, ptr %fp106, align 8
  %t2.addr = alloca ptr
  store ptr %hp104, ptr %t2.addr
  %ld107 = load ptr, ptr %t1.addr
  %fp108 = getelementptr i8, ptr %ld107, i64 16
  %fv109 = load i64, ptr %fp108, align 8
  %r1.addr = alloca i64
  store i64 %fv109, ptr %r1.addr
  %ld110 = load ptr, ptr %t2.addr
  %fp111 = getelementptr i8, ptr %ld110, i64 16
  %fv112 = load i64, ptr %fp111, align 8
  %r2.addr = alloca i64
  store i64 %fv112, ptr %r2.addr
  %ld113 = load i64, ptr %r1.addr
  %ld114 = load i64, ptr %r2.addr
  %ar115 = add i64 %ld113, %ld114
  ret i64 %ar115
}

define void @march_main() {
entry:
  %pool.addr = alloca ptr
  store ptr null, ptr %pool.addr
  %sl116 = call ptr @march_string_lit(ptr @.str1, i64 30)
  call void @march_println(ptr %sl116)
  %ld117 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld117)
  %ld118 = load ptr, ptr %pool.addr
  %cr119 = call i64 @par_fib(ptr %ld118, i64 30, i64 15)
  %r.addr = alloca i64
  store i64 %cr119, ptr %r.addr
  %ld120 = load i64, ptr %r.addr
  %cr121 = call ptr @march_int_to_string(i64 %ld120)
  %$t511.addr = alloca ptr
  store ptr %cr121, ptr %$t511.addr
  %sl122 = call ptr @march_string_lit(ptr @.str2, i64 14)
  %ld123 = load ptr, ptr %$t511.addr
  %cr124 = call ptr @march_string_concat(ptr %sl122, ptr %ld123)
  %$t512.addr = alloca ptr
  store ptr %cr124, ptr %$t512.addr
  %ld125 = load ptr, ptr %$t512.addr
  call void @march_println(ptr %ld125)
  %ld126 = load ptr, ptr %pool.addr
  %cr127 = call i64 @mixed_tiers(ptr %ld126)
  %m.addr = alloca i64
  store i64 %cr127, ptr %m.addr
  %ld128 = load i64, ptr %m.addr
  %cr129 = call ptr @march_int_to_string(i64 %ld128)
  %$t513.addr = alloca ptr
  store ptr %cr129, ptr %$t513.addr
  %sl130 = call ptr @march_string_lit(ptr @.str3, i64 33)
  %ld131 = load ptr, ptr %$t513.addr
  %cr132 = call ptr @march_string_concat(ptr %sl130, ptr %ld131)
  %$t514.addr = alloca ptr
  store ptr %cr132, ptr %$t514.addr
  %ld133 = load ptr, ptr %$t514.addr
  call void @march_println(ptr %ld133)
  ret void
}

define i64 @$lam499$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld134 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld134)
  %ld135 = load ptr, ptr %$clo.addr
  %fp136 = getelementptr i8, ptr %ld135, i64 24
  %fv137 = load ptr, ptr %fp136, align 8
  %cv138 = ptrtoint ptr %fv137 to i64
  %n.addr = alloca i64
  store i64 %cv138, ptr %n.addr
  %ld139 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld139)
  %ld140 = load ptr, ptr %$clo.addr
  %fp141 = getelementptr i8, ptr %ld140, i64 32
  %fv142 = load ptr, ptr %fp141, align 8
  %pool.addr = alloca ptr
  store ptr %fv142, ptr %pool.addr
  %ld143 = load ptr, ptr %$clo.addr
  %fp144 = getelementptr i8, ptr %ld143, i64 40
  %fv145 = load i64, ptr %fp144, align 8
  %threshold.addr = alloca i64
  store i64 %fv145, ptr %threshold.addr
  %ld146 = load i64, ptr %n.addr
  %ar147 = sub i64 %ld146, 1
  %$t500.addr = alloca i64
  store i64 %ar147, ptr %$t500.addr
  %ld148 = load ptr, ptr %pool.addr
  %ld149 = load i64, ptr %$t500.addr
  %ld150 = load i64, ptr %threshold.addr
  %cr151 = call i64 @par_fib(ptr %ld148, i64 %ld149, i64 %ld150)
  ret i64 %cr151
}

define i64 @$lam502$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld152 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld152)
  %ld153 = load ptr, ptr %$clo.addr
  %fp154 = getelementptr i8, ptr %ld153, i64 24
  %fv155 = load ptr, ptr %fp154, align 8
  %cv156 = ptrtoint ptr %fv155 to i64
  %n.addr = alloca i64
  store i64 %cv156, ptr %n.addr
  %ld157 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld157)
  %ld158 = load ptr, ptr %$clo.addr
  %fp159 = getelementptr i8, ptr %ld158, i64 32
  %fv160 = load ptr, ptr %fp159, align 8
  %pool.addr = alloca ptr
  store ptr %fv160, ptr %pool.addr
  %ld161 = load ptr, ptr %$clo.addr
  %fp162 = getelementptr i8, ptr %ld161, i64 40
  %fv163 = load i64, ptr %fp162, align 8
  %threshold.addr = alloca i64
  store i64 %fv163, ptr %threshold.addr
  %ld164 = load i64, ptr %n.addr
  %ar165 = sub i64 %ld164, 2
  %$t503.addr = alloca i64
  store i64 %ar165, ptr %$t503.addr
  %ld166 = load ptr, ptr %pool.addr
  %ld167 = load i64, ptr %$t503.addr
  %ld168 = load i64, ptr %threshold.addr
  %cr169 = call i64 @par_fib(ptr %ld166, i64 %ld167, i64 %ld168)
  ret i64 %cr169
}

define i64 @$lam505$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld170 = load ptr, ptr %$clo.addr
  %fp171 = getelementptr i8, ptr %ld170, i64 24
  %fv172 = load i64, ptr %fp171, align 8
  %n.addr = alloca i64
  store i64 %fv172, ptr %n.addr
  %ld173 = load i64, ptr %n.addr
  %cr174 = call i64 @fib(i64 %ld173)
  ret i64 %cr174
}

define i64 @$lam507$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %n_i1.addr = alloca i64
  store i64 20, ptr %n_i1.addr
  %hp175 = call ptr @march_alloc(i64 32)
  %tgp176 = getelementptr i8, ptr %hp175, i64 8
  store i32 0, ptr %tgp176, align 4
  %fp177 = getelementptr i8, ptr %hp175, i64 16
  store ptr @$lam505$apply, ptr %fp177, align 8
  %ld178 = load i64, ptr %n_i1.addr
  %fp179 = getelementptr i8, ptr %hp175, i64 24
  store i64 %ld178, ptr %fp179, align 8
  %$t506_i2.addr = alloca ptr
  store ptr %hp175, ptr %$t506_i2.addr
  %ld180 = load ptr, ptr %$t506_i2.addr
  %fp181 = getelementptr i8, ptr %ld180, i64 16
  %fv182 = load ptr, ptr %fp181, align 8
  %tsres183 = call i64 %fv182(ptr %ld180, i64 0)
  %hp184 = call ptr @march_alloc(i64 24)
  %tgp185 = getelementptr i8, ptr %hp184, i64 8
  store i32 0, ptr %tgp185, align 4
  %fp186 = getelementptr i8, ptr %hp184, i64 16
  store i64 %tsres183, ptr %fp186, align 8
  %t_i3.addr = alloca ptr
  store ptr %hp184, ptr %t_i3.addr
  %ld187 = load ptr, ptr %t_i3.addr
  %fp188 = getelementptr i8, ptr %ld187, i64 16
  %fv189 = load i64, ptr %fp188, align 8
  ret i64 %fv189
}

define i64 @$lam509$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %n_i4.addr = alloca i64
  store i64 25, ptr %n_i4.addr
  %hp190 = call ptr @march_alloc(i64 32)
  %tgp191 = getelementptr i8, ptr %hp190, i64 8
  store i32 0, ptr %tgp191, align 4
  %fp192 = getelementptr i8, ptr %hp190, i64 16
  store ptr @$lam505$apply, ptr %fp192, align 8
  %ld193 = load i64, ptr %n_i4.addr
  %fp194 = getelementptr i8, ptr %hp190, i64 24
  store i64 %ld193, ptr %fp194, align 8
  %$t506_i5.addr = alloca ptr
  store ptr %hp190, ptr %$t506_i5.addr
  %ld195 = load ptr, ptr %$t506_i5.addr
  %fp196 = getelementptr i8, ptr %ld195, i64 16
  %fv197 = load ptr, ptr %fp196, align 8
  %tsres198 = call i64 %fv197(ptr %ld195, i64 0)
  %hp199 = call ptr @march_alloc(i64 24)
  %tgp200 = getelementptr i8, ptr %hp199, i64 8
  store i32 0, ptr %tgp200, align 4
  %fp201 = getelementptr i8, ptr %hp199, i64 16
  store i64 %tsres198, ptr %fp201, align 8
  %t_i6.addr = alloca ptr
  store ptr %hp199, ptr %t_i6.addr
  %ld202 = load ptr, ptr %t_i6.addr
  %fp203 = getelementptr i8, ptr %ld202, i64 16
  %fv204 = load i64, ptr %fp203, align 8
  ret i64 %fv204
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
