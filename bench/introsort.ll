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

define ptr @append(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld12 = load ptr, ptr %xs.addr
  %res_slot13 = alloca ptr
  %tgp14 = getelementptr i8, ptr %ld12, i64 8
  %tag15 = load i32, ptr %tgp14, align 4
  switch i32 %tag15, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld16 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld16)
  %ld17 = load ptr, ptr %ys.addr
  store ptr %ld17, ptr %res_slot13
  br label %case_merge1
case_br4:
  %fp18 = getelementptr i8, ptr %ld12, i64 16
  %fv19 = load ptr, ptr %fp18, align 8
  %$f975.addr = alloca ptr
  store ptr %fv19, ptr %$f975.addr
  %fp20 = getelementptr i8, ptr %ld12, i64 24
  %fv21 = load ptr, ptr %fp20, align 8
  %$f976.addr = alloca ptr
  store ptr %fv21, ptr %$f976.addr
  %ld22 = load ptr, ptr %$f976.addr
  %t.addr = alloca ptr
  store ptr %ld22, ptr %t.addr
  %ld23 = load ptr, ptr %$f975.addr
  %h.addr = alloca ptr
  store ptr %ld23, ptr %h.addr
  %ld24 = load ptr, ptr %t.addr
  %ld25 = load ptr, ptr %ys.addr
  %cr26 = call ptr @append(ptr %ld24, ptr %ld25)
  %$t974.addr = alloca ptr
  store ptr %cr26, ptr %$t974.addr
  %ld27 = load ptr, ptr %xs.addr
  %ld28 = load i64, ptr %h.addr
  %cv29 = inttoptr i64 %ld28 to ptr
  %ld30 = load ptr, ptr %$t974.addr
  %rc31 = load i64, ptr %ld27, align 8
  %uniq32 = icmp eq i64 %rc31, 1
  %fbip_slot33 = alloca ptr
  br i1 %uniq32, label %fbip_reuse5, label %fbip_fresh6
fbip_reuse5:
  %tgp34 = getelementptr i8, ptr %ld27, i64 8
  store i32 1, ptr %tgp34, align 4
  %fp35 = getelementptr i8, ptr %ld27, i64 16
  store ptr %cv29, ptr %fp35, align 8
  %fp36 = getelementptr i8, ptr %ld27, i64 24
  store ptr %ld30, ptr %fp36, align 8
  store ptr %ld27, ptr %fbip_slot33
  br label %fbip_merge7
fbip_fresh6:
  call void @march_decrc(ptr %ld27)
  %hp37 = call ptr @march_alloc(i64 32)
  %tgp38 = getelementptr i8, ptr %hp37, i64 8
  store i32 1, ptr %tgp38, align 4
  %fp39 = getelementptr i8, ptr %hp37, i64 16
  store ptr %cv29, ptr %fp39, align 8
  %fp40 = getelementptr i8, ptr %hp37, i64 24
  store ptr %ld30, ptr %fp40, align 8
  store ptr %hp37, ptr %fbip_slot33
  br label %fbip_merge7
fbip_merge7:
  %fbip_r41 = load ptr, ptr %fbip_slot33
  store ptr %fbip_r41, ptr %res_slot13
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r42 = load ptr, ptr %res_slot13
  ret ptr %case_r42
}

define i64 @list_len(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp43 = call ptr @march_alloc(i64 24)
  %tgp44 = getelementptr i8, ptr %hp43, i64 8
  store i32 0, ptr %tgp44, align 4
  %fp45 = getelementptr i8, ptr %hp43, i64 16
  store ptr @go$apply$19, ptr %fp45, align 8
  %go.addr = alloca ptr
  store ptr %hp43, ptr %go.addr
  %ld46 = load ptr, ptr %go.addr
  %fp47 = getelementptr i8, ptr %ld46, i64 16
  %fv48 = load ptr, ptr %fp47, align 8
  %ld49 = load ptr, ptr %xs.addr
  %cr50 = call i64 (ptr, ptr, i64) %fv48(ptr %ld46, ptr %ld49, i64 0)
  ret i64 %cr50
}

define i64 @ilog2(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %hp51 = call ptr @march_alloc(i64 24)
  %tgp52 = getelementptr i8, ptr %hp51, i64 8
  store i32 0, ptr %tgp52, align 4
  %fp53 = getelementptr i8, ptr %hp51, i64 16
  store ptr @go$apply$20, ptr %fp53, align 8
  %go.addr = alloca ptr
  store ptr %hp51, ptr %go.addr
  %ld54 = load ptr, ptr %go.addr
  %fp55 = getelementptr i8, ptr %ld54, i64 16
  %fv56 = load ptr, ptr %fp55, align 8
  %ld57 = load i64, ptr %n.addr
  %cr58 = call i64 (ptr, i64, i64) %fv56(ptr %ld54, i64 %ld57, i64 0)
  ret i64 %cr58
}

define i64 @rank(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld59 = load ptr, ptr %h.addr
  %res_slot60 = alloca ptr
  %tgp61 = getelementptr i8, ptr %ld59, i64 8
  %tag62 = load i32, ptr %tgp61, align 4
  switch i32 %tag62, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %ld63 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld63)
  %cv64 = inttoptr i64 0 to ptr
  store ptr %cv64, ptr %res_slot60
  br label %case_merge8
case_br11:
  %fp65 = getelementptr i8, ptr %ld59, i64 16
  %fv66 = load i64, ptr %fp65, align 8
  %$f983.addr = alloca i64
  store i64 %fv66, ptr %$f983.addr
  %fp67 = getelementptr i8, ptr %ld59, i64 24
  %fv68 = load i64, ptr %fp67, align 8
  %$f984.addr = alloca i64
  store i64 %fv68, ptr %$f984.addr
  %fp69 = getelementptr i8, ptr %ld59, i64 32
  %fv70 = load ptr, ptr %fp69, align 8
  %$f985.addr = alloca ptr
  store ptr %fv70, ptr %$f985.addr
  %fp71 = getelementptr i8, ptr %ld59, i64 40
  %fv72 = load ptr, ptr %fp71, align 8
  %$f986.addr = alloca ptr
  store ptr %fv72, ptr %$f986.addr
  %freed73 = call i64 @march_decrc_freed(ptr %ld59)
  %freed_b74 = icmp ne i64 %freed73, 0
  br i1 %freed_b74, label %br_unique12, label %br_shared13
br_shared13:
  call void @march_incrc(ptr %fv72)
  call void @march_incrc(ptr %fv70)
  br label %br_body14
br_unique12:
  br label %br_body14
br_body14:
  %ld75 = load ptr, ptr %$f983.addr
  %r.addr = alloca ptr
  store ptr %ld75, ptr %r.addr
  %ld76 = load i64, ptr %r.addr
  %cv77 = inttoptr i64 %ld76 to ptr
  store ptr %cv77, ptr %res_slot60
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r78 = load ptr, ptr %res_slot60
  %cv79 = ptrtoint ptr %case_r78 to i64
  ret i64 %cv79
}

define ptr @make_node(i64 %v.arg, ptr %left.arg, ptr %right.arg) {
entry:
  %v.addr = alloca i64
  store i64 %v.arg, ptr %v.addr
  %left.addr = alloca ptr
  store ptr %left.arg, ptr %left.addr
  %right.addr = alloca ptr
  store ptr %right.arg, ptr %right.addr
  %ld80 = load ptr, ptr %left.addr
  call void @march_incrc(ptr %ld80)
  %ld81 = load ptr, ptr %left.addr
  %cr82 = call i64 @rank(ptr %ld81)
  %$t987.addr = alloca i64
  store i64 %cr82, ptr %$t987.addr
  %ld83 = load ptr, ptr %right.addr
  call void @march_incrc(ptr %ld83)
  %ld84 = load ptr, ptr %right.addr
  %cr85 = call i64 @rank(ptr %ld84)
  %$t988.addr = alloca i64
  store i64 %cr85, ptr %$t988.addr
  %ld86 = load i64, ptr %$t987.addr
  %ld87 = load i64, ptr %$t988.addr
  %cmp88 = icmp sge i64 %ld86, %ld87
  %ar89 = zext i1 %cmp88 to i64
  %$t989.addr = alloca i64
  store i64 %ar89, ptr %$t989.addr
  %ld90 = load i64, ptr %$t989.addr
  %res_slot91 = alloca ptr
  switch i64 %ld90, label %case_default16 [
      i64 1, label %case_br17
  ]
case_br17:
  %ld92 = load ptr, ptr %right.addr
  call void @march_incrc(ptr %ld92)
  %ld93 = load ptr, ptr %right.addr
  %cr94 = call i64 @rank(ptr %ld93)
  %$t990.addr = alloca i64
  store i64 %cr94, ptr %$t990.addr
  %ld95 = load i64, ptr %$t990.addr
  %ar96 = add i64 %ld95, 1
  %$t991.addr = alloca i64
  store i64 %ar96, ptr %$t991.addr
  %hp97 = call ptr @march_alloc(i64 48)
  %tgp98 = getelementptr i8, ptr %hp97, i64 8
  store i32 1, ptr %tgp98, align 4
  %ld99 = load i64, ptr %$t991.addr
  %fp100 = getelementptr i8, ptr %hp97, i64 16
  store i64 %ld99, ptr %fp100, align 8
  %ld101 = load i64, ptr %v.addr
  %fp102 = getelementptr i8, ptr %hp97, i64 24
  store i64 %ld101, ptr %fp102, align 8
  %ld103 = load ptr, ptr %left.addr
  %fp104 = getelementptr i8, ptr %hp97, i64 32
  store ptr %ld103, ptr %fp104, align 8
  %ld105 = load ptr, ptr %right.addr
  %fp106 = getelementptr i8, ptr %hp97, i64 40
  store ptr %ld105, ptr %fp106, align 8
  store ptr %hp97, ptr %res_slot91
  br label %case_merge15
case_default16:
  %ld107 = load ptr, ptr %left.addr
  call void @march_incrc(ptr %ld107)
  %ld108 = load ptr, ptr %left.addr
  %cr109 = call i64 @rank(ptr %ld108)
  %$t992.addr = alloca i64
  store i64 %cr109, ptr %$t992.addr
  %ld110 = load i64, ptr %$t992.addr
  %ar111 = add i64 %ld110, 1
  %$t993.addr = alloca i64
  store i64 %ar111, ptr %$t993.addr
  %hp112 = call ptr @march_alloc(i64 48)
  %tgp113 = getelementptr i8, ptr %hp112, i64 8
  store i32 1, ptr %tgp113, align 4
  %ld114 = load i64, ptr %$t993.addr
  %fp115 = getelementptr i8, ptr %hp112, i64 16
  store i64 %ld114, ptr %fp115, align 8
  %ld116 = load i64, ptr %v.addr
  %fp117 = getelementptr i8, ptr %hp112, i64 24
  store i64 %ld116, ptr %fp117, align 8
  %ld118 = load ptr, ptr %right.addr
  %fp119 = getelementptr i8, ptr %hp112, i64 32
  store ptr %ld118, ptr %fp119, align 8
  %ld120 = load ptr, ptr %left.addr
  %fp121 = getelementptr i8, ptr %hp112, i64 40
  store ptr %ld120, ptr %fp121, align 8
  store ptr %hp112, ptr %res_slot91
  br label %case_merge15
case_merge15:
  %case_r122 = load ptr, ptr %res_slot91
  ret ptr %case_r122
}

