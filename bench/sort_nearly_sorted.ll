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


define ptr @reverse_list(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp1 = call ptr @march_alloc(i64 24)
  %tgp2 = getelementptr i8, ptr %hp1, i64 8
  store i32 0, ptr %tgp2, align 4
  %fp3 = getelementptr i8, ptr %hp1, i64 16
  store ptr @go$apply$18, ptr %fp3, align 8
  %go.addr = alloca ptr
  store ptr %hp1, ptr %go.addr
  %hp4 = call ptr @march_alloc(i64 16)
  %tgp5 = getelementptr i8, ptr %hp4, i64 8
  store i32 0, ptr %tgp5, align 4
  %$t973.addr = alloca ptr
  store ptr %hp4, ptr %$t973.addr
  %ld6 = load ptr, ptr %go.addr
  %fp7 = getelementptr i8, ptr %ld6, i64 16
  %fv8 = load ptr, ptr %fp7, align 8
  %ld9 = load ptr, ptr %xs.addr
  %ld10 = load ptr, ptr %$t973.addr
  %cr11 = call ptr (ptr, ptr, ptr) %fv8(ptr %ld6, ptr %ld9, ptr %ld10)
  ret ptr %cr11
}

define ptr @build_pairs(i64 %n.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld12 = load i64, ptr %n.addr
  %cmp13 = icmp slt i64 %ld12, 0
  %ar14 = zext i1 %cmp13 to i64
  %$t974.addr = alloca i64
  store i64 %ar14, ptr %$t974.addr
  %ld15 = load i64, ptr %$t974.addr
  %res_slot16 = alloca ptr
  switch i64 %ld15, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld17 = load ptr, ptr %acc.addr
  store ptr %ld17, ptr %res_slot16
  br label %case_merge1
case_default2:
  %ld18 = load i64, ptr %n.addr
  %ld19 = load i64, ptr %n.addr
  %ar20 = add i64 %ld18, %ld19
  %sr_s2.addr = alloca i64
  store i64 %ar20, ptr %sr_s2.addr
  %ld21 = load i64, ptr %sr_s2.addr
  %even.addr = alloca i64
  store i64 %ld21, ptr %even.addr
  %ld22 = load i64, ptr %n.addr
  %ld23 = load i64, ptr %n.addr
  %ar24 = add i64 %ld22, %ld23
  %sr_s1.addr = alloca i64
  store i64 %ar24, ptr %sr_s1.addr
  %ld25 = load i64, ptr %sr_s1.addr
  %$t975.addr = alloca i64
  store i64 %ld25, ptr %$t975.addr
  %ld26 = load i64, ptr %$t975.addr
  %ar27 = add i64 %ld26, 1
  %odd.addr = alloca i64
  store i64 %ar27, ptr %odd.addr
  %ld28 = load i64, ptr %n.addr
  %ar29 = sub i64 %ld28, 1
  %$t976.addr = alloca i64
  store i64 %ar29, ptr %$t976.addr
  %hp30 = call ptr @march_alloc(i64 32)
  %tgp31 = getelementptr i8, ptr %hp30, i64 8
  store i32 1, ptr %tgp31, align 4
  %ld32 = load i64, ptr %odd.addr
  %cv33 = inttoptr i64 %ld32 to ptr
  %fp34 = getelementptr i8, ptr %hp30, i64 16
  store ptr %cv33, ptr %fp34, align 8
  %ld35 = load ptr, ptr %acc.addr
  %fp36 = getelementptr i8, ptr %hp30, i64 24
  store ptr %ld35, ptr %fp36, align 8
  %$t977.addr = alloca ptr
  store ptr %hp30, ptr %$t977.addr
  %hp37 = call ptr @march_alloc(i64 32)
  %tgp38 = getelementptr i8, ptr %hp37, i64 8
  store i32 1, ptr %tgp38, align 4
  %ld39 = load i64, ptr %even.addr
  %cv40 = inttoptr i64 %ld39 to ptr
  %fp41 = getelementptr i8, ptr %hp37, i64 16
  store ptr %cv40, ptr %fp41, align 8
  %ld42 = load ptr, ptr %$t977.addr
  %fp43 = getelementptr i8, ptr %hp37, i64 24
  store ptr %ld42, ptr %fp43, align 8
  %$t978.addr = alloca ptr
  store ptr %hp37, ptr %$t978.addr
  %ld44 = load i64, ptr %$t976.addr
  %ld45 = load ptr, ptr %$t978.addr
  %cr46 = call ptr @build_pairs(i64 %ld44, ptr %ld45)
  store ptr %cr46, ptr %res_slot16
  br label %case_merge1
case_merge1:
  %case_r47 = load ptr, ptr %res_slot16
  ret ptr %case_r47
}

define ptr @merge_ms(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld48 = load ptr, ptr %xs.addr
  %res_slot49 = alloca ptr
  %tgp50 = getelementptr i8, ptr %ld48, i64 8
  %tag51 = load i32, ptr %tgp50, align 4
  switch i32 %tag51, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %ld52 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld52)
  %ld53 = load ptr, ptr %ys.addr
  store ptr %ld53, ptr %res_slot49
  br label %case_merge4
case_br7:
  %fp54 = getelementptr i8, ptr %ld48, i64 16
  %fv55 = load ptr, ptr %fp54, align 8
  %$f984.addr = alloca ptr
  store ptr %fv55, ptr %$f984.addr
  %fp56 = getelementptr i8, ptr %ld48, i64 24
  %fv57 = load ptr, ptr %fp56, align 8
  %$f985.addr = alloca ptr
  store ptr %fv57, ptr %$f985.addr
  %ld58 = load ptr, ptr %$f985.addr
  %xt.addr = alloca ptr
  store ptr %ld58, ptr %xt.addr
  %ld59 = load ptr, ptr %$f984.addr
  %x.addr = alloca ptr
  store ptr %ld59, ptr %x.addr
  %ld60 = load ptr, ptr %ys.addr
  %res_slot61 = alloca ptr
  %tgp62 = getelementptr i8, ptr %ld60, i64 8
  %tag63 = load i32, ptr %tgp62, align 4
  switch i32 %tag63, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %ld64 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld64)
  %ld65 = load ptr, ptr %xs.addr
  store ptr %ld65, ptr %res_slot61
  br label %case_merge8
case_br11:
  %fp66 = getelementptr i8, ptr %ld60, i64 16
  %fv67 = load ptr, ptr %fp66, align 8
  %$f982.addr = alloca ptr
  store ptr %fv67, ptr %$f982.addr
  %fp68 = getelementptr i8, ptr %ld60, i64 24
  %fv69 = load ptr, ptr %fp68, align 8
  %$f983.addr = alloca ptr
  store ptr %fv69, ptr %$f983.addr
  %ld70 = load ptr, ptr %$f983.addr
  %yt.addr = alloca ptr
  store ptr %ld70, ptr %yt.addr
  %ld71 = load ptr, ptr %$f982.addr
  %y.addr = alloca ptr
  store ptr %ld71, ptr %y.addr
  %ld72 = load i64, ptr %x.addr
  %ld73 = load i64, ptr %y.addr
  %cmp74 = icmp sle i64 %ld72, %ld73
  %ar75 = zext i1 %cmp74 to i64
  %$t979.addr = alloca i64
  store i64 %ar75, ptr %$t979.addr
  %ld76 = load i64, ptr %$t979.addr
  %res_slot77 = alloca ptr
  switch i64 %ld76, label %case_default13 [
      i64 1, label %case_br14
  ]
case_br14:
  %ld78 = load ptr, ptr %xt.addr
  %ld79 = load ptr, ptr %ys.addr
  %cr80 = call ptr @merge_ms(ptr %ld78, ptr %ld79)
  %$t980.addr = alloca ptr
  store ptr %cr80, ptr %$t980.addr
  %hp81 = call ptr @march_alloc(i64 32)
  %tgp82 = getelementptr i8, ptr %hp81, i64 8
  store i32 1, ptr %tgp82, align 4
  %ld83 = load i64, ptr %x.addr
  %cv84 = inttoptr i64 %ld83 to ptr
  %fp85 = getelementptr i8, ptr %hp81, i64 16
  store ptr %cv84, ptr %fp85, align 8
  %ld86 = load ptr, ptr %$t980.addr
  %fp87 = getelementptr i8, ptr %hp81, i64 24
  store ptr %ld86, ptr %fp87, align 8
  store ptr %hp81, ptr %res_slot77
  br label %case_merge12
case_default13:
  %ld88 = load ptr, ptr %xs.addr
  %ld89 = load ptr, ptr %yt.addr
  %cr90 = call ptr @merge_ms(ptr %ld88, ptr %ld89)
  %$t981.addr = alloca ptr
  store ptr %cr90, ptr %$t981.addr
  %hp91 = call ptr @march_alloc(i64 32)
  %tgp92 = getelementptr i8, ptr %hp91, i64 8
  store i32 1, ptr %tgp92, align 4
  %ld93 = load i64, ptr %y.addr
  %cv94 = inttoptr i64 %ld93 to ptr
  %fp95 = getelementptr i8, ptr %hp91, i64 16
  store ptr %cv94, ptr %fp95, align 8
  %ld96 = load ptr, ptr %$t981.addr
  %fp97 = getelementptr i8, ptr %hp91, i64 24
  store ptr %ld96, ptr %fp97, align 8
  store ptr %hp91, ptr %res_slot77
  br label %case_merge12
case_merge12:
  %case_r98 = load ptr, ptr %res_slot77
  store ptr %case_r98, ptr %res_slot61
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r99 = load ptr, ptr %res_slot61
  store ptr %case_r99, ptr %res_slot49
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r100 = load ptr, ptr %res_slot49
  ret ptr %case_r100
}

define ptr @take_k(ptr %lst.arg, i64 %k.arg, ptr %acc.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %k.addr = alloca i64
  store i64 %k.arg, ptr %k.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld101 = load i64, ptr %k.addr
  %cmp102 = icmp eq i64 %ld101, 0
  %ar103 = zext i1 %cmp102 to i64
  %$t986.addr = alloca i64
  store i64 %ar103, ptr %$t986.addr
  %ld104 = load i64, ptr %$t986.addr
  %res_slot105 = alloca ptr
  switch i64 %ld104, label %case_default16 [
      i64 1, label %case_br17
  ]
case_br17:
  %ld106 = load ptr, ptr %acc.addr
  %cr107 = call ptr @reverse_list(ptr %ld106)
  %$t987.addr = alloca ptr
  store ptr %cr107, ptr %$t987.addr
  %hp108 = call ptr @march_alloc(i64 32)
  %tgp109 = getelementptr i8, ptr %hp108, i64 8
  store i32 0, ptr %tgp109, align 4
  %ld110 = load ptr, ptr %$t987.addr
  %fp111 = getelementptr i8, ptr %hp108, i64 16
  store ptr %ld110, ptr %fp111, align 8
  %ld112 = load ptr, ptr %lst.addr
  %fp113 = getelementptr i8, ptr %hp108, i64 24
  store ptr %ld112, ptr %fp113, align 8
  store ptr %hp108, ptr %res_slot105
  br label %case_merge15
case_default16:
  %ld114 = load ptr, ptr %lst.addr
  %res_slot115 = alloca ptr
  %tgp116 = getelementptr i8, ptr %ld114, i64 8
  %tag117 = load i32, ptr %tgp116, align 4
  switch i32 %tag117, label %case_default19 [
      i32 0, label %case_br20
      i32 1, label %case_br21
  ]
case_br20:
  %ld118 = load ptr, ptr %acc.addr
  %cr119 = call ptr @reverse_list(ptr %ld118)
  %$t988.addr = alloca ptr
  store ptr %cr119, ptr %$t988.addr
  %ld120 = load ptr, ptr %lst.addr
  %rc121 = load i64, ptr %ld120, align 8
  %uniq122 = icmp eq i64 %rc121, 1
  %fbip_slot123 = alloca ptr
  br i1 %uniq122, label %fbip_reuse22, label %fbip_fresh23
fbip_reuse22:
  %tgp124 = getelementptr i8, ptr %ld120, i64 8
  store i32 0, ptr %tgp124, align 4
  store ptr %ld120, ptr %fbip_slot123
  br label %fbip_merge24
fbip_fresh23:
  call void @march_decrc(ptr %ld120)
  %hp125 = call ptr @march_alloc(i64 16)
  %tgp126 = getelementptr i8, ptr %hp125, i64 8
  store i32 0, ptr %tgp126, align 4
  store ptr %hp125, ptr %fbip_slot123
  br label %fbip_merge24
fbip_merge24:
  %fbip_r127 = load ptr, ptr %fbip_slot123
  %$t989.addr = alloca ptr
  store ptr %fbip_r127, ptr %$t989.addr
  %hp128 = call ptr @march_alloc(i64 32)
  %tgp129 = getelementptr i8, ptr %hp128, i64 8
  store i32 0, ptr %tgp129, align 4
  %ld130 = load ptr, ptr %$t988.addr
  %fp131 = getelementptr i8, ptr %hp128, i64 16
  store ptr %ld130, ptr %fp131, align 8
  %ld132 = load ptr, ptr %$t989.addr
  %fp133 = getelementptr i8, ptr %hp128, i64 24
  store ptr %ld132, ptr %fp133, align 8
  store ptr %hp128, ptr %res_slot115
  br label %case_merge18
case_br21:
  %fp134 = getelementptr i8, ptr %ld114, i64 16
  %fv135 = load ptr, ptr %fp134, align 8
  %$f992.addr = alloca ptr
  store ptr %fv135, ptr %$f992.addr
  %fp136 = getelementptr i8, ptr %ld114, i64 24
  %fv137 = load ptr, ptr %fp136, align 8
  %$f993.addr = alloca ptr
  store ptr %fv137, ptr %$f993.addr
  %ld138 = load ptr, ptr %$f993.addr
  %t.addr = alloca ptr
  store ptr %ld138, ptr %t.addr
  %ld139 = load ptr, ptr %$f992.addr
  %h.addr = alloca ptr
  store ptr %ld139, ptr %h.addr
  %ld140 = load i64, ptr %k.addr
  %ar141 = sub i64 %ld140, 1
  %$t990.addr = alloca i64
  store i64 %ar141, ptr %$t990.addr
  %ld142 = load ptr, ptr %lst.addr
  %ld143 = load i64, ptr %h.addr
  %cv144 = inttoptr i64 %ld143 to ptr
  %ld145 = load ptr, ptr %acc.addr
  %rc146 = load i64, ptr %ld142, align 8
  %uniq147 = icmp eq i64 %rc146, 1
  %fbip_slot148 = alloca ptr
  br i1 %uniq147, label %fbip_reuse25, label %fbip_fresh26
fbip_reuse25:
  %tgp149 = getelementptr i8, ptr %ld142, i64 8
  store i32 1, ptr %tgp149, align 4
  %fp150 = getelementptr i8, ptr %ld142, i64 16
  store ptr %cv144, ptr %fp150, align 8
  %fp151 = getelementptr i8, ptr %ld142, i64 24
  store ptr %ld145, ptr %fp151, align 8
  store ptr %ld142, ptr %fbip_slot148
  br label %fbip_merge27
fbip_fresh26:
  call void @march_decrc(ptr %ld142)
  %hp152 = call ptr @march_alloc(i64 32)
  %tgp153 = getelementptr i8, ptr %hp152, i64 8
  store i32 1, ptr %tgp153, align 4
  %fp154 = getelementptr i8, ptr %hp152, i64 16
  store ptr %cv144, ptr %fp154, align 8
  %fp155 = getelementptr i8, ptr %hp152, i64 24
  store ptr %ld145, ptr %fp155, align 8
  store ptr %hp152, ptr %fbip_slot148
  br label %fbip_merge27
fbip_merge27:
  %fbip_r156 = load ptr, ptr %fbip_slot148
  %$t991.addr = alloca ptr
  store ptr %fbip_r156, ptr %$t991.addr
  %ld157 = load ptr, ptr %t.addr
  %ld158 = load i64, ptr %$t990.addr
  %ld159 = load ptr, ptr %$t991.addr
  %cr160 = call ptr @take_k(ptr %ld157, i64 %ld158, ptr %ld159)
  store ptr %cr160, ptr %res_slot115
  br label %case_merge18
case_default19:
  unreachable
case_merge18:
  %case_r161 = load ptr, ptr %res_slot115
  store ptr %case_r161, ptr %res_slot105
  br label %case_merge15
case_merge15:
  %case_r162 = load ptr, ptr %res_slot105
  ret ptr %case_r162
}

