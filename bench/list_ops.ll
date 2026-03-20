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
  %ld12 = load i64, ptr %h.addr
  %ld13 = load ptr, ptr %acc.addr
  %rc14 = load i64, ptr %ld11, align 8
  %uniq15 = icmp eq i64 %rc14, 1
  %fbip_slot16 = alloca ptr
  br i1 %uniq15, label %fbip_reuse5, label %fbip_fresh6
fbip_reuse5:
  %tgp17 = getelementptr i8, ptr %ld11, i64 8
  store i32 1, ptr %tgp17, align 4
  %fp18 = getelementptr i8, ptr %ld11, i64 16
  store i64 %ld12, ptr %fp18, align 8
  %fp19 = getelementptr i8, ptr %ld11, i64 24
  store ptr %ld13, ptr %fp19, align 8
  store ptr %ld11, ptr %fbip_slot16
  br label %fbip_merge7
fbip_fresh6:
  call void @march_decrc(ptr %ld11)
  %hp20 = call ptr @march_alloc(i64 32)
  %tgp21 = getelementptr i8, ptr %hp20, i64 8
  store i32 1, ptr %tgp21, align 4
  %fp22 = getelementptr i8, ptr %hp20, i64 16
  store i64 %ld12, ptr %fp22, align 8
  %fp23 = getelementptr i8, ptr %hp20, i64 24
  store ptr %ld13, ptr %fp23, align 8
  store ptr %hp20, ptr %fbip_slot16
  br label %fbip_merge7
fbip_merge7:
  %fbip_r24 = load ptr, ptr %fbip_slot16
  %$t574.addr = alloca ptr
  store ptr %fbip_r24, ptr %$t574.addr
  %ld25 = load ptr, ptr %t.addr
  %ld26 = load ptr, ptr %$t574.addr
  %cr27 = call ptr @irev(ptr %ld25, ptr %ld26)
  store ptr %cr27, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r28 = load ptr, ptr %res_slot2
  ret ptr %case_r28
}

define ptr @irange_acc(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld29 = load i64, ptr %lo.addr
  %ld30 = load i64, ptr %hi.addr
  %cmp31 = icmp sgt i64 %ld29, %ld30
  %ar32 = zext i1 %cmp31 to i64
  %$t575.addr = alloca i64
  store i64 %ar32, ptr %$t575.addr
  %ld33 = load i64, ptr %$t575.addr
  %res_slot34 = alloca ptr
  switch i64 %ld33, label %case_default9 [
      i64 1, label %case_br10
  ]
case_br10:
  %ld35 = load ptr, ptr %acc.addr
  store ptr %ld35, ptr %res_slot34
  br label %case_merge8
case_default9:
  %ld36 = load i64, ptr %lo.addr
  %ar37 = add i64 %ld36, 1
  %$t576.addr = alloca i64
  store i64 %ar37, ptr %$t576.addr
  %hp38 = call ptr @march_alloc(i64 32)
  %tgp39 = getelementptr i8, ptr %hp38, i64 8
  store i32 1, ptr %tgp39, align 4
  %ld40 = load i64, ptr %lo.addr
  %fp41 = getelementptr i8, ptr %hp38, i64 16
  store i64 %ld40, ptr %fp41, align 8
  %ld42 = load ptr, ptr %acc.addr
  %fp43 = getelementptr i8, ptr %hp38, i64 24
  store ptr %ld42, ptr %fp43, align 8
  %$t577.addr = alloca ptr
  store ptr %hp38, ptr %$t577.addr
  %ld44 = load i64, ptr %$t576.addr
  %ld45 = load i64, ptr %hi.addr
  %ld46 = load ptr, ptr %$t577.addr
  %cr47 = call ptr @irange_acc(i64 %ld44, i64 %ld45, ptr %ld46)
  store ptr %cr47, ptr %res_slot34
  br label %case_merge8
case_merge8:
  %case_r48 = load ptr, ptr %res_slot34
  ret ptr %case_r48
}