define ptr @heap_merge(ptr %h1.arg, ptr %h2.arg) {
entry:
  %h1.addr = alloca ptr
  store ptr %h1.arg, ptr %h1.addr
  %h2.addr = alloca ptr
  store ptr %h2.arg, ptr %h2.addr
  %ld123 = load ptr, ptr %h1.addr
  %res_slot124 = alloca ptr
  %tgp125 = getelementptr i8, ptr %ld123, i64 8
  %tag126 = load i32, ptr %tgp125, align 4
  switch i32 %tag126, label %case_default19 [
      i32 0, label %case_br20
      i32 1, label %case_br21
  ]
case_br20:
  %ld127 = load ptr, ptr %h1.addr
  call void @march_decrc(ptr %ld127)
  %ld128 = load ptr, ptr %h2.addr
  store ptr %ld128, ptr %res_slot124
  br label %case_merge18
case_br21:
  %fp129 = getelementptr i8, ptr %ld123, i64 16
  %fv130 = load i64, ptr %fp129, align 8
  %$f1001.addr = alloca i64
  store i64 %fv130, ptr %$f1001.addr
  %fp131 = getelementptr i8, ptr %ld123, i64 24
  %fv132 = load i64, ptr %fp131, align 8
  %$f1002.addr = alloca i64
  store i64 %fv132, ptr %$f1002.addr
  %fp133 = getelementptr i8, ptr %ld123, i64 32
  %fv134 = load ptr, ptr %fp133, align 8
  %$f1003.addr = alloca ptr
  store ptr %fv134, ptr %$f1003.addr
  %fp135 = getelementptr i8, ptr %ld123, i64 40
  %fv136 = load ptr, ptr %fp135, align 8
  %$f1004.addr = alloca ptr
  store ptr %fv136, ptr %$f1004.addr
  %ld137 = load ptr, ptr %$f1004.addr
  %r1.addr = alloca ptr
  store ptr %ld137, ptr %r1.addr
  %ld138 = load ptr, ptr %$f1003.addr
  %l1.addr = alloca ptr
  store ptr %ld138, ptr %l1.addr
  %ld139 = load ptr, ptr %$f1002.addr
  %x.addr = alloca ptr
  store ptr %ld139, ptr %x.addr
  %ld140 = load ptr, ptr %h2.addr
  %res_slot141 = alloca ptr
  %tgp142 = getelementptr i8, ptr %ld140, i64 8
  %tag143 = load i32, ptr %tgp142, align 4
  switch i32 %tag143, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
  ]
case_br24:
  %ld144 = load ptr, ptr %h2.addr
  call void @march_decrc(ptr %ld144)
  %ld145 = load ptr, ptr %h1.addr
  store ptr %ld145, ptr %res_slot141
  br label %case_merge22
case_br25:
  %fp146 = getelementptr i8, ptr %ld140, i64 16
  %fv147 = load i64, ptr %fp146, align 8
  %$f997.addr = alloca i64
  store i64 %fv147, ptr %$f997.addr
  %fp148 = getelementptr i8, ptr %ld140, i64 24
  %fv149 = load i64, ptr %fp148, align 8
  %$f998.addr = alloca i64
  store i64 %fv149, ptr %$f998.addr
  %fp150 = getelementptr i8, ptr %ld140, i64 32
  %fv151 = load ptr, ptr %fp150, align 8
  %$f999.addr = alloca ptr
  store ptr %fv151, ptr %$f999.addr
  %fp152 = getelementptr i8, ptr %ld140, i64 40
  %fv153 = load ptr, ptr %fp152, align 8
  %$f1000.addr = alloca ptr
  store ptr %fv153, ptr %$f1000.addr
  %ld154 = load ptr, ptr %$f1000.addr
  %r2.addr = alloca ptr
  store ptr %ld154, ptr %r2.addr
  %ld155 = load ptr, ptr %$f999.addr
  %l2.addr = alloca ptr
  store ptr %ld155, ptr %l2.addr
  %ld156 = load ptr, ptr %$f998.addr
  %y.addr = alloca ptr
  store ptr %ld156, ptr %y.addr
  %ld157 = load i64, ptr %x.addr
  %ld158 = load i64, ptr %y.addr
  %cmp159 = icmp sle i64 %ld157, %ld158
  %ar160 = zext i1 %cmp159 to i64
  %$t994.addr = alloca i64
  store i64 %ar160, ptr %$t994.addr
  %ld161 = load i64, ptr %$t994.addr
  %res_slot162 = alloca ptr
  switch i64 %ld161, label %case_default27 [
      i64 1, label %case_br28
  ]
case_br28:
  %ld163 = load ptr, ptr %r1.addr
  %ld164 = load ptr, ptr %h2.addr
  %cr165 = call ptr @heap_merge(ptr %ld163, ptr %ld164)
  %$t995.addr = alloca ptr
  store ptr %cr165, ptr %$t995.addr
  %ld166 = load i64, ptr %x.addr
  %ld167 = load ptr, ptr %l1.addr
  %ld168 = load ptr, ptr %$t995.addr
  %cr169 = call ptr @make_node(i64 %ld166, ptr %ld167, ptr %ld168)
  store ptr %cr169, ptr %res_slot162
  br label %case_merge26
case_default27:
  %ld170 = load ptr, ptr %h1.addr
  %ld171 = load ptr, ptr %r2.addr
  %cr172 = call ptr @heap_merge(ptr %ld170, ptr %ld171)
  %$t996.addr = alloca ptr
  store ptr %cr172, ptr %$t996.addr
  %ld173 = load i64, ptr %y.addr
  %ld174 = load ptr, ptr %l2.addr
  %ld175 = load ptr, ptr %$t996.addr
  %cr176 = call ptr @make_node(i64 %ld173, ptr %ld174, ptr %ld175)
  store ptr %cr176, ptr %res_slot162
  br label %case_merge26
case_merge26:
  %case_r177 = load ptr, ptr %res_slot162
  store ptr %case_r177, ptr %res_slot141
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r178 = load ptr, ptr %res_slot141
  store ptr %case_r178, ptr %res_slot124
  br label %case_merge18
case_default19:
  unreachable
case_merge18:
  %case_r179 = load ptr, ptr %res_slot124
  ret ptr %case_r179
}

define i64 @heap_min(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld180 = load ptr, ptr %h.addr
  %res_slot181 = alloca ptr
  %tgp182 = getelementptr i8, ptr %ld180, i64 8
  %tag183 = load i32, ptr %tgp182, align 4
  switch i32 %tag183, label %case_default30 [
      i32 0, label %case_br31
      i32 1, label %case_br32
  ]
case_br31:
  %ld184 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld184)
  %cv185 = inttoptr i64 0 to ptr
  store ptr %cv185, ptr %res_slot181
  br label %case_merge29
case_br32:
  %fp186 = getelementptr i8, ptr %ld180, i64 16
  %fv187 = load i64, ptr %fp186, align 8
  %$f1008.addr = alloca i64
  store i64 %fv187, ptr %$f1008.addr
  %fp188 = getelementptr i8, ptr %ld180, i64 24
  %fv189 = load i64, ptr %fp188, align 8
  %$f1009.addr = alloca i64
  store i64 %fv189, ptr %$f1009.addr
  %fp190 = getelementptr i8, ptr %ld180, i64 32
  %fv191 = load ptr, ptr %fp190, align 8
  %$f1010.addr = alloca ptr
  store ptr %fv191, ptr %$f1010.addr
  %fp192 = getelementptr i8, ptr %ld180, i64 40
  %fv193 = load ptr, ptr %fp192, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv193, ptr %$f1011.addr
  %freed194 = call i64 @march_decrc_freed(ptr %ld180)
  %freed_b195 = icmp ne i64 %freed194, 0
  br i1 %freed_b195, label %br_unique33, label %br_shared34
br_shared34:
  call void @march_incrc(ptr %fv193)
  call void @march_incrc(ptr %fv191)
  br label %br_body35
br_unique33:
  br label %br_body35
br_body35:
  %ld196 = load ptr, ptr %$f1009.addr
  %v.addr = alloca ptr
  store ptr %ld196, ptr %v.addr
  %ld197 = load i64, ptr %v.addr
  %cv198 = inttoptr i64 %ld197 to ptr
  store ptr %cv198, ptr %res_slot181
  br label %case_merge29
case_default30:
  unreachable
case_merge29:
  %case_r199 = load ptr, ptr %res_slot181
  %cv200 = ptrtoint ptr %case_r199 to i64
  ret i64 %cv200
}