define i64 @list_len(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp163 = call ptr @march_alloc(i64 24)
  %tgp164 = getelementptr i8, ptr %hp163, i64 8
  store i32 0, ptr %tgp164, align 4
  %fp165 = getelementptr i8, ptr %hp163, i64 16
  store ptr @go$apply$19, ptr %fp165, align 8
  %go.addr = alloca ptr
  store ptr %hp163, ptr %go.addr
  %ld166 = load ptr, ptr %go.addr
  %fp167 = getelementptr i8, ptr %ld166, i64 16
  %fv168 = load ptr, ptr %fp167, align 8
  %ld169 = load ptr, ptr %xs.addr
  %cr170 = call i64 (ptr, ptr, i64) %fv168(ptr %ld166, ptr %ld169, i64 0)
  ret i64 %cr170
}

define ptr @mergesort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp171 = call ptr @march_alloc(i64 24)
  %tgp172 = getelementptr i8, ptr %hp171, i64 8
  store i32 0, ptr %tgp172, align 4
  %fp173 = getelementptr i8, ptr %hp171, i64 16
  store ptr @go$apply$20, ptr %fp173, align 8
  %go.addr = alloca ptr
  store ptr %hp171, ptr %go.addr
  %ld174 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld174)
  %ld175 = load ptr, ptr %xs.addr
  %cr176 = call i64 @list_len(ptr %ld175)
  %$t1003.addr = alloca i64
  store i64 %cr176, ptr %$t1003.addr
  %ld177 = load ptr, ptr %go.addr
  %fp178 = getelementptr i8, ptr %ld177, i64 16
  %fv179 = load ptr, ptr %fp178, align 8
  %ld180 = load ptr, ptr %xs.addr
  %ld181 = load i64, ptr %$t1003.addr
  %cr182 = call ptr (ptr, ptr, i64) %fv179(ptr %ld177, ptr %ld180, i64 %ld181)
  ret ptr %cr182
}

define ptr @scan_asc(ptr %lst.arg, ptr %run.arg, i64 %run_len.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %run.addr = alloca ptr
  store ptr %run.arg, ptr %run.addr
  %run_len.addr = alloca i64
  store i64 %run_len.arg, ptr %run_len.addr
  %ld183 = load ptr, ptr %lst.addr
  %res_slot184 = alloca ptr
  %tgp185 = getelementptr i8, ptr %ld183, i64 8
  %tag186 = load i32, ptr %tgp185, align 4
  switch i32 %tag186, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %ld187 = load ptr, ptr %run.addr
  %cr188 = call ptr @reverse_list(ptr %ld187)
  %$t1004.addr = alloca ptr
  store ptr %cr188, ptr %$t1004.addr
  %ld189 = load ptr, ptr %lst.addr
  %rc190 = load i64, ptr %ld189, align 8
  %uniq191 = icmp eq i64 %rc190, 1
  %fbip_slot192 = alloca ptr
  br i1 %uniq191, label %fbip_reuse32, label %fbip_fresh33
fbip_reuse32:
  %tgp193 = getelementptr i8, ptr %ld189, i64 8
  store i32 0, ptr %tgp193, align 4
  store ptr %ld189, ptr %fbip_slot192
  br label %fbip_merge34
fbip_fresh33:
  call void @march_decrc(ptr %ld189)
  %hp194 = call ptr @march_alloc(i64 16)
  %tgp195 = getelementptr i8, ptr %hp194, i64 8
  store i32 0, ptr %tgp195, align 4
  store ptr %hp194, ptr %fbip_slot192
  br label %fbip_merge34
fbip_merge34:
  %fbip_r196 = load ptr, ptr %fbip_slot192
  %$t1005.addr = alloca ptr
  store ptr %fbip_r196, ptr %$t1005.addr
  %hp197 = call ptr @march_alloc(i64 40)
  %tgp198 = getelementptr i8, ptr %hp197, i64 8
  store i32 0, ptr %tgp198, align 4
  %ld199 = load ptr, ptr %$t1004.addr
  %fp200 = getelementptr i8, ptr %hp197, i64 16
  store ptr %ld199, ptr %fp200, align 8
  %ld201 = load i64, ptr %run_len.addr
  %fp202 = getelementptr i8, ptr %hp197, i64 24
  store i64 %ld201, ptr %fp202, align 8
  %ld203 = load ptr, ptr %$t1005.addr
  %fp204 = getelementptr i8, ptr %hp197, i64 32
  store ptr %ld203, ptr %fp204, align 8
  store ptr %hp197, ptr %res_slot184
  br label %case_merge28
case_br31:
  %fp205 = getelementptr i8, ptr %ld183, i64 16
  %fv206 = load ptr, ptr %fp205, align 8
  %$f1014.addr = alloca ptr
  store ptr %fv206, ptr %$f1014.addr
  %fp207 = getelementptr i8, ptr %ld183, i64 24
  %fv208 = load ptr, ptr %fp207, align 8
  %$f1015.addr = alloca ptr
  store ptr %fv208, ptr %$f1015.addr
  %ld209 = load ptr, ptr %$f1015.addr
  %t.addr = alloca ptr
  store ptr %ld209, ptr %t.addr
  %ld210 = load ptr, ptr %$f1014.addr
  %h.addr = alloca ptr
  store ptr %ld210, ptr %h.addr
  %ld211 = load ptr, ptr %run.addr
  %res_slot212 = alloca ptr
  %tgp213 = getelementptr i8, ptr %ld211, i64 8
  %tag214 = load i32, ptr %tgp213, align 4
  switch i32 %tag214, label %case_default36 [
      i32 0, label %case_br37
      i32 1, label %case_br38
  ]
case_br37:
  %ld215 = load ptr, ptr %run.addr
  call void @march_decrc(ptr %ld215)
  %hp216 = call ptr @march_alloc(i64 16)
  %tgp217 = getelementptr i8, ptr %hp216, i64 8
  store i32 0, ptr %tgp217, align 4
  %$t1006.addr = alloca ptr
  store ptr %hp216, ptr %$t1006.addr
  %hp218 = call ptr @march_alloc(i64 32)
  %tgp219 = getelementptr i8, ptr %hp218, i64 8
  store i32 1, ptr %tgp219, align 4
  %ld220 = load i64, ptr %h.addr
  %cv221 = inttoptr i64 %ld220 to ptr
  %fp222 = getelementptr i8, ptr %hp218, i64 16
  store ptr %cv221, ptr %fp222, align 8
  %ld223 = load ptr, ptr %$t1006.addr
  %fp224 = getelementptr i8, ptr %hp218, i64 24
  store ptr %ld223, ptr %fp224, align 8
  %$t1007.addr = alloca ptr
  store ptr %hp218, ptr %$t1007.addr
  %ld225 = load ptr, ptr %t.addr
  %ld226 = load ptr, ptr %$t1007.addr
  %cr227 = call ptr @scan_asc(ptr %ld225, ptr %ld226, i64 1)
  store ptr %cr227, ptr %res_slot212
  br label %case_merge35
case_br38:
  %fp228 = getelementptr i8, ptr %ld211, i64 16
  %fv229 = load ptr, ptr %fp228, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv229, ptr %$f1012.addr
  %fp230 = getelementptr i8, ptr %ld211, i64 24
  %fv231 = load ptr, ptr %fp230, align 8
  %$f1013.addr = alloca ptr
  store ptr %fv231, ptr %$f1013.addr
  %ld232 = load ptr, ptr %$f1012.addr
  %prev.addr = alloca ptr
  store ptr %ld232, ptr %prev.addr
  %ld233 = load i64, ptr %prev.addr
  %ld234 = load i64, ptr %h.addr
  %cmp235 = icmp sle i64 %ld233, %ld234
  %ar236 = zext i1 %cmp235 to i64
  %$t1008.addr = alloca i64
  store i64 %ar236, ptr %$t1008.addr
  %ld237 = load i64, ptr %$t1008.addr
  %res_slot238 = alloca ptr
  switch i64 %ld237, label %case_default40 [
      i64 1, label %case_br41
  ]
case_br41:
  %hp239 = call ptr @march_alloc(i64 32)
  %tgp240 = getelementptr i8, ptr %hp239, i64 8
  store i32 1, ptr %tgp240, align 4
  %ld241 = load i64, ptr %h.addr
  %cv242 = inttoptr i64 %ld241 to ptr
  %fp243 = getelementptr i8, ptr %hp239, i64 16
  store ptr %cv242, ptr %fp243, align 8
  %ld244 = load ptr, ptr %run.addr
  %fp245 = getelementptr i8, ptr %hp239, i64 24
  store ptr %ld244, ptr %fp245, align 8
  %$t1009.addr = alloca ptr
  store ptr %hp239, ptr %$t1009.addr
  %ld246 = load i64, ptr %run_len.addr
  %ar247 = add i64 %ld246, 1
  %$t1010.addr = alloca i64
  store i64 %ar247, ptr %$t1010.addr
  %ld248 = load ptr, ptr %t.addr
  %ld249 = load ptr, ptr %$t1009.addr
  %ld250 = load i64, ptr %$t1010.addr
  %cr251 = call ptr @scan_asc(ptr %ld248, ptr %ld249, i64 %ld250)
  store ptr %cr251, ptr %res_slot238
  br label %case_merge39
case_default40:
  %ld252 = load ptr, ptr %run.addr
  %cr253 = call ptr @reverse_list(ptr %ld252)
  %$t1011.addr = alloca ptr
  store ptr %cr253, ptr %$t1011.addr
  %hp254 = call ptr @march_alloc(i64 40)
  %tgp255 = getelementptr i8, ptr %hp254, i64 8
  store i32 0, ptr %tgp255, align 4
  %ld256 = load ptr, ptr %$t1011.addr
  %fp257 = getelementptr i8, ptr %hp254, i64 16
  store ptr %ld256, ptr %fp257, align 8
  %ld258 = load i64, ptr %run_len.addr
  %fp259 = getelementptr i8, ptr %hp254, i64 24
  store i64 %ld258, ptr %fp259, align 8
  %ld260 = load ptr, ptr %lst.addr
  %fp261 = getelementptr i8, ptr %hp254, i64 32
  store ptr %ld260, ptr %fp261, align 8
  store ptr %hp254, ptr %res_slot238
  br label %case_merge39
case_merge39:
  %case_r262 = load ptr, ptr %res_slot238
  store ptr %case_r262, ptr %res_slot212
  br label %case_merge35
case_default36:
  unreachable
case_merge35:
  %case_r263 = load ptr, ptr %res_slot212
  store ptr %case_r263, ptr %res_slot184
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r264 = load ptr, ptr %res_slot184
  ret ptr %case_r264
}

