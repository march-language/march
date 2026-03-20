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


define ptr @irev(ptr %xs.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
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
  %ld6 = load ptr, ptr %acc.addr
  store ptr %ld6, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp7 = getelementptr i8, ptr %ld1, i64 16
  %fv8 = load i64, ptr %fp7, align 8
  %h.addr = alloca i64
  store i64 %fv8, ptr %h.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 24
  %fv10 = load ptr, ptr %fp9, align 8
  %t.addr = alloca ptr
  store ptr %fv10, ptr %t.addr
  %ld11 = load ptr, ptr %xs.addr
  %tgp12 = getelementptr i8, ptr %ld11, i64 8
  store i32 1, ptr %tgp12, align 4
  %ld13 = load i64, ptr %h.addr
  %fp14 = getelementptr i8, ptr %ld11, i64 16
  store i64 %ld13, ptr %fp14, align 8
  %ld15 = load ptr, ptr %acc.addr
  %fp16 = getelementptr i8, ptr %ld11, i64 24
  store ptr %ld15, ptr %fp16, align 8
  %$t351.addr = alloca ptr
  store ptr %ld11, ptr %$t351.addr
  %ld17 = load ptr, ptr %t.addr
  %ld18 = load ptr, ptr %$t351.addr
  %cr19 = call ptr @irev(ptr %ld17, ptr %ld18)
  store ptr %cr19, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r20 = load ptr, ptr %res_slot2
  ret ptr %case_r20
}

define ptr @irange_acc(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld21 = load i64, ptr %lo.addr
  %ld22 = load i64, ptr %hi.addr
  %cmp23 = icmp sgt i64 %ld21, %ld22
  %ar24 = zext i1 %cmp23 to i64
  %$t352.addr = alloca i64
  store i64 %ar24, ptr %$t352.addr
  %ld25 = load i64, ptr %$t352.addr
  %res_slot26 = alloca ptr
  switch i64 %ld25, label %case_default6 [
      i64 1, label %case_br7
  ]
case_br7:
  %ld27 = load ptr, ptr %acc.addr
  store ptr %ld27, ptr %res_slot26
  br label %case_merge5
case_default6:
  %ld28 = load i64, ptr %lo.addr
  %ar29 = add i64 %ld28, 1
  %$t353.addr = alloca i64
  store i64 %ar29, ptr %$t353.addr
  %hp30 = call ptr @march_alloc(i64 32)
  %tgp31 = getelementptr i8, ptr %hp30, i64 8
  store i32 1, ptr %tgp31, align 4
  %ld32 = load i64, ptr %lo.addr
  %fp33 = getelementptr i8, ptr %hp30, i64 16
  store i64 %ld32, ptr %fp33, align 8
  %ld34 = load ptr, ptr %acc.addr
  %fp35 = getelementptr i8, ptr %hp30, i64 24
  store ptr %ld34, ptr %fp35, align 8
  %$t354.addr = alloca ptr
  store ptr %hp30, ptr %$t354.addr
  %ld36 = load i64, ptr %$t353.addr
  %ld37 = load i64, ptr %hi.addr
  %ld38 = load ptr, ptr %$t354.addr
  %cr39 = call ptr @irange_acc(i64 %ld36, i64 %ld37, ptr %ld38)
  store ptr %cr39, ptr %res_slot26
  br label %case_merge5
case_merge5:
  %case_r40 = load ptr, ptr %res_slot26
  ret ptr %case_r40
}

define ptr @imap_acc(ptr %xs.arg, ptr %f.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld41 = load ptr, ptr %xs.addr
  %res_slot42 = alloca ptr
  %tgp43 = getelementptr i8, ptr %ld41, i64 8
  %tag44 = load i32, ptr %tgp43, align 4
  switch i32 %tag44, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %ld45 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld45)
  %ld46 = load ptr, ptr %acc.addr
  store ptr %ld46, ptr %res_slot42
  br label %case_merge8