define ptr @imap_acc(ptr %xs.arg, ptr %f.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld49 = load ptr, ptr %xs.addr
  %res_slot50 = alloca ptr
  %tgp51 = getelementptr i8, ptr %ld49, i64 8
  %tag52 = load i32, ptr %tgp51, align 4
  switch i32 %tag52, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld53 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld53)
  %ld54 = load ptr, ptr %acc.addr
  store ptr %ld54, ptr %res_slot50
  br label %case_merge11
case_br14:
  %fp55 = getelementptr i8, ptr %ld49, i64 16
  %fv56 = load i64, ptr %fp55, align 8
  %h.addr = alloca i64
  store i64 %fv56, ptr %h.addr
  %fp57 = getelementptr i8, ptr %ld49, i64 24
  %fv58 = load ptr, ptr %fp57, align 8
  %t.addr = alloca ptr
  store ptr %fv58, ptr %t.addr
  %freed59 = call i64 @march_decrc_freed(ptr %ld49)
  %freed_b60 = icmp ne i64 %freed59, 0
  br i1 %freed_b60, label %br_unique15, label %br_shared16
br_shared16:
  call void @march_incrc(ptr %fv58)
  br label %br_body17
br_unique15:
  br label %br_body17
br_body17:
  %ld61 = load ptr, ptr %f.addr
  %fp62 = getelementptr i8, ptr %ld61, i64 16
  %fv63 = load ptr, ptr %fp62, align 8
  %ld64 = load i64, ptr %h.addr
  %cr65 = call i64 (ptr, i64) %fv63(ptr %ld61, i64 %ld64)
  %$t581.addr = alloca i64
  store i64 %cr65, ptr %$t581.addr
  %hp66 = call ptr @march_alloc(i64 32)
  %tgp67 = getelementptr i8, ptr %hp66, i64 8
  store i32 1, ptr %tgp67, align 4
  %ld68 = load i64, ptr %$t581.addr
  %fp69 = getelementptr i8, ptr %hp66, i64 16
  store i64 %ld68, ptr %fp69, align 8
  %ld70 = load ptr, ptr %acc.addr
  %fp71 = getelementptr i8, ptr %hp66, i64 24
  store ptr %ld70, ptr %fp71, align 8
  %$t582.addr = alloca ptr
  store ptr %hp66, ptr %$t582.addr
  %ld72 = load ptr, ptr %t.addr
  %ld73 = load ptr, ptr %f.addr
  %ld74 = load ptr, ptr %$t582.addr
  %cr75 = call ptr @imap_acc(ptr %ld72, ptr %ld73, ptr %ld74)
  store ptr %cr75, ptr %res_slot50
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r76 = load ptr, ptr %res_slot50
  ret ptr %case_r76
}

define ptr @ifilter_acc(ptr %xs.arg, ptr %pred.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld77 = load ptr, ptr %xs.addr
  %res_slot78 = alloca ptr
  %tgp79 = getelementptr i8, ptr %ld77, i64 8
  %tag80 = load i32, ptr %tgp79, align 4
  switch i32 %tag80, label %case_default19 [
      i32 0, label %case_br20
      i32 1, label %case_br21
  ]
case_br20:
  %ld81 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld81)
  %ld82 = load ptr, ptr %acc.addr
  store ptr %ld82, ptr %res_slot78
  br label %case_merge18
case_br21:
  %fp83 = getelementptr i8, ptr %ld77, i64 16
  %fv84 = load i64, ptr %fp83, align 8
  %h.addr = alloca i64
  store i64 %fv84, ptr %h.addr
  %fp85 = getelementptr i8, ptr %ld77, i64 24
  %fv86 = load ptr, ptr %fp85, align 8
  %t.addr = alloca ptr
  store ptr %fv86, ptr %t.addr
  %freed87 = call i64 @march_decrc_freed(ptr %ld77)
  %freed_b88 = icmp ne i64 %freed87, 0
  br i1 %freed_b88, label %br_unique22, label %br_shared23
br_shared23:
  call void @march_incrc(ptr %fv86)
  br label %br_body24
br_unique22:
  br label %br_body24