define ptr @enforce(ptr %stack.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld265 = load ptr, ptr %stack.addr
  %res_slot266 = alloca ptr
  %tgp267 = getelementptr i8, ptr %ld265, i64 8
  %tag268 = load i32, ptr %tgp267, align 4
  switch i32 %tag268, label %case_default43 [
      i32 0, label %case_br44
      i32 1, label %case_br45
  ]
case_br44:
  %ld269 = load ptr, ptr %stack.addr
  %rc270 = load i64, ptr %ld269, align 8
  %uniq271 = icmp eq i64 %rc270, 1
  %fbip_slot272 = alloca ptr
  br i1 %uniq271, label %fbip_reuse46, label %fbip_fresh47
fbip_reuse46:
  %tgp273 = getelementptr i8, ptr %ld269, i64 8
  store i32 0, ptr %tgp273, align 4
  store ptr %ld269, ptr %fbip_slot272
  br label %fbip_merge48
fbip_fresh47:
  call void @march_decrc(ptr %ld269)
  %hp274 = call ptr @march_alloc(i64 16)
  %tgp275 = getelementptr i8, ptr %hp274, i64 8
  store i32 0, ptr %tgp275, align 4
  store ptr %hp274, ptr %fbip_slot272
  br label %fbip_merge48
fbip_merge48:
  %fbip_r276 = load ptr, ptr %fbip_slot272
  store ptr %fbip_r276, ptr %res_slot266
  br label %case_merge42
case_br45:
  %fp277 = getelementptr i8, ptr %ld265, i64 16
  %fv278 = load ptr, ptr %fp277, align 8
  %$f1033.addr = alloca ptr
  store ptr %fv278, ptr %$f1033.addr
  %fp279 = getelementptr i8, ptr %ld265, i64 24
  %fv280 = load ptr, ptr %fp279, align 8
  %$f1034.addr = alloca ptr
  store ptr %fv280, ptr %$f1034.addr
  %ld281 = load ptr, ptr %$f1034.addr
  %res_slot282 = alloca ptr
  %tgp283 = getelementptr i8, ptr %ld281, i64 8
  %tag284 = load i32, ptr %tgp283, align 4
  switch i32 %tag284, label %case_default50 [
      i32 0, label %case_br51
  ]
case_br51:
  %ld285 = load ptr, ptr %stack.addr
  store ptr %ld285, ptr %res_slot282
  br label %case_merge49
case_default50:
  %ld286 = load ptr, ptr %$f1033.addr
  %res_slot287 = alloca ptr
  %tgp288 = getelementptr i8, ptr %ld286, i64 8
  %tag289 = load i32, ptr %tgp288, align 4
  switch i32 %tag289, label %case_default53 [
      i32 0, label %case_br54
  ]
case_br54:
  %fp290 = getelementptr i8, ptr %ld286, i64 16
  %fv291 = load ptr, ptr %fp290, align 8
  %$f1035.addr = alloca ptr
  store ptr %fv291, ptr %$f1035.addr
  %fp292 = getelementptr i8, ptr %ld286, i64 24
  %fv293 = load ptr, ptr %fp292, align 8
  %$f1036.addr = alloca ptr
  store ptr %fv293, ptr %$f1036.addr
  %ld294 = load ptr, ptr %$f1034.addr
  %res_slot295 = alloca ptr
  %tgp296 = getelementptr i8, ptr %ld294, i64 8
  %tag297 = load i32, ptr %tgp296, align 4
  switch i32 %tag297, label %case_default56 [
      i32 1, label %case_br57
  ]
case_br57:
  %fp298 = getelementptr i8, ptr %ld294, i64 16
  %fv299 = load ptr, ptr %fp298, align 8
  %$f1045.addr = alloca ptr
  store ptr %fv299, ptr %$f1045.addr
  %fp300 = getelementptr i8, ptr %ld294, i64 24
  %fv301 = load ptr, ptr %fp300, align 8
  %$f1046.addr = alloca ptr
  store ptr %fv301, ptr %$f1046.addr
  %ld302 = load ptr, ptr %$f1045.addr
  %res_slot303 = alloca ptr
  %tgp304 = getelementptr i8, ptr %ld302, i64 8
  %tag305 = load i32, ptr %tgp304, align 4
  switch i32 %tag305, label %case_default59 [
      i32 0, label %case_br60
  ]
case_br60:
  %fp306 = getelementptr i8, ptr %ld302, i64 16
  %fv307 = load ptr, ptr %fp306, align 8
  %$f1047.addr = alloca ptr
  store ptr %fv307, ptr %$f1047.addr
  %fp308 = getelementptr i8, ptr %ld302, i64 24
  %fv309 = load ptr, ptr %fp308, align 8
  %$f1048.addr = alloca ptr
  store ptr %fv309, ptr %$f1048.addr
  %ld310 = load ptr, ptr %$f1046.addr
  %res_slot311 = alloca ptr
  %tgp312 = getelementptr i8, ptr %ld310, i64 8
  %tag313 = load i32, ptr %tgp312, align 4
  switch i32 %tag313, label %case_default62 [
      i32 0, label %case_br63
  ]
case_br63:
  %ld314 = load ptr, ptr %$f1048.addr
  %yn.addr = alloca ptr
  store ptr %ld314, ptr %yn.addr
  %ld315 = load ptr, ptr %$f1047.addr
  %y.addr = alloca ptr
  store ptr %ld315, ptr %y.addr
  %ld316 = load ptr, ptr %$f1036.addr
  %xn.addr = alloca ptr
  store ptr %ld316, ptr %xn.addr
  %ld317 = load ptr, ptr %$f1035.addr
  %x.addr = alloca ptr
  store ptr %ld317, ptr %x.addr
  %ld318 = load i64, ptr %yn.addr
  %ld319 = load i64, ptr %xn.addr
  %cmp320 = icmp sle i64 %ld318, %ld319
  %ar321 = zext i1 %cmp320 to i64
  %$t1016.addr = alloca i64
  store i64 %ar321, ptr %$t1016.addr
  %ld322 = load i64, ptr %$t1016.addr
  %res_slot323 = alloca ptr
  switch i64 %ld322, label %case_default65 [
      i64 1, label %case_br66
  ]
case_br66:
  %ld324 = load ptr, ptr %y.addr
  %ld325 = load ptr, ptr %x.addr
  %cr326 = call ptr @merge_ms(ptr %ld324, ptr %ld325)
  %m.addr = alloca ptr
  store ptr %cr326, ptr %m.addr
  %ld327 = load i64, ptr %xn.addr
  %ld328 = load i64, ptr %yn.addr
  %ar329 = add i64 %ld327, %ld328
  %$t1017.addr = alloca i64
  store i64 %ar329, ptr %$t1017.addr
  %hp330 = call ptr @march_alloc(i64 32)
  %tgp331 = getelementptr i8, ptr %hp330, i64 8
  store i32 0, ptr %tgp331, align 4
  %ld332 = load ptr, ptr %m.addr
  %fp333 = getelementptr i8, ptr %hp330, i64 16
  store ptr %ld332, ptr %fp333, align 8
  %ld334 = load i64, ptr %$t1017.addr
  %fp335 = getelementptr i8, ptr %hp330, i64 24
  store i64 %ld334, ptr %fp335, align 8
  %$t1018.addr = alloca ptr
  store ptr %hp330, ptr %$t1018.addr
  %hp336 = call ptr @march_alloc(i64 16)
  %tgp337 = getelementptr i8, ptr %hp336, i64 8
  store i32 0, ptr %tgp337, align 4
  %$t1019.addr = alloca ptr
  store ptr %hp336, ptr %$t1019.addr
  %hp338 = call ptr @march_alloc(i64 32)
  %tgp339 = getelementptr i8, ptr %hp338, i64 8
  store i32 1, ptr %tgp339, align 4
  %ld340 = load ptr, ptr %$t1018.addr
  %fp341 = getelementptr i8, ptr %hp338, i64 16
  store ptr %ld340, ptr %fp341, align 8
  %ld342 = load ptr, ptr %$t1019.addr
  %fp343 = getelementptr i8, ptr %hp338, i64 24
  store ptr %ld342, ptr %fp343, align 8
  store ptr %hp338, ptr %res_slot323
  br label %case_merge64
case_default65:
  %ld344 = load ptr, ptr %stack.addr
  store ptr %ld344, ptr %res_slot323
  br label %case_merge64
case_merge64:
  %case_r345 = load ptr, ptr %res_slot323
  store ptr %case_r345, ptr %res_slot311
  br label %case_merge61
case_default62:
  %ld346 = load ptr, ptr %$f1034.addr
  %res_slot347 = alloca ptr
  %tgp348 = getelementptr i8, ptr %ld346, i64 8
  %tag349 = load i32, ptr %tgp348, align 4
  switch i32 %tag349, label %case_default68 [
      i32 1, label %case_br69
  ]
case_br69:
  %fp350 = getelementptr i8, ptr %ld346, i64 16
  %fv351 = load ptr, ptr %fp350, align 8
  %$f1037.addr = alloca ptr
  store ptr %fv351, ptr %$f1037.addr
  %fp352 = getelementptr i8, ptr %ld346, i64 24
  %fv353 = load ptr, ptr %fp352, align 8
  %$f1038.addr = alloca ptr
  store ptr %fv353, ptr %$f1038.addr
  %ld354 = load ptr, ptr %$f1037.addr
  %res_slot355 = alloca ptr
  %tgp356 = getelementptr i8, ptr %ld354, i64 8
  %tag357 = load i32, ptr %tgp356, align 4
  switch i32 %tag357, label %case_default71 [
      i32 0, label %case_br72
  ]
case_br72:
  %fp358 = getelementptr i8, ptr %ld354, i64 16
  %fv359 = load ptr, ptr %fp358, align 8
  %$f1039.addr = alloca ptr
  store ptr %fv359, ptr %$f1039.addr
  %fp360 = getelementptr i8, ptr %ld354, i64 24
  %fv361 = load ptr, ptr %fp360, align 8
  %$f1040.addr = alloca ptr
  store ptr %fv361, ptr %$f1040.addr
  %ld362 = load ptr, ptr %$f1038.addr
  %res_slot363 = alloca ptr
  %tgp364 = getelementptr i8, ptr %ld362, i64 8
  %tag365 = load i32, ptr %tgp364, align 4
  switch i32 %tag365, label %case_default74 [
      i32 1, label %case_br75
  ]
case_br75:
  %fp366 = getelementptr i8, ptr %ld362, i64 16
  %fv367 = load ptr, ptr %fp366, align 8
  %$f1041.addr = alloca ptr
  store ptr %fv367, ptr %$f1041.addr
  %fp368 = getelementptr i8, ptr %ld362, i64 24
  %fv369 = load ptr, ptr %fp368, align 8
  %$f1042.addr = alloca ptr
  store ptr %fv369, ptr %$f1042.addr
  %ld370 = load ptr, ptr %$f1041.addr
  %res_slot371 = alloca ptr
  %tgp372 = getelementptr i8, ptr %ld370, i64 8
  %tag373 = load i32, ptr %tgp372, align 4
  switch i32 %tag373, label %case_default77 [
      i32 0, label %case_br78
  ]
case_br78:
  %fp374 = getelementptr i8, ptr %ld370, i64 16
  %fv375 = load ptr, ptr %fp374, align 8
  %$f1043.addr = alloca ptr
  store ptr %fv375, ptr %$f1043.addr
  %fp376 = getelementptr i8, ptr %ld370, i64 24
  %fv377 = load ptr, ptr %fp376, align 8
  %$f1044.addr = alloca ptr
  store ptr %fv377, ptr %$f1044.addr
  %ld378 = load ptr, ptr %$f1042.addr
  %rest.addr = alloca ptr
  store ptr %ld378, ptr %rest.addr
  %ld379 = load ptr, ptr %$f1044.addr
  %zn.addr = alloca ptr
  store ptr %ld379, ptr %zn.addr
  %ld380 = load ptr, ptr %$f1043.addr
  %z.addr = alloca ptr
  store ptr %ld380, ptr %z.addr
  %ld381 = load ptr, ptr %$f1040.addr
  %yn_1.addr = alloca ptr
  store ptr %ld381, ptr %yn_1.addr
  %ld382 = load ptr, ptr %$f1039.addr
  %y_1.addr = alloca ptr
  store ptr %ld382, ptr %y_1.addr
  %ld383 = load ptr, ptr %$f1036.addr
  %xn_1.addr = alloca ptr
  store ptr %ld383, ptr %xn_1.addr
  %ld384 = load ptr, ptr %$f1035.addr
  %x_1.addr = alloca ptr
  store ptr %ld384, ptr %x_1.addr
  %ld385 = load i64, ptr %yn_1.addr
  %ld386 = load i64, ptr %xn_1.addr
  %cmp387 = icmp sle i64 %ld385, %ld386
  %ar388 = zext i1 %cmp387 to i64
  %$t1020.addr = alloca i64
  store i64 %ar388, ptr %$t1020.addr
  %ld389 = load i64, ptr %$t1020.addr
  %res_slot390 = alloca ptr
  switch i64 %ld389, label %case_default80 [
      i64 1, label %case_br81
  ]
case_br81:
  %ld391 = load ptr, ptr %y_1.addr
  %ld392 = load ptr, ptr %x_1.addr
  %cr393 = call ptr @merge_ms(ptr %ld391, ptr %ld392)
  %m_1.addr = alloca ptr
  store ptr %cr393, ptr %m_1.addr
  %ld394 = load i64, ptr %xn_1.addr
  %ld395 = load i64, ptr %yn_1.addr
  %ar396 = add i64 %ld394, %ld395
  %$t1021.addr = alloca i64
  store i64 %ar396, ptr %$t1021.addr
  %hp397 = call ptr @march_alloc(i64 32)
  %tgp398 = getelementptr i8, ptr %hp397, i64 8
  store i32 0, ptr %tgp398, align 4
  %ld399 = load ptr, ptr %m_1.addr
  %fp400 = getelementptr i8, ptr %hp397, i64 16
  store ptr %ld399, ptr %fp400, align 8
  %ld401 = load i64, ptr %$t1021.addr
  %fp402 = getelementptr i8, ptr %hp397, i64 24
  store i64 %ld401, ptr %fp402, align 8
  %$t1022.addr = alloca ptr
  store ptr %hp397, ptr %$t1022.addr
  %hp403 = call ptr @march_alloc(i64 32)
  %tgp404 = getelementptr i8, ptr %hp403, i64 8
  store i32 0, ptr %tgp404, align 4
  %ld405 = load ptr, ptr %z.addr
  %fp406 = getelementptr i8, ptr %hp403, i64 16
  store ptr %ld405, ptr %fp406, align 8
  %ld407 = load i64, ptr %zn.addr
  %fp408 = getelementptr i8, ptr %hp403, i64 24
  store i64 %ld407, ptr %fp408, align 8
  %$t1023.addr = alloca ptr
  store ptr %hp403, ptr %$t1023.addr
  %hp409 = call ptr @march_alloc(i64 32)
  %tgp410 = getelementptr i8, ptr %hp409, i64 8
  store i32 1, ptr %tgp410, align 4
  %ld411 = load ptr, ptr %$t1023.addr
  %fp412 = getelementptr i8, ptr %hp409, i64 16
  store ptr %ld411, ptr %fp412, align 8
  %ld413 = load ptr, ptr %rest.addr
  %fp414 = getelementptr i8, ptr %hp409, i64 24
  store ptr %ld413, ptr %fp414, align 8
  %$t1024.addr = alloca ptr
  store ptr %hp409, ptr %$t1024.addr
  %hp415 = call ptr @march_alloc(i64 32)
  %tgp416 = getelementptr i8, ptr %hp415, i64 8
  store i32 1, ptr %tgp416, align 4
  %ld417 = load ptr, ptr %$t1022.addr
  %fp418 = getelementptr i8, ptr %hp415, i64 16
  store ptr %ld417, ptr %fp418, align 8
  %ld419 = load ptr, ptr %$t1024.addr
  %fp420 = getelementptr i8, ptr %hp415, i64 24
  store ptr %ld419, ptr %fp420, align 8
  %$t1025.addr = alloca ptr
  store ptr %hp415, ptr %$t1025.addr
  %ld421 = load ptr, ptr %$t1025.addr
  %cr422 = call ptr @enforce(ptr %ld421)
  store ptr %cr422, ptr %res_slot390
  br label %case_merge79
case_default80:
  %ld423 = load i64, ptr %yn_1.addr
  %ld424 = load i64, ptr %xn_1.addr
  %ar425 = add i64 %ld423, %ld424
  %$t1026.addr = alloca i64
  store i64 %ar425, ptr %$t1026.addr
  %ld426 = load i64, ptr %zn.addr
  %ld427 = load i64, ptr %$t1026.addr
  %cmp428 = icmp sle i64 %ld426, %ld427
  %ar429 = zext i1 %cmp428 to i64
  %$t1027.addr = alloca i64
  store i64 %ar429, ptr %$t1027.addr
  %ld430 = load i64, ptr %$t1027.addr
  %res_slot431 = alloca ptr
  switch i64 %ld430, label %case_default83 [
      i64 1, label %case_br84
  ]
case_br84:
  %ld432 = load ptr, ptr %z.addr
  %ld433 = load ptr, ptr %y_1.addr
  %cr434 = call ptr @merge_ms(ptr %ld432, ptr %ld433)
  %m_2.addr = alloca ptr
  store ptr %cr434, ptr %m_2.addr
  %hp435 = call ptr @march_alloc(i64 32)
  %tgp436 = getelementptr i8, ptr %hp435, i64 8
  store i32 0, ptr %tgp436, align 4
  %ld437 = load ptr, ptr %x_1.addr
  %fp438 = getelementptr i8, ptr %hp435, i64 16
  store ptr %ld437, ptr %fp438, align 8
  %ld439 = load i64, ptr %xn_1.addr
  %fp440 = getelementptr i8, ptr %hp435, i64 24
  store i64 %ld439, ptr %fp440, align 8
  %$t1028.addr = alloca ptr
  store ptr %hp435, ptr %$t1028.addr
  %ld441 = load i64, ptr %yn_1.addr
  %ld442 = load i64, ptr %zn.addr
  %ar443 = add i64 %ld441, %ld442
  %$t1029.addr = alloca i64
  store i64 %ar443, ptr %$t1029.addr
  %hp444 = call ptr @march_alloc(i64 32)
  %tgp445 = getelementptr i8, ptr %hp444, i64 8
  store i32 0, ptr %tgp445, align 4
  %ld446 = load ptr, ptr %m_2.addr
  %fp447 = getelementptr i8, ptr %hp444, i64 16
  store ptr %ld446, ptr %fp447, align 8
  %ld448 = load i64, ptr %$t1029.addr
  %fp449 = getelementptr i8, ptr %hp444, i64 24
  store i64 %ld448, ptr %fp449, align 8
  %$t1030.addr = alloca ptr
  store ptr %hp444, ptr %$t1030.addr
  %hp450 = call ptr @march_alloc(i64 32)
  %tgp451 = getelementptr i8, ptr %hp450, i64 8
  store i32 1, ptr %tgp451, align 4
  %ld452 = load ptr, ptr %$t1030.addr
  %fp453 = getelementptr i8, ptr %hp450, i64 16
  store ptr %ld452, ptr %fp453, align 8
  %ld454 = load ptr, ptr %rest.addr
  %fp455 = getelementptr i8, ptr %hp450, i64 24
  store ptr %ld454, ptr %fp455, align 8
  %$t1031.addr = alloca ptr
  store ptr %hp450, ptr %$t1031.addr
  %hp456 = call ptr @march_alloc(i64 32)
  %tgp457 = getelementptr i8, ptr %hp456, i64 8
  store i32 1, ptr %tgp457, align 4
  %ld458 = load ptr, ptr %$t1028.addr
  %fp459 = getelementptr i8, ptr %hp456, i64 16
  store ptr %ld458, ptr %fp459, align 8
  %ld460 = load ptr, ptr %$t1031.addr
  %fp461 = getelementptr i8, ptr %hp456, i64 24
  store ptr %ld460, ptr %fp461, align 8
  %$t1032.addr = alloca ptr
  store ptr %hp456, ptr %$t1032.addr
  %ld462 = load ptr, ptr %$t1032.addr
  %cr463 = call ptr @enforce(ptr %ld462)
  store ptr %cr463, ptr %res_slot431
  br label %case_merge82
case_default83:
  %ld464 = load ptr, ptr %stack.addr
  store ptr %ld464, ptr %res_slot431
  br label %case_merge82
case_merge82:
  %case_r465 = load ptr, ptr %res_slot431
  store ptr %case_r465, ptr %res_slot390
  br label %case_merge79
case_merge79:
  %case_r466 = load ptr, ptr %res_slot390
  store ptr %case_r466, ptr %res_slot371
  br label %case_merge76
case_default77:
  %cv467 = inttoptr i64 0 to ptr
  store ptr %cv467, ptr %res_slot371
  br label %case_merge76
case_merge76:
  %case_r468 = load ptr, ptr %res_slot371
  store ptr %case_r468, ptr %res_slot363
  br label %case_merge73
case_default74:
  %cv469 = inttoptr i64 0 to ptr
  store ptr %cv469, ptr %res_slot363
  br label %case_merge73
case_merge73:
  %case_r470 = load ptr, ptr %res_slot363
  store ptr %case_r470, ptr %res_slot355
  br label %case_merge70
case_default71:
  %cv471 = inttoptr i64 0 to ptr
  store ptr %cv471, ptr %res_slot355
  br label %case_merge70
case_merge70:
  %case_r472 = load ptr, ptr %res_slot355
  store ptr %case_r472, ptr %res_slot347
  br label %case_merge67
case_default68:
  %cv473 = inttoptr i64 0 to ptr
  store ptr %cv473, ptr %res_slot347
  br label %case_merge67
case_merge67:
  %case_r474 = load ptr, ptr %res_slot347
  store ptr %case_r474, ptr %res_slot311
  br label %case_merge61
case_merge61:
  %case_r475 = load ptr, ptr %res_slot311
  store ptr %case_r475, ptr %res_slot303
  br label %case_merge58
case_default59:
  %ld476 = load ptr, ptr %$f1034.addr
  %res_slot477 = alloca ptr
  %tgp478 = getelementptr i8, ptr %ld476, i64 8
  %tag479 = load i32, ptr %tgp478, align 4
  switch i32 %tag479, label %case_default86 [
      i32 1, label %case_br87
  ]
case_br87:
  %fp480 = getelementptr i8, ptr %ld476, i64 16
  %fv481 = load ptr, ptr %fp480, align 8
  %$f1037_1.addr = alloca ptr
  store ptr %fv481, ptr %$f1037_1.addr
  %fp482 = getelementptr i8, ptr %ld476, i64 24
  %fv483 = load ptr, ptr %fp482, align 8
  %$f1038_1.addr = alloca ptr
  store ptr %fv483, ptr %$f1038_1.addr
  %ld484 = load ptr, ptr %$f1037_1.addr
  %res_slot485 = alloca ptr
  %tgp486 = getelementptr i8, ptr %ld484, i64 8
  %tag487 = load i32, ptr %tgp486, align 4
  switch i32 %tag487, label %case_default89 [
      i32 0, label %case_br90
  ]
case_br90:
  %fp488 = getelementptr i8, ptr %ld484, i64 16
  %fv489 = load ptr, ptr %fp488, align 8
  %$f1039_1.addr = alloca ptr
  store ptr %fv489, ptr %$f1039_1.addr
  %fp490 = getelementptr i8, ptr %ld484, i64 24
  %fv491 = load ptr, ptr %fp490, align 8
  %$f1040_1.addr = alloca ptr
  store ptr %fv491, ptr %$f1040_1.addr
  %ld492 = load ptr, ptr %$f1038_1.addr
  %res_slot493 = alloca ptr
  %tgp494 = getelementptr i8, ptr %ld492, i64 8
  %tag495 = load i32, ptr %tgp494, align 4
  switch i32 %tag495, label %case_default92 [
      i32 1, label %case_br93
  ]
case_br93:
  %fp496 = getelementptr i8, ptr %ld492, i64 16
  %fv497 = load ptr, ptr %fp496, align 8
  %$f1041_1.addr = alloca ptr
  store ptr %fv497, ptr %$f1041_1.addr
  %fp498 = getelementptr i8, ptr %ld492, i64 24
  %fv499 = load ptr, ptr %fp498, align 8
  %$f1042_1.addr = alloca ptr
  store ptr %fv499, ptr %$f1042_1.addr
  %ld500 = load ptr, ptr %$f1041_1.addr
  %res_slot501 = alloca ptr
  %tgp502 = getelementptr i8, ptr %ld500, i64 8
  %tag503 = load i32, ptr %tgp502, align 4
  switch i32 %tag503, label %case_default95 [
      i32 0, label %case_br96
  ]
case_br96:
  %fp504 = getelementptr i8, ptr %ld500, i64 16
  %fv505 = load ptr, ptr %fp504, align 8
  %$f1043_1.addr = alloca ptr
  store ptr %fv505, ptr %$f1043_1.addr
  %fp506 = getelementptr i8, ptr %ld500, i64 24
  %fv507 = load ptr, ptr %fp506, align 8
  %$f1044_1.addr = alloca ptr
  store ptr %fv507, ptr %$f1044_1.addr
  %ld508 = load ptr, ptr %$f1042_1.addr
  %rest_1.addr = alloca ptr
  store ptr %ld508, ptr %rest_1.addr
  %ld509 = load ptr, ptr %$f1044_1.addr
  %zn_1.addr = alloca ptr
  store ptr %ld509, ptr %zn_1.addr
  %ld510 = load ptr, ptr %$f1043_1.addr
  %z_1.addr = alloca ptr
  store ptr %ld510, ptr %z_1.addr
  %ld511 = load ptr, ptr %$f1040_1.addr
  %yn_2.addr = alloca ptr
  store ptr %ld511, ptr %yn_2.addr
  %ld512 = load ptr, ptr %$f1039_1.addr
  %y_2.addr = alloca ptr
  store ptr %ld512, ptr %y_2.addr
  %ld513 = load ptr, ptr %$f1036.addr
  %xn_2.addr = alloca ptr
  store ptr %ld513, ptr %xn_2.addr
  %ld514 = load ptr, ptr %$f1035.addr
  %x_2.addr = alloca ptr
  store ptr %ld514, ptr %x_2.addr
  %ld515 = load i64, ptr %yn_2.addr
  %ld516 = load i64, ptr %xn_2.addr
  %cmp517 = icmp sle i64 %ld515, %ld516
  %ar518 = zext i1 %cmp517 to i64
  %$t1020_1.addr = alloca i64
  store i64 %ar518, ptr %$t1020_1.addr
  %ld519 = load i64, ptr %$t1020_1.addr
  %res_slot520 = alloca ptr
  switch i64 %ld519, label %case_default98 [
      i64 1, label %case_br99
  ]
case_br99:
  %ld521 = load ptr, ptr %y_2.addr
  %ld522 = load ptr, ptr %x_2.addr
  %cr523 = call ptr @merge_ms(ptr %ld521, ptr %ld522)
  %m_3.addr = alloca ptr
  store ptr %cr523, ptr %m_3.addr
  %ld524 = load i64, ptr %xn_2.addr
  %ld525 = load i64, ptr %yn_2.addr
  %ar526 = add i64 %ld524, %ld525
  %$t1021_1.addr = alloca i64
  store i64 %ar526, ptr %$t1021_1.addr
  %hp527 = call ptr @march_alloc(i64 32)
  %tgp528 = getelementptr i8, ptr %hp527, i64 8
  store i32 0, ptr %tgp528, align 4
  %ld529 = load ptr, ptr %m_3.addr
  %fp530 = getelementptr i8, ptr %hp527, i64 16
  store ptr %ld529, ptr %fp530, align 8
  %ld531 = load i64, ptr %$t1021_1.addr
  %fp532 = getelementptr i8, ptr %hp527, i64 24
  store i64 %ld531, ptr %fp532, align 8
  %$t1022_1.addr = alloca ptr
  store ptr %hp527, ptr %$t1022_1.addr
  %hp533 = call ptr @march_alloc(i64 32)
  %tgp534 = getelementptr i8, ptr %hp533, i64 8
  store i32 0, ptr %tgp534, align 4
  %ld535 = load ptr, ptr %z_1.addr
  %fp536 = getelementptr i8, ptr %hp533, i64 16
  store ptr %ld535, ptr %fp536, align 8
  %ld537 = load i64, ptr %zn_1.addr
  %fp538 = getelementptr i8, ptr %hp533, i64 24
  store i64 %ld537, ptr %fp538, align 8
  %$t1023_1.addr = alloca ptr
  store ptr %hp533, ptr %$t1023_1.addr
  %hp539 = call ptr @march_alloc(i64 32)
  %tgp540 = getelementptr i8, ptr %hp539, i64 8
  store i32 1, ptr %tgp540, align 4
  %ld541 = load ptr, ptr %$t1023_1.addr
  %fp542 = getelementptr i8, ptr %hp539, i64 16
  store ptr %ld541, ptr %fp542, align 8
  %ld543 = load ptr, ptr %rest_1.addr
  %fp544 = getelementptr i8, ptr %hp539, i64 24
  store ptr %ld543, ptr %fp544, align 8
  %$t1024_1.addr = alloca ptr
  store ptr %hp539, ptr %$t1024_1.addr
  %hp545 = call ptr @march_alloc(i64 32)
  %tgp546 = getelementptr i8, ptr %hp545, i64 8
  store i32 1, ptr %tgp546, align 4
  %ld547 = load ptr, ptr %$t1022_1.addr
  %fp548 = getelementptr i8, ptr %hp545, i64 16
  store ptr %ld547, ptr %fp548, align 8
  %ld549 = load ptr, ptr %$t1024_1.addr
  %fp550 = getelementptr i8, ptr %hp545, i64 24
  store ptr %ld549, ptr %fp550, align 8
  %$t1025_1.addr = alloca ptr
  store ptr %hp545, ptr %$t1025_1.addr
  %ld551 = load ptr, ptr %$t1025_1.addr
  %cr552 = call ptr @enforce(ptr %ld551)
  store ptr %cr552, ptr %res_slot520
  br label %case_merge97
case_default98:
  %ld553 = load i64, ptr %yn_2.addr
  %ld554 = load i64, ptr %xn_2.addr
  %ar555 = add i64 %ld553, %ld554
  %$t1026_1.addr = alloca i64
  store i64 %ar555, ptr %$t1026_1.addr
  %ld556 = load i64, ptr %zn_1.addr
  %ld557 = load i64, ptr %$t1026_1.addr
  %cmp558 = icmp sle i64 %ld556, %ld557
  %ar559 = zext i1 %cmp558 to i64
  %$t1027_1.addr = alloca i64
  store i64 %ar559, ptr %$t1027_1.addr
  %ld560 = load i64, ptr %$t1027_1.addr
  %res_slot561 = alloca ptr
  switch i64 %ld560, label %case_default101 [
      i64 1, label %case_br102
  ]
case_br102:
  %ld562 = load ptr, ptr %z_1.addr
  %ld563 = load ptr, ptr %y_2.addr
  %cr564 = call ptr @merge_ms(ptr %ld562, ptr %ld563)
  %m_4.addr = alloca ptr
  store ptr %cr564, ptr %m_4.addr
  %hp565 = call ptr @march_alloc(i64 32)
  %tgp566 = getelementptr i8, ptr %hp565, i64 8
  store i32 0, ptr %tgp566, align 4
  %ld567 = load ptr, ptr %x_2.addr
  %fp568 = getelementptr i8, ptr %hp565, i64 16
  store ptr %ld567, ptr %fp568, align 8
  %ld569 = load i64, ptr %xn_2.addr
  %fp570 = getelementptr i8, ptr %hp565, i64 24
  store i64 %ld569, ptr %fp570, align 8
  %$t1028_1.addr = alloca ptr
  store ptr %hp565, ptr %$t1028_1.addr
  %ld571 = load i64, ptr %yn_2.addr
  %ld572 = load i64, ptr %zn_1.addr
  %ar573 = add i64 %ld571, %ld572
  %$t1029_1.addr = alloca i64
  store i64 %ar573, ptr %$t1029_1.addr
  %hp574 = call ptr @march_alloc(i64 32)
  %tgp575 = getelementptr i8, ptr %hp574, i64 8
  store i32 0, ptr %tgp575, align 4
  %ld576 = load ptr, ptr %m_4.addr
  %fp577 = getelementptr i8, ptr %hp574, i64 16
  store ptr %ld576, ptr %fp577, align 8
  %ld578 = load i64, ptr %$t1029_1.addr
  %fp579 = getelementptr i8, ptr %hp574, i64 24
  store i64 %ld578, ptr %fp579, align 8
  %$t1030_1.addr = alloca ptr
  store ptr %hp574, ptr %$t1030_1.addr
  %hp580 = call ptr @march_alloc(i64 32)
  %tgp581 = getelementptr i8, ptr %hp580, i64 8
  store i32 1, ptr %tgp581, align 4
  %ld582 = load ptr, ptr %$t1030_1.addr
  %fp583 = getelementptr i8, ptr %hp580, i64 16
  store ptr %ld582, ptr %fp583, align 8
  %ld584 = load ptr, ptr %rest_1.addr
  %fp585 = getelementptr i8, ptr %hp580, i64 24
  store ptr %ld584, ptr %fp585, align 8
  %$t1031_1.addr = alloca ptr
  store ptr %hp580, ptr %$t1031_1.addr
  %hp586 = call ptr @march_alloc(i64 32)
  %tgp587 = getelementptr i8, ptr %hp586, i64 8
  store i32 1, ptr %tgp587, align 4
  %ld588 = load ptr, ptr %$t1028_1.addr
  %fp589 = getelementptr i8, ptr %hp586, i64 16
  store ptr %ld588, ptr %fp589, align 8
  %ld590 = load ptr, ptr %$t1031_1.addr
  %fp591 = getelementptr i8, ptr %hp586, i64 24
  store ptr %ld590, ptr %fp591, align 8
  %$t1032_1.addr = alloca ptr
  store ptr %hp586, ptr %$t1032_1.addr
  %ld592 = load ptr, ptr %$t1032_1.addr
  %cr593 = call ptr @enforce(ptr %ld592)
  store ptr %cr593, ptr %res_slot561
  br label %case_merge100
case_default101:
  %ld594 = load ptr, ptr %stack.addr
  store ptr %ld594, ptr %res_slot561
  br label %case_merge100
case_merge100:
  %case_r595 = load ptr, ptr %res_slot561
  store ptr %case_r595, ptr %res_slot520
  br label %case_merge97
case_merge97:
  %case_r596 = load ptr, ptr %res_slot520
  store ptr %case_r596, ptr %res_slot501
  br label %case_merge94
case_default95:
  %cv597 = inttoptr i64 0 to ptr
  store ptr %cv597, ptr %res_slot501
  br label %case_merge94
case_merge94:
  %case_r598 = load ptr, ptr %res_slot501
  store ptr %case_r598, ptr %res_slot493
  br label %case_merge91
case_default92:
  %cv599 = inttoptr i64 0 to ptr
  store ptr %cv599, ptr %res_slot493
  br label %case_merge91
case_merge91:
  %case_r600 = load ptr, ptr %res_slot493
  store ptr %case_r600, ptr %res_slot485
  br label %case_merge88
case_default89:
  %cv601 = inttoptr i64 0 to ptr
  store ptr %cv601, ptr %res_slot485
  br label %case_merge88
case_merge88:
  %case_r602 = load ptr, ptr %res_slot485
  store ptr %case_r602, ptr %res_slot477
  br label %case_merge85
case_default86:
  %cv603 = inttoptr i64 0 to ptr
  store ptr %cv603, ptr %res_slot477
  br label %case_merge85
case_merge85:
  %case_r604 = load ptr, ptr %res_slot477
  store ptr %case_r604, ptr %res_slot303
  br label %case_merge58
case_merge58:
  %case_r605 = load ptr, ptr %res_slot303
  store ptr %case_r605, ptr %res_slot295
  br label %case_merge55
case_default56:
  %ld606 = load ptr, ptr %$f1034.addr
  %res_slot607 = alloca ptr
  %tgp608 = getelementptr i8, ptr %ld606, i64 8
  %tag609 = load i32, ptr %tgp608, align 4
  switch i32 %tag609, label %case_default104 [
      i32 1, label %case_br105
  ]
case_br105:
  %fp610 = getelementptr i8, ptr %ld606, i64 16
  %fv611 = load ptr, ptr %fp610, align 8
  %$f1037_2.addr = alloca ptr
  store ptr %fv611, ptr %$f1037_2.addr
  %fp612 = getelementptr i8, ptr %ld606, i64 24
  %fv613 = load ptr, ptr %fp612, align 8
  %$f1038_2.addr = alloca ptr
  store ptr %fv613, ptr %$f1038_2.addr
  %ld614 = load ptr, ptr %$f1037_2.addr
  %res_slot615 = alloca ptr
  %tgp616 = getelementptr i8, ptr %ld614, i64 8
  %tag617 = load i32, ptr %tgp616, align 4
  switch i32 %tag617, label %case_default107 [
      i32 0, label %case_br108
  ]
case_br108:
  %fp618 = getelementptr i8, ptr %ld614, i64 16
  %fv619 = load ptr, ptr %fp618, align 8
  %$f1039_2.addr = alloca ptr
  store ptr %fv619, ptr %$f1039_2.addr
  %fp620 = getelementptr i8, ptr %ld614, i64 24
  %fv621 = load ptr, ptr %fp620, align 8
  %$f1040_2.addr = alloca ptr
  store ptr %fv621, ptr %$f1040_2.addr
  %ld622 = load ptr, ptr %$f1038_2.addr
  %res_slot623 = alloca ptr
  %tgp624 = getelementptr i8, ptr %ld622, i64 8
  %tag625 = load i32, ptr %tgp624, align 4
  switch i32 %tag625, label %case_default110 [
      i32 1, label %case_br111
  ]
case_br111:
  %fp626 = getelementptr i8, ptr %ld622, i64 16
  %fv627 = load ptr, ptr %fp626, align 8
  %$f1041_2.addr = alloca ptr
  store ptr %fv627, ptr %$f1041_2.addr
  %fp628 = getelementptr i8, ptr %ld622, i64 24
  %fv629 = load ptr, ptr %fp628, align 8
  %$f1042_2.addr = alloca ptr
  store ptr %fv629, ptr %$f1042_2.addr
  %ld630 = load ptr, ptr %$f1041_2.addr
  %res_slot631 = alloca ptr
  %tgp632 = getelementptr i8, ptr %ld630, i64 8
  %tag633 = load i32, ptr %tgp632, align 4
  switch i32 %tag633, label %case_default113 [
      i32 0, label %case_br114
  ]
case_br114:
  %fp634 = getelementptr i8, ptr %ld630, i64 16
  %fv635 = load ptr, ptr %fp634, align 8
  %$f1043_2.addr = alloca ptr
  store ptr %fv635, ptr %$f1043_2.addr
  %fp636 = getelementptr i8, ptr %ld630, i64 24
  %fv637 = load ptr, ptr %fp636, align 8
  %$f1044_2.addr = alloca ptr
  store ptr %fv637, ptr %$f1044_2.addr
  %ld638 = load ptr, ptr %$f1042_2.addr
  %rest_2.addr = alloca ptr
  store ptr %ld638, ptr %rest_2.addr
  %ld639 = load ptr, ptr %$f1044_2.addr
  %zn_2.addr = alloca ptr
  store ptr %ld639, ptr %zn_2.addr
  %ld640 = load ptr, ptr %$f1043_2.addr
  %z_2.addr = alloca ptr
  store ptr %ld640, ptr %z_2.addr
  %ld641 = load ptr, ptr %$f1040_2.addr
  %yn_3.addr = alloca ptr
  store ptr %ld641, ptr %yn_3.addr
  %ld642 = load ptr, ptr %$f1039_2.addr
  %y_3.addr = alloca ptr
  store ptr %ld642, ptr %y_3.addr
  %ld643 = load ptr, ptr %$f1036.addr
  %xn_3.addr = alloca ptr
  store ptr %ld643, ptr %xn_3.addr
  %ld644 = load ptr, ptr %$f1035.addr
  %x_3.addr = alloca ptr
  store ptr %ld644, ptr %x_3.addr
  %ld645 = load i64, ptr %yn_3.addr
  %ld646 = load i64, ptr %xn_3.addr
  %cmp647 = icmp sle i64 %ld645, %ld646
  %ar648 = zext i1 %cmp647 to i64
  %$t1020_2.addr = alloca i64
  store i64 %ar648, ptr %$t1020_2.addr
  %ld649 = load i64, ptr %$t1020_2.addr
  %res_slot650 = alloca ptr
  switch i64 %ld649, label %case_default116 [
      i64 1, label %case_br117
  ]
case_br117:
  %ld651 = load ptr, ptr %y_3.addr
  %ld652 = load ptr, ptr %x_3.addr
  %cr653 = call ptr @merge_ms(ptr %ld651, ptr %ld652)
  %m_5.addr = alloca ptr
  store ptr %cr653, ptr %m_5.addr
  %ld654 = load i64, ptr %xn_3.addr
  %ld655 = load i64, ptr %yn_3.addr
  %ar656 = add i64 %ld654, %ld655
  %$t1021_2.addr = alloca i64
  store i64 %ar656, ptr %$t1021_2.addr
  %hp657 = call ptr @march_alloc(i64 32)
  %tgp658 = getelementptr i8, ptr %hp657, i64 8
  store i32 0, ptr %tgp658, align 4
  %ld659 = load ptr, ptr %m_5.addr
  %fp660 = getelementptr i8, ptr %hp657, i64 16
  store ptr %ld659, ptr %fp660, align 8
  %ld661 = load i64, ptr %$t1021_2.addr
  %fp662 = getelementptr i8, ptr %hp657, i64 24
  store i64 %ld661, ptr %fp662, align 8
  %$t1022_2.addr = alloca ptr
  store ptr %hp657, ptr %$t1022_2.addr
  %hp663 = call ptr @march_alloc(i64 32)
  %tgp664 = getelementptr i8, ptr %hp663, i64 8
  store i32 0, ptr %tgp664, align 4
  %ld665 = load ptr, ptr %z_2.addr
  %fp666 = getelementptr i8, ptr %hp663, i64 16
  store ptr %ld665, ptr %fp666, align 8
  %ld667 = load i64, ptr %zn_2.addr
  %fp668 = getelementptr i8, ptr %hp663, i64 24
  store i64 %ld667, ptr %fp668, align 8
  %$t1023_2.addr = alloca ptr
  store ptr %hp663, ptr %$t1023_2.addr
  %hp669 = call ptr @march_alloc(i64 32)
  %tgp670 = getelementptr i8, ptr %hp669, i64 8
  store i32 1, ptr %tgp670, align 4
  %ld671 = load ptr, ptr %$t1023_2.addr
  %fp672 = getelementptr i8, ptr %hp669, i64 16
  store ptr %ld671, ptr %fp672, align 8
  %ld673 = load ptr, ptr %rest_2.addr
  %fp674 = getelementptr i8, ptr %hp669, i64 24
  store ptr %ld673, ptr %fp674, align 8
  %$t1024_2.addr = alloca ptr
  store ptr %hp669, ptr %$t1024_2.addr
  %hp675 = call ptr @march_alloc(i64 32)
  %tgp676 = getelementptr i8, ptr %hp675, i64 8
  store i32 1, ptr %tgp676, align 4
  %ld677 = load ptr, ptr %$t1022_2.addr
  %fp678 = getelementptr i8, ptr %hp675, i64 16
  store ptr %ld677, ptr %fp678, align 8
  %ld679 = load ptr, ptr %$t1024_2.addr
  %fp680 = getelementptr i8, ptr %hp675, i64 24
  store ptr %ld679, ptr %fp680, align 8
  %$t1025_2.addr = alloca ptr
  store ptr %hp675, ptr %$t1025_2.addr
  %ld681 = load ptr, ptr %$t1025_2.addr
  %cr682 = call ptr @enforce(ptr %ld681)
  store ptr %cr682, ptr %res_slot650
  br label %case_merge115
case_default116:
  %ld683 = load i64, ptr %yn_3.addr
  %ld684 = load i64, ptr %xn_3.addr
  %ar685 = add i64 %ld683, %ld684
  %$t1026_2.addr = alloca i64
  store i64 %ar685, ptr %$t1026_2.addr
  %ld686 = load i64, ptr %zn_2.addr
  %ld687 = load i64, ptr %$t1026_2.addr
  %cmp688 = icmp sle i64 %ld686, %ld687
  %ar689 = zext i1 %cmp688 to i64
  %$t1027_2.addr = alloca i64
  store i64 %ar689, ptr %$t1027_2.addr
  %ld690 = load i64, ptr %$t1027_2.addr
  %res_slot691 = alloca ptr
  switch i64 %ld690, label %case_default119 [
      i64 1, label %case_br120
  ]
case_br120:
  %ld692 = load ptr, ptr %z_2.addr
  %ld693 = load ptr, ptr %y_3.addr
  %cr694 = call ptr @merge_ms(ptr %ld692, ptr %ld693)
  %m_6.addr = alloca ptr
  store ptr %cr694, ptr %m_6.addr
  %hp695 = call ptr @march_alloc(i64 32)
  %tgp696 = getelementptr i8, ptr %hp695, i64 8
  store i32 0, ptr %tgp696, align 4
  %ld697 = load ptr, ptr %x_3.addr
  %fp698 = getelementptr i8, ptr %hp695, i64 16
  store ptr %ld697, ptr %fp698, align 8
  %ld699 = load i64, ptr %xn_3.addr
  %fp700 = getelementptr i8, ptr %hp695, i64 24
  store i64 %ld699, ptr %fp700, align 8
  %$t1028_2.addr = alloca ptr
  store ptr %hp695, ptr %$t1028_2.addr
  %ld701 = load i64, ptr %yn_3.addr
  %ld702 = load i64, ptr %zn_2.addr
  %ar703 = add i64 %ld701, %ld702
  %$t1029_2.addr = alloca i64
  store i64 %ar703, ptr %$t1029_2.addr
  %hp704 = call ptr @march_alloc(i64 32)
  %tgp705 = getelementptr i8, ptr %hp704, i64 8
  store i32 0, ptr %tgp705, align 4
  %ld706 = load ptr, ptr %m_6.addr
  %fp707 = getelementptr i8, ptr %hp704, i64 16
  store ptr %ld706, ptr %fp707, align 8
  %ld708 = load i64, ptr %$t1029_2.addr
  %fp709 = getelementptr i8, ptr %hp704, i64 24
  store i64 %ld708, ptr %fp709, align 8
  %$t1030_2.addr = alloca ptr
  store ptr %hp704, ptr %$t1030_2.addr
  %hp710 = call ptr @march_alloc(i64 32)
  %tgp711 = getelementptr i8, ptr %hp710, i64 8
  store i32 1, ptr %tgp711, align 4
  %ld712 = load ptr, ptr %$t1030_2.addr
  %fp713 = getelementptr i8, ptr %hp710, i64 16
  store ptr %ld712, ptr %fp713, align 8
  %ld714 = load ptr, ptr %rest_2.addr
  %fp715 = getelementptr i8, ptr %hp710, i64 24
  store ptr %ld714, ptr %fp715, align 8
  %$t1031_2.addr = alloca ptr
  store ptr %hp710, ptr %$t1031_2.addr
  %hp716 = call ptr @march_alloc(i64 32)
  %tgp717 = getelementptr i8, ptr %hp716, i64 8
  store i32 1, ptr %tgp717, align 4
  %ld718 = load ptr, ptr %$t1028_2.addr
  %fp719 = getelementptr i8, ptr %hp716, i64 16
  store ptr %ld718, ptr %fp719, align 8
  %ld720 = load ptr, ptr %$t1031_2.addr
  %fp721 = getelementptr i8, ptr %hp716, i64 24
  store ptr %ld720, ptr %fp721, align 8
  %$t1032_2.addr = alloca ptr
  store ptr %hp716, ptr %$t1032_2.addr
  %ld722 = load ptr, ptr %$t1032_2.addr
  %cr723 = call ptr @enforce(ptr %ld722)
  store ptr %cr723, ptr %res_slot691
  br label %case_merge118
case_default119:
  %ld724 = load ptr, ptr %stack.addr
  store ptr %ld724, ptr %res_slot691
  br label %case_merge118
case_merge118:
  %case_r725 = load ptr, ptr %res_slot691
  store ptr %case_r725, ptr %res_slot650
  br label %case_merge115
case_merge115:
  %case_r726 = load ptr, ptr %res_slot650
  store ptr %case_r726, ptr %res_slot631
  br label %case_merge112
case_default113:
  %cv727 = inttoptr i64 0 to ptr
  store ptr %cv727, ptr %res_slot631
  br label %case_merge112
case_merge112:
  %case_r728 = load ptr, ptr %res_slot631
  store ptr %case_r728, ptr %res_slot623
  br label %case_merge109
case_default110:
  %cv729 = inttoptr i64 0 to ptr
  store ptr %cv729, ptr %res_slot623
  br label %case_merge109
case_merge109:
  %case_r730 = load ptr, ptr %res_slot623
  store ptr %case_r730, ptr %res_slot615
  br label %case_merge106
case_default107:
  %cv731 = inttoptr i64 0 to ptr
  store ptr %cv731, ptr %res_slot615
  br label %case_merge106
case_merge106:
  %case_r732 = load ptr, ptr %res_slot615
  store ptr %case_r732, ptr %res_slot607
  br label %case_merge103
case_default104:
  %cv733 = inttoptr i64 0 to ptr
  store ptr %cv733, ptr %res_slot607
  br label %case_merge103
case_merge103:
  %case_r734 = load ptr, ptr %res_slot607
  store ptr %case_r734, ptr %res_slot295
  br label %case_merge55
case_merge55:
  %case_r735 = load ptr, ptr %res_slot295
  store ptr %case_r735, ptr %res_slot287
  br label %case_merge52
case_default53:
  unreachable
case_merge52:
  %case_r736 = load ptr, ptr %res_slot287
  store ptr %case_r736, ptr %res_slot282
  br label %case_merge49
case_merge49:
  %case_r737 = load ptr, ptr %res_slot282
  store ptr %case_r737, ptr %res_slot266
  br label %case_merge42
case_default43:
  unreachable
case_merge42:
  %case_r738 = load ptr, ptr %res_slot266
  ret ptr %case_r738
}