define ptr @heap_pop(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld201 = load ptr, ptr %h.addr
  %res_slot202 = alloca ptr
  %tgp203 = getelementptr i8, ptr %ld201, i64 8
  %tag204 = load i32, ptr %tgp203, align 4
  switch i32 %tag204, label %case_default37 [
      i32 0, label %case_br38
      i32 1, label %case_br39
  ]
case_br38:
  %ld205 = load ptr, ptr %h.addr
  %rc206 = load i64, ptr %ld205, align 8
  %uniq207 = icmp eq i64 %rc206, 1
  %fbip_slot208 = alloca ptr
  br i1 %uniq207, label %fbip_reuse40, label %fbip_fresh41
fbip_reuse40:
  %tgp209 = getelementptr i8, ptr %ld205, i64 8
  store i32 0, ptr %tgp209, align 4
  store ptr %ld205, ptr %fbip_slot208
  br label %fbip_merge42
fbip_fresh41:
  call void @march_decrc(ptr %ld205)
  %hp210 = call ptr @march_alloc(i64 16)
  %tgp211 = getelementptr i8, ptr %hp210, i64 8
  store i32 0, ptr %tgp211, align 4
  store ptr %hp210, ptr %fbip_slot208
  br label %fbip_merge42
fbip_merge42:
  %fbip_r212 = load ptr, ptr %fbip_slot208
  store ptr %fbip_r212, ptr %res_slot202
  br label %case_merge36
case_br39:
  %fp213 = getelementptr i8, ptr %ld201, i64 16
  %fv214 = load i64, ptr %fp213, align 8
  %$f1012.addr = alloca i64
  store i64 %fv214, ptr %$f1012.addr
  %fp215 = getelementptr i8, ptr %ld201, i64 24
  %fv216 = load i64, ptr %fp215, align 8
  %$f1013.addr = alloca i64
  store i64 %fv216, ptr %$f1013.addr
  %fp217 = getelementptr i8, ptr %ld201, i64 32
  %fv218 = load ptr, ptr %fp217, align 8
  %$f1014.addr = alloca ptr
  store ptr %fv218, ptr %$f1014.addr
  %fp219 = getelementptr i8, ptr %ld201, i64 40
  %fv220 = load ptr, ptr %fp219, align 8
  %$f1015.addr = alloca ptr
  store ptr %fv220, ptr %$f1015.addr
  %freed221 = call i64 @march_decrc_freed(ptr %ld201)
  %freed_b222 = icmp ne i64 %freed221, 0
  br i1 %freed_b222, label %br_unique43, label %br_shared44
br_shared44:
  call void @march_incrc(ptr %fv220)
  call void @march_incrc(ptr %fv218)
  br label %br_body45
br_unique43:
  br label %br_body45
br_body45:
  %ld223 = load ptr, ptr %$f1015.addr
  %r.addr = alloca ptr
  store ptr %ld223, ptr %r.addr
  %ld224 = load ptr, ptr %$f1014.addr
  %l.addr = alloca ptr
  store ptr %ld224, ptr %l.addr
  %ld225 = load ptr, ptr %l.addr
  %ld226 = load ptr, ptr %r.addr
  %cr227 = call ptr @heap_merge(ptr %ld225, ptr %ld226)
  store ptr %cr227, ptr %res_slot202
  br label %case_merge36
case_default37:
  unreachable
case_merge36:
  %case_r228 = load ptr, ptr %res_slot202
  ret ptr %case_r228
}

define ptr @build_heap(ptr %xs.arg, ptr %h.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld229 = load ptr, ptr %xs.addr
  %res_slot230 = alloca ptr
  %tgp231 = getelementptr i8, ptr %ld229, i64 8
  %tag232 = load i32, ptr %tgp231, align 4
  switch i32 %tag232, label %case_default47 [
      i32 0, label %case_br48
      i32 1, label %case_br49
  ]
case_br48:
  %ld233 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld233)
  %ld234 = load ptr, ptr %h.addr
  store ptr %ld234, ptr %res_slot230
  br label %case_merge46
case_br49:
  %fp235 = getelementptr i8, ptr %ld229, i64 16
  %fv236 = load ptr, ptr %fp235, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv236, ptr %$f1017.addr
  %fp237 = getelementptr i8, ptr %ld229, i64 24
  %fv238 = load ptr, ptr %fp237, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv238, ptr %$f1018.addr
  %freed239 = call i64 @march_decrc_freed(ptr %ld229)
  %freed_b240 = icmp ne i64 %freed239, 0
  br i1 %freed_b240, label %br_unique50, label %br_shared51
br_shared51:
  call void @march_incrc(ptr %fv238)
  br label %br_body52
br_unique50:
  br label %br_body52
br_body52:
  %ld241 = load ptr, ptr %$f1018.addr
  %t.addr = alloca ptr
  store ptr %ld241, ptr %t.addr
  %ld242 = load ptr, ptr %$f1017.addr
  %v.addr = alloca ptr
  store ptr %ld242, ptr %v.addr
  %ld243 = load i64, ptr %v.addr
  %v_i1.addr = alloca i64
  store i64 %ld243, ptr %v_i1.addr
  %ld244 = load ptr, ptr %h.addr
  %h_i2.addr = alloca ptr
  store ptr %ld244, ptr %h_i2.addr
  %hp245 = call ptr @march_alloc(i64 16)
  %tgp246 = getelementptr i8, ptr %hp245, i64 8
  store i32 0, ptr %tgp246, align 4
  %$t1005_i3.addr = alloca ptr
  store ptr %hp245, ptr %$t1005_i3.addr
  %hp247 = call ptr @march_alloc(i64 16)
  %tgp248 = getelementptr i8, ptr %hp247, i64 8
  store i32 0, ptr %tgp248, align 4
  %$t1006_i4.addr = alloca ptr
  store ptr %hp247, ptr %$t1006_i4.addr
  %hp249 = call ptr @march_alloc(i64 48)
  %tgp250 = getelementptr i8, ptr %hp249, i64 8
  store i32 1, ptr %tgp250, align 4
  %fp251 = getelementptr i8, ptr %hp249, i64 16
  store i64 1, ptr %fp251, align 8
  %ld252 = load i64, ptr %v_i1.addr
  %fp253 = getelementptr i8, ptr %hp249, i64 24
  store i64 %ld252, ptr %fp253, align 8
  %ld254 = load ptr, ptr %$t1005_i3.addr
  %fp255 = getelementptr i8, ptr %hp249, i64 32
  store ptr %ld254, ptr %fp255, align 8
  %ld256 = load ptr, ptr %$t1006_i4.addr
  %fp257 = getelementptr i8, ptr %hp249, i64 40
  store ptr %ld256, ptr %fp257, align 8
  %$t1007_i5.addr = alloca ptr
  store ptr %hp249, ptr %$t1007_i5.addr
  %ld258 = load ptr, ptr %$t1007_i5.addr
  %ld259 = load ptr, ptr %h_i2.addr
  %cr260 = call ptr @heap_merge(ptr %ld258, ptr %ld259)
  %$t1016.addr = alloca ptr
  store ptr %cr260, ptr %$t1016.addr
  %ld261 = load ptr, ptr %t.addr
  %ld262 = load ptr, ptr %$t1016.addr
  %cr263 = call ptr @build_heap(ptr %ld261, ptr %ld262)
  store ptr %cr263, ptr %res_slot230
  br label %case_merge46
case_default47:
  unreachable
case_merge46:
  %case_r264 = load ptr, ptr %res_slot230
  ret ptr %case_r264
}

define ptr @drain_heap(ptr %h.arg, ptr %acc.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld265 = load ptr, ptr %h.addr
  %res_slot266 = alloca ptr
  %tgp267 = getelementptr i8, ptr %ld265, i64 8
  %tag268 = load i32, ptr %tgp267, align 4
  switch i32 %tag268, label %case_default54 [
      i32 0, label %case_br55
  ]
case_br55:
  %ld269 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld269)
  %ld270 = load ptr, ptr %acc.addr
  %cr271 = call ptr @reverse_list(ptr %ld270)
  store ptr %cr271, ptr %res_slot266
  br label %case_merge53
case_default54:
  %ld272 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld272)
  %ld273 = load ptr, ptr %h.addr
  %cr274 = call ptr @heap_pop(ptr %ld273)
  %$t1019.addr = alloca ptr
  store ptr %cr274, ptr %$t1019.addr
  %ld275 = load ptr, ptr %h.addr
  %cr276 = call i64 @heap_min(ptr %ld275)
  %$t1020.addr = alloca i64
  store i64 %cr276, ptr %$t1020.addr
  %hp277 = call ptr @march_alloc(i64 32)
  %tgp278 = getelementptr i8, ptr %hp277, i64 8
  store i32 1, ptr %tgp278, align 4
  %ld279 = load i64, ptr %$t1020.addr
  %cv280 = inttoptr i64 %ld279 to ptr
  %fp281 = getelementptr i8, ptr %hp277, i64 16
  store ptr %cv280, ptr %fp281, align 8
  %ld282 = load ptr, ptr %acc.addr
  %fp283 = getelementptr i8, ptr %hp277, i64 24
  store ptr %ld282, ptr %fp283, align 8
  %$t1021.addr = alloca ptr
  store ptr %hp277, ptr %$t1021.addr
  %ld284 = load ptr, ptr %$t1019.addr
  %ld285 = load ptr, ptr %$t1021.addr
  %cr286 = call ptr @drain_heap(ptr %ld284, ptr %ld285)
  store ptr %cr286, ptr %res_slot266
  br label %case_merge53
case_merge53:
  %case_r287 = load ptr, ptr %res_slot266
  ret ptr %case_r287
}

