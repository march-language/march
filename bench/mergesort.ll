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


define ptr @merge(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld1 = load ptr, ptr %xs.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld5 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld5)
  %ld6 = load ptr, ptr %ys.addr
  store ptr %ld6, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp7 = getelementptr i8, ptr %ld1, i64 16
  %fv8 = load ptr, ptr %fp7, align 8
  %x.addr = alloca ptr
  store ptr %fv8, ptr %x.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 24
  %fv10 = load ptr, ptr %fp9, align 8
  %xt.addr = alloca ptr
  store ptr %fv10, ptr %xt.addr
  %ld11 = load ptr, ptr %ys.addr
  %res_slot12 = alloca ptr
  %tgp13 = getelementptr i8, ptr %ld11, i64 8
  %tag14 = load i32, ptr %tgp13, align 4
  switch i32 %tag14, label %case_default6 [
      i32 0, label %case_br7
      i32 1, label %case_br8
  ]
case_br7:
  %ld15 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld15)
  %ld16 = load ptr, ptr %xs.addr
  store ptr %ld16, ptr %res_slot12
  br label %case_merge5
case_br8:
  %fp17 = getelementptr i8, ptr %ld11, i64 16
  %fv18 = load ptr, ptr %fp17, align 8
  %y.addr = alloca ptr
  store ptr %fv18, ptr %y.addr
  %fp19 = getelementptr i8, ptr %ld11, i64 24
  %fv20 = load ptr, ptr %fp19, align 8
  %yt.addr = alloca ptr
  store ptr %fv20, ptr %yt.addr
  %ld21 = load i64, ptr %x.addr
  %ld22 = load i64, ptr %y.addr
  %cmp23 = icmp sle i64 %ld21, %ld22
  %ar24 = zext i1 %cmp23 to i64
  %$t492.addr = alloca i64
  store i64 %ar24, ptr %$t492.addr
  %ld25 = load i64, ptr %$t492.addr
  %res_slot26 = alloca ptr
  switch i64 %ld25, label %case_default10 [
      i64 1, label %case_br11
  ]
case_br11:
  %ld27 = load ptr, ptr %xt.addr
  %ld28 = load ptr, ptr %ys.addr
  %cr29 = call ptr @merge(ptr %ld27, ptr %ld28)
  %$t493.addr = alloca ptr
  store ptr %cr29, ptr %$t493.addr
  %hp30 = call ptr @march_alloc(i64 32)
  %tgp31 = getelementptr i8, ptr %hp30, i64 8
  store i32 1, ptr %tgp31, align 4
  %ld32 = load i64, ptr %x.addr
  %cv33 = inttoptr i64 %ld32 to ptr
  %fp34 = getelementptr i8, ptr %hp30, i64 16
  store ptr %cv33, ptr %fp34, align 8
  %ld35 = load ptr, ptr %$t493.addr
  %fp36 = getelementptr i8, ptr %hp30, i64 24
  store ptr %ld35, ptr %fp36, align 8
  store ptr %hp30, ptr %res_slot26
  br label %case_merge9
case_default10:
  %ld37 = load ptr, ptr %xs.addr
  %ld38 = load ptr, ptr %yt.addr
  %cr39 = call ptr @merge(ptr %ld37, ptr %ld38)
  %$t494.addr = alloca ptr
  store ptr %cr39, ptr %$t494.addr
  %hp40 = call ptr @march_alloc(i64 32)
  %tgp41 = getelementptr i8, ptr %hp40, i64 8
  store i32 1, ptr %tgp41, align 4
  %ld42 = load i64, ptr %y.addr
  %cv43 = inttoptr i64 %ld42 to ptr
  %fp44 = getelementptr i8, ptr %hp40, i64 16
  store ptr %cv43, ptr %fp44, align 8
  %ld45 = load ptr, ptr %$t494.addr
  %fp46 = getelementptr i8, ptr %hp40, i64 24
  store ptr %ld45, ptr %fp46, align 8
  store ptr %hp40, ptr %res_slot26
  br label %case_merge9
case_merge9:
  %case_r47 = load ptr, ptr %res_slot26
  store ptr %case_r47, ptr %res_slot12
  br label %case_merge5
case_default6:
  unreachable
case_merge5:
  %case_r48 = load ptr, ptr %res_slot12
  store ptr %case_r48, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r49 = load ptr, ptr %res_slot2
  ret ptr %case_r49
}