case_br11:
  %fp47 = getelementptr i8, ptr %ld41, i64 16
  %fv48 = load i64, ptr %fp47, align 8
  %h.addr = alloca i64
  store i64 %fv48, ptr %h.addr
  %fp49 = getelementptr i8, ptr %ld41, i64 24
  %fv50 = load ptr, ptr %fp49, align 8
  %t.addr = alloca ptr
  store ptr %fv50, ptr %t.addr
  %ld51 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld51)
  %ld52 = load ptr, ptr %f.addr
  %fp53 = getelementptr i8, ptr %ld52, i64 16
  %fv54 = load ptr, ptr %fp53, align 8
  %ld55 = load i64, ptr %h.addr
  %cr56 = call i64 (ptr, i64) %fv54(ptr %ld52, i64 %ld55)
  %$t358.addr = alloca i64
  store i64 %cr56, ptr %$t358.addr
  %hp57 = call ptr @march_alloc(i64 32)
  %tgp58 = getelementptr i8, ptr %hp57, i64 8
  store i32 1, ptr %tgp58, align 4
  %ld59 = load i64, ptr %$t358.addr
  %fp60 = getelementptr i8, ptr %hp57, i64 16
  store i64 %ld59, ptr %fp60, align 8
  %ld61 = load ptr, ptr %acc.addr
  %fp62 = getelementptr i8, ptr %hp57, i64 24
  store ptr %ld61, ptr %fp62, align 8
  %$t359.addr = alloca ptr
  store ptr %hp57, ptr %$t359.addr
  %ld63 = load ptr, ptr %t.addr
  %ld64 = load ptr, ptr %f.addr
  %ld65 = load ptr, ptr %$t359.addr
  %cr66 = call ptr @imap_acc(ptr %ld63, ptr %ld64, ptr %ld65)
  store ptr %cr66, ptr %res_slot42
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r67 = load ptr, ptr %res_slot42
  ret ptr %case_r67
}

define ptr @ifilter_acc(ptr %xs.arg, ptr %pred.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld68 = load ptr, ptr %xs.addr
  %res_slot69 = alloca ptr
  %tgp70 = getelementptr i8, ptr %ld68, i64 8
  %tag71 = load i32, ptr %tgp70, align 4
  switch i32 %tag71, label %case_default13 [
      i32 0, label %case_br14
      i32 1, label %case_br15
  ]
case_br14:
  %ld72 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld72)
  %ld73 = load ptr, ptr %acc.addr
  store ptr %ld73, ptr %res_slot69
  br label %case_merge12
case_br15:
  %fp74 = getelementptr i8, ptr %ld68, i64 16
  %fv75 = load i64, ptr %fp74, align 8
  %h.addr = alloca i64
  store i64 %fv75, ptr %h.addr
  %fp76 = getelementptr i8, ptr %ld68, i64 24
  %fv77 = load ptr, ptr %fp76, align 8
  %t.addr = alloca ptr
  store ptr %fv77, ptr %t.addr
  %ld78 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld78)
  %ld79 = load ptr, ptr %pred.addr
  %fp80 = getelementptr i8, ptr %ld79, i64 16
  %fv81 = load ptr, ptr %fp80, align 8
  %ld82 = load i64, ptr %h.addr
  %cr83 = call i64 (ptr, i64) %fv81(ptr %ld79, i64 %ld82)
  %$t363.addr = alloca i64
  store i64 %cr83, ptr %$t363.addr
  %ld84 = load i64, ptr %$t363.addr
  %res_slot85 = alloca ptr
  switch i64 %ld84, label %case_default17 [
      i64 1, label %case_br18
  ]
case_br18:
  %hp86 = call ptr @march_alloc(i64 32)
  %tgp87 = getelementptr i8, ptr %hp86, i64 8
  store i32 1, ptr %tgp87, align 4
  %ld88 = load i64, ptr %h.addr
  %fp89 = getelementptr i8, ptr %hp86, i64 16
  store i64 %ld88, ptr %fp89, align 8
  %ld90 = load ptr, ptr %acc.addr
  %fp91 = getelementptr i8, ptr %hp86, i64 24
  store ptr %ld90, ptr %fp91, align 8
  %$t364.addr = alloca ptr
  store ptr %hp86, ptr %$t364.addr
  %ld92 = load ptr, ptr %t.addr
  %ld93 = load ptr, ptr %pred.addr
  %ld94 = load ptr, ptr %$t364.addr
  %cr95 = call ptr @ifilter_acc(ptr %ld92, ptr %ld93, ptr %ld94)
  store ptr %cr95, ptr %res_slot85
  br label %case_merge16
case_default17:
  %ld96 = load ptr, ptr %t.addr
  %ld97 = load ptr, ptr %pred.addr
  %ld98 = load ptr, ptr %acc.addr
  %cr99 = call ptr @ifilter_acc(ptr %ld96, ptr %ld97, ptr %ld98)
  store ptr %cr99, ptr %res_slot85
  br label %case_merge16
case_merge16:
  %case_r100 = load ptr, ptr %res_slot85
  store ptr %case_r100, ptr %res_slot69
  br label %case_merge12
case_default13:
  unreachable
case_merge12:
  %case_r101 = load ptr, ptr %res_slot69
  ret ptr %case_r101
}

define i64 @ifold(ptr %xs.arg, i64 %acc.arg, ptr %f.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld102 = load ptr, ptr %xs.addr
  %res_slot103 = alloca ptr
  %tgp104 = getelementptr i8, ptr %ld102, i64 8
  %tag105 = load i32, ptr %tgp104, align 4
  switch i32 %tag105, label %case_default20 [
      i32 0, label %case_br21
      i32 1, label %case_br22
  ]
case_br21:
  %ld106 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld106)
  %ld107 = load i64, ptr %acc.addr
  %cv108 = inttoptr i64 %ld107 to ptr
  store ptr %cv108, ptr %res_slot103
  br label %case_merge19