br_body24:
  %ld89 = load ptr, ptr %pred.addr
  %fp90 = getelementptr i8, ptr %ld89, i64 16
  %fv91 = load ptr, ptr %fp90, align 8
  %ld92 = load i64, ptr %h.addr
  %cr93 = call i64 (ptr, i64) %fv91(ptr %ld89, i64 %ld92)
  %$t586.addr = alloca i64
  store i64 %cr93, ptr %$t586.addr
  %ld94 = load i64, ptr %$t586.addr
  %res_slot95 = alloca ptr
  switch i64 %ld94, label %case_default26 [
      i64 1, label %case_br27
  ]
case_br27:
  %hp96 = call ptr @march_alloc(i64 32)
  %tgp97 = getelementptr i8, ptr %hp96, i64 8
  store i32 1, ptr %tgp97, align 4
  %ld98 = load i64, ptr %h.addr
  %fp99 = getelementptr i8, ptr %hp96, i64 16
  store i64 %ld98, ptr %fp99, align 8
  %ld100 = load ptr, ptr %acc.addr
  %fp101 = getelementptr i8, ptr %hp96, i64 24
  store ptr %ld100, ptr %fp101, align 8
  %$t587.addr = alloca ptr
  store ptr %hp96, ptr %$t587.addr
  %ld102 = load ptr, ptr %t.addr
  %ld103 = load ptr, ptr %pred.addr
  %ld104 = load ptr, ptr %$t587.addr
  %cr105 = call ptr @ifilter_acc(ptr %ld102, ptr %ld103, ptr %ld104)
  store ptr %cr105, ptr %res_slot95
  br label %case_merge25
case_default26:
  %ld106 = load ptr, ptr %t.addr
  %ld107 = load ptr, ptr %pred.addr
  %ld108 = load ptr, ptr %acc.addr
  %cr109 = call ptr @ifilter_acc(ptr %ld106, ptr %ld107, ptr %ld108)
  store ptr %cr109, ptr %res_slot95
  br label %case_merge25
case_merge25:
  %case_r110 = load ptr, ptr %res_slot95
  store ptr %case_r110, ptr %res_slot78
  br label %case_merge18
case_default19:
  unreachable
case_merge18:
  %case_r111 = load ptr, ptr %res_slot78
  ret ptr %case_r111
}

define i64 @ifold(ptr %xs.arg, i64 %acc.arg, ptr %f.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld112 = load ptr, ptr %xs.addr
  %res_slot113 = alloca ptr
  %tgp114 = getelementptr i8, ptr %ld112, i64 8
  %tag115 = load i32, ptr %tgp114, align 4
  switch i32 %tag115, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %ld116 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld116)
  %ld117 = load i64, ptr %acc.addr
  %cv118 = inttoptr i64 %ld117 to ptr
  store ptr %cv118, ptr %res_slot113
  br label %case_merge28
case_br31:
  %fp119 = getelementptr i8, ptr %ld112, i64 16
  %fv120 = load i64, ptr %fp119, align 8
  %h.addr = alloca i64
  store i64 %fv120, ptr %h.addr
  %fp121 = getelementptr i8, ptr %ld112, i64 24
  %fv122 = load ptr, ptr %fp121, align 8
  %t.addr = alloca ptr
  store ptr %fv122, ptr %t.addr
  %freed123 = call i64 @march_decrc_freed(ptr %ld112)
  %freed_b124 = icmp ne i64 %freed123, 0
  br i1 %freed_b124, label %br_unique32, label %br_shared33
br_shared33:
  call void @march_incrc(ptr %fv122)
  br label %br_body34
br_unique32:
  br label %br_body34