define ptr @split(ptr %xs.arg, ptr %left.arg, ptr %right.arg, i64 %toggle.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %left.addr = alloca ptr
  store ptr %left.arg, ptr %left.addr
  %right.addr = alloca ptr
  store ptr %right.arg, ptr %right.addr
  %toggle.addr = alloca i64
  store i64 %toggle.arg, ptr %toggle.addr
  %ld50 = load ptr, ptr %xs.addr
  %res_slot51 = alloca ptr
  %tgp52 = getelementptr i8, ptr %ld50, i64 8
  %tag53 = load i32, ptr %tgp52, align 4
  switch i32 %tag53, label %case_default13 [
      i32 0, label %case_br14
      i32 1, label %case_br15
  ]
case_br14:
  %ld54 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld54)
  %hp55 = call ptr @march_alloc(i64 32)
  %tgp56 = getelementptr i8, ptr %hp55, i64 8
  store i32 0, ptr %tgp56, align 4
  %ld57 = load ptr, ptr %left.addr
  %fp58 = getelementptr i8, ptr %hp55, i64 16
  store ptr %ld57, ptr %fp58, align 8
  %ld59 = load ptr, ptr %right.addr
  %fp60 = getelementptr i8, ptr %hp55, i64 24
  store ptr %ld59, ptr %fp60, align 8
  store ptr %hp55, ptr %res_slot51
  br label %case_merge12
case_br15:
  %fp61 = getelementptr i8, ptr %ld50, i64 16
  %fv62 = load ptr, ptr %fp61, align 8
  %h.addr = alloca ptr
  store ptr %fv62, ptr %h.addr
  %fp63 = getelementptr i8, ptr %ld50, i64 24
  %fv64 = load ptr, ptr %fp63, align 8
  %t.addr = alloca ptr
  store ptr %fv64, ptr %t.addr
  %freed65 = call i64 @march_decrc_freed(ptr %ld50)
  %freed_b66 = icmp ne i64 %freed65, 0
  br i1 %freed_b66, label %br_unique16, label %br_shared17
br_shared17:
  call void @march_incrc(ptr %fv64)
  br label %br_body18
br_unique16:
  br label %br_body18
br_body18:
  %ld67 = load i64, ptr %toggle.addr
  %res_slot68 = alloca ptr
  switch i64 %ld67, label %case_default20 [
      i64 1, label %case_br21
  ]
case_br21:
  %hp69 = call ptr @march_alloc(i64 32)
  %tgp70 = getelementptr i8, ptr %hp69, i64 8
  store i32 1, ptr %tgp70, align 4
  %ld71 = load i64, ptr %h.addr
  %cv72 = inttoptr i64 %ld71 to ptr
  %fp73 = getelementptr i8, ptr %hp69, i64 16
  store ptr %cv72, ptr %fp73, align 8
  %ld74 = load ptr, ptr %left.addr
  %fp75 = getelementptr i8, ptr %hp69, i64 24
  store ptr %ld74, ptr %fp75, align 8
  %$t495.addr = alloca ptr
  store ptr %hp69, ptr %$t495.addr
  %ld76 = load ptr, ptr %t.addr
  %ld77 = load ptr, ptr %$t495.addr
  %ld78 = load ptr, ptr %right.addr
  %cr79 = call ptr @split(ptr %ld76, ptr %ld77, ptr %ld78, i64 0)
  store ptr %cr79, ptr %res_slot68
  br label %case_merge19
case_default20:
  %hp80 = call ptr @march_alloc(i64 32)
  %tgp81 = getelementptr i8, ptr %hp80, i64 8
  store i32 1, ptr %tgp81, align 4
  %ld82 = load i64, ptr %h.addr
  %cv83 = inttoptr i64 %ld82 to ptr
  %fp84 = getelementptr i8, ptr %hp80, i64 16
  store ptr %cv83, ptr %fp84, align 8
  %ld85 = load ptr, ptr %right.addr
  %fp86 = getelementptr i8, ptr %hp80, i64 24
  store ptr %ld85, ptr %fp86, align 8
  %$t496.addr = alloca ptr
  store ptr %hp80, ptr %$t496.addr
  %ld87 = load ptr, ptr %t.addr
  %ld88 = load ptr, ptr %left.addr
  %ld89 = load ptr, ptr %$t496.addr
  %cr90 = call ptr @split(ptr %ld87, ptr %ld88, ptr %ld89, i64 1)
  store ptr %cr90, ptr %res_slot68
  br label %case_merge19