define ptr @insert(i64 %v.arg, ptr %sorted.arg) {
entry:
  %v.addr = alloca i64
  store i64 %v.arg, ptr %v.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %ld288 = load ptr, ptr %sorted.addr
  %res_slot289 = alloca ptr
  %tgp290 = getelementptr i8, ptr %ld288, i64 8
  %tag291 = load i32, ptr %tgp290, align 4
  switch i32 %tag291, label %case_default57 [
      i32 0, label %case_br58
      i32 1, label %case_br59
  ]
case_br58:
  %ld292 = load ptr, ptr %sorted.addr
  %rc293 = load i64, ptr %ld292, align 8
  %uniq294 = icmp eq i64 %rc293, 1
  %fbip_slot295 = alloca ptr
  br i1 %uniq294, label %fbip_reuse60, label %fbip_fresh61
fbip_reuse60:
  %tgp296 = getelementptr i8, ptr %ld292, i64 8
  store i32 0, ptr %tgp296, align 4
  store ptr %ld292, ptr %fbip_slot295
  br label %fbip_merge62
fbip_fresh61:
  call void @march_decrc(ptr %ld292)
  %hp297 = call ptr @march_alloc(i64 16)
  %tgp298 = getelementptr i8, ptr %hp297, i64 8
  store i32 0, ptr %tgp298, align 4
  store ptr %hp297, ptr %fbip_slot295
  br label %fbip_merge62
fbip_merge62:
  %fbip_r299 = load ptr, ptr %fbip_slot295
  %$t1025.addr = alloca ptr
  store ptr %fbip_r299, ptr %$t1025.addr
  %hp300 = call ptr @march_alloc(i64 32)
  %tgp301 = getelementptr i8, ptr %hp300, i64 8
  store i32 1, ptr %tgp301, align 4
  %ld302 = load i64, ptr %v.addr
  %cv303 = inttoptr i64 %ld302 to ptr
  %fp304 = getelementptr i8, ptr %hp300, i64 16
  store ptr %cv303, ptr %fp304, align 8
  %ld305 = load ptr, ptr %$t1025.addr
  %fp306 = getelementptr i8, ptr %hp300, i64 24
  store ptr %ld305, ptr %fp306, align 8
  store ptr %hp300, ptr %res_slot289
  br label %case_merge56
case_br59:
  %fp307 = getelementptr i8, ptr %ld288, i64 16
  %fv308 = load ptr, ptr %fp307, align 8
  %$f1028.addr = alloca ptr
  store ptr %fv308, ptr %$f1028.addr
  %fp309 = getelementptr i8, ptr %ld288, i64 24
  %fv310 = load ptr, ptr %fp309, align 8
  %$f1029.addr = alloca ptr
  store ptr %fv310, ptr %$f1029.addr
  %ld311 = load ptr, ptr %$f1029.addr
  %t.addr = alloca ptr
  store ptr %ld311, ptr %t.addr
  %ld312 = load ptr, ptr %$f1028.addr
  %h.addr = alloca ptr
  store ptr %ld312, ptr %h.addr
  %ld313 = load i64, ptr %v.addr
  %ld314 = load i64, ptr %h.addr
  %cmp315 = icmp sle i64 %ld313, %ld314
  %ar316 = zext i1 %cmp315 to i64
  %$t1026.addr = alloca i64
  store i64 %ar316, ptr %$t1026.addr
  %ld317 = load i64, ptr %$t1026.addr
  %res_slot318 = alloca ptr
  switch i64 %ld317, label %case_default64 [
      i64 1, label %case_br65
  ]
case_br65:
  %hp319 = call ptr @march_alloc(i64 32)
  %tgp320 = getelementptr i8, ptr %hp319, i64 8
  store i32 1, ptr %tgp320, align 4
  %ld321 = load i64, ptr %v.addr
  %cv322 = inttoptr i64 %ld321 to ptr
  %fp323 = getelementptr i8, ptr %hp319, i64 16
  store ptr %cv322, ptr %fp323, align 8
  %ld324 = load ptr, ptr %sorted.addr
  %fp325 = getelementptr i8, ptr %hp319, i64 24
  store ptr %ld324, ptr %fp325, align 8
  store ptr %hp319, ptr %res_slot318
  br label %case_merge63
case_default64:
  %ld326 = load i64, ptr %v.addr
  %ld327 = load ptr, ptr %t.addr
  %cr328 = call ptr @insert(i64 %ld326, ptr %ld327)
  %$t1027.addr = alloca ptr
  store ptr %cr328, ptr %$t1027.addr
  %hp329 = call ptr @march_alloc(i64 32)
  %tgp330 = getelementptr i8, ptr %hp329, i64 8
  store i32 1, ptr %tgp330, align 4
  %ld331 = load i64, ptr %h.addr
  %cv332 = inttoptr i64 %ld331 to ptr
  %fp333 = getelementptr i8, ptr %hp329, i64 16
  store ptr %cv332, ptr %fp333, align 8
  %ld334 = load ptr, ptr %$t1027.addr
  %fp335 = getelementptr i8, ptr %hp329, i64 24
  store ptr %ld334, ptr %fp335, align 8
  store ptr %hp329, ptr %res_slot318
  br label %case_merge63
case_merge63:
  %case_r336 = load ptr, ptr %res_slot318
  store ptr %case_r336, ptr %res_slot289
  br label %case_merge56
case_default57:
  unreachable
case_merge56:
  %case_r337 = load ptr, ptr %res_slot289
  ret ptr %case_r337
}

define ptr @insertion_sort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp338 = call ptr @march_alloc(i64 24)
  %tgp339 = getelementptr i8, ptr %hp338, i64 8
  store i32 0, ptr %tgp339, align 4
  %fp340 = getelementptr i8, ptr %hp338, i64 16
  store ptr @go$apply$21, ptr %fp340, align 8
  %go.addr = alloca ptr
  store ptr %hp338, ptr %go.addr
  %hp341 = call ptr @march_alloc(i64 16)
  %tgp342 = getelementptr i8, ptr %hp341, i64 8
  store i32 0, ptr %tgp342, align 4
  %$t1033.addr = alloca ptr
  store ptr %hp341, ptr %$t1033.addr
  %ld343 = load ptr, ptr %go.addr
  %fp344 = getelementptr i8, ptr %ld343, i64 16
  %fv345 = load ptr, ptr %fp344, align 8
  %ld346 = load ptr, ptr %xs.addr
  %ld347 = load ptr, ptr %$t1033.addr
  %cr348 = call ptr (ptr, ptr, ptr) %fv345(ptr %ld343, ptr %ld346, ptr %ld347)
  ret ptr %cr348
}

define i64 @median3(i64 %a.arg, i64 %b.arg, i64 %c.arg) {
entry:
  %a.addr = alloca i64
  store i64 %a.arg, ptr %a.addr
  %b.addr = alloca i64
  store i64 %b.arg, ptr %b.addr
  %c.addr = alloca i64
  store i64 %c.arg, ptr %c.addr
  %ld349 = load i64, ptr %a.addr
  %ld350 = load i64, ptr %b.addr
  %cmp351 = icmp sle i64 %ld349, %ld350
  %ar352 = zext i1 %cmp351 to i64
  %$t1034.addr = alloca i64
  store i64 %ar352, ptr %$t1034.addr
  %ld353 = load i64, ptr %$t1034.addr
  %res_slot354 = alloca ptr
  switch i64 %ld353, label %case_default67 [
      i64 1, label %case_br68
  ]
case_br68:
  %ld355 = load i64, ptr %b.addr
  %ld356 = load i64, ptr %c.addr
  %cmp357 = icmp sle i64 %ld355, %ld356
  %ar358 = zext i1 %cmp357 to i64
  %$t1035.addr = alloca i64
  store i64 %ar358, ptr %$t1035.addr
  %ld359 = load i64, ptr %$t1035.addr
  %res_slot360 = alloca ptr
  switch i64 %ld359, label %case_default70 [
      i64 1, label %case_br71
  ]
case_br71:
  %ld361 = load i64, ptr %b.addr
  %cv362 = inttoptr i64 %ld361 to ptr
  store ptr %cv362, ptr %res_slot360
  br label %case_merge69
case_default70:
  %ld363 = load i64, ptr %a.addr
  %ld364 = load i64, ptr %c.addr
  %cmp365 = icmp sle i64 %ld363, %ld364
  %ar366 = zext i1 %cmp365 to i64
  %$t1036.addr = alloca i64
  store i64 %ar366, ptr %$t1036.addr
  %ld367 = load i64, ptr %$t1036.addr
  %res_slot368 = alloca ptr
  switch i64 %ld367, label %case_default73 [
      i64 1, label %case_br74
  ]
case_br74:
  %ld369 = load i64, ptr %c.addr
  %cv370 = inttoptr i64 %ld369 to ptr
  store ptr %cv370, ptr %res_slot368
  br label %case_merge72
case_default73:
  %ld371 = load i64, ptr %a.addr
  %cv372 = inttoptr i64 %ld371 to ptr
  store ptr %cv372, ptr %res_slot368
  br label %case_merge72
case_merge72:
  %case_r373 = load ptr, ptr %res_slot368
  store ptr %case_r373, ptr %res_slot360
  br label %case_merge69
case_merge69:
  %case_r374 = load ptr, ptr %res_slot360
  store ptr %case_r374, ptr %res_slot354
  br label %case_merge66
case_default67:
  %ld375 = load i64, ptr %a.addr
  %ld376 = load i64, ptr %c.addr
  %cmp377 = icmp sle i64 %ld375, %ld376
  %ar378 = zext i1 %cmp377 to i64
  %$t1037.addr = alloca i64
  store i64 %ar378, ptr %$t1037.addr
  %ld379 = load i64, ptr %$t1037.addr
  %res_slot380 = alloca ptr
  switch i64 %ld379, label %case_default76 [
      i64 1, label %case_br77
  ]
case_br77:
  %ld381 = load i64, ptr %a.addr
  %cv382 = inttoptr i64 %ld381 to ptr
  store ptr %cv382, ptr %res_slot380
  br label %case_merge75
case_default76:
  %ld383 = load i64, ptr %b.addr
  %ld384 = load i64, ptr %c.addr
  %cmp385 = icmp sle i64 %ld383, %ld384
  %ar386 = zext i1 %cmp385 to i64
  %$t1038.addr = alloca i64
  store i64 %ar386, ptr %$t1038.addr
  %ld387 = load i64, ptr %$t1038.addr
  %res_slot388 = alloca ptr
  switch i64 %ld387, label %case_default79 [
      i64 1, label %case_br80
  ]
case_br80:
  %ld389 = load i64, ptr %c.addr
  %cv390 = inttoptr i64 %ld389 to ptr
  store ptr %cv390, ptr %res_slot388
  br label %case_merge78
case_default79:
  %ld391 = load i64, ptr %b.addr
  %cv392 = inttoptr i64 %ld391 to ptr
  store ptr %cv392, ptr %res_slot388
  br label %case_merge78
case_merge78:
  %case_r393 = load ptr, ptr %res_slot388
  store ptr %case_r393, ptr %res_slot380
  br label %case_merge75
case_merge75:
  %case_r394 = load ptr, ptr %res_slot380
  store ptr %case_r394, ptr %res_slot354
  br label %case_merge66
case_merge66:
  %case_r395 = load ptr, ptr %res_slot354
  %cv396 = ptrtoint ptr %case_r395 to i64
  ret i64 %cv396
}