define ptr @collapse(ptr %stack.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld739 = load ptr, ptr %stack.addr
  %res_slot740 = alloca ptr
  %tgp741 = getelementptr i8, ptr %ld739, i64 8
  %tag742 = load i32, ptr %tgp741, align 4
  switch i32 %tag742, label %case_default122 [
      i32 0, label %case_br123
      i32 1, label %case_br124
  ]
case_br123:
  %ld743 = load ptr, ptr %stack.addr
  %rc744 = load i64, ptr %ld743, align 8
  %uniq745 = icmp eq i64 %rc744, 1
  %fbip_slot746 = alloca ptr
  br i1 %uniq745, label %fbip_reuse125, label %fbip_fresh126
fbip_reuse125:
  %tgp747 = getelementptr i8, ptr %ld743, i64 8
  store i32 0, ptr %tgp747, align 4
  store ptr %ld743, ptr %fbip_slot746
  br label %fbip_merge127
fbip_fresh126:
  call void @march_decrc(ptr %ld743)
  %hp748 = call ptr @march_alloc(i64 16)
  %tgp749 = getelementptr i8, ptr %hp748, i64 8
  store i32 0, ptr %tgp749, align 4
  store ptr %hp748, ptr %fbip_slot746
  br label %fbip_merge127
fbip_merge127:
  %fbip_r750 = load ptr, ptr %fbip_slot746
  store ptr %fbip_r750, ptr %res_slot740
  br label %case_merge121
case_br124:
  %fp751 = getelementptr i8, ptr %ld739, i64 16
  %fv752 = load ptr, ptr %fp751, align 8
  %$f1052.addr = alloca ptr
  store ptr %fv752, ptr %$f1052.addr
  %fp753 = getelementptr i8, ptr %ld739, i64 24
  %fv754 = load ptr, ptr %fp753, align 8
  %$f1053.addr = alloca ptr
  store ptr %fv754, ptr %$f1053.addr
  %freed755 = call i64 @march_decrc_freed(ptr %ld739)
  %freed_b756 = icmp ne i64 %freed755, 0
  br i1 %freed_b756, label %br_unique128, label %br_shared129
br_shared129:
  call void @march_incrc(ptr %fv754)
  call void @march_incrc(ptr %fv752)
  br label %br_body130
br_unique128:
  br label %br_body130
br_body130:
  %ld757 = load ptr, ptr %$f1052.addr
  %res_slot758 = alloca ptr
  %tgp759 = getelementptr i8, ptr %ld757, i64 8
  %tag760 = load i32, ptr %tgp759, align 4
  switch i32 %tag760, label %case_default132 [
      i32 0, label %case_br133
  ]
case_br133:
  %fp761 = getelementptr i8, ptr %ld757, i64 16
  %fv762 = load ptr, ptr %fp761, align 8
  %$f1054.addr = alloca ptr
  store ptr %fv762, ptr %$f1054.addr
  %fp763 = getelementptr i8, ptr %ld757, i64 24
  %fv764 = load ptr, ptr %fp763, align 8
  %$f1055.addr = alloca ptr
  store ptr %fv764, ptr %$f1055.addr
  %ld765 = load ptr, ptr %$f1053.addr
  %res_slot766 = alloca ptr
  %tgp767 = getelementptr i8, ptr %ld765, i64 8
  %tag768 = load i32, ptr %tgp767, align 4
  switch i32 %tag768, label %case_default135 [
      i32 0, label %case_br136
  ]
case_br136:
  %ld769 = load ptr, ptr %$f1054.addr
  %x.addr = alloca ptr
  store ptr %ld769, ptr %x.addr
  %ld770 = load ptr, ptr %x.addr
  store ptr %ld770, ptr %res_slot766
  br label %case_merge134
case_default135:
  %ld771 = load ptr, ptr %$f1053.addr
  %res_slot772 = alloca ptr
  %tgp773 = getelementptr i8, ptr %ld771, i64 8
  %tag774 = load i32, ptr %tgp773, align 4
  switch i32 %tag774, label %case_default138 [
      i32 1, label %case_br139
  ]
case_br139:
  %fp775 = getelementptr i8, ptr %ld771, i64 16
  %fv776 = load ptr, ptr %fp775, align 8
  %$f1056.addr = alloca ptr
  store ptr %fv776, ptr %$f1056.addr
  %fp777 = getelementptr i8, ptr %ld771, i64 24
  %fv778 = load ptr, ptr %fp777, align 8
  %$f1057.addr = alloca ptr
  store ptr %fv778, ptr %$f1057.addr
  %ld779 = load ptr, ptr %$f1056.addr
  %res_slot780 = alloca ptr
  %tgp781 = getelementptr i8, ptr %ld779, i64 8
  %tag782 = load i32, ptr %tgp781, align 4
  switch i32 %tag782, label %case_default141 [
      i32 0, label %case_br142
  ]
case_br142:
  %fp783 = getelementptr i8, ptr %ld779, i64 16
  %fv784 = load ptr, ptr %fp783, align 8
  %$f1058.addr = alloca ptr
  store ptr %fv784, ptr %$f1058.addr
  %fp785 = getelementptr i8, ptr %ld779, i64 24
  %fv786 = load ptr, ptr %fp785, align 8
  %$f1059.addr = alloca ptr
  store ptr %fv786, ptr %$f1059.addr
  %ld787 = load ptr, ptr %$f1057.addr
  %rest.addr = alloca ptr
  store ptr %ld787, ptr %rest.addr
  %ld788 = load ptr, ptr %$f1059.addr
  %yn.addr = alloca ptr
  store ptr %ld788, ptr %yn.addr
  %ld789 = load ptr, ptr %$f1058.addr
  %y.addr = alloca ptr
  store ptr %ld789, ptr %y.addr
  %ld790 = load ptr, ptr %$f1055.addr
  %xn.addr = alloca ptr
  store ptr %ld790, ptr %xn.addr
  %ld791 = load ptr, ptr %$f1054.addr
  %x_1.addr = alloca ptr
  store ptr %ld791, ptr %x_1.addr
  %ld792 = load ptr, ptr %y.addr
  %ld793 = load ptr, ptr %x_1.addr
  %cr794 = call ptr @merge_ms(ptr %ld792, ptr %ld793)
  %m.addr = alloca ptr
  store ptr %cr794, ptr %m.addr
  %ld795 = load i64, ptr %xn.addr
  %ld796 = load i64, ptr %yn.addr
  %ar797 = add i64 %ld795, %ld796
  %$t1049.addr = alloca i64
  store i64 %ar797, ptr %$t1049.addr
  %hp798 = call ptr @march_alloc(i64 32)
  %tgp799 = getelementptr i8, ptr %hp798, i64 8
  store i32 0, ptr %tgp799, align 4
  %ld800 = load ptr, ptr %m.addr
  %fp801 = getelementptr i8, ptr %hp798, i64 16
  store ptr %ld800, ptr %fp801, align 8
  %ld802 = load i64, ptr %$t1049.addr
  %fp803 = getelementptr i8, ptr %hp798, i64 24
  store i64 %ld802, ptr %fp803, align 8
  %$t1050.addr = alloca ptr
  store ptr %hp798, ptr %$t1050.addr
  %hp804 = call ptr @march_alloc(i64 32)
  %tgp805 = getelementptr i8, ptr %hp804, i64 8
  store i32 1, ptr %tgp805, align 4
  %ld806 = load ptr, ptr %$t1050.addr
  %fp807 = getelementptr i8, ptr %hp804, i64 16
  store ptr %ld806, ptr %fp807, align 8
  %ld808 = load ptr, ptr %rest.addr
  %fp809 = getelementptr i8, ptr %hp804, i64 24
  store ptr %ld808, ptr %fp809, align 8
  %$t1051.addr = alloca ptr
  store ptr %hp804, ptr %$t1051.addr
  %ld810 = load ptr, ptr %$t1051.addr
  %cr811 = call ptr @collapse(ptr %ld810)
  store ptr %cr811, ptr %res_slot780
  br label %case_merge140
case_default141:
  %cv812 = inttoptr i64 0 to ptr
  store ptr %cv812, ptr %res_slot780
  br label %case_merge140
case_merge140:
  %case_r813 = load ptr, ptr %res_slot780
  store ptr %case_r813, ptr %res_slot772
  br label %case_merge137
case_default138:
  %cv814 = inttoptr i64 0 to ptr
  store ptr %cv814, ptr %res_slot772
  br label %case_merge137
case_merge137:
  %case_r815 = load ptr, ptr %res_slot772
  store ptr %case_r815, ptr %res_slot766
  br label %case_merge134
case_merge134:
  %case_r816 = load ptr, ptr %res_slot766
  store ptr %case_r816, ptr %res_slot758
  br label %case_merge131
case_default132:
  unreachable
case_merge131:
  %case_r817 = load ptr, ptr %res_slot758
  store ptr %case_r817, ptr %res_slot740
  br label %case_merge121
case_default122:
  unreachable
case_merge121:
  %case_r818 = load ptr, ptr %res_slot740
  ret ptr %case_r818
}