case_merge19:
  %case_r91 = load ptr, ptr %res_slot68
  store ptr %case_r91, ptr %res_slot51
  br label %case_merge12
case_default13:
  unreachable
case_merge12:
  %case_r92 = load ptr, ptr %res_slot51
  ret ptr %case_r92
}

define ptr @mergesort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld93 = load ptr, ptr %xs.addr
  %res_slot94 = alloca ptr
  %tgp95 = getelementptr i8, ptr %ld93, i64 8
  %tag96 = load i32, ptr %tgp95, align 4
  switch i32 %tag96, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
  ]
case_br24:
  %ld97 = load ptr, ptr %xs.addr
  %rc98 = load i64, ptr %ld97, align 8
  %uniq99 = icmp eq i64 %rc98, 1
  %fbip_slot100 = alloca ptr
  br i1 %uniq99, label %fbip_reuse26, label %fbip_fresh27
fbip_reuse26:
  %tgp101 = getelementptr i8, ptr %ld97, i64 8
  store i32 0, ptr %tgp101, align 4
  store ptr %ld97, ptr %fbip_slot100
  br label %fbip_merge28
fbip_fresh27:
  call void @march_decrc(ptr %ld97)
  %hp102 = call ptr @march_alloc(i64 16)
  %tgp103 = getelementptr i8, ptr %hp102, i64 8
  store i32 0, ptr %tgp103, align 4
  store ptr %hp102, ptr %fbip_slot100
  br label %fbip_merge28
fbip_merge28:
  %fbip_r104 = load ptr, ptr %fbip_slot100
  store ptr %fbip_r104, ptr %res_slot94
  br label %case_merge22
case_br25:
  %fp105 = getelementptr i8, ptr %ld93, i64 16
  %fv106 = load ptr, ptr %fp105, align 8
  %h.addr = alloca ptr
  store ptr %fv106, ptr %h.addr
  %fp107 = getelementptr i8, ptr %ld93, i64 24
  %fv108 = load ptr, ptr %fp107, align 8
  %t.addr = alloca ptr
  store ptr %fv108, ptr %t.addr
  %freed109 = call i64 @march_decrc_freed(ptr %ld93)
  %freed_b110 = icmp ne i64 %freed109, 0
  br i1 %freed_b110, label %br_unique29, label %br_shared30
br_shared30:
  call void @march_incrc(ptr %fv108)
  br label %br_body31
br_unique29:
  br label %br_body31
br_body31:
  %ld111 = load ptr, ptr %t.addr
  %res_slot112 = alloca ptr
  %tgp113 = getelementptr i8, ptr %ld111, i64 8
  %tag114 = load i32, ptr %tgp113, align 4
  switch i32 %tag114, label %case_default33 [
      i32 0, label %case_br34
  ]
case_br34:
  %ld115 = load ptr, ptr %t.addr
  %rc116 = load i64, ptr %ld115, align 8
  %uniq117 = icmp eq i64 %rc116, 1
  %fbip_slot118 = alloca ptr
  br i1 %uniq117, label %fbip_reuse35, label %fbip_fresh36
fbip_reuse35:
  %tgp119 = getelementptr i8, ptr %ld115, i64 8
  store i32 0, ptr %tgp119, align 4
  store ptr %ld115, ptr %fbip_slot118
  br label %fbip_merge37
fbip_fresh36:
  call void @march_decrc(ptr %ld115)
  %hp120 = call ptr @march_alloc(i64 16)
  %tgp121 = getelementptr i8, ptr %hp120, i64 8
  store i32 0, ptr %tgp121, align 4
  store ptr %hp120, ptr %fbip_slot118
  br label %fbip_merge37
fbip_merge37:
  %fbip_r122 = load ptr, ptr %fbip_slot118
  %$t497.addr = alloca ptr
  store ptr %fbip_r122, ptr %$t497.addr
  %hp123 = call ptr @march_alloc(i64 32)
  %tgp124 = getelementptr i8, ptr %hp123, i64 8
  store i32 1, ptr %tgp124, align 4
  %ld125 = load i64, ptr %h.addr
  %cv126 = inttoptr i64 %ld125 to ptr
  %fp127 = getelementptr i8, ptr %hp123, i64 16
  store ptr %cv126, ptr %fp127, align 8
  %ld128 = load ptr, ptr %$t497.addr
  %fp129 = getelementptr i8, ptr %hp123, i64 24
  store ptr %ld128, ptr %fp129, align 8
  store ptr %hp123, ptr %res_slot112
  br label %case_merge32