define ptr @partition3(ptr %xs.arg, i64 %pivot.arg, ptr %lt.arg, ptr %eq.arg, ptr %gt.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %pivot.addr = alloca i64
  store i64 %pivot.arg, ptr %pivot.addr
  %lt.addr = alloca ptr
  store ptr %lt.arg, ptr %lt.addr
  %eq.addr = alloca ptr
  store ptr %eq.arg, ptr %eq.addr
  %gt.addr = alloca ptr
  store ptr %gt.arg, ptr %gt.addr
  %ld397 = load ptr, ptr %xs.addr
  %res_slot398 = alloca ptr
  %tgp399 = getelementptr i8, ptr %ld397, i64 8
  %tag400 = load i32, ptr %tgp399, align 4
  switch i32 %tag400, label %case_default82 [
      i32 0, label %case_br83
      i32 1, label %case_br84
  ]
case_br83:
  %ld401 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld401)
  %ld402 = load ptr, ptr %lt.addr
  %cr403 = call ptr @reverse_list(ptr %ld402)
  %$t1039.addr = alloca ptr
  store ptr %cr403, ptr %$t1039.addr
  %ld404 = load ptr, ptr %gt.addr
  %cr405 = call ptr @reverse_list(ptr %ld404)
  %$t1040.addr = alloca ptr
  store ptr %cr405, ptr %$t1040.addr
  %hp406 = call ptr @march_alloc(i64 40)
  %tgp407 = getelementptr i8, ptr %hp406, i64 8
  store i32 0, ptr %tgp407, align 4
  %ld408 = load ptr, ptr %$t1039.addr
  %fp409 = getelementptr i8, ptr %hp406, i64 16
  store ptr %ld408, ptr %fp409, align 8
  %ld410 = load ptr, ptr %eq.addr
  %fp411 = getelementptr i8, ptr %hp406, i64 24
  store ptr %ld410, ptr %fp411, align 8
  %ld412 = load ptr, ptr %$t1040.addr
  %fp413 = getelementptr i8, ptr %hp406, i64 32
  store ptr %ld412, ptr %fp413, align 8
  store ptr %hp406, ptr %res_slot398
  br label %case_merge81
case_br84:
  %fp414 = getelementptr i8, ptr %ld397, i64 16
  %fv415 = load ptr, ptr %fp414, align 8
  %$f1046.addr = alloca ptr
  store ptr %fv415, ptr %$f1046.addr
  %fp416 = getelementptr i8, ptr %ld397, i64 24
  %fv417 = load ptr, ptr %fp416, align 8
  %$f1047.addr = alloca ptr
  store ptr %fv417, ptr %$f1047.addr
  %freed418 = call i64 @march_decrc_freed(ptr %ld397)
  %freed_b419 = icmp ne i64 %freed418, 0
  br i1 %freed_b419, label %br_unique85, label %br_shared86
br_shared86:
  call void @march_incrc(ptr %fv417)
  br label %br_body87
br_unique85:
  br label %br_body87
br_body87:
  %ld420 = load ptr, ptr %$f1047.addr
  %t.addr = alloca ptr
  store ptr %ld420, ptr %t.addr
  %ld421 = load ptr, ptr %$f1046.addr
  %h.addr = alloca ptr
  store ptr %ld421, ptr %h.addr
  %ld422 = load i64, ptr %h.addr
  %ld423 = load i64, ptr %pivot.addr
  %cmp424 = icmp slt i64 %ld422, %ld423
  %ar425 = zext i1 %cmp424 to i64
  %$t1041.addr = alloca i64
  store i64 %ar425, ptr %$t1041.addr
  %ld426 = load i64, ptr %$t1041.addr
  %res_slot427 = alloca ptr
  switch i64 %ld426, label %case_default89 [
      i64 1, label %case_br90
  ]
case_br90:
  %hp428 = call ptr @march_alloc(i64 32)
  %tgp429 = getelementptr i8, ptr %hp428, i64 8
  store i32 1, ptr %tgp429, align 4
  %ld430 = load i64, ptr %h.addr
  %cv431 = inttoptr i64 %ld430 to ptr
  %fp432 = getelementptr i8, ptr %hp428, i64 16
  store ptr %cv431, ptr %fp432, align 8
  %ld433 = load ptr, ptr %lt.addr
  %fp434 = getelementptr i8, ptr %hp428, i64 24
  store ptr %ld433, ptr %fp434, align 8
  %$t1042.addr = alloca ptr
  store ptr %hp428, ptr %$t1042.addr
  %ld435 = load ptr, ptr %t.addr
  %ld436 = load i64, ptr %pivot.addr
  %ld437 = load ptr, ptr %$t1042.addr
  %ld438 = load ptr, ptr %eq.addr
  %ld439 = load ptr, ptr %gt.addr
  %cr440 = call ptr @partition3(ptr %ld435, i64 %ld436, ptr %ld437, ptr %ld438, ptr %ld439)
  store ptr %cr440, ptr %res_slot427
  br label %case_merge88
case_default89:
  %ld441 = load i64, ptr %h.addr
  %ld442 = load i64, ptr %pivot.addr
  %cmp443 = icmp eq i64 %ld441, %ld442
  %ar444 = zext i1 %cmp443 to i64
  %$t1043.addr = alloca i64
  store i64 %ar444, ptr %$t1043.addr
  %ld445 = load i64, ptr %$t1043.addr
  %res_slot446 = alloca ptr
  switch i64 %ld445, label %case_default92 [
      i64 1, label %case_br93
  ]
case_br93:
  %hp447 = call ptr @march_alloc(i64 32)
  %tgp448 = getelementptr i8, ptr %hp447, i64 8
  store i32 1, ptr %tgp448, align 4
  %ld449 = load i64, ptr %h.addr
  %cv450 = inttoptr i64 %ld449 to ptr
  %fp451 = getelementptr i8, ptr %hp447, i64 16
  store ptr %cv450, ptr %fp451, align 8
  %ld452 = load ptr, ptr %eq.addr
  %fp453 = getelementptr i8, ptr %hp447, i64 24
  store ptr %ld452, ptr %fp453, align 8
  %$t1044.addr = alloca ptr
  store ptr %hp447, ptr %$t1044.addr
  %ld454 = load ptr, ptr %t.addr
  %ld455 = load i64, ptr %pivot.addr
  %ld456 = load ptr, ptr %lt.addr
  %ld457 = load ptr, ptr %$t1044.addr
  %ld458 = load ptr, ptr %gt.addr
  %cr459 = call ptr @partition3(ptr %ld454, i64 %ld455, ptr %ld456, ptr %ld457, ptr %ld458)
  store ptr %cr459, ptr %res_slot446
  br label %case_merge91
case_default92:
  %hp460 = call ptr @march_alloc(i64 32)
  %tgp461 = getelementptr i8, ptr %hp460, i64 8
  store i32 1, ptr %tgp461, align 4
  %ld462 = load i64, ptr %h.addr
  %cv463 = inttoptr i64 %ld462 to ptr
  %fp464 = getelementptr i8, ptr %hp460, i64 16
  store ptr %cv463, ptr %fp464, align 8
  %ld465 = load ptr, ptr %gt.addr
  %fp466 = getelementptr i8, ptr %hp460, i64 24
  store ptr %ld465, ptr %fp466, align 8
  %$t1045.addr = alloca ptr
  store ptr %hp460, ptr %$t1045.addr
  %ld467 = load ptr, ptr %t.addr
  %ld468 = load i64, ptr %pivot.addr
  %ld469 = load ptr, ptr %lt.addr
  %ld470 = load ptr, ptr %eq.addr
  %ld471 = load ptr, ptr %$t1045.addr
  %cr472 = call ptr @partition3(ptr %ld467, i64 %ld468, ptr %ld469, ptr %ld470, ptr %ld471)
  store ptr %cr472, ptr %res_slot446
  br label %case_merge91
case_merge91:
  %case_r473 = load ptr, ptr %res_slot446
  store ptr %case_r473, ptr %res_slot427
  br label %case_merge88
case_merge88:
  %case_r474 = load ptr, ptr %res_slot427
  store ptr %case_r474, ptr %res_slot398
  br label %case_merge81
case_default82:
  unreachable
case_merge81:
  %case_r475 = load ptr, ptr %res_slot398
  ret ptr %case_r475
}

define i64 @nth(ptr %xs.arg, i64 %n.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld476 = load ptr, ptr %xs.addr
  %res_slot477 = alloca ptr
  %tgp478 = getelementptr i8, ptr %ld476, i64 8
  %tag479 = load i32, ptr %tgp478, align 4
  switch i32 %tag479, label %case_default95 [
      i32 0, label %case_br96
      i32 1, label %case_br97
  ]
case_br96:
  %ld480 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld480)
  %cv481 = inttoptr i64 0 to ptr
  store ptr %cv481, ptr %res_slot477
  br label %case_merge94