define ptr @timsort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp819 = call ptr @march_alloc(i64 24)
  %tgp820 = getelementptr i8, ptr %hp819, i64 8
  store i32 0, ptr %tgp820, align 4
  %fp821 = getelementptr i8, ptr %hp819, i64 16
  store ptr @run_pass$apply$21, ptr %fp821, align 8
  %run_pass.addr = alloca ptr
  store ptr %hp819, ptr %run_pass.addr
  %hp822 = call ptr @march_alloc(i64 16)
  %tgp823 = getelementptr i8, ptr %hp822, i64 8
  store i32 0, ptr %tgp823, align 4
  %$t1064.addr = alloca ptr
  store ptr %hp822, ptr %$t1064.addr
  %ld824 = load ptr, ptr %run_pass.addr
  %fp825 = getelementptr i8, ptr %ld824, i64 16
  %fv826 = load ptr, ptr %fp825, align 8
  %ld827 = load ptr, ptr %xs.addr
  %ld828 = load ptr, ptr %$t1064.addr
  %cr829 = call ptr (ptr, ptr, ptr) %fv826(ptr %ld824, ptr %ld827, ptr %ld828)
  ret ptr %cr829
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld830 = load ptr, ptr %xs.addr
  %res_slot831 = alloca ptr
  %tgp832 = getelementptr i8, ptr %ld830, i64 8
  %tag833 = load i32, ptr %tgp832, align 4
  switch i32 %tag833, label %case_default144 [
      i32 0, label %case_br145
      i32 1, label %case_br146
  ]