br_body34:
  %ld125 = load ptr, ptr %f.addr
  %fp126 = getelementptr i8, ptr %ld125, i64 16
  %fv127 = load ptr, ptr %fp126, align 8
  %ld128 = load i64, ptr %acc.addr
  %ld129 = load i64, ptr %h.addr
  %cr130 = call i64 (ptr, i64, i64) %fv127(ptr %ld125, i64 %ld128, i64 %ld129)
  %$t591.addr = alloca i64
  store i64 %cr130, ptr %$t591.addr
  %ld131 = load ptr, ptr %t.addr
  %ld132 = load i64, ptr %$t591.addr
  %ld133 = load ptr, ptr %f.addr
  %cr134 = call i64 @ifold(ptr %ld131, i64 %ld132, ptr %ld133)
  %cv135 = inttoptr i64 %cr134 to ptr
  store ptr %cv135, ptr %res_slot113
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r136 = load ptr, ptr %res_slot113
  %cv137 = ptrtoint ptr %case_r136 to i64
  ret i64 %cv137
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 1000000, ptr %n.addr
  %lo_i11.addr = alloca i64
  store i64 1, ptr %lo_i11.addr
  %ld138 = load i64, ptr %n.addr
  %hi_i12.addr = alloca i64
  store i64 %ld138, ptr %hi_i12.addr
  %hp139 = call ptr @march_alloc(i64 16)
  %tgp140 = getelementptr i8, ptr %hp139, i64 8
  store i32 0, ptr %tgp140, align 4
  %$t578_i13.addr = alloca ptr
  store ptr %hp139, ptr %$t578_i13.addr
  %ld141 = load i64, ptr %lo_i11.addr
  %ld142 = load i64, ptr %hi_i12.addr
  %ld143 = load ptr, ptr %$t578_i13.addr
  %cr144 = call ptr @irange_acc(i64 %ld141, i64 %ld142, ptr %ld143)
  %$t579_i14.addr = alloca ptr
  store ptr %cr144, ptr %$t579_i14.addr
  %hp145 = call ptr @march_alloc(i64 16)
  %tgp146 = getelementptr i8, ptr %hp145, i64 8
  store i32 0, ptr %tgp146, align 4
  %$t580_i15.addr = alloca ptr
  store ptr %hp145, ptr %$t580_i15.addr
  %ld147 = load ptr, ptr %$t579_i14.addr
  %ld148 = load ptr, ptr %$t580_i15.addr
  %cr149 = call ptr @irev(ptr %ld147, ptr %ld148)
  %xs.addr = alloca ptr
  store ptr %cr149, ptr %xs.addr
  %hp150 = call ptr @march_alloc(i64 24)
  %tgp151 = getelementptr i8, ptr %hp150, i64 8
  store i32 0, ptr %tgp151, align 4
  %fp152 = getelementptr i8, ptr %hp150, i64 16
  store ptr @$lam592$apply, ptr %fp152, align 8
  %$t593.addr = alloca ptr
  store ptr %hp150, ptr %$t593.addr
  %ld153 = load ptr, ptr %xs.addr
  %xs_i6.addr = alloca ptr
  store ptr %ld153, ptr %xs_i6.addr
  %ld154 = load ptr, ptr %$t593.addr
  %f_i7.addr = alloca ptr
  store ptr %ld154, ptr %f_i7.addr
  %hp155 = call ptr @march_alloc(i64 16)
  %tgp156 = getelementptr i8, ptr %hp155, i64 8
  store i32 0, ptr %tgp156, align 4
  %$t583_i8.addr = alloca ptr
  store ptr %hp155, ptr %$t583_i8.addr
  %ld157 = load ptr, ptr %xs_i6.addr
  %ld158 = load ptr, ptr %f_i7.addr
  %ld159 = load ptr, ptr %$t583_i8.addr
  %cr160 = call ptr @imap_acc(ptr %ld157, ptr %ld158, ptr %ld159)
  %$t584_i9.addr = alloca ptr
  store ptr %cr160, ptr %$t584_i9.addr
  %hp161 = call ptr @march_alloc(i64 16)
  %tgp162 = getelementptr i8, ptr %hp161, i64 8
  store i32 0, ptr %tgp162, align 4
  %$t585_i10.addr = alloca ptr
  store ptr %hp161, ptr %$t585_i10.addr
  %ld163 = load ptr, ptr %$t584_i9.addr
  %ld164 = load ptr, ptr %$t585_i10.addr
  %cr165 = call ptr @irev(ptr %ld163, ptr %ld164)
  %ys.addr = alloca ptr
  store ptr %cr165, ptr %ys.addr
  %hp166 = call ptr @march_alloc(i64 24)
  %tgp167 = getelementptr i8, ptr %hp166, i64 8
  store i32 0, ptr %tgp167, align 4
  %fp168 = getelementptr i8, ptr %hp166, i64 16
  store ptr @$lam594$apply, ptr %fp168, align 8
  %$t596.addr = alloca ptr
  store ptr %hp166, ptr %$t596.addr
  %ld169 = load ptr, ptr %ys.addr
  %xs_i1.addr = alloca ptr
  store ptr %ld169, ptr %xs_i1.addr
  %ld170 = load ptr, ptr %$t596.addr
  %pred_i2.addr = alloca ptr
  store ptr %ld170, ptr %pred_i2.addr
  %hp171 = call ptr @march_alloc(i64 16)
  %tgp172 = getelementptr i8, ptr %hp171, i64 8
  store i32 0, ptr %tgp172, align 4
  %$t588_i3.addr = alloca ptr
  store ptr %hp171, ptr %$t588_i3.addr
  %ld173 = load ptr, ptr %xs_i1.addr
  %ld174 = load ptr, ptr %pred_i2.addr
  %ld175 = load ptr, ptr %$t588_i3.addr
  %cr176 = call ptr @ifilter_acc(ptr %ld173, ptr %ld174, ptr %ld175)
  %$t589_i4.addr = alloca ptr
  store ptr %cr176, ptr %$t589_i4.addr
  %hp177 = call ptr @march_alloc(i64 16)
  %tgp178 = getelementptr i8, ptr %hp177, i64 8
  store i32 0, ptr %tgp178, align 4
  %$t590_i5.addr = alloca ptr
  store ptr %hp177, ptr %$t590_i5.addr
  %ld179 = load ptr, ptr %$t589_i4.addr
  %ld180 = load ptr, ptr %$t590_i5.addr
  %cr181 = call ptr @irev(ptr %ld179, ptr %ld180)
  %zs.addr = alloca ptr
  store ptr %cr181, ptr %zs.addr
  %hp182 = call ptr @march_alloc(i64 24)
  %tgp183 = getelementptr i8, ptr %hp182, i64 8
  store i32 0, ptr %tgp183, align 4
  %fp184 = getelementptr i8, ptr %hp182, i64 16
  store ptr @$lam597$apply, ptr %fp184, align 8
  %$t598.addr = alloca ptr
  store ptr %hp182, ptr %$t598.addr
  %ld185 = load ptr, ptr %zs.addr
  %ld186 = load ptr, ptr %$t598.addr
  %cr187 = call i64 @ifold(ptr %ld185, i64 0, ptr %ld186)
  %total.addr = alloca i64
  store i64 %cr187, ptr %total.addr
  %ld188 = load i64, ptr %total.addr
  %cr189 = call ptr @march_int_to_string(i64 %ld188)
  %$t599.addr = alloca ptr
  store ptr %cr189, ptr %$t599.addr
  %ld190 = load ptr, ptr %$t599.addr
  call void @march_println(ptr %ld190)
  ret void
}

define i64 @$lam592$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld191 = load i64, ptr %x.addr
  %ld192 = load i64, ptr %x.addr
  %ar193 = add i64 %ld191, %ld192
  %sr_s1.addr = alloca i64
  store i64 %ar193, ptr %sr_s1.addr
  %ld194 = load i64, ptr %sr_s1.addr
  ret i64 %ld194
}

define i64 @$lam594$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld195 = load i64, ptr %x.addr
  %ar196 = srem i64 %ld195, 3
  %$t595.addr = alloca i64
  store i64 %ar196, ptr %$t595.addr
  %ld197 = load i64, ptr %$t595.addr
  %cmp198 = icmp eq i64 %ld197, 0
  %ar199 = zext i1 %cmp198 to i64
  ret i64 %ar199
}

define i64 @$lam597$apply(ptr %$clo.arg, i64 %a.arg, i64 %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca i64
  store i64 %a.arg, ptr %a.addr
  %b.addr = alloca i64
  store i64 %b.arg, ptr %b.addr
  %ld200 = load i64, ptr %a.addr
  %ld201 = load i64, ptr %b.addr
  %ar202 = add i64 %ld200, %ld201
  ret i64 %ar202
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