case_br22:
  %fp109 = getelementptr i8, ptr %ld102, i64 16
  %fv110 = load i64, ptr %fp109, align 8
  %h.addr = alloca i64
  store i64 %fv110, ptr %h.addr
  %fp111 = getelementptr i8, ptr %ld102, i64 24
  %fv112 = load ptr, ptr %fp111, align 8
  %t.addr = alloca ptr
  store ptr %fv112, ptr %t.addr
  %ld113 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld113)
  %ld114 = load ptr, ptr %f.addr
  %fp115 = getelementptr i8, ptr %ld114, i64 16
  %fv116 = load ptr, ptr %fp115, align 8
  %ld117 = load i64, ptr %acc.addr
  %ld118 = load i64, ptr %h.addr
  %cr119 = call i64 (ptr, i64, i64) %fv116(ptr %ld114, i64 %ld117, i64 %ld118)
  %$t368.addr = alloca i64
  store i64 %cr119, ptr %$t368.addr
  %ld120 = load ptr, ptr %t.addr
  %ld121 = load i64, ptr %$t368.addr
  %ld122 = load ptr, ptr %f.addr
  %cr123 = call i64 @ifold(ptr %ld120, i64 %ld121, ptr %ld122)
  %cv124 = inttoptr i64 %cr123 to ptr
  store ptr %cv124, ptr %res_slot103
  br label %case_merge19
case_default20:
  unreachable