case_br145:
  %ld834 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld834)
  %cv835 = inttoptr i64 0 to ptr
  store ptr %cv835, ptr %res_slot831
  br label %case_merge143
case_br146:
  %fp836 = getelementptr i8, ptr %ld830, i64 16
  %fv837 = load ptr, ptr %fp836, align 8
  %$f1065.addr = alloca ptr
  store ptr %fv837, ptr %$f1065.addr
  %fp838 = getelementptr i8, ptr %ld830, i64 24
  %fv839 = load ptr, ptr %fp838, align 8
  %$f1066.addr = alloca ptr
  store ptr %fv839, ptr %$f1066.addr
  %freed840 = call i64 @march_decrc_freed(ptr %ld830)
  %freed_b841 = icmp ne i64 %freed840, 0
  br i1 %freed_b841, label %br_unique147, label %br_shared148
br_shared148:
  call void @march_incrc(ptr %fv839)
  br label %br_body149
br_unique147:
  br label %br_body149
br_body149:
  %ld842 = load ptr, ptr %$f1065.addr
  %h.addr = alloca ptr
  store ptr %ld842, ptr %h.addr
  %ld843 = load i64, ptr %h.addr
  %cv844 = inttoptr i64 %ld843 to ptr
  store ptr %cv844, ptr %res_slot831
  br label %case_merge143