case_default33:
  %hp130 = call ptr @march_alloc(i64 32)
  %tgp131 = getelementptr i8, ptr %hp130, i64 8
  store i32 1, ptr %tgp131, align 4
  %ld132 = load i64, ptr %h.addr
  %cv133 = inttoptr i64 %ld132 to ptr
  %fp134 = getelementptr i8, ptr %hp130, i64 16
  store ptr %cv133, ptr %fp134, align 8
  %ld135 = load ptr, ptr %t.addr
  %fp136 = getelementptr i8, ptr %hp130, i64 24
  store ptr %ld135, ptr %fp136, align 8
  %xs2.addr = alloca ptr
  store ptr %hp130, ptr %xs2.addr
  %hp137 = call ptr @march_alloc(i64 16)
  %tgp138 = getelementptr i8, ptr %hp137, i64 8
  store i32 0, ptr %tgp138, align 4
  %$t498.addr = alloca ptr
  store ptr %hp137, ptr %$t498.addr
  %hp139 = call ptr @march_alloc(i64 16)
  %tgp140 = getelementptr i8, ptr %hp139, i64 8
  store i32 0, ptr %tgp140, align 4
  %$t499.addr = alloca ptr
  store ptr %hp139, ptr %$t499.addr
  %ld141 = load ptr, ptr %xs2.addr
  %ld142 = load ptr, ptr %$t498.addr
  %ld143 = load ptr, ptr %$t499.addr
  %cr144 = call ptr @split(ptr %ld141, ptr %ld142, ptr %ld143, i64 1)
  %$p502.addr = alloca ptr
  store ptr %cr144, ptr %$p502.addr
  %ld145 = load ptr, ptr %$p502.addr
  %fp146 = getelementptr i8, ptr %ld145, i64 16
  %fv147 = load ptr, ptr %fp146, align 8
  %l.addr = alloca ptr
  store ptr %fv147, ptr %l.addr
  %ld148 = load ptr, ptr %$p502.addr
  %fp149 = getelementptr i8, ptr %ld148, i64 24
  %fv150 = load ptr, ptr %fp149, align 8
  %r.addr = alloca ptr
  store ptr %fv150, ptr %r.addr
  %ld151 = load ptr, ptr %l.addr
  %cr152 = call ptr @mergesort(ptr %ld151)
  %$t500.addr = alloca ptr
  store ptr %cr152, ptr %$t500.addr
  %ld153 = load ptr, ptr %r.addr
  %cr154 = call ptr @mergesort(ptr %ld153)
  %$t501.addr = alloca ptr
  store ptr %cr154, ptr %$t501.addr
  %ld155 = load ptr, ptr %$t500.addr
  %ld156 = load ptr, ptr %$t501.addr
  %cr157 = call ptr @merge(ptr %ld155, ptr %ld156)
  store ptr %cr157, ptr %res_slot112
  br label %case_merge32
case_merge32:
  %case_r158 = load ptr, ptr %res_slot112
  store ptr %case_r158, ptr %res_slot94
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r159 = load ptr, ptr %res_slot94
  ret ptr %case_r159
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld160 = load i64, ptr %n.addr
  %cmp161 = icmp eq i64 %ld160, 0
  %ar162 = zext i1 %cmp161 to i64
  %$t503.addr = alloca i64
  store i64 %ar162, ptr %$t503.addr
  %ld163 = load i64, ptr %$t503.addr
  %res_slot164 = alloca ptr
  switch i64 %ld163, label %case_default39 [
      i64 1, label %case_br40
  ]
case_br40:
  %ld165 = load ptr, ptr %acc.addr
  store ptr %ld165, ptr %res_slot164
  br label %case_merge38