case_merge19:
  %case_r125 = load ptr, ptr %res_slot103
  %cv126 = ptrtoint ptr %case_r125 to i64
  ret i64 %cv126
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 1000000, ptr %n.addr
  %lo_i11.addr = alloca i64
  store i64 1, ptr %lo_i11.addr
  %ld127 = load i64, ptr %n.addr
  %hi_i12.addr = alloca i64
  store i64 %ld127, ptr %hi_i12.addr
  %hp128 = call ptr @march_alloc(i64 16)
  %tgp129 = getelementptr i8, ptr %hp128, i64 8
  store i32 0, ptr %tgp129, align 4
  %$t355_i13.addr = alloca ptr
  store ptr %hp128, ptr %$t355_i13.addr
  %ld130 = load i64, ptr %lo_i11.addr
  %ld131 = load i64, ptr %hi_i12.addr
  %ld132 = load ptr, ptr %$t355_i13.addr
  %cr133 = call ptr @irange_acc(i64 %ld130, i64 %ld131, ptr %ld132)
  %$t356_i14.addr = alloca ptr
  store ptr %cr133, ptr %$t356_i14.addr
  %hp134 = call ptr @march_alloc(i64 16)
  %tgp135 = getelementptr i8, ptr %hp134, i64 8
  store i32 0, ptr %tgp135, align 4
  %$t357_i15.addr = alloca ptr
  store ptr %hp134, ptr %$t357_i15.addr
  %ld136 = load ptr, ptr %$t356_i14.addr
  %ld137 = load ptr, ptr %$t357_i15.addr
  %cr138 = call ptr @irev(ptr %ld136, ptr %ld137)
  %xs.addr = alloca ptr
  store ptr %cr138, ptr %xs.addr
  %hp139 = call ptr @march_alloc(i64 24)
  %tgp140 = getelementptr i8, ptr %hp139, i64 8
  store i32 0, ptr %tgp140, align 4
  %fp141 = getelementptr i8, ptr %hp139, i64 16
  store ptr @$lam369$apply, ptr %fp141, align 8
  %$t370.addr = alloca ptr
  store ptr %hp139, ptr %$t370.addr
  %ld142 = load ptr, ptr %xs.addr
  %xs_i6.addr = alloca ptr
  store ptr %ld142, ptr %xs_i6.addr
  %ld143 = load ptr, ptr %$t370.addr
  %f_i7.addr = alloca ptr
  store ptr %ld143, ptr %f_i7.addr
  %hp144 = call ptr @march_alloc(i64 16)
  %tgp145 = getelementptr i8, ptr %hp144, i64 8
  store i32 0, ptr %tgp145, align 4
  %$t360_i8.addr = alloca ptr
  store ptr %hp144, ptr %$t360_i8.addr
  %ld146 = load ptr, ptr %xs_i6.addr
  %ld147 = load ptr, ptr %f_i7.addr
  %ld148 = load ptr, ptr %$t360_i8.addr
  %cr149 = call ptr @imap_acc(ptr %ld146, ptr %ld147, ptr %ld148)
  %$t361_i9.addr = alloca ptr
  store ptr %cr149, ptr %$t361_i9.addr
  %hp150 = call ptr @march_alloc(i64 16)
  %tgp151 = getelementptr i8, ptr %hp150, i64 8
  store i32 0, ptr %tgp151, align 4
  %$t362_i10.addr = alloca ptr
  store ptr %hp150, ptr %$t362_i10.addr
  %ld152 = load ptr, ptr %$t361_i9.addr
  %ld153 = load ptr, ptr %$t362_i10.addr
  %cr154 = call ptr @irev(ptr %ld152, ptr %ld153)
  %ys.addr = alloca ptr
  store ptr %cr154, ptr %ys.addr
  %hp155 = call ptr @march_alloc(i64 24)
  %tgp156 = getelementptr i8, ptr %hp155, i64 8
  store i32 0, ptr %tgp156, align 4
  %fp157 = getelementptr i8, ptr %hp155, i64 16
  store ptr @$lam371$apply, ptr %fp157, align 8
  %$t373.addr = alloca ptr
  store ptr %hp155, ptr %$t373.addr
  %ld158 = load ptr, ptr %ys.addr
  %xs_i1.addr = alloca ptr
  store ptr %ld158, ptr %xs_i1.addr
  %ld159 = load ptr, ptr %$t373.addr
  %pred_i2.addr = alloca ptr
  store ptr %ld159, ptr %pred_i2.addr
  %hp160 = call ptr @march_alloc(i64 16)
  %tgp161 = getelementptr i8, ptr %hp160, i64 8
  store i32 0, ptr %tgp161, align 4
  %$t365_i3.addr = alloca ptr
  store ptr %hp160, ptr %$t365_i3.addr
  %ld162 = load ptr, ptr %xs_i1.addr
  %ld163 = load ptr, ptr %pred_i2.addr
  %ld164 = load ptr, ptr %$t365_i3.addr
  %cr165 = call ptr @ifilter_acc(ptr %ld162, ptr %ld163, ptr %ld164)
  %$t366_i4.addr = alloca ptr
  store ptr %cr165, ptr %$t366_i4.addr
  %hp166 = call ptr @march_alloc(i64 16)
  %tgp167 = getelementptr i8, ptr %hp166, i64 8
  store i32 0, ptr %tgp167, align 4
  %$t367_i5.addr = alloca ptr
  store ptr %hp166, ptr %$t367_i5.addr
  %ld168 = load ptr, ptr %$t366_i4.addr
  %ld169 = load ptr, ptr %$t367_i5.addr
  %cr170 = call ptr @irev(ptr %ld168, ptr %ld169)
  %zs.addr = alloca ptr
  store ptr %cr170, ptr %zs.addr
  %hp171 = call ptr @march_alloc(i64 24)
  %tgp172 = getelementptr i8, ptr %hp171, i64 8
  store i32 0, ptr %tgp172, align 4
  %fp173 = getelementptr i8, ptr %hp171, i64 16
  store ptr @$lam374$apply, ptr %fp173, align 8
  %$t375.addr = alloca ptr
  store ptr %hp171, ptr %$t375.addr
  %ld174 = load ptr, ptr %zs.addr
  %ld175 = load ptr, ptr %$t375.addr
  %cr176 = call i64 @ifold(ptr %ld174, i64 0, ptr %ld175)
  %total.addr = alloca i64
  store i64 %cr176, ptr %total.addr
  %ld177 = load i64, ptr %total.addr
  %cr178 = call ptr @march_int_to_string(i64 %ld177)
  %$t376.addr = alloca ptr
  store ptr %cr178, ptr %$t376.addr
  %ld179 = load ptr, ptr %$t376.addr
  call void @march_println(ptr %ld179)
  ret void
}

define i64 @$lam369$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld180 = load i64, ptr %x.addr
  %ld181 = load i64, ptr %x.addr
  %ar182 = add i64 %ld180, %ld181
  %sr_s1.addr = alloca i64
  store i64 %ar182, ptr %sr_s1.addr
  %ld183 = load i64, ptr %sr_s1.addr
  ret i64 %ld183
}

define i64 @$lam371$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld184 = load i64, ptr %x.addr
  %ar185 = srem i64 %ld184, 3
  %$t372.addr = alloca i64
  store i64 %ar185, ptr %$t372.addr
  %ld186 = load i64, ptr %$t372.addr
  %cmp187 = icmp eq i64 %ld186, 0
  %ar188 = zext i1 %cmp187 to i64
  ret i64 %ar188
}

define i64 @$lam374$apply(ptr %$clo.arg, i64 %a.arg, i64 %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca i64
  store i64 %a.arg, ptr %a.addr
  %b.addr = alloca i64
  store i64 %b.arg, ptr %b.addr
  %ld189 = load i64, ptr %a.addr
  %ld190 = load i64, ptr %b.addr
  %ar191 = add i64 %ld189, %ld190
  ret i64 %ar191
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