case_default144:
  unreachable
case_merge143:
  %case_r845 = load ptr, ptr %res_slot831
  %cv846 = ptrtoint ptr %case_r845 to i64
  ret i64 %cv846
}

define void @march_main() {
entry:
  %hp847 = call ptr @march_alloc(i64 16)
  %tgp848 = getelementptr i8, ptr %hp847, i64 8
  store i32 0, ptr %tgp848, align 4
  %$t1067.addr = alloca ptr
  store ptr %hp847, ptr %$t1067.addr
  %ld849 = load ptr, ptr %$t1067.addr
  %cr850 = call ptr @build_pairs(i64 4999, ptr %ld849)
  %$t1068.addr = alloca ptr
  store ptr %cr850, ptr %$t1068.addr
  %ld851 = load ptr, ptr %$t1068.addr
  %cr852 = call ptr @timsort(ptr %ld851)
  %ts.addr = alloca ptr
  store ptr %cr852, ptr %ts.addr
  %hp853 = call ptr @march_alloc(i64 16)
  %tgp854 = getelementptr i8, ptr %hp853, i64 8
  store i32 0, ptr %tgp854, align 4
  %$t1069.addr = alloca ptr
  store ptr %hp853, ptr %$t1069.addr
  %ld855 = load ptr, ptr %$t1069.addr
  %cr856 = call ptr @build_pairs(i64 4999, ptr %ld855)
  %$t1070.addr = alloca ptr
  store ptr %cr856, ptr %$t1070.addr
  %ld857 = load ptr, ptr %$t1070.addr
  %cr858 = call ptr @mergesort(ptr %ld857)
  %ms.addr = alloca ptr
  store ptr %cr858, ptr %ms.addr
  %ld859 = load ptr, ptr %ts.addr
  %cr860 = call i64 @head(ptr %ld859)
  %$t1071.addr = alloca i64
  store i64 %cr860, ptr %$t1071.addr
  %ld861 = load i64, ptr %$t1071.addr
  %cr862 = call ptr @march_int_to_string(i64 %ld861)
  %$t1072.addr = alloca ptr
  store ptr %cr862, ptr %$t1072.addr
  %ld863 = load ptr, ptr %$t1072.addr
  call void @march_println(ptr %ld863)
  %ld864 = load ptr, ptr %ms.addr
  %cr865 = call i64 @head(ptr %ld864)
  %$t1073.addr = alloca i64
  store i64 %cr865, ptr %$t1073.addr
  %ld866 = load i64, ptr %$t1073.addr
  %cr867 = call ptr @march_int_to_string(i64 %ld866)
  %$t1074.addr = alloca ptr
  store ptr %cr867, ptr %$t1074.addr
  %ld868 = load ptr, ptr %$t1074.addr
  call void @march_println(ptr %ld868)
  ret void
}

define ptr @go$apply$18(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld869 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld869, ptr %go.addr
  %ld870 = load ptr, ptr %lst.addr
  %res_slot871 = alloca ptr
  %tgp872 = getelementptr i8, ptr %ld870, i64 8
  %tag873 = load i32, ptr %tgp872, align 4
  switch i32 %tag873, label %case_default151 [
      i32 0, label %case_br152
      i32 1, label %case_br153
  ]
case_br152:
  %ld874 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld874)
  %ld875 = load ptr, ptr %acc.addr
  store ptr %ld875, ptr %res_slot871
  br label %case_merge150