case_default39:
  %ld166 = load i64, ptr %seed.addr
  %ar167 = mul i64 %ld166, 1664525
  %$t504.addr = alloca i64
  store i64 %ar167, ptr %$t504.addr
  %ld168 = load i64, ptr %$t504.addr
  %ar169 = add i64 %ld168, 1013904223
  %$t505.addr = alloca i64
  store i64 %ar169, ptr %$t505.addr
  %ld170 = load i64, ptr %$t505.addr
  %ar171 = srem i64 %ld170, 1000000
  %next.addr = alloca i64
  store i64 %ar171, ptr %next.addr
  %ld172 = load i64, ptr %n.addr
  %ar173 = sub i64 %ld172, 1
  %$t506.addr = alloca i64
  store i64 %ar173, ptr %$t506.addr
  %ld174 = load i64, ptr %next.addr
  %ar175 = srem i64 %ld174, 100000
  %$t507.addr = alloca i64
  store i64 %ar175, ptr %$t507.addr
  %hp176 = call ptr @march_alloc(i64 32)
  %tgp177 = getelementptr i8, ptr %hp176, i64 8
  store i32 1, ptr %tgp177, align 4
  %ld178 = load i64, ptr %$t507.addr
  %cv179 = inttoptr i64 %ld178 to ptr
  %fp180 = getelementptr i8, ptr %hp176, i64 16
  store ptr %cv179, ptr %fp180, align 8
  %ld181 = load ptr, ptr %acc.addr
  %fp182 = getelementptr i8, ptr %hp176, i64 24
  store ptr %ld181, ptr %fp182, align 8
  %$t508.addr = alloca ptr
  store ptr %hp176, ptr %$t508.addr
  %ld183 = load i64, ptr %$t506.addr
  %ld184 = load i64, ptr %next.addr
  %ld185 = load ptr, ptr %$t508.addr
  %cr186 = call ptr @gen_list(i64 %ld183, i64 %ld184, ptr %ld185)
  store ptr %cr186, ptr %res_slot164
  br label %case_merge38
case_merge38:
  %case_r187 = load ptr, ptr %res_slot164
  ret ptr %case_r187
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld188 = load ptr, ptr %xs.addr
  %res_slot189 = alloca ptr
  %tgp190 = getelementptr i8, ptr %ld188, i64 8
  %tag191 = load i32, ptr %tgp190, align 4
  switch i32 %tag191, label %case_default42 [
      i32 0, label %case_br43
      i32 1, label %case_br44
  ]
case_br43:
  %ld192 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld192)
  %cv193 = inttoptr i64 0 to ptr
  store ptr %cv193, ptr %res_slot189
  br label %case_merge41
case_br44:
  %fp194 = getelementptr i8, ptr %ld188, i64 16
  %fv195 = load ptr, ptr %fp194, align 8
  %h.addr = alloca ptr
  store ptr %fv195, ptr %h.addr
  %fp196 = getelementptr i8, ptr %ld188, i64 24
  %fv197 = load ptr, ptr %fp196, align 8
  %$w509.addr = alloca ptr
  store ptr %fv197, ptr %$w509.addr
  %freed198 = call i64 @march_decrc_freed(ptr %ld188)
  %freed_b199 = icmp ne i64 %freed198, 0
  br i1 %freed_b199, label %br_unique45, label %br_shared46
br_shared46:
  call void @march_incrc(ptr %fv197)
  br label %br_body47
br_unique45:
  br label %br_body47
br_body47:
  %ld200 = load i64, ptr %h.addr
  %cv201 = inttoptr i64 %ld200 to ptr
  store ptr %cv201, ptr %res_slot189
  br label %case_merge41
case_default42:
  unreachable
case_merge41:
  %case_r202 = load ptr, ptr %res_slot189
  %cv203 = ptrtoint ptr %case_r202 to i64
  ret i64 %cv203
}

define void @march_main() {
entry:
  %hp204 = call ptr @march_alloc(i64 16)
  %tgp205 = getelementptr i8, ptr %hp204, i64 8
  store i32 0, ptr %tgp205, align 4
  %$t510.addr = alloca ptr
  store ptr %hp204, ptr %$t510.addr
  %ld206 = load ptr, ptr %$t510.addr
  %cr207 = call ptr @gen_list(i64 10000, i64 42, ptr %ld206)
  %xs.addr = alloca ptr
  store ptr %cr207, ptr %xs.addr
  %ld208 = load ptr, ptr %xs.addr
  %cr209 = call ptr @mergesort(ptr %ld208)
  %sorted.addr = alloca ptr
  store ptr %cr209, ptr %sorted.addr
  %ld210 = load ptr, ptr %sorted.addr
  %cr211 = call i64 @head(ptr %ld210)
  %$t511.addr = alloca i64
  store i64 %cr211, ptr %$t511.addr
  %ld212 = load i64, ptr %$t511.addr
  %cr213 = call ptr @march_int_to_string(i64 %ld212)
  %$t512.addr = alloca ptr
  store ptr %cr213, ptr %$t512.addr
  %ld214 = load ptr, ptr %$t512.addr
  call void @march_println(ptr %ld214)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