case_br97:
  %fp482 = getelementptr i8, ptr %ld476, i64 16
  %fv483 = load ptr, ptr %fp482, align 8
  %$f1050.addr = alloca ptr
  store ptr %fv483, ptr %$f1050.addr
  %fp484 = getelementptr i8, ptr %ld476, i64 24
  %fv485 = load ptr, ptr %fp484, align 8
  %$f1051.addr = alloca ptr
  store ptr %fv485, ptr %$f1051.addr
  %freed486 = call i64 @march_decrc_freed(ptr %ld476)
  %freed_b487 = icmp ne i64 %freed486, 0
  br i1 %freed_b487, label %br_unique98, label %br_shared99
br_shared99:
  call void @march_incrc(ptr %fv485)
  br label %br_body100
br_unique98:
  br label %br_body100
br_body100:
  %ld488 = load ptr, ptr %$f1051.addr
  %t.addr = alloca ptr
  store ptr %ld488, ptr %t.addr
  %ld489 = load ptr, ptr %$f1050.addr
  %h.addr = alloca ptr
  store ptr %ld489, ptr %h.addr
  %ld490 = load i64, ptr %n.addr
  %cmp491 = icmp eq i64 %ld490, 0
  %ar492 = zext i1 %cmp491 to i64
  %$t1048.addr = alloca i64
  store i64 %ar492, ptr %$t1048.addr
  %ld493 = load i64, ptr %$t1048.addr
  %res_slot494 = alloca ptr
  switch i64 %ld493, label %case_default102 [
      i64 1, label %case_br103
  ]
case_br103:
  %ld495 = load i64, ptr %h.addr
  %cv496 = inttoptr i64 %ld495 to ptr
  store ptr %cv496, ptr %res_slot494
  br label %case_merge101
case_default102:
  %ld497 = load i64, ptr %n.addr
  %ar498 = sub i64 %ld497, 1
  %$t1049.addr = alloca i64
  store i64 %ar498, ptr %$t1049.addr
  %ld499 = load ptr, ptr %t.addr
  %ld500 = load i64, ptr %$t1049.addr
  %cr501 = call i64 @nth(ptr %ld499, i64 %ld500)
  %cv502 = inttoptr i64 %cr501 to ptr
  store ptr %cv502, ptr %res_slot494
  br label %case_merge101
case_merge101:
  %case_r503 = load ptr, ptr %res_slot494
  store ptr %case_r503, ptr %res_slot477
  br label %case_merge94
case_default95:
  unreachable
case_merge94:
  %case_r504 = load ptr, ptr %res_slot477
  %cv505 = ptrtoint ptr %case_r504 to i64
  ret i64 %cv505
}

define ptr @introsort(ptr %xs.arg, i64 %depth_limit.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %depth_limit.addr = alloca i64
  store i64 %depth_limit.arg, ptr %depth_limit.addr
  %ld506 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld506)
  %ld507 = load ptr, ptr %xs.addr
  %cr508 = call i64 @list_len(ptr %ld507)
  %n.addr = alloca i64
  store i64 %cr508, ptr %n.addr
  %ld509 = load i64, ptr %n.addr
  %cmp510 = icmp sle i64 %ld509, 1
  %ar511 = zext i1 %cmp510 to i64
  %$t1052.addr = alloca i64
  store i64 %ar511, ptr %$t1052.addr
  %ld512 = load i64, ptr %$t1052.addr
  %res_slot513 = alloca ptr
  switch i64 %ld512, label %case_default105 [
      i64 1, label %case_br106
  ]
case_br106:
  %ld514 = load ptr, ptr %xs.addr
  store ptr %ld514, ptr %res_slot513
  br label %case_merge104
case_default105:
  %ld515 = load i64, ptr %n.addr
  %cmp516 = icmp sle i64 %ld515, 8
  %ar517 = zext i1 %cmp516 to i64
  %$t1053.addr = alloca i64
  store i64 %ar517, ptr %$t1053.addr
  %ld518 = load i64, ptr %$t1053.addr
  %res_slot519 = alloca ptr
  switch i64 %ld518, label %case_default108 [
      i64 1, label %case_br109
  ]
case_br109:
  %ld520 = load ptr, ptr %xs.addr
  %cr521 = call ptr @insertion_sort(ptr %ld520)
  store ptr %cr521, ptr %res_slot519
  br label %case_merge107
case_default108:
  %ld522 = load i64, ptr %depth_limit.addr
  %cmp523 = icmp eq i64 %ld522, 0
  %ar524 = zext i1 %cmp523 to i64
  %$t1054.addr = alloca i64
  store i64 %ar524, ptr %$t1054.addr
  %ld525 = load i64, ptr %$t1054.addr
  %res_slot526 = alloca ptr
  switch i64 %ld525, label %case_default111 [
      i64 1, label %case_br112
  ]
case_br112:
  %ld527 = load ptr, ptr %xs.addr
  %xs_i6.addr = alloca ptr
  store ptr %ld527, ptr %xs_i6.addr
  %hp528 = call ptr @march_alloc(i64 16)
  %tgp529 = getelementptr i8, ptr %hp528, i64 8
  store i32 0, ptr %tgp529, align 4
  %$t1022_i7.addr = alloca ptr
  store ptr %hp528, ptr %$t1022_i7.addr
  %ld530 = load ptr, ptr %xs_i6.addr
  %ld531 = load ptr, ptr %$t1022_i7.addr
  %cr532 = call ptr @build_heap(ptr %ld530, ptr %ld531)
  %$t1023_i8.addr = alloca ptr
  store ptr %cr532, ptr %$t1023_i8.addr
  %hp533 = call ptr @march_alloc(i64 16)
  %tgp534 = getelementptr i8, ptr %hp533, i64 8
  store i32 0, ptr %tgp534, align 4
  %$t1024_i9.addr = alloca ptr
  store ptr %hp533, ptr %$t1024_i9.addr
  %ld535 = load ptr, ptr %$t1023_i8.addr
  %ld536 = load ptr, ptr %$t1024_i9.addr
  %cr537 = call ptr @drain_heap(ptr %ld535, ptr %ld536)
  store ptr %cr537, ptr %res_slot526
  br label %case_merge110
case_default111:
  %ld538 = load i64, ptr %n.addr
  %ar539 = sdiv i64 %ld538, 2
  %mid.addr = alloca i64
  store i64 %ar539, ptr %mid.addr
  %ld540 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld540)
  %ld541 = load ptr, ptr %xs.addr
  %cr542 = call i64 @nth(ptr %ld541, i64 0)
  %a.addr = alloca i64
  store i64 %cr542, ptr %a.addr
  %ld543 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld543)
  %ld544 = load ptr, ptr %xs.addr
  %ld545 = load i64, ptr %mid.addr
  %cr546 = call i64 @nth(ptr %ld544, i64 %ld545)
  %b.addr = alloca i64
  store i64 %cr546, ptr %b.addr
  %ld547 = load i64, ptr %n.addr
  %ar548 = sub i64 %ld547, 1
  %$t1055.addr = alloca i64
  store i64 %ar548, ptr %$t1055.addr
  %ld549 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld549)
  %ld550 = load ptr, ptr %xs.addr
  %ld551 = load i64, ptr %$t1055.addr
  %cr552 = call i64 @nth(ptr %ld550, i64 %ld551)
  %c.addr = alloca i64
  store i64 %cr552, ptr %c.addr
  %ld553 = load i64, ptr %a.addr
  %ld554 = load i64, ptr %b.addr
  %ld555 = load i64, ptr %c.addr
  %cr556 = call i64 @median3(i64 %ld553, i64 %ld554, i64 %ld555)
  %pivot.addr = alloca i64
  store i64 %cr556, ptr %pivot.addr
  %hp557 = call ptr @march_alloc(i64 16)
  %tgp558 = getelementptr i8, ptr %hp557, i64 8
  store i32 0, ptr %tgp558, align 4
  %$t1056.addr = alloca ptr
  store ptr %hp557, ptr %$t1056.addr
  %hp559 = call ptr @march_alloc(i64 16)
  %tgp560 = getelementptr i8, ptr %hp559, i64 8
  store i32 0, ptr %tgp560, align 4
  %$t1057.addr = alloca ptr
  store ptr %hp559, ptr %$t1057.addr
  %hp561 = call ptr @march_alloc(i64 16)
  %tgp562 = getelementptr i8, ptr %hp561, i64 8
  store i32 0, ptr %tgp562, align 4
  %$t1058.addr = alloca ptr
  store ptr %hp561, ptr %$t1058.addr
  %ld563 = load ptr, ptr %xs.addr
  %ld564 = load i64, ptr %pivot.addr
  %ld565 = load ptr, ptr %$t1056.addr
  %ld566 = load ptr, ptr %$t1057.addr
  %ld567 = load ptr, ptr %$t1058.addr
  %cr568 = call ptr @partition3(ptr %ld563, i64 %ld564, ptr %ld565, ptr %ld566, ptr %ld567)
  %$p1062.addr = alloca ptr
  store ptr %cr568, ptr %$p1062.addr
  %ld569 = load ptr, ptr %$p1062.addr
  %fp570 = getelementptr i8, ptr %ld569, i64 16
  %fv571 = load ptr, ptr %fp570, align 8
  %lt.addr = alloca ptr
  store ptr %fv571, ptr %lt.addr
  %ld572 = load ptr, ptr %$p1062.addr
  %fp573 = getelementptr i8, ptr %ld572, i64 24
  %fv574 = load ptr, ptr %fp573, align 8
  %eq.addr = alloca ptr
  store ptr %fv574, ptr %eq.addr
  %ld575 = load ptr, ptr %$p1062.addr
  %fp576 = getelementptr i8, ptr %ld575, i64 32
  %fv577 = load ptr, ptr %fp576, align 8
  %gt.addr = alloca ptr
  store ptr %fv577, ptr %gt.addr
  %ld578 = load i64, ptr %depth_limit.addr
  %ar579 = sub i64 %ld578, 1
  %$t1059.addr = alloca i64
  store i64 %ar579, ptr %$t1059.addr
  %ld580 = load ptr, ptr %lt.addr
  %ld581 = load i64, ptr %$t1059.addr
  %cr582 = call ptr @introsort(ptr %ld580, i64 %ld581)
  %sorted_lt.addr = alloca ptr
  store ptr %cr582, ptr %sorted_lt.addr
  %ld583 = load i64, ptr %depth_limit.addr
  %ar584 = sub i64 %ld583, 1
  %$t1060.addr = alloca i64
  store i64 %ar584, ptr %$t1060.addr
  %ld585 = load ptr, ptr %gt.addr
  %ld586 = load i64, ptr %$t1060.addr
  %cr587 = call ptr @introsort(ptr %ld585, i64 %ld586)
  %sorted_gt.addr = alloca ptr
  store ptr %cr587, ptr %sorted_gt.addr
  %ld588 = load ptr, ptr %sorted_lt.addr
  %ld589 = load ptr, ptr %eq.addr
  %cr590 = call ptr @append(ptr %ld588, ptr %ld589)
  %$t1061.addr = alloca ptr
  store ptr %cr590, ptr %$t1061.addr
  %ld591 = load ptr, ptr %$t1061.addr
  %ld592 = load ptr, ptr %sorted_gt.addr
  %cr593 = call ptr @append(ptr %ld591, ptr %ld592)
  store ptr %cr593, ptr %res_slot526
  br label %case_merge110