case_br153:
  %fp876 = getelementptr i8, ptr %ld870, i64 16
  %fv877 = load ptr, ptr %fp876, align 8
  %$f971.addr = alloca ptr
  store ptr %fv877, ptr %$f971.addr
  %fp878 = getelementptr i8, ptr %ld870, i64 24
  %fv879 = load ptr, ptr %fp878, align 8
  %$f972.addr = alloca ptr
  store ptr %fv879, ptr %$f972.addr
  %ld880 = load ptr, ptr %$f972.addr
  %t.addr = alloca ptr
  store ptr %ld880, ptr %t.addr
  %ld881 = load ptr, ptr %$f971.addr
  %h.addr = alloca ptr
  store ptr %ld881, ptr %h.addr
  %ld882 = load ptr, ptr %lst.addr
  %ld883 = load i64, ptr %h.addr
  %cv884 = inttoptr i64 %ld883 to ptr
  %ld885 = load ptr, ptr %acc.addr
  %rc886 = load i64, ptr %ld882, align 8
  %uniq887 = icmp eq i64 %rc886, 1
  %fbip_slot888 = alloca ptr
  br i1 %uniq887, label %fbip_reuse154, label %fbip_fresh155
fbip_reuse154:
  %tgp889 = getelementptr i8, ptr %ld882, i64 8
  store i32 1, ptr %tgp889, align 4
  %fp890 = getelementptr i8, ptr %ld882, i64 16
  store ptr %cv884, ptr %fp890, align 8
  %fp891 = getelementptr i8, ptr %ld882, i64 24
  store ptr %ld885, ptr %fp891, align 8
  store ptr %ld882, ptr %fbip_slot888
  br label %fbip_merge156
fbip_fresh155:
  call void @march_decrc(ptr %ld882)
  %hp892 = call ptr @march_alloc(i64 32)
  %tgp893 = getelementptr i8, ptr %hp892, i64 8
  store i32 1, ptr %tgp893, align 4
  %fp894 = getelementptr i8, ptr %hp892, i64 16
  store ptr %cv884, ptr %fp894, align 8
  %fp895 = getelementptr i8, ptr %hp892, i64 24
  store ptr %ld885, ptr %fp895, align 8
  store ptr %hp892, ptr %fbip_slot888
  br label %fbip_merge156
fbip_merge156:
  %fbip_r896 = load ptr, ptr %fbip_slot888
  %$t970.addr = alloca ptr
  store ptr %fbip_r896, ptr %$t970.addr
  %ld897 = load ptr, ptr %go.addr
  %fp898 = getelementptr i8, ptr %ld897, i64 16
  %fv899 = load ptr, ptr %fp898, align 8
  %ld900 = load ptr, ptr %t.addr
  %ld901 = load ptr, ptr %$t970.addr
  %cr902 = call ptr (ptr, ptr, ptr) %fv899(ptr %ld897, ptr %ld900, ptr %ld901)
  store ptr %cr902, ptr %res_slot871
  br label %case_merge150
case_default151:
  unreachable
case_merge150:
  %case_r903 = load ptr, ptr %res_slot871
  ret ptr %case_r903
}

define i64 @go$apply$19(ptr %$clo.arg, ptr %lst.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld904 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld904, ptr %go.addr
  %ld905 = load ptr, ptr %lst.addr
  %res_slot906 = alloca ptr
  %tgp907 = getelementptr i8, ptr %ld905, i64 8
  %tag908 = load i32, ptr %tgp907, align 4
  switch i32 %tag908, label %case_default158 [
      i32 0, label %case_br159
      i32 1, label %case_br160
  ]
case_br159:
  %ld909 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld909)
  %ld910 = load i64, ptr %acc.addr
  %cv911 = inttoptr i64 %ld910 to ptr
  store ptr %cv911, ptr %res_slot906
  br label %case_merge157
case_br160:
  %fp912 = getelementptr i8, ptr %ld905, i64 16
  %fv913 = load ptr, ptr %fp912, align 8
  %$f995.addr = alloca ptr
  store ptr %fv913, ptr %$f995.addr
  %fp914 = getelementptr i8, ptr %ld905, i64 24
  %fv915 = load ptr, ptr %fp914, align 8
  %$f996.addr = alloca ptr
  store ptr %fv915, ptr %$f996.addr
  %freed916 = call i64 @march_decrc_freed(ptr %ld905)
  %freed_b917 = icmp ne i64 %freed916, 0
  br i1 %freed_b917, label %br_unique161, label %br_shared162
br_shared162:
  call void @march_incrc(ptr %fv915)
  br label %br_body163
br_unique161:
  br label %br_body163
br_body163:
  %ld918 = load ptr, ptr %$f996.addr
  %t.addr = alloca ptr
  store ptr %ld918, ptr %t.addr
  %ld919 = load i64, ptr %acc.addr
  %ar920 = add i64 %ld919, 1
  %$t994.addr = alloca i64
  store i64 %ar920, ptr %$t994.addr
  %ld921 = load ptr, ptr %go.addr
  %fp922 = getelementptr i8, ptr %ld921, i64 16
  %fv923 = load ptr, ptr %fp922, align 8
  %ld924 = load ptr, ptr %t.addr
  %ld925 = load i64, ptr %$t994.addr
  %cr926 = call i64 (ptr, ptr, i64) %fv923(ptr %ld921, ptr %ld924, i64 %ld925)
  %cv927 = inttoptr i64 %cr926 to ptr
  store ptr %cv927, ptr %res_slot906
  br label %case_merge157
case_default158:
  unreachable
case_merge157:
  %case_r928 = load ptr, ptr %res_slot906
  %cv929 = ptrtoint ptr %case_r928 to i64
  ret i64 %cv929
}

define ptr @go$apply$20(ptr %$clo.arg, ptr %lst.arg, i64 %n.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld930 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld930, ptr %go.addr
  %ld931 = load i64, ptr %n.addr
  %cmp932 = icmp sle i64 %ld931, 1
  %ar933 = zext i1 %cmp932 to i64
  %$t997.addr = alloca i64
  store i64 %ar933, ptr %$t997.addr
  %ld934 = load i64, ptr %$t997.addr
  %res_slot935 = alloca ptr
  switch i64 %ld934, label %case_default165 [
      i64 1, label %case_br166
  ]
case_br166:
  %ld936 = load ptr, ptr %lst.addr
  store ptr %ld936, ptr %res_slot935
  br label %case_merge164
case_default165:
  %ld937 = load i64, ptr %n.addr
  %ar938 = sdiv i64 %ld937, 2
  %half.addr = alloca i64
  store i64 %ar938, ptr %half.addr
  %hp939 = call ptr @march_alloc(i64 16)
  %tgp940 = getelementptr i8, ptr %hp939, i64 8
  store i32 0, ptr %tgp940, align 4
  %$t998.addr = alloca ptr
  store ptr %hp939, ptr %$t998.addr
  %ld941 = load ptr, ptr %lst.addr
  %ld942 = load i64, ptr %half.addr
  %ld943 = load ptr, ptr %$t998.addr
  %cr944 = call ptr @take_k(ptr %ld941, i64 %ld942, ptr %ld943)
  %$p1002.addr = alloca ptr
  store ptr %cr944, ptr %$p1002.addr
  %ld945 = load ptr, ptr %$p1002.addr
  %fp946 = getelementptr i8, ptr %ld945, i64 16
  %fv947 = load ptr, ptr %fp946, align 8
  %l.addr = alloca ptr
  store ptr %fv947, ptr %l.addr
  %ld948 = load ptr, ptr %$p1002.addr
  %fp949 = getelementptr i8, ptr %ld948, i64 24
  %fv950 = load ptr, ptr %fp949, align 8
  %r.addr = alloca ptr
  store ptr %fv950, ptr %r.addr
  %ld951 = load ptr, ptr %go.addr
  %fp952 = getelementptr i8, ptr %ld951, i64 16
  %fv953 = load ptr, ptr %fp952, align 8
  %ld954 = load ptr, ptr %l.addr
  %ld955 = load i64, ptr %half.addr
  %cr956 = call ptr (ptr, ptr, i64) %fv953(ptr %ld951, ptr %ld954, i64 %ld955)
  %$t999.addr = alloca ptr
  store ptr %cr956, ptr %$t999.addr
  %ld957 = load i64, ptr %n.addr
  %ld958 = load i64, ptr %half.addr
  %ar959 = sub i64 %ld957, %ld958
  %$t1000.addr = alloca i64
  store i64 %ar959, ptr %$t1000.addr
  %ld960 = load ptr, ptr %go.addr
  %fp961 = getelementptr i8, ptr %ld960, i64 16
  %fv962 = load ptr, ptr %fp961, align 8
  %ld963 = load ptr, ptr %r.addr
  %ld964 = load i64, ptr %$t1000.addr
  %cr965 = call ptr (ptr, ptr, i64) %fv962(ptr %ld960, ptr %ld963, i64 %ld964)
  %$t1001.addr = alloca ptr
  store ptr %cr965, ptr %$t1001.addr
  %ld966 = load ptr, ptr %$t999.addr
  %ld967 = load ptr, ptr %$t1001.addr
  %cr968 = call ptr @merge_ms(ptr %ld966, ptr %ld967)
  store ptr %cr968, ptr %res_slot935
  br label %case_merge164
case_merge164:
  %case_r969 = load ptr, ptr %res_slot935
  ret ptr %case_r969
}

define ptr @run_pass$apply$21(ptr %$clo.arg, ptr %lst.arg, ptr %stack.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld970 = load ptr, ptr %$clo.addr
  %run_pass.addr = alloca ptr
  store ptr %ld970, ptr %run_pass.addr
  %ld971 = load ptr, ptr %lst.addr
  %res_slot972 = alloca ptr
  %tgp973 = getelementptr i8, ptr %ld971, i64 8
  %tag974 = load i32, ptr %tgp973, align 4
  switch i32 %tag974, label %case_default168 [
      i32 0, label %case_br169
  ]
case_br169:
  %ld975 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld975)
  %ld976 = load ptr, ptr %stack.addr
  %cr977 = call ptr @collapse(ptr %ld976)
  store ptr %cr977, ptr %res_slot972
  br label %case_merge167
case_default168:
  %hp978 = call ptr @march_alloc(i64 16)
  %tgp979 = getelementptr i8, ptr %hp978, i64 8
  store i32 0, ptr %tgp979, align 4
  %$t1060.addr = alloca ptr
  store ptr %hp978, ptr %$t1060.addr
  %ld980 = load ptr, ptr %lst.addr
  %ld981 = load ptr, ptr %$t1060.addr
  %cr982 = call ptr @scan_asc(ptr %ld980, ptr %ld981, i64 0)
  %$p1063.addr = alloca ptr
  store ptr %cr982, ptr %$p1063.addr
  %ld983 = load ptr, ptr %$p1063.addr
  %fp984 = getelementptr i8, ptr %ld983, i64 16
  %fv985 = load ptr, ptr %fp984, align 8
  %run.addr = alloca ptr
  store ptr %fv985, ptr %run.addr
  %ld986 = load ptr, ptr %$p1063.addr
  %fp987 = getelementptr i8, ptr %ld986, i64 24
  %fv988 = load ptr, ptr %fp987, align 8
  %rlen.addr = alloca ptr
  store ptr %fv988, ptr %rlen.addr
  %ld989 = load ptr, ptr %$p1063.addr
  %fp990 = getelementptr i8, ptr %ld989, i64 32
  %fv991 = load ptr, ptr %fp990, align 8
  %rest.addr = alloca ptr
  store ptr %fv991, ptr %rest.addr
  %hp992 = call ptr @march_alloc(i64 32)
  %tgp993 = getelementptr i8, ptr %hp992, i64 8
  store i32 0, ptr %tgp993, align 4
  %ld994 = load ptr, ptr %run.addr
  %fp995 = getelementptr i8, ptr %hp992, i64 16
  store ptr %ld994, ptr %fp995, align 8
  %ld996 = load i64, ptr %rlen.addr
  %fp997 = getelementptr i8, ptr %hp992, i64 24
  store i64 %ld996, ptr %fp997, align 8
  %$t1061.addr = alloca ptr
  store ptr %hp992, ptr %$t1061.addr
  %hp998 = call ptr @march_alloc(i64 32)
  %tgp999 = getelementptr i8, ptr %hp998, i64 8
  store i32 1, ptr %tgp999, align 4
  %ld1000 = load ptr, ptr %$t1061.addr
  %fp1001 = getelementptr i8, ptr %hp998, i64 16
  store ptr %ld1000, ptr %fp1001, align 8
  %ld1002 = load ptr, ptr %stack.addr
  %fp1003 = getelementptr i8, ptr %hp998, i64 24
  store ptr %ld1002, ptr %fp1003, align 8
  %$t1062.addr = alloca ptr
  store ptr %hp998, ptr %$t1062.addr
  %ld1004 = load ptr, ptr %$t1062.addr
  %cr1005 = call ptr @enforce(ptr %ld1004)
  %new_stack.addr = alloca ptr
  store ptr %cr1005, ptr %new_stack.addr
  %ld1006 = load ptr, ptr %run_pass.addr
  %fp1007 = getelementptr i8, ptr %ld1006, i64 16
  %fv1008 = load ptr, ptr %fp1007, align 8
  %ld1009 = load ptr, ptr %rest.addr
  %ld1010 = load ptr, ptr %new_stack.addr
  %cr1011 = call ptr (ptr, ptr, ptr) %fv1008(ptr %ld1006, ptr %ld1009, ptr %ld1010)
  store ptr %cr1011, ptr %res_slot972
  br label %case_merge167
case_merge167:
  %case_r1012 = load ptr, ptr %res_slot972
  ret ptr %case_r1012
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