case_merge110:
  %case_r594 = load ptr, ptr %res_slot526
  store ptr %case_r594, ptr %res_slot519
  br label %case_merge107
case_merge107:
  %case_r595 = load ptr, ptr %res_slot519
  store ptr %case_r595, ptr %res_slot513
  br label %case_merge104
case_merge104:
  %case_r596 = load ptr, ptr %res_slot513
  ret ptr %case_r596
}

define ptr @sort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld597 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld597)
  %ld598 = load ptr, ptr %xs.addr
  %cr599 = call i64 @list_len(ptr %ld598)
  %n.addr = alloca i64
  store i64 %cr599, ptr %n.addr
  %ld600 = load i64, ptr %n.addr
  %ar601 = add i64 %ld600, 1
  %$t1063.addr = alloca i64
  store i64 %ar601, ptr %$t1063.addr
  %ld602 = load i64, ptr %$t1063.addr
  %cr603 = call i64 @ilog2(i64 %ld602)
  %$t1064.addr = alloca i64
  store i64 %cr603, ptr %$t1064.addr
  %ld604 = load i64, ptr %$t1064.addr
  %ld605 = load i64, ptr %$t1064.addr
  %ar606 = add i64 %ld604, %ld605
  %sr_s1.addr = alloca i64
  store i64 %ar606, ptr %sr_s1.addr
  %ld607 = load i64, ptr %sr_s1.addr
  %limit.addr = alloca i64
  store i64 %ld607, ptr %limit.addr
  %ld608 = load ptr, ptr %xs.addr
  %ld609 = load i64, ptr %limit.addr
  %cr610 = call ptr @introsort(ptr %ld608, i64 %ld609)
  ret ptr %cr610
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld611 = load i64, ptr %n.addr
  %cmp612 = icmp eq i64 %ld611, 0
  %ar613 = zext i1 %cmp612 to i64
  %$t1065.addr = alloca i64
  store i64 %ar613, ptr %$t1065.addr
  %ld614 = load i64, ptr %$t1065.addr
  %res_slot615 = alloca ptr
  switch i64 %ld614, label %case_default114 [
      i64 1, label %case_br115
  ]
case_br115:
  %ld616 = load ptr, ptr %acc.addr
  store ptr %ld616, ptr %res_slot615
  br label %case_merge113
case_default114:
  %ld617 = load i64, ptr %seed.addr
  %ar618 = mul i64 %ld617, 1664525
  %$t1066.addr = alloca i64
  store i64 %ar618, ptr %$t1066.addr
  %ld619 = load i64, ptr %$t1066.addr
  %ar620 = add i64 %ld619, 1013904223
  %$t1067.addr = alloca i64
  store i64 %ar620, ptr %$t1067.addr
  %ld621 = load i64, ptr %$t1067.addr
  %ar622 = srem i64 %ld621, 1000000
  %next.addr = alloca i64
  store i64 %ar622, ptr %next.addr
  %ld623 = load i64, ptr %n.addr
  %ar624 = sub i64 %ld623, 1
  %$t1068.addr = alloca i64
  store i64 %ar624, ptr %$t1068.addr
  %ld625 = load i64, ptr %next.addr
  %ar626 = srem i64 %ld625, 100000
  %$t1069.addr = alloca i64
  store i64 %ar626, ptr %$t1069.addr
  %hp627 = call ptr @march_alloc(i64 32)
  %tgp628 = getelementptr i8, ptr %hp627, i64 8
  store i32 1, ptr %tgp628, align 4
  %ld629 = load i64, ptr %$t1069.addr
  %cv630 = inttoptr i64 %ld629 to ptr
  %fp631 = getelementptr i8, ptr %hp627, i64 16
  store ptr %cv630, ptr %fp631, align 8
  %ld632 = load ptr, ptr %acc.addr
  %fp633 = getelementptr i8, ptr %hp627, i64 24
  store ptr %ld632, ptr %fp633, align 8
  %$t1070.addr = alloca ptr
  store ptr %hp627, ptr %$t1070.addr
  %ld634 = load i64, ptr %$t1068.addr
  %ld635 = load i64, ptr %next.addr
  %ld636 = load ptr, ptr %$t1070.addr
  %cr637 = call ptr @gen_list(i64 %ld634, i64 %ld635, ptr %ld636)
  store ptr %cr637, ptr %res_slot615
  br label %case_merge113
case_merge113:
  %case_r638 = load ptr, ptr %res_slot615
  ret ptr %case_r638
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld639 = load ptr, ptr %xs.addr
  %res_slot640 = alloca ptr
  %tgp641 = getelementptr i8, ptr %ld639, i64 8
  %tag642 = load i32, ptr %tgp641, align 4
  switch i32 %tag642, label %case_default117 [
      i32 0, label %case_br118
      i32 1, label %case_br119
  ]
case_br118:
  %ld643 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld643)
  %cv644 = inttoptr i64 0 to ptr
  store ptr %cv644, ptr %res_slot640
  br label %case_merge116
case_br119:
  %fp645 = getelementptr i8, ptr %ld639, i64 16
  %fv646 = load ptr, ptr %fp645, align 8
  %$f1071.addr = alloca ptr
  store ptr %fv646, ptr %$f1071.addr
  %fp647 = getelementptr i8, ptr %ld639, i64 24
  %fv648 = load ptr, ptr %fp647, align 8
  %$f1072.addr = alloca ptr
  store ptr %fv648, ptr %$f1072.addr
  %freed649 = call i64 @march_decrc_freed(ptr %ld639)
  %freed_b650 = icmp ne i64 %freed649, 0
  br i1 %freed_b650, label %br_unique120, label %br_shared121
br_shared121:
  call void @march_incrc(ptr %fv648)
  br label %br_body122
br_unique120:
  br label %br_body122
br_body122:
  %ld651 = load ptr, ptr %$f1071.addr
  %h.addr = alloca ptr
  store ptr %ld651, ptr %h.addr
  %ld652 = load i64, ptr %h.addr
  %cv653 = inttoptr i64 %ld652 to ptr
  store ptr %cv653, ptr %res_slot640
  br label %case_merge116
case_default117:
  unreachable
case_merge116:
  %case_r654 = load ptr, ptr %res_slot640
  %cv655 = ptrtoint ptr %case_r654 to i64
  ret i64 %cv655
}

define void @march_main() {
entry:
  %hp656 = call ptr @march_alloc(i64 16)
  %tgp657 = getelementptr i8, ptr %hp656, i64 8
  store i32 0, ptr %tgp657, align 4
  %$t1073.addr = alloca ptr
  store ptr %hp656, ptr %$t1073.addr
  %ld658 = load ptr, ptr %$t1073.addr
  %cr659 = call ptr @gen_list(i64 10000, i64 42, ptr %ld658)
  %xs.addr = alloca ptr
  store ptr %cr659, ptr %xs.addr
  %ld660 = load ptr, ptr %xs.addr
  %cr661 = call ptr @sort(ptr %ld660)
  %sorted.addr = alloca ptr
  store ptr %cr661, ptr %sorted.addr
  %ld662 = load ptr, ptr %sorted.addr
  %cr663 = call i64 @head(ptr %ld662)
  %$t1074.addr = alloca i64
  store i64 %cr663, ptr %$t1074.addr
  %ld664 = load i64, ptr %$t1074.addr
  %cr665 = call ptr @march_int_to_string(i64 %ld664)
  %$t1075.addr = alloca ptr
  store ptr %cr665, ptr %$t1075.addr
  %ld666 = load ptr, ptr %$t1075.addr
  call void @march_println(ptr %ld666)
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
  %ld667 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld667, ptr %go.addr
  %ld668 = load ptr, ptr %lst.addr
  %res_slot669 = alloca ptr
  %tgp670 = getelementptr i8, ptr %ld668, i64 8
  %tag671 = load i32, ptr %tgp670, align 4
  switch i32 %tag671, label %case_default124 [
      i32 0, label %case_br125
      i32 1, label %case_br126
  ]
case_br125:
  %ld672 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld672)
  %ld673 = load ptr, ptr %acc.addr
  store ptr %ld673, ptr %res_slot669
  br label %case_merge123
case_br126:
  %fp674 = getelementptr i8, ptr %ld668, i64 16
  %fv675 = load ptr, ptr %fp674, align 8
  %$f971.addr = alloca ptr
  store ptr %fv675, ptr %$f971.addr
  %fp676 = getelementptr i8, ptr %ld668, i64 24
  %fv677 = load ptr, ptr %fp676, align 8
  %$f972.addr = alloca ptr
  store ptr %fv677, ptr %$f972.addr
  %ld678 = load ptr, ptr %$f972.addr
  %t.addr = alloca ptr
  store ptr %ld678, ptr %t.addr
  %ld679 = load ptr, ptr %$f971.addr
  %h.addr = alloca ptr
  store ptr %ld679, ptr %h.addr
  %ld680 = load ptr, ptr %lst.addr
  %ld681 = load i64, ptr %h.addr
  %cv682 = inttoptr i64 %ld681 to ptr
  %ld683 = load ptr, ptr %acc.addr
  %rc684 = load i64, ptr %ld680, align 8
  %uniq685 = icmp eq i64 %rc684, 1
  %fbip_slot686 = alloca ptr
  br i1 %uniq685, label %fbip_reuse127, label %fbip_fresh128
fbip_reuse127:
  %tgp687 = getelementptr i8, ptr %ld680, i64 8
  store i32 1, ptr %tgp687, align 4
  %fp688 = getelementptr i8, ptr %ld680, i64 16
  store ptr %cv682, ptr %fp688, align 8
  %fp689 = getelementptr i8, ptr %ld680, i64 24
  store ptr %ld683, ptr %fp689, align 8
  store ptr %ld680, ptr %fbip_slot686
  br label %fbip_merge129
fbip_fresh128:
  call void @march_decrc(ptr %ld680)
  %hp690 = call ptr @march_alloc(i64 32)
  %tgp691 = getelementptr i8, ptr %hp690, i64 8
  store i32 1, ptr %tgp691, align 4
  %fp692 = getelementptr i8, ptr %hp690, i64 16
  store ptr %cv682, ptr %fp692, align 8
  %fp693 = getelementptr i8, ptr %hp690, i64 24
  store ptr %ld683, ptr %fp693, align 8
  store ptr %hp690, ptr %fbip_slot686
  br label %fbip_merge129
fbip_merge129:
  %fbip_r694 = load ptr, ptr %fbip_slot686
  %$t970.addr = alloca ptr
  store ptr %fbip_r694, ptr %$t970.addr
  %ld695 = load ptr, ptr %go.addr
  %fp696 = getelementptr i8, ptr %ld695, i64 16
  %fv697 = load ptr, ptr %fp696, align 8
  %ld698 = load ptr, ptr %t.addr
  %ld699 = load ptr, ptr %$t970.addr
  %cr700 = call ptr (ptr, ptr, ptr) %fv697(ptr %ld695, ptr %ld698, ptr %ld699)
  store ptr %cr700, ptr %res_slot669
  br label %case_merge123
case_default124:
  unreachable
case_merge123:
  %case_r701 = load ptr, ptr %res_slot669
  ret ptr %case_r701
}

define i64 @go$apply$19(ptr %$clo.arg, ptr %lst.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld702 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld702, ptr %go.addr
  %ld703 = load ptr, ptr %lst.addr
  %res_slot704 = alloca ptr
  %tgp705 = getelementptr i8, ptr %ld703, i64 8
  %tag706 = load i32, ptr %tgp705, align 4
  switch i32 %tag706, label %case_default131 [
      i32 0, label %case_br132
      i32 1, label %case_br133
  ]
case_br132:
  %ld707 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld707)
  %ld708 = load i64, ptr %acc.addr
  %cv709 = inttoptr i64 %ld708 to ptr
  store ptr %cv709, ptr %res_slot704
  br label %case_merge130
case_br133:
  %fp710 = getelementptr i8, ptr %ld703, i64 16
  %fv711 = load ptr, ptr %fp710, align 8
  %$f978.addr = alloca ptr
  store ptr %fv711, ptr %$f978.addr
  %fp712 = getelementptr i8, ptr %ld703, i64 24
  %fv713 = load ptr, ptr %fp712, align 8
  %$f979.addr = alloca ptr
  store ptr %fv713, ptr %$f979.addr
  %freed714 = call i64 @march_decrc_freed(ptr %ld703)
  %freed_b715 = icmp ne i64 %freed714, 0
  br i1 %freed_b715, label %br_unique134, label %br_shared135
br_shared135:
  call void @march_incrc(ptr %fv713)
  br label %br_body136
br_unique134:
  br label %br_body136
br_body136:
  %ld716 = load ptr, ptr %$f979.addr
  %t.addr = alloca ptr
  store ptr %ld716, ptr %t.addr
  %ld717 = load i64, ptr %acc.addr
  %ar718 = add i64 %ld717, 1
  %$t977.addr = alloca i64
  store i64 %ar718, ptr %$t977.addr
  %ld719 = load ptr, ptr %go.addr
  %fp720 = getelementptr i8, ptr %ld719, i64 16
  %fv721 = load ptr, ptr %fp720, align 8
  %ld722 = load ptr, ptr %t.addr
  %ld723 = load i64, ptr %$t977.addr
  %cr724 = call i64 (ptr, ptr, i64) %fv721(ptr %ld719, ptr %ld722, i64 %ld723)
  %cv725 = inttoptr i64 %cr724 to ptr
  store ptr %cv725, ptr %res_slot704
  br label %case_merge130
case_default131:
  unreachable
case_merge130:
  %case_r726 = load ptr, ptr %res_slot704
  %cv727 = ptrtoint ptr %case_r726 to i64
  ret i64 %cv727
}

define i64 @go$apply$20(ptr %$clo.arg, i64 %v.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %v.addr = alloca i64
  store i64 %v.arg, ptr %v.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld728 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld728, ptr %go.addr
  %ld729 = load i64, ptr %v.addr
  %cmp730 = icmp sle i64 %ld729, 1
  %ar731 = zext i1 %cmp730 to i64
  %$t980.addr = alloca i64
  store i64 %ar731, ptr %$t980.addr
  %ld732 = load i64, ptr %$t980.addr
  %res_slot733 = alloca ptr
  switch i64 %ld732, label %case_default138 [
      i64 1, label %case_br139
  ]
case_br139:
  %ld734 = load i64, ptr %acc.addr
  %cv735 = inttoptr i64 %ld734 to ptr
  store ptr %cv735, ptr %res_slot733
  br label %case_merge137
case_default138:
  %ld736 = load i64, ptr %v.addr
  %ar737 = sdiv i64 %ld736, 2
  %$t981.addr = alloca i64
  store i64 %ar737, ptr %$t981.addr
  %ld738 = load i64, ptr %acc.addr
  %ar739 = add i64 %ld738, 1
  %$t982.addr = alloca i64
  store i64 %ar739, ptr %$t982.addr
  %ld740 = load ptr, ptr %go.addr
  %fp741 = getelementptr i8, ptr %ld740, i64 16
  %fv742 = load ptr, ptr %fp741, align 8
  %ld743 = load i64, ptr %$t981.addr
  %ld744 = load i64, ptr %$t982.addr
  %cr745 = call i64 (ptr, i64, i64) %fv742(ptr %ld740, i64 %ld743, i64 %ld744)
  %cv746 = inttoptr i64 %cr745 to ptr
  store ptr %cv746, ptr %res_slot733
  br label %case_merge137
case_merge137:
  %case_r747 = load ptr, ptr %res_slot733
  %cv748 = ptrtoint ptr %case_r747 to i64
  ret i64 %cv748
}

define ptr @go$apply$21(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld749 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld749, ptr %go.addr
  %ld750 = load ptr, ptr %lst.addr
  %res_slot751 = alloca ptr
  %tgp752 = getelementptr i8, ptr %ld750, i64 8
  %tag753 = load i32, ptr %tgp752, align 4
  switch i32 %tag753, label %case_default141 [
      i32 0, label %case_br142
      i32 1, label %case_br143
  ]
case_br142:
  %ld754 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld754)
  %ld755 = load ptr, ptr %acc.addr
  store ptr %ld755, ptr %res_slot751
  br label %case_merge140
case_br143:
  %fp756 = getelementptr i8, ptr %ld750, i64 16
  %fv757 = load ptr, ptr %fp756, align 8
  %$f1031.addr = alloca ptr
  store ptr %fv757, ptr %$f1031.addr
  %fp758 = getelementptr i8, ptr %ld750, i64 24
  %fv759 = load ptr, ptr %fp758, align 8
  %$f1032.addr = alloca ptr
  store ptr %fv759, ptr %$f1032.addr
  %freed760 = call i64 @march_decrc_freed(ptr %ld750)
  %freed_b761 = icmp ne i64 %freed760, 0
  br i1 %freed_b761, label %br_unique144, label %br_shared145
br_shared145:
  call void @march_incrc(ptr %fv759)
  br label %br_body146
br_unique144:
  br label %br_body146
br_body146:
  %ld762 = load ptr, ptr %$f1032.addr
  %t.addr = alloca ptr
  store ptr %ld762, ptr %t.addr
  %ld763 = load ptr, ptr %$f1031.addr
  %h.addr = alloca ptr
  store ptr %ld763, ptr %h.addr
  %ld764 = load i64, ptr %h.addr
  %ld765 = load ptr, ptr %acc.addr
  %cr766 = call ptr @insert(i64 %ld764, ptr %ld765)
  %$t1030.addr = alloca ptr
  store ptr %cr766, ptr %$t1030.addr
  %ld767 = load ptr, ptr %go.addr
  %fp768 = getelementptr i8, ptr %ld767, i64 16
  %fv769 = load ptr, ptr %fp768, align 8
  %ld770 = load ptr, ptr %t.addr
  %ld771 = load ptr, ptr %$t1030.addr
  %cr772 = call ptr (ptr, ptr, ptr) %fv769(ptr %ld767, ptr %ld770, ptr %ld771)
  store ptr %cr772, ptr %res_slot751
  br label %case_merge140
case_default141:
  unreachable
case_merge140:
  %case_r773 = load ptr, ptr %res_slot751
  ret ptr %case_r773
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
